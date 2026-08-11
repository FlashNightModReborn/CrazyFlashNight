#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const verifier = require("./verify-source-choice-decisions");

const ROOT = path.resolve(__dirname, "..", "..");
const PLAYWRIGHT = path.join(ROOT, "launcher", "perf", "node_modules", "playwright");
const { startServer, stopServer } = require(path.join(ROOT, "launcher", "perf", "lib", "server"));

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
  const options = { batch: null, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--batch") {
      options.batch = argv[index + 1];
      index += 1;
    } else if (argv[index] === "--check") options.check = true;
    else if (argv[index] === "--help") options.help = true;
    else throw new Error(`未知参数：${argv[index]}`);
  }
  return options;
}

function writeReadyMarker(filePath, value) {
  const temporary = `${filePath}.${process.pid}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  fs.renameSync(temporary, filePath);
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.batch) {
    process.stdout.write("用法：node tools/portrait-pilot/open-source-choice.js --batch <source choice batch> [--check]\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!fs.existsSync(PLAYWRIGHT)) throw new Error("缺 Playwright；运行 npm --prefix launcher/perf ci --ignore-scripts");
  const loaded = verifier.loadSourceChoiceBatch(options.batch);
  if (options.check) {
    process.stdout.write(`${JSON.stringify({ status: "source_choice_open_preflight_verified", manifestDigest: loaded.dataset.manifestDigest, rows: loaded.dataset.items.length, candidates: loaded.dataset.counts.sourceCandidateCount, artifactCount: loaded.artifactCount })}\n`);
    return;
  }

  const { chromium } = require(PLAYWRIGHT);
  const profilePath = path.join(loaded.batchRoot, "source-choice-profile");
  const decisionsPath = path.join(loaded.batchRoot, "portrait-pilot-source-choice-decisions.json");
  const readyPath = path.join(loaded.batchRoot, "source-choice-opened.json");
  if (fs.existsSync(readyPath)) throw new Error("source-choice-opened.json 已存在；拒绝覆盖旧启动证据");
  fs.mkdirSync(profilePath, { recursive: true });
  const server = await startServer(ROOT, 0);
  let context = null;
  try {
    context = await chromium.launchPersistentContext(profilePath, {
      executablePath: findEdge(),
      headless: false,
      viewport: { width: 1680, height: 1000 },
      acceptDownloads: true,
    });
    const page = context.pages()[0] || await context.newPage();
    await page.exposeFunction("savePortraitSourceChoiceDecisions", async (value) => {
      verifier.validateDecisions(loaded.dataset, value);
      const body = `${JSON.stringify(value, null, 2)}\n`;
      const archiveRoot = path.join(loaded.batchRoot, "source-choice-exports");
      fs.mkdirSync(archiveRoot, { recursive: true });
      const stamp = new Date().toISOString().replaceAll(":", "").replaceAll(".", "");
      const archivePath = path.join(archiveRoot, `portrait-pilot-source-choice-decisions-${stamp}.json`);
      fs.writeFileSync(archivePath, body, { encoding: "utf8", flag: "wx" });
      fs.writeFileSync(decisionsPath, body, { encoding: "utf8", flag: "w" });
      return {
        path: path.relative(ROOT, decisionsPath).replaceAll("\\", "/"),
        archivePath: path.relative(ROOT, archivePath).replaceAll("\\", "/"),
      };
    });
    page.on("download", async (download) => {
      await download.saveAs(decisionsPath);
      await page.evaluate((savedPath) => {
        window.dispatchEvent(new CustomEvent("source-choice-export-saved", { detail: savedPath }));
      }, path.relative(ROOT, decisionsPath).replaceAll("\\", "/"));
    });
    const dataPath = `/${path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/")}`;
    const pageUrl = `${server.url}launcher/web/modules/portrait-pilot-review/dev/source-choice.html?data=${encodeURIComponent(dataPath)}`;
    await page.goto(pageUrl, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    writeReadyMarker(readyPath, {
      schema: "cf7.enemy-portrait-source-choice-opened.v1",
      openedAt: new Date().toISOString(),
      openerPid: process.pid,
      manifestDigest: loaded.dataset.manifestDigest,
      sourceDigest: loaded.dataset.sourceDigest,
      rows: loaded.dataset.items.length,
      candidates: loaded.dataset.counts.sourceCandidateCount,
      pageUrl,
    });
    process.stdout.write(`${JSON.stringify({ status: "source_choice_opened", readyPath: path.relative(ROOT, readyPath).replaceAll("\\", "/"), manifestDigest: loaded.dataset.manifestDigest })}\n`);
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
