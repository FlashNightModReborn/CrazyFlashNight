#!/usr/bin/env node
"use strict";

const path = require("path");
const { writeAck } = require("./control-channel");

function parse(argv) {
  const output = {};
  const allowed = new Set(["run-dir", "request-id", "transport", "result",
    "provider-receipt"]);
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const rawKey = token.startsWith("--") ? token.slice(2) : "";
    if (!allowed.has(rawKey) || index + 1 >= argv.length
        || argv[index + 1].startsWith("--")) throw new Error("invalid argument " + token);
    const key = token.slice(2).replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase());
    if (Object.prototype.hasOwnProperty.call(output, key)) throw new Error("duplicate argument " + token);
    output[key] = argv[++index];
  }
  return output;
}

function main(argv, options) {
  const args = parse(argv);
  if (!args.runDir || !args.requestId || !args.transport || !args.result
      || !args.providerReceipt) {
    throw new Error("required: --run-dir --request-id --transport --result --provider-receipt");
  }
  const settings = options || {};
  const root = settings.root ? path.resolve(settings.root)
    : path.resolve(__dirname, "..", "..", "..");
  const result = writeAck(root, path.resolve(args.runDir), args.requestId, {
    transport: args.transport,
    result: args.result,
    providerReceiptArtifact: args.providerReceipt,
  });
  const output = { success: true, ackPath: result.ackPath, sha256: result.sha256 };
  if (!settings.quiet) process.stdout.write(JSON.stringify(output) + "\n");
  return output;
}

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    process.stderr.write(JSON.stringify({ success: false, code: error.code || "ack_failed", message: error.message }) + "\n");
    process.exitCode = 1;
  }
}

module.exports = { main, parse };
