-- 0005 — Row-Level Security
-- Requirement: 18. Validated by db.hook.kiro.
--
-- Convention: the API authenticates the caller and sets the current user id per
-- transaction via `SET LOCAL app.current_user_id = '<uuid>'`. Policies read it through
-- the helper below. The service-role connection used for migrations/cron bypasses RLS.

CREATE OR REPLACE FUNCTION app_current_user_id() RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid;
$$;

-- Enable RLS on every table.
ALTER TABLE users          ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_threads   ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages       ENABLE ROW LEVEL SECURITY;
ALTER TABLE events         ENABLE ROW LEVEL SECURITY;
ALTER TABLE event_rsvps    ENABLE ROW LEVEL SECURITY;
ALTER TABLE blocks         ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- users: any authenticated user may read public profiles; only self may write.
-- (Column-level masking of phone/email is enforced in the API serializer.)
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS users_select_all ON users;
CREATE POLICY users_select_all ON users
    FOR SELECT USING (app_current_user_id() IS NOT NULL);

DROP POLICY IF EXISTS users_update_self ON users;
CREATE POLICY users_update_self ON users
    FOR UPDATE USING (id = app_current_user_id())
    WITH CHECK (id = app_current_user_id());

DROP POLICY IF EXISTS users_delete_self ON users;
CREATE POLICY users_delete_self ON users
    FOR DELETE USING (id = app_current_user_id());

-- ---------------------------------------------------------------------------
-- user_locations: a user may only read/write their OWN location row.
-- Discovery never selects this table directly under the caller's role; the
-- discovery query runs through a SECURITY DEFINER function (0001/0006 service path)
-- that returns only fuzzy coordinates. This prevents leaking others' rows.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS user_locations_owner_all ON user_locations;
CREATE POLICY user_locations_owner_all ON user_locations
    FOR ALL USING (user_id = app_current_user_id())
    WITH CHECK (user_id = app_current_user_id());

-- ---------------------------------------------------------------------------
-- chat_threads / messages: only the two participants may access.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS chat_threads_participants ON chat_threads;
CREATE POLICY chat_threads_participants ON chat_threads
    FOR ALL USING (app_current_user_id() IN (user_a, user_b))
    WITH CHECK (app_current_user_id() IN (user_a, user_b));

DROP POLICY IF EXISTS messages_participants ON messages;
CREATE POLICY messages_participants ON messages
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM chat_threads t
            WHERE t.id = messages.thread_id
              AND app_current_user_id() IN (t.user_a, t.user_b)
        )
    )
    WITH CHECK (
        sender_id = app_current_user_id()
        AND EXISTS (
            SELECT 1 FROM chat_threads t
            WHERE t.id = messages.thread_id
              AND app_current_user_id() IN (t.user_a, t.user_b)
        )
    );

-- ---------------------------------------------------------------------------
-- events: public/active events readable by all authenticated users; only the
-- creator (or a co-host) may modify.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS events_select_visible ON events;
CREATE POLICY events_select_visible ON events
    FOR SELECT USING (
        app_current_user_id() IS NOT NULL
        AND (
            visibility = 'public'
            OR creator_id = app_current_user_id()
            OR EXISTS (
                SELECT 1 FROM event_rsvps r
                WHERE r.event_id = events.id AND r.user_id = app_current_user_id()
            )
        )
    );

DROP POLICY IF EXISTS events_insert_creator ON events;
CREATE POLICY events_insert_creator ON events
    FOR INSERT WITH CHECK (creator_id = app_current_user_id());

DROP POLICY IF EXISTS events_modify_host ON events;
CREATE POLICY events_modify_host ON events
    FOR UPDATE USING (
        creator_id = app_current_user_id()
        OR EXISTS (
            SELECT 1 FROM event_rsvps r
            WHERE r.event_id = events.id
              AND r.user_id = app_current_user_id()
              AND r.role IN ('host', 'co-host')
        )
    );

DROP POLICY IF EXISTS events_delete_creator ON events;
CREATE POLICY events_delete_creator ON events
    FOR DELETE USING (creator_id = app_current_user_id());

-- ---------------------------------------------------------------------------
-- event_rsvps: a user manages their own RSVP; hosts/co-hosts may read all RSVPs
-- for their event (attendee list — Requirement 13.4).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS event_rsvps_select ON event_rsvps;
CREATE POLICY event_rsvps_select ON event_rsvps
    FOR SELECT USING (
        user_id = app_current_user_id()
        OR EXISTS (
            SELECT 1 FROM event_rsvps h
            WHERE h.event_id = event_rsvps.event_id
              AND h.user_id = app_current_user_id()
              AND h.role IN ('host', 'co-host')
        )
    );

DROP POLICY IF EXISTS event_rsvps_write_self ON event_rsvps;
CREATE POLICY event_rsvps_write_self ON event_rsvps
    FOR ALL USING (user_id = app_current_user_id())
    WITH CHECK (user_id = app_current_user_id());

-- ---------------------------------------------------------------------------
-- blocks: a user manages and reads only their own block rows.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS blocks_owner ON blocks;
CREATE POLICY blocks_owner ON blocks
    FOR ALL USING (blocker = app_current_user_id())
    WITH CHECK (blocker = app_current_user_id());
