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
