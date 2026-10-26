export const HARDWARE_MODELS = ['AMB82_MINI_V1', 'ESP32_P4_DEV', 'AMB82_PRO_V2'] as const;

export type HardwareModel = typeof HARDWARE_MODELS[number];

/** A hat's Bluetooth address as the firmware's INFO reply reports it. */
export const SERIAL_NUMBER_PATTERN = '^[0-9A-F]{12}$';

export interface DeviceParams {
  serialNumber: string;
}

/**
 * What the app learned from the hat over BLE, sent each time it connects
 * as the hat's owner.
 */
export interface LinkDeviceRequestBody {
  hardwareModel: HardwareModel;
  firmwareVersion: string;
  cameraRestarts: number;
  cameraFailed: boolean;
}

export interface Device {
  id: string;
  serialNumber: string;
  hardwareModel: HardwareModel;
  firmwareVersion: string;
  linkedAt: string | null;
  lastSeenAt: string | null;
  cameraRestarts: number;
  cameraFailed: boolean;
}

export interface DeviceRow {
  id: string;
  serial_number: string;
  hardware_model: HardwareModel;
  firmware_version: string;
  linked_at: Date | null;
  last_seen_at: Date | null;
  camera_restarts: number;
  camera_failed: boolean;
}

export interface LinkDeviceResult {
  device: Device;
  created: boolean;
}
