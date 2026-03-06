/**
 * 枪械公式引擎 — 从 Excel「枪械」Sheet 翻译的全部 25 个计算列
 *
 * 公式来源: 0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式.xlsx
 * 长枪(dw=1): basePower = power*1.5 + 30
 * 短枪(dw=2): basePower = power + 20
 */

// ─── Input / Output 类型 ───

export interface WeaponInput {
  /** 限制等级 */
  level: number;
  /** 子弹威力 (power) */
  bulletPower: number;
  /** 射击间隔 ms */
  shootInterval: number;
  /** 弹容量 */
  magSize: number;
  /** 弹夹价格 */
  magPrice: number;
  /** 重量 */
  weight: number;
  /** 双枪系数 (1=长枪, 2=短枪) */
  dualWieldFactor: number;
  /** 穿刺系数 */
  pierceFactor: number;
  /** 伤害类型系数 (1=物理, 2=魔法, 3=真伤) */
  damageTypeFactor: number;
  /** 霰弹值 (1=非霰弹) */
  shotgunValue: number;
  /** 冲击力 */
  impact: number;
  /** 额外加权层数 */
  extraWeightLayers: number;
}

export interface WeaponOutput {
  /** 伤害加成 — 等级相关的角色伤害加成 */
  damageBonus: number;
  /** 剧毒 — 等级阈值毒伤 */
  poison: number;
  /** 单段伤害 — 单发期望伤害（不含穿刺/霰弹加成） */
  singleShotDamage: number;
  /** 周期伤害 — 一弹夹总伤害（含穿刺/霰弹） */
  cycleDamage: number;
  /** 平均DPS */
  averageDPS: number;
  /** 平均射速 (发/秒) */
  averageFireRate: number;
  /** 吃拐率 — 有效命中频率 */
  hitRate: number;
  /** 吃拐系数 — 射速过高时的惩罚系数 */
  hitRateCoeff: number;
  /** 冲击力系数 */
  impactCoeff: number;
  /** 裸伤DPS — 仅基础威力部分 */
  nakedDPS: number;
  /** 经济加成DPS — 弹药经济贡献 */
  economicDPS: number;
  /** 增益DPS — 等级/加成贡献 */
  boostDPS: number;
  /** 平衡周期伤害 — 理论基准 */
  balanceCycleDamage: number;
  /** 加权周期伤害 — 含额外层数加权 */
  weightedCycleDamage: number;
  /** 周期伤害系数 — sigmoid 调节 */
  cycleDamageCoeff: number;
  /** 平衡基础DPS */
  balanceBaseDPS: number;
  /** 平衡裸伤DPS */
  balanceNakedDPS: number;
  /** 平衡增益DPS */
  balanceBoostDPS: number;
  /** 平衡DPS */
  balanceDPS: number;
  /** 加权DPS — 最终加权评分 */
  weightedDPS: number;
  /** 周期DPS */
  cycleDPS: number;
  /** 周期DPS系数 */
  cycleDPSCoeff: number;
  /** 旧平衡DPS — 历史公式参考 */
  oldBalanceDPS: number;
  /** DPS总公式 — 等于平均DPS */
  dpsFormula: number;
}

// ─── 子公式 ───

/** 基础威力：长枪 power*1.5+30，短枪 power+20 */
function basePower(power: number, dw: number): number {
  return dw === 1 ? power * 1.5 + 30 : power + 20;
}

/** 伤害加成：分段线性 × 高等级加速乘数 */
function damageBonus(level: number): number {
  const linear = level >= 35 ? 17 * level - 330 : 7 * level + 15;
  if (level < 25) return linear;
  const enhLv = Math.min(13, (level - 18) / 3.5);
  const mult = 1 + (enhLv - 1) * (enhLv - 1) / 100 + 0.05 * (enhLv - 1);
  return linear * mult;
}

/** 剧毒 */
function poison(level: number): number {
  return level >= 30 ? 120 : 30;
}

/** 冲击力系数：S 曲线 0.9~1.1 */
function impactCoeff(impact: number): number {
  return 0.9 + 0.2 * impact / (impact + 50);
}

/** 射击周期时间 ms (含换弹) */
function cycleDenom(interval: number, cap: number, dw: number): number {
  return interval * (cap - 1) + 900 * dw;
}

/** 霰弹有效倍率 */
function shotgunMult(shotgun: number): number {
  return 1 + (shotgun - 1) * 0.5;
}

// ─── 主计算 ───

export function computeWeaponRow(input: WeaponInput): WeaponOutput {
  const {
    level, bulletPower: power, shootInterval: interval, magSize: cap,
    magPrice, weight, dualWieldFactor: dw, pierceFactor: pierce,
    damageTypeFactor: dmgType, shotgunValue: shotgun, impact: impactVal,
    extraWeightLayers: extraWeight,
  } = input;

  const denom = cycleDenom(interval, cap, dw);
  const bp = basePower(power, dw);
  const dmgBonus = damageBonus(level);
  const psn = poison(level);
  const impCoeff = impactCoeff(impactVal);
  const sgMult = shotgunMult(shotgun);

  // 穿刺衰减后的毒伤（周期用）
  const cyclePoison = psn / (shotgun * Math.pow(3, pierce - 1));

  // 增益部分（等级/加成/毒伤）
  const boostPart = power * 2 * level / 256 + dmgBonus + cyclePoison;

  // ── 直接计算列 ──
  const singleShotDamage = bp + power * 2 * level / 256 + dmgBonus + psn / shotgun;
  const cycleDamage = (bp + boostPart) * pierce * cap * sgMult;
  const averageDPS = 1000 * cycleDamage / denom;
  const averageFireRate = 1000 * cap / denom;
  const hitRate = 1000 * pierce * cap * sgMult / denom;
  const nakedDPS = 1000 * bp * pierce * cap * sgMult / denom;
  const economicDPS = (1000 * (magPrice * 6 / dmgType) / denom) / Math.pow(1.5, dw - 1);
  const boostDPS = 1000 * boostPart * pierce * cap * sgMult / denom;

  // ── 平衡参考列 ──
  const balanceCycleDamage =
    (level - 1) * 1200 * impCoeff / (Math.pow(1.6, dmgType - 1) * Math.pow(1.5, dw - 1))
    + magPrice * 5 * (1 + level) / (50 * dmgType)
    + weight * 660 * (2 + level) / (25 * dmgType);

  const weightedCycleDamage = balanceCycleDamage * Math.pow(1.25, extraWeight);

  // 周期伤害系数 (sigmoid)
  let cycleDamageCoeff: number;
  if (cycleDamage <= weightedCycleDamage * 5) {
    cycleDamageCoeff = 0.7 + 0.6 / (1 + Math.exp(-(weightedCycleDamage - cycleDamage) / weightedCycleDamage));
  } else {
    cycleDamageCoeff = 0.1 + 1.5 / (1 + Math.exp(-(weightedCycleDamage - cycleDamage) / (weightedCycleDamage * 10)));
  }

  // 平衡基础DPS
  const balanceBaseDPS =
    (level * 120 * impCoeff * cycleDamageCoeff / Math.pow(1.6, dmgType - 1)
      + weight * 66 / dmgType) / Math.pow(1.5, dw - 1);

  // 平衡裸伤DPS (分段)
  let balanceNakedDPS: number;
  if (economicDPS <= balanceBaseDPS * level / 3) {
    balanceNakedDPS = economicDPS;
  } else {
    balanceNakedDPS = balanceBaseDPS
      + 15 * balanceBaseDPS * (1 - Math.exp(-(economicDPS - balanceBaseDPS) / (15 * balanceBaseDPS)));
  }
  balanceNakedDPS += balanceBaseDPS;

  // 平衡增益DPS
  const balanceBoostDPS =
    (balanceNakedDPS / (Math.pow(1.5, 2 - dw) + (40 - 10 * dw) / power))
      * 2 * level / 256
    + 1000 * (dmgBonus + cyclePoison) * (26.5 + level * 0.5)
      / (120 * 29 + 900 * dw) / dmgType;

  // 平衡DPS
  const balanceDPS = balanceNakedDPS + balanceBoostDPS;

  // 吃拐系数
  const hitThreshold =
    (0.0008 * level * level + 10 + (shotgun + pierce * 2.5 - 3.5) * 0.2 + weight * weight / 50)
    * Math.pow(1.1, extraWeight);

  let hitRateCoeff: number;
  if (hitRate > hitThreshold) {
    hitRateCoeff = (6 / (pierce * pierce * shotgun)) * hitThreshold / hitRate
      - 6 / (pierce * pierce * shotgun) + 1;
  } else {
    hitRateCoeff = 1;
  }
  hitRateCoeff = Math.max(hitRateCoeff, 0.1);

  // 周期DPS
  const cycleDPS = 1000 * cycleDamage / Math.max(interval * (cap - 1), 100 / dw);

  // 周期DPS系数 (sigmoid)
  let cycleDPSCoeff: number;
  if (cycleDPS <= balanceDPS * 2) {
    cycleDPSCoeff = 0.85 + 0.3365 / (1 + Math.exp(-(balanceDPS - cycleDPS) / balanceDPS));
  } else {
    cycleDPSCoeff = 0.75 + 0.7 / (1 + Math.exp(-(balanceDPS - cycleDPS) / balanceDPS));
  }

  // 加权DPS
  const weightedDPS = balanceDPS * cycleDPSCoeff * hitRateCoeff * Math.pow(1.1, extraWeight);

  // 旧平衡DPS
  const oldBalanceDPS =
    ((level * 200 + weight * 61) * impCoeff * cycleDamageCoeff / Math.pow(1.6, dmgType - 1)
      + 1000 * (magPrice * 5 * (8 + level) / (50 * dmgType)
        + weight * 660 * (1 + level) / (25 * dmgType)) / denom)
    / Math.pow(1.5, dw - 1);

  return {
    damageBonus: dmgBonus,
    poison: psn,
    singleShotDamage: singleShotDamage,
    cycleDamage,
    averageDPS,
    averageFireRate,
    hitRate,
    hitRateCoeff,
    impactCoeff: impCoeff,
    nakedDPS,
    economicDPS,
    boostDPS,
    balanceCycleDamage,
    weightedCycleDamage,
    cycleDamageCoeff,
    balanceBaseDPS,
    balanceNakedDPS,
    balanceBoostDPS,
    balanceDPS,
    weightedDPS,
    cycleDPS,
    cycleDPSCoeff,
    oldBalanceDPS,
    dpsFormula: averageDPS,
  };
}
