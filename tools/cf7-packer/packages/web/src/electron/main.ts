import { app, BrowserWindow } from "electron";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { loadConfig } from "@cf7-packer/core";
import type { IpcContext } from "./ipc-context.js";
import { registerConfigHandlers } from "./ipc-config-handlers.js";
import { registerPackHandlers } from "./ipc-pack-handlers.js";
import { registerFileHandlers } from "./ipc-file-handlers.js";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const rendererUrl = process.env.CF7_PACKER_RENDERER_URL;
const windowTitle = "CF7 \u53d1\u884c\u6253\u5305\u5de5\u5177";
const toolRoot = findToolRoot(currentDir);
const configPath = path.join(toolRoot, "pack.config.yaml");

let mainWindow: BrowserWindow | null = null;

function findToolRoot(startDir: string): string {
  let dir = path.resolve(startDir);
  for (let i = 0; i < 10; i++) {
    if (fs.existsSync(path.join(dir, "pack.config.yaml"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error("\u627e\u4e0d\u5230 cf7-packer \u5de5\u4f5c\u533a\u6839\u76ee\u5f55 (pack.config.yaml)");
}

function createMainWindow(): BrowserWindow {
  mainWindow = new BrowserWindow({
    width: 900,
    height: 720,
    minWidth: 780,
    minHeight: 560,
    backgroundColor: "#1a1a2e",
    title: windowTitle,
    webPreferences: {
      preload: path.resolve(currentDir, "preload.js"),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true
    }
  });

  if (rendererUrl) {
    void mainWindow.loadURL(rendererUrl);
  } else {
    void mainWindow.loadFile(path.resolve(currentDir, "../../dist/renderer/index.html"));
  }

  mainWindow.on("closed", () => { mainWindow = null; });

  return mainWindow;
}

function createIpcContext(): IpcContext {
  return {
    configPath,
    toolRoot,
    getMainWindow: () => mainWindow,
    getConfig: () => loadConfig(configPath),
    sendToRenderer: (channel, data) => {
      mainWindow?.webContents.send(channel, data);
    },
    engine: null,
    engineRunning: false,
    knownOutputDirs: new Set<string>()
  };
}

app.whenReady().then(() => {
  const ctx = createIpcContext();
  registerConfigHandlers(ctx);
  registerPackHandlers(ctx);
  registerFileHandlers(ctx);
  createMainWindow();

  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createMainWindow();
    }
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") {
    app.quit();
  }
});
