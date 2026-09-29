import jwt from 'jsonwebtoken';

import type { FastifyReply, FastifyRequest } from 'fastify';

// Must match backend/'s JWT_SECRET exactly — this worker verifies the same
// tokens backend/'s auth API issues, rather than running its own scheme.
const JWT_SECRET = process.env.JWT_SECRET ?? 'umpirehat-dev-secret-change-me';

interface SessionTokenPayload {
  sub: string;
  email: string;
  role: string;
  purpose?: 'session' | 'verify_email';
}

declare module 'fastify' {
  interface FastifyRequest {
    userId?: string;
  }
}

export async function requireAuth(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const header = request.headers.authorization;
  if (!header?.startsWith('Bearer ')) {
    reply.status(401).send({ error: { code: 'UNAUTHORIZED', message: 'Missing bearer token' } });
    return;
  }

  try {
    const payload = jwt.verify(header.slice('Bearer '.length), JWT_SECRET) as SessionTokenPayload;
    if (payload.purpose === 'verify_email') {
      throw new Error('Incorrect token purpose');
    }
    request.userId = payload.sub;
  } catch {
    reply
      .status(401)
      .send({ error: { code: 'UNAUTHORIZED', message: 'Invalid or expired token' } });
  }
}
