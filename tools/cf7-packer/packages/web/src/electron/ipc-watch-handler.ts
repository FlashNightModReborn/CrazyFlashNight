import fs from "node:fs";
import path from "node:path";
import { ipcMain } from "electron";
import { parse as parseYaml } from "yaml";
import { packConfigSchema, loadConfig } from "@cf7-packer/core";
import type { IpcContext } from "./ipc-context.js";
import type { RawConfigResult, SaveConfigRequest, SaveConfigResult, PackerConfigSummary } from "../shared/ipc-types.js";

let configVersion = 0;
let debounceTimer: ReturnType<typeof setTimeout> | undefined;

/**
 * 所有对 pack.config.yaml 的写入都经过此函数。
 * 更新 lastConfigWriteAt 时间戳，供 watcher 做自写抑制（R1）。
 */
export function writeConfigToDisk(ctx: IpcContext, content: string): void {
  ctx.lastConfigWriteAt = Date.now();
  fs.writeFileSync(ctx.configPath, content, "utf8");
}

/**
 * 获取当前 configVersion 并自增（供 config-mutated 推送使用）。
 */
export function nextConfigVersion(): number {
  return ++configVersion;
}

export function registerWatchHandlers(ctx: IpcContext): void {
  // --- read-raw-config: 读取原始 YAML 文本 ---
  ipcMain.handle("cf7-packer:read-raw-config", (): RawConfigResult => {
    const content = fs.readFileSync(ctx.configPath, "utf8");
    configVersion++;
    return { content, version: configVersion };
  });

  // --- save-config: 校验 + 写盘 ---
  ipcMain.handle("cf7-packer:save-config", (_event, req: SaveConfigRequest): SaveConfigResult => {
    // 1. YAML 语法校验
    let raw: unknown;
    try {
      raw = parseYaml(req.content);
    } catch (err) {
      return {
        success: false,
        errors: [{ path: "", message: `YAML syntax error: ${err instanceof Error ? err.message : String(err)}` }]
      };
    }

    // 2. Zod schema 校验
    const result = packConfigSchema.safeParse(raw);
    if (!result.success) {
      const errors = result.error.issues.map(issue => ({
        path: issue.path.join("."),
        message: issue.message
      }));
      return { success: false, errors };
    }

    // 3. 写盘（自写抑制：更新时间戳）
    writeConfigToDisk(ctx, req.content);
    configVersion++;
    return { success: true };
  });

  // --- 目录级 watcher（R7: 原子保存安全 + R12: filename=null 兜底）---
  const configDir = path.dirname(ctx.configPath);
  const configBasename = path.basename(ctx.configPath);
  let lastKnownMtime = 0;

  try {
    lastKnownMtime = fs.statSync(ctx.configPath).mtimeMs;
  } catch {
    // 文件不存在时从 0 开始
  }

  try {
    const watcher = fs.watch(configDir, { persistent: false }, (_eventType, filename) => {
      // R7: 监听父目录，按 basename 过滤
      // R12: filename 可能为 null（某些平台），此时不排除，继续检查
      if (filename !== null && filename !== configBasename) return;

      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        // R1: 自写抑制——500ms 窗口内视为自己的写入
        if (Date.now() - ctx.lastConfigWriteAt < 500) return;

        // R12: 检查文件 mtime 是否真的变化（filename=null 兜底 + 去重）
        try {
          const currentMtime = fs.statSync(ctx.configPath).mtimeMs;
          if (currentMtime === lastKnownMtime) return;
          lastKnownMtime = currentMtime;
        } catch {
          return; // 文件不存在/不可读，不触发
        }

        configVersion++;
        ctx.sendToRenderer("cf7-packer:config-changed", { version: configVersion });
      }, 300);
    });

    ctx.configWatcher = watcher;
  } catch {
    // fs.watch 失败（权限/平台问题），降级为手动重载
  }
}

export function stopWatchHandlers(ctx: IpcContext): void {
  clearTimeout(debounceTimer);
  ctx.configWatcher?.close();
  ctx.configWatcher = undefined;
}
