import cors from '@fastify/cors';
import Fastify from 'fastify';

import { authRoutes } from './auth/auth.routes';
import { deviceRoutes } from './devices/devices.routes';
import { firmwareRoutes } from './firmware/firmware.routes';
import { logger } from './logger';
import { errorHandler } from './middleware/errorHandler';
import { youtubeRoutes } from './youtube/routes';

import type { FastifyBaseLogger, FastifyInstance } from 'fastify';

export function createApp(): FastifyInstance {
  // The cast selects Fastify's base-logger overload so the exported return
  // type stays FastifyInstance; Pino already implements this interface.
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-assertion
  const app = Fastify({ loggerInstance: logger as FastifyBaseLogger });

  app.register(cors);
  app.setErrorHandler(errorHandler);

  app.get('/health', async () => ({ status: 'ok' }));

  app.register(authRoutes, { prefix: '/api/v1/auth' });
  app.register(deviceRoutes, { prefix: '/api/v1/devices' });
  app.register(firmwareRoutes, { prefix: '/api/v1/firmware-releases' });

  app.register(youtubeRoutes, { prefix: '/api/v1/youtube' });
  return app;
}
