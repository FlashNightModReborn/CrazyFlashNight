// 字段层级规则（与 plan prancy-weaving-treasure.md 同步）
//
// L0：阻塞修复，必须人工介入
//   - $[0][0] 角色名（自由文本，无字典可对齐）
//   - $.lastSaved（时间戳）
// L1：字典对齐；命中即修，不命中保留占位 + 提示人工
//   - $.inventory.{背包,装备栏,药剂栏,仓库,战备箱}.*.name
//   - $.inventory.装备栏.*.value.mods[*]（mod 名）
// L2：字典对齐；命中即修，不命中静默丢弃（非关键引用）
//   - $.tasks.tasks_finished[<key>]
//   - $.tasks.task_chains_progress[<key>]（key 是 taskChain 名）
//   - $.others.击杀统计.byType[<key>]
//   - $[5][N][0] 技能名
//   - $[1][N] 发型/外观
//   - $.collection.{材料,情报}[<key>]
// L3：静默丢弃，下次玩自动重建
//   - $.others.物品来源缓存.{discoveredEnemies,discoveredQuests,discoveredStages}[N]
//   - $.others.物品来源缓存.completedChallengeQuests[N]
//   - $.others.设置.<键>（自由命名，无关 gameplay 状态）

export type Layer = 'L0' | 'L1' | 'L2' | 'L3';

/** 字段类型，用于决定查哪个 dict 桶。 */
export type FieldKind =
  | 'item'
  | 'mod'
  | 'enemy'
  | 'skill'
  | 'hairstyle'
  | 'stage'
  | 'taskChain'
  | 'questId'
  | 'free_text'    // 角色名等无字典字段
  | 'equipmentSlot'  // inventory.装备栏 槽位 key — 硬编码 11 项, 不进 save_repair_dict.json
  | 'unknown';

export interface FieldRule {
  layer: Layer;
  kind: FieldKind;
  /** 修复策略：drop = 静默丢弃；preserve = 占位（'[损坏 待修复]'）；manual = 阻塞 */
  fallbackWhenDictMiss: 'drop' | 'preserve' | 'manual';
  /**
   * drop 时的具体方式：
   *   splice = 从数组中移除元素（适合 discoveredEnemies 这类 push-list）
   *   clear  = 设为空串（适合 [5][N][0] 技能名 / [1][N] 发型 这类固定形状的 tuple 槽位）
   *   key    = 删除 object 的整个 entry（适合 byType[key] / tasks_finished[key]）
   * 不指定时按 spot 推断：spot=key 用 'key'，array 用 'splice'，object 用 'key'
   */
  dropMode?: 'splice' | 'clear' | 'key';
}

const RULES: Array<{ test: (path: string[]) => boolean; rule: FieldRule }> = [
  // L0
  { test: (p) => p.length === 2 && p[0] === '0' && p[1] === '0',
    rule: { layer: 'L0', kind: 'free_text', fallbackWhenDictMiss: 'manual' } },
  { test: (p) => p.length === 1 && p[0] === 'lastSaved',
    rule: { layer: 'L0', kind: 'free_text', fallbackWhenDictMiss: 'manual' } },

  // L1: inventory 物品名
  { test: (p) =>
      p.length === 4 &&
      p[0] === 'inventory' &&
      ['背包', '装备栏', '药剂栏', '仓库', '战备箱'].includes(p[1]) &&
      p[3] === 'name',
    rule: { layer: 'L1', kind: 'item', fallbackWhenDictMiss: 'preserve' } },
  // L1: equipment mod
  { test: (p) =>
      p.length >= 6 &&
      p[0] === 'inventory' &&
      ['背包', '装备栏', '药剂栏', '仓库', '战备箱'].includes(p[1]) &&
      p[3] === 'value' &&
      p[4] === 'mods',
    rule: { layer: 'L1', kind: 'mod', fallbackWhenDictMiss: 'preserve' } },

  // L1: 装备栏槽位 key（如 '颈部装备', '上装装备' 等）。AS2 强约定 11 个名称, 硬编码字典命中即
  // 自动 RenameKey（spot=key + dict_unique → policy.ts 走 RenameKey 路径）；命中不到才退 manual.
  { test: (p) =>
      p.length === 3 && p[0] === 'inventory' && p[1] === '装备栏',
    rule: { layer: 'L1', kind: 'equipmentSlot', fallbackWhenDictMiss: 'manual' } },

  // L2: tasks_finished[key]（key 即玩家完成的任务名/状态串；命中 questIds 才能确认，否则丢）
  { test: (p) => p.length >= 2 && p[0] === 'tasks' && p[1] === 'tasks_finished',
    rule: { layer: 'L2', kind: 'questId', fallbackWhenDictMiss: 'drop' } },
  { test: (p) => p.length >= 2 && p[0] === 'tasks' && p[1] === 'task_chains_progress',
    rule: { layer: 'L2', kind: 'taskChain', fallbackWhenDictMiss: 'drop' } },

  // L2: 击杀统计 byType
  { test: (p) =>
      p.length >= 3 && p[0] === 'others' && p[1] === '击杀统计' && p[2] === 'byType',
    rule: { layer: 'L2', kind: 'enemy', fallbackWhenDictMiss: 'drop' } },

  // L2: 技能名 [5][N][0] —— 固定形状 tuple，drop 用 clear 而非 splice
  { test: (p) => p.length === 3 && p[0] === '5' && p[2] === '0',
    rule: { layer: 'L2', kind: 'skill', fallbackWhenDictMiss: 'drop', dropMode: 'clear' } },

  // [5][N][3]：技能模式描述串（如 "枪术-空手"）—— 同 tuple 槽位，置空保形状
  { test: (p) => p.length === 3 && p[0] === '5' && p[2] === '3',
    rule: { layer: 'L3', kind: 'unknown', fallbackWhenDictMiss: 'drop', dropMode: 'clear' } },

  // [0][10][N][0..1]：键位绑定标签（["上键","上键",keycode]）—— 固定 tuple，置空保形状
  { test: (p) =>
      p.length === 4 && p[0] === '0' && p[1] === '10' && (p[3] === '0' || p[3] === '1'),
    rule: { layer: 'L3', kind: 'unknown', fallbackWhenDictMiss: 'drop', dropMode: 'clear' } },

  // L2: 发型 [1][N] —— 同上，[1] 是固定长度的外观槽位数组
  { test: (p) => p.length === 2 && p[0] === '1',
    rule: { layer: 'L2', kind: 'hairstyle', fallbackWhenDictMiss: 'drop', dropMode: 'clear' } },

  // L2: collection
  { test: (p) =>
      p.length >= 2 && p[0] === 'collection' && (p[1] === '材料' || p[1] === '情报'),
    rule: { layer: 'L2', kind: 'item', fallbackWhenDictMiss: 'drop' } },

  // L3: 物品来源缓存（按子类标 kind，便于 report 列候选；策略仍是 drop）
  { test: (p) =>
      p.length >= 3 && p[0] === 'others' && p[1] === '物品来源缓存' &&
      p[2] === 'discoveredEnemies',
    rule: { layer: 'L3', kind: 'enemy', fallbackWhenDictMiss: 'drop' } },
  { test: (p) =>
      p.length >= 3 && p[0] === 'others' && p[1] === '物品来源缓存' &&
      (p[2] === 'discoveredQuests' || p[2] === 'completedChallengeQuests'),
    rule: { layer: 'L3', kind: 'questId', fallbackWhenDictMiss: 'drop' } },
  { test: (p) =>
      p.length >= 3 && p[0] === 'others' && p[1] === '物品来源缓存' &&
      p[2] === 'discoveredStages',
    rule: { layer: 'L3', kind: 'stage', fallbackWhenDictMiss: 'drop' } },

  // L3: 设置
  { test: (p) => p.length >= 2 && p[0] === 'others' && p[1] === '设置',
    rule: { layer: 'L3', kind: 'unknown', fallbackWhenDictMiss: 'drop' } },
];

/** 默认 fallback：未匹配任何规则的字段视为 L3 静默丢弃。 */
const DEFAULT: FieldRule = { layer: 'L3', kind: 'unknown', fallbackWhenDictMiss: 'drop' };

export function classifyField(path: (string | number)[]): FieldRule {
  const strPath = path.map(String);
  for (const r of RULES) {
    if (r.test(strPath)) return r.rule;
  }
  return DEFAULT;
}
