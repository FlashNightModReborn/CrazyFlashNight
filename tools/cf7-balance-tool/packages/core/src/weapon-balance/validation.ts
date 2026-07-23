import { computeWeaponRow } from "../formulas/weapons.js";
import {
  computeWeaponBalanceInputDigest,
  hasCompleteWeaponBalanceDigestInput,
  isWeaponBalanceInputDigest,
  isWeaponBalanceSourceDigest,
  type WeaponBalanceInputDigestSource,
  type WeaponBalanceRuntimeInputs
} from "./digest.js";
import {
  CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION,
  WEAPON_BALANCE_WORKBOOK_SHA256_BY_VERSION,
  WEAPON_BALANCE_BUDGET_CODES,
  WEAPON_BALANCE_FORMULA_FAMILY,
  WEAPON_BALANCE_FORMULA_INPUT_KEYS,
  WEAPON_BALANCE_FORMULA_VERSION,
  WEAPON_BALANCE_SCHEMA_VERSION,
  type WeaponBalanceAuditLedger,
  type WeaponBalanceAuditRecord,
  type WeaponBalanceProfile
} from "./record.js";
import {
  isExplicitWeaponBalanceRuleTarget,
  isWeaponBalanceRuleId,
  isWeaponBalanceRuleTargetAllowed
} from "./rule-catalog.js";

export type WeaponBalanceValidationSeverity = "error" | "warning";

export interface WeaponBalanceValidationIssue {
  severity: WeaponBalanceValidationSeverity;
  code: string;
  path: string;
  message: string;
}

export interface WeaponBalanceValidationOptions {
  container?: {
    formulaFamily: string;
    schemaVersion: number;
    workbookVersion: number;
    profiles: Record<string, WeaponBalanceProfile>;
  };
  ledger?: WeaponBalanceAuditLedger;
  auditRecord?: WeaponBalanceAuditRecord;
  itemName?: string;
  profileKey?: string;
  currentWorkbookVersion?: number;
  currentInputDigest?: string;
  currentSourceDigest?: string;
  digestInput?: WeaponBalanceInputDigestSource;
  runtimeInputs?: WeaponBalanceRuntimeInputs;
  metrics?: WeaponBalanceMetricInputs;
}

export interface WeaponBalanceMetricInputs {
  averageDPS: number;
  weightedDPS: number;
}

export interface WeaponBalanceDerivedMetrics extends WeaponBalanceMetricInputs {
  residualRatio: number;
  withinCalibrationBand: boolean;
}

export interface WeaponBalanceValidationResult {
  valid: boolean;
  displayEligible: boolean;
  currentInputDigest?: string;
  currentSourceDigest?: string;
  metrics?: WeaponBalanceDerivedMetrics;
  issues: WeaponBalanceValidationIssue[];
}

const REQUIRED_CONFIRMED_RULE_TARGETS = WEAPON_BALANCE_FORMULA_INPUT_KEYS.map(
  (key) => `input.${key}`
);

/**
 * 校验一个有效数据 profile。inline 只是一份运行时副本；ledger 缺失、join
 * 失败或任一派生字段漂移都 fail closed。
 */
export function validateWeaponBalanceRecord(
  profile: WeaponBalanceProfile,
  options: WeaponBalanceValidationOptions = {}
): WeaponBalanceValidationResult {
  const issues: WeaponBalanceValidationIssue[] = [];
  const expectedWorkbookVersion =
    options.currentWorkbookVersion ?? CURRENT_WEAPON_BALANCE_WORKBOOK_VERSION;
  const profileKey = options.profileKey ?? profile.profileKey;
  const profilePath = `balance.profiles.${profileKey}`;
  const currentInputDigest = resolveCurrentInputDigest(options, issues, profilePath);
  const currentSourceDigest = validateCurrentSourceDigest(options, issues, profilePath);
  const metrics = resolveMetrics(profile, options, issues, profilePath);

  validateContainer(
    profile,
    profileKey,
    expectedWorkbookVersion,
    options,
    issues
  );
  validateProfileShape(profile, profilePath, issues);

  const auditRecord = options.auditRecord;
  if (!auditRecord) {
    addError(
      issues,
      "audit_record_missing",
      `${profilePath}.auditRef`,
      `no ledger record supplied for ${profile.auditRef || "<empty>"}`
    );
  } else {
    validateLedgerRoot(expectedWorkbookVersion, options, issues);
    validateAuditJoin(
      profile,
      auditRecord,
      options.itemName,
      profileKey,
      profilePath,
      currentInputDigest,
      currentSourceDigest,
      metrics,
      issues
    );
  }

  const valid = !issues.some((issue) => issue.severity === "error");
  const displayEligible = Boolean(
    valid &&
      auditRecord &&
      profile.status === "confirmed" &&
      auditRecord.status === "confirmed" &&
      profile.displayEligible &&
      auditRecord.displayEligible
  );
  const result: WeaponBalanceValidationResult = {
    valid,
    displayEligible,
    issues
  };
  if (currentInputDigest !== undefined) result.currentInputDigest = currentInputDigest;
  if (currentSourceDigest !== undefined) result.currentSourceDigest = currentSourceDigest;
  if (metrics !== undefined) result.metrics = metrics;
  return result;
}

/** Preferred name for new callers. */
export const validateWeaponBalanceProfile = validateWeaponBalanceRecord;

function validateContainer(
  profile: WeaponBalanceProfile,
  profileKey: string,
  expectedWorkbookVersion: number,
  options: WeaponBalanceValidationOptions,
  issues: WeaponBalanceValidationIssue[]
): void {
  const container = options.container;
  if (!container) {
    addError(issues, "balance_container_missing", "balance", "strict v1 container is required");
    return;
  }
  if (container.formulaFamily !== WEAPON_BALANCE_FORMULA_FAMILY) {
    addError(
      issues,
      "formula_family_invalid",
      "balance.formulaFamily",
      `expected ${WEAPON_BALANCE_FORMULA_FAMILY}`
    );
  }
  if (container.schemaVersion !== WEAPON_BALANCE_SCHEMA_VERSION) {
    addError(
      issues,
      "schema_version_invalid",
      "balance.schemaVersion",
      `expected ${WEAPON_BALANCE_SCHEMA_VERSION}`
    );
  }
  validateWorkbookVersion(
    container.workbookVersion,
    expectedWorkbookVersion,
    "balance.workbookVersion",
    issues
  );
  if (!container.profiles[profileKey]) {
    addError(
      issues,
      "profile_not_in_container",
      `balance.profiles.${profileKey}`,
      "selected profile does not exist in the balance container"
    );
  } else if (container.profiles[profileKey]!.auditRef !== profile.auditRef) {
    addError(
      issues,
      "profile_context_mismatch",
      `balance.profiles.${profileKey}.auditRef`,
      "selected profile differs from the profile stored in the container"
    );
  }
}

function validateProfileShape(
  profile: WeaponBalanceProfile,
  profilePath: string,
  issues: WeaponBalanceValidationIssue[]
): void {
  for (const key of WEAPON_BALANCE_FORMULA_INPUT_KEYS) {
    if (!Number.isFinite(profile[key])) {
      addError(
        issues,
        "formula_input_not_finite",
        `${profilePath}.${key}`,
        "expected a finite number"
      );
    }
  }
  if (profile.formula !== WEAPON_BALANCE_FORMULA_VERSION) {
    addError(
      issues,
      "formula_version_invalid",
      `${profilePath}.formula`,
      `formula must equal implemented version ${WEAPON_BALANCE_FORMULA_VERSION}`
    );
  }
  if (!profile.auditRef.trim()) {
    addError(issues, "audit_ref_missing", `${profilePath}.auditRef`, "auditRef is required");
  }
  if (!isWeaponBalanceInputDigest(profile.inputDigest)) {
    addError(
      issues,
      "input_digest_format_invalid",
      `${profilePath}.inputDigest`,
      "expected fnv1a32 followed by eight lower-case hex digits"
    );
  }
  if (profile.status !== "confirmed" && profile.displayEligible) {
    addError(
      issues,
      "display_eligibility_status_mismatch",
      `${profilePath}.displayEligible`,
      "unresolved and invalid profiles must set displayEligible=false"
    );
  }
}

function validateLedgerRoot(
  expectedWorkbookVersion: number,
  options: WeaponBalanceValidationOptions,
  issues: WeaponBalanceValidationIssue[]
): void {
  const ledger = options.ledger;
  if (!ledger) {
    addError(
      issues,
      "audit_ledger_missing",
      "weaponBalanceAudit",
      "strict v1 validation requires the external audit ledger"
    );
    return;
  }
  if (ledger.formulaFamily !== WEAPON_BALANCE_FORMULA_FAMILY) {
    addError(
      issues,
      "ledger_formula_family_invalid",
      "weaponBalanceAudit.formulaFamily",
      `expected ${WEAPON_BALANCE_FORMULA_FAMILY}`
    );
  }
  if (ledger.schemaVersion !== WEAPON_BALANCE_SCHEMA_VERSION) {
    addError(
      issues,
      "ledger_schema_version_invalid",
      "weaponBalanceAudit.schemaVersion",
      `expected ${WEAPON_BALANCE_SCHEMA_VERSION}`
    );
  }
  validateWorkbookVersion(
    ledger.workbookVersion,
    expectedWorkbookVersion,
    "weaponBalanceAudit.workbookVersion",
    issues,
    "ledger_workbook_version"
  );
  validateLedgerWorkbookMapping(ledger, issues);
  if (
    options.container &&
    ledger.workbookVersion !== options.container.workbookVersion
  ) {
    addError(
      issues,
      "ledger_container_workbook_mismatch",
      "weaponBalanceAudit.workbookVersion",
      "ledger and inline container must reference the same workbook"
    );
  }
}

function validateAuditJoin(
  profile: WeaponBalanceProfile,
  audit: WeaponBalanceAuditRecord,
  itemName: string | undefined,
  profileKey: string,
  profilePath: string,
  currentInputDigest: string | undefined,
  currentSourceDigest: string | undefined,
  metrics: WeaponBalanceDerivedMetrics | undefined,
  issues: WeaponBalanceValidationIssue[]
): void {
  const auditPath = `weaponBalanceAudit.records[${audit.auditRef}]`;
  if (profile.auditRef !== audit.auditRef) {
    addError(
      issues,
      "audit_ref_mismatch",
      `${profilePath}.auditRef`,
      `inline ${profile.auditRef} does not match ledger ${audit.auditRef}`
    );
  }
  if (!itemName) {
    addError(
      issues,
      "item_identity_missing",
      `${auditPath}.itemName`,
      "current itemName is required for ledger join"
    );
  } else if (audit.itemName !== itemName) {
    addError(
      issues,
      "audit_item_mismatch",
      `${auditPath}.itemName`,
      `expected ${itemName}, got ${audit.itemName}`
    );
  }
  if (audit.profileKey !== profileKey || profile.profileKey !== profileKey) {
    addError(
      issues,
      "audit_profile_mismatch",
      `${auditPath}.profileKey`,
      `expected ${profileKey}, got ${audit.profileKey}`
    );
  }

  for (const key of WEAPON_BALANCE_FORMULA_INPUT_KEYS) {
    if (!Number.isFinite(audit[key])) {
      addError(
        issues,
        "ledger_formula_input_not_finite",
        `${auditPath}.${key}`,
        "expected a finite number"
      );
    }
    if (!Object.is(profile[key], audit[key])) {
      addError(
        issues,
        "inline_ledger_field_mismatch",
        `${profilePath}.${key}`,
        `inline ${profile[key]} does not match ledger ${audit[key]}`
      );
    }
  }
  if (audit.formula !== WEAPON_BALANCE_FORMULA_VERSION) {
    addError(
      issues,
      "ledger_formula_version_invalid",
      `${auditPath}.formula`,
      `formula must equal implemented version ${WEAPON_BALANCE_FORMULA_VERSION}`
    );
  }
  if (profile.status !== audit.status) {
    addError(
      issues,
      "inline_ledger_status_mismatch",
      `${profilePath}.status`,
      `inline ${profile.status} does not match ledger ${audit.status}`
    );
  }
  if (profile.displayEligible !== audit.displayEligible) {
    addError(
      issues,
      "inline_ledger_display_mismatch",
      `${profilePath}.displayEligible`,
      "inline displayEligible does not match ledger"
    );
  }
  if (profile.inputDigest !== audit.inputDigest) {
    addError(
      issues,
      "inline_ledger_digest_mismatch",
      `${profilePath}.inputDigest`,
      "inline inputDigest does not match ledger"
    );
  }

  validateAuditDigests(
    profile,
    audit,
    profilePath,
    auditPath,
    currentInputDigest,
    currentSourceDigest,
    issues
  );
  validateBudget(audit, auditPath, issues);
  validateRuleRefs(audit, auditPath, issues);
  validateAuditState(audit, auditPath, metrics, issues);
}

function validateAuditDigests(
  profile: WeaponBalanceProfile,
  audit: WeaponBalanceAuditRecord,
  profilePath: string,
  auditPath: string,
  currentInputDigest: string | undefined,
  currentSourceDigest: string | undefined,
  issues: WeaponBalanceValidationIssue[]
): void {
  if (!isWeaponBalanceInputDigest(audit.inputDigest)) {
    addError(
      issues,
      "ledger_input_digest_format_invalid",
      `${auditPath}.inputDigest`,
      "expected fnv1a32 followed by eight lower-case hex digits"
    );
  }
  if (!isWeaponBalanceSourceDigest(audit.sourceDigest)) {
    addError(
      issues,
      "source_digest_format_invalid",
      `${auditPath}.sourceDigest`,
      "expected sha256 followed by 64 lower-case hex digits"
    );
  }
  if (!currentInputDigest) {
    addError(
      issues,
      "input_digest_unverified",
      `${profilePath}.inputDigest`,
      "current item/profile inputs were not supplied"
    );
  } else {
    if (profile.inputDigest !== currentInputDigest) {
      addError(
        issues,
        "input_digest_mismatch",
        `${profilePath}.inputDigest`,
        `stored ${profile.inputDigest} does not match current ${currentInputDigest}`
      );
    }
    if (audit.inputDigest !== currentInputDigest) {
      addError(
        issues,
        "ledger_input_digest_mismatch",
        `${auditPath}.inputDigest`,
        `stored ${audit.inputDigest} does not match current ${currentInputDigest}`
      );
    }
  }
  if (!currentSourceDigest) {
    addError(
      issues,
      "source_digest_unverified",
      `${auditPath}.sourceDigest`,
      "current effective mechanics source was not supplied"
    );
  } else if (audit.sourceDigest !== currentSourceDigest) {
    addError(
      issues,
      "source_digest_mismatch",
      `${auditPath}.sourceDigest`,
      `stored ${audit.sourceDigest} does not match current ${currentSourceDigest}`
    );
  }
}

function validateBudget(
  audit: WeaponBalanceAuditRecord,
  auditPath: string,
  issues: WeaponBalanceValidationIssue[]
): void {
  let deltaTotal = 0;
  const codes = new Set<string>();
  audit.budgetBreakdown.forEach((entry, index) => {
    const path = `${auditPath}.budgetBreakdown.entry[${index}]`;
    if (!/^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)*$/.test(entry.code)) {
      addError(issues, "budget_code_invalid", `${path}.code`, "expected a stable lower-case semantic code");
    } else if (!(WEAPON_BALANCE_BUDGET_CODES as readonly string[]).includes(entry.code)) {
      addError(
        issues,
        "budget_code_unknown",
        `${path}.code`,
        `unsupported weapon balance budget code ${entry.code}`
      );
    } else if (codes.has(entry.code)) {
      addError(issues, "budget_code_duplicate", `${path}.code`, `duplicate budget code ${entry.code}`);
    } else {
      codes.add(entry.code);
    }
    if (!Number.isFinite(entry.delta)) {
      addError(issues, "budget_delta_not_finite", `${path}.delta`, "expected a finite number");
    } else {
      deltaTotal += entry.delta;
    }
    if (!isWeaponBalanceRuleId(entry.ruleRef)) {
      addError(issues, "rule_id_unknown", `${path}.ruleRef`, `unknown rule id ${entry.ruleRef || "<empty>"}`);
    } else if (!isWeaponBalanceRuleTargetAllowed(entry.ruleRef, `budget.${entry.code}`)) {
      addError(
        issues,
        "budget_rule_target_mismatch",
        `${path}.ruleRef`,
        `${entry.ruleRef} cannot justify a weight-layer budget entry`
      );
    }
  });
  if (Math.abs(deltaTotal - audit.weightLayers) > 1e-9) {
    addError(
      issues,
      "budget_sum_mismatch",
      `${auditPath}.budgetBreakdown`,
      `delta sum ${deltaTotal} does not equal weightLayers ${audit.weightLayers}`
    );
  }
}

function validateRuleRefs(
  audit: WeaponBalanceAuditRecord,
  auditPath: string,
  issues: WeaponBalanceValidationIssue[]
): void {
  const seen = new Set<string>();
  audit.ruleRefs.forEach((ref, index) => {
    const path = `${auditPath}.ruleRefs.ref[${index}]`;
    if (!isWeaponBalanceRuleId(ref.id)) {
      addError(issues, "rule_id_unknown", `${path}.id`, `unknown rule id ${ref.id || "<empty>"}`);
    }
    if (!isExplicitWeaponBalanceRuleTarget(ref.target)) {
      addError(issues, "rule_target_invalid", `${path}.target`, `target ${ref.target || "<empty>"} is not explicit`);
    } else if (isWeaponBalanceRuleId(ref.id) && !isWeaponBalanceRuleTargetAllowed(ref.id, ref.target)) {
      addError(issues, "rule_target_mismatch", `${path}.target`, `${ref.id} cannot target ${ref.target}`);
    }
    const identity = `${ref.id}\u0000${ref.target}`;
    if (seen.has(identity)) {
      addWarning(issues, "rule_ref_duplicate", path, `duplicate rule reference ${ref.id} -> ${ref.target}`);
    }
    seen.add(identity);
  });

  if (audit.category !== 1) {
    const supported = audit.ruleRefs.some(
      (ref) =>
        ref.id === "WBR-CAT-002" &&
        ref.target === "input.category" &&
        hasConcreteEvidence(ref.evidenceRef)
    );
    if (!supported) {
      addAuditDiagnostic(
        audit,
        issues,
        "non_default_category_unsubstantiated",
        `${auditPath}.category`,
        "category other than 1 requires WBR-CAT-002 with concrete evidenceRef"
      );
    }
  }
}

function validateAuditState(
  audit: WeaponBalanceAuditRecord,
  auditPath: string,
  metrics: WeaponBalanceDerivedMetrics | undefined,
  issues: WeaponBalanceValidationIssue[]
): void {
  if (audit.status !== "confirmed") {
    if (audit.displayEligible) {
      addError(
        issues,
        "ledger_display_eligibility_status_mismatch",
        `${auditPath}.displayEligible`,
        "unresolved and invalid records must set displayEligible=false"
      );
    }
    if (!audit.note?.trim()) {
      addError(
        issues,
        "pending_note_missing",
        `${auditPath}.note`,
        "unresolved and invalid records require a concise decision note"
      );
    }
    validatePendingEvidence(audit, auditPath, metrics, issues);
    return;
  }

  if (audit.budgetBreakdown.length === 0) {
    addError(
      issues,
      "budget_breakdown_missing",
      `${auditPath}.budgetBreakdown`,
      "confirmed weightLayers needs an explicit contribution, including a zero-delta baseline"
    );
  }
  if (audit.ruleRefs.length === 0) {
    addError(
      issues,
      "confirmed_rule_refs_missing",
      `${auditPath}.ruleRefs`,
      "confirmed record requires structured rule references"
    );
  }
  for (const target of REQUIRED_CONFIRMED_RULE_TARGETS) {
    const supported = audit.ruleRefs.some(
      (ref) =>
        ref.target === target &&
        isWeaponBalanceRuleId(ref.id) &&
        isWeaponBalanceRuleTargetAllowed(ref.id, ref.target) &&
        hasConcreteEvidence(ref.evidenceRef)
    );
    if (!supported) {
      addError(
        issues,
        "confirmed_input_evidence_missing",
        `${auditPath}.${target.slice("input.".length)}`,
        `${target} requires a compatible ruleRef with concrete evidenceRef`
      );
    }
  }
  audit.budgetBreakdown.forEach((entry, index) => {
    if (!hasConcreteEvidence(entry.evidenceRef)) {
      addError(
        issues,
        "confirmed_budget_evidence_missing",
        `${auditPath}.budgetBreakdown.entry[${index}].evidenceRef`,
        "confirmed budget entries require concrete evidenceRef"
      );
    }
  });
  if (!metrics) {
    addError(
      issues,
      "dps_metrics_unverified",
      `${auditPath}.status`,
      "confirmed record requires current averageDPS and weightedDPS verification"
    );
  } else if (!metrics.withinCalibrationBand) {
    addError(
      issues,
      "dps_residual_out_of_band",
      `${auditPath}.status`,
      `signed residual ${metrics.residualRatio} exceeds the +/-5% confirmed band`
    );
  }
}

function validatePendingEvidence(
  audit: WeaponBalanceAuditRecord,
  auditPath: string,
  metrics: WeaponBalanceDerivedMetrics | undefined,
  issues: WeaponBalanceValidationIssue[]
): void {
  for (const target of REQUIRED_CONFIRMED_RULE_TARGETS) {
    const supported = audit.ruleRefs.some(
      (ref) =>
        ref.target === target &&
        isWeaponBalanceRuleId(ref.id) &&
        isWeaponBalanceRuleTargetAllowed(ref.id, ref.target) &&
        hasConcreteEvidence(ref.evidenceRef)
    );
    if (!supported) {
      addWarning(
        issues,
        "pending_input_evidence",
        `${auditPath}.${target.slice("input.".length)}`,
        `${target} still needs a compatible concrete evidenceRef`
      );
    }
  }
  if (!metrics) {
    addWarning(issues, "pending_dps_metrics", `${auditPath}.status`, "current DPS metrics have not been verified");
  } else if (!metrics.withinCalibrationBand) {
    addWarning(
      issues,
      "pending_dps_residual",
      `${auditPath}.status`,
      `signed residual ${metrics.residualRatio} remains outside the +/-5% band`
    );
  }
}

function resolveCurrentInputDigest(
  options: WeaponBalanceValidationOptions,
  issues: WeaponBalanceValidationIssue[],
  profilePath: string
): string | undefined {
  if (options.digestInput) {
    if (
      options.container &&
      options.digestInput.workbookVersion !== options.container.workbookVersion
    ) {
      addError(
        issues,
        "input_digest_workbook_context_mismatch",
        `${profilePath}.inputDigest`,
        "digest workbookVersion differs from the runtime container"
      );
    }
    if (!hasCompleteWeaponBalanceDigestInput(options.digestInput)) {
      addError(
        issues,
        "input_digest_source_incomplete",
        `${profilePath}.inputDigest`,
        "itemName, profileKey, six runtime numbers and eight formula numbers are required"
      );
      return undefined;
    }
    const computed = computeWeaponBalanceInputDigest(options.digestInput);
    if (options.currentInputDigest !== undefined && options.currentInputDigest !== computed) {
      addError(
        issues,
        "input_digest_context_conflict",
        `${profilePath}.inputDigest`,
        "provided current digest disagrees with canonical digest input"
      );
    }
    return computed;
  }
  if (options.currentInputDigest !== undefined) {
    if (!isWeaponBalanceInputDigest(options.currentInputDigest)) {
      addError(
        issues,
        "current_input_digest_format_invalid",
        `${profilePath}.inputDigest`,
        "current digest must use fnv1a32:<8 lower-case hex>"
      );
      return undefined;
    }
    return options.currentInputDigest;
  }
  return undefined;
}

function validateCurrentSourceDigest(
  options: WeaponBalanceValidationOptions,
  issues: WeaponBalanceValidationIssue[],
  profilePath: string
): string | undefined {
  if (options.currentSourceDigest === undefined) return undefined;
  if (!isWeaponBalanceSourceDigest(options.currentSourceDigest)) {
    addError(
      issues,
      "current_source_digest_format_invalid",
      `${profilePath}.auditRef`,
      "current source digest must use sha256:<64 lower-case hex>"
    );
    return undefined;
  }
  return options.currentSourceDigest;
}

function resolveMetrics(
  profile: WeaponBalanceProfile,
  options: WeaponBalanceValidationOptions,
  issues: WeaponBalanceValidationIssue[],
  profilePath: string
): WeaponBalanceDerivedMetrics | undefined {
  let metricInputs = options.metrics;
  if (options.runtimeInputs) {
    const runtime = options.runtimeInputs;
    if (!Object.values(runtime).every((value) => Number.isFinite(value))) {
      addError(issues, "runtime_inputs_not_finite", profilePath, "runtime inputs must be finite numbers");
      return undefined;
    }
    const output = computeWeaponRow({
      level: runtime.level,
      bulletPower: runtime.power,
      shootInterval: runtime.interval,
      magSize: runtime.capacity,
      magPrice: profile.magPrice,
      weight: runtime.weight,
      dualWieldFactor: profile.dualWield,
      pierceFactor: profile.pierce,
      damageTypeFactor: profile.damageType,
      shotgunValue: profile.shotgun,
      impact: runtime.impact,
      extraWeightLayers: profile.weightLayers
    });
    metricInputs = { averageDPS: output.averageDPS, weightedDPS: output.weightedDPS };
  }
  if (!metricInputs) return undefined;
  if (
    !Number.isFinite(metricInputs.averageDPS) ||
    !Number.isFinite(metricInputs.weightedDPS) ||
    metricInputs.weightedDPS <= 0
  ) {
    addError(
      issues,
      "dps_metrics_invalid",
      profilePath,
      "averageDPS and weightedDPS must be finite and weightedDPS positive"
    );
    return undefined;
  }
  const residualRatio =
    (metricInputs.averageDPS - metricInputs.weightedDPS) /
    metricInputs.weightedDPS;
  return {
    averageDPS: metricInputs.averageDPS,
    weightedDPS: metricInputs.weightedDPS,
    residualRatio,
    withinCalibrationBand: Math.abs(residualRatio) <= 0.05
  };
}

function validateWorkbookVersion(
  value: number,
  expected: number,
  path: string,
  issues: WeaponBalanceValidationIssue[],
  codePrefix = "workbook_version"
): void {
  if (!Number.isInteger(value) || value <= 0) {
    addError(
      issues,
      `${codePrefix}_format_invalid`,
      path,
      "expected a positive integer"
    );
    return;
  }
  if (WEAPON_BALANCE_WORKBOOK_SHA256_BY_VERSION[value] === undefined) {
    addError(
      issues,
      `${codePrefix}_unknown`,
      path,
      `unsupported workbook version ${value}`
    );
  }
  if (value !== expected) {
    addError(
      issues,
      `${codePrefix}_stale`,
      path,
      "does not match the current authoritative workbook version"
    );
  }
}

function validateLedgerWorkbookMapping(
  ledger: WeaponBalanceAuditLedger,
  issues: WeaponBalanceValidationIssue[]
): void {
  const path = "weaponBalanceAudit.workbookSha256";
  if (!/^[0-9A-F]{64}$/.test(ledger.workbookSha256)) {
    addError(
      issues,
      "ledger_workbook_sha_format_invalid",
      path,
      "expected 64 upper-case hex digits"
    );
  }
  const expected =
    WEAPON_BALANCE_WORKBOOK_SHA256_BY_VERSION[ledger.workbookVersion];
  if (expected === undefined) return;
  if (ledger.workbookSha256 !== expected) {
    addError(
      issues,
      "ledger_workbook_sha_mapping_mismatch",
      path,
      `does not match workbookVersion ${ledger.workbookVersion}`
    );
  }
}

function addAuditDiagnostic(
  audit: WeaponBalanceAuditRecord,
  issues: WeaponBalanceValidationIssue[],
  code: string,
  path: string,
  message: string
): void {
  if (audit.status === "confirmed") addError(issues, code, path, message);
  else addWarning(issues, code, path, message);
}

function hasConcreteEvidence(value: string | undefined): boolean {
  const normalized = value?.trim();
  return Boolean(normalized && !normalized.toUpperCase().startsWith("UNRESOLVED:"));
}

function addError(
  issues: WeaponBalanceValidationIssue[],
  code: string,
  path: string,
  message: string
): void {
  issues.push({ severity: "error", code, path, message });
}

function addWarning(
  issues: WeaponBalanceValidationIssue[],
  code: string,
  path: string,
  message: string
): void {
  issues.push({ severity: "warning", code, path, message });
}
