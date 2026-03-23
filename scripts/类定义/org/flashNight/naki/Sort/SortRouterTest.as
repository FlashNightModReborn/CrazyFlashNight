import org.flashNight.naki.Sort.*;

/**
 * SortRouterTest - 路由排序正确性 + 性能验证
 *
 * 覆盖：
 * - 正确性：20 种分布 × 排序结果验证
 * - 路由决策：锁定几个高信号输入的预期路径
 * - 交叉验证：vs IntroSort(null) 结果一致
 * - 性能基准：Router vs Native vs IntroSort vs PDQSort
 * - 小数组路径：n=0..63 边界
 * - 比较器路径：走 TimSort
 */
class org.flashNight.naki.Sort.SortRouterTest {

    private static var totalTests:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    // LCG
    private static var _seed:Number;
    private static function resetRng():Void { _seed = 12345; }
    private static function rand():Number {
        return (_seed = (_seed * 1664525 + 1013904223) % 4294967296);
    }

    // ==================================================================
    // 主入口
    // ==================================================================
    public static function runTests():Void {
        totalTests = 0; passedTests = 0; failedTests = 0;
        trace("=================================================================");
        trace("SortRouter Test Suite");
        trace("=================================================================");

        runCorrectnessTests();
        runSmallArrayTests();
        runComparatorTests();
        runRoutingDecisionTests();
        runMultiSeedStabilityTests();
        runCrossValidation();
        runPerformanceTests();

        printSummary();
    }

    public static function runQuickTests():Void {
        totalTests = 0; passedTests = 0; failedTests = 0;
        trace("=================================================================");
        trace("SortRouter Quick Tests");
        trace("=================================================================");

        runCorrectnessTests();
        runSmallArrayTests();
        runComparatorTests();
        runRoutingDecisionTests();
        runMultiSeedStabilityTests();

        printSummary();
    }

    // ==================================================================
    // 正确性测试：20 种分布 × n=10000
    // ==================================================================
    private static function runCorrectnessTests():Void {
        trace("\n--- Correctness Tests (n=10000) ---");

        var dists:Array = [
            "random", "sorted", "reverse", "allEqual",
            "twoValues", "threeValues", "fewUnique5", "fewUnique10",
            "organPipe", "sawTooth20", "sawTooth100",
            "nearSorted1", "nearSorted5", "nearSorted10",
            "nearReverse1", "nearReverse5",
            "sortedTailRand", "sortedMidRand",
            "descPlateaus",
            "pushFront", "pushBack"
        ];

        var sz:Number = 10000;
        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            resetRng();
            var arr:Array = generateArray(sz, dist);
            SortRouter.sort(arr, null);
            assertSorted(arr, "correctness:" + dist);
        }
    }

    // ==================================================================
    // 小数组边界
    // ==================================================================
    private static function runSmallArrayTests():Void {
        trace("\n--- Small Array Tests ---");

        assertSortedResult([], "empty");
        assertSortedResult([1], "single");
        assertSortedResult([2, 1], "two-reverse");
        assertSortedResult([1, 2], "two-sorted");
        assertSortedResult([5, 5], "two-equal");

        // 三元素全排列
        var perms:Array = [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]];
        var allOk:Boolean = true;
        for (var p:Number = 0; p < perms.length; p++) {
            var s:Array = perms[p].slice();
            SortRouter.sort(s, null);
            if (s[0] !== 1 || s[1] !== 2 || s[2] !== 3) { allOk = false; break; }
        }
        assertTrue(allOk, "three-all-perms");

        // 阈值边界 n=32, 63, 64, 65
        var thresholds:Array = [32, 63, 64, 65, 100];
        for (var ti:Number = 0; ti < thresholds.length; ti++) {
            var n:Number = thresholds[ti];
            resetRng();
            var arr:Array = new Array(n);
            for (var i:Number = 0; i < n; i++) arr[i] = rand() % (n * 2);
            SortRouter.sort(arr, null);
            assertSorted(arr, "threshold-n=" + n);
        }
    }

    // ==================================================================
    // 比较器路径 → TimSort
    // ==================================================================
    private static function runComparatorTests():Void {
        trace("\n--- Comparator Path Tests ---");

        var cmp:Function = function(a, b):Number { return a - b; };
        resetRng();
        var arr:Array = new Array(1000);
        for (var i:Number = 0; i < 1000; i++) arr[i] = rand() % 2000;
        SortRouter.sort(arr, cmp);
        assertSorted(arr, "cmp-random-1000");

        // 逆序比较器
        var cmpDesc:Function = function(a, b):Number { return b - a; };
        resetRng();
        arr = new Array(500);
        for (i = 0; i < 500; i++) arr[i] = rand() % 1000;
        SortRouter.sort(arr, cmpDesc);
        var descOk:Boolean = true;
        for (i = 1; i < arr.length; i++) {
            if (arr[i - 1] < arr[i]) { descOk = false; break; }
        }
        assertTrue(descOk, "cmp-desc-500");

        // 字符串排序
        var strArr:Array = ["banana", "apple", "cherry", "date", "apricot"];
        var strCmp:Function = function(a, b):Number {
            if (a < b) return -1;
            if (a > b) return 1;
            return 0;
        };
        SortRouter.sort(strArr, strCmp);
        assertTrue(strArr[0] === "apple" && strArr[1] === "apricot" && strArr[4] === "date", "cmp-strings");
    }

    // ==================================================================
    // 路由决策测试
    // ==================================================================
    private static function runRoutingDecisionTests():Void {
        trace("\n--- Route Decision Tests ---");

        assertRoute("random", 10000, SortRouter.ROUTE_NATIVE);
        assertRoute("organPipe", 10000, SortRouter.ROUTE_NATIVE);
        assertRoute("sawTooth100", 10000, SortRouter.ROUTE_NATIVE);
        assertRoute("sorted", 10000, SortRouter.ROUTE_INTRO);
        assertRoute("reverse", 10000, SortRouter.ROUTE_INTRO);
        assertRoute("allEqual", 10000, SortRouter.ROUTE_INTRO);
        assertRoute("twoValues", 10000, SortRouter.ROUTE_INTRO);
        assertRoute("sawTooth20", 10000, SortRouter.ROUTE_INTRO);
        assertRoute("pushFront", 10000, SortRouter.ROUTE_INTRO);
        assertRoute("pushBack", 10000, SortRouter.ROUTE_INTRO);

        // near-sorted 双端探针支线
        assertRoute("nearSorted1", 10000, SortRouter.ROUTE_INTRO);
        assertRoute("nearSorted5", 10000, SortRouter.ROUTE_NATIVE);
        // nearReverse1%: perfect-sample 捷径概率性吃掉（~55% INTRO, ~45% NATIVE）
        // desc-dominant 短路确保非 perfect-sample 的路径直达 NATIVE（无深扫税）
        // 不做硬断言 — 路由方向取决于采样命中率
        assertRoute("sortedTailRand", 10000, SortRouter.ROUTE_NATIVE);
        assertRoute("sortedMidRand", 10000, SortRouter.ROUTE_NATIVE);
        // desc-dominant 平台结构：cardinality > 20 但 native O(n²)
        assertRoute("descPlateaus", 10000, SortRouter.ROUTE_INTRO);
    }

    // ==================================================================
    // 多 seed 稳定性测试（自动化保护）
    // ==================================================================
    private static function runMultiSeedStabilityTests():Void {
        trace("\n--- Multi-Seed Stability Tests ---");

        var seeds:Array = [12345, 54321, 99999, 77777, 31415, 271828, 141421, 173205];

        // nearSorted1: 必须 8/8 INTRO（核心拦截目标）
        assertStableRoute("nearSorted1", 10000, seeds, SortRouter.ROUTE_INTRO, 8);

        // sortedTailRand: 必须 8/8 NATIVE（常见模式，不可误判）
        assertStableRoute("sortedTailRand", 10000, seeds, SortRouter.ROUTE_NATIVE, 8);

        // sortedMidRand: 必须 8/8 NATIVE
        assertStableRoute("sortedMidRand", 10000, seeds, SortRouter.ROUTE_NATIVE, 8);

        // descPlateaus: 必须 8/8 INTRO（sEq 守卫阻拦 desc 短路，desc Stage B 拦截）
        assertStableRoute("descPlateaus", 10000, seeds, SortRouter.ROUTE_INTRO, 8);

        // nearReverse1: 不稳定是已知性质（perfect-sample 概率性捕获）
        // 非 perfect-sample 路径走 desc 短路 → NATIVE（sEq ≤ 2）
        assertMinRouteCount("nearReverse1", 10000, seeds, SortRouter.ROUTE_NATIVE, 4);
    }

    /**
     * 断言 dist 在所有 seeds 上都路由到 expected。
     * minCount = seeds.length 表示要求完全稳定。
     */
    private static function assertStableRoute(dist:String, sz:Number,
            seeds:Array, expected:String, minCount:Number):Void {
        totalTests++;
        var count:Number = 0;
        for (var si:Number = 0; si < seeds.length; si++) {
            _seed = seeds[si];
            var arr:Array = generateArray(sz, dist);
            if (SortRouter.classifyNumeric(arr) === expected) count++;
        }
        if (count >= minCount) {
            trace("PASS: stability:" + dist + " -> " + expected + " " + count + "/" + seeds.length);
            passedTests++;
        } else {
            trace("FAIL: stability:" + dist + " -> " + expected + " only " + count + "/" + seeds.length + " (need " + minCount + ")");
            failedTests++;
        }
    }

    /**
     * 断言 dist 在至少 minCount 个 seeds 上路由到 expected。
     * 用于已知不稳定的分布（如 nearReverse1）。
     */
    private static function assertMinRouteCount(dist:String, sz:Number,
            seeds:Array, expected:String, minCount:Number):Void {
        totalTests++;
        var count:Number = 0;
        for (var si:Number = 0; si < seeds.length; si++) {
            _seed = seeds[si];
            var arr:Array = generateArray(sz, dist);
            if (SortRouter.classifyNumeric(arr) === expected) count++;
        }
        if (count >= minCount) {
            trace("PASS: minRoute:" + dist + " -> " + expected + " " + count + "/" + seeds.length + " (>=" + minCount + ")");
            passedTests++;
        } else {
            trace("FAIL: minRoute:" + dist + " -> " + expected + " only " + count + "/" + seeds.length + " (need >=" + minCount + ")");
            failedTests++;
        }
    }

    // ==================================================================
    // 交叉验证 vs IntroSort
    // ==================================================================
    private static function runCrossValidation():Void {
        trace("\n--- Cross-Validation vs IntroSort ---");

        var dists:Array = ["random", "sorted", "reverse", "allEqual", "twoValues",
            "fewUnique5", "organPipe", "nearSorted1", "pushFront"];
        var sz:Number = 5000;

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            resetRng();
            var a1:Array = generateArray(sz, dist);
            resetRng();
            var a2:Array = generateArray(sz, dist);

            SortRouter.sort(a1, null);
            IntroSort.sort(a2, null);

            var match:Boolean = true;
            for (var i:Number = 0; i < sz; i++) {
                if (a1[i] !== a2[i]) { match = false; break; }
            }
            assertTrue(match, "cross:" + dist);
        }
    }

    // ==================================================================
    // 性能基准
    // ==================================================================
    private static function runPerformanceTests():Void {
        trace("\n--- Performance Benchmarks ---");
        trace("Format: Router / Native / IntroSort / PDQSort (ms, avg of 3)");

        var sz:Number = 10000;
        var REPEATS:Number = 3;

        var dists:Array = [
            "random", "sorted", "reverse", "allEqual",
            "twoValues", "threeValues", "fewUnique5", "fewUnique10",
            "organPipe", "sawTooth20", "sawTooth100",
            "nearSorted1", "nearSorted5", "nearSorted10",
            "nearReverse1", "nearReverse5",
            "sortedTailRand", "sortedMidRand",
            "descPlateaus",
            "pushFront", "pushBack"
        ];

        trace(padR("distribution", 18) + "  " + padL("Router", 7) + "  " + padL("Native", 7) + "  " + padL("Intro", 7) + "  " + padL("PDQ", 7));

        for (var di:Number = 0; di < dists.length; di++) {
            var dist:String = dists[di];
            resetRng();
            var master:Array = generateArray(sz, dist);

            var tRouter:Number = 0;
            for (var r:Number = 0; r < REPEATS; r++) {
                var a0:Array = master.slice();
                var st:Number = getTimer();
                SortRouter.sort(a0, null);
                tRouter += getTimer() - st;
            }

            var tNat:Number = 0;
            for (r = 0; r < REPEATS; r++) {
                var a1:Array = master.slice();
                st = getTimer();
                a1.sort(Array.NUMERIC);
                tNat += getTimer() - st;
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

            trace(padR(dist, 18) + "  "
                + padL(String(Math.round(tRouter / REPEATS)), 7) + "  "
                + padL(String(Math.round(tNat / REPEATS)), 7) + "  "
                + padL(String(Math.round(tIntro / REPEATS)), 7) + "  "
                + padL(String(Math.round(tPdq / REPEATS)), 7));
        }
    }

    // ==================================================================
    // 数据生成（与 NativeSortProfile 一致）
    // ==================================================================
    private static function generateArray(sz:Number, dist:String):Array {
        var arr:Array = new Array(sz);
        var i:Number, j:Number, tmp:Number, half:Number, k:Number, v:Number;

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
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist === "nearSorted5") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.05));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist === "nearSorted10") {
            for (i = 0; i < sz; i++) arr[i] = i;
            k = Math.max(1, Math.round(sz * 0.10));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist === "nearReverse1") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;
            k = Math.max(1, Math.round(sz * 0.01));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist === "nearReverse5") {
            for (i = 0; i < sz; i++) arr[i] = sz - i;
            k = Math.max(1, Math.round(sz * 0.05));
            for (i = 0; i < k; i++) { j = rand() % sz; tmp = rand() % sz; v = arr[j]; arr[j] = arr[tmp]; arr[tmp] = v; }
        } else if (dist === "sortedTailRand") {
            var cutoff:Number = Math.round(sz * 0.9);
            for (i = 0; i < cutoff; i++) arr[i] = i;
            for (i = cutoff; i < sz; i++) arr[i] = rand() % (sz * 2);
        } else if (dist === "sortedMidRand") {
            var seg:Number = Math.round(sz * 0.45);
            var mid:Number = sz - seg - seg;
            for (i = 0; i < seg; i++) arr[i] = i;
            for (i = seg; i < seg + mid; i++) arr[i] = rand() % (sz * 2);
            for (i = seg + mid; i < sz; i++) arr[i] = i;
        } else if (dist === "descPlateaus") {
            // 25 个降序值，每个重复 sz/25 次
            // cardinality=25 > 20 (过 A-2), 但 native 在此上 O(n²)
            var plateauSize:Number = Math.floor(sz / 25);
            var valIdx:Number = 0;
            for (i = 0; i < sz; i++) {
                arr[i] = 25 - Math.floor(i / plateauSize);
                if (arr[i] < 1) arr[i] = 1;
            }
        } else if (dist === "pushFront") {
            arr[0] = sz;
            for (i = 1; i < sz; i++) arr[i] = i;
        } else if (dist === "pushBack") {
            for (i = 0; i < sz - 1; i++) arr[i] = i + 1;
            arr[sz - 1] = 0;
        } else {
            for (i = 0; i < sz; i++) arr[i] = rand() % (sz * 2);
        }
        return arr;
    }

    // ==================================================================
    // 工具函数
    // ==================================================================
    private static function assertSorted(arr:Array, name:String):Void {
        totalTests++;
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i - 1] > arr[i]) {
                trace("FAIL: " + name + " - not sorted at [" + i + "]: " + arr[i-1] + " > " + arr[i]);
                failedTests++;
                return;
            }
        }
        trace("PASS: " + name);
        passedTests++;
    }

    private static function assertSortedResult(input:Array, name:String):Void {
        totalTests++;
        var arr:Array = input.slice();
        SortRouter.sort(arr, null);
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i - 1] > arr[i]) {
                trace("FAIL: " + name + " - not sorted at [" + i + "]");
                failedTests++;
                return;
            }
        }
        trace("PASS: " + name);
        passedTests++;
    }

    private static function assertTrue(cond:Boolean, name:String):Void {
        totalTests++;
        if (!cond) {
            trace("FAIL: " + name);
            failedTests++;
        } else {
            trace("PASS: " + name);
            passedTests++;
        }
    }

    private static function assertRoute(dist:String, sz:Number, expected:String):Void {
        totalTests++;
        resetRng();
        var arr:Array = generateArray(sz, dist);
        var actual:String = SortRouter.classifyNumeric(arr);
        if (actual !== expected) {
            trace("FAIL: route:" + dist + " - expected " + expected + ", got " + actual);
            failedTests++;
        } else {
            trace("PASS: route:" + dist + " -> " + actual);
            passedTests++;
        }
    }

    private static function padR(s:String, w:Number):String {
        while (length(s) < w) s += " ";
        return s;
    }

    private static function padL(s:String, w:Number):String {
        while (length(s) < w) s = " " + s;
        return s;
    }

    private static function printSummary():Void {
        trace("\n=================================================================");
        trace("TEST SUMMARY");
        trace("=================================================================");
        trace("Total: " + totalTests + "  Passed: " + passedTests + "  Failed: " + failedTests);
        if (failedTests === 0) {
            trace("ALL TESTS PASSED!");
        } else {
            trace(failedTests + " test(s) FAILED.");
        }
        trace("=================================================================");
    }
}
