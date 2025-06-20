
/**
 * ActionScript 2.0 标准 TimSort 实现（优化对象创建开销，彻底消除 _mergeAt 的临时对象）
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
        // 并行数组管理 run 栈
        var runBase:Array = [];
        var runLen:Array  = [];
        var stackSize:Number = 0;

        var state:Object = {
            arr:        arr,
            compare:    compare,
            runBase:    runBase,
            runLen:     runLen,
            stackSize:  stackSize,
            minRun:     _calculateMinRun(n),
            tempArray:  tempArray,
            minGallop:  MIN_GALLOP
        };

        var remaining:Number = n;
        var lo:Number = 0;
        while (remaining > 0) {
            var runLength:Number = _countRunAndReverse(state, lo);
            if (runLength < state.minRun) {
                var force:Number = (remaining < state.minRun) ? remaining : state.minRun;
                _insertionSort(state, lo, lo + force - 1);
                runLength = force;
            }
            // push to parallel arrays
            state.runBase[state.stackSize] = lo;
            state.runLen[state.stackSize]  = runLength;
            state.stackSize++;

            _mergeCollapse(state);

            lo += runLength;
            remaining -= runLength;
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
            while (hi < arr.length && compare(arr[hi - 1], arr[hi]) > 0) hi++;
            _reverseRange(arr, lo, hi - 1);
        } else {
            while (hi < arr.length && compare(arr[hi - 1], arr[hi]) <= 0) hi++;
        }
        return hi - lo;
    }

    private static function _reverseRange(arr:Array, lo:Number, hi:Number):Void {
        while (lo < hi) {
            var tmp:Object = arr[lo]; arr[lo++] = arr[hi]; arr[hi--] = tmp;
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
        var length:Array = state.runLen;
        var size:Number = state.stackSize;

        while (size > 1) {
            var n:Number = size - 2;
            if (n > 0 && length[n - 1] <= length[n] + length[n + 1]) {
                if (length[n - 1] < length[n + 1]) {
                    _mergeAt(state, n - 1);
                } else {
                    _mergeAt(state, n);
                }
            } else if (length[n] <= length[n + 1]) {
                _mergeAt(state, n);
            } else {
                break;
            }
            size = state.stackSize;
        }
    }

    private static function _mergeForceCollapse(state:Object):Void {
        while (state.stackSize > 1) {
            var n:Number = state.stackSize - 2;
            if (n > 0 && state.runLen[n - 1] < state.runLen[n + 1]) {
                _mergeAt(state, n - 1);
            } else {
                _mergeAt(state, n);
            }
        }
    }

    private static function _mergeAt(state:Object, i:Number):Void {
        var baseArr:Array   = state.runBase;
        var lengthArr:Array = state.runLen;
        var arr:Array       = state.arr;

        // 取出 A、B 两个 run 的起始与长度
        var loA:Number = baseArr[i];
        var lenA:Number = lengthArr[i];
        var loB:Number = baseArr[i + 1];
        var lenB:Number = lengthArr[i + 1];

        // 合并后新 run 长度
        lengthArr[i] = lenA + lenB;
        // 左移 stack 中后续元素
        for (var j:Number = i + 1; j < state.stackSize - 1; j++) {
            baseArr[j]   = baseArr[j + 1];
            lengthArr[j] = lengthArr[j + 1];
        }
        state.stackSize--;

        // 边界修剪
        var k:Number = _gallopRight(state, arr[loB], arr, loA, lenA);
        loA += k; lenA -= k;
        if (lenA == 0) return;

        k = _gallopLeft(state, arr[loA + lenA - 1], arr, loB, lenB);
        lenB = k;
        if (lenB == 0) return;

        // 根据长度选择合并方向，并直接传递四个数值参数
        if (lenA <= lenB) {
            _mergeLo(state, loA, lenA, loB, lenB);
        } else {
            _mergeHi(state, loA, lenA, loB, lenB);
        }
    }

    /**
     * _mergeLo(state, baseA, lenA, baseB, lenB)
     */
    private static function _mergeLo(state:Object, baseA:Number, lenA:Number, baseB:Number, lenB:Number):Void {
        var arr:Array        = state.arr;
        var compare:Function = state.compare;
        var temp:Array       = state.tempArray;
        var minGallop:Number = state.minGallop;

        // 复制 A 到 temp
        for (var i:Number = 0; i < lenA; i++) {
            temp[i] = arr[baseA + i];
        }

        var ptrA:Number   = 0;
        var ptrB:Number   = baseB;
        var dest:Number   = baseA;
        var endA:Number   = lenA;
        var endB:Number   = baseB + lenB;
        var countA:Number = 0;
        var countB:Number = 0;

        // 普通合并
        while (ptrA < endA && ptrB < endB && countA < minGallop && countB < minGallop) {
            if (compare(temp[ptrA], arr[ptrB]) <= 0) {
                arr[dest++] = temp[ptrA++];
                countA++; countB = 0;
            } else {
                arr[dest++] = arr[ptrB++];
                countB++; countA = 0;
            }
        }

        // 混合模式合并
        while (ptrA < endA && ptrB < endB) {
            var k:Number;
            // A 疾速合并到 B 前
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
            // B 疾速合并到 A 前
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
            // 回退到普通合并
            else {
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

        // 如果 A 有剩余，复制回去
        if (ptrA < endA) {
            for (var m:Number = 0; m < endA - ptrA; m++) {
                arr[dest + m] = temp[ptrA + m];
            }
        }

        state.minGallop = minGallop;
    }

    /**
     * _mergeHi(state, baseA, lenA, baseB, lenB)
     */
    private static function _mergeHi(state:Object, baseA:Number, lenA:Number, baseB:Number, lenB:Number):Void {
        var arr:Array        = state.arr;
        var compare:Function = state.compare;
        var temp:Array       = state.tempArray;
        var minGallop:Number = state.minGallop;

        // 复制 B 到 temp
        for (var i:Number = 0; i < lenB; i++) {
            temp[i] = arr[baseB + i];
        }

        var ptrA:Number   = baseA + lenA - 1;
        var ptrB:Number   = lenB - 1;
        var dest:Number   = baseB + lenB - 1;
        var baseA0:Number = baseA;
        var baseB0:Number = 0;
        var countA:Number = 0;
        var countB:Number = 0;

        // 普通逆向合并
        while (ptrA >= baseA0 && ptrB >= baseB0 && countA < minGallop && countB < minGallop) {
            if (compare(arr[ptrA], temp[ptrB]) > 0) {
                arr[dest--] = arr[ptrA--];
                countA++; countB = 0;
            } else {
                arr[dest--] = temp[ptrB--];
                countB++; countA = 0;
            }
        }

        // 混合模式逆向合并
        while (ptrA >= baseA0 && ptrB >= baseB0) {
            var k2:Number;
            if (countA >= minGallop) {
                var lenToSearch1:Number = ptrA - baseA0 + 1;
                k2 = lenToSearch1 - _gallopLeft(state, temp[ptrB], arr, baseA0, lenToSearch1);
                for (var j3:Number = 0; j3 < k2; j3++) {
                    arr[dest - j3] = arr[ptrA - j3];
                }
                dest -= k2; ptrA -= k2;
                countA = 0;
                if (k2 < MIN_GALLOP) minGallop++;
                minGallop = Math.max(1, minGallop - 1);
            }
            else if (countB >= minGallop) {
                var lenToSearch2:Number = ptrB - baseB0 + 1;
                k2 = lenToSearch2 - _gallopLeft(state, arr[ptrA], temp, baseB0, lenToSearch2);
                for (var j4:Number = 0; j4 < k2; j4++) {
                    arr[dest - j4] = temp[ptrB - j4];
                }
                dest -= k2; ptrB -= k2;
                countB = 0;
                if (k2 < MIN_GALLOP) minGallop++;
                minGallop = Math.max(1, minGallop - 1);
            }
            else {
                while (ptrA >= baseA0 && ptrB >= baseB0 && countA < minGallop && countB < minGallop) {
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

        // 如果 B 有剩余，复制回去
        if (ptrB >= baseB0) {
            for (var m2:Number = 0; m2 <= ptrB - baseB0; m2++) {
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
            lastOfs = ofs;
            ofs = (ofs << 1) + 1;
            if (ofs <= 0) ofs = len;
        }
        if (ofs > len) ofs = len;
        return lastOfs + _binarySearchLeft(a, compare, key, base + lastOfs, ofs - lastOfs);
    }

    private static function _gallopLeft(state:Object, key:Object, a:Array, base:Number, len:Number):Number {
        var compare:Function = state.compare;
        var ofs:Number = 1, lastOfs:Number = 0;
        if (len == 0 || compare(a[base], key) > 0) return 0;
        while (ofs < len && compare(a[base + ofs], key) <= 0) {
            lastOfs = ofs;
            ofs = (ofs << 1) + 1;
            if (ofs <= 0) ofs = len;
        }
        if (ofs > len) ofs = len;
        return lastOfs + _binarySearchRight(a, compare, key, base + lastOfs, ofs - lastOfs);
    }

    private static function _binarySearchLeft(arr:Array, compare:Function, value:Object, base:Number, len:Number):Number {
        var lo:Number = 0, hi:Number = len;
        while (lo < hi) {
            var mid:Number = lo + ((hi - lo) >> 1);
            if (compare(arr[base + mid], value) < 0) lo = mid + 1;
            else hi = mid;
        }
        return lo;
    }

    private static function _binarySearchRight(arr:Array, compare:Function, value:Object, base:Number, len:Number):Number {
        var lo:Number = 0, hi:Number = len;
        while (lo < hi) {
            var mid:Number = lo + ((hi - lo) >> 1);
            if (compare(arr[base + mid], value) <= 0) lo = mid + 1;
            else hi = mid;
        }
        return lo;
    }
}

