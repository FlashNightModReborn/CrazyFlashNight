import org.flashNight.naki.Sort.*;

/**
 * NativeSortProfile — AS2 Array.sort(NUMERIC) 行为全面表征
 *
 * 目标：
 * 1. 识别所有导致 native sort 退化的输入模式
 * 2. 测量退化的严重程度（相对于 random baseline）
 * 3. 验证正确性（是否真的排好序了）
 * 4. 为 SortRouter 的风险扫描器提供决策依据
 *
 * 测试维度：
 * - 20种输入分布 × 5种规模 (100/500/1000/5000/10000)
 * - 每种配置重复3次取平均
 * - 同时跑 IntroSort(null) 和 PDQSort(null) 作为对照
 */
class org.flashNight.naki.Sort.NativeSortProfile {

    // 确定性 LCG
    private static var _seed:Number;
    private static function resetRng():Void { _seed = 12345; }
    private static function rand():Number {
        return (_seed = (_seed * 1664525 + 1013904223) % 4294967296);
    }
    private static function randRange(lo:Number, hi:Number):Number {
        return lo + (rand() % (hi - lo + 1));
    }

    // ==================================================================
    // 主入口
    // ==================================================================
    public static function run():Void {
        trace("=================================================================");
        trace("Native Array.sort(NUMERIC) Behavior Profile");
        trace("=================================================================");
        trace("Format: Native / IntroSort / PDQSort (ms, avg of 3 runs)");
        trace("        [ratio] = Native / IntroSort  (>1 = native slower)");
        trace("        [correct] = native result is sorted");
        trace("");

        var sizes:Array = [100, 500, 1000, 5000, 10000];

        // 20种输入分布
        var dists:Array = [
            "random",           // 随机
            "sorted",           // 已排序（升序）
            "reverse",          // 逆序
            "allEqual",         // 全等
            "twoValues",        // 交替两值 0/1
            "threeValues",      // 交替三值 0/1/2
            "fewUnique5",       // 5种唯一值
            "fewUnique10",      // 10种唯一值
            "organPipe",        // 管风琴 0..n/2..0
            "sawTooth20",       // 锯齿 周期20
            "sawTooth100",      // 锯齿 周期100
            "nearSorted1",      // 几乎有序 1%扰动
            "nearSorted5",      // 几乎有序 5%扰动
            "nearSorted10",     // 几乎有序 10%扰动
            "nearReverse1",     // 几乎逆序 1%扰动
            "nearReverse5",     // 几乎逆序 5%扰动
            "sortedTailRand",   // 前90%有序 + 尾部10%随机
            "sortedMidRand",    // 前45%有序 + 中间10%随机 + 后45%有序
            "pushFront",        // 有序但最大值在首位
            "pushBack"          // 有序但最小值在末位
        ];

        var REPEATS:Number = 3;

        for (var si:Number = 0; si < sizes.length; si++) {
            var sz:Number = sizes[si];
            trace("\n--- Size: " + sz + " ---");
            trace(padR("distribution", 18) + "  " + padL("Native", 7) + "  " + padL("Intro", 7) + "  " + padL("PDQ", 7) + "  " + padL("ratio", 7) + "  ok?");

            for (var di:Number = 0; di < dists.length; di++) {
                var dist:String = dists[di];
                resetRng();
                var master:Array = generateArray(sz, dist);

                // Native
                var tNat:Number = 0;
                var natOk:Boolean = true;
                for (var r:Number = 0; r < REPEATS; r++) {
                    var a1:Array = master.slice();
                    var st:Number = getTimer();
                    a1.sort(Array.NUMERIC);
                    tNat += getTimer() - st;
                    if (r === 0) natOk = isSorted(a1);
                }

                // IntroSort
                var tIntro:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a2:Array = master.slice();
                    st = getTimer();
                    IntroSort.sort(a2, null);
                    tIntro += getTimer() - st;
                }

                // PDQSort
                var tPdq:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a3:Array = master.slice();
                    st = getTimer();
                    PDQSort.sort(a3, null);
                    tPdq += getTimer() - st;
                }

                var avgNat:Number = Math.round(tNat / REPEATS);
                var avgIntro:Number = Math.round(tIntro / REPEATS);
                var avgPdq:Number = Math.round(tPdq / REPEATS);
                var ratio:String = (avgIntro > 0) ? String(Math.round(avgNat / avgIntro * 100) / 100) : "N/A";

                trace(padR(dist, 18) + "  "
                    + padL(String(avgNat), 7) + "  "
                    + padL(String(avgIntro), 7) + "  "
                    + padL(String(avgPdq), 7) + "  "
                    + padL(ratio, 7) + "  "
                    + (natOk ? "Y" : "FAIL"));
            }
        }

        trace("\n=================================================================");
        trace("Profile Complete");
        trace("=================================================================");
        trace("KEY: ratio = Native/IntroSort. ratio > 2 = significant degradation.");
        trace("     ratio > 10 = catastrophic degradation (quadratic behavior).");
    }

    // ==================================================================
    // 快速版：只跑10000，识别退化模式
    // ==================================================================
    public static function runQuick():Void {
        trace("=================================================================");
        trace("Native Sort Quick Profile (size=10000 only)");
        trace("=================================================================");
        trace("Format: Native / IntroSort / PDQSort (ms) | ratio | correct");

        var sz:Number = 10000;
        var REPEATS:Number = 3;

        var dists:Array = [
            "random", "sorted", "reverse", "allEqual",
            "twoValues", "threeValues", "fewUnique5", "fewUnique10",
            "organPipe", "sawTooth20", "sawTooth100",
            "nearSorted1", "nearSorted5", "nearSorted10",
            "nearReverse1", "nearReverse5",
            "sortedTailRand", "sortedMidRand",
            "pushFront", "pushBack"
        ];

        trace(padR("distribution", 18) + "  " + padL("Native", 7) + "  " + padL("Intro", 7) + "  " + padL("PDQ", 7) + "  " + padL("ratio", 7) + "  ok?");

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            resetRng();
            var master:Array = generateArray(sz, dist);

            var tNat:Number = 0;
            var natOk:Boolean = true;
            for (var r:Number = 0; r < REPEATS; r++) {
                var a1:Array = master.slice();
                var st:Number = getTimer();
                a1.sort(Array.NUMERIC);
                tNat += getTimer() - st;
                if (r === 0) natOk = isSorted(a1);
            }

            var tIntro:Number = 0;
            for (r = 0; r < REPEATS; r++) {
                var a2:Array = master.slice();
                st = getTimer();
                IntroSort.sort(a2, null);
                tIntro += getTimer() - st;
            }

            var tPdq:Number = 0;
            for (r = 0; r < REPEATS; r++) {
                var a3:Array = master.slice();
                st = getTimer();
                PDQSort.sort(a3, null);
                tPdq += getTimer() - st;
            }

            var avgNat:Number = Math.round(tNat / REPEATS);
            var avgIntro:Number = Math.round(tIntro / REPEATS);
            var avgPdq:Number = Math.round(tPdq / REPEATS);
            var ratio:String = (avgIntro > 0) ? String(Math.round(avgNat / avgIntro * 100) / 100) : "N/A";

            trace(padR(dist, 18) + "  "
                + padL(String(avgNat), 7) + "  "
                + padL(String(avgIntro), 7) + "  "
                + padL(String(avgPdq), 7) + "  "
                + padL(ratio, 7) + "  "
                + (natOk ? "Y" : "FAIL"));
        }

        trace("\n=================================================================");
        trace("Profile Complete. ratio > 2 = degradation, > 10 = catastrophic.");
        trace("=================================================================");
    }

    // ==================================================================
    // O(n) 扫描成本基准
    // ==================================================================
    public static function runScanCostBench():Void {
        trace("=================================================================");
        trace("O(n) Scan Cost Benchmark");
        trace("=================================================================");
        trace("Measures cost of a single-pass risk detection scan");

        var sizes:Array = [1000, 5000, 10000, 20000, 50000];
        var REPEATS:Number = 5;

        for (var si:Number = 0; si < sizes.length; si++) {
            var sz:Number = sizes[si];
            resetRng();
            var arr:Array = new Array(sz);
            var i:Number;
            for (i = 0; i < sz; i++) arr[i] = rand() % (sz * 2);

            // 模拟风险扫描：单次遍历，检测 sorted/reverse/runs/等值比例
            var tScan:Number = 0;
            for (var r:Number = 0; r < REPEATS; r++) {
                var st:Number = getTimer();
                // --- 扫描逻辑 ---
                var ascRuns:Number = 0;
                var descRuns:Number = 0;
                var eqCount:Number = 0;
                var totalRuns:Number = 1;
                var maxRun:Number = 1;
                var curRun:Number = 1;
                var prev:Number = arr[0];
                var cur:Number;
                var wasAsc:Boolean = true;

                for (i = 1; i < sz; i++) {
                    cur = arr[i];
                    if (cur > prev) {
                        if (!wasAsc) { totalRuns++; curRun = 1; }
                        wasAsc = true;
                        curRun++;
                        ascRuns++;
                    } else if (cur < prev) {
                        if (wasAsc) { totalRuns++; curRun = 1; }
                        wasAsc = false;
                        curRun++;
                        descRuns++;
                    } else {
                        eqCount++;
                        curRun++;
                    }
                    if (curRun > maxRun) maxRun = curRun;
                    prev = cur;
                }
                // --- 扫描结束 ---
                tScan += getTimer() - st;
            }

            var avgScan:Number = Math.round(tScan / REPEATS * 100) / 100;
            trace("  n=" + padL(String(sz), 6) + "  scan=" + padL(String(avgScan), 6) + "ms"
                + "  (runs=" + totalRuns + " maxRun=" + maxRun + " eq%=" + Math.round(eqCount / sz * 100) + ")");
        }

        trace("\n=================================================================");
    }

    // ==================================================================
    // 精简扫描 + 路由模拟
    // ==================================================================
    public static function runRoutingSim():Void {
        trace("=================================================================");
        trace("Sort Router Simulation (size=10000)");
        trace("=================================================================");
        trace("Lean scan v2: asc/desc/eq counts + 64-sample cardinality estimate");
        trace("Route: cardinality<=20 OR orderRatio>0.95 -> IntroSort, else -> Native");
        trace("");

        var sz:Number = 10000;
        var REPEATS:Number = 3;

        var dists:Array = [
            "random", "sorted", "reverse", "allEqual",
            "twoValues", "threeValues", "fewUnique5", "fewUnique10",
            "organPipe", "sawTooth20", "sawTooth100",
            "nearSorted1", "nearSorted5", "nearSorted10",
            "nearReverse1", "nearReverse5",
            "sortedTailRand", "sortedMidRand",
            "pushFront", "pushBack"
        ];

        // 先测量精简扫描成本
        resetRng();
        var randArr:Array = new Array(sz);
        var ii:Number;
        for (ii = 0; ii < sz; ii++) randArr[ii] = rand() % (sz * 2);

        var scanCost:Number = 0;
        var scanReps:Number = 10;
        for (var sr:Number = 0; sr < scanReps; sr++) {
            var sst:Number = getTimer();
            leanScan(randArr, sz);
            scanCost += getTimer() - sst;
        }
        trace("Lean scan cost (n=10000, random): " + (Math.round(scanCost / scanReps * 100) / 100) + "ms");
        trace("");

        trace(padR("distribution", 18) + "  " + padL("Router", 7) + "  " + padL("Native", 7) + "  " + padL("Intro", 7)
            + "  route  asc%  desc%  eq%  card");

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            resetRng();
            var master:Array = generateArray(sz, dist);

            // 扫描决策
            var scanResult:Array = leanScan(master, sz);
            var ascR:Number = scanResult[0];
            var descR:Number = scanResult[1];
            var eqR:Number = scanResult[2];
            var card:Number = scanResult[3];
            var orderR:Number = (ascR > descR) ? ascR : descR;
            var useNative:Boolean = (card > 20) && (orderR <= 0.95);

            // 路由排序计时
            var tRouter:Number = 0;
            for (var r:Number = 0; r < REPEATS; r++) {
                var a0:Array = master.slice();
                var st:Number = getTimer();
                // 扫描
                var sr2:Array = leanScan(a0, sz);
                var aR:Number = sr2[0]; var dR:Number = sr2[1];
                var card2:Number = sr2[3];
                var oR:Number = (aR > dR) ? aR : dR;
                if (card2 <= 20 || oR > 0.95) {
                    IntroSort.sort(a0, null);
                } else {
                    a0.sort(Array.NUMERIC);
                }
                tRouter += getTimer() - st;
            }

            // Native 对照
            var tNat:Number = 0;
            for (r = 0; r < REPEATS; r++) {
                var a1:Array = master.slice();
                st = getTimer();
                a1.sort(Array.NUMERIC);
                tNat += getTimer() - st;
            }

            // IntroSort 对照
            var tIntro:Number = 0;
            for (r = 0; r < REPEATS; r++) {
                var a2:Array = master.slice();
                st = getTimer();
                IntroSort.sort(a2, null);
                tIntro += getTimer() - st;
            }

            var avgRouter:Number = Math.round(tRouter / REPEATS);
            var avgNat:Number = Math.round(tNat / REPEATS);
            var avgIntro:Number = Math.round(tIntro / REPEATS);
            var route:String = useNative ? "NAT" : "INT";

            trace(padR(dist, 18) + "  "
                + padL(String(avgRouter), 7) + "  "
                + padL(String(avgNat), 7) + "  "
                + padL(String(avgIntro), 7) + "  "
                + padR(route, 5) + " "
                + padL(String(Math.round(ascR * 100)), 4) + "% "
                + padL(String(Math.round(descR * 100)), 4) + "% "
                + padL(String(Math.round(eqR * 100)), 4) + "% "
                + padL(String(card), 4));
        }

        trace("\n=================================================================");
        trace("Router wins if its time <= min(Native, IntroSort) + scan overhead");
        trace("=================================================================");
    }

    /**
     * 精简风险扫描 v2 — 单次遍历 O(n)
     * 同时计算：有序度(asc/desc) + 相邻等值率 + 采样 cardinality
     * 返回 [ascRatio, descRatio, eqRatio, sampleCardinality]
     *
     * cardinality 采样：每隔 stride 取一个值存入小数组，
     * 用 O(k^2) 去重计数，k=64 时成本约 64*64=4096 次比较（微不足道）
     */
    private static function leanScan(arr:Array, n:Number):Array {
        var ascCnt:Number = 0;
        var descCnt:Number = 0;
        var eqCnt:Number = 0;
        var prev:Number = arr[0];
        var cur:Number;
        var total:Number = n - 1;

        // cardinality 采样：采 64 个等距样本
        var SAMPLE_K:Number = 64;
        var stride:Number = n / SAMPLE_K;
        if (stride < 1) stride = 1;
        var samples:Array = new Array(SAMPLE_K);
        var sIdx:Number = 0;
        var nextSample:Number = 0;

        for (var i:Number = 0; i < n; i++) {
            cur = arr[i];
            if (i > 0) {
                if (cur > prev) { ascCnt++; }
                else if (cur < prev) { descCnt++; }
                else { eqCnt++; }
            }
            // 采样
            if (i >= nextSample && sIdx < SAMPLE_K) {
                samples[sIdx] = cur;
                sIdx++;
                nextSample += stride;
            }
            prev = cur;
        }

        // O(k^2) 去重计数
        var uniq:Number = 0;
        for (i = 0; i < sIdx; i++) {
            var dup:Boolean = false;
            var sv:Number = samples[i];
            for (var j:Number = 0; j < i; j++) {
                if (samples[j] === sv) { dup = true; break; }
            }
            if (!dup) uniq++;
        }

        return [ascCnt / total, descCnt / total, eqCnt / total, uniq];
    }

    // ==================================================================
    // 数据生成
    // ==================================================================
    private static function generateArray(sz:Number, dist:String):Array {
        var arr:Array = new Array(sz);
        var i:Number, j:Number, tmp:Number, half:Number, k:Number;

        if (dist === "random") {
            for (i = 0; i < sz; i++) arr[i] = rand() % (sz * 2);

        } else if (dist === "sorted") {
            for (i = 0; i < sz; i++) arr[i] = i;

        } else if (dist === "reverse") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;

        } else if (dist === "allEqual") {
            for (i = 0; i < sz; i++) arr[i] = 42;

        } else if (dist === "twoValues") {
            for (i = 0; i < sz; i++) arr[i] = i % 2;

        } else if (dist === "threeValues") {
            for (i = 0; i < sz; i++) arr[i] = i % 3;

        } else if (dist === "fewUnique5") {
            for (i = 0; i < sz; i++) arr[i] = rand() % 5;

        } else if (dist === "fewUnique10") {
            for (i = 0; i < sz; i++) arr[i] = rand() % 10;

        } else if (dist === "organPipe") {
            half = sz >> 1;
            for (i = 0; i < half; i++) arr[i] = i;
            for (i = half; i < sz; i++) arr[i] = sz - 1 - i;

        } else if (dist === "sawTooth20") {
            for (i = 0; i < sz; i++) arr[i] = i % 20;

        } else if (dist === "sawTooth100") {
            for (i = 0; i < sz; i++) arr[i] = i % 100;

        } else if (dist === "nearSorted1") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.01));
            for (i = 0; i < k; i++) {
                j = rand() % sz;
                tmp = rand() % sz;
                var v:Number = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v;
            }

        } else if (dist === "nearSorted5") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.05));
            for (i = 0; i < k; i++) {
                j = rand() % sz;
                tmp = rand() % sz;
                v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v;
            }

        } else if (dist === "nearSorted10") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.10));
            for (i = 0; i < k; i++) {
                j = rand() % sz;
                tmp = rand() % sz;
                v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v;
            }

        } else if (dist === "nearReverse1") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;
            k = Math.max(1, Math.round(sz * 0.01));
            for (i = 0; i < k; i++) {
                j = rand() % sz;
                tmp = rand() % sz;
                v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v;
            }

        } else if (dist === "nearReverse5") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;
            k = Math.max(1, Math.round(sz * 0.05));
            for (i = 0; i < k; i++) {
                j = rand() % sz;
                tmp = rand() % sz;
                v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v;
            }

        } else if (dist === "sortedTailRand") {
            // 前90%有序，尾部10%随机
            var cutoff:Number = Math.round(sz * 0.9);
            for (i = 0; i < cutoff; i++) arr[i] = i;
            for (i = cutoff; i < sz; i++) arr[i] = rand() % (sz * 2);

        } else if (dist === "sortedMidRand") {
            // 前45%有序 + 中间10%随机 + 后45%有序
            var seg:Number = Math.round(sz * 0.45);
            var mid:Number = sz - seg - seg;
            for (i = 0; i < seg; i++) arr[i] = i;
            for (i = seg; i < seg + mid; i++) arr[i] = rand() % (sz * 2);
            for (i = seg + mid; i < sz; i++) arr[i] = i;

        } else if (dist === "pushFront") {
            // 有序但最大值在首位
            arr[0] = sz;
            for (i = 1; i < sz; i++) arr[i] = i;

        } else if (dist === "pushBack") {
            // 有序但最小值在末位
            for (i = 0; i < sz - 1; i++) arr[i] = i + 1;
            arr[sz - 1] = 0;

        } else {
            // fallback: random
            for (i = 0; i < sz; i++) arr[i] = rand() % (sz * 2);
        }

        return arr;
    }

    // ==================================================================
    // 工具函数
    // ==================================================================
    private static function isSorted(arr:Array):Boolean {
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i - 1] > arr[i]) return false;
        }
        return true;
    }

    private static function padR(s:String, w:Number):String {
        while (length(s) < w) s += " ";
        return s;
    }

    private static function padL(s:String, w:Number):String {
        while (length(s) < w) s = " " + s;
        return s;
    }
}
