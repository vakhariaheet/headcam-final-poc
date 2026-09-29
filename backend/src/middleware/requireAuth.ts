import { verifySessionToken } from '../auth/tokens';
import { ApiError } from '../errors/ApiError';

import type { FastifyReply, FastifyRequest } from 'fastify';

import type { SessionTokenPayload } from '../auth/tokens';

declare module 'fastify' {
  interface FastifyRequest {
    session?: SessionTokenPayload;
  }
}

export async function requireAuth(request: FastifyRequest, _reply: FastifyReply): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    throw ApiError.unauthorized('Missing bearer token');
  }

  const token = header.slice('Bearer '.length);
  try {
    const session = verifySessionToken(token);
    // Tokens issued before the purpose claim was introduced remain valid;
    // email-verification challenge tokens must never authorize API access.
    if (session.purpose && session.purpose !== 'session') {
      throw new Error('Incorrect token purpose');
    }
    request.session = session;
  } catch {
    throw ApiError.unauthorized('Invalid or expired token');
  }
}
