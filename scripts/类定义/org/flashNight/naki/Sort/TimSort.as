/**
 * ActionScript 2.0 TimSort - 高性能稳定排序
 *
 * 核心优化（v3.1 四方审阅调优）：
 * - P0: 标准双向交替galloping + 正确的minGallop自适应（修复双重惩罚）
 * - P0: workspace GC清理（阈值256，防止对象引用泄漏）
 * - P1: 合并逻辑宏化(#include)，零函数调用开销 + 单一维护点
 * - P1: hint-based搜索方向修复（预裁剪gallopLeft + mergeHi B-gallop）
 * - P1: MINRUN_BASE=24 解耦（小数组cutoff=32不变，minRun计算用24）
 * - P2: _inUse重入保护 + 安全阀resetState() + trace警告
 * - P2: 小数组null comparator内联特化（零函数调用开销）
 * - P3: MIN_GALLOP 7→9（benchmark支持，AS2下延迟进入gallop更优）
 * - P3: 哨兵搬运 + do-while合并循环优化（减少分支）
 *
 * v3.2 间接排序扩展：
 * - sortIndirect(arr, keys): 按预提取键数组排序索引数组
 * - TIMSORT_MERGE_INDIRECT.as: 合并宏的内联键比较版本
 * - 完全消除比较器函数调用开销（keys[X] OP keys[Y] 替代 compare(X,Y)）
 * - keys数组排序期间只读，tempArray存索引值，无需额外tempKeys
 *
 * v3.3 微观优化（架构审阅驱动）：
 * - P0: Run识别阶段缓存（sort/sortIndirect），消除arr[hi-1]重复读取，
 *   将逐元素扫描的数组查表量减半
 * - P1: mergeLo远端O(1)拦截（两个宏文件），补齐与mergeHi对称的
 *   tempArray[base+len-1]/arr[base+len-1]快速路径，跳过O(log n)二分
 * - P2: 插入排序移位缓存（5处），tmp=arr[j]消除循环体内重复读取，
 *   同时消除arr[j+1]=arr[j--]的求值顺序平台依赖
 * - P3: 静态默认比较器_defaultCmp，避免每次sort()创建闭包
 * - P4: 删除宏文件中8处if(ofs<=0)ofs=len溢出防护死代码
 *   （AS2数组上限~16M，ofs翻倍最高~33M，远低于Number溢出阈值）
 *
 * AS2/AVM1 平台决策记录（实测验证，勿逆向"优化"）：
 * - 4路循环展开 + 偏移寻址：批量拷贝用 arr[d+k]...d+=4 而非 arr[d++]×4。
 *   AVM1中 d++ 编译为 read-dup-increment-store（4条字节码），
 *   d+k 编译为 push-k-add（3条字节码），每4路展开净省4条指令。
 *   实测 d++ 版本性能回退已确认，偏移寻址为当前最优模式。
 * - 隐式布尔转换优于三元：compare(a,b)<=0 返回 Boolean，
 *   AVM1 的 ActionSubtract 等算术指令内部硬连线 Boolean→Number 快速路径，
 *   比显式三元 (cond ? 1 : 0) 更快。勿尝试"装箱消除"优化。
 * - 副作用合并、变量提升、静态缓存复用
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

    // 默认数值比较器 - 静态方法引用，避免每次sort()创建闭包
    private static function _defaultCmp(a, b):Number { return a - b; }

    // ==============================================================
    //  resetState() - 安全阀：异常后重置_inUse标记
    //  在帧初始化时调用，防止compare()异常导致永久降级
    // ==============================================================
    public static function resetState():Void {
        _inUse = false;
    }

    // ==============================================================
    //  sort() - 主排序入口
    // ==============================================================
    public static function sort(arr:Array, compareFunction:Function):Array {

        // 变量声明提升（AS2函数作用域）
        // --- sort 自有 ---
        var n:Number, MIN_MERGE:Number, MINRUN_BASE:Number, MIN_GALLOP:Number;
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
        var aVal:Object, bVal:Object;
        var copyLen:Number, copyI:Number, copyIdx:Number, copyEnd:Number, tempIdx:Number;

        // 初始化
        n = arr.length;
        if (n < 2) return arr;

        MIN_MERGE = 32;
        MINRUN_BASE = 24;
        MIN_GALLOP = 9;

        // 小数组快速路径（不使用静态状态，无需重入保护）
        if (n <= MIN_MERGE) {
            if (compareFunction != null) {
                compare = compareFunction;
                for (i = 1; i < n; i++) {
                    key = arr[i];
                    if (compare(arr[i - 1], key) <= 0) continue;
                    if (i <= 4) {
                        j = i - 1;
                        while (j >= 0) {
                            tmp = arr[j];
                            if (compare(tmp, key) <= 0) break;
                            arr[j + 1] = tmp;
                            j--;
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
                        while (j > left) { arr[j] = arr[--j]; }
                        arr[left] = key;
                    }
                }
            } else {
                // P2: null comparator 内联数值比较，零函数调用开销
                for (i = 1; i < n; i++) {
                    key = arr[i];
                    if (arr[i - 1] <= key) continue;
                    if (i <= 4) {
                        j = i - 1;
                        while (j >= 0) {
                            tmp = arr[j];
                            if (tmp <= key) break;
                            arr[j + 1] = tmp;
                            j--;
                        }
                        arr[j + 1] = key;
                    } else {
                        left = 0; hi2 = i;
                        while (left < hi2) {
                            mid = (left + hi2) >> 1;
                            if (arr[mid] <= key) left = mid + 1;
                            else hi2 = mid;
                        }
                        j = i;
                        while (j > left) { arr[j] = arr[--j]; }
                        arr[left] = key;
                    }
                }
            }
            return arr;
        }

        // compare闭包仅在完整TimSort路径创建（小数组路径已返回）
        compare = (compareFunction == null) ? _defaultCmp : compareFunction;

        // P2: 重入保护
        if (_inUse) {
            trace("[TimSort] Warning: reentrant call detected, falling back to Array.sort()");
            if (compareFunction != null) arr.sort(compareFunction);
            else arr.sort(_defaultCmp);
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

        // 计算minRun（MINRUN_BASE=24，与小数组cutoff=32解耦）
        ofs = n; lastOfs = 0;
        while (ofs >= MINRUN_BASE) {
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
                // P0: 缓存arr[hi]，避免下一轮重复读取arr[hi-1]
                tmp = arr[hi];
                if (compare(arr[lo], tmp) > 0) {
                    hi++;
                    while (hi < n) {
                        aVal = arr[hi];
                        if (compare(tmp, aVal) <= 0) break;
                        hi++;
                        tmp = aVal;
                    }
                    // 反转下降run
                    revLo = lo; revHi = hi - 1;
                    while (revLo < revHi) {
                        tmp = arr[revLo]; arr[revLo++] = arr[revHi]; arr[revHi--] = tmp;
                    }
                } else {
                    hi++;
                    while (hi < n) {
                        aVal = arr[hi];
                        if (compare(tmp, aVal) > 0) break;
                        hi++;
                        tmp = aVal;
                    }
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
                        while (j >= lo) {
                            tmp = arr[j];
                            if (compare(tmp, key) <= 0) break;
                            arr[j + 1] = tmp;
                            j--;
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
                    while (j > left) { arr[j] = arr[--j]; }
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
                copyI = size - 1;
                cb = runLen[copyI];
                ca = runLen[--copyI];
                n_idx = copyI;
                shouldMerge = false;
                if (copyI > 0) {
                    copyLen = runLen[--copyI];
                    if (copyLen <= ca + cb
                        || (copyI > 0 && runLen[--copyI] <= copyLen + ca)) {
                        mergeIdx = n_idx - (copyLen < cb);
                        shouldMerge = true;
                    }
                }
                if (!shouldMerge && ca <= cb) {
                    mergeIdx = n_idx;
                    shouldMerge = true;
                }
                if (!shouldMerge) break;

                loA = runBase[mergeIdx];
                lenA = runLen[mergeIdx];
                loB = runBase[tempIdx = mergeIdx + 1];
                lenB = runLen[tempIdx];
                runLen[mergeIdx] = lenA + lenB;
                copyI = tempIdx;
                copyLen = stackSize - 1;
                while (copyI < copyLen) {
                    runBase[copyI] = runBase[++copyI];
                    runLen[copyI - 1] = runLen[copyI];
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
            copyI = stackSize - 1;
            cb = runLen[copyI];
            forceIdx = (--copyI > 0 && runLen[copyI - 1] < cb)
                ? copyI - 1 : copyI;

            loA = runBase[forceIdx];
            lenA = runLen[forceIdx];
            loB = runBase[tempIdx = forceIdx + 1];
            lenB = runLen[tempIdx];
            runLen[forceIdx] = lenA + lenB;
            copyI = tempIdx;
            copyLen = stackSize - 1;
            while (copyI < copyLen) {
                runBase[copyI] = runBase[++copyI];
                runLen[copyI - 1] = runLen[copyI];
            }
            stackSize--;

            #include "../macros/TIMSORT_MERGE.as"
        }

        // P0: 清理 - 大workspace释放防止GC泄漏，小workspace保留复用
        if (_wsLen > 256) { _workspace = null; _wsLen = 0; }
        _inUse = false;
        return arr;
    }

    // ==============================================================
    //  sortIndirect() - 间接排序入口
    //  按 keys 数组的值对 indices 数组排序，完全内联比较，零函数调用开销
    //  前置条件：arr[i] 为有效索引，keys[arr[i]] 为对应 Number 键值
    // ==============================================================
    public static function sortIndirect(arr:Array, keys:Array):Array {

        // 变量声明提升（AS2函数作用域）
        // --- sortIndirect 自有 ---
        var n:Number, MIN_MERGE:Number, MINRUN_BASE:Number, MIN_GALLOP:Number;
        var tempArray:Array;
        var runBase:Array, runLen:Array, stackSize:Number, minGallop:Number;
        var minRun:Number;
        var remaining:Number, lo:Number;
        var runLength:Number, hi:Number;
        var revLo:Number, revHi:Number, tmp:Number;
        var force:Number, right:Number, i:Number, key:Number, keyVal:Number, j:Number;
        var size:Number, n_idx:Number, shouldMerge:Boolean, mergeIdx:Number;
        var loA:Number, lenA:Number, loB:Number, lenB:Number;
        var stackCapacity:Number;
        var forceIdx:Number;
        // --- merge 宏使用（TIMSORT_MERGE_INDIRECT.as） ---
        var gallopK:Number, target:Number, base:Number, len:Number;
        var ofs:Number, lastOfs:Number, left:Number, hi2:Number, mid:Number;
        var pa:Number, pb:Number, d:Number, ea:Number, eb:Number;
        var ca:Number, cb:Number, ba0:Number;
        var keyA:Number, keyB:Number, aVal:Number, bVal:Number;
        var copyLen:Number, copyI:Number, copyIdx:Number, copyEnd:Number, tempIdx:Number;

        // 初始化
        n = arr.length;
        if (n < 2) return arr;

        MIN_MERGE = 32;
        MINRUN_BASE = 24;
        MIN_GALLOP = 9;

        // 小数组快速路径（内联键比较，不使用静态状态，无需重入保护）
        if (n <= MIN_MERGE) {
            for (i = 1; i < n; i++) {
                key = arr[i];
                keyVal = keys[key];
                if (keys[arr[i - 1]] <= keyVal) continue;
                if (i <= 4) {
                    j = i - 1;
                    while (j >= 0) {
                        tmp = arr[j];
                        if (keys[tmp] <= keyVal) break;
                        arr[j + 1] = tmp;
                        j--;
                    }
                    arr[j + 1] = key;
                } else {
                    left = 0; hi2 = i;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (keys[arr[mid]] <= keyVal) left = mid + 1;
                        else hi2 = mid;
                    }
                    j = i;
                    while (j > left) { arr[j] = arr[--j]; }
                    arr[left] = key;
                }
            }
            return arr;
        }

        // P2: 重入保护
        if (_inUse) {
            trace("[TimSort] Warning: reentrant call detected in sortIndirect, falling back");
            arr.sort(function(a, b) { return keys[a] - keys[b]; });
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

        // 计算minRun（MINRUN_BASE=24，与小数组cutoff=32解耦）
        ofs = n; lastOfs = 0;
        while (ofs >= MINRUN_BASE) {
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
                // P0: 双重解引用缓存，每次循环省2次数组查表
                keyA = keys[arr[lo]];
                keyB = keys[arr[hi]];
                if (keyA > keyB) {
                    hi++;
                    keyA = keyB;
                    while (hi < n) {
                        keyB = keys[arr[hi]];
                        if (keyA <= keyB) break;
                        hi++;
                        keyA = keyB;
                    }
                    // 反转下降run
                    revLo = lo; revHi = hi - 1;
                    while (revLo < revHi) {
                        tmp = arr[revLo]; arr[revLo++] = arr[revHi]; arr[revHi--] = tmp;
                    }
                } else {
                    hi++;
                    keyA = keyB;
                    while (hi < n) {
                        keyB = keys[arr[hi]];
                        if (keyA > keyB) break;
                        hi++;
                        keyA = keyB;
                    }
                }
                runLength = hi - lo;
            }

            // 短run扩展（插入排序）
            if (runLength < minRun) {
                force = (remaining < minRun) ? remaining : minRun;
                right = lo + force - 1;
                for (i = lo + runLength; i <= right; i++) {
                    key = arr[i];
                    keyVal = keys[key];
                    j = i - 1;
                    if (keys[arr[i - 1]] <= keyVal) continue;
                    if ((i - lo) <= 4) {
                        while (j >= lo) {
                            tmp = arr[j];
                            if (keys[tmp] <= keyVal) break;
                            arr[j + 1] = tmp;
                            j--;
                        }
                        arr[j + 1] = key;
                        continue;
                    }
                    left = lo; hi2 = i;
                    while (left < hi2) {
                        mid = (left + hi2) >> 1;
                        if (keys[arr[mid]] <= keyVal) left = mid + 1;
                        else hi2 = mid;
                    }
                    j = i;
                    while (j > left) { arr[j] = arr[--j]; }
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
                copyI = size - 1;
                cb = runLen[copyI];
                ca = runLen[--copyI];
                n_idx = copyI;
                shouldMerge = false;
                if (copyI > 0) {
                    copyLen = runLen[--copyI];
                    if (copyLen <= ca + cb
                        || (copyI > 0 && runLen[--copyI] <= copyLen + ca)) {
                        mergeIdx = n_idx - (copyLen < cb);
                        shouldMerge = true;
                    }
                }
                if (!shouldMerge && ca <= cb) {
                    mergeIdx = n_idx;
                    shouldMerge = true;
                }
                if (!shouldMerge) break;

                loA = runBase[mergeIdx];
                lenA = runLen[mergeIdx];
                loB = runBase[tempIdx = mergeIdx + 1];
                lenB = runLen[tempIdx];
                runLen[mergeIdx] = lenA + lenB;
                copyI = tempIdx;
                copyLen = stackSize - 1;
                while (copyI < copyLen) {
                    runBase[copyI] = runBase[++copyI];
                    runLen[copyI - 1] = runLen[copyI];
                }
                --stackSize;

                #include "../macros/TIMSORT_MERGE_INDIRECT.as"

                size = stackSize;
            }

            lo += runLength;
            remaining -= runLength;
        }

        // forceCollapse: 合并剩余所有run
        while (stackSize > 1) {
            copyI = stackSize - 1;
            cb = runLen[copyI];
            forceIdx = (--copyI > 0 && runLen[copyI - 1] < cb)
                ? copyI - 1 : copyI;

            loA = runBase[forceIdx];
            lenA = runLen[forceIdx];
            loB = runBase[tempIdx = forceIdx + 1];
            lenB = runLen[tempIdx];
            runLen[forceIdx] = lenA + lenB;
            copyI = tempIdx;
            copyLen = stackSize - 1;
            while (copyI < copyLen) {
                runBase[copyI] = runBase[++copyI];
                runLen[copyI - 1] = runLen[copyI];
            }
            stackSize--;

            #include "../macros/TIMSORT_MERGE_INDIRECT.as"
        }

        // P0: 清理 - 大workspace释放防止GC泄漏，小workspace保留复用
        if (_wsLen > 256) { _workspace = null; _wsLen = 0; }
        _inUse = false;
        return arr;
    }
}
