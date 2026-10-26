import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

import { pool } from '../db';
import { decryptSecret, encryptSecret, tokenKey } from './crypto';
import {
  accessToken, exchangeToken, oauthConfig, youtube,
} from './google';
import { ApiError } from '../errors/ApiError';
import { requireAuth } from '../middleware/requireAuth';

import type { FastifyInstance, FastifyRequest } from 'fastify';

function sessionUser(request: FastifyRequest): string {
  if (!request.session) throw ApiError.unauthorized('Sign in first.');
  return request.session.sub;
}
const hash = (value: string): string => createHash('sha256').update(value).digest('hex');
async function internalAuth(request: FastifyRequest): Promise<void> {
  const expected = process.env.WORKER_API_SECRET ?? '';
  const provided = request.headers['x-worker-secret'];
  if (
    expected.length < 32
    || typeof provided !== 'string'
    || Buffer.byteLength(provided) !== Buffer.byteLength(expected)
    || !timingSafeEqual(Buffer.from(provided), Buffer.from(expected))
  ) {
    throw ApiError.unauthorized('Invalid worker credentials');
  }
}
async function ensureNoActiveYouTube(userId: string): Promise<void> {
  const active = await pool.query(
    'SELECT 1 FROM youtube_broadcasts WHERE user_id=$1 AND ended_at IS NULL',
    [userId],
  );
  if (active.rowCount) {
    throw ApiError.validation(
      'End your broadcast before changing YouTube accounts.',
    );
  }
}
interface Channel {
  id: string;
  snippet: { title: string };
}
interface BroadcastRow {
  broadcast_id: string;
  stream_id: string;
  ingest_cipher: string;
  ended_at: Date | null;
}
const uuid = { type: 'string', format: 'uuid' };
const sessionBody = {
  type: 'object',
  additionalProperties: false,
  required: ['sessionId', 'userId'],
  properties: { sessionId: uuid, userId: uuid },
};

export async function youtubeRoutes(app: FastifyInstance): Promise<void> {
  app.get('/connection', { preHandler: requireAuth }, async (request) => {
    const result = await pool.query(
      'SELECT channel_id, channel_name FROM youtube_connections WHERE user_id=$1',
      [sessionUser(request)],
    );
    return {
      connected: result.rowCount !== 0,
      channel: result.rows[0] ?? null,
    };
  });
  app.post('/connect', { preHandler: requireAuth }, async (request) => {
    await ensureNoActiveYouTube(sessionUser(request));
    const config = oauthConfig();
    tokenKey();
    const state = randomBytes(32).toString('base64url');
    await pool.query(
      'DELETE FROM youtube_oauth_states WHERE expires_at < now() OR user_id=$1',
      [sessionUser(request)],
    );
    await pool.query(
      "INSERT INTO youtube_oauth_states VALUES ($1,$2,now()+interval '10 minutes')",
      [hash(state), sessionUser(request)],
    );
    const query = new URLSearchParams({
      client_id: config.clientId,
      redirect_uri: config.redirectUri,
      response_type: 'code',
      scope: 'https://www.googleapis.com/auth/youtube.force-ssl',
      access_type: 'offline',
      prompt: 'consent select_account',
      state,
    });
    return {
      authorizationUrl: `https://accounts.google.com/o/oauth2/v2/auth?${query}`,
    };
  });
  app.get<{ Querystring: { state?: string; code?: string; error?: string } }>(
    '/oauth/callback',
    async (request, reply) => {
      reply
        .header('Cache-Control', 'no-store')
        .header('Referrer-Policy', 'no-referrer');
      const { state, code, error } = request.query;
      if (!state || state.length > 256) {
        throw ApiError.validation(
          'Invalid OAuth state. Start again from the app.',
        );
      }
      const result = await pool.query<{ user_id: string }>(
        'DELETE FROM youtube_oauth_states WHERE state_hash=$1 '
          + 'AND expires_at > now() RETURNING user_id',
        [hash(state)],
      );
      const row = result.rows[0];
      if (!row) {
        throw ApiError.validation(
          'Expired or already-used OAuth state. Start again from the app.',
        );
      }
      if (error || !code) {
        return reply
          .type('text/plain')
          .send('YouTube connection cancelled. Return to the app.');
      }
      await ensureNoActiveYouTube(row.user_id);
      const token = await exchangeToken({
        grant_type: 'authorization_code',
        code,
        redirect_uri: oauthConfig().redirectUri,
      });
      const channels = await youtube<{ items: Channel[] }>(
        token.access_token,
        'channels',
        { part: 'snippet', mine: 'true' },
      );
      const channel = channels.items[0];
      if (!channel || !token.refresh_token) {
        throw ApiError.validation(
          'A YouTube channel and offline consent are required. Reconnect and grant access.',
        );
      }
      await pool.query(
        `INSERT INTO youtube_connections (user_id,channel_id,channel_name,refresh_token_cipher)
      VALUES ($1,$2,$3,$4) ON CONFLICT (user_id) DO UPDATE
      SET channel_id=$2,channel_name=$3,refresh_token_cipher=$4,updated_at=now()`,
        [
          row.user_id,
          channel.id,
          channel.snippet.title,
          encryptSecret(token.refresh_token),
        ],
      );
      return reply
        .type('text/plain')
        .send(
          'YouTube connected. Return to CreasePoint and tap Refresh connection.',
        );
    },
  );
  app.delete('/connection', { preHandler: requireAuth }, async (request) => {
    const active = await pool.query(
      'SELECT 1 FROM youtube_broadcasts WHERE user_id=$1 AND ended_at IS NULL',
      [sessionUser(request)],
    );
    if (active.rowCount) {
      throw ApiError.validation(
        'End your broadcast before disconnecting YouTube.',
      );
    }
    const result = await pool.query<{ refresh_token_cipher: string }>(
      'SELECT refresh_token_cipher FROM youtube_connections WHERE user_id=$1',
      [sessionUser(request)],
    );
    if (result.rows[0]) {
      const response = await fetch('https://oauth2.googleapis.com/revoke', {
        method: 'POST',
        body: new URLSearchParams({
          token: decryptSecret(result.rows[0].refresh_token_cipher),
        }),
        signal: AbortSignal.timeout(15000),
      });
      if (!response.ok && response.status !== 400) {
        throw ApiError.serviceUnavailable(
          'Google revocation failed. Please retry.',
        );
      }
    }
    await pool.query('DELETE FROM youtube_connections WHERE user_id=$1', [
      sessionUser(request),
    ]);
    await pool.query('DELETE FROM youtube_oauth_states WHERE user_id=$1', [
      sessionUser(request),
    ]);
    return { connected: false };
  });
  app.post<{
    Body: { sessionId: string; userId: string; title: string; privacy: string };
  }>(
    '/internal/start',
    {
      preHandler: internalAuth,
      schema: {
        body: {
          ...sessionBody,
          required: ['sessionId', 'userId', 'title', 'privacy'],
          properties: {
            ...sessionBody.properties,
            title: { type: 'string', minLength: 1, maxLength: 100 },
            privacy: {
              type: 'string',
              enum: ['private', 'unlisted', 'public'],
            },
          },
        },
      },
    },
    async (request) => {
      const {
        sessionId, userId, title, privacy,
      } = request.body;
      const owner = await pool.query(
        'SELECT 1 FROM stream_sessions WHERE id=$1 AND user_id=$2',
        [sessionId, userId],
      );
      if (!owner.rowCount) throw ApiError.notFound('Session not found');
      // Serialize provisioning for this session and retain secrets only server-side.
      const token = await accessToken(userId);
      const client = await pool.connect();
      let broadcastId: string | undefined;
      let streamId: string | undefined;
      try {
        await client.query('BEGIN');
        await client.query(
          'SELECT id FROM stream_sessions WHERE id=$1 FOR UPDATE',
          [sessionId],
        );
        const existing = await client.query<BroadcastRow>(
          'SELECT * FROM youtube_broadcasts WHERE session_id=$1',
          [sessionId],
        );
        if (existing.rows[0]) {
          if (existing.rows[0].ended_at) {
            throw ApiError.validation('This broadcast has already ended.');
          }
          await client.query('COMMIT');
          return {
            ingestUrl: decryptSecret(existing.rows[0].ingest_cipher),
            watchUrl: `https://www.youtube.com/watch?v=${existing.rows[0].broadcast_id}`,
          };
        }
        const broadcast = await youtube<{ id: string }>(
          token,
          'liveBroadcasts',
          { part: 'snippet,status,contentDetails' },
          'POST',
          {
            snippet: { title, scheduledStartTime: new Date().toISOString() },
            status: { privacyStatus: privacy, selfDeclaredMadeForKids: false },
            contentDetails: {
              enableAutoStart: true,
              enableAutoStop: false,
              monitorStream: { enableMonitorStream: false },
            },
          },
        );
        broadcastId = broadcast.id;
        const stream = await youtube<{
          id: string;
          cdn: {
            ingestionInfo: {
              rtmpsIngestionAddress: string;
              streamName: string;
            };
          };
        }>(
          token,
          'liveStreams',
          { part: 'snippet,cdn,contentDetails' },
          'POST',
          {
            snippet: { title },
            cdn: {
              ingestionType: 'rtmp',
              resolution: '1080p',
              frameRate: '30fps',
            },
            contentDetails: { isReusable: false },
          },
        );
        streamId = stream.id;
        await youtube(
          token,
          'liveBroadcasts/bind',
          { part: 'id', id: broadcastId, streamId },
          'POST',
        );
        const ingest = stream.cdn.ingestionInfo;
        if (
          !ingest.rtmpsIngestionAddress?.startsWith('rtmps://')
          || !ingest.streamName
        ) {
          throw ApiError.serviceUnavailable(
            'YouTube did not provide secure ingest.',
          );
        }
        const ingestUrl = `${ingest.rtmpsIngestionAddress}/${ingest.streamName}`;
        await client.query(
          'INSERT INTO youtube_broadcasts '
            + '(session_id,user_id,broadcast_id,stream_id,ingest_cipher) VALUES ($1,$2,$3,$4,$5)',
          [sessionId, userId, broadcastId, streamId, encryptSecret(ingestUrl)],
        );
        await client.query('COMMIT');
        return {
          ingestUrl,
          watchUrl: `https://www.youtube.com/watch?v=${broadcastId}`,
        };
      } catch (err) {
        await client.query('ROLLBACK');
        if (broadcastId) {
          await youtube(
            token,
            'liveBroadcasts',
            { id: broadcastId },
            'DELETE',
          ).catch(() => undefined);
        }
        if (streamId) {
          await youtube(token, 'liveStreams', { id: streamId }, 'DELETE').catch(
            () => undefined,
          );
        }
        throw err;
      } finally {
        client.release();
      }
    },
  );
  app.post<{ Body: { sessionId: string; userId: string } }>(
    '/internal/stop',
    { preHandler: internalAuth, schema: { body: sessionBody } },
    async (request) => {
      const { sessionId, userId } = request.body;
      const result = await pool.query<BroadcastRow>(
        'SELECT * FROM youtube_broadcasts WHERE session_id=$1 AND user_id=$2',
        [sessionId, userId],
      );
      const row = result.rows[0];
      if (!row || row.ended_at) return { stopped: true };
      const token = await accessToken(userId);
      const status = await youtube<{
        items: { status: { lifeCycleStatus: string } }[];
      }>(token, 'liveBroadcasts', { part: 'status', id: row.broadcast_id });
      const lifecycle = status.items[0]?.status.lifeCycleStatus;
      if (lifecycle === 'live' || lifecycle === 'testing') {
        await youtube(
          token,
          'liveBroadcasts/transition',
          { part: 'id', id: row.broadcast_id, broadcastStatus: 'complete' },
          'POST',
        );
      } else if (
        lifecycle
        && lifecycle !== 'complete'
        && lifecycle !== 'revoked'
      ) {
        await youtube(
          token,
          'liveBroadcasts',
          { id: row.broadcast_id },
          'DELETE',
        );
      }
      await pool.query(
        'UPDATE youtube_broadcasts SET ended_at=now() WHERE session_id=$1',
        [sessionId],
      );
      return { stopped: true };
    },
  );
}
