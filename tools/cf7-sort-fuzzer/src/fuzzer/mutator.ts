/**
 * 突变策略 — 从已知 bad 输入出发做局部变异
 */

import { LCG } from "../shared/lcg.js";

/** 随机交换 k 对元素 */
export function mutateSwap(arr: number[], k: number, rng: LCG): number[] {
  const result = [...arr];
  const n = result.length;
  for (let i = 0; i < k; i++) {
    const a = rng.next() % n;
    const b = rng.next() % n;
    const t = result[a]; result[a] = result[b]; result[b] = t;
  }
  return result;
}

/** 用随机值替换 [start, start+len) 段 */
export function mutateSegment(
  arr: number[],
  start: number,
  len: number,
  rng: LCG
): number[] {
  const result = [...arr];
  const n = result.length;
  const end = Math.min(start + len, n);
  for (let i = start; i < end; i++) {
    result[i] = rng.next() % (n * 2);
  }
  return result;
}

/** 拼接两个数组各取一半 */
export function mutateSplice(a: number[], b: number[]): number[] {
  const halfA = Math.floor(a.length / 2);
  const halfB = Math.floor(b.length / 2);
  return [...a.slice(0, halfA), ...b.slice(halfB)];
}

/** 局部反转 [start, end) */
export function mutateReverse(arr: number[], start: number, end: number): number[] {
  const result = [...arr];
  let l = start, r = Math.min(end - 1, result.length - 1);
  while (l < r) {
    const t = result[l]; result[l] = result[r]; result[r] = t;
    l++; r--;
  }
  return result;
}

/** 在指定位置插入一段有序序列 */
export function mutateInsertSorted(
  arr: number[],
  pos: number,
  len: number,
  startVal: number
): number[] {
  const insert = Array.from({ length: len }, (_, i) => startVal + i);
  return [...arr.slice(0, pos), ...insert, ...arr.slice(pos + len)];
}
