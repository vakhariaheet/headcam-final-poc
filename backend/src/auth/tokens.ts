import jwt from 'jsonwebtoken';

import { JWT_SECRET } from '../config';

const JWT_EXPIRES_IN = '30d';

export interface SessionTokenPayload {
  sub: string;
  email: string;
  role: string;
  purpose?: 'session';
}

export function signSessionToken(payload: SessionTokenPayload): string {
  return jwt.sign({ ...payload, purpose: 'session' }, JWT_SECRET, { expiresIn: JWT_EXPIRES_IN });
}

interface VerificationTokenPayload {
  sub: string;
  email: string;
  purpose: 'verify_email';
}

export function signVerificationToken(userId: string, email: string): string {
  return jwt.sign({ sub: userId, email, purpose: 'verify_email' }, JWT_SECRET, {
    expiresIn: '15m',
  });
}

export function verifyEmailVerificationToken(token: string): VerificationTokenPayload {
  const payload = jwt.verify(token, JWT_SECRET) as VerificationTokenPayload;
  if (payload.purpose !== 'verify_email') {
    throw new Error('Incorrect token purpose');
  }
  return payload;
}

export function verifySessionToken(token: string): SessionTokenPayload {
  return jwt.verify(token, JWT_SECRET) as SessionTokenPayload;
}
