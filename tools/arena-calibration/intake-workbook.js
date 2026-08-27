#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const AdmZip = require("adm-zip");
const ArenaCustomMatchCode = require("../../launcher/web/modules/arena-custom-match-code");
const units = require("../../data/units/units.json");
const {
  normalizeManifest,
  sha256OfValue,
  writeJsonFile,
} = require("./lib/arena-calibration-core");
const { assertSchemaInstance } = require("./lib/schema-registry");

const DEFAULT_SHEET = "斗兽标定组合";
const DEFAULT_OVERRIDES = path.join(__dirname, "workbook-overrides.json");
const TIMEOUT_POLICIES = Object.freeze({
  smoke: { frames: 3600, id: "smoke_3600" },
  exploration: { frames: 1800, id: "exploration_1800" },
  confirmatory: { frames: 1800, id: "confirmatory_1800" },
});

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function sha256Buffer(buffer) {
  return `sha256:${crypto.createHash("sha256").update(buffer).digest("hex")}`;
}

function sha256String(text) {
  return sha256Buffer(Buffer.from(String(text), "utf8"));
}

function decodeXml(text) {
  return String(text || "")
    .replace(/&#x([0-9a-f]+);/gi, (_match, value) => String.fromCodePoint(parseInt(value, 16)))
    .replace(/&#([0-9]+);/g, (_match, value) => String.fromCodePoint(parseInt(value, 10)))
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&");
}

function parseAttributes(text) {
  const attributes = {};
  String(text || "").replace(/([A-Za-z_:][A-Za-z0-9_.:-]*)="([^"]*)"/g, (_match, name, value) => {
    attributes[name] = decodeXml(value);
    return _match;
  });
  return attributes;
}

function textNodes(xml) {
  const values = [];
  String(xml || "").replace(/<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g, (_match, value) => {
    values.push(decodeXml(value));
    return _match;
  });
  return values.join("");
}

function readZipText(zip, entryName) {
  const entry = zip.getEntry(entryName);
  if (!entry) return null;
  return zip.readAsText(entry, "utf8");
}

function resolveWorksheetPath(target) {
  const normalized = String(target || "").replace(/\\/g, "/");
  if (normalized.startsWith("/")) return normalized.slice(1);
  return path.posix.normalize(path.posix.join("xl", normalized));
}

function readWorkbookCells(workbookPath, sheetName) {
  const workbookBytes = fs.readFileSync(workbookPath);
  const zip = new AdmZip(workbookBytes);
  const workbookXml = readZipText(zip, "xl/workbook.xml");
  const relsXml = readZipText(zip, "xl/_rels/workbook.xml.rels");
  if (!workbookXml || !relsXml) fail("workbook is missing required OpenXML workbook parts");

  let relationshipId = null;
  workbookXml.replace(/<sheet\b([^>]*)\/?\s*>/g, (_match, attrText) => {
    const attrs = parseAttributes(attrText);
    if (attrs.name === sheetName) relationshipId = attrs["r:id"];
    return _match;
  });
  if (!relationshipId) fail(`worksheet not found: ${sheetName}`);

  let target = null;
  relsXml.replace(/<Relationship\b([^>]*)\/?\s*>/g, (_match, attrText) => {
    const attrs = parseAttributes(attrText);
    if (attrs.Id === relationshipId) target = attrs.Target;
    return _match;
  });
  if (!target) fail(`worksheet relationship not found: ${relationshipId}`);
  const worksheetPath = resolveWorksheetPath(target);
  const worksheetXml = readZipText(zip, worksheetPath);
  if (!worksheetXml) fail(`worksheet part not found: ${worksheetPath}`);

  const sharedStrings = [];
  const sharedXml = readZipText(zip, "xl/sharedStrings.xml");
  if (sharedXml) {
    sharedXml.replace(/<si(?:\s[^>]*)?>([\s\S]*?)<\/si>/g, (_match, body) => {
      sharedStrings.push(textNodes(body));
      return _match;
    });
  }

  const cells = new Map();
  worksheetXml.replace(/<c\b([^>]*)>([\s\S]*?)<\/c>/g, (_match, attrText, body) => {
    const attrs = parseAttributes(attrText);
    if (!attrs.r) return _match;
    let value = "";
    if (attrs.t === "s") {
      const valueMatch = body.match(/<v>([\s\S]*?)<\/v>/);
      value = valueMatch ? sharedStrings[Number(decodeXml(valueMatch[1]))] || "" : "";
    } else if (attrs.t === "inlineStr") {
      value = textNodes(body);
    } else {
      const valueMatch = body.match(/<v>([\s\S]*?)<\/v>/);
      value = valueMatch ? decodeXml(valueMatch[1]) : textNodes(body);
    }
    cells.set(attrs.r.toUpperCase(), value);
    return _match;
  });

  return {
    workbookBytes,
    workbookSha256: sha256Buffer(workbookBytes),
    cells,
  };
}

function cellSort(left, right) {
  const a = left.match(/^([A-Z]+)([0-9]+)$/);
  const b = right.match(/^([A-Z]+)([0-9]+)$/);
  const rowDiff = Number(a[2]) - Number(b[2]);
  return rowDiff || a[1].localeCompare(b[1]);
}

function candidateCellRefs(cells) {
  return Array.from(cells.keys())
    .filter((cell) => {
      const match = cell.match(/^([B-G])([0-9]+)$/);
      return Boolean(match && Number(match[2]) >= 2 && String(cells.get(cell) || "").trim());
    })
    .sort(cellSort);
}

function extractMatchCode(cellValue) {
  const text = String(cellValue || "");
  const start = text.indexOf("CF7ARENA:v1");
  if (start < 0) return null;
  return text.slice(start).split(/\r?\n/, 1)[0].trim();
}

function applyOverride(cell, originalCode, override) {
  if (!override) return { code: originalCode, correction: null, quarantine: null };
  if (override.action === "quarantine") {
    return { code: originalCode, correction: null, quarantine: override.reason };
  }
  if (override.action !== "replace_match_code") fail(`${cell}: unknown workbook override action ${override.action}`);
  if (!originalCode) fail(`${cell}: replacement override has no extracted match code`);
  const first = originalCode.indexOf(override.find);
  const last = originalCode.lastIndexOf(override.find);
  if (first < 0 || first !== last) fail(`${cell}: override find text must match exactly once`);
  const corrected = originalCode.slice(0, first) + override.replace + originalCode.slice(first + override.find.length);
  const correction = {
    correctionId: `correction-${cell.toLowerCase()}-${sha256String(corrected).slice(7, 19)}`,
    cell,
    action: "replace_match_code",
    reason: override.reason,
    beforeSha256: sha256String(originalCode),
    afterSha256: sha256String(corrected),
  };
  return { code: corrected, correction, quarantine: null };
}

function unique(values) {
  return Array.from(new Set(values));
}

function parseDirections(value) {
  if (!value) return null;
  const result = new Map();
  String(value).split(",").map((entry) => entry.trim()).filter(Boolean).forEach((entry) => {
    const match = entry.match(/^([A-Za-z]{1,3}[0-9]+):(original|swapped|both)$/);
    if (!match) fail(`invalid direction selector: ${entry}`);
    const cell = match[1].toUpperCase();
    if (result.has(cell)) fail(`duplicate direction selector: ${cell}`);
    result.set(cell, match[2]);
  });
  return result;
}

function hasRosterParameters(roster) {
  return roster.some((entry) => entry.parameters && Object.keys(entry.parameters).length > 0);
}

function maxRosterLevel(roster) {
  return roster.reduce((max, entry) => Math.max(max, Number(entry.level) || 0), 0);
}

function buildRawSubmission(options) {
  const rawHash = sha256OfValue({ source: options.source, rawValue: options.rawValue });
  const submission = {
    schema: "arena-calibration.raw-submission.v1",
    submissionId: `submission-${rawHash.slice(7, 23)}`,
    ingestedAt: options.generatedAt,
    provider: options.provider,
    source: options.source,
    rawValue: options.rawValue,
    rawSubmissionHash: rawHash,
    extractedMatchCode: options.extractedMatchCode,
    subjectiveTier: options.subjectiveTier || null,
    note: null,
  };
  assertSchemaInstance(submission.schema, submission, `${options.source.cell} raw submission`);
  return submission;
}

function buildCandidate(rawSubmission, correctedCode, correction, timeoutPolicy) {
  const explicitTimeout = /(?:^|;)timeout=[0-9]+(?:;|$)/.test(correctedCode);
  const parsed = ArenaCustomMatchCode.parseMatchCode(correctedCode, {
    unitCatalog: units,
    caseId: "workbook-intake",
  });
  if (parsed.mode !== "mvm") fail(`${rawSubmission.source.cell}: workbook intake requires mode=mvm`);
  const timeoutFrames = explicitTimeout ? parsed.timeoutFrames : timeoutPolicy.frames;
  const parsedForCase = { ...parsed, timeoutFrames };
  const semanticCase = ArenaCustomMatchCode.buildCalibrationCase(parsedForCase, {
    caseId: "candidate-pending",
    repeat: 1,
  });
  semanticCase.timeoutFrames = timeoutFrames;
  const semanticHash = sha256OfValue({
    seed: parsed.seed,
    blueRoster: semanticCase.blueRoster,
    redRoster: semanticCase.redRoster,
    timeoutFrames,
    spawnDistance: semanticCase.spawnDistance,
    blueFormation: semanticCase.blueFormation,
    redFormation: semanticCase.redFormation,
    formationSpacing: semanticCase.formationSpacing,
  });
  const candidateId = `candidate-${semanticHash.slice(7, 23)}`;
  semanticCase.caseId = candidateId;
  const parameterized = hasRosterParameters(semanticCase.blueRoster) || hasRosterParameters(semanticCase.redRoster);
  const maxLevel = Math.max(maxRosterLevel(semanticCase.blueRoster), maxRosterLevel(semanticCase.redRoster));
  const riskTags = [];
  const tags = ["xlsx-intake", `source-${rawSubmission.source.cell.toLowerCase()}`];
  const defaultsApplied = [];
  if (!explicitTimeout) defaultsApplied.push(`timeoutFrames=${timeoutFrames}`);
  if (!/(?:^|;)spawnDistance=/.test(correctedCode)) defaultsApplied.push(`spawnDistance=${semanticCase.spawnDistance}`);
  if (!/(?:^|;)blueFormation=/.test(correctedCode)) defaultsApplied.push(`blueFormation=${semanticCase.blueFormation}`);
  if (!/(?:^|;)redFormation=/.test(correctedCode)) defaultsApplied.push(`redFormation=${semanticCase.redFormation}`);
  if (!/(?:^|;)formationSpacing=/.test(correctedCode)) defaultsApplied.push(`formationSpacing=${semanticCase.formationSpacing}`);
  if (parameterized) {
    tags.push("unit-parameters");
    riskTags.push("unit_payload");
  }
  if (explicitTimeout && timeoutFrames > timeoutPolicy.frames) riskTags.push("long_timeout");
  if (semanticCase.blueFormation !== "line" || semanticCase.redFormation !== "line") riskTags.push("formation");
  if (maxLevel >= 60) riskTags.push("high_level");
  if (correction) riskTags.push("source_semantic_correction");
  semanticCase.tags = unique(tags.concat(riskTags));
  semanticCase.plannerReason = `workbook ${rawSubmission.source.workbookSha256} ${rawSubmission.source.sheetName}!${rawSubmission.source.cell}`;
  const canonicalMatchCode = ArenaCustomMatchCode.serializeMatchCode(parsedForCase);
  const candidate = {
    schema: "arena-calibration.normalized-candidate.v1",
    candidateId,
    candidateHash: semanticHash,
    rawSubmissionId: rawSubmission.submissionId,
    rawSubmissionHash: rawSubmission.rawSubmissionHash,
    source: rawSubmission.source,
    dataQuality: "complete",
    mode: "mvm",
    seed: parsed.seed,
    sourceMatchCode: correctedCode,
    canonicalMatchCode,
    timeout: {
      frames: timeoutFrames,
      source: explicitTimeout ? "match_code_explicit" : "phase_default",
      policy: explicitTimeout ? "explicit" : timeoutPolicy.id,
    },
    caseTemplate: semanticCase,
    riskTags: unique(riskTags),
    correctionReceipts: correction ? [correction] : [],
    weakPrior: rawSubmission.subjectiveTier,
    initialSampleBudget: {
      pilotRuns: 2,
      explorationRuns: 30,
      confirmatoryMinPerSide: 30,
    },
    completionReceipt: {
      defaultsApplied,
      sourceBound: true,
      parametersPreserved: true,
      sideSwapPlanned: true,
    },
  };
  assertSchemaInstance(candidate.schema, candidate, `${rawSubmission.source.cell} normalized candidate`);
  return candidate;
}

function buildException(rawSubmission, reason, generatedAt) {
  const cell = rawSubmission.source.cell;
  const exception = {
    schema: "arena-calibration.exception-inbox-item.v1",
    exceptionId: `exception-${cell.toLowerCase()}-${rawSubmission.rawSubmissionHash.slice(7, 19)}`,
    campaignId: `intake-${rawSubmission.source.workbookSha256.slice(7, 19)}`,
    dedupeKey: `${rawSubmission.source.workbookSha256}|${rawSubmission.source.sheetName}|${cell}`,
    category: "source_ambiguity",
    severity: "blocking_scope",
    status: "open",
    summary: reason,
    affectedScopes: [`cell:${cell}`],
    occurrences: [{
      occurrenceId: `occurrence-${cell.toLowerCase()}-1`,
      observedAt: generatedAt,
      evidenceRef: rawSubmission.rawSubmissionHash,
    }],
    defaultAction: "quarantine",
    reviewDeadline: new Date(Date.parse(generatedAt) + 14 * 24 * 60 * 60 * 1000).toISOString(),
    createdAt: generatedAt,
    updatedAt: generatedAt,
  };
  assertSchemaInstance(exception.schema, exception, `${cell} exception`);
  return exception;
}

function intakeWorkbook(options) {
  const generatedAt = options.generatedAt || new Date().toISOString();
  const timeoutPolicy = TIMEOUT_POLICIES[options.phase];
  if (!timeoutPolicy) fail(`phase must be one of ${Object.keys(TIMEOUT_POLICIES).join(", ")}`);
  const workbook = readWorkbookCells(options.workbookPath, options.sheetName);
  const workbookName = path.basename(options.workbookPath);
  const overrideDocument = options.overridesPath
    ? JSON.parse(fs.readFileSync(options.overridesPath, "utf8"))
    : { workbookSha256: workbook.workbookSha256, sheetName: options.sheetName, overrides: {} };
  if (overrideDocument.workbookSha256 !== workbook.workbookSha256) {
    fail(`workbook hash does not match overrides: expected ${overrideDocument.workbookSha256}, got ${workbook.workbookSha256}`);
  }
  if (overrideDocument.sheetName !== options.sheetName) fail("override sheetName does not match intake sheetName");

  const rawSubmissions = [];
  const candidates = [];
  const corrections = [];
  const quarantines = [];
  const exceptions = [];
  const refs = candidateCellRefs(workbook.cells);
  refs.forEach((cell) => {
    const rawValue = String(workbook.cells.get(cell) || "");
    const row = cell.match(/[0-9]+$/)[0];
    const source = {
      kind: "xlsx_cell",
      workbookSha256: workbook.workbookSha256,
      workbookName,
      sheetName: options.sheetName,
      cell,
      cellValueSha256: sha256String(rawValue),
    };
    const extracted = extractMatchCode(rawValue);
    const rawSubmission = buildRawSubmission({
      source,
      rawValue,
      extractedMatchCode: extracted,
      subjectiveTier: workbook.cells.get(`A${row}`) || null,
      provider: options.provider,
      generatedAt,
    });
    rawSubmissions.push(rawSubmission);
    const applied = applyOverride(cell, extracted, (overrideDocument.overrides || {})[cell]);
    if (applied.correction) corrections.push(applied.correction);
    if (applied.quarantine || !applied.code) {
      const reason = applied.quarantine || "单元格没有可执行 CF7ARENA:v1 代码";
      quarantines.push({ cell, rawSubmissionId: rawSubmission.submissionId, reason });
      exceptions.push(buildException(rawSubmission, reason, generatedAt));
      return;
    }
    try {
      candidates.push(buildCandidate(rawSubmission, applied.code, applied.correction, timeoutPolicy));
    } catch (error) {
      const reason = `match code normalization failed: ${error.message}`;
      quarantines.push({ cell, rawSubmissionId: rawSubmission.submissionId, reason });
      exceptions.push(buildException(rawSubmission, reason, generatedAt));
    }
  });

  const directionMap = options.directions || null;
  const selectedSet = new Set(directionMap ? Array.from(directionMap.keys()) : (options.cells || []));
  if (selectedSet.size > 0) {
    const unknown = Array.from(selectedSet).filter((cell) => !refs.includes(cell));
    if (unknown.length > 0) fail(`selected cells are not populated candidate cells: ${unknown.join(", ")}`);
  }
  const selected = candidates.filter((candidate) => selectedSet.size === 0 || selectedSet.has(candidate.source.cell));
  if (selectedSet.size > 0 && selected.length !== selectedSet.size) {
    const missing = Array.from(selectedSet).filter((cell) => !selected.some((candidate) => candidate.source.cell === cell));
    fail(`selected cells were quarantined or invalid: ${missing.join(", ")}`);
  }

  let manifest = null;
  if (selected.length > 0) {
    const cases = [];
    selected.forEach((candidate) => {
      const original = JSON.parse(JSON.stringify(candidate.caseTemplate));
      original.repeat = options.repeat;
      const direction = directionMap && directionMap.get(candidate.source.cell);
      const includeOriginal = !direction || direction === "original" || direction === "both";
      const includeSwapped = direction
        ? direction === "swapped" || direction === "both"
        : options.sideSwap;
      if (includeOriginal) cases.push(original);
      if (includeSwapped) {
        const swapped = JSON.parse(JSON.stringify(original));
        swapped.caseId = `${original.caseId}-side-swap`;
        swapped.blueRoster = original.redRoster;
        swapped.redRoster = original.blueRoster;
        swapped.blueFormation = original.redFormation;
        swapped.redFormation = original.blueFormation;
        swapped.tags = unique(original.tags.concat("side-swap"));
        swapped.plannerReason = `${original.plannerReason}; deterministic side swap`;
        cases.push(swapped);
      }
    });
    manifest = normalizeManifest({
      schema: "arena-calibration.case-manifest.v1",
      batchId: options.batchId,
      createdAt: generatedAt,
      buildCommit: options.buildCommit,
      planner: {
        name: "xlsx-hash-cell-intake",
        version: 1,
        workbookSha256: workbook.workbookSha256,
        sheetName: options.sheetName,
        phase: options.phase,
      },
      arenaMode: "calibration",
      repeat: options.repeat,
      timeoutFrames: timeoutPolicy.frames,
      blueBench: null,
      cases,
    });
  }

  const receipt = {
    schema: "arena-calibration.workbook-intake.v1",
    generatedAt,
    workbookSha256: workbook.workbookSha256,
    workbookName,
    sheetName: options.sheetName,
    timeoutPolicy: timeoutPolicy.id,
    counts: {
      populatedCells: refs.length,
      rawSubmissions: rawSubmissions.length,
      normalizedCandidates: candidates.length,
      corrected: corrections.length,
      quarantined: quarantines.length,
      selectedCases: manifest ? manifest.cases.length : 0,
      plannedRuns: manifest ? manifest.cases.reduce((sum, testCase) => sum + testCase.repeat, 0) : 0,
    },
    corrections,
    quarantines,
    rawSubmissionIds: rawSubmissions.map((entry) => entry.submissionId),
    candidateIds: candidates.map((entry) => entry.candidateId),
    exceptionIds: exceptions.map((entry) => entry.exceptionId),
    selectedCells: selected.map((candidate) => candidate.source.cell),
    manifestHash: manifest ? manifest.manifestHash : null,
  };
  assertSchemaInstance(receipt.schema, receipt, "workbook intake receipt");
  return { rawSubmissions, candidates, exceptions, receipt, manifest };
}

function parseArgs(argv) {
  const args = {
    workbookPath: null,
    sheetName: DEFAULT_SHEET,
    overridesPath: DEFAULT_OVERRIDES,
    outputDir: null,
    phase: "exploration",
    provider: "test-group",
    cells: [],
    directions: null,
    sideSwap: false,
    repeat: 1,
    batchId: null,
    buildCommit: null,
    check: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--workbook") args.workbookPath = argv[++index];
    else if (token === "--sheet") args.sheetName = argv[++index];
    else if (token === "--overrides") args.overridesPath = argv[++index];
    else if (token === "--output-dir") args.outputDir = argv[++index];
    else if (token === "--phase") args.phase = argv[++index];
    else if (token === "--provider") args.provider = argv[++index];
    else if (token === "--cells") args.cells = String(argv[++index] || "").split(",").map((value) => value.trim().toUpperCase()).filter(Boolean);
    else if (token === "--directions") args.directions = parseDirections(argv[++index]);
    else if (token === "--side-swap") args.sideSwap = true;
    else if (token === "--repeat") args.repeat = Number(argv[++index]);
    else if (token === "--batch-id") args.batchId = argv[++index];
    else if (token === "--build-commit") args.buildCommit = argv[++index];
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail(`unknown argument: ${token}`);
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/intake-workbook.js [options]

Options:
  --workbook <xlsx>       Source workbook.
  --sheet <name>          Source sheet. Default: 斗兽标定组合.
  --overrides <json>      Hash-bound cell corrections/quarantines.
  --output-dir <dir>      Write intake artifacts and case_manifest.json.
  --phase <name>          smoke | exploration | confirmatory.
  --cells <A1,B2>         Select normalized cells for the manifest.
  --directions <spec>     Per-cell original/swapped/both selectors; supersedes --cells/--side-swap.
  --side-swap             Add deterministic side-swapped cases.
  --repeat <n>            Repeats per generated case.
  --batch-id <id>         Required when generating a manifest.
  --build-commit <commit> Source commit recorded in the manifest.
  --check                  Run a pure helper contract check.
`);
}

function runCheck() {
  const raw = "测试说明\nCF7ARENA:v1;mode=mvm;seed=1;blue=u44@30x1;red=u11@30x1";
  if (extractMatchCode(raw) !== raw.split("\n")[1]) fail("match code extraction check failed");
  const changed = applyOverride("C9", extractMatchCode(raw), {
    action: "replace_match_code",
    find: "seed=1",
    replace: "seed=2",
    reason: "fixture",
  });
  if (!changed.code.includes("seed=2") || !changed.correction) fail("override check failed");
  console.log(JSON.stringify({ ok: true, timeoutPolicies: TIMEOUT_POLICIES, workbookWrite: false }, null, 2));
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  if (args.check) return runCheck();
  if (!args.workbookPath) fail("--workbook is required");
  if (!args.outputDir) fail("--output-dir is required");
  if (!Number.isInteger(args.repeat) || args.repeat < 1) fail("--repeat must be a positive integer");
  if (!args.batchId) fail("--batch-id is required");
  const root = path.resolve(__dirname, "../..");
  const result = intakeWorkbook({
    ...args,
    workbookPath: path.resolve(args.workbookPath),
    overridesPath: path.resolve(args.overridesPath),
    outputDir: path.resolve(root, args.outputDir),
    buildCommit: args.buildCommit || require("child_process").execFileSync("git", ["rev-parse", "--short=12", "HEAD"], { cwd: root, encoding: "utf8" }).trim(),
  });
  fs.mkdirSync(path.resolve(root, args.outputDir), { recursive: true });
  writeJsonFile(path.join(root, args.outputDir, "raw-submissions.json"), result.rawSubmissions);
  writeJsonFile(path.join(root, args.outputDir, "normalized-candidates.json"), result.candidates);
  writeJsonFile(path.join(root, args.outputDir, "exceptions.json"), result.exceptions);
  writeJsonFile(path.join(root, args.outputDir, "intake-receipt.json"), result.receipt);
  if (result.manifest) writeJsonFile(path.join(root, args.outputDir, "case_manifest.json"), result.manifest);
  console.log(JSON.stringify({
    ok: true,
    outputDir: path.relative(root, path.resolve(root, args.outputDir)).replace(/\\/g, "/"),
    workbookSha256: result.receipt.workbookSha256,
    counts: result.receipt.counts,
    manifestHash: result.receipt.manifestHash,
  }, null, 2));
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(error.message);
    process.exit(error.isUsageError ? 2 : 1);
  }
}

module.exports = {
  TIMEOUT_POLICIES,
  applyOverride,
  candidateCellRefs,
  extractMatchCode,
  intakeWorkbook,
  readWorkbookCells,
  sha256String,
};
