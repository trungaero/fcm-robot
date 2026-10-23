-- FCM Robot pilot schema (architecture.md §7.2).
-- Applied by the postgres container on first boot in dev, and manually against
-- Azure Database for PostgreSQL Flexible Server after `terraform apply`.

CREATE TABLE IF NOT EXISTS devices (
    device_id          TEXT PRIMARY KEY,
    org_id             TEXT,
    model              TEXT,
    firmware_version   TEXT,
    attestation_state  TEXT NOT NULL DEFAULT 'unknown',
    revoked_at         TIMESTAMPTZ,
    last_seen_at       TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sessions (
    session_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_name       TEXT NOT NULL UNIQUE,
    device_id       TEXT NOT NULL,
    started_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    ended_at        TIMESTAMPTZ,
    end_reason      TEXT,
    agent_worker_id TEXT,
    region          TEXT
);

CREATE TABLE IF NOT EXISTS turns (
    turn_id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id          UUID NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    seq                 INTEGER NOT NULL,
    user_text           TEXT,
    assistant_text      TEXT,
    started_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    vad_end_ms          INTEGER,
    stt_ms              INTEGER,
    llm_first_token_ms  INTEGER,
    tts_first_byte_ms   INTEGER,
    total_ms            INTEGER,
    barge_in            BOOLEAN NOT NULL DEFAULT FALSE,
    degraded            BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (session_id, seq)
);

CREATE TABLE IF NOT EXISTS emotion_events (
    event_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id    UUID NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    turn_id       UUID REFERENCES turns (turn_id) ON DELETE SET NULL,
    label         TEXT NOT NULL,
    confidence    REAL,
    model_version TEXT,
    captured_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recordings (
    recording_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID NOT NULL REFERENCES sessions (session_id) ON DELETE CASCADE,
    blob_path       TEXT NOT NULL,
    consent_ref     TEXT,
    retention_until TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS audit_events (
    event_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor     TEXT,
    action    TEXT NOT NULL,
    target    TEXT,
    at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    source_ip INET,
    result    TEXT
);

CREATE INDEX IF NOT EXISTS idx_sessions_device_started ON sessions (device_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_turns_session_seq       ON turns (session_id, seq);
CREATE INDEX IF NOT EXISTS idx_emotion_session         ON emotion_events (session_id, captured_at);
CREATE INDEX IF NOT EXISTS idx_audit_at                ON audit_events (at DESC);
