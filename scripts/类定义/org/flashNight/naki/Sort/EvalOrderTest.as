/**
 * EvalOrderTest - AVM1 表达式求值顺序实证测试
 *
 * 核心问题：AS2(AVM1) 中 arr[exprL] = arr[exprR] 的求值顺序是什么？
 *   假设A (LHS-first)：先求 exprL（含副作用），再求 exprR
 *   假设B (RHS-first)：先求 exprR，再求 exprL
 *
 * 结论决定了以下两种合并变换是否安全：
 *   Pattern A: arr[j+1] = arr[j]; j--  →  arr[j+1] = arr[j--]
 *   Pattern B: arr[j] = arr[j-1]; j--  →  arr[j] = arr[--j]
 *
 * 用法: org.flashNight.naki.Sort.EvalOrderTest.runTests();
 */
class org.flashNight.naki.Sort.EvalOrderTest {

    private static var _passed:Number;
    private static var _failed:Number;

    // ── 工具函数 ──────────────────────────────────────

    private static function arrEq(a:Array, b:Array):Boolean {
        if (a.length != b.length) return false;
        for (var i:Number = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false;
        }
        return true;
    }

    private static function s(a:Array):String {
        return "[" + a.join(",") + "]";
    }

    private static function ok(name:String, cond:Boolean, detail:String):Void {
        if (cond) {
            trace("  PASS: " + name);
            _passed++;
        } else {
            trace("  FAIL: " + name);
            if (detail != undefined) trace("        " + detail);
            _failed++;
        }
    }

    // ── 主测试 ────────────────────────────────────────

    public static function runTests():Void {
        trace("=== AVM1 Evaluation Order Tests ===");
        trace("Hypothesis: LHS array index is evaluated BEFORE RHS value");
        _passed = 0;
        _failed = 0;

        testGroup1_PatternA();
        testGroup2_PatternB();
        testGroup3_CrossVariable();
        testGroup4_Discriminators();
        testGroup5_WhileLoops();
        testGroup6_InsertionSort();
        testGroup7_Exhaustive();
        testGroup8_EdgeCases();
        testGroup9_ArrayShift();

        trace("");
        trace("=== Summary: " + _passed + " passed, " + _failed + " failed ===");
        if (_failed == 0) {
            trace("All tests passed! Safe transformations:");
            trace("  Pattern A: arr[j+1]=arr[j]; j--  -->  arr[j+1]=arr[j--]");
            trace("  Pattern B: arr[j]=arr[j-1]; j--  -->  arr[j]=arr[--j]");
        } else {
            trace("SOME TESTS FAILED - do NOT apply until resolved!");
        }
    }

    // ── Group 1: Pattern A 单次操作 ──────────────────

    private static function testGroup1_PatternA():Void {
        trace("");
        trace("--- Group 1: Pattern A (arr[j+1]=arr[j]; j-- → arr[j+1]=arr[j--]) ---");
        var a:Array, j:Number;

        // T1.1: 基准 - 原始两条语句
        a = [10, 20, 30, 40, 50]; j = 2;
        a[j + 1] = a[j]; j--;
        ok("T1.1 baseline: a[j+1]=a[j]; j--",
            arrEq(a, [10, 20, 30, 30, 50]) && j == 1,
            "a=" + s(a) + " j=" + j);

        // T1.2: 安全候选 - 副作用仅在RHS
        a = [10, 20, 30, 40, 50]; j = 2;
        a[j + 1] = a[j--];
        ok("T1.2 SAFE: a[j+1]=a[j--]",
            arrEq(a, [10, 20, 30, 30, 50]) && j == 1,
            "a=" + s(a) + " j=" + j);

        // T1.3: 危险 - 副作用在LHS (j--+1)
        // LHS-first: j--→2, +1→3, j=1; RHS a[1]=20 → a[3]=20
        // RHS-first: a[2]=30; j--→2, +1→3 → a[3]=30
        a = [10, 20, 30, 40, 50]; j = 2;
        a[j-- + 1] = a[j];
        // 不做正确性断言,只记录实际行为
        trace("  INFO: T1.3 a[j--+1]=a[j] → a=" + s(a) + " j=" + j
            + (arrEq(a, [10, 20, 30, 20, 50]) ? " [LHS-first]" : " [RHS-first]"));
    }

    // ── Group 2: Pattern B 单次操作 ──────────────────

    private static function testGroup2_PatternB():Void {
        trace("");
        trace("--- Group 2: Pattern B (arr[j]=arr[j-1]; j-- → arr[j]=arr[--j]) ---");
        var a:Array, j:Number;

        // T2.1: 基准 - 原始两条语句
        a = [10, 20, 30, 40, 50]; j = 3;
        a[j] = a[j - 1]; j--;
        ok("T2.1 baseline: a[j]=a[j-1]; j--",
            arrEq(a, [10, 20, 30, 30, 50]) && j == 2,
            "a=" + s(a) + " j=" + j);

        // T2.2: 安全候选 - 副作用仅在RHS (--j)
        // LHS-first: LHS=a[3]; --j→2; RHS=a[2]=30 → a[3]=30, j=2
        // RHS-first: --j→2; a[2]=30; LHS=a[2]; a[2]=30 (no visible change!)
        a = [10, 20, 30, 40, 50]; j = 3;
        a[j] = a[--j];
        ok("T2.2 SAFE: a[j]=a[--j]",
            arrEq(a, [10, 20, 30, 30, 50]) && j == 2,
            "a=" + s(a) + " j=" + j);

        // T2.3: 备选 - 副作用在LHS (j--)
        // LHS-first: j--→3, j=2; RHS a[j]=a[2]=30 → a[3]=30, j=2
        // RHS-first: a[j]=a[3]=40; j--→3 → a[3]=40 (无变化!)
        a = [10, 20, 30, 40, 50]; j = 3;
        a[j--] = a[j];
        ok("T2.3 ALT: a[j--]=a[j] (also valid if LHS-first)",
            arrEq(a, [10, 20, 30, 30, 50]) && j == 2,
            "a=" + s(a) + " j=" + j);

        // T2.4: 危险 - 双重副作用 (j--在LHS, j-1在RHS)
        // LHS-first: j--→3, j=2; RHS a[j-1]=a[1]=20 → a[3]=20
        // RHS-first: a[j-1]=a[2]=30; j--→3 → a[3]=30
        a = [10, 20, 30, 40, 50]; j = 3;
        a[j--] = a[j - 1];
        trace("  INFO: T2.4 a[j--]=a[j-1] → a=" + s(a) + " j=" + j
            + (arrEq(a, [10, 20, 30, 20, 50]) ? " [LHS-first]" : " [RHS-first]"));
    }

    // ── Group 3: 交叉变量 (已用于batch copy的模式) ───

    private static function testGroup3_CrossVariable():Void {
        trace("");
        trace("--- Group 3: Cross-variable (a[d++]=b[p++], a[d--]=b[p--]) ---");
        var dst:Array, src:Array, d:Number, p:Number;

        // T3.1: a[d++] = b[p++] (两个不同变量)
        dst = [0, 0, 0, 0, 0]; src = [100, 200, 300, 400, 500];
        d = 1; p = 2;
        dst[d++] = src[p++];
        ok("T3.1 a[d++]=b[p++]",
            arrEq(dst, [0, 300, 0, 0, 0]) && d == 2 && p == 3,
            "dst=" + s(dst) + " d=" + d + " p=" + p);

        // T3.2: a[d--] = b[p--] (反向，两个不同变量)
        dst = [0, 0, 0, 0, 0]; src = [100, 200, 300, 400, 500];
        d = 3; p = 4;
        dst[d--] = src[p--];
        ok("T3.2 a[d--]=b[p--]",
            arrEq(dst, [0, 0, 0, 500, 0]) && d == 2 && p == 3,
            "dst=" + s(dst) + " d=" + d + " p=" + p);

        // T3.3: 同一数组 a[d++] = a[p++] (d≠p, 不会冲突)
        var c:Array = [10, 20, 30, 40, 50];
        d = 0; p = 2;
        c[d++] = c[p++];
        ok("T3.3 same arr a[d++]=a[p++]",
            arrEq(c, [30, 20, 30, 40, 50]) && d == 1 && p == 3,
            "a=" + s(c) + " d=" + d + " p=" + p);

        // T3.4: 4展开batch copy验证
        dst = [0, 0, 0, 0, 0, 0, 0, 0];
        src = [10, 20, 30, 40, 50, 60, 70, 80];
        d = 0; p = 0;
        dst[d++] = src[p++]; dst[d++] = src[p++];
        dst[d++] = src[p++]; dst[d++] = src[p++];
        ok("T3.4 batch x4 copy",
            arrEq(dst, [10, 20, 30, 40, 0, 0, 0, 0]) && d == 4 && p == 4,
            "dst=" + s(dst) + " d=" + d + " p=" + p);

        // T3.5: 反向4展开batch copy验证
        dst = [0, 0, 0, 0, 0, 0, 0, 0];
        src = [10, 20, 30, 40, 50, 60, 70, 80];
        d = 7; p = 7;
        dst[d--] = src[p--]; dst[d--] = src[p--];
        dst[d--] = src[p--]; dst[d--] = src[p--];
        ok("T3.5 batch x4 reverse copy",
            arrEq(dst, [0, 0, 0, 0, 50, 60, 70, 80]) && d == 3 && p == 3,
            "dst=" + s(dst) + " d=" + d + " p=" + p);
    }

    // ── Group 4: 精确鉴别器 (区分LHS-first vs RHS-first) ──

    private static function testGroup4_Discriminators():Void {
        trace("");
        trace("--- Group 4: LHS-first vs RHS-first discriminators ---");
        var a:Array, i:Number;

        // T4.1: a[i++] = a[i] — 最纯粹的鉴别器
        // LHS-first: i++→1写入a[1], i=2; RHS a[2]=30 → a[1]=30
        // RHS-first: a[i]=a[1]=20; i++→1; a[1]=20 (无变化)
        a = [10, 20, 30, 40, 50]; i = 1;
        a[i++] = a[i];
        var lhsFirst4_1:Boolean = (a[1] == 30);
        ok("T4.1 a[i++]=a[i] → a[1]=" + a[1] + " i=" + i
            + (lhsFirst4_1 ? " [LHS-first confirmed]" : " [RHS-first confirmed]"),
            true, ""); // 不断言对错,只记录行为

        // T4.2: a[i] = a[i++] — 副作用在RHS
        // LHS-first: LHS index=1; RHS i++→1→a[1]=20, i=2 → a[1]=20 (无变化)
        // RHS-first: i++→1→a[1]=20, i=2; LHS a[2] → a[2]=20
        a = [10, 20, 30, 40, 50]; i = 1;
        a[i] = a[i++];
        var lhsFirst4_2:Boolean = (a[1] == 20 && a[2] == 30);
        trace("  INFO: T4.2 a[i]=a[i++] → a=" + s(a) + " i=" + i
            + (lhsFirst4_2 ? " [LHS-first]" : " [RHS-first]"));

        // T4.3: a[--i] = a[i] — pre-decrement在LHS
        // LHS-first: --i→i=2, index=2; RHS a[2] = 现在的a[2]
        //   但a[2]可能已被改写？不，这里RHS读的是a[i]而i已变
        //   → a[2] = a[2] = 30 (无可见变化)
        // RHS-first: a[i]=a[3]=40; --i→2; a[2]=40
        a = [10, 20, 30, 40, 50]; i = 3;
        a[--i] = a[i];
        trace("  INFO: T4.3 a[--i]=a[i] → a=" + s(a) + " i=" + i
            + (a[2] == 30 ? " [LHS-first: a[2] unchanged]" : " [RHS-first: a[2]=" + a[2] + "]"));

        // T4.4: 双变量交叉鉴别 a[i++] = a[--i]
        // LHS-first: i++→1 index=1, i=2; --i→1; a[1]=a[1] (noop)
        // RHS-first: --i→0; a[0]=10; i++→0 index=0; a[0]=10 (noop)
        // 这个不好鉴别。换一个。

        // T4.4 (revised): 交错自增
        // a[i] = ++i — 赋值右边是数值不是数组元素
        a = [10, 20, 30, 40, 50]; i = 1;
        a[i] = ++i;
        // LHS-first: index=1; ++i→2; a[1]=2
        // RHS-first: ++i→2; index=2; a[2]=2
        trace("  INFO: T4.4 a[i]=++i → a=" + s(a) + " i=" + i
            + (a[1] == 2 ? " [LHS-first: a[1]=2]" : " [a[2]=" + a[2] + "]"));
    }

    // ── Group 5: While循环完整测试 ──────────────────

    private static function testGroup5_WhileLoops():Void {
        trace("");
        trace("--- Group 5: Full while-loop pattern tests ---");
        var orig:Array, merged:Array;
        var jo:Number, jm:Number;
        var keyV:Number;

        // T5.1: Pattern A in while loop — 向下搬移
        // while (j >= 0 && a[j] > key) { a[j+1]=a[j]; j--; }
        // → while (j >= 0 && a[j] > key) { a[j+1]=a[j--]; }
        orig = [10, 30, 50, 70, 25]; merged = [10, 30, 50, 70, 25];
        keyV = 25;

        jo = 3;
        while (jo >= 0 && orig[jo] > keyV) { orig[jo + 1] = orig[jo]; jo--; }
        orig[jo + 1] = keyV;

        jm = 3;
        while (jm >= 0 && merged[jm] > keyV) { merged[jm + 1] = merged[jm--]; }
        merged[jm + 1] = keyV;

        ok("T5.1 Pattern A loop: shift-down insert 25 into [10,30,50,70]",
            arrEq(orig, merged) && jo == jm,
            "orig=" + s(orig) + " merged=" + s(merged) + " jo=" + jo + " jm=" + jm);

        // T5.2: Pattern A — 全部搬移（key最小）
        orig = [20, 40, 60, 80, 5]; merged = [20, 40, 60, 80, 5];
        keyV = 5;
        jo = 3;
        while (jo >= 0 && orig[jo] > keyV) { orig[jo + 1] = orig[jo]; jo--; }
        orig[jo + 1] = keyV;
        jm = 3;
        while (jm >= 0 && merged[jm] > keyV) { merged[jm + 1] = merged[jm--]; }
        merged[jm + 1] = keyV;
        ok("T5.2 Pattern A loop: key=5 shifts entire array",
            arrEq(orig, merged) && jo == jm,
            "orig=" + s(orig) + " merged=" + s(merged));

        // T5.3: Pattern A — 无搬移（key已有序）
        orig = [10, 20, 30, 40, 50]; merged = [10, 20, 30, 40, 50];
        keyV = 50;
        jo = 3;
        while (jo >= 0 && orig[jo] > keyV) { orig[jo + 1] = orig[jo]; jo--; }
        orig[jo + 1] = keyV;
        jm = 3;
        while (jm >= 0 && merged[jm] > keyV) { merged[jm + 1] = merged[jm--]; }
        merged[jm + 1] = keyV;
        ok("T5.3 Pattern A loop: already sorted, no shift",
            arrEq(orig, merged) && jo == jm,
            "orig=" + s(orig) + " merged=" + s(merged));

        // T5.4: Pattern B in while loop — 二分插入的块搬移
        // j = i; while (j > left) { a[j]=a[j-1]; j--; }
        // → j = i; while (j > left) { a[j]=a[--j]; }
        orig = [10, 20, 60, 70, 80]; merged = [10, 20, 60, 70, 80];
        var insertAt:Number = 2;

        jo = 4;
        while (jo > insertAt) { orig[jo] = orig[jo - 1]; jo--; }
        orig[insertAt] = 25;

        jm = 4;
        while (jm > insertAt) { merged[jm] = merged[--jm]; }
        merged[insertAt] = 25;

        ok("T5.4 Pattern B loop: shift block [60,70,80] right, insert 25 at pos 2",
            arrEq(orig, merged) && jo == jm,
            "orig=" + s(orig) + " merged=" + s(merged) + " jo=" + jo + " jm=" + jm);

        // T5.5: Pattern B — 搬移单个元素
        orig = [10, 20, 30]; merged = [10, 20, 30];
        insertAt = 1;
        jo = 2;
        while (jo > insertAt) { orig[jo] = orig[jo - 1]; jo--; }
        orig[insertAt] = 5;
        jm = 2;
        while (jm > insertAt) { merged[jm] = merged[--jm]; }
        merged[insertAt] = 5;
        ok("T5.5 Pattern B loop: shift single element",
            arrEq(orig, merged) && jo == jm,
            "orig=" + s(orig) + " merged=" + s(merged));

        // T5.6: Pattern B — 搬移到最右
        orig = [50, 10, 20, 30, 40]; merged = [50, 10, 20, 30, 40];
        insertAt = 0;
        jo = 4;
        while (jo > insertAt) { orig[jo] = orig[jo - 1]; jo--; }
        orig[insertAt] = 1;
        jm = 4;
        while (jm > insertAt) { merged[jm] = merged[--jm]; }
        merged[insertAt] = 1;
        ok("T5.6 Pattern B loop: shift entire array right",
            arrEq(orig, merged) && jo == jm,
            "orig=" + s(orig) + " merged=" + s(merged));
    }

    // ── Group 6: 完整插入排序等价性 ────────────────

    private static function testGroup6_InsertionSort():Void {
        trace("");
        trace("--- Group 6: Full insertion sort equivalence ---");

        var cases:Array = [
            [5, 3, 1, 4, 2],
            [1],
            [2, 1],
            [3, 2, 1],
            [1, 2, 3, 4, 5],
            [5, 4, 3, 2, 1],
            [3, 1, 4, 1, 5, 9, 2, 6],
            [10, 10, 10, 10],
            [1, 3, 2, 3, 1, 2, 3, 1],
            // 大数组：i>4 触发二分插入路径
            [20, 15, 10, 5, 25, 30, 3, 8, 12, 22, 18, 7, 1, 28, 14],
            // 全相同
            [7, 7, 7, 7, 7, 7, 7],
            // 大量逆序
            [16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1],
            // 部分有序（前半段有序，后半段随机）
            [1, 2, 3, 4, 5, 6, 7, 8, 3, 1, 7, 2, 5, 4, 6, 8],
            // 负数
            [-5, 3, -1, 0, 2, -3, 4, -2, 1]
        ];

        for (var t:Number = 0; t < cases.length; t++) {
            var origArr:Array = cases[t].slice(0);
            var mergedArr:Array = cases[t].slice(0);
            sortOriginal(origArr);
            sortMerged(mergedArr);
            ok("T6." + (t + 1) + " sort n=" + cases[t].length,
                arrEq(origArr, mergedArr),
                "input=" + s(cases[t]) + " orig=" + s(origArr) + " merged=" + s(mergedArr));
        }
    }

    // ── Group 7: 穷举全排列 [1..5] ────────────────

    private static function testGroup7_Exhaustive():Void {
        trace("");
        trace("--- Group 7: Exhaustive [1..5] permutations (120 total) ---");

        var perm:Array = [1, 2, 3, 4, 5];
        var n:Number = perm.length;
        var c:Array = [0, 0, 0, 0, 0];
        var permCount:Number = 0;
        var permFail:Number = 0;

        // 测试初始排列
        var o:Array = perm.slice(0);
        var m:Array = perm.slice(0);
        sortOriginal(o);
        sortMerged(m);
        if (!arrEq(o, m)) permFail++;
        permCount++;

        // Heap's algorithm 生成全排列
        var i:Number = 0;
        var swp:Number;
        while (i < n) {
            if (c[i] < i) {
                if (i % 2 == 0) { swp = perm[0]; perm[0] = perm[i]; perm[i] = swp; }
                else { swp = perm[c[i]]; perm[c[i]] = perm[i]; perm[i] = swp; }
                o = perm.slice(0);
                m = perm.slice(0);
                sortOriginal(o);
                sortMerged(m);
                if (!arrEq(o, m)) permFail++;
                permCount++;
                c[i]++;
                i = 0;
            } else {
                c[i] = 0;
                i++;
            }
        }

        ok("T7.1 All " + permCount + " permutations of [1..5]",
            permFail == 0,
            permFail + " mismatches");

        // 也穷举 [1..6]（720排列，覆盖i>4的二分路径）
        perm = [1, 2, 3, 4, 5, 6];
        n = perm.length;
        c = [0, 0, 0, 0, 0, 0];
        permCount = 0; permFail = 0;

        o = perm.slice(0); m = perm.slice(0);
        sortOriginal(o); sortMerged(m);
        if (!arrEq(o, m)) permFail++;
        permCount++;

        i = 0;
        while (i < n) {
            if (c[i] < i) {
                if (i % 2 == 0) { swp = perm[0]; perm[0] = perm[i]; perm[i] = swp; }
                else { swp = perm[c[i]]; perm[c[i]] = perm[i]; perm[i] = swp; }
                o = perm.slice(0); m = perm.slice(0);
                sortOriginal(o); sortMerged(m);
                if (!arrEq(o, m)) permFail++;
                permCount++;
                c[i]++;
                i = 0;
            } else {
                c[i] = 0;
                i++;
            }
        }

        ok("T7.2 All " + permCount + " permutations of [1..6] (covers binary insertion path)",
            permFail == 0,
            permFail + " mismatches");
    }

    // ── Group 8: 边界/极端情况 ─────────────────────

    private static function testGroup8_EdgeCases():Void {
        trace("");
        trace("--- Group 8: Edge cases ---");
        var a:Array, j:Number;

        // T8.1: j=0 边界 Pattern A
        a = [50, 10]; j = 0;
        a[j + 1] = a[j--];
        ok("T8.1 j=0: a[j+1]=a[j--]",
            arrEq(a, [50, 50]) && j == -1,
            "a=" + s(a) + " j=" + j);

        // T8.2: 连续3次 Pattern A（模拟完整搬移链）
        a = [10, 20, 30, 40, 50]; j = 3;
        a[j + 1] = a[j--]; // a[4]=a[3]=40, j=2
        a[j + 1] = a[j--]; // a[3]=a[2]=30, j=1
        a[j + 1] = a[j--]; // a[2]=a[1]=20, j=0
        ok("T8.2 chained 3x Pattern A",
            arrEq(a, [10, 20, 20, 30, 40]) && j == 0,
            "a=" + s(a) + " j=" + j);

        // T8.3: 连续3次 Pattern B
        a = [10, 20, 30, 40, 50]; j = 4;
        a[j] = a[--j]; // a[4]=a[3]=40, j=3
        a[j] = a[--j]; // a[3]=a[2]=30, j=2
        a[j] = a[--j]; // a[2]=a[1]=20, j=1
        ok("T8.3 chained 3x Pattern B",
            arrEq(a, [10, 20, 20, 30, 40]) && j == 1,
            "a=" + s(a) + " j=" + j);

        // T8.4: 单元素数组 — while循环不进入
        a = [42]; j = 0;
        var key:Number = 42;
        while (j >= 0 && a[j] > key) { a[j + 1] = a[j--]; }
        ok("T8.4 single element, no shift",
            arrEq(a, [42]) && j == 0,
            "a=" + s(a) + " j=" + j);

        // T8.5: 两元素交换
        a = [20, 10]; j = 0;
        key = 10;
        while (j >= 0 && a[j] > key) { a[j + 1] = a[j--]; }
        a[j + 1] = key;
        ok("T8.5 two-element swap via Pattern A loop",
            arrEq(a, [10, 20]) && j == -1,
            "a=" + s(a) + " j=" + j);

        // T8.6: 大搬移 (length=10, key最小)
        a = [10, 20, 30, 40, 50, 60, 70, 80, 90, 1];
        key = 1; j = 8;
        while (j >= 0 && a[j] > key) { a[j + 1] = a[j--]; }
        a[j + 1] = key;
        ok("T8.6 shift 9 elements right",
            arrEq(a, [1, 10, 20, 30, 40, 50, 60, 70, 80, 90]) && j == -1,
            "a=" + s(a) + " j=" + j);

        // T8.7: Pattern B 大搬移 (insert at pos 0)
        a = [90, 10, 20, 30, 40, 50, 60, 70, 80];
        var left:Number = 0;
        j = 8;
        while (j > left) { a[j] = a[--j]; }
        a[left] = 5;
        ok("T8.7 Pattern B shift 8 elements right",
            arrEq(a, [5, 90, 10, 20, 30, 40, 50, 60, 70]),
            "a=" + s(a) + " j=" + j);

        // T8.8: --copyEnd >= 0 模式（batch copy的循环控制）
        a = [100, 200, 300, 400, 500, 600, 700, 800];
        var dst:Array = [0, 0, 0, 0, 0, 0, 0, 0];
        var d:Number = 0, p:Number = 0;
        var copyEnd:Number;
        copyEnd = 8 >> 2; // = 2
        while (--copyEnd >= 0) {
            dst[d++] = a[p++]; dst[d++] = a[p++];
            dst[d++] = a[p++]; dst[d++] = a[p++];
        }
        ok("T8.8 --copyEnd>=0 batch control (8 elements, 2 rounds)",
            arrEq(dst, [100, 200, 300, 400, 500, 600, 700, 800]) && d == 8 && p == 8,
            "dst=" + s(dst) + " d=" + d + " p=" + p);
    }

    // ── Group 9: 数组左移模式 (merge collapse stack shift) ────
    //
    // 核心模式 Pattern C: arr[i] = arr[++i]
    //   LHS-first: LHS index = old_i, then ++i, RHS = arr[old_i+1] → 正确左移
    //   RHS-first: ++i, RHS = arr[new_i], LHS = arr[new_i] → noop (错误)
    //
    // 应用场景: mergeCollapse 栈元素移除后的左移
    //   原始: for(copyI=start; copyI<end; copyI++) {
    //            runBase[copyI] = runBase[tempIdx = copyI+1];
    //            runLen[copyI]  = runLen[tempIdx]; }
    //   优化: while(copyI < end) {
    //            runBase[copyI] = runBase[++copyI];
    //            runLen[copyI-1] = runLen[copyI]; }
    //
    // 节省: 每轮省 1 次 SetVariable(tempIdx) + for 头部 copyI++ 换为体内 ++copyI

    private static function testGroup9_ArrayShift():Void {
        trace("");
        trace("--- Group 9: Array shift patterns (Pattern C: arr[i]=arr[++i]) ---");
        var a:Array, b:Array, i:Number;
        var origA:Array, origB:Array, oi:Number;

        // T9.1: 单次 arr[i] = arr[++i] — LHS-first 鉴别器
        // LHS-first: a[1] = a[2] = 30, i = 2 ✓
        // RHS-first: ++i→2, a[2] = a[2] = 30 (noop!), i = 2
        a = [10, 20, 30, 40, 50]; i = 1;
        a[i] = a[++i];
        ok("T9.1 a[i]=a[++i] single",
            a[1] == 30 && i == 2,
            "a=" + s(a) + " i=" + i + (a[1] == 30 ? " [LHS-first OK]" : " [RHS-first: NOOP!]"));

        // T9.2: 循环左移 — 基线 vs 合并形式
        origA = [10, 20, 30, 40, 50];
        oi = 0;
        while (oi < 4) { origA[oi] = origA[oi + 1]; oi++; }

        a = [10, 20, 30, 40, 50];
        i = 0;
        while (i < 4) { a[i] = a[++i]; }

        ok("T9.2 loop left-shift a[i]=a[++i]",
            arrEq(a, origA) && i == oi,
            "orig=" + s(origA) + " merged=" + s(a));

        // T9.3: 双数组共享计数器左移 — 模拟 runBase/runLen 栈移除
        // 基线
        origA = [100, 200, 300, 400, 500];
        origB = [10, 20, 30, 40, 50];
        oi = 1;
        while (oi < 4) {
            origA[oi] = origA[oi + 1];
            origB[oi] = origB[oi + 1];
            oi++;
        }

        // 合并形式: arr1[i]=arr1[++i]; arr2[i-1]=arr2[i];
        a = [100, 200, 300, 400, 500];
        b = [10, 20, 30, 40, 50];
        i = 1;
        while (i < 4) {
            a[i] = a[++i];
            b[i - 1] = b[i];
        }

        ok("T9.3 dual-array shift (runBase/runLen simulation)",
            arrEq(a, origA) && arrEq(b, origB) && i == oi,
            "origA=" + s(origA) + " a=" + s(a) + " origB=" + s(origB) + " b=" + s(b));

        // T9.4: 移除中间元素 — 从 index=2 开始左移，长度=6
        origA = [0, 1, 2, 3, 4, 5];
        origB = [10, 11, 12, 13, 14, 15];
        oi = 2;
        while (oi < 5) {
            origA[oi] = origA[oi + 1];
            origB[oi] = origB[oi + 1];
            oi++;
        }

        a = [0, 1, 2, 3, 4, 5];
        b = [10, 11, 12, 13, 14, 15];
        i = 2;
        while (i < 5) {
            a[i] = a[++i];
            b[i - 1] = b[i];
        }

        ok("T9.4 mid-array shift start=2 len=6",
            arrEq(a, origA) && arrEq(b, origB) && i == oi,
            "origA=" + s(origA) + " a=" + s(a) + " origB=" + s(origB) + " b=" + s(b));

        // T9.5: 边界 — 只移 1 个元素
        origA = [100, 200, 300];
        origB = [10, 20, 30];
        oi = 1;
        while (oi < 2) {
            origA[oi] = origA[oi + 1];
            origB[oi] = origB[oi + 1];
            oi++;
        }

        a = [100, 200, 300];
        b = [10, 20, 30];
        i = 1;
        while (i < 2) {
            a[i] = a[++i];
            b[i - 1] = b[i];
        }

        ok("T9.5 single-element shift",
            arrEq(a, origA) && arrEq(b, origB) && i == oi,
            "origA=" + s(origA) + " a=" + s(a));

        // T9.6: 边界 — 0 个元素需要移动 (start >= end)
        a = [100, 200, 300];
        b = [10, 20, 30];
        i = 2;
        while (i < 2) {
            a[i] = a[++i];
            b[i - 1] = b[i];
        }
        ok("T9.6 zero-element shift (no-op)",
            arrEq(a, [100, 200, 300]) && arrEq(b, [10, 20, 30]) && i == 2,
            "a=" + s(a) + " b=" + s(b) + " i=" + i);

        // T9.7: arr[i++] = val — LHS后置自增，简单RHS (两种求值序结果相同)
        a = [0, 0, 0, 0, 0]; i = 1;
        a[i++] = 42;
        ok("T9.7 a[i++]=val (order-independent)",
            a[1] == 42 && i == 2,
            "a=" + s(a) + " i=" + i);

        // T9.8: arr[++i] = val — LHS前置自增，简单RHS (两种求值序结果相同)
        a = [0, 0, 0, 0, 0]; i = 1;
        a[++i] = 42;
        ok("T9.8 a[++i]=val (order-independent)",
            a[2] == 42 && i == 2,
            "a=" + s(a) + " i=" + i);

        // T9.9: 反向右移 arr[i] = arr[--i] (已在Group2确认安全)
        // 与 arr[i] = arr[++i] 对称验证
        a = [10, 20, 30, 40, 50]; i = 3;
        a[i] = a[--i];
        ok("T9.9 a[i]=a[--i] right-shift single (Pattern B, cross-check)",
            a[3] == 30 && i == 2,
            "a=" + s(a) + " i=" + i);
    }

    // ── 原始插入排序（基准） ─────────────────────────

    private static function sortOriginal(arr:Array):Void {
        var n:Number = arr.length;
        var i:Number, j:Number, key:Number;
        var left:Number, hi2:Number, mid:Number;
        for (i = 1; i < n; i++) {
            key = arr[i];
            if (arr[i - 1] <= key) continue;
            if (i <= 4) {
                j = i - 1;
                while (j >= 0 && arr[j] > key) {
                    arr[j + 1] = arr[j]; j--;
                }
                arr[j + 1] = key;
            } else {
                left = 0; hi2 = i;
                while (left < hi2) {
                    mid = (left + hi2) >> 1;
                    if (arr[mid] <= key) left = mid + 1;
                    else hi2 = mid;
                }
                j = i;
                while (j > left) { arr[j] = arr[j - 1]; j--; }
                arr[left] = key;
            }
        }
    }

    // ── 合并后插入排序（待验证） ─────────────────────

    private static function sortMerged(arr:Array):Void {
        var n:Number = arr.length;
        var i:Number, j:Number, key:Number;
        var left:Number, hi2:Number, mid:Number;
        for (i = 1; i < n; i++) {
            key = arr[i];
            if (arr[i - 1] <= key) continue;
            if (i <= 4) {
                j = i - 1;
                while (j >= 0 && arr[j] > key) {
                    arr[j + 1] = arr[j--];     // ← Pattern A merged
                }
                arr[j + 1] = key;
            } else {
                left = 0; hi2 = i;
                while (left < hi2) {
                    mid = (left + hi2) >> 1;
                    if (arr[mid] <= key) left = mid + 1;
                    else hi2 = mid;
                }
                j = i;
                while (j > left) { arr[j] = arr[--j]; } // ← Pattern B merged
                arr[left] = key;
            }
        }
    }
}
