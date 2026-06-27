-- 0003 — events + event_rsvps
-- Requirements: 11, 12, 13, 14, 15. Validated by db.hook.kiro.

DO $$ BEGIN
    CREATE TYPE rsvp_role AS ENUM ('host', 'co-host', 'guest');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE rsvp_status AS ENUM ('going', 'maybe', 'no');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
    CREATE TYPE event_visibility AS ENUM ('public', 'invite-only');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS events (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    creator_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title       text NOT NULL,
    description text,
    geom        geometry(Point, 4326) NOT NULL,
    radius_m    double precision NOT NULL DEFAULT 500,
    capacity    int,
    tags        text[] NOT NULL DEFAULT '{}',
    visibility  event_visibility NOT NULL DEFAULT 'public',
    starts_at   timestamptz NOT NULL,
    ends_at     timestamptz NOT NULL,
    is_archived boolean NOT NULL DEFAULT false,
    created_at  timestamptz NOT NULL DEFAULT now(),
    -- Max 5 tags per event (Requirement 11.3 / 19.6).
    CONSTRAINT events_max_5_tags CHECK (cardinality(tags) <= 5),
    -- starts_at must precede ends_at (Requirement 11.5).
    CONSTRAINT events_time_order CHECK (starts_at < ends_at),
    CONSTRAINT events_capacity_positive CHECK (capacity IS NULL OR capacity > 0)
);

-- Spatial index for ST_DWithin event discovery (Requirement 12.1 / db.hook.kiro).
CREATE INDEX IF NOT EXISTS events_geom_gist ON events USING GIST (geom);
CREATE INDEX IF NOT EXISTS events_starts_at_idx ON events (starts_at);
-- Partial index over active events: discovery only ever reads non-archived rows.
CREATE INDEX IF NOT EXISTS events_active_idx ON events (ends_at) WHERE is_archived = false;

CREATE TABLE IF NOT EXISTS event_rsvps (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id   uuid NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role       rsvp_role NOT NULL DEFAULT 'guest',
    status     rsvp_status NOT NULL DEFAULT 'going',
    created_at timestamptz NOT NULL DEFAULT now(),
    -- One RSVP per (event, user); upsert target (Requirement 13.2).
    CONSTRAINT event_rsvps_event_user_unique UNIQUE (event_id, user_id)
);

CREATE INDEX IF NOT EXISTS event_rsvps_event_idx ON event_rsvps (event_id);
CREATE INDEX IF NOT EXISTS event_rsvps_user_idx ON event_rsvps (user_id);
