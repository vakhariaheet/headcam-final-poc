import { pool } from '../db';
import { ApiError } from '../errors/ApiError';

import type {
  Device, DeviceRow, LinkDeviceRequestBody, LinkDeviceResult,
} from './devices.types';

const DEVICE_COLUMNS = `id, serial_number, hardware_model, firmware_version, linked_at,
  last_seen_at, camera_restarts, camera_failed`;

function toDevice(row: DeviceRow): Device {
  return {
    id: row.id,
    serialNumber: row.serial_number,
    hardwareModel: row.hardware_model,
    firmwareVersion: row.firmware_version,
    linkedAt: row.linked_at?.toISOString() ?? null,
    lastSeenAt: row.last_seen_at?.toISOString() ?? null,
    cameraRestarts: row.camera_restarts,
    cameraFailed: row.camera_failed,
  };
}

/** AABBCCDDEEFF -> aa:bb:cc:dd:ee:ff, the Postgres MACADDR text form. */
function macAddress(serialNumber: string): string {
  return serialNumber.toLowerCase().match(/../g)?.join(':') ?? serialNumber;
}

/**
 * Links a hat to the signed-in account and records what the hat reported.
 *
 * The hat's BLE ownership protocol is the authority: only the phone holding
 * the hat's owner key can read its INFO, and a new claim needs physical
 * access to the button. The backend cannot verify that itself, so a link
 * request moves the hat to the caller's account. Production hats need a
 * per-device factory key the backend can check before a transfer.
 */
export async function linkDevice(
  userId: string,
  serialNumber: string,
  body: LinkDeviceRequestBody,
): Promise<LinkDeviceResult> {
  const result = await pool.query<DeviceRow & { created: boolean }>(
    `INSERT INTO devices (serial_number, mac_address, hardware_model, firmware_version,
       current_status, assigned_user_id, linked_at, last_seen_at, camera_restarts, camera_failed)
     VALUES ($1, $2, $3, $4, 'READY', $5, now(), now(), $6, $7)
     ON CONFLICT (serial_number) DO UPDATE SET
       hardware_model = EXCLUDED.hardware_model,
       firmware_version = EXCLUDED.firmware_version,
       linked_at = CASE WHEN devices.assigned_user_id IS DISTINCT FROM EXCLUDED.assigned_user_id
         THEN now() ELSE devices.linked_at END,
       assigned_user_id = EXCLUDED.assigned_user_id,
       current_status = CASE WHEN devices.current_status = 'UNPROVISIONED'
         THEN 'READY' ELSE devices.current_status END,
       last_seen_at = now(),
       camera_restarts = EXCLUDED.camera_restarts,
       camera_failed = EXCLUDED.camera_failed
     RETURNING ${DEVICE_COLUMNS}, (xmax = 0) AS created`,
    [
      serialNumber,
      macAddress(serialNumber),
      body.hardwareModel,
      body.firmwareVersion,
      userId,
      body.cameraRestarts,
      body.cameraFailed,
    ],
  );
  const row = result.rows[0];
  return { device: toDevice(row), created: row.created };
}

export async function listDevices(userId: string): Promise<Device[]> {
  const result = await pool.query<DeviceRow>(
    `SELECT ${DEVICE_COLUMNS} FROM devices WHERE assigned_user_id = $1
     ORDER BY linked_at DESC NULLS LAST`,
    [userId],
  );
  return result.rows.map(toDevice);
}

/** Unlinks one of the caller's hats. Other accounts' hats read as missing. */
export async function unlinkDevice(userId: string, serialNumber: string): Promise<void> {
  const result = await pool.query(
    `UPDATE devices SET assigned_user_id = NULL, linked_at = NULL
     WHERE serial_number = $1 AND assigned_user_id = $2`,
    [serialNumber, userId],
  );
  if (!result.rowCount) {
    throw ApiError.notFound('No hat with that serial number is linked to your account');
  }
}
