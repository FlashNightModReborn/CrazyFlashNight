import { describe, expect, it } from 'vitest';
import {
  EMPTY_SKILL_ROW,
  applyDuplicateSkillRepair,
  planDuplicateSkillRepair,
  scanDuplicateSkills,
} from '../src/skill-duplicates.js';

function fixture(): any {
  return {
    version: '3.0',
    lastSaved: '2026-07-15 01:02:03',
    '4': ['', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '闪现'],
    '5': [
      ['闪现', 1, false, '武术', true],
      ['空翻踢', 3, true, '武术', true],
      ['闪现', 4, true, '武术', true],
      ['', 0, false, '', true],
      ['空翻踢', 2, false, '武术', false],
    ],
  };
}

describe('duplicate skill row repair', () => {
  it('scans every duplicate group without mutating the snapshot', () => {
    const snapshot = fixture();
    const before = JSON.stringify(snapshot);
    const scan = scanDuplicateSkills(snapshot);
    expect(scan.tableLength).toBe(5);
    expect(scan.groups.map((group) => [group.skillKey, group.rowIndices])).toEqual([
      ['闪现', [0, 2]],
      ['空翻踢', [1, 4]],
    ]);
    expect(JSON.stringify(snapshot)).toBe(before);
  });

  it('requires exactly one explicit keep row for every duplicate key', () => {
    const snapshot = fixture();
    expect(() => planDuplicateSkillRepair(snapshot, [2])).toThrow(/keep_row_required/);
    expect(() => planDuplicateSkillRepair(snapshot, [2, 1, 3])).toThrow(/keep_row_not_duplicate/);
    expect(() => planDuplicateSkillRepair(snapshot, [2, 2, 1])).toThrow(/duplicate_keep_row/);
  });

  it('clears only rejected duplicate rows in place and bumps lastSaved', () => {
    const snapshot = fixture();
    const table = snapshot['5'];
    const rootSlotsBefore = JSON.stringify(snapshot['4']);
    const plan = planDuplicateSkillRepair(snapshot, [2, 1]);
    const result = applyDuplicateSkillRepair(snapshot, plan, new Date(2026, 6, 16, 12, 34, 56));

    expect(snapshot['5']).toBe(table);
    expect(snapshot['5']).toHaveLength(5);
    expect(snapshot['5'][0]).toEqual([...EMPTY_SKILL_ROW]);
    expect(snapshot['5'][2]).toEqual(['闪现', 4, true, '武术', true]);
    expect(snapshot['5'][1]).toEqual(['空翻踢', 3, true, '武术', true]);
    expect(snapshot['5'][4]).toEqual([...EMPTY_SKILL_ROW]);
    expect(JSON.stringify(snapshot['4'])).toBe(rootSlotsBefore);
    expect(snapshot.lastSaved).toBe('2026-07-16 12:34:56');
    expect(result).toEqual({
      clearedRows: 2,
      keptRows: [1, 2],
      bumpedLastSaved: '2026-07-16 12:34:56',
    });
  });

  it('rejects an apply plan after any bound row changes', () => {
    const snapshot = fixture();
    const plan = planDuplicateSkillRepair(snapshot, [2, 1]);
    snapshot['5'][0][1] = 99;
    expect(() => applyDuplicateSkillRepair(snapshot, plan)).toThrow(/stale_plan/);
  });

  it('binds the explicitly kept row as well as rows being cleared', () => {
    const snapshot = fixture();
    const plan = planDuplicateSkillRepair(snapshot, [2, 1]);
    snapshot['5'][2][1] = 99;
    expect(() => applyDuplicateSkillRepair(snapshot, plan)).toThrow(/kept row 2 changed/);
    expect(snapshot['5'][0]).toEqual(['闪现', 1, false, '武术', true]);
  });

  it('rejects malformed skill tables', () => {
    expect(() => scanDuplicateSkills({ '5': {} })).toThrow(/must be an array/);
    expect(() => scanDuplicateSkills(null)).toThrow(/root must be an object/);
  });
});
