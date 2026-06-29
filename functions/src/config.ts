// Product-wide constants mirroring the Zexo non-functional constraints.

export const RADIUS_MIN_M = 500;
export const RADIUS_MAX_M = 50_000;
export const RADIUS_DEFAULT_M = 5_000;

export const MAX_USER_TAGS = 10;
export const MAX_EVENT_TAGS = 5;

export const LOCATION_FUZZ_METERS = 150;

export const MESSAGE_TTL_HOURS = 24;

// Discovery ranking weights (must both be > 0 — dual-factor rule).
export const W_DISTANCE = 0.6;
export const W_TAG = 0.4;

// Geohash precision used when indexing locations (≈ a few metres of resolution).
export const GEOHASH_PRECISION = 10;

/** Clamp a requested discovery radius into the allowed band. */
export function clampRadius(radiusM: number | undefined): number {
  if (radiusM === undefined || Number.isNaN(radiusM)) return RADIUS_DEFAULT_M;
  return Math.max(RADIUS_MIN_M, Math.min(RADIUS_MAX_M, radiusM));
}
