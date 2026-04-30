// 同源 dict 消费端：直接读 launcher/data/save_repair_dict.json。
// 与 launcher C# 端 RepairDictionary.cs（C2 实施）共用同一份 JSON。
// 由 tools/cf7-save-repair-dict-build 生成，不要手改。

import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import type { FieldKind } from './layering.js';

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
    case 'item':      return dict.items;
    case 'mod':       return dict.mods;
    case 'enemy':     return dict.enemies;
    case 'skill':     return dict.skills;
    case 'hairstyle': return dict.hairstyles;
    case 'stage':     return dict.stages;
    case 'taskChain': return dict.taskChains;
    // questId 当前与 stage 无独立桶；plan 中 questIds 字段未实装时回退用 stages.
    case 'questId':   return dict.stages;
    case 'free_text':
    case 'unknown':
    default:
      return [];
  }
}
