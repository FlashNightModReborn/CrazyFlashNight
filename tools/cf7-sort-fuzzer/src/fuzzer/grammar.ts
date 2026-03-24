/**
 * 参数化语法生成器 — 基于模板 + 连续参数空间
 */

import { LCG } from "../shared/lcg.js";

export interface GeneratedInput {
  array: number[];
  template: string;
  params: Record<string, number>;
}

/** 生成 nearSorted 变体: sorted + perturbRate% 随机交换 */
export function genNearSorted(
  n: number,
  order: "asc" | "desc",
  perturbRate: number,
  rng: LCG
): GeneratedInput {
  const arr = new Array<number>(n);
  for (let i = 0; i < n; i++) arr[i] = order === "asc" ? i : n - i;
  const k = Math.max(1, Math.round(n * perturbRate));
  for (let i = 0; i < k; i++) {
    const a = rng.next() % n;
    const b = rng.next() % n;
    const t = arr[a]; arr[a] = arr[b]; arr[b] = t;
  }
  return { array: arr, template: "nearSorted", params: { order: order === "asc" ? 1 : -1, perturbRate } };
}

/** 生成平台结构: k 个唯一值, 各重复 n/k 次 */
export function genPlateau(
  n: number,
  k: number,
  order: "asc" | "desc" | "random",
  rng: LCG
): GeneratedInput {
  const arr = new Array<number>(n);
  const blockSize = Math.floor(n / k);
  for (let i = 0; i < n; i++) {
    arr[i] = Math.floor(i / blockSize);
    if (arr[i] >= k) arr[i] = k - 1;
  }
  if (order === "desc") arr.reverse();
  else if (order === "random") {
    // Fisher-Yates shuffle
    for (let i = n - 1; i > 0; i--) {
      const j = rng.next() % (i + 1);
      const t = arr[i]; arr[i] = arr[j]; arr[j] = t;
    }
  }
  return { array: arr, template: "plateau", params: { k, order: order === "asc" ? 1 : order === "desc" ? -1 : 0 } };
}

/** 生成 mountain 变体: 上升到 peakPos 再下降, skew 控制值域偏移 */
export function genMountain(
  n: number,
  peakPos: number, // [0, 1] — 峰值位置比例
  allUnique: boolean,
): GeneratedInput {
  const arr = new Array<number>(n);
  const peak = Math.floor(n * peakPos);
  for (let i = 0; i <= peak && i < n; i++) arr[i] = i + 1;
  for (let i = peak + 1; i < n; i++) {
    arr[i] = allUnique
      ? n - (i - peak) + 1  // 全唯一: 从 n 往下递减
      : peak - (i - peak);  // 有重复: 镜像递减
  }
  return { array: arr, template: "mountain", params: { peakPos, allUnique: allUnique ? 1 : 0 } };
}

/** 生成拼接结构: sorted + random + sorted */
export function genComposite(
  n: number,
  sortedFrac: number, // sorted 段占比 (0-1)
  rng: LCG,
): GeneratedInput {
  const arr = new Array<number>(n);
  const seg = Math.round(n * sortedFrac / 2);
  const mid = n - seg * 2;
  for (let i = 0; i < seg; i++) arr[i] = i;
  for (let i = seg; i < seg + mid; i++) arr[i] = rng.next() % (n * 2);
  for (let i = seg + mid; i < n; i++) arr[i] = i;
  return { array: arr, template: "composite", params: { sortedFrac } };
}

/** 生成周期性: i % period */
export function genPeriodic(n: number, period: number): GeneratedInput {
  const arr = new Array<number>(n);
  for (let i = 0; i < n; i++) arr[i] = i % period;
  return { array: arr, template: "periodic", params: { period } };
}

/** McIlroy adversarial sort — 构造最坏情况输入 */
export function genAdversarial(n: number): GeneratedInput {
  // 对最左 pivot + Hoare 分区的对抗性构造:
  // 全唯一的已排序输入即为最坏情况
  const arr = new Array<number>(n);
  for (let i = 0; i < n; i++) arr[i] = i;
  return { array: arr, template: "adversarial", params: { strategy: 0 } };
}

/** 反向全唯一 — 另一种最坏情况 */
export function genAdversarialReverse(n: number): GeneratedInput {
  const arr = new Array<number>(n);
  for (let i = 0; i < n; i++) arr[i] = n - i;
  return { array: arr, template: "adversarial_reverse", params: { strategy: 1 } };
}
