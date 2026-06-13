import { dialog, ipcMain } from "electron";
import {
  currentEnvSnapshot,
  collectDiagnostics,
  installPluginSwf,
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
