#!/usr/bin/env node
"use strict";

const path = require("path");
const { atomicWriteJson, readJsonFile } = require("./common");
const { finalizeDeferredBundleVerification, prepareDeferredBundleVerification,
  verifyBundle } = require("./evidence-verifier");

function usage(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = { bundle: null, receipt: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else if (["--bundle", "--receipt"].includes(token)) {
      if (!argv[index + 1] || argv[index + 1].startsWith("--")) usage(token + " requires a value");
      args[token.slice(2)] = argv[++index];
    } else usage("unknown argument: " + token);
  }
  if (args.check && argv.length !== 1) usage("--check must be used alone");
  return args;
}

function runCheck(options) {
  const result = require("./self-test").runSelfTests();
  if (!options || options.emit !== false) console.log(JSON.stringify({ status: "OFFLINE_VERIFIED",
    liveStatus: "LIVE_BLOCKED", deployment: "NOT_DEPLOYED", checks: result.passed,
    positives: result.positives, negatives: result.negatives }));
  return result;
}

function persistReceipt(receiptPath, receipt) {
  atomicWriteJson(receiptPath, receipt);
  return receiptPath;
}

function prepare(argv) {
  const args = parseArgs(argv);
  if (!args.bundle || args.help || args.check) usage("deferred verification requires --bundle");
  if (!path.isAbsolute(args.bundle)) usage("--bundle must be an absolute path");
  const bundlePath = path.resolve(args.bundle);
  const bundle = readJsonFile(bundlePath, "bundle").value;
  const receiptPath = args.receipt ? path.resolve(args.receipt)
    : path.join(path.dirname(bundlePath), "verified-receipt.json");
  return { bundlePath, bundle, receiptPath,
    evidence: prepareDeferredBundleVerification(bundle) };
}

function finalize(prepared, admission) {
  const receipt = finalizeDeferredBundleVerification(prepared.bundle,
    prepared.evidence, admission);
  persistReceipt(prepared.receiptPath, receipt);
  return { receipt, receiptPath: prepared.receiptPath };
}

function main(argv, options) {
  const settings = options || {};
  const args = parseArgs(argv);
  if (args.help) {
    if (settings.emit !== false) console.log(JSON.stringify({ status: "HELP", usage: [
      "Fail-closed Equipment Tuning two-process live journey verifier",
      "",
      "Usage:",
      "  node tools/workbench-live-e2e/equipment/bootstrap.js --check",
      "  node tools/workbench-live-e2e/equipment/bootstrap.js --verify-bundle <journey-bundle.json>",
      "    [--receipt <receipt.json>]",
      "",
      "Verification is read-only with respect to Launcher, Flash, candidate bytes and saves.",
      "The default receipt path is the bundle's owned run directory.",
    ].join("\n") }));
    return null;
  }
  if (args.check) return runCheck(settings);
  if (!args.bundle) usage("--bundle is required");
  const bundlePath = path.resolve(args.bundle);
  const bundle = readJsonFile(bundlePath, "bundle").value;
  const receiptPath = args.receipt ? path.resolve(args.receipt)
    : path.join(path.dirname(bundlePath), "verified-receipt.json");
  const receipt = verifyBundle(bundle);
  if (settings.persist !== false) persistReceipt(receiptPath, receipt);
  if (settings.emit !== false) console.log(JSON.stringify({ status: receipt.status,
    liveStatus: receipt.liveStatus, deployment: receipt.deployment,
    receiptPath, receiptSha256: receipt.receiptSha256 }));
  return settings.returnEnvelope === true ? { receipt, receiptPath } : receipt;
}

module.exports = { finalize, main, parseArgs, persistReceipt, prepare, runCheck };

if (require.main === module) {
  console.error("verify-live-journey.js is NOT_ADMITTED directly; use equipment/bootstrap.js --verify-bundle");
  process.exitCode = 2;
}
