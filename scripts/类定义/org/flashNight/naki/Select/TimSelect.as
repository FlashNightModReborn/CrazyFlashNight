// ============================================================================
// TimSelect - 高性能混合选择算法模块 (BFPRT 实现)
// ----------------------------------------------------------------------------
//
// TimSelect 是一种结合了快速选择 (QuickSelect) 和 BFPRT (Median-of-Medians)
// 的混合算法。它通过在分区不平衡时启用 BFPRT 来选择主元，从而保证了
// 在最坏情况下仍然具有 O(n) 的线性时间复杂度。
//
// 核心特性：
// 1. 平均时间复杂度 O(n)，最坏情况时间复杂度 O(n)。
// 2. 原地操作，空间复杂度 O(1)（不考虑递归栈，迭代实现则为O(1)）。
// 3. 对小规模子问题使用插入选择，效率更高。
// 4. 通过动态检测分区平衡性，智能地在快速的“三数取中”和稳健的“中位数的中位数”
//    之间切换主元选择策略。
// 5. 支持自定义比较函数，适用于任意类型。
//
// 使用示例：
// var arr:Array = [7,3,5,1,9,2,6,4,8];
// var third:Number = TimSelect.selectKth(arr, 2, TimSelect.numberCompare);
// // 返回第 3 小元素 (索引为2)，此处值为 3
//
class org.flashNight.naki.Select.TimSelect {
    /** 插入选择阈值：子问题小于该长度时使用插入排序选择 */
    private static var INSERTION_THRESHOLD:Number = 32;
    /** 分区不平衡检测系数：当单侧长度 < total/UNBALANCED_RATIO 时，认为分区不平衡 */
    private static var UNBALANCED_RATIO:Number = 8;

    /**
     * 主入口：在 arr[start..end) 区间选择第 k 小元素，并返回其值。
     * 算法原地修改 arr。
     * 
     * @param arr         输入数组
     * @param k           目标元素的绝对索引 (0-based)，必须在 [start, end) 范围内
     * @param start       起始索引 (包含)
     * @param end         结束索引 (不包含)
     * @param compareFunc 比较函数 (a<b: <0, a>b: >0, a==b: 0)
     * @return 第 k 小元素的值
     */
    public static function select(arr:Array, k:Number, start:Number, end:Number, compareFunc:Function):Object {
        // 输入验证
        if (arr == null || start < 0 || end > arr.length || k < start || k >= end) {
            return null;
        }

        // 使用迭代代替递归，避免堆栈溢出，性能更稳定
        while (true) {
            var len:Number = end - start;
            
            // 基础情况：小规模子问题使用插入排序解决
            if (len <= INSERTION_THRESHOLD) {
                insertionSortRange(arr, start, end, compareFunc);
                return arr[k];
            }

            // --- 主元选择与分区 ---
            var pivotIndex:Number;
            
            // 1. 默认使用三数取中进行分区
            pivotIndex = partition(arr, start, end - 1, compareFunc);

            // 2. 检测分区是否严重不平衡
            var leftSize:Number = pivotIndex - start;
            if (leftSize < len / UNBALANCED_RATIO || (len - 1 - leftSize) < len / UNBALANCED_RATIO) {
                // 3. 如果不平衡，则使用 BFPRT 找到一个更好的主元并重新分区
                var momIndex:Number = findMedianOfMediansIndex(arr, start, end, compareFunc);
                swap(arr, momIndex, end - 1); // 将“好”主元放到分区所需的位置
                pivotIndex = partition(arr, start, end - 1, compareFunc);
            }
            
            // --- 根据主元位置缩小范围 ---
            if (pivotIndex == k) {
                return arr[k]; // 找到了
            } else if (pivotIndex > k) {
                end = pivotIndex; // 目标在左边
            } else {
                start = pivotIndex + 1; // 目标在右边
            }
        }
    }

    /**
     * 对小范围 [start, end) 进行插入排序。
     */
    private static function insertionSortRange(arr:Array, start:Number, end:Number, compareFunc:Function):Void {
        for (var i:Number = start + 1; i < end; i++) {
            var key:Object = arr[i];
            var j:Number = i - 1;
            while (j >= start && compareFunc(arr[j], key) > 0) {
                arr[j + 1] = arr[j];
                j--;
            }
            arr[j + 1] = key;
        }
    }

    /**
     * Lomuto 分区方案。
     * 隐含地使用 arr[high] 作为主元。三数取中逻辑将一个好的主元候选放到了 arr[high]。
     */
    private static function partition(arr:Array, low:Number, high:Number, compareFunc:Function):Number {
        // 三数取中优化：选择 low, mid, high 的中位数作为主元，并将其置于 high 位置
        var mid:Number = low + Math.floor((high - low) / 2);
        if (compareFunc(arr[mid], arr[low]) < 0) swap(arr, mid, low);
        if (compareFunc(arr[high], arr[low]) < 0) swap(arr, high, low);
        if (compareFunc(arr[mid], arr[high]) < 0) swap(arr, mid, high);
        
        var pivot:Object = arr[high];
        var i:Number = low - 1;
        for (var j:Number = low; j < high; j++) {
            if (compareFunc(arr[j], pivot) <= 0) {
                i++;
                swap(arr, i, j);
            }
        }
        swap(arr, i + 1, high);
        return i + 1;
    }

    /**
     * 基于 BFPRT 的 Median-of-Medians 主元选择，返回主元的最终索引。
     */
    private static function findMedianOfMediansIndex(arr:Array, start:Number, end:Number, compareFunc:Function):Number {
        var n:Number = end - start;
        if (n <= 5) {
            // 对于小数组，直接排序找到中位数索引
            return findMedianIndexInGroup(arr, start, end, compareFunc);
        }
        
        // 将每 5 个一组的中位数移到数组的前部 [start, start + numMedians)
        var numMedians:Number = Math.floor(n / 5);
        for (var i:Number = 0; i < numMedians; i++) {
            var groupStart:Number = start + i * 5;
            var medianIdx:Number = findMedianIndexInGroup(arr, groupStart, groupStart + 5, compareFunc);
            swap(arr, start + i, medianIdx);
        }
        
        // 递归地在中位数数组中找到中位数的中位数
        return findMedianOfMediansIndex(arr, start, start + numMedians, compareFunc);
    }
    
    /**
     * 辅助函数：在一个小组 [start, end) 内找到中位数的索引，会原地排序该小组。
     */
    private static function findMedianIndexInGroup(arr:Array, start:Number, end:Number, compareFunc:Function):Number {
        insertionSortRange(arr, start, end, compareFunc);
        return start + Math.floor((end - start - 1) / 2);
    }

    /**
     * 元素交换
     */
    private static function swap(arr:Array, i:Number, j:Number):Void {
        var tmp:Object = arr[i];
        arr[i] = arr[j];
        arr[j] = tmp;
    }

    // --- 便捷公共方法 ---

    /**
     * 简化版本：在整个数组上选择第 k 小的元素。
     * @param k 目标元素的绝对索引 (0-based)。
     */
    public static function selectKth(arr:Array, k:Number, compareFunc:Function):Object {
        if (arr == null || arr.length == 0) return null;
        return select(arr, k, 0, arr.length, compareFunc);
    }

    /**
     * 中位数选择：返回下中位数 (e.g., 8个元素返回第4个，索引为3)。
     */
    public static function median(arr:Array, compareFunc:Function):Object {
        if (arr == null || arr.length == 0) return null;
        return selectKth(arr, Math.floor((arr.length - 1) / 2), compareFunc);
    }

    /**
     * 默认数字比较
     */
    public static function numberCompare(a:Number, b:Number):Number {
        return a - b;
    }

    /**
     * 默认字符串比较
     */
    public static function stringCompare(a:String, b:String):Number {
        if (a < b) return -1;
        if (a > b) return 1;
        return 0;
    }
}