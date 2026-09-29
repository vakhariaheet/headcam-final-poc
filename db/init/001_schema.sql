-- UmpireHat production schema (Master Spec §7.2), applied verbatim except
-- for the addition of the create_hypertable() call noted below.

CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Custom Domain Enumerations
CREATE TYPE user_role_enum AS ENUM ('SUPERADMIN', 'TOURNAMENT_ADMIN', 'BROADCASTER', 'UMPIRE');
CREATE TYPE hardware_model_enum AS ENUM ('AMB82_MINI_V1', 'ESP32_P4_DEV', 'AMB82_PRO_V2');
CREATE TYPE device_status_enum AS ENUM ('UNPROVISIONED', 'PAIRING', 'READY', 'STREAMING', 'MAINTENANCE');
CREATE TYPE streaming_platform_enum AS ENUM ('YOUTUBE', 'FACEBOOK', 'CUSTOM_RTMP');
CREATE TYPE stream_status_enum AS ENUM ('IDLE', 'INITIALIZING', 'LIVE', 'RECONNECTING', 'TERMINATED', 'FAILED');

-- 1. Multi-Tenant Organizations & User Directory
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(128) NOT NULL,
    slug VARCHAR(64) UNIQUE NOT NULL,
    billing_tier VARCHAR(32) DEFAULT 'STANDARD',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID REFERENCES organizations(id) ON DELETE SET NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    first_name VARCHAR(64) NOT NULL,
    last_name VARCHAR(64),
    role user_role_enum DEFAULT 'UMPIRE',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 2. Hardware Fleet Management & Encrypted Presets
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    serial_number VARCHAR(64) UNIQUE NOT NULL,
    mac_address MACADDR UNIQUE NOT NULL,
    ble_uuid UUID UNIQUE NOT NULL,
    hardware_model hardware_model_enum NOT NULL,
    firmware_version VARCHAR(32) NOT NULL,
    current_status device_status_enum DEFAULT 'UNPROVISIONED',
    battery_health_pct SMALLINT CHECK (battery_health_pct BETWEEN 0 AND 100),
    assigned_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE hotspot_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    ssid VARCHAR(64) NOT NULL,
    encrypted_passphrase TEXT NOT NULL,
    passphrase_iv VARCHAR(32) NOT NULL,
    passphrase_tag VARCHAR(32) NOT NULL,
    frequency_band VARCHAR(8) DEFAULT '5GHz',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, ssid)
);

-- 3. Third-Party OAuth Integrations & Broadcast Sinks
CREATE TABLE oauth_integrations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform streaming_platform_enum NOT NULL,
    platform_account_id VARCHAR(128) NOT NULL,
    account_name VARCHAR(128) NOT NULL,
    encrypted_access_token TEXT NOT NULL,
    encrypted_refresh_token TEXT,
    token_expires_at TIMESTAMPTZ NOT NULL,
    is_valid BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, platform, platform_account_id)
);

CREATE TABLE broadcast_destinations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    integration_id UUID NOT NULL REFERENCES oauth_integrations(id) ON DELETE CASCADE,
    destination_name VARCHAR(128) NOT NULL,
    platform streaming_platform_enum NOT NULL,
    target_id VARCHAR(128) NOT NULL,
    custom_rtmp_url VARCHAR(255),
    encrypted_custom_stream_key TEXT,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 4. Match Records & CricHeroes Entity Links
CREATE TABLE matches (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cricheroes_match_id VARCHAR(32) UNIQUE NOT NULL,
    raw_input_url TEXT NOT NULL,
    tournament_name VARCHAR(128),
    team_a_name VARCHAR(64) NOT NULL,
    team_b_name VARCHAR(64) NOT NULL,
    overlay_web_url TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 5. Broadcast Sessions & Simulcast Routing Table
CREATE TABLE stream_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_token VARCHAR(64) UNIQUE NOT NULL,
    device_id UUID NOT NULL REFERENCES devices(id),
    user_id UUID NOT NULL REFERENCES users(id),
    match_id UUID NOT NULL REFERENCES matches(id),
    status stream_status_enum DEFAULT 'INITIALIZING',
    hat_ingress_rtsp_url TEXT,
    initialized_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    live_started_at TIMESTAMPTZ,
    ended_at TIMESTAMPTZ,
    total_reconnections INTEGER DEFAULT 0
);

CREATE TABLE session_destinations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id UUID NOT NULL REFERENCES stream_sessions(id) ON DELETE CASCADE,
    destination_id UUID NOT NULL REFERENCES broadcast_destinations(id),
    platform streaming_platform_enum NOT NULL,
    platform_broadcast_id VARCHAR(128),
    stream_key TEXT NOT NULL,
    ingest_endpoint TEXT NOT NULL,
    egress_status stream_status_enum DEFAULT 'INITIALIZING',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 6. TimescaleDB Telemetry Metric Stream (Hypertable)
CREATE TABLE telemetry_samples (
    recorded_at TIMESTAMPTZ NOT NULL,
    session_id UUID NOT NULL,
    battery_level_pct SMALLINT,
    soc_temperature_c NUMERIC(4,1),
    outbound_bitrate_kbps INTEGER,
    fps NUMERIC(4,1),
    packet_loss_pct NUMERIC(4,2)
);

-- The spec's §7.1 narrative calls this a hypertable and its BRIN index on
-- recorded_at implies time-partitioned storage, but the DDL as written never
-- actually converts it — added here so it behaves as intended.
SELECT create_hypertable('telemetry_samples', 'recorded_at');

-- Indexing Strategy
CREATE INDEX idx_telemetry_time ON telemetry_samples USING BRIN (recorded_at);
CREATE INDEX idx_telemetry_session ON telemetry_samples (session_id, recorded_at DESC);
