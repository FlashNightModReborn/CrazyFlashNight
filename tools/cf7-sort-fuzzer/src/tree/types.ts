/** 决策树节点 */
export interface TreeNode {
  /** 分裂特征名 (undefined for leaf) */
  feature?: string;
  /** 分裂阈值 */
  threshold?: number;
  /** <= threshold 走左子树 */
  left?: TreeNode;
  /** > threshold 走右子树 */
  right?: TreeNode;
  /** 叶子标签 */
  label?: "intro" | "native";
  /** 落入此节点的样本数 */
  samples?: number;
  /** 落入此节点的 bad 样本占比 */
  badRate?: number;
  /** 特征计算成本层级 */
  featureCost?: number;
}

/** 训练样本 */
export interface TrainingSample {
  features: Record<string, number>;
  label: "intro" | "native";
  severity: number;
  dist: string;
}

/** 特征成本定义 */
export const FEATURE_COSTS: Record<string, number> = {
  n: 1, endGap: 1, endGapNorm: 1,
  sAsc: 2, sDesc: 2, sEq: 2, turns: 2, sampleOrder: 2, uniq: 2, dominantDir: 2,
  headViol: 4, tailViol: 4,
  antiCnt: 16,
};
