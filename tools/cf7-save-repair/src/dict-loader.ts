// 同源 dict 消费端：直接读 launcher/data/save_repair_dict.json。
// 与 launcher C# 端 RepairDictionary.cs（C2 实施）共用同一份 JSON。
// 由 tools/cf7-save-repair-dict-build 生成，不要手改。

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { FieldKind } from './layering.js';

/**
 * inventory.装备栏 下的固定 11 个槽位 key. AS2 强约定 (DressupInitializer.equipmentKeys),
 * 不会随 dict-build 工具变动, 直接硬编码 (与 launcher/src/Save/RepairDictionary.cs:EquipmentSlots
 * 同源, 双向同步).
 */
export const EQUIPMENT_SLOTS: readonly string[] = [
  '头部装备', '上装装备', '手部装备', '下装装备', '脚部装备', '颈部装备',
  '长枪', '手枪', '手枪2', '刀', '手雷',
];

export interface SaveRepairDict {
  schemaVersion: number;
  generated: {
    at: string;
    tool?: string;
    sourceFiles?: string[];
  };
  items: string[];
  mods: string[];
  enemies: string[];
  hairstyles: string[];
  skills: string[];
  taskChains: string[];
  stages: string[];
}

export function loadDict(projectRoot: string): SaveRepairDict {
  const path = join(projectRoot, 'launcher', 'data', 'save_repair_dict.json');
  const raw = readFileSync(path, 'utf8');
  const dict = JSON.parse(raw) as SaveRepairDict;
  if (!Array.isArray(dict.items) || !Array.isArray(dict.skills)) {
    throw new Error(`save_repair_dict.json malformed: ${path}`);
  }
  return dict;
}

export function dictBucket(dict: SaveRepairDict, kind: FieldKind): string[] {
  switch (kind) {
    case 'item':           return dict.items;
    case 'mod':            return dict.mods;
    case 'enemy':          return dict.enemies;
    case 'skill':          return dict.skills;
    case 'hairstyle':      return dict.hairstyles;
    case 'stage':          return dict.stages;
    case 'taskChain':      return dict.taskChains;
    // questId 当前与 stage 无独立桶；plan 中 questIds 字段未实装时回退用 stages.
    case 'questId':        return dict.stages;
    // 装备槽位 key: 硬编码字典 (本文件 EQUIPMENT_SLOTS), 不依赖 save_repair_dict.json
    case 'equipmentSlot':  return EQUIPMENT_SLOTS as string[];
    case 'free_text':
    case 'unknown':
    default:
      return [];
  }
}
