#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const verifier = require("./verify-frame-reselection");

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
  if (index < 0 || !argv[index + 1]) throw new Error("用法：node tools/portrait-pilot/test-frame-reselection.js --batch <frame reselection batch>");
  return argv[index + 1];
}

async function main() {
  const loaded = verifier.loadBatch(batchArgument(process.argv.slice(2)));
  const edge = findEdge();
  if (!edge) throw new Error("Microsoft Edge not found");
  const { chromium } = require(PLAYWRIGHT);
  const server = await startServer(ROOT, 0);
  const browser = await chromium.launch({ executablePath: edge, headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1800, height: 1050 } });
    let exportedValue = null;
    let nativeSaveCalls = 0;
    let browserDownloads = 0;
    let resolveSaved;
    const saved = new Promise((resolve) => { resolveSaved = resolve; });
    page.on("download", () => { browserDownloads += 1; });
    await page.exposeFunction("savePortraitFrameReselection", async (value) => {
      nativeSaveCalls += 1;
      exportedValue = value;
      await new Promise((resolve) => setTimeout(resolve, 75));
      resolveSaved(value);
      return { path: "tmp/portrait-pilot/test/portrait-pilot-frame-reselection.json", archivePath: "tmp/portrait-pilot/test/frame-reselection-exports/test.json" };
    });
    const dataPath = `/${path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/")}`;
    const pageUrl = `${server.url}launcher/web/modules/portrait-pilot-review/dev/frame-reselection.html?data=${encodeURIComponent(dataPath)}`;
    await page.goto(pageUrl, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator(".source-review-row").count(), loaded.dataset.items.length);
    assert.equal(await page.locator(".frame-card").count(), loaded.dataset.counts.candidateCount);
    assert.equal(await page.locator('.frame-card[data-rejected="true"] .select-frame:disabled').count(), loaded.dataset.counts.rejectedCandidateCount);
    await page.locator(".frame-vector img").first().waitFor({ state: "visible" });
    const vectorLoaded = await page.locator(".frame-vector img").first().evaluate((image) => image.complete && image.naturalWidth > 0 && image.naturalHeight > 0);
    assert.equal(vectorLoaded, true);

    for (const item of loaded.dataset.items) {
      const row = page.locator(`[data-review-key="${item.reviewKey}"]`);
      const selectable = item.candidates.find((candidate) => !item.rejectedCandidateIds.includes(candidate.candidateId));
      await row.locator(`[data-candidate-id="${selectable.candidateId}"] .select-frame`).click();
    }
    assert.equal(await page.locator('.source-review-row[data-reviewed="true"]').count(), loaded.dataset.items.length);
    const storageKey = await page.evaluate(() => window.__portraitFrameReselectionTest.storageKey);
    assert.ok(storageKey.endsWith(loaded.dataset.datasetDigest));
    await page.reload({ waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator('.source-review-row[data-reviewed="true"]').count(), loaded.dataset.items.length);

    const validation = await page.evaluate(() => {
      const api = window.__portraitFrameReselectionTest;
      const value = api.buildExport();
      api.validateImport(value);
      let staleRejected = false;
      let rejectedFrameRejected = false;
      try { api.validateImport({ ...value, datasetDigest: "0".repeat(64) }); } catch { staleRejected = true; }
      try {
        const item = api.dataset.items[0];
        const rejectedId = item.rejectedCandidateIds[0];
        const rejected = item.candidates.find((candidate) => candidate.candidateId === rejectedId);
        api.validateImport({
          ...value,
          choices: {
            ...value.choices,
            [item.reviewKey]: {
              ...value.choices[item.reviewKey],
              candidateId: rejected.candidateId,
              candidateSha256: rejected.artifact.sha256,
              vectorArtifactSha256: rejected.vectorArtifact.sha256,
              frame: rejected.frame,
            },
          },
        });
      } catch { rejectedFrameRejected = true; }
      return { complete: api.completeDecisions(), staleRejected, rejectedFrameRejected };
    });
    assert.deepEqual(validation, { complete: true, staleRejected: true, rejectedFrameRejected: true });
    await page.locator("#export-button:not([disabled])").waitFor({ timeout: 30_000 });
    await page.locator("#export-button").evaluate((button) => { button.click(); button.click(); button.click(); });
    await Promise.race([saved, new Promise((_, reject) => setTimeout(() => reject(new Error("原生重选帧导出回调未触发")), 30_000))]);
    const verified = verifier.validateDecisions(loaded.dataset, exportedValue);
    assert.equal(verified.rows.length, loaded.dataset.items.length);
    assert.equal(nativeSaveCalls, 1);
    assert.equal(browserDownloads, 0);
    assert.match(await page.locator("#message").textContent(), /保存成功：tmp\/portrait-pilot\/test\/portrait-pilot-frame-reselection\.json/);
    assert.match(await page.locator("#export-button").textContent(), /已保存/);
    process.stdout.write(`${JSON.stringify({
      status: "portrait_frame_reselection_edge_verified",
      rows: loaded.dataset.items.length,
      candidates: loaded.dataset.counts.candidateCount,
      vectorFramesVisible: true,
      rejectedCurrentFrameDisabled: true,
      localStorageIsolated: true,
      staleImportRejected: true,
      rejectedFrameImportRejected: true,
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
