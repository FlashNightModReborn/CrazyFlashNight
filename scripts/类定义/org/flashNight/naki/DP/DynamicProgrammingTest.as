/**
 * 文件路径: org/flashNight/naki/DP/DynamicProgrammingTest.as
 */
import org.flashNight.naki.DP.DynamicProgramming;
import org.flashNight.naki.DataStructures.Dictionary;

class org.flashNight.naki.DP.DynamicProgrammingTest {
    
    // 构造函数：在实例化时自动执行所有测试
    public function DynamicProgrammingTest() {
        trace("===== Start DynamicProgramming Test =====");
        testFibonacci();
        testFibonacciEdgeCases();
        testKnapsack();
        testLongestCommonSubsequence();
        testMinPathSum();
        testCacheMechanism();
        testDictionary();
        testPerformance();
        trace("===== End DynamicProgramming Test =====");
    }

    /**
     * 简易断言
     */
    private function assertEquals(expected, actual, testName:String):Void {
        if (expected === actual) {
            trace("[PASS] " + testName);
        } else {
            trace("[FAIL] " + testName + " - Expected: " + expected + ", but got: " + actual);
        }
    }

    /**
     * 测试斐波那契
     */
    private function testFibonacci():Void {
        trace("--- Testing Fibonacci Sequence ---");
        var dp:DynamicProgramming = new DynamicProgramming();
        dp.initialize({ maxN: 50 }, fibonacciTransition);

        // 测试若干典型值（直接用数值作为 context）
        assertEquals(0, dp.solve(0, null), "Fibonacci(0)");
        assertEquals(1, dp.solve(1, null), "Fibonacci(1)");
        assertEquals(1, dp.solve(2, null), "Fibonacci(2)");
        assertEquals(2, dp.solve(3, null), "Fibonacci(3)");
        assertEquals(5, dp.solve(5, null), "Fibonacci(5)");
        assertEquals(55, dp.solve(10, null), "Fibonacci(10)");
        // 如果缓存和递归都正确，这里不会卡死，而会很快给出结果
        assertEquals(102334155, dp.solve(40, null), "Fibonacci(40)");
    }

    /**
     * 测试斐波那契的边界情况和无效输入
     */
    private function testFibonacciEdgeCases():Void {
        trace("--- Testing Fibonacci Edge Cases ---");
        var dp:DynamicProgramming = new DynamicProgramming();
        dp.initialize({ maxN: 50 }, fibonacciTransition);

        // 边界条件
        assertEquals(0, dp.solve(0, null), "Fibonacci Edge Case n=0");
        assertEquals(1, dp.solve(1, null), "Fibonacci Edge Case n=1");

        // 无效输入处理: 负数
        try {
            dp.solve(-1, null);
            trace("[FAIL] Fibonacci Invalid Input n=-1 - Expected Error");
        } catch (e:Error) {
            trace("[PASS] Fibonacci Invalid Input n=-1 - Caught Error");
        }

        // 无效输入处理: 非数字
        try {
            dp.solve("a", null);
            trace("[FAIL] Fibonacci Invalid Input n='a' - Expected Error");
        } catch (e:Error) {
            trace("[PASS] Fibonacci Invalid Input n='a' - Caught Error");
        }
    }

    /**
     * 斐波那契状态转移函数
     * @param context Number   当前要计算 Fibonacci(n)
     * @param param   额外参数（此例中无用，可为 null）
     * @param dp      当前的 DynamicProgramming 实例，用于递归调用 solve
     * @return        F(n)
     */
    private function fibonacciTransition(context:Object, param:Object, dp:DynamicProgramming):Number {
        var n:Number = Number(context);
        if (isNaN(n)) {
            throw new Error("Invalid input for Fibonacci: n is not a number.");
        }
        if (n < 0) {
            throw new Error("Invalid input for Fibonacci: n cannot be negative.");
        }
        if (n < 2) {
            return n;
        }
        // 使用 dp.solve 进行递归调用
        return dp.solve(n - 1, param) + dp.solve(n - 2, param);
    }

    /**
     * 测试 0-1 背包问题
     */
    private function testKnapsack():Void {
        trace("--- Testing 0-1 Knapsack Problem ---");
        var dp:DynamicProgramming = new DynamicProgramming();
        var items:Array = [
            {weight:10, value:60},
            {weight:20, value:100},
            {weight:30, value:120}
        ];
        dp.initialize({ capacity: 50, items: items }, knapsackTransition);

        // 子问题以 {capacity, index} 作为键
        var expected:Number = 220; // 选择20(100) + 30(120)
        var actual:Number   = dp.solve({capacity:50, index:items.length}, null);
        assertEquals(expected, actual, "Knapsack(50)");
    }

    /**
     * 0-1 背包状态转移函数 (Top-Down)
     * @param context {capacity:Number, index:Number} 子问题标识
     * @param param   额外参数（此例中无用）
     * @param dp      DynamicProgramming 实例
     * @return        最大价值
     */
    private function knapsackTransition(context:Object, param:Object, dp:DynamicProgramming):Number {
        var items:Array     = dp.getProblemSize().items;
        var capacity:Number = Number(context.capacity);
        var i:Number        = Number(context.index);

        // 没有物品 或 背包容量为0
        if (i == 0 || capacity <= 0) {
            return 0;
        }

        // 当前要考虑第 (i-1) 个物品
        var item:Object = items[i - 1];
        if (item.weight > capacity) {
            // 不能放这件物品
            return dp.solve({capacity: capacity, index: i - 1}, param);
        } else {
            // 选择放 或 不放
            var includeVal:Number = item.value
                                  + dp.solve({capacity: capacity - item.weight, index: i - 1}, param);
            var excludeVal:Number = dp.solve({capacity: capacity, index: i - 1}, param);
            return Math.max(includeVal, excludeVal);
        }
    }

    /**
     * 测试最长公共子序列（LCS）
     */
    private function testLongestCommonSubsequence():Void {
        trace("--- Testing Longest Common Subsequence (LCS) ---");
        var dp:DynamicProgramming = new DynamicProgramming();
        var str1:String = "AGGTAB";
        var str2:String = "GXTXAYB";

        // problemSize 存原串，子问题只传 (i,j)
        dp.initialize({ str1: str1, str2: str2 }, lcsTransition);

        var expected = 4; // "GTAB"
        var actual   = dp.solve({i: str1.length, j: str2.length}, null);
        assertEquals(expected, actual, "LCS('AGGTAB', 'GXTXAYB')");
    }

    /**
     * LCS 状态转移函数 (Top-Down)
     * @param context {i:Number, j:Number} 分别代表 str1[0..i-1], str2[0..j-1] 的子串
     * @param param   无用
     * @param dp      DynamicProgramming
     */
    private function lcsTransition(context:Object, param:Object, dp:DynamicProgramming):Number {
        var str1:String = dp.getProblemSize().str1;
        var str2:String = dp.getProblemSize().str2;
        var i:Number    = Number(context.i);
        var j:Number    = Number(context.j);

        if (i == 0 || j == 0) {
            return 0;
        }

        if (str1.charAt(i - 1) == str2.charAt(j - 1)) {
            // 末位字符相同
            return 1 + dp.solve({i:i-1, j:j-1}, param);
        } else {
            // 末位字符不同
            var a:Number = dp.solve({i:i,   j:j-1}, param);
            var b:Number = dp.solve({i:i-1, j:j},   param);
            return Math.max(a, b);
        }
    }

    /**
     * 测试最小路径和
     */
    private function testMinPathSum():Void {
        trace("--- Testing Minimum Path Sum ---");
        var dp:DynamicProgramming = new DynamicProgramming();
        var grid:Array = [
            [1, 3, 1],
            [1, 5, 1],
            [4, 2, 1]
        ];

        // 存 grid，全局知道行列数
        dp.initialize({ grid: grid }, minPathSumTransition);

        var expected:Number = 7; // 1→3→1→1→1
        // 目标是从(0,0)到(2,2)的最小路径和
        var actual:Number   = dp.solve({r:2, c:2}, null);
        assertEquals(expected, actual, "MinPathSum(3x3 grid)");
    }

    /**
     * 最小路径和状态转移函数 (Top-Down)
     * @param context {r:Number, c:Number}
     * @param param   无用
     * @param dp      DynamicProgramming
     */
    private function minPathSumTransition(context:Object, param:Object, dp:DynamicProgramming):Number {
        var row:Number = Number(context.r);
        var col:Number = Number(context.c);
        var grid:Array = dp.getProblemSize().grid;

        if (row == 0 && col == 0) {
            return grid[0][0];
        }

        var minUp:Number   = Number.MAX_VALUE;
        var minLeft:Number = Number.MAX_VALUE;

        if (row > 0) {
            minUp = dp.solve({r: row - 1, c: col}, param);
        }
        if (col > 0) {
            minLeft = dp.solve({r: row, c: col - 1}, param);
        }

        return grid[row][col] + Math.min(minUp, minLeft);
    }

    /**
     * 测试缓存机制
     */
    private function testCacheMechanism():Void {
        trace("--- Testing Cache Mechanism ---");
        var dp:DynamicProgramming = new DynamicProgramming();
        var callCount:Number = 0;

        // 定义一个状态转移函数，统计调用次数
        dp.initialize({ maxN: 10 }, function(context:Object, param:Object, dpInstance:DynamicProgramming):Number {
            callCount++;
            var n:Number = Number(context);
            if (n < 2) {
                return n;
            }
            return dpInstance.solve(n - 1, null) + dpInstance.solve(n - 2, null);
        });

        // 计算 Fibonacci(10)
        var expected:Number = 55;
        var actual:Number   = dp.solve(10, null);
        assertEquals(expected, actual, "Fibonacci(10) with Cache");

        // 对于 Fib(10)，只会真正计算 n=0~10 共 11 个子问题
        var expectedCalls:Number = 11;
        assertEquals(expectedCalls, callCount, "Cache Mechanism Call Count");
    }

    /**
     * 测试 Dictionary 类
     * （示范对字符串键、对象键、函数键等的存取）
     */
    private function testDictionary():Void {
        trace("--- Testing Dictionary Class ---");
        var dict:Dictionary = new Dictionary();

        // 测试字符串键
        dict.setItem("key1", "value1");
        assertEquals("value1", dict.getItem("key1"), "Dictionary String Key");

        // 测试对象键
        var objKey:Object = {name: "objectKey"};
        dict.setItem(objKey, "value2");
        assertEquals("value2", dict.getItem(objKey), "Dictionary Object Key");

        // 测试函数键
        var funcKey:Function = function() { return "func"; };
        dict.setItem(funcKey, "value3");
        assertEquals("value3", dict.getItem(funcKey), "Dictionary Function Key");

        // 测试键的数量
        var expectedSize:Number = 3;
        var actualSize:Number   = dict.getCount();
        assertEquals(expectedSize, actualSize, "Dictionary Size");

        // 测试清空字典
        dict.clear();
        assertEquals(0, dict.getCount(), "Dictionary Clear");
    }

    /**
     * 测试性能（多个问题和不同规模）
     */
    private function testPerformance():Void {
        trace("--- Testing Performance ---");

        // 1. 测试 Fibonacci(40)
        var dpFib:DynamicProgramming = new DynamicProgramming();
        dpFib.initialize({ maxN: 40 }, fibonacciTransition);

        var startTimeFib:Number = getTimer();
        var resultFib:Number    = dpFib.solve(40, null);
        var endTimeFib:Number   = getTimer();

        trace("Fibonacci(40) = " + resultFib + ", time = " + (endTimeFib - startTimeFib) + " ms");

        // 2. 测试 0-1 Knapsack with larger input
        var dpKnapsack:DynamicProgramming = new DynamicProgramming();
        var knapsackItems:Array = [];
        for (var i:Number = 1; i <= 20; i++) {
            knapsackItems.push({weight: i * 2, value: i * 10});
        }
        dpKnapsack.initialize({ capacity: 40, items: knapsackItems }, knapsackTransition);

        var startTimeKnapsack:Number = getTimer();
        var resultKnapsack:Number    = dpKnapsack.solve({capacity: 40, index: knapsackItems.length}, null);
        var endTimeKnapsack:Number   = getTimer();

        trace("Knapsack(40) with 20 items = " + resultKnapsack
              + ", time = " + (endTimeKnapsack - startTimeKnapsack) + " ms");

        // 3. 测试 LCS with longer strings
        var dpLCS:DynamicProgramming = new DynamicProgramming();
        dpLCS.initialize({ str1: "ABCBDAB", str2: "BDCABC" }, lcsTransition);

        var startTimeLCS:Number = getTimer();
        var resultLCS:Number    = dpLCS.solve({i: 7, j: 6}, null); // str1.length=7, str2.length=6
        var endTimeLCS:Number   = getTimer();

        trace("LCS('ABCBDAB', 'BDCABC') = " + resultLCS
              + ", time = " + (endTimeLCS - startTimeLCS) + " ms");
    }
}
