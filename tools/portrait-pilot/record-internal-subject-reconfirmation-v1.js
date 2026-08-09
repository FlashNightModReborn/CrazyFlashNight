#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const reviewBuild = require("./build-internal-subject-review-v1");
const decisionVerifier = require("./verify-internal-subject-review-decisions-v1");

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function artifact(filePath) {
  const body = fs.readFileSync(filePath);
  return {
    path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
    sha256: sha256(body),
    bytes: body.length,
  };
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableValue(value[key])]));
  }
  return value;
}

function parseArgs(argv) {
  const options = { batch: null, reviewKey: null, candidateId: null, note: "", apply: false, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    if (["--batch", "--review-key", "--candidate-id", "--note"].includes(key)) {
      const field = { "--batch": "batch", "--review-key": "reviewKey", "--candidate-id": "candidateId", "--note": "note" }[key];
      options[field] = argv[index + 1];
      index += 1;
    } else if (key === "--apply") {
      options.apply = true;
    } else if (key === "--check") {
      options.check = true;
    } else if (key === "--help") {
      options.help = true;
    } else {
      throw new Error(`未知参数：${key}`);
    }
  }
  return options;
}

function load(options) {
  if (!options.batch || !options.reviewKey || !options.candidateId) {
    throw new Error("必须提供 --batch、--review-key 与 --candidate-id");
  }
  if (options.apply === options.check) throw new Error("必须且只能选择 --check 或 --apply");
  if (typeof options.note !== "string" || options.note.length > 500) throw new Error("--note 必须不超过 500 字符");
  const loaded = reviewBuild.loadBatch(options.batch);
  const reviewPath = path.join(loaded.batchRoot, "internal-subject-review-data.json");
  const decisionsPath = path.join(loaded.batchRoot, "internal-subject-human-decisions.json");
  const dataset = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
  reviewBuild.verifyReviewDataset(dataset);
  const decisions = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  decisionVerifier.validateDecisions(dataset, decisions);
  const item = dataset.items.find((entry) => entry.reviewKey === options.reviewKey);
  const prior = decisions.decisions.find((entry) => entry.reviewKey === options.reviewKey);
  const candidate = item?.candidates?.find((entry) => entry.candidateId === options.candidateId);
  if (!item || !prior || !candidate) throw new Error("复核目标或候选不在当前白名单");
  return { ...loaded, reviewPath, decisionsPath, dataset, decisions, item, prior, candidate };
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write("用法：node tools/portrait-pilot/record-internal-subject-reconfirmation-v1.js --batch <batch> --review-key <key> --candidate-id <id> [--note <text>] (--check|--apply)\n");
    return;
  }
  const loaded = load(options);
  if (options.check) {
    process.stdout.write(`${JSON.stringify({
      status: "internal_subject_reconfirmation_write_preflight_verified",
      reviewKey: options.reviewKey,
      priorDecision: loaded.prior,
      requestedCandidateId: options.candidateId,
      requestedCandidate: {
        spriteId: loaded.candidate.spriteId,
        frame: loaded.candidate.frame,
        artifact: loaded.candidate.artifact,
      },
      untouchedDecisionCount: loaded.decisions.decisions.length - 1,
    })}\n`);
    return;
  }

  const before = artifact(loaded.decisionsPath);
  const recordedAt = new Date().toISOString();
  const updated = {
    ...loaded.decisions,
    reviewedAt: recordedAt,
    decisions: loaded.decisions.decisions.map((entry) => entry.reviewKey === options.reviewKey ? {
      reviewKey: entry.reviewKey,
      decision: "select",
      candidateId: options.candidateId,
      note: options.note,
    } : entry),
  };
  decisionVerifier.validateDecisions(loaded.dataset, updated);
  const body = `${JSON.stringify(updated, null, 2)}\n`;
  const archiveRoot = path.join(loaded.batchRoot, "human-exports");
  fs.mkdirSync(archiveRoot, { recursive: true });
  const stamp = recordedAt.replaceAll(":", "").replaceAll(".", "");
  const archivePath = path.join(archiveRoot, `internal-subject-human-decisions-reconfirmed-${stamp}.json`);
  fs.writeFileSync(archivePath, body, { encoding: "utf8", flag: "wx" });
  fs.writeFileSync(loaded.decisionsPath, body, { encoding: "utf8", flag: "w" });
  const persisted = JSON.parse(fs.readFileSync(loaded.decisionsPath, "utf8"));
  decisionVerifier.validateDecisions(loaded.dataset, persisted);
  const after = artifact(loaded.decisionsPath);
  const archive = artifact(archivePath);
  if (after.sha256 !== archive.sha256 || after.bytes !== archive.bytes) throw new Error("canonical 与版本归档不一致");

  const receipt = {
    schema: "cf7.enemy-portrait-internal-subject-reconfirmation-receipt.v1",
    status: "human_subject_reconfirmation_recorded",
    recordedAt,
    batchId: loaded.dataset.batchId,
    reviewDigest: loaded.dataset.reviewDigest,
    reviewKey: options.reviewKey,
    authority: "explicit_maintainer_instruction_in_current_codex_task",
    priorDecision: loaded.prior,
    recordedDecision: persisted.decisions.find((entry) => entry.reviewKey === options.reviewKey),
    selectedCandidate: {
      candidateId: loaded.candidate.candidateId,
      spriteId: loaded.candidate.spriteId,
      frame: loaded.candidate.frame,
      artifact: loaded.candidate.artifact,
    },
    input: {
      reviewData: artifact(loaded.reviewPath),
      decisionsBefore: before,
      controller: artifact(__filename),
    },
    output: {
      canonicalDecisions: after,
      archivedDecisions: archive,
      untouchedDecisionCount: persisted.decisions.length - 1,
    },
    gates: {
      candidateWhitelistClosed: true,
      fullDecisionSetRevalidated: true,
      canonicalMatchesArchive: true,
      modelDidNotAutonomouslyOverrideHuman: true,
      productionWrites: false,
    },
  };
  receipt.receiptDigest = sha256(Buffer.from(JSON.stringify(stableValue(receipt)), "utf8"));
  const receiptPath = path.join(archiveRoot, `internal-subject-reconfirmation-receipt-${stamp}.json`);
  fs.writeFileSync(receiptPath, `${JSON.stringify(receipt, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({
    status: receipt.status,
    reviewKey: receipt.reviewKey,
    candidateId: receipt.recordedDecision.candidateId,
    canonical: after,
    archive,
    receipt: artifact(receiptPath),
    receiptDigest: receipt.receiptDigest,
    untouchedDecisionCount: receipt.output.untouchedDecisionCount,
    productionWrites: false,
  })}\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
  process.exitCode = 1;
}
