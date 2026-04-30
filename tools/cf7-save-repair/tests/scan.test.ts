import { describe, it, expect } from 'vitest';
import { scan } from '../src/scan.js';

describe('scan', () => {
  it('空 snapshot → 0 items', () => {
    expect(scan({}).total).toBe(0);
    expect(scan({}).byLayer).toEqual({ L0: 0, L1: 0, L2: 0, L3: 0 });
  });

  it('数组中含 fffd 的字符串', () => {
    const s = { '5': [['黑�技能', 1, false, '', true]] };
    const r = scan(s);
    expect(r.total).toBe(1);
    expect(r.items[0]!.layer).toBe('L2');
    expect(r.items[0]!.kind).toBe('skill');
    expect(r.items[0]!.spot).toBe('value');
    expect(r.items[0]!.path).toBe('5.0.0');
  });

  it('object key 含 fffd', () => {
    const s = { tasks: { tasks_finished: { '某�任务': 1 } } };
    const r = scan(s);
    // key 一次 + value (1 不是字符串, 不会再算) → 共 1
    expect(r.total).toBe(1);
    expect(r.items[0]!.spot).toBe('key');
    expect(r.items[0]!.layer).toBe('L2');
  });

  it('多处 fffd', () => {
    const s = {
      lastSaved: '2026-04-�9 12:00:00',
      inventory: {
        装备栏: {
          上装装备: { name: '黑色�功夫装', value: { mods: [], level: 1 } },
        },
      },
      others: {
        物品来源缓存: {
          discoveredEnemies: ['黑铁会大叔', '某�敌人'],
        },
      },
    };
    const r = scan(s);
    expect(r.total).toBe(3);
    expect(r.byLayer.L0).toBe(1);
    expect(r.byLayer.L1).toBe(1);
    expect(r.byLayer.L3).toBe(1);
  });

  it('parent + parentKey 可用于回填', () => {
    const s = { '5': [['黑�', 1, false, '', true]] };
    const r = scan(s);
    const item = r.items[0]!;
    item.parent[item.parentKey as number] = '修好了';
    expect(s['5'][0]![0]).toBe('修好了');
  });
});
