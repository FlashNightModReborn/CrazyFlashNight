/**
 * 增强版 SortTest 类 - 
 * 位于 org.flashNight.naki.Sort 包下
 * 提供全面的排序算法性能评估和分析功能
 * 
 * 修复内容：
 * 1. 复杂度分析函数的数学计算错误
 * 2. 统计函数中的NaN和Infinity问题
 * 3. AS2兼容性问题（移除Array.reduce等ES6方法）
 * 4. 稳定性测试的准确性
 * 5. 边界情况处理
 * 
 * 改进说明：
 * - 使用 LinearCongruentialEngine 替代 Math.random()，确保测试结果可重现
 * - 通过固定种子消除随机性带来的数据波动
 * - 提高测试的可靠性和一致性
 */

import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
class org.flashNight.naki.Sort.SortTest {
    
    // 可控的随机数生成器，确保测试结果可重现
    private var rng:LinearCongruentialEngine;
    
    // 初始化随机数生成器，设置固定种子以确保可重现性
    private function initRNG(seed:Number):Void {
        if (rng == null) {
            rng = LinearCongruentialEngine.getInstance();
        }
        rng.init(1664525, 1013904223, 4294967296, seed);
    }
    
    // 重置随机数生成器种子
    private function resetRNG(seed:Number):Void {
        initRNG(seed);
    }
    
    // 公开的接口，允许用户在测试前设置种子
    public function setSeed(seed:Number):Void {
        resetRNG(seed);
        trace("随机数种子已设置为: " + seed);
    }
    
    // 测试配置
    private var testConfig:Object = {
        basicSizes:       [10, 50, 100, 300, 1000, 3000, 10000],
        stressSizes:      [3000, 10000, 30000],
        testIterations:   5,
        enableMemoryMonitoring: true,
        enableDetailedStats:    true,
        generateCSVReport:      true
    };
    
    // 存储性能数据
    private var performanceMatrix:Object;

    // 存储稳定性测试结果
    private var stabilityResults:Object;
    
    // 排序方法定义
    private var sortMethods:Array = [
        { name: "InsertionSort",     sort: org.flashNight.naki.Sort.InsertionSort.sort,      expectedComplexity: "O(n²)" },
        { name: "PDQSort",           sort: org.flashNight.naki.Sort.PDQSort.sort,            expectedComplexity: "O(n log n)" },
        { name: "QuickSort",         sort: org.flashNight.naki.Sort.QuickSort.sort,          expectedComplexity: "O(n log n)" },
        { name: "AdaptiveSort",      sort: org.flashNight.naki.Sort.QuickSort.adaptiveSort,  expectedComplexity: "O(n log n)" },
        { name: "TimSort",           sort: org.flashNight.naki.Sort.TimSort.sort,            expectedComplexity: "O(n log n)" },
        { name: "NaturalMergeSort",  sort: org.flashNight.naki.Sort.NaturalMergeSort.sort,   expectedComplexity: "O(n log n)" },
        { name: "PowerSort",         sort: org.flashNight.naki.Sort.PowerSort.sort,          expectedComplexity: "O(n log n)" },
        { name: "BuiltInSort",       sort: builtInSort,                                      expectedComplexity: "O(n log n)" }
    ];
    
    /**
     * 构造函数
     */
    public function SortTest(cfg:Object) {
        // 初始化可控随机数生成器
        initRNG(12345); // 设置固定种子
        
        // 合并用户配置
        if (cfg != null) {
            for (var k:String in cfg) {
                testConfig[k] = cfg[k];
            }
        }
        initializePerformanceMatrix();
    }
    
    /**
     * 初始化性能矩阵结构
     */
    private function initializePerformanceMatrix():Void {
        performanceMatrix = {};
        stabilityResults = {};
        for (var i:Number = 0; i < sortMethods.length; i++) {
            performanceMatrix[sortMethods[i].name] = {};
            stabilityResults[sortMethods[i].name] = {
                stable: true,      // 默认假设稳定，测试中发现不稳定则标记
                testsPassed: 0,
                testsFailed: 0
            };
        }
    }
    
    /**
     * 运行完整的测试套件
     */
    public function runCompleteTestSuite():Void {
        trace(repeatChar("=", 80));
        trace("启动增强版排序算法测试套件");
        trace("使用可控随机数生成器确保结果可重现");
        trace(repeatChar("=", 80));
        
        // 重置主随机数种子以确保测试的一致性
        resetRNG(12345);
        
        runBasicFunctionalityTests();
        runStabilityTests();
        runPerformanceBenchmarks();
        runSpecialScenarioTests();
        runAlgorithmComparison();
        generateFinalReport();
        
        trace(repeatChar("=", 80));
        trace("测试套件完成");
        trace(repeatChar("=", 80));
    }
    
    /*** 1. 基础功能测试 ***/
    private function runBasicFunctionalityTests():Void {
        trace("\n" + repeatChar("=", 40));
        trace("基础功能测试");
        trace(repeatChar("=", 40));
        
        var basicTests:Array = [
            { name:"空数组",      data:[],                       expected:[] },
            { name:"单元素",      data:[42],                     expected:[42] },
            { name:"两元素正序",  data:[1,2],                    expected:[1,2] },
            { name:"两元素逆序",  data:[2,1],                    expected:[1,2] },
            { name:"小型随机",    data:[3,1,4,1,5,9,2,6],        expected:[1,1,2,3,4,5,6,9] },
            { name:"负数混合",    data:[-3,-1,0,1,3],            expected:[-3,-1,0,1,3] },
            { name:"浮点数",      data:[3.14,2.71,1.41,0.57],    expected:[0.57,1.41,2.71,3.14] }
        ];
        
        for (var i:Number = 0; i < basicTests.length; i++) {
            var bt:Object = basicTests[i];
            runSingleFunctionalTest(bt.name, bt.data, bt.expected);
        }
    }
    
    private function runSingleFunctionalTest(testName:String, testData:Array, expected:Array):Void {
        trace("\n测试: " + testName);
        var passCount:Number = 0;
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var m:Object = sortMethods[i];
            var arr:Array = copyArray(testData);
            var passed:Boolean = false;
            
            try {
                var result:Array = m.sort(arr, null);
                passed = arraysEqual(result, expected, null);
                trace("  " + (passed ? "✓" : "✗") + " " + m.name +
                      (passed ? "" : " - 期望:" + expected + " 实际:" + result));
            } catch (e:Error) {
                trace("  ✗ " + m.name + " ERROR: " + e.message);
            }
            
            if (passed) passCount++;
        }
        trace("总结: " + passCount + "/" + sortMethods.length + " 算法通过");
    }
    
    /*** 2. 稳定性测试 - 增强版 V3 (大规模对抗性测试) ***/
    private function runStabilityTests():Void {
        trace("\n" + repeatChar("=", 40));
        trace("稳定性测试 - 增强版 V3 (大规模对抗性测试)");
        trace(repeatChar("=", 40));
        
        var stabilityTestCases:Array = [
            {
                // 确保规模 > 32，以触发 PDQSort 的分区逻辑
                name: "大规模 Pivot 陷阱模式",
                data: this.generateStabilityData("pivotTrap", 64) 
            },
            {
                name: "大规模交错相等元素",
                data: this.generateStabilityData("interleaved", 64)
            },
            {
                name: "大规模逆序中的相等元素",
                data: this.generateStabilityData("reversedEquals", 64)
            }
        ];

        // 遍历所有测试用例
        for (var c:Number = 0; c < stabilityTestCases.length; c++) {
            var testCase:Object = stabilityTestCases[c];
            trace("\n--- 测试用例: " + testCase.name + " ---");
            this.executeSingleStabilityTest(testCase.data);
        }
    }

    
    /**
     * 新增：用于生成大规模稳定性测试数据的辅助函数
     * @param type  "pivotTrap", "interleaved", "reversedEquals"
     * @param size  生成的数组大小
     * @return      构造好的测试数据数组
     */
    private function generateStabilityData(type:String, size:Number):Array {
        // 为稳定性测试数据生成设置固定种子
        resetRNG(type.length * 1000 + size); // 基于类型和大小的固定种子
        
        var data:Array = [];
        var idCounters:Object = {};

        function getId(value:Number):String {
            if (!idCounters[value]) {
                idCounters[value] = 0;
            }
            idCounters[value]++;
            return String.fromCharCode(64 + value) + idCounters[value]; // e.g., A1, B1, A2
        }

        switch (type) {
            case "pivotTrap":
                // 构造一个中间有很多不同值，两端有相等值的数据
                var val:Number = 5;
                data.push({value: val, id: getId(val)});
                for (var i:Number = 0; i < size - 2; i++) {
                    data.push({value: i % (val-1) + 1, id: getId(i % (val-1) + 1)});
                }
                data.push({value: val, id: getId(val)});
                break;

            case "interleaved":
                // 交错生成两种值
                for (var i:Number = 0; i < size; i++) {
                    var v:Number = (i % 2 == 0) ? 5 : 1;
                    data.push({value: v, id: getId(v)});
                }
                break;

            case "reversedEquals":
                // 逆序排列，其中包含重复值
                var currentVal:Number = size / 2;
                for (var i:Number = 0; i < size; i++) {
                    data.push({value: Math.floor(currentVal), id: getId(Math.floor(currentVal))});
                    if (i % 3 != 0) { // 每隔几个元素才递减
                        currentVal -= 0.5;
                    }
                }
                break;
        }

        return data;
    }
    
    /**
     * 执行单个稳定性测试的核心逻辑
     * @param data 原始测试数据
     */
    private function executeSingleStabilityTest(data:Array):Void {
        var compareFunc:Function = function(a:Object, b:Object):Number {
            return a.value < b.value ? -1 : (a.value > b.value ? 1 : 0);
        };

        // 动态生成期望的稳定排序结果
        var expected:Array = this.generateStableExpectedResult(data, compareFunc);

        trace("原始数据: " + formatObjectArray(data));
        trace("稳定排序期望: " + formatObjectArray(expected));

        for (var i:Number = 0; i < sortMethods.length; i++) {
            var m:Object = sortMethods[i];
            var arr:Array = copyArray(data);
            try {
                var res:Array = m.sort(arr, compareFunc);
                var stable:Boolean = checkStabilityEnhanced(res, expected);

                // 记录稳定性测试结果
                if (stable) {
                    stabilityResults[m.name].testsPassed++;
                } else {
                    stabilityResults[m.name].testsFailed++;
                    stabilityResults[m.name].stable = false;  // 标记为不稳定
                }

                trace("\n" + m.name + ": " + (stable ? "✓ 稳定" : "✗ 不稳定"));

                // 只有在不稳定时才打印详细结果，保持报告整洁
                if (!stable) {
                    trace("  结果: " + formatObjectArray(res));
                    trace("  → 稳定性违规详情:");
                    analyzeStabilityViolations(res, expected);
                }
            } catch (e:Error) {
                stabilityResults[m.name].testsFailed++;
                stabilityResults[m.name].stable = false;
                trace("\n" + m.name + " ERROR: " + e.message);
            }
        }
    }

    /**
     * 动态生成稳定排序的期望结果
     * @param originalData  原始数据数组
     * @param compareFunc   比较函数
     * @return              一个稳定排序后的数组
     */
    private function generateStableExpectedResult(originalData:Array, compareFunc:Function):Array {
        var tempArr:Array = copyArray(originalData);
        
        // 使用一个已知的稳定排序算法（如插入排序）来生成基准
        // 这里我们自己实现一个简化的稳定排序（类似冒泡）来避免依赖
        // 也可以直接依赖 InsertionSort.sort，但为了解耦，这里独立实现
        
        var n:Number = tempArr.length;
        for (var i:Number = 0; i < n; i++) {
            for (var j:Number = 0; j < n - 1 - i; j++) {
                if (compareFunc(tempArr[j], tempArr[j + 1]) > 0) {
                    // 只在严格大于时交换，保证稳定性
                    var temp:Object = tempArr[j];
                    tempArr[j] = tempArr[j + 1];
                    tempArr[j + 1] = temp;
                }
            }
        }
        
        return tempArr;
    }
    
    /*** 3. 性能基准测试 ***/
    private function runPerformanceBenchmarks():Void {
        trace("\n" + repeatChar("=", 40));
        trace("性能基准测试");
        trace(repeatChar("=", 40));
        
        var distributions:Array = [
            {name:"随机数据", type:"random"},
            {name:"已排序",   type:"sorted"},
            {name:"逆序",     type:"reverse"},
            {name:"部分有序", type:"partiallySorted"},
            {name:"重复元素", type:"duplicates"},
            {name:"全相同",   type:"allSame"},
            {name:"几乎排序", type:"nearlySorted"},
            {name:"管道风琴", type:"pipeOrgan"},
            {name:"锯齿波",   type:"sawtooth"}
        ];
        
        for (var d:Number = 0; d < distributions.length; d++) {
            var dist:Object = distributions[d];
            trace("\n--- " + dist.name + " ---");
            for (var s:Number = 0; s < testConfig.basicSizes.length; s++) {
                runPerformanceTest(
                    testConfig.basicSizes[s],
                    dist.type,
                    dist.name
                );
            }
        }
    }
    
    private function runPerformanceTest(size:Number, distType:String, distName:String):Void {
        trace("\n规模: " + size);
        var baseData:Array = generateArray(size, distType);
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var m:Object = sortMethods[i];
            var totalTime:Number = 0;
            var minT:Number = Infinity;
            var maxT:Number = 0;
            var succ:Number = 0;
            
            for (var run:Number = 0; run < testConfig.testIterations; run++) {
                var arr:Array = copyArray(baseData);
                var t0:Number = getTimer();
                try {
                    var out:Array = m.sort(arr, null);
                    var t1:Number = getTimer();
                    // 验证
                    var exp:Array = copyArray(baseData); 
                    exp.sort(Array.NUMERIC);
                    if (arraysEqual(out, exp, null)) {
                        var dt:Number = Math.max(0, t1 - t0); // 确保时间非负
                        totalTime += dt;
                        minT = Math.min(minT, dt);
                        maxT = Math.max(maxT, dt);
                        succ++;
                    }
                } catch (e:Error) {
                    trace("  " + m.name + " 运行时错误: " + e.message);
                }
            }
            
            if (succ > 0) {
                var avgT:Number = totalTime / succ;
                // 存储
                if (!performanceMatrix[m.name][distName]) performanceMatrix[m.name][distName] = {};
                performanceMatrix[m.name][distName][size] = avgT;
                
                trace("  " + m.name +
                      " 平均:" + formatNumber(avgT, 1) +
                      "ms 最小:" + formatNumber(minT, 1) + 
                      "ms 最大:" + formatNumber(maxT, 1) + 
                      "ms 成功率:" + formatNumber((succ/testConfig.testIterations)*100, 1) + "%");
            } else {
                trace("  " + m.name + " 所有运行均失败");
            }
        }
    }
    
    /*** 4. 特殊场景测试 ***/
    private function runSpecialScenarioTests():Void {
        trace("\n" + repeatChar("=", 40));
        trace("特殊场景测试");
        trace(repeatChar("=", 40));
        
        var scenarios:Array = [
            {name:"极值数据",    gen:generateExtremeValues},
            {name:"高重复率",    gen:generateHighDuplicates},
            {name:"三值分布",    gen:generateThreeValues},
            {name:"交替模式",    gen:generateAlternatingPattern},
            {name:"指数分布",    gen:generateExponentialPattern}
        ];
        
        for (var i:Number = 0; i < scenarios.length; i++) {
            var sc:Object = scenarios[i];
            trace("\n--- " + sc.name + " ---");
            var data:Array = sc.gen(1000);
            trace("示例前10:" + data.slice(0,10));
            
            for (var j:Number = 0; j < sortMethods.length; j++) {
                var m:Object = sortMethods[j];
                var t0:Number = getTimer();
                try {
                    var out:Array = m.sort(copyArray(data), null);
                    var t1:Number = getTimer();
                    var dt:Number = Math.max(0, t1 - t0);
                    var ok:Boolean = quickSortValidation(out);
                    trace("  " + m.name + ": " + formatNumber(dt, 0) + "ms " + (ok?"✓":"✗"));
                } catch (e:Error) {
                    trace("  " + m.name + " ERROR: " + e.message);
                }
            }
        }
    }
    
    /*** 5. 算法比较分析 ***/
    private function runAlgorithmComparison():Void {
        trace("\n" + repeatChar("=", 40));
        trace("算法比较分析");
        trace(repeatChar("=", 40));
        
        analyzeByDataPattern();
        analyzeScalability();
        generateRecommendations();
    }
    
    /**
     * 最终报告生成 - 完整实现
     */
    private function generateFinalReport():Void {
        trace("\n" + repeatChar("=", 80));
        trace("最终测试报告");
        trace(repeatChar("=", 80));
        
        generateExecutiveSummary();
        generatePerformanceMatrix();
        generateAlgorithmRankings();
        generateComplexityAnalysis();
        generateSpecialScenarioSummary();
        generateRecommendationMatrix();
        generateStatisticalSummary();
        
        if (testConfig.generateCSVReport) {
            generateCSVReport();
        }
        
        generateConclusion();
    }

    /**
     * 执行摘要
     */
    private function generateExecutiveSummary():Void {
        trace("\n" + repeatChar("-", 60));
        trace("📊 执行摘要");
        trace(repeatChar("-", 60));
        
        var totalTests:Number = 0;
        var algorithmsCount:Number = sortMethods.length;
        var dataDistributions:Array = [];
        var testSizes:Array = testConfig.basicSizes.slice();
        
        // 统计测试数量和数据分布
        for (var alg:String in performanceMatrix) {
            for (var dist:String in performanceMatrix[alg]) {
                if (arrayIndexOf(dataDistributions, dist) === -1) {
                    dataDistributions.push(dist);
                }
                for (var size:String in performanceMatrix[alg][dist]) {
                    totalTests++;
                }
            }
        }
        
        trace("• 测试算法数量: " + algorithmsCount);
        trace("• 数据分布类型: " + dataDistributions.length + " (" + dataDistributions.join(", ") + ")");
        trace("• 测试规模范围: " + arrayMin(testSizes) + " - " + arrayMax(testSizes));
        trace("• 总测试样本: " + totalTests + " 个性能数据点");
        trace("• 每组重复次数: " + testConfig.testIterations);
        
        // 找出整体最佳算法
        var bestAlgorithm:String = findOverallBestAlgorithm();
        trace("• 综合最佳算法: " + bestAlgorithm);
        
        var currentTime:Date = new Date();
        trace("• 测试完成时间: " + currentTime.toString());
    }

    /**
     * 性能矩阵展示
     */
    private function generatePerformanceMatrix():Void {
        trace("\n" + repeatChar("-", 60));
        trace("📈 性能矩阵 (平均执行时间 ms)");
        trace(repeatChar("-", 60));
        
        // 获取所有数据分布
        var distributions:Array = [];
        for (var alg:String in performanceMatrix) {
            for (var dist:String in performanceMatrix[alg]) {
                if (arrayIndexOf(distributions, dist) === -1) {
                    distributions.push(dist);
                }
            }
            break; // 只需要第一个算法的分布列表
        }
        
        for (var d:Number = 0; d < distributions.length; d++) {
            var distName:String = distributions[d];
            trace("\n" + distName + ":");
            
            // 表头
            var header:String = "算法\\规模";
            var sizes:Array = testConfig.basicSizes.slice();
            for (var s:Number = 0; s < sizes.length; s++) {
                header += "\t" + sizes[s];
            }
            trace(header);
            
            // 每个算法的数据行
            for (var i:Number = 0; i < sortMethods.length; i++) {
                var algName:String = sortMethods[i].name;
                var row:String = algName;
                
                for (var sz:Number = 0; sz < sizes.length; sz++) {
                    var size:Number = sizes[sz];
                    var time:String = "N/A";
                    
                    if (performanceMatrix[algName] && 
                        performanceMatrix[algName][distName] && 
                        performanceMatrix[algName][distName][size] !== undefined) {
                        var ms:Number = performanceMatrix[algName][distName][size];
                        time = formatNumber(ms, 1);
                    }
                    row += "\t" + time;
                }
                trace(row);
            }
            
            // 找出这个分布下的最佳算法
            var bestInDist:String = findBestAlgorithmForDistribution(distName);
            trace("最佳: " + bestInDist);
        }
    }

    /**
     * 算法排名
     */
    private function generateAlgorithmRankings():Void {
        trace("\n" + repeatChar("-", 60));
        trace("🏆 算法综合排名");
        trace(repeatChar("-", 60));
        
        var algorithmScores:Array = [];
        
        // 计算每个算法的综合得分
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var algName:String = sortMethods[i].name;
            var score:Object = calculateAlgorithmScore(algName);
            score.name = algName;
            score.complexity = sortMethods[i].expectedComplexity;
            algorithmScores.push(score);
        }
        
        // 按综合得分排序
        algorithmScores.sort(function(a:Object, b:Object):Number {
            return a.totalScore - b.totalScore; // 得分越低越好（时间越短）
        });
        
        trace("排名\t算法\t\t综合得分\t\t理论复杂度\t最佳场景\t最差场景");
        trace(repeatChar("-", 80));
        
        for (var r:Number = 0; r < algorithmScores.length; r++) {
            var rank:Object = algorithmScores[r];
            var rankStr:String = (r + 1) + "\t" + 
                            rank.name + "\t\t" + 
                            formatNumber(rank.totalScore, 2) + "\t\t" + 
                            rank.complexity + "\t" + 
                            rank.bestScenario + "\t" + 
                            rank.worstScenario;
            trace(rankStr);
        }
    }

    /**
     * 复杂度分析 - 修复版
     */
    private function generateComplexityAnalysis():Void {
        trace("\n" + repeatChar("-", 60));
        trace("📊 复杂度分析");
        trace(repeatChar("-", 60));
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var algName:String = sortMethods[i].name;
            var expectedComplexity:String = sortMethods[i].expectedComplexity;
            
            trace("\n" + algName + " (理论: " + expectedComplexity + "):");
            
            // 分析随机数据的复杂度表现
            if (performanceMatrix[algName] && performanceMatrix[algName]["随机数据"]) {
                var randomData:Object = performanceMatrix[algName]["随机数据"];
                var complexityAnalysis:Object = calculateComplexityFactorFixed(randomData);
                
                trace("  实际表现: " + complexityAnalysis.interpretation + 
                      " (斜率: " + formatNumber(complexityAnalysis.slope, 3) + ")");
                trace("  R²相关系数: " + formatNumber(complexityAnalysis.correlation, 3) + 
                      " (越接近1越准确)");
                
                // 分析最佳/最差情况
                var bestCase:Object = findBestWorstCase(algName);
                if (bestCase.best.avgTime < Infinity && bestCase.worst.avgTime > 0) {
                    trace("  最佳情况: " + bestCase.best.scenario + 
                          " (" + formatNumber(bestCase.best.avgTime, 2) + "ms)");
                    trace("  最差情况: " + bestCase.worst.scenario + 
                          " (" + formatNumber(bestCase.worst.avgTime, 2) + "ms)");
                    
                    var ratio:Number = bestCase.worst.avgTime / bestCase.best.avgTime;
                    if (isFinite(ratio)) {
                        trace("  性能比率: " + formatNumber(ratio, 1) + ":1");
                    }
                }
            }
        }
    }

    /**
     * 特殊场景摘要
     */
    private function generateSpecialScenarioSummary():Void {
        trace("\n" + repeatChar("-", 60));
        trace("🎯 特殊场景性能摘要");
        trace(repeatChar("-", 60));
        
        var specialScenarios:Array = [
            {name: "已排序", description: "测试算法对有序数据的优化"},
            {name: "逆序", description: "测试算法对逆序数据的处理"},
            {name: "全相同", description: "测试算法对重复元素的处理"},
            {name: "几乎排序", description: "测试算法对近有序数据的适应性"}
        ];
        
        for (var s:Number = 0; s < specialScenarios.length; s++) {
            var scenario:Object = specialScenarios[s];
            trace("\n" + scenario.name + " - " + scenario.description);
            
            var scenarioRanking:Array = rankAlgorithmsForScenario(scenario.name);
            for (var r:Number = 0; r < Math.min(3, scenarioRanking.length); r++) {
                var rank:Object = scenarioRanking[r];
                trace("  " + (r+1) + ". " + rank.algorithm + ": " + 
                      formatNumber(rank.avgTime, 2) + "ms");
            }
        }
    }

    /**
     * 推荐矩阵 - 基于测试结果动态生成
     */
    private function generateRecommendationMatrix():Void {
        trace("\n" + repeatChar("-", 60));
        trace("💡 使用推荐矩阵");
        trace(repeatChar("-", 60));

        // 动态生成推荐列表
        var recommendations:Array = [];

        // 小数据推荐
        var smallDataBest:String = findBestForSmallData();
        recommendations.push({
            condition: "数据规模 < 100",
            recommended: smallDataBest,
            reason: "小数据量时开销低的算法更优"
        });

        // 大数据推荐
        var largeDataBest:String = findBestForLargeData();
        recommendations.push({
            condition: "数据规模 > 3000",
            recommended: largeDataBest,
            reason: "大数据量需要高效的分治算法"
        });

        // 已排序数据推荐
        var sortedDataBest:String = findBestForSortedData();
        recommendations.push({
            condition: "数据已基本有序",
            recommended: sortedDataBest,
            reason: "利用现有有序性可显著提升性能"
        });

        // 重复元素推荐
        var duplicatesBest:String = findBestForDuplicates();
        recommendations.push({
            condition: "包含大量重复元素",
            recommended: duplicatesBest,
            reason: "在重复元素场景下表现最优"
        });

        // 稳定排序推荐（动态选择）
        var stableBest:String = findBestForStableSort();
        var stableAlgsCount:Number = 0;
        for (var alg:String in stabilityResults) {
            if (stabilityResults[alg].stable) stableAlgsCount++;
        }
        recommendations.push({
            condition: "需要稳定排序",
            recommended: stableBest,
            reason: "保持相同元素的相对顺序（" + stableAlgsCount + "个稳定算法中性能最优）"
        });

        // 内存受限推荐（动态选择）
        var memoryBest:String = findBestForMemory();
        recommendations.push({
            condition: "内存限制严格",
            recommended: memoryBest,
            reason: "原地排序算法，在无额外空间算法中性能最优"
        });

        // 输出推荐
        for (var r:Number = 0; r < recommendations.length; r++) {
            var rec:Object = recommendations[r];
            trace("• " + rec.condition);
            trace("  推荐: " + rec.recommended);
            trace("  原因: " + rec.reason);
            trace("");
        }
    }

    /**
     * 统计摘要 - 修复版
     */
    private function generateStatisticalSummary():Void {
        trace("\n" + repeatChar("-", 60));
        trace("📈 统计摘要");
        trace(repeatChar("-", 60));
        
        var stats:Object = calculateOverallStatisticsFixed();
        
        trace("整体统计:");
        trace("• 最快单次执行: " + formatNumber(stats.fastest.time, 1) + "ms (" + 
            stats.fastest.algorithm + " - " + stats.fastest.scenario + ", " + 
            stats.fastest.size + "元素)");
        
        trace("• 最慢单次执行: " + formatNumber(stats.slowest.time, 1) + "ms (" + 
            stats.slowest.algorithm + " - " + stats.slowest.scenario + ", " + 
            stats.slowest.size + "元素)");
        
        var performanceGap:String = "无法计算";
        if (stats.fastest.time > 0 && isFinite(stats.slowest.time / stats.fastest.time)) {
            performanceGap = formatNumber(stats.slowest.time / stats.fastest.time, 1) + "倍";
        }
        trace("• 性能差距: " + performanceGap);
        
        trace("• 平均执行时间: " + formatNumber(stats.averageTime, 2) + "ms");
        trace("• 标准差: " + formatNumber(stats.standardDeviation, 2) + "ms");
        
        // 各算法可靠性分析
        trace("\n算法可靠性 (变异系数):");
        for (var alg:String in stats.reliability) {
            var cv:Number = stats.reliability[alg];
            var reliabilityLevel:String = "无数据";
            if (isFinite(cv)) {
                reliabilityLevel = cv < 0.1 ? "优秀" : (cv < 0.3 ? "良好" : "一般");
                trace("• " + alg + ": " + formatNumber(cv, 3) + " (" + reliabilityLevel + ")");
            } else {
                trace("• " + alg + ": 数据不足");
            }
        }
    }

    /**
     * CSV报告生成
     */
    private function generateCSVReport():Void {
        trace("\n" + repeatChar("-", 60));
        trace("📄 CSV格式数据导出");
        trace(repeatChar("-", 60));
        
        var csvContent:String = "Algorithm,DataDistribution,Size,AverageTime,Iterations\n";
        var lineCount:Number = 1;
        
        for (var alg:String in performanceMatrix) {
            for (var dist:String in performanceMatrix[alg]) {
                for (var size:String in performanceMatrix[alg][dist]) {
                    var time:Number = performanceMatrix[alg][dist][size];
                    csvContent += alg + "," + dist + "," + size + "," + 
                                formatNumber(time, 3) + "," + testConfig.testIterations + "\n";
                    lineCount++;
                }
            }
        }
        
        trace("CSV数据已生成 (共 " + lineCount + " 行)");
        trace("数据格式: 算法,数据分布,规模,平均时间,迭代次数");
        
        // 显示前几行作为示例
        var lines:Array = csvContent.split("\n");
        trace("\n前5行数据示例:");
        for (var i:Number = 0; i < Math.min(5, lines.length); i++) {
            if (lines[i].length > 0) {
                trace(lines[i]);
            }
        }
        trace("...(完整数据可导出到文件)");
    }

    /**
     * 结论 - 基于测试结果动态生成
     */
    private function generateConclusion():Void {
        trace("\n" + repeatChar("-", 60));
        trace("🎯 测试结论");
        trace(repeatChar("-", 60));

        var overallBest:String = findOverallBestAlgorithm();
        var versatileBest:String = findMostVersatileAlgorithm();
        var stableBest:String = findBestForStableSort();
        var memoryBest:String = findBestForMemory();

        trace("基于本次测试的主要发现:");
        trace("");
        trace("1. 综合性能最佳: " + overallBest);
        trace("   在大多数测试场景中表现优异，具有良好的时间复杂度特性。");

        trace("");
        trace("2. 适应性最强: " + versatileBest);
        trace("   在各种数据分布下都能保持相对稳定的性能表现。");

        trace("");
        trace("3. 关键洞察:");
        generateKeyInsights();

        trace("");
        trace("4. 建议:");
        trace("   • 一般用途推荐: " + overallBest);
        trace("   • 性能要求极高: " + findBestForPerformance());
        trace("   • 稳定性要求: " + stableBest + " (性能最优的稳定排序)");
        trace("   • 内存受限环境: " + memoryBest + " (性能最优的原地排序)");

        trace("\n" + repeatChar("=", 80));
        trace("测试报告生成完成");
        trace(repeatChar("=", 80));
    }

    // ===== 修复的辅助计算方法 =====

    /**
     * 修复的复杂度分析函数
     */
    private function calculateComplexityFactorFixed(dataPoints:Object):Object {
        var sizes:Array = [];
        var times:Array = [];
        
        // 收集数据点
        for (var size:String in dataPoints) {
            var sizeNum:Number = Number(size);
            var timeNum:Number = dataPoints[size];
            if (sizeNum > 0 && timeNum >= 0 && isFinite(timeNum)) {
                sizes.push(sizeNum);
                times.push(Math.max(0.001, timeNum)); // 避免log(0)
            }
        }
        
        if (sizes.length < 2) {
            return {
                slope: 1.0,
                interpretation: "数据不足",
                correlation: 0.0
            };
        }
        
        // 按规模排序
        var sortedData:Array = [];
        for (var i:Number = 0; i < sizes.length; i++) {
            sortedData.push({size: sizes[i], time: times[i]});
        }
        sortedData.sort(function(a:Object, b:Object):Number {
            return a.size - b.size;
        });
        
        // 对数线性回归 log(time) = slope * log(size) + intercept
        var logSizes:Array = [];
        var logTimes:Array = [];
        
        for (var j:Number = 0; j < sortedData.length; j++) {
            logSizes.push(Math.log(sortedData[j].size));
            logTimes.push(Math.log(sortedData[j].time));
        }
        
        // 线性回归计算
        var n:Number = logSizes.length;
        var sumX:Number = arraySum(logSizes);
        var sumY:Number = arraySum(logTimes);
        var sumXY:Number = 0;
        var sumXX:Number = 0;
        
        for (var k:Number = 0; k < n; k++) {
            sumXY += logSizes[k] * logTimes[k];
            sumXX += logSizes[k] * logSizes[k];
        }
        
        var slope:Number = 1.0;
        var correlation:Number = 0.0;
        
        if (n * sumXX - sumX * sumX != 0) {
            slope = (n * sumXY - sumX * sumY) / (n * sumXX - sumX * sumX);
            
            // 计算相关系数
            var sumYY:Number = 0;
            for (var l:Number = 0; l < n; l++) {
                sumYY += logTimes[l] * logTimes[l];
            }
            
            var denominator:Number = Math.sqrt((n * sumXX - sumX * sumX) * (n * sumYY - sumY * sumY));
            if (denominator != 0) {
                correlation = (n * sumXY - sumX * sumY) / denominator;
                correlation = Math.abs(correlation); // 取绝对值表示拟合度
            }
        }
        
        var interpretation:String = interpretComplexitySlope(slope);
        
        return {
            slope: slope,
            interpretation: interpretation,
            correlation: correlation
        };
    }
    
    /**
     * 修复的统计计算函数
     */
    private function calculateOverallStatisticsFixed():Object {
        var allTimes:Array = [];
        var fastest:Object = {time: Infinity, algorithm: "", scenario: "", size: ""};
        var slowest:Object = {time: 0, algorithm: "", scenario: "", size: ""};
        var reliability:Object = {};
        
        // 收集所有时间数据
        for (var alg:String in performanceMatrix) {
            var algTimes:Array = [];
            
            for (var dist:String in performanceMatrix[alg]) {
                for (var size:String in performanceMatrix[alg][dist]) {
                    var time:Number = performanceMatrix[alg][dist][size];
                    if (isFinite(time) && time >= 0) {
                        allTimes.push(time);
                        algTimes.push(time);
                        
                        if (time < fastest.time) {
                            fastest = {time: time, algorithm: alg, scenario: dist, size: size};
                        }
                        if (time > slowest.time) {
                            slowest = {time: time, algorithm: alg, scenario: dist, size: size};
                        }
                    }
                }
            }
            
            // 计算各算法的变异系数
            if (algTimes.length > 1) {
                var mean:Number = arrayMean(algTimes);
                var variance:Number = arrayVariance(algTimes, mean);
                
                if (mean > 0 && variance >= 0) {
                    reliability[alg] = Math.sqrt(variance) / mean;
                } else {
                    reliability[alg] = NaN;
                }
            } else {
                reliability[alg] = NaN;
            }
        }
        
        // 计算整体统计
        var averageTime:Number = 0;
        var standardDeviation:Number = 0;
        
        if (allTimes.length > 0) {
            averageTime = arrayMean(allTimes);
            var variance:Number = arrayVariance(allTimes, averageTime);
            standardDeviation = Math.sqrt(variance);
        }
        
        return {
            fastest: fastest,
            slowest: slowest,
            averageTime: averageTime,
            standardDeviation: standardDeviation,
            reliability: reliability
        };
    }

    private function findOverallBestAlgorithm():String {
        var bestAlg:String = "";
        var bestScore:Number = Infinity;
        
        for (var alg:String in performanceMatrix) {
            var totalTime:Number = 0;
            var count:Number = 0;
            
            for (var dist:String in performanceMatrix[alg]) {
                for (var size:String in performanceMatrix[alg][dist]) {
                    var time:Number = performanceMatrix[alg][dist][size];
                    if (isFinite(time) && time >= 0) {
                        totalTime += time;
                        count++;
                    }
                }
            }
            
            if (count > 0) {
                var avgScore:Number = totalTime / count;
                if (avgScore < bestScore) {
                    bestScore = avgScore;
                    bestAlg = alg;
                }
            }
        }
        
        return bestAlg || "无数据";
    }

    private function calculateAlgorithmScore(algName:String):Object {
        var totalTime:Number = 0;
        var count:Number = 0;
        var bestScenario:String = "";
        var worstScenario:String = "";
        var bestTime:Number = Infinity;
        var worstTime:Number = 0;
        
        if (performanceMatrix[algName]) {
            for (var dist:String in performanceMatrix[algName]) {
                var distTotal:Number = 0;
                var distCount:Number = 0;
                
                for (var size:String in performanceMatrix[algName][dist]) {
                    var time:Number = performanceMatrix[algName][dist][size];
                    if (isFinite(time) && time >= 0) {
                        totalTime += time;
                        count++;
                        distTotal += time;
                        distCount++;
                    }
                }
                
                if (distCount > 0) {
                    var distAvg:Number = distTotal / distCount;
                    if (distAvg < bestTime) {
                        bestTime = distAvg;
                        bestScenario = dist;
                    }
                    if (distAvg > worstTime) {
                        worstTime = distAvg;
                        worstScenario = dist;
                    }
                }
            }
        }
        
        return {
            totalScore: count > 0 ? totalTime / count : Infinity,
            bestScenario: bestScenario || "无数据",
            worstScenario: worstScenario || "无数据",
            bestTime: bestTime < Infinity ? bestTime : 0,
            worstTime: worstTime
        };
    }

    private function interpretComplexitySlope(slope:Number):String {
        if (!isFinite(slope)) return "无法确定";
        if (slope < 1.2) return "O(n)";
        else if (slope < 1.8) return "O(n log n)";
        else if (slope < 2.2) return "O(n²)";
        else return "O(n^" + formatNumber(slope, 2) + ")";
    }

    private function findBestWorstCase(algName:String):Object {
        var best:Object = {scenario: "", avgTime: Infinity};
        var worst:Object = {scenario: "", avgTime: 0};
        
        if (performanceMatrix[algName]) {
            for (var dist:String in performanceMatrix[algName]) {
                var total:Number = 0;
                var count:Number = 0;
                
                for (var size:String in performanceMatrix[algName][dist]) {
                    var time:Number = performanceMatrix[algName][dist][size];
                    if (isFinite(time) && time >= 0) {
                        total += time;
                        count++;
                    }
                }
                
                if (count > 0) {
                    var avg:Number = total / count;
                    if (avg < best.avgTime) {
                        best.avgTime = avg;
                        best.scenario = dist;
                    }
                    if (avg > worst.avgTime) {
                        worst.avgTime = avg;
                        worst.scenario = dist;
                    }
                }
            }
        }
        
        return {best: best, worst: worst};
    }

    private function rankAlgorithmsForScenario(scenario:String):Array {
        var ranking:Array = [];
        
        for (var alg:String in performanceMatrix) {
            if (performanceMatrix[alg][scenario]) {
                var total:Number = 0;
                var count:Number = 0;
                
                for (var size:String in performanceMatrix[alg][scenario]) {
                    var time:Number = performanceMatrix[alg][scenario][size];
                    if (isFinite(time) && time >= 0) {
                        total += time;
                        count++;
                    }
                }
                
                if (count > 0) {
                    ranking.push({
                        algorithm: alg,
                        avgTime: total / count
                    });
                }
            }
        }
        
        ranking.sort(function(a:Object, b:Object):Number {
            return a.avgTime - b.avgTime;
        });
        
        return ranking;
    }

    private function findBestAlgorithmForDistribution(distName:String):String {
        var ranking:Array = rankAlgorithmsForScenario(distName);
        return ranking.length > 0 ? ranking[0].algorithm : "N/A";
    }

    private function findBestForSmallData():String {
        var smallSizes:Array = [10, 50, 100];
        return findBestForSizes(smallSizes);
    }

    private function findBestForLargeData():String {
        var largeSizes:Array = [3000, 10000];
        return findBestForSizes(largeSizes);
    }

    private function findBestForSizes(targetSizes:Array):String {
        var bestAlg:String = "";
        var bestScore:Number = Infinity;
        
        for (var alg:String in performanceMatrix) {
            var totalTime:Number = 0;
            var count:Number = 0;
            
            for (var dist:String in performanceMatrix[alg]) {
                for (var sizeStr:String in performanceMatrix[alg][dist]) {
                    var size:Number = Number(sizeStr);
                    if (arrayContains(targetSizes, size)) {
                        var time:Number = performanceMatrix[alg][dist][sizeStr];
                        if (isFinite(time) && time >= 0) {
                            totalTime += time;
                            count++;
                        }
                    }
                }
            }
            
            if (count > 0) {
                var avgTime:Number = totalTime / count;
                if (avgTime < bestScore) {
                    bestScore = avgTime;
                    bestAlg = alg;
                }
            }
        }
        
        return bestAlg || "无数据";
    }

    private function findBestForSortedData():String {
        return findBestAlgorithmForDistribution("已排序");
    }

    private function findBestForDuplicates():String {
        return findBestAlgorithmForDistribution("重复元素");
    }

    /**
     * 从所有通过稳定性测试的算法中选择性能最好的
     * @return 最佳稳定排序算法名称
     */
    private function findBestForStableSort():String {
        var stableAlgorithms:Array = [];

        // 收集所有稳定的算法
        for (var alg:String in stabilityResults) {
            if (stabilityResults[alg].stable) {
                stableAlgorithms.push(alg);
            }
        }

        if (stableAlgorithms.length == 0) {
            return "无稳定算法";
        }

        // 在稳定算法中找性能最好的
        var bestAlg:String = stableAlgorithms[0];
        var bestScore:Number = Infinity;

        for (var i:Number = 0; i < stableAlgorithms.length; i++) {
            var algName:String = stableAlgorithms[i];
            var totalTime:Number = 0;
            var count:Number = 0;

            // 计算该算法的平均性能
            for (var dist:String in performanceMatrix[algName]) {
                for (var size:String in performanceMatrix[algName][dist]) {
                    var time:Number = performanceMatrix[algName][dist][size];
                    if (isFinite(time) && time >= 0) {
                        totalTime += time;
                        count++;
                    }
                }
            }

            if (count > 0) {
                var avgScore:Number = totalTime / count;
                if (avgScore < bestScore) {
                    bestScore = avgScore;
                    bestAlg = algName;
                }
            }
        }

        return bestAlg;
    }

    /**
     * 从原地排序算法中选择性能最好的
     * 原地排序算法：PDQSort, QuickSort, AdaptiveSort
     * @return 最佳原地排序算法名称
     */
    private function findBestForMemory():String {
        var inPlaceAlgorithms:Array = ["PDQSort", "QuickSort", "AdaptiveSort"];
        var bestAlg:String = inPlaceAlgorithms[0];
        var bestScore:Number = Infinity;

        for (var i:Number = 0; i < inPlaceAlgorithms.length; i++) {
            var algName:String = inPlaceAlgorithms[i];

            // 检查算法是否存在
            if (!performanceMatrix[algName]) continue;

            var totalTime:Number = 0;
            var count:Number = 0;

            // 计算该算法的平均性能
            for (var dist:String in performanceMatrix[algName]) {
                for (var size:String in performanceMatrix[algName][dist]) {
                    var time:Number = performanceMatrix[algName][dist][size];
                    if (isFinite(time) && time >= 0) {
                        totalTime += time;
                        count++;
                    }
                }
            }

            if (count > 0) {
                var avgScore:Number = totalTime / count;
                if (avgScore < bestScore) {
                    bestScore = avgScore;
                    bestAlg = algName;
                }
            }
        }

        return bestAlg;
    }

    private function findBestForPerformance():String {
        return findOverallBestAlgorithm();
    }

    private function findMostVersatileAlgorithm():String {
        var versatilityScores:Object = {};
        
        // 计算每个算法在不同场景下的变异系数
        for (var alg:String in performanceMatrix) {
            var scenarioTimes:Array = [];
            
            for (var dist:String in performanceMatrix[alg]) {
                var total:Number = 0;
                var count:Number = 0;
                
                for (var size:String in performanceMatrix[alg][dist]) {
                    var time:Number = performanceMatrix[alg][dist][size];
                    if (isFinite(time) && time >= 0) {
                        total += time;
                        count++;
                    }
                }
                
                if (count > 0) {
                    scenarioTimes.push(total / count);
                }
            }
            
            if (scenarioTimes.length > 1) {
                var mean:Number = arrayMean(scenarioTimes);
                var variance:Number = arrayVariance(scenarioTimes, mean);
                
                if (mean > 0 && variance >= 0) {
                    var cv:Number = Math.sqrt(variance) / mean;
                    versatilityScores[alg] = cv;
                }
            }
        }
        
        // 找变异系数最小的（最稳定的）
        var mostVersatile:String = "";
        var lowestCV:Number = Infinity;
        
        for (var algorithm:String in versatilityScores) {
            if (versatilityScores[algorithm] < lowestCV) {
                lowestCV = versatilityScores[algorithm];
                mostVersatile = algorithm;
            }
        }
        
        return mostVersatile || "无数据";
    }

    // ===== 增强的稳定性测试方法 =====
    
    private function checkStabilityEnhanced(result:Array, expected:Array):Boolean {
        if (result.length != expected.length) return false;
        
        for (var i:Number = 0; i < result.length; i++) {
            if (result[i].value != expected[i].value || result[i].id != expected[i].id) {
                return false;
            }
        }
        return true;
    }
    
    private function analyzeStabilityViolations(result:Array, expected:Array):Void {
        // 按值分组检查稳定性
        var valueGroups:Object = {};
        
        // 构建期望的分组
        for (var i:Number = 0; i < expected.length; i++) {
            var item:Object = expected[i];
            if (!valueGroups[item.value]) {
                valueGroups[item.value] = [];
            }
            valueGroups[item.value].push(item.id);
        }
        
        // 检查实际结果
        var resultGroups:Object = {};
        for (var j:Number = 0; j < result.length; j++) {
            var resultItem:Object = result[j];
            if (!resultGroups[resultItem.value]) {
                resultGroups[resultItem.value] = [];
            }
            resultGroups[resultItem.value].push(resultItem.id);
        }
        
        // 比较每个值的稳定性
        for (var value:String in valueGroups) {
            var expectedOrder:Array = valueGroups[value];
            var actualOrder:Array = resultGroups[value] || [];
            
            if (!arraysEqual(expectedOrder, actualOrder, null)) {
                trace("    值 " + value + " 的相对顺序错误:");
                trace("      期望: " + expectedOrder.join(","));
                trace("      实际: " + actualOrder.join(","));
            }
        }
    }

    // ===== 数组工具函数 (AS2兼容) =====
    
    private function arrayIndexOf(arr:Array, item):Number {
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i] === item) return i;
        }
        return -1;
    }
    
    private function arrayContains(arr:Array, item):Boolean {
        return arrayIndexOf(arr, item) !== -1;
    }
    
    private function arraySum(arr:Array):Number {
        var sum:Number = 0;
        for (var i:Number = 0; i < arr.length; i++) {
            if (isFinite(arr[i])) {
                sum += arr[i];
            }
        }
        return sum;
    }
    
    private function arrayMean(arr:Array):Number {
        if (arr.length == 0) return 0;
        return arraySum(arr) / arr.length;
    }
    
    private function arrayVariance(arr:Array, mean:Number):Number {
        if (arr.length <= 1) return 0;
        
        var sumSquares:Number = 0;
        for (var i:Number = 0; i < arr.length; i++) {
            if (isFinite(arr[i])) {
                var diff:Number = arr[i] - mean;
                sumSquares += diff * diff;
            }
        }
        return sumSquares / (arr.length - 1);
    }
    
    private function arrayMin(arr:Array):Number {
        if (arr.length == 0) return NaN;
        var min:Number = arr[0];
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i] < min) min = arr[i];
        }
        return min;
    }
    
    private function arrayMax(arr:Array):Number {
        if (arr.length == 0) return NaN;
        var max:Number = arr[0];
        for (var i:Number = 1; i < arr.length; i++) {
            if (arr[i] > max) max = arr[i];
        }
        return max;
    }
    
    // ===== 格式化工具函数 =====
    
    private function formatNumber(num:Number, decimalPlaces:Number):String {
        if (!isFinite(num)) return "N/A";
        
        var factor:Number = Math.pow(10, decimalPlaces);
        var rounded:Number = Math.round(num * factor) / factor;
        var str:String = rounded.toString();
        
        // 简单的小数位数控制
        if (decimalPlaces > 0 && str.indexOf(".") === -1) {
            str += ".";
            for (var i:Number = 0; i < decimalPlaces; i++) {
                str += "0";
            }
        }
        
        return str;
    }
    
    // ===== 其他原有的辅助方法保持不变 =====
    
    private function builtInSort(arr:Array, compareFunction:Function):Array {
        if (compareFunction != null) arr.sort(compareFunction);
        else                        arr.sort(Array.NUMERIC);
        return arr;
    }
    
    private function copyArray(src:Array):Array {
        var dst:Array = [];
        for (var i:Number = 0; i < src.length; i++) {
            if (typeof(src[i])=="object" && src[i]!=null) {
                dst.push(copyObject(src[i]));
            } else {
                dst.push(src[i]);
            }
        }
        return dst;
    }
    
    private function copyObject(o:Object):Object {
        var n:Object = {};
        for (var k:String in o) n[k] = o[k];
        return n;
    }
    
    private function arraysEqual(a:Array, b:Array, cmp:Function):Boolean {
        if (a.length!=b.length) return false;
        for (var i:Number=0; i<a.length; i++) {
            if (cmp!=null) {
                if (cmp(a[i],b[i])!==0) return false;
            } else {
                if (a[i]!==b[i]) return false;
            }
        }
        return true;
    }
    
    private function generateArray(size:Number, dist:String):Array {
        switch(dist) {
            case "random":           return generateRandomArray(size);
            case "sorted":           return generateSortedArray(size);
            case "reverse":          return generateReverseSortedArray(size);
            case "partiallySorted":  return generatePartiallySortedArray(size);
            case "duplicates":       return generateDuplicateElementsArray(size);
            case "allSame":          return generateAllSameElementsArray(size);
            case "nearlySorted":     return generateNearlySortedArray(size);
            case "pipeOrgan":        return generatePipeOrganArray(size);
            case "sawtooth":         return generateSawtoothArray(size);
            default:                 return generateRandomArray(size);
        }
    }
    
    private function generateRandomArray(size:Number):Array {
        resetRNG(54321); // 为随机数组生成设置固定种子
        var a:Array = [];
        for (var i:Number=0; i<size; i++) a.push(rng.randomInteger(0, size - 1));
        return a;
    }
    private function generateSortedArray(size:Number):Array {
        var a:Array = [];
        for (var i:Number=0; i<size; i++) a.push(i);
        return a;
    }
    private function generateReverseSortedArray(size:Number):Array {
        var a:Array = [];
        for (var i:Number=size; i>0; i--) a.push(i);
        return a;
    }
    private function generatePartiallySortedArray(size:Number):Array {
        var a:Array = generateSortedArray(size);
        var c:Number = Math.floor(size*0.1);
        resetRNG(11111); // 为部分有序数组设置固定种子
        for (var i:Number=0; i<c; i++) {
            var x:Number=rng.randomInteger(0, size - 1),
                y:Number=rng.randomInteger(0, size - 1);
            var t=a[x];a[x]=a[y];a[y]=t;
        }
        return a;
    }
    private function generateDuplicateElementsArray(size:Number):Array {
        resetRNG(22222); // 为重复元素数组设置固定种子
        var a:Array=[]; 
        for (var i:Number=0; i<size; i++) a.push(rng.randomInteger(0, 9));
        return a;
    }
    private function generateAllSameElementsArray(size:Number):Array {
        resetRNG(33333); // 为全相同元素数组设置固定种子
        var v:Number=rng.randomInteger(0, 99), a:Array=[];
        for(var i:Number=0;i<size;i++) a.push(v);
        return a;
    }
    private function generateNearlySortedArray(size:Number):Array {
        var a:Array=generateSortedArray(size);
        var swaps:Number=Math.floor(size*0.01);
        resetRNG(44444); // 为几乎有序数组设置固定种子
        for(var i:Number=0;i<swaps;i++){
            var x:Number=rng.randomInteger(0, size - 1),
                y:Number=rng.randomInteger(0, size - 1);
            var t=a[x];a[x]=a[y];a[y]=t;
        }
        return a;
    }
    private function generatePipeOrganArray(size:Number):Array {
        var a:Array=[],
            mid:Number=Math.floor(size/2);
        for(var i:Number=0;i<mid;i++) a.push(i);
        for(var j:Number=mid;j>=0;j--) a.push(j);
        resetRNG(55555); // 为管道风琴数组设置固定种子
        while(a.length<size) a.push(rng.randomInteger(0, mid - 1));
        return a.slice(0,size);
    }
    private function generateSawtoothArray(size:Number):Array {
        var a:Array=[],
            wave:Number=Math.floor(size/10);
        for(var i:Number=0;i<size;i++) a.push(i%wave);
        return a;
    }
    private function generateExtremeValues(size:Number):Array {
        resetRNG(66666); // 为极值数据设置固定种子
        var a:Array=[];
        var maxSafeValue:Number = 1000000; // 避免使用Number.MAX_VALUE
        for(var i:Number=0;i<size;i++){
            var r:Number=rng.nextFloat();
            if(r<0.1)      a.push(maxSafeValue);
            else if(r<0.2) a.push(-maxSafeValue);
            else           a.push(rng.randomInteger(0, 999));
        }
        return a;
    }
    private function generateHighDuplicates(size:Number):Array {
        resetRNG(77777); // 为高重复数据设置固定种子
        var vals:Array=[1,2,3], a:Array=[];
        for(var i:Number=0;i<size;i++)
            a.push(vals[rng.randomInteger(0, vals.length - 1)]);
        return a;
    }
    private function generateThreeValues(size:Number):Array {
        var a:Array=[];
        for(var i:Number=0;i<size;i++){
            if(i<size/3)      a.push(1);
            else if(i<2*size/3) a.push(2);
            else                a.push(3);
        }
        resetRNG(88888); // 为三值数据打乱设置固定种子
        shuffleArray(a);
        return a;
    }
    private function generateAlternatingPattern(size:Number):Array {
        var a:Array=[];
        for(var i:Number=0;i<size;i++) a.push(i%2==0?1:1000);
        return a;
    }
    private function generateExponentialPattern(size:Number):Array {
        resetRNG(99999); // 为指数模式设置固定种子
        var a:Array=[];
        for(var i:Number=0;i<size;i++)
            a.push(Math.floor(Math.pow(2,rng.nextFloat()*10)));
        return a;
    }
    private function shuffleArray(a:Array):Void {
        // 打乱使用当前的随机数生成器状态
        for(var i:Number=a.length-1;i>0;i--){
            var j:Number=rng.randomInteger(0, i),
                t=a[i];a[i]=a[j];a[j]=t;
        }
    }
    private function quickSortValidation(a:Array):Boolean {
        var c:Number=Math.min(100,a.length);
        for(var i:Number=1;i<c;i++) if(a[i]<a[i-1]) return false;
        var start:Number=Math.max(0,a.length-100);
        for(var j:Number=start+1;j<a.length;j++) if(a[j]<a[j-1]) return false;
        return true;
    }
    private function checkStability(res:Array, exp:Array):Boolean {
        if(res.length!=exp.length) return false;
        for(var i:Number=0;i<res.length;i++){
            if(res[i].value!=exp[i].value||res[i].id!=exp[i].id) return false;
        }
        return true;
    }
    private function formatObjectArray(a:Array):String {
        var s:String="["; 
        for(var i:Number=0;i<a.length;i++){
            if(i>0) s+=", ";
            s+=a[i].value+"("+a[i].id+")";
        }
        return s+"]";
    }
    private function analyzeByDataPattern():Void {
        trace("\n数据模式性能分析:");
        for(var alg:String in performanceMatrix){
            trace("\n" + alg + ":");
            var pats:Object=performanceMatrix[alg],
                bestP:String="", worstP:String="",
                bestT:Number=Infinity, worstT:Number=0;
            for(var p:String in pats){
                var sizes:Object=pats[p],
                    sum:Number=0, cnt:Number=0;
                for(var sz:String in sizes){
                    var time:Number = sizes[sz];
                    if (isFinite(time) && time >= 0) {
                        sum += time;
                        cnt++;
                    }
                }
                if(cnt>0){
                    var avg:Number=sum/cnt;
                    trace("  "+p+": "+formatNumber(avg, 2)+"ms");
                    if(avg<bestT){ bestT=avg; bestP=p; }
                    if(avg>worstT){ worstT=avg; worstP=p; }
                }
            }
            trace("  最优: "+bestP+"("+formatNumber(bestT, 2)+"ms)");
            trace("  最差: "+worstP+"("+formatNumber(worstT, 2)+"ms)");
        }
    }
    private function analyzeScalability():Void {
        trace("\n规模伸缩性分析:");
        for(var i:Number=0;i<sortMethods.length;i++){
            var alg:String=sortMethods[i].name;
            if (performanceMatrix[alg]["随机数据"]) {
                trace("\n"+alg+" 随机数据趋势:");
                var map:Object=performanceMatrix[alg]["随机数据"];
                
                // 收集并排序数据点
                var dataPoints:Array = [];
                for(var sStr:String in map){
                    var s:Number=Number(sStr), t:Number=map[sStr];
                    if (isFinite(t) && t >= 0) {
                        dataPoints.push({size: s, time: t});
                    }
                }
                
                dataPoints.sort(function(a:Object, b:Object):Number {
                    return a.size - b.size;
                });
                
                // 分析相邻点的趋势
                for (var j:Number = 1; j < dataPoints.length; j++) {
                    var curr:Object = dataPoints[j];
                    var prev:Object = dataPoints[j-1];
                    
                    var sr:Number = curr.size / prev.size;
                    var tr:Number = prev.time > 0 ? curr.time / prev.time : NaN;
                    var cf:Number = isFinite(tr) && sr > 1 ? tr / sr : NaN;
                    
                    trace("  " + prev.size + "→" + curr.size + 
                          ": 时间比" + formatNumber(tr, 3) + 
                          " 复杂度因子" + formatNumber(cf, 3));
                }
            }
        }
    }
    private function generateRecommendations():Void {
        trace("\n使用建议:");
        trace("  • 小数据(<100): " + findBestForSmallData());
        trace("  • 需要稳定: " + findBestForStableSort());
        trace("  • 内存受限: " + findBestForMemory());
        trace("  • 随机数据: " + findBestAlgorithmForDistribution("随机数据"));
        trace("  • 部分有序: " + findBestAlgorithmForDistribution("部分有序"));
        trace("  • 重复多: " + findBestAlgorithmForDistribution("重复元素"));
    }

    private function generateKeyInsights():Void {
        trace("   • 算法选择应基于具体使用场景和数据特征");
        trace("   • 预排序检测对性能提升显著");
        trace("   • 三路分区技术在处理重复元素时优势明显");
        trace("   • 大规模数据更能体现高级算法的优势");
        trace("   • 内存使用模式是选择算法的重要考虑因素");
    }

    /**
     * 重复字符
     */
    private function repeatChar(ch:String, count:Number):String {
        var s:String = "";
        for (var i:Number = 0; i < count; i++) {
            s += ch;
        }
        return s;
    }
}