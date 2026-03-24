/**
 * 成本敏感 CART 决策树训练器
 *
 * splitScore = giniGain / featureCost
 * 确保决策树优先使用低成本特征。
 */

import { TreeNode, TrainingSample, FEATURE_COSTS } from "./types.js";

export interface CartConfig {
  maxDepth: number;
  minSamplesLeaf: number;
  /** bad 样本权重倍数 */
  badWeight: number;
}

const DEFAULT_CONFIG: CartConfig = {
  maxDepth: 5,
  minSamplesLeaf: 3,
  badWeight: 10,
};

/** 训练决策树 */
export function trainCART(
  data: TrainingSample[],
  featureNames: string[],
  config: Partial<CartConfig> = {}
): TreeNode {
  const cfg = { ...DEFAULT_CONFIG, ...config };
  return buildNode(data, featureNames, 0, cfg);
}

function buildNode(
  data: TrainingSample[],
  features: string[],
  depth: number,
  cfg: CartConfig
): TreeNode {
  const introCount = data.filter(d => d.label === "intro").length;
  const nativeCount = data.length - introCount;
  const badRate = data.length > 0 ? introCount / data.length : 0;

  // 叶子条件
  if (depth >= cfg.maxDepth || data.length < cfg.minSamplesLeaf * 2 || introCount === 0 || nativeCount === 0) {
    return {
      label: introCount >= nativeCount ? "intro" : "native",
      samples: data.length,
      badRate,
    };
  }

  // 寻找最佳分裂
  let bestScore = -Infinity;
  let bestFeature = "";
  let bestThreshold = 0;
  let bestLeftData: TrainingSample[] = [];
  let bestRightData: TrainingSample[] = [];

  const parentGini = weightedGini(data, cfg.badWeight);

  for (const feat of features) {
    const cost = FEATURE_COSTS[feat] ?? 1;
    const values = data.map(d => d.features[feat]).sort((a, b) => a - b);

    // 取去重后的中点作为候选阈值
    const thresholds = new Set<number>();
    for (let i = 1; i < values.length; i++) {
      if (values[i] !== values[i - 1]) {
        thresholds.add((values[i] + values[i - 1]) / 2);
      }
    }

    for (const thresh of thresholds) {
      const left = data.filter(d => d.features[feat] <= thresh);
      const right = data.filter(d => d.features[feat] > thresh);

      if (left.length < cfg.minSamplesLeaf || right.length < cfg.minSamplesLeaf) continue;

      const leftGini = weightedGini(left, cfg.badWeight);
      const rightGini = weightedGini(right, cfg.badWeight);
      const totalWeight = weightedCount(left, cfg.badWeight) + weightedCount(right, cfg.badWeight);
      const splitGini = (weightedCount(left, cfg.badWeight) * leftGini +
                         weightedCount(right, cfg.badWeight) * rightGini) / totalWeight;
      const gain = parentGini - splitGini;

      // 成本敏感: gain / cost
      const score = gain / cost;

      if (score > bestScore) {
        bestScore = score;
        bestFeature = feat;
        bestThreshold = thresh;
        bestLeftData = left;
        bestRightData = right;
      }
    }
  }

  if (bestScore <= 0 || bestFeature === "") {
    return {
      label: introCount >= nativeCount ? "intro" : "native",
      samples: data.length,
      badRate,
    };
  }

  return {
    feature: bestFeature,
    threshold: bestThreshold,
    featureCost: FEATURE_COSTS[bestFeature],
    left: buildNode(bestLeftData, features, depth + 1, cfg),
    right: buildNode(bestRightData, features, depth + 1, cfg),
    samples: data.length,
    badRate,
  };
}

function weightedGini(data: TrainingSample[], badWeight: number): number {
  if (data.length === 0) return 0;
  let wIntro = 0, wNative = 0;
  for (const d of data) {
    if (d.label === "intro") wIntro += badWeight;
    else wNative += 1;
  }
  const total = wIntro + wNative;
  if (total === 0) return 0;
  const pIntro = wIntro / total;
  const pNative = wNative / total;
  return 1 - pIntro * pIntro - pNative * pNative;
}

function weightedCount(data: TrainingSample[], badWeight: number): number {
  let w = 0;
  for (const d of data) {
    w += d.label === "intro" ? badWeight : 1;
  }
  return w;
}

/** 用决策树预测 */
export function predict(tree: TreeNode, features: Record<string, number>): "intro" | "native" {
  if (tree.label !== undefined) return tree.label;
  const val = features[tree.feature!];
  if (val <= tree.threshold!) {
    return predict(tree.left!, features);
  }
  return predict(tree.right!, features);
}

/** 打印决策树为人类可读文本 */
export function printTree(node: TreeNode, indent: number = 0): string {
  const pad = "  ".repeat(indent);
  if (node.label !== undefined) {
    return `${pad}→ ${node.label.toUpperCase()} (n=${node.samples}, badRate=${(node.badRate! * 100).toFixed(0)}%)`;
  }
  const lines = [
    `${pad}if ${node.feature} <= ${formatThreshold(node.threshold!)} [cost=L${costToLayer(node.featureCost!)}]:`,
    printTree(node.left!, indent + 1),
    `${pad}else (${node.feature} > ${formatThreshold(node.threshold!)}):`,
    printTree(node.right!, indent + 1),
  ];
  return lines.join("\n");
}

function formatThreshold(t: number): string {
  return Number.isInteger(t) ? String(t) : t.toFixed(4);
}

function costToLayer(cost: number): string {
  if (cost <= 1) return "0";
  if (cost <= 2) return "1";
  if (cost <= 4) return "2";
  return "3";
}
