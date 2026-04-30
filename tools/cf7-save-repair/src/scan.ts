// 扫描 save snapshot，定位所有含 U+FFFD 的字符串字段。
// 同时定位 object 的 key 含 fffd 的情况（key 是 byType / discoveredEnemies push 的值）。

import { classifyField, type Layer, type FieldKind, type FieldRule } from './layering.js';

export const FFFD = '�';

export interface CorruptionItem {
  /** JSONPath 用 '.' 拼接的路径，含数组索引：例如 "inventory.装备栏.上装装备.value.mods.0" */
  path: string;
  /** 原始 path 段（含数字索引） */
  pathSegments: (string | number)[];
  layer: Layer;
  kind: FieldKind;
  /** 完整的 layering 规则，apply 时用其 dropMode */
  rule: FieldRule;
  /** 是 'key' 表示 object 的某个 key 含 fffd（要重命名/删除整个 entry）；'value' 表示字符串 value 含 fffd */
  spot: 'key' | 'value';
  /** 含 fffd 的原始字符串 */
  brokenString: string;
  /** 在原对象中定位的父对象（修复时通过 parent + indexOrKey 操作） */
  parent: any;
  /** 父中的索引或 key（pathSegments 的最后一段） */
  parentKey: string | number;
}

export interface ScanReport {
  total: number;
  byLayer: Record<Layer, number>;
  items: CorruptionItem[];
}

export function scan(snapshot: any): ScanReport {
  const items: CorruptionItem[] = [];
  walk(snapshot, [], snapshot, '', items);

  const byLayer = { L0: 0, L1: 0, L2: 0, L3: 0 } as Record<Layer, number>;
  for (const it of items) byLayer[it.layer]++;

  return { total: items.length, byLayer, items };
}

function walk(
  node: any,
  path: (string | number)[],
  parent: any,
  parentKey: string | number,
  out: CorruptionItem[],
): void {
  if (node === null || node === undefined) return;

  if (typeof node === 'string') {
    if (node.includes(FFFD)) {
      const rule = classifyField(path);
      out.push({
        path: path.map(String).join('.'),
        pathSegments: path,
        layer: rule.layer,
        kind: rule.kind,
        rule,
        spot: 'value',
        brokenString: node,
        parent,
        parentKey,
      });
    }
    return;
  }

  if (Array.isArray(node)) {
    for (let i = 0; i < node.length; i++) {
      walk(node[i], [...path, i], node, i, out);
    }
    return;
  }

  if (typeof node === 'object') {
    for (const key of Object.keys(node)) {
      // key 自身可能含 fffd（byType[key] / discoveredEnemies 等不会以 key 形式出现，
      // 但 tasks_finished[key]、击杀统计.byType[key]、collection[key] 都会）
      if (key.includes(FFFD)) {
        const childPath = [...path, key];
        const rule = classifyField(childPath);
        out.push({
          path: childPath.map(String).join('.'),
          pathSegments: childPath,
          layer: rule.layer,
          kind: rule.kind,
          rule,
          spot: 'key',
          brokenString: key,
          parent: node,
          parentKey: key,
        });
      }
      walk(node[key], [...path, key], node, key, out);
    }
    return;
  }
}
