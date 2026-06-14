import { defineConfig } from 'vitest/config';

export default defineConfig({
  // Resolve workspace packages to their TS source (no build needed for tests).
  resolve: {
    conditions: ['development'],
  },
  test: {
    include: ['packages/*/tests/**/*.test.ts'],
    passWithNoTests: true,
    environment: 'node',
    reporters: ['default'],
  },
});
