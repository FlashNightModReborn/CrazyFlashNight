import {
  currentEnvSnapshot,
  discoverAnimate,
  collectDiagnostics,
  installPluginSwf,
  deletePluginSwf,
  clearCacheDir,
  applyJvmMemory,
  tightenSidebarFile,
  openFolder,
  type AnimateInstall,
} from '@cf7-animate-kit/an-host';
import { parseArgs, printJson, printLine, fail } from '../lib/args.js';

const USAGE = `cf7-animate-kit an <subcommand>   (offline AN maintenance; plan-first, add --apply to commit)

  doctor                      Discover Animate installs + SharedObjects; print a clean diagnostic (no machine id).
  paths                       Print resolved WindowSWF / Commands / jvm.ini / cache paths per install.
  jvm <xmxMb> [--apply] [--dir <windowSwfDir>]      Set -Xmx (and -Xms=half) in jvm.ini.
  sidebar <fl_dictionary.dat> [--apply]             Tighten the Property Inspector sidebar.
  cache [--apply] [--dir <windowSwfDir>]            Clear the WindowSWF tmp cache.
  install <plugin.swf> [--apply] [--dir <windowSwfDir>]   Copy a plugin SWF into WindowSWF (backs up existing).
  delete <name-or-*.swf> [--apply] [--dir <windowSwfDir>] Delete matching plugin SWF(s) (backs up).
  open <windowswf|commands> [--dir <windowSwfDir>]  Open a folder in the file manager.

No --apply = dry run (prints the plan). This tool never edits hosts or contacts any server.`;

function installs(dir: string | undefined): AnimateInstall[] {
  const all = discoverAnimate(currentEnvSnapshot());
  if (dir) {
    const match = all.filter((i) => i.windowSwfDir === dir);
    return match.length ? match : all;
  }
  return all;
}

function dirFlag(flags: Record<string, string | boolean>): string | undefined {
  return typeof flags['dir'] === 'string' ? flags['dir'] : undefined;
}

export function runAn(argv: string[]): void {
  const sub = argv[0];
  const { _, flags } = parseArgs(argv.slice(1));
  const apply = flags['apply'] === true;

  switch (sub) {
    case 'doctor':
      return printJson(collectDiagnostics(currentEnvSnapshot()));

    case 'paths':
      return printJson(discoverAnimate(currentEnvSnapshot()));

    case 'jvm': {
      const xmx = Number.parseInt(String(_[0] ?? ''), 10);
      if (!Number.isInteger(xmx) || xmx <= 0) fail('usage: an jvm <xmxMb> [--apply] [--dir <windowSwfDir>]');
      const results = installs(dirFlag(flags)).map((i) => applyJvmMemory(i.jvmIniPath, xmx, { apply }));
      return printJson({ apply, results });
    }

    case 'sidebar': {
      const dat = _[0];
      if (!dat) fail('usage: an sidebar <fl_dictionary.dat> [--apply]');
      return printJson(tightenSidebarFile(dat, { apply }));
    }

    case 'cache': {
      const results = installs(dirFlag(flags)).map((i) => clearCacheDir(i.cacheDir, { apply }));
      return printJson({ apply, results });
    }

    case 'install': {
      const swf = _[0];
      if (!swf) fail('usage: an install <plugin.swf> [--apply] [--dir <windowSwfDir>]');
      const dirs = installs(dirFlag(flags)).map((i) => i.windowSwfDir);
      return printJson(installPluginSwf(swf, dirs, { apply }));
    }

    case 'delete': {
      const name = _[0];
      if (!name) fail('usage: an delete <name-or-*.swf> [--apply] [--dir <windowSwfDir>]');
      const dirs = installs(dirFlag(flags)).map((i) => i.windowSwfDir);
      return printJson(deletePluginSwf(name, dirs, { apply }));
    }

    case 'open': {
      const which = _[0];
      const target = installs(dirFlag(flags))[0];
      if (!target) fail('no Animate install discovered to open');
      const dir = which === 'commands' ? target.commandsDir : target.windowSwfDir;
      return printJson(openFolder(dir));
    }

    case undefined:
    case 'help':
    case '--help':
      return printLine(USAGE);

    default:
      fail(`unknown 'an' subcommand: ${sub}. Run 'an help'.`);
  }
}
