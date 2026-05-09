
-- BSConnect Database Initialization
-- Runs once on first Postgres container boot

-- ── Roles ────────────────────────────────
CREATE ROLE api_user        WITH LOGIN PASSWORD 'CHANGE_IN_ENV';
CREATE ROLE api_readonly    WITH LOGIN PASSWORD 'CHANGE_IN_ENV';
CREATE ROLE migrations_user WITH LOGIN PASSWORD 'CHANGE_IN_ENV' CREATEROLE;

-- ── Grant schema usage ───────────────────
GRANT CONNECT ON DATABASE bsconnect TO api_user;
GRANT CONNECT ON DATABASE bsconnect TO api_readonly;
GRANT USAGE ON SCHEMA public TO api_user;
GRANT USAGE ON SCHEMA public TO api_readonly;

-- ── Extensions ───────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- future: username search

-- ─────────────────────────────────────────
-- TABLES
-- ─────────────────────────────────────────

-- ── Users ────────────────────────────────
CREATE TABLE users (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    username        TEXT        NOT NULL UNIQUE,
    email           TEXT        NOT NULL UNIQUE,
    password_hash   TEXT        NOT NULL,
    region_tag      TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen       TIMESTAMPTZ,
    deleted_at      TIMESTAMPTZ                         -- soft delete
);

-- ── Channels ─────────────────────────────
CREATE TABLE channels (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    type            TEXT        NOT NULL CHECK (type IN ('global','regional','topic','dm','group')),
    name            TEXT,
    region_tag      TEXT,
    created_by      UUID        REFERENCES users(id) ON DELETE SET NULL,
    retention_days  INT,                                -- NULL = keep forever
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at      TIMESTAMPTZ
);

-- ── Channel Members ───────────────────────
CREATE TABLE channel_members (
    channel_id              UUID        NOT NULL REFERENCES channels(id) ON DELETE CASCADE,
    user_id                 UUID        NOT NULL REFERENCES users(id)    ON DELETE CASCADE,
    role                    TEXT        NOT NULL DEFAULT 'member' CHECK (role IN ('owner','admin','member')),
    auto_delete_override    INT,                        -- user-level retention opt-in (days)
    joined_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (channel_id, user_id)
);

-- ── Messages ─────────────────────────────
CREATE TABLE messages (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    channel_id      UUID        NOT NULL REFERENCES channels(id)  ON DELETE CASCADE,
    sender_id       UUID        NOT NULL REFERENCES users(id),
    payload         BYTEA       NOT NULL,               -- AES-256-GCM encrypted protobuf
    iv              BYTEA       NOT NULL,               -- per-message IV
    key_version     INT         NOT NULL DEFAULT 1,     -- Vault key version used
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ,                        -- set at insert from retention_days
    deleted_at      TIMESTAMPTZ                         -- soft delete
);

-- ── Refresh Tokens ────────────────────────
CREATE TABLE refresh_tokens (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash      TEXT        NOT NULL UNIQUE,
    expires_at      TIMESTAMPTZ NOT NULL,
    revoked_at      TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ─────────────────────────────────────────
-- INDEXES
-- ─────────────────────────────────────────
CREATE INDEX idx_messages_channel_created
    ON messages (channel_id, created_at DESC)
    WHERE deleted_at IS NULL;

CREATE INDEX idx_messages_expires
    ON messages (expires_at)
    WHERE expires_at IS NOT NULL AND deleted_at IS NULL;

CREATE INDEX idx_channel_members_user
    ON channel_members (user_id);

CREATE INDEX idx_users_username_trgm
    ON users USING GIN (username gin_trgm_ops);

CREATE INDEX idx_refresh_tokens_user
    ON refresh_tokens (user_id)
    WHERE revoked_at IS NULL;

-- ─────────────────────────────────────────
-- ROW LEVEL SECURITY
-- ─────────────────────────────────────────

-- Messages: api_user can only read messages from channels they're a member of
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY message_channel_access ON messages
    FOR SELECT TO api_user
    USING (
        channel_id IN (
            SELECT channel_id FROM channel_members
            WHERE user_id = current_setting('app.current_user_id', true)::UUID
        )
    );

CREATE POLICY message_insert ON messages
    FOR INSERT TO api_user
    WITH CHECK (
        channel_id IN (
            SELECT channel_id FROM channel_members
            WHERE user_id = current_setting('app.current_user_id', true)::UUID
        )
    );

-- Channel members: users can only see channels they belong to
ALTER TABLE channel_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY channel_member_access ON channel_members
    FOR SELECT TO api_user
    USING (
        user_id = current_setting('app.current_user_id', true)::UUID
        OR channel_id IN (
            SELECT channel_id FROM channel_members
            WHERE user_id = current_setting('app.current_user_id', true)::UUID
        )
    );

-- ─────────────────────────────────────────
-- GRANTS
-- ─────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE           ON users           TO api_user;
GRANT SELECT, INSERT, UPDATE           ON channels        TO api_user;
GRANT SELECT, INSERT, UPDATE, DELETE   ON channel_members TO api_user;
GRANT SELECT, INSERT, UPDATE           ON messages        TO api_user;
GRANT SELECT, INSERT, UPDATE           ON refresh_tokens  TO api_user;

GRANT SELECT ON users, channels, channel_members, messages TO api_readonly;

GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO migrations_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO migrations_user;
