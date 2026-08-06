"use strict";

const path = require("path");
const { atomicWriteJson, readJsonFile } = require("./common");
const { verifyBundle } = require("./evidence-verifier");

function prepare(argv) {
  if (!Array.isArray(argv) || ![2, 4].includes(argv.length) || argv[0] !== "--bundle"
      || !argv[1] || !path.isAbsolute(argv[1])
      || (argv.length === 4 && (argv[2] !== "--receipt" || !argv[3]
        || !path.isAbsolute(argv[3])))) {
    const error = new Error("--bundle requires one absolute journey-bundle.json path; optional --receipt also requires an absolute path");
    error.isUsageError = true;
    throw error;
  }
  const bundlePath = path.resolve(argv[1]);
  const bundle = readJsonFile(bundlePath, "bundle", 128 * 1024 * 1024).value;
  if (path.resolve(bundle.runDir || "", "journey-bundle.json") !== bundlePath) {
    throw new Error("bundle path is not the exact owned run artifact");
  }
  const receipt = verifyBundle(bundle);
  return { bundlePath, receipt, receiptPath: argv.length === 4 ? path.resolve(argv[3]) : null };
}

function finalize(prepared) {
  if (!prepared || !prepared.receipt || !prepared.bundlePath) {
    throw new Error("prepared verification is missing");
  }
  if (prepared.receiptPath) atomicWriteJson(prepared.receiptPath, prepared.receipt);
  return { receipt: prepared.receipt, receiptPath: prepared.receiptPath };
}

function main(argv) { return finalize(prepare(argv)); }

module.exports = { finalize, main, prepare };

if (require.main === module) {
  console.error("Use canonical entry: node tools/workbench-live-e2e/crafting/bootstrap.js --verify-bundle <path>");
  process.exitCode = 2;
}
