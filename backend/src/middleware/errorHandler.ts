import { ApiError } from '../errors/ApiError';

import type { FastifyError, FastifyReply, FastifyRequest } from 'fastify';

export interface ErrorResponseBody {
  error: {
    code: string;
    message: string;
  };
}

export function errorHandler(
  error: FastifyError | ApiError,
  request: FastifyRequest,
  reply: FastifyReply,
): void {
  if (error instanceof ApiError) {
    const body: ErrorResponseBody = { error: { code: error.code, message: error.message } };
    reply.status(error.statusCode).send(body);
    return;
  }

  // request.log is a per-request child of the shared logger (see
  // logger.ts) — already carries reqId/method/url, so the exception is
  // traceable back to the request that caused it without re-stating them.
  request.log.error(error);
  const body: ErrorResponseBody = {
    error: { code: 'INTERNAL_ERROR', message: 'Internal server error' },
  };
  reply.status(500).send(body);
}
