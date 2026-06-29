import * as functionsV1 from "firebase-functions/v1";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getMessaging } from "firebase-admin/messaging";

import {
  db,
  usersCol,
  eventsCol,
  threadsCol,
  Timestamp,
} from "./lib/firestore";

/**
 * Create the user profile doc when a Firebase Auth account is created.
 * (Auth triggers are a v1 feature; the rest of the codebase is v2 — both are
 * supported side by side.)
 */
export const onUserCreate = functionsV1.auth.user().onCreate(async (user) => {
  await usersCol().doc(user.uid).set(
    {
      displayName: user.displayName ?? null,
      bio: null,
      avatarUrl: user.photoURL ?? null,
      email: user.email ?? null,
      interestTags: [],
      isVisible: true,
      radiusM: 5000,
      lastSeenAt: Timestamp.now(),
      createdAt: Timestamp.now(),
    },
    { merge: true },
  );
});

/**
 * Purge expired chat messages hourly (Requirement 9.5 / replaces pg_cron). Uses
 * a collection-group query across all threads' message subcollections.
 */
export const purgeExpiredMessages = onSchedule("every 60 minutes", async () => {
  const now = Timestamp.now();
  for (;;) {
    const snap = await db
      .collectionGroup("messages")
      .where("expiresAt", "<", now)
      .limit(400)
      .get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    if (snap.size < 400) break;
  }
});

/**
 * Auto-archive events whose end time has passed (Requirement 15.1). Filters
 * isArchived in code to avoid a composite index.
 */
export const archiveEndedEvents = onSchedule("every 15 minutes", async () => {
  const now = Timestamp.now();
  const snap = await eventsCol().where("endsAt", "<", now).get();
  const batch = db.batch();
  let n = 0;
  snap.docs.forEach((d) => {
    if (d.get("isArchived") !== true) {
      batch.update(d.ref, { isArchived: true });
      n++;
    }
  });
  if (n > 0) await batch.commit();
});

/**
 * On a new message: bump the thread's lastMessageAt (clients can't write the
 * thread doc) and push an FCM notification to the recipient.
 */
export const onMessageCreate = onDocumentCreated(
  "threads/{threadId}/messages/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const msg = snap.data();
    const threadId = event.params.threadId;
    const senderId = msg.senderId as string;

    const createdAt = (msg.createdAt as FirebaseFirestore.Timestamp) ?? Timestamp.now();
    await threadsCol().doc(threadId).set({ lastMessageAt: createdAt }, { merge: true });

    const threadSnap = await threadsCol().doc(threadId).get();
    const participants = (threadSnap.get("participants") as string[]) ?? [];
    const recipientId = participants.find((p) => p !== senderId);
    if (!recipientId) return;

    const recipient = await usersCol().doc(recipientId).get();
    const tokens = (recipient.get("fcmTokens") as string[]) ?? [];
    if (tokens.length === 0) return;

    const senderSnap = await usersCol().doc(senderId).get();
    const senderName = (senderSnap.get("displayName") as string) ?? "Someone";

    try {
      await getMessaging().sendEachForMulticast({
        tokens,
        notification: {
          title: senderName,
          body: String(msg.body ?? "").slice(0, 120),
        },
        data: { type: "message", threadId },
      });
    } catch {
      // Best-effort; never fail the trigger on push errors.
    }
  },
);
