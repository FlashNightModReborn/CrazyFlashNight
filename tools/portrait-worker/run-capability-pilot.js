#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const {
  CodexCliLunaWorker,
  WorkerError,
  publicError,
  sha256Bytes,
  stableStringify,
} = require("./lib/codex-cli-luna-worker");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const FIXTURE_PATH = path.join(__dirname, "fixtures", "capability-tasks.json");
const OUTPUT_SCHEMA_PATH = path.join(__dirname, "schemas", "capability-result.schema.json");
const DEFAULT_TIMEOUT_MS = 180_000;
const CONTROLLER_SOURCE_PATHS = [
  __filename,
  path.join(__dirname, "lib", "codex-cli-luna-worker.js"),
];

function controllerEvidence() {
  const files = CONTROLLER_SOURCE_PATHS.map((filePath) => {
    const bytes = fs.readFileSync(filePath);
    return {
      path: path.relative(REPO_ROOT, filePath).replaceAll("\\", "/"),
      bytes: bytes.length,
      sha256: sha256Bytes(bytes),
    };
  });
  return {
    version: "portrait-worker-p1",
    nodeVersion: process.version,
    platform: process.platform,
    arch: process.arch,
    files,
    sourceClosureDigest: sha256Bytes(stableStringify(files)),
  };
}

function usage() {
  return [
    "用法：node tools/portrait-worker/run-capability-pilot.js --codex-exe <绝对路径> [选项]",
    "",
    "选项：",
    "  --codex-exe <path>   显式 Codex CLI 路径；也可用 CF7_PORTRAIT_CODEX_EXE",
    "  --output <path>      不可覆盖的 report.json 路径",
    "  --timeout-ms <ms>    每个独立进程的超时，默认 180000",
    "  --probe-only         只验证 CLI 版本、hash 与必需参数",
    "  --help               显示帮助",
  ].join("\n");
}

function parseArgs(argv) {
  const options = {
    codexExe: process.env.CF7_PORTRAIT_CODEX_EXE || null,
    output: null,
    timeoutMs: DEFAULT_TIMEOUT_MS,
    probeOnly: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--help") {
      options.help = true;
    } else if (argument === "--probe-only") {
      options.probeOnly = true;
    } else if (argument === "--codex-exe" || argument === "--output" || argument === "--timeout-ms") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new WorkerError("ARGUMENT_MISSING", "arguments", `${argument} 缺少值`, {});
      }
      index += 1;
      if (argument === "--codex-exe") {
        options.codexExe = value;
      } else if (argument === "--output") {
        options.output = value;
      } else {
        options.timeoutMs = Number(value);
      }
    } else {
      throw new WorkerError("ARGUMENT_UNKNOWN", "arguments", `未知参数：${argument}`, {});
    }
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 5_000 || options.timeoutMs > 600_000) {
    throw new WorkerError("TIMEOUT_INVALID", "arguments", "timeout 必须是 5000–600000 的整数毫秒", {
      timeoutMs: options.timeoutMs,
    });
  }
  return options;
}

function defaultReportPath() {
  const timestamp = new Date().toISOString().replace(/[-:.]/gu, "").replace("Z", "Z");
  return path.join(REPO_ROOT, "tmp", "portrait-worker", `capability-pilot-${timestamp}`, "report.json");
}

function reserveOutput(reportPath) {
  const absoluteReportPath = path.resolve(REPO_ROOT, reportPath);
  const outputDirectory = path.dirname(absoluteReportPath);
  const artifactsDirectory = path.join(outputDirectory, "artifacts");
  if (fs.existsSync(absoluteReportPath) || fs.existsSync(artifactsDirectory)) {
    throw new WorkerError("OUTPUT_EXISTS", "output", "capability 证据路径已存在，拒绝覆盖", {
      reportPath: absoluteReportPath,
    });
  }
  fs.mkdirSync(artifactsDirectory, { recursive: true });
  return { absoluteReportPath, outputDirectory, artifactsDirectory };
}

function writeNewFile(filePath, content) {
  fs.writeFileSync(filePath, content, { encoding: "utf8", flag: "wx" });
}

function writeReportAtomic(reportPath, value) {
  const temporaryPath = `${reportPath}.${process.pid}.tmp`;
  writeNewFile(temporaryPath, `${JSON.stringify(value, null, 2)}\n`);
  fs.renameSync(temporaryPath, reportPath);
}

function persistRunArtifacts(runResult, artifactsDirectory) {
  for (let index = 0; index < runResult.run.attempts.length; index += 1) {
    const attempt = runResult.run.attempts[index];
    const artifact = runResult.artifacts[index];
    const baseName = `${runResult.run.role}-attempt-${attempt.attemptNumber}`;
    const stdoutName = `${baseName}.stdout.jsonl`;
    const stderrName = `${baseName}.stderr.log`;
    writeNewFile(path.join(artifactsDirectory, stdoutName), artifact.stdout);
    writeNewFile(path.join(artifactsDirectory, stderrName), artifact.stderr);
    attempt.stdoutArtifact = `artifacts/${stdoutName}`;
    attempt.stderrArtifact = `artifacts/${stderrName}`;
  }
}

function acceptedAttempt(run) {
  return run.attempts.find((attempt) => attempt.attemptNumber === run.acceptedAttempt);
}

async function runPilot(options, output) {
  if (!options.codexExe) {
    throw new WorkerError(
      "CLI_PATH_REQUIRED",
      "arguments",
      "必须通过 --codex-exe 或 CF7_PORTRAIT_CODEX_EXE 显式提供 Codex CLI",
      {},
    );
  }
  const worker = new CodexCliLunaWorker({ executablePath: path.resolve(options.codexExe) });
  const probe = await worker.probe(Math.min(options.timeoutMs, 30_000));
  if (options.probeOnly) {
    return {
      schema: "cf7.portrait-worker-capability-report.v1",
      status: "probe_verified",
      productionReady: false,
      scope: "cli_static_probe_only",
      generatedAt: new Date().toISOString(),
      controller: controllerEvidence(),
      probe,
      runs: [],
    };
  }

  const fixture = JSON.parse(fs.readFileSync(FIXTURE_PATH, "utf8"));
  const imagePath = path.resolve(REPO_ROOT, fixture.imageProbe.relativePath);
  const isolatedCwd = path.join(output.outputDirectory, "isolated-cwd");
  fs.mkdirSync(isolatedCwd, { recursive: true });

  const proposal = await worker.runWithRetry({
    fixture,
    imagePath,
    outputSchemaPath: OUTPUT_SCHEMA_PATH,
    runRole: "proposal",
    cwd: isolatedCwd,
    timeoutMs: options.timeoutMs,
    maxRetries: 1,
  });
  persistRunArtifacts(proposal, output.artifactsDirectory);

  const independentReview = await worker.runWithRetry({
    fixture,
    imagePath,
    outputSchemaPath: OUTPUT_SCHEMA_PATH,
    runRole: "independent_review",
    cwd: isolatedCwd,
    timeoutMs: options.timeoutMs,
    maxRetries: 1,
  });
  persistRunArtifacts(independentReview, output.artifactsDirectory);

  const proposalAttempt = acceptedAttempt(proposal.run);
  const reviewAttempt = acceptedAttempt(independentReview.run);
  if (!proposalAttempt || !reviewAttempt || proposalAttempt.pid === reviewAttempt.pid) {
    throw new WorkerError("RUN_INDEPENDENCE_FAILED", "closure", "A/B 必须是两个不同进程", {
      proposalPid: proposalAttempt?.pid || null,
      reviewPid: reviewAttempt?.pid || null,
    });
  }
  if (proposalAttempt.promptDigest === reviewAttempt.promptDigest) {
    throw new WorkerError("RUN_INDEPENDENCE_FAILED", "closure", "A/B 角色 prompt digest 不得相同", {});
  }
  const proposalSemantic = {
    imageProbe: proposal.run.result.imageProbe,
    results: proposal.run.result.results,
  };
  const reviewSemantic = {
    imageProbe: independentReview.run.result.imageProbe,
    results: independentReview.run.result.results,
  };
  if (stableStringify(proposalSemantic) !== stableStringify(reviewSemantic)) {
    throw new WorkerError("RUN_DISAGREEMENT", "closure", "A/B 对固定 fixture 的结果不一致", {});
  }

  return {
    schema: "cf7.portrait-worker-capability-report.v1",
    status: "capability_verified",
    productionReady: false,
    scope: "fixed_fixture_transport_and_closure_only",
    generatedAt: new Date().toISOString(),
    controller: controllerEvidence(),
    probe,
    fixture: {
      path: path.relative(REPO_ROOT, FIXTURE_PATH).replaceAll("\\", "/"),
      sha256: sha256Bytes(fs.readFileSync(FIXTURE_PATH)),
      taskCount: fixture.tasks.length,
      imagePath: fixture.imageProbe.relativePath,
      imageSha256: sha256Bytes(fs.readFileSync(imagePath)),
      outputSchemaPath: path.relative(REPO_ROOT, OUTPUT_SCHEMA_PATH).replaceAll("\\", "/"),
      outputSchemaSha256: sha256Bytes(fs.readFileSync(OUTPUT_SCHEMA_PATH)),
    },
    runs: [proposal.run, independentReview.run],
    gates: {
      separateProcessIds: true,
      distinctRolePromptDigests: true,
      exactControllerClosure: true,
      semanticAgreement: true,
      orphanProcessGate: true,
    },
    exclusions: [
      "FFDec source extraction",
      "production portrait generation",
      "human art acceptance",
      "candidate promotion",
      "consumer migration",
    ],
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  const output = reserveOutput(options.output || defaultReportPath());
  let report;
  try {
    report = await runPilot(options, output);
  } catch (error) {
    const normalized = publicError(error);
    report = {
      schema: "cf7.portrait-worker-capability-report.v1",
      status: "failed",
      productionReady: false,
      scope: options.probeOnly ? "cli_static_probe_only" : "fixed_fixture_transport_and_closure_only",
      generatedAt: new Date().toISOString(),
      controller: controllerEvidence(),
      error: normalized,
    };
    if (error instanceof WorkerError && Array.isArray(error.details.artifacts)) {
      const failedRun = {
        run: {
          role: error.details.role || "unknown",
          attempts: error.details.attempts || [],
        },
        artifacts: error.details.artifacts,
      };
      persistRunArtifacts(failedRun, output.artifactsDirectory);
      delete report.error.details.artifacts;
    }
    writeReportAtomic(output.absoluteReportPath, report);
    throw new WorkerError(normalized.code, normalized.phase, normalized.message, {
      ...normalized.details,
      reportPath: output.absoluteReportPath,
    });
  }
  writeReportAtomic(output.absoluteReportPath, report);
  process.stdout.write(
    `${JSON.stringify({ status: report.status, reportPath: output.absoluteReportPath })}\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`${JSON.stringify(publicError(error))}\n`);
  process.exitCode = 1;
});
