/**
 * Publishes a firmware build for over-the-air updates:
 *
 *   npm run firmware:publish -- --model AMB82_MINI_V1 --version 0.3.0 \
 *     --file path/to/ota.bin [--notes "What changed"]
 *
 * Use the build's ota.bin (firmware.bin plus its checksum), and bump
 * HAT_FIRMWARE_VERSION in firmware/.../hat_version.h to the same version
 * before building, so the app can tell when the hat is up to date.
 */
import { parseArgs } from 'node:util';

import { pool } from '../db';
import { publishRelease } from './firmware.service';
import { HARDWARE_MODELS } from '../devices/devices.types';

import type { HardwareModel } from '../devices/devices.types';

function isHardwareModel(value: string): value is HardwareModel {
  return (HARDWARE_MODELS as readonly string[]).includes(value);
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      model: { type: 'string' },
      version: { type: 'string' },
      file: { type: 'string' },
      notes: { type: 'string' },
    },
  });
  const {
    model, version, file, notes,
  } = values;
  if (!model || !version || !file || !isHardwareModel(model)) {
    throw new Error(
      `Usage: --model <${HARDWARE_MODELS.join('|')}> --version <x.y.z> `
      + '--file <ota.bin> [--notes <text>]',
    );
  }
  const release = await publishRelease({
    hardwareModel: model, version, filePath: file, notes,
  });
  process.stdout.write(
    `Published ${release.hardware_model} ${release.version}: ${release.size_bytes} bytes, `
    + `sha256 ${release.sha256}, id ${release.id}\n`,
  );
}

main()
  .catch((err: unknown) => {
    process.stderr.write(`${err instanceof Error ? err.message : String(err)}\n`);
    process.exitCode = 1;
  })
  .finally(async () => pool.end());
