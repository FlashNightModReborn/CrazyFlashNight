#!/usr/bin/env node
"use strict";

const path = require("path");
const { writeAck } = require("./control-channel");

function usageError(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  if (argv.length === 1 && argv[0] === "--help") return { help: true };
  if (argv.includes("--help")) usageError("--help cannot be mixed with acknowledgement arguments");
  const args = { providerReceiptFile: null,
    authorizationDecisionId: null };
  const seen = new Set();
  for (let index = 0; index < argv.length; index += 1) {
    const name = argv[index];
    if (["--run-dir", "--request-id", "--transport", "--result", "--provider-receipt-file",
      "--authorization-decision-id"].includes(name)) {
      if (seen.has(name)) usageError("duplicate argument: " + name);
      seen.add(name);
      if (index + 1 >= argv.length) usageError(name + " requires a value");
      const key = name.slice(2).replace(/-([a-z])/g, (_m, letter) => letter.toUpperCase());
      args[key] = argv[++index];
    } else usageError("unknown argument: " + name);
  }
  return args;
}

function printHelp() {
  console.log([
    "Usage:",
    "  node tools/workbench-live-e2e/kshop/ack-cu.js --run-dir <owned-run-dir>",
    "    --request-id <id> --transport <launcher_agent_runtime|codex_computer_use>",
    "    --result <completed|unavailable|cancelled|failed>",
    "    --provider-receipt-file <provider-produced-json>",
    "    [--authorization-decision-id <exact one-shot id>]",
    "",
    "The provider must prewrite the receipt and any required PNG at the exact request-owned",
    "control/provider-receipts/<request-id>.json and control/captures/<request-id>.png paths.",
    "This helper only verifies and references those exact bytes; it never copies an external image",
    "or creates the receipt, operation id, issuer identity, or tool-result provenance.",
  ].join("\n"));
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  ["runDir", "requestId", "transport", "result", "providerReceiptFile"].forEach((name) => {
    if (!args[name]) usageError("--" + name.replace(/[A-Z]/g, (m) => "-" + m.toLowerCase()) + " is required");
  });
  const root = path.resolve(__dirname, "..", "..", "..");
  const written = writeAck(root, args.runDir, args.requestId, {
    transport: args.transport,
    result: args.result,
    providerReceiptFile: path.resolve(args.providerReceiptFile),
    authorizationDecisionId: args.authorizationDecisionId || null,
  });
  console.log(JSON.stringify({
    ok: true,
    requestId: written.request.requestId,
    step: written.request.step,
    result: written.ack.result,
    providerReceiptRef: written.ack.providerReceiptRef,
  }, null, 2));
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(error.message);
  process.exit(error.isUsageError ? 2 : 1);
}
