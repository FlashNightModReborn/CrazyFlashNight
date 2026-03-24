/**
 * Flash CS6 编译运行封装
 *
 * 封装 compile_test.ps1 的调用，返回 flashlog.txt 内容。
 * 调用前需要：Flash CS6 已启动、TestLoader 已打开。
 */

import { execSync } from "node:child_process";
import { readFileSync, existsSync } from "node:fs";
import { resolve, join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

/** 项目根目录 (tools/cf7-sort-fuzzer/src/flash/ → 项目根) */
const PROJECT_ROOT = resolve(__dirname, "../../../../");

/** compile_test.ps1 路径 */
const COMPILE_SCRIPT = join(PROJECT_ROOT, "scripts", "compile_test.ps1");

/** flashlog.txt 本地副本 */
const LOCAL_FLASHLOG = join(PROJECT_ROOT, "scripts", "flashlog.txt");

export interface FlashRunResult {
  success: boolean;
  trace: string;
  error?: string;
  durationMs: number;
}

/**
 * 触发 Flash 编译并返回 trace 输出。
 * 超时默认 30s（compile_test.ps1 的内置上限）。
 */
export function runFlash(timeoutMs: number = 35000): FlashRunResult {
  const start = Date.now();
  try {
    const output = execSync(
      `powershell -ExecutionPolicy Bypass -File "${COMPILE_SCRIPT}"`,
      {
        cwd: PROJECT_ROOT,
        timeout: timeoutMs,
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
      }
    );
    const trace = readFlashlog();
    return {
      success: true,
      trace,
      durationMs: Date.now() - start,
    };
  } catch (err: unknown) {
    const e = err as { status?: number; stdout?: string; stderr?: string; message?: string };
    return {
      success: false,
      trace: readFlashlog(),
      error: e.stderr || e.message || "unknown error",
      durationMs: Date.now() - start,
    };
  }
}

/** 读取 flashlog.txt 本地副本 */
function readFlashlog(): string {
  if (existsSync(LOCAL_FLASHLOG)) {
    return readFileSync(LOCAL_FLASHLOG, "utf-8");
  }
  // 尝试原始位置
  const appdata = process.env.APPDATA || "";
  const orig = join(appdata, "Macromedia", "Flash Player", "Logs", "flashlog.txt");
  if (existsSync(orig)) {
    return readFileSync(orig, "utf-8");
  }
  return "";
}

/** 获取项目根目录 */
export function getProjectRoot(): string {
  return PROJECT_ROOT;
}
