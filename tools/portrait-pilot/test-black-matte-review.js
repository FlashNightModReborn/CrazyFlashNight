#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const verifier = require("./verify-black-matte-review");

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
  if (index < 0 || !argv[index + 1]) throw new Error("用法：node tools/portrait-pilot/test-black-matte-review.js --batch <black matte batch>");
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
    await page.exposeFunction("savePortraitBlackMatteReview", async (value) => {
      nativeSaveCalls += 1;
      exportedValue = value;
      await new Promise((resolve) => setTimeout(resolve, 75));
      resolveSaved(value);
      return { path: "tmp/portrait-pilot/test/portrait-pilot-black-matte-decisions.json", archivePath: "tmp/portrait-pilot/test/black-matte-exports/test.json" };
    });
    const dataPath = `/${path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/")}`;
    const pageUrl = `${server.url}launcher/web/modules/portrait-pilot-review/dev/black-matte.html?data=${encodeURIComponent(dataPath)}`;
    const batchWebPath = `/${path.relative(ROOT, loaded.batchRoot).replaceAll("\\", "/")}`;
    const rejectedDataPaths = {
      outOfScopeDataPathRejected: "/launcher/README.md",
      dotDotTraversalRejected: `${batchWebPath}/../launcher/README.md`,
      encodedTraversalRejected: "/tmp/portrait-pilot/%2e%2e/launcher/README.md",
      backslashDataPathRejected: `${batchWebPath}\\black-matte-review-data.json`,
      wrongSuffixRejected: `${batchWebPath}/portrait-pilot-black-matte-decisions.json`,
      doubleSlashRejected: `${batchWebPath}//black-matte-review-data.json`,
      nulDataPathRejected: `${batchWebPath}/${String.fromCharCode(0)}black-matte-review-data.json`,
    };
    const rejectedDataPathChecks = {};
    const invalidPage = await browser.newPage();
    for (const [check, badDataPath] of Object.entries(rejectedDataPaths)) {
      await invalidPage.goto(
        `${server.url}launcher/web/modules/portrait-pilot-review/dev/black-matte.html?data=${encodeURIComponent(badDataPath)}`,
        { waitUntil: "load" },
      );
      await invalidPage.locator('#app[data-ready="error"]').waitFor({ timeout: 30_000 });
      assert.match(await invalidPage.locator("#message").textContent(), /页面初始化失败：review-data 路径非法/, `${check}：非法 data 路径未被拒绝`);
      rejectedDataPathChecks[check] = true;
    }
    await invalidPage.close();
    await page.goto(pageUrl, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator(".matte-row").count(), 1);
    assert.equal(await page.locator(".original-card").count(), 2);
    assert.equal(await page.locator(".matte-card").count(), 6);
    assert.equal(await page.locator(".matte-card .preview-strip img").count(), 18);
    await page.locator(".matte-card .candidate-link img").first().waitFor({ state: "visible" });
    assert.equal(await page.locator(".matte-card .candidate-link img").first().evaluate((image) => image.complete && image.naturalWidth === 512 && image.naturalHeight === 512), true);

    const item = loaded.dataset.items[0];
    const recommended = item.candidates.find((candidate) => candidate.role === "proposal" && candidate.recommended);
    await page.locator(`[data-candidate-id="${recommended.candidateId}"] .select-matte`).click();
    assert.equal(await page.locator('.matte-row[data-reviewed="true"]').count(), 1);
    const storageKey = await page.evaluate(() => window.__portraitBlackMatteTest.storageKey);
    assert.ok(storageKey.endsWith(loaded.dataset.datasetDigest));
    await page.reload({ waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator('.matte-row[data-reviewed="true"]').count(), 1);

    const validation = await page.evaluate(() => {
      const api = window.__portraitBlackMatteTest;
      const value = api.buildExport();
      api.validateImport(value);
      let staleRejected = false;
      let hashDriftRejected = false;
      try { api.validateImport({ ...value, datasetDigest: "0".repeat(64) }); } catch { staleRejected = true; }
      try {
        const item = api.dataset.items[0];
        api.validateImport({
          ...value,
          choices: { ...value.choices, [item.reviewKey]: { ...value.choices[item.reviewKey], master512Sha256: "0".repeat(64) } },
        });
      } catch { hashDriftRejected = true; }
      return { complete: api.completeDecisions(), staleRejected, hashDriftRejected };
    });
    assert.deepEqual(validation, { complete: true, staleRejected: true, hashDriftRejected: true });
    await page.locator("#export-button:not([disabled])").waitFor({ timeout: 30_000 });
    await page.locator("#export-button").evaluate((button) => { button.click(); button.click(); button.click(); });
    await Promise.race([saved, new Promise((_, reject) => setTimeout(() => reject(new Error("原生透明化导出回调未触发")), 30_000))]);
    const verified = verifier.validateDecisions(loaded.dataset, exportedValue);
    assert.equal(verified.rows.length, 1);
    assert.equal(nativeSaveCalls, 1);
    assert.equal(browserDownloads, 0);
    assert.match(await page.locator("#message").textContent(), /保存成功：tmp\/portrait-pilot\/test\/portrait-pilot-black-matte-decisions\.json/);
    assert.match(await page.locator("#export-button").textContent(), /已保存/);
    process.stdout.write(`${JSON.stringify({
      status: "portrait_black_matte_edge_verified",
      rows: 1,
      originals: 2,
      candidates: 6,
      previewPyramidsVisible: true,
      localStorageIsolated: true,
      staleImportRejected: true,
      hashDriftRejected: true,
      ...rejectedDataPathChecks,
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
