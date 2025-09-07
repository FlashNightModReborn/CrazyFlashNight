import org.flashNight.naki.Sort.PDQSortBenchmark;
import org.flashNight.naki.Sort.PDQSortWithProfiler;
import org.flashNight.naki.Sort.SortProfiler;
import org.flashNight.naki.Sort.TestDataGenerator;
import org.flashNight.naki.Sort.PDQSort;

class org.flashNight.naki.Sort.RunOptimization {
    
    /**
     * 运行优化测试
     * Step 0: 生成基线报告
     * Step 1: 验证小段优先改进
     */
    public static function main():Void {
        trace("\n=====================================");
        trace("PDQSort Optimization - Step 0 & 1");
        trace("=====================================\n");
        
        // Step 0: 运行基线测试
        trace("Step 0: Generating Baseline Report...");
        trace("-------------------------------------");
        PDQSortBenchmark.runBaseline();
        
        // Step 1: 验证小段优先改进
        trace("\n\nStep 1: Verifying Small-First Optimization...");
        trace("-------------------------------------");
        verifyStackDepthImprovement();
        
        // 运行回归测试
        trace("\n\nRunning Regression Tests...");
        trace("-------------------------------------");
        runRegressionTests();
    }
    
    /**
     * 验证栈深度改进
     */
    private static function verifyStackDepthImprovement():Void {
        var profiler:SortProfiler = new SortProfiler();
        profiler.setEnabled(true);
        
        var testSizes:Array = [100, 1000, 10000, 50000];
        var worstCaseFound:Boolean = false;
        
        trace("\nStack Depth Analysis:");
        trace("Size\tExpected Max\tActual Max\tStatus");
        trace("----\t------------\t----------\t------");
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = testSizes[i];
            var expectedMax:Number = Math.floor(Math.log(size) / Math.LN2) + 2;
            
            // 测试多种分布
            var distributions:Array = ["random", "sawtooth2", "organPipe"];
            var maxDepthFound:Number = 0;
            
            for (var j:Number = 0; j < distributions.length; j++) {
                var data:Array = TestDataGenerator.generate(size, distributions[j]);
                profiler.reset();
                
                PDQSortWithProfiler.sort(data.slice(), null, profiler);
                
                if (profiler.maxStackDepth > maxDepthFound) {
                    maxDepthFound = profiler.maxStackDepth;
                }
            }
            
            var status:String = (maxDepthFound <= expectedMax) ? "✓ PASS" : "✗ FAIL";
            if (maxDepthFound > expectedMax) {
                worstCaseFound = true;
            }
            
            trace(size + "\t" + expectedMax + "\t\t" + maxDepthFound + "\t\t" + status);
        }
        
        if (!worstCaseFound) {
            trace("\n✅ Stack depth optimization successful!");
            trace("All stack depths are within O(log n) bounds.");
        } else {
            trace("\n⚠️ Stack depth still exceeds bounds in some cases.");
            trace("Further optimization may be needed.");
        }
    }
    
    /**
     * 运行回归测试
     */
    private static function runRegressionTests():Void {
        var testCount:Number = 0;
        var passCount:Number = 0;
        var failCount:Number = 0;
        
        // 测试不同大小和分布
        var sizes:Array = [0, 1, 2, 10, 32, 33, 100, 1000];
        var distributions:Array = ["random", "sorted", "reversed", "sawtooth2", "manyDuplicates"];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = sizes[i];
            
            for (var j:Number = 0; j < distributions.length; j++) {
                var dist:String = distributions[j];
                testCount++;
                
                // 生成测试数据
                var data:Array;
                if (size <= 2) {
                    // 特殊处理小数组
                    data = [];
                    for (var k:Number = 0; k < size; k++) {
                        data.push(size - k);
                    }
                } else {
                    data = TestDataGenerator.generate(size, dist);
                }
                
                // 复制数组用于验证
                var sorted:Array = data.slice();
                var expected:Array = data.slice();
                expected.sort(Array.NUMERIC);
                
                // 执行排序
                PDQSort.sort(sorted, null);
                
                // 验证结果
                var isCorrect:Boolean = arraysEqual(sorted, expected);
                
                if (isCorrect) {
                    passCount++;
                } else {
                    failCount++;
                    trace("❌ Failed: size=" + size + ", distribution=" + dist);
                }
            }
        }
        
        trace("\nRegression Test Results:");
        trace("Total: " + testCount + " | Passed: " + passCount + " | Failed: " + failCount);
        
        if (failCount === 0) {
            trace("✅ All regression tests passed!");
        } else {
            trace("⚠️ " + failCount + " regression test(s) failed.");
        }
    }
    
    /**
     * 比较两个数组是否相等
     */
    private static function arraysEqual(a:Array, b:Array):Boolean {
        if (a.length !== b.length) return false;
        for (var i:Number = 0; i < a.length; i++) {
            if (a[i] !== b[i]) return false;
        }
        return true;
    }
}