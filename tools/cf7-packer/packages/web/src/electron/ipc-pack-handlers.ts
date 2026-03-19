import { dialog, ipcMain } from "electron";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import {
  PackerEngine,
  resolveOutputDir,
  OutputDirNotOwnedError,
  estimateEtaMs,
  withSourceOverride,
  isPathInsideRoot
} from "@cf7-packer/core";
import type { PackerLogEvent, PackerProgressEvent } from "@cf7-packer/core";
import type { PackerRunOptions, BuildSfxOptions } from "../shared/ipc-types.js";
import type { IpcContext } from "./ipc-context.js";

export function registerPackHandlers(ctx: IpcContext): void {
  ipcMain.handle("cf7-packer:run", async (_event, opts: PackerRunOptions) => {
    if (ctx.engineRunning) throw new Error("打包正在运行中，请等待完成或取消");

    if (opts.tag !== undefined && opts.tag !== null && !opts.tag) {
      throw new Error("git-tag 模式需要指定非空的 tag 名称");
    }
    const config = withSourceOverride(ctx.getConfig(), opts.tag ? { tag: opts.tag } : undefined);

    const outputDir = opts.outputDir
      ? resolveOutputDir(config, ctx.configPath, opts.outputDir)
      : resolveOutputDir(config, ctx.configPath);

    let forceClean = opts.forceClean ?? false;

    async function runEngine(): ReturnType<PackerEngine["run"]> {
      ctx.engineRunning = true;
      ctx.engine = new PackerEngine(config);

      ctx.engine.on("log", (event: PackerLogEvent) => {
        ctx.sendToRenderer("cf7-packer:log", event);
      });

      ctx.engine.on("progress", (event: PackerProgressEvent) => {
        ctx.sendToRenderer("cf7-packer:progress", event);
      });

      try {
        const packResult = await ctx.engine.run({
          dryRun: opts.dryRun,
          outputDir,
          clean: config.output.clean,
          forceClean
        });
        if (!packResult.cancelled && packResult.outputDir) {
          ctx.knownOutputDirs.add(packResult.outputDir);
        }
        return packResult;
      } finally {
        ctx.engine = null;
        ctx.engineRunning = false;
      }
    }

    try {
      return await runEngine();
    } catch (err) {
      const mainWindow = ctx.getMainWindow();
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
    ctx.engine?.cancel();
  });

  ipcMain.handle("cf7-packer:build-sfx", async (_event, opts: BuildSfxOptions) => {
    // 白名单校验 version：仅允许字母、数字、中文、点、连字符、下划线、空格
    if (opts.version && !/^[\w.\-\u4e00-\u9fff ]+$/.test(opts.version)) {
      return { success: false, error: `版本名含非法字符: "${opts.version}"（仅允许字母、数字、中文、点、连字符、下划线、空格）` };
    }

    // 校验 packOutput 必须在已知输出目录或 toolRoot/output 内
    const resolvedPackOutput = path.resolve(opts.packOutput);
    const outputBase = path.resolve(ctx.toolRoot, "output");
    const packOutputAllowed =
      isPathInsideRoot(outputBase, resolvedPackOutput) ||
      [...ctx.knownOutputDirs].some(dir => isPathInsideRoot(dir, resolvedPackOutput));
    if (!packOutputAllowed) {
      return { success: false, error: `packOutput 路径不在允许范围内: "${opts.packOutput}"` };
    }

    // 校验 unityDataDir（如果提供）必须在 repoRoot 或内置 assets 目录内
    if (opts.unityDataDir) {
      const resolvedUnityData = path.resolve(opts.unityDataDir);
      const config = ctx.getConfig();
      const assetsDir = path.resolve(ctx.toolRoot, "assets");
      if (!isPathInsideRoot(config.source.repoRoot, resolvedUnityData) &&
          !isPathInsideRoot(assetsDir, resolvedUnityData)) {
        return { success: false, error: `unityDataDir 路径不在允许范围内: "${opts.unityDataDir}"` };
      }
    }

    const { spawn } = await import("node:child_process");
    const isWindows = process.platform === "win32";
    const sfxScript = path.join(ctx.toolRoot, "sfx", "build-sfx.sh").replace(/\\/g, "/");
    const packOutput = isWindows ? opts.packOutput.replace(/\\/g, "/") : opts.packOutput;

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

    env.CF7_SFX_VERSION = opts.version;
    env.CF7_SFX_PACK_OUTPUT = packOutput;
    if (opts.unityDataDir) {
      env.CF7_SFX_UNITY_DATA = isWindows ? opts.unityDataDir.replace(/\\/g, "/") : opts.unityDataDir;
    }

    return new Promise<{ success: boolean; outputPath?: string; error?: string }>((resolve) => {
      const child = spawn(bashExe, [sfxScript], { cwd: ctx.toolRoot, env });
      let stdout = "";
      let stderr = "";
      const sfxStartedAt = Date.now();
      let lastSfxProgress = -1;

      ctx.sendToRenderer("cf7-packer:progress", {
        phase: "sfx",
        current: 0,
        total: 100,
        label: "构建安装包",
        detail: "准备压缩资源"
      } satisfies PackerProgressEvent);

      child.stdout.on("data", (chunk: Buffer) => {
        const text = chunk.toString("utf8");
        stdout += text;
        const pctMatch = text.match(/(\d+)%/);
        if (pctMatch) {
          const pct = parseInt(pctMatch[1]!, 10);
          if (pct !== lastSfxProgress) {
            lastSfxProgress = pct;
            ctx.sendToRenderer("cf7-packer:progress", {
              phase: "sfx",
              current: pct,
              total: 100,
              label: "构建安装包",
              detail: "7-Zip 压缩中",
              etaMs: estimateEtaMs(sfxStartedAt, pct, 100)
            } satisfies PackerProgressEvent);
          }
        }
        for (const line of text.split("\n")) {
          const trimmed = line.trim();
          if (trimmed && !trimmed.match(/^\d+%/) && !trimmed.startsWith("7-Zip")
            && !trimmed.startsWith("Scanning") && !trimmed.startsWith("Creating")
            && !trimmed.startsWith("Add ") && !trimmed.startsWith("Files ")
            && !trimmed.startsWith("Archive ") && !trimmed.startsWith("Everything")) {
            ctx.sendToRenderer("cf7-packer:log", { layer: "sfx", level: "info", message: trimmed } satisfies PackerLogEvent);
          }
        }
      });

      child.stderr.on("data", (chunk: Buffer) => { stderr += chunk.toString("utf8"); });

      child.on("close", (code) => {
        if (code !== 0) {
          resolve({ success: false, error: (stderr || stdout).slice(-500) });
        } else {
          ctx.sendToRenderer("cf7-packer:progress", {
            phase: "sfx",
            current: 100,
            total: 100,
            label: "构建安装包",
            detail: "安装包构建完成"
          } satisfies PackerProgressEvent);
          const match = stdout.match(/构建完成:\s*(.+)\s+\(/);
          let outputPath = (match?.[1] ?? stdout.match(/构建完成:\s*(.+)/)?.[1])?.trim();
          if (outputPath) {
            // Git Bash 输出 /c/Users/... 格式，Windows 的 path.resolve 会误解为 C:\c\Users\...
            // 需要转换为 C:/Users/... 格式
            if (isWindows) {
              outputPath = outputPath.replace(/^\/([a-zA-Z])\//, "$1:/");
            }
            // 将 SFX 输出路径及其所在目录加入已知输出目录，使 revealOutput 可用
            const resolved = path.resolve(outputPath);
            ctx.knownOutputDirs.add(resolved);
            ctx.knownOutputDirs.add(path.dirname(resolved));
          }
          resolve(outputPath ? { success: true, outputPath } : { success: true });
        }
      });

      child.on("error", (err) => {
        resolve({ success: false, error: err.message });
      });
    });
  });
}
