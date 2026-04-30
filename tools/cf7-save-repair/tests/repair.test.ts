import { describe, it, expect } from 'vitest';
import { planRepair, applyRepair, PLACEHOLDER } from '../src/repair.js';
import type { SaveRepairDict } from '../src/dict-loader.js';
import { packTimestamp } from '../src/timestamp.js';

const baseDict: SaveRepairDict = {
  schemaVersion: 1,
  generated: { at: '2026-01-01T00:00:00Z' },
  items: ['黑色功夫装', '咖啡色多包裤', '棕色皮鞋'],
  mods: ['攻击+5'],
  enemies: ['黑铁会大叔', '军阀步兵'],
  hairstyles: ['发型-男式-黑暴走头'],
  skills: ['基础攻击', '空翻踢', '强化拳'],
  taskChains: ['主线'],
  stages: ['第一关', '第二关'],
};

function freshSnapshot(): any {
  return {
    version: '3.0',
    lastSaved: '2026-04-15 15:03:28',
    '0': ['玩家A', '男', 1000, 1, 0, 175, 0, null, 1000, 0, [], 0, [], ''],
    '1': ['发型-男式-黑暴走头'],
    '5': [
      ['基础攻击', 1, true, '', true],
      ['空翻踢', 1, false, '', true],
    ],
    inventory: {
      装备栏: {
        上装装备: { name: '黑色功夫装', value: { mods: [], level: 1 } },
        下装装备: { name: '咖啡色多包裤', value: { mods: [], level: 1 } },
      },
      背包: {},
    },
    tasks: { tasks_finished: {}, task_chains_progress: { 主线: 0 } },
    others: {
      设置: { jukeboxPlayMode: 'singleLoop' },
      击杀统计: { total: 0, byType: {} },
      物品来源缓存: { discoveredStages: [], discoveredEnemies: [], discoveredQuests: [] },
    },
    collection: { 材料: {}, 情报: {} },
  };
}

describe('planRepair → applyRepair 集成', () => {
  it('L1 单候选字典命中 → fix_value', () => {
    const s = freshSnapshot();
    s.inventory.装备栏.上装装备.name = '黑色�夫装'; // 1 fffd 替换 1 char (5 chars)
    const plan = planRepair(s, baseDict);
    expect(plan.scan.total).toBe(1);
    expect(plan.decisions[0]!.action.kind).toBe('fix_value');

    const before = s.lastSaved;
    const r = applyRepair(s, plan);
    expect(r.applied).toBe(1);
    expect(r.bumpedLastSaved).not.toBeNull();
    expect(s.inventory.装备栏.上装装备.name).toBe('黑色功夫装');
    expect(s.lastSaved).not.toBe(before);
    // 格式 yyyy-MM-dd HH:mm:ss
    expect(s.lastSaved).toMatch(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
  });

  it('L2 技能 → 命中即修', () => {
    const s = freshSnapshot();
    s['5'][0][0] = '基础�击';
    const plan = planRepair(s, baseDict);
    expect(plan.decisions[0]!.action.kind).toBe('fix_value');
    applyRepair(s, plan);
    expect(s['5'][0][0]).toBe('基础攻击');
  });

  it('L1 字典不命中 → preserve placeholder', () => {
    const s = freshSnapshot();
    s.inventory.装备栏.上装装备.name = '完全�生�词';  // 不可还原
    const plan = planRepair(s, baseDict);
    expect(plan.decisions[0]!.action.kind).toBe('preserve_placeholder');
    applyRepair(s, plan);
    expect(s.inventory.装备栏.上装装备.name).toBe(PLACEHOLDER);
  });

  it('L2 技能名字典不命中 → clear_value (固定 tuple 槽位置空)', () => {
    const s = freshSnapshot();
    s['5'][0][0] = '完全�陌生�技能';
    const plan = planRepair(s, baseDict);
    expect(plan.decisions[0]!.action.kind).toBe('clear_value');
    applyRepair(s, plan);
    // tuple 形状保留，name 清空
    expect(s['5'][0][0]).toBe('');
    expect(s['5'][0][1]).toBe(1);   // level 不动
    expect(s['5'][1][0]).toBe('空翻踢'); // 第二个 slot 不动
  });

  it('L3 discoveredEnemies → 静默丢弃数组项', () => {
    const s = freshSnapshot();
    s.others.物品来源缓存.discoveredEnemies = ['黑铁会大叔', '某�敌人'];
    const plan = planRepair(s, baseDict);
    expect(plan.decisions[0]!.item.layer).toBe('L3');
    applyRepair(s, plan);
    expect(s.others.物品来源缓存.discoveredEnemies).toEqual(['黑铁会大叔']);
  });

  it('L0 角色名 → manual_required', () => {
    const s = freshSnapshot();
    s['0'][0] = '玩家�';
    const plan = planRepair(s, baseDict);
    expect(plan.decisions[0]!.action.kind).toBe('manual_required');
    expect(plan.manualRequired).toBe(1);

    const r = applyRepair(s, plan);
    expect(r.skippedManual).toBe(1);
    expect(r.applied).toBe(0);
    // L0 manual 也算可修复任务的一部分；但既然有其他可修项就 bump，
    // 当前 case 没有其他可修项 → willBumpLastSaved=false
    expect(plan.willBumpLastSaved).toBe(false);
    expect(r.bumpedLastSaved).toBeNull();
  });

  it('击杀统计.byType 的 fffd key → rename 到候选 key', () => {
    const s = freshSnapshot();
    s.others.击杀统计.byType = { '黑铁会�叔': 5, '军阀步兵': 2 };
    const plan = planRepair(s, baseDict);
    expect(plan.decisions[0]!.action.kind).toBe('rename_key');
    applyRepair(s, plan);
    expect(s.others.击杀统计.byType['黑铁会大叔']).toBe(5);
    expect(s.others.击杀统计.byType['黑铁会�叔']).toBeUndefined();
  });

  it('自参考池: byType 的完好 key 帮助 discoveredEnemies 修复（同名匹配）', () => {
    const s = freshSnapshot();
    // byType 完整 key
    s.others.击杀统计.byType = { '黑铁会大叔': 5 };
    // discoveredEnemies 损坏
    s.others.物品来源缓存.discoveredEnemies = ['黑铁会�叔'];
    // dict 里也有它，但自参考池应让 source = self_ref
    const plan = planRepair(s, baseDict);
    const decision = plan.decisions.find((d) => d.item.path.startsWith('others.物品来源缓存'));
    expect(decision).toBeDefined();
    // L3 默认 drop，但若 high-confidence 候选存在仍 drop（L3 不修）
    expect(decision!.action.kind).toBe('drop_value');
    // 即便如此，self-ref pool 应该被构建
    // 用 enemy kind 字段（byType key）也走自参考
    s.others.击杀统计.byType['军阀步�'] = 1;
    const plan2 = planRepair(s, baseDict);
    const byTypeDecision = plan2.decisions.find((d) => d.item.spot === 'key');
    expect(byTypeDecision!.action.kind).toBe('rename_key');
  });

  it('多坏字段：混合分层 + lastSaved bump', () => {
    const s = freshSnapshot();
    s.inventory.装备栏.上装装备.name = '黑色�夫装';        // L1 单候选 (5 chars)
    s['5'][0][0] = '基础�击';                               // L2 单候选
    s.others.物品来源缓存.discoveredEnemies = ['某�'];     // L3 drop
    s['0'][0] = '玩家�';                                    // L0 manual

    const plan = planRepair(s, baseDict);
    expect(plan.scan.total).toBe(4);
    expect(plan.willBumpLastSaved).toBe(true);

    const before = s.lastSaved;
    const r = applyRepair(s, plan);
    expect(r.applied).toBe(2);    // L1 + L2 fix
    expect(r.drops).toBe(1);      // L3
    expect(r.skippedManual).toBe(1); // L0
    expect(s.lastSaved).not.toBe(before);
    // 字典序新值 > 老值
    expect(s.lastSaved > before).toBe(true);
  });

  it('多个 splice 同一数组：按 parentKey 降序应用，索引不漂移', () => {
    const s = freshSnapshot();
    // discoveredEnemies 多个非首位破损：scan 会按 walk 顺序 (0,1,2,3,4) 出 items，
    // 直接顺序 splice 会让 idx=2 的 splice 错误删掉原 idx=3。
    s.others.物品来源缓存.discoveredEnemies = [
      'OK1',                  // 0
      '坏�一',                // 1 ← drop
      'OK2',                  // 2
      '坏�二',                // 3 ← drop
      'OK3',                  // 4
      '坏�三',                // 5 ← drop
      'OK4',                  // 6
    ];
    const plan = planRepair(s, baseDict);
    expect(plan.scan.total).toBe(3);
    applyRepair(s, plan);
    expect(s.others.物品来源缓存.discoveredEnemies).toEqual(['OK1', 'OK2', 'OK3', 'OK4']);
  });

  it('packTimestamp 格式正确', () => {
    const ts = packTimestamp(new Date(2026, 3, 29, 12, 34, 56)); // month is 0-indexed
    expect(ts).toBe('2026-04-29 12:34:56');
  });
});
