#!/usr/bin/env node
"use strict";

const {
  analyzeRows,
  createFixtureRows,
  fail,
  planNextBatch,
  readJsonFile,
  writeJsonFile,
} = require("./lib/arena-calibration-core");

function parseArgs(argv) {
  const args = {
    check: false,
    summary: null,
    output: null,
    planner: "rule",
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--check") {
      args.check = true;
    } else if (token === "--summary") {
      args.summary = argv[++index];
    } else if (token === "--output") {
      args.output = argv[++index];
    } else if (token === "--planner") {
      args.planner = argv[++index];
    } else if (token === "--help" || token === "-h") {
      args.help = true;
    } else {
      fail(`unknown argument: ${token}`);
    }
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/plan-next-batch.js [options]

Options:
  --check              Plan from built-in fixture summary.
  --summary <file>     Input summary JSON.
  --output <file>      Write next-batch plan JSON.
  --planner <name>     Planner label. Default: rule.
`);
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return;
  }
  if (!args.check && !args.summary) {
    fail("--summary is required unless --check is used");
  }

  const summary = args.check ? analyzeRows(createFixtureRows(), { resultPath: "fixture" }) : readJsonFile(args.summary);
  const plan = planNextBatch(summary, { planner: args.planner });

  if (!args.check && args.output) {
    writeJsonFile(args.output, plan);
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        schema: plan.schema,
        sourceBatchId: plan.sourceBatchId,
        decisions: plan.decisions.length,
        planner: plan.planner.name,
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
