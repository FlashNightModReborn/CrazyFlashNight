#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const PILOT_ROOT = path.join(ROOT, "tmp", "portrait-pilot");
const PLAYWRIGHT_ROOT = path.join(ROOT, "launcher", "perf", "node_modules", "playwright");
const PLAYWRIGHT_PACKAGE = path.join(PLAYWRIGHT_ROOT, "package.json");

class VectorRenderError extends Error {}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableValue(value[key])]));
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableValue(value));
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function sha256File(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

function findEdge() {
  const candidates = [
    path.join(process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)", "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(process.env.ProgramFiles || "C:\\Program Files", "Microsoft", "Edge", "Application", "msedge.exe"),
    process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, "Microsoft", "Edge", "Application", "msedge.exe") : "",
  ];
  const found = candidates.find((candidate) => candidate && fs.existsSync(candidate));
  if (!found) throw new VectorRenderError("Microsoft Edge not found");
  return found;
}

function parseArgs(argv) {
  const options = { jobs: null, report: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--jobs" || argument === "--report") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) throw new VectorRenderError(`${argument} 缺少值`);
      index += 1;
      if (argument === "--jobs") options.jobs = value;
      if (argument === "--report") options.report = value;
    } else if (argument === "--help") {
      options.help = true;
    } else {
      throw new VectorRenderError(`未知参数：${argument}`);
    }
  }
  return options;
}

function below(candidate, parent, label) {
  const absolute = path.resolve(ROOT, candidate);
  const relative = path.relative(parent, absolute);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new VectorRenderError(`${label} 越出允许目录`);
  }
  return absolute;
}

function verifyArtifact(record, label) {
  if (!record || typeof record.path !== "string" || !Number.isInteger(record.bytes) || typeof record.sha256 !== "string") {
    throw new VectorRenderError(`${label} artifact 记录不闭合`);
  }
  const filePath = below(record.path, ROOT, label);
  if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
    throw new VectorRenderError(`${label} artifact 缺失：${record.path}`);
  }
  if (fs.statSync(filePath).size !== record.bytes || sha256File(filePath) !== record.sha256) {
    throw new VectorRenderError(`${label} artifact 字节闭包不匹配：${record.path}`);
  }
  return filePath;
}

function validateJobs(value) {
  if (
    !value ||
    value.schema !== "cf7.portrait-pilot-vector-render-jobs.v1" ||
    typeof value.batchId !== "string" ||
    typeof value.sourceDigest !== "string" ||
    typeof value.modelReportDigest !== "string" ||
    !Number.isInteger(value.renderSize) ||
    value.renderSize < 1024 ||
    value.renderSize > 4096 ||
    !Array.isArray(value.jobs) ||
    value.jobs.length < 1 ||
    value.jobs.length > 24
  ) {
    throw new VectorRenderError("vector render jobs 顶层合同非法");
  }
  const ids = new Set();
  for (const job of value.jobs) {
    if (
      !job ||
      typeof job.jobId !== "string" ||
      ids.has(job.jobId) ||
      !Array.isArray(job.viewBox) ||
      job.viewBox.length !== 4 ||
      job.viewBox.some((entry) => typeof entry !== "number" || !Number.isFinite(entry)) ||
      job.viewBox[2] <= 0 ||
      job.viewBox[3] <= 0 ||
      Math.abs(job.viewBox[2] - job.viewBox[3]) > 0.0001 ||
      typeof job.outputPath !== "string"
    ) {
      throw new VectorRenderError(`vector render job 非法：${job?.jobId || "unknown"}`);
    }
    ids.add(job.jobId);
    job.sourcePath = verifyArtifact(job.sourceSvg, `vector source ${job.jobId}`);
    job.outputAbsolute = below(job.outputPath, PILOT_ROOT, `vector output ${job.jobId}`);
    if (fs.existsSync(job.outputAbsolute)) {
      throw new VectorRenderError(`vector output 已存在，拒绝覆盖：${job.outputPath}`);
    }
  }
  return value;
}

function sourceEvidence(edgePath) {
  const files = [__filename, PLAYWRIGHT_PACKAGE].map((filePath) => ({
    path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
    bytes: fs.statSync(filePath).size,
    sha256: sha256File(filePath),
  }));
  return {
    version: "portrait-pilot-vector-renderer-v1",
    nodeVersion: process.version,
    platform: process.platform,
    arch: process.arch,
    files,
    sourceClosureDigest: sha256Bytes(stableStringify(files)),
    edge: {
      path: edgePath,
      bytes: fs.statSync(edgePath).size,
      sha256: sha256File(edgePath),
    },
  };
}

async function renderOne(page, job, renderSize) {
  const svg = fs.readFileSync(job.sourcePath, "utf8");
  await page.setContent(`<style>html,body{margin:0;background:transparent;overflow:hidden}svg{display:block;width:${renderSize}px!important;height:${renderSize}px!important}</style>${svg}`);
  const locator = page.locator("svg");
  if (await locator.count() !== 1) throw new VectorRenderError(`SVG 根不唯一：${job.jobId}`);
  await locator.evaluate((element, viewBox) => {
    element.setAttribute("viewBox", viewBox.join(" "));
    element.setAttribute("preserveAspectRatio", "none");
    element.setAttribute("width", String(viewBox[2]));
    element.setAttribute("height", String(viewBox[3]));
  }, job.viewBox);
  fs.mkdirSync(path.dirname(job.outputAbsolute), { recursive: true });
  await locator.screenshot({ path: job.outputAbsolute, omitBackground: true, animations: "disabled" });
  const stat = fs.statSync(job.outputAbsolute);
  return {
    jobId: job.jobId,
    sourceSvg: job.sourceSvg,
    viewBox: job.viewBox,
    output: {
      path: path.relative(ROOT, job.outputAbsolute).replaceAll("\\", "/"),
      bytes: stat.size,
      sha256: sha256File(job.outputAbsolute),
    },
  };
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help || !options.jobs || !options.report) {
    process.stdout.write("用法：node tools/portrait-pilot/render-svg-selections.js --jobs <jobs.json> --report <report.json>\n");
    if (!options.help) process.exitCode = 1;
    return;
  }
  if (!fs.existsSync(PLAYWRIGHT_ROOT)) {
    throw new VectorRenderError("缺 Playwright；运行 npm --prefix launcher/perf ci --ignore-scripts");
  }
  const jobsPath = below(options.jobs, PILOT_ROOT, "vector jobs");
  const reportPath = below(options.report, PILOT_ROOT, "vector report");
  if (!fs.existsSync(jobsPath) || !fs.statSync(jobsPath).isFile()) throw new VectorRenderError("vector jobs 文件缺失");
  if (fs.existsSync(reportPath)) throw new VectorRenderError("vector report 已存在，拒绝覆盖");
  const jobs = validateJobs(JSON.parse(fs.readFileSync(jobsPath, "utf8")));
  const edgePath = findEdge();
  const { chromium } = require(PLAYWRIGHT_ROOT);
  const browser = await chromium.launch({ headless: true, executablePath: edgePath });
  const browserVersion = browser.version();
  const startedAt = new Date().toISOString();
  const outputs = [];
  try {
    const page = await browser.newPage({
      viewport: { width: jobs.renderSize, height: jobs.renderSize },
      deviceScaleFactor: 1,
    });
    for (const job of jobs.jobs) outputs.push(await renderOne(page, job, jobs.renderSize));
  } finally {
    await browser.close();
  }
  const report = {
    schema: "cf7.portrait-pilot-vector-render-report.v1",
    status: "vector_supersample_rendered",
    productionReady: false,
    batchId: jobs.batchId,
    sourceDigest: jobs.sourceDigest,
    modelReportDigest: jobs.modelReportDigest,
    startedAt,
    endedAt: new Date().toISOString(),
    renderSize: jobs.renderSize,
    targetMasterSize: 512,
    supersampleFactor: jobs.renderSize / 512,
    controller: sourceEvidence(edgePath),
    browserVersion,
    jobsFile: {
      path: path.relative(ROOT, jobsPath).replaceAll("\\", "/"),
      bytes: fs.statSync(jobsPath).size,
      sha256: sha256File(jobsPath),
    },
    outputs,
    gates: {
      svgSourceHashesClosed: true,
      squareViewBoxApplied: true,
      transparentBackground: true,
      productionWrites: false,
    },
  };
  report.reportDigest = sha256Bytes(stableStringify(report));
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, `${JSON.stringify(report, null, 2)}\n`, { encoding: "utf8", flag: "wx" });
  process.stdout.write(`${JSON.stringify({
    status: report.status,
    report: path.relative(ROOT, reportPath).replaceAll("\\", "/"),
    reportDigest: report.reportDigest,
    outputs: outputs.length,
    supersampleFactor: report.supersampleFactor,
  })}\n`);
}

main().catch((error) => {
  process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
  process.exitCode = 1;
});
