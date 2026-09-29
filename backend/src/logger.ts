import pino from 'pino';

import { LOG_LEVEL, NODE_ENV } from './config';

// The one logger instance for this service — passed into Fastify (so
// request/response logs share it) and imported directly wherever code runs
// outside a request (server.ts's startup line, the top-level fatal-error
// handler). Pretty-printed in development, structured JSON in production
// so log output is actually queryable once this runs somewhere real.
export const logger = pino({
  level: LOG_LEVEL,
  transport:
    NODE_ENV === 'production'
      ? undefined
      : { target: 'pino-pretty', options: { colorize: true, translateTime: 'HH:MM:ss' } },
});
