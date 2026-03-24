/**
 * 分布生成器 — 与 SortRouterTest.as generateArray() 1:1 对齐
 *
 * 所有随机分布使用相同的 LCG 种子，确保与 AS2 结果完全一致。
 */

import { LCG } from "./lcg.js";

/** 所有已知分布名 */
export const ALL_DISTRIBUTIONS = [
  "random", "sorted", "reverse", "allEqual",
  "twoValues", "threeValues", "fewUnique5", "fewUnique10",
  "organPipe", "sawTooth20", "sawTooth100",
  "nearSorted1", "nearSorted5", "nearSorted10",
  "nearReverse1", "nearReverse5",
  "sortedTailRand", "sortedMidRand",
  "descPlateaus", "descPlateaus30", "descPlateaus31",
  "mountain", "valley",
  "pushFront", "pushBack",
] as const;

export type DistributionName = (typeof ALL_DISTRIBUTIONS)[number];

/**
 * 生成指定分布的数组。
 * rng 在调用前必须已设置到正确种子。
 */
export function generateArray(sz: number, dist: string, rng: LCG): number[] {
  const arr = new Array<number>(sz);
  let i: number;
  const half = sz >> 1;

  switch (dist) {
    case "random":
      for (i = 0; i < sz; i++) arr[i] = rng.next() % (sz * 2);
      break;
    case "sorted":
      for (i = 0; i < sz; i++) arr[i] = i;
      break;
    case "reverse":
      for (i = 0; i < sz; i++) arr[i] = sz - i;
      break;
    case "allEqual":
      for (i = 0; i < sz; i++) arr[i] = 42;
      break;
    case "twoValues":
      for (i = 0; i < sz; i++) arr[i] = i % 2;
      break;
    case "threeValues":
      for (i = 0; i < sz; i++) arr[i] = i % 3;
      break;
    case "fewUnique5":
      for (i = 0; i < sz; i++) arr[i] = rng.next() % 5;
      break;
    case "fewUnique10":
      for (i = 0; i < sz; i++) arr[i] = rng.next() % 10;
      break;
    case "organPipe":
      for (i = 0; i < half; i++) arr[i] = i;
      for (i = half; i < sz; i++) arr[i] = sz - 1 - i;
      break;
    case "sawTooth20":
      for (i = 0; i < sz; i++) arr[i] = i % 20;
      break;
    case "sawTooth100":
      for (i = 0; i < sz; i++) arr[i] = i % 100;
      break;
    case "nearSorted1":
      for (i = 0; i < sz; i++) arr[i] = i;
      swapRandom(arr, sz, 0.01, rng);
      break;
    case "nearSorted5":
      for (i = 0; i < sz; i++) arr[i] = i;
      swapRandom(arr, sz, 0.05, rng);
      break;
    case "nearSorted10":
      for (i = 0; i < sz; i++) arr[i] = i;
      swapRandom(arr, sz, 0.10, rng);
      break;
    case "nearReverse1":
      for (i = 0; i < sz; i++) arr[i] = sz - i;
      swapRandom(arr, sz, 0.01, rng);
      break;
    case "nearReverse5":
      for (i = 0; i < sz; i++) arr[i] = sz - i;
      swapRandom(arr, sz, 0.05, rng);
      break;
    case "sortedTailRand": {
      const cutoff = Math.round(sz * 0.9);
      for (i = 0; i < cutoff; i++) arr[i] = i;
      for (i = cutoff; i < sz; i++) arr[i] = rng.next() % (sz * 2);
      break;
    }
    case "sortedMidRand": {
      const seg = Math.round(sz * 0.45);
      const mid = sz - seg - seg;
      for (i = 0; i < seg; i++) arr[i] = i;
      for (i = seg; i < seg + mid; i++) arr[i] = rng.next() % (sz * 2);
      for (i = seg + mid; i < sz; i++) arr[i] = i;
      break;
    }
    case "descPlateaus":
      makePlateaus(arr, sz, 25);
      break;
    case "descPlateaus30":
      makePlateaus(arr, sz, 30);
      break;
    case "descPlateaus31":
      makePlateaus(arr, sz, 31);
      break;
    case "mountain":
      for (i = 0; i < half; i++) arr[i] = i + 1;
      for (i = half; i < sz; i++) arr[i] = sz - (i - half);
      break;
    case "valley":
      for (i = 0; i < half; i++) arr[i] = half - i;
      for (i = half; i < sz; i++) arr[i] = i - half;
      break;
    case "pushFront":
      arr[0] = sz;
      for (i = 1; i < sz; i++) arr[i] = i;
      break;
    case "pushBack":
      for (i = 0; i < sz - 1; i++) arr[i] = i + 1;
      arr[sz - 1] = 0;
      break;
    default:
      // fallback: random
      for (i = 0; i < sz; i++) arr[i] = rng.next() % (sz * 2);
  }

  return arr;
}

function swapRandom(arr: number[], sz: number, rate: number, rng: LCG): void {
  const k = Math.max(1, Math.round(sz * rate));
  for (let i = 0; i < k; i++) {
    const j = rng.next() % sz;
    const t = rng.next() % sz;
    const v = arr[j];
    arr[j] = arr[t];
    arr[t] = v;
  }
}

function makePlateaus(arr: number[], sz: number, numValues: number): void {
  const plateauSize = Math.floor(sz / numValues);
  for (let i = 0; i < sz; i++) {
    arr[i] = numValues - Math.floor(i / plateauSize);
    if (arr[i] < 1) arr[i] = 1;
  }
}
