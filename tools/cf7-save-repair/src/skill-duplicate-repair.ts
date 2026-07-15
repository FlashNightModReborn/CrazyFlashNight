#!/usr/bin/env -S npx tsx
// 重复技能行的显式、带备份修复入口。

import {
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import {
  applyDuplicateSkillRepair,
  planDuplicateSkillRepair,
  scanDuplicateSkills,
} from './skill-duplicates.js';

const CONFIRM_PHRASE = 'DUPLICATE-SKILL-ROWS';

interface CliArgs {
  savePath: string;
  apply: boolean;
  json: boolean;
  keepRows: number[];
  confirm: string;
}

function usage(): string {
  return [
    'cf7-save-repair:skill-duplicates <save.json> [--json]',
    'cf7-save-repair:skill-duplicates <save.json> --apply --keep-row <index> [...]',
    `  --confirm ${CONFIRM_PHRASE}`,
    '',
    '默认只扫描。apply 时，每组重复 skillKey 必须恰好选择一个保留行。',
  ].join('\n');
}

function parseArgs(argv: string[]): CliArgs {
  const args: CliArgs = {
    savePath: '',
    apply: false,
    json: false,
    keepRows: [],
    confirm: '',
  };
  for (let i = 0; i < argv.length; i++) {
    const value = argv[i]!;
    if (value === '--apply') args.apply = true;
    else if (value === '--json') args.json = true;
    else if (value === '--keep-row') {
      const raw = argv[++i];
      const parsed = raw === undefined ? Number.NaN : Number(raw);
      if (!Number.isInteger(parsed) || parsed < 0) {
        throw new Error(`--keep-row requires a non-negative integer, got ${String(raw)}`);
      }
      args.keepRows.push(parsed);
    } else if (value === '--confirm') args.confirm = argv[++i] ?? '';
    else if (value === '-h' || value === '--help') {
      process.stdout.write(usage() + '\n');
      process.exit(0);
    } else if (!value.startsWith('-') && !args.savePath) args.savePath = value;
    else throw new Error(`unknown argument: ${value}`);
  }
  if (!args.savePath) throw new Error('save path is required');
  if (args.apply && args.confirm !== CONFIRM_PHRASE) {
    throw new Error(`--apply requires --confirm ${CONFIRM_PHRASE}`);
  }
  return args;
}

function pad2(value: number): string {
  return String(value).padStart(2, '0');
}

function pad3(value: number): string {
  return String(value).padStart(3, '0');
}

function timestamp(now: Date = new Date()): string {
  return `${now.getFullYear()}-${pad2(now.getMonth() + 1)}-${pad2(now.getDate())}`
    + `T${pad2(now.getHours())}-${pad2(now.getMinutes())}-${pad2(now.getSeconds())}-${pad3(now.getMilliseconds())}`;
}

function renderReport(savePath: string, scan: ReturnType<typeof scanDuplicateSkills>): string {
  const lines = [
    '# 重复技能行扫描',
    '',
    `- 存档：${savePath}`,
    `- 技能表长度：${scan.tableLength}`,
    `- 重复技能数：${scan.groups.length}`,
    '',
  ];
  for (const group of scan.groups) {
    lines.push(`## ${group.skillKey}`, '');
    for (let i = 0; i < group.rowIndices.length; i++) {
      lines.push(`- 行 ${group.rowIndices[i]}：\`${JSON.stringify(group.rows[i])}\``);
    }
    lines.push('');
  }
  if (scan.groups.length === 0) lines.push('未发现重复技能行。', '');
  lines.push(
    'apply 前请人工比较每行等级、类型和启用状态；工具不会自动合并字段。',
    '每组使用一个 `--keep-row <index>` 明确保留行，其余重复行将原位置空。',
  );
  return lines.join('\n');
}

function replaceFileSafely(path: string, nextPath: string, swapPath: string, expectedRaw: string): void {
  renameSync(path, swapPath);
  try {
    if (readFileSync(swapPath, 'utf8') !== expectedRaw) {
      throw new Error('stale_plan: save changed on disk before atomic replace');
    }
    renameSync(nextPath, path);
  } catch (error) {
    if (!existsSync(path) && existsSync(swapPath)) renameSync(swapPath, path);
    throw error;
  }
  unlinkSync(swapPath);
}

function main(): void {
  const args = parseArgs(process.argv.slice(2));
  const savePath = resolve(args.savePath);
  const raw = readFileSync(savePath, 'utf8');
  const snapshot = JSON.parse(raw) as unknown;
  const scan = scanDuplicateSkills(snapshot);

  if (!args.apply) {
    const report = renderReport(savePath, scan);
    if (args.json) process.stdout.write(JSON.stringify(scan, null, 2) + '\n');
    else process.stdout.write(report + '\n');
    writeFileSync(savePath + '.skill-duplicates.md', report, 'utf8');
    return;
  }

  const plan = planDuplicateSkillRepair(snapshot, args.keepRows);
  if (plan.removals.length === 0) {
    throw new Error('no duplicate skill rows to repair');
  }

  const saveDir = dirname(savePath);
  const slot = basename(savePath, '.json');
  const ts = timestamp();
  const backupDir = join(saveDir, '.repair-backups', slot);
  mkdirSync(backupDir, { recursive: true });
  const backupPath = join(backupDir, `${ts}.duplicate-skills.json`);
  const auditPath = join(backupDir, `${ts}.duplicate-skills.audit.json`);
  const nextPath = savePath + '.skill-repair.next';
  const swapPath = savePath + '.skill-repair.previous';
  if (existsSync(nextPath) || existsSync(swapPath)) {
    throw new Error('stale repair temporary file exists; inspect it before retrying');
  }
  writeFileSync(backupPath, raw, { encoding: 'utf8', flag: 'wx' });

  const result = applyDuplicateSkillRepair(snapshot, plan);
  writeFileSync(nextPath, JSON.stringify(snapshot), 'utf8');
  replaceFileSafely(savePath, nextPath, swapPath, raw);

  const audit = {
    savePath,
    backupPath,
    confirmation: CONFIRM_PHRASE,
    plan,
    result,
  };
  writeFileSync(auditPath, JSON.stringify(audit, null, 2), { encoding: 'utf8', flag: 'wx' });
  process.stdout.write(JSON.stringify({ success: true, backupPath, auditPath, result }, null, 2) + '\n');
}

try {
  main();
} catch (error) {
  process.stderr.write(`[skill-duplicate-repair] ${(error as Error).message}\n${usage()}\n`);
  process.exitCode = 1;
}
