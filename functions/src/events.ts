import { onCall } from "firebase-functions/v2/https";

import { MAX_EVENT_TAGS, clampRadius } from "./config";
import {
  db,
  usersCol,
  eventsCol,
  rsvpsCol,
  Timestamp,
} from "./lib/firestore";
import {
  requireUid,
  invalidArg,
  notFound,
  permissionDenied,
  failedPrecondition,
} from "./lib/errors";
import { geohashFor, haversineM, queryBounds, LatLng } from "./lib/geo";
import { RsvpStatus } from "./lib/types";

const HOST_ROLES = new Set(["host", "co-host"]);
const VALID_STATUS = new Set(["going", "maybe", "no"]);

function eventDetail(
  id: string,
  d: FirebaseFirestore.DocumentData,
  extra: { distanceM?: number; myRsvp?: string | null } = {},
) {
  return {
    id,
    creatorId: d.creatorId,
    title: d.title,
    description: d.description ?? null,
    lat: d.lat,
    lng: d.lng,
    radiusM: d.radiusM,
    capacity: d.capacity ?? null,
    tags: d.tags ?? [],
    visibility: d.visibility,
    startsAt: d.startsAt.toDate().toISOString(),
    endsAt: d.endsAt.toDate().toISOString(),
    isArchived: d.isArchived ?? false,
    attendeeCount: d.attendeeCount ?? 0,
    distanceM: extra.distanceM ?? null,
    myRsvp: extra.myRsvp ?? null,
  };
}

/** Create a geofenced event. Enforces ≤5 tags and starts < ends. */
export const createEvent = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const d = req.data ?? {};

  const title = String(d.title ?? "").trim();
  if (!title) throw invalidArg("title is required");
  const tags: string[] = Array.isArray(d.tags) ? d.tags : [];
  if (tags.length > MAX_EVENT_TAGS) throw invalidArg(`At most ${MAX_EVENT_TAGS} tags`);
  if (typeof d.lat !== "number" || typeof d.lng !== "number") {
    throw invalidArg("lat and lng are required");
  }
  const startsAt = new Date(d.startsAt);
  const endsAt = new Date(d.endsAt);
  if (Number.isNaN(startsAt.getTime()) || Number.isNaN(endsAt.getTime())) {
    throw invalidArg("startsAt and endsAt must be valid dates");
  }
  if (startsAt >= endsAt) throw invalidArg("startsAt must be before endsAt");

  const ref = eventsCol().doc();
  await ref.set({
    creatorId: uid,
    title,
    description: d.description ? String(d.description).slice(0, 2000) : null,
    lat: d.lat,
    lng: d.lng,
    geohash: geohashFor(d.lat, d.lng),
    radiusM: typeof d.radiusM === "number" ? d.radiusM : 500,
    capacity: typeof d.capacity === "number" ? d.capacity : null,
    tags,
    visibility: d.visibility === "invite-only" ? "invite-only" : "public",
    startsAt: Timestamp.fromDate(startsAt),
    endsAt: Timestamp.fromDate(endsAt),
    isArchived: false,
    attendeeCount: 1,
    createdAt: Timestamp.now(),
  });
  // Creator becomes the host (going).
  await rsvpsCol(ref.id).doc(uid).set({
    role: "host",
    status: "going",
    createdAt: Timestamp.now(),
  });

  const snap = await ref.get();
  return eventDetail(ref.id, snap.data()!, { myRsvp: "going" });
});

/** Nearby active events, distance-sorted, cursor-paginated. */
export const listEvents = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const d = req.data ?? {};
  if (typeof d.lat !== "number" || typeof d.lng !== "number") {
    throw invalidArg("lat and lng are required");
  }
  const center: LatLng = { lat: d.lat, lng: d.lng };
  const radiusM = clampRadius(typeof d.radius === "number" ? d.radius : undefined);
  const filterTags: string[] = Array.isArray(d.tags) ? d.tags : [];
  const now = Date.now();

  const bounds = queryBounds(center, radiusM);
  const snaps = await Promise.all(
    bounds.map((b) =>
      eventsCol().orderBy("geohash").startAt(b[0]).endAt(b[1]).get(),
    ),
  );

  type Row = { id: string; data: FirebaseFirestore.DocumentData; distanceM: number };
  const rows: Row[] = [];
  const seen = new Set<string>();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      const e = doc.data();
      if (e.isArchived) continue;
      if (e.endsAt && e.endsAt.toMillis() < now) continue;
      if (e.visibility !== "public" && e.creatorId !== uid) continue;
      const distanceM = haversineM(center, { lat: e.lat, lng: e.lng });
      if (distanceM > radiusM) continue;
      if (filterTags.length > 0) {
        const tagSet = new Set<string>(e.tags ?? []);
        if (!filterTags.some((t) => tagSet.has(t))) continue;
      }
      rows.push({ id: doc.id, data: e, distanceM });
    }
  }

  rows.sort((a, b) =>
    a.distanceM !== b.distanceM ? a.distanceM - b.distanceM : a.id < b.id ? -1 : 1,
  );

  const limit = Math.min(Math.max(Number(d.limit) || 20, 1), 50);
  const cursor = d.cursor as { distanceM: number; id: string } | undefined;
  let filtered = rows;
  if (cursor) {
    filtered = rows.filter(
      (r) =>
        r.distanceM > cursor.distanceM ||
        (r.distanceM === cursor.distanceM && r.id > cursor.id),
    );
  }
  const page = filtered.slice(0, limit);

  // Attach myRsvp for the page.
  const myRsvps = await Promise.all(
    page.map((r) => rsvpsCol(r.id).doc(uid).get()),
  );
  const items = page.map((r, i) =>
    eventDetail(r.id, r.data, {
      distanceM: Math.round(r.distanceM * 10) / 10,
      myRsvp: myRsvps[i].exists ? (myRsvps[i].get("status") as string) : null,
    }),
  );

  const last = page[page.length - 1];
  const nextCursor =
    page.length === limit && filtered.length > limit
      ? { distanceM: last.distanceM, id: last.id }
      : null;

  return { items, nextCursor };
});

/** Single event detail. */
export const getEvent = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const eventId = (req.data ?? {}).eventId as string;
  if (!eventId) throw invalidArg("eventId is required");
  const [snap, rsvp] = await Promise.all([
    eventsCol().doc(eventId).get(),
    rsvpsCol(eventId).doc(uid).get(),
  ]);
  if (!snap.exists) throw notFound("Event not found");
  return eventDetail(eventId, snap.data()!, {
    myRsvp: rsvp.exists ? (rsvp.get("status") as string) : null,
  });
});

/** RSVP (going/maybe/no). Maintains attendeeCount + capacity in a transaction. */
export const rsvpEvent = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const { eventId, status } = req.data ?? {};
  if (!eventId) throw invalidArg("eventId is required");
  if (!VALID_STATUS.has(status)) throw invalidArg("status must be going|maybe|no");

  const result = await db.runTransaction(async (tx) => {
    const evRef = eventsCol().doc(eventId);
    const ev = await tx.get(evRef);
    if (!ev.exists) throw notFound("Event not found");

    const rsvpRef = rsvpsCol(eventId).doc(uid);
    const prev = await tx.get(rsvpRef);
    const prevStatus = prev.exists ? (prev.get("status") as string) : null;
    const role = prev.exists ? (prev.get("role") as string) : "guest";

    const capacity = ev.get("capacity") as number | null;
    const count = (ev.get("attendeeCount") as number) ?? 0;
    const wasGoing = prevStatus === "going";
    const willGo = status === "going";

    if (willGo && !wasGoing && capacity != null && count >= capacity) {
      throw failedPrecondition("Event is full");
    }

    tx.set(rsvpRef, {
      role,
      status,
      createdAt: prev.exists ? prev.get("createdAt") : Timestamp.now(),
    });

    let delta = 0;
    if (willGo && !wasGoing) delta = 1;
    else if (!willGo && wasGoing) delta = -1;
    if (delta !== 0) tx.update(evRef, { attendeeCount: count + delta });

    return { role, status };
  });

  return { eventId, status: result.status as RsvpStatus, role: result.role };
});

/** Attendee list — full list for host/co-host only; otherwise just the count. */
export const eventAttendees = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const eventId = (req.data ?? {}).eventId as string;
  if (!eventId) throw invalidArg("eventId is required");

  const myRsvp = await rsvpsCol(eventId).doc(uid).get();
  const role = myRsvp.exists ? (myRsvp.get("role") as string) : null;
  const all = await rsvpsCol(eventId).get();
  const goingCount = all.docs.filter((r) => r.get("status") === "going").length;

  if (role && HOST_ROLES.has(role)) {
    const attendees = await Promise.all(
      all.docs.map(async (r) => {
        const u = await usersCol().doc(r.id).get();
        return {
          userId: r.id,
          displayName: u.get("displayName") ?? null,
          avatarUrl: u.get("avatarUrl") ?? null,
          role: r.get("role"),
          status: r.get("status"),
        };
      }),
    );
    return { eventId, attendeeCount: goingCount, attendees };
  }
  return { eventId, attendeeCount: goingCount, attendees: null };
});

/** Promote a user to co-host (host only). */
export const addCohost = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const { eventId, userId } = req.data ?? {};
  if (!eventId || !userId) throw invalidArg("eventId and userId are required");

  const mine = await rsvpsCol(eventId).doc(uid).get();
  if (!mine.exists || mine.get("role") !== "host") {
    throw permissionDenied("Host only");
  }
  await rsvpsCol(eventId).doc(userId).set(
    { role: "co-host", status: "going", createdAt: Timestamp.now() },
    { merge: true },
  );
  return { eventId, cohostId: userId };
});

/** Update an event (host/co-host only). */
export const updateEvent = onCall(async (req) => {
  const uid = requireUid(req.auth);
  const d = req.data ?? {};
  const eventId = d.eventId as string;
  if (!eventId) throw invalidArg("eventId is required");

  const evSnap = await eventsCol().doc(eventId).get();
  if (!evSnap.exists) throw notFound("Event not found");
  const myRsvp = await rsvpsCol(eventId).doc(uid).get();
  const role = myRsvp.exists ? (myRsvp.get("role") as string) : null;
  if (evSnap.get("creatorId") !== uid && !(role && HOST_ROLES.has(role))) {
    throw permissionDenied("Host only");
  }

  const update: Record<string, unknown> = {};
  if (d.title !== undefined) update.title = String(d.title).trim();
  if (d.description !== undefined) update.description = String(d.description).slice(0, 2000);
  if (d.capacity !== undefined) update.capacity = d.capacity;
  if (d.visibility !== undefined) {
    update.visibility = d.visibility === "invite-only" ? "invite-only" : "public";
  }
  if (d.tags !== undefined) {
    if (!Array.isArray(d.tags) || d.tags.length > MAX_EVENT_TAGS) {
      throw invalidArg(`At most ${MAX_EVENT_TAGS} tags`);
    }
    update.tags = d.tags;
  }
  let startsAt = evSnap.get("startsAt") as FirebaseFirestore.Timestamp;
  let endsAt = evSnap.get("endsAt") as FirebaseFirestore.Timestamp;
  if (d.startsAt !== undefined) {
    startsAt = Timestamp.fromDate(new Date(d.startsAt));
    update.startsAt = startsAt;
  }
  if (d.endsAt !== undefined) {
    endsAt = Timestamp.fromDate(new Date(d.endsAt));
    update.endsAt = endsAt;
  }
  if (startsAt.toMillis() >= endsAt.toMillis()) {
    throw invalidArg("startsAt must be before endsAt");
  }

  await eventsCol().doc(eventId).set(update, { merge: true });
  const snap = await eventsCol().doc(eventId).get();
  return eventDetail(eventId, snap.data()!, {
    myRsvp: myRsvp.exists ? (myRsvp.get("status") as string) : null,
  });
});
