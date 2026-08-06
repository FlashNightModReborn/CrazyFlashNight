#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const { NpcJourneyError, canonicalJson, deepClone, sha256Text } = require("./common");
const { verifyEvidenceFile } = require("./verify-evidence");

function usage(message) {
  const error = new Error(message);
  error.code = "usage";
  throw error;
}

function parseArgs(argv) {
  if (!Array.isArray(argv) || ![2, 4].includes(argv.length)
      || argv[0] !== "--bundle" || !argv[1] || argv[1].startsWith("--")
      || (argv.length === 4 && (argv[2] !== "--receipt" || !argv[3]
        || argv[3].startsWith("--")))) {
    usage("usage: verify-live-journey.js --bundle <absolute evidence-bundle.json> [--receipt <absolute new file>]");
  }
  return { bundle: argv[1], receipt: argv.length === 4 ? argv[3] : null };
}

function validateArgs(args) {
  if (!args.bundle || !path.isAbsolute(args.bundle)) usage("--bundle must be absolute");
  args.bundle = path.resolve(args.bundle);
  if (args.receipt) {
    if (!path.isAbsolute(args.receipt)) usage("--receipt must be absolute");
    args.receipt = path.resolve(args.receipt);
    if (path.dirname(args.receipt).toLowerCase() !== path.dirname(args.bundle).toLowerCase()) {
      usage("--receipt must stay in the evidence bundle directory");
    }
  }
  return args;
}

function immutableReceipt(filePath, receipt) {
  fs.writeFileSync(filePath, JSON.stringify(receipt, null, 2) + "\n", {
    encoding: "utf8",
    mode: 0o600,
    flag: "wx",
  });
}

function prepare(argv) {
  const args = validateArgs(parseArgs(argv));
  const receipt = verifyEvidenceFile(args.bundle);
  const frozen = {
    schema: "workbench-live-e2e.npc.external-verification.v1",
    bundlePath: args.bundle,
    receiptPath: args.receipt,
    receipt,
  };
  frozen.evidenceSha256 = sha256Text(canonicalJson(frozen));
  return frozen;
}

function finalize(prepared) {
  const frozen = deepClone(prepared);
  const digest = frozen && frozen.evidenceSha256;
  if (frozen) delete frozen.evidenceSha256;
  if (!prepared || prepared.schema !== "workbench-live-e2e.npc.external-verification.v1"
      || digest !== sha256Text(canonicalJson(frozen))) {
    throw new Error("prepared NPC verification is missing or changed");
  }
  if (prepared.receiptPath) immutableReceipt(prepared.receiptPath, prepared.receipt);
  return { receipt: prepared.receipt, receiptPath: prepared.receiptPath };
}

function main(argv) { return finalize(prepare(argv)).receipt; }

module.exports = { finalize, immutableReceipt, main, parseArgs, prepare, validateArgs };

if (require.main === module) {
  process.stderr.write("verify-live-journey.js is NOT_ADMITTED directly; use npc/bootstrap.js --verify-bundle\n");
  process.exitCode = 2;
}
