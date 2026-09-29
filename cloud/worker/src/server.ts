import { execSync, spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import Fastify from 'fastify';
import { PNG } from 'pngjs';
import puppeteer from 'puppeteer';

import { requireAuth } from './auth';
import { pool } from './db';
import { logger } from './logger';

import type { ChildProcess } from 'node:child_process';

import type { FastifyReply } from 'fastify';
import type { Logger } from 'pino';
import type { Browser, Page } from 'puppeteer';

const WIDTH = 1920;
const HEIGHT = 1080;
const FPS = 30;

const DEFAULT_RTSP_URL = process.env.RTSP_URL ?? 'rtsp://mediamtx:8554/live/hat';
const DEFAULT_OVERLAY_URL = `file://${path.join(process.cwd(), 'overlay.html')}`;
const CONTROL_PORT = Number(process.env.CONTROL_PORT) || 4100;
const MAX_SESSIONS_PER_INSTANCE = Number(process.env.MAX_SESSIONS_PER_INSTANCE) || 4;
// This instance's own reachable address — recorded on every session it
// creates, so a request can tell whether it landed on the instance that's
// actually running that session (see findOwnedSession below).
const WORKER_HOST = process.env.WORKER_HOST ?? `localhost:${CONTROL_PORT}`;

// The base puppeteer image's cached Chrome build doesn't always match the
// revision the npm-installed puppeteer version looks for by default, so
// fall back to the path resolved at image build time (see Dockerfile).
function resolveExecutablePath(): string | undefined {
  if (process.env.PUPPETEER_EXECUTABLE_PATH) {
    return process.env.PUPPETEER_EXECUTABLE_PATH;
  }
  try {
    const resolved = fs.readFileSync('/app/chrome-path.txt', 'utf8').trim();
    if (resolved) return resolved;
  } catch {
    // fall through to puppeteer's own default resolution
  }
  return undefined;
}

function ensureFifo(fifoPath: string): void {
  if (fs.existsSync(fifoPath)) {
    fs.unlinkSync(fifoPath);
  }
  execSync(`mkfifo ${fifoPath}`);
}

// Mirrors the filter_complex overlay + tee simulcast command from spec §5.3.
// outputs is a list, not two fixed names, so a session can represent any
// number of destinations (see cloud/README.md and the worker design notes
// on why this matters for the per-platform toggle on Screen 4).
function spawnFfmpeg(
  rtspUrl: string,
  fifoPath: string,
  outputs: string[],
  log: Logger,
): ChildProcess {
  const args = [
    '-rtsp_transport', 'tcp',
    '-i', rtspUrl,
    '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s', `${WIDTH}x${HEIGHT}`, '-r', String(FPS),
    '-i', fifoPath,
    '-filter_complex', `[0:v]scale=${WIDTH}:${HEIGHT}[bg];[bg][1:v]overlay=0:0:format=auto[outv]`,
    '-map', '[outv]', '-map', '0:a?',
    '-c:v', 'libx264', '-preset', 'veryfast',
    '-b:v', '2500k', '-maxrate', '2800k', '-bufsize', '5600k', '-g', '60',
    '-c:a', 'aac', '-b:a', '128k',
    '-f', 'tee', outputs.join('|'),
  ];

  log.info({ rtspUrl, outputs }, 'spawning ffmpeg');
  return spawn('ffmpeg', args, { stdio: ['ignore', 'inherit', 'inherit'] });
}

// Captures the rendered overlay DOM at ~30fps via page.screenshot() and
// writes raw RGBA frames into the FIFO. This is a pragmatic stand-in for
// CDP's native screencast API (spec §5.2) — simpler and deterministic for a
// POC, though throughput depends on host performance rather than being
// hardware-paced; a production implementation should move to the CDP
// screencast session for better sustained framerate.
async function startCaptureLoop(
  page: Page,
  writeStream: fs.WriteStream,
  isAlive: () => boolean,
  log: Logger,
): Promise<void> {
  const intervalMs = 1000 / FPS;

  while (isAlive()) {
    const start = Date.now();
    try {
      const png = await page.screenshot({ type: 'png', omitBackground: true });
      const decoded = PNG.sync.read(Buffer.from(png));
      if (!writeStream.destroyed) {
        writeStream.write(decoded.data);
      }
    } catch (err) {
      if (!isAlive()) break;
      log.warn({ err }, 'capture frame error');
    }
    const elapsed = Date.now() - start;
    const wait = Math.max(0, intervalMs - elapsed);
    await new Promise<void>((resolve) => {
      setTimeout(resolve, wait);
    });
  }
}

// What a POST /sessions request body may supply. Just overlayUrl — see
// cloud/README.md and the plan this was built from for why rtspUrl and
// output destinations aren't request fields: nothing yet has a real
// per-hat source or real destination to supply, so exposing them as input
// would imply a contract nothing fulfills.
interface CreateSessionRequest {
  overlayUrl?: string;
}

// What actually drives a running session, after defaults are applied.
// Only overlayUrl can differ per session; rtspUrl is always the worker's
// env default. outputs is a list, not two named fields, so a session can
// represent any number of destinations.
interface SessionConfig {
  rtspUrl: string;
  overlayUrl: string;
  outputs: string[];
}

interface SessionPipeline {
  ownerId: string; // request.userId at creation time — never client-supplied
  page: Page;
  stopRequested: boolean;
  currentFfmpeg: ChildProcess | null;
  loopPromise: Promise<void>;
}

interface StreamSessionRow {
  id: string;
  user_id: string;
  worker_host: string | null;
  status: string;
}

// In-process only: the live Page/ChildProcess handles that actually control
// a running session. stream_sessions in Postgres is the durable, shared
// record of a session's existence/ownership/instance — any number of
// worker instances can read that; only the instance holding the matching
// entry here can actually control the session.
const sessions = new Map<string, SessionPipeline>();

// Resolves a request into a full SessionConfig. overlayUrl falls back to
// the local demo overlay.html file (today's only option) — this is
// deliberately the one field cloud/README.md documents as the real future
// swap point (page.goto() → the real CricHeroes overlay_web_url).
function resolveSessionConfig(body: CreateSessionRequest): SessionConfig {
  return {
    rtspUrl: DEFAULT_RTSP_URL,
    overlayUrl: body.overlayUrl ?? DEFAULT_OVERLAY_URL,
    outputs: [],
  };
}

function outputsForSession(sessionId: string): string[] {
  return [
    `[f=mpegts]/output/${sessionId}_a.ts`,
    `[f=mpegts]/output/${sessionId}_b.ts`,
  ];
}

// Each iteration re-creates the FIFO and re-spawns FFmpeg, so the pipeline
// recovers on its own once the simulator (or, later, the real hat) starts
// publishing — this is a coarse stand-in for the reconnect holding-loop
// behavior described in spec §8.1, which is tracked as follow-up work.
async function runSessionLoop(sessionId: string, config: SessionConfig): Promise<void> {
  const pipeline = sessions.get(sessionId);
  if (!pipeline) return;

  const log = logger.child({ sessionId });
  const fifoPath = `/tmp/overlay_pipe_${sessionId}`;

  while (!pipeline.stopRequested) {
    ensureFifo(fifoPath);

    let alive = true;
    const isAlive = (): boolean => alive && !pipeline.stopRequested;

    const ffmpeg = spawnFfmpeg(config.rtspUrl, fifoPath, config.outputs, log);
    pipeline.currentFfmpeg = ffmpeg;
    const writeStream = fs.createWriteStream(fifoPath);
    writeStream.on('error', (err) => {
      log.error({ err }, 'fifo write error');
    });

    const capturePromise = startCaptureLoop(pipeline.page, writeStream, isAlive, log);

    const exitCode = await new Promise<number | NodeJS.Signals | null>((resolve) => {
      ffmpeg.on('exit', (code, signal) => {
        resolve(code ?? signal);
      });
    });

    pipeline.currentFfmpeg = null;
    alive = false;
    await capturePromise;
    writeStream.destroy();

    log.info({ exitCode }, 'ffmpeg exited');
    if (pipeline.stopRequested) break;

    await new Promise<void>((resolve) => {
      setTimeout(resolve, 3000);
    });
  }
}

async function startSession(
  sessionId: string,
  ownerId: string,
  config: SessionConfig,
  browser: Browser,
): Promise<void> {
  const page = await browser.newPage();
  await page.setViewport({ width: WIDTH, height: HEIGHT, deviceScaleFactor: 1 });
  await page.goto(config.overlayUrl);

  const pipeline: SessionPipeline = {
    ownerId,
    page,
    stopRequested: false,
    currentFfmpeg: null,
    loopPromise: Promise.resolve(),
  };
  sessions.set(sessionId, pipeline);

  pipeline.loopPromise = runSessionLoop(sessionId, config).catch(async (err: unknown) => {
    logger.child({ sessionId }).error({ err }, 'session fatal error');
    await pool.query(
      "UPDATE stream_sessions SET status = 'FAILED', ended_at = now() WHERE id = $1",
      [sessionId],
    );
  });
}

// A stopped session is gone, not paused — matches Kill Switch semantics.
async function stopSession(sessionId: string): Promise<void> {
  const pipeline = sessions.get(sessionId);
  if (!pipeline) return;

  pipeline.stopRequested = true;
  pipeline.currentFfmpeg?.kill('SIGTERM');
  await pipeline.loopPromise;
  await pipeline.page.close();
  sessions.delete(sessionId);

  await pool.query(
    "UPDATE stream_sessions SET status = 'TERMINATED', ended_at = now() WHERE id = $1",
    [sessionId],
  );
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Looks up a session's durable Postgres row and checks both ownership and
// instance placement, replying with the right error and returning null if
// either check fails — every route touching an existing session shares
// this rather than repeating the same three checks.
async function findOwnedSession(
  sessionId: string,
  userId: string,
  reply: FastifyReply,
): Promise<StreamSessionRow | null> {
  // A malformed :id (not shaped like a UUID at all) is just as much "no
  // such session" as a well-formed one that doesn't match a row — but
  // without this check it reaches Postgres as raw input and comes back as
  // an unhandled invalid-UUID-syntax error instead of a clean 404.
  if (!UUID_PATTERN.test(sessionId)) {
    reply.status(404).send({ error: { code: 'NOT_FOUND', message: 'Session not found' } });
    return null;
  }

  const result = await pool.query<StreamSessionRow>(
    'SELECT id, user_id, worker_host, status FROM stream_sessions WHERE id = $1',
    [sessionId],
  );
  const row = result.rows[0];
  if (!row) {
    reply.status(404).send({ error: { code: 'NOT_FOUND', message: 'Session not found' } });
    return null;
  }
  if (row.user_id !== userId) {
    reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Not your session' } });
    return null;
  }
  if (row.worker_host !== WORKER_HOST) {
    reply.status(409).send({
      error: {
        code: 'WRONG_INSTANCE',
        message: 'This session is running on a different worker instance',
        workerHost: row.worker_host,
      },
    });
    return null;
  }
  return row;
}

function buildApp(browser: Browser) {
  const app = Fastify({ loggerInstance: logger });

  app.post<{ Body: CreateSessionRequest | undefined }>(
    '/sessions',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { userId } = request;
      if (!userId) {
        reply
          .status(401)
          .send({ error: { code: 'UNAUTHORIZED', message: 'Missing bearer token' } });
        return;
      }

      if (sessions.size >= MAX_SESSIONS_PER_INSTANCE) {
        reply.status(503).send({
          error: { code: 'AT_CAPACITY', message: 'This worker instance is at capacity' },
        });
        return;
      }

      const config = resolveSessionConfig(request.body ?? {});

      const result = await pool.query<{ id: string }>(
        `INSERT INTO stream_sessions
           (session_token, user_id, status, hat_ingress_rtsp_url, worker_host, live_started_at)
         VALUES (gen_random_uuid()::text, $1, 'LIVE', $2, $3, now())
         RETURNING id`,
        [userId, config.rtspUrl, WORKER_HOST],
      );
      const { id: sessionId } = result.rows[0];
      config.outputs = outputsForSession(sessionId);

      await startSession(sessionId, userId, config, browser);

      reply.status(201).send({ sessionId, status: 'LIVE' });
    },
  );

  app.post<{ Params: { id: string } }>(
    '/sessions/:id/stop',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { userId } = request;
      if (!userId) {
        reply
          .status(401)
          .send({ error: { code: 'UNAUTHORIZED', message: 'Missing bearer token' } });
        return;
      }

      const row = await findOwnedSession(request.params.id, userId, reply);
      if (!row) return;

      await stopSession(row.id);
      reply.status(200).send({ sessionId: row.id, status: 'TERMINATED' });
    },
  );

  app.get<{ Params: { id: string } }>(
    '/sessions/:id/status',
    { preHandler: requireAuth },
    async (request, reply) => {
      const { userId } = request;
      if (!userId) {
        reply
          .status(401)
          .send({ error: { code: 'UNAUTHORIZED', message: 'Missing bearer token' } });
        return;
      }

      const row = await findOwnedSession(request.params.id, userId, reply);
      if (!row) return;

      reply.send({ sessionId: row.id, status: row.status });
    },
  );

  app.get('/sessions', { preHandler: requireAuth }, async (request, reply) => {
    const { userId } = request;
    if (!userId) {
      reply.status(401).send({ error: { code: 'UNAUTHORIZED', message: 'Missing bearer token' } });
      return;
    }

    const result = await pool.query<{ id: string; status: string }>(
      "SELECT id, status FROM stream_sessions WHERE user_id = $1 AND status = 'LIVE'",
      [userId],
    );
    reply.send({
      sessions: result.rows.map((row) => ({ sessionId: row.id, status: row.status })),
    });
  });

  return app;
}

async function main(): Promise<void> {
  const browser = await puppeteer.launch({
    headless: true,
    executablePath: resolveExecutablePath(),
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--use-gl=angle',
      '--enable-accelerated-2d-canvas',
    ],
  });

  const app = buildApp(browser);
  await app.listen({ port: CONTROL_PORT, host: '0.0.0.0' });
  app.log.info({ port: CONTROL_PORT, workerHost: WORKER_HOST }, 'control server listening');
}

// No explicit process.exit() on failure: an unhandled rejection here already
// terminates the container with a non-zero exit code (Node's default since
// v15), without risking a premature exit that skips in-flight cleanup.
main().catch((err: unknown) => {
  logger.fatal({ err }, 'worker fatal error');
  throw err;
});
