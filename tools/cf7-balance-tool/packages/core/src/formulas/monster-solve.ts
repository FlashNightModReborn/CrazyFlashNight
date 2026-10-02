/**
 * 怪物标识反推求解器 — monsters.ts 正算的逆问题。
 *
 * 可辨识性（面板字段 → 标识系数），结构与 Excel《怪物大致面板》N~W 列一致：
 * - 成长系数 E 有三条互相独立的通道：空手攻击 MAX/MIN 之比、经验 MIN、经验 MAX（HP 之比需先知道霸体乘子）。
 *   同一 E 由多条通道给出，因此通道分歧可用来怀疑阶段或档次系数。
 * - 高攻低血防 J、高防低血 L、速度系数 I、霸体乘子只出现在防御与 HP 公式里，与攻击节奏无关，
 *   但那里只有三条独立方程：defMin 关联 L 与 L/J，defMax 关联 L/J 与 I，HP 对（比值已被成长系数锁死）
 *   关联 J*sqrt(L) 与 I 的乘积和霸体乘子。所以必须先把速度系数 I 定住，J、L 才闭式可解，HP 残差才等于霸体乘子。
 *   I 有三条来路：人工给定；J 与 L 都已给定时由 defMax 闭式解出（残缺标识的怪多属这种，优先采用）；
 *   否则只能用 Excel D15 的移动速度档次取整数。三条都没有时只能取一参数族
 *   （本求解器按霸体乘子=1 参数化，并把速度系数标为联立估计）。
 * - 攻击倍率 G、段数系数 H、攻速系数 F 只以乘积 G*sqrt(H)*1.2^(F-3) 进入空手攻击，
 *   面板只能确定该乘积，必须由攻击动作观测拆分，故记为未定。
 * - 档次系数 D 是设计判断，且金币/K 点价格没有落在敌人属性里，只能由人工给定。
 */
import { computeMonsterRow } from "./monsters.js";
import type { MonsterInput, MonsterOutput } from "./monsters.js";

export type MonsterCoefficientName = keyof MonsterInput;
export type MonsterPanelField = keyof MonsterOutput;

/** 敌人属性里可观察到的面板值，取正算输出字段的任意子集。 */
export type MonsterPanel = Partial<Record<MonsterPanelField, number>>;

export interface MonsterSolveRequest {
  /** 阶段：由首次出现关卡的主线/支线规则推出，或人工标注。 */
  stage: number;
  /** 档次系数：设计判断，不可由面板反推。 */
  tierFactor: number;
  panel: MonsterPanel;
  /** 已给定的基础系数；求解只填补未给定的字段。 */
  known?: Partial<MonsterInput>;
  /** 敌人属性里的移动速度区间：Excel D15 用它定速度系数档次。 */
  moveSpeed?: { min: number; max: number };
}

export type CoefficientConfidence = "given" | "closed-form" | "definition-band" | "joint-solve" | "workbook-default";

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

export interface MonsterSolveResult {
  coefficients: MonsterInput;
  estimates: CoefficientEstimate[];
  /** 面板无法唯一确定的系数，需要人工按动画/设定补。 */
  unresolved: MonsterCoefficientName[];
  /** 攻击节奏乘积目标 G*sqrt(H)*1.2^(F-3)，供人工拆分攻速系数/攻击倍率/段数系数。 */
  attackTempoTarget?: number;
  residuals: MonsterPanelResidual[];
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

/** Excel C11~C17 与各参考表给出的取值范围。 */
export const MONSTER_COEFFICIENT_RANGES: Record<MonsterCoefficientName, [number, number]> = {
  stage: [1, 15],
  tierFactor: [1, 25],
  growthFactor: [0.5, 2],
  atkSpeedFactor: [1, 5],
  atkMultiplier: [0.5, 3],
  segmentFactor: [1, 10],
  speedFactor: [1, 3],
  highAtkFactor: [0.5, 2],
  superArmorFactor: [1, 5.5],
  highDefFactor: [0.1, 10],
};

const ATTACK_BASE = 5;
const ATTACK_BASE_MAX = 40;
const DEFENSE_MIN_TERM = 30;
const DEFENSE_BASE_MAX = 210;
const HP_MIN_CLAMP = 50;
const HP_MAX_CLAMP = 100;

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
 * 面板反推（防御MAX 闭式解）只校验这个值，不覆盖它。
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

/**
 * 反推得到的连续解归到制作组的取值词表上：整数 → 0.5 半档 → 0.1 十分档，逐档放宽。
 * 现存标注的取值词表是按系数实测出来的：速度/攻速/倍率/段数/档次全在 0.5 网格上，
 * 成长、高攻低血防、高防低血里约 1/4 的用例需要 0.1（含一例 1.25），所以不能只给整数。
 * 相邻两档只差一档的容差内（0.05）算“够用”，因此连续解 2.014 取 2、1.840 取 1.8。
 */
export function snapMonsterCoefficient(value: number): { value: number; grid: MonsterCoefficientGrid } {
  const integer = Math.round(value);
  if (Math.abs(value - integer) <= 0.05) return { value: integer, grid: "integer" };
  const half = Math.round(value * 2) / 2;
  if (Math.abs(value - half) <= 0.05) return { value: half, grid: "half" };
  return { value: Math.round(value * 10) / 10, grid: "tenth" };
}

/** 空手攻击公式里的攻击节奏乘积 G*sqrt(H)*1.2^(F-3)*1.1^(I-2)。 */
export function attackTempo(input: MonsterInput): number {
  return (
    input.atkMultiplier *
    Math.sqrt(input.segmentFactor) *
    1.2 ** (input.atkSpeedFactor - 3) *
    1.1 ** (input.speedFactor - 2)
  );
}

export function solveMonsterCoefficients(request: MonsterSolveRequest): MonsterSolveResult {
  const { stage, tierFactor } = request;
  if (!Number.isFinite(stage) || stage <= 0) {
    throw new Error("怪物反推需要正的阶段（阶段）");
  }
  if (!Number.isFinite(tierFactor) || tierFactor <= 0) {
    throw new Error("怪物反推需要正面的档次系数（档次系数）");
  }

  const notes: string[] = [];
  const estimates: CoefficientEstimate[] = [];
  const coefficients: MonsterInput = {
    stage,
    tierFactor,
    ...MONSTER_COEFFICIENT_DEFAULTS,
    ...(request.known ?? {}),
  };
  const pinned = new Set(Object.keys(request.known ?? {}) as MonsterCoefficientName[]);

  const addNote = (text: string): void => {
    if (!notes.includes(text)) notes.push(text);
  };

  const adopt = (estimate: CoefficientEstimate | undefined): boolean => {
    if (!estimate) return false;
    const [low, high] = MONSTER_COEFFICIENT_RANGES[estimate.name];
    const value = clamp(estimate.value, low, high);
    if (Math.abs(value - estimate.value) > 1e-9) {
      addNote(`${estimate.name} 反推值 ${round(estimate.value, 4)} 超出工作表范围 ${low}~${high}，已夹紧为 ${value}`);
    }
    const settled = { ...estimate, value: round(value, 6) };
    coefficients[estimate.name] = settled.value;
    const previous = estimates.findIndex((entry) => entry.name === estimate.name);
    if (previous >= 0) estimates[previous] = settled;
    else estimates.push(settled);
    return true;
  };

  for (const name of pinned) {
    estimates.push({ name, value: coefficients[name], confidence: "given", basis: "人工给定基础系数" });
  }

  const growth = solveGrowthFactor({ stage, tierFactor, panel: request.panel });
  if (growth) {
    if (pinned.has("growthFactor")) addNote(`成长系数给定 ${coefficients.growthFactor}，面板主通道为 ${round(growth.value, 4)}（${growth.basis}）`);
    else adopt(growth);
    growth.crossChecks.forEach(addNote);
  } else if (!pinned.has("growthFactor")) {
    adopt({ name: "growthFactor", value: coefficients.growthFactor, confidence: "workbook-default", basis: "缺少成对面板字段" });
  }
  const E = coefficients.growthFactor;

  // 速度系数按定义取自移动速度（Excel D15 均值定档），面板只作校验；
  // 防御MAX 的闭式解退居第二条通道，仅在查不到移动速度区间时给值。
  const closedSpeed = solveSpeedFactorFromDefense({
    stage,
    tierFactor,
    growthFactor: E,
    panel: request.panel,
    current: coefficients,
    pinned,
  });
  const moveSpeed = request.moveSpeed;
  const band = moveSpeed
    ? speedFactorFromMoveSpeed(moveSpeed.min, moveSpeed.max)
    : undefined;

  if (band !== undefined && moveSpeed !== undefined) {
    if (!pinned.has("speedFactor")) {
      adopt({
        name: "speedFactor",
        value: band.value,
        confidence: "definition-band",
        basis: `移动速度 ${moveSpeed.min}~${moveSpeed.max} 按 Excel D15 取均值档次${band.upper !== band.value ? `，跨档可取两档中点 ${band.upper}` : ""}`,
      });
    }
    const other = pinned.has("speedFactor") ? coefficients.speedFactor : closedSpeed?.value;
    if (other !== undefined && Math.abs(band.value - other) >= 0.5) {
      addNote(
        `速度系数定义档 ${band.value}（移动速度 ${moveSpeed.min}~${moveSpeed.max}）与${pinned.has("speedFactor") ? `人工给定 ${round(other, 2)}` : `防御MAX 反推 ${round(other, 2)}`} 相差 ${round(Math.abs(band.value - other), 2)} 档，${pinned.has("speedFactor") ? "取值仍以人工给定为准，请回查移动速度区间或面板" : "取值以定义档为准，请回查面板是否手填或阶段/档次可疑"}`,
      );
    }
  } else if (closedSpeed) {
    adopt(closedSpeed);
  }
  const speedSettled = pinned.has("speedFactor") || estimates.some((entry) => entry.name === "speedFactor");

  // 防御/HP 与霸体乘子的依赖：I 定住时 J/L/HP 全闭式；I 未给定时按霸体乘子=1 解一参数族。
  const superArmorKnown = pinned.has("superArmorFactor");
  let superArmorIdentified = false;
  {
    const hpFactor = superArmorKnown ? superArmorHpFactor(tierFactor, coefficients.superArmorFactor) : 1;
    const defense = solveDefenseCoefficients({
      stage,
      tierFactor,
      growthFactor: E,
      panel: request.panel,
      current: coefficients,
      pinned,
      speedSettled,
      hpFactor,
    });
    for (const estimate of defense.estimates) {
      if (pinned.has(estimate.name)) continue;
      adopt(estimate);
    }
    defense.notes.forEach(addNote);

    const superArmor = solveSuperArmorFactor({
      stage,
      tierFactor,
      growthFactor: E,
      panel: request.panel,
      current: coefficients,
      speedSettled,
    });
    if (superArmor) {
      addNote(superArmor.note);
      superArmorIdentified = superArmor.identifiable;
      if (superArmor.identifiable && !pinned.has("superArmorFactor")) adopt(superArmor.estimate);
    }
  }

  const tempo = attackTempoTarget({ stage, tierFactor, growthFactor: E, panel: request.panel, current: coefficients });
  const unresolved: MonsterCoefficientName[] = [];
  for (const name of ["atkSpeedFactor", "atkMultiplier", "segmentFactor"] as MonsterCoefficientName[]) {
    if (!pinned.has(name)) unresolved.push(name);
  }
  if (!speedSettled) unresolved.push("speedFactor");
  if (!superArmorKnown && !superArmorIdentified) unresolved.push("superArmorFactor");
  if (tempo === undefined) addNote("空手攻击MIN 缺失，无法给出攻击节奏乘积目标");
  else addNote(`攻击节奏乘积目标 G*sqrt(H)*1.2^(F-3) = ${round(tempo, 4)}，须由攻击动作观测拆分攻速系数/攻击倍率/段数系数`);

  const solved = { ...coefficients };
  return {
    coefficients: solved,
    estimates,
    unresolved,
    ...(tempo === undefined ? {} : { attackTempoTarget: round(tempo, 6) }),
    residuals: panelResiduals(request.panel, computeMonsterRow(solved)),
    notes,
  };
}

interface GrowthSolution extends CoefficientEstimate {
  crossChecks: string[];
}

function solveGrowthFactor(input: { stage: number; tierFactor: number; panel: MonsterPanel }): GrowthSolution | undefined {
  const { stage: C, tierFactor: D, panel } = input;
  const routes: Array<{ value: number; basis: string }> = [];

  if (panel.atkMin !== undefined && panel.atkMax !== undefined && panel.atkMin > ATTACK_BASE && panel.atkMax > ATTACK_BASE_MAX) {
    routes.push({
      value: ((panel.atkMax - ATTACK_BASE_MAX) / (panel.atkMin - ATTACK_BASE)) * ((C * D * 9) / (50 + C * D * 23)),
      basis: "空手攻击MAX/MIN比值",
    });
  }

  if (panel.expMin !== undefined && panel.expMin > 0) {
    const solved = invertMonotone(
      (E) => 1.25 ** (1 - E) / Math.sqrt(E),
      panel.expMin / (C ** 1.15 * D ** 1.2 * 12 * (D > 17 ? 1.2 ** (D - 15) : 1)),
      MONSTER_COEFFICIENT_RANGES.growthFactor[0],
      MONSTER_COEFFICIENT_RANGES.growthFactor[1],
    );
    if (solved !== undefined) routes.push({ value: solved, basis: "经验MIN" });
  }

  if (panel.expMax !== undefined) {
    const solved = invertMonotone(
      (E) => 1.25 ** (1 - E) * Math.sqrt(E),
      (panel.expMax - 95 - (C >= 6 ? C * 200 : 0)) / (C * D ** 1.58 * 33),
      MONSTER_COEFFICIENT_RANGES.growthFactor[0],
      MONSTER_COEFFICIENT_RANGES.growthFactor[1],
    );
    if (solved !== undefined) routes.push({ value: solved, basis: "经验MAX" });
  }

  if (panel.hpMin !== undefined && panel.hpMax !== undefined) {
    const n1 = panel.hpMin - 200 * (D - 2);
    const n2 = panel.hpMax - 180 * (D - 2);
    if (n1 > HP_MIN_CLAMP && n2 > HP_MAX_CLAMP) {
      routes.push({ value: (n2 / n1) * (293 / 900), basis: "HPMAX/MIN比值（未计霸体乘子）" });
    }
  }

  const [primary, rest] = [routes[0], routes.slice(1)];
  if (!primary) return undefined;

  const crossChecks: string[] = [];
  for (const route of rest) {
    const diff = Math.abs(route.value - primary.value) / primary.value;
    if (diff > 0.1) {
      crossChecks.push(
        `成长系数通道分歧：${route.basis} 给出 ${round(route.value, 3)}，主通道 ${round(primary.value, 3)}（差 ${Math.round(diff * 100)}%），阶段或档次系数可疑`,
      );
    }
  }

  return {
    name: "growthFactor",
    value: primary.value,
    confidence: "closed-form",
    basis: `${primary.basis}，另有 ${rest.length} 条通道交叉校验`,
    crossChecks,
  };
}

/**
 * 高攻低血防 J 与高防低血 L 都已给定时，Excel S 列只剩速度系数 I 一个未知数，防御MAX 直接锁死它。
 * 残缺标识的怪多半属于这种情形，比按移动速度档次取整数更准。
 */
function solveSpeedFactorFromDefense(input: {
  stage: number;
  tierFactor: number;
  growthFactor: number;
  panel: MonsterPanel;
  current: MonsterInput;
  pinned: Set<MonsterCoefficientName>;
}): CoefficientEstimate | undefined {
  const { stage: C, tierFactor: D, growthFactor: E, panel, current, pinned } = input;
  if (pinned.has("speedFactor")) return undefined;
  if (!pinned.has("highAtkFactor") || !pinned.has("highDefFactor")) return undefined;
  if (panel.defMax === undefined) return undefined;

  const excess = panel.defMax - DEFENSE_BASE_MAX;
  if (!(excess > 0)) return undefined;
  const value = logBase(((190 + C * D) * current.highDefFactor * Math.sqrt(E)) / (excess * current.highAtkFactor), 1.1) + 2;
  if (!Number.isFinite(value)) return undefined;

  return { name: "speedFactor", value, confidence: "closed-form", basis: "防御MAX，高攻低血防与高防低血系数已给定" };
}

interface DefenseSolveInput {
  stage: number;
  tierFactor: number;
  growthFactor: number;
  panel: MonsterPanel;
  current: MonsterInput;
  pinned: Set<MonsterCoefficientName>;
  /** 速度系数是否已由人工给定或移动速度档次定住；定住后 J/L 才闭式，HP 残差才等于霸体乘子。 */
  speedSettled: boolean;
  /** 联立解 HP 时假定的霸体乘子。 */
  hpFactor: number;
}

/**
 * 按给定链解高攻低血防 J、高防低血 L、速度系数 I。
 * I 定住时走全闭式链；I 未给定且有 HP 时按霸体乘子=1 解一参数族。
 */
function solveDefenseCoefficients(input: DefenseSolveInput): { estimates: CoefficientEstimate[]; notes: string[] } {
  const { stage: C, tierFactor: D, growthFactor: E, panel, current, pinned, speedSettled, hpFactor } = input;
  const sqrtE = Math.sqrt(E);
  const notes: string[] = [];

  const defMinExcess = panel.defMin === undefined ? undefined : panel.defMin - DEFENSE_MIN_TERM / sqrtE + 30;
  const defMaxExcess = panel.defMax === undefined ? undefined : panel.defMax - DEFENSE_BASE_MAX;
  const hasDefPair = defMinExcess !== undefined && defMaxExcess !== undefined && defMaxExcess > 0;

  const lOverJ = (I: number): number | undefined => {
    if (!hasDefPair) return undefined;
    const value = (defMaxExcess! * 1.1 ** (I - 2)) / ((190 + C * D) * sqrtE);
    return value > 0 ? value : undefined;
  };

  // 1) 速度系数已定：defMax 给 L/J，defMin 给 J，L=(L/J)*J，全部闭式。
  if (speedSettled && hasDefPair && defMinExcess !== undefined && !pinned.has("highDefFactor") && !pinned.has("highAtkFactor")) {
    const ratio = lOverJ(current.speedFactor);
    if (ratio) {
      const subtracted = (ratio * (50 + C * D)) / sqrtE;
      const highAtk = (defMinExcess - subtracted) / (30 * ratio);
      if (highAtk > 0) {
        if (defMinExcess - subtracted < 0.4 * defMinExcess) {
          notes.push("防御MIN 里 (L/J)*(50+C*D) 项占比高，J/L 对速度系数取值敏感，反推误差会被放大");
        }
        return {
          estimates: [
            { name: "highAtkFactor", value: highAtk, confidence: "closed-form", basis: "防御MIN，速度系数已定" },
            { name: "highDefFactor", value: ratio * highAtk, confidence: "closed-form", basis: "防御MAX的L/J比值×J" },
          ],
          notes,
        };
      }
    }
    notes.push("速度系数已定但防御方程无正解，检查阶段/档次系数或面板数据");
  }

  // 2) 已给高攻低血防或高防低血且速度系数未定：另一件由 defMin/defMax 闭式解，速度系数由 defMax 取对数。
  if (!speedSettled && hasDefPair && defMinExcess !== undefined && (pinned.has("highAtkFactor") || pinned.has("highDefFactor"))) {
    const estimates: CoefficientEstimate[] = [];
    const pinnedJ = pinned.has("highAtkFactor") ? current.highAtkFactor : undefined;
    const pinnedL = pinned.has("highDefFactor") ? current.highDefFactor : undefined;
    const L = pinnedJ === undefined ? pinnedL! : defMinExcess / ((50 + C * D) / (pinnedJ * sqrtE) + 30);
    const J = pinnedJ === undefined ? ((50 + C * D) * L) / (sqrtE * (defMinExcess - 30 * L)) : pinnedJ;
    if (L > 0 && J > 0) {
      if (pinnedJ === undefined) estimates.push({ name: "highAtkFactor", value: J, confidence: "closed-form", basis: "防御MIN，高防低血系数已给定" });
      else estimates.push({ name: "highDefFactor", value: L, confidence: "closed-form", basis: "防御MIN，高攻低血防系数已给定" });
      estimates.push({
        name: "speedFactor",
        value: logBase(((190 + C * D) * L * sqrtE) / (defMaxExcess * J), 1.1) + 2,
        confidence: "closed-form",
        basis: "防御MAX，J/L 已定",
      });
      return { estimates, notes };
    }
    notes.push("给定 J/L 后防御方程无正解，检查面板数据");
  }

  // 3) 速度系数与 J/L 都未给定：按霸体乘子=1 对速度系数二分，解出一参数族代表元。
  const canJoint =
    !speedSettled &&
    hasDefPair &&
    defMinExcess !== undefined &&
    panel.hpMin !== undefined &&
    panel.hpMax !== undefined &&
    panel.hpMin > HP_MIN_CLAMP &&
    panel.hpMax > HP_MAX_CLAMP &&
    !pinned.has("highDefFactor");

  if (canJoint) {
    const joint = jointDefenseSolve({
      C,
      D,
      E,
      defMinExcess: defMinExcess!,
      defMaxExcess: defMaxExcess!,
      panel,
      hpFactor,
    });
    if (joint) {
      return {
        estimates: [
          { name: "speedFactor", value: joint.speedFactor, confidence: "joint-solve", basis: "霸体乘子=1 下防御与HP参数族代表元" },
          { name: "highAtkFactor", value: joint.highAtkFactor, confidence: "joint-solve", basis: "同上（L/J 与 J 的分离）" },
          { name: "highDefFactor", value: joint.highDefFactor, confidence: "joint-solve", basis: "同上，L=(L/J)*J" },
        ],
        notes,
      };
    }
    notes.push("防御/HP 参数族在 1~3 内无解区间，速度系数与 J/L 退回默认值");
  }

  // 4) 面板不足：只能用默认值，并说明缺什么。
  if (!hasDefPair) notes.push("缺少成对防御字段，J/L/I 无法由面板反推");
  return { estimates: [], notes };
}

function jointDefenseSolve(input: {
  C: number;
  D: number;
  E: number;
  defMinExcess: number;
  defMaxExcess: number;
  panel: MonsterPanel;
  hpFactor: number;
}): { speedFactor: number; highAtkFactor: number; highDefFactor: number } | undefined {
  const { C, D, E, defMinExcess, defMaxExcess, panel, hpFactor } = input;
  const sqrtE = Math.sqrt(E);
  const n1 = panel.hpMin! / hpFactor - 200 * (D - 2);
  const n2 = panel.hpMax! / hpFactor - 180 * (D - 2);
  if (n1 <= HP_MIN_CLAMP || n2 <= HP_MAX_CLAMP) return undefined;

  const w = n2 / (C * D * 900 * sqrtE * 1.3 ** (1 - E));
  if (!(w > 0)) return undefined;

  const ratioOf = (I: number) => (defMaxExcess * 1.1 ** (I - 2)) / ((190 + C * D) * sqrtE);
  const residual = (I: number): number => {
    const ratio = ratioOf(I);
    const J = (defMinExcess - (ratio * (50 + C * D)) / sqrtE) / (30 * ratio);
    const L = ratio * J;
    if (!(J > 0) || !(L > 0)) return Number.NaN;
    return J * Math.sqrt(L) - 1 / (1.2 ** (I - 2) * w);
  };

  const bracket = findSignChange(residual, MONSTER_COEFFICIENT_RANGES.speedFactor[0], MONSTER_COEFFICIENT_RANGES.speedFactor[1]);
  if (!bracket) return undefined;

  let [lo, hi] = bracket;
  for (let step = 0; step < 80; step += 1) {
    const mid = (lo + hi) / 2;
    if (residual(mid) > 0) hi = mid;
    else lo = mid;
  }
  const speedFactor = (lo + hi) / 2;
  const ratio = ratioOf(speedFactor);
  const highAtkFactor = (defMinExcess - (ratio * (50 + C * D)) / sqrtE) / (30 * ratio);
  const highDefFactor = ratio * highAtkFactor;
  if (!(highAtkFactor > 0) || !(highDefFactor > 0)) return undefined;
  return { speedFactor, highAtkFactor, highDefFactor };
}

/** HP 相对 J/L/I 解的残差就是霸体乘子；按 Excel 分支反解整数位。 */
function solveSuperArmorFactor(input: {
  stage: number;
  tierFactor: number;
  growthFactor: number;
  panel: MonsterPanel;
  current: MonsterInput;
  speedSettled: boolean;
}): { estimate: CoefficientEstimate; identifiable: boolean; note: string } | undefined {
  const { stage: C, tierFactor: D, growthFactor: E, panel, current, speedSettled } = input;
  if (panel.hpMin === undefined || panel.hpMax === undefined) return undefined;
  if (panel.hpMin <= HP_MIN_CLAMP || panel.hpMax <= HP_MAX_CLAMP) {
    return {
      identifiable: false,
      estimate: {
        name: "superArmorFactor",
        value: current.superArmorFactor,
        confidence: "workbook-default",
        basis: "HP 落在公式的 MAX 下限里",
      },
      note: "HP 触及公式下限 50/100，霸体乘子不可读，霸体系数需人工按击退动画判定",
    };
  }

  const shared = (C * D * 1.3 ** (1 - E)) / (1.2 ** (current.speedFactor - 2) * current.highAtkFactor * Math.sqrt(current.highDefFactor));
  const baseMin = Math.max(200 * (D - 2) + (shared * 293) / Math.sqrt(E), HP_MIN_CLAMP);
  const baseMax = Math.max(180 * (D - 2) + shared * 900 * Math.sqrt(E), HP_MAX_CLAMP);
  const factors = [panel.hpMin / baseMin, panel.hpMax / baseMax].filter((value) => Number.isFinite(value) && value > 0);
  if (factors.length === 0) return undefined;
  const factor = factors.reduce((sum, value) => sum + value, 0) / factors.length;

  const candidates: Array<{ value: number; error: number }> = [];
  const offer = (value: number | undefined) => {
    if (value === undefined || !Number.isFinite(value)) return;
    const [low, high] = MONSTER_COEFFICIENT_RANGES.superArmorFactor;
    if (value < low || value > high) return;
    candidates.push({ value, error: Math.abs(superArmorHpFactor(D, value) - factor) });
  };
  if (D < 9 && factor < 1) offer(50 * (1 - factor));
  if (D > 12 && factor > 1) offer(1 / (factor - 1));

  const best = candidates.sort((left, right) => left.error - right.error)[0];
  if (speedSettled && best && best.error < 0.02) {
    return {
      identifiable: true,
      estimate: {
        name: "superArmorFactor",
        value: Math.round(best.value * 100) / 100,
        confidence: "joint-solve",
        basis: `HP 相对防御解的乘子 ${round(factor, 4)}，落在${D < 9 ? "长击退" : "短击退"}分支`,
      },
      note: `HP 霸体乘子 ${round(factor, 3)} 反解出霸体系数 ${round(best.value, 2)}，整数位仍建议按击退/击飞动画复核`,
    };
  }

  return {
    identifiable: false,
    estimate: {
      name: "superArmorFactor",
      value: current.superArmorFactor,
      confidence: "workbook-default",
      basis: speedSettled ? `HP 霸体乘子 ${round(factor, 4)} 落在乘子为 1 的分支` : "速度系数未定住，HP 残差与霸体乘子不可分离",
    },
    note: speedSettled
      ? `HP 霸体乘子 ${round(factor, 4)}：整数位由击退/击飞动画决定，面板只能确认 HP${Math.abs(factor - 1) < 0.01 ? "不带" : "带"}霸体修正，建议人工定档后复算`
      : "先给定速度系数（或按移动速度档次）后，HP 残差才等于霸体乘子",
  };
}

/** 攻击节奏乘积目标：面板只能确定 G*sqrt(H)*1.2^(F-3) 这一个乘积。 */
function attackTempoTarget(input: {
  stage: number;
  tierFactor: number;
  growthFactor: number;
  panel: MonsterPanel;
  current: MonsterInput;
}): number | undefined {
  const { stage: C, tierFactor: D, growthFactor: E, panel, current } = input;
  if (panel.atkMin === undefined || panel.atkMin <= ATTACK_BASE) return undefined;
  const tempo = (C * D * 9 * 1.25 ** (1 - E) * current.highAtkFactor) / ((panel.atkMin - ATTACK_BASE) * Math.sqrt(E));
  const withoutSpeed = tempo / 1.1 ** (current.speedFactor - 2);
  return withoutSpeed > 0 ? withoutSpeed : undefined;
}

/**
 * 档次系数扫描：面板里的加性常数项（200*(D-2)、180*(D-2)、50+C*D、190+C*D、C*D^1.58 等）
 * 让 D 在给定阶段与其余系数自由度时并非完全不可辨识，可用来给人工定档排序候选。
 * 这不是判定结论——攻击节奏三系数仍按乘积吸收误差，所以只用于排序与提示。
 */
export interface MonsterTierCandidate {
  tierFactor: number;
  fitError: number;
  coefficients: MonsterInput;
  residuals: MonsterPanelResidual[];
}

/** Excel B20~C32 的档次表习惯取值：小怪半档，boss 档按整数上探。 */
export function defaultTierCandidates(): number[] {
  const fine: number[] = [];
  for (let value = 1; value <= 10; value += 0.5) fine.push(value);
  for (let value = 11; value <= MONSTER_COEFFICIENT_RANGES.tierFactor[1]; value += 1) fine.push(value);
  return fine;
}

export function scanTierFactor(
  request: Omit<MonsterSolveRequest, "tierFactor"> & { tierCandidates?: number[] },
): MonsterTierCandidate[] {
  const candidates = request.tierCandidates ?? defaultTierCandidates();
  const scored: MonsterTierCandidate[] = [];
  for (const tierFactor of candidates) {
    const solved = solveMonsterCoefficients({ ...request, tierFactor });
    if (solved.residuals.length === 0) continue;
    const error = Math.sqrt(solved.residuals.reduce((sum, item) => sum + item.relativeError ** 2, 0) / solved.residuals.length);
    scored.push({ tierFactor, fitError: round(error, 6), coefficients: solved.coefficients, residuals: solved.residuals });
  }
  return scored.sort((left, right) => left.fitError - right.fitError);
}

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

/** 单调函数反解：按端点判断增减方向，目标落在值域外返回 undefined。 */
export function invertMonotone(
  fn: (value: number) => number,
  target: number,
  lo: number,
  hi: number,
  iterations = 80,
): number | undefined {
  const a = fn(lo);
  const b = fn(hi);
  if (!Number.isFinite(a) || !Number.isFinite(b) || !Number.isFinite(target)) return undefined;
  const increasing = b > a;
  const [low, high] = increasing ? [a, b] : [b, a];
  if (target < low || target > high) return undefined;

  let left = lo;
  let right = hi;
  for (let step = 0; step < iterations; step += 1) {
    const mid = (left + right) / 2;
    if (increasing ? fn(mid) > target : fn(mid) < target) right = mid;
    else left = mid;
  }
  return (left + right) / 2;
}

function findSignChange(fn: (value: number) => number, lo: number, hi: number, steps = 40): [number, number] | undefined {
  let previous = lo;
  let previousValue = fn(previous);
  for (let index = 1; index <= steps; index += 1) {
    const current = lo + ((hi - lo) * index) / steps;
    const currentValue = fn(current);
    if (Number.isFinite(previousValue) && Number.isFinite(currentValue) && previousValue * currentValue <= 0) {
      return [previous, current];
    }
    previous = current;
    previousValue = currentValue;
  }
  return undefined;
}

function logBase(value: number, base: number): number {
  return Math.log(value) / Math.log(base);
}

function clamp(value: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, value));
}

function round(value: number, digits: number): number {
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}
