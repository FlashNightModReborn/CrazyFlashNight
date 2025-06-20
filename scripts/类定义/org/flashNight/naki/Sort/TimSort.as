/**
 * ActionScript 2.0 标准 TimSort 实现（s算法特性集成，已优化 mergeLo 与 mergeHi）
 *
 * 本版本对 _mergeLo 与 _mergeHi 进行了循环拆分（Loop Unswitching）和状态缓存优化，
 * 将常用 state 属性缓存为局部变量，并分离普通合并与疾速模式的逻辑。
 */
class org.flashNight.naki.Sort.TimSort {
    private static var MIN_MERGE:Number = 32;
    private static var MIN_GALLOP:Number = 7;

    public static function sort(arr:Array, compareFunction:Function):Array {
        var n:Number = arr.length;
        if (n < 2) return arr;
        var compare:Function = (compareFunction == null)
            ? function(a, b):Number { return a - b; }
            : compareFunction;
        var tempArray:Array = new Array(Math.ceil(n / 2));
        var state:Object = {
            arr:        arr,
            compare:    compare,
            runStack:   new Array(),
            minRun:     _calculateMinRun(n),
            tempArray:  tempArray,
            minGallop:  MIN_GALLOP
        };
        var remaining:Number = n;
        var lo:Number = 0;
        while (remaining > 0) {
            var runLen:Number = _countRunAndReverse(state, lo);
            if (runLen < state.minRun) {
                var force:Number = (remaining < state.minRun) ? remaining : state.minRun;
                _insertionSort(state, lo, lo + force - 1);
                runLen = force;
            }
            state.runStack.push({base: lo, len: runLen});
            _mergeCollapse(state);
            lo += runLen;
            remaining -= runLen;
        }
        _mergeForceCollapse(state);
        return arr;
    }

    private static function _calculateMinRun(n:Number):Number {
        var r:Number = 0;
        while (n >= MIN_MERGE) {
            r |= (n & 1);
            n >>= 1;
        }
        return n + r;
    }

    private static function _countRunAndReverse(state:Object, lo:Number):Number {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var hi:Number = lo + 1;
        if (hi >= arr.length) return 1;
        if (compare(arr[lo], arr[hi++]) > 0) {
            while (hi < arr.length && compare(arr[hi - 1], arr[hi]) > 0) { hi++; }
            _reverseRange(arr, lo, hi - 1);
        } else {
            while (hi < arr.length && compare(arr[hi - 1], arr[hi]) <= 0) { hi++; }
        }
        return hi - lo;
    }

    private static function _reverseRange(arr:Array, lo:Number, hi:Number):Void {
        while (lo < hi) {
            var t:Object = arr[lo]; arr[lo++] = arr[hi]; arr[hi--] = t;
        }
    }

    private static function _insertionSort(state:Object, left:Number, right:Number):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        for (var i:Number = left + 1; i <= right; i++) {
            var key:Object = arr[i];
            var j:Number = i - 1;
            while (j >= left && compare(arr[j], key) > 0) {
                arr[j + 1] = arr[j]; j--;
            }
            arr[j + 1] = key;
        }
    }

    private static function _mergeCollapse(state:Object):Void {
        var stack:Array = state.runStack;
        while (stack.length > 1) {
            var n:Number = stack.length - 2;
            if (n > 0 && stack[n - 1].len <= stack[n].len + stack[n + 1].len) {
                if (stack[n - 1].len < stack[n + 1].len) {
                    _mergeAt(state, n - 1);
                } else {
                    _mergeAt(state, n);
                }
            } else if (stack[n].len <= stack[n + 1].len) {
                _mergeAt(state, n);
            } else {
                break;
            }
        }
    }

    private static function _mergeForceCollapse(state:Object):Void {
        var stack:Array = state.runStack;
        while (stack.length > 1) {
            var n:Number = stack.length - 2;
            if (n > 0 && stack[n - 1].len < stack[n + 1].len) {
                _mergeAt(state, n - 1);
            } else {
                _mergeAt(state, n);
            }
        }
    }

    private static function _mergeAt(state:Object, i:Number):Void {
        var stack:Array = state.runStack;
        var runA:Object = stack[i];
        var runB:Object = stack[i + 1];
        stack[i] = {base: runA.base, len: runA.len + runB.len};
        stack.splice(i + 1, 1);
        var arr:Array = state.arr;
        var k:Number = _gallopRight(state, arr[runB.base], arr, runA.base, runA.len);
        var loA:Number = runA.base + k;
        var lenA:Number = runA.len - k;
        if (lenA == 0) return;
        k = _gallopLeft(state, arr[loA + lenA - 1], arr, runB.base, runB.len);
        var lenB:Number = k;
        if (lenB == 0) return;
        if (lenA <= lenB) {
            _mergeLo(state, {base: loA, len: lenA}, {base: runB.base, len: lenB});
        } else {
            _mergeHi(state, {base: loA, len: lenA}, {base: runB.base, len: lenB});
        }
    }

    /**
     * 优化版 mergeLo：分离普通合并与疾速模式，缓存状态为局部变量
     */
    private static function _mergeLo(state:Object, runA:Object, runB:Object):Void {
        var arr:Array        = state.arr;
        var compare:Function = state.compare;
        var temp:Array       = state.tempArray;
        var minGallop:Number = state.minGallop;

        // 复制 runA 到临时
        for (var i:Number = 0; i < runA.len; i++) {
            temp[i] = arr[runA.base + i];
        }
        var ptrA:Number   = 0;
        var ptrB:Number   = runB.base;
        var dest:Number   = runA.base;
        var endA:Number   = runA.len;
        var endB:Number   = runB.base + runB.len;
        var countA:Number = 0;
        var countB:Number = 0;

        // 普通合并循环：无疾速检查
        while (ptrA < endA && ptrB < endB && countA < minGallop && countB < minGallop) {
            if (compare(temp[ptrA], arr[ptrB]) <= 0) {
                arr[dest++] = temp[ptrA++];
                countA++; countB = 0;
            } else {
                arr[dest++] = arr[ptrB++];
                countB++; countA = 0;
            }
        }

        // 混合模式：当触发疾速或仍有元素未处理
        while (ptrA < endA && ptrB < endB) {
            var k:Number;
            // runA 疾速
            if (countA >= minGallop) {
                k = _gallopRight(state, temp[ptrA], arr, ptrB, endB - ptrB);
                for (var j:Number = 0; j < k; j++) {
                    arr[dest + j] = arr[ptrB + j];
                }
                dest += k; ptrB += k;
                countA = 0;
                if (k < MIN_GALLOP) minGallop++;
                minGallop = Math.max(1, minGallop - 1);
            }
            // runB 疾速
            else if (countB >= minGallop) {
                k = _gallopLeft(state, arr[ptrB], temp, ptrA, endA - ptrA);
                for (var j2:Number = 0; j2 < k; j2++) {
                    arr[dest + j2] = temp[ptrA + j2];
                }
                dest += k; ptrA += k;
                countB = 0;
                if (k < MIN_GALLOP) minGallop++;
                minGallop = Math.max(1, minGallop - 1);
            }
            else {
                // 回到普通合并直至再次触发
                while (ptrA < endA && ptrB < endB && countA < minGallop && countB < minGallop) {
                    if (compare(temp[ptrA], arr[ptrB]) <= 0) {
                        arr[dest++] = temp[ptrA++];
                        countA++; countB = 0;
                    } else {
                        arr[dest++] = arr[ptrB++];
                        countB++; countA = 0;
                    }
                }
            }
        }

        // 余下元素
        if (ptrA < endA) {
            for (var m:Number = 0; m < endA - ptrA; m++) {
                arr[dest + m] = temp[ptrA + m];
            }
        }

        state.minGallop = minGallop;
    }

    /**
     * 优化版 mergeHi：分离普通合并与疾速模式，缓存状态为局部变量
     */
    private static function _mergeHi(state:Object, runA:Object, runB:Object):Void {
        var arr:Array        = state.arr;
        var compare:Function = state.compare;
        var temp:Array       = state.tempArray;
        var minGallop:Number = state.minGallop;

        // 复制 runB 到临时
        for (var i:Number = 0; i < runB.len; i++) {
            temp[i] = arr[runB.base + i];
        }
        var ptrA:Number   = runA.base + runA.len - 1;
        var ptrB:Number   = runB.len - 1;
        var dest:Number   = runB.base   + runB.len - 1;
        var baseA:Number  = runA.base;
        var baseB:Number  = 0;
        var countA:Number = 0;
        var countB:Number = 0;

        // 普通逆向合并循环
        while (ptrA >= baseA && ptrB >= baseB && countA < minGallop && countB < minGallop) {
            if (compare(arr[ptrA], temp[ptrB]) > 0) {
                arr[dest--] = arr[ptrA--];
                countA++; countB = 0;
            } else {
                arr[dest--] = temp[ptrB--];
                countB++; countA = 0;
            }
        }

        // 混合模式
        while (ptrA >= baseA && ptrB >= baseB) {
            var k2:Number;
            if (countA >= minGallop) {
                var lenToSearch1:Number = ptrA - baseA + 1;
                k2 = lenToSearch1 - _gallopLeft(state, temp[ptrB], arr, baseA, lenToSearch1);
                for (var j3:Number = 0; j3 < k2; j3++) {
                    arr[dest - j3] = arr[ptrA - j3];
                }
                dest -= k2; ptrA -= k2;
                countA = 0;
                if (k2 < MIN_GALLOP) minGallop++;
                minGallop = Math.max(1, minGallop - 1);
            }
            else if (countB >= minGallop) {
                var lenToSearch2:Number = ptrB - baseB + 1;
                k2 = lenToSearch2 - _gallopLeft(state, arr[ptrA], temp, baseB, lenToSearch2);
                for (var j4:Number = 0; j4 < k2; j4++) {
                    arr[dest - j4] = temp[ptrB - j4];
                }
                dest -= k2; ptrB -= k2;
                countB = 0;
                if (k2 < MIN_GALLOP) minGallop++;
                minGallop = Math.max(1, minGallop - 1);
            }
            else {
                while (ptrA >= baseA && ptrB >= baseB && countA < minGallop && countB < minGallop) {
                    if (compare(arr[ptrA], temp[ptrB]) > 0) {
                        arr[dest--] = arr[ptrA--];
                        countA++; countB = 0;
                    } else {
                        arr[dest--] = temp[ptrB--];
                        countB++; countA = 0;
                    }
                }
            }
        }

        // 余下元素
        if (ptrB >= baseB) {
            for (var m2:Number = 0; m2 <= ptrB - baseB; m2++) {
                arr[dest - m2] = temp[ptrB - m2];
            }
        }

        state.minGallop = minGallop;
    }

    // 以下 _gallopRight, _gallopLeft, _binarySearchLeft, _binarySearchRight 同原实现，不变
    private static function _gallopRight(state:Object, key:Object, a:Array, base:Number, len:Number):Number {
        var compare:Function = state.compare;
        var ofs:Number = 1, lastOfs:Number = 0;
        if (len == 0 || compare(a[base], key) >= 0) return 0;
        while (ofs < len && compare(a[base + ofs], key) < 0) {
            lastOfs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = len;
        }
        if (ofs > len) ofs = len;
        return lastOfs + _binarySearchLeft(a, compare, key, base + lastOfs, ofs - lastOfs);
    }
    private static function _gallopLeft(state:Object, key:Object, a:Array, base:Number, len:Number):Number {
        var compare:Function = state.compare;
        var ofs:Number = 1, lastOfs:Number = 0;
        if (len == 0 || compare(a[base], key) > 0) return 0;
        while (ofs < len && compare(a[base + ofs], key) <= 0) {
            lastOfs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = len;
        }
        if (ofs > len) ofs = len;
        return lastOfs + _binarySearchRight(a, compare, key, base + lastOfs, ofs - lastOfs);
    }
    private static function _binarySearchLeft(arr:Array, compare:Function, value:Object, base:Number, len:Number):Number {
        var lo:Number = 0, hi:Number = len;
        while (lo < hi) {
            var mid:Number = lo + ((hi - lo) >> 1);
            if (compare(arr[base + mid], value) < 0) lo = mid + 1; else hi = mid;
        }
        return lo;
    }
    private static function _binarySearchRight(arr:Array, compare:Function, value:Object, base:Number, len:Number):Number {
        var lo:Number = 0, hi:Number = len;
        while (lo < hi) {
            var mid:Number = lo + ((hi - lo) >> 1);
            if (compare(arr[base + mid], value) <= 0) lo = mid + 1; else hi = mid;
        }
        return lo;
    }
}
