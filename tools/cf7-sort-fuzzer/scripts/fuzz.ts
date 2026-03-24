/**
 * Fuzzer 入口 — npm run fuzz
 *
 * 运行语法生成 + 突变 fuzzer，输出 top candidates 统计。
 * 所有评估在 TS 模型上完成，无需 Flash。
 */

import { runFuzzer } from "../src/fuzzer/runner.js";
import { LABEL_THRESHOLD, DISCARD_THRESHOLD } from "../src/shared/constants.js";
import { writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
const DATA_DIR = resolve(__dirname, "../data/corpus");
mkdirSync(DATA_DIR, { recursive: true });

console.log(`Thresholds: DISCARD=${DISCARD_THRESHOLD}, LABEL=${LABEL_THRESHOLD}`);
console.log("");

const corpus = runFuzzer({
  n: 10000,
  grammarRounds: 500,
  mutationRounds: 2000,
  mutationsPerSeed: 5,
  seed: 42,
});

console.log("");
console.log("=== Results ===");
console.log(`Total corpus entries: ${corpus.size}`);

const labelCandidates = corpus.all().filter(e => e.risk >= LABEL_THRESHOLD);
console.log(`Candidates for Flash labeling (risk >= ${LABEL_THRESHOLD}): ${labelCandidates.length}`);

// Top 20 candidates
const top = corpus.topN(20);
console.log("\nTop 20 by risk:");
console.log("  risk    template                 params");
console.log("  ------  -----------------------  ------");
for (const entry of top) {
  const riskStr = entry.risk.toFixed(1).padStart(7);
  const tmpl = entry.template.padEnd(24);
  const params = Object.entries(entry.params)
    .map(([k, v]) => `${k}=${typeof v === "number" ? v.toFixed(3) : v}`)
    .join(", ");
  console.log(`  ${riskStr}  ${tmpl} ${params}`);
}

// 分布统计
const byTemplate = new Map<string, { count: number; maxRisk: number }>();
for (const e of corpus.all()) {
  const base = e.template.replace(/^mutant_/, "");
  const stat = byTemplate.get(base) || { count: 0, maxRisk: 0 };
  stat.count++;
  stat.maxRisk = Math.max(stat.maxRisk, e.risk);
  byTemplate.set(base, stat);
}

console.log("\nBy template family:");
for (const [tmpl, stat] of [...byTemplate.entries()].sort((a, b) => b[1].maxRisk - a[1].maxRisk)) {
  console.log(`  ${tmpl.padEnd(24)} count=${String(stat.count).padStart(5)}  maxRisk=${stat.maxRisk.toFixed(1)}`);
}

// 保存语料库
const corpusData = corpus.topN(500).map(e => ({
  template: e.template,
  params: e.params,
  risk: e.risk,
  arrayHash: simpleHash(e.array),
}));

writeFileSync(
  resolve(DATA_DIR, "corpus-summary.json"),
  JSON.stringify(corpusData, null, 2)
);
console.log(`\nCorpus summary saved to data/corpus/corpus-summary.json`);

function simpleHash(arr: number[]): string {
  let h = 0;
  for (let i = 0; i < arr.length; i++) {
    h = ((h << 5) - h + arr[i]) | 0;
  }
  return h.toString(16);
}
