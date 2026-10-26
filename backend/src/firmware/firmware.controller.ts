import { listReleases, openImage } from './firmware.service';

import type { FastifyReply, FastifyRequest } from 'fastify';

import type { FirmwareReleaseParams, FirmwareReleaseQuery } from './firmware.types';

const DEFAULT_LIMIT = 20;

export async function listReleasesHandler(
  request: FastifyRequest<{ Querystring: FirmwareReleaseQuery }>,
  reply: FastifyReply,
): Promise<void> {
  const { hardwareModel, limit = DEFAULT_LIMIT } = request.query;
  const origin = `${request.protocol}://${request.host}`;
  const items = await listReleases(hardwareModel, limit, origin);
  reply.status(200).send({ items });
}

/**
 * Serves the image to the hat, which has no account token. The release id
 * is unguessable and the hat verifies the SHA-256 the owner's app sent it.
 * Content-Length is required: the hat's downloader rejects chunked bodies.
 * Returns the reply: an async handler that sends a stream without returning
 * it ends the response before the stream is piped.
 */
export async function downloadImageHandler(
  request: FastifyRequest<{ Params: FirmwareReleaseParams }>,
  reply: FastifyReply,
): Promise<FastifyReply> {
  const image = await openImage(request.params.id);
  return reply
    .status(200)
    .header('content-type', 'application/octet-stream')
    .header('content-length', image.sizeBytes)
    .header('content-disposition', `attachment; filename="${image.fileName}"`)
    .send(image.stream);
}
