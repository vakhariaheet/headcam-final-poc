import { linkDeviceHandler, listDevicesHandler, unlinkDeviceHandler } from './devices.controller';
import { HARDWARE_MODELS, SERIAL_NUMBER_PATTERN } from './devices.types';
import { requireAuth } from '../middleware/requireAuth';

import type { FastifyInstance } from 'fastify';

import type { DeviceParams, LinkDeviceRequestBody } from './devices.types';

const deviceParams = {
  type: 'object',
  required: ['serialNumber'],
  properties: { serialNumber: { type: 'string', pattern: SERIAL_NUMBER_PATTERN } },
};

const linkDeviceBody = {
  type: 'object',
  additionalProperties: false,
  required: ['hardwareModel', 'firmwareVersion', 'cameraRestarts', 'cameraFailed'],
  properties: {
    hardwareModel: { type: 'string', enum: HARDWARE_MODELS },
    firmwareVersion: { type: 'string', pattern: '^[0-9A-Za-z.+-]{1,20}$' },
    cameraRestarts: { type: 'integer', minimum: 0, maximum: 100 },
    cameraFailed: { type: 'boolean' },
  },
};

export async function deviceRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.addHook('preHandler', requireAuth);
  fastify.get('/', listDevicesHandler);
  fastify.put<{ Params: DeviceParams; Body: LinkDeviceRequestBody }>(
    '/:serialNumber',
    { schema: { params: deviceParams, body: linkDeviceBody } },
    linkDeviceHandler,
  );
  fastify.delete<{ Params: DeviceParams }>(
    '/:serialNumber',
    { schema: { params: deviceParams } },
    unlinkDeviceHandler,
  );
}
