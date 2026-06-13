import { app, BrowserWindow } from "electron";
import path from "node:path";
import { fileURLToPath } from "node:url";

import type { IpcContext } from "./ipc-context.js";
import { registerMaintenanceHandlers } from "./ipc-maintenance-handlers.js";
import { registerSolHandlers } from "./ipc-sol-handlers.js";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
// Set by `dev:renderer` workflow when serving the Vite dev server; otherwise we
// load the built renderer from dist/renderer.
const rendererUrl = process.env["CF7_ANKIT_RENDERER_URL"];
const windowTitle = "CF7 Animate Kit · 驾驶舱"; // "驾驶舱"

let mainWindow: BrowserWindow | null = null;

function createMainWindow(): BrowserWindow {
  mainWindow = new BrowserWindow({
    width: 1080,
    height: 760,
    minWidth: 880,
    minHeight: 600,
    backgroundColor: "#13161f",
    title: windowTitle,
    webPreferences: {
      preload: path.resolve(currentDir, "preload.js"),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: true,
    },
  });

  if (rendererUrl) {
    void mainWindow.loadURL(rendererUrl);
  } else {
    void mainWindow.loadFile(path.resolve(currentDir, "../renderer/index.html"));
  }

  mainWindow.on("closed", () => {
    mainWindow = null;
  });

  return mainWindow;
}

function createIpcContext(): IpcContext {
  return {
    getMainWindow: () => mainWindow,
    installs: [],
  };
}

app.whenReady().then(() => {
  const ctx = createIpcContext();
  registerMaintenanceHandlers(ctx);
  registerSolHandlers(ctx);
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
