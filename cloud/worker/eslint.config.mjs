import js from '@eslint/js';
import { defineConfig } from 'eslint/config';
import { configs, plugins, rules } from 'eslint-config-airbnb-extended';

const jsConfig = defineConfig([
  {
    name: 'js/config',
    ...js.configs.recommended,
  },
  plugins.stylistic,
  plugins.importX,
  ...configs.base.recommended,
  rules.base.importsStrict,
]);

const nodeConfig = defineConfig([plugins.node, ...configs.node.recommended]);

const typescriptConfig = defineConfig([
  plugins.typescriptEslint,
  ...configs.base.typescript,
  rules.typescript.typescriptEslintStrict,
]);

export default defineConfig([
  { ignores: ['dist/**'] },
  ...jsConfig,
  ...nodeConfig,
  ...typescriptConfig,
  {
    name: 'project/overrides',
    rules: {
      // A real logger exists now (logger.ts, wired into Fastify and
      // threaded into the ffmpeg/capture pipeline) — a stray console.*
      // call is a leftover Airbnb's default rule should catch.
      // fs/child_process sync calls here run only at startup and once per
      // reconnect-loop iteration, not per-request — blocking briefly there
      // is intentional, not the hot-path anti-pattern this rule targets.
      'n/no-sync': 'off',
      // Both loops are inherently sequential by design: frame capture must
      // pace itself to the target FPS, and the reconnect loop must wait for
      // ffmpeg to exit before retrying — neither is parallelizable work.
      'no-await-in-loop': 'off',
      // Named exports are consistent across the backend service in this
      // repo; this file has no exports at all (it's a directly-run script),
      // so this rule doesn't apply either way.
      'import-x/prefer-default-export': 'off',
    },
  },
]);
