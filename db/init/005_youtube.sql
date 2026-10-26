-- Apply explicitly to existing databases; init scripts only run on new volumes.
CREATE TABLE youtube_connections (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    channel_id TEXT NOT NULL,
    channel_name TEXT NOT NULL,
    refresh_token_cipher TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE youtube_oauth_states (
    state_hash TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMPTZ NOT NULL
);
CREATE TABLE youtube_broadcasts (
    session_id UUID PRIMARY KEY REFERENCES stream_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    broadcast_id TEXT NOT NULL,
    stream_id TEXT NOT NULL,
    ingest_cipher TEXT NOT NULL,
    ended_at TIMESTAMPTZ
);
ALTER TABLE stream_sessions ADD COLUMN scoreboard JSONB;
