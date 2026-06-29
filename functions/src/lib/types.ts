import { Timestamp } from "firebase-admin/firestore";

export type RsvpStatus = "going" | "maybe" | "no";
export type RsvpRole = "host" | "co-host" | "guest";
export type EventVisibility = "public" | "invite-only";

export interface UserDoc {
  displayName: string | null;
  bio: string | null;
  avatarUrl: string | null;
  email: string | null;
  interestTags: string[];
  isVisible: boolean;
  radiusM: number;
  lastSeenAt: Timestamp | null;
  createdAt: Timestamp;
}

/** Denormalised location doc — carries the profile fields the feed needs so a
 *  single geohash query can both filter by distance and render cards. Only the
 *  FUZZED coordinates are ever stored here (raw GPS never persisted). */
export interface UserLocationDoc {
  geohash: string;
  lat: number; // fuzzy
  lng: number; // fuzzy
  accuracyM: number | null;
  isVisible: boolean;
  displayName: string | null;
  avatarUrl: string | null;
  interestTags: string[];
  updatedAt: Timestamp;
}

export interface BlockDoc {
  blocker: string;
  blocked: string;
  reason: string | null;
  reported: boolean;
  createdAt: Timestamp;
}

export interface ThreadDoc {
  participants: string[]; // [uidA, uidB]
  participantsKey: string; // "min_max" — uniqueness guard
  expiresAt: Timestamp | null;
  lastMessageAt: Timestamp | null;
  createdAt: Timestamp;
}

export interface MessageDoc {
  senderId: string;
  body: string;
  readAt: Timestamp | null;
  expiresAt: Timestamp;
  createdAt: Timestamp;
}

export interface EventDoc {
  creatorId: string;
  title: string;
  description: string | null;
  lat: number;
  lng: number;
  geohash: string;
  radiusM: number;
  capacity: number | null;
  tags: string[];
  visibility: EventVisibility;
  startsAt: Timestamp;
  endsAt: Timestamp;
  isArchived: boolean;
  attendeeCount: number;
  createdAt: Timestamp;
}

export interface RsvpDoc {
  role: RsvpRole;
  status: RsvpStatus;
  createdAt: Timestamp;
}
