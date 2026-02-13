/**
 * ActionScript 2.0 TimSort - 高性能稳定排序
 *
 * 核心优化（v2.0重构）：
 * - P0: 标准双向交替galloping + 正确的minGallop自适应（修复双重惩罚）
 * - P1: mergeAt方法提取，消除~450行重复代码
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

    // 共享合并状态 - sort() 与 mergeAt() 之间传递
    private static var _sArr:Array;
    private static var _sCmp:Function;
    private static var _sTmp:Array;
    private static var _sMG:Number;
    private static var _sMGC:Number;
    private static var _sN:Number;

    // 重入保护
    private static var _inUse:Boolean = false;

    /**
     * 合并两个相邻run: arr[loA..loA+lenA-1] 与 arr[loB..loB+lenB-1]
     * 前置条件: loB == loA + lenA, 两段各自已排序
     * 读写共享静态字段 _sArr/_sCmp/_sTmp/_sMG/_sMGC/_sN
     */
    private static function mergeAt(loA:Number, lenA:Number,
                                    loB:Number, lenB:Number):Void {
        // 缓存共享状态到局部变量（热路径优化）
        var arr:Array      = _sArr;
        var compare:Function = _sCmp;
        var tempArray:Array = _sTmp;
        var minGallop:Number = _sMG;
        var MIN_GALLOP:Number = _sMGC;
        var n:Number       = _sN;

        // 所有局部变量提升
        var gallopK:Number, target:Object, base:Number, len:Number;
        var ofs:Number, lastOfs:Number, left:Number, hi2:Number, mid:Number;
        var pa:Number, pb:Number, d:Number, ea:Number, eb:Number;
        var ca:Number, cb:Number, ba0:Number;
        var tmp:Object, i:Number, j:Number;
        var copyLen:Number, copyI:Number, copyIdx:Number, copyEnd:Number, tempIdx:Number;

        // ---- gallopRight: 在A中找B[0]的插入位置（upper_bound），裁剪A前缀 ----
        gallopK = 0;
        target = arr[loB];
        base = loA;
        len = lenA;
        if (compare(arr[base], target) <= 0) {
            ofs = 1; lastOfs = 0;
            while (ofs < len && compare(arr[base + ofs], target) <= 0) {
                lastOfs = ofs; ofs = (ofs << 1) + 1;
                if (ofs <= 0) ofs = len;
            }
            if (ofs > len) ofs = len;
            left = lastOfs; hi2 = ofs;
            while (left < hi2) {
                mid = (left + hi2) >> 1;
                if (compare(arr[base + mid], target) <= 0) left = mid + 1;
                else hi2 = mid;
            }
            gallopK = left;
        }
        if (gallopK == lenA) { _sMG = minGallop; _sTmp = tempArray; return; }
        loA += gallopK;
        lenA -= gallopK;

        // ---- gallopLeft: 在B中找A[last]的插入位置（lower_bound），裁剪B尾部 ----
        // P1 fix: 从RIGHT搜索，因为A[last]大，答案接近B右端
        target = arr[loA + lenA - 1];
        base = loB;
        len = lenB;
        if (compare(arr[base + len - 1], target) < 0) {
            gallopK = len; // 全部B < target
        } else if (compare(arr[base], target) >= 0) {
            gallopK = 0;
        } else {
            ofs = 1; lastOfs = 0;
            while (ofs < len && compare(arr[base + len - 1 - ofs], target) >= 0) {
                lastOfs = ofs; ofs = (ofs << 1) + 1;
                if (ofs <= 0) ofs = len;
            }
            if (ofs > len) ofs = len;
            left = lastOfs; hi2 = ofs;
            while (left < hi2) {
                mid = (left + hi2) >> 1;
                if (compare(arr[base + len - 1 - mid], target) >= 0) left = mid + 1;
                else hi2 = mid;
            }
            gallopK = len - left;
        }
        if (gallopK == 0) { _sMG = minGallop; _sTmp = tempArray; return; }
        lenB = gallopK;

        // ---- 单元素快速路径 ----
        if (lenA == 1) {
            tmp = arr[loA];
            left = 0; hi2 = lenB;
            while (left < hi2) {
                mid = (left + hi2) >> 1;
                if (compare(arr[loB + mid], tmp) < 0) left = mid + 1;
                else hi2 = mid;
            }
            for (i = 0; i < left; i++) { arr[loA + i] = arr[loB + i]; }
            arr[loA + left] = tmp;
            _sMG = minGallop; _sTmp = tempArray; return;
        }
        if (lenB == 1) {
            tmp = arr[loB];
            left = 0; hi2 = lenA;
            while (left < hi2) {
                mid = (left + hi2) >> 1;
                if (compare(arr[loA + mid], tmp) <= 0) left = mid + 1;
                else hi2 = mid;
            }
            for (j = lenA - 1; j >= left; j--) { arr[loA + j + 1] = arr[loA + j]; }
            arr[loA + left] = tmp;
            _sMG = minGallop; _sTmp = tempArray; return;
        }

        // ---- 延迟分配临时数组 ----
        if (tempArray == null) {
            tempArray = new Array((n + 1) >> 1);
            _workspace = tempArray; _wsLen = tempArray.length;
        }

        // ======================================================================
        //  mergeLo / mergeHi 分支
        // ======================================================================
        if (lenA <= lenB) {
            // ============ mergeLo: 复制A到tempArray，从左到右合并 ============
            pa = 0; pb = loB; d = loA; ea = lenA; eb = loB + lenB;

            // 复制A到临时数组（×4展开）
            copyEnd = lenA - (lenA & 3);
            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                tempArray[copyI]     = arr[copyIdx = loA + copyI];
                tempArray[copyI + 1] = arr[copyIdx + 1];
                tempArray[copyI + 2] = arr[copyIdx + 2];
                tempArray[copyI + 3] = arr[copyIdx + 3];
            }
            for (; copyI < lenA; copyI++) { tempArray[copyI] = arr[loA + copyI]; }

            // === P0: 标准双阶段合并 ===
            // outer loop
            while (pa < ea && pb < eb) {
                // Phase 1: one-at-a-time
                ca = 0; cb = 0;
                while (pa < ea && pb < eb) {
                    if (compare(tempArray[pa], arr[pb]) <= 0) {
                        arr[d++] = tempArray[pa++];
                        ca++; cb = 0;
                        if (ca >= minGallop) break;
                    } else {
                        arr[d++] = arr[pb++];
                        cb++; ca = 0;
                        if (cb >= minGallop) break;
                    }
                }
                if (pa >= ea || pb >= eb) break;

                // Phase 2: galloping (do-while)
                do {
                    // A-gallop: gallopRight in tempArray for arr[pb]
                    target = arr[pb];
                    base = pa; len = ea - pa;
                    ca = 0;
                    if (compare(tempArray[base], target) <= 0) {
                        ofs = 1; lastOfs = 0;
                        while (ofs < len && compare(tempArray[base + ofs], target) <= 0) {
                            lastOfs = ofs; ofs = (ofs << 1) + 1;
                            if (ofs <= 0) ofs = len;
                        }
                        if (ofs > len) ofs = len;
                        left = lastOfs; hi2 = ofs;
                        while (left < hi2) {
                            mid = (left + hi2) >> 1;
                            if (compare(tempArray[base + mid], target) <= 0) left = mid + 1;
                            else hi2 = mid;
                        }
                        ca = left;
                    }
                    // batch copy ca elements from A
                    copyEnd = ca - (ca & 3);
                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                        arr[tempIdx = d + copyI] = tempArray[copyIdx = pa + copyI];
                        arr[tempIdx + 1] = tempArray[copyIdx + 1];
                        arr[tempIdx + 2] = tempArray[copyIdx + 2];
                        arr[tempIdx + 3] = tempArray[copyIdx + 3];
                    }
                    for (; copyI < ca; copyI++) { arr[d + copyI] = tempArray[pa + copyI]; }
                    d += ca; pa += ca;
                    if (pa >= ea) break;
                    // copy 1 B trigger element
                    arr[d++] = arr[pb++];
                    if (pb >= eb) break;

                    // B-gallop: gallopLeft in arr for tempArray[pa]
                    target = tempArray[pa];
                    base = pb; len = eb - pb;
                    cb = 0;
                    if (compare(arr[base], target) < 0) {
                        ofs = 1; lastOfs = 0;
                        while (ofs < len && compare(arr[base + ofs], target) < 0) {
                            lastOfs = ofs; ofs = (ofs << 1) + 1;
                            if (ofs <= 0) ofs = len;
                        }
                        if (ofs > len) ofs = len;
                        left = lastOfs; hi2 = ofs;
                        while (left < hi2) {
                            mid = (left + hi2) >> 1;
                            if (compare(arr[base + mid], target) < 0) left = mid + 1;
                            else hi2 = mid;
                        }
                        cb = left;
                    }
                    // batch copy cb elements from B
                    copyEnd = cb - (cb & 3);
                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                        arr[copyIdx = d + copyI] = arr[tempIdx = pb + copyI];
                        arr[copyIdx + 1] = arr[tempIdx + 1];
                        arr[copyIdx + 2] = arr[tempIdx + 2];
                        arr[copyIdx + 3] = arr[tempIdx + 3];
                    }
                    for (; copyI < cb; copyI++) { arr[d + copyI] = arr[pb + copyI]; }
                    d += cb; pb += cb;
                    if (pb >= eb) break;
                    // copy 1 A trigger element
                    arr[d++] = tempArray[pa++];
                    if (pa >= ea) break;

                    --minGallop;
                } while (ca >= MIN_GALLOP || cb >= MIN_GALLOP);

                if (pa >= ea || pb >= eb) break;
                if (minGallop < 0) minGallop = 0;
                minGallop += 2; // penalty for leaving gallop mode
            }

            // remainder: copy leftover A
            copyLen = ea - pa;
            copyEnd = copyLen - (copyLen & 3);
            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                arr[tempIdx = d + copyI] = tempArray[copyIdx = pa + copyI];
                arr[tempIdx + 1] = tempArray[copyIdx + 1];
                arr[tempIdx + 2] = tempArray[copyIdx + 2];
                arr[tempIdx + 3] = tempArray[copyIdx + 3];
            }
            for (; copyI < copyLen; copyI++) { arr[d + copyI] = tempArray[pa + copyI]; }

        } else {
            // ============ mergeHi: 复制B到tempArray，从右到左合并 ============
            pa = loA + lenA - 1; pb = lenB - 1; d = loB + lenB - 1; ba0 = loA;

            // 复制B到临时数组（×4展开）
            copyEnd = lenB - (lenB & 3);
            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                tempArray[copyI]     = arr[copyIdx = loB + copyI];
                tempArray[copyI + 1] = arr[copyIdx + 1];
                tempArray[copyI + 2] = arr[copyIdx + 2];
                tempArray[copyI + 3] = arr[copyIdx + 3];
            }
            for (; copyI < lenB; copyI++) { tempArray[copyI] = arr[loB + copyI]; }

            // === P0: 标准双阶段合并（反向） ===
            while (pa >= ba0 && pb >= 0) {
                // Phase 1: one-at-a-time (right to left)
                ca = 0; cb = 0;
                while (pa >= ba0 && pb >= 0) {
                    if (compare(arr[pa], tempArray[pb]) > 0) {
                        arr[d--] = arr[pa--];
                        ca++; cb = 0;
                        if (ca >= minGallop) break;
                    } else {
                        arr[d--] = tempArray[pb--];
                        cb++; ca = 0;
                        if (cb >= minGallop) break;
                    }
                }
                if (pa < ba0 || pb < 0) break;

                // Phase 2: galloping (do-while, right to left)
                do {
                    // A-gallop: reverse gallopRight from pa leftward
                    target = tempArray[pb];
                    len = pa - ba0 + 1;
                    ca = 0;
                    if (compare(arr[pa], target) > 0) {
                        if (compare(arr[ba0], target) > 0) {
                            ca = len;
                        } else {
                            ofs = 1; lastOfs = 0;
                            while (ofs < len && compare(arr[pa - ofs], target) > 0) {
                                lastOfs = ofs; ofs = (ofs << 1) + 1;
                                if (ofs <= 0) ofs = len;
                            }
                            if (ofs > len) ofs = len;
                            left = lastOfs; hi2 = ofs;
                            while (left < hi2) {
                                mid = (left + hi2) >> 1;
                                if (compare(arr[pa - mid], target) > 0) left = mid + 1;
                                else hi2 = mid;
                            }
                            ca = left;
                        }
                    }
                    // batch copy ca elements from A (right to left)
                    copyEnd = ca - (ca & 3);
                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                        arr[copyIdx = d - copyI]     = arr[tempIdx = pa - copyI];
                        arr[copyIdx - 1] = arr[tempIdx - 1];
                        arr[copyIdx - 2] = arr[tempIdx - 2];
                        arr[copyIdx - 3] = arr[tempIdx - 3];
                    }
                    for (; copyI < ca; copyI++) { arr[d - copyI] = arr[pa - copyI]; }
                    d -= ca; pa -= ca;
                    if (pa < ba0) break;
                    // copy 1 B trigger element
                    arr[d--] = tempArray[pb--];
                    if (pb < 0) break;

                    // B-gallop: reverse gallopLeft in tempArray from pb leftward
                    // P1 fix: search from RIGHT (pb) since answer is near pb
                    target = arr[pa];
                    len = pb + 1;
                    cb = 0;
                    if (compare(tempArray[pb], target) >= 0) {
                        if (compare(tempArray[0], target) >= 0) {
                            cb = len;
                        } else {
                            ofs = 1; lastOfs = 0;
                            while (ofs < len && compare(tempArray[pb - ofs], target) >= 0) {
                                lastOfs = ofs; ofs = (ofs << 1) + 1;
                                if (ofs <= 0) ofs = len;
                            }
                            if (ofs > len) ofs = len;
                            left = lastOfs; hi2 = ofs;
                            while (left < hi2) {
                                mid = (left + hi2) >> 1;
                                if (compare(tempArray[pb - mid], target) >= 0) left = mid + 1;
                                else hi2 = mid;
                            }
                            cb = left;
                        }
                    }
                    // batch copy cb elements from B (right to left)
                    copyEnd = cb - (cb & 3);
                    for (copyI = 0; copyI < copyEnd; copyI += 4) {
                        arr[copyIdx = d - copyI]     = tempArray[tempIdx = pb - copyI];
                        arr[copyIdx - 1] = tempArray[tempIdx - 1];
                        arr[copyIdx - 2] = tempArray[tempIdx - 2];
                        arr[copyIdx - 3] = tempArray[tempIdx - 3];
                    }
                    for (; copyI < cb; copyI++) { arr[d - copyI] = tempArray[pb - copyI]; }
                    d -= cb; pb -= cb;
                    if (pb < 0) break;
                    // copy 1 A trigger element
                    arr[d--] = arr[pa--];
                    if (pa < ba0) break;

                    --minGallop;
                } while (ca >= MIN_GALLOP || cb >= MIN_GALLOP);

                if (pa < ba0 || pb < 0) break;
                if (minGallop < 0) minGallop = 0;
                minGallop += 2;
            }

            // remainder: copy leftover B
            copyLen = pb + 1;
            copyEnd = copyLen - (copyLen & 3);
            for (copyI = 0; copyI < copyEnd; copyI += 4) {
                arr[copyIdx = d - copyI]     = tempArray[tempIdx = pb - copyI];
                arr[copyIdx - 1] = tempArray[tempIdx - 1];
                arr[copyIdx - 2] = tempArray[tempIdx - 2];
                arr[copyIdx - 3] = tempArray[tempIdx - 3];
            }
            for (; copyI < copyLen; copyI++) { arr[d - copyI] = tempArray[pb - copyI]; }
        }

        // final clamp
        if (minGallop < 1) minGallop = 1;

        // write back shared state
        _sMG = minGallop;
        _sTmp = tempArray;
    }

    // ==============================================================
    //  sort() - 主排序入口
    // ==============================================================
    public static function sort(arr:Array, compareFunction:Function):Array {

        // 变量声明提升（AS2函数作用域）
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
        var left:Number, hi2:Number, mid:Number;
        var stackCapacity:Number;
        var ofs:Number, lastOfs:Number;
        var copyLen:Number, copyI:Number, copyIdx:Number, copyEnd:Number, tempIdx:Number;
        var forceIdx:Number;

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
                if (i <= 8) {
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

        // 设置共享状态
        _sArr = arr; _sCmp = compare; _sTmp = tempArray;
        _sMG = minGallop; _sMGC = MIN_GALLOP; _sN = n;

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
                    if ((i - lo) <= 8) {
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

                mergeAt(loA, lenA, loB, lenB);

                // 回读可能被mergeAt更新的共享状态
                tempArray = _sTmp;
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

            mergeAt(loA, lenA, loB, lenB);
            tempArray = _sTmp;
        }

        // 清理共享状态
        _sArr = null; _sCmp = null; _inUse = false;
        return arr;
    }
}
