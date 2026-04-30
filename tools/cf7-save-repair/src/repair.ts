// 修复主流程：scan → 自参考池构建 → 候选匹配 → 应用 plan → bump lastSaved。

import { scan, type CorruptionItem, type ScanReport } from './scan.js';
import { findCandidates, type MatchCandidate } from './matcher.js';
import { dictBucket, type SaveRepairDict } from './dict-loader.js';
import { bumpLastSaved } from './timestamp.js';
import type { Layer, FieldKind } from './layering.js';

export type Action =
  | { kind: 'fix_value';  newValue: string; via: MatchCandidate }
  | { kind: 'rename_key'; newKey: string; via: MatchCandidate }
  /** 数组 splice 移除：用于 push-list (discoveredEnemies / mods 等) */
  | { kind: 'drop_value' }
  /** 把字段值清空（设为 ''）：用于固定形状 tuple 的槽位 (技能名 / 发型) */
  | { kind: 'clear_value' }
  /** 删除 object 的整条 entry：用于 byType[key] / tasks_finished[key] */
  | { kind: 'drop_key' }
  | { kind: 'preserve_placeholder'; placeholder: string }
  | { kind: 'manual_required' };

export const PLACEHOLDER = '[损坏 待修复]';

export interface ItemDecision {
  item: CorruptionItem;
  action: Action;
  candidates: MatchCandidate[];  // 决策时考察的全部候选（含未采用的）
}

export interface RepairPlan {
  scan: ScanReport;
  decisions: ItemDecision[];
  /** 修复后是否需要 bump lastSaved（即 decisions 中至少有一条非 manual_required 即 true） */
  willBumpLastSaved: boolean;
  /** 仍需人工介入的 item 数 */
  manualRequired: number;
}

export function planRepair(snapshot: any, dict: SaveRepairDict): RepairPlan {
  const sc = scan(snapshot);
  const selfRef = buildSelfReferencePool(snapshot);

  const decisions: ItemDecision[] = [];
  let manualRequired = 0;
  for (const item of sc.items) {
    const decision = decideOne(item, dict, selfRef);
    if (decision.action.kind === 'manual_required') manualRequired++;
    decisions.push(decision);
  }

  return {
    scan: sc,
    decisions,
    willBumpLastSaved: decisions.some((d) => d.action.kind !== 'manual_required'),
    manualRequired,
  };
}

function decideOne(
  item: CorruptionItem,
  dict: SaveRepairDict,
  selfRef: SelfReferencePool,
): ItemDecision {
  // 字典桶 + 自参考池
  const bucket = dictBucket(dict, item.kind);
  const ref = selfRef.byKind[item.kind] ?? [];
  const candidates = findCandidates(item.brokenString, bucket, ref);

  const top = candidates[0];
  const isHighConfidence =
    !!top && (top.source === 'self_ref' || top.source === 'dict_unique');

  // L0：永远阻塞
  if (item.layer === 'L0') {
    return { item, action: { kind: 'manual_required' }, candidates };
  }

  // L3：永远丢弃（即便有 dict_unique 命中也不修；候选只用于 report 透明化）
  if (item.layer === 'L3') {
    return applyFallback(item, candidates);
  }

  // L1 / L2：高置信度命中即修
  if (isHighConfidence) {
    if (item.spot === 'key')
      return { item, action: { kind: 'rename_key', newKey: top.value, via: top }, candidates };
    return { item, action: { kind: 'fix_value', newValue: top.value, via: top }, candidates };
  }

  // L1：多候选 → manual；0 候选 → 按 fallback（preserve / manual）
  if (item.layer === 'L1') {
    if (candidates.length > 1) {
      return { item, action: { kind: 'manual_required' }, candidates };
    }
    return applyFallback(item, candidates);
  }

  // L2：多/0 候选都按 fallback（默认 drop）
  return applyFallback(item, candidates);
}

function applyFallback(
  item: CorruptionItem,
  candidates: MatchCandidate[],
): ItemDecision {
  switch (item.rule.fallbackWhenDictMiss) {
    case 'manual':
      return { item, action: { kind: 'manual_required' }, candidates };
    case 'preserve':
      return {
        item,
        action: { kind: 'preserve_placeholder', placeholder: PLACEHOLDER },
        candidates,
      };
    case 'drop':
    default:
      return { item, action: dropAction(item), candidates };
  }
}

function dropAction(item: CorruptionItem): Action {
  if (item.spot === 'key') return { kind: 'drop_key' };
  // value drop 按 layering 规则的 dropMode 决定
  switch (item.rule.dropMode) {
    case 'clear':  return { kind: 'clear_value' };
    case 'key':    return { kind: 'drop_key' };
    case 'splice':
    default:       return { kind: 'drop_value' };
  }
}

/** 同存档自参考池：从未坏掉的字段聚合 string 备选，按 FieldKind 分桶。 */
interface SelfReferencePool {
  byKind: Partial<Record<FieldKind, string[]>>;
}

function buildSelfReferencePool(snapshot: any): SelfReferencePool {
  const byKind: Partial<Record<FieldKind, string[]>> = {};
  const push = (k: FieldKind, v: string) => {
    if (!v || v.includes('�')) return;
    (byKind[k] ??= []).push(v);
  };

  // 装备栏 name → item
  const equipSlots = snapshot?.inventory?.装备栏;
  if (equipSlots && typeof equipSlots === 'object') {
    for (const slot of Object.values(equipSlots)) {
      const name = (slot as any)?.name;
      if (typeof name === 'string') push('item', name);
    }
  }

  // 击杀统计.byType 的 key → enemy（已破的 key 自身不会被回收，但其他完好 key 是宝贵参考）
  const byType = snapshot?.others?.击杀统计?.byType;
  if (byType && typeof byType === 'object') {
    for (const k of Object.keys(byType)) push('enemy', k);
  }

  // 物品来源缓存.discoveredEnemies → enemy
  const discE = snapshot?.others?.物品来源缓存?.discoveredEnemies;
  if (Array.isArray(discE)) for (const v of discE) if (typeof v === 'string') push('enemy', v);

  // collection.材料 / 情报 keys → item
  for (const cat of ['材料', '情报']) {
    const obj = snapshot?.collection?.[cat];
    if (obj && typeof obj === 'object') {
      for (const k of Object.keys(obj)) push('item', k);
    }
  }

  return { byKind };
}

// ─────────────── apply ───────────────

export interface ApplyResult {
  applied: number;
  skippedManual: number;
  drops: number;
  preserves: number;
  bumpedLastSaved: string | null;
}

/** 在原 snapshot（可变）上应用 plan。返回统计。
 *
 * 重要：对同一数组的多个 splice 必须按 parentKey 降序执行，否则前一个 splice 会让
 * 后续的 parentKey 索引漂移。把所有 drop_value（数组父）放到最后，按 parentKey 降序处理；
 * 其他动作（fix_value / clear / drop_key / rename_key）不影响索引，正常顺序处理。
 */
export function applyRepair(snapshot: any, plan: RepairPlan, now: Date = new Date()): ApplyResult {
  let applied = 0,
    skippedManual = 0,
    drops = 0,
    preserves = 0;

  const decisions = [...plan.decisions];
  decisions.sort((a, b) => {
    const aSplice = a.action.kind === 'drop_value' && Array.isArray(a.item.parent);
    const bSplice = b.action.kind === 'drop_value' && Array.isArray(b.item.parent);
    if (aSplice !== bSplice) return aSplice ? 1 : -1; // splice 排到末尾
    if (aSplice && bSplice) {
      // 同一父数组按 parentKey 降序；不同父数组顺序无所谓
      const ak = a.item.parentKey as number;
      const bk = b.item.parentKey as number;
      return bk - ak;
    }
    return 0;
  });

  for (const d of decisions) {
    const { item, action } = d;
    switch (action.kind) {
      case 'manual_required':
        skippedManual++;
        break;
      case 'fix_value':
        setAt(item.parent, item.parentKey, action.newValue);
        applied++;
        break;
      case 'rename_key': {
        const old = item.parent[item.parentKey as string];
        delete item.parent[item.parentKey as string];
        item.parent[action.newKey] = old;
        applied++;
        break;
      }
      case 'preserve_placeholder':
        setAt(item.parent, item.parentKey, action.placeholder);
        preserves++;
        break;
      case 'drop_value':
        // 数组 vs 对象
        if (Array.isArray(item.parent)) {
          item.parent.splice(item.parentKey as number, 1);
        } else {
          delete item.parent[item.parentKey as string];
        }
        drops++;
        break;
      case 'clear_value':
        setAt(item.parent, item.parentKey, '');
        drops++;
        break;
      case 'drop_key':
        delete item.parent[item.parentKey as string];
        drops++;
        break;
    }
  }

  let bumped: string | null = null;
  if (plan.willBumpLastSaved) {
    bumped = bumpLastSaved(snapshot, now);
  }

  return { applied, skippedManual, drops, preserves, bumpedLastSaved: bumped };
}

function setAt(parent: any, key: string | number, value: string): void {
  if (Array.isArray(parent)) parent[key as number] = value;
  else parent[key as string] = value;
}
