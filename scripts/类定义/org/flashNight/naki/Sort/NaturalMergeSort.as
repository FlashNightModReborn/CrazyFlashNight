/**
 * ================================================================================================
 * ActionScript 2.0 稳定自然归并排序（Natural Merge Sort）- 极简自适应版本
 * ================================================================================================
 *
 * 【算法要点】
 * - 稳定：相等元素保持相对顺序（合并时相等取左）
 * - 自然：一次线性扫描识别“天然有序 run”（升序；降序将地就地反转为升序）
 * - 归并：按相邻 run 成对归并；一轮结束后 run 数量减半，循环直到仅剩 1 个 run
 * - 常数：不维护 TimSort 的 run 栈不变量、minRun、gallop、自适应阈值等，AS2 下常数更小
 * - 空间：一次性分配 tmp = new Array(ceil(n/2))，每次只拷贝较短一侧
 *
 * 【适用建议】
 * - n ∈ [64, 192] 的常见场景、或 run 较少的“略有序”数据
 * - 需要稳定排序、避免递归/复杂状态机时
 */
class org.flashNight.naki.Sort.NaturalMergeSort {

    /**
     * 自然归并主函数（稳定，原地）
     * @param arr 待排序数组
     * @param compareFunction 比较器，(a,b)->Number：<0 a<b，=0 a=b，>0 a>b；null 则用数值快路径
     * @return 原数组引用（已排序）
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        // ========= 基础与比较器 =========
        var n:Number = (arr == null) ? 0 : arr.length;
        if (n <= 1) return arr;

        var compare:Function = (compareFunction == null)
            ? function(a, b):Number { return a - b; }  // 数值快路径
            : compareFunction;

        // ========= 一次性缓冲：最大仅需 n/2 =========
        var tmp:Array = new Array(Math.ceil(n / 2));

        // ========= 第一次线性扫描：识别天然 run（升序；若降序就地反转） =========
        // 我们把 run 的起止索引暂存到 runBase/runLen，随后做成对归并
        var runBase:Array = [];   // 每个 run 的起点
        var runLen:Array  = [];   // 每个 run 的长度
        var runCount:Number = 0;

        var i:Number = 0, j:Number, lo:Number, hi:Number, c:Number, t:Object;
        while (i < n) {
            lo = i;
            // 至少包含一个元素
            i++;

            if (i < n) {
                // 判断趋势：升 / 降
                c = compare(arr[i], arr[i - 1]);
                if (c >= 0) {
                    // 升序 run
                    while (i < n && compare(arr[i], arr[i - 1]) >= 0) i++;
                    hi = i; // [lo, hi)
                } else {
                    // 降序 run —— 原地反转为升序
                    while (i < n && compare(arr[i], arr[i - 1]) < 0) i++;
                    hi = i;
                    reverseRange(arr, lo, hi - 1);
                }
            } else {
                hi = i; // 末尾单元素 run
            }

            runBase[runCount] = lo;
            runLen[runCount]  = hi - lo;
            runCount++;
        }

        // ========= 多轮成对归并：直到 runCount==1 =========
        // 策略：一轮中依次把 (0,1), (2,3), ... 合并为更长 run，落回原数组
        // 拷贝较短侧到 tmp：lenA<=lenB → mergeLo；否则 mergeHi（从右向左）
        var nextBase:Array, nextLen:Array, k:Number, a0:Number, aLen:Number, b0:Number, bLen:Number;

        while (runCount > 1) {
            nextBase = [];
            nextLen  = [];
            k = 0;

            for (i = 0; i + 1 < runCount; i += 2) {
                a0   = runBase[i];
                aLen = runLen[i];
                b0   = runBase[i + 1];
                bLen = runLen[i + 1];

                // 合并相邻 run：保证起点连续（构造方式即如此）
                if (aLen <= bLen) {
                    mergeLo(arr, a0, aLen, b0, bLen, tmp, compare);
                } else {
                    mergeHi(arr, a0, aLen, b0, bLen, tmp, compare);
                }

                nextBase[k] = a0;
                nextLen[k]  = aLen + bLen;
                k++;
            }

            // 若剩奇数个 run，把最后一个直接抬升到下一轮
            if ((runCount & 1) != 0) {
                nextBase[k] = runBase[runCount - 1];
                nextLen[k]  = runLen[runCount - 1];
                k++;
            }

            runBase  = nextBase;
            runLen   = nextLen;
            runCount = k;
        }

        return arr;
    }

    // =============================================================================================
    // 内部工具：区间反转
    // =============================================================================================
    private static function reverseRange(a:Array, left:Number, right:Number):Void {
        var t:Object;
        while (left < right) {
            t = a[left]; a[left] = a[right]; a[right] = t;
            left++; right--;
        }
    }

    // =============================================================================================
    // 合并（左短右长）：把左侧 A 拷到 tmp，正向写回；稳定性由 <= 保证（相等取左）
    // a[a0 .. a0+aLen), a[b0 .. b0+bLen)
    // =============================================================================================
    private static function mergeLo(a:Array, a0:Number, aLen:Number, b0:Number, bLen:Number,
                                   tmp:Array, compare:Function):Void {
        var i:Number, j:Number, k:Number, end:Number;

        // 1) 左侧 A 拷入 tmp[0..aLen)
        for (i = 0; i < aLen; ++i) tmp[i] = a[a0 + i];

        // 2) 三指针合并：tmp[i] vs a[j] → a[k]
        i = 0;               // tmp（原 A）
        j = b0;              // 原数组右侧 B
        k = a0;              // 写回指针（原 A 的起点）
        end = b0 + bLen;     // B 的右开边界

        // 主循环：相等时取左（稳定）
        while (i < aLen && j < end) {
            if (compare(tmp[i], a[j]) <= 0) a[k++] = tmp[i++];
            else                            a[k++] = a[j++];
        }
        // 收尾：谁剩下拷谁
        while (i < aLen) a[k++] = tmp[i++];
        // B 若有剩余，它本来就在 a[j..end) 且位置已正确，无需再搬
    }

    // =============================================================================================
    // 合并（右短左长）：把右侧 B 拷到 tmp，**从右往左**写回，避免覆盖
    // a[a0 .. a0+aLen), a[b0 .. b0+bLen)
    // =============================================================================================
    private static function mergeHi(a:Array, a0:Number, aLen:Number, b0:Number, bLen:Number,
                                   tmp:Array, compare:Function):Void {
        var i:Number, j:Number, k:Number;

        // 1) 右侧 B 拷入 tmp[0..bLen)
        for (i = 0; i < bLen; ++i) tmp[i] = a[b0 + i];

        // 2) 三指针（从右向左）：a 与 tmp 末端向前归并
        i = a0 + aLen - 1;       // A 的末端
        j = bLen - 1;            // tmp（原 B）的末端
        k = b0 + bLen - 1;       // 写回位置（整个区间的末端）

        // 主循环：相等时取右边的原 B（为了稳定，反向合并时应取“右侧”）
        // 但我们整体要保持“相等取左”的全局稳定性，反向时等价规则是：a[i] > tmp[j] 时先放 a[i]
        // 推导：正向规则（相等取左） <=> 反向写入时应先放“严格大的那边”
        while (i >= a0 && j >= 0) {
            if (compare(a[i], tmp[j]) > 0) a[k--] = a[i--];
            else                           a[k--] = tmp[j--];
        }
        // 收尾：若 B 仍有剩余，拷回；若 A 有剩余，它本就位于正确位置
        while (j >= 0) a[k--] = tmp[j--];
    }
}
