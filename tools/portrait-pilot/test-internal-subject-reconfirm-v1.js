#!/usr/bin/env node
"use strict";

const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const PLAYWRIGHT = path.join(ROOT, "launcher", "perf", "node_modules", "playwright");
const { startServer, stopServer } = require(path.join(ROOT, "launcher", "perf", "lib", "server"));
const reviewBuild = require("./build-internal-subject-review-v1");
const decisionVerifier = require("./verify-internal-subject-review-decisions-v1");

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

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

async function main() {
  const batchArgument = process.argv[2];
  const reviewKey = process.argv[3];
  if (!batchArgument || !reviewKey) throw new Error("用法：node tools/portrait-pilot/test-internal-subject-reconfirm-v1.js <batch-dir> <reviewKey>");
  const loaded = reviewBuild.loadBatch(batchArgument);
  const reviewPath = path.join(loaded.batchRoot, "internal-subject-review-data.json");
  const decisionsPath = path.join(loaded.batchRoot, "internal-subject-human-decisions.json");
  const dataset = JSON.parse(fs.readFileSync(reviewPath, "utf8"));
  const decisions = JSON.parse(fs.readFileSync(decisionsPath, "utf8"));
  reviewBuild.verifyReviewDataset(dataset, { supersession: loaded.supersession });
  decisionVerifier.validateDecisions(dataset, decisions);
  const item = dataset.items.find((entry) => entry.reviewKey === reviewKey);
  if (!item) throw new Error(`reviewKey 不存在：${reviewKey}`);
  const recommendedId = item.model.proposal.candidateId;
  if (!recommendedId) throw new Error("测试目标没有模型候选");

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
    const canonicalPath = `/${path.relative(ROOT, decisionsPath).replaceAll("\\", "/")}`;
    const query = new URLSearchParams({ data: dataPath, decisions: canonicalPath, reviewKey });
    const invalidPage = await browser.newPage();
    const invalidQuery = new URLSearchParams({ data: "/launcher/README.md", decisions: canonicalPath, reviewKey });
    await invalidPage.goto(
      `${server.url}launcher/web/modules/portrait-pilot-review/dev/internal-subject-reconfirm.html?${invalidQuery}`,
      { waitUntil: "load" },
    );
    await invalidPage.locator('#app[data-ready="error"]').waitFor({ timeout: 30_000 });
    assert(/review-data 路径非法/.test(await invalidPage.locator("#load-error").textContent()), "越界 review-data 未被拒绝");
    const encodedTraversal = "/tmp/portrait-pilot/%2e%2e/launcher/README.md";
    const traversalQuery = new URLSearchParams({ data: encodedTraversal, decisions: canonicalPath, reviewKey });
    await invalidPage.goto(
      `${server.url}launcher/web/modules/portrait-pilot-review/dev/internal-subject-reconfirm.html?${traversalQuery}`,
      { waitUntil: "load" },
    );
    await invalidPage.locator('#app[data-ready="error"]').waitFor({ timeout: 30_000 });
    assert(/review-data 路径非法/.test(await invalidPage.locator("#load-error").textContent()), "编码 traversal review-data 未被拒绝");
    await invalidPage.close();
    await page.goto(`${server.url}launcher/web/modules/portrait-pilot-review/dev/internal-subject-reconfirm.html?${query}`, { waitUntil: "load" });
    await page.locator('#app[data-ready="true"]').waitFor({ timeout: 30_000 });
    assert(await page.locator(".card").count() === 1, "复核页必须只显示一项");
    assert(await page.locator(".candidate.is-prior").count() === 1, "旧决定没有作为未确认提示显示");
    assert(await page.locator('.candidate[aria-pressed="true"]').count() === 0, "旧决定被静默当作本次确认");
    assert(await page.locator("#save").isDisabled(), "没有重新点击时保存按钮必须禁用");
    await page.locator(`.candidate[data-candidate-id="${recommendedId}"]`).click();
    assert(await page.locator("#save").isEnabled(), "重新点击后保存按钮未启用");
    await page.locator("#save").click();
    await page.waitForFunction(() => document.querySelector("#commit-title")?.textContent === "修正已保存导出");
    assert(captured?.decisions?.length === dataset.items.length, "保存没有保留完整决定集");
    assert(captured.decisions.find((entry) => entry.reviewKey === reviewKey)?.candidateId === recommendedId, "目标修正未写入 payload");
    process.stdout.write(`${JSON.stringify({
      status: "internal_subject_reconfirmation_browser_harness_passed",
      reviewKey,
      untouchedDecisionCount: dataset.items.length - 1,
      outOfScopeDataPathRejected: true,
      encodedTraversalRejected: true,
      explicitReselectionRequired: true,
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
