import { describe, expect, it } from "vitest";
import {
  computePotionV2Row,
  type PotionV2Input,
} from "../../src/formulas/potions.js";

const EMPTY: PotionV2Input = {
  instantHp: 0,
  instantMp: 0,
  regenHp: 0,
  regenMp: 0,
  regenFrames: 0,
  playerLevel: 1,
  isGroup: 0,
  purifyValue: 0,
  toxicity: 0,
  buffHp: 0,
  buffMp: 0,
  buffDefence: 0,
  buffMagicResist: 0,
  buffDamage: 0,
  buffPunch: 0,
  buffSpeed: 0,
  buffToughness: 0,
  buffDuration: 0,
};

describe("potion formula v2", () => {
  it("只折价混合食品中的缓释分量", () => {
    const output = computePotionV2Row({
      ...EMPTY,
      instantHp: 150,
      instantMp: 150,
      regenHp: 300,
      regenMp: 300,
      regenFrames: 900,
      playerLevel: 15,
    });

    expect(output.instantRecoveryStrength).toBe(300);
    expect(output.regenRecoveryStrength).toBe(600);
    expect(output.discountedRegenStrength).toBe(300);
    expect(output.currentValue).toBe(600);
  });

  it.each([
    ["番茄炒蛋", 200, 200, 0, 0, 0, 20, 20, 1, 1315],
    ["土豆炒肉丝", 200, 200, 0, 0, 0, 15, 30, 1, 1345.5],
    ["黄瓜炒肉片", 200, 200, 0, 0, 0, 25, 0, 1.5, 1315],
    ["蒜蓉炒空心菜", 200, 200, 0, 0, 5, 15, 0, 1, 1279.5],
    ["清炒白菜", 150, 150, 300, 300, 0, 18, 30, 0, 1295.4],
    ["清炒花菜", 200, 200, 0, 0, 0, 15, 25, 1, 1284.5],
    ["清炒土豆丝", 200, 200, 300, 0, 0, 15, 40, 0, 1312.5],
    ["葱花炒蛋", 200, 200, 0, 0, 0, 18, 22, 1, 1302.8],
  ])(
    "%s 落在 15 级配额内",
    (_name, hp, mp, regenHp, regenMp, purify, damage, defence, speed, expected) => {
      const output = computePotionV2Row({
        ...EMPTY,
        instantHp: hp,
        instantMp: mp,
        regenHp,
        regenMp,
        regenFrames: regenHp + regenMp > 0 ? (regenHp === 300 && regenMp === 0 ? 600 : 900) : 0,
        playerLevel: 15,
        purifyValue: purify,
        buffDamage: damage,
        buffDefence: defence,
        buffSpeed: speed,
        buffDuration: 1800,
      });

      expect(output.currentValue).toBeCloseTo(expected, 6);
      expect(output.currentValue).toBeLessThanOrEqual(1600);
    },
  );

  it.each([
    [20, 300, 360, 550, 275, 17.5, 20, 2750, 1210],
    [40, 450, 580, 875, 440, 27.5, 36, 4375, 2800],
    [60, 600, 760, 1150, 575, 37.5, 46, 5750, 4830],
  ])(
    "九龙 %i 级档位的 toughness 与防御预算等价",
    (level, duration, damage, defence, punch, speed, allResistanceInput, toughness, expectedDefenceStrength) => {
      const defenceOutput = computePotionV2Row({
        ...EMPTY,
        playerLevel: level,
        buffDefence: defence,
        buffDuration: duration,
      });
      const toughnessOutput = computePotionV2Row({
        ...EMPTY,
        playerLevel: level,
        buffToughness: toughness,
        buffDuration: duration,
      });

      expect(defenceOutput.buffStrength).toBeCloseTo(expectedDefenceStrength, 6);
      expect(toughnessOutput.buffStrength).toBeCloseTo(defenceOutput.buffStrength, 6);
      expect(
        computePotionV2Row({ ...EMPTY, playerLevel: level, buffDamage: damage, buffDuration: duration }).currentValue,
      ).toBeLessThanOrEqual(100 + level * 100);
      expect(
        computePotionV2Row({ ...EMPTY, playerLevel: level, buffPunch: punch, buffDuration: duration }).currentValue,
      ).toBeLessThanOrEqual(100 + level * 100);
      expect(
        computePotionV2Row({ ...EMPTY, playerLevel: level, buffSpeed: speed, buffDuration: duration }).currentValue,
      ).toBeLessThanOrEqual(100 + level * 100);
      expect(
        computePotionV2Row({
          ...EMPTY,
          playerLevel: level,
          buffMagicResist: allResistanceInput,
          buffDuration: duration,
        }).currentValue,
      ).toBeLessThanOrEqual(100 + level * 100);
    },
  );
});
