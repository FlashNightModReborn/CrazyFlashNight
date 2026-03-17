import { app, BrowserWindow, dialog, ipcMain, shell } from "electron";
import { execFile, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { loadConfig, PackerEngine, collect, filterFiles, enrichWithSize, diffFilterResults } from "@cf7-packer/core";
import type { PackConfig, PackerLogEvent, PackerProgressEvent, DiffResult } from "@cf7-packer/core";
import type { PackerRunOptions, PackerConfigSummary, PreviewFilesResult, PreviewFilesOptions, DiffOptions, BuildSfxOptions } from "../shared/ipc-types.js";

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

  ipcMain.handle("cf7-packer:preview-files", async (_event, opts?: PreviewFilesOptions): Promise<PreviewFilesResult> => {
    const config = getConfig();
    if (opts?.tag) {
      config.source.mode = "git-tag";
      config.source.tag = opts.tag;
    }
    const collected = await collect(config);
    const filtered = filterFiles(collected.files, config);
    if (config.source.mode === "worktree") {
      enrichWithSize(filtered.included, config.source.repoRoot);
    }
    return {
      included: filtered.included,
      excluded: filtered.excluded,
      layers: filtered.layers,
      unmatchedCount: filtered.unmatchedCount
    };
  });

  ipcMain.handle("cf7-packer:diff-files", async (_event, opts: DiffOptions): Promise<DiffResult> => {
    async function collectFiltered(tag: string | null | undefined) {
      const cfg = getConfig();
      if (tag) {
        cfg.source.mode = "git-tag";
        cfg.source.tag = tag;
      } else {
        cfg.source.mode = "worktree";
      }
      const collected = await collect(cfg);
      return filterFiles(collected.files, cfg);
    }

    const [baseline, target] = await Promise.all([
      collectFiltered(opts.baseTag),
      collectFiltered(opts.targetTag)
    ]);
    return diffFilterResults(baseline, target);
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

  ipcMain.handle("cf7-packer:open-file", async (_event, relativePath: string) => {
    const config = getConfig();
    const fullPath = path.resolve(config.source.repoRoot, relativePath);
    if (fs.existsSync(fullPath)) await shell.openPath(fullPath);
  });

  ipcMain.handle("cf7-packer:reveal-file", async (_event, relativePath: string) => {
    const config = getConfig();
    const fullPath = path.resolve(config.source.repoRoot, relativePath);
    if (fs.existsSync(fullPath)) shell.showItemInFolder(fullPath);
  });

  ipcMain.handle("cf7-packer:build-sfx", async (_event, opts: BuildSfxOptions) => {
    const { spawn } = await import("node:child_process");
    const sfxScript = path.join(toolRoot, "sfx", "build-sfx.sh").replace(/\\/g, "/");
    const packOutput = opts.packOutput.replace(/\\/g, "/");

    // 定位 Git Bash（避免命中 WSL 的 bash）
    const gitBashCandidates = [
      "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
      "C:\\Program Files (x86)\\Git\\usr\\bin\\bash.exe",
      "C:\\Git\\usr\\bin\\bash.exe"
    ];
    let bashExe = "bash";
    for (const candidate of gitBashCandidates) {
      if (fs.existsSync(candidate)) { bashExe = candidate; break; }
    }

    // 确保 Git 的 coreutils 在 PATH 中
    const gitDir = path.dirname(path.dirname(bashExe));
    const gitBinDirs = [
      path.join(gitDir, "usr", "bin"),
      path.join(gitDir, "bin"),
      path.join(gitDir, "..", "..", "bin")
    ].filter((d) => fs.existsSync(d)).map((d) => d.replace(/\\/g, "/"));
    const env = { ...process.env, PATH: gitBinDirs.join(";") + ";" + (process.env.PATH ?? "") };

    // 通过环境变量传递路径（避免 Windows CreateProcess 吃掉花括号）
    env.CF7_SFX_VERSION = opts.version;
    env.CF7_SFX_PACK_OUTPUT = packOutput;
    if (opts.unityDataDir) env.CF7_SFX_UNITY_DATA = opts.unityDataDir.replace(/\\/g, "/");

    return new Promise<{ success: boolean; outputPath?: string; error?: string }>((resolve) => {
      const child = spawn(bashExe, [sfxScript], { cwd: toolRoot, env });
      let stdout = "";
      let stderr = "";

      child.stdout.on("data", (chunk: Buffer) => {
        const text = chunk.toString("utf8");
        stdout += text;
        // 解析 7z 的进度百分比（格式: "  42% 1234 + filename"）
        const pctMatch = text.match(/(\d+)%/);
        if (pctMatch) {
          const pct = parseInt(pctMatch[1]!, 10);
          sendToRenderer("cf7-packer:log", {
            layer: "sfx", level: "info",
            message: `压缩中... ${pct}%`
          } satisfies PackerLogEvent);
        }
        // 转发其他阶段信息
        for (const line of text.split("\n")) {
          const trimmed = line.trim();
          if (trimmed && !trimmed.match(/^\d+%/) && !trimmed.startsWith("7-Zip")
            && !trimmed.startsWith("Scanning") && !trimmed.startsWith("Creating")
            && !trimmed.startsWith("Add ") && !trimmed.startsWith("Files ")
            && !trimmed.startsWith("Archive ") && !trimmed.startsWith("Everything")) {
            sendToRenderer("cf7-packer:log", { layer: "sfx", level: "info", message: trimmed } satisfies PackerLogEvent);
          }
        }
      });

      child.stderr.on("data", (chunk: Buffer) => { stderr += chunk.toString("utf8"); });

      child.on("close", (code) => {
        if (code !== 0) {
          resolve({ success: false, error: (stderr || stdout).slice(-500) });
        } else {
          const match = stdout.match(/构建完成:\s*(\S+)/);
          resolve({ success: true, outputPath: match?.[1]?.trim() });
        }
      });

      child.on("error", (err) => {
        resolve({ success: false, error: err.message });
      });
    });
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
