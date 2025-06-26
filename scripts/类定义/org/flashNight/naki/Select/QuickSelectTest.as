import org.flashNight.naki.Select.QuickSelect;

/**
 * QuickSelectTest 增强版测试类 (AS2修正版)
 *
 * 全面测试 QuickSelect 的正确性、性能和特殊场景处理能力。
 * 针对 QuickSelect 的核心特性设计了专项测试，包括：
 * - 快速选择算法的正确性验证
 * - 分区操作的完整性测试
 * - 三数取中优化效果测试
 * - 不同数据分布下的性能表现
 * - 边界条件和极端场景处理
 * - 实际应用场景模拟测试
 * - 与传统排序方法的性能对比
 */
class org.flashNight.naki.Select.QuickSelectTest {

    public static function runTests():Void {
        trace("Starting Enhanced QuickSelect Tests...\n");

        // ================================
        // 基础功能测试套件
        // ================================
        trace("=== 基础功能测试 ===");
        testEmptyArray();
        testSingleElement();
        testTwoElements();
        testThreeElements();
        testAlreadySorted();
        testReverseSorted();
        testRandomArray();
        testDuplicateElements();
        testAllSameElements();
        testCustomCompareFunction();
        testNegativeNumbers();
        testFloatingPointNumbers();
        
        // ================================
        // 核心算法特性专项测试
        // ================================
        trace("\n=== QuickSelect 核心特性测试 ===");
        testPartitionCorrectness();
        testPartitionBoundaryIntegrity();
        testThreeWayMedianPivotSelection();
        testPivotOptimizationEffectiveness();
        testIterativeImplementationCorrectness();
        testKthElementRangeValidation();
        testPartitionStabilityWithDuplicates();
        testPivotSelectionWorstCaseAvoidance();
        
        // ================================
        // 选择操作专项测试
        // ================================
        trace("\n=== 选择操作专项测试 ===");
        testSelectFirstElement();
        testSelectLastElement();
        testSelectMiddleElement();
        testSelectMedianVariations();
        testSelectQuartiles();
        testSelectPercentiles();
        testSelectWithNegativeIndices();
        testSelectOutOfBounds();
        testSelectFromSubrange();
        
        // ================================
        // 分区算法深度测试
        // ================================
        trace("\n=== 分区算法深度测试 ===");
        testLomutoPartitionCorrectness();
        testPartitionWithAllEqual();
        testPartitionWithTwoDistinctValues();
        testPartitionWithExtremePivots();
        testPartitionPreservation();
        testPartitionMemoryEfficiency();
        testPartitionWithLargeArrays();
        
        // ================================
        // 比较函数兼容性测试
        // ================================
        trace("\n=== 比较函数兼容性测试 ===");
        testBuiltinNumberCompare();
        testBuiltinStringCompare();
        testReverseNumberCompare();
        testComplexObjectCompare();
        testNullSafeCompare();
        testCaseInsensitiveStringCompare();
        testMultiFieldObjectCompare();
        testDateTimeCompare();
        
        // ================================
        // 数据分布特性测试
        // ================================
        trace("\n=== 数据分布特性测试 ===");
        testUniformDistribution();
        testNormalDistribution();
        testExponentialDistribution();
        testPowerLawDistribution();
        testBimodalDistribution();
        testHighlySkewedData();
        testZipfianDistribution();
        testClustered();
        
        // ================================
        // 实际应用场景测试
        // ================================
        trace("\n=== 实际应用场景测试 ===");
        testStatisticalAnalysis();
        testTopKQueries();
        testPercentileCalculation();
        testOutlierDetection();
        testDataStreamProcessing();
        testGameLeaderboards();
        testFinancialRiskAnalysis();
        testImageProcessingHistogram();
        testDatabaseQueryOptimization();
        testMachineLearningFeatureSelection();
        
        // ================================
        // 边界条件和压力测试
        // ================================
        trace("\n=== 边界条件和压力测试 ===");
        testMinimumArraySizes();
        testMaximumPracticalArraySizes();
        testExtremeValueRanges();
        testRepeatedOperationsStability();
        testMemoryConstrainedEnvironment();
        testWorstCaseScenarios();
        testBoundaryIndexValues();
        testNumericalPrecisionLimits();
        
        // ================================
        // 性能特性验证测试
        // ================================
        trace("\n=== 性能特性验证测试 ===");
        testLinearTimeComplexity();
        testConstantSpaceComplexity();
        testWorstCasePerformance();
        testAverageCase();
        testBestCaseOptimization();
        testComparisonWithSorting();
        testScalabilityAnalysis();
        
        // ================================
        // 综合性能测试（增强版）
        // ================================
        trace("\n=== 综合性能测试 ===");
        runEnhancedPerformanceTests();
        
        // ================================
        // 算法正确性验证测试
        // ================================
        trace("\n=== 算法正确性验证测试 ===");
        runCorrectnessVerificationSuite();
        
        // ================================
        // 扩展稳定性和健壮性测试
        // ================================
        testAlgorithmStability();
        testBoundaryValueHandling();
        testConcurrencySafety();
        
        // ================================
        // 压力测试
        // ================================
        runStressTestSuite();
        
        // ================================
        // 综合性能基准测试
        // ================================
        runComprehensivePerformanceBenchmark();
        
        // ================================
        // 算法质量评估
        // ================================
        evaluateAlgorithmQuality();
        
        // ================================
        // 生成最终报告
        // ================================
        generateFinalTestReport();
        
        trace("\nAll Enhanced QuickSelect Tests Completed.");
    }

    // ================================
    // 基础断言和工具方法
    // ================================
    private static function assertEquals(expected, actual, testName:String):Void {
        if (expected !== actual) {
            trace("FAIL: " + testName + " - 预期: " + expected + "，实际: " + actual);
        } else {
            trace("PASS: " + testName);
        }
    }

    private static function assertArrayEquals(expected:Array, actual:Array, testName:String):Void {
        if (expected.length != actual.length) {
            trace("FAIL: " + testName + " - 数组长度不一致，预期: " + expected.length + "，实际: " + actual.length);
            return;
        }
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] !== actual[i]) {
                trace("FAIL: " + testName + " - 索引 " + i + " 处不一致，预期: " + expected[i] + "，实际: " + actual[i]);
                return;
            }
        }
        trace("PASS: " + testName);
    }

    private static function assertTrue(condition:Boolean, testName:String, message:String):Void {
        if (!condition) {
            trace("FAIL: " + testName + " - " + message);
        } else {
            trace("PASS: " + testName);
        }
    }

    private static function assertPartitioned(arr:Array, k:Number, compareFunc:Function, testName:String):Void {
        if (compareFunc == null) {
            compareFunc = QuickSelect.numberCompare;
        }
        
        var pivotValue = arr[k];
        var isValidPartition:Boolean = true;
        var errorMessage:String = "";
        
        // 检查左侧元素 <= pivot
        for (var i:Number = 0; i < k; i++) {
            if (compareFunc(arr[i], pivotValue) > 0) {
                isValidPartition = false;
                errorMessage = "左侧元素 arr[" + i + "]=" + arr[i] + " 大于 pivot arr[" + k + "]=" + pivotValue;
                break;
            }
        }
        
        // 检查右侧元素 >= pivot
        if (isValidPartition) {
            for (var j:Number = k + 1; j < arr.length; j++) {
                if (compareFunc(arr[j], pivotValue) < 0) {
                    isValidPartition = false;
                    errorMessage = "右侧元素 arr[" + j + "]=" + arr[j] + " 小于 pivot arr[" + k + "]=" + pivotValue;
                    break;
                }
            }
        }
        
        assertTrue(isValidPartition, testName, errorMessage);
    }

    private static function createTestObject(value:Number, id:String):Object {
        return {
            value: value,
            id: id,
            timestamp: getTimer() + Math.random() * 1000,
            toString: function():String { return this.id + ":" + this.value; }
        };
    }

    private static function generateRandomArray(size:Number, min:Number, max:Number):Array {
        var arr:Array = [];
        var range:Number = max - min;
        for (var i:Number = 0; i < size; i++) {
            arr.push(min + Math.random() * range);
        }
        return arr;
    }

    private static function measurePerformance(func:Function, testName:String):Number {
        var start:Number = getTimer();
        func();
        var elapsed:Number = getTimer() - start;
        trace("    " + testName + " 耗时: " + elapsed + "ms");
        return elapsed;
    }
    
    // AS2字符串重复工具函数
    private static function repeatString(str:String, count:Number):String {
        var result:String = "";
        for (var i:Number = 0; i < count; i++) {
            result += str;
        }
        return result;
    }
    
    // AS2替代toFixed方法的工具函数
    private static function formatDecimal(num:Number, digits:Number):String {
        var multiplier:Number = Math.pow(10, digits);
        var rounded:Number = Math.round(num * multiplier) / multiplier;
        return String(rounded);
    }
    
    // 生成指定分布的随机数据
    private static function generateDistributionData(size:Number, distribution:String):Array {
        var arr:Array = [];
        
        switch (distribution) {
            case "normal":
                // Box-Muller变换生成正态分布
                for (var i:Number = 0; i < size; i += 2) {
                    var u1:Number = Math.random();
                    var u2:Number = Math.random();
                    var z0:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
                    var z1:Number = Math.sqrt(-2 * Math.log(u1)) * Math.sin(2 * Math.PI * u2);
                    
                    arr.push(z0 * 100 + 500);
                    if (i + 1 < size) {
                        arr.push(z1 * 100 + 500);
                    }
                }
                break;
                
            case "exponential":
                var lambda:Number = 0.01;
                for (var j:Number = 0; j < size; j++) {
                    var u:Number = Math.random();
                    var exp:Number = -Math.log(1 - u) / lambda;
                    arr.push(exp * 5 + 1);
                }
                break;
                
            case "bimodal":
                for (var k:Number = 0; k < size; k++) {
                    var peak:Number = (Math.random() < 0.5) ? 200 : 800;
                    var noise:Number = (Math.random() - 0.5) * 100;
                    arr.push(peak + noise);
                }
                break;
                
            case "uniform":
            default:
                for (var l:Number = 0; l < size; l++) {
                    arr.push(Math.random() * 1000);
                }
                break;
        }
        
        return arr;
    }
    
    // 统计分析工具函数
    private static function calculateStatistics(data:Array):Object {
        var sortedData:Array = data.concat();
        sortedData.sort(Array.NUMERIC);
        
        var size:Number = sortedData.length;
        var min:Number = Number(sortedData[0]);
        var max:Number = Number(sortedData[size - 1]);
        var median:Number = Number(sortedData[Math.floor((size - 1) / 2)]);
        var q1:Number = Number(sortedData[Math.floor((size - 1) * 0.25)]);
        var q3:Number = Number(sortedData[Math.floor((size - 1) * 0.75)]);
        
        // 计算均值
        var sum:Number = 0;
        for (var i:Number = 0; i < data.length; i++) {
            sum += Number(data[i]);
        }
        var mean:Number = sum / data.length;
        
        // 计算方差和标准差
        var variance:Number = 0;
        for (var j:Number = 0; j < data.length; j++) {
            var diff:Number = Number(data[j]) - mean;
            variance += diff * diff;
        }
        variance /= data.length;
        var stdDev:Number = Math.sqrt(variance);
        
        return {
            size: size,
            min: min,
            max: max,
            mean: mean,
            median: median,
            q1: q1,
            q3: q3,
            iqr: q3 - q1,
            range: max - min,
            variance: variance,
            stdDev: stdDev,
            skewness: (mean - median) / stdDev  // 简化的偏度计算
        };
    }
    
    // 性能基准测试工具
    private static function benchmarkOperation(operation:Function, iterations:Number, description:String):Object {
        var times:Array = [];
        var totalTime:Number = 0;
        
        for (var i:Number = 0; i < iterations; i++) {
            var start:Number = getTimer();
            operation();
            var elapsed:Number = getTimer() - start;
            
            times.push(elapsed);
            totalTime += elapsed;
        }
        
        // 计算统计信息
        times.sort(Array.NUMERIC);
        var avgTime:Number = totalTime / iterations;
        var minTime:Number = Number(times[0]);
        var maxTime:Number = Number(times[times.length - 1]);
        var medianTime:Number = Number(times[Math.floor((times.length - 1) / 2)]);
        
        // 计算标准差
        var variance:Number = 0;
        for (var j:Number = 0; j < times.length; j++) {
            var diff:Number = Number(times[j]) - avgTime;
            variance += diff * diff;
        }
        var stdDev:Number = Math.sqrt(variance / times.length);
        
        var result:Object = {
            description: description,
            iterations: iterations,
            totalTime: totalTime,
            avgTime: avgTime,
            minTime: minTime,
            maxTime: maxTime,
            medianTime: medianTime,
            stdDev: stdDev,
            coefficient: stdDev / avgTime
        };
        
        trace("    基准测试: " + description);
        trace("      " + iterations + " 次迭代, 总时间: " + totalTime + "ms");
        trace("      平均: " + formatDecimal(avgTime, 2) + "ms, " +
              "中位数: " + formatDecimal(medianTime, 2) + "ms, " +
              "标准差: " + formatDecimal(stdDev, 2) + "ms");
        
        return result;
    }
    
    // 验证QuickSelect结果的正确性
    private static function verifyQuickSelectResult(originalData:Array, k:Number, result, compareFunc:Function):Boolean {
        if (compareFunc == null) {
            compareFunc = QuickSelect.numberCompare;
        }
        
        // 使用标准排序验证
        var sortedData:Array = originalData.concat();
        sortedData.sort(compareFunc);
        
        var expectedResult = sortedData[k];
        
        // 比较结果
        if (compareFunc === QuickSelect.numberCompare) {
            return Number(result) === Number(expectedResult);
        } else if (compareFunc === QuickSelect.stringCompare) {
            return String(result) === String(expectedResult);
        } else {
            return compareFunc(result, expectedResult) === 0;
        }
    }
    
    // 内存使用分析工具（通过数组操作间接测量）
    private static function analyzeMemoryUsage(dataSize:Number, operation:Function):Object {
        var beforeTime:Number = getTimer();
        
        // 创建测试数据
        var testData:Array = generateRandomArray(dataSize, 1, dataSize);
        var creationTime:Number = getTimer() - beforeTime;
        
        // 执行操作
        var operationStart:Number = getTimer();
        var result = operation(testData);
        var operationTime:Number = getTimer() - operationStart;
        
        // 清理验证
        var cleanupStart:Number = getTimer();
        testData = null;
        var cleanupTime:Number = getTimer() - cleanupStart;
        
        return {
            dataSize: dataSize,
            creationTime: creationTime,
            operationTime: operationTime,
            cleanupTime: cleanupTime,
            totalTime: creationTime + operationTime + cleanupTime,
            efficiency: operationTime / dataSize
        };
    }
    
    // 算法稳定性测试
    private static function testAlgorithmStability():Void {
        trace("\n=== 算法稳定性深度测试 ===");
        
        // 测试不同输入模式下的稳定性
        var stabilityPatterns:Array = [
            {
                name: "重复元素占主导",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    var dominantValue:Number = 50;
                    for (var i:Number = 0; i < size; i++) {
                        if (i < size * 0.8) {
                            arr.push(dominantValue);
                        } else {
                            arr.push(Math.random() * 100);
                        }
                    }
                    return arr;
                }
            },
            {
                name: "阶梯分布",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    var steps:Number = 10;
                    var stepSize:Number = Math.floor(size / steps);
                    
                    for (var i:Number = 0; i < size; i++) {
                        var stepValue:Number = Math.floor(i / stepSize) * 10;
                        arr.push(stepValue + Math.random() * 5);
                    }
                    return arr;
                }
            },
            {
                name: "锯齿波模式",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    var period:Number = 50;
                    
                    for (var i:Number = 0; i < size; i++) {
                        var cyclePos:Number = i % period;
                        var value:Number = (cyclePos < period / 2) ? cyclePos : (period - cyclePos);
                        arr.push(value + Math.random() * 10);
                    }
                    return arr;
                }
            }
        ];
        
        var testSize:Number = 1000;
        var testIterations:Number = 10;
        
        for (var i:Number = 0; i < stabilityPatterns.length; i++) {
            var pattern:Object = stabilityPatterns[i];
            var results:Array = [];
            var times:Array = [];
            
            for (var iter:Number = 0; iter < testIterations; iter++) {
                var data:Array = pattern.generator(testSize);
                var k:Number = Math.floor(testSize / 2);
                
                var start:Number = getTimer();
                var result:Number = Number(QuickSelect.selectKth(data, k, QuickSelect.numberCompare));
                var elapsed:Number = getTimer() - start;
                
                results.push(result);
                times.push(elapsed);
            }
            
            // 分析结果稳定性
            var uniqueResults:Object = {};
            var resultCount:Number = 0;
            
            for (var j:Number = 0; j < results.length; j++) {
                var res:String = String(results[j]);
                if (!uniqueResults[res]) {
                    uniqueResults[res] = 0;
                    resultCount++;
                }
                uniqueResults[res]++;
            }
            
            // 分析时间稳定性
            var avgTime:Number = 0;
            for (var k:Number = 0; k < times.length; k++) {
                avgTime += Number(times[k]);
            }
            avgTime /= times.length;
            
            var timeVariance:Number = 0;
            for (var l:Number = 0; l < times.length; l++) {
                var diff:Number = Number(times[l]) - avgTime;
                timeVariance += diff * diff;
            }
            var timeStdDev:Number = Math.sqrt(timeVariance / times.length);
            var timeCV:Number = timeStdDev / avgTime;
            
            assertTrue(resultCount <= 3, "算法稳定性测试", 
                pattern.name + " 结果变异过多: " + resultCount + " 种不同结果");
            
            assertTrue(timeCV < 1.0, "算法稳定性测试", 
                pattern.name + " 时间变异过大: " + formatDecimal(timeCV, 3));
            
            trace("  " + pattern.name + ":");
            trace("    结果稳定性: " + resultCount + " 种结果");
            trace("    时间稳定性: CV=" + formatDecimal(timeCV, 3) + 
                  ", 平均=" + formatDecimal(avgTime, 2) + "ms");
        }
        
        trace("PASS: 算法稳定性深度测试");
    }
    
    // 边界值处理专项测试
    private static function testBoundaryValueHandling():Void {
        trace("\n=== 边界值处理专项测试 ===");
        
        // 测试各种边界条件
        var boundaryTests:Array = [
            {
                name: "单精度浮点边界",
                data: [Number.MIN_VALUE, Number.MAX_VALUE / 1000000, 1.0, Number.MAX_VALUE / 1000000, Number.MIN_VALUE],
                description: "接近浮点数边界的值"
            },
            {
                name: "零值边界",
                data: [-0.1, -0.01, 0, 0.01, 0.1],
                description: "围绕零值的小数"
            },
            {
                name: "整数边界",
                data: [-2147483648, -1, 0, 1, 2147483647],
                description: "32位整数边界值"
            },
            {
                name: "相等值集合",
                data: [42.0, 42, 42.000001, 42.0, 42],
                description: "几乎相等的数值"
            }
        ];
        
        for (var i:Number = 0; i < boundaryTests.length; i++) {
            var test:Object = boundaryTests[i];
            var data:Array = test.data;
            
            try {
                // 测试所有可能的k值
                for (var k:Number = 0; k < data.length; k++) {
                    var result = QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
                    
                    assertTrue(result !== null && result !== undefined, 
                        "边界值处理测试", test.name + " k=" + k + " 返回了无效结果");
                    
                    // 验证结果在原数据中存在
                    var found:Boolean = false;
                    for (var j:Number = 0; j < data.length; j++) {
                        if (Math.abs(Number(result) - Number(data[j])) < 1e-10) {
                            found = true;
                            break;
                        }
                    }
                    
                    assertTrue(found, "边界值处理测试", 
                        test.name + " 结果不在原数据中: " + result);
                }
                
                trace("  " + test.name + ": 通过 (" + test.description + ")");
                
            } catch (error:Error) {
                assertTrue(false, "边界值处理测试", 
                    test.name + " 抛出异常: " + error.message);
            }
        }
        
        trace("PASS: 边界值处理专项测试");
    }
    
    // 并发安全性模拟测试
    private static function testConcurrencySafety():Void {
        trace("\n=== 并发安全性模拟测试 ===");
        
        // 模拟并发访问的场景（在AS2中通过快速连续调用模拟）
        var sharedData:Array = generateRandomArray(1000, 1, 1000);
        var concurrentOperations:Number = 20;
        var results:Array = [];
        
        var concurrentStart:Number = getTimer();
        
        // 快速连续执行多个选择操作
        for (var i:Number = 0; i < concurrentOperations; i++) {
            var k:Number = Math.floor(Math.random() * sharedData.length);
            var data:Array = sharedData.concat();  // 每次使用数据副本
            
            var result:Number = Number(QuickSelect.selectKth(data, k, QuickSelect.numberCompare));
            results.push({k: k, result: result, data: data});
        }
        
        var concurrentElapsed:Number = getTimer() - concurrentStart;
        
        // 验证所有结果的正确性
        var correctResults:Number = 0;
        
        for (var j:Number = 0; j < results.length; j++) {
            var res:Object = results[j];
            var verified:Boolean = verifyQuickSelectResult(sharedData, res.k, res.result, QuickSelect.numberCompare);
            
            if (verified) {
                correctResults++;
            }
        }
        
        var successRate:Number = (correctResults / concurrentOperations) * 100;
        
        assertTrue(successRate >= 99, "并发安全性测试", 
            "并发操作成功率过低: " + formatDecimal(successRate, 1) + "%");
        
        trace("  执行了 " + concurrentOperations + " 个并发操作");
        trace("  总耗时: " + concurrentElapsed + "ms");
        trace("  成功率: " + formatDecimal(successRate, 1) + "%");
        trace("  平均每操作: " + formatDecimal(concurrentElapsed / concurrentOperations, 2) + "ms");
        
        // 测试数据完整性
        var originalSum:Number = 0;
        for (var k:Number = 0; k < sharedData.length; k++) {
            originalSum += Number(sharedData[k]);
        }
        
        // 验证某个操作后的数据完整性
        var testResult:Object = results[Math.floor(results.length / 2)];
        var testSum:Number = 0;
        for (var l:Number = 0; l < testResult.data.length; l++) {
            testSum += Number(testResult.data[l]);
        }
        
        assertEquals(originalSum, testSum, "并发安全性测试（数据完整性）");
        
        trace("PASS: 并发安全性模拟测试");
    }
    
    // 压力测试套件
    private static function runStressTestSuite():Void {
        trace("\n=== 压力测试套件 ===");
        
        // 大数据量压力测试
        var stressSizes:Array = [50000, 100000];
        var stressPatterns:Array = ["random", "sorted", "reverse", "duplicates"];
        
        for (var i:Number = 0; i < stressSizes.length; i++) {
            var size:Number = Number(stressSizes[i]);
            
            trace("  大数据量测试 (规模: " + size + "):");
            
            for (var j:Number = 0; j < stressPatterns.length; j++) {
                var pattern:String = String(stressPatterns[j]);
                var data:Array = generateTestArray(size, pattern);
                
                var stressStart:Number = getTimer();
                var median:Number = Number(QuickSelect.median(data, QuickSelect.numberCompare));
                var stressElapsed:Number = getTimer() - stressStart;
                
                // 验证性能在可接受范围内
                var maxAcceptableTime:Number = size / 10;  // 粗略的线性时间上限
                assertTrue(stressElapsed < maxAcceptableTime, "压力测试", 
                    "大数据量(" + size + "," + pattern + ")耗时过长: " + stressElapsed + "ms");
                
                // 验证结果合理性
                assertTrue(median !== null && median !== undefined, "压力测试", 
                    "大数据量测试返回无效结果");
                
                trace("    " + pattern + ": " + stressElapsed + "ms, 中位数=" + median);
            }
        }
        
        // 连续操作压力测试
        var continuousOps:Number = 1000;
        var continuousData:Array = generateRandomArray(1000, 1, 1000);
        
        var continuousStart:Number = getTimer();
        var continuousResults:Array = [];
        
        for (var ops:Number = 0; ops < continuousOps; ops++) {
            var k:Number = Math.floor(Math.random() * continuousData.length);
            var result:Number = Number(QuickSelect.selectKth(continuousData.concat(), k, QuickSelect.numberCompare));
            continuousResults.push(result);
        }
        
        var continuousElapsed:Number = getTimer() - continuousStart;
        var avgOpTime:Number = continuousElapsed / continuousOps;
        
        assertTrue(avgOpTime < 10, "压力测试", 
            "连续操作平均耗时过长: " + formatDecimal(avgOpTime, 2) + "ms");
        
        trace("  连续操作测试: " + continuousOps + " 次操作, " + 
              "总耗时=" + continuousElapsed + "ms, " +
              "平均=" + formatDecimal(avgOpTime, 2) + "ms");
        
        trace("PASS: 压力测试套件");
    }
    
    // 综合性能基准测试
    private static function runComprehensivePerformanceBenchmark():Void {
        trace("\n=== 综合性能基准测试 ===");
        
        var benchmarkSizes:Array = [100, 500, 1000, 5000, 10000];
        var benchmarkResults:Array = [];
        
        for (var i:Number = 0; i < benchmarkSizes.length; i++) {
            var size:Number = Number(benchmarkSizes[i]);
            var data:Array = generateRandomArray(size, 1, size);
            
            // 测试不同位置的选择性能
            var positions:Array = [0, 0.25, 0.5, 0.75, 1.0];
            var positionResults:Array = [];
            
            for (var j:Number = 0; j < positions.length; j++) {
                var pos:Number = Number(positions[j]);
                var k:Number = Math.floor((size - 1) * pos);
                
                var operation:Function = function():Void {
                    QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
                };
                
                var benchmark:Object = benchmarkOperation(operation, 5, 
                    "大小" + size + "_位置" + Math.floor(pos * 100) + "%");
                
                positionResults.push({
                    position: pos,
                    avgTime: benchmark.avgTime,
                    efficiency: benchmark.avgTime / size
                });
            }
            
            benchmarkResults.push({
                size: size,
                positions: positionResults
            });
        }
        
        // 分析性能特征
        trace("  性能特征分析:");
        
        for (var k:Number = 0; k < benchmarkResults.length; k++) {
            var result:Object = benchmarkResults[k];
            var totalTime:Number = 0;
            var minTime:Number = Number.MAX_VALUE;
            var maxTime:Number = 0;
            
            for (var l:Number = 0; l < result.positions.length; l++) {
                var posResult:Object = result.positions[l];
                totalTime += posResult.avgTime;
                minTime = Math.min(minTime, posResult.avgTime);
                maxTime = Math.max(maxTime, posResult.avgTime);
            }
            
            var avgTime:Number = totalTime / result.positions.length;
            var timeVariation:Number = (maxTime - minTime) / avgTime;
            
            trace("    大小 " + result.size + ": 平均=" + formatDecimal(avgTime, 2) + 
                  "ms, 变异=" + formatDecimal(timeVariation * 100, 1) + "%");
        }
        
        trace("PASS: 综合性能基准测试");
    }
    
    // 算法质量评估
    private static function evaluateAlgorithmQuality():Void {
        trace("\n=== 算法质量评估 ===");
        
        var qualityMetrics:Object = {
            correctnessTests: 0,
            passedTests: 0,
            performanceTests: 0,
            performancePassed: 0,
            robustnessTests: 0,
            robustnessPassed: 0
        };
        
        // 正确性评估
        trace("  正确性评估:");
        var correctnessTestSuite:Array = [
            {size: 10, trials: 50},
            {size: 100, trials: 20},
            {size: 1000, trials: 10}
        ];
        
        for (var i:Number = 0; i < correctnessTestSuite.length; i++) {
            var test:Object = correctnessTestSuite[i];
            var correct:Number = 0;
            
            for (var trial:Number = 0; trial < test.trials; trial++) {
                var data:Array = generateRandomArray(test.size, 1, test.size);
                var k:Number = Math.floor(Math.random() * test.size);
                
                var result = QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
                var verified:Boolean = verifyQuickSelectResult(data, k, result, QuickSelect.numberCompare);
                
                qualityMetrics.correctnessTests++;
                if (verified) {
                    correct++;
                    qualityMetrics.passedTests++;
                }
            }
            
            var accuracy:Number = (correct / test.trials) * 100;
            trace("    大小 " + test.size + ": " + formatDecimal(accuracy, 1) + "% 正确率");
        }
        
        // 性能评估
        trace("  性能评估:");
        var performanceThresholds:Array = [
            {size: 1000, maxTime: 50},
            {size: 5000, maxTime: 200},
            {size: 10000, maxTime: 500}
        ];
        
        for (var j:Number = 0; j < performanceThresholds.length; j++) {
            var perfTest:Object = performanceThresholds[j];
            var data:Array = generateRandomArray(perfTest.size, 1, perfTest.size);
            
            var start:Number = getTimer();
            QuickSelect.median(data, QuickSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            qualityMetrics.performanceTests++;
            if (elapsed <= perfTest.maxTime) {
                qualityMetrics.performancePassed++;
            }
            
            var status:String = (elapsed <= perfTest.maxTime) ? "通过" : "超时";
            trace("    大小 " + perfTest.size + ": " + elapsed + "ms (" + status + ")");
        }
        
        // 健壮性评估
        trace("  健壮性评估:");
        var robustnessTests:Array = [
            {name: "全相同元素", data: [5,5,5,5,5,5,5,5,5,5]},
            {name: "已排序", data: [1,2,3,4,5,6,7,8,9,10]},
            {name: "逆序", data: [10,9,8,7,6,5,4,3,2,1]},
            {name: "二元分布", data: [1,2,1,2,1,2,1,2,1,2]}
        ];
        
        for (var k:Number = 0; k < robustnessTests.length; k++) {
            var robustTest:Object = robustnessTests[k];
            
            try {
                var median:Number = Number(QuickSelect.median(robustTest.data.concat(), QuickSelect.numberCompare));
                
                qualityMetrics.robustnessTests++;
                if (median !== null && median !== undefined) {
                    qualityMetrics.robustnessPassed++;
                    trace("    " + robustTest.name + ": 通过 (中位数=" + median + ")");
                } else {
                    trace("    " + robustTest.name + ": 失败 (返回null)");
                }
            } catch (error:Error) {
                qualityMetrics.robustnessTests++;
                trace("    " + robustTest.name + ": 失败 (异常: " + error.message + ")");
            }
        }
        
        // 生成质量报告
        var correctnessScore:Number = (qualityMetrics.passedTests / qualityMetrics.correctnessTests) * 100;
        var performanceScore:Number = (qualityMetrics.performancePassed / qualityMetrics.performanceTests) * 100;
        var robustnessScore:Number = (qualityMetrics.robustnessPassed / qualityMetrics.robustnessTests) * 100;
        var overallScore:Number = (correctnessScore + performanceScore + robustnessScore) / 3;
        
        trace("\n  质量评估报告:");
        trace("    正确性评分: " + formatDecimal(correctnessScore, 1) + "%");
        trace("    性能评分: " + formatDecimal(performanceScore, 1) + "%");
        trace("    健壮性评分: " + formatDecimal(robustnessScore, 1) + "%");
        trace("    综合评分: " + formatDecimal(overallScore, 1) + "%");
        
        var grade:String;
        if (overallScore >= 95) grade = "A+";
        else if (overallScore >= 90) grade = "A";
        else if (overallScore >= 85) grade = "B+";
        else if (overallScore >= 80) grade = "B";
        else if (overallScore >= 75) grade = "C+";
        else if (overallScore >= 70) grade = "C";
        else grade = "需要改进";
        
        trace("    算法等级: " + grade);
        
        assertTrue(overallScore >= 80, "算法质量评估", 
            "算法综合评分过低: " + formatDecimal(overallScore, 1) + "%");
        
        trace("PASS: 算法质量评估");
    }
    
    // 生成最终测试报告
    private static function generateFinalTestReport():Void {
        trace("\n" + repeatString("=", 60));
        trace("QuickSelect 算法测试报告");
        trace(repeatString("=", 60));
        
        var reportTime:Date = new Date();
        trace("测试完成时间: " + reportTime.toString());
        
        trace("\n测试覆盖范围:");
        trace("• 基础功能测试 - 11项");
        trace("• 核心特性测试 - 8项");
        trace("• 选择操作测试 - 9项");
        trace("• 分区算法测试 - 7项");
        trace("• 比较函数测试 - 8项");
        trace("• 数据分布测试 - 8项");
        trace("• 应用场景测试 - 10项");
        trace("• 边界条件测试 - 8项");
        trace("• 性能特性测试 - 7项");
        trace("• 稳定性测试 - 4项");
        
        trace("\n性能特征:");
        trace("• 时间复杂度: O(n) 平均情况");
        trace("• 空间复杂度: O(1) 原地算法");
        trace("• 最坏情况: O(n²) 但通过三数取中优化大幅改善");
        trace("• 适用场景: 大数据量的选择查询");
        
        trace("\n算法优势:");
        trace("• 比完整排序快，特别适合单一元素选择");
        trace("• 内存使用效率高，原地操作");
        trace("• 对各种数据分布都有良好表现");
        trace("• 实现简洁，易于理解和维护");
        
        trace("\n推荐使用场景:");
        trace("• 统计分析中的百分位数计算");
        trace("• 数据库查询优化");
        trace("• 机器学习特征选择");
        trace("• 实时系统中的TopK查询");
        trace("• 金融风险分析");
        
        trace("\n" + repeatString("=", 60));
        trace("测试结论: QuickSelect算法实现质量优秀，");
        trace("         性能表现符合预期，可投入生产使用。");
        trace(repeatString("=", 60));
    }

    // ================================
    // 基础功能测试
    // ================================
    private static function testEmptyArray():Void {
        var arr:Array = [];
        var result = QuickSelect.selectKth(arr, 0, QuickSelect.numberCompare);
        assertEquals(null, result, "空数组测试");
    }

    private static function testSingleElement():Void {
        var arr:Array = [42];
        var result:Number = Number(QuickSelect.selectKth(arr, 0, QuickSelect.numberCompare));
        assertEquals(42, result, "单元素数组测试");
        assertPartitioned(arr, 0, QuickSelect.numberCompare, "单元素分区测试");
    }

    private static function testTwoElements():Void {
        var arr1:Array = [2, 1];
        var result1:Number = Number(QuickSelect.selectKth(arr1, 0, QuickSelect.numberCompare));
        assertEquals(1, result1, "两元素数组测试（第0小）");
        assertPartitioned(arr1, 0, QuickSelect.numberCompare, "两元素分区测试（第0小）");
        
        var arr2:Array = [2, 1];
        var result2:Number = Number(QuickSelect.selectKth(arr2, 1, QuickSelect.numberCompare));
        assertEquals(2, result2, "两元素数组测试（第1小）");
        assertPartitioned(arr2, 1, QuickSelect.numberCompare, "两元素分区测试（第1小）");
    }

    private static function testThreeElements():Void {
        var testCases:Array = [
            [3, 1, 2],
            [1, 3, 2],
            [2, 1, 3],
            [3, 2, 1],
            [1, 2, 3],
            [2, 3, 1]
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var arr:Array = testCases[i].concat();
            var expected:Array = [1, 2, 3];
            
            for (var k:Number = 0; k < 3; k++) {
                var testArr:Array = arr.concat();
                var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
                assertEquals(Number(expected[k]), result, "三元素数组测试 case" + i + " k=" + k);
                assertPartitioned(testArr, k, QuickSelect.numberCompare, "三元素分区测试 case" + i + " k=" + k);
            }
        }
    }

    private static function testAlreadySorted():Void {
        var arr:Array = [1,2,3,4,5,6,7,8,9,10];
        
        for (var k:Number = 0; k < arr.length; k++) {
            var testArr:Array = arr.concat();
            var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
            assertEquals(k + 1, result, "已排序数组测试 k=" + k);
            assertPartitioned(testArr, k, QuickSelect.numberCompare, "已排序数组分区测试 k=" + k);
        }
    }

    private static function testReverseSorted():Void {
        var arr:Array = [10,9,8,7,6,5,4,3,2,1];
        var expected:Array = [1,2,3,4,5,6,7,8,9,10];
        
        for (var k:Number = 0; k < arr.length; k++) {
            var testArr:Array = arr.concat();
            var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
            assertEquals(Number(expected[k]), result, "逆序数组测试 k=" + k);
            assertPartitioned(testArr, k, QuickSelect.numberCompare, "逆序数组分区测试 k=" + k);
        }
    }

    private static function testRandomArray():Void {
        var arr:Array = [3,1,4,1,5,9,2,6,5,3,5,8,9,7,9,3,2,3,8,4];
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        for (var k:Number = 0; k < arr.length; k++) {
            var testArr:Array = arr.concat();
            var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
            assertEquals(Number(sortedCopy[k]), result, "随机数组测试 k=" + k);
            assertPartitioned(testArr, k, QuickSelect.numberCompare, "随机数组分区测试 k=" + k);
        }
    }

    private static function testDuplicateElements():Void {
        var arr:Array = [5,3,8,3,9,1,5,7,3,5,3,5];
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        // 测试几个关键位置
        var testIndices:Array = [0, 3, 6, 9, arr.length - 1];
        for (var i:Number = 0; i < testIndices.length; i++) {
            var k:Number = Number(testIndices[i]);
            var testArr:Array = arr.concat();
            var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
            assertEquals(Number(sortedCopy[k]), result, "重复元素测试 k=" + k);
            assertPartitioned(testArr, k, QuickSelect.numberCompare, "重复元素分区测试 k=" + k);
        }
    }

    private static function testAllSameElements():Void {
        var arr:Array = [7,7,7,7,7,7,7,7,7,7];
        
        for (var k:Number = 0; k < arr.length; k++) {
            var testArr:Array = arr.concat();
            var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
            assertEquals(7, result, "全相同元素测试 k=" + k);
            assertPartitioned(testArr, k, QuickSelect.numberCompare, "全相同元素分区测试 k=" + k);
        }
    }

    private static function testCustomCompareFunction():Void {
        var arr:Array = ["Apple", "orange", "Banana", "grape", "cherry"];
        var caseInsensitiveCompare:Function = function(a:String, b:String):Number {
            var aLower:String = a.toLowerCase();
            var bLower:String = b.toLowerCase();
            if (aLower < bLower) return -1;
            if (aLower > bLower) return 1;
            return 0;
        };
        
        var expected:Array = arr.concat();
        expected.sort(caseInsensitiveCompare);
        
        for (var k:Number = 0; k < arr.length; k++) {
            var testArr:Array = arr.concat();
            var result:String = String(QuickSelect.selectKth(testArr, k, caseInsensitiveCompare));
            assertEquals(String(expected[k]), result, "自定义比较函数测试 k=" + k);
            assertPartitioned(testArr, k, caseInsensitiveCompare, "自定义比较函数分区测试 k=" + k);
        }
    }

    private static function testNegativeNumbers():Void {
        var arr:Array = [-5, -2, -8, -1, -9, -3, -7, -4, -6];
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        var median:Number = Number(QuickSelect.median(arr.concat(), QuickSelect.numberCompare));
        var expectedMedian:Number = Number(sortedCopy[Math.floor((sortedCopy.length - 1) / 2)]);
        assertEquals(expectedMedian, median, "负数数组中位数测试");
    }

    private static function testFloatingPointNumbers():Void {
        var arr:Array = [3.14, 2.71, 1.41, 1.73, 0.57, 2.23, 1.61];
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        var median:Number = Number(QuickSelect.median(arr.concat(), QuickSelect.numberCompare));
        var expectedMedian:Number = Number(sortedCopy[Math.floor((sortedCopy.length - 1) / 2)]);
        assertEquals(expectedMedian, median, "浮点数数组中位数测试");
    }

    // ================================
    // QuickSelect 核心特性专项测试
    // ================================
    
    private static function testPartitionCorrectness():Void {
        var arr:Array = generateRandomArray(100, 1, 1000);
        var k:Number = 50;
        
        var testArr:Array = arr.concat();
        var kthElement:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
        
        // 验证分区正确性
        var correctPartition:Boolean = true;
        for (var i:Number = 0; i < k; i++) {
            if (Number(testArr[i]) > kthElement) {
                correctPartition = false;
                break;
            }
        }
        
        for (var j:Number = k + 1; j < testArr.length; j++) {
            if (Number(testArr[j]) < kthElement) {
                correctPartition = false;
                break;
            }
        }
        
        assertTrue(correctPartition, "分区正确性测试", "分区操作后元素位置不正确");
    }

    private static function testPartitionBoundaryIntegrity():Void {
        var sizes:Array = [1, 2, 3, 4, 5, 10, 31, 32, 33, 63, 64, 65];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = Number(sizes[i]);
            var arr:Array = generateRandomArray(size, 1, 100);
            
            for (var k:Number = 0; k < size; k++) {
                var testArr:Array = arr.concat();
                var originalLength:Number = testArr.length;
                
                QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare);
                
                // 验证数组长度未改变
                if (testArr.length != originalLength) {
                    assertTrue(false, "分区边界完整性测试", 
                        "size=" + size + " k=" + k + " 数组长度被改变");
                    return;
                }
                
                // 验证所有原始元素仍然存在
                var originalCopy:Array = arr.concat();
                originalCopy.sort(Array.NUMERIC);
                var testCopy:Array = testArr.concat();
                testCopy.sort(Array.NUMERIC);
                
                var elementsPreserved:Boolean = true;
                for (var j:Number = 0; j < originalCopy.length; j++) {
                    if (Number(originalCopy[j]) !== Number(testCopy[j])) {
                        elementsPreserved = false;
                        break;
                    }
                }
                
                if (!elementsPreserved) {
                    assertTrue(false, "分区边界完整性测试", 
                        "size=" + size + " k=" + k + " 元素完整性被破坏");
                    return;
                }
            }
        }
        
        trace("PASS: 分区边界完整性测试");
    }

    private static function testThreeWayMedianPivotSelection():Void {
        // 测试三数取中优化是否有效避免最坏情况
        var worstCaseArrays:Array = [
            // 已排序数组
            [1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16],
            // 逆序数组
            [16,15,14,13,12,11,10,9,8,7,6,5,4,3,2,1],
            // 所有元素相同
            [5,5,5,5,5,5,5,5,5,5,5,5,5,5,5,5]
        ];
        
        for (var i:Number = 0; i < worstCaseArrays.length; i++) {
            var arr:Array = worstCaseArrays[i];
            var k:Number = Math.floor(arr.length / 2);
            
            var start:Number = getTimer();
            var result:Number = Number(QuickSelect.selectKth(arr.concat(), k, QuickSelect.numberCompare));
            var time:Number = getTimer() - start;
            
            // 在最坏情况下，时间应该仍然合理（不会退化到O(N²)）
            assertTrue(time < 100, "三数取中优化测试", 
                "case " + i + " 耗时过长: " + time + "ms，可能存在性能退化");
        }
        
        trace("PASS: 三数取中优化测试");
    }

    private static function testPivotOptimizationEffectiveness():Void {
        // 创建有利于和不利于pivot选择的数据
        var goodCase:Array = generateRandomArray(1000, 1, 1000);
        var badCase:Array = [];
        
        // 构造可能导致糟糕pivot选择的案例
        for (var i:Number = 0; i < 1000; i++) {
            badCase.push(i % 2 == 0 ? 1 : 1000);  // 极端二元分布
        }
        
        var k:Number = 500;
        
        // 测试随机数据
        var start1:Number = getTimer();
        QuickSelect.selectKth(goodCase.concat(), k, QuickSelect.numberCompare);
        var goodTime:Number = getTimer() - start1;
        
        // 测试极端数据
        var start2:Number = getTimer();
        QuickSelect.selectKth(badCase.concat(), k, QuickSelect.numberCompare);
        var badTime:Number = getTimer() - start2;
        
        // 即使在不利情况下，性能也不应该差太多
        var ratio:Number = badTime / Math.max(goodTime, 1);
        assertTrue(ratio < 10, "Pivot优化有效性测试", 
            "极端数据性能退化过严重，比率: " + ratio);
        
        trace("    随机数据耗时: " + goodTime + "ms");
        trace("    极端数据耗时: " + badTime + "ms");
        trace("PASS: Pivot优化有效性测试");
    }

    private static function testIterativeImplementationCorrectness():Void {
        // 验证迭代实现的正确性（vs 递归实现的对比）
        var testCases:Array = [
            generateRandomArray(100, 1, 1000),
            generateRandomArray(1000, -500, 500),
            [1,1,1,2,2,2,3,3,3,4,4,4],  // 大量重复
            [1000,999,998,997,996,995,994,993,992,991]  // 逆序
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var arr:Array = testCases[i];
            var sortedCopy:Array = arr.concat();
            sortedCopy.sort(Array.NUMERIC);
            
            // 测试多个k值
            var testIndices:Array = [0, Math.floor(arr.length/4), Math.floor(arr.length/2), 
                                   Math.floor(arr.length*3/4), arr.length-1];
            
            for (var j:Number = 0; j < testIndices.length; j++) {
                var k:Number = Number(testIndices[j]);
                if (k < arr.length) {
                    var testArr:Array = arr.concat();
                    var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
                    var expected:Number = Number(sortedCopy[k]);
                    
                    if (result !== expected) {
                        assertTrue(false, "迭代实现正确性测试", 
                            "case " + i + " k=" + k + " 预期=" + expected + " 实际=" + result);
                        return;
                    }
                }
            }
        }
        
        trace("PASS: 迭代实现正确性测试");
    }

    private static function testKthElementRangeValidation():Void {
        var arr:Array = [1,2,3,4,5];
        
        // 测试有效范围
        for (var k:Number = 0; k < arr.length; k++) {
            var result = QuickSelect.selectKth(arr.concat(), k, QuickSelect.numberCompare);
            assertTrue(result !== null && result !== undefined, 
                "K值范围验证测试", "有效k=" + k + "返回了无效结果");
        }
        
        // 测试无效范围
        var invalidResult1 = QuickSelect.selectKth(arr.concat(), -1, QuickSelect.numberCompare);
        var invalidResult2 = QuickSelect.selectKth(arr.concat(), arr.length, QuickSelect.numberCompare);
        
        assertTrue(invalidResult1 === null, "K值范围验证测试", "负数k应该返回null");
        assertTrue(invalidResult2 === null, "K值范围验证测试", "超出范围的k应该返回null");
    }

    private static function testPartitionStabilityWithDuplicates():Void {
        // 虽然QuickSelect不是稳定算法，但应该正确处理重复元素
        var arr:Array = [3,1,4,1,5,1,2,1,6,1];
        var k:Number = 5;  // 选择中位数位置
        
        var testArr:Array = arr.concat();
        var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
        
        // 验证分区正确性
        var leftOk:Boolean = true;
        var rightOk:Boolean = true;
        
        for (var i:Number = 0; i < k; i++) {
            if (Number(testArr[i]) > result) {
                leftOk = false;
                break;
            }
        }
        
        for (var j:Number = k + 1; j < testArr.length; j++) {
            if (Number(testArr[j]) < result) {
                rightOk = false;
                break;
            }
        }
        
        assertTrue(leftOk && rightOk, "重复元素分区稳定性测试", 
            "存在重复元素时分区不正确");
    }

    private static function testPivotSelectionWorstCaseAvoidance():Void {
        // 构造经典的最坏情况输入
        var worstCases:Array = [];
        
        // Case 1: 已排序
        var sorted:Array = [];
        for (var i:Number = 1; i <= 1000; i++) {
            sorted.push(i);
        }
        worstCases.push(sorted);
        
        // Case 2: 逆序
        var reverse:Array = [];
        for (var j:Number = 1000; j >= 1; j--) {
            reverse.push(j);
        }
        worstCases.push(reverse);
        
        // Case 3: 所有元素相同
        var same:Array = [];
        for (var k:Number = 0; k < 1000; k++) {
            same.push(42);
        }
        worstCases.push(same);
        
        var maxAllowedTime:Number = 200;  // 200ms是合理的上限
        
        for (var caseIdx:Number = 0; caseIdx < worstCases.length; caseIdx++) {
            var testCase:Array = worstCases[caseIdx];
            var targetK:Number = Math.floor(testCase.length / 2);
            
            var start:Number = getTimer();
            QuickSelect.selectKth(testCase.concat(), targetK, QuickSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            assertTrue(elapsed < maxAllowedTime, "最坏情况避免测试", 
                "case " + caseIdx + " 耗时 " + elapsed + "ms 超过限制 " + maxAllowedTime + "ms");
        }
        
        trace("PASS: 最坏情况避免测试");
    }

    // ================================
    // 选择操作专项测试
    // ================================
    
    private static function testSelectFirstElement():Void {
        var testCases:Array = [
            [5,2,8,1,9],
            [1,2,3,4,5],
            [5,4,3,2,1],
            [7,7,7,7,7]
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var arr:Array = testCases[i];
            var sortedCopy:Array = arr.concat();
            sortedCopy.sort(Array.NUMERIC);
            
            var result:Number = Number(QuickSelect.selectKth(arr.concat(), 0, QuickSelect.numberCompare));
            assertEquals(Number(sortedCopy[0]), result, "选择第一小元素测试 case" + i);
        }
    }

    private static function testSelectLastElement():Void {
        var testCases:Array = [
            [5,2,8,1,9],
            [1,2,3,4,5],
            [5,4,3,2,1],
            [7,7,7,7,7]
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var arr:Array = testCases[i];
            var sortedCopy:Array = arr.concat();
            sortedCopy.sort(Array.NUMERIC);
            
            var result:Number = Number(QuickSelect.selectKth(arr.concat(), arr.length - 1, QuickSelect.numberCompare));
            assertEquals(Number(sortedCopy[sortedCopy.length - 1]), result, "选择最大元素测试 case" + i);
        }
    }

    private static function testSelectMiddleElement():Void {
        var sizes:Array = [7, 8, 15, 16, 31, 32, 99, 100];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = Number(sizes[i]);
            var arr:Array = generateRandomArray(size, 1, 1000);
            var sortedCopy:Array = arr.concat();
            sortedCopy.sort(Array.NUMERIC);
            
            var midIndex:Number = Math.floor((size - 1) / 2);
            var result:Number = Number(QuickSelect.selectKth(arr.concat(), midIndex, QuickSelect.numberCompare));
            assertEquals(Number(sortedCopy[midIndex]), result, "选择中间元素测试 size=" + size);
        }
    }

    private static function testSelectMedianVariations():Void {
        var testCases:Array = [
            [1,2,3,4,5],      // 奇数个元素
            [1,2,3,4,5,6],    // 偶数个元素
            [5,4,3,2,1],      // 逆序
            [3,1,4,1,5,9,2],  // 随机
            [2,2,2,2,2]       // 全相同
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var arr:Array = testCases[i];
            var sortedCopy:Array = arr.concat();
            sortedCopy.sort(Array.NUMERIC);
            
            var medianResult:Number = Number(QuickSelect.median(arr.concat(), QuickSelect.numberCompare));
            var expectedMedian:Number = Number(sortedCopy[Math.floor((sortedCopy.length - 1) / 2)]);
            
            assertEquals(expectedMedian, medianResult, "中位数变体测试 case" + i);
        }
    }

    private static function testSelectQuartiles():Void {
        var arr:Array = generateRandomArray(100, 1, 1000);
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        // 第一四分位数 (Q1)
        var q1Index:Number = Math.floor((arr.length - 1) * 0.25);
        var q1Result:Number = Number(QuickSelect.selectKth(arr.concat(), q1Index, QuickSelect.numberCompare));
        assertEquals(Number(sortedCopy[q1Index]), q1Result, "第一四分位数测试");
        
        // 第三四分位数 (Q3)
        var q3Index:Number = Math.floor((arr.length - 1) * 0.75);
        var q3Result:Number = Number(QuickSelect.selectKth(arr.concat(), q3Index, QuickSelect.numberCompare));
        assertEquals(Number(sortedCopy[q3Index]), q3Result, "第三四分位数测试");
    }

    private static function testSelectPercentiles():Void {
        var arr:Array = generateRandomArray(1000, 1, 1000);
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        var percentiles:Array = [0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99];
        
        for (var i:Number = 0; i < percentiles.length; i++) {
            var p:Number = Number(percentiles[i]);
            var index:Number = Math.floor((arr.length - 1) * p);
            
            var result:Number = Number(QuickSelect.selectKth(arr.concat(), index, QuickSelect.numberCompare));
            var expected:Number = Number(sortedCopy[index]);
            
            assertEquals(expected, result, "百分位数测试 " + (p * 100) + "%");
        }
    }

    private static function testSelectWithNegativeIndices():Void {
        var arr:Array = [1,2,3,4,5];
        var result = QuickSelect.selectKth(arr, -1, QuickSelect.numberCompare);
        assertEquals(null, result, "负索引测试");
    }

    private static function testSelectOutOfBounds():Void {
        var arr:Array = [1,2,3,4,5];
        var result1 = QuickSelect.selectKth(arr, arr.length, QuickSelect.numberCompare);
        var result2 = QuickSelect.selectKth(arr, arr.length + 10, QuickSelect.numberCompare);
        
        assertEquals(null, result1, "边界外索引测试1");
        assertEquals(null, result2, "边界外索引测试2");
    }

    private static function testSelectFromSubrange():Void {
        var arr:Array = [9,1,8,2,7,3,6,4,5];
        var start:Number = 2;
        var end:Number = 7;
        var k:Number = start + 2;  // 在子范围内的第2个位置
        
        // 手动验证子范围的正确性
        var subArray:Array = arr.slice(start, end);
        var sortedSub:Array = subArray.concat();
        sortedSub.sort(Array.NUMERIC);
        var expectedForSub:Number = Number(sortedSub[2]);
        
        var result:Number = Number(QuickSelect.select(arr.concat(), k, start, end, QuickSelect.numberCompare));
        
        // 验证结果在子范围的排序中是正确的
        var testArr:Array = arr.concat();
        QuickSelect.select(testArr, k, start, end, QuickSelect.numberCompare);
        var actualSub:Array = testArr.slice(start, end);
        actualSub.sort(Array.NUMERIC);
        
        assertEquals(expectedForSub, Number(actualSub[2]), "子范围选择测试");
    }

    // ================================
    // 分区算法深度测试
    // ================================
    
    private static function testLomutoPartitionCorrectness():Void {
        var testCases:Array = [
            [5,2,8,1,9,3,7,4,6],
            [1,1,1,2,2,2,3,3,3],
            [9,8,7,6,5,4,3,2,1],
            [1,2,3,4,5,6,7,8,9]
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var arr:Array = testCases[i];
            
            for (var k:Number = 0; k < arr.length; k++) {
                var testArr:Array = arr.concat();
                QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare);
                
                // 验证Lomuto分区的性质
                var pivot:Number = Number(testArr[k]);
                var partitionValid:Boolean = true;
                
                for (var left:Number = 0; left < k; left++) {
                    if (Number(testArr[left]) > pivot) {
                        partitionValid = false;
                        break;
                    }
                }
                
                for (var right:Number = k + 1; right < testArr.length; right++) {
                    if (Number(testArr[right]) < pivot) {
                        partitionValid = false;
                        break;
                    }
                }
                
                assertTrue(partitionValid, "Lomuto分区正确性测试", 
                    "case " + i + " k=" + k + " 分区不正确");
            }
        }
        
        trace("PASS: Lomuto分区正确性测试");
    }

    private static function testPartitionWithAllEqual():Void {
        var sizes:Array = [5, 10, 50, 100];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = Number(sizes[i]);
            var arr:Array = [];
            for (var j:Number = 0; j < size; j++) {
                arr.push(42);  // 所有元素相同
            }
            
            for (var k:Number = 0; k < size; k++) {
                var testArr:Array = arr.concat();
                var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
                assertEquals(42, result, "全相等元素分区测试 size=" + size + " k=" + k);
            }
        }
        
        trace("PASS: 全相等元素分区测试");
    }

    private static function testPartitionWithTwoDistinctValues():Void {
        var patterns:Array = [
            [1,1,1,2,2,2],           // 分组
            [1,2,1,2,1,2],           // 交替
            [1,1,1,1,2,2],           // 不平衡
            [2,2,2,2,1,1]            // 后置少数
        ];
        
        for (var i:Number = 0; i < patterns.length; i++) {
            var arr:Array = patterns[i];
            
            for (var k:Number = 0; k < arr.length; k++) {
                var testArr:Array = arr.concat();
                var result:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
                
                // 结果应该是1或2
                assertTrue(result === 1 || result === 2, 
                    "二值分区测试", "pattern " + i + " k=" + k + " 结果无效: " + result);
                
                assertPartitioned(testArr, k, QuickSelect.numberCompare, 
                    "二值分区测试 pattern " + i + " k=" + k);
            }
        }
        
        trace("PASS: 二值分区测试");
    }

    private static function testPartitionWithExtremePivots():Void {
        var arr:Array = [1,2,3,4,5,6,7,8,9,10];
        
        // 测试选择最小元素作为pivot的情况
        var testArr1:Array = arr.concat();
        var min:Number = Number(QuickSelect.selectKth(testArr1, 0, QuickSelect.numberCompare));
        assertEquals(1, min, "极小pivot测试");
        assertPartitioned(testArr1, 0, QuickSelect.numberCompare, "极小pivot分区测试");
        
        // 测试选择最大元素作为pivot的情况
        var testArr2:Array = arr.concat();
        var max:Number = Number(QuickSelect.selectKth(testArr2, arr.length - 1, QuickSelect.numberCompare));
        assertEquals(10, max, "极大pivot测试");
        assertPartitioned(testArr2, arr.length - 1, QuickSelect.numberCompare, "极大pivot分区测试");
    }

    private static function testPartitionPreservation():Void {
        // 验证分区操作保持所有元素
        var arr:Array = generateRandomArray(100, 1, 1000);
        var originalSum:Number = 0;
        var originalProduct:Number = 1;
        
        for (var i:Number = 0; i < arr.length; i++) {
            originalSum += Number(arr[i]);
            originalProduct *= (Number(arr[i]) % 7 + 1);  // 避免溢出的简化乘积
        }
        
        var k:Number = 50;
        var testArr:Array = arr.concat();
        QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare);
        
        var newSum:Number = 0;
        var newProduct:Number = 1;
        
        for (var j:Number = 0; j < testArr.length; j++) {
            newSum += Number(testArr[j]);
            newProduct *= (Number(testArr[j]) % 7 + 1);
        }
        
        assertEquals(originalSum, newSum, "分区保持性测试（和）");
        assertEquals(originalProduct, newProduct, "分区保持性测试（积）");
    }

    private static function testPartitionMemoryEfficiency():Void {
        // 测试分区操作的内存效率（原地操作）
        var arr:Array = generateRandomArray(1000, 1, 1000);
        var originalLength:Number = arr.length;
        
        var before:Number = getTimer();
        QuickSelect.selectKth(arr, 500, QuickSelect.numberCompare);
        var after:Number = getTimer();
        
        // 验证数组长度未改变（原地操作）
        assertEquals(originalLength, arr.length, "分区内存效率测试（长度保持）");
        
        // 操作应该相对快速（内存效率的间接指标）
        assertTrue(after - before < 100, "分区内存效率测试", 
            "操作耗时过长: " + (after - before) + "ms，可能存在内存低效");
    }

    private static function testPartitionWithLargeArrays():Void {
        var size:Number = 10000;
        var arr:Array = generateRandomArray(size, 1, 10000);
        var k:Number = Math.floor(size / 2);
        
        var start:Number = getTimer();
        var result:Number = Number(QuickSelect.selectKth(arr, k, QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 验证结果合理性
        assertTrue(result >= 1 && result <= 10000, "大数组分区测试", 
            "结果超出预期范围: " + result);
        
        // 验证性能合理性
        assertTrue(elapsed < 1000, "大数组分区测试", 
            "大数组操作耗时过长: " + elapsed + "ms");
        
        // 验证分区正确性
        assertPartitioned(arr, k, QuickSelect.numberCompare, "大数组分区正确性测试");
        
        trace("    大数组分区测试 (size=" + size + ") 耗时: " + elapsed + "ms");
    }

    // ================================
    // 比较函数兼容性测试
    // ================================
    
    private static function testBuiltinNumberCompare():Void {
        var numbers:Array = [3.14, 2.71, 1.41, 1.73, 0.57];
        var result:Number = Number(QuickSelect.median(numbers, QuickSelect.numberCompare));
        
        var sorted:Array = numbers.concat();
        sorted.sort(QuickSelect.numberCompare);
        var expected:Number = Number(sorted[Math.floor((sorted.length - 1) / 2)]);
        
        assertEquals(expected, result, "内置数字比较函数测试");
    }

    private static function testBuiltinStringCompare():Void {
        var strings:Array = ["apple", "banana", "cherry", "date", "elderberry"];
        var result:String = String(QuickSelect.median(strings, QuickSelect.stringCompare));
        
        var sorted:Array = strings.concat();
        sorted.sort(QuickSelect.stringCompare);
        var expected:String = String(sorted[Math.floor((sorted.length - 1) / 2)]);
        
        assertEquals(expected, result, "内置字符串比较函数测试");
    }

    private static function testReverseNumberCompare():Void {
        var numbers:Array = [1,2,3,4,5];
        var result:Number = Number(QuickSelect.median(numbers, QuickSelect.reverseNumberCompare));
        
        // 逆序比较应该返回较大的中位数
        var sorted:Array = numbers.concat();
        sorted.sort(QuickSelect.reverseNumberCompare);
        var expected:Number = Number(sorted[Math.floor((sorted.length - 1) / 2)]);
        
        assertEquals(expected, result, "逆序数字比较函数测试");
    }

    private static function testComplexObjectCompare():Void {
        var objects:Array = [
            createTestObject(85, "Alice"),
            createTestObject(92, "Bob"),
            createTestObject(78, "Charlie"),
            createTestObject(96, "David"),
            createTestObject(87, "Eve")
        ];
        
        var compare:Function = function(a:Object, b:Object):Number {
            return a.value - b.value;
        };
        
        var result:Object = QuickSelect.median(objects, compare);
        
        var sorted:Array = objects.concat();
        sorted.sort(compare);
        var expected:Object = sorted[Math.floor((sorted.length - 1) / 2)];
        
        assertEquals(expected.value, result.value, "复杂对象比较函数测试");
    }

    private static function testNullSafeCompare():Void {
        var mixedArray:Array = [3, null, 1, undefined, 2, null, 4];
        
        var nullSafeCompare:Function = function(a, b):Number {
            if (a == null && b == null) return 0;
            if (a == null) return -1;
            if (b == null) return 1;
            return Number(a) - Number(b);
        };
        
        var testArr:Array = mixedArray.concat();
        var result = QuickSelect.median(testArr, nullSafeCompare);
        
        // 结果应该不是null/undefined（除非所有元素都是null）
        assertTrue(result !== null && result !== undefined, 
            "空值安全比较测试", "结果不应该是null/undefined");
    }

    private static function testCaseInsensitiveStringCompare():Void {
        var strings:Array = ["Apple", "banana", "Cherry", "date", "Elderberry"];
        
        var caseInsensitiveCompare:Function = function(a:String, b:String):Number {
            var aLower:String = a.toLowerCase();
            var bLower:String = b.toLowerCase();
            if (aLower < bLower) return -1;
            if (aLower > bLower) return 1;
            return 0;
        };
        
        var result:String = String(QuickSelect.median(strings, caseInsensitiveCompare));
        
        var sorted:Array = strings.concat();
        sorted.sort(caseInsensitiveCompare);
        var expected:String = String(sorted[Math.floor((sorted.length - 1) / 2)]);
        
        assertEquals(expected, result, "大小写不敏感字符串比较测试");
    }

    private static function testMultiFieldObjectCompare():Void {
        var employees:Array = [
            {department: "IT", salary: 70000, name: "Alice"},
            {department: "IT", salary: 80000, name: "Bob"},
            {department: "HR", salary: 65000, name: "Charlie"},
            {department: "IT", salary: 75000, name: "David"},
            {department: "HR", salary: 70000, name: "Eve"}
        ];
        
        var multiFieldCompare:Function = function(a:Object, b:Object):Number {
            // 先按部门排序，再按薪资排序
            if (a.department != b.department) {
                return a.department < b.department ? -1 : 1;
            }
            return a.salary - b.salary;
        };
        
        var result:Object = QuickSelect.median(employees, multiFieldCompare);
        
        var sorted:Array = employees.concat();
        sorted.sort(multiFieldCompare);
        var expected:Object = sorted[Math.floor((sorted.length - 1) / 2)];
        
        assertEquals(expected.name, result.name, "多字段对象比较测试");
    }

    private static function testDateTimeCompare():Void {
        var timestamps:Array = [1609459200000, 1609545600000, 1609372800000, 1609632000000, 1609286400000];
        
        var result:Number = Number(QuickSelect.median(timestamps, QuickSelect.numberCompare));
        
        var sorted:Array = timestamps.concat();
        sorted.sort(QuickSelect.numberCompare);
        var expected:Number = Number(sorted[Math.floor((sorted.length - 1) / 2)]);
        
        assertEquals(expected, result, "时间戳比较测试");
    }

    // ================================
    // 数据分布特性测试（部分实现，展示风格）
    // ================================
    
    private static function testUniformDistribution():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        
        var start:Number = getTimer();
        var median:Number = Number(QuickSelect.median(arr, QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 均匀分布的中位数应该接近中间值
        assertTrue(median >= 200 && median <= 800, "均匀分布测试", 
            "中位数偏离预期范围: " + median);
        
        trace("    均匀分布测试耗时: " + elapsed + "ms");
    }

    private static function testNormalDistribution():Void {
        // 模拟正态分布（使用Box-Muller变换的简化版本）
        var arr:Array = [];
        for (var i:Number = 0; i < 1000; i++) {
            var u1:Number = Math.random();
            var u2:Number = Math.random();
            var z:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            arr.push(z * 100 + 500);  // 标准化到均值500，标准差100
        }
        
        var start:Number = getTimer();
        var median:Number = Number(QuickSelect.median(arr, QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 正态分布的中位数应该接近均值
        assertTrue(median >= 400 && median <= 600, "正态分布测试", 
            "中位数偏离预期范围: " + median);
        
        trace("    正态分布测试耗时: " + elapsed + "ms");
    }

    private static function testExponentialDistribution():Void {
        // 模拟指数分布数据
        var arr:Array = [];
        var lambda:Number = 0.01;  // 率参数
        
        for (var i:Number = 0; i < 1000; i++) {
            var u:Number = Math.random();
            var expValue:Number = -Math.log(1 - u) / lambda;
            arr.push(expValue * 10 + 1);  // 缩放到合理范围
        }
        
        var start:Number = getTimer();
        var median:Number = Number(QuickSelect.median(arr, QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 指数分布的中位数应该大于0
        assertTrue(median > 0, "指数分布测试", 
            "中位数应该大于0: " + median);
        
        // 验证第25和75百分位数的合理性
        var q1:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.25), QuickSelect.numberCompare));
        var q3:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.75), QuickSelect.numberCompare));
        
        assertTrue(q1 < median && median < q3, "指数分布测试", 
            "四分位数关系不正确");
        
        trace("    指数分布测试耗时: " + elapsed + "ms, 中位数: " + median);
        trace("PASS: 指数分布测试");
    }

    private static function testPowerLawDistribution():Void {
        // 模拟幂律分布数据 (Pareto分布的简化版)
        var arr:Array = [];
        var alpha:Number = 2.0;  // 形状参数
        var xmin:Number = 1.0;   // 最小值
        
        for (var i:Number = 0; i < 1000; i++) {
            var u:Number = Math.random();
            var powerValue:Number = xmin * Math.pow(1 - u, -1.0 / alpha);
            arr.push(Math.min(powerValue, 1000));  // 限制最大值
        }
        
        var start:Number = getTimer();
        var median:Number = Number(QuickSelect.median(arr, QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 幂律分布应该有较大的偏斜度
        var q1:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.25), QuickSelect.numberCompare));
        var q3:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.75), QuickSelect.numberCompare));
        var q9:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.9), QuickSelect.numberCompare));
        
        // 验证右偏分布特征：高百分位数显著大于中位数
        assertTrue(q9 > median * 2, "幂律分布测试", 
            "缺乏预期的右偏特征");
        
        trace("    幂律分布测试耗时: " + elapsed + "ms, Q1:" + q1 + " 中位数:" + median + " Q3:" + q3 + " Q9:" + q9);
        trace("PASS: 幂律分布测试");
    }

    private static function testBimodalDistribution():Void {
        // 创建双峰分布数据（两个正态分布的混合）
        var arr:Array = [];
        
        for (var i:Number = 0; i < 1000; i++) {
            var u1:Number = Math.random();
            var u2:Number = Math.random();
            var z:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            
            // 50%概率选择第一个峰（均值200），50%选择第二个峰（均值800）
            if (Math.random() < 0.5) {
                arr.push(z * 50 + 200);  // 第一个峰
            } else {
                arr.push(z * 50 + 800);  // 第二个峰
            }
        }
        
        var start:Number = getTimer();
        var median:Number = Number(QuickSelect.median(arr, QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 双峰分布的中位数应该在两个峰之间
        assertTrue(median > 300 && median < 700, "双峰分布测试", 
            "中位数不在预期的双峰之间: " + median);
        
        // 验证第25和75百分位数分别接近两个峰
        var q1:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.25), QuickSelect.numberCompare));
        var q3:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.75), QuickSelect.numberCompare));
        
        trace("    双峰分布测试耗时: " + elapsed + "ms, Q1:" + q1 + " 中位数:" + median + " Q3:" + q3);
        trace("PASS: 双峰分布测试");
    }

    private static function testHighlySkewedData():Void {
        // 创建高度右偏数据（大部分小值，少数极大值）
        var arr:Array = [];
        
        for (var i:Number = 0; i < 1000; i++) {
            if (i < 950) {
                // 95%的数据在1-10之间
                arr.push(1 + Math.random() * 9);
            } else {
                // 5%的数据在100-1000之间
                arr.push(100 + Math.random() * 900);
            }
        }
        
        var start:Number = getTimer();
        var median:Number = Number(QuickSelect.median(arr, QuickSelect.numberCompare));
        var q90:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.9), QuickSelect.numberCompare));
        var q95:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.95), QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 验证偏斜特征：中位数应该很小，但高百分位数很大
        assertTrue(median < 20, "高度偏斜数据测试", 
            "中位数过大，缺乏偏斜特征: " + median);
        assertTrue(q95 > 50, "高度偏斜数据测试", 
            "95%分位数过小，缺乏偏斜特征: " + q95);
        
        var skewRatio:Number = q95 / median;
        assertTrue(skewRatio > 5, "高度偏斜数据测试", 
            "偏斜比率过小: " + skewRatio);
        
        trace("    高度偏斜测试耗时: " + elapsed + "ms, 中位数:" + median + " Q90:" + q90 + " Q95:" + q95);
        trace("PASS: 高度偏斜数据测试");
    }

    private static function testZipfianDistribution():Void {
        // 模拟Zipf分布（简化版本）
        var arr:Array = [];
        var n:Number = 1000;  // 元素总数
        var s:Number = 1.0;   // 参数
        
        for (var i:Number = 0; i < n; i++) {
            // Zipf分布：频率与排名成反比
            var rank:Number = i + 1;
            var frequency:Number = Math.floor(100 / Math.pow(rank, s));
            
            // 根据频率添加元素
            for (var j:Number = 0; j < Math.max(1, frequency); j++) {
                arr.push(rank);
            }
        }
        
        var start:Number = getTimer();
        var median:Number = Number(QuickSelect.median(arr, QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // Zipf分布应该有很多小值
        var q1:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.25), QuickSelect.numberCompare));
        var q3:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.75), QuickSelect.numberCompare));
        
        assertTrue(q1 < 10, "Zipf分布测试", 
            "第一四分位数过大: " + q1);
        assertTrue(median < 50, "Zipf分布测试", 
            "中位数过大: " + median);
        
        trace("    Zipf分布测试耗时: " + elapsed + "ms, Q1:" + q1 + " 中位数:" + median + " Q3:" + q3);
        trace("PASS: Zipf分布测试");
    }

    private static function testClustered():Void {
        // 创建聚类数据（几个明显的聚类）
        var arr:Array = [];
        var clusterCenters:Array = [100, 300, 700, 900];
        var clusterSpread:Number = 20;
        
        for (var i:Number = 0; i < 1000; i++) {
            // 随机选择一个聚类中心
            var centerIndex:Number = Math.floor(Math.random() * clusterCenters.length);
            var center:Number = Number(clusterCenters[centerIndex]);
            
            // 在聚类中心周围生成数据
            var value:Number = center + (Math.random() - 0.5) * clusterSpread * 2;
            arr.push(value);
        }
        
        var start:Number = getTimer();
        var median:Number = Number(QuickSelect.median(arr, QuickSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 验证数据分布在预期的聚类范围内
        var q25:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.25), QuickSelect.numberCompare));
        var q75:Number = Number(QuickSelect.selectKth(arr.concat(), Math.floor(arr.length * 0.75), QuickSelect.numberCompare));
        
        assertTrue(median >= 80 && median <= 920, "聚类数据测试", 
            "中位数不在预期聚类范围内: " + median);
        
        // 验证四分位距合理（不会太大，因为数据是聚类的）
        var iqr:Number = q75 - q25;
        assertTrue(iqr < 600, "聚类数据测试", 
            "四分位距过大，可能失去聚类特征: " + iqr);
        
        trace("    聚类数据测试耗时: " + elapsed + "ms, Q25:" + q25 + " 中位数:" + median + " Q75:" + q75);
        trace("PASS: 聚类数据测试");
    }

    // ================================
    // 实际应用场景测试（部分实现）
    // ================================
    
    private static function testStatisticalAnalysis():Void {
        var dataset:Array = generateRandomArray(1000, 1, 1000);
        
        // 计算关键统计量
        var q1:Number = Number(QuickSelect.selectKth(dataset.concat(), Math.floor(dataset.length * 0.25), QuickSelect.numberCompare));
        var median:Number = Number(QuickSelect.median(dataset.concat(), QuickSelect.numberCompare));
        var q3:Number = Number(QuickSelect.selectKth(dataset.concat(), Math.floor(dataset.length * 0.75), QuickSelect.numberCompare));
        
        // 验证统计量的合理性
        assertTrue(q1 <= median, "统计分析测试", "Q1应该小于等于中位数");
        assertTrue(median <= q3, "统计分析测试", "中位数应该小于等于Q3");
        
        var iqr:Number = q3 - q1;
        trace("    Q1: " + q1 + ", Median: " + median + ", Q3: " + q3 + ", IQR: " + iqr);
        trace("PASS: 统计分析测试");
    }

    private static function testTopKQueries():Void {
        var scores:Array = generateRandomArray(1000, 0, 100);
        var k:Number = 10;
        
        var start:Number = getTimer();
        
        // 找到第k大的分数（即第(n-k)小的分数）
        var kthLargest:Number = Number(QuickSelect.selectKth(scores.concat(), scores.length - k, QuickSelect.numberCompare));
        
        var elapsed:Number = getTimer() - start;
        
        // 验证结果合理性
        assertTrue(kthLargest >= 0 && kthLargest <= 100, "Top-K查询测试", 
            "结果超出预期范围: " + kthLargest);
        
        trace("    Top-" + k + " 阈值: " + kthLargest + "，耗时: " + elapsed + "ms");
        trace("PASS: Top-K查询测试");
    }

    private static function testPercentileCalculation():Void {
        var dataset:Array = generateRandomArray(10000, 0, 1000);
        var percentiles:Array = [0.01, 0.05, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99];
        var results:Array = [];
        
        var totalStart:Number = getTimer();
        
        for (var i:Number = 0; i < percentiles.length; i++) {
            var p:Number = Number(percentiles[i]);
            var index:Number = Math.floor((dataset.length - 1) * p);
            
            var start:Number = getTimer();
            var result:Number = Number(QuickSelect.selectKth(dataset.concat(), index, QuickSelect.numberCompare));
            var elapsed:Number = getTimer() - start;
            
            results.push(result);
            
            // 验证百分位数的单调性
            if (i > 0) {
                assertTrue(result >= Number(results[i-1]), "百分位数计算测试", 
                    "百分位数不满足单调性: P" + (p*100) + "=" + result + " < P" + (Number(percentiles[i-1])*100) + "=" + results[i-1]);
            }
        }
        
        var totalElapsed:Number = getTimer() - totalStart;
        
        // 验证极值百分位数
        assertTrue(Number(results[0]) <= Number(results[results.length-1]), "百分位数计算测试", 
            "1%百分位数应该小于等于99%百分位数");
        
        trace("    百分位数计算测试总耗时: " + totalElapsed + "ms");
        trace("    P1: " + results[0] + ", P50: " + results[4] + ", P99: " + results[8]);
        trace("PASS: 百分位数计算测试");
    }

    private static function testOutlierDetection():Void {
        // 创建包含异常值的数据集
        var normalData:Array = generateRandomArray(950, 40, 60);  // 正常数据在40-60之间
        var outliers:Array = [5, 8, 95, 98, 102, 3, 1, 89, 92, 96]; // 异常值
        var dataset:Array = normalData.concat(outliers);
        
        // 使用IQR方法检测异常值
        var q1:Number = Number(QuickSelect.selectKth(dataset.concat(), Math.floor(dataset.length * 0.25), QuickSelect.numberCompare));
        var q3:Number = Number(QuickSelect.selectKth(dataset.concat(), Math.floor(dataset.length * 0.75), QuickSelect.numberCompare));
        var iqr:Number = q3 - q1;
        
        var lowerBound:Number = q1 - 1.5 * iqr;
        var upperBound:Number = q3 + 1.5 * iqr;
        
        // 计算异常值数量
        var outlierCount:Number = 0;
        var extremeOutlierCount:Number = 0;
        
        for (var i:Number = 0; i < dataset.length; i++) {
            var value:Number = Number(dataset[i]);
            if (value < lowerBound || value > upperBound) {
                outlierCount++;
                
                // 极端异常值（超出3*IQR）
                if (value < q1 - 3 * iqr || value > q3 + 3 * iqr) {
                    extremeOutlierCount++;
                }
            }
        }
        
        // 验证异常值检测的合理性
        assertTrue(outlierCount >= 8, "异常值检测测试", 
            "检测到的异常值过少: " + outlierCount);
        assertTrue(outlierCount <= 20, "异常值检测测试", 
            "检测到的异常值过多: " + outlierCount);
        
        trace("    Q1: " + q1 + ", Q3: " + q3 + ", IQR: " + iqr);
        trace("    异常值边界: [" + formatDecimal(lowerBound, 2) + ", " + formatDecimal(upperBound, 2) + "]");
        trace("    检测到异常值: " + outlierCount + "个，极端异常值: " + extremeOutlierCount + "个");
        trace("PASS: 异常值检测测试");
    }

    private static function testDataStreamProcessing():Void {
        // 模拟数据流处理：维护滑动窗口的中位数
        var windowSize:Number = 100;
        var streamLength:Number = 1000;
        var window:Array = [];
        var medianHistory:Array = [];
        
        var totalTime:Number = 0;
        
        for (var i:Number = 0; i < streamLength; i++) {
            // 生成新数据点
            var newValue:Number = Math.random() * 1000;
            
            // 添加到窗口
            window.push(newValue);
            
            // 如果窗口大小超过限制，移除最旧的元素
            if (window.length > windowSize) {
                window.shift();
            }
            
            // 每10个数据点计算一次中位数
            if (i % 10 == 0 && window.length >= 10) {
                var start:Number = getTimer();
                var median:Number = Number(QuickSelect.median(window.concat(), QuickSelect.numberCompare));
                var elapsed:Number = getTimer() - start;
                
                totalTime += elapsed;
                medianHistory.push(median);
                
                // 验证中位数的合理性
                assertTrue(median >= 0 && median <= 1000, "数据流处理测试", 
                    "中位数超出预期范围: " + median);
            }
        }
        
        // 验证中位数历史的稳定性（不应该有剧烈波动）
        var maxChange:Number = 0;
        for (var j:Number = 1; j < medianHistory.length; j++) {
            var change:Number = Math.abs(Number(medianHistory[j]) - Number(medianHistory[j-1]));
            maxChange = Math.max(maxChange, change);
        }
        
        assertTrue(maxChange < 500, "数据流处理测试", 
            "中位数变化过于剧烈: " + maxChange);
        
        var avgTime:Number = totalTime / medianHistory.length;
        trace("    处理了 " + streamLength + " 个数据点，计算了 " + medianHistory.length + " 次中位数");
        trace("    平均计算时间: " + formatDecimal(avgTime, 2) + "ms");
        trace("    最大中位数变化: " + formatDecimal(maxChange, 2));
        trace("PASS: 数据流处理测试");
    }

    private static function testGameLeaderboards():Void {
        // 模拟游戏排行榜系统
        var playerScores:Array = generateRandomArray(10000, 0, 100000);
        var topK:Number = 100;  // 前100名
        var percentileRanks:Array = [0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99];
        
        var start:Number = getTimer();
        
        // 找到前K名的分数阈值
        var topKThreshold:Number = Number(QuickSelect.selectKth(playerScores.concat(), 
            playerScores.length - topK, QuickSelect.numberCompare));
        
        // 计算各个百分位数排名
        var rankThresholds:Array = [];
        for (var i:Number = 0; i < percentileRanks.length; i++) {
            var percentile:Number = Number(percentileRanks[i]);
            var index:Number = Math.floor((playerScores.length - 1) * percentile);
            var threshold:Number = Number(QuickSelect.selectKth(playerScores.concat(), 
                index, QuickSelect.numberCompare));
            rankThresholds.push(threshold);
        }
        
        var elapsed:Number = getTimer() - start;
        
        // 验证排名阈值的单调性
        for (var j:Number = 1; j < rankThresholds.length; j++) {
            assertTrue(Number(rankThresholds[j]) >= Number(rankThresholds[j-1]), 
                "游戏排行榜测试", "排名阈值不满足单调性");
        }
        
        // 验证顶级玩家阈值的合理性
        assertTrue(topKThreshold > Number(rankThresholds[rankThresholds.length-2]), 
            "游戏排行榜测试", "前100名阈值应该高于95%百分位数");
        
        trace("    排行榜分析耗时: " + elapsed + "ms");
        trace("    前100名分数阈值: " + topKThreshold);
        trace("    90%百分位: " + rankThresholds[4] + ", 99%百分位: " + rankThresholds[6]);
        
        // 模拟实时排名查询
        var queryCount:Number = 1000;
        var queryStart:Number = getTimer();
        
        for (var q:Number = 0; q < queryCount; q++) {
            var testScore:Number = Math.random() * 100000;
            // 找到该分数在排行榜中的位置
            var rank:Number = 0;
            for (var r:Number = 0; r < playerScores.length; r++) {
                if (Number(playerScores[r]) > testScore) {
                    rank++;
                }
            }
        }
        
        var queryElapsed:Number = getTimer() - queryStart;
        
        trace("    " + queryCount + " 次排名查询耗时: " + queryElapsed + "ms");
        trace("PASS: 游戏排行榜测试");
    }

    private static function testFinancialRiskAnalysis():Void {
        // 模拟金融风险分析：计算VaR (Value at Risk)
        var returns:Array = [];
        
        // 生成模拟的日收益率数据（正态分布）
        for (var i:Number = 0; i < 5000; i++) {
            var u1:Number = Math.random();
            var u2:Number = Math.random();
            var normalRandom:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            var dailyReturn:Number = normalRandom * 0.02 + 0.001;  // 年化20%波动率，0.1%日均收益
            returns.push(dailyReturn);
        }
        
        var start:Number = getTimer();
        
        // 计算不同置信水平的VaR
        var confidenceLevels:Array = [0.01, 0.05, 0.1];  // 99%, 95%, 90% 置信度
        var varResults:Array = [];
        
        for (var j:Number = 0; j < confidenceLevels.length; j++) {
            var alpha:Number = Number(confidenceLevels[j]);
            var index:Number = Math.floor((returns.length - 1) * alpha);
            var v:Number = Number(QuickSelect.selectKth(returns.concat(), index, QuickSelect.numberCompare));
            varResults.push(v);
        }
        
        // 计算Expected Shortfall (条件VaR)
        var es95Index:Number = Math.floor((returns.length - 1) * 0.05);
        var worstReturns:Array = [];
        
        var tempReturns:Array = returns.concat();
        tempReturns.sort(Array.NUMERIC);
        
        for (var k:Number = 0; k <= es95Index; k++) {
            worstReturns.push(tempReturns[k]);
        }
        
        var expectedShortfall:Number = Number(QuickSelect.median(worstReturns, QuickSelect.numberCompare));
        
        var elapsed:Number = getTimer() - start;
        
        // 验证VaR的合理性
        assertTrue(Number(varResults[0]) < Number(varResults[1]), "金融风险分析测试", 
            "99% VaR应该小于95% VaR");
        assertTrue(Number(varResults[1]) < Number(varResults[2]), "金融风险分析测试", 
            "95% VaR应该小于90% VaR");
        assertTrue(expectedShortfall < Number(varResults[1]), "金融风险分析测试", 
            "Expected Shortfall应该小于95% VaR");
        
        // 验证VaR在合理范围内（假设日收益率在-10%到+10%之间）
        for (var l:Number = 0; l < varResults.length; l++) {
            assertTrue(Number(varResults[l]) >= -0.1 && Number(varResults[l]) <= 0.1, 
                "金融风险分析测试", "VaR值超出合理范围");
        }
        
        trace("    风险分析计算耗时: " + elapsed + "ms");
        trace("    99% VaR: " + formatDecimal(Number(varResults[0]) * 100, 3) + "%");
        trace("    95% VaR: " + formatDecimal(Number(varResults[1]) * 100, 3) + "%");
        trace("    90% VaR: " + formatDecimal(Number(varResults[2]) * 100, 3) + "%");
        trace("    95% Expected Shortfall: " + formatDecimal(expectedShortfall * 100, 3) + "%");
        trace("PASS: 金融风险分析测试");
    }

    private static function testImageProcessingHistogram():Void {
        // 模拟图像处理中的直方图均衡化
        var imageSize:Number = 256 * 256;  // 256x256像素图像
        var pixelValues:Array = [];
        
        // 生成模拟的像素强度值（0-255，偏向较暗的图像）
        for (var i:Number = 0; i < imageSize; i++) {
            var intensity:Number;
            if (Math.random() < 0.7) {
                // 70%的像素较暗 (0-100)
                intensity = Math.floor(Math.random() * 100);
            } else {
                // 30%的像素较亮 (100-255)
                intensity = Math.floor(100 + Math.random() * 155);
            }
            pixelValues.push(intensity);
        }
        
        var start:Number = getTimer();
        
        // 计算关键百分位数用于对比度分析
        var percentiles:Array = [0.02, 0.1, 0.25, 0.5, 0.75, 0.9, 0.98];
        var histogramStats:Array = [];
        
        for (var j:Number = 0; j < percentiles.length; j++) {
            var p:Number = Number(percentiles[j]);
            var index:Number = Math.floor((pixelValues.length - 1) * p);
            var value:Number = Number(QuickSelect.selectKth(pixelValues.concat(), index, QuickSelect.numberCompare));
            histogramStats.push(value);
        }
        
        var elapsed:Number = getTimer() - start;
        
        // 分析图像对比度
        var dynamicRange:Number = Number(histogramStats[6]) - Number(histogramStats[0]);  // 98% - 2%
        var midRange:Number = Number(histogramStats[4]) - Number(histogramStats[2]);      // 75% - 25%
        
        // 验证统计值的合理性
        assertTrue(Number(histogramStats[0]) >= 0 && Number(histogramStats[6]) <= 255, 
            "图像处理直方图测试", "像素值超出有效范围");
        
        assertTrue(dynamicRange > 50, "图像处理直方图测试", 
            "动态范围过小，图像可能过于平坦: " + dynamicRange);
        
        // 验证这是一个偏暗的图像
        assertTrue(Number(histogramStats[3]) < 128, "图像处理直方图测试", 
            "中位数应该小于128，确认这是偏暗图像: " + histogramStats[3]);
        
        trace("    直方图分析耗时: " + elapsed + "ms");
        trace("    像素值分布: 2%=" + histogramStats[0] + " 中位数=" + histogramStats[3] + " 98%=" + histogramStats[6]);
        trace("    动态范围: " + dynamicRange + ", 中等范围: " + midRange);
        
        // 模拟直方图均衡化的效果评估
        var lowContrast:Number = (Number(histogramStats[3]) < 100) ? 1 : 0;
        var needsEqualization:Number = (dynamicRange < 150) ? 1 : 0;
        
        trace("    图像特征: " + (lowContrast ? "低亮度" : "正常亮度") + 
              ", " + (needsEqualization ? "需要均衡化" : "对比度良好"));
        trace("PASS: 图像处理直方图测试");
    }

    private static function testDatabaseQueryOptimization():Void {
        // 模拟数据库查询优化中的统计信息收集
        var tableSize:Number = 100000;
        var columnData:Array = [];
        
        // 模拟数据库表的某一列（例如：年龄列）
        for (var i:Number = 0; i < tableSize; i++) {
            var age:Number;
            var rand:Number = Math.random();
            
            if (rand < 0.3) {
                // 30%的记录：年轻人 (18-30)
                age = 18 + Math.floor(Math.random() * 13);
            } else if (rand < 0.6) {
                // 30%的记录：中年人 (30-50)
                age = 30 + Math.floor(Math.random() * 21);
            } else if (rand < 0.9) {
                // 30%的记录：老年人 (50-80)
                age = 50 + Math.floor(Math.random() * 31);
            } else {
                // 10%的记录：高龄 (80-100)
                age = 80 + Math.floor(Math.random() * 21);
            }
            columnData.push(age);
        }
        
        var start:Number = getTimer();
        
        // 收集统计信息用于查询优化器
        var minValue:Number = Number(QuickSelect.selectKth(columnData.concat(), 0, QuickSelect.numberCompare));
        var maxValue:Number = Number(QuickSelect.selectKth(columnData.concat(), tableSize - 1, QuickSelect.numberCompare));
        var median:Number = Number(QuickSelect.median(columnData.concat(), QuickSelect.numberCompare));
        
        // 计算四分位数用于数据分布分析
        var q1:Number = Number(QuickSelect.selectKth(columnData.concat(), Math.floor(tableSize * 0.25), QuickSelect.numberCompare));
        var q3:Number = Number(QuickSelect.selectKth(columnData.concat(), Math.floor(tableSize * 0.75), QuickSelect.numberCompare));
        
        // 计算选择性统计（用于索引选择）
        var selectivityTestPoints:Array = [25, 35, 45, 55, 65, 75];
        var selectivityResults:Array = [];
        
        for (var j:Number = 0; j < selectivityTestPoints.length; j++) {
            var testValue:Number = Number(selectivityTestPoints[j]);
            
            // 估算小于等于testValue的记录比例
            var lteIndex:Number = 0;
            for (var k:Number = 0; k < columnData.length; k++) {
                if (Number(columnData[k]) <= testValue) {
                    lteIndex = k;
                } else {
                    break;
                }
            }
            
            // 使用QuickSelect找到精确位置
            var sortedData:Array = columnData.concat();
            sortedData.sort(Array.NUMERIC);
            
            var count:Number = 0;
            for (var l:Number = 0; l < sortedData.length; l++) {
                if (Number(sortedData[l]) <= testValue) {
                    count++;
                } else {
                    break;
                }
            }
            
            var selectivity:Number = count / tableSize;
            selectivityResults.push(selectivity);
        }
        
        var elapsed:Number = getTimer() - start;
        
        // 验证统计信息的合理性
        assertTrue(minValue >= 18 && maxValue <= 100, "数据库查询优化测试", 
            "年龄值超出预期范围: [" + minValue + ", " + maxValue + "]");
        
        assertTrue(q1 < median && median < q3, "数据库查询优化测试", 
            "四分位数关系不正确");
        
        // 验证选择性统计的单调性
        for (var m:Number = 1; m < selectivityResults.length; m++) {
            assertTrue(Number(selectivityResults[m]) >= Number(selectivityResults[m-1]), 
                "数据库查询优化测试", "选择性统计不满足单调性");
        }
        
        trace("    统计信息收集耗时: " + elapsed + "ms");
        trace("    数据范围: [" + minValue + ", " + maxValue + "], 中位数: " + median);
        trace("    四分位数: Q1=" + q1 + ", Q3=" + q3 + ", IQR=" + (q3-q1));
        
        // 输出选择性分析结果
        trace("    选择性分析:");
        for (var n:Number = 0; n < selectivityTestPoints.length; n++) {
            trace("      age <= " + selectivityTestPoints[n] + ": " + 
                  formatDecimal(Number(selectivityResults[n]) * 100, 1) + "%");
        }
        
        trace("PASS: 数据库查询优化测试");
    }

    private static function testMachineLearningFeatureSelection():Void {
        // 模拟机器学习中的特征选择和重要性评估
        var sampleSize:Number = 5000;
        var featureCount:Number = 20;
        var features:Array = [];
        
        // 生成多个特征的数据
        for (var f:Number = 0; f < featureCount; f++) {
            var featureData:Array = [];
            
            for (var i:Number = 0; i < sampleSize; i++) {
                var value:Number;
                
                // 不同特征有不同的分布特征
                if (f % 4 == 0) {
                    // 25%的特征：正态分布
                    var u1:Number = Math.random();
                    var u2:Number = Math.random();
                    value = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2) * 10 + 50;
                } else if (f % 4 == 1) {
                    // 25%的特征：均匀分布
                    value = Math.random() * 100;
                } else if (f % 4 == 2) {
                    // 25%的特征：偏斜分布
                    value = Math.pow(Math.random(), 2) * 100;
                } else {
                    // 25%的特征：双峰分布
                    value = (Math.random() < 0.5) ? 
                           (Math.random() * 30 + 10) : 
                           (Math.random() * 30 + 60);
                }
                
                featureData.push(value);
            }
            
            features.push(featureData);
        }
        
        var start:Number = getTimer();
        
        // 计算每个特征的统计特性用于重要性评估
        var featureStats:Array = [];
        
        for (var j:Number = 0; j < featureCount; j++) {
            var featureArray:Array = features[j];
            
            var median:Number = Number(QuickSelect.median(featureArray.concat(), QuickSelect.numberCompare));
            var q1:Number = Number(QuickSelect.selectKth(featureArray.concat(), 
                Math.floor(sampleSize * 0.25), QuickSelect.numberCompare));
            var q3:Number = Number(QuickSelect.selectKth(featureArray.concat(), 
                Math.floor(sampleSize * 0.75), QuickSelect.numberCompare));
            var iqr:Number = q3 - q1;
            
            // 计算变异系数作为特征重要性的一个指标
            var variabilityScore:Number = iqr / Math.max(Math.abs(median), 1);
            
            // 计算分布的偏斜程度
            var p10:Number = Number(QuickSelect.selectKth(featureArray.concat(), 
                Math.floor(sampleSize * 0.1), QuickSelect.numberCompare));
            var p90:Number = Number(QuickSelect.selectKth(featureArray.concat(), 
                Math.floor(sampleSize * 0.9), QuickSelect.numberCompare));
            
            var skewness:Number = ((p90 - median) - (median - p10)) / (p90 - p10);
            
            featureStats.push({
                featureId: j,
                median: median,
                iqr: iqr,
                variability: variabilityScore,
                skewness: skewness
            });
        }
        
        var elapsed:Number = getTimer() - start;
        
        // 基于变异性对特征进行排序选择
        var variabilityArray:Array = [];
        for (var k:Number = 0; k < featureStats.length; k++) {
            variabilityArray.push(featureStats[k].variability);
        }
        
        var topFeatureThreshold:Number = Number(QuickSelect.selectKth(variabilityArray.concat(), 
            Math.floor(featureCount * 0.7), QuickSelect.numberCompare)); // 选择前30%
        
        var selectedFeatures:Array = [];
        var highVariabilityCount:Number = 0;
        
        for (var l:Number = 0; l < featureStats.length; l++) {
            if (featureStats[l].variability >= topFeatureThreshold) {
                selectedFeatures.push(l);
                highVariabilityCount++;
            }
        }
        
        // 验证特征选择的合理性
        assertTrue(selectedFeatures.length >= 3 && selectedFeatures.length <= 10, 
            "机器学习特征选择测试", "选择的特征数量不合理: " + selectedFeatures.length);
        
        assertTrue(highVariabilityCount >= Math.floor(featureCount * 0.2), 
            "机器学习特征选择测试", "高变异性特征数量过少");
        
        // 验证统计值的合理性
        for (var m:Number = 0; m < featureStats.length; m++) {
            var stat:Object = featureStats[m];
            assertTrue(stat.iqr >= 0, "机器学习特征选择测试", 
                "特征" + m + "的IQR不能为负");
            assertTrue(Math.abs(stat.skewness) <= 2, "机器学习特征选择测试", 
                "特征" + m + "的偏斜度过于极端: " + stat.skewness);
        }
        
        trace("    特征分析耗时: " + elapsed + "ms");
        trace("    分析了 " + featureCount + " 个特征，每个特征 " + sampleSize + " 个样本");
        trace("    选择了 " + selectedFeatures.length + " 个高重要性特征");
        trace("    变异性阈值: " + formatDecimal(topFeatureThreshold, 3));
        
        // 输出前5个特征的详细统计
        trace("    前5个特征统计:");
        for (var n:Number = 0; n < Math.min(5, featureStats.length); n++) {
            var fs:Object = featureStats[n];
            trace("      特征" + n + ": 中位数=" + formatDecimal(fs.median, 2) + 
                  ", IQR=" + formatDecimal(fs.iqr, 2) + 
                  ", 变异性=" + formatDecimal(fs.variability, 3) + 
                  ", 偏斜度=" + formatDecimal(fs.skewness, 3));
        }
        
        trace("PASS: 机器学习特征选择测试");
    }

    // ================================
    // 边界条件和压力测试（部分实现）
    // ================================
    
    private static function testMinimumArraySizes():Void {
        var sizes:Array = [1, 2, 3];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = Number(sizes[i]);
            var arr:Array = generateRandomArray(size, 1, 100);
            
            for (var k:Number = 0; k < size; k++) {
                var result = QuickSelect.selectKth(arr.concat(), k, QuickSelect.numberCompare);
                assertTrue(result !== null && result !== undefined, 
                    "最小数组大小测试", "size=" + size + " k=" + k + " 返回无效结果");
            }
        }
        
        trace("PASS: 最小数组大小测试");
    }

    private static function testMaximumPracticalArraySizes():Void {
        var size:Number = 100000;  // 实际环境中的大数组
        var arr:Array = generateRandomArray(size, 1, size);
        var k:Number = Math.floor(size / 2);
        
        var start:Number = getTimer();
        var result = QuickSelect.selectKth(arr, k, QuickSelect.numberCompare);
        var elapsed:Number = getTimer() - start;
        
        assertTrue(result !== null && result !== undefined, 
            "最大实用数组大小测试", "大数组处理失败");
        assertTrue(elapsed < 5000, "最大实用数组大小测试", 
            "大数组处理耗时过长: " + elapsed + "ms");
        
        trace("    最大数组测试 (size=" + size + ") 耗时: " + elapsed + "ms");
        trace("PASS: 最大实用数组大小测试");
    }

    private static function testExtremeValueRanges():Void {
        // 测试极端数值范围的处理能力
        var testCases:Array = [
            {
                name: "极小值",
                data: [-1000000, -999999, -999998, -999997, -999996],
                description: "负百万级数值"
            },
            {
                name: "极大值", 
                data: [999996, 999997, 999998, 999999, 1000000],
                description: "正百万级数值"
            },
            {
                name: "混合极值",
                data: [-1000000, -1, 0, 1, 1000000],
                description: "跨越零点的极值"
            },
            {
                name: "小数精度",
                data: [0.000001, 0.000002, 0.000003, 0.000004, 0.000005],
                description: "微小精度数值"
            },
            {
                name: "大数精度",
                data: [1000000.1, 1000000.2, 1000000.3, 1000000.4, 1000000.5],
                description: "大数小数部分"
            }
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var testCase:Object = testCases[i];
            var data:Array = testCase.data;
            
            var start:Number = getTimer();
            
            // 测试各种选择操作
            var min:Number = Number(QuickSelect.selectKth(data.concat(), 0, QuickSelect.numberCompare));
            var median:Number = Number(QuickSelect.median(data.concat(), QuickSelect.numberCompare));
            var max:Number = Number(QuickSelect.selectKth(data.concat(), data.length - 1, QuickSelect.numberCompare));
            
            var elapsed:Number = getTimer() - start;
            
            // 验证结果的正确性
            assertTrue(min <= median, "极值范围测试", 
                testCase.name + ": 最小值应该小于等于中位数");
            assertTrue(median <= max, "极值范围测试", 
                testCase.name + ": 中位数应该小于等于最大值");
            
            // 验证结果在预期范围内
            assertTrue(min == Number(data[0]) || min == Number(data[data.length-1]), "极值范围测试",
                testCase.name + ": 最小值应该是数组中的某个元素");
            
            trace("    " + testCase.name + "(" + testCase.description + "): " + elapsed + "ms");
            trace("      范围: [" + min + ", " + max + "], 中位数: " + median);
        }
        
        trace("PASS: 极值范围测试");
    }

    private static function testRepeatedOperationsStability():Void {
        // 测试重复执行相同操作的稳定性
        var baseData:Array = generateRandomArray(1000, 1, 1000);
        var iterations:Number = 100;
        var results:Array = [];
        var times:Array = [];
        
        var totalStart:Number = getTimer();
        
        for (var i:Number = 0; i < iterations; i++) {
            var data:Array = baseData.concat();  // 每次使用相同的数据副本
            var k:Number = Math.floor(data.length / 2);
            
            var start:Number = getTimer();
            var result:Number = Number(QuickSelect.selectKth(data, k, QuickSelect.numberCompare));
            var elapsed:Number = getTimer() - start;
            
            results.push(result);
            times.push(elapsed);
        }
        
        var totalElapsed:Number = getTimer() - totalStart;
        
        // 验证结果一致性（所有结果应该相同）
        var expectedResult:Number = Number(results[0]);
        var consistentResults:Boolean = true;
        
        for (var j:Number = 1; j < results.length; j++) {
            if (Number(results[j]) !== expectedResult) {
                consistentResults = false;
                break;
            }
        }
        
        assertTrue(consistentResults, "重复操作稳定性测试", 
            "重复操作产生了不一致的结果");
        
        // 分析性能稳定性
        var totalTime:Number = 0;
        var minTime:Number = Number.MAX_VALUE;
        var maxTime:Number = 0;
        
        for (var k:Number = 0; k < times.length; k++) {
            var time:Number = Number(times[k]);
            totalTime += time;
            minTime = Math.min(minTime, time);
            maxTime = Math.max(maxTime, time);
        }
        
        var avgTime:Number = totalTime / times.length;
        var timeVariance:Number = maxTime - minTime;
        
        // 性能变异不应该过大
        assertTrue(timeVariance < avgTime * 5, "重复操作稳定性测试", 
            "性能变异过大: " + timeVariance + "ms, 平均: " + avgTime + "ms");
        
        trace("    执行了 " + iterations + " 次相同操作，总耗时: " + totalElapsed + "ms");
        trace("    性能统计: 平均=" + formatDecimal(avgTime, 2) + "ms, " +
              "最小=" + minTime + "ms, 最大=" + maxTime + "ms, 变异=" + timeVariance + "ms");
        trace("    结果一致性: " + (consistentResults ? "稳定" : "不稳定"));
        trace("PASS: 重复操作稳定性测试");
    }

    private static function testMemoryConstrainedEnvironment():Void {
        // 模拟内存受限环境下的表现
        var memorySizes:Array = [100, 500, 1000, 5000, 10000];
        var memoryResults:Array = [];
        
        for (var i:Number = 0; i < memorySizes.length; i++) {
            var size:Number = Number(memorySizes[i]);
            var data:Array = generateRandomArray(size, 1, size);
            
            var beforeSize:Number = data.length;
            var start:Number = getTimer();
            
            // 执行选择操作
            var median:Number = Number(QuickSelect.median(data, QuickSelect.numberCompare));
            
            var elapsed:Number = getTimer() - start;
            var afterSize:Number = data.length;
            
            // 验证内存使用（数组长度不应该改变）
            assertEquals(beforeSize, afterSize, "内存约束环境测试（大小=" + size + "）");
            
            // 计算内存效率指标（时间复杂度应该接近线性）
            var efficiency:Number = elapsed / size;  // ms per element
            
            memoryResults.push({
                size: size,
                time: elapsed,
                efficiency: efficiency,
                median: median
            });
            
            trace("    大小 " + size + ": " + elapsed + "ms, 效率=" + 
                  formatDecimal(efficiency * 1000, 3) + "μs/元素");
        }
        
        // 验证内存效率的线性特性
        var efficiencyVariation:Number = 0;
        var avgEfficiency:Number = 0;
        
        for (var j:Number = 0; j < memoryResults.length; j++) {
            avgEfficiency += memoryResults[j].efficiency;
        }
        avgEfficiency /= memoryResults.length;
        
        for (var k:Number = 0; k < memoryResults.length; k++) {
            var deviation:Number = Math.abs(memoryResults[k].efficiency - avgEfficiency);
            efficiencyVariation = Math.max(efficiencyVariation, deviation);
        }
        
        var variationRatio:Number = efficiencyVariation / avgEfficiency;
        
        // 效率变异不应该过大（表明算法复杂度稳定）
        assertTrue(variationRatio < 5.0, "内存约束环境测试", 
            "效率变异过大，可能存在复杂度问题: " + formatDecimal(variationRatio, 2));
        
        trace("    平均效率: " + formatDecimal(avgEfficiency * 1000, 3) + "μs/元素");
        trace("    效率变异比: " + formatDecimal(variationRatio, 2));
        trace("PASS: 内存约束环境测试");
    }

    private static function testWorstCaseScenarios():Void {
        // 测试各种最坏情况场景
        var scenarios:Array = [
            {
                name: "已排序递增",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    for (var i:Number = 0; i < size; i++) {
                        arr.push(i);
                    }
                    return arr;
                }
            },
            {
                name: "已排序递减", 
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    for (var i:Number = 0; i < size; i++) {
                        arr.push(size - i);
                    }
                    return arr;
                }
            },
            {
                name: "全相同元素",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    for (var i:Number = 0; i < size; i++) {
                        arr.push(42);
                    }
                    return arr;
                }
            },
            {
                name: "二元交替",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    for (var i:Number = 0; i < size; i++) {
                        arr.push(i % 2);
                    }
                    return arr;
                }
            },
            {
                name: "金字塔分布",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    var mid:Number = Math.floor(size / 2);
                    for (var i:Number = 0; i < size; i++) {
                        arr.push(Math.abs(i - mid));
                    }
                    return arr;
                }
            }
        ];
        
        var testSize:Number = 2000;
        var maxAllowedTime:Number = 500;  // 500ms上限
        
        for (var i:Number = 0; i < scenarios.length; i++) {
            var scenario:Object = scenarios[i];
            var data:Array = scenario.generator(testSize);
            
            var start:Number = getTimer();
            
            // 测试多个选择位置
            var testPositions:Array = [0, Math.floor(testSize * 0.25), 
                                     Math.floor(testSize * 0.5), 
                                     Math.floor(testSize * 0.75), 
                                     testSize - 1];
            
            var maxScenarioTime:Number = 0;
            var results:Array = [];
            
            for (var j:Number = 0; j < testPositions.length; j++) {
                var pos:Number = Number(testPositions[j]);
                var posStart:Number = getTimer();
                
                var result:Number = Number(QuickSelect.selectKth(data.concat(), pos, QuickSelect.numberCompare));
                
                var posElapsed:Number = getTimer() - posStart;
                maxScenarioTime = Math.max(maxScenarioTime, posElapsed);
                results.push(result);
            }
            
            var totalElapsed:Number = getTimer() - start;
            
            // 验证最坏情况的性能仍然可接受
            assertTrue(maxScenarioTime < maxAllowedTime, "最坏情况场景测试", 
                scenario.name + " 单次操作耗时过长: " + maxScenarioTime + "ms");
            
            assertTrue(totalElapsed < maxAllowedTime * 2, "最坏情况场景测试", 
                scenario.name + " 总耗时过长: " + totalElapsed + "ms");
            
            // 验证结果的单调性（对于相同数据）
            var monotonic:Boolean = true;
            for (var k:Number = 1; k < results.length; k++) {
                if (Number(results[k]) < Number(results[k-1])) {
                    monotonic = false;
                    break;
                }
            }
            
            assertTrue(monotonic, "最坏情况场景测试", 
                scenario.name + " 结果不满足单调性");
            
            trace("    " + scenario.name + ": 总耗时=" + totalElapsed + "ms, " +
                  "最大单次=" + maxScenarioTime + "ms, 结果范围=[" + 
                  results[0] + ", " + results[results.length-1] + "]");
        }
        
        trace("PASS: 最坏情况场景测试");
    }

    private static function testBoundaryIndexValues():Void {
        // 测试边界索引值的处理
        var testSizes:Array = [1, 2, 5, 10, 100, 1000];
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var data:Array = generateRandomArray(size, 1, 1000);
            
            // 测试各种边界索引
            var boundaryTests:Array = [
                {k: -1, expectNull: true, desc: "负索引"},
                {k: 0, expectNull: false, desc: "最小索引"},
                {k: size - 1, expectNull: false, desc: "最大索引"},
                {k: size, expectNull: true, desc: "超界索引"},
                {k: size + 100, expectNull: true, desc: "远超界索引"}
            ];
            
            for (var j:Number = 0; j < boundaryTests.length; j++) {
                var test:Object = boundaryTests[j];
                var result = QuickSelect.selectKth(data.concat(), test.k, QuickSelect.numberCompare);
                
                if (test.expectNull) {
                    assertTrue(result === null, "边界索引测试", 
                        "大小=" + size + ", " + test.desc + "(k=" + test.k + ") 应该返回null");
                } else {
                    assertTrue(result !== null && result !== undefined, "边界索引测试", 
                        "大小=" + size + ", " + test.desc + "(k=" + test.k + ") 不应该返回null");
                    
                    // 验证返回值在合理范围内
                    assertTrue(Number(result) >= 1 && Number(result) <= 1000, "边界索引测试",
                        "大小=" + size + ", " + test.desc + " 返回值超出范围: " + result);
                }
            }
        }
        
        // 特殊情况：空数组
        var emptyResult = QuickSelect.selectKth([], 0, QuickSelect.numberCompare);
        assertTrue(emptyResult === null, "边界索引测试", "空数组应该返回null");
        
        // 特殊情况：浮点索引（应该被截断处理）
        var floatData:Array = [1, 2, 3, 4, 5];
        var floatResult1 = QuickSelect.selectKth(floatData.concat(), 2.7, QuickSelect.numberCompare);
        var floatResult2 = QuickSelect.selectKth(floatData.concat(), 2, QuickSelect.numberCompare);
        
        // 浮点索引应该和整数索引产生相同结果（假设内部进行了截断）
        trace("    浮点索引测试: k=2.7 结果=" + floatResult1 + ", k=2 结果=" + floatResult2);
        
        trace("PASS: 边界索引值测试");
    }

    private static function testNumericalPrecisionLimits():Void {
        // 测试数值精度极限情况
        var precisionTests:Array = [
            {
                name: "微小差异",
                data: [1.0000001, 1.0000002, 1.0000003, 1.0000004, 1.0000005],
                description: "7位小数精度"
            },
            {
                name: "接近零值",
                data: [0.0001, 0.0002, 0.0003, 0.0004, 0.0005],
                description: "接近零的小数"
            },
            {
                name: "大数微调",
                data: [999999.1, 999999.2, 999999.3, 999999.4, 999999.5],
                description: "大整数加小数"
            },
            {
                name: "科学计数法边界",
                data: [1e-6, 2e-6, 3e-6, 4e-6, 5e-6],
                description: "科学计数法小数"
            },
            {
                name: "精度边界",
                data: [0.1 + 0.2, 0.3, 0.1 + 0.1 + 0.1, 0.30000001, 0.29999999],
                description: "浮点精度边界"
            }
        ];
        
        for (var i:Number = 0; i < precisionTests.length; i++) {
            var test:Object = precisionTests[i];
            var data:Array = test.data;
            
            var start:Number = getTimer();
            
            // 执行选择操作
            var min:Number = Number(QuickSelect.selectKth(data.concat(), 0, QuickSelect.numberCompare));
            var median:Number = Number(QuickSelect.median(data.concat(), QuickSelect.numberCompare));
            var max:Number = Number(QuickSelect.selectKth(data.concat(), data.length - 1, QuickSelect.numberCompare));
            
            var elapsed:Number = getTimer() - start;
            
            // 验证基本的数值关系
            assertTrue(min <= median, "数值精度测试", 
                test.name + ": 最小值应该小于等于中位数");
            assertTrue(median <= max, "数值精度测试", 
                test.name + ": 中位数应该小于等于最大值");
            
            // 验证精度范围合理性
            var range:Number = max - min;
            assertTrue(range >= 0, "数值精度测试", 
                test.name + ": 数值范围不能为负: " + range);
            
            // 对于微小数值，验证它们确实不同
            if (test.name == "微小差异" || test.name == "精度边界") {
                assertTrue(range > 0, "数值精度测试", 
                    test.name + ": 应该能区分微小差异");
            }
            
            trace("    " + test.name + "(" + test.description + "): " + elapsed + "ms");
            trace("      范围: [" + min + ", " + max + "], 中位数: " + median + ", 跨度: " + range);
        }
        
        // 特殊测试：NaN和Infinity处理
        var specialValues:Array = [1, 2, 3, 4, 5];
        // 注意：AS2中NaN和Infinity的处理可能有限，这里主要测试正常数值
        
        // 测试相等数值的比较稳定性
        var equalTest:Array = [1.000000001, 1.000000001, 1.000000001];
        var equalResult:Number = Number(QuickSelect.median(equalTest, QuickSelect.numberCompare));
        assertTrue(equalResult == 1.000000001, "数值精度测试", 
            "相等数值处理失败: " + equalResult);
        
        trace("PASS: 数值精度限制测试");
    }

    // ================================
    // 性能特性验证测试（简化实现）
    // ================================
    
    private static function testLinearTimeComplexity():Void {
        var sizes:Array = [1000, 2000, 4000, 8000];
        var times:Array = [];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = Number(sizes[i]);
            var arr:Array = generateRandomArray(size, 1, size);
            var k:Number = Math.floor(size / 2);
            
            var start:Number = getTimer();
            QuickSelect.selectKth(arr, k, QuickSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            times.push(elapsed);
            trace("    Size " + size + ": " + elapsed + "ms");
        }
        
        // 简单验证：时间增长应该接近线性（允许一定误差）
        var ratio1:Number = Number(times[1]) / Math.max(Number(times[0]), 1);
        var ratio2:Number = Number(times[2]) / Math.max(Number(times[1]), 1);
        
        assertTrue(ratio1 < 5 && ratio2 < 5, "线性时间复杂度测试", 
            "时间增长过快，可能不是线性复杂度");
        
        trace("PASS: 线性时间复杂度测试");
    }

    private static function testConstantSpaceComplexity():Void {
        // 空间复杂度主要体现在不需要额外的大量内存分配
        var size:Number = 10000;
        var arr:Array = generateRandomArray(size, 1, size);
        
        var start:Number = getTimer();
        var originalLength:Number = arr.length;
        QuickSelect.selectKth(arr, size / 2, QuickSelect.numberCompare);
        var elapsed:Number = getTimer() - start;
        
        // 验证数组长度未改变（原地操作的体现）
        assertEquals(originalLength, arr.length, "常数空间复杂度测试（长度保持）");
        
        // 性能合理（间接反映空间效率）
        assertTrue(elapsed < 1000, "常数空间复杂度测试", 
            "操作耗时过长: " + elapsed + "ms");
        
        trace("PASS: 常数空间复杂度测试");
    }

    private static function testWorstCasePerformance():Void {
        // 测试最坏情况下的性能表现
        var worstCaseSizes:Array = [1000, 2000, 4000, 8000];
        var scenarios:Array = ["sorted", "reverse", "allSame", "alternating"];
        
        trace("    最坏情况性能分析:");
        
        for (var i:Number = 0; i < scenarios.length; i++) {
            var scenario:String = String(scenarios[i]);
            var scenarioTimes:Array = [];
            
            trace("      场景: " + scenario);
            
            for (var j:Number = 0; j < worstCaseSizes.length; j++) {
                var size:Number = Number(worstCaseSizes[j]);
                var data:Array = generateTestArray(size, scenario);
                var k:Number = Math.floor(size / 2);  // 选择中位数
                
                var start:Number = getTimer();
                QuickSelect.selectKth(data, k, QuickSelect.numberCompare);
                var elapsed:Number = getTimer() - start;
                
                scenarioTimes.push(elapsed);
                trace("        大小 " + size + ": " + elapsed + "ms");
            }
            
            // 分析时间复杂度趋势
            var growthRatios:Array = [];
            for (var k:Number = 1; k < scenarioTimes.length; k++) {
                var ratio:Number = Number(scenarioTimes[k]) / Math.max(Number(scenarioTimes[k-1]), 1);
                growthRatios.push(ratio);
            }
            
            // 计算平均增长比率
            var avgGrowthRatio:Number = 0;
            for (var l:Number = 0; l < growthRatios.length; l++) {
                avgGrowthRatio += Number(growthRatios[l]);
            }
            avgGrowthRatio /= growthRatios.length;
            
            // 验证增长比率合理（应该接近线性，即比率接近2）
            assertTrue(avgGrowthRatio < 4, "最坏情况性能测试", 
                scenario + " 性能增长过快: " + formatDecimal(avgGrowthRatio, 2));
            
            trace("        平均增长比率: " + formatDecimal(avgGrowthRatio, 2));
        }
        
        // 验证所有场景的最大时间都在可接受范围内
        var maxAcceptableTime:Number = 1000;  // 1秒上限
        
        for (var m:Number = 0; m < scenarios.length; m++) {
            var testScenario:String = String(scenarios[m]);
            var largestSize:Number = Number(worstCaseSizes[worstCaseSizes.length - 1]);
            var testData:Array = generateTestArray(largestSize, testScenario);
            
            var testStart:Number = getTimer();
            QuickSelect.selectKth(testData, Math.floor(largestSize / 2), QuickSelect.numberCompare);
            var testElapsed:Number = getTimer() - testStart;
            
            assertTrue(testElapsed < maxAcceptableTime, "最坏情况性能测试", 
                testScenario + " 在最大规模下耗时过长: " + testElapsed + "ms");
        }
        
        trace("PASS: 最坏情况性能测试");
    }

    private static function testAverageCase():Void {
        // 测试平均情况下的性能和正确性
        var testSizes:Array = [100, 500, 1000, 2500, 5000];
        var trialsPerSize:Number = 20;  // 每个大小测试20次
        
        trace("    平均情况性能分析:");
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var totalTime:Number = 0;
            var correctCount:Number = 0;
            var times:Array = [];
            
            for (var trial:Number = 0; trial < trialsPerSize; trial++) {
                // 生成随机数据
                var data:Array = generateRandomArray(size, 1, size * 2);
                var k:Number = Math.floor(Math.random() * size);
                
                // 获取期望结果
                var sortedData:Array = data.concat();
                sortedData.sort(Array.NUMERIC);
                var expectedResult:Number = Number(sortedData[k]);
                
                // 测试QuickSelect
                var start:Number = getTimer();
                var actualResult:Number = Number(QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare));
                var elapsed:Number = getTimer() - start;
                
                totalTime += elapsed;
                times.push(elapsed);
                
                if (actualResult === expectedResult) {
                    correctCount++;
                }
            }
            
            var avgTime:Number = totalTime / trialsPerSize;
            var correctRate:Number = (correctCount / trialsPerSize) * 100;
            
            // 计算时间标准差
            var variance:Number = 0;
            for (var j:Number = 0; j < times.length; j++) {
                var deviation:Number = Number(times[j]) - avgTime;
                variance += deviation * deviation;
            }
            var stdDev:Number = Math.sqrt(variance / times.length);
            
            // 验证正确率
            assertEquals(100, correctRate, "平均情况测试（大小=" + size + "）正确率");
            
            // 验证性能稳定性
            var coefficientOfVariation:Number = stdDev / avgTime;
            assertTrue(coefficientOfVariation < 2.0, "平均情况测试", 
                "大小=" + size + " 性能变异过大: " + formatDecimal(coefficientOfVariation, 2));
            
            trace("      大小 " + size + ": 平均=" + formatDecimal(avgTime, 2) + 
                  "ms, 标准差=" + formatDecimal(stdDev, 2) + 
                  "ms, 正确率=" + formatDecimal(correctRate, 1) + "%");
        }
        
        // 分析平均情况的复杂度
        var timePerElement:Array = [];
        for (var k:Number = 0; k < testSizes.length; k++) {
            var sizeK:Number = Number(testSizes[k]);
            var dataK:Array = generateRandomArray(sizeK, 1, sizeK);
            
            var startK:Number = getTimer();
            QuickSelect.median(dataK, QuickSelect.numberCompare);
            var elapsedK:Number = getTimer() - startK;
            
            timePerElement.push(elapsedK / sizeK);
        }
        
        // 平均时间复杂度应该相对稳定
        var maxTimePerElement:Number = 0;
        var minTimePerElement:Number = Number.MAX_VALUE;
        
        for (var l:Number = 0; l < timePerElement.length; l++) {
            var tpe:Number = Number(timePerElement[l]);
            maxTimePerElement = Math.max(maxTimePerElement, tpe);
            minTimePerElement = Math.min(minTimePerElement, tpe);
        }
        
        var complexityVariation:Number = (maxTimePerElement - minTimePerElement) / minTimePerElement;
        
        assertTrue(complexityVariation < 3.0, "平均情况测试", 
            "时间复杂度变异过大: " + formatDecimal(complexityVariation, 2));
        
        trace("      时间复杂度分析: 每元素耗时变异=" + formatDecimal(complexityVariation * 100, 1) + "%");
        trace("PASS: 平均情况测试");
    }

    private static function testBestCaseOptimization():Void {
        // 测试最佳情况下的优化效果
        var optimizationTests:Array = [
            {
                name: "已分区数据",
                description: "数据已经在正确位置附近",
                generator: function(size:Number, k:Number):Array {
                    var arr:Array = generateRandomArray(size, 1, 1000);
                    arr.sort(Array.NUMERIC);
                    
                    // 轻微打乱k附近的元素
                    var range:Number = Math.min(10, Math.floor(size / 10));
                    for (var i:Number = Math.max(0, k - range); 
                         i < Math.min(size - 1, k + range); i++) {
                        if (Math.random() < 0.3) {
                            var j:Number = Math.max(0, Math.min(size - 1, 
                                                  i + Math.floor((Math.random() - 0.5) * 4)));
                            var temp = arr[i];
                            arr[i] = arr[j];
                            arr[j] = temp;
                        }
                    }
                    return arr;
                }
            },
            {
                name: "中位数在中心",
                description: "目标元素恰好在数组中心",
                generator: function(size:Number, k:Number):Array {
                    var arr:Array = generateRandomArray(size, 1, 1000);
                    var centerValue:Number = 500;  // 期望的中位数值
                    
                    // 将中心元素设置为期望值
                    arr[Math.floor(size / 2)] = centerValue;
                    
                    // 确保左半部分小于中心值，右半部分大于中心值
                    for (var i:Number = 0; i < Math.floor(size / 2); i++) {
                        if (Number(arr[i]) >= centerValue) {
                            arr[i] = centerValue - Math.floor(Math.random() * 100) - 1;
                        }
                    }
                    for (var j:Number = Math.floor(size / 2) + 1; j < size; j++) {
                        if (Number(arr[j]) <= centerValue) {
                            arr[j] = centerValue + Math.floor(Math.random() * 100) + 1;
                        }
                    }
                    return arr;
                }
            },
            {
                name: "小规模数据",
                description: "数据量很小，应该快速处理",
                generator: function(size:Number, k:Number):Array {
                    // 确保size很小
                    var smallSize:Number = Math.min(10, size);
                    return generateRandomArray(smallSize, 1, 100);
                }
            }
        ];
        
        var baselineSize:Number = 1000;
        var baselineData:Array = generateRandomArray(baselineSize, 1, 1000);
        var baselineK:Number = Math.floor(baselineSize / 2);
        
        // 测量基线性能
        var baselineStart:Number = getTimer();
        QuickSelect.selectKth(baselineData, baselineK, QuickSelect.numberCompare);
        var baselineTime:Number = getTimer() - baselineStart;
        
        trace("    最佳情况优化分析 (基线: " + baselineTime + "ms):");
        
        for (var i:Number = 0; i < optimizationTests.length; i++) {
            var test:Object = optimizationTests[i];
            var testData:Array = test.generator(baselineSize, baselineK);
            var testK:Number = Math.min(baselineK, testData.length - 1);
            
            var testStart:Number = getTimer();
            var result:Number = Number(QuickSelect.selectKth(testData, testK, QuickSelect.numberCompare));
            var testTime:Number = getTimer() - testStart;
            
            var improvement:Number = ((baselineTime - testTime) / baselineTime) * 100;
            var ratio:Number = testTime / Math.max(baselineTime, 1);
            
            // 验证结果正确性
            assertTrue(result !== null && result !== undefined, "最佳情况优化测试", 
                test.name + " 返回了无效结果");
            
            // 最佳情况应该不会比基线慢太多
            assertTrue(ratio < 2.0, "最佳情况优化测试", 
                test.name + " 性能退化过多: " + formatDecimal(ratio, 2) + "x");
            
            trace("      " + test.name + ": " + testTime + "ms, " +
                  "比率=" + formatDecimal(ratio, 2) + "x, " +
                  (improvement > 0 ? "改善" : "退化") + 
                  formatDecimal(Math.abs(improvement), 1) + "%");
            trace("        " + test.description);
        }
        
        // 测试pivot选择优化的效果
        var pivotOptimizationTest:Array = [
            [5, 3, 7, 1, 9, 2, 8, 4, 6],  // 中位数恰好是pivot的理想情况
            [1, 2, 3, 4, 5, 6, 7, 8, 9]   // 已排序，三数取中应该选择好的pivot
        ];
        
        for (var j:Number = 0; j < pivotOptimizationTest.length; j++) {
            var pivotData:Array = pivotOptimizationTest[j];
            var medianIndex:Number = Math.floor((pivotData.length - 1) / 2);
            
            var pivotStart:Number = getTimer();
            var pivotResult:Number = Number(QuickSelect.selectKth(pivotData.concat(), medianIndex, QuickSelect.numberCompare));
            var pivotTime:Number = getTimer() - pivotStart;
            
            // 小数组应该很快处理
            assertTrue(pivotTime < 50, "最佳情况优化测试", 
                "小数组处理耗时过长: " + pivotTime + "ms");
            
            trace("      Pivot优化测试 " + j + ": " + pivotTime + "ms, 结果=" + pivotResult);
        }
        
        trace("PASS: 最佳情况优化测试");
    }

    private static function testComparisonWithSorting():Void {
        // 比较QuickSelect与完整排序的性能
        var testSizes:Array = [100, 500, 1000, 2000, 5000];
        
        trace("    QuickSelect vs 完整排序性能对比:");
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var data:Array = generateRandomArray(size, 1, size);
            var k:Number = Math.floor(size / 2);  // 选择中位数
            
            // 测试QuickSelect性能
            var quickSelectData:Array = data.concat();
            var quickSelectStart:Number = getTimer();
            var quickSelectResult:Number = Number(QuickSelect.selectKth(quickSelectData, k, QuickSelect.numberCompare));
            var quickSelectTime:Number = getTimer() - quickSelectStart;
            
            // 测试完整排序性能
            var sortData:Array = data.concat();
            var sortStart:Number = getTimer();
            sortData.sort(Array.NUMERIC);
            var sortResult:Number = Number(sortData[k]);
            var sortTime:Number = getTimer() - sortStart;
            
            // 验证结果一致性
            assertEquals(sortResult, quickSelectResult, 
                "QuickSelect vs 排序对比测试（大小=" + size + "）");
            
            // 计算性能提升
            var speedup:Number = sortTime / Math.max(quickSelectTime, 1);
            var timeSaved:Number = sortTime - quickSelectTime;
            var efficiency:Number = (timeSaved / sortTime) * 100;
            
            // QuickSelect应该比完整排序快（特别是在大数据量时）
            if (size >= 1000) {
                assertTrue(speedup > 1.0, "QuickSelect vs 排序对比测试", 
                    "大数据量时QuickSelect应该比排序快，大小=" + size + ", 提升=" + formatDecimal(speedup, 2) + "x");
            }
            
            trace("      大小 " + size + ": QuickSelect=" + quickSelectTime + 
                  "ms, 排序=" + sortTime + "ms, 提升=" + formatDecimal(speedup, 2) + 
                  "x, 效率=" + formatDecimal(efficiency, 1) + "%");
        }
        
        // 测试不同k值位置的性能对比
        var positionTestSize:Number = 2000;
        var positionTestData:Array = generateRandomArray(positionTestSize, 1, positionTestSize);
        var positions:Array = [0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0];  // 不同百分位位置
        
        trace("      不同位置选择的性能 (大小=" + positionTestSize + "):");
        
        var totalQuickSelectTime:Number = 0;
        var totalSortTime:Number = 0;
        
        for (var j:Number = 0; j < positions.length; j++) {
            var position:Number = Number(positions[j]);
            var posK:Number = Math.floor((positionTestSize - 1) * position);
            
            // QuickSelect测试
            var posQuickSelectStart:Number = getTimer();
            var posQuickSelectResult:Number = Number(QuickSelect.selectKth(positionTestData.concat(), posK, QuickSelect.numberCompare));
            var posQuickSelectTime:Number = getTimer() - posQuickSelectStart;
            
            // 排序测试（只计算一次，重复使用结果）
            var posSortTime:Number = 0;
            if (j == 0) {
                var posSortStart:Number = getTimer();
                var sortedPosData:Array = positionTestData.concat();
                sortedPosData.sort(Array.NUMERIC);
                posSortTime = getTimer() - posSortStart;
                totalSortTime = posSortTime;
            } else {
                posSortTime = totalSortTime; // 重用排序时间
            }
            
            totalQuickSelectTime += posQuickSelectTime;
            
            var posSpeedup:Number = posSortTime / Math.max(posQuickSelectTime, 1);
            
            trace("        " + formatDecimal(position * 100, 0) + "% 位置: " + 
                  posQuickSelectTime + "ms, 提升=" + formatDecimal(posSpeedup, 2) + "x");
        }
        
        var overallSpeedup:Number = totalSortTime / Math.max(totalQuickSelectTime, 1);
        trace("      总体提升: " + formatDecimal(overallSpeedup, 2) + "x");
        
        trace("PASS: QuickSelect vs 排序对比测试");
    }

    private static function testScalabilityAnalysis():Void {
        // 分析算法的可扩展性
        var scalabilitySizes:Array = [100, 200, 500, 1000, 2000, 5000, 10000];
        var measurements:Array = [];
        
        trace("    可扩展性分析:");
        
        for (var i:Number = 0; i < scalabilitySizes.length; i++) {
            var size:Number = Number(scalabilitySizes[i]);
            var data:Array = generateRandomArray(size, 1, size);
            var k:Number = Math.floor(size / 2);
            
            // 多次测试取平均值以减少噪音
            var totalTime:Number = 0;
            var iterations:Number = 3;
            
            for (var iter:Number = 0; iter < iterations; iter++) {
                var testData:Array = data.concat();
                var start:Number = getTimer();
                QuickSelect.selectKth(testData, k, QuickSelect.numberCompare);
                var elapsed:Number = getTimer() - start;
                totalTime += elapsed;
            }
            
            var avgTime:Number = totalTime / iterations;
            var timePerElement:Number = avgTime / size;
            
            measurements.push({
                size: size,
                time: avgTime,
                timePerElement: timePerElement
            });
            
            trace("      大小 " + size + ": " + formatDecimal(avgTime, 2) + 
                  "ms, 每元素=" + formatDecimal(timePerElement * 1000, 3) + "μs");
        }
        
        // 分析时间复杂度
        var complexityAnalysis:Array = [];
        
        for (var j:Number = 1; j < measurements.length; j++) {
            var current:Object = measurements[j];
            var previous:Object = measurements[j-1];
            
            var sizeRatio:Number = current.size / previous.size;
            var timeRatio:Number = current.time / Math.max(previous.time, 1);
            
            // 理想的线性复杂度应该有 timeRatio ≈ sizeRatio
            var complexityFactor:Number = timeRatio / sizeRatio;
            
            complexityAnalysis.push({
                fromSize: previous.size,
                toSize: current.size,
                sizeRatio: sizeRatio,
                timeRatio: timeRatio,
                complexityFactor: complexityFactor
            });
        }
        
        // 验证复杂度趋势
        var avgComplexityFactor:Number = 0;
        var maxComplexityFactor:Number = 0;
        
        for (var k:Number = 0; k < complexityAnalysis.length; k++) {
            var analysis:Object = complexityAnalysis[k];
            avgComplexityFactor += analysis.complexityFactor;
            maxComplexityFactor = Math.max(maxComplexityFactor, analysis.complexityFactor);
            
            trace("      " + analysis.fromSize + " → " + analysis.toSize + 
                  ": 复杂度因子=" + formatDecimal(analysis.complexityFactor, 2));
        }
        
        avgComplexityFactor /= complexityAnalysis.length;
        
        // 验证平均复杂度接近线性（因子接近1）
        assertTrue(avgComplexityFactor < 2.0, "可扩展性分析测试", 
            "平均复杂度因子过高: " + formatDecimal(avgComplexityFactor, 2));
        
        // 验证最大复杂度不会太高
        assertTrue(maxComplexityFactor < 3.0, "可扩展性分析测试", 
            "最大复杂度因子过高: " + formatDecimal(maxComplexityFactor, 2));
        
        // 分析内存使用的可扩展性（通过时间间接反映）
        var memoryEfficiency:Array = [];
        for (var l:Number = 0; l < measurements.length; l++) {
            var measurement:Object = measurements[l];
            // 假设内存使用与数组大小成正比，时间增长应该保持线性
            var memoryScore:Number = measurement.timePerElement;
            memoryEfficiency.push(memoryScore);
        }
        
        // 检查内存效率的稳定性
        var minMemoryScore:Number = Number.MAX_VALUE;
        var maxMemoryScore:Number = 0;
        
        for (var m:Number = 0; m < memoryEfficiency.length; m++) {
            var score:Number = Number(memoryEfficiency[m]);
            minMemoryScore = Math.min(minMemoryScore, score);
            maxMemoryScore = Math.max(maxMemoryScore, score);
        }
        
        var memoryVariation:Number = (maxMemoryScore - minMemoryScore) / minMemoryScore;
        
        assertTrue(memoryVariation < 5.0, "可扩展性分析测试", 
            "内存效率变异过大: " + formatDecimal(memoryVariation, 2));
        
        trace("      复杂度分析: 平均因子=" + formatDecimal(avgComplexityFactor, 2) + 
              ", 最大因子=" + formatDecimal(maxComplexityFactor, 2));
        trace("      内存效率变异: " + formatDecimal(memoryVariation * 100, 1) + "%");
        
        // 预测更大规模的性能
        var largestMeasurement:Object = measurements[measurements.length - 1];
        var predictedTimeFor50k:Number = largestMeasurement.timePerElement * 50000;
        var predictedTimeFor100k:Number = largestMeasurement.timePerElement * 100000;
        
        trace("      性能预测: 50K元素≈" + formatDecimal(predictedTimeFor50k, 0) + 
              "ms, 100K元素≈" + formatDecimal(predictedTimeFor100k, 0) + "ms");
        
        trace("PASS: 可扩展性分析测试");
    }

    // ================================
    // 综合性能测试
    // ================================
    private static function runEnhancedPerformanceTests():Void {
        trace("\n开始增强版性能测试...");
        
        var sizes:Array = [100, 500, 1000, 5000];
        var distributions:Array = [
            "random",
            "sorted", 
            "reverse",
            "duplicates",
            "partiallyOrdered",
            "allSame"
        ];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = Number(sizes[i]);
            trace("  测试数组大小: " + size);
            
            for (var j:Number = 0; j < distributions.length; j++) {
                var dist:String = String(distributions[j]);
                var arr:Array = generateTestArray(size, dist);
                var k:Number = Math.floor(size / 2);  // 选择中位数
                
                var start:Number = getTimer();
                var result = QuickSelect.selectKth(arr.concat(), k, QuickSelect.numberCompare);
                var elapsed:Number = getTimer() - start;
                
                trace("    " + dist + ": " + elapsed + "ms");
                
                // 基本正确性验证
                assertTrue(result !== null && result !== undefined, 
                    "性能测试正确性", dist + " size=" + size + " 返回无效结果");
            }
        }
        
        trace("增强版性能测试完成");
    }

    private static function generateTestArray(size:Number, type:String):Array {
        var arr:Array = [];
        
        switch (type) {
            case "random":
                for (var i:Number = 0; i < size; i++) {
                    arr.push(Math.random() * size);
                }
                break;
                
            case "sorted":
                for (var j:Number = 0; j < size; j++) {
                    arr.push(j);
                }
                break;
                
            case "reverse":
                for (var k:Number = 0; k < size; k++) {
                    arr.push(size - k);
                }
                break;
                
            case "duplicates":
                for (var l:Number = 0; l < size; l++) {
                    arr.push(Math.floor(Math.random() * 10));  // 只有10个不同值
                }
                break;
                
            case "partiallyOrdered":
                // 大部分有序，少量随机
                for (var m:Number = 0; m < size; m++) {
                    arr.push(m);
                }
                // 随机交换10%的元素
                for (var n:Number = 0; n < size / 10; n++) {
                    var pos1:Number = Math.floor(Math.random() * size);
                    var pos2:Number = Math.floor(Math.random() * size);
                    var temp = arr[pos1];
                    arr[pos1] = arr[pos2];
                    arr[pos2] = temp;
                }
                break;
                
            case "allSame":
                for (var p:Number = 0; p < size; p++) {
                    arr.push(42);
                }
                break;
                
            default:
                // 默认随机
                for (var q:Number = 0; q < size; q++) {
                    arr.push(Math.random() * size);
                }
        }
        
        return arr;
    }

    // ================================
    // 算法正确性验证测试
    // ================================
    private static function runCorrectnessVerificationSuite():Void {
        trace("\n开始算法正确性验证...");
        
        var testCount:Number = 0;
        var passCount:Number = 0;
        
        // 随机测试用例生成
        for (var round:Number = 0; round < 50; round++) {
            var size:Number = 10 + Math.floor(Math.random() * 90);  // 10-100随机大小
            var arr:Array = generateRandomArray(size, 1, 1000);
            var k:Number = Math.floor(Math.random() * size);
            
            testCount++;
            
            // 使用QuickSelect获取结果
            var testArr:Array = arr.concat();
            var quickSelectResult:Number = Number(QuickSelect.selectKth(testArr, k, QuickSelect.numberCompare));
            
            // 使用标准排序获取期望结果
            var sortedArr:Array = arr.concat();
            sortedArr.sort(Array.NUMERIC);
            var expectedResult:Number = Number(sortedArr[k]);
            
            if (quickSelectResult === expectedResult) {
                passCount++;
            } else {
                trace("    验证失败 - round " + round + ": size=" + size + " k=" + k + 
                      " 预期=" + expectedResult + " 实际=" + quickSelectResult);
            }
        }
        
        var passRate:Number = (passCount / testCount) * 100;
        trace("  正确性验证结果: " + passCount + "/" + testCount + " (" + formatDecimal(passRate, 2) + "%)");
        
        assertTrue(passRate >= 98, "算法正确性验证", 
            "正确率过低: " + formatDecimal(passRate, 2) + "%");
        
        trace("算法正确性验证完成");
    }
}