/**
 * 怪物数值重算 CLI —— 正算方向：`<标识>` 十项系数 → 面板（经验 / HP / 空手攻击 / 基本防御）。
 *
 * 这是「怪物数值填写」的标准工具，也是新怪上线、旧怪调平衡的唯一入口：
 * **系数是输入，面板是输出**。系数来源只有两条 —— 观测/定义通道算出来的，或人工给定/按外形判定的。
 *
 * 与早期那批反推工作的区别（很重要，别混）：
 * - `monster-solve` / `monster-flags` 是从**已有面板**反推「最贴合这块面板」的系数，用来把存量怪的 `<标识>` 补齐。
 *   那批工作已经完成，之后很少再用；它不知道设计意图，所以不能拿来定新怪的强弱。
 * - 本工具走相反方向：先按设计意图定下系数（观测类实测、定义类自动、人工类由用户或 AI 判定），
 *   再用公式算出面板。新怪、重做怪、调平衡一律走这里，不要反过来用面板去猜系数。
 *
 * 公式权威：`packages/core/src/formulas/monsters.ts`（对应工作簿《怪物大致面板》）。
 *
 * ============================ 一、系数分三类 ============================
 *
 * 1) 观测类（**不要人工改**，只能由动画/元件实测得到）
 *    - 攻速系数：前摇帧数档位，见 data/monster-census.json 的 `attackTempoBands`（极快 5 / 快 4 / 中等 3 / 慢 2 / 极慢 1）。
 *    - 攻击倍率：每次命中的子弹威力折算（物理 1、法伤/元素 ×2、真伤 ×3）。
 *    - 段数系数：一招实际能吃到的段数（霰弹值加总 / 每 15 帧一次出手）。
 *    - 霸体系数：击退与击飞元件观测，五档 1~5（长击退可击飞 1 … 不可击退不可击飞 5）。
 *    实测入口：`npm run monster-attack -- --template 敌人-XXX`，结果落在 tools/cf7-balance-tool 的实测报告里。
 *    **存量怪重算数值时不要重新观测**：行内已经有实测值就直接沿用，本工具也从不自行触发实测；
 *    只有新建模板、动作/元件改过、或用户明确要求重测时，才去跑上面那条命令。
 *
 * 2) 定义映射类（**不要人工改**，按当前数据自动定）
 *    - 速度系数：取 `速度_min` 与 `速度_max` 的均值落档，10~40 慢=1、40~60 中=2、60~90 快=3（区间上限归本档）。
 *      标识里缺这一项时，本工具会用 `speedFactorFromMoveSpeed()` 自动补出来并写回。
 *    - 阶段：按「首次出场关卡」的主线/支线序号反查（`npm run monster-census` 的 first-appearance 通道）。
 *      这是测量项，但**尚未实装进任何关卡的怪没有出场记录**，此时必须人工补 `阶段`。
 *    存量怪的这两项已有值一律直接沿用，重算数值时不需要重新映射；只有新怪或缺值时才反查、补算。
 *
 * 3) 人工给定类（**只有这四项允许决策**，也是调平衡时唯一该动的旋钮）
 *    - 档次系数   ：整体强弱档次，**定义逐条抄自工作簿《怪物大致面板》B19~C32 的档次表**（见 `TIER_TABLE`）：
 *                  1 小型小怪「毫无威胁的杂毛，凑数的」；1.5 中型小怪「常规水平/偏科较强其他较弱，大量出现」；
 *                  2 大型小怪「整体较强/偏科强其他中等，大量出现」；3~4 低级精英「可经常复数出现」；
 *                  5~6 中级精英「有威胁，有时复数出现」；8~9 高级精英「数值接近小boss，出场数量要控制」；
 *                  9 低级boss「数值和高级精英差别不大，但基本性能强（霸体/破韧），可能复数出现」；
 *                  13 中级boss「最常规单体boss，诺亚后期之前不会同时出现超过1个」；
 *                  16 高级boss「较强的boss」；20~25 顶级boss「同期阶段下极强，存在感极高」。
 *                  工作簿明确：档次定位**只相对当前阶段**，不代表绝对数值；不同档次之间有间隔，可按具体情况
 *                  插空或上下浮动；多阶段单位按阶段合计评档。
 *                  它会同时抬高 HP、攻击、防御、经验，是最粗的那根杠杆。
 *    - 成长系数   ：工作簿原文「代表战宠跟随等级的面板与经验成长率，范围 0.5~2，默认 1。**系数高代表低级时更弱
 *                  但高等级时更强**」。工具参考区间放宽到 0.2~5。
 *    - 高攻低血防系数（J）：工作簿「默认 1，范围 0.5~2。2 代表攻击力明显更高、血防明显更低；0.5 代表血防明显更高、攻击力更低」。
 *                  它同时压低 **HP 与防御**（两处都在分母），所以抬 J 会得到「薄皮高输出」。
 *    - 高防低血系数（L）：工作簿「默认 1，通常 0.2~5，最大 0.1~10。数值越高防御越高、血量越低；视觉和设定上更硬的
 *                  单位应给更高值」。它只压 HP（分母开根号，影响温和），并让**防御反而升高**
 *                  （防御公式里有 `(50+C·D)·L` 与 `30·(L-1)` 正项）。
 *    参考区间（`MONSTER_COEFFICIENT_RANGES`，是判断合理性的参考、不是硬边界）：
 *    档次 1~25、成长 0.2~5、高攻低血防 0.5~2、高防低血 0.1~10。
 *    工作簿另有提醒：对拥有暖机、强力 buff、多阶段等显著影响面板的特殊机制单位，「大致面板」这套估法可能不适用。
 *
 * ============================ 二、标准填写流程 ============================
 *
 * 1. 先跑 `npm run monster-recalc -- explain` 把三类系数、参考区间与作用方向摆给用户看（本文件顶部同源）。
 * 2. 明确问用户：档次 / 成长 / 高攻低血防 / 高防低血 这四项要不要指定？用户给了就照用户的值。
 * 3. 用户没给的部分，由 AI 按怪物外形与定位自己定，并在回报里写明判断依据，例如：
 *    - 「看起来是普通杂兵、无甲」→ 档次 1~1.5、高防低血 0.2~0.5；
 *    - 「体型壮、穿重甲」→ 档次 2~4、高防低血 1.5~3；
 *    - 「拿大枪的输出手、血量一般」→ 高攻低血防 1.5~2.5；
 *    - 「血厚、伤害刮」→ 高攻低血防 0.5~1、高防低血 2 以上。
 * 4. 观测类/定义类系数**不要手填**。存量怪的行内已有值直接沿用，**不重测、不重映射** —— 重算数值只动
 *    人工那四项。只有新建怪、动作或元件改过、阶段没有出场记录，或用户明确要求重新测算时，才去跑实测/反查。
 * 5. 用 `preview` 看旧值 → 新值，确认后再 `apply` 写盘；`apply` 结束会自动重读文件校验。
 *
 * ============================ 三、命令 ============================
 *
 *   npm run monster-recalc -- explain
 *       打印系数分类、参考区间、作用方向与流程（给人看，也给 AI 当工作口径）。
 *
 *   npm run monster-recalc -- preview --templates 敌人-A,敌人-B [选项]
 *       只算不写：打印每个模板的 HP / 攻击 / 防御 / 经验 旧 → 新，以及指定等级的实战血量。
 *
 *   npm run monster-recalc -- apply   --templates 敌人-A,敌人-B [选项]
 *       写盘：改 `<标识>` 里被覆盖的系数 + 重算后的八项面板；HP 按 `--hp-round` 取整（默认整百）。
 *
 *   选项：
 *     --set "敌人-A.高防低血系数=1.5"    覆盖系数，可重复、可逗号分隔；不写模板前缀则作用于本批全部模板。
 *                                        字段名用中文标识名（档次系数…）或英文名（highDefFactor…）都认。
 *     --level 20                         preview 里额外算这个等级的实际血量（默认 20）。
 *     --max-level 60                     `根据等级计算值` 的分母上限，与 `_root.最大等级` 一致（默认 60）。
 *     --difficulty 1                     `出生难度` 乘数，非 CF6 关卡等于 `_root.难度等级`（默认 1）。
 *     --hp-round 100                     HP 取整步长；100 = 取整百（现网这批杂兵的惯例），0 = 四舍五入到整数。
 *     --file "原版敌人 2011-2012.xml"     只在这些文件里找模板（默认全库按 list.xml 搜索）。
 *     --allow-measured                   允许 `--set` 覆盖观测类/定义类系数（默认拒绝，防止把手填值伪装成实测）；
 *                                        只在你明确要求重测、且拿得到实测来源时才用。
 *     --dry-run                          apply 时只打印将要写入的差异，不落盘。
 *     --json                            以 JSON 输出结果，便于其他脚本消费。
 *
 * ============================ 四、取整与排版 ============================
 *
 * - HP：`--hp-round` 步长取整（默认 100）。现网 2011-2012 那批杂兵就是整百，写回去和相邻行一致。
 * - 攻击 / 防御 / 经验：四舍五入到整数（工作簿这几列本来就是整数口径）。
 * - 只改目标节点内部文本，BOM、CRLF、缩进、注释、其余字段保持原样（`XmlDocument` 的补丁式写入）。
 *
 * ============================ 五、与既有工具的边界 ============================
 *
 * - `monster-census` / `monster-solve`：从**现有面板**反推四个自由量，用于给存量怪补标识。
 *   它不知道设计意图，所以**不能用它覆盖人工定过的系数**；要改平衡方向请走本工具。
 * - `monster-flags-apply`：只写 `<标识>`，不动面板。它写的是反推结果。
 * - 本工具：**系数是输入，面板是输出**。改完系数必须同时写回 `<标识>` 与面板，否则 census 会认为面板对不上标识。
 *
 * ============================ 六、失败与校验 ============================
 *
 * - 模板找不到 / 同名模板出现在多个文件 → 直接报错，不猜。
 * - 缺 `阶段` → 报错并提示先跑 census 或人工 `--set 阶段=N`（未实装怪必须人工补）。
 * - 缺观测类系数 → 报错，提示先跑 `monster-attack` 实测；不会拿默认值偷偷顶上。
 * - 系数落在参考区间外 → 只警告不拦，值照写（区间是参考，不是硬边界）。
 * - `apply` 写完后重读文件比对每个字段，任一处不一致即报错退出（非 0）。
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  MONSTER_COEFFICIENT_RANGES,
  MONSTER_OBSERVED_COEFFICIENTS,
  computeMonsterRow,
  speedFactorFromMoveSpeed,
} from "@cf7-balance-tool/core";
import type { MonsterCoefficientName, MonsterInput, MonsterOutput } from "@cf7-balance-tool/core";
import {
  MONSTER_COEFFICIENT_TO_FLAG,
  MONSTER_FLAG_TO_COEFFICIENT,
  loadMonsterCensusConfig,
  loadXmlDocument,
} from "@cf7-balance-tool/xml-io";
import type { MonsterCensusConfig, XmlDocument, XmlDocumentNode } from "@cf7-balance-tool/xml-io";

const TOOL_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../..");
const REPO_ROOT = path.resolve(TOOL_ROOT, "../..");
const CONFIG_PATH = path.join(TOOL_ROOT, "data", "monster-census.json");
const PROPERTIES_DIR = path.join(REPO_ROOT, "data", "enemy_properties");

/** 观测类系数对应的 `<标识>` 字段：只认实测，`--set` 默认拒绝覆盖这五个。 */
const OBSERVED_FLAGS: string[] = MONSTER_OBSERVED_COEFFICIENTS.map((name) => MONSTER_COEFFICIENT_TO_FLAG[name]);
/** 定义映射类：速度系数（缺值时自动补）；阶段按首次出场反查，未实装怪人工补。 */
const DERIVED_FLAGS: string[] = ["速度系数"];
const STAGE_FLAG = "阶段";
/** 人工给定类：调平衡时唯一该动的四项。 */
const HUMAN_FLAGS: string[] = ["档次系数", "成长系数", "高攻低血防系数", "高防低血系数"];

/**
 * 档次系数原始定义 —— **逐条抄自工作簿《怪物大致面板》B19~C32 的档次表**，不要按印象改写。
 * 工作簿原话：档次定位仅相对当前阶段，举例也是同阶段的相对强度，不代表绝对数值；不同档次之间系数有间隔，
 * 可按具体情况插空或上下浮动；多阶段单位按阶段合计评档（如「黑龙两阶段之和」= 高级boss）。
 */
const TIER_TABLE: Array<{ band: string; label: string; note: string }> = [
  { band: "1", label: "小型小怪", note: "毫无威胁的杂毛，凑数的" },
  { band: "1.5", label: "中型小怪", note: "常规水平/偏科较强其他较弱的小怪，大量出现" },
  { band: "2", label: "大型小怪", note: "整体较强/偏科强其他中等的小怪，大量出现" },
  { band: "3~4", label: "低级精英", note: "可经常复数出现的低级精英" },
  { band: "5~6", label: "中级精英", note: "有威胁的精英怪，有时复数出现" },
  { band: "8~9", label: "高级精英", note: "数值接近小boss，出场数量需要控制" },
  { band: "9", label: "低级boss", note: "数值和高级精英差别不大，但基本性能强（通常表现在霸体或破韧），可能复数出现" },
  { band: "13", label: "中级boss", note: "最常规的单体boss，诺亚后期之前不会同时出现超过1个" },
  { band: "16", label: "高级boss", note: "较强的boss" },
  { band: "20~25", label: "顶级boss", note: "同期阶段下极强的boss，存在感极高" },
];

/** 阶段系数原始定义 —— 工作簿 B19~C32 阶次表：主线章节定档，支线按对应主线进度 +1。 */
const STAGE_TABLE: Array<{ stage: string; label: string; note: string }> = [
  { stage: "1", label: "废城", note: "" },
  { stage: "2", label: "盗贼", note: "" },
  { stage: "3", label: "军阀", note: "" },
  { stage: "4", label: "总堂前期", note: "包括通缉犯，不包括黑龙" },
  { stage: "5", label: "总堂后期", note: "黑龙~深入禁区" },
  { stage: "6", label: "诺亚前期", note: "包括初见爪豪" },
  { stage: "7", label: "诺亚后期", note: "爪豪之后" },
  { stage: "8", label: "雪山", note: "" },
  { stage: "9", label: "主线完结", note: "" },
  { stage: "10~15", label: "主线后", note: "" },
  { stage: "+1", label: "支线", note: "根据对应主线进度 +1" },
];

/** 霸体系数原始定义 —— 工作簿：以击退/击飞动画定整数位；韧性 >20 时每 20 点 +0.1，最高 +0.5。 */
const ARMOR_TABLE: Array<{ band: string; label: string }> = [
  { band: "1", label: "长击退可击飞" },
  { band: "2", label: "短击退可击飞" },
  { band: "3", label: "长击退不可击飞" },
  { band: "4", label: "短击退不可击飞" },
  { band: "5", label: "不可击退不可击飞" },
];

/** 面板字段的短标签，仅用于报表。 */
const PANEL_LABELS: Record<string, string> = {
  最小经验值: "经验MIN",
  最大经验值: "经验MAX",
  hp_min: "HP MIN",
  hp_max: "HP MAX",
  空手攻击力_min: "攻击MIN",
  空手攻击力_max: "攻击MAX",
  基本防御力_min: "防御MIN",
  基本防御力_max: "防御MAX",
};

interface OverrideSet {
  template?: string;
  field: string;
  value: number;
  raw: string;
}

interface Options {
  command: string;
  templates: string[];
  sets: OverrideSet[];
  files: string[];
  level: number;
  maxLevel: number;
  difficulty: number;
  hpRound: number;
  json: boolean;
  dryRun: boolean;
  allowMeasured: boolean;
}

interface Target {
  template: string;
  displayName: string;
  sourceFile: string;
  document: XmlDocument;
  node: XmlDocumentNode;
}

interface PlannedRow {
  target: Target;
  before: MonsterInput;
  after: MonsterInput;
  output: MonsterOutput;
  /** xml 字段名 → 将要写入的文本 */
  panel: Map<string, string>;
  /** `<标识>` 字段名 → 将要写入的数值（仅包含本次覆盖或自动补的项） */
  flags: Map<string, number>;
  /** 写盘前的标识快照，用于报表「旧值 → 新值」 */
  oldFlags: Map<string, number>;
  /** 旧面板文本，用于报表 */
  oldPanel: Map<string, string>;
}

interface ParsedArgs {
  options: Options;
  errors: string[];
}

function main(argv: string[]): number {
  const parsed = parseArgs(argv);
  if (parsed.errors.length > 0) {
    for (const message of parsed.errors) console.error(`✗ ${message}`);
    console.error("用法见：npm run monster-recalc -- explain");
    return 2;
  }
  const options = parsed.options;

  if (options.command === "explain") {
    printExplain();
    return 0;
  }
  if (options.command !== "preview" && options.command !== "apply") {
    console.error(`未知命令：${options.command}（支持 explain / preview / apply）`);
    return 2;
  }
  if (options.templates.length === 0) {
    console.error("缺少 --templates（逗号分隔的模板名，如 敌人-盗贼枪手,敌人-盗贼侏儒）");
    return 2;
  }

  const config = loadMonsterCensusConfig(CONFIG_PATH);
  const targets = findTargets(options.templates, options.files);
  const planned = targets.map((target) => plan(target, options, config));

  warnOutOfRange(planned, config);

  if (options.command === "preview") {
    if (options.json) console.log(JSON.stringify(toJson(planned, options), null, 2));
    else printReport(planned, options);
    return 0;
  }

  // apply：先写再验，任何不一致都返回非 0，避免「以为写了」。
  if (options.dryRun) {
    printReport(planned, options);
    console.log("\n（--dry-run：未写入文件）");
    return 0;
  }
  const written = writeAll(planned, options, config);
  verifyAll(planned, config);
  printReport(planned, options);
  console.log(
    written.files === 0
      ? "\n✓ 全部模板与盘上一致，未产生写入；重读校验通过。"
      : `\n✓ 已写入 ${written.files} 个文件、${written.rows} 个模板；重读校验通过。`,
  );
  return 0;
}

// ============================ 参数解析 ============================

function parseArgs(argv: string[]): ParsedArgs {
  const options: Options = {
    command: argv[0] ?? "explain",
    templates: [],
    sets: [],
    files: [],
    level: 20,
    maxLevel: 60,
    difficulty: 1,
    hpRound: 100,
    json: false,
    dryRun: false,
    allowMeasured: false,
  };
  const errors: string[] = [];
  const rest = argv.slice(1);

  // 允许 `--key=value` 与 `--key value` 两种写法；布尔开关不吃下一个参数。
  for (let index = 0; index < rest.length; index += 1) {
    const token = rest[index]!;
    if (!token.startsWith("--")) {
      errors.push(`无法识别的参数：${token}`);
      continue;
    }
    const equal = token.indexOf("=");
    const key = equal >= 0 ? token.slice(2, equal) : token.slice(2);
    const inline = equal >= 0 ? token.slice(equal + 1) : undefined;
    const takeValue = (): string | undefined => {
      if (inline !== undefined) return inline;
      const next = rest[index + 1];
      if (next === undefined || next.startsWith("--")) return undefined;
      index += 1;
      return next;
    };

    switch (key) {
      case "templates": {
        const value = takeValue();
        if (value === undefined) errors.push("--templates 需要值");
        else options.templates.push(...value.split(/[,，]/).map((item) => item.trim()).filter((item) => item !== ""));
        break;
      }
      case "set": {
        const value = takeValue();
        if (value === undefined) errors.push("--set 需要值");
        else for (const item of value.split(/[;,；]/)) parseOverride(item.trim(), options, errors);
        break;
      }
      case "file": {
        const value = takeValue();
        if (value === undefined) errors.push("--file 需要值");
        else options.files.push(value.trim());
        break;
      }
      case "level":
        options.level = parseNumberOption(takeValue(), "--level", 1, errors);
        break;
      case "max-level":
        options.maxLevel = parseNumberOption(takeValue(), "--max-level", 2, errors);
        break;
      case "difficulty":
        options.difficulty = parseNumberOption(takeValue(), "--difficulty", 0.01, errors);
        break;
      case "hp-round":
        options.hpRound = parseNumberOption(takeValue(), "--hp-round", 0, errors);
        break;
      case "json":
        options.json = true;
        break;
      case "dry-run":
        options.dryRun = true;
        break;
      case "allow-measured":
        options.allowMeasured = true;
        break;
      default:
        errors.push(`未知选项：--${key}`);
    }
  }
  return { options, errors };
}

function parseNumberOption(value: string | undefined, name: string, min: number, errors: string[]): number {
  if (value === undefined) {
    errors.push(`${name} 需要数值`);
    return 0;
  }
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < min) {
    errors.push(`${name} 需要 ≥ ${min} 的数值，收到：${value}`);
    return 0;
  }
  return parsed;
}

/** `[模板.]字段=数值`；字段名接受中文标识名或英文系数名。 */
function parseOverride(item: string, options: Options, errors: string[]): void {
  if (item === "") return;
  const equal = item.indexOf("=");
  if (equal < 0) {
    errors.push(`--set 需要「字段=数值」：${item}`);
    return;
  }
  const left = item.slice(0, equal).trim();
  const rawValue = item.slice(equal + 1).trim();
  const dot = left.indexOf(".");
  const template = dot >= 0 ? left.slice(0, dot).trim() : undefined;
  const field = dot >= 0 ? left.slice(dot + 1).trim() : left;
  const value = Number(rawValue);
  if (!Number.isFinite(value)) {
    errors.push(`--set 数值无效：${item}`);
    return;
  }
  const normalized = normalizeField(field);
  if (normalized === undefined) {
    errors.push(`--set 字段无效：${field}（可用：${Object.keys(MONSTER_FLAG_TO_COEFFICIENT).join("、")}）`);
    return;
  }
  if (!options.allowMeasured && (OBSERVED_FLAGS.includes(normalized) || DERIVED_FLAGS.includes(normalized))) {
    errors.push(
      `${normalized} 是观测/定义类系数，不接受手填（真值来自实测或速度定义档）。` +
        "确有必要请加 --allow-measured，并在回报里说明来源。",
    );
    return;
  }
  const entry: OverrideSet = { field: normalized, value, raw: rawValue };
  if (template !== undefined) entry.template = template;
  options.sets.push(entry);
}

/** 中文标识名或英文系数名 → 统一的 `<标识>` 字段名。 */
function normalizeField(field: string): string | undefined {
  if (MONSTER_FLAG_TO_COEFFICIENT[field] !== undefined) return field;
  if (MONSTER_COEFFICIENT_TO_FLAG[field as MonsterCoefficientName] !== undefined) {
    return MONSTER_COEFFICIENT_TO_FLAG[field as MonsterCoefficientName];
  }
  return undefined;
}

// ============================ 目标定位 ============================

function readRegistry(): string[] {
  const listPath = path.join(PROPERTIES_DIR, "list.xml");
  const document = loadXmlDocument(listPath);
  const root = document.root.children[0] ?? document.root;
  return root.children
    .map((node) => document.leafText(node))
    .filter((value): value is string => value !== undefined && value !== "");
}

function findTargets(templates: string[], files: string[]): Target[] {
  const registry = readRegistry().filter((file) => files.length === 0 || files.includes(file));
  const documents = new Map<string, XmlDocument>();
  const found = new Map<string, Target[]>();

  for (const file of registry) {
    const document = loadXmlDocument(path.join(PROPERTIES_DIR, file));
    documents.set(file, document);
    const root = document.root.children[0] ?? document.root;
    for (const node of root.children) {
      if (!templates.includes(node.name)) continue;
      const list = found.get(node.name) ?? [];
      const displayName = document.childText(node, "displayname") ?? "";
      list.push({ template: node.name, displayName, sourceFile: file, document, node });
      found.set(node.name, list);
    }
  }

  const targets: Target[] = [];
  for (const template of templates) {
    const hits = found.get(template);
    if (hits === undefined || hits.length === 0) {
      throw new Error(`找不到敌人模板：${template}（已搜索 ${registry.length} 个文件；可用 --file 缩小范围）`);
    }
    if (hits.length > 1) {
      throw new Error(`模板 ${template} 命中多个文件，请用 --file 指定：${hits.map((hit) => hit.sourceFile).join("、")}`);
    }
    targets.push(hits[0]!);
  }
  return targets;
}

// ============================ 读取与计算 ============================

function readFlags(document: XmlDocument, node: XmlDocumentNode, config: MonsterCensusConfig): Map<string, number> {
  const flags = new Map<string, number>();
  const block = document.childrenNamed(node, config.flagElement)[0];
  if (block === undefined) return flags;
  for (const child of block.children) {
    const value = Number(document.leafText(child));
    if (Number.isFinite(value)) flags.set(child.name, value);
  }
  return flags;
}

function readMoveSpeed(document: XmlDocument, node: XmlDocumentNode, config: MonsterCensusConfig): { min: number; max: number } | undefined {
  const min = Number(document.childText(node, config.moveSpeedFields.min));
  const max = Number(document.childText(node, config.moveSpeedFields.max));
  return Number.isFinite(min) && Number.isFinite(max) ? { min, max } : undefined;
}

/**
 * 把行内标识 + 本次覆盖拼成完整的十项系数。
 * 取值次序是「本次覆盖 > 行内已有值 > 定义档补算」，因此存量怪重算时既不会重测、也不会被重新映射；
 * 本函数不触发任何实测，阶段与观测项缺失时只报错并指回它们的来源通道。
 */
function buildCoefficients(
  target: Target,
  flags: Map<string, number>,
  overrides: Map<string, number>,
  config: MonsterCensusConfig,
): { input: MonsterInput; derived: Map<string, number> } {
  const derived = new Map<string, number>();
  const pick = (field: string): number | undefined => overrides.get(field) ?? flags.get(field);

  const missing: string[] = [];
  const valueOf = (field: string): number => {
    const value = pick(field);
    if (value === undefined) {
      missing.push(field);
      return Number.NaN;
    }
    return value;
  };

  const stage = valueOf(STAGE_FLAG);
  const tierFactor = valueOf("档次系数");
  const growthFactor = valueOf("成长系数");
  const atkSpeedFactor = valueOf("攻速系数");
  const atkMultiplier = valueOf("攻击倍率");
  const segmentFactor = valueOf("段数系数");
  const highAtkFactor = valueOf("高攻低血防系数");
  const superArmorFactor = valueOf("霸体系数");
  const highDefFactor = valueOf("高防低血系数");

  // 速度系数：行内已有就用行内（人工标过的 2.5 这类实测档要保留），没有才按定义档补。
  let speedFactor = pick("速度系数");
  if (speedFactor === undefined) {
    const moveSpeed = readMoveSpeed(target.document, target.node, config);
    if (moveSpeed !== undefined) {
      speedFactor = speedFactorFromMoveSpeed(moveSpeed.min, moveSpeed.max).value;
      derived.set("速度系数", speedFactor);
    } else {
      missing.push("速度系数");
      speedFactor = Number.NaN;
    }
  }

  if (missing.length > 0) {
    const hints: string[] = [];
    if (missing.includes(STAGE_FLAG)) {
      hints.push("阶段：先跑 `npm run monster-census` 反查首次出场关卡；未实装的怪请人工 `--set 阶段=N`。");
    }
    const observed = missing.filter((field) => OBSERVED_FLAGS.includes(field));
    if (observed.length > 0) {
      hints.push(`观测类缺项 ${observed.join("、")}：先跑 \`npm run monster-attack -- --template ${target.template}\` 实测。`);
    }
    const others = missing.filter(
      (field) => field !== STAGE_FLAG && !OBSERVED_FLAGS.includes(field) && field !== "速度系数" && !DERIVED_FLAGS.includes(field),
    );
    if (others.length > 0) hints.push(`人工给定类缺项 ${others.join("、")}：按标准流程询问用户，或由 AI 按外形判定后用 --set 给出。`);
    throw new Error(`${target.template} 缺少系数：${missing.join("、")}\n  ${hints.join("\n  ")}`);
  }

  return {
    input: {
      stage,
      tierFactor,
      growthFactor,
      atkSpeedFactor,
      atkMultiplier,
      segmentFactor,
      speedFactor,
      highAtkFactor,
      superArmorFactor,
      highDefFactor,
    },
    derived,
  };
}

function plan(target: Target, options: Options, config: MonsterCensusConfig): PlannedRow {
  const flags = readFlags(target.document, target.node, config);
  const overrides = new Map<string, number>();
  for (const entry of options.sets) {
    if (entry.template !== undefined && entry.template !== target.template) continue;
    overrides.set(entry.field, entry.value);
  }

  const { input: after, derived } = buildCoefficients(target, flags, overrides, config);
  const { input: before } = buildCoefficients(target, flags, new Map(), config);
  const output = computeMonsterRow(after);

  const panel = new Map<string, string>();
  const oldPanel = new Map<string, string>();
  for (const [xmlField, outputKey] of Object.entries(config.panelFields)) {
    const computed = output[outputKey as keyof MonsterOutput];
    if (typeof computed !== "number" || !Number.isFinite(computed)) continue;
    const rounded = xmlField.startsWith("hp_") ? roundTo(computed, options.hpRound) : Math.round(computed);
    panel.set(xmlField, String(rounded));
    oldPanel.set(xmlField, target.document.childText(target.node, xmlField) ?? "");
  }

  // 写回的标识 = 本次覆盖项 ∪ 自动补出来的定义类项（已有的实测档不动）。
  const writeFlags = new Map<string, number>(overrides);
  for (const [field, value] of derived) writeFlags.set(field, value);

  return { target, before, after, output, panel, flags: writeFlags, oldFlags: flags, oldPanel };
}

/** HP 的取整步长：100 = 整百（现网杂兵惯例），0 = 四舍五入到整数。 */
function roundTo(value: number, step: number): number {
  if (step <= 0) return Math.round(value);
  return Math.round(value / step) * step;
}

/**
 * 运行时血量：与 `_root.根据等级计算值` 同式 —— `floor(min + (max-min)/(最大等级-1) × 等级)`，
 * 再乘 `出生难度`（非 CF6 关卡 = `_root.难度等级`）。注意这里用的是「等级」而不是「等级-1」，和游戏一致。
 */
function runtimeValue(min: number, max: number, level: number, maxLevel: number, difficulty: number): number {
  return Math.floor(min + ((max - min) / (maxLevel - 1)) * level) * difficulty;
}

// ============================ 报表 ============================

function printReport(planned: PlannedRow[], options: Options): void {
  for (const row of planned) {
    const name = row.target.displayName === "" ? row.target.template : `${row.target.displayName}（${row.target.template}）`;
    console.log(`\n=== ${name} — ${row.target.sourceFile} ===`);

    const changedFlags = [...row.flags.entries()];
    if (changedFlags.length > 0) {
      console.log("  标识：");
      for (const [field, value] of changedFlags) {
        const old = row.oldFlags.get(field);
        console.log(`    ${field.padEnd(8, "　")} ${String(old ?? "-").padStart(8)} → ${String(value)}`);
      }
    } else {
      console.log("  标识：无改动");
    }

    console.log("  面板：");
    for (const [field, text] of row.panel) {
      const label = PANEL_LABELS[field] ?? field;
      const old = row.oldPanel.get(field) ?? "";
      const mark = old === text ? "  " : "→ ";
      console.log(`    ${label}  ${old.padStart(7)} ${mark}${text}`);
    }

    const hpMin = Number(row.panel.get("hp_min"));
    const hpMax = Number(row.panel.get("hp_max"));
    if (Number.isFinite(hpMin) && Number.isFinite(hpMax)) {
      const current = runtimeValue(hpMin, hpMax, options.level, options.maxLevel, options.difficulty);
      console.log(`    L${options.level} 实际血量 ≈ ${current}（难度 ×${options.difficulty}）`);
    }
  }
}


function toJson(planned: PlannedRow[], options: Options): unknown {
  return planned.map((row) => ({
    template: row.target.template,
    displayName: row.target.displayName,
    sourceFile: row.target.sourceFile,
    coefficientsBefore: row.before,
    coefficientsAfter: row.after,
    panel: Object.fromEntries(row.panel),
    panelBefore: Object.fromEntries(row.oldPanel),
    runtimeHp: {
      level: options.level,
      maxLevel: options.maxLevel,
      difficulty: options.difficulty,
      value: runtimeValue(Number(row.panel.get("hp_min")), Number(row.panel.get("hp_max")), options.level, options.maxLevel, options.difficulty),
    },
  }));
}

function warnOutOfRange(planned: PlannedRow[], config: MonsterCensusConfig): void {
  for (const row of planned) {
    for (const [flagField, coefficient] of Object.entries(MONSTER_FLAG_TO_COEFFICIENT)) {
      const range = MONSTER_COEFFICIENT_RANGES[coefficient];
      const value = row.after[coefficient];
      if (!Number.isFinite(value) || range === undefined) continue;
      if (value < range[0] || value > range[1]) {
        console.warn(`⚠ ${row.target.template} 的 ${flagField}=${value} 落在参考区间 ${range[0]}~${range[1]} 之外（仅提示，不夹紧）`);
      }
    }
  }
  void config;
}

// ============================ 写盘 ============================

function writeAll(planned: PlannedRow[], options: Options, config: MonsterCensusConfig): { files: number; rows: number } {
  const byDocument = new Map<XmlDocument, PlannedRow[]>();
  for (const row of planned) {
    const list = byDocument.get(row.target.document) ?? [];
    list.push(row);
    byDocument.set(row.target.document, list);
  }

  let changedFiles = 0;
  let changedRows = 0;
  for (const [document, rows] of byDocument) {
    let changed = false;
    for (const row of rows) {
      // 逐行记差异：只统计真的改了内容的模板，复跑时才好报「0 个文件」。
      let rowChanged = writeFlags(document, row, config);
      rowChanged = writePanel(document, row, config) || rowChanged;
      if (rowChanged) changedRows += 1;
      changed = rowChanged || changed;
    }
    if (!changed) continue;
    document.save();
    changedFiles += 1;
  }
  void options;
  return { files: changedFiles, rows: changedRows };
}

/** 只改被覆盖的标识项；同值不写，避免留下无意义 diff。 */
function writeFlags(document: XmlDocument, row: PlannedRow, config: MonsterCensusConfig): boolean {
  if (row.flags.size === 0) return false;
  const block = document.childrenNamed(row.target.node, config.flagElement)[0];
  if (block === undefined) throw new Error(`${row.target.template} 没有 <${config.flagElement}> 段，无法写系数`);
  let changed = false;
  for (const [field, value] of row.flags) {
    changed = ensureLeaf(document, block, field, formatNumber(value), true) || changed;
  }
  return changed;
}

function writePanel(document: XmlDocument, row: PlannedRow, config: MonsterCensusConfig): boolean {
  let changed = false;
  for (const [field, text] of row.panel) {
    changed = ensureLeaf(document, row.target.node, field, text, false, config) || changed;
  }
  return changed;
}

/**
 * 写一个叶子节点：已存在就改内部文本，缺失就在同层补一行（缩进按同级兄弟对齐）。
 * `insideFlagBlock = true` 时插到标识块末尾；否则插在 `<标识>` 之前，保持「面板在前、标识在后」的既有排布。
 */
function ensureLeaf(
  document: XmlDocument,
  parent: XmlDocumentNode,
  field: string,
  text: string,
  insideFlagBlock: boolean,
  config?: MonsterCensusConfig,
): boolean {
  const existing = parent.children.find((child) => child.name === field);
  if (existing !== undefined) {
    if (document.leafText(existing) === text) return false;
    document.setLeafText(existing, text);
    return true;
  }

  const entryIndent = lastChildIndent(document, parent) ?? `${indentOf(document, parent)}    `;
  if (insideFlagBlock) {
    const anchor = lastChildEnd(parent);
    document.insertTextAt(anchor, `\n${entryIndent}<${field}>${text}</${field}>`);
    return true;
  }

  const flagBlock = config === undefined ? undefined : document.childrenNamed(parent, config.flagElement)[0];
  if (flagBlock === undefined) {
    document.insertTextAt(lastChildEnd(parent), `\n${entryIndent}<${field}>${text}</${field}>`);
    return true;
  }
  // 插在 <标识> 起始标签之前：既留住它前面的换行与缩进，也不打乱后面的行。
  const blockIndent = indentOf(document, flagBlock);
  document.insertTextAt(flagBlock.startTagStart, `<${field}>${text}</${field}>\n${blockIndent}`);
  return true;
}

function lastChildIndent(document: XmlDocument, node: XmlDocumentNode): string | undefined {
  const last = node.children[node.children.length - 1];
  return last === undefined ? undefined : indentOf(document, last);
}

function lastChildEnd(node: XmlDocumentNode): number {
  const last = node.children[node.children.length - 1];
  return last === undefined ? node.innerEnd : (last.endTagEnd ?? last.innerEnd);
}

function indentOf(document: XmlDocument, node: XmlDocumentNode): string {
  const match = /([ \t]*)$/.exec(document.originalSource.slice(0, node.startTagStart));
  return match?.[1] ?? "";
}

/** 整数不补小数位；小数最多两位（与人手写标识的习惯一致）。 */
function formatNumber(value: number): string {
  return String(Math.round(value * 100) / 100);
}

// ============================ 写后校验 ============================

/** 重读落盘文件，逐字段比对；不一致直接抛错，避免「工具说写了、数据没变」。 */
function verifyAll(planned: PlannedRow[], config: MonsterCensusConfig): void {
  const cache = new Map<string, XmlDocument>();
  for (const row of planned) {
    const filePath = path.join(PROPERTIES_DIR, row.target.sourceFile);
    let document = cache.get(filePath);
    if (document === undefined) {
      document = loadXmlDocument(filePath);
      cache.set(filePath, document);
    }
    const root = document.root.children[0] ?? document.root;
    const node = root.children.find((child) => child.name === row.target.template);
    if (node === undefined) throw new Error(`校验失败：重读 ${row.target.sourceFile} 找不到 ${row.target.template}`);

    for (const [field, text] of row.panel) {
      const actual = document.childText(node, field);
      if (actual !== text) {
        throw new Error(`校验失败：${row.target.template} 的 ${field} 写入 ${text}，重读为 ${actual ?? "(空)"}`);
      }
    }
    const flags = readFlags(document, node, config);
    for (const [field, value] of row.flags) {
      if (flags.get(field) !== value) {
        throw new Error(`校验失败：${row.target.template} 的 ${field} 写入 ${value}，重读为 ${flags.get(field)}`);
      }
    }
  }
}

// ============================ explain ============================

function printExplain(): void {
  const range = (field: string): string => {
    const coefficient = MONSTER_FLAG_TO_COEFFICIENT[field] as MonsterCoefficientName;
    const bounds = MONSTER_COEFFICIENT_RANGES[coefficient];
    return bounds === undefined ? "-" : `${bounds[0]} ~ ${bounds[1]}`;
  };
  const lines: string[] = [];

  lines.push("怪物数值重算（正算：<标识> 系数 → 面板）");
  lines.push("公式权威：packages/core/src/formulas/monsters.ts（= 工作簿《怪物大致面板》）");
  lines.push("数据位置：data/enemy_properties/*.xml（按 list.xml 注册）");
  lines.push("");
  lines.push("一、系数分三类（下面所有区间与定义均取自工作簿，不是经验印象）");
  lines.push("");
  lines.push("  观测类（实测得出，不要手填）");
  lines.push(`    攻速系数        参考 ${range("攻速系数")}    单次攻击的总时长与前后摇：1 极慢 … 5 极快，默认 3`);
  lines.push(`    攻击倍率        参考 ${range("攻击倍率")}  平均每次攻击的平均倍率，默认 1~2（通常 1~3）；法伤招式 ×2、真伤 ×3 折算`);
  lines.push(`    段数系数        参考 ${range("段数系数")}   平均每次攻击的段数，默认 3（大致 1~10）`);
  lines.push(`    霸体系数        参考 ${range("霸体系数")}  由击退/击飞动画定整数位（见下表）；韧性 >20 时每 20 点 +0.1，最高 +0.5`);
  lines.push("    入口：npm run monster-attack -- --template 敌人-XXX");
  lines.push("");
  lines.push("  定义映射类（按现有数据自动定，不要手填）");
  lines.push(`    速度系数        参考 ${range("速度系数")}    移动速度落档：10~40 慢=1、40~60 中=2、60~90 快=3（区间上限归本档）`);
  lines.push(`    阶段            参考 ${range("阶段")}   首次出场关卡反查；未实装的怪必须人工补`);
  lines.push("");
  lines.push("  人工给定类（调平衡只动这四项，括注为工作簿原话）");
  lines.push(`    成长系数        参考 ${range("成长系数")}  「范围 0.5~2，默认 1；系数高代表低级时更弱但高等级时更强」`);
  lines.push(`    高攻低血防系数  参考 ${range("高攻低血防系数")}  「默认 1，范围 0.5~2；2 代表攻击力明显更高、血防明显更低，`);
  lines.push("                                0.5 代表血防明显更高、攻击力更低」；同时压 HP 与防御");
  lines.push(`    高防低血系数    参考 ${range("高防低血系数")}  「默认 1，通常 0.2~5，最大 0.1~10；数值越高防御越高、血量越低，`);
  lines.push("                                视觉和设定上更硬的单位应给更高值」；只压 HP（开根号），防御反而升高");
  lines.push("");
  lines.push("  档次系数（工作簿 B19~C32 原表，逐条抄录，只保留注释）：");
  lines.push("    系数     档次        注释");
  for (const row of TIER_TABLE) {
    lines.push(`    ${row.band.padEnd(8, " ")} ${row.label.padEnd(6, "　")} ${row.note}`);
  }
  lines.push("    工作簿备注：档次定位仅相对当前阶段，不代表绝对数值；");
  lines.push("                不同档次之间的系数有间隔，可按具体情况插空或上下浮动；多阶段单位按合计评档。");
  lines.push("");
  lines.push("  阶段系数（工作簿 B19~C32）：");
  for (const row of STAGE_TABLE) {
    lines.push(`    ${row.stage.padEnd(6, " ")} ${row.label}${row.note === "" ? "" : `（${row.note}）`}`);
  }
  lines.push("");
  lines.push("  霸体系数（工作簿）：");
  for (const row of ARMOR_TABLE) {
    lines.push(`    ${row.band}  ${row.label}`);
  }
  lines.push("");
  lines.push("二、标准流程（AI 必须按这个顺序）");
  lines.push("  1. 询问用户是否指定 档次/成长/高攻低血防/高防低血；给了就照用户的值。");
  lines.push("  2. 没给的，由 AI 对照上面的档次表、按外形与定位判定，并在回报里写依据（哪一档、为什么）。");
  lines.push("  3. 观测类/定义类不准手填。存量怪行内已有值直接沿用，不重测、不重映射，重算只动人工四项；");
  lines.push("     只有新建怪、动作/元件改过、阶段无出场记录，或用户明确要求重算时才去实测/反查。");
  lines.push("  4. npm run monster-recalc -- preview --templates ... --set ...");
  lines.push("  5. 确认后 npm run monster-recalc -- apply --templates ... --set ...（写盘后自动重读校验）");
  lines.push("  提醒：工作簿写明「暖机、强力 buff、多阶段等显著影响面板的特殊机制单位」这套估法可能不适用。");
  lines.push("");
  lines.push("三、取整约定");
  lines.push("  HP       默认取整百（--hp-round 100）；现有 2011-2012 那批杂兵就是这个口径");
  lines.push("  攻击/防御/经验  四舍五入到整数");
  lines.push("");
  lines.push("四、本次可用的命令");
  lines.push('  npm run monster-recalc -- preview --templates 敌人-A,敌人-B --set "敌人-A.高防低血系数=1.5" --level 20');
  lines.push('  npm run monster-recalc -- apply   --templates 敌人-A,敌人-B --set "..." [--dry-run]');
  console.log(lines.join("\n"));
}

main(process.argv.slice(2));
