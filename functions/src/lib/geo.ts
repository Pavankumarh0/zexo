import {
  geohashForLocation,
  geohashQueryBounds,
  distanceBetween,
} from "geofire-common";

import { GEOHASH_PRECISION, LOCATION_FUZZ_METERS } from "../config";

const EARTH_RADIUS_M = 6_371_008.8;
const DEFAULT_JITTER = 0.25;

export interface LatLng {
  lat: number;
  lng: number;
}

export interface FuzzedPoint extends LatLng {
  offsetM: number;
}

function clampLat(lat: number): number {
  return Math.max(-90, Math.min(90, lat));
}

function wrapLng(lng: number): number {
  return ((lng + 180) % 360 + 360) % 360 - 180;
}

/** Project a point a given distance (metres) along a bearing (radians). */
export function offsetPoint(
  lat: number,
  lng: number,
  distanceM: number,
  bearingRad: number,
): LatLng {
  const ang = distanceM / EARTH_RADIUS_M;
  const lat1 = (lat * Math.PI) / 180;
  const lng1 = (lng * Math.PI) / 180;

  const sinLat2 =
    Math.sin(lat1) * Math.cos(ang) +
    Math.cos(lat1) * Math.sin(ang) * Math.cos(bearingRad);
  const lat2 = Math.asin(Math.max(-1, Math.min(1, sinLat2)));

  const y = Math.sin(bearingRad) * Math.sin(ang) * Math.cos(lat1);
  const x = Math.cos(ang) - Math.sin(lat1) * Math.sin(lat2);
  const lng2 = lng1 + Math.atan2(y, x);

  return {
    lat: clampLat((lat2 * 180) / Math.PI),
    lng: wrapLng((lng2 * 180) / Math.PI),
  };
}

/**
 * Offset a coordinate by ~`fuzzM` metres in a uniformly random direction
 * (Requirement 3). The realised offset is drawn from
 * [fuzzM*(1-jitter), fuzzM*(1+jitter)] so the magnitude is not a constant.
 *
 * `rand` is injectable for deterministic tests; defaults to Math.random.
 */
export function fuzzCoordinates(
  lat: number,
  lng: number,
  fuzzM: number = LOCATION_FUZZ_METERS,
  jitter: number = DEFAULT_JITTER,
  rand: () => number = Math.random,
): FuzzedPoint {
  if (fuzzM <= 0) throw new Error("fuzzM must be positive");
  if (jitter < 0 || jitter >= 1) throw new Error("jitter must be in [0, 1)");

  const bearing = rand() * 2 * Math.PI;
  const low = fuzzM * (1 - jitter);
  const high = fuzzM * (1 + jitter);
  const distance = low + rand() * (high - low);

  const p = offsetPoint(lat, lng, distance, bearing);
  return { lat: p.lat, lng: p.lng, offsetM: distance };
}

/** Great-circle distance in metres. */
export function haversineM(a: LatLng, b: LatLng): number {
  return distanceBetween([a.lat, a.lng], [b.lat, b.lng]) * 1000;
}

/** Geohash for a coordinate at the configured precision. */
export function geohashFor(lat: number, lng: number): string {
  return geohashForLocation([lat, lng], GEOHASH_PRECISION);
}

/** Geohash query bound pairs that cover a circle of `radiusM` around the centre. */
export function queryBounds(
  center: LatLng,
  radiusM: number,
): [string, string][] {
  return geohashQueryBounds([center.lat, center.lng], radiusM) as [
    string,
    string,
  ][];
}
