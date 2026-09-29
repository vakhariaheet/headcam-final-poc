-- device_id/match_id are NOT NULL in the spec (§7.2), but this POC
-- doesn't yet sync BLE-paired hats into `devices` or parsed CricHeroes
-- matches into `matches` (both are still mobile-local-only state) —
-- relaxed to nullable so the cloud worker can use this table as a real
-- session registry now, backfilled once device/match sync exists.
ALTER TABLE stream_sessions ALTER COLUMN device_id DROP NOT NULL;
ALTER TABLE stream_sessions ALTER COLUMN match_id DROP NOT NULL;

-- Which worker instance is actually running this session's Puppeteer/
-- FFmpeg pipeline — not in the original spec, needed so a request can be
-- routed to the right instance once more than one worker exists.
ALTER TABLE stream_sessions ADD COLUMN worker_host TEXT;
