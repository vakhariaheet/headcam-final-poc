import { downloadImageHandler, listReleasesHandler } from './firmware.controller';
import { HARDWARE_MODELS } from '../devices/devices.types';
import { requireAuth } from '../middleware/requireAuth';

import type { FastifyInstance } from 'fastify';

import type { FirmwareReleaseParams, FirmwareReleaseQuery } from './firmware.types';

const releaseQuery = {
  type: 'object',
  additionalProperties: false,
  required: ['hardwareModel'],
  properties: {
    hardwareModel: { type: 'string', enum: HARDWARE_MODELS },
    limit: { type: 'integer', minimum: 1, maximum: 100 },
  },
};

const releaseParams = {
  type: 'object',
  required: ['id'],
  properties: { id: { type: 'string', format: 'uuid' } },
};

export async function firmwareRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.get<{ Querystring: FirmwareReleaseQuery }>(
    '/',
    { preHandler: requireAuth, schema: { querystring: releaseQuery } },
    listReleasesHandler,
  );
  // Unauthenticated: the hat downloads this itself.
  fastify.get<{ Params: FirmwareReleaseParams }>(
    '/:id/image',
    { schema: { params: releaseParams } },
    downloadImageHandler,
  );
}
