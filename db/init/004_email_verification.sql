-- New accounts remain pending until the six-digit email challenge succeeds.
ALTER TABLE users ADD COLUMN email_verified_at TIMESTAMPTZ;

-- Accounts created before verification existed remain usable.
UPDATE users SET email_verified_at = created_at WHERE email_verified_at IS NULL;

CREATE TABLE email_verification_codes (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    code_hash CHAR(64) NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    attempts SMALLINT NOT NULL DEFAULT 0,
    last_sent_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);
