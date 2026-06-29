# Zexo — Firebase Backend (Cloud Functions + Firestore)

The Zexo backend on **Firebase**: Cloud Functions (TypeScript, 2nd gen) for the API +
triggers, **Firestore** as the database (proximity via **geohash** since Firestore has no
native geo query), **Firebase Auth** (Google), Firestore real-time listeners for chat, and
scheduled functions for cleanup.

> This replaces the FastAPI/PostGIS service in [`../backend`](../backend), which is kept for
> reference only and is no longer the source of truth.

## Layout

```
functions/
  src/
    index.ts            # exports every callable + trigger
    config.ts           # constants (radius, tag caps, fuzz, weights, geohash precision)
    lib/
      firestore.ts      # admin init + collection refs
      geo.ts            # ±150m fuzzing, haversine, geohash (geofire-common)
      ranking.ts        # distance × tag-overlap scoring
      blocks.ts         # bidirectional block exclusion
      errors.ts         # HttpsError helpers
      types.ts          # Firestore document interfaces
    users.ts            # getMe, updateMe, updateLocation, setVisibility,
                        # getUser, blockUser, deleteMe, registerPushToken
    discover.ts         # discoverNearby (ranked geohash feed), discoverMap (bbox)
    threads.ts          # openThread, listThreads, expireThread, evaluateThreadExpiry
    events.ts           # createEvent, listEvents, getEvent, rsvpEvent,
                        # eventAttendees, addCohost, updateEvent
    triggers.ts         # onUserCreate, purgeExpiredMessages, archiveEndedEvents,
                        # onMessageCreate (FCM)
  test/                 # node:test unit tests for geo + ranking
../firestore.rules      # security rules
../firestore.indexes.json
../firebase.json        # functions + firestore + emulator config
```

## Data model (Firestore)

| Collection | Doc | Notes |
| --- | --- | --- |
| `users/{uid}` | profile | displayName, bio, avatarUrl, email, interestTags[], isVisible, radiusM, fcmTokens[] |
| `userLocations/{uid}` | fuzzed location | geohash, lat/lng (**fuzzed ±150m**), + denormalised displayName/avatarUrl/interestTags/isVisible. **Functions-only** (clients never read it) |
| `blocks/{blocker_blocked}` | block | blocker, blocked, reason, reported |
| `threads/{id}` | chat thread | participants[], participantsKey, expiresAt, lastMessageAt |
| `threads/{id}/messages/{id}` | message | senderId, body, readAt, expiresAt (24h) — written directly by participants |
| `events/{id}` | event | geohash, lat/lng, radiusM, tags[], capacity, attendeeCount, startsAt/endsAt |
| `events/{id}/rsvps/{uid}` | rsvp | role, status |

## Proximity without PostGIS

Firestore has no radius query, so locations carry a **geohash**. `discoverNearby` /
`discoverMap` / `listEvents` compute the geohash ranges that cover the requested radius
(`geofire-common`), query those ranges, then filter by exact haversine distance and rank in
code. The ±150m fuzzing is applied server-side in `updateLocation`; only fuzzed coordinates
are ever stored or returned.

## Prerequisites

- Node 20, the Firebase CLI (`npm i -g firebase-tools`)
- A Firebase project with **Firestore**, **Authentication → Google**, and **Cloud
  Messaging** enabled. Cloud Functions (2nd gen) require the **Blaze** plan.

## Local development (emulators)

```bash
cd functions
npm install
npm run build           # tsc -> lib/
# from the repo root (where firebase.json lives):
firebase emulators:start --only functions,firestore,auth
```

Set your project id in `../.firebaserc` (replace `REPLACE_WITH_FIREBASE_PROJECT_ID`).

## Tests

Unit tests cover the framework-independent geo + ranking math:

```bash
cd functions
npm install
npm test                # node --test via tsx
```

## Deploy

```bash
# from the repo root
firebase deploy --only firestore:rules,firestore:indexes,functions
```

## API surface (callable functions)

All are HTTPS **callable** functions (invoke from the app via the Cloud Functions SDK);
auth is taken from the Firebase ID token automatically.

- **users:** `getMe`, `updateMe`, `updateLocation`, `setVisibility`, `getUser`,
  `blockUser`, `deleteMe`, `registerPushToken`
- **discover:** `discoverNearby`, `discoverMap`
- **threads:** `openThread`, `listThreads`, `expireThread`, `evaluateThreadExpiry`
- **events:** `createEvent`, `listEvents`, `getEvent`, `rsvpEvent`, `eventAttendees`,
  `addCohost`, `updateEvent`

Chat **messages** are written directly to `threads/{id}/messages` by participants (enforced
by security rules) so the app can use real-time listeners; the `onMessageCreate` trigger
maintains `lastMessageAt` and sends FCM.
