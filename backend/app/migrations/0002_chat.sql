-- 0002 — chat_threads + messages
-- Requirements: 8, 9. Validated by db.hook.kiro / chat.hook.kiro.

CREATE TABLE IF NOT EXISTS chat_threads (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_a          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_b          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at      timestamptz,            -- set on range exit (Requirement 9.2)
    last_message_at timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT chat_threads_distinct_users CHECK (user_a <> user_b)
);

-- One thread per unordered pair: normalise so (a,b) and (b,a) collide.
CREATE UNIQUE INDEX IF NOT EXISTS chat_threads_pair_unique
    ON chat_threads (LEAST(user_a, user_b), GREATEST(user_a, user_b));

CREATE INDEX IF NOT EXISTS chat_threads_user_a_idx ON chat_threads (user_a);
CREATE INDEX IF NOT EXISTS chat_threads_user_b_idx ON chat_threads (user_b);
CREATE INDEX IF NOT EXISTS chat_threads_last_message_idx
    ON chat_threads (last_message_at DESC NULLS LAST);

CREATE TABLE IF NOT EXISTS messages (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    thread_id  uuid NOT NULL REFERENCES chat_threads(id) ON DELETE CASCADE,
    sender_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    body       text NOT NULL,
    read_at    timestamptz,                       -- NULL = unread (Requirement 9.4)
    -- Every message carries a 24h TTL by default (Requirement 9.1 / chat.hook.kiro).
    expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT messages_body_not_blank CHECK (length(btrim(body)) > 0)
);

CREATE INDEX IF NOT EXISTS messages_thread_created_idx
    ON messages (thread_id, created_at DESC);
-- Supports the hourly purge job (Requirement 9.5 / 19.4).
CREATE INDEX IF NOT EXISTS messages_expires_at_idx ON messages (expires_at);
