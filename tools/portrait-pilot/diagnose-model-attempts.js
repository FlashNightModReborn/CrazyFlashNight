#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const reviewBuild = require("./build-review");
const {
  createPrompt,
  loadManifest,
  repairFeedbackFor,
  validateResult,
} = require("./run-visual-pilot");
const {
  extractFinalAgentMessage,
  parseJsonl,
  publicError,
} = require("../portrait-worker/lib/codex-cli-luna-worker");

const ROOT = path.resolve(__dirname, "..", "..");
const PORTRAIT_TMP = path.join(ROOT, "tmp", "portrait-pilot");
const ROLES = ["proposal", "independent_review"];

function fail(message) {
  throw new reviewBuild.ReviewError(message);
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function artifact(filePath) {
  return {
    path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
    bytes: fs.statSync(filePath).size,
    sha256: reviewBuild.sha256File(filePath),
  };
}

function parseArgs(argv) {
  const options = { manifest: null, output: null, transportRepair: false };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--manifest" || argument === "--output") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) fail(`${argument} 缺少值`);
      options[argument === "--manifest" ? "manifest" : "output"] = value;
      index += 1;
    } else if (argument === "--historical-transport-repair") {
      options.transportRepair = true;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      fail(`未知参数：${argument}`);
    }
  }
  return options;
}

function resolveOutput(value) {
  const outputPath = path.resolve(ROOT, value);
  const relative = path.relative(PORTRAIT_TMP, outputPath);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) fail("output 必须位于 tmp/portrait-pilot 下");
  return outputPath;
}

function runtimeTransportError(stdout) {
  if (
    stdout.includes('"type":"item.completed"') &&
    stdout.includes('"type":"error"') &&
    !stdout.includes('"type":"turn.completed"')
  ) {
    return { code: "PROCESS_TIMEOUT", phase: "transport", message: "Luna 视觉进程超时" };
  }
  return null;
}

function diagnoseAttempt(filePath, prompt, context) {
  const stdout = fs.readFileSync(filePath, "utf8");
  const transport = runtimeTransportError(stdout);
  if (transport) return { status: "rejected", error: transport };
  try {
    const finalMessage = extractFinalAgentMessage(parseJsonl(stdout));
    const parsed = JSON.parse(finalMessage.text);
    const result = validateResult(parsed, {
      manifest: context.manifest,
      reviewItems: context.reviewItems,
      promptDigest: prompt.promptDigest,
      runRole: context.role,
      selectionMode: context.selectionMode,
      resultSchema: context.resultSchema,
    });
    return {
      status: "accepted",
      threadId: finalMessage.threadId,
      resultSha256: sha256Bytes(reviewBuild.stableStringify(result)),
      result,
    };
  } catch (error) {
    return { status: "rejected", error: publicError(error) };
  }
}

function buildReport(options) {
  const loaded = loadManifest(options.manifest);
  const artifactsDirectory = path.join(path.dirname(loaded.manifestPath), "model-artifacts");
  if (!fs.existsSync(artifactsDirectory)) fail("model-artifacts 缺失");
  const runs = [];
  for (const batch of loaded.modelBatches) {
    for (const role of ROLES) {
      let repairFeedback = null;
      const attempts = [];
      let acceptedResult = null;
      for (let attemptNumber = 1; attemptNumber <= 3; attemptNumber += 1) {
        const base = `${role}-${batch.modelBatchId}-attempt-${attemptNumber}`;
        const stdoutPath = path.join(artifactsDirectory, `${base}.stdout.jsonl`);
        const stderrPath = path.join(artifactsDirectory, `${base}.stderr.log`);
        if (!fs.existsSync(stdoutPath) || !fs.existsSync(stderrPath)) break;
        const prompt = createPrompt(
          loaded.manifest,
          batch.reviewItems,
          role,
          batch.modelBatchId,
          batch.contactSheet,
          batch.imageInputs,
          repairFeedback,
        );
        const diagnosed = diagnoseAttempt(stdoutPath, prompt, {
          ...loaded,
          ...batch,
          role,
        });
        attempts.push({
          attemptNumber,
          promptDigest: prompt.promptDigest,
          stdout: artifact(stdoutPath),
          stderr: artifact(stderrPath),
          status: diagnosed.status,
          error: diagnosed.error || null,
          threadId: diagnosed.threadId || null,
          resultSha256: diagnosed.resultSha256 || null,
        });
        if (diagnosed.status === "accepted") {
          acceptedResult = diagnosed.result;
          break;
        }
        repairFeedback = diagnosed.error.phase === "closure" || options.transportRepair
          ? repairFeedbackFor(diagnosed.error)
          : null;
      }
      runs.push({
        role,
        modelBatchId: batch.modelBatchId,
        status: acceptedResult ? "accepted" : "exhausted",
        attempts,
        result: acceptedResult,
      });
    }
  }
  const report = {
    schema: "cf7.portrait-pilot-model-attempt-diagnostic.v1",
    status: "model_attempts_diagnosed",
    productionReady: false,
    generatedAt: new Date().toISOString(),
    input: {
      manifest: artifact(loaded.manifestPath),
      manifestDigest: loaded.manifest.manifestDigest,
      historicalTransportRepair: options.transportRepair,
    },
    counts: {
      expectedRuns: runs.length,
      acceptedRuns: runs.filter((run) => run.status === "accepted").length,
      exhaustedRuns: runs.filter((run) => run.status === "exhausted").length,
      transportRejections: runs.flatMap((run) => run.attempts).filter((attempt) => attempt.error?.phase === "transport").length,
      closureRejections: runs.flatMap((run) => run.attempts).filter((attempt) => attempt.error?.phase === "closure").length,
    },
    runs,
    gates: {
      artifactHashesVerified: true,
      acceptedResultsRevalidated: true,
      diagnosticOnly: true,
      humanReviewOpened: false,
      productionWrites: false,
    },
  };
  report.reportDigest = sha256Bytes(reviewBuild.stableStringify(report));
  return report;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.manifest || !options.output) {
    process.stdout.write("用法：node tools/portrait-pilot/diagnose-model-attempts.js --manifest <manifest> --output <new.json> [--historical-transport-repair]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  const outputPath = resolveOutput(options.output);
  if (fs.existsSync(outputPath)) fail("output 已存在，禁止覆盖");
  const report = buildReport(options);
  fs.writeFileSync(outputPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({ status: report.status, output: artifact(outputPath), counts: report.counts, reportDigest: report.reportDigest })}\n`);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`${JSON.stringify({ error: error.message })}\n`);
    process.exitCode = 1;
  }
}

module.exports = { buildReport };
