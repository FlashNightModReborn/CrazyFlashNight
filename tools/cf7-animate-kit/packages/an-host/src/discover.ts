import fs from 'node:fs';
import os from 'node:os';
import { anEnv } from '@cf7-animate-kit/core';
import type { EnvSnapshot, AnimatePaths, MachineInfo } from '@cf7-animate-kit/core';
import { expandPattern } from './glob.js';

export interface AnimateInstall extends AnimatePaths {
  windowSwfExists: boolean;
  jvmIniExists: boolean;
  commandsExists: boolean;
}

/** Build an EnvSnapshot from the current process environment (no undefined assigned). */
export function currentEnvSnapshot(): EnvSnapshot {
  const snap: EnvSnapshot = { platform: process.platform };
  const appData = process.env['APPDATA'];
  const localAppData = process.env['LOCALAPPDATA'];
  const programFiles = process.env['ProgramFiles'];
  const programFilesX86 = process.env['ProgramFiles(x86)'];
  if (appData) snap.appData = appData;
  if (localAppData) snap.localAppData = localAppData;
  if (programFiles) snap.programFiles = programFiles;
  if (programFilesX86) snap.programFilesX86 = programFilesX86;
  snap.home = os.homedir();
  return snap;
}

/** Discover installed Adobe Animate `WindowSWF` directories and their sibling config paths. */
export function discoverAnimate(env: EnvSnapshot): AnimateInstall[] {
  const dirs = new Set<string>();
  for (const pattern of anEnv.windowSwfGlobs(env)) {
    for (const d of expandPattern(pattern)) dirs.add(d);
  }
  const installs: AnimateInstall[] = [];
  for (const windowSwfDir of dirs) {
    const paths = anEnv.pathsFromWindowSwf(windowSwfDir);
    installs.push({
      ...paths,
      windowSwfExists: fs.existsSync(windowSwfDir),
      jvmIniExists: fs.existsSync(paths.jvmIniPath),
      commandsExists: fs.existsSync(paths.commandsDir),
    });
  }
  return installs.sort((a, b) => a.windowSwfDir.localeCompare(b.windowSwfDir));
}

/** Existing CEP extensions directories (where the P4 panel installs). */
export function discoverCepExtensionsDirs(env: EnvSnapshot): string[] {
  return anEnv.cepExtensionsDirs(env).filter((d) => fs.existsSync(d));
}

export interface Diagnostics {
  machine: MachineInfo;
  installs: AnimateInstall[];
  sharedObjectsBase: string | null;
  sharedObjectsExists: boolean;
}

/** Collect a clean diagnostic report (NO machine id / MAC / activation). */
export function collectDiagnostics(env: EnvSnapshot): Diagnostics {
  const installs = discoverAnimate(env);
  const soBase = anEnv.sharedObjectsBase(env);
  const machine = anEnv.machineInfoSafe({
    platform: env.platform,
    osRelease: os.release(),
    nodeVersion: process.version,
    resolvedWindowSwf: installs.map((i) => i.windowSwfDir),
    cepExtensionsDirs: discoverCepExtensionsDirs(env),
    sharedObjectsBase: soBase,
  });
  return {
    machine,
    installs,
    sharedObjectsBase: soBase,
    sharedObjectsExists: soBase ? fs.existsSync(soBase) : false,
  };
}
