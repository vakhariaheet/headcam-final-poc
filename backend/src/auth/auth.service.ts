import { createHash, randomInt, timingSafeEqual } from 'node:crypto';

import { pool } from '../db';
import { hashPassword, verifyPassword } from './passwords';
import {
  signSessionToken, signVerificationToken, verifyEmailVerificationToken,
} from './tokens';
import { sendVerificationCode } from './verification-email';
import { ApiError } from '../errors/ApiError';
import { toAppUser } from '../types';

import type { AppUser, UserRow } from '../types';
import type {
  AuthResult,
  LoginRequestBody,
  ResendVerificationRequestBody,
  SignupChallengeResult,
  SignupRequestBody,
  VerifyEmailRequestBody,
} from './auth.types';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MIN_PASSWORD_LENGTH = 8;
const VERIFICATION_TTL_SECONDS = 600;
const MAX_VERIFICATION_ATTEMPTS = 5;
const RESEND_COOLDOWN_SECONDS = 30;

interface VerifiableUserRow extends UserRow {
  email_verified_at: Date | null;
}

function isUniqueViolation(err: unknown): boolean {
  return typeof err === 'object' && err !== null && (err as { code?: string }).code === '23505';
}

function issueSession(user: AppUser): AuthResult {
  const token = signSessionToken({ sub: user.id, email: user.email, role: user.role });
  return { token, user };
}

function createVerificationCode(): string {
  return randomInt(100000, 1000000).toString();
}

function hashVerificationCode(code: string): string {
  return createHash('sha256').update(code).digest('hex');
}

function codesMatch(actualCode: string, expectedHash: string): boolean {
  const actual = Buffer.from(hashVerificationCode(actualCode), 'hex');
  const expected = Buffer.from(expectedHash, 'hex');
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

function challengeResult(
  userId: string,
  email: string,
  developmentCode?: string,
): SignupChallengeResult {
  return {
    verificationToken: signVerificationToken(userId, email),
    email,
    expiresInSeconds: VERIFICATION_TTL_SECONDS,
    ...(developmentCode ? { developmentCode } : {}),
  };
}

export async function signup(body: SignupRequestBody): Promise<SignupChallengeResult> {
  const {
    email, password, firstName, lastName,
  } = body;

  if (typeof email !== 'string' || !EMAIL_PATTERN.test(email.trim())) {
    throw ApiError.validation('A valid email is required');
  }
  if (typeof password !== 'string' || password.length < MIN_PASSWORD_LENGTH) {
    throw ApiError.validation(`Password must be at least ${MIN_PASSWORD_LENGTH} characters`);
  }
  if (!/[A-Za-z]/.test(password) || !/\d/.test(password)) {
    throw ApiError.validation('Password must contain at least one letter and one number');
  }
  if (typeof firstName !== 'string' || firstName.trim().length === 0) {
    throw ApiError.validation('Full name is required');
  }

  const normalizedEmail = email.trim().toLowerCase();
  const existingResult = await pool.query<VerifiableUserRow>(
    `SELECT id, email, first_name, last_name, role, password_hash, email_verified_at
     FROM users WHERE email = $1`,
    [normalizedEmail],
  );
  const existing = existingResult.rows[0];
  if (existing) {
    const samePassword = await verifyPassword(password, existing.password_hash);
    if (existing.email_verified_at || !samePassword) {
      throw ApiError.emailAlreadyExists();
    }
    // Resume a pending signup after an app restart. The existing code remains
    // valid; the verification screen can request a replacement after cooldown.
    return challengeResult(existing.id, existing.email);
  }

  const passwordHash = await hashPassword(password);
  const code = createVerificationCode();
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    const result = await client.query<UserRow>(
      `INSERT INTO users (email, first_name, last_name, role, password_hash)
       VALUES ($1, $2, $3, 'UMPIRE', $4)
       RETURNING id, email, first_name, last_name, role, password_hash`,
      [
        normalizedEmail,
        firstName.trim(),
        // eslint-disable-next-line @typescript-eslint/prefer-nullish-coalescing
        lastName?.trim() || null,
        passwordHash,
      ],
    );
    const row = result.rows[0];
    await client.query(
      `INSERT INTO email_verification_codes
         (user_id, code_hash, expires_at, attempts, last_sent_at)
       VALUES ($1, $2, now() + make_interval(secs => $3), 0, now())`,
      [row.id, hashVerificationCode(code), VERIFICATION_TTL_SECONDS],
    );
    const delivery = await sendVerificationCode(row.email, code);
    await client.query('COMMIT');
    return challengeResult(row.id, row.email, delivery.developmentCode);
  } catch (err: unknown) {
    await client.query('ROLLBACK');
    if (isUniqueViolation(err)) {
      throw ApiError.emailAlreadyExists();
    }
    throw err;
  } finally {
    client.release();
  }
}

export async function verifyEmail(body: VerifyEmailRequestBody): Promise<AuthResult> {
  if (typeof body?.verificationToken !== 'string' || typeof body?.code !== 'string') {
    throw ApiError.validation('Verification token and six-digit code are required');
  }
  if (!/^\d{6}$/.test(body.code)) {
    throw ApiError.invalidVerificationCode();
  }

  let challenge: ReturnType<typeof verifyEmailVerificationToken>;
  try {
    challenge = verifyEmailVerificationToken(body.verificationToken);
  } catch {
    throw ApiError.verificationExpired();
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const codeResult = await client.query<{
      code_hash: string;
      expires_at: Date;
      attempts: number;
    }>(
      `SELECT code_hash, expires_at, attempts
       FROM email_verification_codes WHERE user_id = $1 FOR UPDATE`,
      [challenge.sub],
    );
    const stored = codeResult.rows[0];
    if (!stored || stored.expires_at.getTime() <= Date.now()) {
      throw ApiError.verificationExpired();
    }
    if (stored.attempts >= MAX_VERIFICATION_ATTEMPTS) {
      throw ApiError.rateLimited('Too many attempts. Request a new code');
    }
    if (!codesMatch(body.code, stored.code_hash)) {
      await client.query(
        'UPDATE email_verification_codes SET attempts = attempts + 1 WHERE user_id = $1',
        [challenge.sub],
      );
      await client.query('COMMIT');
      throw ApiError.invalidVerificationCode();
    }

    const userResult = await client.query<UserRow>(
      `UPDATE users SET email_verified_at = now()
       WHERE id = $1
       RETURNING id, email, first_name, last_name, role, password_hash`,
      [challenge.sub],
    );
    const row = userResult.rows[0];
    if (!row) throw ApiError.notFound('Account no longer exists');
    await client.query('DELETE FROM email_verification_codes WHERE user_id = $1', [row.id]);
    await client.query('COMMIT');
    return issueSession(toAppUser(row));
  } catch (err: unknown) {
    // Invalid codes commit their attempt increment above. Every other failure
    // reaches this catch with an open transaction and is safe to roll back.
    if (!(err instanceof ApiError && err.code === 'INVALID_VERIFICATION_CODE')) {
      await client.query('ROLLBACK');
    }
    throw err;
  } finally {
    client.release();
  }
}

export async function resendVerification(
  body: ResendVerificationRequestBody,
): Promise<SignupChallengeResult> {
  if (typeof body?.verificationToken !== 'string') {
    throw ApiError.validation('Verification token is required');
  }

  let challenge: ReturnType<typeof verifyEmailVerificationToken>;
  try {
    challenge = verifyEmailVerificationToken(body.verificationToken);
  } catch {
    throw ApiError.verificationExpired();
  }

  const result = await pool.query<{
    email: string;
    email_verified_at: Date | null;
    seconds_since_sent: number | null;
  }>(
    `SELECT u.email, u.email_verified_at,
            EXTRACT(EPOCH FROM (now() - c.last_sent_at))::integer AS seconds_since_sent
     FROM users u
     LEFT JOIN email_verification_codes c ON c.user_id = u.id
     WHERE u.id = $1`,
    [challenge.sub],
  );
  const row = result.rows[0];
  if (!row) throw ApiError.notFound('Account no longer exists');
  if (row.email_verified_at) throw ApiError.validation('Email is already verified');
  if (row.seconds_since_sent !== null && row.seconds_since_sent < RESEND_COOLDOWN_SECONDS) {
    throw ApiError.rateLimited('Wait before requesting another code');
  }

  const code = createVerificationCode();
  const delivery = await sendVerificationCode(row.email, code);
  await pool.query(
    `INSERT INTO email_verification_codes
       (user_id, code_hash, expires_at, attempts, last_sent_at)
     VALUES ($1, $2, now() + make_interval(secs => $3), 0, now())
     ON CONFLICT (user_id) DO UPDATE SET
       code_hash = EXCLUDED.code_hash,
       expires_at = EXCLUDED.expires_at,
       attempts = 0,
       last_sent_at = now()`,
    [challenge.sub, hashVerificationCode(code), VERIFICATION_TTL_SECONDS],
  );
  return challengeResult(challenge.sub, row.email, delivery.developmentCode);
}

export async function login(body: LoginRequestBody): Promise<AuthResult> {
  const { email, password } = body;

  if (typeof email !== 'string' || typeof password !== 'string') {
    throw ApiError.validation('Email and password are required');
  }

  const normalizedEmail = email.trim().toLowerCase();
  const result = await pool.query<VerifiableUserRow>(
    `SELECT id, email, first_name, last_name, role, password_hash, email_verified_at
     FROM users WHERE email = $1`,
    [normalizedEmail],
  );

  const row = result.rows[0];
  if (!row || !(await verifyPassword(password, row.password_hash))) {
    throw ApiError.invalidCredentials();
  }
  if (!row.email_verified_at) {
    throw ApiError.emailNotVerified();
  }

  return issueSession(toAppUser(row));
}

export async function getUserById(userId: string): Promise<AppUser> {
  const result = await pool.query<UserRow>(
    `SELECT id, email, first_name, last_name, role, password_hash
     FROM users WHERE id = $1`,
    [userId],
  );

  const row = result.rows[0];
  if (!row) {
    throw ApiError.notFound('User no longer exists');
  }

  return toAppUser(row);
}
