import { linkDevice, listDevices, unlinkDevice } from './devices.service';
import { ApiError } from '../errors/ApiError';

import type { FastifyReply, FastifyRequest } from 'fastify';

import type { DeviceParams, LinkDeviceRequestBody } from './devices.types';

function sessionUserId(request: FastifyRequest): string {
  if (!request.session) {
    throw ApiError.unauthorized('Missing bearer token');
  }
  return request.session.sub;
}

export async function linkDeviceHandler(
  request: FastifyRequest<{ Params: DeviceParams; Body: LinkDeviceRequestBody }>,
  reply: FastifyReply,
): Promise<void> {
  const { device, created } = await linkDevice(
    sessionUserId(request),
    request.params.serialNumber,
    request.body,
  );
  reply.status(created ? 201 : 200).send(device);
}

export async function listDevicesHandler(
  request: FastifyRequest,
  reply: FastifyReply,
): Promise<void> {
  const items = await listDevices(sessionUserId(request));
  reply.status(200).send({ items });
}

export async function unlinkDeviceHandler(
  request: FastifyRequest<{ Params: DeviceParams }>,
  reply: FastifyReply,
): Promise<void> {
  await unlinkDevice(sessionUserId(request), request.params.serialNumber);
  reply.status(204).send();
}
