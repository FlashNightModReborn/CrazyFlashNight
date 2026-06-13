import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { authoring } from '@cf7-animate-kit/core';
import {
  currentEnvSnapshot,
  discoverAnimate,
  jobDirForCommands,
  runJsflJob,
  type JsflTrigger,
} from '@cf7-animate-kit/an-host';
import { parseArgs, printJson, printLine, fail } from '../lib/args.js';

const USAGE = `cf7-animate-kit art <subcommand>

Headless XFL helpers (no Animate required):
  linkage-scan <DOMDocument.xml>           List symbols/media with AS linkage.
  lint <DOMDocument.xml> [--naming <re>]   Lint linkage (dup ids, exported-without-id; optional naming).
  dup-scan <xflDir>                        Find exact structural duplicate symbols under <xflDir>/LIBRARY.
  frame-extract <DOMDocument.xml|symbol.xml>   List named frame labels.

Drive the live document via the JSFL host (needs CS6 / Animate; mirrors the repo's compile chain):
  run <fn> [--args <json>] [--timeout 30] (--exe <AnimateExe> | --task <name>) [--dir <windowSwfDir>] [--jobdir <dir>] [--runner <path>]
                                           fn = ping|probe|scanLinkage|applyLinkage|listFrameLabels|exportSelected|publish
  setup-task --exe <AnimateExe> [--task AnimateKitJsflTask] [--out <file.ps1>]
                                           Generate a Register-ScheduledTask script (run it as admin to dodge UAC).`;

export function runArt(argv: string[]): void {
  const sub = argv[0];
  const { _, flags } = parseArgs(argv.slice(1));
  switch (sub) {
    case 'linkage-scan':
      return linkageScan(_[0]);
    case 'lint':
      return lint(_[0], flags);
    case 'dup-scan':
      return dupScan(_[0]);
    case 'frame-extract':
      return frameExtract(_[0]);
    case 'run':
      void runJsfl(_[0], flags).catch((e: unknown) => fail(String(e)));
      return;
    case 'setup-task':
      return setupTask(flags);
    case undefined:
    case 'help':
    case '--help':
      return printLine(USAGE);
    default:
      fail(`unknown 'art' subcommand: ${sub}. Run 'art help'.`);
  }
}

function defaultRunnerPath(): string {
  const here = path.dirname(url.fileURLToPath(import.meta.url)); // packages/cli/src/commands
  return path.resolve(here, '..', '..', '..', 'jsfl-host', 'host', 'cf7ak-runner.jsfl');
}

function resolveJobDir(flags: Record<string, string | boolean>): string {
  if (typeof flags['jobdir'] === 'string') return flags['jobdir'];
  const installs = discoverAnimate(currentEnvSnapshot());
  const dir = typeof flags['dir'] === 'string' ? flags['dir'] : undefined;
  const inst = dir ? installs.find((i) => i.windowSwfDir === dir) : installs[0];
  if (!inst) fail('no Animate install discovered; pass --jobdir <dir> explicitly');
  return jobDirForCommands(inst.commandsDir);
}

async function runJsfl(fn: string | undefined, flags: Record<string, string | boolean>): Promise<void> {
  if (!fn) fail('usage: art run <fn> (--exe <AnimateExe> | --task <name>) [--args <json>] [--timeout 30]');
  const args = typeof flags['args'] === 'string' ? JSON.parse(flags['args']) : undefined;
  const timeoutSeconds = typeof flags['timeout'] === 'string' ? Number.parseInt(flags['timeout'], 10) : 30;
  const jobDir = resolveJobDir(flags);
  const runnerPath = typeof flags['runner'] === 'string' ? flags['runner'] : defaultRunnerPath();

  let trigger: JsflTrigger;
  if (typeof flags['exe'] === 'string') {
    trigger = { kind: 'exe', exePath: flags['exe'], scriptPath: runnerPath };
  } else if (typeof flags['task'] === 'string') {
    trigger = { kind: 'task', taskName: flags['task'] };
  } else {
    fail('specify a trigger: --exe <AnimateExe> (direct launch) or --task <ScheduledTaskName>');
  }

  const res = await runJsflJob({ jobDir, fn, args, trigger, timeoutSeconds });
  printJson(res);
  if (!res.ok) process.exitCode = 2;
}

function setupTask(flags: Record<string, string | boolean>): void {
  const exe = typeof flags['exe'] === 'string' ? flags['exe'] : undefined;
  if (!exe) fail('usage: art setup-task --exe <AnimateExe> [--task AnimateKitJsflTask] [--out <file.ps1>]');
  const taskName = typeof flags['task'] === 'string' ? flags['task'] : 'AnimateKitJsflTask';
  const runnerPath = typeof flags['runner'] === 'string' ? flags['runner'] : defaultRunnerPath();
  const outPath = typeof flags['out'] === 'string' ? flags['out'] : path.resolve('register-animatekit-task.ps1');
  const ps = [
    '# Register a scheduled task that runs the cf7ak JSFL runner with RunLevel=Highest',
    '# (so the child process is already elevated and Animate is launched without a UAC prompt).',
    '# Run this script ONCE, as Administrator.',
    `$exe = '${exe.replace(/'/g, "''")}'`,
    `$runner = '${runnerPath.replace(/'/g, "''")}'`,
    `$action = New-ScheduledTaskAction -Execute $exe -Argument ('"' + $runner + '"')`,
    "$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest",
    "$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries",
    `Register-ScheduledTask -TaskName '${taskName}' -Action $action -Principal $principal -Settings $settings -Force`,
    `Write-Host "registered scheduled task '${taskName}'. Trigger headless jobs with: art run <fn> --task ${taskName}"`,
  ].join('\n');
  fs.writeFileSync(outPath, ps, 'utf8');
  printJson({
    wrote: path.resolve(outPath),
    taskName,
    next: `Run as admin:  powershell -ExecutionPolicy Bypass -File "${path.resolve(outPath)}"`,
    then: `Then:  npm run art -- run probe --task ${taskName}`,
  });
}

function linkageScan(file: string | undefined): void {
  if (!file) fail('usage: art linkage-scan <DOMDocument.xml>');
  const doc = authoring.parseXflDocument(fs.readFileSync(file, 'utf8'));
  const items = authoring.collectLinkageItems(doc);
  printJson({
    file: path.resolve(file),
    info: doc.info,
    symbolCount: doc.symbols.length,
    mediaCount: doc.media.length,
    exportedForAS: items.filter((i) => i.linkageExportForAS).length,
    withIdentifier: items.filter((i) => i.linkageIdentifier).length,
    items: items.filter((i) => i.linkageExportForAS || i.linkageIdentifier),
  });
}

function lint(file: string | undefined, flags: Record<string, string | boolean>): void {
  if (!file) fail('usage: art lint <DOMDocument.xml> [--naming <regex>]');
  const doc = authoring.parseXflDocument(fs.readFileSync(file, 'utf8'));
  const naming = typeof flags['naming'] === 'string' ? new RegExp(flags['naming']) : undefined;
  const findings = authoring.lintLinkage(
    authoring.collectLinkageItems(doc),
    naming ? { namingPattern: naming } : {},
  );
  const summary = authoring.summarizeLint(findings);
  printJson({ file: path.resolve(file), ...summary });
  if (summary.errors > 0) process.exitCode = 2;
}

function dupScan(dir: string | undefined): void {
  if (!dir) fail('usage: art dup-scan <xflDir>');
  const libDir = fs.existsSync(path.join(dir, 'LIBRARY')) ? path.join(dir, 'LIBRARY') : dir;
  const files = findXmlFiles(libDir);
  const items = files.map((f) => ({
    name: path.relative(dir, f).replace(/\\/g, '/'),
    key: authoring.canonicalizeSymbolXml(fs.readFileSync(f, 'utf8')),
  }));
  const clusters = authoring.clusterDuplicates(items);
  printJson({
    dir: path.resolve(dir),
    scanned: files.length,
    duplicateClusters: clusters.length,
    clusters: clusters.map((c) => ({ count: c.members.length, members: c.members })),
  });
}

function frameExtract(file: string | undefined): void {
  if (!file) fail('usage: art frame-extract <DOMDocument.xml|symbol.xml>');
  const labels = authoring.extractFrameLabels(fs.readFileSync(file, 'utf8'));
  printJson({ file: path.resolve(file), count: labels.length, labels });
}

function findXmlFiles(dir: string): string[] {
  const out: string[] = [];
  const walk = (d: string): void => {
    let entries: fs.Dirent[];
    try {
      entries = fs.readdirSync(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entries) {
      const full = path.join(d, e.name);
      if (e.isDirectory()) walk(full);
      else if (e.isFile() && e.name.toLowerCase().endsWith('.xml')) out.push(full);
    }
  };
  walk(dir);
  return out;
}
