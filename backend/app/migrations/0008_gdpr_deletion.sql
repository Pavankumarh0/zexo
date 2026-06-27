-- 0008 — GDPR account deletion
-- Requirement: 17. Purges all PII and location history. FK cascades remove dependent
-- rows (user_locations, messages, event_rsvps, blocks); events created by the user
-- cascade via creator_id ON DELETE CASCADE.

CREATE OR REPLACE FUNCTION delete_user_account(target uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
    -- Explicitly clear location history first (defence in depth; cascade also covers it).
    DELETE FROM user_locations WHERE user_id = target;
    -- Deleting the user cascades to threads, messages, rsvps, blocks, and owned events.
    DELETE FROM users WHERE id = target;
END;
$$;

COMMENT ON FUNCTION delete_user_account(uuid) IS
    'GDPR erasure: removes the user and all dependent PII/location rows. '
    'Auth credentials are revoked separately via Supabase Auth admin API.';
