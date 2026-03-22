import org.flashNight.naki.Sort.*;

/**
 * IntroSort 综合测试套件
 *
 * 覆盖范围：
 * - 基础功能（空/单元素/两元素/三元素全排列/已排序/逆序/随机/重复/全等/负数）
 * - 边界情况（阈值附近3~64/混合类型/极端重复）
 * - 算法特性（自适应分区检测/Hoare路径/DNF路径/堆排序回退）
 * - 数据类型（字符串/对象/混合/自定义比较器）
 * - 一致性（多次一致/就地/幂等）
 * - 对抗性输入（管风琴/锯齿/交替两值/三值/全等+异常值/尾部扰动）
 * - 交叉验证（vs PDQSort 结果一致性）
 * - 性能基准（IntroSort vs PDQSort vs TimSort vs Array.sort，多分布/多规模）
 */
class org.flashNight.naki.Sort.IntroSortTest {

    private static var totalTests:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    private static var STRESS_SIZE:Number = 10000;

    // 确定性LCG随机数
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
        trace("IntroSort Comprehensive Test Suite");
        trace("=================================================================");

        runBasicTests();
        runBoundaryTests();
        runAlgorithmTests();
        runDataTypeTests();
        runCompareFunctionTests();
        runConsistencyTests();
        runAdversarialTests();
        runCrossValidationTests();
        runStressTests();
        runPerformanceTests();

        printTestSummary();
    }

    public static function runQuickTests():Void {
        totalTests = 0; passedTests = 0; failedTests = 0;
        trace("=================================================================");
        trace("IntroSort Quick Tests");
        trace("=================================================================");
        runBasicTests();
        runBoundaryTests();
        runCrossValidationTests();
        printTestSummary();
    }

    // ==================================================================
    // 基础功能测试
    // ==================================================================
    private static function runBasicTests():Void {
        trace("\n--- Basic Functionality Tests ---");

        assertEquals([], IntroSort.sort([], null), "Empty Array");
        assertEquals([42], IntroSort.sort([42], null), "Single Element");
        assertEquals([1, 2], IntroSort.sort([2, 1], null), "Two Elements (Reverse)");
        assertEquals([1, 2], IntroSort.sort([1, 2], null), "Two Elements (Sorted)");
        assertEquals([5, 5], IntroSort.sort([5, 5], null), "Two Elements (Equal)");

        // 三元素全排列
        var perms:Array = [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]];
        var allOk:Boolean = true;
        for (var p:Number = 0; p < perms.length; p++) {
            var s:Array = IntroSort.sort(perms[p].slice(), null);
            if (s[0] !== 1 || s[1] !== 2 || s[2] !== 3) { allOk = false; break; }
        }
        assertTrue(allOk, "Three Elements (All 6 Permutations)", "All correct");

        assertEquals([1,2,3,4,5,6,7,8,9,10], IntroSort.sort([1,2,3,4,5,6,7,8,9,10], null), "Already Sorted");
        assertEquals([1,2,3,4,5,6,7,8,9,10], IntroSort.sort([10,9,8,7,6,5,4,3,2,1], null), "Reverse Sorted");
        assertEquals([1,1,2,3,4,5,5,6,9], IntroSort.sort([3,1,4,1,5,9,2,6,5], null), "Random Array");
        assertEquals([1,3,3,3,5,5,7,8,9], IntroSort.sort([5,3,8,3,9,1,5,7,3], null), "Duplicate Elements");
        assertEquals([7,7,7,7,7,7,7], IntroSort.sort([7,7,7,7,7,7,7], null), "All Same Elements");
        assertEquals([-5,-3,-1,0,2,4], IntroSort.sort([4,-1,2,-5,0,-3], null), "Negative Numbers");
        assertEquals([-1000000,0,1000000], IntroSort.sort([1000000,-1000000,0], null), "Large Range");
    }

    // ==================================================================
    // 边界情况测试
    // ==================================================================
    private static function runBoundaryTests():Void {
        trace("\n--- Boundary Case Tests ---");

        // 阈值附近全扫（触发插入排序/Hoare/DNF各路径）
        var sizes:Array = [3,4,5,8,10,16,24,30,31,32,33,34,48,64,100,128,129,200];
        var allOk:Boolean = true;
        resetRng();
        for (var si:Number = 0; si < sizes.length; si++) {
            var sz:Number = sizes[si];
            var arr:Array = new Array(sz);
            for (var fi:Number = 0; fi < sz; fi++) arr[fi] = rand() % (sz * 2);
            var expected:Array = arr.slice();
            expected.sort(Array.NUMERIC);
            IntroSort.sort(arr, null);
            if (!compareArrays(expected, arr)) { allOk = false; trace("  Failed at size=" + sz); break; }
        }
        assertTrue(allOk, "Threshold Boundary Sizes (3~200)", "All sizes correct");

        // 混合类型+比较器
        var mixArr:Array = [1, "2", 3, "1", 4];
        IntroSort.sort(mixArr, function(a, b):Number { return Number(a) - Number(b); });
        var mixOk:Boolean = true;
        for (var mi:Number = 1; mi < mixArr.length; mi++) {
            if (Number(mixArr[mi - 1]) > Number(mixArr[mi])) { mixOk = false; break; }
        }
        assertTrue(mixOk, "Mixed Types With Comparator", "Correct");

        // 中等规模
        resetRng();
        var medArr:Array = genRandom(1000);
        var st:Number = getTimer();
        IntroSort.sort(medArr, null);
        var et:Number = getTimer();
        assertTrue(isSortedArr(medArr), "Moderate Array (1000)", "Sorted in " + (et - st) + "ms");

        // 极端重复
        var dupSizes:Array = [50, 200, 500, 1000];
        var dupOk:Boolean = true;
        for (var di:Number = 0; di < dupSizes.length; di++) {
            var ds:Number = dupSizes[di];
            var darr:Array = new Array(ds);
            for (var dj:Number = 0; dj < ds; dj++) darr[dj] = 42;
            IntroSort.sort(darr, null);
            for (var dk:Number = 0; dk < ds; dk++) { if (darr[dk] !== 42) { dupOk = false; break; } }
            if (!dupOk) break;
        }
        assertTrue(dupOk, "Extreme Duplicates (50~1000)", "All handled correctly");
    }

    // ==================================================================
    // 算法特性测试
    // ==================================================================
    private static function runAlgorithmTests():Void {
        trace("\n--- Algorithm-Specific Tests ---");

        // 自适应分区检测：5种唯一值 → 样本等值概率高 → 应走DNF
        resetRng();
        var fewArr:Array = new Array(500);
        for (var fi:Number = 0; fi < 500; fi++) fewArr[fi] = rand() % 5;
        IntroSort.sort(fewArr, null);
        assertTrue(isSortedArr(fewArr), "Few Unique (DNF path)", "5 values sorted correctly");

        // 唯一值 → 样本不等 → 应走Hoare
        resetRng();
        var uniqArr:Array = new Array(500);
        for (var ui:Number = 0; ui < 500; ui++) uniqArr[ui] = rand() % 100000;
        IntroSort.sort(uniqArr, null);
        assertTrue(isSortedArr(uniqArr), "Unique Values (Hoare path)", "Sorted correctly");

        // 两值（高重复率，DNF路径）
        var twoArr:Array = new Array(500);
        for (var ti:Number = 0; ti < 500; ti++) twoArr[ti] = (ti % 2 === 0) ? 1 : 100;
        IntroSort.sort(twoArr, null);
        assertTrue(isSortedArr(twoArr), "Two Values (DNF path)", "Sorted correctly");

        // 堆排序回退（管风琴容易耗尽深度）
        var heapArr:Array = genOrganPipe(200);
        IntroSort.sort(heapArr, null);
        assertTrue(isSortedArr(heapArr), "Heapsort Fallback", "Organ pipe sorted correctly");

        // 有序检测
        var scenOk:Boolean = true;
        var scenarios:Array = [
            {arr: [1,2,3,4,5], name: "Fully Sorted"},
            {arr: [5,4,3,2,1], name: "Fully Reverse"},
            {arr: [1,2,3,5,4], name: "Nearly Sorted"}
        ];
        for (var sci:Number = 0; sci < scenarios.length; sci++) {
            var sc:Object = scenarios[sci];
            var ssa:Array = IntroSort.sort(sc.arr.slice(), null);
            if (!isSortedArr(ssa)) { scenOk = false; break; }
        }
        assertTrue(scenOk, "Ordered Detection", "All scenarios correct");

        assertEquals([1,2,3,4,5,6,7,8,9], IntroSort.sort([9,1,8,2,7,3,6,4,5], null), "Pivot Selection");
    }

    // ==================================================================
    // 数据类型测试
    // ==================================================================
    private static function runDataTypeTests():Void {
        trace("\n--- Data Type Tests ---");

        var strCmp:Function = function(a, b):Number { if (a < b) return -1; if (a > b) return 1; return 0; };
        assertEquals(["apple","banana","cherry","date"],
            IntroSort.sort(["banana","apple","cherry","date"], strCmp), "String Array");

        var objs:Array = [{name:"John",age:30},{name:"Jane",age:25},{name:"Bob",age:35}];
        IntroSort.sort(objs, function(a, b):Number { return a.age - b.age; });
        assertTrue(objs[0].age === 25 && objs[1].age === 30 && objs[2].age === 35,
            "Object Array", "Sorted by age");

        var tasks:Array = [{priority:1,name:"A"},{priority:3,name:"C"},{priority:2,name:"B"}];
        IntroSort.sort(tasks, function(a, b):Number { return a.priority - b.priority; });
        assertTrue(tasks[0].priority === 1 && tasks[1].priority === 2 && tasks[2].priority === 3,
            "Custom Objects", "Sorted by priority");
    }

    // ==================================================================
    // 比较函数测试
    // ==================================================================
    private static function runCompareFunctionTests():Void {
        trace("\n--- Compare Function Tests ---");

        // 大小写不敏感
        var ciArr:Array = ["apple","Orange","banana","grape","Cherry"];
        IntroSort.sort(ciArr, function(a, b):Number {
            var al:String = a.toLowerCase(), bl:String = b.toLowerCase();
            if (al < bl) return -1; if (al > bl) return 1; return 0;
        });
        var ciOk:Boolean = true;
        for (var ci:Number = 1; ci < ciArr.length; ci++) {
            if (ciArr[ci - 1].toLowerCase() > ciArr[ci].toLowerCase()) { ciOk = false; break; }
        }
        assertTrue(ciOk, "Case-Insensitive Compare", "Works correctly");

        assertEquals([5,4,3,2,1], IntroSort.sort([1,2,3,4,5], function(a, b):Number { return b - a; }), "Reverse Compare");

        // 多级排序
        var mlArr:Array = [{value:5,category:"A"},{value:3,category:"B"},{value:5,category:"B"},{value:3,category:"A"}];
        IntroSort.sort(mlArr, function(a, b):Number {
            if (a.category !== b.category) return (a.category < b.category) ? -1 : 1;
            return a.value - b.value;
        });
        assertTrue(mlArr[0].category === "A" && mlArr[0].value === 3 &&
                   mlArr[1].category === "A" && mlArr[1].value === 5 &&
                   mlArr[2].category === "B" && mlArr[2].value === 3 &&
                   mlArr[3].category === "B" && mlArr[3].value === 5,
            "Multi-Level Compare", "Works correctly");

        assertEquals([1,1,3,4,5], IntroSort.sort([3,1,4,1,5], null), "Null Compare Function");
    }

    // ==================================================================
    // 一致性测试
    // ==================================================================
    private static function runConsistencyTests():Void {
        trace("\n--- Consistency Tests ---");

        resetRng();
        var cArr:Array = genRandom(200);
        var s1:Array = IntroSort.sort(cArr.slice(), null);
        var s2:Array = IntroSort.sort(cArr.slice(), null);
        assertTrue(compareArrays(s1, s2), "Consistent Results", "Multiple sorts produce identical results");

        var ipArr:Array = [3,1,4,1,5,9,2,6];
        var ipResult:Array = IntroSort.sort(ipArr, null);
        assertTrue(ipArr === ipResult, "In-Place Sorting", "Returns same array reference");

        var idArr:Array = [3,1,4,1,5,9,2,6];
        var id1:Array = IntroSort.sort(idArr.slice(), null);
        var id2:Array = IntroSort.sort(id1.slice(), null);
        assertTrue(compareArrays(id1, id2), "Idempotency", "Sorting sorted array doesn't change it");
    }

    // ==================================================================
    // 对抗性输入测试
    // ==================================================================
    private static function runAdversarialTests():Void {
        trace("\n--- Adversarial Input Tests ---");

        var opArr:Array = genOrganPipe(500);
        IntroSort.sort(opArr, null);
        assertTrue(isSortedArr(opArr), "Organ Pipe (500)", "Sorted correctly");

        var stArr:Array = genSawTooth(500, 10);
        IntroSort.sort(stArr, null);
        assertTrue(isSortedArr(stArr), "Saw Tooth (500, period=10)", "Sorted correctly");

        var altArr:Array = new Array(500);
        for (var ai:Number = 0; ai < 500; ai++) altArr[ai] = (ai % 2 === 0) ? 1 : 100;
        IntroSort.sort(altArr, null);
        assertTrue(isSortedArr(altArr), "Alternating Two Values (500)", "Sorted correctly");

        resetRng();
        var tvArr:Array = new Array(1000);
        for (var tvi:Number = 0; tvi < 1000; tvi++) tvArr[tvi] = rand() % 3;
        IntroSort.sort(tvArr, null);
        assertTrue(isSortedArr(tvArr), "Three Values Random (1000)", "Sorted correctly");

        var drArr:Array = new Array(500);
        for (var dri:Number = 0; dri < 500; dri++) drArr[dri] = 50;
        drArr[0] = 1; drArr[100] = 99; drArr[499] = 0; drArr[250] = 100;
        IntroSort.sort(drArr, null);
        assertTrue(isSortedArr(drArr), "Mostly Equal + Outliers", "Sorted correctly");

        var ptArr:Array = new Array(200);
        for (var pti:Number = 0; pti < 200; pti++) ptArr[pti] = pti;
        ptArr[198] = 0; ptArr[199] = 1;
        IntroSort.sort(ptArr, null);
        assertTrue(isSortedArr(ptArr), "Sorted + Tail Perturbation", "Sorted correctly");

        var lgOp:Array = genOrganPipe(STRESS_SIZE);
        var st:Number = getTimer();
        IntroSort.sort(lgOp, null);
        var et:Number = getTimer();
        assertTrue(isSortedArr(lgOp), "Large Organ Pipe (" + STRESS_SIZE + ")",
            "Sorted in " + (et - st) + "ms");

        var cmpOp:Array = genOrganPipe(500);
        IntroSort.sort(cmpOp, function(a, b):Number { return a - b; });
        assertTrue(isSortedArr(cmpOp), "Organ Pipe (comparator path)", "Sorted correctly");
    }

    // ==================================================================
    // 交叉验证测试（vs PDQSort）
    // ==================================================================
    private static function runCrossValidationTests():Void {
        trace("\n--- Cross-Validation vs PDQSort ---");

        var distributions:Array = ["random", "sorted", "reverse", "duplicates", "organPipe", "fewUnique"];
        var crossSizes:Array = [100, 500, 2000, 5000];
        var allMatch:Boolean = true;

        for (var si:Number = 0; si < crossSizes.length; si++) {
            var sz:Number = crossSizes[si];
            for (var di:Number = 0; di < distributions.length; di++) {
                var dist:String = distributions[di];
                resetRng();
                var master:Array = generateArray(sz, dist);
                var introArr:Array = master.slice();
                var pdqArr:Array = master.slice();
                IntroSort.sort(introArr, null);
                PDQSort.sort(pdqArr, null);
                if (!compareArrays(introArr, pdqArr)) {
                    allMatch = false;
                    trace("  Mismatch: size=" + sz + " dist=" + dist);
                    break;
                }
            }
            if (!allMatch) break;
        }
        assertTrue(allMatch, "Cross-Validation (4 sizes x 6 distributions)",
            "IntroSort and PDQSort produce identical results");

        // 比较器路径交叉验证
        resetRng();
        var cmpMaster:Array = genRandom(1000);
        var introCmp:Array = cmpMaster.slice();
        var pdqCmp:Array = cmpMaster.slice();
        var numCmp:Function = function(a, b):Number { return a - b; };
        IntroSort.sort(introCmp, numCmp);
        PDQSort.sort(pdqCmp, numCmp);
        assertTrue(compareArrays(introCmp, pdqCmp), "Cross-Validation (comparator path, 1000)",
            "Results match");
    }

    // ==================================================================
    // 压力测试
    // ==================================================================
    private static function runStressTests():Void {
        trace("\n--- Stress Tests ---");

        var distributions:Array = ["random", "sorted", "reverse", "duplicates", "organPipe", "fewUnique"];
        var stressOk:Boolean = true;
        for (var di:Number = 0; di < distributions.length; di++) {
            var dist:String = distributions[di];
            resetRng();
            var arr:Array = generateArray(STRESS_SIZE, dist);
            IntroSort.sort(arr, null);
            if (!isSortedArr(arr)) {
                stressOk = false;
                trace("  Failed: " + dist);
                break;
            }
        }
        assertTrue(stressOk, "Stress Test (" + STRESS_SIZE + ", 6 distributions)", "All correct");

        resetRng();
        var repArr:Array = genRandom(500);
        var repOk:Boolean = true;
        for (var ri:Number = 0; ri < 5; ri++) {
            var ra:Array = repArr.slice();
            IntroSort.sort(ra, null);
            if (!isSortedArr(ra)) { repOk = false; break; }
        }
        assertTrue(repOk, "Repeated Sorting", "5 iterations consistent");
    }

    // ==================================================================
    // 性能基准测试
    // ==================================================================
    private static function runPerformanceTests():Void {
        trace("\n--- Performance Benchmarks ---");
        trace("Format: IntroSort(null) / PDQSort(null) / PDQSort(cmp) / TimSort(cmp) / Array.sort(NUMERIC) ms");

        var sizes:Array = [100, 1000, 5000, 10000];
        var distributions:Array = ["random", "sorted", "reverse", "duplicates", "organPipe", "fewUnique"];
        var REPEATS:Number = 3;
        var numCmp:Function = function(a, b):Number { return a - b; };

        for (var si:Number = 0; si < sizes.length; si++) {
            var sz:Number = sizes[si];
            trace("\n  Size: " + sz);

            for (var di:Number = 0; di < distributions.length; di++) {
                var dist:String = distributions[di];
                resetRng();
                var master:Array = generateArray(sz, dist);

                var tIntro:Number = 0;
                for (var r:Number = 0; r < REPEATS; r++) {
                    var a1:Array = master.slice();
                    var st:Number = getTimer();
                    IntroSort.sort(a1, null);
                    tIntro += getTimer() - st;
                }

                var tPdqN:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a2:Array = master.slice();
                    st = getTimer();
                    PDQSort.sort(a2, null);
                    tPdqN += getTimer() - st;
                }

                var tPdqC:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a3:Array = master.slice();
                    st = getTimer();
                    PDQSort.sort(a3, numCmp);
                    tPdqC += getTimer() - st;
                }

                var tTs:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a4:Array = master.slice();
                    st = getTimer();
                    TimSort.sort(a4, numCmp);
                    tTs += getTimer() - st;
                }

                var tNat:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a5:Array = master.slice();
                    st = getTimer();
                    a5.sort(Array.NUMERIC);
                    tNat += getTimer() - st;
                }

                trace("    " + padR(dist, 12) + ": "
                    + padL(String(Math.round(tIntro / REPEATS)), 5) + " / "
                    + padL(String(Math.round(tPdqN / REPEATS)), 5) + " / "
                    + padL(String(Math.round(tPdqC / REPEATS)), 5) + " / "
                    + padL(String(Math.round(tTs / REPEATS)), 5) + " / "
                    + padL(String(Math.round(tNat / REPEATS)), 5));
            }
        }
    }

    // ==================================================================
    // 辅助函数
    // ==================================================================

    private static function assertEquals(expected:Array, actual:Array, testName:String):Void {
        totalTests++;
        if (expected.length != actual.length) {
            trace("FAIL: " + testName + " - Length mismatch. Expected: " + expected.length + ", Actual: " + actual.length);
            failedTests++; return;
        }
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] !== actual[i]) {
                trace("FAIL: " + testName + " - Mismatch at [" + i + "]. Expected: " + expected[i] + ", Actual: " + actual[i]);
                failedTests++; return;
            }
        }
        trace("PASS: " + testName);
        passedTests++;
    }

    private static function assertTrue(condition:Boolean, testName:String, message:String):Void {
        totalTests++;
        if (!condition) {
            trace("FAIL: " + testName + " - " + message);
            failedTests++;
        } else {
            trace("PASS: " + testName + (message ? " - " + message : ""));
            passedTests++;
        }
    }

    private static function compareArrays(a:Array, b:Array):Boolean {
        if (a.length != b.length) return false;
        for (var i:Number = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false;
        }
        return true;
    }

    private static function isSortedArr(arr:Array):Boolean {
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i - 1] > arr[i]) return false;
        }
        return true;
    }

    // ===== 数据生成 =====

    private static function genRandom(n:Number):Array {
        var a:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) a[i] = rand() % (n * 2);
        return a;
    }

    private static function genOrganPipe(n:Number):Array {
        var a:Array = new Array(n);
        var half:Number = n >> 1;
        for (var i:Number = 0; i < half; i++) a[i] = i;
        for (var j:Number = half; j < n; j++) a[j] = n - 1 - j;
        return a;
    }

    private static function genSawTooth(n:Number, period:Number):Array {
        var a:Array = new Array(n);
        for (var i:Number = 0; i < n; i++) a[i] = i % period;
        return a;
    }

    private static function generateArray(size:Number, distribution:String):Array {
        var arr:Array = new Array(size);
        var i:Number;
        if (distribution === "random") {
            for (i = 0; i < size; i++) arr[i] = rand() % (size * 2);
        } else if (distribution === "sorted") {
            for (i = 0; i < size; i++) arr[i] = i;
        } else if (distribution === "reverse") {
            for (i = 0; i < size; i++) arr[i] = size - i;
        } else if (distribution === "duplicates") {
            for (i = 0; i < size; i++) arr[i] = rand() % 5;
        } else if (distribution === "organPipe") {
            return genOrganPipe(size);
        } else if (distribution === "fewUnique") {
            for (i = 0; i < size; i++) arr[i] = rand() % 10;
        } else {
            for (i = 0; i < size; i++) arr[i] = rand() % (size * 2);
        }
        return arr;
    }

    private static function padR(s:String, w:Number):String {
        while (length(s) < w) s += " ";
        return s;
    }

    private static function padL(s:String, w:Number):String {
        while (length(s) < w) s = " " + s;
        return s;
    }

    private static function printTestSummary():Void {
        trace("\n=================================================================");
        trace("TEST SUMMARY");
        trace("=================================================================");
        trace("Total: " + totalTests + "  Passed: " + passedTests + "  Failed: " + failedTests);
        trace("Success Rate: " + (Math.round(passedTests / totalTests * 10000) / 100) + "%");
        if (failedTests === 0) {
            trace("ALL TESTS PASSED!");
        } else {
            trace(failedTests + " test(s) FAILED. Review failures above.");
        }
        trace("=================================================================");
    }
}
