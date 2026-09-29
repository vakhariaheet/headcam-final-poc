import pino from 'pino';

const NODE_ENV = process.env.NODE_ENV ?? 'development';
const LOG_LEVEL = process.env.LOG_LEVEL ?? (NODE_ENV === 'production' ? 'info' : 'debug');

// The one logger instance for this service — passed into Fastify (request/
// response logs share it) and imported anywhere that logs outside a
// request: the ffmpeg/capture pipeline, session lifecycle, startup. Child
// loggers (logger.child({ sessionId })) replace the old "[session <id>]"
// string prefixes with a structured field, so logs from one session can be
// filtered/queried instead of just visually scanned.
export const logger = pino({
  level: LOG_LEVEL,
  transport:
    NODE_ENV === 'production'
      ? undefined
      : { target: 'pino-pretty', options: { colorize: true, translateTime: 'HH:MM:ss' } },
});
