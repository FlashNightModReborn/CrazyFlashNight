import fs from "node:fs";
import path from "node:path";

const [, , manifestArgument, queueArgument] = process.argv;
if (!manifestArgument) {
  console.error("usage: node validate-h3-batch.mjs <manifest.json> [queue.tsv]");
  process.exit(64);
}

const tokenPattern = /^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$/;
const errors = [];

function add(condition, message) {
  if (!condition) errors.push(message);
}

function readUtf8(filePath) {
  return fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
}

function isPositiveInteger(value) {
  return Number.isInteger(value) && value > 0;
}

const manifestPath = path.resolve(manifestArgument);
let manifest;
try {
  manifest = JSON.parse(readUtf8(manifestPath));
} catch (error) {
  console.error(`manifest parse failed: ${error.message}`);
  process.exit(2);
}

add(manifest.schemaVersion === 1, "schemaVersion must be 1");
add(tokenPattern.test(manifest.runId ?? ""), "runId must be a safe token");
add(tokenPattern.test(manifest.remoteLeaf ?? ""), "remoteLeaf must be a safe token");
add(tokenPattern.test(manifest.controllerLogPrefix ?? ""), "controllerLogPrefix must be a safe token");
add(tokenPattern.test(manifest.reviewStem ?? ""), "reviewStem must be a safe token");

const generation = manifest.generation ?? {};
add(typeof generation.modelId === "string" && generation.modelId.length > 0, "generation.modelId is required");
add(isPositiveInteger(generation.steps), "generation.steps must be a positive integer");
add(Number.isInteger(generation.audioSeconds) && generation.audioSeconds >= 0, "generation.audioSeconds must be a non-negative integer");

const raw = manifest.rawProfile ?? {};
add(isPositiveInteger(raw.width), "rawProfile.width must be a positive integer");
add(isPositiveInteger(raw.height), "rawProfile.height must be a positive integer");
add(isPositiveInteger(raw.frames), "rawProfile.frames must be a positive integer");
add(/^\d+\/\d+$/.test(raw.fpsRate ?? ""), "rawProfile.fpsRate must look like 24/1");

const target = manifest.targetProfile ?? {};
add(typeof target.enabled === "boolean", "targetProfile.enabled must be boolean");
if (target.enabled) {
  add(
    target.kind === "center-crop-1280x736-to-1024x576",
    "enabled targetProfile.kind must be center-crop-1280x736-to-1024x576",
  );
  add(
    raw.width === 1280 && raw.height === 736 && raw.fpsRate === "24/1",
    "the built-in target profile requires 1280x736 raw video at 24/1 fps",
  );
}

const jobs = Array.isArray(manifest.jobs) ? [...manifest.jobs] : [];
add(jobs.length >= 1 && jobs.length <= 6, "jobs must contain 1 to 6 entries");
jobs.sort((left, right) => left.order - right.order);
const slugs = new Set();
for (let index = 0; index < jobs.length; index += 1) {
  const job = jobs[index] ?? {};
  const expectedOrder = index + 1;
  add(job.order === expectedOrder, `jobs[${index}].order must be ${expectedOrder}`);
  add(tokenPattern.test(job.slug ?? ""), `jobs[${index}].slug must be a safe token`);
  add(!slugs.has(job.slug), `duplicate slug: ${job.slug}`);
  slugs.add(job.slug);
  add(Number.isInteger(job.seed) && job.seed >= 0, `jobs[${index}].seed must be a non-negative integer`);
  add(
    typeof job.reviewLabel === "string" &&
      job.reviewLabel.length >= 1 &&
      job.reviewLabel.length <= 80 &&
      !/[:'\\%\[\];,\t\r\n]/.test(job.reviewLabel),
    `jobs[${index}].reviewLabel contains characters unsafe for TSV or FFmpeg drawtext`,
  );
  const expectedPipeline = `pipelines/${manifest.remoteLeaf}/${job.slug}.vpipeline`;
  add(job.remotePipeline === expectedPipeline, `jobs[${index}].remotePipeline must be ${expectedPipeline}`);
}

if (queueArgument) {
  const queuePath = path.resolve(queueArgument);
  const rows = readUtf8(queuePath)
    .split(/\r?\n/)
    .map((line) => line.trimEnd())
    .filter((line) => line.length > 0 && !line.startsWith("#"))
    .map((line, index) => {
      const columns = line.split("\t");
      if (columns.length !== 4) {
        errors.push(`queue row ${index + 1} must have exactly four tab-separated fields`);
      }
      return {
        order: Number(columns[0]),
        slug: columns[1],
        seed: Number(columns[2]),
        reviewLabel: columns[3],
      };
    });
  add(rows.length === jobs.length, "queue row count must equal manifest job count");
  for (let index = 0; index < Math.min(rows.length, jobs.length); index += 1) {
    for (const field of ["order", "slug", "seed", "reviewLabel"]) {
      add(rows[index][field] === jobs[index][field], `queue row ${index + 1} differs from manifest field ${field}`);
    }
  }
}

if (errors.length > 0) {
  for (const error of errors) console.error(`ERROR: ${error}`);
  process.exit(1);
}

console.log(`VALID runId=${manifest.runId} jobs=${jobs.length} raw=${raw.width}x${raw.height}/${raw.frames}@${raw.fpsRate}`);
