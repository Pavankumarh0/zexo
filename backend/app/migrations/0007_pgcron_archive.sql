-- 0007 — pg_cron: auto-archive ended events
-- Requirement: 15.1. Validated by db.hook.kiro.

CREATE OR REPLACE FUNCTION archive_ended_events() RETURNS integer
LANGUAGE plpgsql AS $$
DECLARE
    updated integer;
BEGIN
    UPDATE events
       SET is_archived = true
     WHERE is_archived = false
       AND ends_at < now();
    GET DIAGNOSTICS updated = ROW_COUNT;
    RETURN updated;
END;
$$;

DO $$
BEGIN
    PERFORM cron.unschedule('zexo_archive_ended_events')
    WHERE EXISTS (
        SELECT 1 FROM cron.job WHERE jobname = 'zexo_archive_ended_events'
    );
END $$;

SELECT cron.schedule(
    'zexo_archive_ended_events',
    '*/15 * * * *',                    -- every 15 minutes
    $$SELECT archive_ended_events();$$
);
