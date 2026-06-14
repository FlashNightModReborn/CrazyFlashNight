import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

/**
 * Vite config for the CEP panel.
 *
 *  - base: './'  — CEP loads index.html from disk via file://; all asset URLs
 *    MUST be relative or the CEF webview can't resolve them.
 *  - server.host: true — binds 0.0.0.0 so Animate's CEF webview process can
 *    reach the dev server during hot-reload (see index.html dual-mode entry).
 *  - build.outDir: 'dist' — the post-build copy step (see package.json
 *    "build") then drops ../jsfl-host/host, CSXS/, and .debug alongside it so
 *    dist/ is a self-contained, installable CEP extension.
 */
export default defineConfig({
  base: './',
  // viteSingleFile inlines the JS + CSS into index.html so there is NO external
  // module script. CEF (file://) enforces strict MIME on external type="module"
  // scripts and blocks them (file:// has no MIME) → blank panel. Inlining avoids
  // the external fetch entirely.
  plugins: [react(), viteSingleFile()],
  resolve: {
    alias: {
      // core's anEnv (node:path) is dragged in by `export * as anEnv` and cannot
      // be tree-shaken out; the panel never calls it, so stub node:path so the
      // bare specifier resolves instead of crashing the CEF webview (blank panel).
      'node:path': fileURLToPath(new URL('./src/lib/node-path-stub.ts', import.meta.url)),
    },
  },
  server: {
    port: 5173,
    host: true,
    strictPort: true,
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    target: 'chrome88', // CEP 9 ships a recent-ish CEF; conservative target.
    sourcemap: true,
  },
});
