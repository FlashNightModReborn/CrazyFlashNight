#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const guidanceVerifier = require("./verify-framing-guidance");

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
  if (index < 0 || !argv[index + 1]) throw new Error("用法：node tools/portrait-pilot/test-framing-guidance.js --batch <guidance batch>");
  return argv[index + 1];
}

async function main() {
  const loaded = guidanceVerifier.loadGuidanceBatch(batchArgument(process.argv.slice(2)));
  const edge = findEdge();
  if (!edge) throw new Error("Microsoft Edge not found");
  const { chromium } = require(PLAYWRIGHT);
  const server = await startServer(ROOT, 0);
  const browser = await chromium.launch({ executablePath: edge, headless: true });
  try {
    const page = await browser.newPage({ viewport: { width: 1680, height: 1000 } });
    let exportedValue = null;
    let nativeSaveCalls = 0;
    let browserDownloads = 0;
    let resolveSaved;
    const saved = new Promise((resolve) => { resolveSaved = resolve; });
    page.on("download", () => { browserDownloads += 1; });
    await page.exposeFunction("savePortraitFramingGuidance", async (value) => {
      nativeSaveCalls += 1;
      exportedValue = value;
      await new Promise((resolve) => setTimeout(resolve, 75));
      resolveSaved(value);
      return {
        path: "tmp/portrait-pilot/test/portrait-pilot-framing-guidance.json",
        archivePath: "tmp/portrait-pilot/test/guidance-exports/portrait-pilot-framing-guidance-test.json",
      };
    });
    const dataPath = `/${path.relative(ROOT, loaded.dataPath).replaceAll("\\", "/")}`;
    const pageUrl = `${server.url}launcher/web/modules/portrait-pilot-review/dev/framing-guidance.html?data=${encodeURIComponent(dataPath)}`;
    await page.goto(pageUrl, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator(".guidance-card").count(), loaded.dataset.items.length);
    assert.equal(await page.locator(".source-choice-buttons button").count(), loaded.dataset.items.length * 2);
    const firstItem = loaded.dataset.items[0];
    const card = page.locator(".guidance-card").first();
    const initial = await page.evaluate((reviewKey) => {
      const state = window.__portraitFramingGuidanceTest.states[reviewKey];
      const preview = document.querySelector(".preview-80").toDataURL();
      return { state: JSON.parse(JSON.stringify(state)), preview };
    }, firstItem.reviewKey);
    assert.equal(initial.state.sourceRole, firstItem.preferredRoleHint || "proposal");
    assert.equal(initial.state.confirmed, false);

    const initialChoice = firstItem.choices.find((choice) => choice.sourceRole === initial.state.sourceRole);
    const initialSide = (initial.state.cropBox[2] - initial.state.cropBox[0]) * initialChoice.candidateWidth;
    const minimumSide = Math.max(
      48,
      initialChoice.minimumCandidateCropSide,
      Math.min(initialChoice.candidateWidth, initialChoice.candidateHeight) * 0.1,
    );
    const maximumSide = Math.min(initialChoice.candidateWidth * 2, initialChoice.candidateHeight * 2);
    const zoomDirection = initialSide > minimumSide * 1.01 ? "in" : "out";
    if (zoomDirection === "out" && initialSide >= maximumSide * 0.99) {
      throw new Error("框选初始尺寸同时命中放大与缩小边界，无法验证交互变化");
    }
    await card.locator(zoomDirection === "in" ? ".zoom-in" : ".zoom-out").click();
    const changed = await page.evaluate((reviewKey) => {
      const api = window.__portraitFramingGuidanceTest;
      const state = api.states[reviewKey];
      const item = api.dataset.items.find((entry) => entry.reviewKey === reviewKey);
      const choice = item.choices.find((entry) => entry.sourceRole === state.sourceRole);
      return {
        state: JSON.parse(JSON.stringify(state)),
        pixelSide: (state.cropBox[2] - state.cropBox[0]) * choice.candidateWidth,
        preview: document.querySelector(".preview-80").toDataURL(),
      };
    }, firstItem.reviewKey);
    if (zoomDirection === "in") assert.ok(changed.pixelSide < initialSide);
    else assert.ok(changed.pixelSide > initialSide);
    assert.notEqual(changed.preview, initial.preview);
    assert.equal(changed.state.confirmed, false);

    await card.locator(".confirm-guidance").click();
    assert.equal(await card.getAttribute("data-confirmed"), "true");
    const storageKey = await page.evaluate(() => window.__portraitFramingGuidanceTest.storageKey);
    assert.ok(storageKey.endsWith(loaded.dataset.guidanceDigest));
    await page.reload({ waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert.equal(await page.locator(".guidance-card").first().getAttribute("data-confirmed"), "true");

    const pendingConfirmButtons = page.locator('.guidance-card[data-confirmed="false"] .confirm-guidance');
    for (let index = 0; index < loaded.dataset.items.length && await pendingConfirmButtons.count() > 0; index += 1) {
      await pendingConfirmButtons.first().click();
    }
    const unconfirmed = await page.locator('.guidance-card[data-confirmed="false"]').evaluateAll((cards) =>
      cards.map((candidate) => ({
        reviewKey: candidate.dataset.reviewKey || candidate.querySelector("h2")?.textContent || "<unknown>",
        state: window.__portraitFramingGuidanceTest.states[candidate.dataset.reviewKey],
        message: document.getElementById("message")?.textContent || "",
      })),
    );
    assert.deepEqual(unconfirmed, []);

    const validation = await page.evaluate(() => {
      const api = window.__portraitFramingGuidanceTest;
      const guidance = Object.fromEntries(api.dataset.items.map((item) => [item.reviewKey, api.entryFromState(item, api.states[item.reviewKey])]));
      const value = {
        schema: api.dataset.guidanceSchema,
        batchId: api.dataset.batchId,
        guidanceDigest: api.dataset.guidanceDigest,
        parentReceiptDigest: api.dataset.parent.receiptDigest,
        complete: true,
        exportedAt: new Date().toISOString(),
        guidance,
      };
      api.validateImport(value);
      let staleRejected = false;
      try {
        api.validateImport({ ...value, guidanceDigest: "0".repeat(64) });
      } catch {
        staleRejected = true;
      }
      return { complete: api.completeStateMap(), staleRejected };
    });
    assert.deepEqual(validation, { complete: true, staleRejected: true });

    await page.locator("#export-button:not([disabled])").waitFor({ timeout: 30_000 });
    await page.locator("#export-button").evaluate((button) => {
      button.click();
      button.click();
      button.click();
    });
    await Promise.race([saved, new Promise((_, reject) => setTimeout(() => reject(new Error("原生框选导出回调未触发")), 30_000))]);
    const verified = guidanceVerifier.validateGuidance(loaded.dataset, exportedValue);
    assert.equal(verified.rows.length, loaded.dataset.items.length);
    const firstKey = loaded.dataset.items[0].reviewKey;
    assert.throws(
      () => guidanceVerifier.validateGuidance(loaded.dataset, {
        ...exportedValue,
        guidance: {
          ...exportedValue.guidance,
          [firstKey]: { ...exportedValue.guidance[firstKey], sourceCandidateSha256: "0".repeat(64) },
        },
      }),
      /来源角色、候选或 hash 不闭合/,
    );
    assert.throws(
      () => guidanceVerifier.validateGuidance(loaded.dataset, {
        ...exportedValue,
        guidance: {
          ...exportedValue.guidance,
          [firstKey]: { ...exportedValue.guidance[firstKey], cropBox: [0.1, 0.1, 0.8, 0.3] },
        },
      }),
      /不是像素正方形/,
    );
    assert.equal(nativeSaveCalls, 1);
    assert.equal(browserDownloads, 0);
    assert.match(await page.locator("#message").textContent(), /保存成功：tmp\/portrait-pilot\/test\/portrait-pilot-framing-guidance\.json/);
    assert.match(await page.locator("#export-button").textContent(), /已保存/);
    process.stdout.write(`${JSON.stringify({
      status: "portrait_framing_guidance_edge_verified",
      rows: loaded.dataset.items.length,
      guidanceDigest: loaded.dataset.guidanceDigest,
      preferredRoleApplied: initial.state.sourceRole,
      zoomChangedPreview: true,
      pixelSquareValidated: true,
      localStorageIsolated: true,
      staleImportRejected: true,
      wrongCandidateHashRejected: true,
      nonSquareCropRejected: true,
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
