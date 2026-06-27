-- 0006 — pg_cron: purge expired messages
-- Requirements: 9.5, 19.4. Deleted within 1 hour of expiry. Validated by db.hook.kiro.

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Idempotent purge routine: removes messages past their TTL.
CREATE OR REPLACE FUNCTION purge_expired_messages() RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    deleted integer;
BEGIN
    DELETE FROM messages WHERE expires_at < now();
    GET DIAGNOSTICS deleted = ROW_COUNT;
    RETURN deleted;
END;
$$;

-- Run hourly (purge within 1h of expiry). Unschedule any prior definition first.
DO $$
BEGIN
    PERFORM cron.unschedule('zexo_purge_expired_messages')
    WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'zexo_purge_expired_messages'
    );
END $$;

SELECT cron.schedule(
    'zexo_purge_expired_messages',
    '0 * * * *',                       -- top of every hour
    $$SELECT purge_expired_messages();$$
);
