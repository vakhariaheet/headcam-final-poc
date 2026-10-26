-- Apply explicitly to existing databases; init scripts only run on new volumes.

-- Hats are linked to the account of the phone that claimed them over BLE.
-- The hat identifies itself by its Bluetooth address (serial_number, and the
-- same EUI-48 in mac_address). The spec's ble_uuid is the service UUID, which
-- every hat shares, so it cannot be a unique per-device value.
ALTER TABLE devices ALTER COLUMN ble_uuid DROP NOT NULL;
ALTER TABLE devices ADD COLUMN linked_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN last_seen_at TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN camera_restarts SMALLINT NOT NULL DEFAULT 0;
ALTER TABLE devices ADD COLUMN camera_failed BOOLEAN NOT NULL DEFAULT FALSE;
CREATE INDEX idx_devices_assigned_user ON devices (assigned_user_id);

-- Published firmware images (the build's ota.bin). The file lives in the
-- backend's FIRMWARE_DIR as <id>.bin; sha256 is what the app sends the hat,
-- sealed, so the hat can verify an image it downloads over plain HTTP.
CREATE TABLE firmware_releases (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    hardware_model hardware_model_enum NOT NULL,
    version VARCHAR(20) NOT NULL,
    sha256 CHAR(64) NOT NULL,
    size_bytes INTEGER NOT NULL CHECK (size_bytes > 0),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (hardware_model, version)
);
CREATE INDEX idx_firmware_latest ON firmware_releases (hardware_model, created_at DESC);
