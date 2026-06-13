import { fileURLToPath } from "node:url";
import path from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(currentDir, "../..");

// The renderer is pure UI. It must NEVER import @cf7-animate-kit/an-host or
// node:fs — all native work happens in the Electron main process and is reached
// only through the preload contextBridge (window.ankit.*).
export default defineConfig({
  plugins: [react()],
  base: "./",
  resolve: {
    alias: {
      "@renderer": path.resolve(currentDir, "src/renderer")
    }
  },
  server: {
    host: "127.0.0.1",
    port: 5183,
    fs: {
      allow: [workspaceRoot]
    }
  },
  build: {
    outDir: "dist/renderer",
    emptyOutDir: true
  }
});
