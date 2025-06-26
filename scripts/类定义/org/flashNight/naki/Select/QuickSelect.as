// ============================================================================
// QuickSelect - 高性能快速选择算法模块
// ----------------------------------------------------------------------------
// 
// 快速选择(Quickselect)是一种高效的选择算法，用于在未排序的数组中寻找第k小的元素。
// 它基于快速排序的分治思想，但只递归处理包含目标元素的那一半，从而达到平均O(N)的时间复杂度。
//
// 核心特性：
// 1. 平均时间复杂度 O(N)，最坏情况 O(N²)
// 2. 原地操作，空间复杂度 O(1)
// 3. 三数取中优化，避免最坏情况
// 4. 支持自定义比较函数，适用于任意类型
// 5. 分区副作用：完成后数组被分为小于、等于、大于目标值的三部分
//
// 适用场景：
// - 寻找中位数、百分位数等统计量
// - 数组分区操作（如BVH树构建）
// - Top-K问题的高效解决
// - 任何需要部分排序的场景
//
// ============================================================================

/**
 * QuickSelect - 快速选择算法工具类
 * 
 * 提供高效的数组选择和分区操作。与完整排序相比，快速选择算法在只需要
 * 找到特定位置元素时具有显著的性能优势。
 * 
 * 主要功能：
 * - 寻找第k小元素（包括中位数）
 * - 数组分区操作
 * - 支持自定义比较逻辑
 * - 高性能的统计查询
 * 
 * 性能特点：
 * - 平均情况：O(N) 时间，O(1) 空间
 * - 最坏情况：O(N²) 时间（极少发生）
 * - 实际表现：通常比完整排序快3-5倍
 */
class org.flashNight.naki.Select.QuickSelect {

    /**
     * 寻找数组中第k小的元素（基于0的索引）
     * 
     * 这是快速选择算法的主要入口点。算法完成后，数组会被重新排列，
     * 使得第k个位置包含正确的元素，且该位置左侧都是较小的元素，
     * 右侧都是较大的元素。
     * 
     * 算法优势：
     * - 比完整排序快得多，因为只需要部分有序
     * - 原地操作，不需要额外的内存空间
     * - 可以处理任意类型的数据（通过比较函数）
     * 
     * 使用示例：
     * ```actionscript
     * var numbers:Array = [3, 1, 4, 1, 5, 9, 2, 6];
     * var median:Number = QuickSelect.select(numbers, 3, 0, 8, numberCompare);
     * // 现在 numbers[3] 是第4小的元素，数组已被分区
     * ```
     * 
     * @param arr         要操作的数组，会被原地修改
     * @param k           目标元素的索引（0-based），必须在[start, end)范围内
     * @param start       搜索范围的起始索引（包含）
     * @param end         搜索范围的结束索引（不包含）
     * @param compareFunc 比较函数，定义元素大小关系
     *                    函数签名：function(a, b):Number
     *                    返回值：< 0 表示 a < b，> 0 表示 a > b，= 0 表示 a == b
     * @return 第k小的元素值
     * 
     * 前提条件：
     * - start <= k < end
     * - arr 不为 null 且长度足够
     * - compareFunc 提供一致的比较结果
     * 
     * 副作用：
     * - 数组元素顺序会被改变
     * - 完成后 arr[0...k-1] <= arr[k] <= arr[k+1...end-1]
     */
    public static function select(arr:Array, k:Number, start:Number, end:Number, compareFunc:Function):Object {
        // 输入验证
        if (arr == null || k < start || k >= end) {
            return null;
        }
        
        // 转换为包含式边界进行内部处理
        var low:Number = start;
        var high:Number = end - 1;
        
        // 迭代式快速选择主循环
        // 每次迭代都会缩小搜索范围，直到找到目标位置
        while (high > low) {
            // 执行分区操作，获取pivot的最终位置
            var pivotIndex:Number = partition(arr, low, high, compareFunc);
            
            if (pivotIndex == k) {
                // 找到目标位置，选择完成
                break;
            } else if (pivotIndex > k) {
                // 目标在左半部分，缩小搜索范围
                high = pivotIndex - 1;
            } else {
                // 目标在右半部分，缩小搜索范围
                low = pivotIndex + 1;
            }
        }
        
        return arr[k];
    }

    /**
     * 便捷方法：寻找整个数组的第k小元素
     * 
     * 这是select方法的简化版本，自动处理整个数组范围。
     * 适用于大多数常见的使用场景。
     * 
     * @param arr         要操作的数组
     * @param k           目标元素的索引（0-based）
     * @param compareFunc 比较函数
     * @return 第k小的元素值
     */
    public static function selectKth(arr:Array, k:Number, compareFunc:Function):Object {
        if (arr == null || arr.length == 0) {
            return null;
        }
        return select(arr, k, 0, arr.length, compareFunc);
    }

    /**
     * 便捷方法：寻找数组的中位数
     * 
     * 自动计算中位数位置并返回对应元素。对于偶数长度的数组，
     * 返回下中位数（第n/2个元素，0-based）。
     * 
     * @param arr         要操作的数组
     * @param compareFunc 比较函数
     * @return 中位数元素
     */
    public static function median(arr:Array, compareFunc:Function):Object {
        if (arr == null || arr.length == 0) {
            return null;
        }
        var medianIndex:Number = Math.floor((arr.length - 1) / 2);
        return select(arr, medianIndex, 0, arr.length, compareFunc);
    }

    // ========================================================================
    // 内部实现方法
    // ========================================================================

    /**
     * Lomuto分区方案实现
     * 
     * 这是快速选择算法的核心分区操作。使用Lomuto分区方案，
     * 结合三数取中优化，提供稳定高效的分区性能。
     * 
     * 算法步骤：
     * 1. 三数取中选择最优pivot
     * 2. 将数组分为 <= pivot 和 > pivot 两部分
     * 3. 将pivot放到正确位置
     * 4. 返回pivot的最终位置
     * 
     * 三数取中优化：
     * 从low、mid、high三个位置选择中位数作为pivot，
     * 大大降低了在有序数据上遇到最坏情况的概率。
     * 
     * @param arr         要分区的数组
     * @param low         分区范围起始（包含）
     * @param high        分区范围结束（包含）
     * @param compareFunc 比较函数
     * @return pivot元素的最终位置
     */
    private static function partition(arr:Array, low:Number, high:Number, compareFunc:Function):Number {
        // 三数取中法选择pivot，避免最坏情况
        var mid:Number = low + Math.floor((high - low) / 2);
        
        // 对三个候选位置进行排序：low <= mid <= high
        if (compareFunc(arr[mid], arr[low]) < 0) {
            swap(arr, mid, low);
        }
        if (compareFunc(arr[high], arr[low]) < 0) {
            swap(arr, high, low);
        }
        if (compareFunc(arr[mid], arr[high]) < 0) {
            swap(arr, mid, high);
        }
        
        // 选择high位置的元素作为pivot（经过三数取中优化）
        var pivot:Object = arr[high];
        
        // Lomuto分区的核心实现
        var i:Number = low - 1; // 小于等于pivot区域的边界
        
        for (var j:Number = low; j < high; j++) {
            if (compareFunc(arr[j], pivot) <= 0) {
                i++;
                swap(arr, i, j);
            }
        }
        
        // 将pivot放到正确位置
        swap(arr, i + 1, high);
        
        return i + 1;
    }

    /**
     * 高效的元素交换操作
     * 
     * 使用经典的三变量交换法，安全地交换数组中两个位置的元素。
     * 
     * @param arr 要操作的数组
     * @param i   第一个元素索引
     * @param j   第二个元素索引
     */
    private static function swap(arr:Array, i:Number, j:Number):Void {
        var temp:Object = arr[i];
        arr[i] = arr[j];
        arr[j] = temp;
    }

    // ========================================================================
    // 工具方法和常用比较函数
    // ========================================================================

    /**
     * 数字比较函数
     * 
     * 提供标准的数字大小比较，可直接用于Number类型数组的快速选择。
     * 
     * @param a 第一个数字
     * @param b 第二个数字
     * @return 比较结果：a - b
     */
    public static function numberCompare(a:Number, b:Number):Number {
        return a - b;
    }

    /**
     * 字符串比较函数
     * 
     * 提供标准的字符串字典序比较，可直接用于String类型数组的快速选择。
     * 
     * @param a 第一个字符串
     * @param b 第二个字符串
     * @return 比较结果
     */
    public static function stringCompare(a:String, b:String):Number {
        if (a < b) return -1;
        if (a > b) return 1;
        return 0;
    }

    /**
     * 反向数字比较函数
     * 
     * 提供逆序的数字比较，用于寻找第k大元素而不是第k小元素。
     * 
     * @param a 第一个数字
     * @param b 第二个数字
     * @return 比较结果：b - a
     */
    public static function reverseNumberCompare(a:Number, b:Number):Number {
        return b - a;
    }
}