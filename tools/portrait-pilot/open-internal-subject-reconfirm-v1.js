#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const PLAYWRIGHT = path.join(ROOT, "launcher", "perf", "node_modules", "playwright");
const { startServer, stopServer } = require(path.join(ROOT, "launcher", "perf", "lib", "server"));
const reviewBuild = require("./build-internal-subject-review-v1");
const decisionVerifier = require("./verify-internal-subject-review-decisions-v1");

function findEdge() {
  const candidates = [
    path.join(process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)", "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(process.env.ProgramFiles || "C:\\Program Files", "Microsoft", "Edge", "Application", "msedge.exe"),
    process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, "Microsoft", "Edge", "Application", "msedge.exe") : "",
  ];
  const found = candidates.find((candidate) => candidate && fs.existsSync(candidate));
  if (!found) throw new Error("Microsoft Edge not found");
  return found;
}

function parseArgs(argv) {
  const options = { batch: null, reviewKey: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--batch") {
      options.batch = argv[index + 1];
      index += 1;
    } else if (argv[index] === "--review-key") {
      options.reviewKey = argv[index + 1];
      index += 1;
    } else if (argv[index] === "--check") {
      options.check = true;
    } else if (argv[index] === "--help") {
      options.help = true;
    } else {
      throw new Error(`未知参数：${argv[index]}`);
    }
  }
  return options;
}

function loadAndVerify(batchArgument, reviewKey) {
  const loaded = reviewBuild.loadBatch(batchArgument);
  const reviewPath = path.join(loaded.batchRoot, "internal-subject-review-data.json");
  const decisionsPath = path.join(loaded.batchRoot, "internal-subject-human-decisions.json");
  if (!fs.existsSync(reviewPath) || !fs.existsSync(decisionsPath)) throw new Error("复核数据或 canonical 人工决定缺失");
  const dataset = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
  reviewBuild.verifyReviewDataset(dataset);
  const decisions = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  decisionVerifier.validateDecisions(dataset, decisions);
  const item = dataset.items.find((entry) => entry.reviewKey === reviewKey);
  const prior = decisions.decisions.find((entry) => entry.reviewKey === reviewKey);
  if (!item || !prior) throw new Error(`reviewKey 不在当前批次：${reviewKey}`);
  return { ...loaded, reviewPath, decisionsPath, dataset, decisions, item, prior };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch || !options.reviewKey) {
    process.stdout.write("用法：node tools/portrait-pilot/open-internal-subject-reconfirm-v1.js --batch <tmp/portrait-pilot/...> --review-key <portraitRef::variant> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!fs.existsSync(PLAYWRIGHT)) throw new Error("缺 Playwright；运行 npm --prefix launcher/perf ci --ignore-scripts");
  const loaded = loadAndVerify(options.batch, options.reviewKey);
  if (options.check) {
    process.stdout.write(`${JSON.stringify({
      status: "internal_subject_reconfirmation_preflight_verified",
      reviewDigest: loaded.dataset.reviewDigest,
      reviewKey: options.reviewKey,
      priorDecision: loaded.prior,
      untouchedDecisionCount: loaded.decisions.decisions.length - 1,
    })}\n`);
    return;
  }

  const { chromium } = require(PLAYWRIGHT);
  const profilePath = path.join(loaded.batchRoot, "internal-subject-reconfirm-profile");
  fs.mkdirSync(profilePath, { recursive: true });
  const server = await startServer(ROOT, 0);
  let context = null;
  try {
    context = await chromium.launchPersistentContext(profilePath, {
      executablePath: findEdge(),
      headless: false,
      viewport: { width: 1680, height: 1000 },
      acceptDownloads: false,
    });
    const page = context.pages()[0] || await context.newPage();
    await page.exposeFunction("saveInternalSubjectReviewDecisions", async (value) => {
      decisionVerifier.validateDecisions(loaded.dataset, value);
      const body = `${JSON.stringify(value, null, 2)}\n`;
      const archiveRoot = path.join(loaded.batchRoot, "human-exports");
      fs.mkdirSync(archiveRoot, { recursive: true });
      const stamp = new Date().toISOString().replaceAll(":", "").replaceAll(".", "");
      const archivePath = path.join(archiveRoot, `internal-subject-human-decisions-reconfirmed-${stamp}.json`);
      fs.writeFileSync(archivePath, body, { encoding: "utf8", flag: "wx" });
      fs.writeFileSync(loaded.decisionsPath, body, { encoding: "utf8", flag: "w" });
      return {
        path: path.relative(ROOT, loaded.decisionsPath).replaceAll("\\", "/"),
        archivePath: path.relative(ROOT, archivePath).replaceAll("\\", "/"),
      };
    });
    const dataPath = `/${path.relative(ROOT, loaded.reviewPath).replaceAll("\\", "/")}`;
    const decisionsPath = `/${path.relative(ROOT, loaded.decisionsPath).replaceAll("\\", "/")}`;
    const query = new URLSearchParams({ data: dataPath, decisions: decisionsPath, reviewKey: options.reviewKey });
    const pageUrl = `${server.url}launcher/web/modules/portrait-pilot-review/dev/internal-subject-reconfirm.html?${query}`;
    await page.goto(pageUrl, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    const archiveRoot = path.join(loaded.batchRoot, "human-exports");
    fs.mkdirSync(archiveRoot, { recursive: true });
    const stamp = new Date().toISOString().replaceAll(":", "").replaceAll(".", "");
    const readyPath = path.join(archiveRoot, `internal-subject-reconfirm-opened-${stamp}.json`);
    fs.writeFileSync(readyPath, `${JSON.stringify({
      schema: "cf7.enemy-portrait-internal-subject-reconfirmation-opened.v1",
      openedAt: new Date().toISOString(),
      openerPid: process.pid,
      reviewDigest: loaded.dataset.reviewDigest,
      reviewKey: options.reviewKey,
      priorDecision: loaded.prior,
      pageUrl,
      productionWrites: false,
    }, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
    process.stdout.write(`${JSON.stringify({ status: "internal_subject_reconfirmation_opened", readyPath, reviewKey: options.reviewKey, pageUrl })}\n`);
    const browser = context.browser();
    await new Promise((resolve) => browser.on("disconnected", resolve));
    context = null;
  } finally {
    if (context) await context.close();
    await stopServer(server);
  }
}

main().catch((error) => {
  process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
  process.exitCode = 1;
});
