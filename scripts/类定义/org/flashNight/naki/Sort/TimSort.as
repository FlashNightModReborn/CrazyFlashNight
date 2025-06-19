class org.flashNight.naki.Sort.TimSort {
    /**
     * 	ActionScript 2.0 标准 TimSort 实现（增强版，含边界修剪优化）
     * 	根据 Python 的 listsort.txt 规范进行重构和优化。
     */
    
    // --- 私有常量 ---
    private static var MIN_MERGE:Number = 32;

    // --- 公共主函数 ---
    public static function sort(arr:Array, compareFunction:Function):Array {
        var n:Number = arr.length;
        if (n < 2) return arr;

        var compare:Function = (compareFunction == null)
            ? function(a, b):Number { return a - b; }
            : compareFunction;

        var state:Object = {
            arr:        arr,
            compare:    compare,
            runStack:   new Array(),
            minRun:     _calculateMinRun(n),
            tempArray:  new Array(Math.ceil(n / 2))
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

    // --- 私有辅助函数 ---
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
            var t:Object = arr[lo];
            arr[lo++] = arr[hi];
            arr[hi--] = t;
        }
    }

    private static function _insertionSort(state:Object, left:Number, right:Number):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        for (var i:Number = left + 1; i <= right; i++) {
            var key:Object = arr[i];
            var j:Number = i - 1;
            while (j >= left && compare(arr[j], key) > 0) {
                arr[j + 1] = arr[j];
                j--;
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

    /**
     * 合并堆栈中索引 i 和 i+1 的两个相邻 run，
     * 并在合并前利用二分搜索对边界进行“修剪”。
     */
    private static function _mergeAt(state:Object, i:Number):Void {
        var stack:Array = state.runStack;
        var arr:Array = state.arr;
        var compare:Function = state.compare;

        // 原始 A 和 B
        var runA:Object = stack[i];
        var runB:Object = stack[i + 1];

        // 1. 边界修剪 —— A 端
        var trimA:Number = _binarySearchLeft(arr, compare, arr[runB.base], runA.base, runA.len);
        var loA:Number = runA.base + trimA;
        var lenA:Number = runA.len - trimA;

        // 2. 边界修剪 —— B 端
        var lastA:Object = arr[loA + lenA - 1];
        var trimB:Number = _binarySearchRight(arr, compare, lastA, runB.base, runB.len);
        var loB:Number = runB.base;
        var lenB:Number = trimB;

        // 若中央区间为空，则仅 collapse 不实际合并
        if (lenA <= 0 || lenB <= 0) {
            stack[i] = {base: runA.base, len: runA.len + runB.len};
            stack.splice(i + 1, 1);
            return;
        }

        // 更新堆栈：整个 A+B 作为一个新 run
        stack[i] = {base: runA.base, len: runA.len + runB.len};
        stack.splice(i + 1, 1);

        // 根据较小的一端选择合并方向
        if (lenA <= lenB) {
            // 复制中央 A 区到临时区
            for (var k:Number = 0; k < lenA; k++) {
                state.tempArray[k] = arr[loA + k];
            }
            // 合并中央区域
            _mergeLo(state, {base: loA, len: lenA}, {base: loB, len: lenB});
        } else {
            // 复制中央 B 区到临时区
            for (var k2:Number = 0; k2 < lenB; k2++) {
                state.tempArray[k2] = arr[loB + k2];
            }
            // 合并中央区域
            _mergeHi(state, {base: loA, len: lenA}, {base: loB, len: lenB});
        }
    }

    private static function _mergeLo(state:Object, runA:Object, runB:Object):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var temp:Array = state.tempArray;
        var dest:Number = runA.base;
        var ptr1:Number = 0;
        var ptr2:Number = runB.base;
        var end2:Number = runB.base + runB.len;
        while (ptr1 < runA.len && ptr2 < end2) {
            if (compare(temp[ptr1], arr[ptr2]) <= 0) {
                arr[dest++] = temp[ptr1++];
            } else {
                arr[dest++] = arr[ptr2++];
            }
        }
        while (ptr1 < runA.len) {
            arr[dest++] = temp[ptr1++];
        }
    }

    private static function _mergeHi(state:Object, runA:Object, runB:Object):Void {
        var arr:Array = state.arr;
        var compare:Function = state.compare;
        var temp:Array = state.tempArray;
        var dest:Number = runB.base + runB.len - 1;
        var ptr1:Number = runA.base + runA.len - 1;
        var ptr2:Number = runB.len - 1;
        while (ptr1 >= runA.base && ptr2 >= 0) {
            if (compare(arr[ptr1], temp[ptr2]) > 0) {
                arr[dest--] = arr[ptr1--];
            } else {
                arr[dest--] = temp[ptr2--];
            }
        }
        while (ptr2 >= 0) {
            arr[dest--] = temp[ptr2--];
        }
    }

    /**
     * 二分查找：在 [base, base+len) 中寻找 value 的左侧插入位置（lower bound）。
     */
    private static function _binarySearchLeft(arr:Array, compare:Function,
                                               value:Object, base:Number, len:Number):Number {
        var lo:Number = 0, hi:Number = len;
        while (lo < hi) {
            var mid:Number = lo + ((hi - lo) >> 1);
            if (compare(arr[base + mid], value) < 0) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        return lo;
    }

    /**
     * 二分查找：在 [base, base+len) 中寻找 value 的右侧插入位置（upper bound）。
     */
    private static function _binarySearchRight(arr:Array, compare:Function,
                                                value:Object, base:Number, len:Number):Number {
        var lo:Number = 0, hi:Number = len;
        while (lo < hi) {
            var mid:Number = lo + ((hi - lo) >> 1);
            if (compare(arr[base + mid], value) <= 0) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        return lo;
    }
}
