import { blocksCol } from "./firestore";

/**
 * Returns the set of user ids that are in a block relationship with `me` in
 * EITHER direction (Requirement 16.2). Used to exclude them from discovery,
 * map, and attendee results.
 */
export async function blockedUserIds(me: string): Promise<Set<string>> {
  const [iBlocked, blockedMe] = await Promise.all([
    blocksCol().where("blocker", "==", me).get(),
    blocksCol().where("blocked", "==", me).get(),
  ]);
  const ids = new Set<string>();
  iBlocked.forEach((d) => ids.add(d.get("blocked") as string));
  blockedMe.forEach((d) => ids.add(d.get("blocker") as string));
  return ids;
}

/** Deterministic block doc id for a directed (blocker → blocked) pair. */
export function blockId(blocker: string, blocked: string): string {
  return `${blocker}_${blocked}`;
}
