/**
 * Linear Congruential Generator — 与 AS2 SortRouterTest 完全一致
 *
 * AS2 公式: _seed = (_seed * 1664525 + 1013904223) % 4294967296
 * JS 中 Number 是 float64，对 < 2^53 的整数运算精确，无需 BigInt。
 */

const A = 1664525;
const C = 1013904223;
const M = 4294967296; // 2^32

export class LCG {
  private seed: number;

  constructor(seed: number = 12345) {
    this.seed = seed >>> 0; // 确保无符号 32 位
  }

  /** 返回 [0, 2^32) 的无符号整数，同时推进状态 */
  next(): number {
    this.seed = (this.seed * A + C) % M;
    return this.seed;
  }

  /** 重置种子 */
  reset(seed: number = 12345): void {
    this.seed = seed >>> 0;
  }

  /** 返回 [0, max) 的整数 */
  nextInt(max: number): number {
    return this.next() % max;
  }
}
