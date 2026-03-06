import { fileURLToPath } from "node:url";
import path from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const workspaceRoot = path.resolve(currentDir, "../..");

export default defineConfig({
  plugins: [react()],
  base: "./",
  resolve: {
    conditions: ["development"],
    alias: {
      "@renderer": path.resolve(currentDir, "src/renderer")
    }
  },
  server: {
    host: "127.0.0.1",
    port: 5173,
    fs: {
      allow: [workspaceRoot]
    }
  },
  build: {
    outDir: "dist/renderer",
    emptyOutDir: true
  }
});