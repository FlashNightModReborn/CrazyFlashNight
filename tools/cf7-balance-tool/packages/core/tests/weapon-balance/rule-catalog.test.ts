import { describe, expect, it } from "vitest";

import {
  WEAPON_BALANCE_RULE_CATALOG,
  WEAPON_BALANCE_RULE_IDS,
  isWeaponBalanceRuleTargetAllowed
} from "../../src/index.js";

describe("weapon balance rule catalog", () => {
  it("contains the 57 stable WBR ids from the current rulebook", () => {
    expect(WEAPON_BALANCE_RULE_CATALOG).toHaveLength(57);
    expect(WEAPON_BALANCE_RULE_IDS.size).toBe(57);
    expect(WEAPON_BALANCE_RULE_IDS).toContain("WBR-AUTH-001");
    expect(WEAPON_BALANCE_RULE_IDS).toContain("WBR-WL-009");
    expect(WEAPON_BALANCE_RULE_IDS).toContain("WBR-PRICE-004");
  });

  it("requires domain-compatible explicit targets", () => {
    expect(
      isWeaponBalanceRuleTargetAllowed("WBR-DUAL-001", "input.dualWield")
    ).toBe(true);
    expect(
      isWeaponBalanceRuleTargetAllowed("WBR-DUAL-001", "input.pierce")
    ).toBe(false);
    expect(
      isWeaponBalanceRuleTargetAllowed(
        "WBR-DUAL-001",
        "input.dualWieldUnexpectedSuffix"
      )
    ).toBe(false);
  });
});
