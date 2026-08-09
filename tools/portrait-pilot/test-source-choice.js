#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
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
  return candidates.find((candidate) => candidate && fs.existsSync(candidate));
}

function batchArgument(argv) {
  const index = argv.indexOf("--batch");
  if (index < 0 || !argv[index + 1]) throw new Error("用法：node tools/portrait-pilot/test-source-choice.js --batch <source choice batch>");
  return argv[index + 1];
}

async function main() {
  const loaded = verifier.loadSourceChoiceBatch(batchArgument(process.argv.slice(2)));
  const edge = findEdge();
  if (!edge) throw new Error("Microsoft Edge not found");
  const { chromium } = require(PLAYWRIGHT);
  const server = await startServer(ROOT, 0);
  const browser = await chromium.launch({ executablePath: edge, headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1500, height: 960 } });
    let exportedValue = null;
    let nativeSaveCalls = 0;
    let browserDownloads = 0;
    let resolveSaved;
    const saved = new Promise((resolve) => { resolveSaved = resolve; });
    page.on("download", () => { browserDownloads += 1; });
    await page.exposeFunction("savePortraitSourceChoiceDecisions", async (value) => {
      nativeSaveCalls += 1;
      exportedValue = value;
      await new Promise((resolve) => setTimeout(resolve, 75));
      resolveSaved(value);
      return {
        path: "tmp/portrait-pilot/test/portrait-pilot-source-choice-decisions.json",
        archivePath: "tmp/portrait-pilot/test/source-choice-exports/portrait-pilot-source-choice-decisions-test.json",
      };
    });
    const dataPath = `/${path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/")}`;
    const pageUrl = `${server.url}launcher/web/modules/portrait-pilot-review/dev/source-choice.html?data=${encodeURIComponent(dataPath)}`;
    await page.goto(pageUrl, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator(".source-review-row").count(), loaded.dataset.counts.identityCount);
    assert.equal(await page.locator(".source-card").count(), loaded.dataset.counts.sourceCandidateCount);
    assert.equal(await page.locator('.source-card[data-renderable="false"]').count(), loaded.dataset.counts.manualSourceCandidateCount);
    assert.equal(await page.locator('.source-card[data-renderable="true"] .frame-strip img').count() > 0, true);

    const firstRow = page.locator(".source-review-row").first();
    await firstRow.locator('.source-card[data-renderable="true"] .select-source').first().click();
    const firstReviewKey = await firstRow.getAttribute("data-review-key");
    const storageKey = await page.evaluate(() => window.__portraitSourceChoiceTest.storageKey);
    assert.ok(storageKey.endsWith(loaded.dataset.manifestDigest));
    assert.equal(await page.evaluate((key) => Boolean(JSON.parse(localStorage.getItem(key)).decisions), storageKey), true);
    await page.reload({ waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator(`.source-review-row[data-review-key=${JSON.stringify(firstReviewKey)}]`).getAttribute("data-reviewed"), "true");

    const validation = await page.evaluate(() => {
      const api = window.__portraitSourceChoiceTest;
      const now = new Date().toISOString();
      const choices = Object.fromEntries(api.dataset.items.map((item) => [item.reviewKey, {
        status: "selected",
        sourceCandidateKey: item.sources.find((source) => source.renderable).sourceCandidateKey,
        notes: "",
        updatedAt: now,
      }]));
      const value = {
        schema: api.dataset.decisionSchema,
        batchId: api.dataset.batchId,
        sourceDigest: api.dataset.sourceDigest,
        manifestDigest: api.dataset.manifestDigest,
        complete: true,
        exportedAt: now,
        choices,
      };
      api.validateImport(value);
      let staleRejected = false;
      try { api.validateImport({ ...value, manifestDigest: "0".repeat(64) }); } catch { staleRejected = true; }
      const manualSource = api.dataset.items.flatMap((item) => item.sources.map((source) => ({ item, source }))).find((entry) => !entry.source.renderable);
      let unrenderableSelectedRejected = false;
      try {
        api.validateImport({
          ...value,
          choices: {
            ...choices,
            [manualSource.item.reviewKey]: {
              status: "selected",
              sourceCandidateKey: manualSource.source.sourceCandidateKey,
              notes: "",
              updatedAt: now,
            },
          },
        });
      } catch { unrenderableSelectedRejected = true; }
      const manualChoices = {
        ...choices,
        [api.dataset.items[0].reviewKey]: { status: "manual_maintenance", sourceCandidateKey: null, notes: "CS6 人工定位", updatedAt: now },
      };
      api.validateImport({ ...value, choices: manualChoices });
      return { staleRejected, unrenderableSelectedRejected };
    });
    assert.deepEqual(validation, { staleRejected: true, unrenderableSelectedRejected: true });

    for (const item of loaded.dataset.items) {
      const row = page.locator(`.source-review-row[data-review-key=${JSON.stringify(item.reviewKey)}]`);
      await row.locator('.source-card[data-renderable="true"] .select-source').first().click();
    }
    await page.locator("#export-button:not([disabled])").waitFor({ timeout: 30_000 });
    await page.locator("#export-button").evaluate((button) => { button.click(); button.click(); button.click(); });
    await Promise.race([saved, new Promise((_, reject) => setTimeout(() => reject(new Error("原生导出回调未触发")), 30_000))]);
    verifier.validateDecisions(loaded.dataset, exportedValue);
    assert.equal(nativeSaveCalls, 1);
    assert.equal(browserDownloads, 0);
    assert.match(await page.locator("#message").textContent(), /保存成功：tmp\/portrait-pilot\/test\/portrait-pilot-source-choice-decisions\.json/);
    assert.match(await page.locator("#export-button").textContent(), /已保存/);
    process.stdout.write(`${JSON.stringify({
      status: "source_choice_edge_verified",
      rows: loaded.dataset.items.length,
      candidates: loaded.dataset.counts.sourceCandidateCount,
      internalManCandidates: loaded.dataset.items.flatMap((item) => item.sources).filter((source) => source.renderStrategy === "first_frame_named_man_instance").length,
      manualCandidates: loaded.dataset.counts.manualSourceCandidateCount,
      localStorageIsolated: true,
      staleImportRejected: true,
      unrenderableSelectionRejected: true,
      manualMaintenancePathValidated: true,
      nativeExportVerified: true,
      repeatedClickSuppressed: true,
      browserDownloadSuppressed: true,
    })}\n`);
  } finally {
    await browser.close();
    await stopServer(server);
  }
}

main().catch((error) => {
  process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
  process.exitCode = 1;
});
