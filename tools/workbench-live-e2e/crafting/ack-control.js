#!/usr/bin/env node
"use strict";

const path = require("path");
const { writeAck } = require("./control-channel");

function usage(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = { root: path.resolve(__dirname, "..", "..", ".."), runDir: null,
    requestId: null, transport: null, result: null,
    authorizationDecisionId: null, providerReceipt: null };
  const seen = new Set();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (["--root", "--run-dir", "--request-id", "--transport", "--result",
      "--authorization-decision-id",
      "--provider-receipt"].includes(token)) {
      if (seen.has(token)) usage("duplicate argument: " + token);
      if (!argv[index + 1] || argv[index + 1].startsWith("--")) usage(token + " requires a value");
      seen.add(token);
      const key = token.slice(2).replace(/-([a-z])/g, (_all, letter) => letter.toUpperCase());
      args[key] = argv[++index];
    } else if (token === "--help" || token === "-h") {
      if (argv.length !== 1) usage("help must be used alone");
      args.help = true;
    }
    else usage("unknown argument: " + token);
  }
  return args;
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    console.log(JSON.stringify({ usage: "node ack-control.js --run-dir <owned-run> --request-id <id> --transport <launcher_agent_runtime|codex_computer_use> --result <completed|unavailable|cancelled|failed> --provider-receipt <owned-provider-receipt.json> [--authorization-decision-id <id>]", captureContract: "provider must prewrite control/captures/<request-id>.png and bind it in the provider receipt" }));
    return null;
  }
  if (!args.runDir || !args.requestId || !args.transport || !args.result
      || !args.providerReceipt) {
    usage("run-dir, request-id, transport, result and provider-receipt are required");
  }
  const result = writeAck(args.root, path.resolve(args.runDir), args.requestId, {
    transport: args.transport,
    result: args.result,
    authorizationDecisionId: args.authorizationDecisionId,
    providerReceiptArtifact: args.providerReceipt,
  });
  console.log(JSON.stringify({ requestId: result.request.requestId, result: result.ack.result }, null, 2));
  return result;
}

module.exports = { main, parseArgs };

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    console.error(error.message);
    process.exit(error.isUsageError ? 2 : 1);
  }
}
