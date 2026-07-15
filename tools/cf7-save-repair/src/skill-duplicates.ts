// 重复技能行修复核心。
//
// 该修复只面向 launcher JSON shadow 的 mydata["5"] 技能表：
// - 扫描永不改动输入；
// - 每个重复 skillKey 必须由操作者显式选定唯一保留行；
// - 其余重复行原位清成标准空行，不 splice、不重排；
// - apply 前后都校验计划绑定的行，防止对过期报告施工。

import { bumpLastSaved } from './timestamp.js';

export const EMPTY_SKILL_ROW: readonly [string, number, boolean, string, boolean] = [
  '',
  0,
  false,
  '',
  true,
];

export interface DuplicateSkillGroup {
  skillKey: string;
  rowIndices: number[];
  rows: unknown[][];
}

export interface DuplicateSkillScan {
  tableLength: number;
  groups: DuplicateSkillGroup[];
}

export interface DuplicateSkillRemoval {
  skillKey: string;
  keepRowIndex: number;
  expectedKeepRow: unknown[];
  clearRowIndex: number;
  expectedRow: unknown[];
}

export interface DuplicateSkillRepairPlan {
  tableLength: number;
  groups: DuplicateSkillGroup[];
  removals: DuplicateSkillRemoval[];
}

export interface DuplicateSkillApplyResult {
  clearedRows: number;
  keptRows: number[];
  bumpedLastSaved: string | null;
}

function requireSkillTable(snapshot: unknown): unknown[] {
  if (!snapshot || typeof snapshot !== 'object') {
    throw new Error('invalid_snapshot: root must be an object');
  }
  const table = (snapshot as Record<string, unknown>)['5'];
  if (!Array.isArray(table)) {
    throw new Error('invalid_snapshot: mydata["5"] must be an array');
  }
  return table;
}

function cloneRow(row: unknown[]): unknown[] {
  return row.map((value) => {
    if (value === null || typeof value !== 'object') return value;
    return JSON.parse(JSON.stringify(value)) as unknown;
  });
}

function sameRow(actual: unknown[], expected: unknown[]): boolean {
  return JSON.stringify(actual) === JSON.stringify(expected);
}

export function scanDuplicateSkills(snapshot: unknown): DuplicateSkillScan {
  const table = requireSkillTable(snapshot);
  const byKey = new Map<string, { indices: number[]; rows: unknown[][] }>();

  for (let index = 0; index < table.length; index++) {
    const row = table[index];
    if (!Array.isArray(row)) continue;
    const skillKey = row[0];
    if (typeof skillKey !== 'string' || skillKey.length === 0) continue;

    let bucket = byKey.get(skillKey);
    if (!bucket) {
      bucket = { indices: [], rows: [] };
      byKey.set(skillKey, bucket);
    }
    bucket.indices.push(index);
    bucket.rows.push(cloneRow(row));
  }

  const groups: DuplicateSkillGroup[] = [];
  for (const [skillKey, bucket] of byKey) {
    if (bucket.indices.length < 2) continue;
    groups.push({
      skillKey,
      rowIndices: [...bucket.indices],
      rows: bucket.rows.map(cloneRow),
    });
  }
  groups.sort((a, b) => a.rowIndices[0]! - b.rowIndices[0]!);

  return { tableLength: table.length, groups };
}

export function planDuplicateSkillRepair(
  snapshot: unknown,
  keepRowIndices: readonly number[],
): DuplicateSkillRepairPlan {
  const scan = scanDuplicateSkills(snapshot);
  const selected = new Set<number>();
  for (const index of keepRowIndices) {
    if (!Number.isInteger(index) || index < 0) {
      throw new Error(`invalid_keep_row: ${String(index)}`);
    }
    if (selected.has(index)) {
      throw new Error(`duplicate_keep_row: ${index}`);
    }
    selected.add(index);
  }

  const validDuplicateRows = new Set<number>();
  for (const group of scan.groups) {
    for (const index of group.rowIndices) validDuplicateRows.add(index);
  }
  for (const index of selected) {
    if (!validDuplicateRows.has(index)) {
      throw new Error(`keep_row_not_duplicate: ${index}`);
    }
  }

  const removals: DuplicateSkillRemoval[] = [];
  for (const group of scan.groups) {
    const kept = group.rowIndices.filter((index) => selected.has(index));
    if (kept.length !== 1) {
      throw new Error(
        `keep_row_required: skill=${JSON.stringify(group.skillKey)} rows=${group.rowIndices.join(',')}`,
      );
    }
    const keepRowIndex = kept[0]!;
    const keepGroupIndex = group.rowIndices.indexOf(keepRowIndex);
    for (let i = 0; i < group.rowIndices.length; i++) {
      const clearRowIndex = group.rowIndices[i]!;
      if (clearRowIndex === keepRowIndex) continue;
      removals.push({
        skillKey: group.skillKey,
        keepRowIndex,
        expectedKeepRow: cloneRow(group.rows[keepGroupIndex]!),
        clearRowIndex,
        expectedRow: cloneRow(group.rows[i]!),
      });
    }
  }

  return {
    tableLength: scan.tableLength,
    groups: scan.groups,
    removals,
  };
}

export function applyDuplicateSkillRepair(
  snapshot: unknown,
  plan: DuplicateSkillRepairPlan,
  now: Date = new Date(),
): DuplicateSkillApplyResult {
  const table = requireSkillTable(snapshot);
  if (table.length !== plan.tableLength) {
    throw new Error(`stale_plan: skill table length changed (${plan.tableLength} -> ${table.length})`);
  }

  for (const removal of plan.removals) {
    const actual = table[removal.clearRowIndex];
    if (!Array.isArray(actual) || !sameRow(actual, removal.expectedRow)) {
      throw new Error(`stale_plan: row ${removal.clearRowIndex} changed`);
    }
    const kept = table[removal.keepRowIndex];
    if (!Array.isArray(kept) || kept[0] !== removal.skillKey
      || !sameRow(kept, removal.expectedKeepRow)) {
      throw new Error(`stale_plan: kept row ${removal.keepRowIndex} changed`);
    }
  }

  for (const removal of plan.removals) {
    table[removal.clearRowIndex] = [...EMPTY_SKILL_ROW];
  }

  const bumped = plan.removals.length > 0
    ? bumpLastSaved(snapshot as Record<string, unknown>, now)
    : null;

  const keptRows = [...new Set(plan.removals.map((item) => item.keepRowIndex))]
    .sort((a, b) => a - b);
  return {
    clearedRows: plan.removals.length,
    keptRows,
    bumpedLastSaved: bumped,
  };
}
