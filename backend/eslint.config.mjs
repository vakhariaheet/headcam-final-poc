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
      // A real logger exists now (logger.ts, wired into Fastify) — a stray
      // console.* call is a leftover Airbnb's default rule should catch.
      // Named exports are consistent across every module in this codebase
      // (controllers/services routinely grow beyond one export) and play
      // better with IDE auto-import than a default export would.
      'import-x/prefer-default-export': 'off',
    },
  },
]);
