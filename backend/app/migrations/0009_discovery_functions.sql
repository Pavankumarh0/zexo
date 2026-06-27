-- 0009 — discovery functions
-- Requirements: 4.4, 5.1, 5.7, 6.3, 16.2.
--
-- nearby_users() is SECURITY DEFINER so it can read fuzzy locations for ranking WITHOUT
-- granting the caller direct SELECT on other users' user_locations rows (RLS keeps that
-- table owner-only). It returns ONLY fuzzy coordinates — raw geom is never exposed
-- (Requirement 3.3 / location.hook.kiro) — and applies visibility + bidirectional block
-- exclusion in-query.

CREATE OR REPLACE FUNCTION nearby_users(
    me uuid,
    origin geometry(Point, 4326),
    radius_m double precision
)
RETURNS TABLE (
    user_id       uuid,
    display_name  text,
    avatar_url    text,
    interest_tags text[],
    fuzzy_lat     double precision,
    fuzzy_lng     double precision,
    distance_m    double precision
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT u.id,
           u.display_name,
           u.avatar_url,
           u.interest_tags,
           ST_Y(l.fuzzy_geom)::double precision AS fuzzy_lat,
           ST_X(l.fuzzy_geom)::double precision AS fuzzy_lng,
           ST_Distance(l.fuzzy_geom::geography, origin::geography) AS distance_m
    FROM users u
    JOIN user_locations l ON l.user_id = u.id
    WHERE u.is_visible = true
      AND u.id <> me
      AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker = me AND b.blocked = u.id)
             OR (b.blocker = u.id AND b.blocked = me)
      )
      AND ST_DWithin(l.fuzzy_geom::geography, origin::geography, radius_m);
$$;

-- users_in_bbox() powers the map endpoint for people (Requirement 6.3). SECURITY DEFINER
-- so it can read fuzzy locations without granting direct table access; returns ONLY fuzzy
-- coordinates and applies visibility + bidirectional block exclusion.
CREATE OR REPLACE FUNCTION users_in_bbox(
    me uuid,
    min_lng double precision,
    min_lat double precision,
    max_lng double precision,
    max_lat double precision
)
RETURNS TABLE (
    user_id   uuid,
    fuzzy_lat double precision,
    fuzzy_lng double precision
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT u.id,
           ST_Y(l.fuzzy_geom)::double precision AS fuzzy_lat,
           ST_X(l.fuzzy_geom)::double precision AS fuzzy_lng
    FROM users u
    JOIN user_locations l ON l.user_id = u.id
    WHERE u.is_visible = true
      AND u.id <> me
      AND NOT EXISTS (
          SELECT 1 FROM blocks b
          WHERE (b.blocker = me AND b.blocked = u.id)
             OR (b.blocker = u.id AND b.blocked = me)
      )
      AND l.fuzzy_geom && ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326);
$$;

-- events_in_bbox() powers the map endpoint (Requirement 6.3); active events only.
CREATE OR REPLACE FUNCTION events_in_bbox(
    me uuid,
    min_lng double precision,
    min_lat double precision,
    max_lng double precision,
    max_lat double precision
)
RETURNS TABLE (
    id    uuid,
    title text,
    lat   double precision,
    lng   double precision,
    tags  text[]
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT e.id,
           e.title,
           ST_Y(e.geom)::double precision AS lat,
           ST_X(e.geom)::double precision AS lng,
           e.tags
    FROM events e
    WHERE e.is_archived = false
      AND e.ends_at > now()
      AND (e.visibility = 'public' OR e.creator_id = me)
      AND e.geom && ST_MakeEnvelope(min_lng, min_lat, max_lng, max_lat, 4326);
$$;
