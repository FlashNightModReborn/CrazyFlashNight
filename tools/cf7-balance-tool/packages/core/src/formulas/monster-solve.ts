/**
 * 怪物标识反推 — monsters.ts 正算的逆问题。
 *
 * 通道分工（制作组 2026-10-05 口径）：
 * - 观测系数不参与反推：攻速系数／攻击倍率／段数系数 来自攻击动作实测，霸体系数 来自击退与击飞元件观测，
 *   速度系数 先按 Excel D15 的移动速度档次取定义档。缺观测时按工作簿默认值参与拟合，同时记进未定清单，
 *   由写盘侧跳过 —— 面板不能替动画做判断。
 * - 反推只解四个自由量：档次系数、成长系数、高攻低血防系数、高防低血系数，用空手攻击／HP／防御六项面板做联合最小二乘。
 *   这四量与六项公式之间没有可用的闭式解：HP 与防御共用「高攻低血防 × √高防低血」这一乘积，
 *   空手两项里档次与成长又互相抵消，所以按「档次粗格 × 成长粗格 → 血防交替乘性线搜索 → 四量细扫」求数值最优。
 * - 经验两项不进误差目标（制作组口径：经验是随时可按标识重算的数值，不承载成长信息），只在结果里单列供复核。
 * - 档次系数放开拟合会带来四类必须顶给人工的报警：解落在参考区间下界/上界之外、解停在搜索网格两端（下 0.1、上 200）、面板方程数少于自由量。
 *   搜索网格本身不受参考区间约束（2026-10-06 制作组口径：Excel 的 1~25 只是正常情况的范围，不是上下限），越界只登记不夹紧。
 * - 参考区间只用来列「越界待人工修正」名单，不参与搜索边界也不夹紧取值：夹紧会把面板误差伪装成反推误差。
 */
import { computeMonsterRow } from "./monsters.js";
import type { MonsterInput, MonsterOutput } from "./monsters.js";

export type MonsterCoefficientName = keyof MonsterInput;
export type MonsterPanelField = keyof MonsterOutput;

/** 敌人属性里可观察到的面板值，取正算输出字段的任意子集。 */
export type MonsterPanel = Partial<Record<MonsterPanelField, number>>;

/** 进入误差目标的六项面板：空手攻击、HP、防御。 */
export const MONSTER_FIT_PANEL_FIELDS: MonsterPanelField[] = ["atkMin", "atkMax", "hpMin", "hpMax", "defMin", "defMax"];

/** 只对照、不进误差目标的经验两项。 */
export const MONSTER_EXP_PANEL_FIELDS: MonsterPanelField[] = ["expMin", "expMax"];

/** 反推的自由量；被观测或人工钉住的那几个自动退出搜索。 */
export const MONSTER_FIT_FREE_COEFFICIENTS: MonsterCoefficientName[] = ["tierFactor", "growthFactor", "highAtkFactor", "highDefFactor"];

/** 只能由动画/元件观测得到的系数：缺值时按默认参与拟合并进未定清单，绝不由面板写盘。 */
export const MONSTER_OBSERVED_COEFFICIENTS: MonsterCoefficientName[] = ["atkSpeedFactor", "atkMultiplier", "segmentFactor", "superArmorFactor"];

export interface MonsterFitRequest {
  /** 阶段：由首次出现关卡的主线/支线规则推出，或人工标注。 */
  stage: number;
  panel: MonsterPanel;
  /** 已钉住的系数（观测值或人工判定）；拟合只填补未钉住的自由量。 */
  known?: Partial<MonsterInput>;
  /** 敌人属性里的移动速度区间：Excel D15 用它定速度系数档次。 */
  moveSpeed?: { min: number; max: number };
  /** 档次系数的搜索网格，缺省用 `tierFitCandidates()`：Excel 档次表的词表粒度，向下到 0.1，解顶到上界时按需加长。 */
  tierCandidates?: number[];
}

/** 系数的来源标签：人工或观测钉住、移动速度定义档、面板反推。 */
export type CoefficientConfidence = "given" | "definition-band" | "panel-fit";

export interface CoefficientEstimate {
  name: MonsterCoefficientName;
  value: number;
  confidence: CoefficientConfidence;
  /** 依据的面板字段或规则，供人工复核。 */
  basis: string;
}

export interface MonsterPanelResidual {
  field: MonsterPanelField;
  observed: number;
  computed: number;
  relativeError: number;
}

/** 反推值落在参考区间之外的系数，取值仍按实算采用。 */
export interface MonsterOutOfRangeCoefficient {
  name: MonsterCoefficientName;
  value: number;
  range: [number, number];
}

export interface MonsterFitResult {
  coefficients: MonsterInput;
  estimates: CoefficientEstimate[];
  /** 既无观测又无面板依据、只能按默认值参与拟合的系数，写盘侧必须跳过。 */
  unresolved: MonsterCoefficientName[];
  /** 本次实际参与拟合的自由量（档次系数被人工钉住时不在其中）。 */
  freeCoefficients: MonsterCoefficientName[];
  /** 参与拟合的面板项数。 */
  equations: number;
  /** 计入误差的六项面板的相对误差均方根；经验两项不计入。 */
  fitError: number;
  residuals: MonsterPanelResidual[];
  /** 经验两项的复算对照，只给人看，不影响 fitError。 */
  expResiduals: MonsterPanelResidual[];
  /** 反推值超出参考区间的系数：取值照登，只集中列出来给人工复核区间。 */
  outOfRange?: MonsterOutOfRangeCoefficient[];
  notes: string[];
}

/** Excel D11~D17 注释给出的默认系数。 */
export const MONSTER_COEFFICIENT_DEFAULTS: Omit<MonsterInput, "stage" | "tierFactor"> = {
  growthFactor: 1,
  atkSpeedFactor: 3,
  atkMultiplier: 1,
  segmentFactor: 3,
  speedFactor: 2,
  highAtkFactor: 1,
  superArmorFactor: 1,
  highDefFactor: 1,
};

/**
 * Excel C11~C17 与各参考表给出的取值范围。
 * 这是**参考区间**（判断算出来的值合不合理），不是硬区间：反推算出多少就登记多少，不夹紧，
 * 超出者集中到结果的 `outOfRange` 里由人工复核区间本身；夹紧会把面板误差伪装成反推误差。
 * 成长系数按制作组 2026-10-05 口径放宽：工作簿推荐 0.5~2，实算面板要 0.2~5 才谈得上合。
 */
export const MONSTER_COEFFICIENT_RANGES: Record<MonsterCoefficientName, [number, number]> = {
  stage: [1, 15],
  tierFactor: [1, 25],
  growthFactor: [0.2, 5],
  atkSpeedFactor: [1, 5],
  atkMultiplier: [0.5, 3],
  segmentFactor: [1, 10],
  speedFactor: [1, 3],
  highAtkFactor: [0.5, 2],
  superArmorFactor: [1, 5.5],
  highDefFactor: [0.1, 10],
};

/** HP 公式里的两段霸体乘子，与 Excel P/Q 列的 IF(AND(...)) 一致。 */
export function superArmorHpFactor(tierFactor: number, superArmorFactor: number): number {
  const longKnockback = tierFactor < 9 && superArmorFactor > 3 ? 1 - superArmorFactor / 50 : 1;
  const shortKnockback = tierFactor > 12 && superArmorFactor < 5 ? 1 + 1 / superArmorFactor : 1;
  return longKnockback * shortKnockback;
}

/**
 * Excel D15：移动速度 10-40 慢、40-60 中、60-90 快，对应速度系数 1/2/3。
 * 区间上限归本档：现存标注里 速度_min/max 均值正好落在 60 的三行都标 2，不是 3。
 */
export function speedBandOf(moveSpeed: number): 1 | 2 | 3 {
  if (moveSpeed <= 40) return 1;
  if (moveSpeed <= 60) return 2;
  return 3;
}

/**
 * 速度系数的定义通道：Excel D15 用移动速度区间定义慢/中/快，取值按 速度_min 与 速度_max 的均值落在哪一档。
 * 现存标注的 9 行实测：按均值 8/9 命中，按 速度_min 只有 6/9，按 速度_max 只有 2/9。
 * 区间跨档时 upper 给出 速度_min 档与 速度_max 档的中点（如 2.5），
 * 这是设计实操里对跨档怪写小数档次的写法，由人工按手感在 value 与 upper 之间取。
 * 面板拟合只消费这个值，不再从防御公式反解速度系数去覆盖它。
 */
export function speedFactorFromMoveSpeed(min: number, max: number): { value: number; upper: number } {
  const low = speedBandOf(min);
  const high = speedBandOf(max);
  const value = speedBandOf((min + max) / 2);
  return { value, upper: high > low ? (low + high) / 2 : value };
}

/** Excel H34：韧性系数高于 20 时每 20 点加 0.1 霸体系数，上限 0.5。 */
export function superArmorDecimalFromTenacity(tenacityCoefficient: number): number {
  if (tenacityCoefficient <= 20) return 0;
  return Math.min(0.5, Math.floor(tenacityCoefficient / 20) * 0.1);
}

/** 标识取值档位：整数优先，半档其次，十分档最细。 */
export type MonsterCoefficientGrid = "integer" | "half" | "tenth";

/** 取值词表的下限，也是写进标识的最小正数。 */
const SNAP_FLOOR = 0.1;

/**
 * 反推得到的连续解归到制作组的取值词表上：整数 → 0.5 半档 → 0.1 十分档，逐档放宽。
 * 现存标注的取值词表是按系数实测出来的：速度/攻速/倍率/段数/档次全在 0.5 网格上，
 * 成长、高攻低血防、高防低血里约 1/4 的用例需要 0.1（含一例 1.25），所以不能只给整数。
 * 相邻两档只差一档的容差内（0.05）算“够用”，因此连续解 2.014 取 2、1.840 取 1.8。
 * 词表没有 0 档：十项系数全都站在公式分母或指数上，写 0 会把面板算成无穷大，所以最低落到 0.1。
 */
export function snapMonsterCoefficient(value: number): { value: number; grid: MonsterCoefficientGrid } {
  const integer = Math.round(value);
  if (integer !== 0 && Math.abs(value - integer) <= 0.05) return { value: integer, grid: "integer" };
  const half = Math.round(value * 2) / 2;
  if (half !== 0 && Math.abs(value - half) <= 0.05) return { value: half, grid: "half" };
  return { value: Math.max(SNAP_FLOOR, Math.round(value * 10) / 10), grid: "tenth" };
}

/**
 * 档次系数的搜索网格：1 以下按十分档下探到取值词表下界 0.1，1~10 半档，11 以上按整数上探。
 * 档次是设计判断，拟合只在这个词表上取，所以不会写出 19.36 这类不在档次表上的值。
 * **网格与 `MONSTER_COEFFICIENT_RANGES.tierFactor` 无关**（制作组 2026-10-06 口径）：
 * Excel 的 1~25 只是正常情况参考区间，不是上下限；解出多少就登记多少，越界只进 `outOfRange` 与超范围表。
 * 上界之外的整数档由 `searchFit` 在解贴住网格上界时按块加长；下界 0.1 是取值词表的硬底（写 0 会把面板算成无穷大），
 * 贴住它说明面板比公式能表达的最低档还弱，只能回查面板。
 */
const TIER_SEARCH_FLOOR = 0.1;
const TIER_SEARCH_TENTH_TOP = 0.9;
const TIER_SEARCH_HALF_TOP = 10;
const TIER_SEARCH_INITIAL_TOP = 25;
const TIER_SEARCH_BLOCK = 25;
const TIER_SEARCH_HARD_CAP = 200;

export function tierFitCandidates(top: number = TIER_SEARCH_INITIAL_TOP): number[] {
  const grid: number[] = [];
  for (let value = TIER_SEARCH_FLOOR; value <= TIER_SEARCH_TENTH_TOP + 1e-9; value += 0.1) {
    grid.push(Math.round(value * 10) / 10);
  }
  for (let value = 1; value <= Math.min(TIER_SEARCH_HALF_TOP, top) + 1e-9; value += 0.5) {
    grid.push(Math.round(value * 100) / 100);
  }
  for (let value = TIER_SEARCH_HALF_TOP + 1; value <= top; value += 1) grid.push(value);
  return grid;
}

/** 网格已经解到上界，就再往上加一块整数档；返回加长后的整张网格。 */
function extendTierGrid(grid: number[]): number[] {
  const current = grid[grid.length - 1] ?? TIER_SEARCH_INITIAL_TOP;
  const extended = [...grid];
  for (let value = current + 1; value <= Math.min(current + TIER_SEARCH_BLOCK, TIER_SEARCH_HARD_CAP); value += 1) {
    extended.push(value);
  }
  return extended;
}

/** 成长的粗格按可用带回扫；细扫允许越出可用带，好让真需要极端值的行暴露出来而不是顶在边界。 */
const COARSE_GROWTH_LOW = 0.2;
const COARSE_GROWTH_HIGH = 5;
const COARSE_GROWTH_STEP = 0.25;
const GROWTH_FLOOR = 0.05;
const GROWTH_CAP = 12;
const RATIO_FLOOR = 0.01;
const RATIO_CAP = 60;
/** 乘性步长：先大步跳出量级，再小步收敛。 */
const COARSE_STEPS = [0.25, 0.4, 0.55, 0.7, 0.85, 0.95, 1, 1.05, 1.2, 1.4, 1.7, 2.2, 3];
const REFINE_STEPS = [0.4, 0.6, 0.8, 0.9, 1.1, 1.25, 1.6, 2.5];
const COARSE_PASSES = 6;
const REFINE_ROUNDS = 4;
/** 档次细扫只在网格邻域内挪，避免写出 19.36 这类不在档次词表上的值。 */
const TIER_REFINE_RADIUS = 3;

type FreeKey = "tierFactor" | "growthFactor" | "highAtkFactor" | "highDefFactor";

/** 一次评估用的四个自由量；rms 是它们对应的面板拟合误差。 */
interface FitPoint {
  tierFactor: number;
  growthFactor: number;
  highAtkFactor: number;
  highDefFactor: number;
  rms: number;
}

type Score = (point: Omit<FitPoint, "rms">) => number;

export function fitMonsterCoefficients(request: MonsterFitRequest): MonsterFitResult {
  const stage = request.stage;
  if (!Number.isFinite(stage) || stage <= 0) {
    throw new Error("怪物反推需要正的阶段（阶段）");
  }

  const notes: string[] = [];
  const estimates: CoefficientEstimate[] = [];
  const unresolved: MonsterCoefficientName[] = [];
  const known = request.known ?? {};
  const pinned = new Set(Object.keys(known) as MonsterCoefficientName[]);
  const coefficients: MonsterInput = { stage, tierFactor: 1, ...MONSTER_COEFFICIENT_DEFAULTS, ...known };

  // 速度系数：标识给定值优先，其次 Excel D15 的移动速度定义档，两者都没有才按默认参与拟合并记未定。
  if (pinned.has("speedFactor")) {
    pushGiven(estimates, "speedFactor", coefficients.speedFactor);
  } else if (request.moveSpeed !== undefined) {
    const band = speedFactorFromMoveSpeed(request.moveSpeed.min, request.moveSpeed.max);
    coefficients.speedFactor = band.value;
    estimates.push({
      name: "speedFactor",
      value: band.value,
      confidence: "definition-band",
      basis: `移动速度 ${request.moveSpeed.min}~${request.moveSpeed.max} 按 Excel D15 取均值档次${band.upper !== band.value ? `，跨档可取两档中点 ${band.upper}` : ""}`,
    });
  } else {
    unresolved.push("speedFactor");
    notes.push(`速度系数 既无标识也读不到 速度_min/max，按默认 ${coefficients.speedFactor} 参与拟合`);
  }
  for (const name of pinned) {
    if (name !== "speedFactor") pushGiven(estimates, name, coefficients[name]);
  }

  const missingObserved = MONSTER_OBSERVED_COEFFICIENTS.filter((name) => !pinned.has(name));
  if (missingObserved.length > 0) {
    unresolved.push(...missingObserved);
    notes.push(`${missingObserved.map((name) => COEFFICIENT_LABEL[name]).join("、")} 缺观测，按工作簿默认值参与拟合（攻速系数/攻击倍率/段数系数 只以乘积进入空手攻击，面板定不了它们）`);
  }

  const fields = MONSTER_FIT_PANEL_FIELDS.filter((field) => {
    const value = request.panel[field];
    return value !== undefined && Number.isFinite(value);
  });
  const targets: MonsterPanel = {};
  for (const field of fields) Object.assign(targets, { [field]: request.panel[field] as number });

  const nonPositive = fields.filter((field) => (request.panel[field] as number) <= 0);
  if (nonPositive.length > 0) {
    notes.push(`面板的 ${nonPositive.map((field) => PANEL_FIELD_LABEL[field]).join("、")} 不是正数，公式给不出非正结果，只能回查面板数值`);
  }

  const free = MONSTER_FIT_FREE_COEFFICIENTS.filter((name) => !pinned.has(name)) as FreeKey[];
  const fitted = searchFit({
    base: coefficients,
    targets,
    fields,
    free,
    tierCandidates: request.tierCandidates ?? tierFitCandidates(),
  });

  const solved: MonsterInput = { ...coefficients, ...fitted };
  for (const key of free) {
    estimates.push({
      name: key,
      value: round(solved[key], 6),
      confidence: "panel-fit",
      basis: `空手/HP/防御 ${fields.length} 项面板联立拟合，与 档次系数、成长系数、高攻低血防系数、高防低血系数 一起解`,
    });
  }

  const output = computeMonsterRow(solved);
  const residuals = panelResiduals(targets, output);
  const expTargets: MonsterPanel = {};
  for (const field of MONSTER_EXP_PANEL_FIELDS) {
    const value = request.panel[field];
    if (value !== undefined && Number.isFinite(value)) Object.assign(expTargets, { [field]: value });
  }

  const outOfRange: MonsterOutOfRangeCoefficient[] = [];
  for (const name of Object.keys(MONSTER_COEFFICIENT_RANGES) as MonsterCoefficientName[]) {
    const [low, high] = MONSTER_COEFFICIENT_RANGES[name];
    const value = solved[name];
    if (value < low || value > high) outOfRange.push({ name, value: round(value, 6), range: [low, high] });
  }

  if (free.includes("tierFactor") && solved.tierFactor < MONSTER_COEFFICIENT_RANGES.tierFactor[0]) {
    notes.push(`档次系数 ${solved.tierFactor} 低于参考区间下限 ${MONSTER_COEFFICIENT_RANGES.tierFactor[0]}：面板比最小怪还弱，阶段或档次归属可疑`);
  }
  if (free.includes("tierFactor") && solved.tierFactor > MONSTER_COEFFICIENT_RANGES.tierFactor[1]) {
    notes.push(`档次系数 ${solved.tierFactor} 高于参考区间上限 ${MONSTER_COEFFICIENT_RANGES.tierFactor[1]}：面板比顶级 boss 还强，阶段或档次归属可疑（搜索网格无此上限，这是实算值）`);
  }
  if (free.includes("tierFactor") && solved.tierFactor <= TIER_SEARCH_FLOOR) {
    notes.push(`档次系数 停在取值词表下界 ${TIER_SEARCH_FLOOR}：网格已放开到 0 以上仍解不满，面板比公式能表达的最低档还弱，只能回查面板`);
  }
  if (free.includes("tierFactor") && tierSaturatesAtGridTop(solved.tierFactor)) {
    notes.push(`档次系数 停在搜索网格上界 ${TIER_SEARCH_HARD_CAP}：网格已按无上限放开仍解不满，面板与公式不合，必须先回查面板数值`);
  }
  if (fields.length < free.length) {
    notes.push(`面板只有 ${fields.length} 项可参与、自由量有 ${free.length} 个，方程数少于自由量，解不唯一，误差小不代表标识可信`);
  }

  return {
    coefficients: solved,
    estimates,
    unresolved,
    freeCoefficients: free,
    equations: fields.length,
    fitError: round(residualRms(residuals), 6),
    residuals,
    expResiduals: panelResiduals(expTargets, output),
    ...(outOfRange.length === 0 ? {} : { outOfRange }),
    notes: [...new Set(notes)],
  };
}

function pushGiven(estimates: CoefficientEstimate[], name: MonsterCoefficientName, value: number): void {
  estimates.push({ name, value, confidence: "given", basis: "观测或人工给定的系数，不参与拟合" });
}

interface FitSearch {
  base: MonsterInput;
  targets: MonsterPanel;
  fields: MonsterPanelField[];
  free: FreeKey[];
  tierCandidates: number[];
}

/** 档次粗格 × 成长粗格，每格里对 高攻低血防／高防低血 做交替乘性线搜索，最后四个自由量轮流细扫。 */
function searchFit(input: FitSearch): Omit<FitPoint, "rms"> {
  const { base, targets, fields, free } = input;
  const measure = scoreFor(base, targets, fields);

  const start: Omit<FitPoint, "rms"> = {
    tierFactor: base.tierFactor,
    growthFactor: base.growthFactor,
    highAtkFactor: base.highAtkFactor,
    highDefFactor: base.highDefFactor,
  };
  if (fields.length === 0 || free.length === 0) return start;
  let best: FitPoint = { ...start, rms: measure(start) };

  const tierIsFree = free.includes("tierFactor");
  const growths = free.includes("growthFactor") ? coarseGrowthGrid() : [base.growthFactor];
  const ratioKeys = free.filter((key) => key === "highAtkFactor" || key === "highDefFactor");
  let pending = tierIsFree ? input.tierCandidates : [];
  let grid = pending;

  while (true) {
    const tiers = tierIsFree ? pending : [base.tierFactor];
    for (const tierFactor of tiers) {
      for (const growthFactor of growths) {
        const seed: Omit<FitPoint, "rms"> = { tierFactor, growthFactor, highAtkFactor: base.highAtkFactor, highDefFactor: base.highDefFactor };
        let point: FitPoint = { ...seed, rms: measure(seed) };
        for (let pass = 0; pass < COARSE_PASSES; pass += 1) {
          for (const key of ratioKeys) point = sweep(point, key, COARSE_STEPS, measure);
        }
        if (point.rms < best.rms) best = point;
      }
    }

    for (let cycle = 0; cycle < REFINE_ROUNDS; cycle += 1) {
      for (const key of free) {
        best = key === "tierFactor" ? sweepTierGrid(best, grid, measure) : sweep(best, key, REFINE_STEPS, measure);
      }
    }

    // 解贴住网格上界说明面板要的档次比上界还高，加长整数档继续搜；其余情况（含钉住档次、空网格）就此收。
    const top = grid[grid.length - 1];
    if (!tierIsFree || top === undefined || best.tierFactor < top || top >= TIER_SEARCH_HARD_CAP) break;
    const extended = extendTierGrid(grid);
    pending = extended.slice(grid.length);
    grid = extended;
  }

  return {
    tierFactor: best.tierFactor,
    growthFactor: best.growthFactor,
    highAtkFactor: best.highAtkFactor,
    highDefFactor: best.highDefFactor,
  };
}

/** 本次搜索是否停在网格上界之外够不到的地方：只用于报警，取值仍按实算登记。 */
function tierSaturatesAtGridTop(tierFactor: number): boolean {
  return tierFactor >= TIER_SEARCH_HARD_CAP;
}

/** 误差函数：只算被钉住的观测系数，四个自由量每次重建一份正算输入。 */
function scoreFor(base: MonsterInput, targets: MonsterPanel, fields: MonsterPanelField[]): Score {
  return (point) => {
    const out = computeMonsterRow({ ...base, ...point });
    let sum = 0;
    for (const field of fields) {
      const observed = targets[field] as number;
      const relative = Math.abs(out[field] - observed) / (Math.abs(observed) + 1e-9);
      sum += relative * relative;
    }
    return Math.sqrt(sum / fields.length);
  };
}

function coarseGrowthGrid(): number[] {
  const grid: number[] = [];
  for (let value = COARSE_GROWTH_LOW; value <= COARSE_GROWTH_HIGH + 1e-9; value += COARSE_GROWTH_STEP) {
    grid.push(Math.round(value * 100) / 100);
  }
  return grid;
}

/** 单量乘性线搜索：围绕当前值上下试步长，取到更优即更新，由外层多轮收敛。档次走 sweepTierGrid，不经这里。 */
function sweep(point: FitPoint, key: Exclude<FreeKey, "tierFactor">, steps: number[], measure: Score): FitPoint {
  const [floor, cap] = key === "growthFactor" ? [GROWTH_FLOOR, GROWTH_CAP] : [RATIO_FLOOR, RATIO_CAP];
  let best = point;
  for (const step of steps) {
    const value = Math.min(cap, Math.max(floor, point[key] * step));
    if (value === point[key]) continue;
    const score = measure({ ...best, [key]: value });
    if (score < best.rms) best = { ...best, [key]: value, rms: score };
  }
  return best;
}

/** 档次只沿 Excel 档次网格挪：写进标识的档次必须落在词表上。 */
function sweepTierGrid(point: FitPoint, candidates: number[], measure: Score): FitPoint {
  const index = nearestIndex(candidates, point.tierFactor);
  let best = point;
  for (let offset = -TIER_REFINE_RADIUS; offset <= TIER_REFINE_RADIUS; offset += 1) {
    const tierFactor = candidates[index + offset];
    if (tierFactor === undefined || tierFactor === best.tierFactor) continue;
    const score = measure({ ...best, tierFactor });
    if (score < best.rms) best = { ...best, tierFactor, rms: score };
  }
  return best;
}

function nearestIndex(values: number[], value: number): number {
  let best = 0;
  let bestGap = Number.POSITIVE_INFINITY;
  for (let index = 0; index < values.length; index += 1) {
    const gap = Math.abs((values[index] as number) - value);
    if (gap < bestGap) {
      best = index;
      bestGap = gap;
    }
  }
  return best;
}

const COEFFICIENT_LABEL: Record<MonsterCoefficientName, string> = {
  stage: "阶段",
  tierFactor: "档次系数",
  growthFactor: "成长系数",
  atkSpeedFactor: "攻速系数",
  atkMultiplier: "攻击倍率",
  segmentFactor: "段数系数",
  speedFactor: "速度系数",
  highAtkFactor: "高攻低血防系数",
  superArmorFactor: "霸体系数",
  highDefFactor: "高防低血系数",
};

const PANEL_FIELD_LABEL: Record<MonsterPanelField, string> = {
  atkMin: "空手攻击力_min",
  atkMax: "空手攻击力_max",
  hpMin: "hp_min",
  hpMax: "hp_max",
  defMin: "基本防御力_min",
  defMax: "基本防御力_max",
  expMin: "最小经验值",
  expMax: "最大经验值",
  goldPrice: "金币价格",
  kPointPrice: "K点价格",
};

function panelResiduals(panel: MonsterPanel, computed: MonsterOutput): MonsterPanelResidual[] {
  const residuals: MonsterPanelResidual[] = [];
  for (const key of Object.keys(panel) as MonsterPanelField[]) {
    const observed = panel[key];
    if (observed === undefined || !Number.isFinite(observed)) continue;
    const value = computed[key];
    residuals.push({
      field: key,
      observed,
      computed: value,
      relativeError: Math.abs(value - observed) / (Math.abs(observed) + 1e-9),
    });
  }
  return residuals.sort((left, right) => right.relativeError - left.relativeError);
}

function residualRms(residuals: MonsterPanelResidual[]): number {
  if (residuals.length === 0) return 0;
  return Math.sqrt(residuals.reduce((sum, item) => sum + item.relativeError ** 2, 0) / residuals.length);
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}
