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
    
    /*** 7. 最终报告生成 ***/
    private function generateFinalReport():Void {
        trace("\n" + repeatChar("=", 40));
        trace("最终测试报告");
        trace(repeatChar("=", 40));
        // 这里只做简介展示
        trace("…（略：性能摘要、特性总结、CSV导出等）");
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
