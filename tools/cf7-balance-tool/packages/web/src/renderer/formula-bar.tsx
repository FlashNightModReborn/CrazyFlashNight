import { useCallback, useMemo, useState } from "react";

import {
  computeWeaponRow,
  computeArmorRow,
  computeMeleeRow,
  computeExplosivesRow,
  computePhysicalDamage,
  computeMagicDamage,
  computePotionRow,
  computeMonsterRow
} from "@cf7-balance-tool/core";

type FormulaEngine =
  | "weapons"
  | "armor"
  | "melee"
  | "explosives"
  | "physical-damage"
  | "magic-damage"
  | "potions"
  | "monsters";

interface FieldDef {
  key: string;
  label: string;
  defaultValue: number;
}

const ENGINE_OPTIONS: Array<{ value: FormulaEngine; label: string }> = [
  { value: "weapons", label: "枪械" },
  { value: "armor", label: "防具" },
  { value: "melee", label: "近战" },
  { value: "explosives", label: "爆炸类" },
  { value: "physical-damage", label: "物理伤害" },
  { value: "magic-damage", label: "魔法伤害" },
  { value: "potions", label: "药剂" },
  { value: "monsters", label: "怪物" }
];

const ENGINE_FIELDS: Record<FormulaEngine, FieldDef[]> = {
  weapons: [
    { key: "level", label: "限制等级", defaultValue: 10 },
    { key: "bulletPower", label: "子弹威力", defaultValue: 50 },
    { key: "shootInterval", label: "射击间隔(ms)", defaultValue: 200 },
    { key: "magSize", label: "弹容量", defaultValue: 30 },
    { key: "magPrice", label: "弹夹价格", defaultValue: 500 },
    { key: "weight", label: "重量", defaultValue: 5 },
    { key: "dualWieldFactor", label: "双枪系数(1长/2短)", defaultValue: 1 },
    { key: "pierceFactor", label: "穿刺系数", defaultValue: 1 },
    { key: "damageTypeFactor", label: "伤害类型(1物/2魔/3真)", defaultValue: 1 },
    { key: "shotgunValue", label: "霰弹值(1=非霰弹)", defaultValue: 1 },
    { key: "impact", label: "冲击力", defaultValue: 0 },
    { key: "extraWeightLayers", label: "额外加权层数", defaultValue: 0 },
    { key: "categoryFactor", label: "种类系数", defaultValue: 1 }
  ],
  armor: [
    { key: "level", label: "限制等级", defaultValue: 10 },
    { key: "defence", label: "防御力", defaultValue: 50 },
    { key: "hp", label: "HP", defaultValue: 100 },
    { key: "mp", label: "MP", defaultValue: 0 },
    { key: "damageBonus", label: "伤害加成", defaultValue: 0 },
    { key: "weaponBonus", label: "刀/枪加成", defaultValue: 0 },
    { key: "weight", label: "重量", defaultValue: 5 },
    { key: "punchBonus", label: "空手加成", defaultValue: 0 },
    { key: "magicDefence", label: "法抗", defaultValue: 0 },
    { key: "extraWeightLayers", label: "额外加权层数", defaultValue: 0 },
    { key: "categoryFactor", label: "种类系数", defaultValue: 1 },
    { key: "damageTypeFactor", label: "伤害类型系数", defaultValue: 1 }
  ],
  melee: [
    { key: "level", label: "限制等级", defaultValue: 10 },
    { key: "weight", label: "重量", defaultValue: 5 },
    { key: "damageTypeFactor", label: "伤害类型系数", defaultValue: 1 },
    { key: "weightLayers", label: "加权层数", defaultValue: 0 },
    { key: "categoryFactor", label: "种类系数", defaultValue: 1 }
  ],
  explosives: [
    { key: "magPrice", label: "弹夹价格", defaultValue: 500 },
    { key: "magSize", label: "弹容量", defaultValue: 1 },
    { key: "level", label: "限制等级", defaultValue: 10 },
    { key: "weightLayers", label: "加权层数", defaultValue: 0 }
  ],
  "physical-damage": [
    { key: "damage", label: "伤害", defaultValue: 100 },
    { key: "defence", label: "防御", defaultValue: 50 },
    { key: "penetration", label: "穿透(0-1)", defaultValue: 0 },
    { key: "hp", label: "HP", defaultValue: 1000 }
  ],
  "magic-damage": [
    { key: "damage", label: "伤害", defaultValue: 100 },
    { key: "magicResist", label: "魔抗(0-100)", defaultValue: 30 },
    { key: "hp", label: "HP", defaultValue: 1000 }
  ],
  potions: [
    { key: "hp", label: "恢复HP", defaultValue: 100 },
    { key: "mp", label: "恢复MP", defaultValue: 0 },
    { key: "sustainFrames", label: "缓释帧(0=瞬间)", defaultValue: 0 },
    { key: "playerLevel", label: "玩家等级", defaultValue: 10 },
    { key: "isGroup", label: "群体(0/1)", defaultValue: 0 },
    { key: "purifyValue", label: "净化值", defaultValue: 0 },
    { key: "toxicity", label: "剧毒性", defaultValue: 0 },
    { key: "buffHp", label: "buff HP", defaultValue: 0 },
    { key: "buffMp", label: "buff MP", defaultValue: 0 },
    { key: "buffDefence", label: "buff 防御", defaultValue: 0 },
    { key: "buffMagicResist", label: "buff 法抗", defaultValue: 0 },
    { key: "buffDamage", label: "buff 伤害", defaultValue: 0 },
    { key: "buffPunch", label: "buff 空手", defaultValue: 0 },
    { key: "buffSpeed", label: "buff 速度", defaultValue: 0 },
    { key: "buffDuration", label: "buff 帧(0=永久)", defaultValue: 0 }
  ],
  monsters: [
    { key: "stage", label: "阶段", defaultValue: 1 },
    { key: "tierFactor", label: "档次系数", defaultValue: 5 },
    { key: "growthFactor", label: "成长系数", defaultValue: 1 },
    { key: "atkSpeedFactor", label: "攻速系数", defaultValue: 1 },
    { key: "atkMultiplier", label: "攻击倍率", defaultValue: 1 },
    { key: "segmentFactor", label: "段数系数", defaultValue: 3 },
    { key: "speedFactor", label: "速度系数", defaultValue: 1 },
    { key: "highAtkFactor", label: "高攻低血防系数", defaultValue: 1 },
    { key: "superArmorFactor", label: "霸体系数", defaultValue: 1 },
    { key: "highDefFactor", label: "高防低血系数", defaultValue: 1 }
  ]
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any -- spread typed outputs into plain records
function toRecord(obj: any): Record<string, number> {
  return { ...obj } as Record<string, number>;
}

function computeOutput(
  engine: FormulaEngine,
  values: Record<string, number>
): Record<string, number> {
  try {
    switch (engine) {
      case "weapons":
        return toRecord(computeWeaponRow(values as never));
      case "armor":
        return toRecord(computeArmorRow(values as never));
      case "melee":
        return toRecord(computeMeleeRow(values as never));
      case "explosives":
        return toRecord(computeExplosivesRow(values as never));
      case "physical-damage":
        return toRecord(computePhysicalDamage(values as never));
      case "magic-damage":
        return toRecord(computeMagicDamage(values as never));
      case "potions":
        return toRecord(computePotionRow(values as never));
      case "monsters":
        return toRecord(computeMonsterRow(values as never));
    }
  } catch {
    return {};
  }
}

const OUTPUT_LABELS: Record<string, string> = {
  // weapons
  averageDPS: "平均DPS",
  weightedDPS: "加权DPS",
  balanceDPS: "平衡DPS",
  cycleDamage: "周期伤害",
  singleShotDamage: "单段伤害",
  averageFireRate: "平均射速(发/秒)",
  hitRate: "吃拐率",
  nakedDPS: "裸伤DPS",
  economicDPS: "经济DPS",
  boostDPS: "增益DPS",
  recommendedGoldPrice: "推荐金币价格",
  recommendedKPointPrice: "推荐K点价格",
  // armor
  currentScore: "当前总分",
  balanceScore: "平衡总分",
  weightedScore: "加权总分",
  magicDefenceCap: "法抗上限",
  recommendedPrice: "推荐价格",
  // melee
  recommendedSharpness: "推荐锋利度",
  // explosives
  recommendedPower: "推荐单发威力",
  // damage
  effectiveDefence: "有效防御",
  reductionRatio: "减伤比例",
  remainRatio: "剩余比例",
  effectiveHP: "等效血量",
  finalDamage: "最终伤害",
  hitsToKill: "承伤次数",
  // potions
  recoveryStrength: "恢复强度",
  purifyStrength: "净化强度",
  toxicStrength: "剧毒强度",
  buffStrength: "增益强度",
  totalStrength: "总强度",
  recommendedValue: "推荐数值",
  // monsters
  atkMin: "攻击MIN",
  atkMax: "攻击MAX",
  hpMin: "HP MIN",
  hpMax: "HP MAX",
  defMin: "防御MIN",
  defMax: "防御MAX",
  expMin: "经验MIN",
  expMax: "经验MAX",
  goldPrice: "金币价格",
  kPointPrice: "K点价格"
};

export function FormulaBar() {
  const [engine, setEngine] = useState<FormulaEngine>("weapons");
  const [values, setValues] = useState<Record<string, Record<string, number>>>(() => {
    const init: Record<string, Record<string, number>> = {};
    for (const [key, fields] of Object.entries(ENGINE_FIELDS)) {
      const defaults: Record<string, number> = {};
      for (const f of fields) defaults[f.key] = f.defaultValue;
      init[key] = defaults;
    }
    return init;
  });

  const currentValues = values[engine] ?? {};
  const fields = ENGINE_FIELDS[engine];

  const output = useMemo(
    () => computeOutput(engine, currentValues),
    [engine, currentValues]
  );

  const handleFieldChange = useCallback(
    (key: string, raw: string) => {
      const num = Number(raw);
      if (Number.isNaN(num)) return;
      setValues((prev) => ({
        ...prev,
        [engine]: { ...prev[engine], [key]: num }
      }));
    },
    [engine]
  );

  const outputEntries = Object.entries(output).filter(
    ([, v]) => typeof v === "number" && Number.isFinite(v)
  );

  return (
    <section className="detail-section">
      <div className="detail-section-header">
        <h4>公式计算器</h4>
      </div>
      <div className="formula-bar-engine">
        <select
          className="formula-bar-select"
          value={engine}
          onChange={(e) => setEngine(e.currentTarget.value as FormulaEngine)}
        >
          {ENGINE_OPTIONS.map((opt) => (
            <option key={opt.value} value={opt.value}>
              {opt.label}
            </option>
          ))}
        </select>
      </div>
      <div className="formula-bar-inputs">
        {fields.map((field) => (
          <label className="formula-bar-field" key={field.key}>
            <span className="formula-bar-label">{field.label}</span>
            <input
              className="formula-bar-input"
              type="number"
              value={currentValues[field.key] ?? field.defaultValue}
              onChange={(e) => handleFieldChange(field.key, e.currentTarget.value)}
            />
          </label>
        ))}
      </div>
      {outputEntries.length > 0 && (
        <div className="formula-bar-outputs">
          <div className="formula-bar-output-title">计算结果</div>
          {outputEntries.map(([key, value]) => (
            <div className="formula-bar-output-row" key={key}>
              <span>{OUTPUT_LABELS[key] ?? key}</span>
              <strong>{formatNum(value as number)}</strong>
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

function formatNum(value: number): string {
  if (Number.isInteger(value)) return value.toLocaleString("zh-CN");
  return value.toLocaleString("zh-CN", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 4
  });
}
