/**
 * 怪物「阶段」反查 — 按首次出场关卡对应的主线/支线序号换算 Excel《怪物大致面板》的阶段系数。
 *
 * 规则来自工作表 B19~C32 的阶次表与人工约定：
 * - 主线序号严格递增，每个章节对应一个阶段数字（废城1 盗贼2 军阀3 总堂前期4 总堂后期5 诺亚前期6 诺亚后期7 雪山8）。
 * - 主线关里首次出场的怪 → 该关所在章节的阶段数字。
 * - 非主线关：先找绑定该关的有序号支线，沿 get_requirements 回溯最近（最大）的前置主线序号，
 *   取那条主线所在章节 +1；没有支线任务时退回关卡 UnlockCondition，同样 +1。
 * - 主线序号大于配置上限（默认 77，诺亚前后与雪山尚未做完）→ 标记 deferred，等人工划分。
 *
 * 数据真源：data/stages/<章节目录>/__list__.xml、data/stages/<章节目录>/<关卡>.xml、
 * data/units/units.json、data/task/list.xml 与其登记的任务 JSON。
 */
import fs from "node:fs";
import path from "node:path";

import { loadXmlDocument } from "./document.js";
import type { ArmorRules, MeleeBulletRules, PierceSegmentRules } from "./monster-attack.js";
import type { XmlDocument, XmlDocumentNode } from "./document.js";

export interface MonsterCensusConfig {
  version: number;
  comment?: string;
  flagFields: string[];
  panelFields: Record<string, string>;
  moveSpeedFields: { min: string; max: string };
  tenacityField: string;
  displayNameField: string;
  flagElement: string;
  templatePrefix: string;
  excludedSourceFiles: string[];
  excludedStagePatterns: string[];
  mainlineCompletedUntil: number;
  /**
   * 主线序号区间 → 阶段数字，对应工作表 B19~C32 的阶次表。
   * 主线序号严格递增，区间边界即阶段分界；超出最后一个区间的序号按 mainlineCompletedUntil 之前
   * 处理时退回章节目录，超过已完成上限则标记 deferred。
   */
  mainlineBands: Array<{ from: number; to: number; stage: number; label: string }>;
  /** 关卡目录 → 阶段数字；未列出的目录（副本任务、异界战场等）视为待划分。 */
  chapters: Record<string, number>;
  /** 同名目录内需要单独指定阶段的关卡（如总堂前期/后期的分界）。 */
  stageChapterOverrides: Record<string, number>;
  /**
   * 前摇均值（帧，动画开始帧到第一个子弹实例）→ 攻速系数档位。
   * 制作组口径：<9 极快、9~16 快、16~26 中等、26~41 慢、>41 极慢（门槛是人工定的，改这里不用改代码）。
   * 上界不含，即前摇均值正好 16 帧起算中等档。
   */
  attackTempoBands?: Array<{ maxWindupFrames: number; factor: number; label: string }>;
  /**
   * 段数的一次攻击换算窗口（帧）：量子弹跨度（首子弹帧到末子弹帧），不满一个窗口算 1 次，
   * 满窗口按 跨度/窗口 折成小数次数，段数 = 霰弹值加总 / 次数（制作组 2026-10-04 口径）。
   */
  attackSegmentWindowFrames?: number;
  /**
   * 后摇换算倍率：攻速取档比的是「前摇均值 + 后摇均值×该倍率」，档位门槛同步乘 (1 + 该倍率)。
   * 0.2 就是"后摇只按两成的分量算，同时允许整档放宽两成"，一个旋钮管两处，不改 attackTempoBands 的常量值。
   */
  attackTempoTailFactor?: number;
  /**
   * 状态硬门词表：容器状态段名命中 attackStateWords 且不含 nonAttackStateWords 才算出手动作，
   * 只有挂在出手状态段上的元件才产招式（被击/击倒/血腥死 一类的状态段里摆了带参数的子弹也不算）。
   * 缺省用 xml-io 里的 DEFAULT_ATTACK_STATE_RULES；新增进攻状态改这里，不用改代码。
   */
  attackStateWords?: string[];
  nonAttackStateWords?: string[];
  /**
   * 近战子弹有效颗数口径（段数系数的第二层折算）：联弹打折 霰弹值（横向联弹无条件折、纵向联弹一律不折、其余要传 区域定位area），
   * 点状判定（没传 区域定位area）的近战子弹按拨折成打得中人的颗数。
   * 缺省用 xml-io 的 DEFAULT_MELEE_BULLET_RULES；mode 取简单法还是几何法由人工定，两种取法的对照值都在实测 JSON 里。
   */
  meleeSegmentRules?: MeleeBulletRules;
  /**
   * 穿刺类子弹的段数放大（段数系数的第三层）：命中 穿刺 词的子弹自己那段数乘 pierceFactor，
   * 命中 次级穿刺 词的乘 secondaryPierceFactor（判定先认次级穿刺，否则「次级穿刺子弹」会被当成穿刺）。
   * 缺省用 xml-io 的 DEFAULT_PIERCE_SEGMENT_RULES；命中的种类串在实测 JSON 的 pierce 块里，人工据此核对词表。
   */
  pierceSegmentRules?: PierceSegmentRules;
  /**
   * 霸体系数 的元件观测口径：击倒/倒地 两段的击飞逻辑词表（含没统一进函数的内联浮空写法）+ 被击 状态词表
   * + 长击退的帧阈值与多发击退时长的归类读法。缺省用 xml-io 的 DEFAULT_ARMOR_RULES；改口径改这里，不改代码。
   */
  armorRules?: ArmorRules;
  /**
   * 攻击实测的人工定源覆盖：模板名 → 用哪个包的哪个元件取源。
   * 注册表把跨包同名副本记在 `<conflict>`、同包多处导出记在 `<duplicate>`，那是扫描器刻意留给人工的定源名单，
   * 而 `data/items/asset_source_map.xml` 是 scan_linkage.py 的 DO-NOT-EDIT 生成物、又被图标/换装烘焙管线消费，
   * 所以不替它补 `<asset>`；要量这一类模板就在这一条里指定源，note 记下另一份实测差多少。
   */
  attackSourceOverrides?: Record<string, Array<{ swf: string; symbolName?: string; note?: string }>>;
  /**
   * 人工判定「无需标识」的模板（分身、投影、召唤物一类不挂面板的单位）。
   * 这些行不参与关卡反查、不拟合、不写盘 —— 少了这条通道，普查每次重跑都会按出场关卡给它们长出 `<阶段>`。
   * 取代原先 `monster-stage-backfill.csv` 里「待填阶段」填 0 的写法。
   */
  noFlagTemplates?: string[];
  /**
   * 制作组点名的档次判定：模板名 → 档次系数。
   * 档次是设计判断（看样貌与招式），不是面板能定住的东西，点名了就不参与联立拟合。
   * 写在配置而不是行内标识里，是为了让"这一档是人工钉的"在重跑之后仍然读得出来。
   */
  humanTierFactors?: Record<string, number>;
  /**
   * HEAD 里写了 `<档次系数>` 但制作组认定那只是**预估**的模板：档次放回本次联立搜索，重算后照写回。
   * 只豁免 `档次系数` 这一项 —— 同一批标识里的 阶段 等其余字段照旧按 git HEAD 钉住，不靠这份名单翻案。
   * 与 `humanTierFactors` 的分工：那张表是「人工把档次钉死」，这里是「HEAD 有值但钉不住」；两边都不许把观测五项放出去。
   * 两份名单点到同一行时按 `humanTierFactors` 钉住 —— 点名比「那颗是预估」更强。
   */
  estimatedTierTemplates?: string[];
  /**
   * 阶段数字 → 主线进度描述，对应工作表 B19~C32 的阶次表（废城 1 … 雪山 8、主线完结 9、主线后 10~15）。
   * 全量表的「主线进度」列用它；区间写成 [from, to]，取值落在哪个区间就报哪个描述。
   */
  stageLabels?: Array<{ from: number; to: number; label: string }>;
  /**
   * 档次系数 → 中文档次描述，对应工作表 B20~C32 的档次表（小型小怪 1 … 顶级boss 20~25）。
   * 全量表的「档次描述」列用它；门槛只取各档下限（8~9 按 8 起算），落在两档之间时按就近档写「本档+」或「上一档−」。
   */
  tierLabels?: Array<{ from: number; to: number; label: string }>;
}

export interface StageResolution {
  status: "mainline" | "subquest" | "unlock" | "deferred" | "unresolved";
  /** 换算出的阶段系数；deferred/unresolved 时缺失。 */
  stageNumber?: number;
  /** 依据的主线序号。 */
  mainlineId?: number;
  /** 人可读的依据说明。 */
  basis: string;
}

export interface FirstAppearance {
  spritename: string;
  stageName?: string;
  resolution?: StageResolution;
  candidates: string[];
}

export interface StageIndex {
  stageNames: string[];
  spawnStagesBySprite: Map<string, string[]>;
  resolutionByStage: Map<string, StageResolution>;
  excludedStages: string[];
}

interface StageInfoEntry {
  name: string;
  directory: string;
  type?: string;
  unlockCondition?: number;
}

interface TaskEntry {
  id: number;
  chain?: { name: string; number?: number };
  requirements: number[];
  stageNames: string[];
}

const BATTLE_TYPE_PATTERN = /^兵种(\d+)$/;

export function buildStageIndex(repoRoot: string, config: MonsterCensusConfig): StageIndex {
  const stagesRoot = path.join(repoRoot, "data", "stages");
  const stages = readStageInfos(stagesRoot);
  const units = readUnits(path.join(repoRoot, "data", "units", "units.json"));
  const excluded = new RegExp(config.excludedStagePatterns.join("|"));

  const spawnStagesBySprite = new Map<string, string[]>();
  for (const stage of stages) {
    if (excluded.test(stage.name)) continue;
    const stagePath = path.join(stagesRoot, stage.directory, `${stage.name}.xml`);
    if (!fs.existsSync(stagePath)) continue;
    const document = loadXmlDocument(stagePath);
    const sprites = new Set<string>();
    const refs = collectSpawnRefs(document, document.root);
    for (const id of refs.unitIds) {
      const spritename = units.get(id);
      if (spritename) sprites.add(spritename);
    }
    for (const spritename of refs.spriteNames) {
      if (spritename.startsWith(config.templatePrefix)) sprites.add(spritename);
    }
    for (const spritename of sprites) {
      const list = spawnStagesBySprite.get(spritename) ?? [];
      list.push(stage.name);
      spawnStagesBySprite.set(spritename, list);
    }
  }

  const tasks = readTasks(path.join(repoRoot, "data", "task"));
  const tasksById = new Map(tasks.map((task) => [task.id, task]));
  const mainlineByNumber = new Map<number, TaskEntry>();
  for (const task of tasks) {
    if (task.chain?.name === "主线" && task.chain.number !== undefined) {
      const previous = mainlineByNumber.get(task.chain.number);
      if (!previous || previous.id < task.id) mainlineByNumber.set(task.chain.number, task);
    }
  }

  const stageDirectory = new Map(stages.map((stage) => [stage.name, stage.directory]));
  const chapterOfStageName = (name: string | undefined): number | undefined => {
    if (!name) return undefined;
    const override = config.stageChapterOverrides[name];
    if (override !== undefined) return override;
    const directory = stageDirectory.get(name);
    return directory === undefined ? undefined : config.chapters[directory];
  };

  const bandOf = (mainlineId: number): { stage: number; label: string } | undefined =>
    config.mainlineBands.find((band) => mainlineId >= band.from && mainlineId <= band.to);

  const describeChapter = (mainlineId: number, chapter: number): string => {
    const label = bandOf(mainlineId)?.label;
    return label === undefined ? `章节 ${chapter}` : `${label}，阶段 ${chapter}`;
  };

  // 主线序号 → 章节：优先阶次表区间，其次该序号关卡所在目录；没有绑定的序号沿用上一个已知章节。
  const chapterByMainlineId = new Map<number, number>();
  let carried: number | undefined;
  for (const number of [...mainlineByNumber.keys()].sort((left, right) => left - right)) {
    const task = mainlineByNumber.get(number)!;
    const chapter = bandOf(number)?.stage ?? task.stageNames.map(chapterOfStageName).find((value) => value !== undefined);
    carried = chapter ?? carried;
    if (carried !== undefined) chapterByMainlineId.set(number, carried);
  }

  const mainlineIdByStage = new Map<string, number>();
  const bindingsByStage = new Map<string, TaskEntry[]>();
  for (const task of tasks) {
    for (const name of task.stageNames) {
      const list = bindingsByStage.get(name) ?? [];
      list.push(task);
      bindingsByStage.set(name, list);
      if (task.chain?.name === "主线" && task.chain.number !== undefined) {
        const known = mainlineIdByStage.get(name);
        if (known === undefined || task.chain.number > known) mainlineIdByStage.set(name, task.chain.number);
      }
    }
  }

  const resolve = (stageName: string): StageResolution => {
    const info = stages.find((entry) => entry.name === stageName);
    const mainlineId = mainlineIdByStage.get(stageName);

    if (mainlineId !== undefined) {
      const chapter = bandOf(mainlineId)?.stage ?? chapterOfStageName(stageName);
      if (mainlineId > config.mainlineCompletedUntil) {
        return { status: "deferred", mainlineId, basis: `主线#${mainlineId} 超过已完成上限 ${config.mainlineCompletedUntil}` };
      }
      if (chapter === undefined) {
        return { status: "unresolved", mainlineId, basis: `主线#${mainlineId} 既不在阶次表区间内，所在目录也未登记章节，需在配置里补` };
      }
      return {
        status: "mainline",
        stageNumber: chapter,
        mainlineId,
        basis: `主线#${mainlineId} 所在关卡（${describeChapter(mainlineId, chapter)}）`,
      };
    }

    const bindings = bindingsByStage.get(stageName) ?? [];
    const sequenced = bindings.filter((task) => task.chain !== undefined && task.chain.number !== undefined && task.chain.name !== "主线");
    if (sequenced.length > 0) {
      const ancestors = nearestMainlineNumbers(sequenced, tasksById, mainlineByNumber);
      if (ancestors.length > 0) {
        const nearest = Math.max(...ancestors);
        if (nearest > config.mainlineCompletedUntil) {
          return { status: "deferred", mainlineId: nearest, basis: `支线 ${describeChains(sequenced)} 回溯到主线#${nearest}，超出已完成上限` };
        }
        const chapter = chapterByMainlineId.get(nearest);
        if (chapter === undefined) {
          return { status: "unresolved", mainlineId: nearest, basis: `支线 ${describeChains(sequenced)} 回溯到主线#${nearest}，该序号无章节` };
        }
        return {
          status: "subquest",
          stageNumber: chapter + 1,
          mainlineId: nearest,
          basis: `支线 ${describeChains(sequenced)} 最近前置主线#${nearest}（${describeChapter(nearest, chapter)}）+1 → 阶段 ${chapter + 1}`,
        };
      }
    }

    const unlock = info?.unlockCondition;
    if (unlock !== undefined) {
      const nearest = [...mainlineByNumber.keys()].filter((number) => number <= unlock).sort((left, right) => right - left)[0];
      if (unlock > config.mainlineCompletedUntil || nearest === undefined) {
        return { status: "deferred", mainlineId: unlock, basis: `关卡解锁主线序号 ${unlock} 超出已完成上限或无对应主线` };
      }
      const chapter = chapterByMainlineId.get(nearest);
      if (chapter === undefined) {
        return { status: "unresolved", mainlineId: unlock, basis: `解锁序号 ${unlock} 对应主线#${nearest} 无章节` };
      }
      return {
        status: "unlock",
        stageNumber: chapter + 1,
        mainlineId: unlock,
        basis: `无支线，按 UnlockCondition ${unlock} → 主线#${nearest}（${describeChapter(nearest, chapter)}）+1 → 阶段 ${chapter + 1}`,
      };
    }

    return { status: "unresolved", basis: "既无主线/支线绑定，也没有 UnlockCondition" };
  };

  const resolutionByStage = new Map<string, StageResolution>();
  for (const stage of stages) {
    if (excluded.test(stage.name)) continue;
    resolutionByStage.set(stage.name, resolve(stage.name));
  }

  return {
    stageNames: stages.map((stage) => stage.name),
    spawnStagesBySprite,
    resolutionByStage,
    excludedStages: stages.filter((stage) => excluded.test(stage.name)).map((stage) => stage.name),
  };
}

/** 该怪物所有出场关卡里“最早”的那条阶段结论：优先主线，其次支线回溯，再次解锁序号。 */
export function resolveFirstAppearance(spritename: string, index: StageIndex): FirstAppearance {
  const candidates = index.spawnStagesBySprite.get(spritename) ?? [];
  const ranked = candidates
    .map((name) => ({ name, resolution: index.resolutionByStage.get(name) }))
    .filter((entry): entry is { name: string; resolution: StageResolution } => entry.resolution !== undefined)
    .sort((left, right) => rank(left.resolution) - rank(right.resolution) || (left.resolution.mainlineId ?? 1e9) - (right.resolution.mainlineId ?? 1e9));

  const best = ranked[0];
  return {
    spritename,
    candidates: candidates.sort(),
    ...(best
      ? { stageName: best.name, resolution: best.resolution }
      : { resolution: { status: "unresolved" as const, basis: "没有任何关卡注册该怪物" } }),
  };
}

function rank(resolution: StageResolution): number {
  switch (resolution.status) {
    case "mainline":
      return 0;
    case "subquest":
      return 1;
    case "unlock":
      return 2;
    case "deferred":
      return 3;
    default:
      return 4;
  }
}

function nearestMainlineNumbers(
  tasks: TaskEntry[],
  tasksById: Map<number, TaskEntry>,
  mainlineByNumber: Map<number, TaskEntry>,
): number[] {
  const found: number[] = [];
  const seen = new Set<number>();
  const queue = [...tasks];
  const mainlineIds = new Set([...mainlineByNumber.values()].map((task) => task.id));

  while (queue.length > 0) {
    const task = queue.pop();
    if (!task || seen.has(task.id)) continue;
    seen.add(task.id);
    if (mainlineIds.has(task.id)) {
      const number = [...mainlineByNumber.entries()].find(([, entry]) => entry.id === task.id)?.[0];
      if (number !== undefined) found.push(number);
    }
    for (const requirement of task.requirements) {
      const parent = tasksById.get(requirement);
      if (parent) queue.push(parent);
    }
    if (seen.size > 400) break;
  }
  return found;
}

function describeChains(tasks: TaskEntry[]): string {  return [...new Set(tasks.map((task) => (task.chain?.number === undefined ? task.chain!.name : `${task.chain.name}#${task.chain.number}`)))].join("/");
}

function readStageInfos(stagesRoot: string): StageInfoEntry[] {
  const entries: StageInfoEntry[] = [];
  if (!fs.existsSync(stagesRoot)) return entries;
  for (const directory of fs.readdirSync(stagesRoot, { withFileTypes: true })) {
    if (!directory.isDirectory()) continue;
    const listPath = path.join(stagesRoot, directory.name, "__list__.xml");
    if (!fs.existsSync(listPath)) continue;
    const document = loadXmlDocument(listPath);
    for (const node of descendantsNamed(document.root, "StageInfo")) {
      const name = document.childText(node, "Name");
      if (!name) continue;
      const unlock = document.childText(node, "UnlockCondition");
      const type = document.childText(node, "Type");
      entries.push({
        name,
        directory: directory.name,
        ...(type === undefined ? {} : { type }),
        ...(unlock === undefined || !/^\d+$/.test(unlock) ? {} : { unlockCondition: Number(unlock) }),
      });
    }
  }
  return entries;
}

function readUnits(unitsPath: string): Map<number, string> {
  const map = new Map<number, string>();
  if (!fs.existsSync(unitsPath)) return map;
  const raw = JSON.parse(fs.readFileSync(unitsPath, "utf8")) as unknown;
  if (!Array.isArray(raw)) return map;
  for (const entry of raw) {
    if (typeof entry !== "object" || entry === null) continue;
    const record = entry as Record<string, unknown>;
    if (typeof record.id === "number" && typeof record.spritename === "string") {
      map.set(record.id, record.spritename);
    }
  }
  return map;
}

function readTasks(taskRoot: string): TaskEntry[] {
  const listPath = path.join(taskRoot, "list.xml");
  if (!fs.existsSync(listPath)) return [];
  const document = loadXmlDocument(listPath);
  const files = descendantsNamed(document.root, "task")
    .map((node) => document.leafText(node))
    .filter((value): value is string => Boolean(value));

  const tasks: TaskEntry[] = [];
  for (const file of files) {
    const filePath = path.join(taskRoot, file);
    if (!fs.existsSync(filePath)) continue;
    const raw = JSON.parse(fs.readFileSync(filePath, "utf8")) as unknown;
    const list = Array.isArray(raw) ? raw : isRecord(raw) && Array.isArray(raw.tasks) ? raw.tasks : [];
    for (const entry of list) {
      if (!isRecord(entry) || typeof entry.id !== "number") continue;
      tasks.push({
        id: entry.id,
        ...parseChain(entry.chain),
        requirements: Array.isArray(entry.get_requirements) ? entry.get_requirements.filter((value): value is number => typeof value === "number") : [],
        stageNames: stageNamesOf(entry.finish_requirements),
      });
    }
  }
  return tasks;
}

function parseChain(value: unknown): { chain?: { name: string; number?: number } } {
  if (typeof value !== "string") return {};
  const match = /^(.*?)(?:#(-?\d+))?$/.exec(value);
  if (!match?.[1]) return {};
  const number = match[2] === undefined ? undefined : Number(match[2]);
  return { chain: { name: match[1], ...(number === undefined ? {} : { number }) } };
}

function stageNamesOf(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  const names: string[] = [];
  for (const entry of value) {
    if (typeof entry !== "string") continue;
    const name = entry.split("#")[0]?.trim();
    if (name) names.push(name);
  }
  return names;
}

function collectSpawnRefs(
  document: XmlDocument,
  node: XmlDocumentNode,
  into: { unitIds: Set<number>; spriteNames: Set<string> } = { unitIds: new Set(), spriteNames: new Set() },
): typeof into {
  for (const child of node.children) {
    if (child.name === "Type") {
      const value = document.leafText(child);
      const match = value === undefined ? undefined : BATTLE_TYPE_PATTERN.exec(value);
      if (match?.[1]) into.unitIds.add(Number(match[1]));
    } else if (child.name === "spritename") {
      const value = document.leafText(child);
      if (value) into.spriteNames.add(value);
    }
    collectSpawnRefs(document, child, into);
  }
  return into;
}

function descendantsNamed(node: XmlDocumentNode, name: string): XmlDocumentNode[] {
  const found: XmlDocumentNode[] = [];
  for (const child of node.children) {
    if (child.name === name) found.push(child);
    found.push(...descendantsNamed(child, name));
  }
  return found;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

/**
 * 单元格级 CSV 切分：吃掉文首 BOM，容忍引号包裹、`""` 转义、CRLF 与引号内的换行，丢掉全空行。
 * 标识全量表要按原文读回人工改过的系数，Excel 保存出来的这几种写法都得吃下。
 */
export function parseCsvRows(input: string): string[][] {
  const text = input.charCodeAt(0) === 0xfeff ? input.slice(1) : input;
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let index = 0; index < text.length; index += 1) {
    const char = text[index]!;
    if (quoted) {
      if (char !== '"') {
        cell += char;
        continue;
      }
      if (text[index + 1] === '"') {
        cell += '"';
        index += 1;
        continue;
      }
      quoted = false;
      continue;
    }
    if (char === '"') quoted = true;
    else if (char === ",") {
      row.push(cell);
      cell = "";
    } else if (char === "\r") continue;
    else if (char === "\n") {
      row.push(cell);
      rows.push(row);
      row = [];
      cell = "";
    } else cell += char;
  }
  if (cell !== "" || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }
  return rows.filter((entry) => entry.some((value) => value.trim() !== ""));
}
