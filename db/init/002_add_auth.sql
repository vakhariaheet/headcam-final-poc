-- Adds password storage for real email/password authentication
-- (backend/), which spec §7.2's original `users` table didn't account for.
ALTER TABLE users ADD COLUMN password_hash TEXT NOT NULL;
