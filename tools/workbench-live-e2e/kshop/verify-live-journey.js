#!/usr/bin/env node
"use strict";

const path = require("path");
const { atomicWriteJson, readJson } = require("./common");
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
    if (token === "--help" || token === "-h") args.help = true;
    else if (token === "--check") args.check = true;
    else if (token === "--bundle" || token === "--receipt") {
      if (index + 1 >= argv.length || argv[index + 1].startsWith("--")) {
        usage(token + " requires a value");
      }
      args[token.slice(2)] = argv[++index];
    } else usage("unknown argument: " + token);
  }
  if (args.check && argv.length !== 1) usage("--check must be used alone");
  return args;
}

function helpText() {
  return [
    "Fail-closed KShop live journey verifier",
    "",
    "Usage:",
    "  node tools/workbench-live-e2e/kshop/bootstrap.js --check",
    "  node tools/workbench-live-e2e/kshop/bootstrap.js --verify-bundle <journey-bundle.json>",
    "    [--receipt <verified-receipt.json>]",
    "",
    "Verification is read-only with respect to Launcher, Flash, saves, and the candidate.",
    "Only the requested receipt file is written. Raw checkout capability tokens are rejected.",
  ].join("\n");
}

function printHelp() {
  console.log(helpText());
}

function runCheck() {
  const { runSelfTests } = require("./self-test");
  return runSelfTests();
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  if (args.check) return runCheck();
  if (!args.bundle) usage("--bundle is required");
  if (!path.isAbsolute(args.bundle)) usage("--bundle must be an absolute path");
  const bundlePath = path.resolve(args.bundle);
  const receiptPath = args.receipt
    ? path.resolve(args.receipt)
    : path.join(path.dirname(bundlePath), "verified-receipt.json");
  const receipt = verifyBundle(readJson(bundlePath, "KShop journey bundle"));
  atomicWriteJson(receiptPath, receipt);
  return { receipt, receiptPath };
}

function prepare(argv) {
  const args = parseArgs(argv);
  if (!args.bundle || args.help || args.check) usage("deferred verification requires --bundle");
  if (!path.isAbsolute(args.bundle)) usage("--bundle must be an absolute path");
  const bundlePath = path.resolve(args.bundle);
  const receiptPath = args.receipt
    ? path.resolve(args.receipt)
    : path.join(path.dirname(bundlePath), "verified-receipt.json");
  const bundle = readJson(bundlePath, "KShop journey bundle");
  return { bundlePath, receiptPath, bundle,
    evidence: prepareDeferredBundleVerification(bundle) };
}

function finalize(prepared) {
  const receipt = finalizeDeferredBundleVerification(prepared.bundle, prepared.evidence);
  atomicWriteJson(prepared.receiptPath, receipt);
  return { receipt, receiptPath: prepared.receiptPath };
}

module.exports = { finalize, helpText, main, parseArgs, prepare, runCheck };

if (require.main === module) {
  console.error("verify-live-journey.js is NOT_ADMITTED directly; use kshop/bootstrap.js --verify-bundle");
  process.exitCode = 2;
}
