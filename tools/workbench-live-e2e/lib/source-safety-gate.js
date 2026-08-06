"use strict";

const path = require("path");
const {
  canonicalJson,
  contractFail,
  isPlainObject,
  pathInside,
  readExactRegularFile,
  sha256Text,
} = require("./evidence-artifact");

// RETIRED: this regex scan is diagnostic compatibility evidence only. It is not
// an admission control, does not close transitive source dependencies, and must
// never be used to claim that a runner cannot synthesize business input. New
// runners must use source-fingerprint.js plus narrow runtime APIs and review.
const ADMISSION_STATUS = "RETIRED_DIAGNOSTIC_ONLY";
const GATE_SCHEMA = "workbench-live-e2e.tool-source-safety-gate.v1";
const RULES = Object.freeze([
  Object.freeze({ id: "playwright-page-click", pattern: /\bpage\s*\.\s*click\s*\(/ }),
  Object.freeze({ id: "playwright-locator-click", pattern: /\.\s*locator\s*\([^\r\n]*\)\s*\.\s*click\s*\(/ }),
  Object.freeze({ id: "playwright-mouse-input", pattern: /\bmouse\s*\.\s*(?:click|down|up|move)\s*\(/ }),
  Object.freeze({ id: "playwright-keyboard-input", pattern: /\bkeyboard\s*\.\s*(?:press|down|up|type|insertText)\s*\(/ }),
  Object.freeze({ id: "dom-dispatch-event", pattern: /\bdispatchEvent\s*\(/ }),
  Object.freeze({ id: "synthetic-input-constructor", pattern: /\bnew\s+(?:MouseEvent|PointerEvent|KeyboardEvent)\s*\(/ }),
  Object.freeze({ id: "cdp-input-domain", pattern: /\bInput\s*\.\s*dispatch(?:Mouse|Key|Touch)Event\b/ }),
  Object.freeze({ id: "bridge-business-send", pattern: /\b(?:window\s*\.\s*)?Bridge\s*\.\s*send\s*\(/ }),
  Object.freeze({ id: "uidata-business-dispatch", pattern: /\bUiData\s*\.\s*dispatch\s*\(/ }),
  Object.freeze({ id: "webview-business-post", pattern: /\bchrome\s*\.\s*webview\s*\.\s*postMessage\s*\(/ }),
]);
const RULE_IDS = Object.freeze(RULES.map((entry) => entry.id));

function normalizedRelativePaths(relativePaths) {
  if (!Array.isArray(relativePaths) || relativePaths.length < 1) {
    contractFail("source_gate_paths_invalid", "source_gate", "source gate needs an exact non-empty path set");
  }
  const normalized = relativePaths.map((entry) => String(entry || "").replace(/\\/g, "/"));
  normalized.forEach((entry) => {
    if (!entry || path.isAbsolute(entry) || entry.split("/").includes("..")
        || !entry.endsWith(".js")) {
      contractFail("source_gate_path_invalid", "source_gate", "source gate path is not closed", {
        relativePath: entry,
      });
    }
  });
  const sorted = Array.from(new Set(normalized)).sort();
  if (sorted.length !== normalized.length
      || canonicalJson(sorted) !== canonicalJson(normalized.slice().sort())) {
    contractFail("source_gate_paths_invalid", "source_gate", "source gate paths are duplicated");
  }
  return sorted;
}

function inspectSources(root, relativePaths) {
  const exactRoot = path.resolve(root);
  return normalizedRelativePaths(relativePaths).map((relativePath) => {
    const filePath = path.resolve(exactRoot, relativePath.replace(/\//g, path.sep));
    if (!pathInside(exactRoot, filePath)) {
      contractFail("source_gate_path_escape", "source_gate", "source path escaped the evidence root", {
        relativePath,
      });
    }
    const file = readExactRegularFile(filePath, { phase: "source_gate", maximumBytes: 4 * 1024 * 1024 });
    const text = file.bytes.toString("utf8");
    const violations = RULES.filter((rule) => rule.pattern.test(text)).map((rule) => rule.id);
    return { relativePath, sha256: file.sha256, bytes: file.length, violations };
  });
}

function unsignedGate(files, checkedAt) {
  return {
    schema: GATE_SCHEMA,
    admissionStatus: ADMISSION_STATUS,
    admissionEligible: false,
    checkedAt,
    status: files.every((entry) => entry.violations.length === 0) ? "pass" : "fail",
    ruleIds: RULE_IDS.slice(),
    files,
  };
}

function buildSourceSafetyGate(options) {
  const checkedAt = options && options.checkedAt ? String(options.checkedAt) : new Date().toISOString();
  if (!Number.isFinite(Date.parse(checkedAt))) {
    contractFail("source_gate_time_invalid", "source_gate", "source gate timestamp is invalid");
  }
  const gate = unsignedGate(inspectSources(options.root, options.relativePaths), checkedAt);
  gate.manifestSha256 = sha256Text(canonicalJson(gate));
  if (gate.status !== "pass") {
    contractFail("source_gate_violation", "source_gate",
      "operational source contains a forbidden business-input primitive", {
        files: gate.files.filter((entry) => entry.violations.length > 0),
      });
  }
  return gate;
}

function verifySourceSafetyGate(options) {
  const gate = options && options.gate;
  if (!isPlainObject(gate) || gate.schema !== GATE_SCHEMA || gate.status !== "pass"
      || gate.admissionStatus !== ADMISSION_STATUS || gate.admissionEligible !== false
      || !Number.isFinite(Date.parse(gate.checkedAt))
      || !Array.isArray(gate.ruleIds) || canonicalJson(gate.ruleIds) !== canonicalJson(RULE_IDS)
      || !Array.isArray(gate.files) || !/^[a-f0-9]{64}$/.test(String(gate.manifestSha256 || ""))) {
    contractFail("source_gate_envelope_invalid", "source_gate", "source gate envelope is malformed");
  }
  const expectedPaths = normalizedRelativePaths(options.relativePaths);
  const declaredPaths = gate.files.map((entry) => entry && entry.relativePath);
  if (canonicalJson(declaredPaths) !== canonicalJson(expectedPaths)) {
    contractFail("source_gate_scope_invalid", "source_gate", "source gate does not cover the exact source set");
  }
  const recomputed = unsignedGate(inspectSources(options.root, expectedPaths), gate.checkedAt);
  const declaredUnsigned = {
    schema: gate.schema,
    admissionStatus: gate.admissionStatus,
    admissionEligible: gate.admissionEligible,
    checkedAt: gate.checkedAt,
    status: gate.status,
    ruleIds: gate.ruleIds,
    files: gate.files,
  };
  if (recomputed.status !== "pass" || canonicalJson(recomputed) !== canonicalJson(declaredUnsigned)
      || sha256Text(canonicalJson(declaredUnsigned)) !== gate.manifestSha256) {
    contractFail("source_gate_mismatch", "source_gate",
      "source gate no longer matches exact operational source bytes and rules");
  }
  return gate;
}

module.exports = {
  ADMISSION_STATUS,
  GATE_SCHEMA,
  RULE_IDS,
  buildSourceSafetyGate,
  verifySourceSafetyGate,
};
