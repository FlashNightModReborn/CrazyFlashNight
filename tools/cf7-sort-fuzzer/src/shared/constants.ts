/** 预筛选阈值：predictedRisk < DISCARD 的候选直接丢弃 */
export const DISCARD_THRESHOLD = 2.0;

/**
 * 预筛选阈值：predictedRisk >= LABEL 的候选进入 Flash 标注池
 *
 * Phase 0 校准：organPipe 模型 risk=3.08 但 Flash 实测安全 (11ms)。
 * Hoare 分区对重复值的右指针扫描导致模型高估比较次数，
 * 但实际执行受益于分支预测/缓存效果，wall-clock 远低于模型预期。
 * 因此阈值从 3.0 上调到 5.0，避免将此类"模型偏高但实际安全"的输入误送入标注池。
 */
export const LABEL_THRESHOLD = 5.0;

/** 训练标签阈值：Flash severity >= 此值 → INTRO */
export const SEVERITY_INTRO_THRESHOLD = 5.0;

/** 默认数组大小 */
export const DEFAULT_N = 10000;

/** 默认 LCG 种子 */
export const DEFAULT_SEED = 12345;

/** 多 seed 稳定性测试用的种子集 */
export const STABILITY_SEEDS = [12345, 54321, 99999, 77777, 31415, 271828, 141421, 173205];
