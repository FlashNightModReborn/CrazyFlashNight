/**
 * 训练入口 — npm run train
 *
 * 使用已知 Flash benchmark 数据标注训练集，训练决策树，
 * 输出管线优化建议报告。
 */

import { LCG } from "../src/shared/lcg.js";
import { generateArray, ALL_DISTRIBUTIONS } from "../src/shared/distributions.js";
import { extractFeatures, Features } from "../src/features/extractors.js";
import { trainCART, predict, printTree } from "../src/tree/cart.js";
import { TrainingSample } from "../src/tree/types.js";
import { STABILITY_SEEDS } from "../src/shared/constants.js";
import { nativeSortModel, predictedRisk } from "../src/model/native-sort.js";

// ============================================================
// Flash benchmark 数据 (来自 SortProbe + NativeSortProfile)
// severity = native_ms / intro_ms
// ============================================================
// 全部来自 Phase 0 实测数据 (SortProbe Batch A + B, n=10000, 1 rep)
const FLASH_BENCHMARKS: Record<string, { native: number; intro: number }> = {
  // Batch A (安全分布)
  random:         { native: 13,   intro: 139 },
  fewUnique5:     { native: 283,  intro: 27 },
  fewUnique10:    { native: 146,  intro: 35 },
  organPipe:      { native: 18,   intro: 162 },
  sawTooth100:    { native: 27,   intro: 62 },
  nearSorted1:    { native: 108,  intro: 59 },
  nearSorted5:    { native: 33,   intro: 67 },
  nearSorted10:   { native: 16,   intro: 77 },
  nearReverse1:   { native: 38,   intro: 99 },
  nearReverse5:   { native: 20,   intro: 115 },
  sortedTailRand: { native: 40,   intro: 124 },
  sortedMidRand:  { native: 39,   intro: 116 },
  valley:         { native: 18,   intro: 152 },
  // Batch B (危险分布)
  sorted:         { native: 1385, intro: 17 },
  reverse:        { native: 1365, intro: 23 },
  allEqual:       { native: 1375, intro: 15 },
  twoValues:      { native: 688,  intro: 15 },
  threeValues:    { native: 462,  intro: 18 },
  sawTooth20:     { native: 78,   intro: 44 },
  descPlateaus:   { native: 701,  intro: 22 },
  descPlateaus30: { native: 681,  intro: 22 },
  descPlateaus31: { native: 669,  intro: 22 },
  mountain:       { native: 1387, intro: 72 },
  pushFront:      { native: 1357, intro: 73 },
  pushBack:       { native: 701,  intro: 84 },
};

// severity >= 5 → INTRO (保守阈值)
const SEVERITY_THRESHOLD = 5;

function getSeverity(dist: string): number {
  const b = FLASH_BENCHMARKS[dist];
  if (!b || b.intro === 0) return Infinity;
  return b.native / b.intro;
}

function getLabel(dist: string): "intro" | "native" {
  return getSeverity(dist) >= SEVERITY_THRESHOLD ? "intro" : "native";
}

// ============================================================
// 生成训练数据
// ============================================================
console.log("Generating training data...");

const N = 10000;
const trainingData: TrainingSample[] = [];

for (const dist of ALL_DISTRIBUTIONS) {
  const severity = getSeverity(dist);
  const label = getLabel(dist);

  // 多 seed 生成
  for (const seed of STABILITY_SEEDS) {
    const rng = new LCG(seed);
    const arr = generateArray(N, dist, rng);
    const features = extractFeatures(arr);
    trainingData.push({
      features: features as unknown as Record<string, number>,
      label,
      severity,
      dist,
    });
  }
}

console.log(`Training samples: ${trainingData.length}`);
console.log(`  INTRO: ${trainingData.filter(d => d.label === "intro").length}`);
console.log(`  NATIVE: ${trainingData.filter(d => d.label === "native").length}`);

// ============================================================
// 训练决策树
// ============================================================
const featureNames = [
  "n", "endGap", "endGapNorm",
  "sAsc", "sDesc", "sEq", "turns", "sampleOrder", "uniq", "dominantDir",
  "headViol", "tailViol",
  "antiCnt",
];

console.log("\nTraining decision tree...");
const tree = trainCART(trainingData, featureNames, {
  maxDepth: 5,
  minSamplesLeaf: 3,
  badWeight: 10,
});

// ============================================================
// 评估
// ============================================================
console.log("\n=== Decision Tree ===");
console.log(printTree(tree));

console.log("\n=== Predictions vs Labels ===");
let correct = 0, falseNeg = 0, falsePos = 0;
const mismatches: Array<{ dist: string; predicted: string; actual: string; severity: number }> = [];

for (const sample of trainingData) {
  const predicted = predict(tree, sample.features);
  if (predicted === sample.label) {
    correct++;
  } else {
    if (predicted === "native" && sample.label === "intro") falseNeg++;
    else falsePos++;
    mismatches.push({
      dist: sample.dist,
      predicted,
      actual: sample.label,
      severity: sample.severity,
    });
  }
}

const accuracy = (correct / trainingData.length * 100).toFixed(1);
console.log(`Accuracy: ${accuracy}% (${correct}/${trainingData.length})`);
console.log(`False negatives (bad→native, DANGEROUS): ${falseNeg}`);
console.log(`False positives (safe→intro, wastes perf): ${falsePos}`);

if (mismatches.length > 0) {
  console.log("\nMismatches:");
  // deduplicate by dist
  const seen = new Set<string>();
  for (const m of mismatches) {
    if (seen.has(m.dist)) continue;
    seen.add(m.dist);
    console.log(`  ${m.dist}: predicted=${m.predicted}, actual=${m.actual}, severity=${m.severity.toFixed(1)}`);
  }
}

// ============================================================
// 与当前 SortRouter 对比
// ============================================================
console.log("\n=== Current SortRouter Comparison ===");
console.log("Known routing decisions from SortRouterTest:");

const KNOWN_ROUTES: Record<string, string> = {
  random: "native", organPipe: "native", sawTooth100: "native",
  sorted: "intro", reverse: "intro", allEqual: "intro",
  twoValues: "intro", sawTooth20: "intro",
  pushFront: "intro", pushBack: "intro",
  nearSorted1: "intro", nearSorted5: "native",
  sortedTailRand: "native", sortedMidRand: "native",
  descPlateaus: "intro", descPlateaus30: "intro", descPlateaus31: "intro",
  mountain: "intro", valley: "native",
};

let routerMatch = 0, routerTotal = 0;
for (const [dist, expectedRoute] of Object.entries(KNOWN_ROUTES)) {
  const rng = new LCG(12345);
  const arr = generateArray(N, dist, rng);
  const features = extractFeatures(arr);
  const treePrediction = predict(tree, features as unknown as Record<string, number>);
  routerTotal++;
  if (treePrediction === expectedRoute) routerMatch++;
  else {
    console.log(`  DIVERGE: ${dist} — tree=${treePrediction}, router=${expectedRoute}`);
  }
}
console.log(`Tree agrees with current router: ${routerMatch}/${routerTotal}`);

// ============================================================
// 管线优化建议
// ============================================================
console.log("\n=== Pipeline Optimization Report ===");
console.log("Decision tree structure suggests the following pipeline stages:");
console.log("(See tree above for exact thresholds)\n");

// 提取树使用的特征集
const usedFeatures = new Set<string>();
function collectFeatures(node: typeof tree) {
  if (node.feature) {
    usedFeatures.add(node.feature);
    if (node.left) collectFeatures(node.left);
    if (node.right) collectFeatures(node.right);
  }
}
collectFeatures(tree);
console.log(`Features used by tree: ${[...usedFeatures].join(", ")}`);
console.log(`Features NOT used: ${featureNames.filter(f => !usedFeatures.has(f)).join(", ")}`);

// 模型 vs Flash 校准信息
console.log("\n=== Model Calibration Notes ===");
console.log("Model blind spot: Hoare partition's duplicate-value balancing");
console.log("  - organPipe: model risk=3.08, Flash severity=0.11 (SAFE)");
console.log("  - ascending plateaus: model risk=376, but Flash may be safe for high-k");
console.log("  → Model overestimates risk for inputs with many duplicate values");
console.log("  → LABEL_THRESHOLD raised to 5.0 to compensate");
