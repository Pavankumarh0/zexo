import { initializeApp } from "firebase-admin/app";
import { getFirestore, Firestore, Timestamp } from "firebase-admin/firestore";

// Initialise the Admin SDK exactly once for the whole function runtime.
initializeApp();

export const db: Firestore = getFirestore();

export { Timestamp };

// Collection name constants to avoid string typos across modules.
export const COL = {
  users: "users",
  userLocations: "userLocations",
  blocks: "blocks",
  threads: "threads",
  events: "events",
} as const;

export const usersCol = () => db.collection(COL.users);
export const userLocationsCol = () => db.collection(COL.userLocations);
export const blocksCol = () => db.collection(COL.blocks);
export const threadsCol = () => db.collection(COL.threads);
export const eventsCol = () => db.collection(COL.events);

export const messagesCol = (threadId: string) =>
  threadsCol().doc(threadId).collection("messages");

export const rsvpsCol = (eventId: string) =>
  eventsCol().doc(eventId).collection("rsvps");
