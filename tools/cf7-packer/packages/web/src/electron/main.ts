import { app, BrowserWindow, dialog, ipcMain, shell } from "electron";
import { execFile, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { parseDocument, Scalar } from "yaml";
import { loadConfig, PackerEngine, collect, filterFiles, enrichWithSize, diffFilterResults } from "@cf7-packer/core";
import type { PackConfig, PackerLogEvent, PackerProgressEvent, DiffResult } from "@cf7-packer/core";
import type { PackerRunOptions, PackerConfigSummary, PreviewFilesResult, PreviewFilesOptions, DiffOptions, BuildSfxOptions, ExcludeRequest, ExcludeResult } from "../shared/ipc-types.js";

const currentDir = path.dirname(fileURLToPath(import.meta.url));
const rendererUrl = process.env.CF7_PACKER_RENDERER_URL;
const windowTitle = "CF7 \u53d1\u884c\u6253\u5305\u5de5\u5177";
const toolRoot = findToolRoot(currentDir);
const configPath = path.join(toolRoot, "pack.config.yaml");

let mainWindow: BrowserWindow | null = null;
let engine: PackerEngine | null = null;
let engineRunning = false;

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
    if (engineRunning) throw new Error("打包正在运行中，请等待完成或取消");
    engineRunning = true;

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
      engineRunning = false;
    }
  });

  ipcMain.handle("cf7-packer:cancel", () => {
    engine?.cancel();
  });

  ipcMain.handle("cf7-packer:open-file", async (_event, relativePath: string) => {
    const config = getConfig();
    const fullPath = path.resolve(config.source.repoRoot, relativePath);
    if (!fullPath.startsWith(path.resolve(config.source.repoRoot))) return; // 路径穿越防护
    if (fs.existsSync(fullPath)) await shell.openPath(fullPath);
  });

  ipcMain.handle("cf7-packer:reveal-file", async (_event, relativePath: string) => {
    const config = getConfig();
    const fullPath = path.resolve(config.source.repoRoot, relativePath);
    if (!fullPath.startsWith(path.resolve(config.source.repoRoot))) return; // 路径穿越防护
    if (fs.existsSync(fullPath)) shell.showItemInFolder(fullPath);
  });

  ipcMain.handle("cf7-packer:build-sfx", async (_event, opts: BuildSfxOptions) => {
    const { spawn } = await import("node:child_process");
    const sfxScript = path.join(toolRoot, "sfx", "build-sfx.sh").replace(/\\/g, "/");
    const packOutput = opts.packOutput.replace(/\\/g, "/");

    // 定位 Git Bash（避免命中 WSL 的 bash）
    let bashExe = "bash";
    // 优先通过 where 查找 Git 安装路径下的 bash
    try {
      const whereOutput = execFileSync("where", ["bash.exe"], { encoding: "utf8", timeout: 5000 });
      const gitBash = whereOutput.trim().split("\n").map((l) => l.trim())
        .find((l) => l.toLowerCase().includes("git") && !l.toLowerCase().includes("wsl"));
      if (gitBash && fs.existsSync(gitBash)) bashExe = gitBash;
    } catch { /* where 失败，回退到硬编码列表 */ }
    if (bashExe === "bash") {
      const gitBashCandidates = [
        "C:\\Program Files\\Git\\usr\\bin\\bash.exe",
        "C:\\Program Files (x86)\\Git\\usr\\bin\\bash.exe",
        "C:\\Git\\usr\\bin\\bash.exe"
      ];
      for (const candidate of gitBashCandidates) {
        if (fs.existsSync(candidate)) { bashExe = candidate; break; }
      }
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

  ipcMain.handle("cf7-packer:exclude-file", async (_event, req: ExcludeRequest): Promise<ExcludeResult> => {
    try {
      const config = getConfig();
      const filePath = req.filePath.replace(/\\/g, "/");

      // 安全检查：路径不能包含 .. 逃逸
      if (filePath.includes("..")) {
        return { success: false, pattern: "", layerName: "", error: "路径包含非法字符" };
      }

      // 找到匹配的 layer
      let matchedLayerName = "";
      let excludePattern = "";

      if (req.layer) {
        const layer = config.layers.find((l) => l.name === req.layer);
        if (layer) {
          matchedLayerName = layer.name;
          const prefix = (layer.source === "." || layer.source === "./") ? "" : normalizePrefix(layer.source);
          const relPath = prefix ? filePath.slice(prefix.length) : filePath;
          excludePattern = req.isDir ? relPath + "/**" : relPath;
        }
      }

      if (!matchedLayerName) {
        for (const layer of config.layers) {
          const isRoot = layer.source === "." || layer.source === "./";
          const prefix = isRoot ? "" : normalizePrefix(layer.source);
          if (!isRoot && !filePath.startsWith(prefix)) continue;
          matchedLayerName = layer.name;
          const relPath = prefix ? filePath.slice(prefix.length) : filePath;
          excludePattern = req.isDir ? relPath + "/**" : relPath;
          break;
        }
      }

      if (!matchedLayerName) {
        matchedLayerName = "__global__";
        excludePattern = req.isDir ? filePath + "/**" : filePath;
      }

      // 构造带引号的 YAML Scalar，保持配置风格一致
      function quotedScalar(value: string): Scalar {
        const s = new Scalar(value);
        s.type = "QUOTE_DOUBLE";
        return s;
      }

      // 用 yaml Document API 写入，保留注释
      const yamlContent = fs.readFileSync(configPath, "utf8");
      const doc = parseDocument(yamlContent);

      if (matchedLayerName === "__global__") {
        const globalExclude = doc.get("globalExclude") as any;
        if (!globalExclude) {
          doc.set("globalExclude", [excludePattern]);
        } else {
          globalExclude.add(quotedScalar(excludePattern));
        }
      } else {
        const docLayers = doc.get("layers") as any;
        if (docLayers?.items) {
          for (const layerNode of docLayers.items) {
            if (layerNode.get("name") === matchedLayerName) {
              const excludeArr = layerNode.get("exclude") as any;
              if (!excludeArr) {
                layerNode.set("exclude", [excludePattern]);
              } else {
                excludeArr.add(quotedScalar(excludePattern));
              }
              break;
            }
          }
        }
      }

      fs.writeFileSync(configPath, doc.toString(), "utf8");

      // 发送日志到渲染器
      const action = req.deleteFromDisk ? "删除并排除" : "排除";
      sendToRenderer("cf7-packer:log", {
        layer: matchedLayerName === "__global__" ? "global" : matchedLayerName,
        level: "info",
        message: `${action}: ${filePath} → exclude: "${excludePattern}"`
      } satisfies PackerLogEvent);

      // 如果需要删除文件
      if (req.deleteFromDisk) {
        const fullPath = path.resolve(config.source.repoRoot, req.filePath);
        const realPath = path.resolve(fullPath);
        const realRepoRoot = path.resolve(config.source.repoRoot);
        if (!realPath.startsWith(realRepoRoot)) {
          return { success: false, pattern: excludePattern, layerName: matchedLayerName, error: "路径超出仓库范围" };
        }
        if (fs.existsSync(fullPath)) {
          const stat = fs.statSync(fullPath);
          fs.rmSync(fullPath, { recursive: true, force: true });
          sendToRenderer("cf7-packer:log", {
            layer: matchedLayerName === "__global__" ? "global" : matchedLayerName,
            level: "warn",
            message: `已从磁盘删除: ${filePath}${stat.isDirectory() ? " (目录)" : ""}`
          } satisfies PackerLogEvent);
        }
      }

      return { success: true, pattern: excludePattern, layerName: matchedLayerName };
    } catch (err) {
      sendToRenderer("cf7-packer:log", {
        layer: "system", level: "error",
        message: `排除操作失败: ${String(err)}`
      } satisfies PackerLogEvent);
      return { success: false, pattern: "", layerName: "", error: String(err) };
    }
  });
}

function normalizePrefix(source: string): string {
  let s = source.replace(/\\/g, "/");
  if (!s.endsWith("/")) s += "/";
  return s;
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
