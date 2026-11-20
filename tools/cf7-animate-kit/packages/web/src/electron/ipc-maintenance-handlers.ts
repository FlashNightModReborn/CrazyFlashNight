import { dialog, ipcMain } from "electron";
import { readdirSync } from "node:fs";
import {
  currentEnvSnapshot,
  collectDiagnostics,
  installPluginSwf,
  deletePluginSwf,
  clearCacheDir,
  applyJvmMemory,
  tightenSidebarFile,
  openFolder,
} from "@cf7-animate-kit/an-host";
import type { Diagnostics, OpResult, JvmOpResult } from "@cf7-animate-kit/an-host";
import type { IpcContext } from "./ipc-context.js";
import type {
  PickResult,
  InstallSwfRequest,
  DeleteSwfRequest,
  PluginDirectory,
  ClearCacheRequest,
  JvmMemoryRequest,
  TightenSidebarRequest,
  OpenFolderRequest,
} from "../shared/ipc-types.js";

function installAt(ctx: IpcContext, index: number) {
  const install = ctx.installs[index];
  if (!install) throw new Error(`安装项 #${index} 不存在，请先运行 “AN 体检”`);
  return install;
}

export function registerMaintenanceHandlers(ctx: IpcContext): void {
  function pluginDirectory(target: PluginDirectory): string {
    const dir = installAt(ctx, target.installIndex).windowSwfDir;
    if (dir !== target.windowSwfDir) throw new Error("安装目录已变更，请重新运行体检。");
    return dir;
  }

  function installedSwfs(dir: string): string[] {
    return readdirSync(dir, { withFileTypes: true })
      .filter(entry => entry.isFile() && entry.name.toLowerCase().endsWith(".swf"))
      .map(entry => entry.name)
      .sort((a, b) => a.localeCompare(b));
  }

  // --- AN doctor: discover installs + cache them for index-addressed ops ---
  ipcMain.handle("ankit:doctor", (): Diagnostics => {
    const diag = collectDiagnostics(currentEnvSnapshot());
    ctx.installs = diag.installs;
    return diag;
  });

  // --- file pickers ---
  ipcMain.handle("ankit:pick-swf", async (): Promise<PickResult> => {
    const win = ctx.getMainWindow();
    if (!win) return { canceled: true };
    const res = await dialog.showOpenDialog(win, {
      title: "选择插件 .swf",
      properties: ["openFile"],
      filters: [{ name: "Flash SWF", extensions: ["swf"] }],
    });
    if (res.canceled || res.filePaths.length === 0) return { canceled: true };
    return { canceled: false, path: res.filePaths[0]! };
  });

  ipcMain.handle("ankit:pick-dat", async (): Promise<PickResult> => {
    const win = ctx.getMainWindow();
    if (!win) return { canceled: true };
    const res = await dialog.showOpenDialog(win, {
      title: "选择侧边栏字典 .dat",
      properties: ["openFile"],
      filters: [
        { name: "Sidebar dictionary", extensions: ["dat"] },
        { name: "All files", extensions: ["*"] },
      ],
    });
    if (res.canceled || res.filePaths.length === 0) return { canceled: true };
    return { canceled: false, path: res.filePaths[0]! };
  });

  // --- install plugin .swf into a single install's WindowSWF dir ---
  ipcMain.handle("ankit:install-swf", (_e, req: InstallSwfRequest): OpResult => {
    const install = installAt(ctx, req.installIndex);
    return installPluginSwf(req.srcSwf, [install.windowSwfDir], { apply: req.apply });
  });

  ipcMain.handle("ankit:list-plugin-swfs", (_e, target: PluginDirectory) =>
    installedSwfs(pluginDirectory(target)));

  ipcMain.handle("ankit:delete-swf", (_e, req: DeleteSwfRequest): OpResult => {
    const dir = pluginDirectory(req);
    if (!installedSwfs(dir).includes(req.name)) {
      throw new Error("所选插件已不在当前目录，请重新运行体检。");
    }
    return deletePluginSwf(req.name, [dir], { apply: req.apply === true, exactName: true });
  });

  // --- clear WindowSWF tmp cache ---
  ipcMain.handle("ankit:clear-cache", (_e, req: ClearCacheRequest): OpResult => {
    const install = installAt(ctx, req.installIndex);
    return clearCacheDir(install.cacheDir, { apply: req.apply });
  });

  // --- set jvm.ini -Xmx memory ---
  ipcMain.handle("ankit:set-jvm-memory", (_e, req: JvmMemoryRequest): JvmOpResult => {
    const install = installAt(ctx, req.installIndex);
    return applyJvmMemory(install.jvmIniPath, req.xmxMb, { apply: req.apply });
  });

  // --- tighten sidebar dictionary (.dat chosen via picker) ---
  ipcMain.handle("ankit:tighten-sidebar", (_e, req: TightenSidebarRequest): OpResult => {
    return tightenSidebarFile(req.datPath, { apply: req.apply });
  });

  // --- open a folder in the OS file manager ---
  ipcMain.handle("ankit:open-folder", (_e, req: OpenFolderRequest): { ok: boolean; summary: string } => {
    const install = installAt(ctx, req.installIndex);
    const dir =
      req.kind === "windowSwf"
        ? install.windowSwfDir
        : req.kind === "commands"
          ? install.commandsDir
          : req.kind === "configuration"
            ? install.configurationDir
            : install.cacheDir;
    return openFolder(dir);
  });
}
