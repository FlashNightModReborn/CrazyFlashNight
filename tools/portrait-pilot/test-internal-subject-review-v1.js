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

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function main() {
  const batchArgument = process.argv[2];
  if (!batchArgument) throw new Error("用法：node tools/portrait-pilot/test-internal-subject-review-v1.js <batch-dir>");
  if (!fs.existsSync(PLAYWRIGHT)) throw new Error("Playwright 未安装");
  const loaded = reviewBuild.loadBatch(batchArgument);
  const reviewPath = path.join(loaded.batchRoot, "internal-subject-review-data.json");
  const dataset = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
  reviewBuild.verifyReviewDataset(dataset, { supersession: loaded.supersession });
  const { chromium } = require(PLAYWRIGHT);
  const server = await startServer(ROOT, 0);
  const browser = await chromium.launch({ executablePath: findEdge(), headless: true });
  let captured = null;
  try {
    const page = await browser.newPage({ viewport: { width: 1680, height: 1000 } });
    await page.exposeFunction("saveInternalSubjectReviewDecisions", async (value) => {
      captured = decisionVerifier.validateDecisions(dataset, value);
      return { path: "test/canonical.json", archivePath: "test/archive.json" };
    });
    const dataPath = `/${path.relative(ROOT, reviewPath).replaceAll("\\", "/")}`;
    const pageUrl = `${server.url}launcher/web/modules/portrait-pilot-review/dev/internal-subject.html?data=${encodeURIComponent(dataPath)}`;
    const invalidPage = await browser.newPage();
    await invalidPage.goto(
      `${server.url}launcher/web/modules/portrait-pilot-review/dev/internal-subject.html?data=${encodeURIComponent("/launcher/README.md")}`,
      { waitUntil: "load" },
    );
    await invalidPage.locator('#app[data-ready="error"]').waitFor({ timeout: 30_000 });
    assert(/review-data 路径非法/.test(await invalidPage.locator("#load-error").textContent()), "越界 review-data 未被拒绝");
    const encodedTraversal = "/tmp/portrait-pilot/%2e%2e/launcher/README.md";
    await invalidPage.goto(
      `${server.url}launcher/web/modules/portrait-pilot-review/dev/internal-subject.html?data=${encodeURIComponent(encodedTraversal)}`,
      { waitUntil: "load" },
    );
    await invalidPage.locator('#app[data-ready="error"]').waitFor({ timeout: 30_000 });
    assert(/review-data 路径非法/.test(await invalidPage.locator("#load-error").textContent()), "编码 traversal review-data 未被拒绝");
    await invalidPage.close();
    await page.goto(pageUrl, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert(await page.locator(".review-card").count() === dataset.items.length, "审核卡片数量不闭合");
    assert(await page.locator(".candidate").count() === dataset.counts.candidateCount, "候选按钮数量不闭合");
    assert(await page.locator('.candidate[aria-pressed="true"]').count() === 0, "模型建议被静默预选");
    assert(await page.locator('.none-choice[aria-pressed="true"]').count() === 0, "无有效主体被静默预选");
    assert(await page.locator(".review-card.is-focus").count() === dataset.counts.highlightedForHuman, "模型分歧高亮数量不闭合");
    const cards = page.locator(".review-card");
    for (let index = 0; index < dataset.items.length; index += 1) {
      await cards.nth(index).locator(".candidate").first().click();
    }
    await cards.first().locator(".decision-note").fill("browser harness persistence note");
    assert(await page.locator("#resolved-count").textContent() === String(dataset.items.length), "完整裁决进度未更新");
    assert(await page.locator("#save-decisions").isEnabled(), "完整裁决后保存按钮未启用");
    await page.reload({ waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert(await page.locator("#resolved-count").textContent() === String(dataset.items.length), "重载后自动暂存未恢复");
    assert(await page.locator(".decision-note").first().inputValue() === "browser harness persistence note", "重载后备注未恢复");
    await page.locator("#save-decisions").click();
    await page.waitForFunction(() => document.querySelector("#commit-title")?.textContent === "决策已保存导出");
    assert(captured?.decisions?.length === dataset.items.length, "保存 payload 未闭合");
    await page.evaluate(() => localStorage.clear());
    process.stdout.write(`${JSON.stringify({
      status: "internal_subject_review_browser_harness_passed",
      reviewDigest: dataset.reviewDigest,
      identities: dataset.items.length,
      candidates: dataset.counts.candidateCount,
      modelPreselectionCount: 0,
      outOfScopeDataPathRejected: true,
      encodedTraversalRejected: true,
      persistedAcrossReload: true,
      savePayloadValidated: true,
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
