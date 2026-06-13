import type { BrowserWindow } from "electron";
import type { AnimateInstall } from "@cf7-animate-kit/an-host";

/**
 * Shared IPC handler context. `main.ts` creates one instance; each register*
 * module reads from it. The install cache lets index-addressed maintenance ops
 * (installSwf / clearCache / setJvmMemory / openFolder) refer to the install
 * list last produced by `doctor()` without re-running discovery each call.
 */
export interface IpcContext {
  getMainWindow: () => BrowserWindow | null;
  /** Installs discovered by the most recent `doctor()` call (index-addressed). */
  installs: AnimateInstall[];
}
