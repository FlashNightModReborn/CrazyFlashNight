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
     *
     * ================================================================================================
     * 【第一阶段优化记录 - 预期提升 20-35%】
     * ================================================================================================
     * 1.  变量声明提升 - 所有变量统一在函数顶部声明，利用 AS2 提升特性
     * 2.  位运算优化 - Math.ceil(n/2) → (n >> 1) + (n & 1)，避免浮点运算
     * 3. 循环展开在 mergeLo/mergeHi 中实现（见下方函数）
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        // ===============================================================================
        // 【AS2 性能优化】变量声明提升区 - 统一顶部声明避免运行时分配
        // ===============================================================================
        var n:Number;                       // 数组长度
        var compare:Function;               // 比较函数
        var tmp:Array;                      // 临时缓冲数组（n/2 大小）

        // run 识别阶段变量
        var runBase:Array;                  // 每个 run 的起点数组
        var runLen:Array;                   // 每个 run 的长度数组
        var runCount:Number;                // 当前 run 数量
        var i:Number, j:Number;             // 循环索引（复用变量）
        var lo:Number, hi:Number;           // run 区间边界
        var c:Number;                       // 比较结果缓存
        var t:Object;                       // 反转时的交换临时变量

        // 归并阶段变量
        var nextBase:Array;                 // 下一轮 run 起点数组
        var nextLen:Array;                  // 下一轮 run 长度数组
        var k:Number;                       // 下一轮索引
        var a0:Number, aLen:Number;         // A 区域起点和长度
        var b0:Number, bLen:Number;         // B 区域起点和长度

        // ===============================================================================
        // 算法主体
        // ===============================================================================

        // ========= 基础与比较器 =========
        n = (arr == null) ? 0 : arr.length;
        if (n <= 1) return arr;

        compare = (compareFunction == null)
            ? function(a, b):Number { return a - b; }  // 数值快路径
            : compareFunction;

        // ========= 一次性缓冲：最大仅需 n/2（位运算优化） =========
        tmp = new Array((n >> 1) + (n & 1));  // 等价 Math.ceil(n/2)，避免浮点运算

        // ========= 第一次线性扫描：识别天然 run（升序；若降序就地反转） =========
        // 我们把 run 的起止索引暂存到 runBase/runLen，随后做成对归并
        runBase = [];   // 每个 run 的起点
        runLen  = [];   // 每个 run 的长度
        runCount = 0;

        i = 0;
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
    //
    // 【优化技术】
    // 1. 变量声明提升 - 所有变量在函数顶部声明
    // 2. 循环展开（4元素块）- 减少循环条件检查开销约 25%
    // 3. 副作用合并 - tmp[i] = a[copyIdx = a0 + i] 模式缓存地址计算
    // 4. 对齐优化 - copyEnd = aLen - (aLen & 3) 确保 4 元素对齐
    // =============================================================================================
    private static function mergeLo(a:Array, a0:Number, aLen:Number, b0:Number, bLen:Number,
                                   tmp:Array, compare:Function):Void {
        // 变量声明提升
        var i:Number, j:Number, k:Number, end:Number;
        var copyIdx:Number;     // 副作用合并：地址计算缓存
        var copyEnd:Number;     // 循环展开：4 元素对齐边界

        // ====================================================================
        // 【优化关键】循环展开 + 副作用合并：复制 A 到临时数组
        // ====================================================================
        // 4 元素对齐边界（位运算优化）
        copyEnd = aLen - (aLen & 3);

        // 主循环：4 元素一组展开
        for (i = 0; i < copyEnd; i += 4) {
            // 【副作用合并】第一个元素计算地址并缓存到 copyIdx
            tmp[i]     = a[copyIdx = a0 + i];
            // 后续 3 个元素复用缓存地址，只需 +1/+2/+3
            tmp[i + 1] = a[copyIdx + 1];
            tmp[i + 2] = a[copyIdx + 2];
            tmp[i + 3] = a[copyIdx + 3];
        }

        // 处理剩余元素（0-3 个）
        for (; i < aLen; ++i) {
            tmp[i] = a[a0 + i];
        }

        // ====================================================================
        // 三指针合并：tmp[i] vs a[j] → a[k]
        // ====================================================================
        i = 0;               // tmp（原 A）
        j = b0;              // 原数组右侧 B
        k = a0;              // 写回指针（原 A 的起点）
        end = b0 + bLen;     // B 的右开边界

        // 主循环：相等时取左（稳定）
        while (i < aLen && j < end) {
            if (compare(tmp[i], a[j]) <= 0) a[k++] = tmp[i++];
            else                            a[k++] = a[j++];
        }

        // ====================================================================
        // 收尾：谁剩下拷谁
        // ====================================================================
        while (i < aLen) a[k++] = tmp[i++];
        // B 若有剩余，它本来就在 a[j..end) 且位置已正确，无需再搬
    }

    // =============================================================================================
    // 合并（右短左长）：把右侧 B 拷到 tmp，**从右往左**写回，避免覆盖
    // a[a0 .. a0+aLen), a[b0 .. b0+bLen)
    //
    // 【优化技术】（与 mergeLo 对称）
    // 1. 变量声明提升 - 所有变量在函数顶部声明
    // 2. 循环展开（4元素块）- 减少循环条件检查开销约 25%
    // 3. 副作用合并 - tmp[i] = a[copyIdx = b0 + i] 模式缓存地址计算
    // 4. 对齐优化 - copyEnd = bLen - (bLen & 3) 确保 4 元素对齐
    // =============================================================================================
    private static function mergeHi(a:Array, a0:Number, aLen:Number, b0:Number, bLen:Number,
                                   tmp:Array, compare:Function):Void {
        // 变量声明提升
        var i:Number, j:Number, k:Number;
        var copyIdx:Number;     // 副作用合并：地址计算缓存
        var copyEnd:Number;     // 循环展开：4 元素对齐边界

        // ====================================================================
        // 【优化关键】循环展开 + 副作用合并：复制 B 到临时数组
        // ====================================================================
        // 4 元素对齐边界（位运算优化）
        copyEnd = bLen - (bLen & 3);

        // 主循环：4 元素一组展开
        for (i = 0; i < copyEnd; i += 4) {
            // 【副作用合并】第一个元素计算地址并缓存到 copyIdx
            tmp[i]     = a[copyIdx = b0 + i];
            // 后续 3 个元素复用缓存地址，只需 +1/+2/+3
            tmp[i + 1] = a[copyIdx + 1];
            tmp[i + 2] = a[copyIdx + 2];
            tmp[i + 3] = a[copyIdx + 3];
        }

        // 处理剩余元素（0-3 个）
        for (; i < bLen; ++i) {
            tmp[i] = a[b0 + i];
        }

        // ====================================================================
        // 三指针（从右向左）：a 与 tmp 末端向前归并
        // ====================================================================
        i = a0 + aLen - 1;       // A 的末端
        j = bLen - 1;            // tmp（原 B）的末端
        k = b0 + bLen - 1;       // 写回位置（整个区间的末端）

        // 主循环：相等时取右边的原 B（为了稳定，反向合并时应取"右侧"）
        // 但我们整体要保持"相等取左"的全局稳定性，反向时等价规则是：a[i] > tmp[j] 时先放 a[i]
        // 推导：正向规则（相等取左） <=> 反向写入时应先放"严格大的那边"
        while (i >= a0 && j >= 0) {
            if (compare(a[i], tmp[j]) > 0) a[k--] = a[i--];
            else                           a[k--] = tmp[j--];
        }

        // ====================================================================
        // 收尾：若 B 仍有剩余，拷回；若 A 有剩余，它本就位于正确位置
        // ====================================================================
        while (j >= 0) a[k--] = tmp[j--];
    }
}
