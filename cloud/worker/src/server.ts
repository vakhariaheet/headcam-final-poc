import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';

import Fastify from 'fastify';

import { requireAuth } from './auth';
import { pool } from './db';
import { logger } from './logger';
import {
  defaultScoreboard,
  scoreboardSchema,
  videoFilter,
  writeScore,
} from './scoreboard';
import { youtubeControl } from './youtube';

import type { ChildProcess } from 'node:child_process';

import type {
  FastifyBaseLogger,
  FastifyInstance,
  FastifyReply,
  FastifyRequest,
} from 'fastify';

import type { Scoreboard } from './scoreboard';

const PORT = Number(process.env.CONTROL_PORT) || 4100;
const HOST = process.env.WORKER_HOST ?? `localhost:${PORT}`;
const RTSP = process.env.RTSP_URL ?? 'rtsp://mediamtx:8554/live/hat';
interface CreateBody {
  target?: 'recording' | 'youtube';
  title?: string;
  privacy?: 'private' | 'unlisted' | 'public';
  scoreboard?: Scoreboard;
}
interface Pipeline {
  owner: string;
  stopped: boolean;
  child: ChildProcess | null;
  task: Promise<void>;
  folder: string;
  scoreFile: string;
  output: string;
  youtube: boolean;
  watchUrl?: string;
  lastError?: string;
  stopTask?: Promise<void>;
}
const sessions = new Map<string, Pipeline>();
interface SessionRow {
  id: string;
  user_id: string;
  worker_host: string;
  status: string;
  scoreboard: Scoreboard;
}
function requestUser(request: FastifyRequest): string {
  if (!request.userId) throw new Error('Missing session identity');
  return request.userId;
}
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
async function status(id: string, value: string): Promise<void> {
  await pool.query(
    'UPDATE stream_sessions SET status=$2::stream_status_enum WHERE id=$1',
    [id, value],
  );
}
function ffmpegArgs(p: Pipeline): string[] {
  return [
    '-hide_banner',
    '-loglevel',
    'warning',
    '-nostats',
    '-progress',
    'pipe:1',
    '-rtsp_transport',
    'tcp',
    '-timeout',
    '10000000',
    '-i',
    RTSP,
    '-f',
    'lavfi',
    '-i',
    'anullsrc=channel_layout=stereo:sample_rate=48000',
    '-map',
    '0:v:0',
    '-map',
    '1:a:0',
    '-vf',
    videoFilter(p.scoreFile),
    '-c:v',
    'libx264',
    '-preset',
    'veryfast',
    '-threads',
    '2',
    '-pix_fmt',
    'yuv420p',
    '-r',
    '30',
    '-g',
    '60',
    '-keyint_min',
    '60',
    '-sc_threshold',
    '0',
    '-b:v',
    '6000k',
    '-maxrate',
    '6000k',
    '-bufsize',
    '12000k',
    '-c:a',
    'aac',
    '-b:a',
    '128k',
    '-ar',
    '48000',
    '-shortest',
    '-f',
    p.youtube ? 'flv' : 'mpegts',
    '-y',
    p.output,
  ];
}
async function runPipeline(id: string, pipeline: Pipeline): Promise<void> {
  const p = pipeline;
  let failures = 0;
  let attempt = 0;
  const recordingOutput = p.output;
  while (!p.stopped && failures < 10) {
    if (!p.youtube) p.output = recordingOutput.replace(/\.ts$/, `-${attempt}.ts`);
    attempt += 1;
    let progress = '';
    let gotFrame = false;
    const began = Date.now();
    const child = spawn('ffmpeg', ffmpegArgs(p), {
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    p.child = child;
    // Do not pipe FFmpeg stderr directly: it can contain a YouTube stream key.
    // Drain diagnostics without logging arbitrary chunks: a stream key can be
    // split across chunks and evade URL redaction.
    child.stderr.on('data', () => {
      p.lastError = 'Encoder reported a diagnostic; check source connectivity.';
    });
    let lastProgress = Date.now();
    child.stdout.on('data', (chunk: Buffer) => {
      progress = (progress + chunk.toString()).slice(-8192);
      if (/frame=\s*[1-9]\d*/.test(progress)) {
        lastProgress = Date.now();
        if (!gotFrame && !p.stopped) {
          gotFrame = true;
          status(id, 'LIVE').catch(() => {
            p.stopped = true;
            child.kill('SIGTERM');
          });
        }
      }
      if (progress.includes('progress=')) progress = '';
    });
    const watchdog = setInterval(() => {
      if (Date.now() - lastProgress > 30000) child.kill('SIGKILL');
    }, 5000);
    await new Promise<void>((resolve) => {
      child.once('error', () => {
        p.lastError = 'Encoder could not start.';
        resolve();
      });
      child.once('close', () => resolve());
    });
    clearInterval(watchdog);
    p.child = null;
    if (p.stopped) break;
    failures = gotFrame && Date.now() - began > 60000 ? 1 : failures + 1;
    await status(id, 'RECONNECTING');
    // Short interruptible retry wait, without unbounded producer queues.
    for (let i = 0; i < 30 && !p.stopped; i += 1) await delay(100);
  }
  if (!p.stopped) {
    await status(id, 'FAILED');
    if (p.youtube) await youtubeControl('stop', { sessionId: id, userId: p.owner });
  }
}
async function stopPipeline(id: string, pipeline: Pipeline): Promise<void> {
  const p = pipeline;
  p.stopped = true;
  const { child } = p;
  child?.kill('SIGTERM');
  const kill = setTimeout(() => child?.kill('SIGKILL'), 5000);
  try {
    await p.task;
    if (p.youtube) await youtubeControl('stop', { sessionId: id, userId: p.owner });
    await pool.query(
      "UPDATE stream_sessions SET status='TERMINATED',ended_at=now() WHERE id=$1",
      [id],
    );
    fs.rmSync(p.folder, { recursive: true, force: true });
    sessions.delete(id);
  } finally {
    clearTimeout(kill);
  }
}
async function owned(id: string, userId: string, reply: FastifyReply) {
  if (!uuid.test(id)) {
    reply.code(404).send({ error: { message: 'Session not found' } });
    return null;
  }
  const result = await pool.query<SessionRow>(
    'SELECT * FROM stream_sessions WHERE id=$1',
    [id],
  );
  const row = result.rows[0];
  if (row?.user_id !== userId) {
    reply.code(404).send({ error: { message: 'Session not found' } });
    return null;
  }
  if (row.worker_host !== HOST) {
    reply
      .code(409)
      .send({ error: { message: 'Session belongs to a different worker' } });
    return null;
  }
  return row;
}
export function buildApp(): FastifyInstance {
  const app = Fastify({
    // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
    loggerInstance: logger as FastifyBaseLogger,
    ajv: { customOptions: { removeAdditional: false, coerceTypes: false } },
  });
  app.setErrorHandler((error, request, reply) => {
    // Database/upstream details stay out of client messages and credential logs.
    if (error && typeof error === 'object' && 'validation' in error) {
      reply.code(400).send({
        error: {
          code: 'VALIDATION_ERROR',
          message: 'Invalid broadcast or scoreboard fields.',
        },
      });
      return;
    }
    request.log.error(
      { errorType: error instanceof Error ? error.name : 'Unknown' },
      'Worker request failed',
    );
    reply.code(503).send({
      error: {
        code: 'SERVICE_UNAVAILABLE',
        message:
          'Broadcast service failed. Check the worker configuration and YouTube connection.',
      },
    });
  });
  app.post<{ Body: CreateBody }>(
    '/sessions',
    {
      preHandler: requireAuth,
      schema: {
        body: {
          type: 'object',
          additionalProperties: false,
          properties: {
            target: { type: 'string', enum: ['recording', 'youtube'] },
            title: { type: 'string', minLength: 1, maxLength: 100 },
            privacy: {
              type: 'string',
              enum: ['private', 'unlisted', 'public'],
            },
            scoreboard: scoreboardSchema,
          },
        },
      },
    },
    async (request, reply) => {
      const body = request.body ?? {};
      const userId = requestUser(request);
      // One shared hat path in this POC: never let another account silently
      // broadcast the same camera concurrently. Device-bound routing comes later.
      const db = await pool.connect();
      let id: string;
      try {
        await db.query('BEGIN');
        await db.query('SELECT pg_advisory_xact_lock(8219,1)');
        const user = await db.query('SELECT 1 FROM users WHERE id=$1', [
          userId,
        ]);
        if (!user.rowCount) {
          await db.query('ROLLBACK');
          return await reply.code(401).send({
            error: {
              message:
                'Sign in through the deployed backend; this user does not exist here.',
            },
          });
        }
        const active = await db.query(
          "SELECT 1 FROM stream_sessions WHERE status IN ('INITIALIZING','LIVE','RECONNECTING')",
        );
        if (active.rowCount) {
          await db.query('ROLLBACK');
          return await reply.code(409).send({
            error: {
              message:
                'The hat already has an active broadcast. Stop it first.',
            },
          });
        }
        const result = await db.query<{ id: string }>(
          `INSERT INTO stream_sessions
        (session_token,user_id,status,hat_ingress_rtsp_url,worker_host,scoreboard)
        VALUES (gen_random_uuid()::text,$1,'INITIALIZING',$2,$3,$4) RETURNING id`,
          [userId, RTSP, HOST, body.scoreboard ?? defaultScoreboard],
        );
        id = result.rows[0].id;
        await db.query('COMMIT');
      } catch (err) {
        await db.query('ROLLBACK');
        throw err;
      } finally {
        db.release();
      }
      const folder = fs.mkdtempSync(path.join(os.tmpdir(), 'hat-score-'));
      const p: Pipeline = {
        owner: userId,
        stopped: false,
        child: null,
        task: Promise.resolve(),
        folder,
        scoreFile: path.join(folder, 'score.txt'),
        output: '',
        youtube: body.target === 'youtube',
      };
      try {
        writeScore(p.scoreFile, body.scoreboard ?? defaultScoreboard);
        if (p.youtube) {
          const target = await youtubeControl<{
            ingestUrl: string;
            watchUrl: string;
          }>('start', {
            sessionId: id,
            userId,
            title: body.title ?? 'CreasePoint Live',
            privacy: body.privacy ?? 'private',
          });
          p.output = target.ingestUrl;
          p.watchUrl = target.watchUrl;
        } else {
          fs.mkdirSync('/output', { recursive: true });
          p.output = `/output/${id}.ts`;
        }
        sessions.set(id, p);
        p.task = runPipeline(id, p)
          .catch(async () => {
            p.child?.kill('SIGKILL');
            await status(id, 'FAILED');
            if (p.youtube) await youtubeControl('stop', { sessionId: id, userId });
          })
          .catch(() => {
            logger.error({ sessionId: id }, 'Session cleanup needs retry');
          });
        return await reply.code(201).send({
          sessionId: id,
          status: 'INITIALIZING',
          watchUrl: p.watchUrl,
        });
      } catch (err) {
        await status(id, 'FAILED');
        fs.rmSync(folder, { recursive: true, force: true });
        if (p.youtube) {
          await youtubeControl('stop', { sessionId: id, userId }).catch(
            () => undefined,
          );
        }
        return reply.code(503).send({
          error: {
            message:
              err instanceof Error ? err.message : 'YouTube setup failed.',
          },
        });
      }
    },
  );
  app.patch<{ Params: { id: string }; Body: Scoreboard }>(
    '/sessions/:id/scoreboard',
    { preHandler: requireAuth, schema: { body: scoreboardSchema } },
    async (request, reply) => {
      if (!(await owned(request.params.id, requestUser(request), reply))) return reply;
      const p = sessions.get(request.params.id);
      if (!p || p.stopped) {
        return reply
          .code(409)
          .send({ error: { message: 'Broadcast is not running.' } });
      }
      writeScore(p.scoreFile, request.body);
      await pool.query('UPDATE stream_sessions SET scoreboard=$2 WHERE id=$1', [
        request.params.id,
        request.body,
      ]);
      return { scoreboard: request.body };
    },
  );
  app.post<{ Params: { id: string } }>(
    '/sessions/:id/stop',
    { preHandler: requireAuth },
    async (request, reply) => {
      const row = await owned(request.params.id, requestUser(request), reply);
      if (!row) return reply;
      const p = sessions.get(row.id);
      if (p) {
        p.stopTask ??= stopPipeline(row.id, p).catch((err: unknown) => {
          p.stopTask = undefined;
          throw err;
        });
        await p.stopTask;
      } else {
        const destination = await pool.query(
          'SELECT 1 FROM youtube_broadcasts WHERE session_id=$1 AND ended_at IS NULL',
          [row.id],
        );
        if (destination.rowCount) {
          await youtubeControl('stop', {
            sessionId: row.id,
            userId: request.userId,
          });
        }
        await pool.query(
          "UPDATE stream_sessions SET status='TERMINATED',ended_at=now() WHERE id=$1",
          [row.id],
        );
      }
      return { sessionId: row.id, status: 'TERMINATED' };
    },
  );
  app.get<{ Params: { id: string } }>(
    '/sessions/:id/status',
    { preHandler: requireAuth },
    async (request, reply) => {
      const row = await owned(request.params.id, requestUser(request), reply);
      if (!row) return reply;
      return {
        sessionId: row.id,
        status: row.status,
        scoreboard: row.scoreboard,
        watchUrl: sessions.get(row.id)?.watchUrl,
      };
    },
  );
  app.get('/sessions', { preHandler: requireAuth }, async (request) => {
    const result = await pool.query(
      'SELECT id,status FROM stream_sessions WHERE user_id=$1 '
        + "AND status IN ('INITIALIZING','LIVE','RECONNECTING')",
      [request.userId],
    );
    return {
      sessions: result.rows.map((row) => ({
        sessionId: row.id,
        status: row.status,
      })),
    };
  });
  return app;
}
async function main(): Promise<void> {
  // Finish abandoned YouTube broadcasts before accepting a new publisher session.
  const abandoned = await pool.query<{ session_id: string; user_id: string }>(
    'SELECT y.session_id,y.user_id FROM youtube_broadcasts y JOIN stream_sessions s '
      + 'ON s.id=y.session_id WHERE s.worker_host=$1 AND y.ended_at IS NULL',
    [HOST],
  );
  await Promise.all(
    abandoned.rows.map(async (row) => youtubeControl('stop', {
      sessionId: row.session_id,
      userId: row.user_id,
    })),
  );
  // No browser/FIFO producer: drawtext reloads the app's scoreboard atomically.
  await pool.query(
    "UPDATE stream_sessions SET status='FAILED' WHERE worker_host=$1 "
      + "AND status IN ('INITIALIZING','LIVE','RECONNECTING')",
    [HOST],
  );
  const app = buildApp();
  await app.listen({ port: PORT, host: '0.0.0.0' });
  (['SIGTERM', 'SIGINT'] as const).forEach((signal) => {
    process.once(signal, () => {
      Promise.allSettled(
        [...sessions].map(async ([id, p]) => stopPipeline(id, p)),
      )
        .then(async () => {
          await app.close();
          await pool.end();
          process.exitCode = 0;
        })
        .catch(() => {
          process.exitCode = 1;
        });
    });
  });
}
if (require.main === module) {
  main().catch(() => {
    logger.fatal(
      'Worker startup failed. Check database migrations/configuration.',
    );
    process.exitCode = 1;
  });
}
