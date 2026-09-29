import {
  loginHandler, meHandler, resendVerificationHandler, signupHandler, verifyEmailHandler,
} from './auth.controller';
import { requireAuth } from '../middleware/requireAuth';

import type { FastifyInstance } from 'fastify';

export async function authRoutes(fastify: FastifyInstance): Promise<void> {
  fastify.post('/signup', signupHandler);
  fastify.post('/verify-email', verifyEmailHandler);
  fastify.post('/resend-verification', resendVerificationHandler);
  fastify.post('/login', loginHandler);
  fastify.get('/me', { preHandler: requireAuth }, meHandler);
}
