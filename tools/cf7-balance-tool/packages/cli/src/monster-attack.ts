/**
 * 怪物攻击结构实测 CLI — 逐个敌人翻 XFL/.fla 量出攻速、倍率、段数的观测值。
 *
 * 用法：
 *   npm run monster-attack                       量全部模板，写 reports/monster-attack-census.json
 *     --markdown <路径>                          同时输出人工复核用表格（默认 reports/monster-attack-census.md）
 *     --only 敌人-A,敌人-B                        只量指定模板
 *     --no-markdown                              只写 JSON
 *     --overwrite                                口径变更后重标：观测值与已标注不同的也进候选（配合 --only 圈行，别碰人工标注）
 *   npm run monster-attack-show -- 敌人-特警僵尸   展开单个怪的有效招式明细（标签、帧、段数、倍率表达式）
 *
 * 三个系数都是观测值：段数量「子弹跨度折出的小数次数」的均摊值，倍率取有效招式均值，
 * 攻速比「前摇均值 + 后摇均值×attackTempoTailFactor」，后摇是末子弹帧到招式结束帧（认 动画完毕 调用），
 * 档位门槛同步放宽 (1+该倍率) 倍；两个口径常量与 attackTempoBands 都写在 data/monster-census.json。
 * 段数在颗数之上再过两层：meleeSegmentRules 只对近战类子弹折有效颗数（非近战子弹射出多少算多少），
 * pierceSegmentRules 给穿刺子弹的段数乘 2、次级穿刺乘 1.5（先认次级穿刺，否则会被「穿刺」误收）。
 * 颗数来源有两类：摆出来的子弹实例，以及只调函数发弹的招（Surveyor 这类）—— 函数体给 霰弹值/子弹威力/子弹种类，
 * 调用点按类型计真实触发次数（enterFrame 锚点逐帧、帧脚本逐关键帧），射击计数 % 性能倍率 这类闸门每 N 次触发发 1 颗。
 * 子弹威力 的系数认尾数（空手攻击力 * 4）也认乘积式（4 * 空手攻击力、0.5 * 性能倍率 * 空手攻击力，标识数从同文件数值声明取）；
 * 含加减或括号的表达式仍只认尾数，其余 2395 处尾数写法走原通道不受影响。
 * 候选值写进 reports/monster-attack-proposal.json，
 * 连同机械可定的 阶段/速度系数 一起给（首出关卡与移动速度区间），
 * 面板只读一个字段：韧性系数 按 Excel H34 给 霸体系数 带小数位（高于 20 时每 20 点加 0.1、上限 0.5），
 * 由 monster-flags-apply 决定要不要落盘，这里不直接改数据。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  censusMonsterFlags,
  DEFAULT_ATTACK_STATE_RULES,
  loadAssetSources,
  loadMonsterCensusConfig,
  loadUnresolvedAssetSources,
  measureMonsterAttack,
  mechanicalFlags,
  proposeAttackFlags,
  summarizeAttack,
} from "@cf7-balance-tool/xml-io";
import type {
  AttackSkillMeasure,
  AttackStateRules,
  AttackSummary,
  FunctionShotAudit,
  MeleeSegmentAudit,
  PierceSegmentAudit,
  MonsterAttackMeasure,
  MonsterCensusConfig,
} from "@cf7-balance-tool/xml-io";

const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const CONFIG_PATH = path.join(TOOL_ROOT, "data", "monster-census.json");
const CENSUS_PATH = path.join(TOOL_ROOT, "reports", "monster-attack-census.json");
const CENSUS_MARKDOWN_PATH = path.join(TOOL_ROOT, "reports", "monster-attack-census.md");
const PROPOSAL_PATH = path.join(TOOL_ROOT, "reports", "monster-attack-proposal.json");

/** 一行实测记录：观测结果 + 候选标识 + 机械可定项 + 已有的 攻速/倍率/段数 标识（用于对照）。 */
export interface MonsterAttackRow {
  spritename: string;
  sourceFile: string;
  summary: AttackSummary;
  measure: MonsterAttackMeasure;
  proposal: ReturnType<typeof proposeAttackFlags>;
  /** 阶段与速度系数：来自关卡反查与移动速度定义档，已在标识里的不重复给。 */
  mechanical: Record<string, number>;
  annotated: Record<string, number>;
  /** 面板 韧性系数：按 Excel H34 给 霸体系数 带小数位（高于 20 时每 20 点加 0.1，上限 0.5）。 */
  tenacity?: number;
}

/** 近战颗数对照表的一行：一只怪的一招，且这一招里有近战类子弹。 */
interface MeleeSkillEntry {
  row: MonsterAttackRow;
  skill: AttackSkillMeasure;
  audit: MeleeSegmentAudit;
}

/** 穿刺对照表的一行：一只怪的一招，且这一招里有被认成穿刺/次级穿刺的子弹。 */
interface PierceSkillEntry {
  row: MonsterAttackRow;
  skill: AttackSkillMeasure;
  audit: PierceSegmentAudit;
}

/** 函数发弹对照表的一行：一只怪的一招里的一个发弹函数。 */
interface FunctionShotEntry {
  row: MonsterAttackRow;
  skill: AttackSkillMeasure;
  audit: FunctionShotAudit;
}

function main(argv: string[]): void {
  const [command = "measure", ...rest] = argv;
  const { flags, positional } = parseFlags(rest);
  if (command === "show") {
    const spritename = positional[0];
    if (!spritename) throw new Error("show 需要指定 spritename");
    printDetail(spritename);
    return;
  }
  if (command !== "measure") throw new Error(`未知命令：${command}（支持 measure / show）`);
  runMeasure(flags, positional);
}

function runMeasure(flags: Record<string, string | boolean>, positional: string[]): void {
  const rows = attackRows(flags, positional);
  const measured = rows.filter((row) => row.summary.skills > 0);
  const empty = rows.length - measured.length;

  fs.mkdirSync(path.dirname(CENSUS_PATH), { recursive: true });
  fs.writeFileSync(CENSUS_PATH, `${JSON.stringify(rows, null, 2)}\n`, "utf8");
  // 默认只补缺项：apply 会直接改写同名子节点，人工给过值的就是权威。
  // --overwrite 供口径变更后重标：把与已有标注不一致的观测值也放进候选，配合 --only 圈定要改的行。
  const overwrite = flags["overwrite"] === true;
  const updates = rows
    .map((row) => ({
      sourceFile: row.sourceFile,
      spritename: row.spritename,
      flags: {
        ...row.mechanical,
        ...Object.fromEntries(
          Object.entries(row.proposal.flags).filter(([key, value]) =>
            overwrite ? row.annotated[key] !== value : row.annotated[key] === undefined,
          ),
        ),
      },
    }))
    .filter((update) => Object.keys(update.flags).length > 0);
  fs.writeFileSync(PROPOSAL_PATH, `${JSON.stringify(updates, null, 2)}\n`, "utf8");
  console.log(`实测完成：${rows.length} 个模板，量到有效招式 ${measured.length}，无招式/未定位 ${empty}`);
  console.log(`  有倍率证据 ${measured.filter((row) => row.summary.multiplier !== undefined).length}，全程固定值伤害 ${measured.filter((row) => row.summary.fixedValueSkills > 0).length}`);
  const shots = measured.flatMap((row) => row.measure.skills.flatMap((skill) => skill.functionShots ?? []));
  console.log(
    `  函数式发弹 ${shots.length} 个发弹函数（涉及 ${measured.filter((row) => row.measure.skills.some((skill) => skill.functionShots !== undefined)).length} 只怪）：` +
      `真实触发 ${shots.reduce((sum, shot) => sum + shot.calls, 0)} 次→折出 ${shots.reduce((sum, shot) => sum + shot.emissions, 0)} 颗，` +
      `闸门变量读不出按 1 的 ${shots.filter((shot) => shot.throttleBasis === "读不出").length} 个`,
  );
  console.log(`  候选标识 ${updates.length} 条（观测到的攻速/倍率/段数/霸体 + 机械可定的阶段/速度系数；${overwrite ? "overwrite：与已标值不同的观测值也进候选" : "只补缺项，已标注字段不覆盖"}；未写入数据）`);
  const armored = rows.filter((row) => row.measure.armor !== undefined);
  const tiered = armored.filter((row) => row.measure.armor?.factor !== undefined);
  console.log(
    `  霸体系数：读到容器 ${armored.length}，给出档位 ${tiered.length}`
      + `（${[1, 2, 3, 4, 5].map((factor) => `${factor} 档 ${tiered.filter((row) => row.measure.armor?.factor === factor).length}`).join("／")}）；`
      + `韧性 >20 带出小数位的 ${tiered.filter((row) => (row.tenacity ?? 0) > 20).length}；`
      + `与人工现标可对照 ${armored.filter((row) => row.annotated["霸体系数"] !== undefined).length}，`
      + `其中分歧 ${armored.filter((row) => row.annotated["霸体系数"] !== undefined && armorCandidate(row) !== row.annotated["霸体系数"]).length}`,
  );
  console.log(`JSON → ${CENSUS_PATH}`);
  console.log(`候选 → ${PROPOSAL_PATH}`);

  if (flags["no-markdown"] !== true) {
    const markdownPath = typeof flags.markdown === "string" ? path.resolve(TOOL_ROOT, flags.markdown) : CENSUS_MARKDOWN_PATH;
    fs.mkdirSync(path.dirname(markdownPath), { recursive: true });
    fs.writeFileSync(markdownPath, renderMarkdown(rows), "utf8");
    console.log(`Markdown → ${markdownPath}`);
  }
}

/** 用普查拿到模板清单与面板，再逐个翻动画包实测。 */
function attackRows(flags: Record<string, string | boolean>, positional: string[]): MonsterAttackRow[] {
  const config = loadMonsterCensusConfig(CONFIG_PATH);
  const bands = config.attackTempoBands;
  if (bands === undefined || bands.length === 0) {
    throw new Error(`${CONFIG_PATH} 缺少 attackTempoBands：攻速档位门槛是人工口径，请先在配置里给出`);
  }
  const windowFrames = config.attackSegmentWindowFrames;
  if (windowFrames === undefined) {
    throw new Error(`${CONFIG_PATH} 缺少 attackSegmentWindowFrames：段数按子弹跨度折次数的窗口是人工口径，请先在配置里给出`);
  }
  const tailFactor = config.attackTempoTailFactor;
  if (tailFactor === undefined) {
    throw new Error(`${CONFIG_PATH} 缺少 attackTempoTailFactor：后摇折算分量是人工口径，请先在配置里给出（不给后摇分量就写 0）`);
  }
  const only = typeof flags.only === "string" ? splitList(flags.only) : positional;
  const census = censusMonsterFlags(REPO_ROOT, config, { skipFit: true });
  const wanted = only.length > 0 ? new Set(only) : undefined;
  const assets = loadAssetSources(REPO_ROOT, config.attackSourceOverrides);
  const unresolved = loadUnresolvedAssetSources(REPO_ROOT);
  const stateRules: AttackStateRules = {
    attack: config.attackStateWords ?? DEFAULT_ATTACK_STATE_RULES.attack,
    nonAttack: config.nonAttackStateWords ?? DEFAULT_ATTACK_STATE_RULES.nonAttack,
  };
  const meleeRules = config.meleeSegmentRules;
  const pierceRules = config.pierceSegmentRules;
  const armorRules = config.armorRules;
  return census.rows
    .filter((row) => wanted === undefined || wanted.has(row.spritename))
    .map((row) => {
      const conflictSources = unresolved.get(row.spritename);
      const measure = measureMonsterAttack(
        {
          spritename: row.spritename,
          panelAtkMin: row.panel.atkMin ?? 0,
          panelAtkMax: row.panel.atkMax ?? 0,
          segmentWindowFrames: windowFrames,
          stateRules,
          ...(meleeRules === undefined ? {} : { meleeRules }),
          ...(pierceRules === undefined ? {} : { pierceRules }),
          ...(armorRules === undefined ? {} : { armorRules }),
          ...(conflictSources === undefined ? {} : { unresolvedSources: conflictSources }),
        },
        assets,
        REPO_ROOT,
      );
      const summary = summarizeAttack(measure);
      return {
        spritename: row.spritename,
        sourceFile: row.sourceFile,
        summary,
        measure,
        proposal: proposeAttackFlags(summary, bands, tailFactor, row.tenacity),
        // 阶段 0 的行只留实测那四项：机械项（阶段/速度系数）不写，反推与统计那边也已经把它排除了
        mechanical: row.excluded === true ? {} : mechanicalFlags(row),
        annotated: pick(row.flags, ["攻速系数", "攻击倍率", "段数系数", "霸体系数"]),
        ...(row.tenacity === undefined ? {} : { tenacity: row.tenacity }),
      };
    });
}

function printDetail(spritename: string): void {
  const row = attackRows({ only: spritename }, []).find((entry) => entry.spritename === spritename);
  if (!row) throw new Error(`普查里找不到 ${spritename}`);
  const measure = row.measure;
  console.log(`${spritename}　包 ${measure.source ?? "—"}（${measure.kind ?? "未定位"}／作用域 ${measure.scope ?? "—"}）`);
  if (measure.attackDesire) console.log(`  攻击欲望：${measure.attackDesire.join("、")}　闸门：${(measure.gates ?? []).join("、") || "—"}`);
  if (measure.note) console.log(`  说明：${measure.note}`);
  const sorted = [...measure.skills].sort((a, b) => a.file.localeCompare(b.file) || a.label.localeCompare(b.label));
  for (const skill of sorted) {
    const fixedValue = skill.concerns.some((concern) => concern.startsWith("倍率来自固定值"));
    console.log(
      `  ${skill.usable ? "✓" : "×"} ${skill.file} :: ${skill.label}　状态 ${skill.state ?? "—"}／摆放第 ${skill.depth} 层／帧 ${skill.frames}／子弹跨度 ${skill.bulletSpanFrames} 帧（首 ${skill.firstBulletOffset} 末 ${skill.lastBulletOffset}）／攻击次数 ${round(skill.attacks, 3)}／每攻 ${round(skill.tempoFrames, 1)} 帧／命中 ${skill.hits}／段数 ${round(skill.segments, 2)}／前摇 ${skill.windupFrames} 帧／后摇 ${skill.tailFrames} 帧（${skill.tailBasis}）／倍率 ${skill.multiplier === undefined ? "—" : round(skill.multiplier, 2)}${fixedValue ? "（固定值折算）" : ""}`,
    );
    skill.expressions.forEach((expr) => console.log(`        ${expr}`));
    if (skill.melee !== undefined) {
      const audit = skill.melee;
      console.log(
        `        近战颗数：近战 ${audit.meleeHits} 颗（按元件名认的 ${audit.byNameHits}）／区域判定 ${audit.areaHits}（横向联弹折 ${audit.linkageHorizontalHits}／传 area 的折 ${audit.linkageAreaHits}）／纵向联弹不折 ${audit.linkageVerticalHits}／` +
          `无区域 ${audit.spreadHits} 颗分 ${audit.clusters} 摆／计入颗数 简单法 ${audit.countedCap}、几何法 ${audit.countedHitbox}（${audit.unpositionedClusters} 拨退回简单法）／` +
          `段数 不过滤 ${round(audit.segmentsUnfiltered, 2)}、简单法 ${round(audit.segmentsCap, 2)}、几何法 ${round(audit.segmentsHitbox, 2)}／当前口径 ${audit.mode}`,
      );
    }
    if (skill.pierce !== undefined) {
      const audit = skill.pierce;
      console.log(
        `        穿刺段数：穿刺 ${audit.pierceHits} 颗（${audit.pierceKinds.join("、") || "—"}）／次级穿刺 ${audit.secondaryHits} 颗（${audit.secondaryKinds.join("、") || "—"}）／按元件名认的 ${audit.byNameHits} 颗`,
      );
    }
    for (const shot of skill.functionShots ?? []) {
      console.log(
        `        函数发弹：${shot.name}（声明于 ${shot.declaredIn}）／一次 ${shot.pelletsPerShot} 颗／倍率 ${shot.multiplier === undefined ? "—" : round(shot.multiplier, 2)}／` +
          `闸门 ${shot.throttle}（${shot.throttleBasis}）／有效帧内触发 ${shot.calls} 次→折出 ${shot.emissions} 颗／这些颗折进段数 ${round(shot.pelletSum, 2)}`,
      );
      console.log(`          种类 ${shot.kinds.join("、") || "—"}　${shot.expressions.join("　") || "威力读不出数值"}`);
    }
    skill.concerns.forEach((concern) => console.log(`        疑点：${concern}`));
  }
  const summary = row.summary;
  if (
    summary.segments !== undefined &&
    summary.segmentsUnfiltered !== undefined &&
    summary.segmentsCap !== undefined &&
    summary.segmentsHitbox !== undefined
  ) {
    console.log(
      `  段数对照（近战颗数）：不过滤 ${round(summary.segmentsUnfiltered, 2)}／简单法 ${round(summary.segmentsCap, 2)}／几何法 ${round(summary.segmentsHitbox, 2)}／当前取 ${round(summary.segments, 2)}`,
    );
  }
  const armor = measure.armor;
  if (armor !== undefined) {
    console.log(
      `  霸体：档位 ${armor.factor ?? "—"}（${armor.band ?? "—"}）／韧性 ${row.tenacity ?? "—"} → 候选 ${armorCandidate(row) ?? "—"}／`
        + `可击飞 ${armor.airborne === true ? "是" : "否"}／`
        + `击飞证据 ${armor.evidences.length} 处／被击状态段 ${armor.hitStates || "无"}／受创动画 ${armor.hitFiles} 份／`
        + `击退时长 ${armor.knockbackSpans.map((span) => `${span.label}=${span.frames}${span.basis === "段尾" ? "(段尾)" : ""}`).join("、") || "—"}`,
    );
    armor.evidences.forEach(
      (evidence) => console.log(`        ${evidence.state} 第 ${evidence.frame} 帧命中「${evidence.word}」（${evidence.via}${evidence.item === undefined ? "" : `　${evidence.item}`}）`),
    );
    armor.concerns.forEach((concern) => console.log(`        疑点：${concern}`));
  }
  console.log(
    `  合计：有效招式 ${summary.skills}/${summary.candidates}（${summary.overCallSkills} 招找到 动画完毕），段数均值 ${summary.segments === undefined ? "—" : round(summary.segments, 2)}，倍率均值 ${summary.multiplier === undefined ? "—" : round(summary.multiplier, 2)}，单次攻击中位 ${summary.tempoMedian === undefined ? "—" : round(summary.tempoMedian, 1)} 帧，前摇均值 ${summary.windupMean === undefined ? "—" : round(summary.windupMean, 1)} 帧，后摇均值 ${summary.tailMean === undefined ? "—" : round(summary.tailMean, 1)} 帧`,
  );
  console.log(`  候选标识：${Object.entries(row.proposal.flags).map(([key, value]) => `${key}=${value}`).join(" ") || "无"}`);
  console.log(`  机械项：${Object.entries(row.mechanical).map(([key, value]) => `${key}=${value}`).join(" ") || "无"}`);
  row.proposal.notes.forEach((note) => console.log(`  取档：${note}`));
  console.log(`  已标注：${Object.entries(row.annotated).map(([key, value]) => `${key}=${value}`).join(" ") || "无"}`);
}

function renderMarkdown(rows: MonsterAttackRow[]): string {
  const measured = rows.filter((row) => row.summary.skills > 0);
  const orphan = rows.filter((row) => row.summary.skills === 0);
  // 近战颗数对照：按"不折与简单法差多少"从大到小排，人工先看被折得最狠的那几招
  const meleeSkills: MeleeSkillEntry[] = [];
  // 穿刺对照：命中穿刺/次级穿刺的招式，人工核对词表覆盖到哪一类子弹
  const pierceSkills: PierceSkillEntry[] = [];
  // 函数发弹对照：只走函数调用才发弹的招式，人工核对触发次数与闸门
  const functionShots: FunctionShotEntry[] = [];
  for (const row of measured) {
    for (const skill of row.measure.skills) {
      if (skill.usable && skill.melee !== undefined) meleeSkills.push({ row, skill, audit: skill.melee });
      if (skill.usable && skill.pierce !== undefined) pierceSkills.push({ row, skill, audit: skill.pierce });
      for (const audit of skill.usable ? skill.functionShots ?? [] : []) {
        functionShots.push({ row, skill, audit });
      }
    }
  }
  meleeSkills.sort(
    (a, b) =>
      b.audit.segmentsUnfiltered - b.audit.segmentsCap - (a.audit.segmentsUnfiltered - a.audit.segmentsCap) ||
      b.audit.segmentsUnfiltered - a.audit.segmentsUnfiltered,
  );
  pierceSkills.sort(
    (a, b) =>
      b.audit.pierceHits + b.audit.secondaryHits - (a.audit.pierceHits + a.audit.secondaryHits) ||
      a.row.spritename.localeCompare(b.row.spritename),
  );
  functionShots.sort(
    (a, b) =>
      b.audit.pelletSum - a.audit.pelletSum ||
      b.audit.emissions - a.audit.emissions ||
      a.row.spritename.localeCompare(b.row.spritename),
  );
  const shotTemplates = new Set(functionShots.map((entry) => entry.row.spritename));
  const lines: string[] = [];
  lines.push("# 怪物攻击结构实测");
  lines.push("");
  lines.push(`- 模板 ${rows.length}，量到有效招式 ${measured.length}，未量到 ${orphan.length}`);
  lines.push(`- 有倍率证据 ${measured.filter((row) => row.summary.multiplier !== undefined).length}，含固定值伤害折算 ${measured.filter((row) => row.summary.fixedValueSkills > 0).length}`);
  lines.push(`- 已带 攻速/倍率/段数 标识可对照的 ${rows.filter((row) => Object.keys(row.annotated).length > 0).length} 行`);
  lines.push(`- 靠函数调用发弹的 ${shotTemplates.size} 只怪、${functionShots.length} 个发弹函数（见「函数式发弹对照」）`);
  lines.push("");
  lines.push("段数=一次攻击内打得中玩家的那些子弹的 霰弹值 加总，再除以按子弹跨度（首子弹帧到末子弹帧）折出的攻击次数：跨度不满 attackSegmentWindowFrames 帧算 1 次，满了按 跨度/窗口 取小数次数（不 ceil 补整）。加总前过两层口径（meleeSegmentRules + pierceSegmentRules）。近战颗数只管近战类子弹（联弹本身不算近战类）：横向联弹无条件打折 霰弹值、纵向联弹一律不折、其余联弹要传了 区域定位area 才折，没传 area 的点状判定近战子弹按拨（相邻帧）折成玩家命中框 80×170 框得住的颗数，非近战子弹射出多少颗就算多少颗。穿刺层在这之上乘倍数：种类含 穿刺 的这颗子弹段数乘 pierceFactor（现 2），含 次级穿刺 的乘 secondaryPierceFactor（现 1.5），判定先认次级穿刺再认穿刺，否则「次级穿刺子弹」会被误当 2 倍。颗数来源有两类：摆出来的子弹实例，以及只调函数发弹的招（函数体给 霰弹值/子弹威力，调用点按 enterFrame 逐帧或帧脚本逐关键帧计次数，闸门 每 N 次触发发 1 弹，详见「函数式发弹对照」）。倍率按物理=1、法伤×2、真伤×3 折算，固定值伤害按面板空手 MIN/MAX 均值折算；子弹威力 的系数认两种写法，`空手攻击力 * 4` 这种尾数和 `4 * 空手攻击力`、`0.5 * 性能倍率 * 空手攻击力` 这种乘积式都认（乘积式里的标识数从同文件数值声明取，含加减或括号的表达式仍只认尾数）。攻速比的是「前摇均值 + 后摇均值×attackTempoTailFactor」，档位门槛同步放宽 (1+该倍率) 倍，前摇仍占主导；后摇是末子弹帧到招式结束帧，结束帧认 动画完毕 调用，找不到的退回段尾并在备注里说明。三个系数都是观测值，不从面板反推。候选 JSON 里还带上机械可定的 阶段/速度系数。");
  lines.push("");

  lines.push(`## 已标注对照（${rows.filter((row) => Object.keys(row.annotated).length > 0).length}）`);
  lines.push("");
  lines.push("| 模板 | 来源 | 招式 | 动画完毕 | 单次攻击帧 | 段数 | 倍率 | 前摇帧 | 后摇帧 | 欲望 | 候选攻速/倍率/段数 | 已标攻速/倍率/段数 | 备注 |");
  lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const row of rows.filter((entry) => Object.keys(entry.annotated).length > 0)) {
    lines.push(`| ${rowTable(row)} |`);
  }
  lines.push("");

  lines.push(`## 实测到招式的模板（${measured.length}）`);
  lines.push("");
  lines.push("| 模板 | 来源 | 招式 | 动画完毕 | 单次攻击帧 | 段数 | 倍率 | 前摇帧 | 后摇帧 | 欲望 | 候选攻速/倍率/段数 | 已标攻速/倍率/段数 | 备注 |");
  lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const row of measured.filter((entry) => Object.keys(entry.annotated).length === 0)) {
    lines.push(`| ${rowTable(row)} |`);
  }
  lines.push("");

  if (meleeSkills.length > 0) {
    lines.push(`## 近战子弹有效颗数对照（${meleeSkills.length} 招）`);
    lines.push("");
    lines.push("只有近战类才折颗数（联弹本身不算近战类）：非近战子弹射出多少算多少；联弹打折 霰弹值（横向联弹无条件折、纵向联弹一律不折、其余要传 区域定位area）；点状判定（没传 区域定位area）的近战子弹按拨折颗数。段数三列分别是 不折颗数／每拨最多几颗（简单法）／玩家命中框最多框住颗数（几何法），参数见 data/monster-census.json 的 meleeSegmentRules，末列是当前口径。「段数不折」是摆了颗数就算的基线，不含联弹打折也不含穿刺倍数；简单法与几何法两列已乘过穿刺倍数（见下一节），所以某列比另一列高未必是几何门造成的。");
    lines.push("");
    lines.push("| 模板 | 招式 | 子弹 | 近战 | 按名认 | 区域 | 联弹打折（横向/靠区域） | 纵向不折 | 无区域 | 拨 | 简单法计入 | 几何法计入 | 退回简单法 | 段数不折 | 段数简单法 | 段数几何法 | 当前 |");
    lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const entry of meleeSkills) {
      const audit = entry.audit;
      lines.push(
        `| ${entry.row.spritename} | ${entry.skill.file} :: ${entry.skill.label} | ${entry.skill.hits} | ${audit.meleeHits} | ${audit.byNameHits} | ${audit.areaHits} | ${audit.linkageHorizontalHits}/${audit.linkageAreaHits} | ${audit.linkageVerticalHits} | ${audit.spreadHits} | ${audit.clusters} | ${audit.countedCap} | ${audit.countedHitbox} | ${audit.unpositionedClusters} | ${round(audit.segmentsUnfiltered, 2)} | ${round(audit.segmentsCap, 2)} | ${round(audit.segmentsHitbox, 2)} | ${audit.mode} |`,
      );
    }
    lines.push("");
  }

  if (pierceSkills.length > 0) {
    lines.push(`## 穿刺子弹段数放大对照（${pierceSkills.length} 招）`);
    lines.push("");
    lines.push("穿刺子弹命中后不消失、能连着打到人，所以这一颗自己的段数乘倍数（制作组 2026-10-06 口径）：种类含 穿刺 乘 pierceFactor（现 2），含 次级穿刺 乘 secondaryPierceFactor（现 1.5）。判定先认次级穿刺再认穿刺 —— 「次级穿刺子弹」里也含「穿刺」两字，顺序反了会全按 2 倍算。种类没声明时退回子弹元件名认（「按名认」列）。词表与倍数见 data/monster-census.json 的 pierceSegmentRules；命中过的种类串就是这张表的两列，人工据此看词表覆盖到哪一类。");
    lines.push("");
    lines.push("| 模板 | 招式 | 子弹 | 穿刺颗数 | 穿刺种类 | 次级穿刺颗数 | 次级穿刺种类 | 按名认 | 当前段数 |");
    lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const entry of pierceSkills) {
      const audit = entry.audit;
      lines.push(
        `| ${entry.row.spritename} | ${entry.skill.file} :: ${entry.skill.label} | ${entry.skill.hits} | ${audit.pierceHits} | ${audit.pierceKinds.join("、") || "—"} | ${audit.secondaryHits} | ${audit.secondaryKinds.join("、") || "—"} | ${audit.byNameHits} | ${round(entry.skill.segments, 2)} |`,
      );
    }
    lines.push("");
  }

  if (functionShots.length > 0) {
    lines.push(`## 函数式发弹对照（${functionShots.length} 个发弹函数，涉及 ${shotTemplates.size} 只怪）`);
    lines.push("");
    lines.push("这批怪靠函数调用发弹而不是摆子弹实例，颗数得从函数体折。口径：函数体里读到 子弹威力 才算发弹函数；一次真实触发折 霰弹值 颗，触发次数按调用点类型累计 —— `onClipEvent (enterFrame)` 的锚点元件按它在台上活过的帧数逐帧计，帧脚本里的调用一个关键帧进一次。函数体有 `if((射击计数++ % 性能倍率) != 0) return;` 这类闸门时每 N 次触发才发 1 弹，N 从同文件的数值声明里认（「闸门」列标 字面／数值声明／读不出，读不出按 1 并写疑点）。折进来的这些颗同时进 段数 与 子弹跨度，所以攻击次数、前摇、后摇都跟着动，最后一列是折完之后的该招段数；函数名声明在别的文件（「声明于」与「招式」不同份）时疑点会单独说明。");
    lines.push("");
    lines.push("| 模板 | 招式 | 函数 | 声明于 | 一次颗数 | 倍率 | 闸门 | 触发 | 发弹 | 折进段数 | 该招式段数 |");
    lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const entry of functionShots) {
      const audit = entry.audit;
      lines.push(
        `| ${entry.row.spritename} | ${entry.skill.file} :: ${entry.skill.label} | ${audit.name} | ${audit.declaredIn} | ${audit.pelletsPerShot} | ${audit.multiplier === undefined ? "—" : round(audit.multiplier, 2)} | ${audit.throttle}（${audit.throttleBasis}） | ${audit.calls} | ${audit.emissions} | ${round(audit.pelletSum, 2)} | ${round(entry.skill.segments, 2)} |`,
      );
    }
    lines.push("");
  }

  const armored = rows.filter((row) => row.measure.armor !== undefined);
  if (armored.length > 0) {
    // 分歧行排前面：人工已标 霸体系数 的这几十行是这条通道的校准靶，先看不合的
    const ordered = [...armored].sort((a, b) => {
      const aa = a.annotated["霸体系数"];
      const bb = b.annotated["霸体系数"];
      const rank = (row: MonsterAttackRow): number => {
        const known = row.annotated["霸体系数"];
        if (known === undefined) return 2;
        return armorCandidate(row) === known ? 1 : 0;
      };
      return rank(a) - rank(b) || (aa ?? 0) - (bb ?? 0) || a.spritename.localeCompare(b.spritename);
    });
    const disagreed = ordered.filter((row) => row.annotated["霸体系数"] !== undefined && armorCandidate(row) !== row.annotated["霸体系数"]).length;
    const calibrated = ordered.filter((row) => row.annotated["霸体系数"] !== undefined).length;
    lines.push(`## 霸体系数 的元件观测（${armored.length}，与人工现标可对照 ${calibrated}，分歧 ${disagreed}）`);
    lines.push("");
    lines.push("可击飞 = 击倒 与 倒地 两段各自都有生效的击飞代码、且那段确实摆了元件：统一函数 `_parent.击飞浮空();`／`_parent.击飞倒地();`（airborneCallWords），或没并进函数的内联写法 `_parent.浮空 = true;`／`_parent.倒地 = true;`（inlineAirborneWords，匹配前先剔注释）。两条都不算证据：只摆了名字叫 击飞 的元件而没有代码（那是美术摆放）、写在注释里的击飞代码。击退长短看 被击 段那份受创动画里每个命名帧到 动画完毕 的持续，大于 longKnockbackFrames（9 帧）算长击退，多发时按 knockbackReading 归类（现 any：有一发长就算长）。被击 读不出时长取 5，不可击飞取 3/4。档位再按 Excel H34 加韧性小数位：面板 韧性系数 高于 20 时每 20 点加 0.1、上限 0.5（`superArmorDecimalFromTenacity`），所以 韧性 50 的 3 档候选是 3.2。词表与阈值都在 data/monster-census.json 的 armorRules，击退时长的逐发账留在 census JSON 的 measure.armor.knockbackSpans 里，换读法不用重测。");
    lines.push("");
    lines.push("| 模板 | 来源 | 档位 | 可击飞 | 击退 | 被击状态段 | 受创动画 | 击退时长（帧） | 击飞证据 | 已标霸体 | 韧性 | 候选霸体 | 说明 |");
    lines.push("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const row of ordered) {
      const armor = row.measure.armor!;
      const evidence = armor.evidences
        .map((item) => `${item.state}${item.frame}帧「${item.word}」${item.via}`)
        .slice(0, 4)
        .join("、");
      lines.push(
        `| ${row.spritename} | ${row.sourceFile} | ${armor.band ?? "—"} | ${armor.airborne === true ? "是" : "否"} | ${armor.knockback ?? "—"} | ${armor.hitStates || "无"} | ${armor.hitFiles} | ${armor.knockbackSpans.map((span) => `${span.label}=${span.frames}${span.basis === "段尾" ? "†" : ""}`).join("、") || "—"} | ${armor.evidences.length}${evidence === "" ? "" : `（${evidence}）`} | ${row.annotated["霸体系数"] ?? "—"} | ${row.tenacity ?? "—"} | ${armorCandidate(row) ?? "—"} | ${armor.concerns.join("；") || "—"} |`,
      );
    }
    lines.push("");
  }

  if (orphan.length > 0) {
    lines.push(`## 未量到招式（${orphan.length}）`);
    lines.push("");
    lines.push("| 模板 | 来源 | 说明 |");
    lines.push("| --- | --- | --- |");
    for (const row of orphan) lines.push(`| ${row.spritename} | ${row.sourceFile} | ${row.measure.note ?? "无"} |`);
    lines.push("");
  }

  return `${lines.join("\n")}\n`;
}

function rowTable(row: MonsterAttackRow): string {
  const summary = row.summary;
  const desire = (row.measure.attackDesire ?? []).join("、") || "—";
  const trio = (values: Record<string, number>) => ["攻速系数", "攻击倍率", "段数系数"].map((key) => values[key] ?? "—").join("/");
  const cells = [
    row.spritename,
    row.sourceFile,
    `${summary.skills}${summary.candidates > summary.skills ? `/${summary.candidates}` : ""}`,
    `${summary.overCallSkills}/${summary.skills}`,
    String(summary.tempoMedian === undefined ? "—" : round(summary.tempoMedian, 1)),
    summary.segments === undefined ? "—" : String(round(summary.segments, 2)),
    summary.multiplier === undefined ? "—" : String(round(summary.multiplier, 2)),
    String(summary.windupMean === undefined ? "—" : round(summary.windupMean, 1)),
    String(summary.tailMean === undefined ? "—" : round(summary.tailMean, 1)),
    desire,
    trio(row.proposal.flags),
    trio(row.annotated),
    [...row.proposal.notes, row.measure.note ?? ""].filter(Boolean).join("；"),
  ];
  return cells.join(" | ");
}

/** 候选霸体＝观测档位＋韧性带出的小数位；量不到档位时退回 undefined。 */
function armorCandidate(row: MonsterAttackRow): number | undefined {
  return row.proposal.flags["霸体系数"] ?? row.measure.armor?.factor;
}

function pick(flags: Record<string, number>, keys: string[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const key of keys) {
    if (flags[key] !== undefined) out[key] = flags[key]!;
  }
  return out;
}

function splitList(value: string): string[] {
  return value.split(",").map((entry) => entry.trim()).filter(Boolean);
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

function parseFlags(argv: string[]): { flags: Record<string, string | boolean>; positional: string[] } {
  const flags: Record<string, string | boolean> = {};
  const positional: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index]!;
    if (!token.startsWith("--")) {
      positional.push(token);
      continue;
    }
    const key = token.slice(2);
    const next = argv[index + 1];
    if (next === undefined || next.startsWith("--")) {
      flags[key] = true;
      continue;
    }
    flags[key] = next;
    index += 1;
  }
  return { flags, positional };
}

main(process.argv.slice(2));
