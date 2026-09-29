import nodemailer from 'nodemailer';

import {
  NODE_ENV, SMTP_FROM, SMTP_HOST, SMTP_PASSWORD, SMTP_PORT, SMTP_USER,
} from '../config';
import { ApiError } from '../errors/ApiError';
import { logger } from '../logger';

export interface DeliveryResult {
  developmentCode?: string;
}

export async function sendVerificationCode(
  email: string,
  code: string,
): Promise<DeliveryResult> {
  if (!SMTP_HOST) {
    if (NODE_ENV === 'production') {
      throw ApiError.serviceUnavailable('Email verification is temporarily unavailable');
    }
    logger.warn(
      { email, verificationCode: code },
      'SMTP is not configured; using development verification code',
    );
    return { developmentCode: code };
  }

  const transport = nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_PORT === 465,
    auth: SMTP_USER && SMTP_PASSWORD ? { user: SMTP_USER, pass: SMTP_PASSWORD } : undefined,
  });
  await transport.sendMail({
    from: SMTP_FROM,
    to: email,
    subject: 'Verify your CreasePoint account',
    text: `Your CreasePoint verification code is ${code}. It expires in 10 minutes.`,
    html: [
      '<p>Your CreasePoint verification code is:</p>',
      `<p style="font-size:28px;font-weight:700;letter-spacing:6px">${code}</p>`,
      '<p>It expires in 10 minutes.</p>',
    ].join(''),
  });
  return {};
}
