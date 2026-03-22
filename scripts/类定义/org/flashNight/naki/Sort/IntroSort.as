/**
 * IntroSort - 精简内省排序（Lean Introsort）
 *
 * - Hoare双指针分区（比DNF更少swap，内循环更紧凑）
 * - 等值元素后聚集（Hoare后扫描pivot边界，平衡重复值场景）
 * - Ninther选轴（大分区中位数的中位数）
 * - 零模式检测（TimSort负责有序场景）
 * - null比较器完全内联，零函数调用
 * - 位运算替代Math.log计算深度限制
 * - 静态栈 + 重入保护
 *
 * 设计目标：验证Hoare分区在AVM1上是否优于DNF三路分区
 */
class org.flashNight.naki.Sort.IntroSort {

    private static var _stack:Array = null;
    private static var _stackCap:Number = 0;
    private static var _inUse:Boolean = false;

    public static function resetState():Void { _inUse = false; }
    private static function _defaultCmp(a, b):Number { var _:Number = a; return a - b; }

    public static function sort(arr:Array, compareFunction:Function):Array {
        var n:Number = arr.length;
        if (n < 2) return arr;

        // 变量声明
        var i:Number, j:Number, k:Number, t:Number, c:Number;
        var tmp:Object, key:Object;
        var sp:Number, depth:Number, maxD:Number;
        var size:Number, mid:Number;
        var pivotVal:Object;
        var left:Number, right:Number;
        var leftLen:Number, rightLen:Number;
        var stack:Array;
        var asc:Boolean, desc:Boolean;
        var root:Number, boundary:Number, lch:Number, rch:Number, largest:Number;
        var cmp:Function;
        var eqL:Number, eqR:Number;

        if (compareFunction == null) {
            // ==========================================================
            // 路径A：内联数值比较 + Hoare分区
            // ==========================================================

            // [1] 预排序检测
            asc = true; desc = true;
            for (i = 1; i < n; i++) {
                if (arr[i - 1] > arr[i]) asc = false;
                if (arr[i - 1] < arr[i]) desc = false;
                if (!(asc || desc)) break;
            }
            if (asc) return arr;
            if (desc) {
                i = 0; j = n - 1;
                while (i < j) { tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp; i++; j--; }
                return arr;
            }

            // [2] 小数组快速路径
            if (n <= 32) {
                for (i = 1; i < n; i++) {
                    key = arr[i]; j = i - 1;
                    tmp = arr[j];
                    if (tmp <= key) continue;
                    arr[--j + 2] = tmp;
                    while (j >= 0) { tmp = arr[j]; if (tmp <= key) break; arr[--j + 2] = tmp; }
                    arr[j + 1] = key;
                }
                return arr;
            }

            // [3] 重入保护
            if (_inUse) { arr.sort(_defaultCmp); return arr; }
            _inUse = true;

            // [4] 栈初始化（位运算替代Math.log）
            maxD = 0; t = n; while (t > 0) { maxD++; t >>= 1; } maxD <<= 1;
            k = (maxD + 4) * 3;
            if (_stackCap < k) { _stack = new Array(k); _stackCap = k; }
            stack = _stack;
            sp = 0;
            stack[sp++] = 0; stack[sp++] = n - 1; stack[sp++] = maxD;

            // [5] 主循环
            while (sp > 0) {
                depth = stack[--sp]; right = stack[--sp]; left = stack[--sp];
                size = right - left + 1;

                // [A] 小分区 → 插入排序
                if (size <= 32) {
                    for (i = left + 1; i <= right; i++) {
                        key = arr[i]; j = i - 1;
                        tmp = arr[j];
                        if (tmp <= key) continue;
                        arr[--j + 2] = tmp;
                        while (j >= left) { tmp = arr[j]; if (tmp <= key) break; arr[--j + 2] = tmp; }
                        arr[j + 1] = key;
                    }
                    continue;
                }

                // [B] 深度耗尽 → 堆排序
                if (depth <= 0) {
                    k = size;
                    for (i = left + ((k >> 1) - 1); i >= left; i--) {
                        root = i;
                        while (true) {
                            lch = (root << 1) - left + 1;
                            if (lch > right) break;
                            rch = lch + 1;
                            largest = (rch <= right && arr[rch] > arr[lch]) ? rch : lch;
                            if (arr[largest] > arr[root]) {
                                tmp = arr[root]; arr[root] = arr[largest]; arr[largest] = tmp;
                                root = largest;
                            } else break;
                        }
                    }
                    for (i = right; i > left; i--) {
                        tmp = arr[left]; arr[left] = arr[i]; arr[i] = tmp;
                        boundary = i - 1; root = left;
                        while (true) {
                            lch = (root << 1) - left + 1;
                            if (lch > boundary) break;
                            rch = lch + 1;
                            largest = (rch <= boundary && arr[rch] > arr[lch]) ? rch : lch;
                            if (arr[largest] > arr[root]) {
                                tmp = arr[root]; arr[root] = arr[largest]; arr[largest] = tmp;
                                root = largest;
                            } else break;
                        }
                    }
                    continue;
                }

                // [C] 选轴：ninther(>128) / median-of-3
                mid = left + ((size - 1) >> 1);
                if (size > 128) {
                    t = size >> 3;
                    k = left + t; j = left + t + t;
                    if (arr[left] > arr[k]) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; }
                    if (arr[k] > arr[j]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp;
                        if (arr[left] > arr[k]) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; } }
                    tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp;
                    k = mid - t; j = mid + t;
                    if (arr[k] > arr[mid]) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; }
                    if (arr[mid] > arr[j]) { tmp = arr[mid]; arr[mid] = arr[j]; arr[j] = tmp;
                        if (arr[k] > arr[mid]) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; } }
                    k = right - t - t; j = right - t;
                    if (arr[k] > arr[j]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp; }
                    if (arr[j] > arr[right]) { tmp = arr[j]; arr[j] = arr[right]; arr[right] = tmp;
                        if (arr[k] > arr[j]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp; } }
                    tmp = arr[right]; arr[right] = arr[j]; arr[j] = tmp;
                }
                // median-of-3 排序：arr[left] <= arr[mid] <= arr[right]
                if (arr[left] > arr[mid]) { tmp = arr[left]; arr[left] = arr[mid]; arr[mid] = tmp; }
                if (arr[left] > arr[right]) { tmp = arr[left]; arr[left] = arr[right]; arr[right] = tmp; }
                if (arr[mid] > arr[right]) { tmp = arr[mid]; arr[mid] = arr[right]; arr[right] = tmp; }

                // [D] 自适应分区：样本等值检测决定Hoare或DNF
                if (arr[left] === arr[mid] || arr[mid] === arr[right]) {
                    // ---- 重复值模式 → DNF三路分区 ----
                    tmp = arr[left]; arr[left] = arr[mid]; arr[mid] = tmp;
                    pivotVal = arr[left];
                    eqL = left + 1; eqR = right; k = left + 1;
                    while (k <= eqR) {
                        tmp = arr[k];
                        if (tmp < pivotVal) {
                            arr[k] = arr[eqL]; arr[eqL] = tmp;
                            eqL++; k++;
                        } else if (tmp > pivotVal) {
                            arr[k] = arr[eqR]; arr[eqR] = tmp;
                            eqR--;
                        } else { k++; }
                    }
                    eqL--;
                    tmp = arr[left]; arr[left] = arr[eqL]; arr[eqL] = tmp;
                    // arr[left..eqL-1] < pivot, arr[eqL..eqR] == pivot, arr[eqR+1..right] > pivot
                    depth--;
                    leftLen = eqL - 1 - left;
                    rightLen = right - eqR;
                    t = size >> 3;
                    if (leftLen < t || rightLen < t) depth--;
                    if (leftLen <= rightLen) {
                        if (eqR + 1 < right) { stack[sp++] = eqR + 1; stack[sp++] = right; stack[sp++] = depth; }
                        if (left < eqL - 1) { stack[sp++] = left; stack[sp++] = eqL - 1; stack[sp++] = depth; }
                    } else {
                        if (left < eqL - 1) { stack[sp++] = left; stack[sp++] = eqL - 1; stack[sp++] = depth; }
                        if (eqR + 1 < right) { stack[sp++] = eqR + 1; stack[sp++] = right; stack[sp++] = depth; }
                    }
                } else {
                    // ---- 唯一值模式 → Hoare双指针分区 ----
                    // pivot留在arr[mid]，arr[left]和arr[right]为自然哨兵
                    pivotVal = arr[mid];
                    i = left; j = right + 1;
                    while (true) {
                        while (arr[++i] < pivotVal) {}
                        while (arr[--j] > pivotVal) {}
                        if (i >= j) break;
                        tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp;
                    }
                    // 等值后聚集：扫描j附近
                    eqL = j;
                    while (eqL > left && arr[eqL] === pivotVal) eqL--;
                    eqR = j + 1;
                    while (eqR <= right && arr[eqR] === pivotVal) eqR++;
                    depth--;
                    leftLen = eqL - left + 1;
                    rightLen = right - eqR + 1;
                    t = size >> 3;
                    if (leftLen < t || rightLen < t) depth--;
                    if (leftLen <= rightLen) {
                        if (eqR <= right) { stack[sp++] = eqR; stack[sp++] = right; stack[sp++] = depth; }
                        if (left <= eqL) { stack[sp++] = left; stack[sp++] = eqL; stack[sp++] = depth; }
                    } else {
                        if (left <= eqL) { stack[sp++] = left; stack[sp++] = eqL; stack[sp++] = depth; }
                        if (eqR <= right) { stack[sp++] = eqR; stack[sp++] = right; stack[sp++] = depth; }
                    }
                }
            }

            _inUse = false;
            return arr;

        } else {
            // ==========================================================
            // 路径B：自定义比较器 + Hoare分区
            // ==========================================================
            cmp = compareFunction;

            asc = true; desc = true;
            for (i = 1; i < n; i++) {
                c = cmp(arr[i - 1], arr[i]);
                if (c > 0) asc = false;
                if (c < 0) desc = false;
                if (!(asc || desc)) break;
            }
            if (asc) return arr;
            if (desc) {
                i = 0; j = n - 1;
                while (i < j) { tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp; i++; j--; }
                return arr;
            }

            if (n <= 32) {
                for (i = 1; i < n; i++) {
                    key = arr[i]; j = i - 1;
                    tmp = arr[j];
                    if (cmp(tmp, key) <= 0) continue;
                    if (i <= 4) {
                        arr[--j + 2] = tmp;
                        while (j >= 0) { tmp = arr[j]; if (cmp(tmp, key) <= 0) break; arr[--j + 2] = tmp; }
                        arr[j + 1] = key;
                    } else {
                        left = 0; right = j;
                        while (left < right) { mid = (left + right) >> 1; if (cmp(arr[mid], key) <= 0) left = mid + 1; else right = mid; }
                        j = i; while (j > left) { arr[j] = arr[--j]; } arr[left] = key;
                    }
                }
                return arr;
            }

            if (_inUse) { arr.sort(cmp); return arr; }
            _inUse = true;

            maxD = 0; t = n; while (t > 0) { maxD++; t >>= 1; } maxD <<= 1;
            k = (maxD + 4) * 3;
            if (_stackCap < k) { _stack = new Array(k); _stackCap = k; }
            stack = _stack;
            sp = 0;
            stack[sp++] = 0; stack[sp++] = n - 1; stack[sp++] = maxD;

            while (sp > 0) {
                depth = stack[--sp]; right = stack[--sp]; left = stack[--sp];
                size = right - left + 1;

                if (size <= 32) {
                    for (i = left + 1; i <= right; i++) {
                        key = arr[i]; j = i - 1;
                        tmp = arr[j];
                        if (cmp(tmp, key) <= 0) continue;
                        if ((i - left) <= 4) {
                            arr[--j + 2] = tmp;
                            while (j >= left) { tmp = arr[j]; if (cmp(tmp, key) <= 0) break; arr[--j + 2] = tmp; }
                            arr[j + 1] = key;
                        } else {
                            k = left; t = j;
                            while (k < t) { mid = (k + t) >> 1; if (cmp(arr[mid], key) <= 0) k = mid + 1; else t = mid; }
                            j = i; while (j > k) { arr[j] = arr[--j]; } arr[k] = key;
                        }
                    }
                    continue;
                }

                if (depth <= 0) {
                    k = size;
                    for (i = left + ((k >> 1) - 1); i >= left; i--) {
                        root = i;
                        while (true) {
                            lch = (root << 1) - left + 1;
                            if (lch > right) break;
                            rch = lch + 1;
                            largest = (rch <= right && cmp(arr[rch], arr[lch]) > 0) ? rch : lch;
                            if (cmp(arr[largest], arr[root]) > 0) {
                                tmp = arr[root]; arr[root] = arr[largest]; arr[largest] = tmp;
                                root = largest;
                            } else break;
                        }
                    }
                    for (i = right; i > left; i--) {
                        tmp = arr[left]; arr[left] = arr[i]; arr[i] = tmp;
                        boundary = i - 1; root = left;
                        while (true) {
                            lch = (root << 1) - left + 1;
                            if (lch > boundary) break;
                            rch = lch + 1;
                            largest = (rch <= boundary && cmp(arr[rch], arr[lch]) > 0) ? rch : lch;
                            if (cmp(arr[largest], arr[root]) > 0) {
                                tmp = arr[root]; arr[root] = arr[largest]; arr[largest] = tmp;
                                root = largest;
                            } else break;
                        }
                    }
                    continue;
                }

                mid = left + ((size - 1) >> 1);
                if (size > 128) {
                    t = size >> 3;
                    k = left + t; j = left + t + t;
                    if (cmp(arr[left], arr[k]) > 0) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; }
                    if (cmp(arr[k], arr[j]) > 0) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp;
                        if (cmp(arr[left], arr[k]) > 0) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; } }
                    tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp;
                    k = mid - t; j = mid + t;
                    if (cmp(arr[k], arr[mid]) > 0) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; }
                    if (cmp(arr[mid], arr[j]) > 0) { tmp = arr[mid]; arr[mid] = arr[j]; arr[j] = tmp;
                        if (cmp(arr[k], arr[mid]) > 0) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; } }
                    k = right - t - t; j = right - t;
                    if (cmp(arr[k], arr[j]) > 0) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp; }
                    if (cmp(arr[j], arr[right]) > 0) { tmp = arr[j]; arr[j] = arr[right]; arr[right] = tmp;
                        if (cmp(arr[k], arr[j]) > 0) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp; } }
                    tmp = arr[right]; arr[right] = arr[j]; arr[j] = tmp;
                }
                if (cmp(arr[left], arr[mid]) > 0) { tmp = arr[left]; arr[left] = arr[mid]; arr[mid] = tmp; }
                if (cmp(arr[left], arr[right]) > 0) { tmp = arr[left]; arr[left] = arr[right]; arr[right] = tmp; }
                if (cmp(arr[mid], arr[right]) > 0) { tmp = arr[mid]; arr[mid] = arr[right]; arr[right] = tmp; }
                tmp = arr[left]; arr[left] = arr[mid]; arr[mid] = tmp;
                pivotVal = arr[left];

                // DNF三路分区（比较器路径：函数调用开销压倒swap开销，DNF最优）
                eqL = left + 1; eqR = right; k = left + 1;
                while (k <= eqR) {
                    c = cmp(arr[k], pivotVal);
                    if (c < 0) {
                        tmp = arr[k]; arr[k] = arr[eqL]; arr[eqL] = tmp;
                        eqL++; k++;
                    } else if (c > 0) {
                        tmp = arr[k]; arr[k] = arr[eqR]; arr[eqR] = tmp;
                        eqR--;
                    } else { k++; }
                }
                eqL--;
                tmp = arr[left]; arr[left] = arr[eqL]; arr[eqL] = tmp;

                depth--;
                leftLen = eqL - 1 - left;
                rightLen = right - eqR;
                t = size >> 3;
                if (leftLen < t || rightLen < t) depth--;

                if (leftLen <= rightLen) {
                    if (eqR + 1 < right) { stack[sp++] = eqR + 1; stack[sp++] = right; stack[sp++] = depth; }
                    if (left < eqL - 1) { stack[sp++] = left; stack[sp++] = eqL - 1; stack[sp++] = depth; }
                } else {
                    if (left < eqL - 1) { stack[sp++] = left; stack[sp++] = eqL - 1; stack[sp++] = depth; }
                    if (eqR + 1 < right) { stack[sp++] = eqR + 1; stack[sp++] = right; stack[sp++] = depth; }
                }
            }

            _inUse = false;
            return arr;
        }
    }
}
