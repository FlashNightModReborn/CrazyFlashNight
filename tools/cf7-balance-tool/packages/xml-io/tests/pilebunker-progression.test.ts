import { describe, expect, it } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { XMLParser } from "fast-xml-parser";
import { resolveWeaponItemEffectiveProfile } from "../src/weapon-balance.js";
import { buildReport, defenceTransfer, deriveBranches, burstTierMultiplier } from "../../../models/pilebunker/model.js";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../../../../..");
const parser = new XMLParser({ ignoreAttributes: false, parseTagValue: true });
const items = parser.parse(fs.readFileSync(path.join(root, "data/items/武器_长枪_近战.xml"), "utf8")).root.item;
const raw = items.find((item: any) => item.name === "火药燃气液压打桩机");

describe("打桩机在原物品身份内进阶", () => {
  it("按刀页总层与0层的差额转让，重量项不得重复转让", () => {
    expect(defenceTransfer(35,80,3).transferredSharpness).toBeCloseTo(333.59375,8);
    expect(defenceTransfer(55,150,5).transferredSharpness).toBeCloseTo(1128.466796875,8);
    expect(defenceTransfer(35,150,3).transferredSharpness).toBe(defenceTransfer(35,80,3).transferredSharpness);
    const report = buildReport();
    expect(report.profiles.map(p => p.totalWeightLayers)).toEqual([3,5]);
    for (const profile of report.profiles) {
      expect(profile.gunWeightLayers).toBe(0);
      expect(profile.power).toBe(profile.candidatePower);
      expect(profile.actualDefence).toBe(profile.transfer.defence);
      expect(profile.actualHp).toBe(profile.transfer.hp);
      expect(Math.abs(profile.transfer.roundingResidual)).toBeLessThan(1);
    }
  });
  it("基础形态保留旧外观和生命周期，进阶独立覆盖战技与玩法", () => {
    const base = resolveWeaponItemEffectiveProfile(raw, "data", 1);
    const tier = resolveWeaponItemEffectiveProfile(raw, "data_pilebunker_m7", 1);
    expect(base.itemName).toBe(tier.itemName);
    expect(base.effectiveData.clipname).toBe("榴弹弹药");
    expect(tier.effectiveData.clipname).toBe("榴弹弹药");
    expect(items.some((item: any) => item.name === "重锤燃气打桩机")).toBe(false);
    expect(base.effectiveSkill).toBeNull();
    expect(base.effectiveData.dressup).toBe("枪-长枪-火药燃气液压打桩机");
    expect((base.effectiveLifecycle as any).attr_0.init.initRoutines).toBe("火药燃气液压打桩机初始化");
    expect(tier.effectiveData).toMatchObject({ level: 55, weight: 150, capacity: 3, split: 3, impact: 1, accuracy: 300, evasion: 300, toughness: 300 });
    expect(base.effectiveData).toMatchObject({ impact: 1, accuracy: 300, evasion: 300, toughness: 300 });
    expect((tier.effectiveLifecycle as any).attr_0.init.initRoutines).toBe("打桩机M7初始化");
    expect(tier.effectiveSkill).toMatchObject({ skillname: "打桩过载", mp: 120, cd: 10000 });
    expect(raw.data.weight).toBe(80);
  });

  it("按2秒间隔加真实44帧蓄力反推倍率，单弹容不吞掉机械时间", () => {
    const tier = buildReport().profiles[1];
    expect(tier.derived).toMatchObject({ fps: 30, chargeFrames: 44, intervalFrames: 60,
      recoveryFrames: { N0: 35, N1: 56, S1: 68 } });
    expect(tier.derived!.chargedIntervalMs).toBeCloseTo(104 / 30 * 1000, 8);
    expect(tier.derived!.burstCycleOverheadMs).toBeCloseTo(112 / 30 * 1000, 8);
    expect(tier.derived!.literalWorkbookCap1Power).toBeLessThan(tier.derived!.chargedPower);
    expect(tier.derived!.burstPower).toBeGreaterThan(tier.derived!.chargedPower);
    expect(tier.branches[1].multiplier).toBe(1.5);
    expect(tier.branches[2].multiplier).toBe(3);
    expect(tier.branches[1].templatePower).toBe(26130);
    expect(tier.branches[2].templatePower).toBe(52260);
    expect(tier.multiplierPolicy).toMatchObject({mode:"three_ammo_indicators",middle:2});
    expect(tier.multiplierPolicy!.chargedDeltaPercent).toBeCloseTo(-4.0044, 3);
    expect(tier.multiplierPolicy!.middleDeltaPercent).toBeCloseTo(-11.0430, 3);
    expect(tier.multiplierPolicy!.fullDeltaPercent).toBeCloseTo(2.2500, 3);
    expect(tier.meleePower).toBe(890);
    expect(tier.meleePower).toBe(tier.meleeCandidatePower);
    expect(tier.branches[2].cooldownMs).toBe(10000);
    expect(tier.branches[2].mpPerShot).toBe(120);
  });

  it("原版获得0层普通锤，两形态+200%换弹代偿不追加枪械威力预算", () => {
    const base = resolveWeaponItemEffectiveProfile(raw, "data", 1);
    const tier = resolveWeaponItemEffectiveProfile(raw, "data_pilebunker_m7", 1);
    const param = (base.effectiveLifecycle as any).attr_0.init.initParam;
    expect(param).toMatchObject({bladePower:590,bladeRotation:90,bladeFaceHalfHeight:100});
    expect(param.flamethrower).toBeUndefined();
    expect(base.effectiveSkill).toBeNull();
    expect([base.effectiveData.reloadPenalty,tier.effectiveData.reloadPenalty]).toEqual([200,200]);
    const report = buildReport();
    expect(report.profiles.map(p => p.power)).toEqual([8270,17420]);
    expect(report.profiles.map(p => p.meleePower)).toEqual([590,890]);
    for (const profile of report.profiles) {
      expect(profile.meleeCandidatePower).toBe(profile.meleePower);
      expect(profile.reloadTradeoff).toEqual({penaltyPercent:200,normalMainBurden:300,
        ordinaryAnimationMultiplier:3,skillReloadPath:"unchanged",formulaReloadAssumptionMs:900,increasesGunPowerBudget:false});
    }
  });

  it("余弹1/2/3映射1.5/2/3档，每次只发射一次并耗尽余弹", () => {
    const tier = buildReport().profiles[1];
    const [one, two, three] = tier.burstByRemaining;
    expect(one.multiplier).toBe(tier.branches[1].multiplier);
    expect(three.multiplier).toBe(tier.branches[2].multiplier);
    expect([one.multiplier, two.multiplier, three.multiplier]).toEqual([1.5, 2, 3]);
    for (const shot of tier.burstByRemaining) {
      expect(shot.ammoSpent).toBe(shot.remaining);
      expect(shot.remainingAfter).toBe(0);
      expect(shot.emittedShots).toBe(1);
      expect(shot.mpCost).toBe(120);
      expect(shot.cooldownMs).toBe(10000);
    }
    expect(burstTierMultiplier(1.5, 2, 3, 1, 1)).toBe(3);
    expect([1,2,3,4].map(r => burstTierMultiplier(1.5, 2, 3, r, 4))).toEqual([1.5,2,3,3]);
    expect([1,2,3,4,5,6].map(r => burstTierMultiplier(1.5, 2, 3, r, 6))).toEqual([1.5,1.5,2,2,3,3]);
    for (const remaining of [0, -1, .5, 4, NaN]) expect(() => burstTierMultiplier(1.5, 2, 3, remaining, 3)).toThrow();
  });

  it("姿态时间改变会改变反推端点，MP与冷却不进入反推输入", () => {
    const pose = JSON.parse(fs.readFileSync(path.join(root, "data/weapon-animations/pilebunker-m7.json"), "utf8"));
    const fixed = { level: 55, weight: 150, shootInterval: 2000, magSize: 3, magPrice: 2500,
      dualWieldFactor: 1, pierceFactor: 1, damageTypeFactor: 1, shotgunValue: 3, impact: 1, extraWeightLayers: 0 };
    const before = deriveBranches(fixed, pose);
    pose.config.chargeCountMax += 30;
    const after = deriveBranches(fixed, pose);
    expect(after.normalPower).toBe(before.normalPower);
    expect(after.chargedPower).toBeGreaterThan(before.chargedPower);
    expect(after.burstPower).toBeGreaterThan(before.burstPower);
    expect(after.chargedIntervalMs - before.chargedIntervalMs).toBeCloseTo(1000, 8);
  });

  it("同一专属特殊槽切换喷火与过载，独立锋利度和燃料均有唯一参数源", () => {
    const tier = resolveWeaponItemEffectiveProfile(raw, "data_pilebunker_m7", 1);
    const param = (tier.effectiveLifecycle as any).attr_0.init.initParam;
    expect(param.bladePower).toBe(890);
    expect(param.bladePowerRatio).toBeUndefined();
    expect(param.flamethrower).toMatchObject({ power: 850, cd: 220, capacity: 12, initialLoaded: 12, range: 25, velocity: 45,
      diffusion: 10, impact: 100, bullet: "喷火束", mp: 0, consumeMode: "onLoadGroup", consumeTiming: "onReloadCommit", clipCostPerLoad: 1 });
    expect((tier.effectiveSkill as any).skillLocked).toBe(true);
    expect(param.skill_1).toMatchObject({ skillname: "燃气破坏", mp: 50, cd: 10000, skillLocked: true });
    expect(param.hammerBuffFrames).toBe(180);
    expect([param.flame_0.powerMultiplier,param.flame_1.powerMultiplier,param.flame_2.powerMultiplier]).toEqual([1,1.5,2]);
    expect(raw.subweapon).toBeUndefined();
    expect(raw.data_pilebunker_m7.subweapon).toBeUndefined();
    expect(buildReport().profiles[1].additionalMechanics!.status).toBe("runtime_candidate_not_in_base_DPS_budget");
  });

  it("专属重锤进阶不能使用通用二阶组件，武器没有独立合成产物", () => {
    const config = parser.parse(fs.readFileSync(path.join(root, "data/equipment/equipment_config.xml"), "utf8"));
    const mappings = config.root.EquipmentConfig.TierSystem.TierMapping;
    expect(mappings.some((m: any) => m["@_name"] === "重锤" && m["@_key"] === "data_pilebunker_m7" && m["@_material"] === "重锤改装组件")).toBe(true);
    expect(raw.data_2).toBeUndefined();
    for (const file of fs.readdirSync(path.join(root, "data/crafting")).filter((p) => p.endsWith(".json"))) {
      expect(fs.readFileSync(path.join(root, "data/crafting", file), "utf8")).not.toContain('"重锤燃气打桩机"');
    }
  });
});
