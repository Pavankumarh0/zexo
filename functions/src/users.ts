import { onCall } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";

import { MAX_USER_TAGS } from "./config";
import {
  db,
  usersCol,
  userLocationsCol,
  blocksCol,
  Timestamp,
} from "./lib/firestore";
import { requireUid, invalidArg, notFound } from "./lib/errors";
import { fuzzCoordinates, geohashFor } from "./lib/geo";
import { blockId } from "./lib/blocks";

function publicProfile(id: string, data: FirebaseFirestore.DocumentData) {
  return {
    id,
    displayName: data.displayName ?? null,
    bio: data.bio ?? null,
    avatarUrl: data.avatarUrl ?? null,
    interestTags: data.interestTags ?? [],
  };
}

/** GET own profile. */
export const getMe = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const snap = await usersCol().doc(uid).get();
  if (!snap.exists) throw notFound("Profile not found");
  const d = snap.data()!;
  return {
    id: uid,
    displayName: d.displayName ?? null,
    bio: d.bio ?? null,
    avatarUrl: d.avatarUrl ?? null,
    interestTags: d.interestTags ?? [],
    isVisible: d.isVisible ?? true,
    radiusM: d.radiusM ?? 5000,
  };
});

/** Update editable profile fields. Enforces the 10-tag cap. */
export const updateMe = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const data = req.data ?? {};
  const update: Record<string, unknown> = {};

  if (data.displayName !== undefined) update.displayName = String(data.displayName).slice(0, 80);
  if (data.bio !== undefined) update.bio = String(data.bio).slice(0, 500);
  if (data.avatarUrl !== undefined) update.avatarUrl = data.avatarUrl;
  if (data.radiusM !== undefined) update.radiusM = Number(data.radiusM);
  if (data.interestTags !== undefined) {
    const tags = data.interestTags as string[];
    if (!Array.isArray(tags)) throw invalidArg("interestTags must be an array");
    if (tags.length > MAX_USER_TAGS) {
      throw invalidArg(`At most ${MAX_USER_TAGS} interest tags`);
    }
    update.interestTags = tags;
  }

  await usersCol().doc(uid).set(update, { merge: true });

  // Keep the denormalised location doc in sync for the discovery feed.
  const locUpdate: Record<string, unknown> = {};
  if (update.displayName !== undefined) locUpdate.displayName = update.displayName;
  if (update.avatarUrl !== undefined) locUpdate.avatarUrl = update.avatarUrl;
  if (update.interestTags !== undefined) locUpdate.interestTags = update.interestTags;
  if (Object.keys(locUpdate).length > 0) {
    await userLocationsCol().doc(uid).set(locUpdate, { merge: true });
  }

  const snap = await usersCol().doc(uid).get();
  const d = snap.data()!;
  return {
    id: uid,
    displayName: d.displayName ?? null,
    bio: d.bio ?? null,
    avatarUrl: d.avatarUrl ?? null,
    interestTags: d.interestTags ?? [],
    isVisible: d.isVisible ?? true,
    radiusM: d.radiusM ?? 5000,
  };
});

/**
 * Update location. The raw coordinates are fuzzed ±150m SERVER-SIDE; only the
 * fuzzed point + its geohash are persisted (Requirement 3 / location.hook).
 */
export const updateLocation = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const { lat, lng, accuracyM } = req.data ?? {};
  if (typeof lat !== "number" || typeof lng !== "number") {
    throw invalidArg("lat and lng are required numbers");
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw invalidArg("lat/lng out of range");
  }

  const fuzzed = fuzzCoordinates(lat, lng);
  const geohash = geohashFor(fuzzed.lat, fuzzed.lng);

  // Pull current profile fields to denormalise onto the location doc.
  const userSnap = await usersCol().doc(uid).get();
  const u = userSnap.data() ?? {};

  await userLocationsCol().doc(uid).set(
    {
      geohash,
      lat: fuzzed.lat,
      lng: fuzzed.lng,
      accuracyM: typeof accuracyM === "number" ? accuracyM : null,
      isVisible: u.isVisible ?? true,
      displayName: u.displayName ?? null,
      avatarUrl: u.avatarUrl ?? null,
      interestTags: u.interestTags ?? [],
      updatedAt: Timestamp.now(),
    },
    { merge: true },
  );

  await usersCol().doc(uid).set({ lastSeenAt: Timestamp.now() }, { merge: true });

  // Return ONLY the fuzzed coordinates.
  return { fuzzyLat: fuzzed.lat, fuzzyLng: fuzzed.lng, updatedAt: new Date().toISOString() };
});

/** Toggle visibility (kept in sync on the location doc for feed filtering). */
export const setVisibility = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const isVisible = !!(req.data ?? {}).isVisible;
  await usersCol().doc(uid).set({ isVisible }, { merge: true });
  await userLocationsCol().doc(uid).set({ isVisible }, { merge: true });
  return { isVisible };
});

/** Public profile of another user. */
export const getUser = onCall(async (req) => {
  requireUid(req.auth);
  const otherId = (req.data ?? {}).userId as string;
  if (!otherId) throw invalidArg("userId is required");
  const snap = await usersCol().doc(otherId).get();
  if (!snap.exists) throw notFound("User not found");
  return publicProfile(otherId, snap.data()!);
});

/** Block (and optionally report) another user. Bidirectional exclusion is
 *  applied at query time via blockedUserIds(). */
export const blockUser = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const { userId, report, reason } = req.data ?? {};
  if (!userId) throw invalidArg("userId is required");
  if (userId === uid) throw invalidArg("Cannot block yourself");

  await blocksCol().doc(blockId(uid, userId)).set({
    blocker: uid,
    blocked: userId,
    reason: reason ?? null,
    reported: !!report,
    createdAt: Timestamp.now(),
  });

  // Moderation webhook stub: a report is recorded on the block doc above. A
  // real integration would forward it to an external moderation system here.
  return { blocked: true };
});

/** GDPR deletion: remove the user's profile + location + block docs. (Auth
 *  account deletion is handled by the client / Admin Auth separately.) */
export const deleteMe = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const batch = db.batch();
  batch.delete(usersCol().doc(uid));
  batch.delete(userLocationsCol().doc(uid));
  await batch.commit();

  // Remove block docs authored by this user.
  const mine = await blocksCol().where("blocker", "==", uid).get();
  await Promise.all(mine.docs.map((d) => d.ref.delete()));
  return { deleted: true };
});

/** Register an FCM device token for push notifications. */
export const registerPushToken = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const token = (req.data ?? {}).token as string;
  if (!token) throw invalidArg("token is required");
  await usersCol()
    .doc(uid)
    .set({ fcmTokens: FieldValue.arrayUnion(token) }, { merge: true });
  return { ok: true };
});
