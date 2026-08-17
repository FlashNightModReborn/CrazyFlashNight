#!/usr/bin/env node
"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..", "..");
const DEFAULT_OUTPUT = path.join(ROOT, "tmp", "dialogue-portrait-source-review", "review.html");
const TEMPLATE_PATH = path.join(__dirname, "review-template.html");
const DATA_SCHEMA = "cf7.dialogue-portrait-source-authority-review.v1";
const DECISION_SCHEMA = "cf7.dialogue-portrait-source-authority-decisions.v1";
const DEFAULT_EXPRESSION = "普通";

function sha1(value) {
  return crypto.createHash("sha1").update(value, "utf8").digest("hex");
}

function sha256Buffer(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function decodeXml(value) {
  return String(value)
    .replace(/&#x([0-9a-f]+);/gi, (_, code) => String.fromCodePoint(Number.parseInt(code, 16)))
    .replace(/&#([0-9]+);/g, (_, code) => String.fromCodePoint(Number.parseInt(code, 10)))
    .replaceAll("&quot;", '"')
    .replaceAll("&apos;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">")
    .replaceAll("&amp;", "&");
}

function attributes(fragment) {
  const result = {};
  for (const match of fragment.matchAll(/([A-Za-z_:][\w:.-]*)=(?:"([^"]*)"|'([^']*)')/g)) {
    result[match[1]] = decodeXml(match[2] ?? match[3] ?? "");
  }
  return result;
}

function readExternalNames(filePath) {
  const xml = fs.readFileSync(filePath, "utf8");
  const names = [...xml.matchAll(/<portrait>([\s\S]*?)<\/portrait>/g)]
    .map((match) => decodeXml(match[1]).trim())
    .filter(Boolean);
  if (names.length === 0) throw new Error(`外部立绘清单为空：${filePath}`);
  if (new Set(names).size !== names.length) throw new Error("flashswf/portraits/list.xml 自身包含重复 portrait 名称");
  return names;
}

function readInternalLabels(filePath) {
  const xml = fs.readFileSync(filePath, "utf8");
  const labelsLayer = xml.match(/<DOMLayer\b(?=[^>]*\bname=(?:"Labels Layer"|'Labels Layer'))[^>]*>([\s\S]*?)<\/DOMLayer>/);
  if (!labelsLayer) throw new Error(`找不到对话框肖像 Labels Layer：${filePath}`);
  const labels = [];
  for (const match of labelsLayer[1].matchAll(/<DOMFrame\b([^>]*)>/g)) {
    const attrs = attributes(match[1]);
    const name = String(attrs.name || "").trim();
    if (!name || name.startsWith("--")) continue;
    labels.push({
      name,
      frame: Number.parseInt(attrs.index || "0", 10) + 1,
      duration: Number.parseInt(attrs.duration || "1", 10),
    });
  }
  if (labels.length === 0) throw new Error(`对话框肖像 Labels Layer 没有有效名称：${filePath}`);
  const seen = new Set();
  for (const label of labels) {
    if (seen.has(label.name)) throw new Error(`对话框肖像 Labels Layer 名称重复：${label.name}`);
    seen.add(label.name);
  }
  return labels;
}

function pngRecord(filePath) {
  const content = fs.readFileSync(filePath);
  if (content.length < 24 || content.subarray(0, 8).toString("hex") !== "89504e470d0a1a0a") {
    throw new Error(`不是有效 PNG：${filePath}`);
  }
  return {
    assetPath: path.relative(ROOT, filePath).replaceAll("\\", "/"),
    assetSha256: sha256Buffer(content),
    width: content.readUInt32BE(16),
    height: content.readUInt32BE(20),
    dataUri: `data:image/png;base64,${content.toString("base64")}`,
  };
}

function stableAssetPath(kind, name) {
  const portraitDirectory = `p_${sha1(name).slice(0, 12)}`;
  const expressionFile = `e_${sha1(DEFAULT_EXPRESSION).slice(0, 12)}.png`;
  const relativeParts = [kind, portraitDirectory, expressionFile];
  const productionPath = path.join(ROOT, "launcher", "web", "assets", "dialogue-portraits", ...relativeParts);
  if (fs.existsSync(productionPath)) return productionPath;
  return path.join(ROOT, "tmp", "dialogue-portrait-source-review", "candidates", ...relativeParts);
}

function sourceRecord({ id, label, role, sourcePath, imagePath, frame, duration }) {
  const absoluteSource = path.join(ROOT, ...sourcePath.split("/"));
  if (!fs.existsSync(absoluteSource)) throw new Error(`缺少源文件：${sourcePath}`);
  if (!fs.existsSync(imagePath)) throw new Error(`缺少已烘焙的对照 PNG：${path.relative(ROOT, imagePath)}`);
  return {
    id,
    label,
    role,
    sourcePath,
    sourceSha256: sha256File(absoluteSource),
    expression: DEFAULT_EXPRESSION,
    frame: frame ?? null,
    duration: duration ?? null,
    image: pngRecord(imagePath),
  };
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function buildDataset() {
  const externalListPath = path.join(ROOT, "flashswf", "portraits", "list.xml");
  const internalXflPath = path.join(ROOT, "flashswf", "UI", "对话框界面", "LIBRARY", "对话框肖像.xml");
  const manifestPath = path.join(ROOT, "launcher", "web", "assets", "dialogue-portraits", "manifest.json");
  const bakerPath = path.join(ROOT, "tools", "bake-dialogue-portraits.py");
  const authorityPolicyPath = path.join(ROOT, "tools", "dialogue-portrait-source-review", "authority-policy.json");
  const externalNames = readExternalNames(externalListPath);
  const internalLabels = readInternalLabels(internalXflPath);
  const internalByName = new Map(internalLabels.map((entry) => [entry.name, entry]));
  const collisions = externalNames.filter((name) => internalByName.has(name));
  if (collisions.length === 0) throw new Error("当前没有发现外部清单与内嵌时间轴的同名项");

  const manifestRaw = fs.readFileSync(manifestPath);
  const manifest = JSON.parse(manifestRaw.toString("utf8"));
  const authorityPolicy = JSON.parse(fs.readFileSync(authorityPolicyPath, "utf8"));
  const internalSwfPath = "flashswf/UI/对话框界面.swf";
  const items = collisions.map((name, index) => {
    const internal = internalByName.get(name);
    const manifestEntry = manifest.entries?.[name];
    if (!manifestEntry || typeof manifestEntry.source !== "string") {
      throw new Error(`Web manifest 缺少同名项：${name}`);
    }
    const sources = [
      sourceRecord({
        id: "external-swf",
        label: "外部肖像 SWF",
        role: "Flash 当前运行时来源",
        sourcePath: `flashswf/portraits/${name}.swf`,
        imagePath: stableAssetPath("external", name),
      }),
      sourceRecord({
        id: "dialogue-ui-sprite",
        label: "对话框内嵌时间轴",
        role: "旧内嵌肖像帧",
        sourcePath: internalSwfPath,
        imagePath: stableAssetPath("internal", name),
        frame: internal.frame,
        duration: internal.duration,
      }),
    ];
    return {
      reviewKey: `portrait-${sha1(name).slice(0, 12)}`,
      order: index + 1,
      name,
      flashCurrentSource: "external-swf",
      webCurrentSource: manifestEntry.source,
      policyCurrentSource: authorityPolicy.decisions?.[name] || null,
      webCurrentAsset: manifestEntry.expressions?.[manifestEntry.defaultExpression || DEFAULT_EXPRESSION]?.uri || null,
      webSourcePath: manifestEntry.sourcePath || null,
      diverged: manifestEntry.source !== "external-swf",
      sources,
    };
  });

  const manifestDigest = sha256Buffer(manifestRaw);
  const sourceFiles = [externalListPath, internalXflPath, manifestPath, bakerPath, authorityPolicyPath, __filename, TEMPLATE_PATH].map((filePath) => ({
    path: path.relative(ROOT, filePath).replaceAll("\\", "/"),
    sha256: sha256File(filePath),
  }));
  const digestInput = {
    schema: DATA_SCHEMA,
    sourceFiles,
    items: items.map((item) => ({
      reviewKey: item.reviewKey,
      name: item.name,
      flashCurrentSource: item.flashCurrentSource,
      webCurrentSource: item.webCurrentSource,
      policyCurrentSource: item.policyCurrentSource,
      sources: item.sources.map((source) => ({
        id: source.id,
        sourcePath: source.sourcePath,
        sourceSha256: source.sourceSha256,
        frame: source.frame,
        duration: source.duration,
        assetPath: source.image.assetPath,
        assetSha256: source.image.assetSha256,
      })),
    })),
  };
  const sourceDigest = sha256Buffer(Buffer.from(stableJson(digestInput), "utf8"));
  return {
    schema: DATA_SCHEMA,
    decisionSchema: DECISION_SCHEMA,
    generatedAt: new Date().toISOString(),
    batchId: `dialogue-portrait-authority-${sourceDigest.slice(0, 12)}`,
    sourceDigest,
    manifestDigest,
    productionWrites: false,
    scope: "仅审计会共同进入 dialogue portrait manifest 的外部 SWF 与对话框内嵌时间轴；profile 缩略图不属于该消费链。",
    counts: {
      externalListEntries: externalNames.length,
      internalNamedFrames: internalLabels.length,
      exactNameCollisions: items.length,
      currentWebDivergences: items.filter((item) => item.diverged).length,
    },
    sourceFiles,
    items,
  };
}

function escapeEmbeddedJson(value) {
  return JSON.stringify(value)
    .replaceAll("&", "\\u0026")
    .replaceAll("<", "\\u003c")
    .replaceAll(">", "\\u003e")
    .replaceAll("\u2028", "\\u2028")
    .replaceAll("\u2029", "\\u2029");
}

function renderReview(dataset) {
  const template = fs.readFileSync(TEMPLATE_PATH, "utf8");
  const placeholders = ["__CF7_REVIEW_DATA__", "__CF7_SOURCE_DIGEST__"];
  for (const placeholder of placeholders) {
    if (!template.includes(placeholder)) throw new Error(`复核页模板缺少占位符：${placeholder}`);
  }
  return template
    .replace("__CF7_REVIEW_DATA__", escapeEmbeddedJson(dataset))
    .replaceAll("__CF7_SOURCE_DIGEST__", dataset.sourceDigest);
}

function parseArguments(argv) {
  const args = { output: DEFAULT_OUTPUT, check: false };
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--output") {
      if (!argv[index + 1]) throw new Error("--output 后必须提供路径");
      args.output = path.resolve(ROOT, argv[++index]);
    } else if (value === "--check") {
      args.check = true;
    } else if (value === "--help" || value === "-h") {
      process.stdout.write("用法：node tools/dialogue-portrait-source-review/build-review.js [--output <html>] [--check]\n");
      process.exit(0);
    } else {
      throw new Error(`未知参数：${value}`);
    }
  }
  return args;
}

function run(argv = process.argv.slice(2)) {
  const args = parseArguments(argv);
  const dataset = buildDataset();
  const html = renderReview(dataset);
  if (args.check) {
    if (!fs.existsSync(args.output)) throw new Error(`复核页尚未生成：${args.output}`);
    const current = fs.readFileSync(args.output, "utf8");
    const embeddedDigest = current.match(/<meta name="cf7-review-source-digest" content="([0-9a-f]{64})">/)?.[1];
    if (embeddedDigest !== dataset.sourceDigest) throw new Error("复核页已过期；请重新运行 build-review.js");
  } else {
    fs.mkdirSync(path.dirname(args.output), { recursive: true });
    fs.writeFileSync(args.output, html, "utf8");
  }
  process.stdout.write(`${JSON.stringify({
    status: args.check ? "current" : "generated",
    output: path.relative(ROOT, args.output).replaceAll("\\", "/"),
    sourceDigest: dataset.sourceDigest,
    collisions: dataset.counts.exactNameCollisions,
    webDivergences: dataset.counts.currentWebDivergences,
    productionWrites: dataset.productionWrites,
  }, null, 2)}\n`);
  return { args, dataset, html };
}

if (require.main === module) {
  try {
    run();
  } catch (error) {
    process.stderr.write(`${error && error.stack ? error.stack : String(error)}\n`);
    process.exitCode = 1;
  }
}

module.exports = {
  DATA_SCHEMA,
  DECISION_SCHEMA,
  DEFAULT_OUTPUT,
  ROOT,
  buildDataset,
  renderReview,
  run,
};
