import { pool } from '../db';
import { decryptSecret } from './crypto';
import { ApiError } from '../errors/ApiError';

export function oauthConfig(): { clientId: string; clientSecret: string; redirectUri: string } {
  const clientId = process.env.GOOGLE_CLIENT_ID;
  const clientSecret = process.env.GOOGLE_CLIENT_SECRET;
  const redirectUri = process.env.GOOGLE_REDIRECT_URI;
  if (!clientId || !clientSecret || !redirectUri?.startsWith('https://')) {
    throw ApiError.serviceUnavailable(
      'YouTube connection is not configured on this server.',
    );
  }
  return { clientId, clientSecret, redirectUri };
}
interface GoogleToken {
  access_token: string;
  refresh_token?: string;
}
export async function exchangeToken(
  fields: Record<string, string>,
): Promise<GoogleToken> {
  const config = oauthConfig();
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    body: new URLSearchParams({
      client_id: config.clientId,
      client_secret: config.clientSecret,
      ...fields,
    }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) {
    throw ApiError.serviceUnavailable(
      'Google authorization expired or failed. Reconnect YouTube in Settings.',
    );
  }
  const token = (await response.json()) as GoogleToken;
  if (!token.access_token) {
    throw ApiError.serviceUnavailable('Google did not return an access token.');
  }
  return token;
}
export async function accessToken(userId: string): Promise<string> {
  const result = await pool.query<{ refresh_token_cipher: string }>(
    'SELECT refresh_token_cipher FROM youtube_connections WHERE user_id = $1',
    [userId],
  );
  if (!result.rows[0]) {
    throw ApiError.validation(
      'Connect your YouTube channel in Settings first.',
    );
  }
  const token = await exchangeToken({
    grant_type: 'refresh_token',
    refresh_token: decryptSecret(result.rows[0].refresh_token_cipher),
  });
  return token.access_token;
}
export async function youtube<T>(
  token: string,
  resource: string,
  query: Record<string, string>,
  method = 'GET',
  body?: unknown,
): Promise<T> {
  const response = await fetch(
    `https://www.googleapis.com/youtube/v3/${resource}?${new URLSearchParams(query)}`,
    {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(15000),
    },
  );
  if (!response.ok) {
    // Never surface upstream bodies, tokens, stream keys, or request URLs.
    throw ApiError.serviceUnavailable(
      `YouTube rejected the request (${response.status}). `
      + 'Check live-stream eligibility, consent, and API quota.',
    );
  }
  return (response.status === 204 ? {} : await response.json()) as T;
}
