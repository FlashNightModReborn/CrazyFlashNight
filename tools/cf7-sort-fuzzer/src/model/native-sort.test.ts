import { describe, it, expect } from "vitest";
import { nativeSortModel, predictedRisk } from "./native-sort.js";

describe("nativeSortModel", () => {
  it("sorts empty and single-element arrays", () => {
    expect(nativeSortModel([]).sorted).toEqual([]);
    expect(nativeSortModel([42]).sorted).toEqual([42]);
    expect(nativeSortModel([42]).stats.comparisons).toBe(0);
  });

  it("sorts small arrays correctly", () => {
    expect(nativeSortModel([3, 1, 2]).sorted).toEqual([1, 2, 3]);
    expect(nativeSortModel([5, 4, 3, 2, 1]).sorted).toEqual([1, 2, 3, 4, 5]);
    expect(nativeSortModel([1, 2, 3]).sorted).toEqual([1, 2, 3]);
  });

  it("sorts random array correctly", () => {
    const arr = [5, 2, 8, 1, 7, 3, 6, 4];
    expect(nativeSortModel(arr).sorted).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
  });

  it("handles all-equal values", () => {
    const arr = [3, 3, 3, 3, 3];
    const { sorted, stats } = nativeSortModel(arr);
    expect(sorted).toEqual([3, 3, 3, 3, 3]);
    // allEqual should have many comparisons (no three-way partition)
    expect(stats.comparisons).toBeGreaterThan(0);
  });

  // 验证与 Flash 探针数据的比较次数一致性
  // Flash probe 数据: [CMP_SEQ] 行的比较计数
  describe("comparison count matches Flash probes", () => {
    const flashProbeData: Array<{ label: string; arr: number[]; flashCount: number }> = [
      { label: "asc3", arr: [1, 2, 3], flashCount: 4 },
      { label: "desc3", arr: [3, 2, 1], flashCount: 3 },
      { label: "mid3", arr: [2, 3, 1], flashCount: 5 },
      { label: "asc5", arr: [1, 2, 3, 4, 5], flashCount: 13 },
      { label: "desc5", arr: [5, 4, 3, 2, 1], flashCount: 11 },
      { label: "pipe5", arr: [1, 3, 5, 3, 1], flashCount: 13 },
      { label: "eq5", arr: [3, 3, 3, 3, 3], flashCount: 13 },
      { label: "asc8", arr: [1, 2, 3, 4, 5, 6, 7, 8], flashCount: 34 },
      { label: "rand8", arr: [5, 2, 8, 1, 7, 3, 6, 4], flashCount: 22 },
      {
        label: "asc16",
        arr: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16],
        flashCount: 134,
      },
    ];

    for (const { label, arr, flashCount } of flashProbeData) {
      it(`${label}: comparisons = ${flashCount}`, () => {
        const { stats } = nativeSortModel(arr);
        expect(stats.comparisons).toBe(flashCount);
      });
    }
  });

  // 验证退化/安全分类与 Flash wall-clock 一致
  describe("degradation pattern matches Flash benchmarks", () => {
    function makeSorted(n: number): number[] {
      return Array.from({ length: n }, (_, i) => i);
    }

    function makeMountain(n: number): number[] {
      const half = n >> 1;
      const arr = new Array(n);
      for (let i = 0; i < half; i++) arr[i] = i + 1;
      for (let i = half; i < n; i++) arr[i] = n - (i - half);
      return arr;
    }

    function makeOrganPipe(n: number): number[] {
      const half = n >> 1;
      const arr = new Array(n);
      for (let i = 0; i < half; i++) arr[i] = i;
      for (let i = half; i < n; i++) arr[i] = n - 1 - i;
      return arr;
    }

    function makeAllEqual(n: number): number[] {
      return Array.from({ length: n }, () => 42);
    }

    const N = 10000;

    it("sorted n=10000 is catastrophic (risk > 3)", () => {
      const { stats } = nativeSortModel(makeSorted(N));
      const risk = predictedRisk(stats.comparisons, N);
      expect(risk).toBeGreaterThan(3);
    });

    it("mountain n=10000 is catastrophic (risk > 3)", () => {
      const { stats } = nativeSortModel(makeMountain(N));
      const risk = predictedRisk(stats.comparisons, N);
      expect(risk).toBeGreaterThan(3);
    });

    it("organPipe n=10000 is moderate risk in model but safe in Flash", () => {
      // Model gives risk ~3.08 (comparisons ~3x nlogn) due to Hoare's
      // right-pointer scanning through duplicate values.
      // But Flash measures 11ms (safe!) — branch prediction + cache effects
      // make the constant factor much smaller for this pattern.
      // This means LABEL_THRESHOLD must be > 3.0 to avoid false positives.
      const { stats } = nativeSortModel(makeOrganPipe(N));
      const risk = predictedRisk(stats.comparisons, N);
      // Model risk should be moderate (2-5), NOT catastrophic (>100)
      expect(risk).toBeGreaterThan(2);
      expect(risk).toBeLessThan(10);
    });

    it("allEqual n=10000 is catastrophic (risk > 3)", () => {
      const { stats } = nativeSortModel(makeAllEqual(N));
      const risk = predictedRisk(stats.comparisons, N);
      expect(risk).toBeGreaterThan(3);
    });
  });
});
