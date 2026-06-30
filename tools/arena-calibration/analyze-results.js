#!/usr/bin/env node
"use strict";

const {
  analyzeRows,
  createFixtureRows,
  fail,
  formatSummaryMarkdown,
  readJsonLines,
  writeJsonFile,
} = require("./lib/arena-calibration-core");
const fs = require("fs");
const path = require("path");

function parseArgs(argv) {
  const args = {
    check: false,
    input: null,
    summary: null,
    summaryMd: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--check") {
      args.check = true;
    } else if (token === "--input") {
      args.input = argv[++index];
    } else if (token === "--summary") {
      args.summary = argv[++index];
    } else if (token === "--summary-md") {
      args.summaryMd = argv[++index];
    } else if (token === "--help" || token === "-h") {
      args.help = true;
    } else {
      fail(`unknown argument: ${token}`);
    }
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/analyze-results.js [options]

Options:
  --check                 Analyze built-in fixture JSONL rows.
  --input <file>          Input result JSONL.
  --summary <file>        Write summary JSON.
  --summary-md <file>     Write markdown summary.
`);
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return;
  }
  if (!args.check && !args.input) {
    fail("--input is required unless --check is used");
  }

  const rows = args.check ? createFixtureRows() : readJsonLines(args.input);
  const summary = analyzeRows(rows, {
    resultPath: args.input ? path.resolve(args.input) : "fixture",
  });

  if (!args.check && args.summary) {
    writeJsonFile(args.summary, summary);
  }
  if (!args.check && args.summaryMd) {
    fs.mkdirSync(path.dirname(args.summaryMd), { recursive: true });
    fs.writeFileSync(args.summaryMd, formatSummaryMarkdown(summary), "utf8");
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        schema: summary.schema,
        batchId: summary.batchId,
        cases: summary.cases.length,
        rows: summary.totals.rows,
        errors: summary.totals.errors,
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
