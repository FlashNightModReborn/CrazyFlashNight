#!/usr/bin/env node
"use strict";

const {
  createPilotManifest,
  fail,
  normalizeManifest,
  readJsonFile,
  writeJsonFile,
} = require("./lib/arena-calibration-core");

function parseArgs(argv) {
  const args = {
    check: false,
    input: null,
    output: null,
    batchId: null,
    repeat: 5,
    timeoutFrames: 5400,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--check") {
      args.check = true;
    } else if (token === "--input") {
      args.input = argv[++index];
    } else if (token === "--output") {
      args.output = argv[++index];
    } else if (token === "--batch-id") {
      args.batchId = argv[++index];
    } else if (token === "--repeat") {
      args.repeat = Number(argv[++index]);
    } else if (token === "--timeout-frames") {
      args.timeoutFrames = Number(argv[++index]);
    } else if (token === "--help" || token === "-h") {
      args.help = true;
    } else {
      fail(`unknown argument: ${token}`);
    }
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/build-candidates.js [options]

Options:
  --check                 Run the built-in pilot manifest validation.
  --input <file>          Normalize and validate an existing manifest seed.
  --output <file>         Write normalized case_manifest.json.
  --batch-id <id>         Override generated pilot batch id.
  --repeat <n>            Repeat count for generated pilot cases. Default: 5.
  --timeout-frames <n>    Timeout frames for generated pilot cases. Default: 5400.
`);
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return;
  }

  const manifest = args.input
    ? normalizeManifest(readJsonFile(args.input))
    : createPilotManifest({
        batchId: args.batchId,
        repeat: args.repeat,
        timeoutFrames: args.timeoutFrames,
      });

  if (args.output && !args.check) {
    writeJsonFile(args.output, manifest);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        schema: manifest.schema,
        batchId: manifest.batchId,
        manifestHash: manifest.manifestHash,
        cases: manifest.cases.length,
        output: args.output || null,
      },
      null,
      2
    )
  );
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(error.message);
  process.exit(error.isUsageError ? 2 : 1);
}
