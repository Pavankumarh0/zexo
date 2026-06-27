-- 0004 — blocks (safety / moderation)
-- Requirement: 16. Used by every discovery, map, and attendee query for bidirectional
-- exclusion.

CREATE TABLE IF NOT EXISTS blocks (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason     text,                 -- optional report reason (Requirement 16.1)
    reported   boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT blocks_not_self CHECK (blocker <> blocked),
    CONSTRAINT blocks_pair_unique UNIQUE (blocker, blocked)
);

CREATE INDEX IF NOT EXISTS blocks_blocker_idx ON blocks (blocker);
CREATE INDEX IF NOT EXISTS blocks_blocked_idx ON blocks (blocked);
