import { onCall } from "firebase-functions/v2/https";

import { clampRadius } from "./config";
import { usersCol, userLocationsCol, eventsCol } from "./lib/firestore";
import { requireUid, invalidArg, notFound } from "./lib/errors";
import { haversineM, queryBounds, LatLng } from "./lib/geo";
import { rank, Candidate } from "./lib/ranking";
import { blockedUserIds } from "./lib/blocks";

interface RawCandidate {
  id: string;
  lat: number;
  lng: number;
  tags: string[];
  displayName: string | null;
  avatarUrl: string | null;
  isVisible: boolean;
  distanceM: number;
}

/** Collect userLocation docs within `radiusM` of `center` via geohash bounds. */
async function locationsWithin(center: LatLng, radiusM: number): Promise<RawCandidate[]> {
  const bounds = queryBounds(center, radiusM);
  const snaps = await Promise.all(
    bounds.map((b) =>
      userLocationsCol().orderBy("geohash").startAt(b[0]).endAt(b[1]).get(),
    ),
  );

  const out: RawCandidate[] = [];
  const seen = new Set<string>();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue; // bounds can overlap
      seen.add(doc.id);
      const d = doc.data();
      if (typeof d.lat !== "number" || typeof d.lng !== "number") continue;
      const distanceM = haversineM(center, { lat: d.lat, lng: d.lng });
      if (distanceM > radiusM) continue; // geohash bounds over-fetch; filter exactly
      out.push({
        id: doc.id,
        lat: d.lat,
        lng: d.lng,
        tags: d.interestTags ?? [],
        displayName: d.displayName ?? null,
        avatarUrl: d.avatarUrl ?? null,
        isVisible: d.isVisible !== false,
        distanceM,
      });
    }
  }
  return out;
}

/** Ranked nearby-user feed (distance × tag overlap), cursor-paginated. */
export const discoverNearby = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const data = req.data ?? {};

  const meSnap = await usersCol().doc(uid).get();
  if (!meSnap.exists) throw notFound("Profile not found");
  const me = meSnap.data()!;
  const myTags: string[] = me.interestTags ?? [];

  const radiusM = clampRadius(
    typeof data.radius === "number" ? data.radius : me.radiusM,
  );

  // Center: provided coords, else the caller's own stored fuzzy location.
  let center: LatLng;
  if (typeof data.lat === "number" && typeof data.lng === "number") {
    center = { lat: data.lat, lng: data.lng };
  } else {
    const locSnap = await userLocationsCol().doc(uid).get();
    if (!locSnap.exists) return { items: [], nextCursor: null };
    const l = locSnap.data()!;
    center = { lat: l.lat, lng: l.lng };
  }

  const [raw, blocked] = await Promise.all([
    locationsWithin(center, radiusM),
    blockedUserIds(uid),
  ]);

  const visibleRaw = raw.filter(
    (c) => c.id !== uid && !blocked.has(c.id) && c.isVisible,
  );

  const candidates: Candidate[] = visibleRaw.map((c) => ({
    userId: c.id,
    distanceM: c.distanceM,
    tags: c.tags,
  }));
  const byId = new Map(visibleRaw.map((c) => [c.id, c]));

  let ranked = rank(myTags, candidates, radiusM);

  // Cursor encodes the last (score, id); resume strictly after it.
  const limit = Math.min(Math.max(Number(data.limit) || 20, 1), 50);
  const cursor = data.cursor as { score: number; id: string } | undefined;
  if (cursor) {
    ranked = ranked.filter(
      (s) =>
        s.score < cursor.score ||
        (s.score === cursor.score && s.userId > cursor.id),
    );
  }

  const page = ranked.slice(0, limit);
  const items = page.map((s) => {
    const c = byId.get(s.userId)!;
    return {
      user: {
        id: s.userId,
        displayName: c.displayName,
        avatarUrl: c.avatarUrl,
        interestTags: c.tags,
      },
      distanceM: Math.round(s.distanceM * 10) / 10,
      sharedTags: s.sharedTags,
      score: Math.round(s.score * 1e6) / 1e6,
    };
  });

  const last = page[page.length - 1];
  const nextCursor =
    page.length === limit && ranked.length > limit
      ? { score: last.score, id: last.userId }
      : null;

  return { items, nextCursor };
});

/** Users + events within a bounding box (for the map view). */
export const discoverMap = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const { minLat, minLng, maxLat, maxLng } = req.data ?? {};
  if (
    [minLat, minLng, maxLat, maxLng].some((v) => typeof v !== "number")
  ) {
    throw invalidArg("minLat,minLng,maxLat,maxLng are required");
  }

  const center: LatLng = { lat: (minLat + maxLat) / 2, lng: (minLng + maxLng) / 2 };
  // Radius that comfortably covers the bbox (half-diagonal).
  const radiusM = haversineM(center, { lat: maxLat, lng: maxLng });

  const [raw, blocked] = await Promise.all([
    locationsWithin(center, radiusM),
    blockedUserIds(uid),
  ]);

  const inBox = (lat: number, lng: number) =>
    lat >= minLat && lat <= maxLat && lng >= minLng && lng <= maxLng;

  const users = raw
    .filter((c) => c.id !== uid && !blocked.has(c.id) && inBox(c.lat, c.lng))
    .map((c) => ({ id: c.id, fuzzyLat: c.lat, fuzzyLng: c.lng }));

  // Events within the bbox (geohash range + exact filter).
  const bounds = queryBounds(center, radiusM);
  const eventSnaps = await Promise.all(
    bounds.map((b) =>
      eventsCol().orderBy("geohash").startAt(b[0]).endAt(b[1]).get(),
    ),
  );
  const events: { id: string; title: string; lat: number; lng: number; tags: string[] }[] = [];
  const seen = new Set<string>();
  const now = Date.now();
  for (const s of eventSnaps) {
    for (const doc of s.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const e = doc.data();
      if (e.isArchived) continue;
      if (e.endsAt && e.endsAt.toMillis() < now) continue;
      if (e.visibility !== "public" && e.creatorId !== uid) continue;
      if (!inBox(e.lat, e.lng)) continue;
      events.push({ id: doc.id, title: e.title, lat: e.lat, lng: e.lng, tags: e.tags ?? [] });
    }
  }

  return { users, events };
});
