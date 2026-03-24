/**
 * Flash Player native Array.sort(NUMERIC) 的忠实 TS 复现
 *
 * 基于 Phase 0 探测确认的算法参数：
 * - Pivot: 最左元素 (arr[low])
 * - Partition: Hoare 双指针
 * - 无三路分区、无 insertion sort cutoff、无内省深度限制
 * - 迭代式（显式栈代替递归）
 *
 * 参考: Ruffle AVM1 array.rs qsort()
 *
 * 重复值对 Hoare 分区的隐式均衡化效果:
 * - left 指针找 >= pivot，right 指针找 <= pivot (实际是找 > pivot 然后停)
 * - 重复值使两侧指针都在中间附近停下交换，导致接近中位数分区
 * - 因此全唯一值的有序输入退化(O(n²))，但有重复值的相似结构不退化
 */

export interface SortStats {
  comparisons: number;
  maxDepth: number;
}

/**
 * 模拟 Flash native sort，返回排序后数组和统计信息。
 * 不修改输入数组。
 */
export function nativeSortModel(input: readonly number[]): {
  sorted: number[];
  stats: SortStats;
} {
  const arr = [...input];
  const stats: SortStats = { comparisons: 0, maxDepth: 0 };

  if (arr.length < 2) {
    return { sorted: arr, stats };
  }

  // 迭代式快排，显式栈
  const stack: Array<[number, number]> = [];
  stack.push([0, arr.length - 1]);
  let depth = 0;

  while (stack.length > 0) {
    const [low, high] = stack.pop()!;
    depth = stack.length + 1;
    if (depth > stats.maxDepth) stats.maxDepth = depth;

    if (low >= high) continue;

    // Pivot = leftmost element
    const pivot = arr[low];

    let left = low + 1;
    let right = high;

    // Hoare partition (matching Ruffle's implementation)
    while (true) {
      // Find element >= pivot from the left
      // Ruffle: compare_fn(pivot, item).is_le() means pivot <= item
      while (left < right) {
        stats.comparisons++;
        if (pivot <= arr[left]) break; // pivot <= item means item >= pivot
        left++;
      }

      // Find element < pivot from the right
      // Ruffle: compare_fn(pivot, item).is_gt() means pivot > item
      while (right > low) {
        stats.comparisons++;
        if (pivot > arr[right]) break; // pivot > item means item < pivot
        right--;
      }

      if (left >= right) break;

      // Swap
      const tmp = arr[left];
      arr[left] = arr[right];
      arr[right] = tmp;
    }

    // Place pivot at partition boundary
    const tmp = arr[low];
    arr[low] = arr[right];
    arr[right] = tmp;

    // Push sub-arrays (right first so left is processed first from stack)
    if (right + 1 < high) stack.push([right + 1, high]);
    if (right > 0 && low < right - 1) stack.push([low, right - 1]);
  }

  return { sorted: arr, stats };
}

/**
 * 计算 predictedRisk = comparisons / (n * log2(n))
 */
export function predictedRisk(comparisons: number, n: number): number {
  if (n <= 1) return 0;
  return comparisons / (n * Math.log2(n));
}
