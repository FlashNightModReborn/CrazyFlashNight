import { app, BrowserWindow, dialog, ipcMain, shell } from "electron";
import { execFile, execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  loadConfig,
  PackerEngine,
  collect,
  filterFiles,
  enrichWithSize,
  diffFilterResults,
  applyEstimatedSizes,
  applyExcludeMutation,
  prepareExcludeAction,
  getTagBlobInfo,
  getWorktreeBlobHashes,
  getModifiedPathsBetweenTags,
  resolveOutputDir,
  normalizeRepoRelativePath,
  isPathInsideRoot,
  OutputDirNotOwnedError
} from "@cf7-packer/core";
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
    if (opts?.tag !== undefined && opts.tag !== null) {
      if (!opts.tag) throw new Error("git-tag 模式需要指定非空的 tag 名称");
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
      layers: applyEstimatedSizes(filtered.layers, filtered.included),
      unmatchedCount: filtered.unmatchedCount
    };
  });

  ipcMain.handle("cf7-packer:diff-files", async (_event, opts: DiffOptions): Promise<DiffResult> => {
    const config = getConfig();
    const repoRoot = config.source.repoRoot;

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

    // 检测内容变更
    let modifiedPaths: Set<string> | undefined;
    const baseIsTag = !!opts.baseTag;
    const targetIsTag = !!opts.targetTag;

    try {
      if (baseIsTag && targetIsTag) {
        // tag ↔ tag: 单次 git diff --name-only
        modifiedPaths = await getModifiedPathsBetweenTags(repoRoot, opts.baseTag!, opts.targetTag!);
      } else if (baseIsTag !== targetIsTag) {
        // tag ↔ worktree: 比较 object hash
        const tag = baseIsTag ? opts.baseTag! : opts.targetTag!;
        const tagInfo = await getTagBlobInfo(repoRoot, tag);
        // 找 common 路径
        const baselineSet = new Set(baseline.included.map(f => f.path));
        const targetSet = new Set(target.included.map(f => f.path));
        const commonPaths = [...baselineSet].filter(p => targetSet.has(p));
        const worktreeHashes = await getWorktreeBlobHashes(repoRoot, commonPaths);
        modifiedPaths = new Set<string>();
        for (const p of commonPaths) {
          const tagHash = tagInfo.get(p)?.hash;
          const wtHash = worktreeHashes.get(p);
          if (tagHash && wtHash && tagHash !== wtHash) {
            modifiedPaths.add(p);
          }
        }
      }
      // worktree ↔ worktree: 无 content 检测，退化为纯路径比较
    } catch {
      // 内容检测失败不阻塞，退化为纯路径 diff
    }

    return diffFilterResults(baseline, target, modifiedPaths);
  });

  ipcMain.handle("cf7-packer:run", async (_event, opts: PackerRunOptions) => {
    if (engineRunning) throw new Error("打包正在运行中，请等待完成或取消");

    const config = getConfig();

    if (opts.tag !== undefined && opts.tag !== null) {
      if (!opts.tag) throw new Error("git-tag 模式需要指定非空的 tag 名称");
      config.source.mode = "git-tag";
      config.source.tag = opts.tag;
    }

    const outputDir = opts.outputDir
      ? resolveOutputDir(config, configPath, opts.outputDir)
      : resolveOutputDir(config, configPath);

    let forceClean = opts.forceClean ?? false;

    async function runEngine(): ReturnType<PackerEngine["run"]> {
      engineRunning = true;
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
          clean: config.output.clean,
          forceClean
        });
      } finally {
        engine = null;
        engineRunning = false;
      }
    }

    try {
      return await runEngine();
    } catch (err) {
      if (err instanceof OutputDirNotOwnedError && mainWindow) {
        const result = await dialog.showMessageBox(mainWindow, {
          type: "warning",
          buttons: ["取消", "确认清理"],
          defaultId: 0,
          cancelId: 0,
          title: "输出目录确认",
          message: "目标目录非本工具创建",
          detail: `路径: ${err.dir}\n\n该目录缺少打包工具标记文件，继续将清空该目录。确认继续？`
        });
        if (result.response === 1) {
          forceClean = true;
          return await runEngine();
        }
        // 用户取消
        return {
          mode: "execute" as const,
          cancelled: true,
          totalFiles: 0,
          copiedFiles: 0,
          totalSize: 0,
          layers: [],
          outputDir,
          duration: 0,
          errors: []
        };
      }
      throw err;
    }
  });

  ipcMain.handle("cf7-packer:cancel", () => {
    engine?.cancel();
  });

  ipcMain.handle("cf7-packer:open-file", async (_event, relativePath: string) => {
    const config = getConfig();
    const normalizedPath = normalizeRepoRelativePath(relativePath);
    const fullPath = path.resolve(config.source.repoRoot, normalizedPath);
    if (!isPathInsideRoot(config.source.repoRoot, fullPath)) return; // 路径穿越防护
    if (fs.existsSync(fullPath)) await shell.openPath(fullPath);
  });

  ipcMain.handle("cf7-packer:reveal-file", async (_event, relativePath: string) => {
    const config = getConfig();
    const normalizedPath = normalizeRepoRelativePath(relativePath);
    const fullPath = path.resolve(config.source.repoRoot, normalizedPath);
    if (!isPathInsideRoot(config.source.repoRoot, fullPath)) return; // 路径穿越防护
    if (fs.existsSync(fullPath)) shell.showItemInFolder(fullPath);
  });

  ipcMain.handle("cf7-packer:build-sfx", async (_event, opts: BuildSfxOptions) => {
    const { spawn } = await import("node:child_process");
    const isWindows = process.platform === "win32";
    const sfxScript = path.join(toolRoot, "sfx", "build-sfx.sh").replace(/\\/g, "/");
    const packOutput = isWindows ? opts.packOutput.replace(/\\/g, "/") : opts.packOutput;

    // Windows 下定位 Git Bash；Unix 直接使用系统 bash。
    let bashExe = "bash";
    if (isWindows) {
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
    }

    const env = { ...process.env };
    if (isWindows && bashExe !== "bash") {
      const gitDir = path.dirname(path.dirname(bashExe));
      const gitBinDirs = [
        path.join(gitDir, "usr", "bin"),
        path.join(gitDir, "bin"),
        path.join(gitDir, "..", "..", "bin")
      ].filter((d) => fs.existsSync(d));
      const existingPath = env.PATH ?? "";
      env.PATH = [...gitBinDirs, existingPath].filter(Boolean).join(path.delimiter);
    }

    // 通过环境变量传递路径（避免 Windows CreateProcess 吃掉花括号）
    env.CF7_SFX_VERSION = opts.version;
    env.CF7_SFX_PACK_OUTPUT = packOutput;
    if (opts.unityDataDir) {
      env.CF7_SFX_UNITY_DATA = isWindows ? opts.unityDataDir.replace(/\\/g, "/") : opts.unityDataDir;
    }

    return new Promise<{ success: boolean; outputPath?: string; error?: string }>((resolve) => {
      const child = spawn(bashExe, [sfxScript], { cwd: toolRoot, env });
      let stdout = "";
      let stderr = "";
      const sfxStartedAt = Date.now();
      let lastSfxProgress = -1;

      sendToRenderer("cf7-packer:progress", {
        phase: "sfx",
        current: 0,
        total: 100,
        label: "构建安装包",
        detail: "准备压缩资源"
      } satisfies PackerProgressEvent);

      child.stdout.on("data", (chunk: Buffer) => {
        const text = chunk.toString("utf8");
        stdout += text;
        // 解析 7z 的进度百分比（格式: "  42% 1234 + filename"）
        const pctMatch = text.match(/(\d+)%/);
        if (pctMatch) {
          const pct = parseInt(pctMatch[1]!, 10);
          if (pct !== lastSfxProgress) {
            lastSfxProgress = pct;
            sendToRenderer("cf7-packer:progress", {
              phase: "sfx",
              current: pct,
              total: 100,
              label: "构建安装包",
              detail: "7-Zip 压缩中",
              etaMs: estimateEtaMs(sfxStartedAt, pct, 100)
            } satisfies PackerProgressEvent);
          }
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
          sendToRenderer("cf7-packer:progress", {
            phase: "sfx",
            current: 100,
            total: 100,
            label: "构建安装包",
            detail: "安装包构建完成"
          } satisfies PackerProgressEvent);
          const match = stdout.match(/构建完成:\s*(\S+)/);
          const outputPath = match?.[1]?.trim();
          resolve(outputPath ? { success: true, outputPath } : { success: true });
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

  ipcMain.handle("cf7-packer:confirm-delete", async (_event, filePath: string, isDir: boolean): Promise<boolean> => {
    if (!mainWindow) return false;
    const detail = isDir
      ? `将递归删除目录 "${filePath}" 及其所有内容，并添加排除规则。\n此操作不可撤销。`
      : `将删除文件 "${filePath}" 并添加排除规则。\n此操作不可撤销。`;
    const result = await dialog.showMessageBox(mainWindow, {
      type: "warning",
      buttons: ["取消", "确认删除"],
      defaultId: 0,
      cancelId: 0,
      title: "确认删除",
      message: "确定要删除并排除？",
      detail
    });
    return result.response === 1;
  });

  ipcMain.handle("cf7-packer:exclude-file", async (_event, req: ExcludeRequest): Promise<ExcludeResult> => {
    try {
      const config = getConfig();
      const yamlContent = fs.readFileSync(configPath, "utf8");
      const { content, result } = applyExcludeMutation(yamlContent, config, req);
      fs.writeFileSync(configPath, content, "utf8");

      // 发送日志到渲染器
      const action = req.deleteFromDisk ? "删除并排除" : "排除";
      sendToRenderer("cf7-packer:log", {
        layer: result.layerName === "__global__" ? "global" : result.layerName,
        level: "info",
        message: result.alreadyPresent
          ? `${action}: ${result.normalizedPath} 已存在 exclude: "${result.pattern}"`
          : `${action}: ${result.normalizedPath} → exclude: "${result.pattern}"`
      } satisfies PackerLogEvent);

      // 如果需要删除文件，使用 prepareExcludeAction 做安全校验
      if (req.deleteFromDisk) {
        const prepared = prepareExcludeAction(config.source.repoRoot, req.filePath, true);
        if (prepared.error) {
          return { success: false, pattern: result.pattern, layerName: result.layerName, error: prepared.error };
        }
        if (prepared.shouldDelete && fs.existsSync(prepared.fullPath)) {
          const stat = fs.statSync(prepared.fullPath);
          fs.rmSync(prepared.fullPath, { recursive: true, force: true });
          sendToRenderer("cf7-packer:log", {
            layer: result.layerName === "__global__" ? "global" : result.layerName,
            level: "warn",
            message: `已从磁盘删除: ${prepared.normalizedPath}${stat.isDirectory() ? " (目录)" : ""}`
          } satisfies PackerLogEvent);
        }
      }

      return { success: true, pattern: result.pattern, layerName: result.layerName };
    } catch (err) {
      sendToRenderer("cf7-packer:log", {
        layer: "system", level: "error",
        message: `排除操作失败: ${String(err)}`
      } satisfies PackerLogEvent);
      return { success: false, pattern: "", layerName: "", error: String(err) };
    }
  });
}

function estimateEtaMs(startedAtMs: number, current: number, total: number): number | undefined {
  if (current <= 0 || total <= current) return undefined;
  const elapsed = Date.now() - startedAtMs;
  if (elapsed <= 0) return undefined;
  const avgPerUnit = elapsed / current;
  return Math.max(0, Math.round(avgPerUnit * (total - current)));
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
