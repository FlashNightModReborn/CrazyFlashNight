/**
 * 分层特征提取器
 *
 * 与 SortRouter.classifyNumeric 中使用的特征 1:1 对齐，
 * 用于训练决策树和分析路由决策。
 */

/** 各层级特征 */
export interface Features {
  // L0: O(1)
  n: number;
  endGap: number;        // |arr[0] - arr[n-1]|
  endGapNorm: number;    // endGap / n

  // L1: O(k=32) 采样
  sAsc: number;          // 采样升序对数
  sDesc: number;         // 采样降序对数
  sEq: number;           // 采样等值对数
  turns: number;         // 方向切换次数
  sampleOrder: number;   // max(sAsc+sEq, sDesc+sEq) / (K-1)
  uniq: number;          // 互素步长采样唯一值数
  dominantDir: number;   // 1=升序主导, -1=降序主导

  // L2: O(probe=256) 局部探测
  headViol: number;      // 首 256 对中的降序违规数
  tailViol: number;      // 尾 256 对中的降序违规数

  // L3: O(n) 全量扫描 (with early exit)
  antiCnt: number;       // 少数方向违规数 (capped at 33 for early exit)
}

const SAMPLE_K = 32;
const PROBE_LEN = 256;
const ANTI_LIMIT = 33; // early exit at 33 (one past the 32 threshold)

/**
 * 提取全部特征。
 * 不修改输入数组。
 */
export function extractFeatures(arr: readonly number[]): Features {
  const n = arr.length;

  // L0
  const endGap = n >= 2 ? Math.abs(arr[0] - arr[n - 1]) : 0;
  const endGapNorm = n >= 2 ? endGap / n : 0;

  // L1: Stage A-1 顺序采样
  let sAsc = 0, sDesc = 0, sEq = 0, turns = 0, dir = 0;
  const bias = (n * 3) >> 3;
  let prev = 0;

  for (let i = 0; i < SAMPLE_K && n >= 2; i++) {
    let idx = ((i * n + bias) >> 5); // floor((i*n+bias)/32)
    if (idx >= n) idx = n - 1;
    const cur = arr[idx];
    if (i > 0) {
      if (cur > prev) {
        sAsc++;
        if (dir === -1) turns++;
        dir = 1;
      } else if (cur < prev) {
        sDesc++;
        if (dir === 1) turns++;
        dir = -1;
      } else {
        sEq++;
      }
    }
    prev = cur;
  }

  // L1: Stage A-2 互素步长采样 cardinality
  let step = (n >> 5) + 1;
  while (gcd(step, n) !== 1) step++;

  const sampleVals: number[] = [];
  let uniq = 0;
  let idx2 = 17 % n;

  for (let i = 0; i < SAMPLE_K && n >= 2; i++) {
    const cur = arr[idx2];
    let dup = false;
    for (let j = 0; j < uniq; j++) {
      if (sampleVals[j] === cur) { dup = true; break; }
    }
    if (!dup) {
      sampleVals[uniq] = cur;
      uniq++;
    }
    idx2 += step;
    if (idx2 >= n) idx2 -= n;
  }

  const samplePairs = SAMPLE_K - 1;
  const sampleOrder = samplePairs > 0
    ? (sAsc > sDesc
      ? (sAsc + sEq) / samplePairs
      : (sDesc + sEq) / samplePairs)
    : 0;

  const dominantDir = sAsc >= sDesc ? 1 : -1;

  // L2: 双端探测
  const probLen = Math.min(PROBE_LEN, n >> 2, n);
  let headViol = 0;
  if (n >= 2) {
    prev = arr[0];
    for (let i = 1; i < probLen; i++) {
      if (arr[i] < prev) headViol++;
      prev = arr[i];
    }
  }

  let tailViol = 0;
  if (n >= 2) {
    const tailStart = n - probLen;
    prev = arr[tailStart];
    for (let i = tailStart + 1; i < n; i++) {
      if (arr[i] < prev) tailViol++;
      prev = arr[i];
    }
  }

  // L3: 全量扫描 (with early exit)
  let antiCnt = 0;
  if (n >= 2) {
    if (dominantDir === 1) {
      // 升序主导：计数 desc 对
      prev = arr[0];
      for (let i = 1; i < n; i++) {
        if (arr[i] < prev) {
          antiCnt++;
          if (antiCnt >= ANTI_LIMIT) break;
        }
        prev = arr[i];
      }
    } else {
      // 降序主导：计数 asc 对
      prev = arr[0];
      for (let i = 1; i < n; i++) {
        if (arr[i] > prev) {
          antiCnt++;
          if (antiCnt >= ANTI_LIMIT) break;
        }
        prev = arr[i];
      }
    }
  }

  return {
    n, endGap, endGapNorm,
    sAsc, sDesc, sEq, turns, sampleOrder, uniq, dominantDir,
    headViol, tailViol,
    antiCnt,
  };
}

function gcd(a: number, b: number): number {
  while (b !== 0) {
    const t = a % b;
    a = b;
    b = t;
  }
  return a < 0 ? -a : a;
}
