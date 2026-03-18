import { dialog, ipcMain, shell } from "electron";
import fs from "node:fs";
import path from "node:path";
import {
  applyExcludeMutation,
  prepareExcludeAction,
  normalizeRepoRelativePath,
  isPathInsideRoot
} from "@cf7-packer/core";
import type { PackerLogEvent } from "@cf7-packer/core";
import type { ExcludeRequest, ExcludeResult } from "../shared/ipc-types.js";
import type { IpcContext } from "./ipc-context.js";

export function registerFileHandlers(ctx: IpcContext): void {
  ipcMain.handle("cf7-packer:open-file", async (_event, relativePath: string) => {
    const config = ctx.getConfig();
    const normalizedPath = normalizeRepoRelativePath(relativePath);
    const fullPath = path.resolve(config.source.repoRoot, normalizedPath);
    if (!isPathInsideRoot(config.source.repoRoot, fullPath)) return;
    if (fs.existsSync(fullPath)) await shell.openPath(fullPath);
  });

  ipcMain.handle("cf7-packer:reveal-file", async (_event, relativePath: string) => {
    const config = ctx.getConfig();
    const normalizedPath = normalizeRepoRelativePath(relativePath);
    const fullPath = path.resolve(config.source.repoRoot, normalizedPath);
    if (!isPathInsideRoot(config.source.repoRoot, fullPath)) return;
    if (fs.existsSync(fullPath)) shell.showItemInFolder(fullPath);
  });

  ipcMain.handle("cf7-packer:pick-output-dir", async (_event, currentPath?: string) => {
    const mainWindow = ctx.getMainWindow();
    if (!mainWindow) return { canceled: true };
    const result = await dialog.showOpenDialog(mainWindow, {
      defaultPath: currentPath ?? ctx.toolRoot,
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
    const isAllowed = [...ctx.knownOutputDirs].some(dir => isPathInsideRoot(dir, resolved));
    if (!isAllowed) return;
    if (fs.existsSync(resolved)) {
      const stats = fs.statSync(resolved);
      if (stats.isDirectory()) {
        await shell.openPath(resolved);
      } else {
        shell.showItemInFolder(resolved);
      }
    }
  });

  /**
   * 仅弹出确认对话框，不做路径校验和删除。
   * 实际的路径安全校验和删除逻辑在 cf7-packer:exclude-file handler 中通过 prepareExcludeAction 完成。
   */
  ipcMain.handle("cf7-packer:confirm-delete", async (_event, filePath: string, isDir: boolean): Promise<boolean> => {
    const mainWindow = ctx.getMainWindow();
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
      const config = ctx.getConfig();
      const yamlContent = fs.readFileSync(ctx.configPath, "utf8");
      const { content, result } = applyExcludeMutation(yamlContent, config, req);
      fs.writeFileSync(ctx.configPath, content, "utf8");

      const action = req.deleteFromDisk ? "删除并排除" : "排除";
      ctx.sendToRenderer("cf7-packer:log", {
        layer: result.layerName === "__global__" ? "global" : result.layerName,
        level: "info",
        message: result.alreadyPresent
          ? `${action}: ${result.normalizedPath} 已存在 exclude: "${result.pattern}"`
          : `${action}: ${result.normalizedPath} → exclude: "${result.pattern}"`
      } satisfies PackerLogEvent);

      if (req.deleteFromDisk) {
        const prepared = prepareExcludeAction(config.source.repoRoot, req.filePath, true);
        if (prepared.error) {
          return { success: false, pattern: result.pattern, layerName: result.layerName, error: prepared.error };
        }
        if (prepared.shouldDelete && fs.existsSync(prepared.fullPath)) {
          const stat = fs.statSync(prepared.fullPath);
          fs.rmSync(prepared.fullPath, { recursive: true, force: true });
          ctx.sendToRenderer("cf7-packer:log", {
            layer: result.layerName === "__global__" ? "global" : result.layerName,
            level: "warn",
            message: `已从磁盘删除: ${prepared.normalizedPath}${stat.isDirectory() ? " (目录)" : ""}`
          } satisfies PackerLogEvent);
        }
      }

      return { success: true, pattern: result.pattern, layerName: result.layerName };
    } catch (err) {
      ctx.sendToRenderer("cf7-packer:log", {
        layer: "system", level: "error",
        message: `排除操作失败: ${String(err)}`
      } satisfies PackerLogEvent);
      return { success: false, pattern: "", layerName: "", error: String(err) };
    }
  });
}
