export interface WeaponBalanceRuleDefinition {
  id: string;
  domain: string;
  allowedTargetPrefixes: readonly string[];
  playerProjectable: boolean;
}

const RULE_NUMBERS_BY_DOMAIN = {
  AMMO: [1, 2],
  AUTH: [1, 2, 3, 4],
  CAP: [1, 2],
  CAT: [1, 2],
  DMG: [1, 2, 3, 4],
  DPS: [1, 2, 3],
  DUAL: [1],
  FIRE: [1, 2],
  INT: [1, 2],
  LAYER: [1, 2, 3, 4, 5],
  MAP: [1, 2],
  PIERCE: [1, 2, 3, 4],
  PL: [1, 2, 3, 4, 5],
  PRICE: [1, 2, 3, 4],
  SHOT: [1, 2, 3],
  TRIAGE: [1, 2, 3],
  WL: [1, 2, 3, 4, 5, 6, 7, 8, 9]
} as const;

const TARGET_POLICY_BY_DOMAIN: Record<
  keyof typeof RULE_NUMBERS_BY_DOMAIN,
  { prefixes: readonly string[]; playerProjectable: boolean }
> = {
  AMMO: { prefixes: ["input.magPrice"], playerProjectable: true },
  AUTH: {
    prefixes: ["audit.", "evidence.", "input.formula"],
    playerProjectable: false
  },
  CAP: { prefixes: ["mechanic.capacity"], playerProjectable: true },
  CAT: { prefixes: ["input.category"], playerProjectable: false },
  DMG: { prefixes: ["input.damageType"], playerProjectable: true },
  DPS: { prefixes: ["metric."], playerProjectable: false },
  DUAL: { prefixes: ["input.dualWield"], playerProjectable: true },
  FIRE: { prefixes: ["mechanic.fireMode"], playerProjectable: true },
  INT: { prefixes: ["mechanic.interval"], playerProjectable: true },
  LAYER: { prefixes: ["mechanic."], playerProjectable: true },
  MAP: { prefixes: ["pricing."], playerProjectable: false },
  PIERCE: { prefixes: ["input.pierce"], playerProjectable: true },
  PL: { prefixes: ["pricing.priceLayers"], playerProjectable: false },
  PRICE: { prefixes: ["pricing."], playerProjectable: false },
  SHOT: { prefixes: ["input.shotgun"], playerProjectable: true },
  TRIAGE: { prefixes: ["audit.status"], playerProjectable: false },
  WL: {
    prefixes: ["input.weightLayers", "budget."],
    playerProjectable: true
  }
};

export const WEAPON_BALANCE_RULE_CATALOG: readonly WeaponBalanceRuleDefinition[] =
  Object.entries(RULE_NUMBERS_BY_DOMAIN).flatMap(([domain, numbers]) => {
    const policy = TARGET_POLICY_BY_DOMAIN[
      domain as keyof typeof TARGET_POLICY_BY_DOMAIN
    ];

    return numbers.map((number) => ({
      id: `WBR-${domain}-${String(number).padStart(3, "0")}`,
      domain,
      allowedTargetPrefixes: policy.prefixes,
      playerProjectable: policy.playerProjectable
    }));
  });

const RULES_BY_ID = new Map(
  WEAPON_BALANCE_RULE_CATALOG.map((rule) => [rule.id, rule])
);

export const WEAPON_BALANCE_RULE_IDS = new Set(RULES_BY_ID.keys());

export function getWeaponBalanceRule(
  id: string
): WeaponBalanceRuleDefinition | undefined {
  return RULES_BY_ID.get(id);
}

export function isWeaponBalanceRuleId(id: string): boolean {
  return RULES_BY_ID.has(id);
}

export function isExplicitWeaponBalanceRuleTarget(target: string): boolean {
  if (!/^[a-z][a-zA-Z0-9]*(?:\.[a-z][a-zA-Z0-9_-]*)+$/.test(target)) {
    return false;
  }

  const [root] = target.split(".");
  return [
    "input",
    "budget",
    "mechanic",
    "metric",
    "pricing",
    "audit",
    "evidence"
  ].includes(root ?? "");
}

export function isWeaponBalanceRuleTargetAllowed(
  ruleId: string,
  target: string
): boolean {
  const rule = getWeaponBalanceRule(ruleId);
  return Boolean(
    rule &&
      isExplicitWeaponBalanceRuleTarget(target) &&
      rule.allowedTargetPrefixes.some(
        (prefix) =>
          target === prefix || (prefix.endsWith(".") && target.startsWith(prefix))
      )
  );
}
