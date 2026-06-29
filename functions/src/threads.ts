import { onCall } from "firebase-functions/v2/https";

import {
  usersCol,
  userLocationsCol,
  threadsCol,
  messagesCol,
  Timestamp,
} from "./lib/firestore";
import { requireUid, invalidArg, notFound, permissionDenied } from "./lib/errors";
import { haversineM } from "./lib/geo";

function participantsKey(a: string, b: string): string {
  return [a, b].sort().join("_");
}

/** Open or reuse a 1:1 thread. Idempotent on the unordered pair. */
export const openThread = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const peerId = (req.data ?? {}).peerId as string;
  if (!peerId) throw invalidArg("peerId is required");
  if (peerId === uid) throw invalidArg("Cannot open a thread with yourself");

  const key = participantsKey(uid, peerId);
  const existing = await threadsCol().where("participantsKey", "==", key).limit(1).get();
  if (!existing.empty) {
    return { threadId: existing.docs[0].id, created: false };
  }

  const ref = await threadsCol().add({
    participants: [uid, peerId].sort(),
    participantsKey: key,
    expiresAt: null,
    lastMessageAt: null,
    createdAt: Timestamp.now(),
  });
  return { threadId: ref.id, created: true };
});

/** List the caller's active threads, newest first, with unread counts. */
export const listThreads = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const snap = await threadsCol()
    .where("participants", "array-contains", uid)
    .orderBy("lastMessageAt", "desc")
    .get();

  const now = Date.now();
  const items = await Promise.all(
    snap.docs.map(async (doc) => {
      const t = doc.data();
      const expiresAt = t.expiresAt as FirebaseFirestore.Timestamp | null;
      if (expiresAt && expiresAt.toMillis() <= now) return null; // expired

      const peerId = (t.participants as string[]).find((p) => p !== uid)!;
      const [peerSnap, unreadAgg] = await Promise.all([
        usersCol().doc(peerId).get(),
        messagesCol(doc.id)
          .where("senderId", "==", peerId)
          .where("readAt", "==", null)
          .count()
          .get(),
      ]);
      const p = peerSnap.data() ?? {};
      return {
        id: doc.id,
        peer: {
          id: peerId,
          displayName: p.displayName ?? null,
          avatarUrl: p.avatarUrl ?? null,
          bio: p.bio ?? null,
          interestTags: p.interestTags ?? [],
        },
        lastMessageAt: t.lastMessageAt ? t.lastMessageAt.toDate().toISOString() : null,
        unreadCount: unreadAgg.data().count,
        expiresAt: expiresAt ? expiresAt.toDate().toISOString() : null,
      };
    }),
  );

  return { items: items.filter((i) => i !== null) };
});

async function assertParticipant(threadId: string, uid: string) {
  const snap = await threadsCol().doc(threadId).get();
  if (!snap.exists) throw notFound("Thread not found");
  const participants = snap.get("participants") as string[];
  if (!participants.includes(uid)) throw permissionDenied("Not a participant");
  return snap;
}

/** Force-expire a thread (manual end). */
export const expireThread = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const threadId = (req.data ?? {}).threadId as string;
  if (!threadId) throw invalidArg("threadId is required");
  await assertParticipant(threadId, uid);
  await threadsCol().doc(threadId).set({ expiresAt: Timestamp.now() }, { merge: true });
  return { expired: true, reason: "manual" };
});

/**
 * Heartbeat range-check (Requirement 9.2): if the caller has moved outside the
 * peer's discovery radius, expire the thread immediately. The client calls this
 * periodically while a chat is open (the Firebase analogue of the WS heartbeat).
 */
export const evaluateThreadExpiry = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const { threadId, lat, lng } = req.data ?? {};
  if (!threadId) throw invalidArg("threadId is required");
  if (typeof lat !== "number" || typeof lng !== "number") {
    throw invalidArg("lat and lng are required");
  }

  const thread = await assertParticipant(threadId, uid);
  const existingExpiry = thread.get("expiresAt") as FirebaseFirestore.Timestamp | null;
  if (existingExpiry && existingExpiry.toMillis() <= Date.now()) {
    return { expired: true, reason: "already" };
  }

  const peerId = (thread.get("participants") as string[]).find((p) => p !== uid)!;
  const [peerUser, peerLoc] = await Promise.all([
    usersCol().doc(peerId).get(),
    userLocationsCol().doc(peerId).get(),
  ]);
  if (!peerLoc.exists) return { expired: false, reason: "no_peer_location" };

  const peerRadius = (peerUser.data()?.radiusM as number) ?? 5000;
  const distanceM = haversineM(
    { lat, lng },
    { lat: peerLoc.get("lat"), lng: peerLoc.get("lng") },
  );

  if (distanceM > peerRadius) {
    await threadsCol().doc(threadId).set({ expiresAt: Timestamp.now() }, { merge: true });
    return { expired: true, reason: "range_exit" };
  }
  return { expired: false, reason: "in_range" };
});
