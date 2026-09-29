import { createApp } from './app';
import { PORT } from './config';

const app = createApp();

// No explicit process.exit() on failure: an unhandled rejection here already
// terminates the process with a non-zero exit code (Node's default since
// v15), without risking a premature exit that skips in-flight cleanup.
app.listen({ port: PORT, host: '0.0.0.0' }).then((): void => {
  app.log.info(`umpirehat-backend listening on :${PORT}`);
});
