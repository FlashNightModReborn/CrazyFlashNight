import org.flashNight.naki.Sort.TestDataGenerator;
import org.flashNight.naki.Sort.PDQSortWithProfiler;
import org.flashNight.naki.Sort.SortProfiler;

class org.flashNight.naki.Sort.PDQSortBenchmark {
    
    // 测试配置
    private static var TEST_SIZES:Array = [100, 500, 1000, 5000, 10000];
    private static var DISTRIBUTIONS:Array = ["random", "sorted", "reversed", "nearlySorted", 
                                              "sawtooth2", "sawtooth4", "sawtooth8", 
                                              "organPipe", "manyDuplicates", "alternating"];
    
    /**
     * 运行基准测试并生成基线报告
     */
    public static function runBaseline():Void {
        trace("\n");
        trace("================================================================");
        trace("PDQSort Baseline Performance Report");
        trace("================================================================");
        trace("Generated: " + new Date());
        trace("\n");
        
        // 创建性能分析器
        var profiler:SortProfiler = new SortProfiler();
        profiler.setEnabled(true);
        
        // 结果存储
        var results:Array = [];
        
        // 对每个测试规模
        for (var sizeIdx:Number = 0; sizeIdx < TEST_SIZES.length; sizeIdx++) {
            var size:Number = TEST_SIZES[sizeIdx];
            trace("\n--- Array Size: " + size + " ---");
            
            // 对每个数据分布
            for (var distIdx:Number = 0; distIdx < DISTRIBUTIONS.length; distIdx++) {
                var distribution:String = DISTRIBUTIONS[distIdx];
                
                // 生成测试数据
                var testData:Array = TestDataGenerator.generate(size, distribution);
                var testCopy:Array = testData.slice();
                
                // 重置性能计数器
                profiler.reset();
                
                // 执行排序并计时
                var startTime:Number = getTimer();
                var sorted:Array = PDQSortWithProfiler.sort(testCopy, null, profiler);
                var endTime:Number = getTimer();
                var timeTaken:Number = endTime - startTime;
                
                // 验证正确性
                var isCorrect:Boolean = verifySort(sorted);
                
                // 记录结果
                var result:Object = {
                    size: size,
                    distribution: distribution,
                    time: timeTaken,
                    comparisons: profiler.comparisons,
                    swaps: profiler.swaps,
                    partitions: profiler.partitions,
                    badSplits: profiler.badSplits,
                    heapsortCalls: profiler.heapsortCalls,
                    maxStackDepth: profiler.maxStackDepth,
                    correct: isCorrect
                };
                results.push(result);
                
                // 输出结果
                trace(formatResult(result));
            }
        }
        
        // 输出汇总
        trace("\n");
        trace("================================================================");
        trace("Summary Statistics");
        trace("================================================================");
        outputSummary(results);
        
        // 识别问题区域
        trace("\n");
        trace("================================================================");
        trace("Problem Areas Identified");
        trace("================================================================");
        identifyProblems(results);
    }
    
    /**
     * 格式化单个结果
     */
    private static function formatResult(result:Object):String {
        var str:String = result.distribution + ": ";
        str += result.time + "ms";
        str += " | Cmp:" + result.comparisons;
        str += " Swp:" + result.swaps;
        str += " Part:" + result.partitions;
        str += " Bad:" + result.badSplits;
        str += " Heap:" + result.heapsortCalls;
        str += " Stack:" + result.maxStackDepth;
        str += " | " + (result.correct ? "✓" : "✗");
        return str;
    }
    
    /**
     * 验证排序正确性
     */
    private static function verifySort(arr:Array):Boolean {
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i-1] > arr[i]) {
                return false;
            }
        }
        return true;
    }
    
    /**
     * 输出汇总统计
     */
    private static function outputSummary(results:Array):Void {
        // 按分布类型分组统计
        var byDistribution:Object = {};
        
        for (var i:Number = 0; i < results.length; i++) {
            var result:Object = results[i];
            var dist:String = result.distribution;
            
            if (!byDistribution[dist]) {
                byDistribution[dist] = {
                    totalTime: 0,
                    totalComparisons: 0,
                    totalBadSplits: 0,
                    totalHeapsortCalls: 0,
                    maxStackDepth: 0,
                    count: 0
                };
            }
            
            var stats:Object = byDistribution[dist];
            stats.totalTime += result.time;
            stats.totalComparisons += result.comparisons;
            stats.totalBadSplits += result.badSplits;
            stats.totalHeapsortCalls += result.heapsortCalls;
            stats.maxStackDepth = Math.max(stats.maxStackDepth, result.maxStackDepth);
            stats.count++;
        }
        
        // 输出每个分布的平均性能
        for (var distribution:String in byDistribution) {
            var stat:Object = byDistribution[distribution];
            trace("\n" + distribution + ":");
            trace("  Avg Time: " + Math.round(stat.totalTime / stat.count) + "ms");
            trace("  Avg Comparisons: " + Math.round(stat.totalComparisons / stat.count));
            trace("  Total Bad Splits: " + stat.totalBadSplits);
            trace("  Total Heapsort Calls: " + stat.totalHeapsortCalls);
            trace("  Max Stack Depth: " + stat.maxStackDepth);
        }
    }
    
    /**
     * 识别性能问题
     */
    private static function identifyProblems(results:Array):Void {
        var problems:Array = [];
        
        for (var i:Number = 0; i < results.length; i++) {
            var result:Object = results[i];
            
            // 检查锯齿波性能问题
            if (result.distribution.indexOf("sawtooth") >= 0) {
                if (result.badSplits > 0 || result.heapsortCalls > 0) {
                    problems.push("❗ " + result.distribution + " (size=" + result.size + "): " +
                                "Bad splits=" + result.badSplits + ", Heapsort calls=" + result.heapsortCalls);
                }
            }
            
            // 检查栈深度问题
            var expectedMaxDepth:Number = Math.floor(Math.log(result.size) / Math.LN2) + 2;
            if (result.maxStackDepth > expectedMaxDepth) {
                problems.push("⚠️  " + result.distribution + " (size=" + result.size + "): " +
                            "Stack depth " + result.maxStackDepth + " exceeds expected " + expectedMaxDepth);
            }
            
            // 检查正确性
            if (!result.correct) {
                problems.push("❌ " + result.distribution + " (size=" + result.size + "): " +
                            "Sort result incorrect!");
            }
        }
        
        if (problems.length > 0) {
            for (var j:Number = 0; j < problems.length; j++) {
                trace(problems[j]);
            }
        } else {
            trace("✅ No critical problems detected in baseline");
        }
    }
}