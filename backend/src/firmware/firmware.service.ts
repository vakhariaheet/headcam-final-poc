import { createHash, randomUUID } from 'node:crypto';
import { createReadStream } from 'node:fs';
import {
  copyFile, mkdir, readFile, rename, rm, stat,
} from 'node:fs/promises';
import path from 'node:path';

import { FIRMWARE_DIR, FIRMWARE_DOWNLOAD_BASE_URL } from '../config';
import { pool } from '../db';
import {
  FIRMWARE_VERSION_PATTERN, MAX_IMAGE_BYTES, MIN_IMAGE_BYTES,
} from './firmware.types';
import { ApiError } from '../errors/ApiError';

import type { ReadStream } from 'node:fs';

import type {
  FirmwareRelease, FirmwareReleaseRow, PublishFirmwareInput,
} from './firmware.types';
import type { HardwareModel } from '../devices/devices.types';

const RELEASE_COLUMNS = 'id, hardware_model, version, sha256, size_bytes, notes, created_at';
const LOOPBACK_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]', '0.0.0.0']);

function imagePath(id: string): string {
  return path.join(FIRMWARE_DIR, `${id}.bin`);
}

/**
 * Picks the origin the hat downloads from: [configured]
 * (FIRMWARE_DOWNLOAD_BASE_URL), or else the origin the app used, when the
 * hat could reach that too.
 */
export function downloadBaseUrl(
  requestOrigin: string,
  configured: string | null = FIRMWARE_DOWNLOAD_BASE_URL ?? null,
): string {
  const base = configured ?? requestOrigin;
  let url: URL;
  try {
    url = new URL(base);
  } catch {
    throw ApiError.serviceUnavailable('FIRMWARE_DOWNLOAD_BASE_URL is not a valid URL.');
  }
  if (url.protocol !== 'http:' || LOOPBACK_HOSTS.has(url.hostname)) {
    throw ApiError.serviceUnavailable(
      'Hats download updates over plain HTTP on their own network. Set '
      + 'FIRMWARE_DOWNLOAD_BASE_URL to an http:// address the hat can reach.',
    );
  }
  return url.origin;
}

function toRelease(row: FirmwareReleaseRow, baseUrl: string): FirmwareRelease {
  return {
    id: row.id,
    hardwareModel: row.hardware_model,
    version: row.version,
    sha256: row.sha256,
    sizeBytes: row.size_bytes,
    notes: row.notes,
    createdAt: row.created_at.toISOString(),
    downloadUrl: `${baseUrl}/api/v1/firmware-releases/${row.id}/image`,
  };
}

/** Newest first. */
export async function listReleases(
  hardwareModel: HardwareModel,
  limit: number,
  requestOrigin: string,
): Promise<FirmwareRelease[]> {
  const baseUrl = downloadBaseUrl(requestOrigin);
  const result = await pool.query<FirmwareReleaseRow>(
    `SELECT ${RELEASE_COLUMNS} FROM firmware_releases WHERE hardware_model = $1
     ORDER BY created_at DESC LIMIT $2`,
    [hardwareModel, limit],
  );
  return result.rows.map((row) => toRelease(row, baseUrl));
}

export interface FirmwareImage {
  stream: ReadStream;
  sizeBytes: number;
  fileName: string;
}

/** Opens a release's image, refusing a file that no longer matches its record. */
export async function openImage(id: string): Promise<FirmwareImage> {
  const result = await pool.query<FirmwareReleaseRow>(
    `SELECT ${RELEASE_COLUMNS} FROM firmware_releases WHERE id = $1`,
    [id],
  );
  const row = result.rows[0];
  if (!row) throw ApiError.notFound('No firmware release with that id');
  const file = imagePath(row.id);
  const info = await stat(file).catch(() => null);
  if (info?.size !== row.size_bytes) {
    throw ApiError.notFound('That firmware image is missing on the server');
  }
  return {
    stream: createReadStream(file),
    sizeBytes: row.size_bytes,
    fileName: `umpirehat-${row.hardware_model.toLowerCase()}-${row.version}.bin`,
  };
}

/**
 * Records a build's ota.bin as a release and stores a copy. Used by the
 * firmware:publish script, not exposed over HTTP.
 */
export async function publishRelease(input: PublishFirmwareInput): Promise<FirmwareReleaseRow> {
  if (!new RegExp(FIRMWARE_VERSION_PATTERN).test(input.version)) {
    throw ApiError.validation('Version may use letters, digits, ".", "+" and "-" (at most 20).');
  }
  const image = await readFile(input.filePath);
  if (image.length < MIN_IMAGE_BYTES || image.length > MAX_IMAGE_BYTES) {
    throw ApiError.validation(
      `Image must be ${MIN_IMAGE_BYTES}-${MAX_IMAGE_BYTES} bytes (the build's ota.bin).`,
    );
  }
  const sha256 = createHash('sha256').update(image).digest('hex');
  const id = randomUUID();

  await mkdir(FIRMWARE_DIR, { recursive: true });
  const partial = `${imagePath(id)}.partial`;
  await copyFile(input.filePath, partial);
  try {
    const result = await pool.query<FirmwareReleaseRow>(
      `INSERT INTO firmware_releases (id, hardware_model, version, sha256, size_bytes, notes)
       VALUES ($1, $2, $3, $4, $5, $6) RETURNING ${RELEASE_COLUMNS}`,
      [id, input.hardwareModel, input.version, sha256, image.length, input.notes ?? null],
    );
    await rename(partial, imagePath(id));
    return result.rows[0];
  } catch (err) {
    await rm(partial, { force: true });
    throw err;
  }
}
