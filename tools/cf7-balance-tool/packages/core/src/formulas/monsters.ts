/**
 * 怪物面板公式引擎 — 对应 Excel "怪物大致面板" sheet。
 *
 * 高防低血系数（L）有两套口径，用 `MonsterFormulaVersion` 选：
 * - `v1`（历史口径）：HP 按 1/√L 缩、防御按 L 放大。实测物理等效血量非单调，
 *   L 在 1~3 反而更脆，高防单位在高 L 段收益又过大；保留它只用于对照旧面板（存量怪反推、校准）。
 * - `v2`（当前口径，默认）：把 L 定义成「血防互换 + 一点物理 EHP 斜率」——
 *   防御按 `g^β` 搬运、HP 用守恒式反解，使物理等效血量 = 基准 × L^γ，与单位本身的防御基数无关：
 *   高防单位不会因为基数大而多吃收益，低防单位也不会被重罚；L=1 时与 v1 逐字相同。
 *   β、γ 是公式常量，写死在这里，不作为用户可调旋钮。
 *   对魔法/真伤没有防御补偿，HP 随 L 下降，所以在 7:2:1 的伤害构成下，高 L 的综合扛伤会低于 L=1。
 */
export interface MonsterInput {
  stage: number;           // C: 阶段
  tierFactor: number;      // D: 档次系数
  growthFactor: number;    // E: 成长系数
  atkSpeedFactor: number;  // F: 攻速系数
  atkMultiplier: number;   // G: 攻击倍率
  segmentFactor: number;   // H: 段数系数
  speedFactor: number;     // I: 速度系数
  highAtkFactor: number;   // J: 高攻低血防系数
  superArmorFactor: number; // K: 霸体系数
  highDefFactor: number;   // L: 高防低血系数
}

export interface MonsterOutput {
  atkMin: number;       // 空手攻击MIN
  atkMax: number;       // 空手攻击MAX
  hpMin: number;        // HP最小值
  hpMax: number;        // HP最大值
  defMin: number;       // 防御力MIN
  defMax: number;       // 防御力MAX
  expMin: number;       // 经验MIN
  expMax: number;       // 经验MAX
  goldPrice: number;    // 金币价格
  kPointPrice: number;  // K点价格
}

/** v1 = 旧口径（HP 1/√L、防御 ·L）；v2 = 当前口径（血防互换 + 物理 EHP 斜率）。 */
export type MonsterFormulaVersion = "v1" | "v2";

/** 默认口径。改这里等于改全项目的前向计算口径，需要单独授权。 */
export const MONSTER_FORMULA_VERSION: MonsterFormulaVersion = "v2";

/**
 * v2 公式常量（不是用户旋钮，后续也很少改）：
 * - β：防御搬运指数。L 从 1 变到 10 时防御约 ×3.16，0.1 时约 ×0.316；越大血防互换越猛。
 * - γ：物理等效血量斜率。0.05 表示 L=10 时物理 EHP 约 +12%、L=0.1 时约 −11%，全程幅度可控。
 */
export const MONSTER_DEF_TRANSFER_EXPONENT = 0.5;
export const MONSTER_PHYSICAL_EHP_EXPONENT = 0.05;

interface MonsterCommon {
  atkMin: number;
  atkMax: number;
  expMin: number;
  expMax: number;
  goldPrice: number;
  kPointPrice: number;
}

export function computeMonsterRow(
  input: MonsterInput,
  formula: MonsterFormulaVersion = MONSTER_FORMULA_VERSION,
): MonsterOutput {
  const common = computeCommon(input);
  const { hpMin, hpMax, defMin, defMax } = formula === "v1" ? computeHpDefV1(input) : computeHpDefV2(input);
  return { ...common, hpMin, hpMax, defMin, defMax };
}

/** 面板中与高防低血系数无关的部分：空手攻击、经验、金币、K 点。两种口径共用。 */
function computeCommon(input: MonsterInput): MonsterCommon {
  const { stage: C, tierFactor: D, growthFactor: E, atkSpeedFactor: F,
          atkMultiplier: G, segmentFactor: H, speedFactor: I,
          highAtkFactor: J } = input;

  const sqrtE = Math.sqrt(E);
  const growth125 = Math.pow(1.25, 1 - E);
  const atkSpeedMod = Math.pow(1.2, F - 3);
  const speedMod11 = Math.pow(1.1, I - 2); // atk/def/exp use 1.1 base
  const sqrtH = Math.sqrt(H);

  // N: 空手攻击MIN
  const atkMin = 5 + C * D * 9 * growth125 * J / (G * sqrtH * atkSpeedMod * speedMod11 * sqrtE);

  // O: 空手攻击MAX
  const atkMax = 40 + (50 + C * D * 23) * sqrtE * growth125 * J / (G * sqrtH * atkSpeedMod * speedMod11);

  // T: 经验MIN（档次 >17 的高档加成封顶在 ×1.2^5：原式 1.2^(D-15) 在 D=25 时达 6.19 倍，
  // 会把经验下限顶到上限之上，见 2026-11-28 方舟收割者 38700 > 36400 的倒挂）
  const highTierExpBoost = D > 17 ? Math.min(Math.pow(1.2, D - 15), Math.pow(1.2, 5)) : 1;
  const expMin = C ** 1.15 * D ** 1.2 * 12 * growth125 / sqrtE * highTierExpBoost;

  // U: 经验MAX
  const expMax = 95 + C ** 1 * D ** 1.58 * 33 * growth125 * sqrtE + (C >= 6 ? C * 200 : 0);

  // V: 金币价格
  const goldPrice = Math.floor(
    2 * C ** 1.3 * D ** 1.3 +
    (D > 2 ? D * 10 : 0) +
    (D > 8 ? C ** 0.5 * D ** 0.7 : 0) +
    (D > 16 ? C ** 1.2 * (D - 15) ** 2.5 : 0)
  ) * 500;

  // W: K点价格
  const kPointPrice = Math.floor(goldPrice / 700) * 20;

  return { atkMin, atkMax, expMin, expMax, goldPrice, kPointPrice };
}

/** HP 公式里的两段霸体乘子，与 Excel P/Q 列的 IF(AND(...)) 一致。 */
export function superArmorHpFactor(tierFactor: number, superArmorFactor: number): number {
  const longKnockback = tierFactor < 9 && superArmorFactor > 3 ? 1 - superArmorFactor / 50 : 1;
  const shortKnockback = tierFactor > 12 && superArmorFactor < 5 ? 1 + 1 / superArmorFactor : 1;
  return longKnockback * shortKnockback;
}

/** v1（历史）：HP 按 1/√L 缩、防御按 L 放大。仅用于对照旧面板。 */
function computeHpDefV1(input: MonsterInput): { hpMin: number; hpMax: number; defMin: number; defMax: number } {
  const { stage: C, tierFactor: D, growthFactor: E, speedFactor: I,
          highAtkFactor: J, superArmorFactor: K, highDefFactor: L } = input;
  const sqrtE = Math.sqrt(E);
  const growth130 = Math.pow(1.3, 1 - E);
  const speedMod11 = Math.pow(1.1, I - 2);
  const speedMod12 = Math.pow(1.2, I - 2);
  const sqrtL = Math.sqrt(L);
  const armor = superArmorHpFactor(D, K);

  const hpMinBase = Math.max(
    200 * (D - 2) + C * D * 293 * growth130 / (speedMod12 * sqrtE * J * sqrtL),
    50,
  );
  const hpMaxBase = Math.max(
    180 * (D - 2) + C * D * 900 * sqrtE * growth130 / (speedMod12 * J * sqrtL),
    100,
  );

  // R: 防御力MIN
  const defMin = 30 / sqrtE + (50 + C * D) * L / (J * sqrtE) + 30 * (L - 1);

  // S: 防御力MAX
  const defMax = 210 + (190 + C * D) * L * sqrtE / (J * speedMod11);

  return { hpMin: hpMinBase * armor, hpMax: hpMaxBase * armor, defMin, defMax };
}

/**
 * v2（当前）：先把 L 折成两个因子，再把 HP 按「物理 EHP 守恒」反解。
 * - g = L^β：防御搬运。R/S 里的 ·L 全部换成 ·g，30·(L−1) 同步换成 30·(g−1)。
 * - m = L^γ：物理 EHP 斜率。HP 乘 m 与 (基准防御+300)/(新防御+300)，使 HP×(防御+300) 恰好是基准的 m 倍。
 * 因此物理 EHP 只随 m 变，与基础防御无关；L=1 时 g=m=1、两个 300 比值都是 1，退化成 v1。
 */
function computeHpDefV2(input: MonsterInput): { hpMin: number; hpMax: number; defMin: number; defMax: number } {
  const { stage: C, tierFactor: D, growthFactor: E, speedFactor: I,
          highAtkFactor: J, superArmorFactor: K, highDefFactor: L } = input;
  const sqrtE = Math.sqrt(E);
  const growth130 = Math.pow(1.3, 1 - E);
  const speedMod11 = Math.pow(1.1, I - 2);
  const speedMod12 = Math.pow(1.2, I - 2);
  const armor = superArmorHpFactor(D, K);

  // 防御搬运因子与物理 EHP 斜率（常量见文件头）。
  const g = Math.pow(L, MONSTER_DEF_TRANSFER_EXPONENT);
  const m = Math.pow(L, MONSTER_PHYSICAL_EHP_EXPONENT);

  // R: 防御力MIN（30·(g−1) 在 g<1 时为负，但幅度不超过 30，实测最低档小怪仍为正）
  const defMin = 30 / sqrtE + (50 + C * D) * g / (J * sqrtE) + 30 * (g - 1);

  // S: 防御力MAX
  const defMax = 210 + (190 + C * D) * g * sqrtE / (J * speedMod11);

  // 基准防御 = L=1 的值（g=1），只用于 HP 守恒式，不写盘。
  const defMinRef = 30 / sqrtE + (50 + C * D) / (J * sqrtE);
  const defMaxRef = 210 + (190 + C * D) * sqrtE / (J * speedMod11);

  // 基准 HP = v1 在 L=1 的值（去掉 1/√L 项）
  const hpMinBase = Math.max(
    200 * (D - 2) + C * D * 293 * growth130 / (speedMod12 * sqrtE * J),
    50,
  );
  const hpMaxBase = Math.max(
    180 * (D - 2) + C * D * 900 * sqrtE * growth130 / (speedMod12 * J),
    100,
  );

  // HP 守恒反解：HP × (防御+300) 恒等于基准 × m
  const hpMin = Math.max(hpMinBase * m * (defMinRef + 300) / (defMin + 300), 50) * armor;
  const hpMax = Math.max(hpMaxBase * m * (defMaxRef + 300) / (defMax + 300), 100) * armor;

  return { hpMin, hpMax, defMin, defMax };
}

/** 物理等效血量：`HP × (防御+300)/300`，与 DamageResistanceHandler.defenseDamageRatio 同源。 */
export function monsterPhysicalEhp(hp: number, defense: number): number {
  return hp * (defense + 300) / 300;
}

/**
 * 混合伤害等效血量。默认 7:2:1（物理:能量:真伤）与 30 点法抗：
 * 每点原始伤害里，物理走 `300/(防御+300)`，能量走 `(100−法抗)/100`，真伤全额。
 */
export function monsterMixedEhp(
  hp: number,
  defense: number,
  options: { magicResist?: number; physicalShare?: number; magicShare?: number; trueShare?: number } = {},
): number {
  const resist = options.magicResist ?? 30;
  const physicalShare = options.physicalShare ?? 0.7;
  const magicShare = options.magicShare ?? 0.2;
  const trueShare = options.trueShare ?? 0.1;
  const perRaw = physicalShare * 300 / (defense + 300) + magicShare * (100 - resist) / 100 + trueShare;
  return hp / perRaw;
}
