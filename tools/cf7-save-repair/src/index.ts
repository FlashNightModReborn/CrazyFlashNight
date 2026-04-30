#!/usr/bin/env -S npx tsx
// CF7 Save Repair CLI
//
// 用法:
//   npm run scan -- <save.json> --project-root <dir>          # 默认 dry-run
//   npm run scan -- <save.json> --project-root <dir> --apply  # 真改文件
//
// dry-run 默认输出 markdown 报告到 stdout + .repair-report.md 旁路文件。
// --apply 时:
//   1. 备份原档到 <save_dir>/.repair-backups/<slot>/<ts>.broken.json
//   2. 在内存修复 + bump lastSaved (INV-1)
//   3. 原子写回原路径 (.tmp → rename)
//   4. 写 audit log .repair.log

import { readFileSync, writeFileSync, mkdirSync, existsSync, renameSync, unlinkSync } from 'node:fs';
import { dirname, join, basename } from 'node:path';
import { loadDict } from './dict-loader.js';
import { planRepair, applyRepair } from './repair.js';
import { renderMarkdown, renderJson } from './report.js';

interface CliArgs {
  savePath: string;
  projectRoot: string;
  apply: boolean;
  json: boolean;
}

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = {
    savePath: '',
    projectRoot: '',
    apply: false,
    json: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i]!;
    if (a === '--project-root') args.projectRoot = argv[++i] ?? '';
    else if (a === '--apply') args.apply = true;
    else if (a === '--json') args.json = true;
    else if (a === '-h' || a === '--help') {
      printUsage();
      process.exit(0);
    } else if (!a.startsWith('-') && !args.savePath) {
      args.savePath = a;
    }
  }
  if (!args.savePath || !args.projectRoot) {
    printUsage();
    process.exit(1);
  }
  return args;
}

function printUsage(): void {
  console.error(
    [
      'cf7-save-repair <save.json> --project-root <dir> [--apply] [--json]',
      '',
      '默认 dry-run，扫描 + 输出 markdown 报告。',
      '--apply 真改文件（备份原档到 .repair-backups/{slot}/，原子写回，bump lastSaved）。',
      '--json  输出 JSON 报告（不影响 --apply）。',
    ].join('\n'),
  );
}

function pad2(n: number): string { return String(n).padStart(2, '0'); }
function tsForFilename(d: Date = new Date()): string {
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
    + `T${pad2(d.getHours())}-${pad2(d.getMinutes())}-${pad2(d.getSeconds())}`;
}

function main(): void {
  const args = parseArgs(process.argv.slice(2));

  const dict = loadDict(args.projectRoot);
  const raw = readFileSync(args.savePath, 'utf8');
  const snapshot = JSON.parse(raw);

  const plan = planRepair(snapshot, dict);

  if (!args.apply) {
    if (args.json) {
      process.stdout.write(JSON.stringify(renderJson(plan), null, 2) + '\n');
    } else {
      const md = renderMarkdown(plan);
      process.stdout.write(md + '\n');
      const reportPath = args.savePath + '.repair-report.md';
      writeFileSync(reportPath, md, 'utf8');
      console.error(`\n[dry-run] 报告写入: ${reportPath}`);
    }
    return;
  }

  // --apply 路径
  const saveDir = dirname(args.savePath);
  const slot = basename(args.savePath, '.json');
  const ts = tsForFilename();
  const backupDir = join(saveDir, '.repair-backups', slot);
  mkdirSync(backupDir, { recursive: true });

  // 1. 备份原档
  const brokenPath = join(backupDir, `${ts}.broken.json`);
  writeFileSync(brokenPath, raw, 'utf8');

  // 2. 应用修复
  const applied = applyRepair(snapshot, plan);

  // 3. 原子写回 (Windows: renameSync 不能覆盖 → 先 unlink)
  const tmpPath = args.savePath + '.tmp';
  writeFileSync(tmpPath, JSON.stringify(snapshot), 'utf8');
  if (existsSync(args.savePath)) {
    try { unlinkSync(args.savePath); } catch { /* 防病毒锁档时回退由 renameSync 抛 */ }
  }
  renameSync(tmpPath, args.savePath);

  // 4. audit log
  const auditPath = join(backupDir, `${ts}.repair.log`);
  const md = renderMarkdown(plan, applied);
  writeFileSync(auditPath, md, 'utf8');

  if (args.json) {
    process.stdout.write(JSON.stringify(renderJson(plan, applied), null, 2) + '\n');
  } else {
    process.stdout.write(md + '\n');
    console.error(`\n[apply] 备份: ${brokenPath}`);
    console.error(`[apply] audit: ${auditPath}`);
    console.error(`[apply] 已写回: ${args.savePath}`);
  }
}

main();
