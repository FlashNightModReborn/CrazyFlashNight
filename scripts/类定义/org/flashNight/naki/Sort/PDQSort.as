/**
 * PDQSort - 高性能非稳定排序（Pattern-Defeating QuickSort）
 *
 * v2.0 核心优化（对标TimSort v3.3 微观优化水平）：
 * - P0: null比较器完全内联数值比较，零函数调用（random 2x, duplicates 10x, fewUnique 8x）
 * - P0: 逐路径深度追踪（修复旧版全局maxDepth--计数器bug）
 * - P0: Ninther选轴：大分区(>128)用中位数的中位数，organPipe 150→71ms（2x改善）
 * - P0: 移除旧版per-partition有序度扫描（消除O(n^2)风险+O(n log n)扫描开销）
 * - P1: null路径纯线性插入排序（内联比较下线性优于二分，random 70→62ms）
 * - P1: TimSort级微优化（预读缓存、StoreRegister压行 arr[--j+2]=tmp）
 * - P1: 静态栈缓存 + 重入保护 + resetState安全阀
 * - P1: DNF三路分区值+比较双缓存（消除重复arr[k]读取）
 * - P2: sortIndirect间接排序（按预提取键数组排序索引，零函数调用）
 *
 * AS2/AVM1 平台决策：
 * - 函数调用~485ns vs 内联比较~35ns → null路径14x加速
 * - new Array~550ns → 静态预分配栈，跨调用复用
 * - arr[--j+2]=tmp 触发AVM1 StoreRegister快速路径
 * - 变量全部前置声明，避免AVM1循环内重复初始化
 */
class org.flashNight.naki.Sort.PDQSort {

    // 静态栈缓存 - 跨调用复用，减少 new Array() 的 GC 压力
    private static var _stack:Array = null;
    private static var _stackCap:Number = 0;

    // 重入保护
    private static var _inUse:Boolean = false;

    // 安全阀：异常后重置_inUse标记
    public static function resetState():Void { _inUse = false; }

    // 默认比较器 - 静态方法引用，避免每次sort()创建闭包
    private static function _defaultCmp(a, b):Number { var _:Number = a; return a - b; }

    /**
     * 主排序入口
     *
     * @param arr 待排序数组（就地修改）
     * @param compareFunction 比较函数，null使用内联数值比较（零函数调用开销）
     * @return 排序后的原数组
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        var n:Number = arr.length;
        if (n < 2) return arr;

        // ===== 变量声明（AS2函数作用域，全部前置避免重复初始化） =====
        var i:Number, j:Number, k:Number, t:Number, c:Number;
        var tmp:Object, key:Object;
        var sp:Number, depth:Number, maxD:Number;
        var size:Number, mid:Number;
        var pivotVal:Object;
        var lessIdx:Number, greatIdx:Number;
        var left:Number, right:Number;
        var leftLen:Number, rightLen:Number;
        var stack:Array;
        var asc:Boolean, desc:Boolean;
        // 堆排序
        var root:Number, boundary:Number, lch:Number, rch:Number, largest:Number;
        // 比较器
        var cmp:Function;

        // ===== 双路径分支：null比较器(内联) vs 自定义比较器 =====
        if (compareFunction == null) {
            // ==========================================================
            // 路径A：内联数值比较（零函数调用开销）
            // ==========================================================

            // [1] 预排序检测（O(n)最好，O(1)期望随机数据）
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

            // [2] 小数组快速路径（<=32，纯线性插入排序，内联比较下线性优于二分）
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
            if (_inUse) {
                trace("[PDQSort] Warning: reentrant call detected, falling back to Array.sort()");
                arr.sort(_defaultCmp);
                return arr;
            }
            _inUse = true;

            // [4] 栈初始化（每项3个值：left, right, depth）
            maxD = (2 * (Math.log(n) / Math.LN2)) | 0;
            k = (maxD + 4) * 3;
            if (_stackCap < k) { _stack = new Array(k); _stackCap = k; }
            stack = _stack;
            sp = 0;
            stack[sp++] = 0; stack[sp++] = n - 1; stack[sp++] = maxD;

            // [5] 主循环
            while (sp > 0) {
                depth = stack[--sp]; right = stack[--sp]; left = stack[--sp];
                size = right - left + 1;

                // [A] 小分区 → 插入排序（阈值32，内联比较）
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

                // [B] 深度耗尽 → 堆排序（O(n log n)保证）
                if (depth <= 0) {
                    // 构建最大堆（自底向上）
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
                    // 逐个提取最大值
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

                // [C] 选轴：大分区ninther，小分区median-of-3
                mid = left + ((size - 1) >> 1);
                if (size > 128) {
                    // Ninther：3组各取中位数，再取总中位数（12次内联比较）
                    t = size >> 3;
                    // 组1：arr[left], arr[left+t], arr[left+2t] → median放arr[left]
                    k = left + t; j = left + t + t;
                    if (arr[left] > arr[k]) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; }
                    if (arr[k] > arr[j]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp;
                        if (arr[left] > arr[k]) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; } }
                    tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp;
                    // 组2：arr[mid-t], arr[mid], arr[mid+t] → median放arr[mid]
                    k = mid - t; j = mid + t;
                    if (arr[k] > arr[mid]) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; }
                    if (arr[mid] > arr[j]) { tmp = arr[mid]; arr[mid] = arr[j]; arr[j] = tmp;
                        if (arr[k] > arr[mid]) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; } }
                    // 组3：arr[right-2t], arr[right-t], arr[right] → median放arr[right]
                    k = right - t - t; j = right - t;
                    if (arr[k] > arr[j]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp; }
                    if (arr[j] > arr[right]) { tmp = arr[j]; arr[j] = arr[right]; arr[right] = tmp;
                        if (arr[k] > arr[j]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp; } }
                    tmp = arr[right]; arr[right] = arr[j]; arr[j] = tmp;
                }
                // Median-of-3 on arr[left], arr[mid], arr[right]
                if (arr[left] > arr[mid]) { tmp = arr[left]; arr[left] = arr[mid]; arr[mid] = tmp; }
                if (arr[left] > arr[right]) { tmp = arr[left]; arr[left] = arr[right]; arr[right] = tmp; }
                if (arr[mid] > arr[right]) { tmp = arr[mid]; arr[mid] = arr[right]; arr[right] = tmp; }
                // 轴值移至left位置
                tmp = arr[left]; arr[left] = arr[mid]; arr[mid] = tmp;
                pivotVal = arr[left];

                // [D] DNF三路分区（值缓存，每swap少一次arr读取）
                lessIdx = left + 1; greatIdx = right; k = left + 1;
                while (k <= greatIdx) {
                    tmp = arr[k]; // P1: 缓存当前值，swap时复用
                    if (tmp < pivotVal) {
                        arr[k] = arr[lessIdx]; arr[lessIdx] = tmp;
                        lessIdx++; k++;
                    } else if (tmp > pivotVal) {
                        arr[k] = arr[greatIdx]; arr[greatIdx] = tmp;
                        greatIdx--;
                    } else { k++; }
                }
                // 轴值归位
                lessIdx--;
                tmp = arr[left]; arr[left] = arr[lessIdx]; arr[lessIdx] = tmp;

                // [E] 子分区入栈（逐路径深度追踪）
                depth--;
                leftLen = lessIdx - 1 - left;
                rightLen = right - greatIdx;
                t = size >> 3;
                if (leftLen < t || rightLen < t) depth--; // 坏分区额外惩罚

                // 大分区先入栈（小分区优先弹出处理，保证栈深O(log n)）
                if (leftLen < rightLen) {
                    if (greatIdx + 1 < right) { stack[sp++] = greatIdx + 1; stack[sp++] = right; stack[sp++] = depth; }
                    if (left < lessIdx - 1) { stack[sp++] = left; stack[sp++] = lessIdx - 1; stack[sp++] = depth; }
                } else {
                    if (left < lessIdx - 1) { stack[sp++] = left; stack[sp++] = lessIdx - 1; stack[sp++] = depth; }
                    if (greatIdx + 1 < right) { stack[sp++] = greatIdx + 1; stack[sp++] = right; stack[sp++] = depth; }
                }
            }

            _inUse = false;
            return arr;

        } else {
            // ==========================================================
            // 路径B：自定义比较器
            // ==========================================================
            cmp = compareFunction;

            // [1] 预排序检测
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

            // [2] 小数组快速路径
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

            // [3] 重入保护
            if (_inUse) {
                trace("[PDQSort] Warning: reentrant call detected, falling back to Array.sort()");
                arr.sort(cmp);
                return arr;
            }
            _inUse = true;

            // [4] 栈初始化
            maxD = (2 * (Math.log(n) / Math.LN2)) | 0;
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

                // [B] 深度耗尽 → 堆排序
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

                // [C] 选轴：大分区ninther，小分区median-of-3
                mid = left + ((size - 1) >> 1);
                if (size > 128) {
                    t = size >> 3;
                    // 组1
                    k = left + t; j = left + t + t;
                    if (cmp(arr[left], arr[k]) > 0) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; }
                    if (cmp(arr[k], arr[j]) > 0) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp;
                        if (cmp(arr[left], arr[k]) > 0) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; } }
                    tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp;
                    // 组2
                    k = mid - t; j = mid + t;
                    if (cmp(arr[k], arr[mid]) > 0) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; }
                    if (cmp(arr[mid], arr[j]) > 0) { tmp = arr[mid]; arr[mid] = arr[j]; arr[j] = tmp;
                        if (cmp(arr[k], arr[mid]) > 0) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; } }
                    // 组3
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

                // [D] DNF三路分区（值+比较双缓存，避免重复arr[k]读取）
                lessIdx = left + 1; greatIdx = right; k = left + 1;
                while (k <= greatIdx) {
                    tmp = arr[k]; c = cmp(tmp, pivotVal);
                    if (c < 0) {
                        arr[k] = arr[lessIdx]; arr[lessIdx] = tmp;
                        lessIdx++; k++;
                    } else if (c > 0) {
                        arr[k] = arr[greatIdx]; arr[greatIdx] = tmp;
                        greatIdx--;
                    } else { k++; }
                }
                lessIdx--;
                tmp = arr[left]; arr[left] = arr[lessIdx]; arr[lessIdx] = tmp;

                // [E] 子分区入栈
                depth--;
                leftLen = lessIdx - 1 - left;
                rightLen = right - greatIdx;
                t = size >> 3;
                if (leftLen < t || rightLen < t) depth--;

                if (leftLen < rightLen) {
                    if (greatIdx + 1 < right) { stack[sp++] = greatIdx + 1; stack[sp++] = right; stack[sp++] = depth; }
                    if (left < lessIdx - 1) { stack[sp++] = left; stack[sp++] = lessIdx - 1; stack[sp++] = depth; }
                } else {
                    if (left < lessIdx - 1) { stack[sp++] = left; stack[sp++] = lessIdx - 1; stack[sp++] = depth; }
                    if (greatIdx + 1 < right) { stack[sp++] = greatIdx + 1; stack[sp++] = right; stack[sp++] = depth; }
                }
            }

            _inUse = false;
            return arr;
        }
    }

    /**
     * 间接排序：按keys数组的值对索引数组排序
     * 完全内联数值比较，零函数调用开销
     *
     * @param arr 索引数组（arr[i]为keys的有效索引）
     * @param keys 键值数组（排序期间只读）
     * @return 排序后的索引数组
     */
    public static function sortIndirect(arr:Array, keys:Array):Array {
        var n:Number = arr.length;
        if (n < 2) return arr;

        // 变量声明
        var i:Number, j:Number, k:Number, t:Number;
        var tmp:Number, key:Number, keyVal:Number, kv:Number, pivotKey:Number;
        var sp:Number, depth:Number, maxD:Number;
        var size:Number, mid:Number;
        var lessIdx:Number, greatIdx:Number;
        var left:Number, right:Number;
        var leftLen:Number, rightLen:Number;
        var stack:Array;
        var asc:Boolean, desc:Boolean;
        var root:Number, boundary:Number, lch:Number, rch:Number, largest:Number;
        var ka:Number, kb:Number;

        // [1] 预排序检测
        asc = true; desc = true;
        for (i = 1; i < n; i++) {
            ka = keys[arr[i - 1]]; kb = keys[arr[i]];
            if (ka > kb) asc = false;
            if (ka < kb) desc = false;
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
                key = arr[i]; keyVal = keys[key]; j = i - 1;
                tmp = arr[j];
                if (keys[tmp] <= keyVal) continue;
                if (i <= 4) {
                    arr[--j + 2] = tmp;
                    while (j >= 0) { tmp = arr[j]; if (keys[tmp] <= keyVal) break; arr[--j + 2] = tmp; }
                    arr[j + 1] = key;
                } else {
                    left = 0; right = j;
                    while (left < right) { mid = (left + right) >> 1; if (keys[arr[mid]] <= keyVal) left = mid + 1; else right = mid; }
                    j = i; while (j > left) { arr[j] = arr[--j]; } arr[left] = key;
                }
            }
            return arr;
        }

        // [3] 重入保护
        if (_inUse) {
            trace("[PDQSort] Warning: reentrant call in sortIndirect, falling back");
            arr.sort(function(a, b) { return keys[a] - keys[b]; });
            return arr;
        }
        _inUse = true;

        // [4] 栈初始化
        maxD = (2 * (Math.log(n) / Math.LN2)) | 0;
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
                    key = arr[i]; keyVal = keys[key]; j = i - 1;
                    tmp = arr[j];
                    if (keys[tmp] <= keyVal) continue;
                    if ((i - left) <= 4) {
                        arr[--j + 2] = tmp;
                        while (j >= left) { tmp = arr[j]; if (keys[tmp] <= keyVal) break; arr[--j + 2] = tmp; }
                        arr[j + 1] = key;
                    } else {
                        k = left; t = j;
                        while (k < t) { mid = (k + t) >> 1; if (keys[arr[mid]] <= keyVal) k = mid + 1; else t = mid; }
                        j = i; while (j > k) { arr[j] = arr[--j]; } arr[k] = key;
                    }
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
                        largest = (rch <= right && keys[arr[rch]] > keys[arr[lch]]) ? rch : lch;
                        if (keys[arr[largest]] > keys[arr[root]]) {
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
                        largest = (rch <= boundary && keys[arr[rch]] > keys[arr[lch]]) ? rch : lch;
                        if (keys[arr[largest]] > keys[arr[root]]) {
                            tmp = arr[root]; arr[root] = arr[largest]; arr[largest] = tmp;
                            root = largest;
                        } else break;
                    }
                }
                continue;
            }

            // [C] 选轴：大分区ninther，小分区median-of-3
            mid = left + ((size - 1) >> 1);
            if (size > 128) {
                t = size >> 3;
                // 组1
                k = left + t; j = left + t + t;
                if (keys[arr[left]] > keys[arr[k]]) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; }
                if (keys[arr[k]] > keys[arr[j]]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp;
                    if (keys[arr[left]] > keys[arr[k]]) { tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp; } }
                tmp = arr[left]; arr[left] = arr[k]; arr[k] = tmp;
                // 组2
                k = mid - t; j = mid + t;
                if (keys[arr[k]] > keys[arr[mid]]) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; }
                if (keys[arr[mid]] > keys[arr[j]]) { tmp = arr[mid]; arr[mid] = arr[j]; arr[j] = tmp;
                    if (keys[arr[k]] > keys[arr[mid]]) { tmp = arr[k]; arr[k] = arr[mid]; arr[mid] = tmp; } }
                // 组3
                k = right - t - t; j = right - t;
                if (keys[arr[k]] > keys[arr[j]]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp; }
                if (keys[arr[j]] > keys[arr[right]]) { tmp = arr[j]; arr[j] = arr[right]; arr[right] = tmp;
                    if (keys[arr[k]] > keys[arr[j]]) { tmp = arr[k]; arr[k] = arr[j]; arr[j] = tmp; } }
                tmp = arr[right]; arr[right] = arr[j]; arr[j] = tmp;
            }
            if (keys[arr[left]] > keys[arr[mid]]) { tmp = arr[left]; arr[left] = arr[mid]; arr[mid] = tmp; }
            if (keys[arr[left]] > keys[arr[right]]) { tmp = arr[left]; arr[left] = arr[right]; arr[right] = tmp; }
            if (keys[arr[mid]] > keys[arr[right]]) { tmp = arr[mid]; arr[mid] = arr[right]; arr[right] = tmp; }
            tmp = arr[left]; arr[left] = arr[mid]; arr[mid] = tmp;
            pivotKey = keys[arr[left]];

            // [D] DNF三路分区
            lessIdx = left + 1; greatIdx = right; k = left + 1;
            while (k <= greatIdx) {
                kv = keys[arr[k]]; // 缓存双重解引用
                if (kv < pivotKey) {
                    tmp = arr[k]; arr[k] = arr[lessIdx]; arr[lessIdx] = tmp;
                    lessIdx++; k++;
                } else if (kv > pivotKey) {
                    tmp = arr[k]; arr[k] = arr[greatIdx]; arr[greatIdx] = tmp;
                    greatIdx--;
                } else { k++; }
            }
            lessIdx--;
            tmp = arr[left]; arr[left] = arr[lessIdx]; arr[lessIdx] = tmp;

            // [E] 子分区入栈
            depth--;
            leftLen = lessIdx - 1 - left;
            rightLen = right - greatIdx;
            t = size >> 3;
            if (leftLen < t || rightLen < t) depth--;

            if (leftLen < rightLen) {
                if (greatIdx + 1 < right) { stack[sp++] = greatIdx + 1; stack[sp++] = right; stack[sp++] = depth; }
                if (left < lessIdx - 1) { stack[sp++] = left; stack[sp++] = lessIdx - 1; stack[sp++] = depth; }
            } else {
                if (left < lessIdx - 1) { stack[sp++] = left; stack[sp++] = lessIdx - 1; stack[sp++] = depth; }
                if (greatIdx + 1 < right) { stack[sp++] = greatIdx + 1; stack[sp++] = right; stack[sp++] = depth; }
            }
        }

        _inUse = false;
        return arr;
    }
}
