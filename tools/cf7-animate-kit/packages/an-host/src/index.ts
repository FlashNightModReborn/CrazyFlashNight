/**
 * @cf7-animate-kit/an-host — the ONLY package that touches the real machine
 * (filesystem, child_process, environment). It executes the pure plans produced
 * by `@cf7-animate-kit/core`'s AnEnv. Every mutating op is plan-first
 * (apply:false by default) and backs up before overwriting/deleting.
 *
 * Clean-room: no networking, no hosts edits, no activation. Maintenance only.
 */
export { expandPattern } from './glob.js';
export { backupFile } from './backup.js';
export type { BackupResult } from './backup.js';
export {
  currentEnvSnapshot,
  discoverAnimate,
  discoverCepExtensionsDirs,
  collectDiagnostics,
} from './discover.js';
export type { AnimateInstall, Diagnostics } from './discover.js';
export {
  installPluginSwf,
  deletePluginSwf,
  clearCacheDir,
  applyJvmMemory,
  tightenSidebarFile,
  openFolder,
} from './maintenance.js';
export { runJsflJob, jobDirForCommands } from './jsfl-runner.js';
export type { JsflTrigger, RunJsflOptions, JsflRunResult } from './jsfl-runner.js';
export type {
  FileAction,
  FileChange,
  OpResult,
  JvmOpResult,
  ApplyOpts,
} from './maintenance.js';
