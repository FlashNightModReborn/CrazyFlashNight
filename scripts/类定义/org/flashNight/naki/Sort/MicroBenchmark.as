/**
 * TimSort 微结构参数基准测试套件
 *
 * 目的：隔离测试各子算法在不同参数设置下的性能表现，
 *       排除 TimSort 整体架构的影响，为调参提供数据支撑。
 *
 * 基准测试项目：
 * 1. 插入排序 线性/二分 切换阈值 (当前=8)
 * 2. Gallop 激活阈值 MIN_GALLOP (当前=7)
 * 3. MIN_MERGE / minRun 对插入排序负载的影响
 *
 * 调用方式：MicroBenchmark.runAll() 或单独调用各 bench* 方法
 */
class org.flashNight.naki.Sort.MicroBenchmark {

    // ===== 内联 LCG 随机数（自包含，无外部依赖）=====
    private static var _seed:Number;
    private static function resetRng():Void { _seed = 12345; }
    private static function rand():Number {
        return (_seed = (_seed * 1664525 + 1013904223) % 4294967296);
    }

    // ===== 比较计数器 =====
    private static var _cmpCount:Number;
    private static function cmpNum(a, b):Number { return a - b; }
    private static function cmpCounted(a, b):Number { _cmpCount++; return a - b; }

    // ===== 工具函数 =====
    private static function copyArr(src:Array):Array {
        var n:Number = src.length, dst:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) dst[i] = src[i];
        return dst;
    }
    private static function isSorted(a:Array):Boolean {
        for (var i:Number = 1; i < a.length; i++) if (a[i - 1] > a[i]) return false;
        return true;
    }
    private static function padR(s:String, w:Number):String {
        while (s.length < w) s += " ";
        return s;
    }
    private static function padL(s:String, w:Number):String {
        while (s.length < w) s = " " + s;
        return s;
    }
    private static function ruler(n:Number):String {
        var s:String = "";
        for (var i:Number = 0; i < n; i++) s += "-";
        return s;
    }

    // ===== 数据生成 =====
    private static function genRandom(n:Number):Array {
        var a:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) a[i] = rand() % 100000;
        return a;
    }
    private static function genSorted(n:Number):Array {
        var a:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) a[i] = i;
        return a;
    }
    private static function genReversed(n:Number):Array {
        var a:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) a[i] = n - i;
        return a;
    }
    private static function genNearlySorted(n:Number, swaps:Number):Array {
        var a:Array = genSorted(n);
        for (var s:Number = 0; s < swaps; s++) {
            var i:Number = rand() % n, j:Number = rand() % n;
            var t:Number = a[i]; a[i] = a[j]; a[j] = t;
        }
        return a;
    }
    private static function genDuplicates(n:Number, unique:Number):Array {
        var a:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) a[i] = rand() % unique;
        return a;
    }

    /**
     * 生成两个已排序的相邻 run 用于合并基准测试
     * 返回: arr[0..lenA-1] 已排序, arr[lenA..lenA+lenB-1] 已排序
     *
     * pattern:
     *   "random"   - 两半范围随机重叠
     *   "block"    - 值域交错（长 run 交替胜出，gallop 有利）
     *   "oneSided" - A 全部 < B（gallop 极度有利）
     */
    private static function genMergeData(lenA:Number, lenB:Number, pattern:String):Array {
        var total:Number = lenA + lenB;
        var arr:Array = new Array(total);
        var i:Number, j:Number, t:Number;

        if (pattern == "oneSided") {
            for (i = 0; i < lenA; i++) arr[i] = i;
            for (i = 0; i < lenB; i++) arr[lenA + i] = lenA + i;
        } else if (pattern == "block") {
            // 产生值域交错的两组：A 取偶数值，B 取奇数值（排序后交替胜出）
            var pA:Array = new Array(lenA), pB:Array = new Array(lenB);
            for (i = 0; i < lenA; i++) pA[i] = i * 2;      // 0,2,4,...
            for (i = 0; i < lenB; i++) pB[i] = i * 2 + 1;  // 1,3,5,...
            // 保留一些连续块：每20个元素一组，组内偏移相同方向
            for (i = 0; i < lenA; i++) arr[i] = pA[i];
            for (i = 0; i < lenB; i++) arr[lenA + i] = pB[i];
        } else {
            // "random" - 两半各自用随机值排序
            var tmpA:Array = new Array(lenA), tmpB:Array = new Array(lenB);
            for (i = 0; i < lenA; i++) tmpA[i] = rand() % total;
            for (i = 0; i < lenB; i++) tmpB[i] = rand() % total;
            // 用简单插入排序排序（数据量不大）
            for (i = 1; i < lenA; i++) {
                t = tmpA[i]; j = i - 1;
                while (j >= 0 && tmpA[j] > t) { tmpA[j + 1] = tmpA[j]; j--; }
                tmpA[j + 1] = t;
            }
            for (i = 1; i < lenB; i++) {
                t = tmpB[i]; j = i - 1;
                while (j >= 0 && tmpB[j] > t) { tmpB[j + 1] = tmpB[j]; j--; }
                tmpB[j + 1] = t;
            }
            for (i = 0; i < lenA; i++) arr[i] = tmpA[i];
            for (i = 0; i < lenB; i++) arr[lenA + i] = tmpB[i];
        }
        return arr;
    }

    // =====================================================================
    //  Benchmark 1: 插入排序 线性/二分 切换阈值
    // =====================================================================

    /**
     * 参数化插入排序：threshold 以下用线性搜索，以上用二分搜索
     * threshold=0 → 全部二分, threshold=999 → 全部线性
     */
    private static function insertSort(arr:Array, lo:Number, hi:Number,
                                       threshold:Number, cmp:Function):Void {
        var i:Number, j:Number, key:Object, left:Number, h2:Number, mid:Number;
        for (i = lo + 1; i <= hi; i++) {
            key = arr[i];
            if (cmp(arr[i - 1], key) <= 0) continue;
            if ((i - lo) <= threshold) {
                j = i - 1;
                while (j >= lo && cmp(arr[j], key) > 0) { arr[j + 1] = arr[j]; j--; }
                arr[j + 1] = key;
            } else {
                left = lo; h2 = i;
                while (left < h2) {
                    mid = (left + h2) >> 1;
                    if (cmp(arr[mid], key) <= 0) left = mid + 1;
                    else h2 = mid;
                }
                j = i;
                while (j > left) { arr[j] = arr[j - 1]; j--; }
                arr[left] = key;
            }
        }
    }

    public static function benchInsertionThreshold():Void {
        trace("\n" + ruler(76));
        trace("  Benchmark 1: Insertion Sort - Binary/Linear Threshold");
        trace(ruler(76));

        var thresholds:Array = [0, 4, 8, 12, 16, 20, 999];
        var labels:Array     = ["T=0", "T=4", "T=8", "T=12", "T=16", "T=20", "T=ALL"];
        var sizes:Array = [32, 48, 64];
        var iters:Number = 3000;

        var pi:Number, ti:Number, si:Number, iter:Number;

        for (si = 0; si < sizes.length; si++) {
            var n:Number = sizes[si];
            trace("\n--- size=" + n + "  iterations=" + iters + " ---");

            // 表头
            var hdr:String = padR("Pattern", 16);
            for (ti = 0; ti < labels.length; ti++) hdr += padL(labels[ti], 9);
            trace(hdr);
            trace(ruler(76));

            var patterns:Array = [
                {name: "random",       gen: function():Array { return genRandom(n); }},
                {name: "nearlySorted", gen: function():Array { return genNearlySorted(n, 3); }},
                {name: "reversed",     gen: function():Array { return genReversed(n); }},
                {name: "duplicates",   gen: function():Array { return genDuplicates(n, 5); }},
                {name: "sorted",       gen: function():Array { return genSorted(n); }}
            ];

            // 时间行
            for (pi = 0; pi < patterns.length; pi++) {
                resetRng();
                var master:Array = patterns[pi].gen();
                var row:String = padR(patterns[pi].name, 16);
                for (ti = 0; ti < thresholds.length; ti++) {
                    var t0:Number = getTimer();
                    for (iter = 0; iter < iters; iter++) {
                        var work:Array = copyArr(master);
                        insertSort(work, 0, n - 1, thresholds[ti], cmpNum);
                    }
                    row += padL(String(getTimer() - t0), 9);
                }
                trace(row + " ms");
            }

            // 比较次数行（单次）
            trace("");
            hdr = padR("Compares", 16);
            for (ti = 0; ti < labels.length; ti++) hdr += padL(labels[ti], 9);
            trace(hdr);
            trace(ruler(76));
            for (pi = 0; pi < patterns.length; pi++) {
                resetRng();
                var master2:Array = patterns[pi].gen();
                var row2:String = padR(patterns[pi].name, 16);
                for (ti = 0; ti < thresholds.length; ti++) {
                    _cmpCount = 0;
                    var work2:Array = copyArr(master2);
                    insertSort(work2, 0, n - 1, thresholds[ti], cmpCounted);
                    row2 += padL(String(_cmpCount), 9);
                }
                trace(row2);
            }
        }
    }

    // =====================================================================
    //  Benchmark 2: Gallop 激活阈值 (MIN_GALLOP)
    // =====================================================================

    /**
     * 独立 mergeLo，使用标准 P0 双阶段结构，gallop 参数可配
     * arr[0..lenA-1] 与 arr[lenA..lenA+lenB-1] 各自已排序
     */
    private static function mergeLoBench(arr:Array, lenA:Number, lenB:Number,
                                         tmp:Array, mgInit:Number, MG:Number,
                                         cmp:Function):Void {
        var pa:Number = 0, pb:Number = lenA, d:Number = 0;
        var ea:Number = lenA, eb:Number = lenA + lenB;
        var ca:Number, cb:Number, minGallop:Number = mgInit;
        var target:Object, base:Number, len:Number;
        var ofs:Number, lastOfs:Number, left:Number, h2:Number, mid:Number;
        var ci:Number;

        // copy A to tmp
        for (ci = 0; ci < lenA; ci++) tmp[ci] = arr[ci];

        // two-phase merge
        while (pa < ea && pb < eb) {
            // Phase 1: one-at-a-time
            ca = 0; cb = 0;
            while (pa < ea && pb < eb) {
                if (cmp(tmp[pa], arr[pb]) <= 0) {
                    arr[d++] = tmp[pa++]; ca++; cb = 0;
                    if (ca >= minGallop) break;
                } else {
                    arr[d++] = arr[pb++]; cb++; ca = 0;
                    if (cb >= minGallop) break;
                }
            }
            if (pa >= ea || pb >= eb) break;

            // Phase 2: galloping
            do {
                // A-gallop: gallopRight in tmp for arr[pb]
                target = arr[pb]; base = pa; len = ea - pa; ca = 0;
                if (cmp(tmp[base], target) <= 0) {
                    ofs = 1; lastOfs = 0;
                    while (ofs < len && cmp(tmp[base + ofs], target) <= 0) {
                        lastOfs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = len;
                    }
                    if (ofs > len) ofs = len;
                    left = lastOfs; h2 = ofs;
                    while (left < h2) {
                        mid = (left + h2) >> 1;
                        if (cmp(tmp[base + mid], target) <= 0) left = mid + 1;
                        else h2 = mid;
                    }
                    ca = left;
                }
                for (ci = 0; ci < ca; ci++) arr[d + ci] = tmp[pa + ci];
                d += ca; pa += ca;
                if (pa >= ea) break;
                arr[d++] = arr[pb++];
                if (pb >= eb) break;

                // B-gallop: gallopLeft in arr for tmp[pa]
                target = tmp[pa]; base = pb; len = eb - pb; cb = 0;
                if (cmp(arr[base], target) < 0) {
                    ofs = 1; lastOfs = 0;
                    while (ofs < len && cmp(arr[base + ofs], target) < 0) {
                        lastOfs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = len;
                    }
                    if (ofs > len) ofs = len;
                    left = lastOfs; h2 = ofs;
                    while (left < h2) {
                        mid = (left + h2) >> 1;
                        if (cmp(arr[base + mid], target) < 0) left = mid + 1;
                        else h2 = mid;
                    }
                    cb = left;
                }
                for (ci = 0; ci < cb; ci++) arr[d + ci] = arr[pb + ci];
                d += cb; pb += cb;
                if (pb >= eb) break;
                arr[d++] = tmp[pa++];
                if (pa >= ea) break;
                --minGallop;
            } while (ca >= MG || cb >= MG);

            if (pa >= ea || pb >= eb) break;
            if (minGallop < 0) minGallop = 0;
            minGallop += 2;
        }
        // remainder A
        while (pa < ea) arr[d++] = tmp[pa++];
    }

    public static function benchGallopThreshold():Void {
        trace("\n" + ruler(76));
        trace("  Benchmark 2: Gallop Threshold (MIN_GALLOP)");
        trace(ruler(76));

        var thresholds:Array = [3, 5, 7, 9, 11, 13];
        var mergeLen:Number = 500;
        var iters:Number = 300;
        var tmp:Array = new Array(mergeLen);
        var patterns:Array = ["random", "block", "oneSided"];

        var pi:Number, ti:Number, iter:Number;

        for (pi = 0; pi < patterns.length; pi++) {
            var pName:String = patterns[pi];
            trace("\n--- pattern: " + pName + "  merge " + mergeLen + "+" + mergeLen
                  + "  x" + iters + " ---");

            var hdr:String = padR("Metric", 14);
            for (ti = 0; ti < thresholds.length; ti++) hdr += padL("MG=" + thresholds[ti], 10);
            trace(hdr);
            trace(ruler(74));

            // 固定种子生成 master 数据
            resetRng();
            var master:Array = genMergeData(mergeLen, mergeLen, pName);

            // 时间
            var tRow:String = padR("Time (ms)", 14);
            for (ti = 0; ti < thresholds.length; ti++) {
                var mg:Number = thresholds[ti];
                var t0:Number = getTimer();
                for (iter = 0; iter < iters; iter++) {
                    var work:Array = copyArr(master);
                    mergeLoBench(work, mergeLen, mergeLen, tmp, mg, mg, cmpNum);
                }
                tRow += padL(String(getTimer() - t0), 10);
            }
            trace(tRow);

            // 比较次数（单次）
            var cRow:String = padR("Compares", 14);
            for (ti = 0; ti < thresholds.length; ti++) {
                _cmpCount = 0;
                var work2:Array = copyArr(master);
                mergeLoBench(work2, mergeLen, mergeLen, tmp,
                             thresholds[ti], thresholds[ti], cmpCounted);
                cRow += padL(String(_cmpCount), 10);
            }
            trace(cRow);

            // 正确性验证
            var vWork:Array = copyArr(master);
            mergeLoBench(vWork, mergeLen, mergeLen, tmp, 7, 7, cmpNum);
            trace("Verify: " + (isSorted(vWork) ? "PASS" : "FAIL"));
        }
    }

    // =====================================================================
    //  Benchmark 3: MIN_MERGE / minRun
    // =====================================================================

    private static function calcMinRun(n:Number, minMerge:Number):Number {
        var r:Number = 0;
        while (n >= minMerge) { r |= n & 1; n >>= 1; }
        return n + r;
    }

    public static function benchMinRun():Void {
        trace("\n" + ruler(76));
        trace("  Benchmark 3: MIN_MERGE / minRun Effect on Insertion Sort");
        trace(ruler(76));

        var minMerges:Array = [16, 24, 32, 48, 64];
        var sizes:Array     = [100, 500, 1000, 5000];

        // 先展示 minRun 值对照表
        trace("\nminRun values for reference:");
        var hdr:String = padR("n", 8);
        var mi:Number, si:Number;
        for (mi = 0; mi < minMerges.length; mi++) hdr += padL("MM=" + minMerges[mi], 10);
        trace(hdr);
        trace(ruler(58));
        for (si = 0; si < sizes.length; si++) {
            var row:String = padR(String(sizes[si]), 8);
            for (mi = 0; mi < minMerges.length; mi++) {
                row += padL(String(calcMinRun(sizes[si], minMerges[mi])), 10);
            }
            trace(row);
        }

        // 基准测试：以不同 minRun 大小做插入排序切片
        var patterns:Array = ["random", "nearlySorted", "reversed"];
        var pi:Number, iter:Number;

        for (pi = 0; pi < patterns.length; pi++) {
            var pName:String = patterns[pi];
            trace("\n--- pattern: " + pName + " ---");
            hdr = padR("n", 8);
            for (mi = 0; mi < minMerges.length; mi++) hdr += padL("MM=" + minMerges[mi], 10);
            hdr += "   (ms, normalized to 1000 iters)";
            trace(hdr);
            trace(ruler(76));

            for (si = 0; si < sizes.length; si++) {
                var n:Number = sizes[si];
                row = padR(String(n), 8);

                for (mi = 0; mi < minMerges.length; mi++) {
                    var minR:Number = calcMinRun(n, minMerges[mi]);
                    var numChunks:Number = Math.ceil(n / minR);

                    resetRng();
                    var master:Array;
                    if (pName == "random") master = genRandom(n);
                    else if (pName == "nearlySorted") master = genNearlySorted(n, Math.max(3, Math.floor(n * 0.03)));
                    else master = genReversed(n);

                    // 自适应迭代次数：保证总工作量可测
                    var adjIters:Number = Math.max(10, Math.floor(50000 / n));
                    var t0:Number = getTimer();
                    for (iter = 0; iter < adjIters; iter++) {
                        var work:Array = copyArr(master);
                        for (var c:Number = 0; c < numChunks; c++) {
                            var cLo:Number = c * minR;
                            var cHi:Number = cLo + minR - 1;
                            if (cHi >= n) cHi = n - 1;
                            insertSort(work, cLo, cHi, 8, cmpNum);
                        }
                    }
                    var elapsed:Number = getTimer() - t0;
                    // 归一化到 1000 次迭代
                    var norm:Number = Math.round(elapsed * 1000 / adjIters);
                    row += padL(String(norm), 10);
                }
                trace(row);
            }
        }

        // 比较次数（单次，n=1000）
        trace("\nComparison counts (n=1000, single pass):");
        hdr = padR("Pattern", 16);
        for (mi = 0; mi < minMerges.length; mi++) hdr += padL("MM=" + minMerges[mi], 10);
        trace(hdr);
        trace(ruler(66));
        for (pi = 0; pi < patterns.length; pi++) {
            var pName2:String = patterns[pi];
            var row2:String = padR(pName2, 16);
            for (mi = 0; mi < minMerges.length; mi++) {
                var minR2:Number = calcMinRun(1000, minMerges[mi]);
                var chunks2:Number = Math.ceil(1000 / minR2);
                resetRng();
                var m2:Array;
                if (pName2 == "random") m2 = genRandom(1000);
                else if (pName2 == "nearlySorted") m2 = genNearlySorted(1000, 30);
                else m2 = genReversed(1000);
                _cmpCount = 0;
                for (var c2:Number = 0; c2 < chunks2; c2++) {
                    var lo2:Number = c2 * minR2;
                    var hi2:Number = lo2 + minR2 - 1;
                    if (hi2 >= 1000) hi2 = 999;
                    insertSort(m2, lo2, hi2, 8, cmpCounted);
                }
                row2 += padL(String(_cmpCount), 10);
            }
            trace(row2);
        }
    }

    // =====================================================================
    //  Benchmark 4: Gallop 搜索方向对比（前向 vs 后向）
    // =====================================================================

    /**
     * 模拟 gallopLeft 前向搜索（从左到右）
     * 返回 lower_bound 位置 + 比较次数
     */
    private static function gallopLeftForward(target:Number, arr:Array,
                                              base:Number, len:Number):Number {
        if (len == 0) return 0;
        if (arr[base] >= target) return 0;
        var ofs:Number = 1, lastOfs:Number = 0;
        while (ofs < len && arr[base + ofs] < target) {
            lastOfs = ofs; ofs = (ofs << 1) + 1;
            if (ofs <= 0) ofs = len;
        }
        if (ofs > len) ofs = len;
        var lo:Number = lastOfs, hi:Number = ofs;
        while (lo < hi) {
            var mid:Number = (lo + hi) >> 1;
            if (arr[base + mid] < target) lo = mid + 1;
            else hi = mid;
        }
        return lo;
    }

    /**
     * 模拟 gallopLeft 后向搜索（从右到左，hint = len-1）
     * 返回 lower_bound 位置 + 比较次数
     */
    private static function gallopLeftBackward(target:Number, arr:Array,
                                               base:Number, len:Number):Number {
        if (len == 0) return 0;
        if (arr[base + len - 1] < target) return len;
        if (arr[base] >= target) return 0;
        var ofs:Number = 1, lastOfs:Number = 0;
        while (ofs < len && arr[base + len - 1 - ofs] >= target) {
            lastOfs = ofs; ofs = (ofs << 1) + 1;
            if (ofs <= 0) ofs = len;
        }
        if (ofs > len) ofs = len;
        var lo:Number = lastOfs, hi:Number = ofs;
        while (lo < hi) {
            var mid:Number = (lo + hi) >> 1;
            if (arr[base + len - 1 - mid] >= target) lo = mid + 1;
            else hi = mid;
        }
        return len - lo;
    }

    public static function benchGallopDirection():Void {
        trace("\n" + ruler(76));
        trace("  Benchmark 4: Gallop Search Direction (Forward vs Backward)");
        trace(ruler(76));

        var sizes:Array = [100, 500, 2000, 10000];
        var iters:Number = 5000;

        // target 在数组右端附近（模拟 pre-trim gallopLeft 场景）
        trace("\n--- Target near RIGHT end (typical pre-trim scenario) ---");
        var hdr:String = padR("ArrayLen", 10)
                       + padL("Fwd(ms)", 10) + padL("Bwd(ms)", 10)
                       + padL("Fwd-cmp", 10) + padL("Bwd-cmp", 10);
        trace(hdr);
        trace(ruler(50));

        for (var si:Number = 0; si < sizes.length; si++) {
            var n:Number = sizes[si];
            var arr:Array = genSorted(n); // 0,1,2,...,n-1
            // target = n - 5, 答案接近右端
            var target:Number = n - 5;

            // 时间
            var t0:Number = getTimer();
            for (var it:Number = 0; it < iters; it++) gallopLeftForward(target, arr, 0, n);
            var fwdMs:Number = getTimer() - t0;

            t0 = getTimer();
            for (it = 0; it < iters; it++) gallopLeftBackward(target, arr, 0, n);
            var bwdMs:Number = getTimer() - t0;

            // 比较次数（单次）
            _cmpCount = 0;
            var arrC:Array = genSorted(n);
            // 用 counted 版本计数需要手动替换...
            // 简化：直接算理论值
            // Forward: O(log n) 步, Backward: O(log k) 步 where k = 5
            // 用实际计数
            var fwdCmp:Number = countGallopCmp(target, arrC, 0, n, true);
            var bwdCmp:Number = countGallopCmp(target, arrC, 0, n, false);

            trace(padR(String(n), 10)
                  + padL(String(fwdMs), 10) + padL(String(bwdMs), 10)
                  + padL(String(fwdCmp), 10) + padL(String(bwdCmp), 10));
        }

        // target 在数组左端附近（gallop方向不利的对比情况）
        trace("\n--- Target near LEFT end (reversed scenario) ---");
        trace(hdr);
        trace(ruler(50));
        for (si = 0; si < sizes.length; si++) {
            n = sizes[si];
            arr = genSorted(n);
            target = 5;

            t0 = getTimer();
            for (it = 0; it < iters; it++) gallopLeftForward(target, arr, 0, n);
            fwdMs = getTimer() - t0;

            t0 = getTimer();
            for (it = 0; it < iters; it++) gallopLeftBackward(target, arr, 0, n);
            bwdMs = getTimer() - t0;

            arrC = genSorted(n);
            fwdCmp = countGallopCmp(target, arrC, 0, n, true);
            bwdCmp = countGallopCmp(target, arrC, 0, n, false);

            trace(padR(String(n), 10)
                  + padL(String(fwdMs), 10) + padL(String(bwdMs), 10)
                  + padL(String(fwdCmp), 10) + padL(String(bwdCmp), 10));
        }
    }

    /** 精确计算 gallopLeft 的比较次数 */
    private static function countGallopCmp(target:Number, arr:Array,
                                           base:Number, len:Number,
                                           forward:Boolean):Number {
        var cnt:Number = 0;
        if (len == 0) return 0;

        if (forward) {
            cnt++;
            if (arr[base] >= target) return cnt;
            var ofs:Number = 1, lastOfs:Number = 0;
            while (ofs < len) {
                cnt++;
                if (arr[base + ofs] < target) {
                    lastOfs = ofs; ofs = (ofs << 1) + 1; if (ofs <= 0) ofs = len;
                } else break;
            }
            if (ofs > len) ofs = len;
            var lo:Number = lastOfs, hi:Number = ofs;
            while (lo < hi) {
                cnt++;
                var mid:Number = (lo + hi) >> 1;
                if (arr[base + mid] < target) lo = mid + 1;
                else hi = mid;
            }
        } else {
            cnt++;
            if (arr[base + len - 1] < target) return cnt;
            cnt++;
            if (arr[base] >= target) return cnt;
            var ofs2:Number = 1, lastOfs2:Number = 0;
            while (ofs2 < len) {
                cnt++;
                if (arr[base + len - 1 - ofs2] >= target) {
                    lastOfs2 = ofs2; ofs2 = (ofs2 << 1) + 1; if (ofs2 <= 0) ofs2 = len;
                } else break;
            }
            if (ofs2 > len) ofs2 = len;
            var lo2:Number = lastOfs2, hi2:Number = ofs2;
            while (lo2 < hi2) {
                cnt++;
                var mid2:Number = (lo2 + hi2) >> 1;
                if (arr[base + len - 1 - mid2] >= target) lo2 = mid2 + 1;
                else hi2 = mid2;
            }
        }
        return cnt;
    }

    // =====================================================================
    //  入口
    // =====================================================================

    public static function runAll():Void {
        trace("\n" + ruler(76));
        trace("  TimSort MicroBenchmark Suite");
        trace("  Isolate micro-structure parameters for AS2 tuning");
        trace(ruler(76));

        benchInsertionThreshold();
        benchGallopThreshold();
        benchMinRun();
        benchGallopDirection();

        trace("\n" + ruler(76));
        trace("  All benchmarks complete.");
        trace(ruler(76));
    }
}
