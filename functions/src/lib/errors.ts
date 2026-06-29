import { HttpsError } from "firebase-functions/v2/https";

// Thin wrappers around HttpsError for consistent, readable failures.
export const unauthenticated = (msg = "Sign-in required") =>
  new HttpsError("unauthenticated", msg);

export const invalidArg = (msg: string) =>
  new HttpsError("invalid-argument", msg);

export const notFound = (msg = "Not found") =>
  new HttpsError("not-found", msg);

export const permissionDenied = (msg = "Not allowed") =>
  new HttpsError("permission-denied", msg);

export const failedPrecondition = (msg: string) =>
  new HttpsError("failed-precondition", msg);

/** Resolve the caller's uid from a callable request, or throw unauthenticated. */
export function requireUid(auth: { uid: string } | undefined): string {
  if (!auth || !auth.uid) throw unauthenticated();
  return auth.uid;
}
