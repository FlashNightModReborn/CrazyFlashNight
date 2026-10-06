import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { XMLParser } from "fast-xml-parser";
import { computeWeaponRow, computeWeaponRowWithCycleOverhead, type WeaponInput } from "../../packages/core/src/formulas/weapons.js";
import { computeMeleeRow } from "../../packages/core/src/formulas/melee.js";
import { resolveWeaponItemEffectiveProfile } from "../../packages/xml-io/src/weapon-balance.js";

const directory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(directory, "../../../..");
const read = (relative: string) => fs.readFileSync(path.join(root, relative), "utf8");
const hash = (relative: string) => createHash("sha256").update(fs.readFileSync(path.join(root, relative))).digest("hex");
const parser = new XMLParser({ ignoreAttributes: false, parseTagValue: true });
const workbook = "0.说明文件与教程/武器-技能数值-价格-合成表填写的参考公式（修改后请勿上传git）.xlsx";

export function solveCandidate(fixed: Omit<WeaponInput, "bulletPower">, share = 1, cycleOverheadMs = 0): number {
  let lo = 1, hi = 100000;
  for (let i = 0; i < 70; i++) {
    const power = (lo + hi) / 2;
    const row = computeWeaponRowWithCycleOverhead({ ...fixed, bulletPower: power }, cycleOverheadMs);
    if (row.averageDPS > row.weightedDPS * share) hi = power;
    else lo = power;
  }
  return Math.round((lo + hi) / 20) * 10;
}

/** 使用三个机械弹仓指示窗的档位；扩容只改变余弹区间，不增加发射次数。 */
export function burstTierMultiplier(charged: number, middle: number, full: number, remaining: number, capacity: number): number {
  if (![charged, middle, full, remaining, capacity].every(Number.isFinite) || charged <= 0 || middle < charged || full < middle
      || !Number.isInteger(remaining) || !Number.isInteger(capacity) || remaining < 1 || remaining > capacity) {
    throw new Error("invalid burst tiers or ammunition");
  }
  return [charged, middle, full][Math.ceil(remaining * 3 / capacity) - 1]!;
}

export function deriveBranches(fixed: Omit<WeaponInput, "bulletPower">, pose: any) {
  const fps = Number(pose.fps);
  const chargeFrames = pose.config.chargeCountMax + pose.config.prepareTicks - 1;
  const intervalFrames = Math.ceil(fixed.shootInterval * fps / 1000);
  const recoveryFrames = Object.fromEntries(["N0", "N1", "S1"].map(branch =>
    [branch, pose.clips[branch].frames.length - (branch === "N0" ? pose.config.normalFireEntry0 : 0) - 1]));
  const repeatMs = (branch: string) => (Math.max(intervalFrames, recoveryFrames[branch]) + chargeFrames) * 1000 / fps;
  const chargedIntervalMs = repeatMs("N1"), burstCycleOverheadMs = repeatMs("S1");
  const normalPower = solveCandidate(fixed);
  const chargedPower = solveCandidate({ ...fixed, shootInterval: chargedIntervalMs });
  // cap=1会消去工作簿interval*(cap-1)；必须显式加回这一次完整机械周期。
  // 同一榴弹弹匣仍付同一价格；120 MP与10秒战技冷却不增加伤害预算。
  const burstPower = solveCandidate({ ...fixed, magSize: 1 }, 1, burstCycleOverheadMs);
  const roundedMultiplier = (power: number) => Math.round(power / normalPower * 1e6) / 1e6;
  return { fps, chargeFrames, intervalFrames, recoveryFrames, chargedIntervalMs, burstCycleOverheadMs,
    normalPower, chargedPower, burstPower,
    chargedMultiplier: roundedMultiplier(chargedPower), burstMultiplier: roundedMultiplier(burstPower),
    literalWorkbookCap1Power: solveCandidate({ ...fixed, magSize: 1 }) };
}

export function defenceTransfer(level: number, weight: number, layers: number, defenceShare = 0.7) {
  const sharpness = (weightLayers: number) => computeMeleeRow({ level, weight, weightLayers, damageTypeFactor: 1 }).recommendedSharpness;
  const baselineSharpness = sharpness(0), weightedSharpness = sharpness(layers);
  const transferredSharpness = weightedSharpness - baselineSharpness;
  const defence = Math.round(transferredSharpness * defenceShare * 1.5 / 5) * 5;
  const hp = Math.round(transferredSharpness * (1 - defenceShare) * 3 / 5) * 5;
  return { baselineSharpness, weightedSharpness, transferredSharpness, defence, hp,
    convertedSharpness: defence / 1.5 + hp / 3, roundingResidual: defence / 1.5 + hp / 3 - transferredSharpness };
}

export function buildReport() {
  const design = JSON.parse(fs.readFileSync(path.join(directory, "design.json"), "utf8"));
  if (hash(workbook) !== design.verifiedCurrentWorkbookSha256) throw new Error("权威工作簿已变化，须重核相关公式");
  const itemPath = "data/items/武器_长枪_近战.xml";
  const items = parser.parse(read(itemPath)).root.item;
  const matches = items.filter((item: any) => item.name === design.itemName);
  if (matches.length !== 1) throw new Error("必须保留唯一打桩机物品身份");
  const raw = matches[0];
  const ammoItems = parser.parse(read("data/items/消耗品_弹夹.xml")).root.item;
  const posePath = "data/weapon-animations/pilebunker-m7.json";
  const pose = JSON.parse(read(posePath));
  const profiles = Object.entries(design.profiles).map(([key, settings]: [string, any]) => {
    const effective = resolveWeaponItemEffectiveProfile(raw, key, design.workbookVersion);
    const d = effective.effectiveData as Record<string, number | string>;
    const ammo = ammoItems.find((item: any) => item.name === d.clipname);
    if (!ammo) throw new Error("缺少弹药价格来源");
    const transfer = defenceTransfer(Number(d.level), Number(d.weight), settings.totalWeightLayers, design.defenceAllocation.defenceShare);
    const fixed = {
      ...design.formulaInputs, level: Number(d.level), shootInterval: Number(d.interval),
      magSize: Number(d.capacity), magPrice: Number(ammo.price), weight: Number(d.weight),
      shotgunValue: Number(d.split), impact: Number(d.impact)
    };
    const row = computeWeaponRow({ ...fixed, bulletPower: Number(d.power) });
    const baseEncumbrance = 12 + Math.floor(Number(d.level) * 0.6);
    const speedRatio = (extraWeight: number) => {
      const weight = Number(d.weight) + extraWeight;
      if (weight < baseEncumbrance) return 1 + (baseEncumbrance - weight) / baseEncumbrance * 0.25;
      if (weight <= baseEncumbrance * 2) return 1;
      return 1 - Math.min(1, (weight - baseEncumbrance * 2) / (baseEncumbrance * 2)) * 0.25;
    };
    const skill = effective.effectiveSkill as any;
    const param = (effective.effectiveLifecycle as any)?.attr_0?.init?.initParam;
    const derived = key === "data_pilebunker_m7" ? deriveBranches(fixed, pose) : null;
    const branches = key === "data_pilebunker_m7" ? ["N0", "N1", "S1"].map((branch) => {
      const entry = branch === "N0" ? pose.config.normalFireEntry0 : 0;
      const chargeFrames = branch === "N0" ? 0 : pose.config.chargeCountMax + pose.config.prepareTicks - 1;
      const recoveryFrames = pose.clips[branch].frames.length - entry - 1;
      const multiplierKey = { N0: "normalPowerMultiplier", N1: "chargedPowerMultiplier", S1: "skillPowerMultiplier" }[branch]!;
      const multiplier = Number(param[multiplierKey]);
      if (!(multiplier > 0 && Number.isFinite(multiplier))) throw new Error("分支倍率无效");
      const mechanicalRepeatMs = Math.max(Math.ceil(Number(d.interval) * pose.fps / 1000), recoveryFrames) * 1000 / pose.fps
        + chargeFrames * 1000 / pose.fps;
      const repeatMs = Math.max(mechanicalRepeatMs, branch === "S1" ? Number(skill.cd) : 0);
      return { branch, multiplier, templatePower: Number(d.power) * multiplier,
        ammoPerShot: branch === "S1" ? Number(d.capacity) : 1,
        mpPerShot: branch === "S1" ? Number(skill.mp) : 0, recoveryFrames, chargeFrames,
        mechanicalRepeatMs, cooldownMs: branch === "S1" ? Number(skill.cd) : 0,
        repeatMsWithoutReload: repeatMs, templatePowerPerSecondWithoutReload: Number(d.power) * multiplier * 1000 / repeatMs };
    }) : [];
    const burstByRemaining = derived ? Array.from({ length: Number(d.capacity) }, (_, i) => {
      const remaining = i + 1;
      const multiplier = burstTierMultiplier(Number(param.chargedPowerMultiplier), Number(param.skillMiddlePowerMultiplier),
        Number(param.skillPowerMultiplier), remaining, Number(d.capacity));
      return { remaining, ammoTier: Math.ceil(remaining * 3 / Number(d.capacity)),
        ammoSpent: remaining, remainingAfter: 0, emittedShots: 1, multiplier,
        templatePower: Number(d.power) * multiplier, mpCost: Number(skill.mp), cooldownMs: Number(skill.cd) };
    }) : [];
    return { profileKey: key, level: Number(d.level), weight: Number(d.weight), power: Number(d.power),
      totalWeightLayers: settings.totalWeightLayers, gunWeightLayers: fixed.extraWeightLayers,
      candidatePower: solveCandidate(fixed, 1),
      formulaAverageDPS: row.averageDPS, zeroLayerWeightedDPS: row.weightedDPS,
      transfer, actualDefence: Number(d.defence || 0), actualHp: Number(d.hp || 0),
      weaponOnlySpeedRatio: speedRatio(0), speedRatioWith30kgOtherEquipment: speedRatio(30),
      meleePower: Number(param.bladePower),
      meleeCandidatePower: Math.round(computeMeleeRow({level:Number(d.level),weight:Number(d.weight),
        weightLayers:settings.bladeWeightLayers,damageTypeFactor:1}).recommendedSharpness),
      reloadTradeoff: { penaltyPercent:Number(d.reloadPenalty), normalMainBurden:100+Number(d.reloadPenalty),
        ordinaryAnimationMultiplier:(100+Number(d.reloadPenalty))/100, skillReloadPath:"unchanged",
        formulaReloadAssumptionMs:900, increasesGunPowerBudget:false },
      fuelModule: key === "data_pilebunker_m7" ? param.flamethrower : null,
      additionalMechanics: key === "data_pilebunker_m7" ? {chargedCrumble:param.chargedCrumble,skillExecute:param.skillExecute,
        hammerFrames:param.hammerBuffFrames,hammerCrumble:param.hammerCrumble,hammerExecute:param.hammerExecute,
        flameMultipliers:[param.flame_0.powerMultiplier,param.flame_1.powerMultiplier,param.flame_2.powerMultiplier],
        status:"runtime_candidate_not_in_base_DPS_budget"} : null,
      multiplierPolicy: derived ? {
        mode: "three_ammo_indicators", targets: design.gameplayMultipliers,
        charged: Number(param.chargedPowerMultiplier), middle: Number(param.skillMiddlePowerMultiplier), full: Number(param.skillPowerMultiplier),
        chargedDeltaPercent: (Number(param.chargedPowerMultiplier) / derived.chargedMultiplier - 1) * 100,
        middleDeltaPercent: (Number(param.skillMiddlePowerMultiplier) / ((derived.chargedMultiplier + derived.burstMultiplier) / 2) - 1) * 100,
        fullDeltaPercent: (Number(param.skillPowerMultiplier) / derived.burstMultiplier - 1) * 100
      } : null,
      derived, branches, burstByRemaining };
  });
  return { status: "candidate_numbers_unresolved", itemName: design.itemName,
    sources: { [itemPath]: hash(itemPath), [posePath]: hash(posePath), [workbook]: hash(workbook) },
    profiles, notes: design.notes };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const report = buildReport();
  if (process.argv.includes("--check")) {
    for (const profile of report.profiles) {
      if (profile.power !== profile.candidatePower) throw new Error(`${profile.profileKey}威力与当前候选预算未同步`);
      if (profile.actualDefence !== profile.transfer.defence || profile.actualHp !== profile.transfer.hp) throw new Error(`${profile.profileKey}防护转让未同步`);
      if (profile.meleePower !== profile.meleeCandidatePower) throw new Error(`${profile.profileKey}独立锋利度未同步`);
      if (profile.reloadTradeoff.penaltyPercent !== 200) throw new Error(`${profile.profileKey}换弹代偿未同步`);
      if (profile.multiplierPolicy && (profile.multiplierPolicy.charged !== profile.multiplierPolicy.targets.charged
          || profile.multiplierPolicy.middle !== profile.multiplierPolicy.targets.skillMiddle
          || profile.multiplierPolicy.full !== profile.multiplierPolicy.targets.skillFull)) throw new Error(`${profile.profileKey}三档取整裁定未同步`);
    }
  }
  const output = path.join(root, "tmp/pilebunker-m7/balance-report.json");
  fs.mkdirSync(path.dirname(output), { recursive: true });
  fs.writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
  console.log(JSON.stringify({ output, status: report.status, profiles: report.profiles }));
}
