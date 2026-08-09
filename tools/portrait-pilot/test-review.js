#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");

const ROOT = path.resolve(__dirname, "..", "..");
const PLAYWRIGHT = path.join(ROOT, "launcher", "perf", "node_modules", "playwright");
const { startServer, stopServer } = require(path.join(ROOT, "launcher", "perf", "lib", "server"));
const reviewBuild = require("./build-review");
const decisionVerifier = require("./verify-review-decisions");

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
  if (index < 0 || !argv[index + 1]) throw new Error("用法：node tools/portrait-pilot/test-review.js --batch <tmp/portrait-pilot/...>");
  return argv[index + 1];
}

async function main() {
  const loaded = reviewBuild.loadBatch(batchArgument(process.argv.slice(2)));
  reviewBuild.verifyCurrentSource(loaded.manifest);
  const reviewPath = path.join(loaded.batchRoot, "review-data.json");
  const dataset = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
  reviewBuild.verifyReviewDataset(dataset);
  assert.equal(dataset.items.length, dataset.counts.total);
  assert.equal(dataset.items.filter((item) => item.blocked).length, dataset.counts.blocked);
  assert.equal(dataset.items.filter((item) => !item.blocked).length, dataset.counts.eligible);

  const edge = findEdge();
  if (!edge) throw new Error("Microsoft Edge not found");
  const { chromium } = require(PLAYWRIGHT);
  const server = await startServer(ROOT, 0);
  const browser = await chromium.launch({ executablePath: edge, headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1500, height: 900 } });
    let exportedValue = null;
    let nativeSaveCalls = 0;
    let resolveSaved;
    const saved = new Promise((resolve) => { resolveSaved = resolve; });
    let browserDownloads = 0;
    page.on("download", () => { browserDownloads += 1; });
    await page.exposeFunction("savePortraitReviewDecisions", async (value) => {
      nativeSaveCalls += 1;
      exportedValue = value;
      await new Promise((resolve) => setTimeout(resolve, 75));
      resolveSaved(value);
      return {
        path: "tmp/portrait-pilot/test/portrait-pilot-review-decisions.json",
        archivePath: "tmp/portrait-pilot/test/review-exports/portrait-pilot-review-decisions-test.json",
      };
    });
    const dataPath = `/${path.relative(ROOT, reviewPath).replaceAll("\\", "/")}`;
    const pageUrl = `${server.url}launcher/web/modules/portrait-pilot-review/dev/review.html?data=${encodeURIComponent(dataPath)}`;
    await page.goto(pageUrl, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator(".review-card").count(), dataset.counts.total);
    assert.equal(await page.locator('.review-card[data-blocked="true"]').count(), dataset.counts.blocked);
    assert.equal(await page.locator('.review-card[data-blocked="true"] button[data-status="pass"]').count(), 0);
    assert.equal(
      await page.locator('.review-card[data-blocked="true"] button[data-status="source"]').count(),
      dataset.counts.blocked,
    );

    const firstEligible = page.locator('.review-card[data-blocked="false"]').first();
    await firstEligible.locator('button[data-status="pass"]').click();
    const reviewKey = await firstEligible.getAttribute("data-review-key");
    const storageKey = await page.evaluate(() => window.__portraitReviewTest.storageKey);
    assert.ok(storageKey.endsWith(dataset.reviewDigest));
    assert.equal(await page.evaluate((key) => Boolean(JSON.parse(localStorage.getItem(key)).decisions), storageKey), true);
    await page.reload({ waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator(".review-card").evaluateAll(
      (cards, key) => cards.find((card) => card.dataset.reviewKey === key)?.dataset.reviewed,
      reviewKey,
    ), "true");

    const validation = await page.evaluate(() => {
      const api = window.__portraitReviewTest;
      const now = new Date().toISOString();
      const decisions = Object.fromEntries(api.dataset.items.map((item) => [
        item.reviewKey,
        {
          status: item.blocked ? "source" : "pass",
          notes: item.blocked ? "来源阻断已人工确认" : "",
          updatedAt: now,
        },
      ]));
      const value = {
        schema: api.dataset.decisionSchema,
        batchId: api.dataset.batchId,
        sourceDigest: api.dataset.sourceDigest,
        reviewDigest: api.dataset.reviewDigest,
        complete: true,
        exportedAt: now,
        decisions,
      };
      api.validateImport(value);
      let staleRejected = false;
      try {
        api.validateImport({ ...value, reviewDigest: "0".repeat(64) });
      } catch {
        staleRejected = true;
      }
      return { complete: api.completeDecisionMap(decisions), staleRejected };
    });
    assert.deepEqual(validation, { complete: true, staleRejected: true });

    for (const item of dataset.items) {
      const card = page.locator(`.review-card[data-review-key=${JSON.stringify(item.reviewKey)}]`);
      await card.locator(`button[data-status="${item.blocked ? "source" : "pass"}"]`).click();
      if (item.blocked) await card.locator("textarea").fill("来源阻断已人工确认");
    }
    await page.locator("#export-button:not([disabled])").waitFor({ timeout: 30_000 });
    await page.locator("#export-button").evaluate((button) => {
      button.click();
      button.click();
      button.click();
    });
    await Promise.race([
      saved,
      new Promise((_, reject) => setTimeout(() => reject(new Error("原生导出回调未触发")), 30_000)),
    ]);
    decisionVerifier.validateDecisions(dataset, exportedValue);
    assert.equal(nativeSaveCalls, 1);
    assert.equal(browserDownloads, 0);
    assert.match(await page.locator("#message").textContent(), /保存成功：tmp\/portrait-pilot\/test\/portrait-pilot-review-decisions\.json/);
    assert.match(await page.locator("#export-button").textContent(), /已保存/);
    process.stdout.write(`${JSON.stringify({
      status: "portrait_review_edge_verified",
      rows: dataset.items.length,
      blocked: dataset.counts.blocked,
      reviewDigest: dataset.reviewDigest,
      localStorageIsolated: true,
      staleImportRejected: true,
      nativeExportVerified: true,
      repeatedClickSuppressed: true,
      visibleSaveFeedbackVerified: true,
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
