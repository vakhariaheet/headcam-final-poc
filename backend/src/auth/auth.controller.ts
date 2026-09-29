import {
  getUserById, login, resendVerification, signup, verifyEmail,
} from './auth.service';
import { ApiError } from '../errors/ApiError';

import type { FastifyReply, FastifyRequest } from 'fastify';

import type {
  LoginRequestBody,
  ResendVerificationRequestBody,
  SignupRequestBody,
  VerifyEmailRequestBody,
} from './auth.types';

export async function signupHandler(
  request: FastifyRequest<{ Body: SignupRequestBody }>,
  reply: FastifyReply,
): Promise<void> {
  const result = await signup(request.body);
  reply.status(201).send(result);
}

export async function verifyEmailHandler(
  request: FastifyRequest<{ Body: VerifyEmailRequestBody }>,
  reply: FastifyReply,
): Promise<void> {
  const result = await verifyEmail(request.body);
  reply.status(200).send(result);
}

export async function resendVerificationHandler(
  request: FastifyRequest<{ Body: ResendVerificationRequestBody }>,
  reply: FastifyReply,
): Promise<void> {
  const result = await resendVerification(request.body);
  reply.status(200).send(result);
}

export async function loginHandler(
  request: FastifyRequest<{ Body: LoginRequestBody }>,
  reply: FastifyReply,
): Promise<void> {
  const result = await login(request.body);
  reply.status(200).send(result);
}

export async function meHandler(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  if (!request.session) {
    throw ApiError.unauthorized('Missing bearer token');
  }
  const user = await getUserById(request.session.sub);
  reply.status(200).send({ user });
}
