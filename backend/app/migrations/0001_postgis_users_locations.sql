-- 0001 — PostGIS + users + user_locations
-- Requirements: 2, 3, 18. Validated by db.hook.kiro.

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "pgcrypto";  -- gen_random_uuid()

-- ---------------------------------------------------------------------------
-- users
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    phone         text UNIQUE,
    email         text UNIQUE,
    display_name  text,
    bio           text,
    avatar_url    text,
    interest_tags text[] NOT NULL DEFAULT '{}',
    radius_m      double precision NOT NULL DEFAULT 5000,
    is_visible    boolean NOT NULL DEFAULT true,
    last_seen_at  timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    -- Enforce the 10-tag-per-user cap at the database level (Requirement 19.6).
    CONSTRAINT users_max_10_tags CHECK (cardinality(interest_tags) <= 10),
    CONSTRAINT users_radius_bounds CHECK (radius_m >= 500 AND radius_m <= 50000)
);

-- ---------------------------------------------------------------------------
-- user_locations
--   geom       : raw GPS — transient, never exposed/exported (Requirement 3.3)
--   fuzzy_geom : ±150m offset applied server-side — used for ALL queries
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_locations (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    geom       geometry(Point, 4326),
    fuzzy_geom geometry(Point, 4326) NOT NULL,
    accuracy_m double precision,
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_locations_user_unique UNIQUE (user_id)
);

-- Spatial index used by every ST_DWithin proximity query (Requirement 3.6 / 18.4).
CREATE INDEX IF NOT EXISTS user_locations_fuzzy_geom_gist
    ON user_locations USING GIST (fuzzy_geom);

CREATE INDEX IF NOT EXISTS user_locations_user_id_idx
    ON user_locations (user_id);
