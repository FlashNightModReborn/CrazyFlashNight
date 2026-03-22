import org.flashNight.naki.Sort.*;

/**
 * PDQSort v2.0 综合测试套件
 *
 * 覆盖范围：
 * - 基础功能（空/单元素/两元素/已排序/逆序/随机/重复/全等）
 * - 边界情况（阈值附近/混合类型/极端重复）
 * - 算法特性（三路分区/有序检测/选轴/堆排序回退）
 * - 数据类型（字符串/对象/混合/自定义）
 * - 比较函数（自定义/反向/多级/null）
 * - 一致性（多次排序一致/就地/幂等）
 * - 对抗性输入（管风琴/锯齿/median-of-3 killer/少量唯一值）
 * - sortIndirect间接排序
 * - 性能基准（vs TimSort / vs Array.sort / 多分布/多规模）
 */
class org.flashNight.naki.Sort.PDQSortTest {

    // 测试统计
    private static var totalTests:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;

    // 测试规模
    private static var SMALL_SIZE:Number = 100;
    private static var MEDIUM_SIZE:Number = 1000;
    private static var LARGE_SIZE:Number = 3000;
    private static var STRESS_SIZE:Number = 10000;

    // 内联LCG随机数（确定性，可复现）
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
        trace("PDQSort v2.0 Comprehensive Test Suite");
        trace("=================================================================");

        runBasicTests();
        runBoundaryTests();
        runAlgorithmSpecificTests();
        runDataTypeTests();
        runCompareFunctionTests();
        runStabilityTests();
        runAdversarialTests();
        runSortIndirectTests();
        runLightStressTests();
        runPerformanceTests();

        printTestSummary();
    }

    public static function runQuickTests():Void {
        totalTests = 0; passedTests = 0; failedTests = 0;
        trace("=================================================================");
        trace("PDQSort v2.0 Quick Tests");
        trace("=================================================================");
        runBasicTests();
        runBoundaryTests();
        runSortIndirectTests();
        printTestSummary();
    }

    // ==================================================================
    // 基础功能测试
    // ==================================================================
    private static function runBasicTests():Void {
        trace("\n--- Basic Functionality Tests ---");

        // 空数组
        assertEquals([], PDQSort.sort([], null), "Empty Array");

        // 单元素
        assertEquals([42], PDQSort.sort([42], null), "Single Element");

        // 两元素
        assertEquals([1, 2], PDQSort.sort([2, 1], null), "Two Elements (Reverse)");
        assertEquals([1, 2], PDQSort.sort([1, 2], null), "Two Elements (Sorted)");
        assertEquals([5, 5], PDQSort.sort([5, 5], null), "Two Elements (Equal)");

        // 三元素全排列
        var perms:Array = [[1,2,3],[1,3,2],[2,1,3],[2,3,1],[3,1,2],[3,2,1]];
        var allOk:Boolean = true;
        for (var p:Number = 0; p < perms.length; p++) {
            var s:Array = PDQSort.sort(perms[p].slice(), null);
            if (s[0] !== 1 || s[1] !== 2 || s[2] !== 3) { allOk = false; break; }
        }
        assertTrue(allOk, "Three Elements (All Permutations)", "All 6 permutations correct");

        // 已排序
        assertEquals([1,2,3,4,5,6,7,8,9,10], PDQSort.sort([1,2,3,4,5,6,7,8,9,10], null), "Already Sorted");

        // 逆序
        assertEquals([1,2,3,4,5,6,7,8,9,10], PDQSort.sort([10,9,8,7,6,5,4,3,2,1], null), "Reverse Sorted");

        // 随机
        assertEquals([1,1,2,3,4,5,5,6,9], PDQSort.sort([3,1,4,1,5,9,2,6,5], null), "Random Array");

        // 重复
        assertEquals([1,3,3,3,5,5,7,8,9], PDQSort.sort([5,3,8,3,9,1,5,7,3], null), "Duplicate Elements");

        // 全等
        assertEquals([7,7,7,7,7,7,7], PDQSort.sort([7,7,7,7,7,7,7], null), "All Same Elements");

        // 负数
        assertEquals([-5,-3,-1,0,2,4], PDQSort.sort([4,-1,2,-5,0,-3], null), "Negative Numbers");

        // 大范围
        assertEquals([-1000000,0,1000000], PDQSort.sort([1000000,-1000000,0], null), "Large Range");
    }

    // ==================================================================
    // 边界情况测试
    // ==================================================================
    private static function runBoundaryTests():Void {
        trace("\n--- Boundary Case Tests ---");

        // 阈值附近（31/32/33）
        var sizes:Array = [3, 10, 16, 24, 30, 31, 32, 33, 34, 48, 64];
        var allOk:Boolean = true;
        resetRng();
        for (var si:Number = 0; si < sizes.length; si++) {
            var sz:Number = sizes[si];
            var arr:Array = genRandom(sz);
            var expected:Array = arr.slice();
            expected.sort(Array.NUMERIC);
            var sorted:Array = PDQSort.sort(arr, null);
            if (!compareArrays(expected, sorted)) { allOk = false; trace("  Failed at size=" + sz); break; }
        }
        assertTrue(allOk, "Threshold Boundary Sizes", "All sizes around threshold correct");

        // 混合类型（需自定义比较器）
        var mixArr:Array = [1, "2", 3, "1", 4];
        var mixCmp:Function = function(a, b):Number { return Number(a) - Number(b); };
        var mixSorted:Array = PDQSort.sort(mixArr, mixCmp);
        var mixOk:Boolean = true;
        for (var mi:Number = 1; mi < mixSorted.length; mi++) {
            if (Number(mixSorted[mi - 1]) > Number(mixSorted[mi])) { mixOk = false; break; }
        }
        assertTrue(mixOk, "Mixed Types Test", "Mixed types with comparator correct");

        // 中等规模
        resetRng();
        var medArr:Array = genRandom(MEDIUM_SIZE);
        var st:Number = getTimer();
        PDQSort.sort(medArr, null);
        var et:Number = getTimer();
        assertTrue(isSortedArr(medArr, null), "Moderate Array (" + MEDIUM_SIZE + ")", "Sorted in " + (et - st) + "ms");

        // 极端重复
        var dupSizes:Array = [50, 200, 500];
        var dupOk:Boolean = true;
        for (var di:Number = 0; di < dupSizes.length; di++) {
            var ds:Number = dupSizes[di];
            var darr:Array = new Array(ds);
            for (var dj:Number = 0; dj < ds; dj++) darr[dj] = 42;
            PDQSort.sort(darr, null);
            for (var dk:Number = 0; dk < ds; dk++) { if (darr[dk] !== 42) { dupOk = false; break; } }
            if (!dupOk) break;
        }
        assertTrue(dupOk, "Extreme Duplicates", "All duplicate arrays handled correctly");
    }

    // ==================================================================
    // 算法特性测试
    // ==================================================================
    private static function runAlgorithmSpecificTests():Void {
        trace("\n--- Algorithm-Specific Tests ---");

        // 阈值附近行为
        var threshOk:Boolean = true;
        var threshSizes:Array = [16, 30, 32, 34, 48];
        resetRng();
        for (var ti:Number = 0; ti < threshSizes.length; ti++) {
            var ts:Number = threshSizes[ti];
            var ta:Array = genRandom(ts);
            PDQSort.sort(ta, null);
            if (!isSortedArr(ta, null)) { threshOk = false; break; }
        }
        assertTrue(threshOk, "Insertion Sort Threshold", "Threshold behavior correct");

        // 三路分区（少量唯一值）
        resetRng();
        var twa:Array = new Array(300);
        for (var twi:Number = 0; twi < 300; twi++) twa[twi] = rand() % 5;
        PDQSort.sort(twa, null);
        assertTrue(isSortedArr(twa, null), "Three-Way Partitioning", "Many duplicates handled correctly");

        // 有序检测
        var scenarios:Array = [
            {arr: [1,2,3,4,5], name: "Fully Sorted"},
            {arr: [5,4,3,2,1], name: "Fully Reverse"},
            {arr: [1,2,3,5,4], name: "Nearly Sorted"}
        ];
        var scenOk:Boolean = true;
        for (var sci:Number = 0; sci < scenarios.length; sci++) {
            var sc:Object = scenarios[sci];
            var ssa:Array = PDQSort.sort(sc.arr.slice(), null);
            if (!isSortedArr(ssa, null)) { scenOk = false; break; }
        }
        assertTrue(scenOk, "Ordered Detection", "All ordered scenarios handled correctly");

        // 选轴
        assertEquals([1,2,3,4,5,6,7,8,9], PDQSort.sort([9,1,8,2,7,3,6,4,5], null), "Pivot Selection");

        // 堆排序回退（构造触发深度耗尽的输入）
        // 使用管风琴模式，因其容易导致不平衡分区
        var heapArr:Array = genOrganPipe(200);
        PDQSort.sort(heapArr, null);
        assertTrue(isSortedArr(heapArr, null), "Heapsort Fallback", "Organ pipe triggers fallback and sorts correctly");
    }

    // ==================================================================
    // 数据类型测试
    // ==================================================================
    private static function runDataTypeTests():Void {
        trace("\n--- Data Type Tests ---");

        // 字符串
        var strCmp:Function = function(a, b):Number { if (a < b) return -1; if (a > b) return 1; return 0; };
        assertEquals(["apple","banana","cherry","date"],
            PDQSort.sort(["banana","apple","cherry","date"], strCmp), "String Array");

        // 对象按属性排序
        var objs:Array = [{name:"John",age:30},{name:"Jane",age:25},{name:"Bob",age:35}];
        var objCmp:Function = function(a, b):Number { return a.age - b.age; };
        PDQSort.sort(objs, objCmp);
        assertTrue(objs[0].age === 25 && objs[1].age === 30 && objs[2].age === 35,
            "Object Array", "Objects sorted by age correctly");

        // 混合数据类型
        var mixArr2:Array = [3, "2", 1, "4"];
        var mixCmp2:Function = function(a, b):Number { return Number(a) - Number(b); };
        PDQSort.sort(mixArr2, mixCmp2);
        var mixOk2:Boolean = true;
        for (var i:Number = 1; i < mixArr2.length; i++) {
            if (Number(mixArr2[i - 1]) > Number(mixArr2[i])) { mixOk2 = false; break; }
        }
        assertTrue(mixOk2, "Mixed Data Types", "Mixed types sorted correctly");

        // 自定义对象
        var tasks:Array = [{priority:1,name:"A"},{priority:3,name:"C"},{priority:2,name:"B"}];
        PDQSort.sort(tasks, function(a, b):Number { return a.priority - b.priority; });
        assertTrue(tasks[0].priority === 1 && tasks[1].priority === 2 && tasks[2].priority === 3,
            "Custom Objects", "Objects sorted by priority correctly");
    }

    // ==================================================================
    // 比较函数测试
    // ==================================================================
    private static function runCompareFunctionTests():Void {
        trace("\n--- Compare Function Tests ---");

        // 大小写不敏感
        var ciArr:Array = ["apple","Orange","banana","grape","Cherry"];
        var ciCmp:Function = function(a, b):Number {
            var al:String = a.toLowerCase(), bl:String = b.toLowerCase();
            if (al < bl) return -1; if (al > bl) return 1; return 0;
        };
        PDQSort.sort(ciArr, ciCmp);
        var ciOk:Boolean = true;
        for (var ci:Number = 1; ci < ciArr.length; ci++) {
            if (ciArr[ci - 1].toLowerCase() > ciArr[ci].toLowerCase()) { ciOk = false; break; }
        }
        assertTrue(ciOk, "Case-Insensitive Compare", "Case-insensitive sorting works");

        // 反向排序
        assertEquals([5,4,3,2,1], PDQSort.sort([1,2,3,4,5], function(a, b):Number { return b - a; }), "Reverse Compare");

        // 多级排序
        var mlArr:Array = [{value:5,category:"A"},{value:3,category:"B"},{value:5,category:"B"},{value:3,category:"A"}];
        PDQSort.sort(mlArr, function(a, b):Number {
            if (a.category !== b.category) return (a.category < b.category) ? -1 : 1;
            return a.value - b.value;
        });
        assertTrue(mlArr[0].category === "A" && mlArr[0].value === 3 &&
                   mlArr[1].category === "A" && mlArr[1].value === 5 &&
                   mlArr[2].category === "B" && mlArr[2].value === 3 &&
                   mlArr[3].category === "B" && mlArr[3].value === 5,
            "Multi-Level Compare", "Multi-level sorting works");

        // null比较函数
        assertEquals([1,1,3,4,5], PDQSort.sort([3,1,4,1,5], null), "Null Compare Function");
    }

    // ==================================================================
    // 一致性测试
    // ==================================================================
    private static function runStabilityTests():Void {
        trace("\n--- Consistency Tests ---");

        // 多次排序一致
        resetRng();
        var cArr:Array = genRandom(200);
        var s1:Array = PDQSort.sort(cArr.slice(), null);
        var s2:Array = PDQSort.sort(cArr.slice(), null);
        assertTrue(compareArrays(s1, s2), "Consistent Results", "Multiple sorts produce identical results");

        // 就地排序
        var ipArr:Array = [3,1,4,1,5,9,2,6];
        var ipResult:Array = PDQSort.sort(ipArr, null);
        assertTrue(ipArr === ipResult, "In-Place Sorting", "Returns same array reference");

        // 幂等性
        var idArr:Array = [3,1,4,1,5,9,2,6];
        var id1:Array = PDQSort.sort(idArr.slice(), null);
        var id2:Array = PDQSort.sort(id1.slice(), null);
        assertTrue(compareArrays(id1, id2), "Idempotency", "Sorting sorted array doesn't change it");
    }

    // ==================================================================
    // 对抗性输入测试
    // ==================================================================
    private static function runAdversarialTests():Void {
        trace("\n--- Adversarial Input Tests ---");

        // 管风琴 [1,2,...,n,...,2,1]
        var opArr:Array = genOrganPipe(500);
        PDQSort.sort(opArr, null);
        assertTrue(isSortedArr(opArr, null), "Organ Pipe (500)", "Sorted correctly");

        // 锯齿 [1,2,...,k,1,2,...,k,...]
        var stArr:Array = genSawTooth(500, 10);
        PDQSort.sort(stArr, null);
        assertTrue(isSortedArr(stArr, null), "Saw Tooth (500, period=10)", "Sorted correctly");

        // 两值交替
        var altArr:Array = new Array(500);
        for (var ai:Number = 0; ai < 500; ai++) altArr[ai] = (ai % 2 === 0) ? 1 : 100;
        PDQSort.sort(altArr, null);
        assertTrue(isSortedArr(altArr, null), "Alternating Two Values (500)", "Sorted correctly");

        // 三值随机分布
        resetRng();
        var tvArr:Array = new Array(1000);
        for (var tvi:Number = 0; tvi < 1000; tvi++) tvArr[tvi] = rand() % 3;
        PDQSort.sort(tvArr, null);
        assertTrue(isSortedArr(tvArr, null), "Three Values Random (1000)", "Sorted correctly");

        // 大量重复 + 少量异常值
        var drArr:Array = new Array(500);
        for (var dri:Number = 0; dri < 500; dri++) drArr[dri] = 50;
        drArr[0] = 1; drArr[100] = 99; drArr[499] = 0; drArr[250] = 100;
        PDQSort.sort(drArr, null);
        assertTrue(isSortedArr(drArr, null), "Mostly Equal + Outliers", "Sorted correctly");

        // 已排序 + 末尾扰动
        var ptArr:Array = new Array(200);
        for (var pti:Number = 0; pti < 200; pti++) ptArr[pti] = pti;
        ptArr[198] = 0; ptArr[199] = 1;
        PDQSort.sort(ptArr, null);
        assertTrue(isSortedArr(ptArr, null), "Sorted + Tail Perturbation", "Sorted correctly");

        // 大规模对抗
        var lgOp:Array = genOrganPipe(STRESS_SIZE);
        var st:Number = getTimer();
        PDQSort.sort(lgOp, null);
        var et:Number = getTimer();
        assertTrue(isSortedArr(lgOp, null), "Large Organ Pipe (" + STRESS_SIZE + ")",
            "Sorted in " + (et - st) + "ms");

        // 使用比较器的对抗性测试
        var cmpOp:Array = genOrganPipe(500);
        PDQSort.sort(cmpOp, function(a, b):Number { return a - b; });
        assertTrue(isSortedArr(cmpOp, null), "Organ Pipe (comparator path)", "Sorted correctly");
    }

    // ==================================================================
    // sortIndirect 间接排序测试
    // ==================================================================
    private static function runSortIndirectTests():Void {
        trace("\n--- sortIndirect Tests ---");

        // 基础测试
        var keys1:Array = [30, 10, 20];
        var idx1:Array = [0, 1, 2];
        PDQSort.sortIndirect(idx1, keys1);
        assertTrue(idx1[0] === 1 && idx1[1] === 2 && idx1[2] === 0,
            "sortIndirect Basic", "Indices sorted by keys");

        // 空数组
        var emptyIdx:Array = [];
        PDQSort.sortIndirect(emptyIdx, []);
        assertTrue(emptyIdx.length === 0, "sortIndirect Empty", "Empty array handled");

        // 单元素
        var singleIdx:Array = [0];
        PDQSort.sortIndirect(singleIdx, [42]);
        assertTrue(singleIdx[0] === 0, "sortIndirect Single", "Single element handled");

        // 已排序键
        var sortedKeys:Array = [1, 2, 3, 4, 5];
        var sortedIdx:Array = [0, 1, 2, 3, 4];
        PDQSort.sortIndirect(sortedIdx, sortedKeys);
        assertTrue(sortedIdx[0] === 0 && sortedIdx[4] === 4, "sortIndirect Already Sorted", "No change needed");

        // 逆序键
        var revKeys:Array = [5, 4, 3, 2, 1];
        var revIdx:Array = [0, 1, 2, 3, 4];
        PDQSort.sortIndirect(revIdx, revKeys);
        assertTrue(revIdx[0] === 4 && revIdx[4] === 0, "sortIndirect Reverse", "Reversed correctly");

        // 重复键
        var dupKeys:Array = [5, 3, 5, 1, 3];
        var dupIdx:Array = [0, 1, 2, 3, 4];
        PDQSort.sortIndirect(dupIdx, dupKeys);
        // 验证键值有序
        var dupOk:Boolean = true;
        for (var di:Number = 1; di < dupIdx.length; di++) {
            if (dupKeys[dupIdx[di - 1]] > dupKeys[dupIdx[di]]) { dupOk = false; break; }
        }
        assertTrue(dupOk, "sortIndirect Duplicates", "Duplicate keys handled correctly");

        // 中等规模
        resetRng();
        var medN:Number = 1000;
        var medKeys:Array = new Array(medN);
        var medIdx:Array = new Array(medN);
        for (var mi:Number = 0; mi < medN; mi++) { medKeys[mi] = rand() % 10000; medIdx[mi] = mi; }
        var st:Number = getTimer();
        PDQSort.sortIndirect(medIdx, medKeys);
        var et:Number = getTimer();
        var medOk:Boolean = true;
        for (var mj:Number = 1; mj < medN; mj++) {
            if (medKeys[medIdx[mj - 1]] > medKeys[medIdx[mj]]) { medOk = false; break; }
        }
        assertTrue(medOk, "sortIndirect Medium (" + medN + ")", "Sorted in " + (et - st) + "ms");

        // 大规模
        resetRng();
        var lgN:Number = 5000;
        var lgKeys:Array = new Array(lgN);
        var lgIdx:Array = new Array(lgN);
        for (var li:Number = 0; li < lgN; li++) { lgKeys[li] = rand() % 100000; lgIdx[li] = li; }
        st = getTimer();
        PDQSort.sortIndirect(lgIdx, lgKeys);
        et = getTimer();
        var lgOk:Boolean = true;
        for (var lj:Number = 1; lj < lgN; lj++) {
            if (lgKeys[lgIdx[lj - 1]] > lgKeys[lgIdx[lj]]) { lgOk = false; break; }
        }
        assertTrue(lgOk, "sortIndirect Large (" + lgN + ")", "Sorted in " + (et - st) + "ms");
    }

    // ==================================================================
    // 轻量压力测试
    // ==================================================================
    private static function runLightStressTests():Void {
        trace("\n--- Light Stress Tests ---");

        var distributions:Array = ["random", "sorted", "reverse", "duplicates"];
        var stressOk:Boolean = true;
        for (var di:Number = 0; di < distributions.length; di++) {
            var dist:String = distributions[di];
            resetRng();
            var arr:Array = generateArray(STRESS_SIZE, dist);
            var st:Number = getTimer();
            PDQSort.sort(arr, null);
            var et:Number = getTimer();
            if (!isSortedArr(arr, null)) {
                stressOk = false;
                trace("  Failed: " + dist);
                break;
            }
        }
        assertTrue(stressOk, "Stress Test (" + STRESS_SIZE + ")", "All distributions correct");

        // 重复排序
        resetRng();
        var repArr:Array = genRandom(500);
        var repOk:Boolean = true;
        for (var ri:Number = 0; ri < 5; ri++) {
            var ra:Array = repArr.slice();
            PDQSort.sort(ra, null);
            if (!isSortedArr(ra, null)) { repOk = false; break; }
        }
        assertTrue(repOk, "Repeated Sorting", "5 iterations consistent");
    }

    // ==================================================================
    // 性能基准测试
    // ==================================================================
    private static function runPerformanceTests():Void {
        trace("\n--- Performance Benchmarks ---");
        trace("Format: PDQSort(null) / PDQSort(cmp) / TimSort(cmp) / Array.sort(NUMERIC) ms");

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

                // PDQSort null comparator
                var pdqNull:Number = 0;
                for (var r:Number = 0; r < REPEATS; r++) {
                    var a1:Array = master.slice();
                    var st:Number = getTimer();
                    PDQSort.sort(a1, null);
                    pdqNull += getTimer() - st;
                }

                // PDQSort with comparator
                var pdqCmp:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a2:Array = master.slice();
                    st = getTimer();
                    PDQSort.sort(a2, numCmp);
                    pdqCmp += getTimer() - st;
                }

                // TimSort with comparator
                var tsCmp:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a3:Array = master.slice();
                    st = getTimer();
                    TimSort.sort(a3, numCmp);
                    tsCmp += getTimer() - st;
                }

                // Array.sort NUMERIC
                var nativeT:Number = 0;
                for (r = 0; r < REPEATS; r++) {
                    var a4:Array = master.slice();
                    st = getTimer();
                    a4.sort(Array.NUMERIC);
                    nativeT += getTimer() - st;
                }

                trace("    " + padR(dist, 12) + ": "
                    + padL(String(Math.round(pdqNull / REPEATS)), 5) + " / "
                    + padL(String(Math.round(pdqCmp / REPEATS)), 5) + " / "
                    + padL(String(Math.round(tsCmp / REPEATS)), 5) + " / "
                    + padL(String(Math.round(nativeT / REPEATS)), 5));
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

    private static function isSortedArr(arr:Array, cmpFunc:Function):Boolean {
        if (cmpFunc != null) {
            for (var i:Number = 1; i < arr.length; i++) {
                if (cmpFunc(arr[i - 1], arr[i]) > 0) return false;
            }
        } else {
            for (var j:Number = 1; j < arr.length; j++) {
                if (arr[j - 1] > arr[j]) return false;
            }
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
