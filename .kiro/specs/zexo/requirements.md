# Zexo — Requirements

## Introduction

Zexo is a proximity-first social discovery platform that connects real people, events,
and local opportunities within a configurable radius. Unlike follower-graph social apps,
Zexo surfaces connections based purely on physical distance and shared interests, making
every interaction spontaneous and hyper-local.

This document defines the functional requirements for the initial release across four
core pillars — Proximity Engine, Discovery Feed, Ephemeral Chat, and Local Events — plus
the supporting authentication, privacy, safety, and non-functional concerns.

### Product Context

| Attribute | Value |
| --- | --- |
| Platforms | iOS and Android (Flutter single codebase) |
| Target users | Young urban professionals, college students, travellers |
| Key differentiator | No follower graph — proximity and interest matching only |
| Privacy approach | Coordinates fuzzed ±150m before storage, no raw GPS persisted |

### Requirements Index

1. Authentication & Account
2. Profile & Onboarding
3. Location Capture & Privacy Fuzzing
4. Proximity Engine & Polling
5. Discovery Feed (Cards)
6. Discovery Map
7. Visibility / Invisible Mode
8. Chat Threads & Connections
9. Ephemeral Messaging & Expiry
10. Push Notifications
11. Event Creation
12. Event Discovery & Detail
13. RSVP & Attendance
14. Co-hosting
15. Event Lifecycle / Archival
16. Safety: Block, Report & Moderation
17. GDPR & Account Deletion
18. Row-Level Security & Data Protection
19. Non-Functional Performance & Constraints

---

## Requirement 1 — Authentication & Account

**User Story:** As a new user, I want to sign up and sign in using my phone number or
Google account, so that I can access Zexo without managing a password.

#### Acceptance Criteria

1. WHEN a user submits a phone number THEN the system SHALL send a one-time passcode (OTP) via Supabase Auth.
2. WHEN a user submits a valid OTP THEN the system SHALL verify it through `POST /auth/verify-otp` and return a signed JWT.
3. WHEN a user submits an invalid or expired OTP THEN the system SHALL reject the request with a 401 and a descriptive error.
4. WHEN a user chooses Google sign-in THEN the system SHALL complete the OAuth flow via `POST /auth/google` and return a signed JWT.
5. WHEN a JWT is presented on any protected endpoint THEN the system SHALL validate its signature and expiry before processing the request.
6. IF a phone or email already maps to an existing account THEN the system SHALL authenticate the existing user rather than creating a duplicate.

---

## Requirement 2 — Profile & Onboarding

**User Story:** As a newly authenticated user, I want to set up my profile and
preferences, so that other people can discover me and I can be matched on shared interests.

#### Acceptance Criteria

1. WHEN onboarding starts THEN the system SHALL collect a display name, optional bio, and optional avatar.
2. WHEN a user uploads an avatar THEN the system SHALL store it in Supabase Storage and persist the resulting `avatar_url`.
3. WHEN a user selects interest tags THEN the system SHALL allow a maximum of 10 tags and SHALL reject selections beyond that limit.
4. WHEN a user picks a discovery radius THEN the system SHALL accept a value between 500m and 50km inclusive and default to 5km.
5. WHEN onboarding reaches the location step THEN the system SHALL display a permission explainer before requesting OS location permission.
6. WHEN a user edits their profile via `PUT /users/me` THEN the system SHALL update display name, bio, tags, and avatar and return the updated profile.
7. IF a user denies location permission THEN the system SHALL allow continued use with city-level fallback location.

---

## Requirement 3 — Location Capture & Privacy Fuzzing

**User Story:** As a privacy-conscious user, I want my exact location to never be stored or
shared, so that other users only ever see an approximate position.

#### Acceptance Criteria

1. WHEN the client sends coordinates to `PUT /users/location` THEN the server SHALL apply a random offset of approximately ±150m before persisting.
2. WHEN a location row is written THEN the system SHALL store the fuzzed point in `fuzzy_geom` and SHALL use only `fuzzy_geom` for all discovery queries.
3. WHEN any coordinate is exposed through an API response THEN the system SHALL expose only fuzzed coordinates and SHALL NOT expose raw GPS.
4. WHEN precise GPS is unavailable THEN the system SHALL fall back to a city-level coordinate (two-tier fallback).
5. IF accuracy metadata is provided THEN the system SHALL store `accuracy_m` alongside the location.
6. WHEN location data is queried THEN the system SHALL rely on a GIST index over `fuzzy_geom`.

---

## Requirement 4 — Proximity Engine & Polling

**User Story:** As an active user, I want my position to stay current while I use the app,
so that the people and events I see reflect where I actually am.

#### Acceptance Criteria

1. WHEN the app is in the foreground THEN the system SHALL poll location every 30 seconds.
2. WHEN the app is closed THEN the system SHALL pause location polling.
3. WHEN the accelerometer detects no movement THEN the system SHALL reduce polling frequency to once every 5 minutes (stationary optimisation).
4. WHEN computing nearby entities THEN the system SHALL use a PostGIS `ST_DWithin` radius query (Haversine-equivalent on geography).
5. WHEN a discovery radius is supplied THEN the system SHALL enforce a hard server-side cap of 50km.

---

## Requirement 5 — Discovery Feed (Cards)

**User Story:** As a user, I want a ranked feed of nearby people, so that I can find
spontaneous local connections based on proximity and shared interests.

#### Acceptance Criteria

1. WHEN a user requests `GET /discover?lat&lng&radius&tags` THEN the system SHALL return users ranked by a score of distance combined with interest-tag overlap.
2. WHEN ranking results THEN the system SHALL weight BOTH a distance score AND an interest-overlap score.
3. WHEN returning the feed THEN the system SHALL use cursor-based pagination.
4. WHEN a feed card is rendered THEN it SHALL display avatar, display name, distance badge, and shared interest tags highlighted.
5. WHEN the user has moved more than 200m from their last feed position THEN the system SHALL auto-refresh the feed.
6. WHEN a user pulls to refresh THEN the system SHALL re-fetch the feed for the current position.
7. WHEN building feed results THEN the system SHALL exclude users who are invisible, blocked, or blocking the requester.

---

## Requirement 6 — Discovery Map

**User Story:** As a user, I want to see nearby people and events on a live map, so that I
can understand the spatial layout of opportunities around me.

#### Acceptance Criteria

1. WHEN a user opens the map THEN the system SHALL render a Mapbox GL map with fuzzy dot clusters for nearby users.
2. WHEN the map is shown THEN the system SHALL overlay a ring representing the user's current discovery radius.
3. WHEN a user requests `GET /discover/map?bbox` THEN the system SHALL return users and events within the bounding box.
4. WHEN a user taps a cluster THEN the system SHALL expand it into individual dots.
5. WHEN a user taps a dot THEN the system SHALL open a peek bottom sheet with avatar, name, distance, and a connect button.
6. WHEN switching between card and map views THEN the system SHALL preserve the current discovery context.

---

## Requirement 7 — Visibility / Invisible Mode

**User Story:** As a user, I want to go invisible without deleting my account, so that I
can stop appearing in discovery while preserving my data and chats.

#### Acceptance Criteria

1. WHEN a user toggles visibility via `PUT /users/visibility` THEN the system SHALL update the `is_visible` flag.
2. WHILE a user is invisible THEN the system SHALL exclude them from all discovery feed and map results.
3. WHILE a user is invisible THEN the system SHALL preserve their existing chat threads and account data.
4. WHEN a user becomes visible again THEN the system SHALL include them in discovery without requiring re-onboarding.

---

## Requirement 8 — Chat Threads & Connections

**User Story:** As a user, I want to start a chat with someone nearby, so that I can connect
in real time.

#### Acceptance Criteria

1. WHEN a user taps connect THEN the system SHALL open or reuse a thread between the two users via `POST /threads`.
2. WHEN a user requests `GET /threads` THEN the system SHALL return their active threads sorted by last message time.
3. WHEN a thread row is rendered THEN it SHALL show an expiry countdown chip and an unread count badge.
4. WHEN a user connects to `WS /ws/thread/:id` THEN the system SHALL stream messages in real time over a WebSocket.
5. WHEN delivering real-time messages THEN the system SHALL use Redis pub/sub keyed per thread channel.

---

## Requirement 9 — Ephemeral Messaging & Expiry

**User Story:** As a user, I want messages to disappear automatically, so that conversations
stay ephemeral and tied to physical proximity.

#### Acceptance Criteria

1. WHEN a message is created THEN the system SHALL set `expires_at` to 24 hours from creation.
2. WHEN the sender moves outside the connected user's discovery radius THEN the system SHALL expire the thread immediately (whichever comes first with the 24h TTL).
3. WHEN a thread must be force-expired THEN the system SHALL support `POST /threads/:id/expire`.
4. WHEN a message is read THEN the system SHALL set `read_at` and surface a read receipt to the sender.
5. WHEN a message reaches expiry THEN a `pg_cron` job SHALL purge it within 1 hour of expiry.
6. WHILE a message approaches its TTL THEN the client SHALL visually fade the message and display a TTL banner.
7. WHEN a WebSocket heartbeat occurs THEN the system SHALL evaluate range-expiry for the thread.

---

## Requirement 10 — Push Notifications

**User Story:** As a user, I want to be notified of new messages when the app is in the
background, so that I do not miss time-sensitive connections.

#### Acceptance Criteria

1. WHEN a new message arrives AND the recipient's app is backgrounded THEN the system SHALL send a push via Firebase Cloud Messaging (FCM).
2. WHEN the app is foregrounded on the relevant thread THEN the system SHALL NOT send a redundant push.
3. WHEN a user disables notifications in settings THEN the system SHALL suppress FCM pushes for that user.

---

## Requirement 11 — Event Creation

**User Story:** As a host, I want to create a geofenced micro-event, so that nearby people
with shared interests can discover and join it.

#### Acceptance Criteria

1. WHEN a host submits `POST /events` THEN the system SHALL persist title, description, location, radius, capacity, tags, start time, and end time.
2. WHEN a host draws a radius on the map THEN the system SHALL store the geofenced `radius_m` (default 500m).
3. WHEN a host adds interest tags THEN the system SHALL allow a maximum of 5 tags per event.
4. WHEN an event is created THEN the system SHALL record the creator as the host in `event_rsvps`.
5. IF start time is not before end time THEN the system SHALL reject the event with a validation error.

---

## Requirement 12 — Event Discovery & Detail

**User Story:** As a user, I want to browse nearby events, so that I can find local
activities to attend.

#### Acceptance Criteria

1. WHEN a user requests `GET /events?lat&lng&radius&tags` THEN the system SHALL return nearby events using an `ST_DWithin` query, sorted by distance, with cursor-based pagination.
2. WHEN a user filters by tag or date THEN the system SHALL apply those filters to the results.
3. WHEN a user requests `GET /events/:id` THEN the system SHALL return full event detail including cover image, description, location, times, tags, and attendee count.
4. WHEN an event card is rendered THEN it SHALL show title, distance, tag chips, attendee count, and an RSVP control.
5. WHEN the events map view is shown THEN the system SHALL render event pins.

---

## Requirement 13 — RSVP & Attendance

**User Story:** As a user, I want to RSVP to events, so that hosts can plan and I can signal
my intent.

#### Acceptance Criteria

1. WHEN a user submits `POST /events/:id/rsvp` THEN the system SHALL record a status of going, maybe, or no.
2. WHEN a user RSVPs more than once THEN the system SHALL update the existing RSVP (unique per event/user) rather than duplicate it.
3. WHEN capacity is reached AND a new "going" RSVP is attempted THEN the system SHALL reject or waitlist the RSVP per capacity rules.
4. WHEN a user requests `GET /events/:id/attendees` THEN the system SHALL return the full attendee list only to the host (and co-hosts); non-hosts SHALL receive only the count or host-permitted view.

---

## Requirement 14 — Co-hosting

**User Story:** As a host, I want to invite co-hosts, so that I can share event management.

#### Acceptance Criteria

1. WHEN a host invites a co-host THEN the system SHALL deliver an invite via deep link.
2. WHEN a co-host accepts THEN the system SHALL set their RSVP role to `co-host`.
3. WHILE a user holds the co-host role THEN the system SHALL grant them host-equivalent attendee-list visibility and edit rights as configured.

---

## Requirement 15 — Event Lifecycle / Archival

**User Story:** As a user, I want past events to disappear from discovery, so that the feed
only shows relevant upcoming activity.

#### Acceptance Criteria

1. WHEN an event's `ends_at` has passed THEN a cron job SHALL set `is_archived` to true.
2. WHILE an event is archived THEN the system SHALL exclude it from discovery queries.
3. WHEN a host edits an event via `PUT /events/:id` THEN the system SHALL allow updates only by the host or a co-host.

---

## Requirement 16 — Safety: Block, Report & Moderation

**User Story:** As a user, I want to block and report others, so that I can keep my
experience safe.

#### Acceptance Criteria

1. WHEN a user submits `POST /users/:id/block` THEN the system SHALL block the target and optionally capture a report reason.
2. WHEN a block exists in either direction THEN the system SHALL exclude both users from each other's feed, map, and event-attendee queries.
3. WHEN a report is filed THEN the system SHALL forward it to a content-moderation webhook stub.
4. WHEN a user manages their block list in settings THEN the system SHALL allow viewing and removing blocks.

---

## Requirement 17 — GDPR & Account Deletion

**User Story:** As a user, I want to delete my account and data, so that I can exercise my
privacy rights.

#### Acceptance Criteria

1. WHEN a user requests account deletion THEN the system SHALL purge all PII and location history within 24 hours.
2. WHEN an account is deleted THEN the system SHALL cascade-delete dependent rows (locations, messages, RSVPs) per the schema.
3. WHEN deletion completes THEN the system SHALL invalidate the user's auth credentials.

---

## Requirement 18 — Row-Level Security & Data Protection

**User Story:** As the platform operator, I want every table protected by RLS, so that
users can only access data they are authorised to see.

#### Acceptance Criteria

1. WHEN any Supabase table is created THEN the system SHALL enable Row-Level Security on it.
2. WHEN a user queries `user_locations` THEN RLS SHALL restrict access according to ownership and discovery rules.
3. WHEN a user queries `users` THEN RLS SHALL expose only permitted public fields.
4. WHEN a migration runs THEN the system SHALL ensure the PostGIS extension is enabled and GIST indexes exist on all geometry columns.

---

## Requirement 19 — Non-Functional Performance & Constraints

**User Story:** As a user, I want a fast and reliable experience, so that discovery feels
instant and trustworthy.

#### Acceptance Criteria

1. WHEN `GET /discover` is called THEN the system SHALL respond within 200ms at p95.
2. WHEN a radius is requested THEN the system SHALL enforce 500m minimum and 50km maximum, defaulting to 5km.
3. WHEN coordinates are stored THEN the system SHALL always apply the ±150m server-side fuzzing first.
4. WHEN messages expire THEN the system SHALL delete them within 1 hour via `pg_cron`.
5. WHEN errors occur in Flutter or FastAPI THEN the system SHALL report them to Sentry.
6. WHEN tags are submitted THEN the system SHALL enforce 10 per user and 5 per event.
