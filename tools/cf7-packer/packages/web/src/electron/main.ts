import { app, BrowserWindow, dialog, ipcMain, shell } from "electron";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { loadConfig, PackerEngine } from "@cf7-packer/core";
import type { PackConfig, PackerLogEvent, PackerProgressEvent } from "@cf7-packer/core";
import type { PackerRunOptions, PackerConfigSummary } from "../shared/ipc-types.js";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const rendererUrl = process.env.CF7_PACKER_RENDERER_URL;
const windowTitle = "CF7 \u53d1\u884c\u6253\u5305\u5de5\u5177";
const toolRoot = findToolRoot(currentDir);
const configPath = path.join(toolRoot, "pack.config.yaml");

let mainWindow: BrowserWindow | null = null;
let engine: PackerEngine | null = null;

function findToolRoot(startDir: string): string {
  let dir = path.resolve(startDir);
  for (let i = 0; i < 10; i++) {
    if (fs.existsSync(path.join(dir, "pack.config.yaml"))) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  throw new Error("找不到 cf7-packer 工作区根目录 (pack.config.yaml)");
}

function getConfig(): PackConfig {
  return loadConfig(configPath);
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
      preload: path.resolve(currentDir, "preload.js")
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

function sendToRenderer(channel: string, data: unknown): void {
  mainWindow?.webContents.send(channel, data);
}

function registerIpcHandlers(): void {
  ipcMain.handle("cf7-packer:load-config", (): PackerConfigSummary => {
    const config = getConfig();
    return {
      name: config.meta.name,
      mode: config.source.mode,
      tag: config.source.tag ?? undefined,
      layers: config.layers.map((l) => ({
        name: l.name,
        description: l.description
      })),
      globalExcludeCount: config.globalExclude.length,
      outputDir: config.output.dir
    };
  });

  ipcMain.handle("cf7-packer:get-tags", (): string[] => {
    const config = getConfig();
    try {
      const output = execFileSync("git", ["tag", "-l"], {
        cwd: config.source.repoRoot,
        encoding: "utf8"
      });
      return output.trim().split("\n").filter(Boolean);
    } catch {
      return [];
    }
  });

  ipcMain.handle("cf7-packer:run", async (_event, opts: PackerRunOptions) => {
    const config = getConfig();

    if (opts.tag) {
      config.source.mode = "git-tag";
      config.source.tag = opts.tag;
    }

    const outputDir = opts.outputDir
      ? path.resolve(opts.outputDir)
      : path.resolve(toolRoot, config.output.dir);

    engine = new PackerEngine(config);

    engine.on("log", (event: PackerLogEvent) => {
      sendToRenderer("cf7-packer:log", event);
    });

    engine.on("progress", (event: PackerProgressEvent) => {
      sendToRenderer("cf7-packer:progress", event);
    });

    try {
      return await engine.run({
        dryRun: opts.dryRun,
        outputDir,
        clean: config.output.clean
      });
    } finally {
      engine = null;
    }
  });

  ipcMain.handle("cf7-packer:cancel", () => {
    engine?.cancel();
  });

  ipcMain.handle("cf7-packer:pick-output-dir", async (_event, currentPath?: string) => {
    if (!mainWindow) return { canceled: true };
    const result = await dialog.showOpenDialog(mainWindow, {
      defaultPath: currentPath ?? toolRoot,
      title: "选择输出目录",
      properties: ["openDirectory", "createDirectory"]
    });
    return {
      canceled: result.canceled,
      path: result.filePaths[0]
    };
  });

  ipcMain.handle("cf7-packer:reveal-output", async (_event, targetPath: string) => {
    const resolved = path.resolve(targetPath);
    if (fs.existsSync(resolved)) {
      const stats = fs.statSync(resolved);
      if (stats.isDirectory()) {
        await shell.openPath(resolved);
      } else {
        shell.showItemInFolder(resolved);
      }
    }
  });
}

app.whenReady().then(() => {
  registerIpcHandlers();
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
