/**
 * 增强版 SortTest 类
 * 位于 org.flashNight.naki.Sort 包下
 * 提供全面的排序算法性能评估和分析功能
 */
class org.flashNight.naki.Sort.SortTest {
    
    // 测试配置
    private var testConfig:Object = {
        basicSizes:       [10, 50, 100, 300, 1000, 3000, 10000],
        stressSizes:      [30000, 100000, 300000],
        testIterations:   5,
        enableMemoryMonitoring: true,
        enableDetailedStats:    true,
        generateCSVReport:      true
    };
    
    // 存储性能数据
    private var performanceMatrix:Object;
    
    // 排序方法定义
    private var sortMethods:Array = [
        { name: "InsertionSort", sort: org.flashNight.naki.Sort.InsertionSort.sort, expectedComplexity: "O(n²)" },
        { name: "PDQSort",       sort: org.flashNight.naki.Sort.PDQSort.sort,       expectedComplexity: "O(n log n)" },
        { name: "QuickSort",     sort: org.flashNight.naki.Sort.QuickSort.sort,     expectedComplexity: "O(n log n)" },
        { name: "AdaptiveSort",  sort: org.flashNight.naki.Sort.QuickSort.adaptiveSort, expectedComplexity: "O(n log n)" },
        { name: "TimSort",       sort: org.flashNight.naki.Sort.TimSort.sort,       expectedComplexity: "O(n log n)" },
        { name: "BuiltInSort",   sort: builtInSort,                                 expectedComplexity: "O(n log n)" }
    ];
    
    /**
     * 构造函数
     */
    public function SortTest(cfg:Object) {
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
        for (var i:Number = 0; i < sortMethods.length; i++) {
            performanceMatrix[sortMethods[i].name] = {};
        }
    }
    
    /**
     * 运行完整的测试套件
     */
    public function runCompleteTestSuite():Void {
        trace(repeatChar("=", 80));
        trace("启动增强版排序算法测试套件");
        trace(repeatChar("=", 80));
        
        runBasicFunctionalityTests();
        runStabilityTests();
        runPerformanceBenchmarks();
        // runStressTests();
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
    
    /*** 2. 稳定性测试 ***/
    private function runStabilityTests():Void {
        trace("\n" + repeatChar("=", 40));
        trace("稳定性测试");
        trace(repeatChar("=", 40));
        
        var data:Array = [
            {value:3, id:"A"},
            {value:1, id:"B"},
            {value:3, id:"C"},
            {value:2, id:"D"},
            {value:1, id:"E"},
            {value:3, id:"F"}
        ];
        var compareFunc:Function = function(a:Object,b:Object):Number {
            return a.value < b.value ? -1 : (a.value > b.value ? 1 : 0);
        };
        var expected:Array = [
            {value:1, id:"B"},
            {value:1, id:"E"},
            {value:2, id:"D"},
            {value:3, id:"A"},
            {value:3, id:"C"},
            {value:3, id:"F"}
        ];
        
        trace("\n原始: " + formatObjectArray(data));
        trace("期望: " + formatObjectArray(expected));
        
        for (var i:Number = 0; i < sortMethods.length; i++) {
            var m:Object = sortMethods[i];
            var arr:Array = copyArray(data);
            try {
                var res:Array = m.sort(arr, compareFunc);
                var stable:Boolean = checkStability(res, expected);
                trace("\n" + m.name + ": " + (stable ? "✓ 稳定" : "✗ 不稳定") +
                      " 结果:" + formatObjectArray(res));
            } catch (e:Error) {
                trace(m.name + " ERROR: " + e.message);
            }
        }
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
                    var exp:Array = copyArray(baseData); exp.sort(Array.NUMERIC);
                    if (arraysEqual(out, exp, null)) {
                        var dt:Number = t1 - t0;
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
                      " 平均:" + avgT +
                      "ms 最小:" + minT + "ms 最大:" + maxT + "ms 成功率:" + ((succ/testConfig.testIterations)*100) + "%");
            } else {
                trace("  " + m.name + " 所有运行均失败");
            }
        }
    }
    
    /*** 4. 压力测试 ***/
    private function runStressTests():Void {
        trace("\n" + repeatChar("=", 40));
        trace("压力测试 (大数据量)");
        trace(repeatChar("=", 40));
        
        for (var i:Number = 0; i < testConfig.stressSizes.length; i++) {
            var size:Number = testConfig.stressSizes[i];
            trace("\n-- 规模: " + size + " --");
            var baseData:Array = generateArray(size, "random");
            
            for (var j:Number = 0; j < sortMethods.length; j++) {
                var m:Object = sortMethods[j];
                trace("  测试 " + m.name + " ...");
                var t0:Number = getTimer();
                try {
                    var out:Array = m.sort(copyArray(baseData), null);
                    var t1:Number = getTimer();
                    var ok:Boolean = quickSortValidation(out);
                    trace("    时间:" + (t1-t0) + "ms 正确:" + (ok?"✓":"✗"));
                } catch (e:Error) {
                    trace("    ERROR: " + e.message);
                }
            }
        }
    }
    
    /*** 5. 特殊场景测试 ***/
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
                    var ok:Boolean = quickSortValidation(out);
                    trace("  " + m.name + ": " + (t1-t0) + "ms " + (ok?"✓":"✗"));
                } catch (e:Error) {
                    trace("  " + m.name + " ERROR: " + e.message);
                }
            }
        }
    }
    
    /*** 6. 算法比较分析 ***/
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
                if (dataDistributions.indexOf(dist) === -1) {
                    dataDistributions.push(dist);
                }
                for (var size:String in performanceMatrix[alg][dist]) {
                    totalTests++;
                }
            }
        }
        
        trace("• 测试算法数量: " + algorithmsCount);
        trace("• 数据分布类型: " + dataDistributions.length + " (" + dataDistributions.join(", ") + ")");
        trace("• 测试规模范围: " + Math.min.apply(null, testSizes) + " - " + Math.max.apply(null, testSizes));
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
                if (distributions.indexOf(dist) === -1) {
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
                    var time = "N/A";
                    
                    if (performanceMatrix[algName] && 
                        performanceMatrix[algName][distName] && 
                        performanceMatrix[algName][distName][size]) {
                        var ms:Number = performanceMatrix[algName][distName][size];
                        time = ms;
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
        
        trace("排名\t算法\t\t综合得分\t理论复杂度\t最佳场景\t最差场景");
        trace(repeatChar("-", 70));
        
        for (var r:Number = 0; r < algorithmScores.length; r++) {
            var rank:Object = algorithmScores[r];
            var rankStr:String = (r + 1) + "\t" + 
                            rank.name + "\t\t" + 
                            rank.totalScore + "\t\t" + 
                            rank.complexity + "\t" + 
                            rank.bestScenario + "\t" + 
                            rank.worstScenario;
            trace(rankStr);
        }
    }

    /**
     * 复杂度分析
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
                var complexityFactor:Number = calculateComplexityFactor(randomData);
                var actualComplexity:String = interpretComplexityFactor(complexityFactor);
                
                trace("  实际表现: " + actualComplexity + " (因子: " + complexityFactor + ")");
                
                // 分析最佳/最差情况
                var bestCase:Object = findBestWorstCase(algName);
                trace("  最佳情况: " + bestCase.best.scenario + " (" + bestCase.best.avgTime + "ms)");
                trace("  最差情况: " + bestCase.worst.scenario + " (" + bestCase.worst.avgTime + "ms)");
                trace("  性能比率: " + (bestCase.worst.avgTime / bestCase.best.avgTime) + ":1");
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
                trace("  " + (r+1) + ". " + rank.algorithm + ": " + rank.avgTime + "ms");
            }
        }
    }

    /**
     * 推荐矩阵
     */
    private function generateRecommendationMatrix():Void {
        trace("\n" + repeatChar("-", 60));
        trace("💡 使用推荐矩阵");
        trace(repeatChar("-", 60));
        
        var recommendations:Array = [
            {
                condition: "数据规模 < 50",
                recommended: findBestForSmallData(),
                reason: "小数据量时插入排序等简单算法效率更高"
            },
            {
                condition: "数据规模 > 10000",
                recommended: findBestForLargeData(),
                reason: "大数据量需要高效的分治算法"
            },
            {
                condition: "数据已基本有序",
                recommended: findBestForSortedData(),
                reason: "利用现有有序性可显著提升性能"
            },
            {
                condition: "包含大量重复元素",
                recommended: findBestForDuplicates(),
                reason: "三路分区等技术可优化重复元素处理"
            },
            {
                condition: "需要稳定排序",
                recommended: "TimSort",
                reason: "保持相同元素的相对顺序"
            },
            {
                condition: "内存限制严格",
                recommended: findBestForMemory(),
                reason: "原地排序算法减少额外内存使用"
            }
        ];
        
        for (var r:Number = 0; r < recommendations.length; r++) {
            var rec:Object = recommendations[r];
            trace("• " + rec.condition);
            trace("  推荐: " + rec.recommended);
            trace("  原因: " + rec.reason);
            trace("");
        }
    }

    /**
     * 统计摘要
     */
    private function generateStatisticalSummary():Void {
        trace("\n" + repeatChar("-", 60));
        trace("📈 统计摘要");
        trace(repeatChar("-", 60));
        
        var stats:Object = calculateOverallStatistics();
        
        trace("整体统计:");
        trace("• 最快单次执行: " + stats.fastest.time + "ms (" + 
            stats.fastest.algorithm + " - " + stats.fastest.scenario + ", " + 
            stats.fastest.size + "元素)");
        
        trace("• 最慢单次执行: " + stats.slowest.time + "ms (" + 
            stats.slowest.algorithm + " - " + stats.slowest.scenario + ", " + 
            stats.slowest.size + "元素)");
        
        trace("• 性能差距: " + (stats.slowest.time / stats.fastest.time) + "倍");
        
        trace("• 平均执行时间: " + stats.averageTime + "ms");
        trace("• 标准差: " + stats.standardDeviation + "ms");
        
        // 各算法可靠性分析
        trace("\n算法可靠性 (变异系数):");
        for (var alg:String in stats.reliability) {
            var cv:Number = stats.reliability[alg];
            var reliabilityLevel:String = cv < 0.1 ? "优秀" : (cv < 0.3 ? "良好" : "一般");
            trace("• " + alg + ": " + cv + " (" + reliabilityLevel + ")");
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
        
        for (var alg:String in performanceMatrix) {
            for (var dist:String in performanceMatrix[alg]) {
                for (var size:String in performanceMatrix[alg][dist]) {
                    var time:Number = performanceMatrix[alg][dist][size];
                    csvContent += alg + "," + dist + "," + size + "," + 
                                time + "," + testConfig.testIterations + "\n";
                }
            }
        }
        
        trace("CSV数据已生成 (共 " + csvContent.split("\n").length + " 行)");
        trace("数据格式: 算法,数据分布,规模,平均时间,迭代次数");
        
        // 在实际应用中，这里可以保存到文件
        // 由于AS2限制，这里只输出前几行作为示例
        var lines:Array = csvContent.split("\n");
        trace("\n前5行数据示例:");
        for (var i:Number = 0; i < Math.min(5, lines.length); i++) {
            trace(lines[i]);
        }
        trace("...(完整数据可导出到文件)");
    }

    /**
     * 结论
     */
    private function generateConclusion():Void {
        trace("\n" + repeatChar("-", 60));
        trace("🎯 测试结论");
        trace(repeatChar("-", 60));
        
        var overallBest:String = findOverallBestAlgorithm();
        var versatileBest:String = findMostVersatileAlgorithm();
        
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
        trace("   • 稳定性要求: TimSort");
        trace("   • 内存受限环境: " + findBestForMemory());
        
        trace("\n" + repeatChar("=", 80));
        trace("测试报告生成完成");
        trace(repeatChar("=", 80));
    }

    // ===== 辅助计算方法 =====

    private function findOverallBestAlgorithm():String {
        var bestAlg:String = "";
        var bestScore:Number = Infinity;
        
        for (var alg:String in performanceMatrix) {
            var score:Number = 0;
            var count:Number = 0;
            
            for (var dist:String in performanceMatrix[alg]) {
                for (var size:String in performanceMatrix[alg][dist]) {
                    score += performanceMatrix[alg][dist][size];
                    count++;
                }
            }
            
            if (count > 0) {
                var avgScore:Number = score / count;
                if (avgScore < bestScore) {
                    bestScore = avgScore;
                    bestAlg = alg;
                }
            }
        }
        
        return bestAlg;
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
                    totalTime += time;
                    count++;
                    distTotal += time;
                    distCount++;
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
            bestScenario: bestScenario,
            worstScenario: worstScenario,
            bestTime: bestTime,
            worstTime: worstTime
        };
    }

    private function calculateComplexityFactor(dataPoints:Object):Number {
        var sizes:Array = [];
        var times:Array = [];
        
        for (var size:String in dataPoints) {
            sizes.push(Number(size));
            times.push(dataPoints[size]);
        }
        
        if (sizes.length < 2) return 1.0;
        
        // 简单的复杂度估算：比较相邻点的时间增长率与规模增长率
        var totalFactor:Number = 0;
        var factorCount:Number = 0;
        
        for (var i:Number = 1; i < sizes.length; i++) {
            var sizeRatio:Number = sizes[i] / sizes[i-1];
            var timeRatio:Number = times[i] / times[i-1];
            
            if (sizeRatio > 1 && timeRatio > 0) {
                var factor:Number = Math.log(timeRatio) / Math.log(sizeRatio);
                totalFactor += factor;
                factorCount++;
            }
        }
        
        return factorCount > 0 ? totalFactor / factorCount : 1.0;
    }

    private function interpretComplexityFactor(factor:Number):String {
        if (factor < 1.2) return "O(n)";
        else if (factor < 1.8) return "O(n log n)";
        else if (factor < 2.2) return "O(n²)";
        else return "O(n^" + factor + ")";
    }

    private function findBestWorstCase(algName:String):Object {
        var best:Object = {scenario: "", avgTime: Infinity};
        var worst:Object = {scenario: "", avgTime: 0};
        
        if (performanceMatrix[algName]) {
            for (var dist:String in performanceMatrix[algName]) {
                var total:Number = 0;
                var count:Number = 0;
                
                for (var size:String in performanceMatrix[algName][dist]) {
                    total += performanceMatrix[algName][dist][size];
                    count++;
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
                    total += performanceMatrix[alg][scenario][size];
                    count++;
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
        // 基于小规模数据的性能找最佳算法
        var smallSizes:Array = [10, 50, 100];
        return findBestForSizes(smallSizes);
    }

    private function findBestForLargeData():String {
        // 基于大规模数据的性能找最佳算法
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
                        totalTime += performanceMatrix[alg][dist][sizeStr];
                        count++;
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
        
        return bestAlg;
    }

    private function findBestForSortedData():String {
        return findBestAlgorithmForDistribution("已排序");
    }

    private function findBestForDuplicates():String {
        return findBestAlgorithmForDistribution("全相同");
    }

    private function findBestForMemory():String {
        // 基于算法特性推断，通常PDQSort和QuickSort是原地的
        return "PDQSort";
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
                    total += performanceMatrix[alg][dist][size];
                    count++;
                }
                
                if (count > 0) {
                    scenarioTimes.push(total / count);
                }
            }
            
            if (scenarioTimes.length > 1) {
                var mean:Number = scenarioTimes.reduce(function(sum:Number, val:Number):Number {
                    return sum + val;
                }, 0) / scenarioTimes.length;
                
                var variance:Number = scenarioTimes.reduce(function(sum:Number, val:Number):Number {
                    return sum + Math.pow(val - mean, 2);
                }, 0) / scenarioTimes.length;
                
                var cv:Number = Math.sqrt(variance) / mean; // 变异系数
                versatilityScores[alg] = cv;
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
        
        return mostVersatile;
    }

    private function calculateOverallStatistics():Object {
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
            
            // 计算各算法的变异系数
            if (algTimes.length > 1) {
                var mean:Number = algTimes.reduce(function(sum:Number, val:Number):Number {
                    return sum + val;
                }, 0) / algTimes.length;
                
                var variance:Number = algTimes.reduce(function(sum:Number, val:Number):Number {
                    return sum + Math.pow(val - mean, 2);
                }, 0) / algTimes.length;
                
                reliability[alg] = Math.sqrt(variance) / mean;
            }
        }
        
        // 计算整体统计
        var totalTime:Number = allTimes.reduce(function(sum:Number, val:Number):Number {
            return sum + val;
        }, 0);
        var averageTime:Number = totalTime / allTimes.length;
        
        var variance:Number = allTimes.reduce(function(sum:Number, val:Number):Number {
            return sum + Math.pow(val - averageTime, 2);
        }, 0) / allTimes.length;
        
        return {
            fastest: fastest,
            slowest: slowest,
            averageTime: averageTime,
            standardDeviation: Math.sqrt(variance),
            reliability: reliability
        };
    }

    private function generateKeyInsights():Void {
        trace("   • 算法选择应基于具体使用场景和数据特征");
        trace("   • 预排序检测对性能提升显著");
        trace("   • 三路分区技术在处理重复元素时优势明显");
        trace("   • 大规模数据更能体现高级算法的优势");
        trace("   • 内存使用模式是选择算法的重要考虑因素");
    }

    private function arrayContains(arr:Array, item):Boolean {
        for (var i:Number = 0; i < arr.length; i++) {
            if (arr[i] === item) return true;
        }
        return false;
    }
    
    
    // ===== 辅助方法 =====
    
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
        var a:Array = [];
        for (var i:Number=0; i<size; i++) a.push(Math.floor(Math.random()*size));
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
        for (var i:Number=0; i<c; i++) {
            var x:Number=Math.floor(Math.random()*size),
                y:Number=Math.floor(Math.random()*size);
            var t=a[x];a[x]=a[y];a[y]=t;
        }
        return a;
    }
    private function generateDuplicateElementsArray(size:Number):Array {
        var a:Array=[]; for (var i:Number=0; i<size; i++) a.push(Math.floor(Math.random()*10));
        return a;
    }
    private function generateAllSameElementsArray(size:Number):Array {
        var v:Number=Math.floor(Math.random()*100), a:Array=[];
        for(var i:Number=0;i<size;i++) a.push(v);
        return a;
    }
    private function generateNearlySortedArray(size:Number):Array {
        var a:Array=generateSortedArray(size);
        var swaps:Number=Math.floor(size*0.01);
        for(var i:Number=0;i<swaps;i++){
            var x:Number=Math.floor(Math.random()*size),
                y:Number=Math.floor(Math.random()*size);
            var t=a[x];a[x]=a[y];a[y]=t;
        }
        return a;
    }
    private function generatePipeOrganArray(size:Number):Array {
        var a:Array=[],
            mid:Number=Math.floor(size/2);
        for(var i:Number=0;i<mid;i++) a.push(i);
        for(var j:Number=mid;j>=0;j--) a.push(j);
        while(a.length<size) a.push(Math.floor(Math.random()*mid));
        return a.slice(0,size);
    }
    private function generateSawtoothArray(size:Number):Array {
        var a:Array=[],
            wave:Number=Math.floor(size/10);
        for(var i:Number=0;i<size;i++) a.push(i%wave);
        return a;
    }
    private function generateExtremeValues(size:Number):Array {
        var a:Array=[];
        for(var i:Number=0;i<size;i++){
            var r:Number=Math.random();
            if(r<0.1)      a.push(Number.MAX_VALUE);
            else if(r<0.2) a.push(-Number.MAX_VALUE);
            else           a.push(Math.floor(Math.random()*1000));
        }
        return a;
    }
    private function generateHighDuplicates(size:Number):Array {
        var vals:Array=[1,2,3], a:Array=[];
        for(var i:Number=0;i<size;i++)
            a.push(vals[Math.floor(Math.random()*vals.length)]);
        return a;
    }
    private function generateThreeValues(size:Number):Array {
        var a:Array=[];
        for(var i:Number=0;i<size;i++){
            if(i<size/3)      a.push(1);
            else if(i<2*size/3) a.push(2);
            else                a.push(3);
        }
        shuffleArray(a);
        return a;
    }
    private function generateAlternatingPattern(size:Number):Array {
        var a:Array=[];
        for(var i:Number=0;i<size;i++) a.push(i%2==0?1:1000);
        return a;
    }
    private function generateExponentialPattern(size:Number):Array {
        var a:Array=[];
        for(var i:Number=0;i<size;i++)
            a.push(Math.floor(Math.pow(2,Math.random()*10)));
        return a;
    }
    private function shuffleArray(a:Array):Void {
        for(var i:Number=a.length-1;i>0;i--){
            var j:Number=Math.floor(Math.random()*(i+1)),
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
                    sum += sizes[sz]; cnt++;
                }
                if(cnt>0){
                    var avg:Number=sum/cnt;
                    trace("  "+p+": "+avg+"ms");
                    if(avg<bestT){ bestT=avg; bestP=p; }
                    if(avg>worstT){ worstT=avg; worstP=p; }
                }
            }
            trace("  最优: "+bestP+"("+bestT+"ms)");
            trace("  最差: "+worstP+"("+worstT+"ms)");
        }
    }
    private function analyzeScalability():Void {
        trace("\n规模伸缩性分析:");
        for(var i:Number=0;i<sortMethods.length;i++){
            var alg:String=sortMethods[i].name;
            trace("\n"+alg+" 随机数据趋势:");
            var map:Object=performanceMatrix[alg]["随机数据"];
            var prevS:Number=0, prevT:Number=0;
            for(var sStr:String in map){
                var s:Number=Number(sStr), t:Number=map[sStr];
                if(prevS>0){
                    var sr:Number=s/prevS, tr:Number=t/prevT,
                        cf:Number=tr/sr;
                    trace("  "+prevS+"→"+s+": 时间比"+tr+" 复杂度因子"+cf);
                }
                prevS=s; prevT=t;
            }
        }
    }
    private function generateRecommendations():Void {
        trace("\n使用建议:");
        trace("  • 小数据(<50): InsertionSort");
        trace("  • 需要稳定: TimSort");
        trace("  • 内存受限: PDQSort");
        trace("  • 随机数据: PDQSort");
        trace("  • 部分有序: TimSort");
        trace("  • 重复多: PDQSort");
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
