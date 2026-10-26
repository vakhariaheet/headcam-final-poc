import type { HardwareModel } from '../devices/devices.types';

/** Release names travel to the hat; the firmware accepts only these. */
export const FIRMWARE_VERSION_PATTERN = '^[0-9A-Za-z.+-]{1,20}$';

/** One AmebaPro2 firmware slot (0x400000) plus the image's 4-byte checksum. */
export const MAX_IMAGE_BYTES = 0x400000 + 4;

/** Smallest image that still holds the manifest timestamp the hat checks. */
export const MIN_IMAGE_BYTES = 0x2d4 + 8;

export interface FirmwareReleaseQuery {
  hardwareModel: HardwareModel;
  limit?: number;
}

export interface FirmwareReleaseParams {
  id: string;
}

export interface FirmwareRelease {
  id: string;
  hardwareModel: HardwareModel;
  version: string;
  sha256: string;
  sizeBytes: number;
  notes: string | null;
  createdAt: string;
  /** Plain-HTTP address the hat downloads the image from. */
  downloadUrl: string;
}

export interface FirmwareReleaseRow {
  id: string;
  hardware_model: HardwareModel;
  version: string;
  sha256: string;
  size_bytes: number;
  notes: string | null;
  created_at: Date;
}

export interface PublishFirmwareInput {
  hardwareModel: HardwareModel;
  version: string;
  filePath: string;
  notes?: string;
}
