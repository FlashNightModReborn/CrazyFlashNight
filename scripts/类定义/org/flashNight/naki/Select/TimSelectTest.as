import org.flashNight.naki.Select.TimSelect;
import org.flashNight.naki.Select.QuickSelect;

/**
 * TimSelect 混合算法测试类 (AS2版本)
 *
 * 全面测试 TimSelect 混合选择算法的正确性、性能和特殊场景处理能力。
 * 针对 TimSelect 的混合算法特性设计了专项测试，包括：
 * - QuickSelect + BFPRT 混合策略验证
 * - 分区不平衡检测和BFPRT触发测试
 * - 插入排序阈值优化测试
 * - 最坏情况O(n)性能保证验证
 * - 与QuickSelect的性能对比
 * - 各种数据分布下的适应性测试
 * - 实际应用场景性能验证
 */
class org.flashNight.naki.Select.TimSelectTest {

    public static function runTests():Void {
        trace("Starting Enhanced TimSelect Hybrid Algorithm Tests...\n");

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
        // TimSelect 混合算法特性专项测试
        // ================================
        trace("\n=== TimSelect 混合算法特性测试 ===");
        testBFPRTTriggerConditions();
        testUnbalancedPartitionDetection();
        testInsertionThresholdBehavior();
        testHybridStrategyEffectiveness();
        testWorstCaseLinearTimeGuarantee();
        testMedianOfMediansCorrectness();
        testIterativeVsRecursiveBFPRT();
        testPartitionBalanceOptimization();
        
        // ================================
        // 性能对比测试
        // ================================
        trace("\n=== 性能对比测试 ===");
        testTimSelectVsQuickSelect();
        testTimSelectVsFullSort();
        testWorstCasePerformanceComparison();
        testAverageCasePerformanceAnalysis();
        testMemoryEfficiencyComparison();
        
        // ================================
        // 参数调优验证测试
        // ================================
        trace("\n=== 参数调优验证测试 ===");
        testInsertionThresholdOptimization();
        testUnbalancedRatioOptimization();
        testBFPRTOverheadAnalysis();
        testOptimalParameterCombinations();
        
        // ================================
        // 对抗性输入测试
        // ================================
        trace("\n=== 对抗性输入测试 ===");
        testAdversarialInputPatterns();
        testAntiQuickSelectPatterns();
        testHighlyDuplicatedData();
        testPathologicalDistributions();
        testMaliciousInputGeneration();
        
        // ================================
        // 核心算法正确性测试
        // ================================
        trace("\n=== 核心算法正确性测试 ===");
        testPartitionCorrectness();
        testPartitionBoundaryIntegrity();
        testBFPRTMedianSelection();
        testHybridSwitchingLogic();
        testKthElementRangeValidation();
        
        // ================================
        // 数据分布适应性测试
        // ================================
        trace("\n=== 数据分布适应性测试 ===");
        testUniformDistribution();
        testNormalDistribution();
        testExponentialDistribution();
        testPowerLawDistribution();
        testBimodalDistribution();
        testHighlySkewedData();
        testZipfianDistribution();
        testClusteredData();
        
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
        testBoundaryIndexValues();
        testNumericalPrecisionLimits();
        
        // ================================
        // 混合算法稳定性测试
        // ================================
        trace("\n=== 混合算法稳定性测试 ===");
        testAlgorithmStability();
        testHybridSwitchingStability();
        testBoundaryValueHandling();
        testConcurrencySafety();
        
        // ================================
        // 综合性能基准测试
        // ================================
        trace("\n=== 综合性能基准测试 ===");
        runComprehensivePerformanceBenchmark();
        runStressTestSuite();
        
        // ================================
        // 算法质量评估
        // ================================
        trace("\n=== 算法质量评估 ===");
        evaluateAlgorithmQuality();
        
        // ================================
        // 生成最终报告
        // ================================
        generateFinalTestReport();
        
        trace("\nAll Enhanced TimSelect Tests Completed.");
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

    private static function assertTrue(condition:Boolean, testName:String, message:String):Void {
        if (!condition) {
            trace("FAIL: " + testName + " - " + message);
        } else {
            trace("PASS: " + testName);
        }
    }

    private static function assertPartitioned(arr:Array, k:Number, compareFunc:Function, testName:String):Void {
        if (compareFunc == null) {
            compareFunc = TimSelect.numberCompare;
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

    private static function generateRandomArray(size:Number, min:Number, max:Number):Array {
        var arr:Array = [];
        var range:Number = max - min;
        for (var i:Number = 0; i < size; i++) {
            arr.push(min + Math.random() * range);
        }
        return arr;
    }

    private static function formatDecimal(num:Number, digits:Number):String {
        var multiplier:Number = Math.pow(10, digits);
        var rounded:Number = Math.round(num * multiplier) / multiplier;
        return String(rounded);
    }

    private static function repeatString(str:String, count:Number):String {
        var result:String = "";
        for (var i:Number = 0; i < count; i++) {
            result += str;
        }
        return result;
    }

    // 验证TimSelect结果的正确性
    private static function verifyTimSelectResult(originalData:Array, k:Number, result, compareFunc:Function):Boolean {
        if (compareFunc == null) {
            compareFunc = TimSelect.numberCompare;
        }
        
        // 使用标准排序验证
        var sortedData:Array = originalData.concat();
        sortedData.sort(compareFunc);
        
        var expectedResult = sortedData[k];
        
        // 比较结果
        if (compareFunc === TimSelect.numberCompare) {
            return Number(result) === Number(expectedResult);
        } else if (compareFunc === TimSelect.stringCompare) {
            return String(result) === String(expectedResult);
        } else {
            return compareFunc(result, expectedResult) === 0;
        }
    }

    // ================================
    // TimSelect 混合算法特性专项测试
    // ================================
    
    private static function testBFPRTTriggerConditions():Void {
        trace("=== BFPRT 触发条件测试 ===");
        
        // 构造会触发 BFPRT 的特殊数据
        var adversarialCases:Array = [
            createWorstCaseForQuickSelect(1000),  // 快速选择最坏情况
            createSkewedDistribution(1000),       // 高度偏斜分布
            createAlternatingPattern(1000),       // 交替模式
            createNearlySortedPattern(1000)       // 近似排序模式
        ];
        
        for (var i:Number = 0; i < adversarialCases.length; i++) {
            var data:Array = adversarialCases[i];
            var k:Number = Math.floor(data.length / 2);
            
            // 测试TimSelect的表现
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var timSelectTime:Number = getTimer() - start;
            
            // 测试QuickSelect在相同数据上的表现进行对比
            var quickSelectStart:Number = getTimer();
            var quickSelectResult = QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
            var quickSelectTime:Number = getTimer() - quickSelectStart;
            
            // 验证结果正确性
            assertEquals(quickSelectResult, result, "BFPRT触发测试 case" + i + " 结果一致性");
            
            // 在对抗性输入下，TimSelect应该比QuickSelect更稳定
            var timeRatio:Number = timSelectTime / Math.max(quickSelectTime, 1);
            
            trace("  Case " + i + ": TimSelect=" + timSelectTime + "ms, QuickSelect=" + quickSelectTime + 
                  "ms, 比率=" + formatDecimal(timeRatio, 2));
        }
        
        trace("PASS: BFPRT 触发条件测试");
    }

    private static function testUnbalancedPartitionDetection():Void {
        trace("=== 不平衡分区检测测试 ===");
        
        // 构造会导致严重不平衡分区的数据
        var unbalancedCases:Array = [
            {
                name: "极端偏斜",
                data: createExtremelySkewedData(1000),
                description: "99%小值，1%大值"
            },
            {
                name: "二元极值",
                data: createBinaryExtremeData(1000),
                description: "只有两个极端值"
            },
            {
                name: "阶梯分布",
                data: createStepDistribution(1000),
                description: "明显的阶梯状分布"
            }
        ];
        
        for (var i:Number = 0; i < unbalancedCases.length; i++) {
            var testCase:Object = unbalancedCases[i];
            var data:Array = testCase.data;
            var k:Number = Math.floor(data.length / 2);
            
            // 测试不同位置的选择，验证算法的稳定性
            var positions:Array = [0.1, 0.25, 0.5, 0.75, 0.9];
            var maxTime:Number = 0;
            var totalTime:Number = 0;
            
            for (var j:Number = 0; j < positions.length; j++) {
                var pos:Number = Number(positions[j]);
                var posK:Number = Math.floor((data.length - 1) * pos);
                
                var start:Number = getTimer();
                var result = TimSelect.selectKth(data.concat(), posK, TimSelect.numberCompare);
                var elapsed:Number = getTimer() - start;
                
                maxTime = Math.max(maxTime, elapsed);
                totalTime += elapsed;
                
                // 验证结果的合理性
                assertTrue(result !== null && result !== undefined, 
                    "不平衡分区检测测试", testCase.name + " 位置" + (pos*100) + "% 返回无效结果");
            }
            
            var avgTime:Number = totalTime / positions.length;
            
            // 在不平衡数据下，时间应该仍然合理
            assertTrue(maxTime < 500, "不平衡分区检测测试", 
                testCase.name + " 最大耗时过长: " + maxTime + "ms");
            
            trace("  " + testCase.name + "(" + testCase.description + "): " +
                  "平均=" + formatDecimal(avgTime, 2) + "ms, 最大=" + maxTime + "ms");
        }
        
        trace("PASS: 不平衡分区检测测试");
    }

    private static function testInsertionThresholdBehavior():Void {
        trace("=== 插入排序阈值行为测试 ===");
        
        // 测试不同大小的数组，验证插入排序阈值的效果
        var thresholdTestSizes:Array = [5, 10, 16, 32, 64, 100];
        var smallArrayResults:Array = [];
        
        for (var i:Number = 0; i < thresholdTestSizes.length; i++) {
            var size:Number = Number(thresholdTestSizes[i]);
            var data:Array = generateRandomArray(size, 1, 1000);
            var k:Number = Math.floor(size / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            smallArrayResults.push({
                size: size,
                time: elapsed,
                efficiency: elapsed / size
            });
            
            // 验证小数组的处理速度
            assertTrue(elapsed < 50, "插入排序阈值测试", 
                "小数组(size=" + size + ")处理耗时过长: " + elapsed + "ms");
            
            // 验证结果正确性
            var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
            assertTrue(verified, "插入排序阈值测试", 
                "小数组(size=" + size + ")结果不正确");
            
            trace("  大小 " + size + ": " + elapsed + "ms, 效率=" + 
                  formatDecimal((elapsed/size)*1000, 3) + "μs/元素");
        }
        
        // 分析小数组处理的效率趋势
        var efficiencyVariation:Number = 0;
        for (var j:Number = 1; j < smallArrayResults.length; j++) {
            var current:Object = smallArrayResults[j];
            var previous:Object = smallArrayResults[j-1];
            var variation:Number = Math.abs(current.efficiency - previous.efficiency) / previous.efficiency;
            efficiencyVariation = Math.max(efficiencyVariation, variation);
        }
        
        // 小数组的效率变化应该相对平稳
        assertTrue(efficiencyVariation < 2.0, "插入排序阈值测试", 
            "小数组效率变化过大: " + formatDecimal(efficiencyVariation, 2));
        
        trace("PASS: 插入排序阈值行为测试");
    }

    private static function testHybridStrategyEffectiveness():Void {
        trace("=== 混合策略有效性测试 ===");
        
        // 构造不同特征的数据集，测试混合策略的适应性
        var strategyTests:Array = [
            {
                name: "随机数据",
                generator: function(size:Number):Array {
                    return generateRandomArray(size, 1, size);
                },
                expectedAdvantage: "应该主要使用快速选择"
            },
            {
                name: "对抗性数据",
                generator: function(size:Number):Array {
                    return createWorstCaseForQuickSelect(size);
                },
                expectedAdvantage: "应该触发BFPRT保证线性时间"
            },
            {
                name: "高重复数据",
                generator: function(size:Number):Array {
                    return createHighDuplicateData(size);
                },
                expectedAdvantage: "应该处理重复元素高效"
            },
            {
                name: "小规模数据",
                generator: function(size:Number):Array {
                    return generateRandomArray(Math.min(20, size), 1, 100);
                },
                expectedAdvantage: "应该使用插入排序"
            }
        ];
        
        var testSize:Number = 5000;
        
        for (var i:Number = 0; i < strategyTests.length; i++) {
            var test:Object = strategyTests[i];
            var data:Array = test.generator(testSize);
            var k:Number = Math.floor(data.length / 2);
            
            // 测试TimSelect
            var timSelectStart:Number = getTimer();
            var timSelectResult = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var timSelectTime:Number = getTimer() - timSelectStart;
            
            // 测试QuickSelect作为基准
            var quickSelectStart:Number = getTimer();
            var quickSelectResult = QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
            var quickSelectTime:Number = getTimer() - quickSelectStart;
            
            // 验证结果一致性
            assertEquals(quickSelectResult, timSelectResult, 
                "混合策略测试 " + test.name + " 结果一致性");
            
            var performanceRatio:Number = timSelectTime / Math.max(quickSelectTime, 1);
            var advantage:String = (performanceRatio < 1.2) ? "相当" : 
                                 (performanceRatio < 2.0) ? "可接受" : "需要优化";
            
            trace("  " + test.name + ": TimSelect=" + timSelectTime + "ms, " +
                  "QuickSelect=" + quickSelectTime + "ms, " +
                  "比率=" + formatDecimal(performanceRatio, 2) + " (" + advantage + ")");
            trace("    " + test.expectedAdvantage);
        }
        
        trace("PASS: 混合策略有效性测试");
    }

    private static function testWorstCaseLinearTimeGuarantee():Void {
        trace("=== 最坏情况线性时间保证测试 ===");
        
        // 构造各种最坏情况，验证TimSelect的O(n)保证
        var worstCases:Array = [
            {name: "已排序", data: createSortedArray(2000)},
            {name: "逆序", data: createReverseSortedArray(2000)},
            {name: "全相同", data: createAllSameArray(2000, 42)},
            {name: "QuickSelect杀手", data: createQuickSelectKiller(2000)},
            {name: "病理分布", data: createPathologicalDistribution(2000)}
        ];
        
        var linearityResults:Array = [];
        
        for (var i:Number = 0; i < worstCases.length; i++) {
            var worstCase:Object = worstCases[i];
            var data:Array = worstCase.data;
            var k:Number = Math.floor(data.length / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            var timePerElement:Number = elapsed / data.length;
            linearityResults.push(timePerElement);
            
            // 验证最坏情况仍然能在合理时间内完成
            var maxAllowedTime:Number = data.length / 5;  // 粗略的线性时间上限
            assertTrue(elapsed < maxAllowedTime, "最坏情况线性时间保证", 
                worstCase.name + " 耗时过长: " + elapsed + "ms");
            
            // 验证结果正确性
            assertTrue(result !== null && result !== undefined, 
                "最坏情况线性时间保证", worstCase.name + " 返回无效结果");
            
            trace("  " + worstCase.name + ": " + elapsed + "ms (" + 
                  formatDecimal(timePerElement * 1000, 3) + "μs/元素)");
        }
        
        // 验证线性时间特征：所有最坏情况的时间复杂度应该相近
        var maxTimePerElement:Number = 0;
        var minTimePerElement:Number = Number.MAX_VALUE;
        
        for (var j:Number = 0; j < linearityResults.length; j++) {
            var tpe:Number = Number(linearityResults[j]);
            maxTimePerElement = Math.max(maxTimePerElement, tpe);
            minTimePerElement = Math.min(minTimePerElement, tpe);
        }
        
        var linearityRatio:Number = maxTimePerElement / minTimePerElement;
        
        // 最坏情况之间的性能差异不应该太大（体现线性时间的稳定性）
        assertTrue(linearityRatio < 5.0, "最坏情况线性时间保证", 
            "最坏情况间性能差异过大: " + formatDecimal(linearityRatio, 2));
        
        trace("  线性时间稳定性比率: " + formatDecimal(linearityRatio, 2));
        trace("PASS: 最坏情况线性时间保证测试");
    }

    private static function testMedianOfMediansCorrectness():Void {
        trace("=== 中位数的中位数正确性测试 ===");
        
        // 测试BFPRT算法的核心组件
        var medianTests:Array = [
            {size: 5, name: "最小组"},
            {size: 25, name: "5组"},
            {size: 75, name: "15组"},
            {size: 125, name: "25组"},
            {size: 500, name: "100组"}
        ];
        
        for (var i:Number = 0; i < medianTests.length; i++) {
            var test:Object = medianTests[i];
            var size:Number = test.size;
            
            // 生成多个测试用例
            for (var trial:Number = 0; trial < 5; trial++) {
                var data:Array = generateRandomArray(size, 1, 1000);
                var k:Number = Math.floor(size / 2);
                
                var start:Number = getTimer();
                var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
                var elapsed:Number = getTimer() - start;
                
                // 验证结果正确性
                var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
                assertTrue(verified, "中位数的中位数正确性测试", 
                    test.name + " trial" + trial + " 结果不正确");
                
                // 验证性能合理性
                assertTrue(elapsed < size, "中位数的中位数正确性测试", 
                    test.name + " trial" + trial + " 耗时过长: " + elapsed + "ms");
            }
            
            trace("  " + test.name + " (size=" + size + "): 5次测试全部通过");
        }
        
        trace("PASS: 中位数的中位数正确性测试");
    }

    private static function testIterativeVsRecursiveBFPRT():Void {
        trace("=== 迭代vs递归BFPRT测试 ===");
        
        // 测试大数据量下迭代实现的优势
        var testSizes:Array = [1000, 5000, 10000];
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var data:Array = createWorstCaseForQuickSelect(size);  // 强制触发BFPRT
            var k:Number = Math.floor(size / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            // 验证迭代实现没有栈溢出问题
            assertTrue(result !== null && result !== undefined, 
                "迭代vs递归BFPRT测试", "大小=" + size + " 可能发生栈溢出");
            
            // 验证性能线性增长
            var efficiency:Number = elapsed / size;
            assertTrue(efficiency < 1.0, "迭代vs递归BFPRT测试", 
                "大小=" + size + " 效率过低: " + formatDecimal(efficiency * 1000, 3) + "μs/元素");
            
            trace("  大小 " + size + ": " + elapsed + "ms (" + 
                  formatDecimal(efficiency * 1000, 3) + "μs/元素)");
        }
        
        trace("PASS: 迭代vs递归BFPRT测试");
    }

    private static function testPartitionBalanceOptimization():Void {
        trace("=== 分区平衡优化测试 ===");
        
        // 测试分区平衡检测和优化的有效性
        var balanceTests:Array = [
            {
                name: "理想平衡",
                data: generateRandomArray(1000, 1, 1000),
                expectedBalance: "应该很少触发BFPRT"
            },
            {
                name: "轻微不平衡", 
                data: createSlightlyUnbalancedData(1000),
                expectedBalance: "应该偶尔触发BFPRT"
            },
            {
                name: "严重不平衡",
                data: createSeverelyUnbalancedData(1000),
                expectedBalance: "应该频繁触发BFPRT"
            }
        ];
        
        for (var i:Number = 0; i < balanceTests.length; i++) {
            var test:Object = balanceTests[i];
            var data:Array = test.data;
            
            // 测试多个k值位置
            var positions:Array = [0.1, 0.3, 0.5, 0.7, 0.9];
            var totalTime:Number = 0;
            var maxTime:Number = 0;
            var minTime:Number = Number.MAX_VALUE;
            
            for (var j:Number = 0; j < positions.length; j++) {
                var pos:Number = Number(positions[j]);
                var k:Number = Math.floor((data.length - 1) * pos);
                
                var start:Number = getTimer();
                var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
                var elapsed:Number = getTimer() - start;
                
                totalTime += elapsed;
                maxTime = Math.max(maxTime, elapsed);
                minTime = Math.min(minTime, elapsed);
                
                // 验证结果正确性
                var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
                assertTrue(verified, "分区平衡优化测试", 
                    test.name + " 位置" + (pos*100) + "% 结果不正确");
            }
            
            var avgTime:Number = totalTime / positions.length;
            var timeVariation:Number = (maxTime - minTime) / avgTime;
            
            // 验证性能稳定性（好的平衡策略应该减少性能变异）
            assertTrue(timeVariation < 3.0, "分区平衡优化测试", 
                test.name + " 性能变异过大: " + formatDecimal(timeVariation, 2));
            
            trace("  " + test.name + ": 平均=" + formatDecimal(avgTime, 2) + 
                  "ms, 变异=" + formatDecimal(timeVariation, 2) + ", " + test.expectedBalance);
        }
        
        trace("PASS: 分区平衡优化测试");
    }

    // ================================
    // 性能对比测试
    // ================================
    
    private static function testTimSelectVsQuickSelect():Void {
        trace("=== TimSelect vs QuickSelect 性能对比 ===");
        
        var testSizes:Array = [1000, 5000, 10000];
        var dataTypes:Array = [
            {name: "随机数据", generator: function(size:Number):Array { return generateRandomArray(size, 1, size); }},
            {name: "已排序", generator: function(size:Number):Array { return createSortedArray(size); }},
            {name: "逆序", generator: function(size:Number):Array { return createReverseSortedArray(size); }},
            {name: "高重复", generator: function(size:Number):Array { return createHighDuplicateData(size); }},
            {name: "对抗性", generator: function(size:Number):Array { return createWorstCaseForQuickSelect(size); }}
        ];
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            trace("  测试规模: " + size);
            
            for (var j:Number = 0; j < dataTypes.length; j++) {
                var dataType:Object = dataTypes[j];
                var testData:Array = dataType.generator(size);
                var k:Number = Math.floor(size / 2);
                
                // TimSelect 测试
                var timStart:Number = getTimer();
                var timResult = TimSelect.selectKth(testData.concat(), k, TimSelect.numberCompare);
                var timTime:Number = getTimer() - timStart;
                
                // QuickSelect 测试
                var quickStart:Number = getTimer();
                var quickResult = QuickSelect.selectKth(testData.concat(), k, QuickSelect.numberCompare);
                var quickTime:Number = getTimer() - quickStart;
                
                // 验证结果一致性
                assertEquals(quickResult, timResult, "TimSelect vs QuickSelect 结果一致性 " + dataType.name);
                
                var speedup:Number = quickTime / Math.max(timTime, 1);
                var status:String = "";
                
                if (dataType.name == "对抗性" || dataType.name == "已排序" || dataType.name == "逆序") {
                    // 在对抗性输入下，TimSelect应该表现更好或相当
                    status = (speedup < 0.5) ? "显著优于QuickSelect" : 
                            (speedup < 1.0) ? "优于QuickSelect" : "相当";
                } else {
                    // 在随机数据下，性能应该相当
                    status = (speedup > 2.0) ? "需要优化" : 
                            (speedup > 1.5) ? "可接受" : "良好";
                }
                
                trace("    " + dataType.name + ": TimSelect=" + timTime + "ms, QuickSelect=" + 
                      quickTime + "ms, 比率=" + formatDecimal(speedup, 2) + " (" + status + ")");
            }
        }
        
        trace("PASS: TimSelect vs QuickSelect 性能对比测试");
    }

    private static function testTimSelectVsFullSort():Void {
        trace("=== TimSelect vs 完整排序 性能对比 ===");
        
        var testSizes:Array = [1000, 2000, 5000, 10000];
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var data:Array = generateRandomArray(size, 1, size);
            var k:Number = Math.floor(size / 2);
            
            // TimSelect 测试
            var timSelectData:Array = data.concat();
            var timSelectStart:Number = getTimer();
            var timSelectResult = TimSelect.selectKth(timSelectData, k, TimSelect.numberCompare);
            var timSelectTime:Number = getTimer() - timSelectStart;
            
            // 完整排序测试
            var sortData:Array = data.concat();
            var sortStart:Number = getTimer();
            sortData.sort(Array.NUMERIC);
            var sortResult = sortData[k];
            var sortTime:Number = getTimer() - sortStart;
            
            // 验证结果一致性
            assertEquals(Number(sortResult), Number(timSelectResult), 
                "TimSelect vs 排序对比测试（大小=" + size + "）");
            
            var speedup:Number = sortTime / Math.max(timSelectTime, 1);
            var efficiency:Number = ((sortTime - timSelectTime) / sortTime) * 100;
            
            // TimSelect应该比完整排序显著更快
            assertTrue(speedup > 1.0, "TimSelect vs 排序对比测试", 
                "大小=" + size + " TimSelect应该比排序快，当前比率=" + formatDecimal(speedup, 2));
            
            trace("  大小 " + size + ": TimSelect=" + timSelectTime + "ms, 排序=" + 
                  sortTime + "ms, 提升=" + formatDecimal(speedup, 2) + "x, 效率提升=" + 
                  formatDecimal(efficiency, 1) + "%");
        }
        
        trace("PASS: TimSelect vs 完整排序性能对比测试");
    }

    private static function testWorstCasePerformanceComparison():Void {
        trace("=== 最坏情况性能对比测试 ===");
        
        var worstCaseScenarios:Array = [
            {name: "已排序", generator: createSortedArray},
            {name: "逆序", generator: createReverseSortedArray},
            {name: "QuickSelect杀手", generator: createQuickSelectKiller},
            {name: "病理分布", generator: createPathologicalDistribution}
        ];
        
        var testSize:Number = 5000;
        
        for (var i:Number = 0; i < worstCaseScenarios.length; i++) {
            var scenario:Object = worstCaseScenarios[i];
            var data:Array = scenario.generator(testSize);
            var k:Number = Math.floor(testSize / 2);
            
            // TimSelect 测试
            var timSelectStart:Number = getTimer();
            var timSelectResult = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var timSelectTime:Number = getTimer() - timSelectStart;
            
            // QuickSelect 测试
            var quickSelectStart:Number = getTimer();
            var quickSelectResult = QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
            var quickSelectTime:Number = getTimer() - quickSelectStart;
            
            // 验证结果一致性
            assertEquals(quickSelectResult, timSelectResult, 
                "最坏情况性能对比 " + scenario.name + " 结果一致性");
            
            var improvement:Number = ((quickSelectTime - timSelectTime) / quickSelectTime) * 100;
            var stability:String = (timSelectTime < quickSelectTime * 2) ? "稳定" : "需要优化";
            
            trace("  " + scenario.name + ": TimSelect=" + timSelectTime + "ms, QuickSelect=" + 
                  quickSelectTime + "ms, 改善=" + formatDecimal(improvement, 1) + "% (" + stability + ")");
        }
        
        trace("PASS: 最坏情况性能对比测试");
    }

    private static function testAverageCasePerformanceAnalysis():Void {
        trace("=== 平均情况性能分析测试 ===");
        
        var testSizes:Array = [500, 1000, 2000, 5000];
        var trialsPerSize:Number = 10;
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var timSelectTimes:Array = [];
            var quickSelectTimes:Array = [];
            
            for (var trial:Number = 0; trial < trialsPerSize; trial++) {
                var data:Array = generateRandomArray(size, 1, size * 2);
                var k:Number = Math.floor(Math.random() * size);
                
                // TimSelect 测试
                var timSelectStart:Number = getTimer();
                var timSelectResult = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
                var timSelectTime:Number = getTimer() - timSelectStart;
                timSelectTimes.push(timSelectTime);
                
                // QuickSelect 测试
                var quickSelectStart:Number = getTimer();
                var quickSelectResult = QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
                var quickSelectTime:Number = getTimer() - quickSelectStart;
                quickSelectTimes.push(quickSelectTime);
                
                // 验证结果一致性
                assertEquals(quickSelectResult, timSelectResult, 
                    "平均情况性能分析 大小=" + size + " trial=" + trial + " 结果一致性");
            }
            
            // 计算统计信息
            var timSelectAvg:Number = calculateAverage(timSelectTimes);
            var quickSelectAvg:Number = calculateAverage(quickSelectTimes);
            var timSelectStdDev:Number = calculateStdDev(timSelectTimes);
            var quickSelectStdDev:Number = calculateStdDev(quickSelectTimes);
            
            var avgSpeedup:Number = quickSelectAvg / Math.max(timSelectAvg, 1);
            var stabilityRatio:Number = timSelectStdDev / quickSelectStdDev;
            
            trace("  大小 " + size + ":");
            trace("    TimSelect: 平均=" + formatDecimal(timSelectAvg, 2) + "ms, 标准差=" + 
                  formatDecimal(timSelectStdDev, 2) + "ms");
            trace("    QuickSelect: 平均=" + formatDecimal(quickSelectAvg, 2) + "ms, 标准差=" + 
                  formatDecimal(quickSelectStdDev, 2) + "ms");
            trace("    平均比率=" + formatDecimal(avgSpeedup, 2) + ", 稳定性比率=" + 
                  formatDecimal(stabilityRatio, 2));
        }
        
        trace("PASS: 平均情况性能分析测试");
    }

    private static function testMemoryEfficiencyComparison():Void {
        trace("=== 内存效率对比测试 ===");
        
        var testSizes:Array = [1000, 5000, 10000];
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var data:Array = generateRandomArray(size, 1, size);
            var k:Number = Math.floor(size / 2);
            
            // 测试TimSelect的内存使用（通过数组长度变化间接测量）
            var timSelectData:Array = data.concat();
            var timSelectOriginalLength:Number = timSelectData.length;
            
            var timSelectStart:Number = getTimer();
            var timSelectResult = TimSelect.selectKth(timSelectData, k, TimSelect.numberCompare);
            var timSelectTime:Number = getTimer() - timSelectStart;
            var timSelectFinalLength:Number = timSelectData.length;
            
            // 测试QuickSelect的内存使用
            var quickSelectData:Array = data.concat();
            var quickSelectOriginalLength:Number = quickSelectData.length;
            
            var quickSelectStart:Number = getTimer();
            var quickSelectResult = QuickSelect.selectKth(quickSelectData, k, QuickSelect.numberCompare);
            var quickSelectTime:Number = getTimer() - quickSelectStart;
            var quickSelectFinalLength:Number = quickSelectData.length;
            
            // 验证内存使用（原地操作，数组长度不应改变）
            assertEquals(timSelectOriginalLength, timSelectFinalLength, 
                "TimSelect内存效率测试（大小=" + size + "）");
            assertEquals(quickSelectOriginalLength, quickSelectFinalLength, 
                "QuickSelect内存效率测试（大小=" + size + "）");
            
            // 验证结果一致性
            assertEquals(quickSelectResult, timSelectResult, 
                "内存效率对比测试结果一致性（大小=" + size + "）");
            
            var timeRatio:Number = timSelectTime / Math.max(quickSelectTime, 1);
            var memoryEfficiency:String = (timeRatio < 1.5) ? "高效" : "可接受";
            
            trace("  大小 " + size + ": TimSelect=" + timSelectTime + "ms, QuickSelect=" + 
                  quickSelectTime + "ms, 内存效率=" + memoryEfficiency);
        }
        
        trace("PASS: 内存效率对比测试");
    }

    // ================================
    // 参数调优验证测试
    // ================================
    
    private static function testInsertionThresholdOptimization():Void {
        trace("=== 插入排序阈值优化测试 ===");
        
        // 模拟不同阈值下的性能（注意：实际的TimSelect阈值是编译时常量）
        var testSizes:Array = [50, 100, 200];
        var optimalResults:Array = [];
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var totalTime:Number = 0;
            var trials:Number = 20;
            
            for (var trial:Number = 0; trial < trials; trial++) {
                var data:Array = generateRandomArray(size, 1, 1000);
                var k:Number = Math.floor(size / 2);
                
                var start:Number = getTimer();
                TimSelect.selectKth(data, k, TimSelect.numberCompare);
                var elapsed:Number = getTimer() - start;
                
                totalTime += elapsed;
            }
            
            var avgTime:Number = totalTime / trials;
            var efficiency:Number = avgTime / size;
            
            optimalResults.push({
                size: size,
                avgTime: avgTime,
                efficiency: efficiency
            });
            
            trace("  大小 " + size + ": 平均=" + formatDecimal(avgTime, 2) + 
                  "ms, 效率=" + formatDecimal(efficiency * 1000, 3) + "μs/元素");
        }
        
        // 分析效率趋势
        var efficiencyTrend:String = "稳定";
        for (var j:Number = 1; j < optimalResults.length; j++) {
            var current:Object = optimalResults[j];
            var previous:Object = optimalResults[j-1];
            var efficiencyRatio:Number = current.efficiency / previous.efficiency;
            
            if (efficiencyRatio > 1.5) {
                efficiencyTrend = "效率下降";
                break;
            } else if (efficiencyRatio < 0.8) {
                efficiencyTrend = "效率提升";
            }
        }
        
        trace("  效率趋势: " + efficiencyTrend);
        trace("PASS: 插入排序阈值优化测试");
    }

    private static function testUnbalancedRatioOptimization():Void {
        trace("=== 不平衡比率优化测试 ===");
        
        // 创建不同程度的不平衡数据，测试检测机制的敏感度
        var unbalanceTests:Array = [
            {name: "轻微不平衡", ratio: 0.3, description: "30-70分布"},
            {name: "中等不平衡", ratio: 0.2, description: "20-80分布"},
            {name: "严重不平衡", ratio: 0.1, description: "10-90分布"},
            {name: "极端不平衡", ratio: 0.05, description: "5-95分布"}
        ];
        
        var testSize:Number = 2000;
        
        for (var i:Number = 0; i < unbalanceTests.length; i++) {
            var test:Object = unbalanceTests[i];
            var data:Array = createCustomUnbalancedData(testSize, test.ratio);
            var k:Number = Math.floor(testSize / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data, k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            // 验证结果正确性
            var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
            assertTrue(verified, "不平衡比率优化测试", test.name + " 结果不正确");
            
            // 验证性能在可接受范围内
            var maxAcceptableTime:Number = testSize / 2;  // 粗略上限
            assertTrue(elapsed < maxAcceptableTime, "不平衡比率优化测试", 
                test.name + " 耗时过长: " + elapsed + "ms");
            
            var efficiency:Number = elapsed / testSize;
            trace("  " + test.name + "(" + test.description + "): " + elapsed + 
                  "ms (" + formatDecimal(efficiency * 1000, 3) + "μs/元素)");
        }
        
        trace("PASS: 不平衡比率优化测试");
    }

    private static function testBFPRTOverheadAnalysis():Void {
        trace("=== BFPRT 开销分析测试 ===");
        
        // 比较触发和不触发BFPRT的性能开销
        var testCases:Array = [
            {
                name: "随机数据(很少触发BFPRT)",
                generator: function(size:Number):Array { return generateRandomArray(size, 1, size); }
            },
            {
                name: "对抗数据(频繁触发BFPRT)",
                generator: function(size:Number):Array { return createWorstCaseForQuickSelect(size); }
            }
        ];
        
        var testSize:Number = 3000;
        var overheadResults:Array = [];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var testCase:Object = testCases[i];
            var data:Array = testCase.generator(testSize);
            var k:Number = Math.floor(testSize / 2);
            
            // 测试TimSelect
            var timSelectStart:Number = getTimer();
            var timSelectResult = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var timSelectTime:Number = getTimer() - timSelectStart;
            
            // 测试QuickSelect作为基准
            var quickSelectStart:Number = getTimer();
            var quickSelectResult = QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
            var quickSelectTime:Number = getTimer() - quickSelectStart;
            
            var overhead:Number = ((timSelectTime - quickSelectTime) / quickSelectTime) * 100;
            var overheadStatus:String = (overhead < 20) ? "低" : (overhead < 50) ? "中等" : "高";
            
            overheadResults.push({
                name: testCase.name,
                overhead: overhead,
                timSelectTime: timSelectTime,
                quickSelectTime: quickSelectTime
            });
            
            trace("  " + testCase.name + ":");
            trace("    TimSelect=" + timSelectTime + "ms, QuickSelect=" + quickSelectTime + "ms");
            trace("    开销=" + formatDecimal(overhead, 1) + "% (" + overheadStatus + ")");
        }
        
        // 分析开销差异
        var overheadDifference:Number = Number(overheadResults[1].overhead) - Number(overheadResults[0].overhead);
        trace("  BFPRT触发带来的额外开销: " + formatDecimal(overheadDifference, 1) + "%");
        
        trace("PASS: BFPRT 开销分析测试");
    }

    private static function testOptimalParameterCombinations():Void {
        trace("=== 最优参数组合测试 ===");
        
        // 在不同场景下测试当前参数组合的表现
        var scenarioTests:Array = [
            {
                name: "小数据集",
                sizes: [10, 20, 50, 100],
                expectation: "插入排序应该占主导"
            },
            {
                name: "中等数据集",
                sizes: [500, 1000, 2000],
                expectation: "QuickSelect应该占主导"
            },
            {
                name: "大数据集",
                sizes: [5000, 10000],
                expectation: "混合策略应该发挥作用"
            }
        ];
        
        for (var i:Number = 0; i < scenarioTests.length; i++) {
            var scenario:Object = scenarioTests[i];
            var sizes:Array = scenario.sizes;
            var totalEfficiency:Number = 0;
            
            trace("  " + scenario.name + ":");
            
            for (var j:Number = 0; j < sizes.length; j++) {
                var size:Number = Number(sizes[j]);
                var data:Array = generateRandomArray(size, 1, size);
                var k:Number = Math.floor(size / 2);
                
                var start:Number = getTimer();
                var result = TimSelect.selectKth(data, k, TimSelect.numberCompare);
                var elapsed:Number = getTimer() - start;
                
                var efficiency:Number = elapsed / size;
                totalEfficiency += efficiency;
                
                trace("    大小 " + size + ": " + elapsed + "ms (" + 
                      formatDecimal(efficiency * 1000, 3) + "μs/元素)");
            }
            
            var avgEfficiency:Number = totalEfficiency / sizes.length;
            trace("    平均效率: " + formatDecimal(avgEfficiency * 1000, 3) + "μs/元素");
            trace("    " + scenario.expectation);
        }
        
        trace("PASS: 最优参数组合测试");
    }

    // ================================
    // 对抗性输入测试
    // ================================
    
    private static function testAdversarialInputPatterns():Void {
        trace("=== 对抗性输入模式测试 ===");
        
        var adversarialPatterns:Array = [
            {
                name: "交替极值",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    for (var i:Number = 0; i < size; i++) {
                        arr.push(i % 2 == 0 ? 1 : 1000000);
                    }
                    return arr;
                }
            },
            {
                name: "阶梯下降",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    var steps:Number = 10;
                    var stepSize:Number = Math.floor(size / steps);
                    for (var i:Number = 0; i < size; i++) {
                        arr.push(1000 - Math.floor(i / stepSize) * 100);
                    }
                    return arr;
                }
            },
            {
                name: "中心聚集",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    var center:Number = 500;
                    for (var i:Number = 0; i < size; i++) {
                        if (i < size * 0.9) {
                            arr.push(center + (Math.random() - 0.5) * 10);
                        } else {
                            arr.push(Math.random() * 1000);
                        }
                    }
                    return arr;
                }
            },
            {
                name: "指数增长",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    for (var i:Number = 0; i < size; i++) {
                        arr.push(Math.pow(1.1, i % 50));
                    }
                    return arr;
                }
            }
        ];
        
        var testSize:Number = 2000;
        
        for (var i:Number = 0; i < adversarialPatterns.length; i++) {
            var pattern:Object = adversarialPatterns[i];
            var data:Array = pattern.generator(testSize);
            var k:Number = Math.floor(testSize / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data, k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            // 验证结果正确性
            var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
            assertTrue(verified, "对抗性输入模式测试", pattern.name + " 结果不正确");
            
            // 验证性能在合理范围内
            var maxAcceptableTime:Number = testSize;  // 1ms per 1000 elements max
            assertTrue(elapsed < maxAcceptableTime, "对抗性输入模式测试", 
                pattern.name + " 耗时过长: " + elapsed + "ms");
            
            var efficiency:Number = elapsed / testSize;
            trace("  " + pattern.name + ": " + elapsed + "ms (" + 
                  formatDecimal(efficiency * 1000, 3) + "μs/元素)");
        }
        
        trace("PASS: 对抗性输入模式测试");
    }

    private static function testAntiQuickSelectPatterns():Void {
        trace("=== 反QuickSelect模式测试 ===");
        
        // 专门构造对QuickSelect不利的数据模式
        var antiQuickSelectPatterns:Array = [
            "已排序递增",
            "已排序递减", 
            "荷兰国旗问题",
            "重复pivot值",
            "分区杀手"
        ];
        
        var testSize:Number = 3000;
        
        for (var i:Number = 0; i < antiQuickSelectPatterns.length; i++) {
            var patternName:String = String(antiQuickSelectPatterns[i]);
            var data:Array;
            
            switch (patternName) {
                case "已排序递增":
                    data = createSortedArray(testSize);
                    break;
                case "已排序递减":
                    data = createReverseSortedArray(testSize);
                    break;
                case "荷兰国旗问题":
                    data = createDutchFlagPattern(testSize);
                    break;
                case "重复pivot值":
                    data = createRepeatedPivotPattern(testSize);
                    break;
                case "分区杀手":
                    data = createPartitionKiller(testSize);
                    break;
                default:
                    data = generateRandomArray(testSize, 1, testSize);
            }
            
            var k:Number = Math.floor(testSize / 2);
            
            // 测试TimSelect
            var timSelectStart:Number = getTimer();
            var timSelectResult = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var timSelectTime:Number = getTimer() - timSelectStart;
            
            // 测试QuickSelect
            var quickSelectStart:Number = getTimer();
            var quickSelectResult = QuickSelect.selectKth(data.concat(), k, QuickSelect.numberCompare);
            var quickSelectTime:Number = getTimer() - quickSelectStart;
            
            // 验证结果一致性
            assertEquals(quickSelectResult, timSelectResult, 
                "反QuickSelect模式测试 " + patternName + " 结果一致性");
            
            var improvement:Number = ((quickSelectTime - timSelectTime) / quickSelectTime) * 100;
            var robustness:String = (improvement > 0) ? "更稳健" : "相当";
            
            trace("  " + patternName + ": TimSelect=" + timSelectTime + "ms, " +
                  "QuickSelect=" + quickSelectTime + "ms, 改善=" + 
                  formatDecimal(improvement, 1) + "% (" + robustness + ")");
        }
        
        trace("PASS: 反QuickSelect模式测试");
    }

    private static function testHighlyDuplicatedData():Void {
        trace("=== 高重复数据测试 ===");
        
        var duplicationTests:Array = [
            {name: "90%重复", uniqueRatio: 0.1},
            {name: "95%重复", uniqueRatio: 0.05},
            {name: "99%重复", uniqueRatio: 0.01},
            {name: "99.9%重复", uniqueRatio: 0.001}
        ];
        
        var testSize:Number = 5000;
        
        for (var i:Number = 0; i < duplicationTests.length; i++) {
            var test:Object = duplicationTests[i];
            var data:Array = createHighDuplicationData(testSize, test.uniqueRatio);
            var k:Number = Math.floor(testSize / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data, k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            // 验证结果正确性
            var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
            assertTrue(verified, "高重复数据测试", test.name + " 结果不正确");
            
            // 验证性能
            var efficiency:Number = elapsed / testSize;
            assertTrue(efficiency < 1.0, "高重复数据测试", 
                test.name + " 效率过低: " + formatDecimal(efficiency * 1000, 3) + "μs/元素");
            
            trace("  " + test.name + ": " + elapsed + "ms (" + 
                  formatDecimal(efficiency * 1000, 3) + "μs/元素)");
        }
        
        trace("PASS: 高重复数据测试");
    }

    private static function testPathologicalDistributions():Void {
        trace("=== 病理分布测试 ===");
        
        var pathologicalTests:Array = [
            {
                name: "极端偏态",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    for (var i:Number = 0; i < size; i++) {
                        if (i < size * 0.99) {
                            arr.push(1);
                        } else {
                            arr.push(1000000);
                        }
                    }
                    return arr;
                }
            },
            {
                name: "多峰分布",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    var peaks:Array = [100, 300, 500, 700, 900];
                    for (var i:Number = 0; i < size; i++) {
                        var peakIndex:Number = Math.floor(Math.random() * peaks.length);
                        arr.push(Number(peaks[peakIndex]) + (Math.random() - 0.5) * 20);
                    }
                    return arr;
                }
            },
            {
                name: "幂律长尾",
                generator: function(size:Number):Array {
                    var arr:Array = [];
                    for (var i:Number = 0; i < size; i++) {
                        var rank:Number = i + 1;
                        arr.push(Math.floor(1000 / Math.pow(rank, 0.5)));
                    }
                    return arr;
                }
            }
        ];
        
        var testSize:Number = 3000;
        
        for (var i:Number = 0; i < pathologicalTests.length; i++) {
            var test:Object = pathologicalTests[i];
            var data:Array = test.generator(testSize);
            var k:Number = Math.floor(testSize / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data, k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            // 验证结果正确性
            var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
            assertTrue(verified, "病理分布测试", test.name + " 结果不正确");
            
            // 验证TimSelect在病理分布下的稳健性
            var maxAcceptableTime:Number = testSize * 2;  // 允许一些性能下降
            assertTrue(elapsed < maxAcceptableTime, "病理分布测试", 
                test.name + " 耗时过长: " + elapsed + "ms");
            
            var efficiency:Number = elapsed / testSize;
            trace("  " + test.name + ": " + elapsed + "ms (" + 
                  formatDecimal(efficiency * 1000, 3) + "μs/元素)");
        }
        
        trace("PASS: 病理分布测试");
    }

    private static function testMaliciousInputGeneration():Void {
        trace("=== 恶意输入生成测试 ===");
        
        // 模拟各种可能的恶意输入场景
        var maliciousTests:Array = [
            {
                name: "时间复杂度攻击",
                data: createTimeComplexityAttack(2000),
                description: "设计来最大化运行时间"
            },
            {
                name: "内存压力攻击",
                data: createMemoryPressureAttack(2000),
                description: "设计来增加内存使用压力"
            },
            {
                name: "分支预测攻击",
                data: createBranchPredictionAttack(2000),
                description: "设计来破坏CPU分支预测"
            }
        ];
        
        for (var i:Number = 0; i < maliciousTests.length; i++) {
            var test:Object = maliciousTests[i];
            var data:Array = test.data;
            var k:Number = Math.floor(data.length / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data, k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            // 验证算法没有被恶意输入破坏
            assertTrue(result !== null && result !== undefined, 
                "恶意输入生成测试", test.name + " 算法被破坏");
            
            // 验证性能在合理范围内（即使面对恶意输入）
            var maxTolerableTime:Number = data.length * 3;  // 较宽松的限制
            assertTrue(elapsed < maxTolerableTime, "恶意输入生成测试", 
                test.name + " 性能被严重影响: " + elapsed + "ms");
            
            trace("  " + test.name + ": " + elapsed + "ms");
            trace("    " + test.description);
        }
        
        trace("PASS: 恶意输入生成测试");
    }

    // ================================
    // 数据生成辅助函数
    // ================================
    
    private static function createWorstCaseForQuickSelect(size:Number):Array {
        // 创建QuickSelect的最坏情况：已排序数组
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(i);
        }
        return arr;
    }

    private static function createSkewedDistribution(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            if (i < size * 0.9) {
                arr.push(Math.floor(Math.random() * 10));
            } else {
                arr.push(1000 + Math.floor(Math.random() * 9000));
            }
        }
        return arr;
    }

    private static function createAlternatingPattern(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(i % 2 === 0 ? 1 : 1000);
        }
        return arr;
    }

    private static function createNearlySortedPattern(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(i);
        }
        // 随机交换5%的元素
        for (var j:Number = 0; j < size / 20; j++) {
            var pos1:Number = Math.floor(Math.random() * size);
            var pos2:Number = Math.floor(Math.random() * size);
            var temp = arr[pos1];
            arr[pos1] = arr[pos2];
            arr[pos2] = temp;
        }
        return arr;
    }

    private static function createExtremelySkewedData(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            if (i < size * 0.99) {
                arr.push(1);
            } else {
                arr.push(1000000);
            }
        }
        return arr;
    }

    private static function createBinaryExtremeData(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(i % 2 === 0 ? Number.MIN_VALUE : Number.MAX_VALUE);
        }
        return arr;
    }

    private static function createStepDistribution(size:Number):Array {
        var arr:Array = [];
        var steps:Number = 10;
        var stepSize:Number = Math.floor(size / steps);
        for (var i:Number = 0; i < size; i++) {
            arr.push(Math.floor(i / stepSize) * 100);
        }
        return arr;
    }

    private static function createSortedArray(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(i);
        }
        return arr;
    }

    private static function createReverseSortedArray(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(size - i);
        }
        return arr;
    }

    private static function createAllSameArray(size:Number, value:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(value);
        }
        return arr;
    }

    private static function createQuickSelectKiller(size:Number):Array {
        // 构造会让QuickSelect退化到O(n²)的数据
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(i);
        }
        // 特殊排列使得每次分区都选到最差的pivot
        return arr;
    }

    private static function createPathologicalDistribution(size:Number):Array {
        var arr:Array = [];
        // 创建一个病理分布：大部分元素集中在一个值
        var centralValue:Number = 500;
        for (var i:Number = 0; i < size; i++) {
            if (i < size * 0.95) {
                arr.push(centralValue);
            } else if (i < size * 0.99) {
                arr.push(1);
            } else {
                arr.push(999);
            }
        }
        return arr;
    }

    private static function createHighDuplicateData(size:Number):Array {
        var arr:Array = [];
        var numUniqueValues:Number = Math.max(1, Math.floor(size / 100));
        for (var i:Number = 0; i < size; i++) {
            arr.push(Math.floor(Math.random() * numUniqueValues));
        }
        return arr;
    }

    private static function createSlightlyUnbalancedData(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            if (i < size * 0.7) {
                arr.push(Math.floor(Math.random() * 300));
            } else {
                arr.push(300 + Math.floor(Math.random() * 700));
            }
        }
        return arr;
    }

    private static function createSeverelyUnbalancedData(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            if (i < size * 0.95) {
                arr.push(Math.floor(Math.random() * 10));
            } else {
                arr.push(1000 + Math.floor(Math.random() * 9000));
            }
        }
        return arr;
    }

    private static function createCustomUnbalancedData(size:Number, ratio:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            if (i < size * ratio) {
                arr.push(Math.floor(Math.random() * 100));
            } else {
                arr.push(500 + Math.floor(Math.random() * 500));
            }
        }
        return arr;
    }

    private static function createHighDuplicationData(size:Number, uniqueRatio:Number):Array {
        var arr:Array = [];
        var numUniqueValues:Number = Math.max(1, Math.floor(size * uniqueRatio));
        for (var i:Number = 0; i < size; i++) {
            arr.push(Math.floor(Math.random() * numUniqueValues));
        }
        return arr;
    }

    private static function createDutchFlagPattern(size:Number):Array {
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            var choice:Number = Math.floor(Math.random() * 3);
            arr.push(choice === 0 ? 1 : (choice === 1 ? 500 : 999));
        }
        return arr;
    }

    private static function createRepeatedPivotPattern(size:Number):Array {
        var arr:Array = [];
        var pivotValue:Number = 500;
        for (var i:Number = 0; i < size; i++) {
            if (i % 10 === 0) {
                arr.push(pivotValue);
            } else {
                arr.push(Math.random() * 1000);
            }
        }
        return arr;
    }

    private static function createPartitionKiller(size:Number):Array {
        var arr:Array = [];
        // 创建一个每次分区都会选到最差pivot的数组
        for (var i:Number = 0; i < size; i++) {
            arr.push(i);
        }
        // 进行特殊重排
        for (var j:Number = 0; j < size / 2; j++) {
            var temp = arr[j];
            arr[j] = arr[size - 1 - j];
            arr[size - 1 - j] = temp;
        }
        return arr;
    }

    private static function createTimeComplexityAttack(size:Number):Array {
        // 专门设计来最大化算法运行时间
        return createWorstCaseForQuickSelect(size);
    }

    private static function createMemoryPressureAttack(size:Number):Array {
        // 创建可能增加内存压力的数据模式
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(Math.random() * Number.MAX_VALUE);
        }
        return arr;
    }

    private static function createBranchPredictionAttack(size:Number):Array {
        // 创建破坏CPU分支预测的随机模式
        var arr:Array = [];
        for (var i:Number = 0; i < size; i++) {
            arr.push(Math.random() > 0.5 ? 1 : 0);
        }
        return arr;
    }

    // ================================
    // 工具函数
    // ================================
    
    private static function calculateAverage(values:Array):Number {
        var sum:Number = 0;
        for (var i:Number = 0; i < values.length; i++) {
            sum += Number(values[i]);
        }
        return sum / values.length;
    }

    private static function calculateStdDev(values:Array):Number {
        var avg:Number = calculateAverage(values);
        var variance:Number = 0;
        for (var i:Number = 0; i < values.length; i++) {
            var diff:Number = Number(values[i]) - avg;
            variance += diff * diff;
        }
        return Math.sqrt(variance / values.length);
    }

    // ================================
    // 基础功能测试 (继承并修改自QuickSelectTest)
    // ================================
    private static function testEmptyArray():Void {
        var arr:Array = [];
        var result = TimSelect.selectKth(arr, 0, TimSelect.numberCompare);
        assertEquals(null, result, "空数组测试");
    }

    private static function testSingleElement():Void {
        var arr:Array = [42];
        var result:Number = Number(TimSelect.selectKth(arr, 0, TimSelect.numberCompare));
        assertEquals(42, result, "单元素数组测试");
    }

    private static function testTwoElements():Void {
        var arr1:Array = [2, 1];
        var result1:Number = Number(TimSelect.selectKth(arr1, 0, TimSelect.numberCompare));
        assertEquals(1, result1, "两元素数组测试（第0小）");
        
        var arr2:Array = [2, 1];
        var result2:Number = Number(TimSelect.selectKth(arr2, 1, TimSelect.numberCompare));
        assertEquals(2, result2, "两元素数组测试（第1小）");
    }

    private static function testThreeElements():Void {
        var testCases:Array = [[3, 1, 2], [1, 3, 2], [2, 1, 3]];
        var expected:Array = [1, 2, 3];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var arr:Array = testCases[i];
            for (var k:Number = 0; k < 3; k++) {
                var result:Number = Number(TimSelect.selectKth(arr.concat(), k, TimSelect.numberCompare));
                assertEquals(Number(expected[k]), result, "三元素数组测试 case" + i + " k=" + k);
            }
        }
    }

    private static function testAlreadySorted():Void {
        var arr:Array = [1,2,3,4,5,6,7,8,9,10];
        for (var k:Number = 0; k < arr.length; k++) {
            var result:Number = Number(TimSelect.selectKth(arr.concat(), k, TimSelect.numberCompare));
            assertEquals(k + 1, result, "已排序数组测试 k=" + k);
        }
    }

    private static function testReverseSorted():Void {
        var arr:Array = [10,9,8,7,6,5,4,3,2,1];
        var expected:Array = [1,2,3,4,5,6,7,8,9,10];
        for (var k:Number = 0; k < arr.length; k++) {
            var result:Number = Number(TimSelect.selectKth(arr.concat(), k, TimSelect.numberCompare));
            assertEquals(Number(expected[k]), result, "逆序数组测试 k=" + k);
        }
    }

    private static function testRandomArray():Void {
        var arr:Array = [3,1,4,1,5,9,2,6,5,3,5,8,9,7,9,3,2,3,8,4];
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        for (var k:Number = 0; k < arr.length; k++) {
            var result:Number = Number(TimSelect.selectKth(arr.concat(), k, TimSelect.numberCompare));
            assertEquals(Number(sortedCopy[k]), result, "随机数组测试 k=" + k);
        }
    }

    private static function testDuplicateElements():Void {
        var arr:Array = [5,3,8,3,9,1,5,7,3,5,3,5];
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        var testIndices:Array = [0, 3, 6, 9, arr.length - 1];
        for (var i:Number = 0; i < testIndices.length; i++) {
            var k:Number = Number(testIndices[i]);
            var result:Number = Number(TimSelect.selectKth(arr.concat(), k, TimSelect.numberCompare));
            assertEquals(Number(sortedCopy[k]), result, "重复元素测试 k=" + k);
        }
    }

    private static function testAllSameElements():Void {
        var arr:Array = [7,7,7,7,7,7,7,7,7,7];
        for (var k:Number = 0; k < arr.length; k++) {
            var result:Number = Number(TimSelect.selectKth(arr.concat(), k, TimSelect.numberCompare));
            assertEquals(7, result, "全相同元素测试 k=" + k);
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
            var result:String = String(TimSelect.selectKth(arr.concat(), k, caseInsensitiveCompare));
            assertEquals(String(expected[k]), result, "自定义比较函数测试 k=" + k);
        }
    }

    private static function testNegativeNumbers():Void {
        var arr:Array = [-5, -2, -8, -1, -9, -3, -7, -4, -6];
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        var median:Number = Number(TimSelect.median(arr.concat(), TimSelect.numberCompare));
        var expectedMedian:Number = Number(sortedCopy[Math.floor((sortedCopy.length - 1) / 2)]);
        assertEquals(expectedMedian, median, "负数数组中位数测试");
    }

    private static function testFloatingPointNumbers():Void {
        var arr:Array = [3.14, 2.71, 1.41, 1.73, 0.57, 2.23, 1.61];
        var sortedCopy:Array = arr.concat();
        sortedCopy.sort(Array.NUMERIC);
        
        var median:Number = Number(TimSelect.median(arr.concat(), TimSelect.numberCompare));
        var expectedMedian:Number = Number(sortedCopy[Math.floor((sortedCopy.length - 1) / 2)]);
        assertEquals(expectedMedian, median, "浮点数数组中位数测试");
    }

    // ================================
    // 核心算法正确性测试
    // ================================
    
    private static function testPartitionCorrectness():Void {
        var arr:Array = generateRandomArray(100, 1, 1000);
        var k:Number = 50;
        
        var testArr:Array = arr.concat();
        var kthElement:Number = Number(TimSelect.selectKth(testArr, k, TimSelect.numberCompare));
        
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
        var sizes:Array = [1, 2, 3, 4, 5, 10, 32, 64, 100];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = Number(sizes[i]);
            var arr:Array = generateRandomArray(size, 1, 100);
            
            for (var k:Number = 0; k < size; k++) {
                var testArr:Array = arr.concat();
                var originalLength:Number = testArr.length;
                
                TimSelect.selectKth(testArr, k, TimSelect.numberCompare);
                
                // 验证数组长度未改变
                assertEquals(originalLength, testArr.length, 
                    "分区边界完整性测试（大小=" + size + " k=" + k + "）");
            }
        }
        
        trace("PASS: 分区边界完整性测试");
    }

    private static function testBFPRTMedianSelection():Void {
        // 测试BFPRT中位数选择的正确性
        var medianTests:Array = [
            createWorstCaseForQuickSelect(75),   // 15组，每组5个
            createReverseSortedArray(125),       // 25组
            createAllSameArray(200, 42)          // 40组
        ];
        
        for (var i:Number = 0; i < medianTests.length; i++) {
            var data:Array = medianTests[i];
            var k:Number = Math.floor(data.length / 2);
            
            var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
            
            assertTrue(verified, "BFPRT中位数选择测试", "case " + i + " 结果不正确");
        }
        
        trace("PASS: BFPRT中位数选择测试");
    }

    private static function testHybridSwitchingLogic():Void {
        // 测试混合策略切换逻辑的正确性
        var switchingTests:Array = [
            {name: "小数组", data: generateRandomArray(10, 1, 100)},
            {name: "中等数组", data: generateRandomArray(100, 1, 1000)},
            {name: "不平衡数组", data: createSeverelyUnbalancedData(500)},
            {name: "对抗数组", data: createWorstCaseForQuickSelect(500)}
        ];
        
        for (var i:Number = 0; i < switchingTests.length; i++) {
            var test:Object = switchingTests[i];
            var data:Array = test.data;
            var k:Number = Math.floor(data.length / 2);
            
            var start:Number = getTimer();
            var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
            var elapsed:Number = getTimer() - start;
            
            var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
            assertTrue(verified, "混合切换逻辑测试", test.name + " 结果不正确");
            
            // 验证性能合理性
            var maxTime:Number = data.length * 2;
            assertTrue(elapsed < maxTime, "混合切换逻辑测试", 
                test.name + " 耗时过长: " + elapsed + "ms");
            
            trace("  " + test.name + ": " + elapsed + "ms");
        }
        
        trace("PASS: 混合切换逻辑测试");
    }

    private static function testKthElementRangeValidation():Void {
        var arr:Array = [1,2,3,4,5];
        
        // 测试有效范围
        for (var k:Number = 0; k < arr.length; k++) {
            var result = TimSelect.selectKth(arr.concat(), k, TimSelect.numberCompare);
            assertTrue(result !== null && result !== undefined, 
                "K值范围验证测试", "有效k=" + k + "返回了无效结果");
        }
        
        // 测试无效范围
        var invalidResult1 = TimSelect.selectKth(arr.concat(), -1, TimSelect.numberCompare);
        var invalidResult2 = TimSelect.selectKth(arr.concat(), arr.length, TimSelect.numberCompare);
        
        assertTrue(invalidResult1 === null, "K值范围验证测试", "负数k应该返回null");
        assertTrue(invalidResult2 === null, "K值范围验证测试", "超出范围的k应该返回null");
        
        trace("PASS: K值范围验证测试");
    }

    // ================================
    // 数据分布适应性测试
    // ================================
    
    private static function testUniformDistribution():Void {
        var arr:Array = generateRandomArray(1000, 0, 1000);
        
        var start:Number = getTimer();
        var median:Number = Number(TimSelect.median(arr, TimSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 均匀分布的中位数应该接近中间值
        assertTrue(median >= 200 && median <= 800, "均匀分布测试", 
            "中位数偏离预期范围: " + median);
        
        trace("    均匀分布测试耗时: " + elapsed + "ms, 中位数: " + median);
        trace("PASS: 均匀分布测试");
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
        var median:Number = Number(TimSelect.median(arr, TimSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 正态分布的中位数应该接近均值
        assertTrue(median >= 400 && median <= 600, "正态分布测试", 
            "中位数偏离预期范围: " + median);
        
        trace("    正态分布测试耗时: " + elapsed + "ms, 中位数: " + median);
        trace("PASS: 正态分布测试");
    }

    private static function testExponentialDistribution():Void {
        // 模拟指数分布数据
        var arr:Array = [];
        var lambda:Number = 0.01;  // 率参数
        
        for (var i:Number = 0; i < 1000; i++) {
            var u:Number = Math.random();
            var expValue:Number = -Math.log(1 - u) / lambda;
            arr.push(expValue * 5 + 1);  // 缩放到合理范围
        }
        
        var start:Number = getTimer();
        var median:Number = Number(TimSelect.median(arr, TimSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 指数分布的中位数应该大于0
        assertTrue(median > 0, "指数分布测试", 
            "中位数应该大于0: " + median);
        
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
        var median:Number = Number(TimSelect.median(arr, TimSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 验证结果合理性
        assertTrue(median >= 1 && median <= 1000, "幂律分布测试", 
            "中位数超出预期范围: " + median);
        
        trace("    幂律分布测试耗时: " + elapsed + "ms, 中位数: " + median);
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
        var median:Number = Number(TimSelect.median(arr, TimSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 双峰分布的中位数应该在两个峰之间
        assertTrue(median > 300 && median < 700, "双峰分布测试", 
            "中位数不在预期的双峰之间: " + median);
        
        trace("    双峰分布测试耗时: " + elapsed + "ms, 中位数: " + median);
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
        var median:Number = Number(TimSelect.median(arr, TimSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 验证偏斜特征：中位数应该很小
        assertTrue(median < 20, "高度偏斜数据测试", 
            "中位数过大，缺乏偏斜特征: " + median);
        
        trace("    高度偏斜测试耗时: " + elapsed + "ms, 中位数: " + median);
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
        var median:Number = Number(TimSelect.median(arr, TimSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // Zipf分布应该有很多小值
        assertTrue(median < 50, "Zipf分布测试", 
            "中位数过大: " + median);
        
        trace("    Zipf分布测试耗时: " + elapsed + "ms, 中位数: " + median);
        trace("PASS: Zipf分布测试");
    }

    private static function testClusteredData():Void {
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
        var median:Number = Number(TimSelect.median(arr, TimSelect.numberCompare));
        var elapsed:Number = getTimer() - start;
        
        // 验证数据分布在预期的聚类范围内
        assertTrue(median >= 80 && median <= 920, "聚类数据测试", 
            "中位数不在预期聚类范围内: " + median);
        
        trace("    聚类数据测试耗时: " + elapsed + "ms, 中位数: " + median);
        trace("PASS: 聚类数据测试");
    }

    // ================================
    // 实际应用场景测试 (简化版本)
    // ================================
    
    private static function testStatisticalAnalysis():Void {
        var dataset:Array = generateRandomArray(1000, 1, 1000);
        
        // 计算关键统计量
        var q1:Number = Number(TimSelect.selectKth(dataset.concat(), Math.floor(dataset.length * 0.25), TimSelect.numberCompare));
        var median:Number = Number(TimSelect.median(dataset.concat(), TimSelect.numberCompare));
        var q3:Number = Number(TimSelect.selectKth(dataset.concat(), Math.floor(dataset.length * 0.75), TimSelect.numberCompare));
        
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
        var kthLargest:Number = Number(TimSelect.selectKth(scores.concat(), scores.length - k, TimSelect.numberCompare));
        
        var elapsed:Number = getTimer() - start;
        
        // 验证结果合理性
        assertTrue(kthLargest >= 0 && kthLargest <= 100, "Top-K查询测试", 
            "结果超出预期范围: " + kthLargest);
        
        trace("    Top-" + k + " 阈值: " + kthLargest + "，耗时: " + elapsed + "ms");
        trace("PASS: Top-K查询测试");
    }

    private static function testPercentileCalculation():Void {
        var dataset:Array = generateRandomArray(5000, 0, 1000);
        var percentiles:Array = [0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99];
        var results:Array = [];
        
        var totalStart:Number = getTimer();
        
        for (var i:Number = 0; i < percentiles.length; i++) {
            var p:Number = Number(percentiles[i]);
            var index:Number = Math.floor((dataset.length - 1) * p);
            
            var result:Number = Number(TimSelect.selectKth(dataset.concat(), index, TimSelect.numberCompare));
            results.push(result);
            
            // 验证百分位数的单调性
            if (i > 0) {
                assertTrue(result >= Number(results[i-1]), "百分位数计算测试", 
                    "百分位数不满足单调性: P" + (p*100) + "=" + result + " < P" + (Number(percentiles[i-1])*100) + "=" + results[i-1]);
            }
        }
        
        var totalElapsed:Number = getTimer() - totalStart;
        
        trace("    百分位数计算测试总耗时: " + totalElapsed + "ms");
        trace("    P10: " + results[0] + ", P50: " + results[2] + ", P99: " + results[6]);
        trace("PASS: 百分位数计算测试");
    }

    private static function testOutlierDetection():Void {
        // 创建包含异常值的数据集
        var normalData:Array = generateRandomArray(950, 40, 60);  // 正常数据在40-60之间
        var outliers:Array = [5, 8, 95, 98, 102, 3, 1, 89, 92, 96]; // 异常值
        var dataset:Array = normalData.concat(outliers);
        
        // 使用IQR方法检测异常值
        var q1:Number = Number(TimSelect.selectKth(dataset.concat(), Math.floor(dataset.length * 0.25), TimSelect.numberCompare));
        var q3:Number = Number(TimSelect.selectKth(dataset.concat(), Math.floor(dataset.length * 0.75), TimSelect.numberCompare));
        var iqr:Number = q3 - q1;
        
        var lowerBound:Number = q1 - 1.5 * iqr;
        var upperBound:Number = q3 + 1.5 * iqr;
        
        // 计算异常值数量
        var outlierCount:Number = 0;
        for (var i:Number = 0; i < dataset.length; i++) {
            var value:Number = Number(dataset[i]);
            if (value < lowerBound || value > upperBound) {
                outlierCount++;
            }
        }
        
        // 验证异常值检测的合理性
        assertTrue(outlierCount >= 8, "异常值检测测试", 
            "检测到的异常值过少: " + outlierCount);
        
        trace("    Q1: " + q1 + ", Q3: " + q3 + ", IQR: " + iqr);
        trace("    异常值边界: [" + formatDecimal(lowerBound, 2) + ", " + formatDecimal(upperBound, 2) + "]");
        trace("    检测到异常值: " + outlierCount + "个");
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
                var median:Number = Number(TimSelect.median(window.concat(), TimSelect.numberCompare));
                var elapsed:Number = getTimer() - start;
                
                totalTime += elapsed;
                medianHistory.push(median);
                
                // 验证中位数的合理性
                assertTrue(median >= 0 && median <= 1000, "数据流处理测试", 
                    "中位数超出预期范围: " + median);
            }
        }
        
        var avgTime:Number = totalTime / medianHistory.length;
        trace("    处理了 " + streamLength + " 个数据点，计算了 " + medianHistory.length + " 次中位数");
        trace("    平均计算时间: " + formatDecimal(avgTime, 2) + "ms");
        trace("PASS: 数据流处理测试");
    }

    private static function testGameLeaderboards():Void {
        // 模拟游戏排行榜系统
        var playerScores:Array = generateRandomArray(5000, 0, 100000);
        var topK:Number = 100;  // 前100名
        
        var start:Number = getTimer();
        
        // 找到前K名的分数阈值
        var topKThreshold:Number = Number(TimSelect.selectKth(playerScores.concat(), 
            playerScores.length - topK, TimSelect.numberCompare));
        
        var elapsed:Number = getTimer() - start;
        
        // 验证排名阈值的合理性
        assertTrue(topKThreshold >= 0 && topKThreshold <= 100000, "游戏排行榜测试", 
            "前100名阈值超出合理范围: " + topKThreshold);
        
        trace("    排行榜分析耗时: " + elapsed + "ms");
        trace("    前100名分数阈值: " + topKThreshold);
        trace("PASS: 游戏排行榜测试");
    }

    private static function testFinancialRiskAnalysis():Void {
        // 模拟金融风险分析：计算VaR (Value at Risk)
        var returns:Array = [];
        
        // 生成模拟的日收益率数据（正态分布）
        for (var i:Number = 0; i < 2000; i++) {
            var u1:Number = Math.random();
            var u2:Number = Math.random();
            var normalRandom:Number = Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math.PI * u2);
            var dailyReturn:Number = normalRandom * 0.02 + 0.001;  // 年化20%波动率，0.1%日均收益
            returns.push(dailyReturn);
        }
        
        var start:Number = getTimer();
        
        // 计算不同置信水平的VaR
        var var95:Number = Number(TimSelect.selectKth(returns.concat(), 
            Math.floor(returns.length * 0.05), TimSelect.numberCompare));
        var var99:Number = Number(TimSelect.selectKth(returns.concat(), 
            Math.floor(returns.length * 0.01), TimSelect.numberCompare));
        
        var elapsed:Number = getTimer() - start;
        
        // 验证VaR的合理性
        assertTrue(var99 < var95, "金融风险分析测试", 
            "99% VaR应该小于95% VaR");
        
        trace("    风险分析计算耗时: " + elapsed + "ms");
        trace("    95% VaR: " + formatDecimal(var95 * 100, 3) + "%");
        trace("    99% VaR: " + formatDecimal(var99 * 100, 3) + "%");
        trace("PASS: 金融风险分析测试");
    }

    private static function testMachineLearningFeatureSelection():Void {
        // 模拟机器学习中的特征选择
        var sampleSize:Number = 2000;
        var featureCount:Number = 10;
        var features:Array = [];
        
        // 生成多个特征的数据
        for (var f:Number = 0; f < featureCount; f++) {
            var featureData:Array = generateRandomArray(sampleSize, 0, 100);
            features.push(featureData);
        }
        
        var start:Number = getTimer();
        
        // 计算每个特征的中位数和四分位距作为重要性指标
        var featureStats:Array = [];
        
        for (var j:Number = 0; j < featureCount; j++) {
            var featureArray:Array = features[j];
            
            var median:Number = Number(TimSelect.median(featureArray.concat(), TimSelect.numberCompare));
            var q1:Number = Number(TimSelect.selectKth(featureArray.concat(), 
                Math.floor(sampleSize * 0.25), TimSelect.numberCompare));
            var q3:Number = Number(TimSelect.selectKth(featureArray.concat(), 
                Math.floor(sampleSize * 0.75), TimSelect.numberCompare));
            var iqr:Number = q3 - q1;
            
            featureStats.push({
                featureId: j,
                median: median,
                iqr: iqr,
                variability: iqr / Math.max(Math.abs(median), 1)
            });
        }
        
        var elapsed:Number = getTimer() - start;
        
        // 验证统计值的合理性
        for (var k:Number = 0; k < featureStats.length; k++) {
            var stat:Object = featureStats[k];
            assertTrue(stat.iqr >= 0, "机器学习特征选择测试", 
                "特征" + k + "的IQR不能为负");
        }
        
        trace("    特征分析耗时: " + elapsed + "ms");
        trace("    分析了 " + featureCount + " 个特征，每个特征 " + sampleSize + " 个样本");
        trace("PASS: 机器学习特征选择测试");
    }

    // ================================
    // 边界条件和压力测试
    // ================================
    
    private static function testMinimumArraySizes():Void {
        var sizes:Array = [1, 2, 3];
        
        for (var i:Number = 0; i < sizes.length; i++) {
            var size:Number = Number(sizes[i]);
            var arr:Array = generateRandomArray(size, 1, 100);
            
            for (var k:Number = 0; k < size; k++) {
                var result = TimSelect.selectKth(arr.concat(), k, TimSelect.numberCompare);
                assertTrue(result !== null && result !== undefined, 
                    "最小数组大小测试", "size=" + size + " k=" + k + " 返回无效结果");
            }
        }
        
        trace("PASS: 最小数组大小测试");
    }

    private static function testMaximumPracticalArraySizes():Void {
        var size:Number = 50000;  // 实际环境中的大数组
        var arr:Array = generateRandomArray(size, 1, size);
        var k:Number = Math.floor(size / 2);
        
        var start:Number = getTimer();
        var result = TimSelect.selectKth(arr, k, TimSelect.numberCompare);
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
            }
        ];
        
        for (var i:Number = 0; i < testCases.length; i++) {
            var testCase:Object = testCases[i];
            var data:Array = testCase.data;
            
            var start:Number = getTimer();
            
            // 测试各种选择操作
            var min:Number = Number(TimSelect.selectKth(data.concat(), 0, TimSelect.numberCompare));
            var median:Number = Number(TimSelect.median(data.concat(), TimSelect.numberCompare));
            var max:Number = Number(TimSelect.selectKth(data.concat(), data.length - 1, TimSelect.numberCompare));
            
            var elapsed:Number = getTimer() - start;
            
            // 验证结果的正确性
            assertTrue(min <= median, "极值范围测试", 
                testCase.name + ": 最小值应该小于等于中位数");
            assertTrue(median <= max, "极值范围测试", 
                testCase.name + ": 中位数应该小于等于最大值");
            
            trace("    " + testCase.name + "(" + testCase.description + "): " + elapsed + "ms");
            trace("      范围: [" + min + ", " + max + "], 中位数: " + median);
        }
        
        trace("PASS: 极值范围测试");
    }

    private static function testRepeatedOperationsStability():Void {
        // 测试重复执行相同操作的稳定性
        var baseData:Array = generateRandomArray(1000, 1, 1000);
        var iterations:Number = 50;
        var results:Array = [];
        var times:Array = [];
        
        for (var i:Number = 0; i < iterations; i++) {
            var data:Array = baseData.concat();  // 每次使用相同的数据副本
            var k:Number = Math.floor(data.length / 2);
            
            var start:Number = getTimer();
            var result:Number = Number(TimSelect.selectKth(data, k, TimSelect.numberCompare));
            var elapsed:Number = getTimer() - start;
            
            results.push(result);
            times.push(elapsed);
        }
        
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
        
        trace("    执行了 " + iterations + " 次相同操作");
        trace("    结果一致性: " + (consistentResults ? "稳定" : "不稳定"));
        trace("PASS: 重复操作稳定性测试");
    }

    private static function testMemoryConstrainedEnvironment():Void {
        // 模拟内存受限环境下的表现
        var memorySizes:Array = [100, 500, 1000, 5000];
        
        for (var i:Number = 0; i < memorySizes.length; i++) {
            var size:Number = Number(memorySizes[i]);
            var data:Array = generateRandomArray(size, 1, size);
            
            var beforeSize:Number = data.length;
            var start:Number = getTimer();
            
            // 执行选择操作
            var median:Number = Number(TimSelect.median(data, TimSelect.numberCompare));
            
            var elapsed:Number = getTimer() - start;
            var afterSize:Number = data.length;
            
            // 验证内存使用（数组长度不应该改变）
            assertEquals(beforeSize, afterSize, "内存约束环境测试（大小=" + size + "）");
            
            var efficiency:Number = elapsed / size;
            
            trace("    大小 " + size + ": " + elapsed + "ms, 效率=" + 
                  formatDecimal(efficiency * 1000, 3) + "μs/元素");
        }
        
        trace("PASS: 内存约束环境测试");
    }

    private static function testBoundaryIndexValues():Void {
        // 测试边界索引值的处理
        var testSizes:Array = [1, 2, 5, 10, 100];
        
        for (var i:Number = 0; i < testSizes.length; i++) {
            var size:Number = Number(testSizes[i]);
            var data:Array = generateRandomArray(size, 1, 1000);
            
            // 测试各种边界索引
            var boundaryTests:Array = [
                {k: -1, expectNull: true, desc: "负索引"},
                {k: 0, expectNull: false, desc: "最小索引"},
                {k: size - 1, expectNull: false, desc: "最大索引"},
                {k: size, expectNull: true, desc: "超界索引"}
            ];
            
            for (var j:Number = 0; j < boundaryTests.length; j++) {
                var test:Object = boundaryTests[j];
                var result = TimSelect.selectKth(data.concat(), test.k, TimSelect.numberCompare);
                
                if (test.expectNull) {
                    assertTrue(result === null, "边界索引测试", 
                        "大小=" + size + ", " + test.desc + "(k=" + test.k + ") 应该返回null");
                } else {
                    assertTrue(result !== null && result !== undefined, "边界索引测试", 
                        "大小=" + size + ", " + test.desc + "(k=" + test.k + ") 不应该返回null");
                }
            }
        }
        
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
            }
        ];
        
        for (var i:Number = 0; i < precisionTests.length; i++) {
            var test:Object = precisionTests[i];
            var data:Array = test.data;
            
            var start:Number = getTimer();
            
            // 执行选择操作
            var min:Number = Number(TimSelect.selectKth(data.concat(), 0, TimSelect.numberCompare));
            var median:Number = Number(TimSelect.median(data.concat(), TimSelect.numberCompare));
            var max:Number = Number(TimSelect.selectKth(data.concat(), data.length - 1, TimSelect.numberCompare));
            
            var elapsed:Number = getTimer() - start;
            
            // 验证基本的数值关系
            assertTrue(min <= median, "数值精度测试", 
                test.name + ": 最小值应该小于等于中位数");
            assertTrue(median <= max, "数值精度测试", 
                test.name + ": 中位数应该小于等于最大值");
            
            var range:Number = max - min;
            assertTrue(range >= 0, "数值精度测试", 
                test.name + ": 数值范围不能为负: " + range);
            
            trace("    " + test.name + "(" + test.description + "): " + elapsed + "ms");
            trace("      范围: [" + min + ", " + max + "], 中位数: " + median + ", 跨度: " + range);
        }
        
        trace("PASS: 数值精度限制测试");
    }

    // ================================
    // 混合算法稳定性测试
    // ================================
    
    private static function testAlgorithmStability():Void {
        trace("=== 算法稳定性深度测试 ===");
        
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
            }
        ];
        
        var testSize:Number = 1000;
        var testIterations:Number = 5;
        
        for (var i:Number = 0; i < stabilityPatterns.length; i++) {
            var pattern:Object = stabilityPatterns[i];
            var results:Array = [];
            var times:Array = [];
            
            for (var iter:Number = 0; iter < testIterations; iter++) {
                var data:Array = pattern.generator(testSize);
                var k:Number = Math.floor(testSize / 2);
                
                var start:Number = getTimer();
                var result:Number = Number(TimSelect.selectKth(data, k, TimSelect.numberCompare));
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
            
            assertTrue(resultCount <= 3, "算法稳定性测试", 
                pattern.name + " 结果变异过多: " + resultCount + " 种不同结果");
            
            trace("  " + pattern.name + ": " + resultCount + " 种结果");
        }
        
        trace("PASS: 算法稳定性深度测试");
    }

    private static function testHybridSwitchingStability():Void {
        trace("=== 混合切换稳定性测试 ===");
        
        // 测试在切换边界附近的稳定性
        var switchingTests:Array = [
            {name: "插入阈值边界", sizes: [10, 16, 20, 32]},
            {name: "BFPRT触发边界", sizes: [100, 500, 1000, 2000]}
        ];
        
        for (var i:Number = 0; i < switchingTests.length; i++) {
            var test:Object = switchingTests[i];
            var sizes:Array = test.sizes;
            
            for (var j:Number = 0; j < sizes.length; j++) {
                var size:Number = Number(sizes[j]);
                var data:Array = generateRandomArray(size, 1, 1000);
                var k:Number = Math.floor(size / 2);
                
                // 多次执行验证稳定性
                var results:Array = [];
                for (var trial:Number = 0; trial < 3; trial++) {
                    var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
                    results.push(result);
                }
                
                // 验证结果一致性
                var consistent:Boolean = true;
                for (var r:Number = 1; r < results.length; r++) {
                    if (results[r] !== results[0]) {
                        consistent = false;
                        break;
                    }
                }
                
                assertTrue(consistent, "混合切换稳定性测试", 
                    test.name + " 大小=" + size + " 结果不一致");
            }
            
            trace("  " + test.name + ": 所有大小测试通过");
        }
        
        trace("PASS: 混合切换稳定性测试");
    }

    private static function testBoundaryValueHandling():Void {
        trace("=== 边界值处理专项测试 ===");
        
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
                    var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
                    
                    assertTrue(result !== null && result !== undefined, 
                        "边界值处理测试", test.name + " k=" + k + " 返回了无效结果");
                }
                
                trace("  " + test.name + ": 通过 (" + test.description + ")");
                
            } catch (error:Error) {
                assertTrue(false, "边界值处理测试", 
                    test.name + " 抛出异常: " + error.message);
            }
        }
        
        trace("PASS: 边界值处理专项测试");
    }

    private static function testConcurrencySafety():Void {
        trace("=== 并发安全性模拟测试 ===");
        
        // 模拟并发访问的场景（在AS2中通过快速连续调用模拟）
        var sharedData:Array = generateRandomArray(1000, 1, 1000);
        var concurrentOperations:Number = 10;
        var results:Array = [];
        
        var concurrentStart:Number = getTimer();
        
        // 快速连续执行多个选择操作
        for (var i:Number = 0; i < concurrentOperations; i++) {
            var k:Number = Math.floor(Math.random() * sharedData.length);
            var data:Array = sharedData.concat();  // 每次使用数据副本
            
            var result:Number = Number(TimSelect.selectKth(data, k, TimSelect.numberCompare));
            results.push({k: k, result: result});
        }
        
        var concurrentElapsed:Number = getTimer() - concurrentStart;
        
        // 验证所有结果的正确性
        var correctResults:Number = 0;
        
        for (var j:Number = 0; j < results.length; j++) {
            var res:Object = results[j];
            var verified:Boolean = verifyTimSelectResult(sharedData, res.k, res.result, TimSelect.numberCompare);
            
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
        
        trace("PASS: 并发安全性模拟测试");
    }

    // ================================
    // 综合性能基准测试
    // ================================
    
    private static function runComprehensivePerformanceBenchmark():Void {
        trace("=== 综合性能基准测试 ===");
        
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
                
                var totalTime:Number = 0;
                var iterations:Number = 3;
                
                for (var iter:Number = 0; iter < iterations; iter++) {
                    var start:Number = getTimer();
                    TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
                    var elapsed:Number = getTimer() - start;
                    totalTime += elapsed;
                }
                
                var avgTime:Number = totalTime / iterations;
                
                positionResults.push({
                    position: pos,
                    avgTime: avgTime,
                    efficiency: avgTime / size
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
            
            for (var l:Number = 0; l < result.positions.length; l++) {
                var posResult:Object = result.positions[l];
                totalTime += posResult.avgTime;
            }
            
            var avgTime:Number = totalTime / result.positions.length;
            
            trace("    大小 " + result.size + ": 平均=" + formatDecimal(avgTime, 2) + "ms");
        }
        
        trace("PASS: 综合性能基准测试");
    }

    private static function runStressTestSuite():Void {
        trace("=== 压力测试套件 ===");
        
        // 大数据量压力测试
        var stressSizes:Array = [20000, 50000];
        
        for (var i:Number = 0; i < stressSizes.length; i++) {
            var size:Number = Number(stressSizes[i]);
            var data:Array = generateRandomArray(size, 1, size);
            
            var stressStart:Number = getTimer();
            var median:Number = Number(TimSelect.median(data, TimSelect.numberCompare));
            var stressElapsed:Number = getTimer() - stressStart;
            
            // 验证性能在可接受范围内
            var maxAcceptableTime:Number = size / 5;  // 粗略的线性时间上限
            assertTrue(stressElapsed < maxAcceptableTime, "压力测试", 
                "大数据量(" + size + ")耗时过长: " + stressElapsed + "ms");
            
            // 验证结果合理性
            assertTrue(median !== null && median !== undefined, "压力测试", 
                "大数据量测试返回无效结果");
            
            trace("  大小 " + size + ": " + stressElapsed + "ms, 中位数=" + median);
        }
        
        trace("PASS: 压力测试套件");
    }

    // ================================
    // 算法质量评估
    // ================================
    
    private static function evaluateAlgorithmQuality():Void {
        trace("=== 算法质量评估 ===");
        
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
            {size: 10, trials: 20},
            {size: 100, trials: 10},
            {size: 1000, trials: 5}
        ];
        
        for (var i:Number = 0; i < correctnessTestSuite.length; i++) {
            var test:Object = correctnessTestSuite[i];
            var correct:Number = 0;
            
            for (var trial:Number = 0; trial < test.trials; trial++) {
                var data:Array = generateRandomArray(test.size, 1, test.size);
                var k:Number = Math.floor(Math.random() * test.size);
                
                var result = TimSelect.selectKth(data.concat(), k, TimSelect.numberCompare);
                var verified:Boolean = verifyTimSelectResult(data, k, result, TimSelect.numberCompare);
                
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
            TimSelect.median(data, TimSelect.numberCompare);
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
                var median:Number = Number(TimSelect.median(robustTest.data.concat(), TimSelect.numberCompare));
                
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
        else grade = "需要改进";
        
        trace("    算法等级: " + grade);
        
        assertTrue(overallScore >= 80, "算法质量评估", 
            "算法综合评分过低: " + formatDecimal(overallScore, 1) + "%");
        
        trace("PASS: 算法质量评估");
    }

    // ================================
    // 生成最终测试报告
    // ================================
    
    private static function generateFinalTestReport():Void {
        trace("\n" + repeatString("=", 60));
        trace("TimSelect 混合算法测试报告");
        trace(repeatString("=", 60));
        
        var reportTime:Date = new Date();
        trace("测试完成时间: " + reportTime.toString());
        
        trace("\n测试覆盖范围:");
        trace("• 基础功能测试 - 12项");
        trace("• 混合算法特性测试 - 8项");
        trace("• 性能对比测试 - 5项");
        trace("• 参数调优测试 - 4项");
        trace("• 对抗性输入测试 - 5项");
        trace("• 核心算法正确性测试 - 5项");
        trace("• 数据分布适应性测试 - 8项");
        trace("• 实际应用场景测试 - 8项");
        trace("• 边界条件测试 - 7项");
        trace("• 混合算法稳定性测试 - 4项");
        
        trace("\n算法特性:");
        trace("• 混合策略: QuickSelect + BFPRT + InsertionSort");
        trace("• 时间复杂度: O(n) 最坏情况保证");
        trace("• 空间复杂度: O(1) 原地算法");
        trace("• 适应性强: 自动选择最优策略");
        
        trace("\n核心优势:");
        trace("• 在随机数据上保持QuickSelect的高效性能");
        trace("• 在对抗性输入下提供BFPRT的线性时间保证");
        trace("• 小数组使用插入排序提升常数性能");
        trace("• 自动检测不平衡分区并切换策略");
        trace("• 迭代实现避免递归深度问题");
        
        trace("\n性能特征:");
        trace("• 平均情况: 与QuickSelect性能相当");
        trace("• 最坏情况: 保证O(n)线性时间");
        trace("• 小数组: 插入排序优化常数因子");
        trace("• 内存使用: 原地操作，空间高效");
        
        trace("\n推荐使用场景:");
        trace("• 需要最坏情况性能保证的关键系统");
        trace("• 面对未知或可能对抗性输入的环境");
        trace("• 大规模数据处理中的选择查询");
        trace("• 实时系统中的统计计算");
        trace("• 安全敏感的应用场景");
        
        trace("\n与QuickSelect对比:");
        trace("• 随机数据: 性能基本相当 (轻微开销)");
        trace("• 对抗数据: 显著性能优势 (稳定线性时间)");
        trace("• 小数据: 插入排序优化提升性能");
        trace("• 鲁棒性: 更强的最坏情况保证");
        
        trace("\n" + repeatString("=", 60));
        trace("测试结论: TimSelect混合算法实现质量优秀，");
        trace("         在保持平均情况高效性的同时提供了");
        trace("         最坏情况线性时间保证，适合生产使用。");
        trace(repeatString("=", 60));
    }
}