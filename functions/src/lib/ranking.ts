import { W_DISTANCE, W_TAG } from "../config";

export interface Candidate {
  userId: string;
  distanceM: number;
  tags: string[];
}

export interface ScoredCandidate {
  userId: string;
  distanceM: number;
  score: number;
  sharedTags: string[];
}

/** 1.0 at the origin, 0.0 at/beyond the radius edge. */
export function distanceScore(distanceM: number, radiusM: number): number {
  if (radiusM <= 0) return 0;
  return Math.max(0, Math.min(1, 1 - distanceM / radiusM));
}

/** Jaccard similarity of two tag sets, in [0, 1]. */
export function tagOverlap(a: string[], b: string[]): number {
  const sa = new Set(a);
  const sb = new Set(b);
  if (sa.size === 0 && sb.size === 0) return 0;
  let inter = 0;
  for (const t of sa) if (sb.has(t)) inter++;
  const union = new Set([...sa, ...sb]).size;
  return union === 0 ? 0 : inter / union;
}

export function sharedTags(a: string[], b: string[]): string[] {
  const sb = new Set(b);
  return [...new Set(a)].filter((t) => sb.has(t)).sort();
}

/** Blend distance and tag-overlap scores. Both weights must be > 0. */
export function computeScore(
  distanceM: number,
  radiusM: number,
  userTags: string[],
  candidateTags: string[],
  wDistance: number = W_DISTANCE,
  wTag: number = W_TAG,
): number {
  if (wDistance <= 0 || wTag <= 0) {
    throw new Error("Both distance and tag weights must be positive");
  }
  const d = distanceScore(distanceM, radiusM);
  const t = tagOverlap(userTags, candidateTags);
  return wDistance * d + wTag * t;
}

/** Score and order candidates by score DESC, distance ASC, id ASC. */
export function rank(
  userTags: string[],
  candidates: Candidate[],
  radiusM: number,
): ScoredCandidate[] {
  const scored: ScoredCandidate[] = candidates.map((c) => ({
    userId: c.userId,
    distanceM: c.distanceM,
    score: computeScore(c.distanceM, radiusM, userTags, c.tags),
    sharedTags: sharedTags(userTags, c.tags),
  }));
  scored.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    if (a.distanceM !== b.distanceM) return a.distanceM - b.distanceM;
    return a.userId < b.userId ? -1 : a.userId > b.userId ? 1 : 0;
  });
  return scored;
}
