/**
 * ActionScript 2.0 TimSort - 高性能稳定排序
 *
 * 核心优化（v3.0 宏化重构）：
 * - P0: 标准双向交替galloping + 正确的minGallop自适应（修复双重惩罚）
 * - P1: 合并逻辑宏化(#include)，零函数调用开销 + 单一维护点
 * - P1: hint-based搜索方向修复（预裁剪gallopLeft + mergeHi B-gallop）
 * - P2: _inUse重入保护
 *
 * AS2专项优化保留：循环展开×4、副作用合并、变量提升、静态缓存复用
 */
class org.flashNight.naki.Sort.TimSort {

    // 静态工作区缓存 - 跨调用复用，减少 new Array() 产生的 GC 压力
    private static var _workspace:Array   = null;
    private static var _wsLen:Number      = 0;
    private static var _runBase:Array     = null;
    private static var _runLen:Array      = null;
    private static var _stackCap:Number   = 0;

    // 重入保护
    private static var _inUse:Boolean = false;

    // ==============================================================
    //  sort() - 主排序入口
    // ==============================================================
    public static function sort(arr:Array, compareFunction:Function):Array {

        // 变量声明提升（AS2函数作用域）
        // --- sort 自有 ---
        var n:Number, MIN_MERGE:Number, MIN_GALLOP:Number;
        var compare:Function, tempArray:Array;
        var runBase:Array, runLen:Array, stackSize:Number, minGallop:Number;
        var minRun:Number;
        var remaining:Number, lo:Number;
        var runLength:Number, hi:Number;
        var revLo:Number, revHi:Number, tmp:Object;
        var force:Number, right:Number, i:Number, key:Object, j:Number;
        var size:Number, n_idx:Number, shouldMerge:Boolean, mergeIdx:Number;
        var loA:Number, lenA:Number, loB:Number, lenB:Number;
        var stackCapacity:Number;
        var forceIdx:Number;
        // --- merge 宏使用（TIMSORT_MERGE.as） ---
        var gallopK:Number, target:Object, base:Number, len:Number;
        var ofs:Number, lastOfs:Number, left:Number, hi2:Number, mid:Number;
        var pa:Number, pb:Number, d:Number, ea:Number, eb:Number;
        var ca:Number, cb:Number, ba0:Number;
        var copyLen:Number, copyI:Number, copyIdx:Number, copyEnd:Number, tempIdx:Number;

        // 初始化
        n = arr.length;
        if (n < 2) return arr;

        MIN_MERGE = 32;
        MIN_GALLOP = 7;

        compare = (compareFunction == null)
            ? function(a, b):Number { return a - b; }
            : compareFunction;

        // 小数组快速路径（不使用静态状态，无需重入保护）
        if (n <= MIN_MERGE) {
            for (i = 1; i < n; i++) {
                key = arr[i];
                if (compare(arr[i - 1], key) <= 0) continue;
                if (i <= 4) {
                    j = i - 1;
                    while (j >= 0 && compare(arr[j], key) > 0) {
                        arr[j + 1] = arr[j]; j--;
                    }
                    arr[j + 1] = key;
                } else {
                    left = 0; hi2 = i;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (compare(arr[mid], key) <= 0) left = mid + 1;
                        else hi2 = mid;
                    }
                    j = i;
                    while (j > left) { arr[j] = arr[j - 1]; j--; }
                    arr[left] = key;
                }
            }
            return arr;
        }

        // P2: 重入保护
        if (_inUse) {
            if (compareFunction != null) arr.sort(compareFunction);
            else arr.sort(function(a, b) { return a - b; });
            return arr;
        }
        _inUse = true;

        // 初始化栈缓存
        stackCapacity = 64;
        if (_stackCap < stackCapacity) {
            _runBase  = new Array(stackCapacity);
            _runLen   = new Array(stackCapacity);
            _stackCap = stackCapacity;
        }
        runBase = _runBase;
        runLen  = _runLen;

        // tempArray: 优先复用缓存
        if (_wsLen >= ((n + 1) >> 1)) {
            tempArray = _workspace;
        } else {
            tempArray = null;
        }
        stackSize = 0;
        minGallop = MIN_GALLOP;

        // 计算minRun（复用ofs/lastOfs）
        ofs = n; lastOfs = 0;
        while (ofs >= MIN_MERGE) {
            lastOfs |= ofs & 1;
            ofs >>= 1;
        }
        minRun = ofs + lastOfs;

        // 主循环
        remaining = n;
        lo = 0;
        while (remaining > 0) {
            // 识别run
            hi = lo + 1;
            if (hi >= n) {
                runLength = 1;
            } else {
                if (compare(arr[lo], arr[hi]) > 0) {
                    hi++;
                    while (hi < n && compare(arr[hi - 1], arr[hi]) > 0) hi++;
                    // 反转下降run
                    revLo = lo; revHi = hi - 1;
                    while (revLo < revHi) {
                        tmp = arr[revLo]; arr[revLo++] = arr[revHi]; arr[revHi--] = tmp;
                    }
                } else {
                    while (hi < n && compare(arr[hi - 1], arr[hi]) <= 0) hi++;
                }
                runLength = hi - lo;
            }

            // 短run扩展（插入排序）
            if (runLength < minRun) {
                force = (remaining < minRun) ? remaining : minRun;
                right = lo + force - 1;
                for (i = lo + runLength; i <= right; i++) {
                    key = arr[i];
                    j = i - 1;
                    if (compare(arr[i - 1], key) <= 0) continue;
                    if ((i - lo) <= 4) {
                        while (j >= lo && compare(arr[j], key) > 0) {
                            arr[j + 1] = arr[j]; j--;
                        }
                        arr[j + 1] = key;
                        continue;
                    }
                    left = lo; hi2 = i;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (compare(arr[mid], key) <= 0) left = mid + 1;
                        else hi2 = mid;
                    }
                    j = i;
                    while (j > left) { arr[j] = arr[j - 1]; j--; }
                    arr[left] = key;
                }
                runLength = force;
            }

            // 压栈
            runBase[stackSize] = lo;
            runLen[stackSize++] = runLength;

            // mergeCollapse: 维护栈不变量
            size = stackSize;
            while (size > 1) {
                n_idx = size - 2;
                shouldMerge = false;
                if ((n_idx > 0 && runLen[n_idx - 1] <= runLen[n_idx] + runLen[n_idx + 1])
                    || (n_idx > 1 && runLen[n_idx - 2] <= runLen[n_idx - 1] + runLen[n_idx])) {
                    mergeIdx = n_idx - (runLen[n_idx - 1] < runLen[n_idx + 1]);
                    shouldMerge = true;
                } else if (runLen[n_idx] <= runLen[n_idx + 1]) {
                    mergeIdx = n_idx;
                    shouldMerge = true;
                }
                if (!shouldMerge) break;

                loA = runBase[mergeIdx];
                lenA = runLen[mergeIdx];
                loB = runBase[tempIdx = mergeIdx + 1];
                lenB = runLen[tempIdx];
                runLen[mergeIdx] = lenA + lenB;
                copyLen = stackSize - 1;
                for (copyI = tempIdx; copyI < copyLen; copyI++) {
                    runBase[copyI] = runBase[tempIdx = copyI + 1];
                    runLen[copyI] = runLen[tempIdx];
                }
                --stackSize;

                #include "../macros/TIMSORT_MERGE.as"

                size = stackSize;
            }

            lo += runLength;
            remaining -= runLength;
        }

        // forceCollapse: 合并剩余所有run
        while (stackSize > 1) {
            forceIdx = (stackSize > 2 && runLen[stackSize - 3] < runLen[stackSize - 1])
                ? stackSize - 3 : stackSize - 2;

            loA = runBase[forceIdx];
            lenA = runLen[forceIdx];
            loB = runBase[forceIdx + 1];
            lenB = runLen[forceIdx + 1];
            runLen[forceIdx] = lenA + lenB;
            copyLen = stackSize - 1;
            for (copyI = forceIdx + 1; copyI < copyLen; copyI++) {
                runBase[copyI] = runBase[copyI + 1];
                runLen[copyI] = runLen[copyI + 1];
            }
            stackSize--;

            #include "../macros/TIMSORT_MERGE.as"
        }

        // 清理
        _inUse = false;
        return arr;
    }
}
