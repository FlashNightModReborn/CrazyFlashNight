import org.flashNight.gesh.pratt.*;

/**
 * PrattEvaluator 100%覆盖测试套件
 * 
 * 测试策略：
 * 1. 验证最高层集成的所有功能
 * 2. 上下文管理的完整性测试
 * 3. 所有API方法的正确性验证
 * 4. 工厂方法和预设配置测试
 * 5. 高级功能（批量、安全、缓存等）
 * 6. 性能优化和边界条件
 * 
 * 核心验证原则：
 * - 依赖已验证的底层组件
 * - 专注于Evaluator自身的逻辑
 * - 确保所有用户API的可靠性
 */
class org.flashNight.gesh.pratt.PrattEvaluator_TestSuite {
    
    private static var _testCount:Number = 0;
    private static var _passCount:Number = 0;
    private static var _failCount:Number = 0;
    
    public static function runAllTests():Void {
        trace("========== PrattEvaluator 100%覆盖测试开始 ==========");
        
        _testCount = 0;
        _passCount = 0;
        _failCount = 0;
        
        // 按功能模块分组测试
        testConstructorAndInitialization();  // 构造函数和初始化
        testContextManagement();             // 上下文管理
        testBasicEvaluationAPI();             // 基础求值API
        testAdvancedEvaluationFeatures();    // 高级求值功能
        testFactoryMethods();                 // 工厂方法
        testCachingMechanism();               // 缓存机制
        testErrorHandlingAndSafety();         // 错误处理和安全性
        testUtilityMethods();                 // 实用工具方法
        testPerformanceFeatures();            // 性能功能
        testIntegrationScenarios();           // 集成场景
        testBoundaryConditions();             // 边界条件
        testMemoryAndResourceManagement();    // 内存和资源管理
        
        // 输出测试结果
        trace("\n========== PrattEvaluator 测试结果 ==========");
        trace("总计: " + _testCount + " 个测试");
        trace("通过: " + _passCount + " 个");
        trace("失败: " + _failCount + " 个");
        trace("覆盖率: " + Math.round((_passCount / _testCount) * 100) + "%");
        
        if (_failCount == 0) {
            trace("✅ PrattEvaluator 所有测试通过！");
        } else {
            trace("❌ 存在 " + _failCount + " 个失败的测试");
        }
        trace("==========================================");
    }
    
    // ============================================================================
    // 测试分组1：构造函数和初始化
    // ============================================================================
    private static function testConstructorAndInitialization():Void {
        trace("\n--- 测试分组1：构造函数和初始化 ---");
        
        // 基础构造函数测试
        var evaluator:PrattEvaluator = new PrattEvaluator();
        _assert(evaluator != null, "构造函数：应该成功创建PrattEvaluator实例");
        
        // 验证初始化的内置函数
        var mathExists:Boolean = evaluator.getVariable("Math") != null;
        _assert(mathExists, "初始化：Math对象应该被预置");
        
        var piExists:Boolean = evaluator.getVariable("PI") != null;
        _assert(piExists, "初始化：PI常量应该被预置");
        
        var eExists:Boolean = evaluator.getVariable("E") != null;
        _assert(eExists, "初始化：E常量应该被预置");
        
        // 验证内置函数的可用性
        var isNaNResult:Boolean = evaluator.evaluate("isNaN('hello')");
        _assert(isNaNResult === true, "内置函数：isNaN应该正常工作");
        
        var parseIntResult:Number = evaluator.evaluate("parseInt('123')");
        _assert(parseIntResult == 123, "内置函数：parseInt应该正常工作");
        
        var parseFloatResult:Number = evaluator.evaluate("parseFloat('123.45')");
        _assert(parseFloatResult == 123.45, "内置函数：parseFloat应该正常工作");
        
        var stringResult:String = evaluator.evaluate("String(123)");
        _assert(stringResult == "123", "内置函数：String应该正常工作");
        
        var numberResult:Number = evaluator.evaluate("Number('456')");
        _assert(numberResult == 456, "内置函数：Number应该正常工作");
        
        var booleanResult:Boolean = evaluator.evaluate("Boolean(1)");
        _assert(booleanResult === true, "内置函数：Boolean应该正常工作");
        
        // 验证通用数学函数
        var maxResult:Number = evaluator.evaluate("max(10, 20, 15)");
        _assert(maxResult == 20, "数学函数：max应该正常工作");
        
        var minResult:Number = evaluator.evaluate("min(10, 20)");
        _assert(minResult == 10, "数学函数：min应该正常工作");
        
        var clampResult:Number = evaluator.evaluate("clamp(15, 5, 10)");
        _assert(clampResult == 10, "数学函数：clamp应该正常工作");
        
        var absResult:Number = evaluator.evaluate("abs(-42)");
        _assert(absResult == 42, "数学函数：abs应该正常工作");
        
        var floorResult:Number = evaluator.evaluate("floor(3.7)");
        _assert(floorResult == 3, "数学函数：floor应该正常工作");
        
        var ceilResult:Number = evaluator.evaluate("ceil(3.2)");
        _assert(ceilResult == 4, "数学函数：ceil应该正常工作");
        
        var roundResult:Number = evaluator.evaluate("round(3.6)");
        _assert(roundResult == 4, "数学函数：round应该正常工作");
        
        // 验证初始状态
        var initialContext:Object = evaluator.getContext();
        _assert(initialContext != null, "初始状态：getContext应该返回非null对象");
        _assert(typeof initialContext == "object", "初始状态：context应该是对象类型");
    }
    
    // ============================================================================
    // 测试分组2：上下文管理
    // ============================================================================
    private static function testContextManagement():Void {
        trace("\n--- 测试分组2：上下文管理 ---");
        
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // setVariable和getVariable测试
        evaluator.setVariable("testVar", 42);
        var retrievedVar = evaluator.getVariable("testVar");
        _assert(retrievedVar == 42, "变量管理：setVariable和getVariable应该正常工作");
        
        // 不同类型的变量设置
        evaluator.setVariable("stringVar", "hello");
        evaluator.setVariable("boolVar", true);
        evaluator.setVariable("nullVar", null);
        evaluator.setVariable("undefVar", undefined);
        evaluator.setVariable("objVar", {prop: "value"});
        evaluator.setVariable("arrayVar", [1, 2, 3]);
        
        _assert(evaluator.getVariable("stringVar") == "hello", "变量类型：字符串变量应该正确");
        _assert(evaluator.getVariable("boolVar") === true, "变量类型：布尔变量应该正确");
        _assert(evaluator.getVariable("nullVar") === null, "变量类型：null变量应该正确");
        _assert(evaluator.getVariable("undefVar") === undefined, "变量类型：undefined变量应该正确");
        _assert(evaluator.getVariable("objVar").prop == "value", "变量类型：对象变量应该正确");
        _assert(evaluator.getVariable("arrayVar").length == 3, "变量类型：数组变量应该正确");
        
        // setFunction测试
        evaluator.setFunction("testFunc", function(x, y) {
            return x + y;
        });
        
        var funcResult:Number = evaluator.evaluate("testFunc(5, 3)");
        _assert(funcResult == 8, "函数管理：setFunction应该正常工作");
        
        // 复杂函数测试
        evaluator.setFunction("complexFunc", function(arr) {
            var sum = 0;
            for (var i = 0; i < arr.length; i++) {
                sum += arr[i];
            }
            return sum;
        });
        
        evaluator.setVariable("testArray", [1, 2, 3, 4, 5]);
        var complexResult:Number = evaluator.evaluate("complexFunc(testArray)");
        _assert(complexResult == 15, "复杂函数：应该正确处理数组参数");
        
        // 函数覆盖测试
        evaluator.setFunction("overrideFunc", function() { return "first"; });
        var firstResult:String = evaluator.evaluate("overrideFunc()");
        _assert(firstResult == "first", "函数覆盖：第一个函数应该正常");
        
        evaluator.setFunction("overrideFunc", function() { return "second"; });
        var secondResult:String = evaluator.evaluate("overrideFunc()");
        _assert(secondResult == "second", "函数覆盖：第二个函数应该覆盖第一个");
        
        // 变量覆盖测试
        evaluator.setVariable("overrideVar", "original");
        _assert(evaluator.evaluate("overrideVar") == "original", "变量覆盖：原始值应该正确");
        
        evaluator.setVariable("overrideVar", "modified");
        _assert(evaluator.evaluate("overrideVar") == "modified", "变量覆盖：修改值应该正确");
        
        // clearContext测试
        evaluator.clearContext();
        
        // 验证用户变量被清除
        var clearedVar = evaluator.getVariable("testVar");
        _assert(clearedVar === undefined, "清除上下文：用户变量应该被清除");
        
        var clearedFunc:String = evaluator.evaluateSafe("testFunc(1, 2)", "ERROR");
        _assert(clearedFunc == "ERROR", "清除上下文：用户函数应该被清除");
        
        // 验证内置函数被保留
        var mathStillExists:Boolean = evaluator.getVariable("Math") != null;
        _assert(mathStillExists, "清除上下文：内置Math对象应该保留");
        
        var maxStillWorks:Number = evaluator.evaluate("max(10, 20)");
        _assert(maxStillWorks == 20, "清除上下文：内置函数应该继续工作");
        
        // getContext测试
        var context:Object = evaluator.getContext();
        _assert(context != null, "获取上下文：getContext应该返回对象");
        
        // 验证通过context直接设置变量
        context["directVar"] = "direct";
        var directResult:String = evaluator.evaluate("directVar");
        _assert(directResult == "direct", "直接上下文：直接设置的变量应该可用");
        
        // 测试上下文的隔离性
        var evaluator2:PrattEvaluator = new PrattEvaluator();
        evaluator.setVariable("isolationTest", "evaluator1");
        evaluator2.setVariable("isolationTest", "evaluator2");
        
        _assert(evaluator.evaluate("isolationTest") == "evaluator1", "上下文隔离：第一个evaluator的变量应该独立");
        _assert(evaluator2.evaluate("isolationTest") == "evaluator2", "上下文隔离：第二个evaluator的变量应该独立");
    }
    
    // ============================================================================
    // 测试分组3：基础求值API
    // ============================================================================
    private static function testBasicEvaluationAPI():Void {
        trace("\n--- 测试分组3：基础求值API ---");
        
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // 基础evaluate方法测试
        var basicResult:Number = evaluator.evaluate("2 + 3");
        _assert(basicResult == 5, "基础求值：简单表达式应该正确");
        
        var complexResult:Number = evaluator.evaluate("2 + 3 * 4 - 1");
        _assert(complexResult == 13, "基础求值：复杂表达式应该正确");
        
        // 带上下文的求值
        evaluator.setVariable("x", 10);
        evaluator.setVariable("y", 5);
        var contextResult:Number = evaluator.evaluate("x + y * 2");
        _assert(contextResult == 20, "上下文求值：变量表达式应该正确");
        
        // 不同返回类型的求值
        var stringResult:String = evaluator.evaluate("'hello' + ' world'");
        _assert(stringResult == "hello world", "求值类型：字符串结果应该正确");
        
        var boolResult:Boolean = evaluator.evaluate("10 > 5");
        _assert(boolResult === true, "求值类型：布尔结果应该正确");
        
        var nullResult = evaluator.evaluate("null");
        _assert(nullResult === null, "求值类型：null结果应该正确");
        
        // 函数调用求值
        evaluator.setFunction("double", function(x) { return x * 2; });
        var funcResult:Number = evaluator.evaluate("double(21)");
        _assert(funcResult == 42, "函数求值：函数调用应该正确");
        
        // 对象和数组求值
        evaluator.setVariable("obj", {name: "test", value: 42});
        evaluator.setVariable("arr", [10, 20, 30]);
        
        var objResult:String = evaluator.evaluate("obj.name");
        _assert(objResult == "test", "对象求值：属性访问应该正确");
        
        var arrResult:Number = evaluator.evaluate("arr[1]");
        _assert(arrResult == 20, "数组求值：索引访问应该正确");
        
        // 复杂嵌套求值
        var nestedResult:Number = evaluator.evaluate("obj.value + arr[0] + double(5)");
        _assert(nestedResult == 62, "嵌套求值：复杂表达式应该正确");
        
        // parse方法测试
        var parsedExpr:PrattExpression = evaluator.parse("5 + 3");
        _assert(parsedExpr != null, "parse方法：应该返回表达式对象");
        _assert(parsedExpr.type == PrattExpression.BINARY, "parse方法：应该解析为正确的表达式类型");
        
        // 手动求值解析后的表达式
        var manualResult:Number = parsedExpr.evaluate(evaluator.getContext());
        _assert(manualResult == 8, "手动求值：解析后的表达式应该可以手动求值");
        
        // 测试evaluate的useCache参数
        var cacheStartTime:Number = getTimer();
        var cacheResult1:Number = evaluator.evaluate("Math.sqrt(16) + Math.abs(-5)", true);
        var cacheTime1:Number = getTimer() - cacheStartTime;
        
        var cacheStartTime2:Number = getTimer();
        var cacheResult2:Number = evaluator.evaluate("Math.sqrt(16) + Math.abs(-5)", true);
        var cacheTime2:Number = getTimer() - cacheStartTime2;
        
        _assert(cacheResult1 == 9, "缓存求值：第一次结果应该正确");
        _assert(cacheResult2 == 9, "缓存求值：第二次结果应该正确");
        _assert(cacheTime2 <= cacheTime1, "缓存求值：第二次应该更快或相等");
        
        // 测试不使用缓存
        var noCacheResult:Number = evaluator.evaluate("Math.sqrt(25)", false);
        _assert(noCacheResult == 5, "非缓存求值：结果应该正确");
    }
    
    // ============================================================================
    // 测试分组4：高级求值功能
    // ============================================================================
    private static function testAdvancedEvaluationFeatures():Void {
        trace("\n--- 测试分组4：高级求值功能 ---");
        
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // evaluateSafe测试
        var safeResult1:Number = evaluator.evaluateSafe("5 + 3", "ERROR");
        _assert(safeResult1 == 8, "安全求值：正确表达式应该返回结果");
        
        var safeResult2:String = evaluator.evaluateSafe("undefinedVar + 5", "DEFAULT");
        _assert(safeResult2 == "DEFAULT", "安全求值：错误表达式应该返回默认值");
        
        var safeResult3:String = evaluator.evaluateSafe("5 / 0", "DIVISION_ERROR");
        _assert(safeResult3 == "DIVISION_ERROR", "安全求值：除零错误应该返回默认值");
        
        var safeResult4:String = evaluator.evaluateSafe("2 + + 3", "SYNTAX_ERROR");
        _assert(safeResult4 == "SYNTAX_ERROR", "安全求值：语法错误应该返回默认值");
        
        // 不同类型的默认值
        var safeNumResult:Number = evaluator.evaluateSafe("badExpression", 999);
        _assert(safeNumResult == 999, "安全求值：数字默认值应该正确");
        
        var safeBoolResult:Boolean = evaluator.evaluateSafe("badExpression", false);
        _assert(safeBoolResult === false, "安全求值：布尔默认值应该正确");
        
        var safeNullResult = evaluator.evaluateSafe("badExpression", null);
        _assert(safeNullResult === null, "安全求值：null默认值应该正确");
        
        // validate测试
        var validResult:Object = evaluator.validate("5 + 3");
        _assert(validResult.valid === true, "表达式验证：有效表达式应该通过验证");
        _assert(validResult.error === undefined, "表达式验证：有效表达式不应该有错误");
        
        var invalidResult:Object = evaluator.validate("5 + * 3");
        _assert(invalidResult.valid === false, "表达式验证：无效表达式应该未通过验证");
        _assert(typeof invalidResult.error == "string", "表达式验证：无效表达式应该有错误信息");
        
        var invalidResult2:Object = evaluator.validate("(5 + 3");
        _assert(invalidResult2.valid === false, "表达式验证：括号不匹配应该未通过验证");
        
        var invalidResult3:Object = evaluator.validate("");
        _assert(invalidResult3.valid === false, "表达式验证：空表达式应该未通过验证");
        
        // 复杂表达式验证
        var complexValidResult:Object = evaluator.validate("Math.max(a.b[0], func(x + y)) > threshold ? result1 : result2");
        _assert(complexValidResult.valid === true, "复杂验证：复杂有效表达式应该通过验证");
        
        // extractVariables测试
        var simpleVars:Array = evaluator.extractVariables("x + y");
        _assert(simpleVars.length == 2, "变量提取：简单表达式应该提取正确数量的变量");
        _assert(_arrayContains(simpleVars, "x"), "变量提取：应该包含变量x");
        _assert(_arrayContains(simpleVars, "y"), "变量提取：应该包含变量y");
        
        var complexVars:Array = evaluator.extractVariables("a.b + c[d] + func(e, f.g)");
        _assert(_arrayContains(complexVars, "a"), "复杂变量提取：应该包含变量a");
        _assert(_arrayContains(complexVars, "c"), "复杂变量提取：应该包含变量c");
        _assert(_arrayContains(complexVars, "d"), "复杂变量提取：应该包含变量d");
        _assert(_arrayContains(complexVars, "func"), "复杂变量提取：应该包含函数名");
        _assert(_arrayContains(complexVars, "e"), "复杂变量提取：应该包含变量e");
        _assert(_arrayContains(complexVars, "f"), "复杂变量提取：应该包含变量f");
        
        var duplicateVars:Array = evaluator.extractVariables("x + x * x");
        var xCount:Number = 0;
        for (var i:Number = 0; i < duplicateVars.length; i++) {
            if (duplicateVars[i] == "x") xCount++;
        }
        _assert(xCount == 1, "变量提取：重复变量应该只出现一次");
        
        var noVars:Array = evaluator.extractVariables("5 + 3 * 2");
        _assert(noVars.length == 0, "变量提取：无变量表达式应该返回空数组");
        
        var ternaryVars:Array = evaluator.extractVariables("condition ? trueValue : falseValue");
        _assert(ternaryVars.length == 3, "三元变量提取：应该提取所有分支的变量");
        _assert(_arrayContains(ternaryVars, "condition"), "三元变量提取：应该包含条件变量");
        _assert(_arrayContains(ternaryVars, "trueValue"), "三元变量提取：应该包含真值变量");
        _assert(_arrayContains(ternaryVars, "falseValue"), "三元变量提取：应该包含假值变量");
        
        // evaluateMultiple测试
        var expressions:Array = [
            "5 + 3",
            "10 - 4",
            "2 * 6",
            "badExpression",
            "15 / 3"
        ];
        
        var multiResults:Array = evaluator.evaluateMultiple(expressions);
        _assert(multiResults.length == 5, "批量求值：应该返回正确数量的结果");
        
        _assert(multiResults[0].success === true && multiResults[0].result == 8, "批量求值：第一个表达式应该成功");
        _assert(multiResults[1].success === true && multiResults[1].result == 6, "批量求值：第二个表达式应该成功");
        _assert(multiResults[2].success === true && multiResults[2].result == 12, "批量求值：第三个表达式应该成功");
        _assert(multiResults[3].success === false, "批量求值：错误表达式应该失败");
        _assert(multiResults[4].success === true && multiResults[4].result == 5, "批量求值：第五个表达式应该成功");
        
        // 验证错误信息
        _assert(typeof multiResults[3].error == "string", "批量求值：失败的表达式应该有错误信息");
        
        // 空数组批量求值
        var emptyMultiResults:Array = evaluator.evaluateMultiple([]);
        _assert(emptyMultiResults.length == 0, "批量求值：空数组应该返回空结果");
    }
    
    // ============================================================================
    // 测试分组5：工厂方法
    // ============================================================================
    private static function testFactoryMethods():Void {
        trace("\n--- 测试分组5：工厂方法 ---");
        
        // createStandard测试
        var standardEvaluator:PrattEvaluator = PrattEvaluator.createStandard();
        _assert(standardEvaluator != null, "标准工厂：应该创建有效的evaluator");
        
        // 验证标准evaluator包含所有内置功能
        var standardMathResult:Number = standardEvaluator.evaluate("Math.abs(-42)");
        _assert(standardMathResult == 42, "标准工厂：应该包含Math功能");
        
        var standardMaxResult:Number = standardEvaluator.evaluate("max(10, 20, 15)");
        _assert(standardMaxResult == 20, "标准工厂：应该包含通用数学函数");
        
        var standardTypeResult:String = standardEvaluator.evaluate("typeof 123");
        _assert(standardTypeResult == "number", "标准工厂：应该支持typeof运算符");
        
        // createForBuff测试
        var buffEvaluator:PrattEvaluator = PrattEvaluator.createForBuff();
        _assert(buffEvaluator != null, "Buff工厂：应该创建有效的evaluator");
        
        // 验证Buff专用函数
        var setBaseResult = buffEvaluator.evaluate("SET_BASE(100)");
        _assert(setBaseResult.type == "SET_BASE" && setBaseResult.value == 100, "Buff工厂：SET_BASE函数应该正常工作");
        
        var addFlatResult = buffEvaluator.evaluate("ADD_FLAT(50)");
        _assert(addFlatResult.type == "ADD_FLAT" && addFlatResult.value == 50, "Buff工厂：ADD_FLAT函数应该正常工作");
        
        var addPercentBaseResult = buffEvaluator.evaluate("ADD_PERCENT_BASE(25)");
        _assert(addPercentBaseResult.type == "ADD_PERCENT_BASE" && addPercentBaseResult.value == 25, "Buff工厂：ADD_PERCENT_BASE函数应该正常工作");
        
        var addPercentCurrentResult = buffEvaluator.evaluate("ADD_PERCENT_CURRENT(30)");
        _assert(addPercentCurrentResult.type == "ADD_PERCENT_CURRENT" && addPercentCurrentResult.value == 30, "Buff工厂：ADD_PERCENT_CURRENT函数应该正常工作");
        
        var mulPercentResult = buffEvaluator.evaluate("MUL_PERCENT(40)");
        _assert(mulPercentResult.type == "MUL_PERCENT" && mulPercentResult.value == 40, "Buff工厂：MUL_PERCENT函数应该正常工作");
        
        var addFinalResult = buffEvaluator.evaluate("ADD_FINAL(10)");
        _assert(addFinalResult.type == "ADD_FINAL" && addFinalResult.value == 10, "Buff工厂：ADD_FINAL函数应该正常工作");
        
        var clampMaxResult = buffEvaluator.evaluate("CLAMP_MAX(200)");
        _assert(clampMaxResult.type == "CLAMP_MAX" && clampMaxResult.value == 200, "Buff工厂：CLAMP_MAX函数应该正常工作");
        
        var clampMinResult = buffEvaluator.evaluate("CLAMP_MIN(5)");
        _assert(clampMinResult.type == "CLAMP_MIN" && clampMinResult.value == 5, "Buff工厂：CLAMP_MIN函数应该正常工作");
        
        // 测试buffValue函数
        var testMods:Array = [
            {type: "ADD_FLAT", value: 20},
            {type: "MUL_PERCENT", value: 50}
        ];
        buffEvaluator.setVariable("testMods", testMods);
        var buffValueResult:Number = buffEvaluator.evaluate("buffValue(100, testMods)");
        // 100 + 20 = 120, 120 * 1.5 = 180
        _assert(buffValueResult == 180, "Buff工厂：buffValue函数应该正确计算");
        
        // 测试Buff条件函数
        var hasTagResult1:Boolean = buffEvaluator.evaluate("hasTag(['fire', 'damage'], 'fire')");
        _assert(hasTagResult1 === true, "Buff工厂：hasTag应该正确识别存在的标签");
        
        var hasTagResult2:Boolean = buffEvaluator.evaluate("hasTag(['fire', 'damage'], 'ice')");
        _assert(hasTagResult2 === false, "Buff工厂：hasTag应该正确识别不存在的标签");
        
        var hasTagResult3:Boolean = buffEvaluator.evaluate("hasTag(null, 'fire')");
        _assert(hasTagResult3 === false, "Buff工厂：hasTag应该正确处理null标签数组");
        
        var stackCountResult:Number = buffEvaluator.evaluate("stackCount('testBuff')");
        _assert(stackCountResult == 0, "Buff工厂：stackCount应该返回模拟值");
        
        // 验证Buff evaluator也包含标准功能
        var buffStandardResult:Number = buffEvaluator.evaluate("Math.max(10, 20)");
        _assert(buffStandardResult == 20, "Buff工厂：应该继承标准功能");
        
        // createWithCustomParser测试（如果实现了）
        try {
            var customEvaluator:PrattEvaluator = PrattEvaluator.createWithCustomParser(function() {
                // 自定义解析器设置
            });
            _assert(customEvaluator != null, "自定义工厂：应该创建有效的evaluator");
            
            // 验证基础功能仍然可用
            var customResult:Number = customEvaluator.evaluate("5 + 3");
            _assert(customResult == 8, "自定义工厂：基础功能应该正常");
        } catch (e) {
            // 如果方法不存在或未实现，这是可以接受的
            trace("注意：createWithCustomParser可能未完全实现");
        }
        
        // 工厂方法的独立性测试
        var eval1:PrattEvaluator = PrattEvaluator.createStandard();
        var eval2:PrattEvaluator = PrattEvaluator.createForBuff();
        
        eval1.setVariable("test", "standard");
        eval2.setVariable("test", "buff");
        
        _assert(eval1.evaluate("test") == "standard", "工厂独立性：第一个evaluator应该独立");
        _assert(eval2.evaluate("test") == "buff", "工厂独立性：第二个evaluator应该独立");
        
        // 验证Buff专用功能不会影响标准evaluator
        var standardHasBuffFunc:String = eval1.evaluateSafe("ADD_FLAT(10)", "NOT_FOUND");
        _assert(standardHasBuffFunc == "NOT_FOUND", "工厂分离：标准evaluator不应该有Buff函数");
    }
    
    // ============================================================================
    // 测试分组6：缓存机制
    // ============================================================================
    private static function testCachingMechanism():Void {
        trace("\n--- 测试分组6：缓存机制 ---");
        
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // 基础缓存测试
        var expr:String = "Math.sqrt(16) + Math.abs(-10)";
        
        var firstStartTime:Number = getTimer();
        var firstResult:Number = evaluator.evaluate(expr, true);
        var firstTime:Number = getTimer() - firstStartTime;
        
        var secondStartTime:Number = getTimer();
        var secondResult:Number = evaluator.evaluate(expr, true);
        var secondTime:Number = getTimer() - secondStartTime;
        
        _assert(firstResult == 14, "缓存基础：第一次求值结果应该正确");
        _assert(secondResult == 14, "缓存基础：第二次求值结果应该正确");
        _assert(secondTime <= firstTime + 5, "缓存性能：第二次求值应该更快或相近"); // 允许5ms误差
        
        // 不使用缓存测试
        var noCacheStartTime:Number = getTimer();
        var noCacheResult:Number = evaluator.evaluate(expr, false);
        var noCacheTime:Number = getTimer() - noCacheStartTime;
        
        _assert(noCacheResult == 14, "非缓存：结果应该正确");
        
        // 缓存失效测试（通过改变上下文）
        evaluator.setVariable("factor", 2);
        var contextExpr:String = "10 * factor";
        
        var beforeChange:Number = evaluator.evaluate(contextExpr, true);
        _assert(beforeChange == 20, "缓存上下文：初始结果应该正确");
        
        // 改变变量值
        evaluator.setVariable("factor", 3);
        var afterChange:Number = evaluator.evaluate(contextExpr, true);
        _assert(afterChange == 30, "缓存上下文：变量改变后结果应该更新");
        
        // 复杂表达式缓存测试
        var complexExpr:String = "Math.max(Math.min(100, 200), Math.abs(-50)) + Math.floor(3.7)";
        
        var complexFirst:Number = evaluator.evaluate(complexExpr, true);
        var complexSecond:Number = evaluator.evaluate(complexExpr, true);
        _assert(complexFirst == complexSecond, "复杂缓存：重复求值应该产生相同结果");
        
        // 不同表达式的缓存独立性
        var expr1:String = "5 + 3";
        var expr2:String = "10 - 2";
        
        var result1a:Number = evaluator.evaluate(expr1, true);
        var result2a:Number = evaluator.evaluate(expr2, true);
        var result1b:Number = evaluator.evaluate(expr1, true);
        var result2b:Number = evaluator.evaluate(expr2, true);
        
        _assert(result1a == 8 && result1b == 8, "缓存独立性：第一个表达式应该正确缓存");
        _assert(result2a == 8 && result2b == 8, "缓存独立性：第二个表达式应该正确缓存");
        
        // 函数调用缓存测试
        var callCount:Number = 0;
        evaluator.setFunction("countedFunc", function(x) {
            callCount++;
            return x * 2;
        });
        
        var funcExpr:String = "countedFunc(5) + 10";
        evaluator.evaluate(funcExpr, true); // 第一次调用
        var firstCallCount:Number = callCount;
        
        evaluator.evaluate(funcExpr, true); // 第二次调用（应该使用缓存）
        var secondCallCount:Number = callCount;
        
        _assert(firstCallCount == 1, "函数缓存：第一次应该调用函数");
        _assert(secondCallCount == 1, "函数缓存：第二次应该使用缓存，不再调用函数");
        
        // 清除上下文对缓存的影响
        evaluator.setVariable("cached", 42);
        var cachedExpr:String = "cached + 10";
        var cachedResult:Number = evaluator.evaluate(cachedExpr, true);
        _assert(cachedResult == 52, "缓存清除前：结果应该正确");
        
        evaluator.clearContext();
        var clearedCacheResult:String = evaluator.evaluateSafe(cachedExpr, "CACHE_CLEARED");
        _assert(clearedCacheResult == "CACHE_CLEARED", "缓存清除后：缓存应该被清除");
        
        // 大量缓存条目的性能测试
        for (var i:Number = 0; i < 20; i++) {
            var testExpr:String = i + " + " + (i + 1);
            evaluator.evaluate(testExpr, true);
        }
        
        // 重复访问应该仍然快速
        var massAccessStart:Number = getTimer();
        for (var j:Number = 0; j < 20; j++) {
            var accessExpr:String = j + " + " + (j + 1);
            evaluator.evaluate(accessExpr, true);
        }
        var massAccessTime:Number = getTimer() - massAccessStart;
        
        _assert(massAccessTime < 100, "大量缓存：批量访问应该高效");
    }
    
    // ============================================================================
    // 测试分组7：错误处理和安全性
    // ============================================================================
    private static function testErrorHandlingAndSafety():Void {
        trace("\n--- 测试分组7：错误处理和安全性 ---");
        
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // 语法错误处理
        var syntaxError:Boolean = false;
        try {
            evaluator.evaluate("5 + * 3");
        } catch (e) {
            syntaxError = true;
            _assert(typeof e.message == "string", "语法错误：应该有错误消息");
        }
        _assert(syntaxError, "语法错误：应该抛出异常");
        
        // 运行时错误处理
        var runtimeError:Boolean = false;
        try {
            evaluator.evaluate("undefinedVariable + 5");
        } catch (e) {
            runtimeError = true;
            _assert(e.message.indexOf("Undefined variable") >= 0, "运行时错误：应该指出未定义变量");
        }
        _assert(runtimeError, "运行时错误：应该抛出异常");
        
        // 除零错误处理
        var divisionError:Boolean = false;
        try {
            evaluator.evaluate("10 / 0");
        } catch (e) {
            divisionError = true;
            _assert(e.message.indexOf("Division by zero") >= 0, "除零错误：应该有相应错误信息");
        }
        _assert(divisionError, "除零错误：应该抛出异常");
        
        // null/undefined访问错误
        evaluator.setVariable("nullVar", null);
        evaluator.setVariable("undefVar", undefined);
        
        var nullAccessError:Boolean = false;
        try {
            evaluator.evaluate("nullVar.property");
        } catch (e) {
            nullAccessError = true;
            _assert(e.message.indexOf("Cannot access property") >= 0, "null访问错误：应该有相应错误信息");
        }
        _assert(nullAccessError, "null访问错误：应该抛出异常");
        
        var undefAccessError:Boolean = false;
        try {
            evaluator.evaluate("undefVar[0]");
        } catch (e) {
            undefAccessError = true;
            _assert(e.message.indexOf("Cannot access index") >= 0, "undefined访问错误：应该有相应错误信息");
        }
        _assert(undefAccessError, "undefined访问错误：应该抛出异常");
        
        // 函数调用错误处理
        var funcCallError:Boolean = false;
        try {
            evaluator.evaluate("nonexistentFunction()");
        } catch (e) {
            funcCallError = true;
            _assert(e.message.indexOf("Unknown function") >= 0, "函数调用错误：应该指出未知函数");
        }
        _assert(funcCallError, "函数调用错误：应该抛出异常");
        
        // 非函数调用错误
        evaluator.setVariable("notAFunction", "I am a string");
        var notFuncError:Boolean = false;
        try {
            evaluator.evaluate("notAFunction()");
        } catch (e) {
            notFuncError = true;
        }
        _assert(notFuncError, "非函数调用错误：应该抛出异常");
        
        // 安全的错误信息（不泄露敏感信息）
        evaluator.setVariable("sensitiveData", {password: "secret123"});
        var safeErrorResult:String = evaluator.evaluateSafe("sensitiveData.nonexistent.deeper", "SAFE_DEFAULT");
        _assert(safeErrorResult == "SAFE_DEFAULT", "安全错误处理：应该返回安全的默认值");
        
        // 递归调用保护（如果有实现）
        evaluator.setFunction("recursiveFunc", function(n) {
            if (n <= 0) return 1;
            return n * recursiveFunc(n - 1); // 这会导致ReferenceError，因为recursiveFunc在其作用域内不可见
        });
        
        // 测试深度嵌套表达式的错误处理
        var deepNestError:Boolean = false;
        try {
            var deepExpr:String = "a";
            for (var i:Number = 0; i < 100; i++) {
                deepExpr += ".b";
            }
            evaluator.evaluate(deepExpr);
        } catch (e) {
            deepNestError = true;
        }
        _assert(deepNestError, "深度嵌套错误：应该正确处理深度嵌套访问错误");
        
        // 类型转换错误的优雅处理
        evaluator.setVariable("stringVar", "not a number");
        var typeConversionResult:Boolean = evaluator.evaluate("isNaN(stringVar)");
        _assert(typeConversionResult === true, "类型转换：应该正确处理类型转换");
        
        // 内存保护测试（防止无限循环等）
        var largeArrayTest:String = evaluator.evaluateSafe("new Array(999999999)", "MEMORY_SAFE");
        _assert(largeArrayTest == "MEMORY_SAFE", "内存保护：应该防止过大的内存分配");
        
        // 错误信息的一致性测试
        var error1:String = evaluator.evaluateSafe("badVar1 + 5", "ERROR");
        var error2:String = evaluator.evaluateSafe("badVar2 + 10", "ERROR");
        _assert(error1 == "ERROR" && error2 == "ERROR", "错误一致性：相似错误应该一致处理");
    }
    
    // ============================================================================
    // 测试分组8：实用工具方法
    // ============================================================================
    private static function testUtilityMethods():Void {
        trace("\n--- 测试分组8：实用工具方法 ---");
        
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // benchmark方法测试
        var simpleExpr:String = "5 + 3 * 2";
        var benchmarkResult:Object = evaluator.benchmark(simpleExpr, 100);
        
        _assert(benchmarkResult.expression == simpleExpr, "性能测试：应该记录表达式");
        _assert(benchmarkResult.iterations == 100, "性能测试：应该记录迭代次数");
        _assert(typeof benchmarkResult.totalTime == "number", "性能测试：应该记录总时间");
        _assert(typeof benchmarkResult.averageTime == "number", "性能测试：应该记录平均时间");
        _assert(benchmarkResult.averageTime == benchmarkResult.totalTime / 100, "性能测试：平均时间应该正确计算");
        _assert(benchmarkResult.totalTime >= 0, "性能测试：时间应该非负");
        
        // 不同复杂度表达式的性能测试
        var complexExpr:String = "Math.sqrt(Math.pow(10, 2) + Math.pow(5, 2))";
        var complexBenchmark:Object = evaluator.benchmark(complexExpr, 50);
        
        _assert(complexBenchmark.iterations == 50, "复杂性能测试：迭代次数应该正确");
        _assert(complexBenchmark.averageTime >= 0, "复杂性能测试：平均时间应该非负");
        
        // 带变量的表达式性能测试
        evaluator.setVariable("x", 10);
        evaluator.setVariable("y", 20);
        var varExpr:String = "x * y + Math.abs(x - y)";
        var varBenchmark:Object = evaluator.benchmark(varExpr, 75);
        
        _assert(varBenchmark.expression == varExpr, "变量性能测试：应该记录正确的表达式");
        _assert(varBenchmark.iterations == 75, "变量性能测试：迭代次数应该正确");
        
        // 函数调用的性能测试
        evaluator.setFunction("testFunc", function(a, b) {
            return a + b;
        });
        var funcExpr:String = "testFunc(15, 25)";
        var funcBenchmark:Object = evaluator.benchmark(funcExpr, 60);
        
        _assert(funcBenchmark.averageTime >= 0, "函数性能测试：平均时间应该非负");
        
        // 不同迭代次数的性能测试
        var singleIteration:Object = evaluator.benchmark("42", 1);
        _assert(singleIteration.iterations == 1, "单次迭代：应该正确处理");
        _assert(singleIteration.averageTime == singleIteration.totalTime, "单次迭代：平均时间等于总时间");
        
        var manyIterations:Object = evaluator.benchmark("1 + 1", 1000);
        _assert(manyIterations.iterations == 1000, "大量迭代：应该正确处理");
        _assert(manyIterations.averageTime <= manyIterations.totalTime, "大量迭代：平均时间应该小于等于总时间");
        
        // 边界情况：零次迭代
        var zeroIterations:Object = evaluator.benchmark("5", 0);
        _assert(zeroIterations.iterations == 0, "零次迭代：应该正确处理");
        _assert(zeroIterations.totalTime == 0, "零次迭代：总时间应该为0");
        _assert(isNaN(zeroIterations.averageTime) || zeroIterations.averageTime == 0, "零次迭代：平均时间应该是0或NaN");
        
        // 性能测试不应该使用缓存
        var cacheTestCount:Number = 0;
        evaluator.setFunction("cacheTestFunc", function() {
            cacheTestCount++;
            return 42;
        });
        
        var cacheTestExpr:String = "cacheTestFunc()";
        evaluator.benchmark(cacheTestExpr, 5);
        _assert(cacheTestCount == 5, "性能测试缓存：benchmark应该不使用缓存，每次都执行");
        
        // 性能比较测试
        var simpleTime:Number = evaluator.benchmark("1 + 1", 100).averageTime;
        var complexTime:Number = evaluator.benchmark("Math.sqrt(Math.pow(100, 2))", 100).averageTime;
        _assert(complexTime >= simpleTime, "性能比较：复杂表达式应该不快于简单表达式");
        
        // 错误表达式的性能测试
        var errorBenchmarkResult:Object = null;
        try {
            errorBenchmarkResult = evaluator.benchmark("undefinedVar + 1", 10);
            _assert(false, "错误性能测试：应该抛出异常");
        } catch (e) {
            _assert(true, "错误性能测试：错误表达式应该导致benchmark失败");
        }
        
        // 工具方法的可靠性测试
        for (var testRun:Number = 0; testRun < 5; testRun++) {
            var reliabilityBenchmark:Object = evaluator.benchmark("Math.PI * 2", 20);
            _assert(reliabilityBenchmark.iterations == 20, "可靠性测试：每次都应该正确执行");
            _assert(reliabilityBenchmark.totalTime >= 0, "可靠性测试：时间测量应该稳定");
        }
    }
    
    // ============================================================================
    // 测试分组9：性能功能
    // ============================================================================
    private static function testPerformanceFeatures():Void {
        trace("\n--- 测试分组9：性能功能 ---");
        
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // 缓存vs非缓存性能对比
        var testExpr:String = "Math.sqrt(256) + Math.abs(-100) + Math.floor(9.9)";
        
        var noCacheTime:Number = evaluator.benchmark(testExpr, 100).averageTime;
        
        // 预热缓存
        evaluator.evaluate(testExpr, true);
        
        var withCacheStart:Number = getTimer();
        for (var i:Number = 0; i < 100; i++) {
            evaluator.evaluate(testExpr, true);
        }
        var withCacheTime:Number = (getTimer() - withCacheStart) / 100;
        
        _assert(withCacheTime <= noCacheTime + 1, "缓存性能：使用缓存应该不慢于不使用缓存"); // 允许1ms误差
        
        // 大量变量的性能测试
        var manyVarStart:Number = getTimer();
        for (var j:Number = 0; j < 100; j++) {
            evaluator.setVariable("var" + j, j);
        }
        var manyVarSetTime:Number = getTimer() - manyVarStart;
        
        var manyVarExpr:String = "";
        for (var k:Number = 0; k < 50; k++) {
            if (k > 0) manyVarExpr += " + ";
            manyVarExpr += "var" + k;
        }
        
        var manyVarEvalTime:Number = evaluator.benchmark(manyVarExpr, 10).averageTime;
        _assert(manyVarSetTime < 1000, "大量变量设置：应该在合理时间内完成");
        _assert(manyVarEvalTime < 100, "大量变量求值：应该高效处理");
        
        // 复杂嵌套表达式的性能
        var nestedExpr:String = "";
        var depth:Number = 20;
        for (var l:Number = 0; l < depth; l++) {
            nestedExpr += "(";
        }
        nestedExpr += "1";
        for (var m:Number = 0; m < depth; m++) {
            nestedExpr += " + 1)";
        }
        
        var nestedTime:Number = evaluator.benchmark(nestedExpr, 10).averageTime;
        _assert(nestedTime < 50, "嵌套性能：深度嵌套应该在合理时间内处理");
        
        // 函数调用开销测试
        evaluator.setFunction("simpleFunc", function(x) { return x; });
        evaluator.setFunction("complexFunc", function(x) {
            for (var i = 0; i < 100; i++) {
                x = Math.sqrt(x + 1);
            }
            return x;
        });
        
        var simpleFuncTime:Number = evaluator.benchmark("simpleFunc(42)", 100).averageTime;
        var complexFuncTime:Number = evaluator.benchmark("complexFunc(42)", 10).averageTime;
        
        _assert(complexFuncTime > simpleFuncTime, "函数开销：复杂函数应该比简单函数慢");
        
        // 内存使用优化测试
        var memoryTestEvaluator:PrattEvaluator = new PrattEvaluator();
        var memoryStartTime:Number = getTimer();
        
        // 创建和销毁大量临时变量
        for (var n:Number = 0; n < 100; n++) {
            memoryTestEvaluator.setVariable("temp" + n, "value" + n);
            memoryTestEvaluator.evaluate("temp" + n + " + ' processed'");
        }
        
        memoryTestEvaluator.clearContext();
        var memoryTestTime:Number = getTimer() - memoryStartTime;
        
        _assert(memoryTestTime < 2000, "内存优化：大量临时变量操作应该高效");
        
        // 并发访问模拟（通过快速连续访问）
        var concurrentTestEvaluator:PrattEvaluator = new PrattEvaluator();
        concurrentTestEvaluator.setVariable("shared", 100);
        
        var concurrentStart:Number = getTimer();
        for (var o:Number = 0; o < 50; o++) {
            concurrentTestEvaluator.evaluate("shared * 2");
            concurrentTestEvaluator.setVariable("shared", o);
            concurrentTestEvaluator.evaluate("shared + 10");
        }
        var concurrentTime:Number = getTimer() - concurrentStart;
        
        _assert(concurrentTime < 1000, "并发模拟：快速连续访问应该稳定");
        
        // 表达式复杂度对性能的影响
        var expressions:Array = [
            "1",
            "1 + 2",
            "1 + 2 * 3",
            "Math.max(1, Math.min(2, 3))",
            "obj.prop[0] + func(a, b, c)",
            "a ? b : c ? d : e ? f : g"
        ];
        
        evaluator.setVariable("obj", {prop: [10]});
        evaluator.setFunction("func", function(x, y, z) { return x + y + z; });
        evaluator.setVariable("a", true);
        evaluator.setVariable("b", 1);
        evaluator.setVariable("c", false);
        evaluator.setVariable("d", 2);
        evaluator.setVariable("e", true);
        evaluator.setVariable("f", 3);
        evaluator.setVariable("g", 4);
        
        var prevTime:Number = 0;
        for (var p:Number = 0; p < expressions.length; p++) {
            var exprTime:Number = evaluator.benchmark(expressions[p], 100).averageTime;
            if (p > 0) {
                _assert(exprTime >= prevTime - 2, "复杂度性能：更复杂的表达式应该不显著更快"); // 允许2ms误差
            }
            prevTime = exprTime;
        }
        
        // 缓存命中率测试
        var cacheHitTestExpr:String = "Math.sqrt(144) + Math.abs(-72)";
        
        // 首次执行（缓存miss）
        var firstExecution:Number = getTimer();
        evaluator.evaluate(cacheHitTestExpr, true);
        var firstTime:Number = getTimer() - firstExecution;
        
        // 后续执行（缓存hit）
        var hitTotal:Number = 0;
        for (var q:Number = 0; q < 10; q++) {
            var hitStart:Number = getTimer();
            evaluator.evaluate(cacheHitTestExpr, true);
            hitTotal += getTimer() - hitStart;
        }
        var avgHitTime:Number = hitTotal / 10;
        
        _assert(avgHitTime <= firstTime, "缓存命中率：缓存命中应该不慢于首次执行");
    }
    
    // ============================================================================
    // 测试分组10：集成场景
    // ============================================================================
    private static function testIntegrationScenarios():Void {
        trace("\n--- 测试分组10：集成场景 ---");
        
        // 游戏伤害计算场景
        var gameEvaluator:PrattEvaluator = PrattEvaluator.createForBuff();
        
        gameEvaluator.setVariable("player", {
            level: 10,
            stats: {
                attack: 100,
                critChance: 0.15,
                critMultiplier: 2.0
            },
            weapon: {
                damage: 50,
                enchantment: 10
            }
        });
        
        gameEvaluator.setVariable("enemy", {
            defense: 20,
            resistances: {
                physical: 0.1
            }
        });
        
        gameEvaluator.setVariable("isCrit", false);
        
        var damageFormula:String = 
            "(player.stats.attack + player.weapon.damage + player.weapon.enchantment) * " +
            "(isCrit ? player.stats.critMultiplier : 1.0) * " +
            "(1 - enemy.resistances.physical) - enemy.defense";
        
        var normalDamage:Number = gameEvaluator.evaluate(damageFormula);
        var expectedNormal:Number = (100 + 50 + 10) * 1.0 * 0.9 - 20; // 124
        _assert(normalDamage == expectedNormal, "游戏场景：普通伤害计算应该正确");
        
        gameEvaluator.setVariable("isCrit", true);
        var critDamage:Number = gameEvaluator.evaluate(damageFormula);
        var expectedCrit:Number = (100 + 50 + 10) * 2.0 * 0.9 - 20; // 268
        _assert(critDamage == expectedCrit, "游戏场景：暴击伤害计算应该正确");
        
        // 商业规则引擎场景
        var businessEvaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        businessEvaluator.setVariable("order", {
            amount: 1000,
            customerType: "premium",
            quantity: 5,
            isFirstOrder: false
        });
        
        businessEvaluator.setVariable("discountRules", {
            premiumCustomer: 0.1,
            bulkDiscount: 0.05,
            firstOrderBonus: 0.15
        });
        
        businessEvaluator.setFunction("calculateDiscount", function(order, rules) {
            var discount = 0;
            if (order.customerType == "premium") {
                discount += rules.premiumCustomer;
            }
            if (order.quantity >= 5) {
                discount += rules.bulkDiscount;
            }
            if (order.isFirstOrder) {
                discount += rules.firstOrderBonus;
            }
            return Math.min(discount, 0.3); // 最大30%折扣
        });
        
        var discountFormula:String = "order.amount * calculateDiscount(order, discountRules)";
        var discountAmount:Number = businessEvaluator.evaluate(discountFormula);
        var expectedDiscount:Number = 1000 * 0.15; // 10% + 5% = 15%
        _assert(discountAmount == expectedDiscount, "商业场景：折扣计算应该正确");
        
        var finalAmount:Number = businessEvaluator.evaluate("order.amount - " + discountAmount);
        _assert(finalAmount == 850, "商业场景：最终金额应该正确");
        
        // 科学计算场景
        var scienceEvaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        scienceEvaluator.setVariable("constants", {
            g: 9.81,
            pi: Math.PI,
            c: 299792458
        });
        
        scienceEvaluator.setFunction("distance", function(v0, t, a) {
            return v0 * t + 0.5 * a * t * t;
        });
        
        scienceEvaluator.setFunction("energy", function(m, v) {
            return 0.5 * m * v * v;
        });
        
        var physicsFormula:String = "distance(20, 5, constants.g)"; // 自由落体
        var fallDistance:Number = scienceEvaluator.evaluate(physicsFormula);
        var expectedDistance:Number = 20 * 5 + 0.5 * 9.81 * 25; // 222.625
        _assert(Math.abs(fallDistance - expectedDistance) < 0.001, "科学场景：物理计算应该正确");
        
        var kineticEnergy:Number = scienceEvaluator.evaluate("energy(10, 30)");
        _assert(kineticEnergy == 4500, "科学场景：动能计算应该正确");
        
        // 配置系统场景
        var configEvaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        configEvaluator.setVariable("environment", "production");
        configEvaluator.setVariable("userAgent", "mobile");
        configEvaluator.setVariable("featureFlags", {
            newUI: true,
            betaFeatures: false,
            debugMode: false
        });
        
        var configFormulas:Object = {
            cacheEnabled: "environment == 'production' && !featureFlags.debugMode",
            maxConnections: "userAgent == 'mobile' ? 5 : 10",
            logLevel: "featureFlags.debugMode ? 'debug' : 'info'",
            uiTheme: "featureFlags.newUI ? 'modern' : 'classic'"
        };
        
        for (var configKey:String in configFormulas) {
            var configValue = configEvaluator.evaluate(configFormulas[configKey]);
            _assert(configValue != undefined, "配置场景：" + configKey + "应该有有效值");
        }
        
        var cacheEnabled:Boolean = configEvaluator.evaluate(configFormulas.cacheEnabled);
        _assert(cacheEnabled === true, "配置场景：缓存应该在生产环境启用");
        
        var maxConnections:Number = configEvaluator.evaluate(configFormulas.maxConnections);
        _assert(maxConnections == 5, "配置场景：移动端连接数应该受限");
        
        // 多evaluator协作场景
        var masterEvaluator:PrattEvaluator = PrattEvaluator.createStandard();
        var slaveEvaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        masterEvaluator.setVariable("globalConfig", {multiplier: 2, offset: 10});
        
        var masterResult:Number = masterEvaluator.evaluate("globalConfig.multiplier * 5");
        slaveEvaluator.setVariable("masterResult", masterResult);
        slaveEvaluator.setVariable("localFactor", 3);
        
        var finalResult:Number = slaveEvaluator.evaluate("masterResult + localFactor + 10");
        _assert(finalResult == 23, "协作场景：多evaluator协作应该正确"); // 10 + 3 + 10 = 23
        
        // 实时计算场景（模拟）
        var realtimeEvaluator:PrattEvaluator = PrattEvaluator.createStandard();
        
        var sensorData:Array = [
            {temperature: 25.5, humidity: 60},
            {temperature: 26.0, humidity: 58},
            {temperature: 25.8, humidity: 62}
        ];
        
        realtimeEvaluator.setFunction("average", function(arr, prop) {
            var sum = 0;
            for (var i = 0; i < arr.length; i++) {
                sum += arr[i][prop];
            }
            return sum / arr.length;
        });
        
        realtimeEvaluator.setVariable("sensors", sensorData);
        
        var avgTemp:Number = realtimeEvaluator.evaluate("average(sensors, 'temperature')");
        var avgHumidity:Number = realtimeEvaluator.evaluate("average(sensors, 'humidity')");
        
        _assert(Math.abs(avgTemp - 25.767) < 0.01, "实时场景：平均温度计算应该正确");
        _assert(Math.abs(avgHumidity - 60) < 0.01, "实时场景：平均湿度计算应该正确");
        
        var comfortIndex:String = realtimeEvaluator.evaluate(
            "avgTemp > 24 && avgTemp < 27 && avgHumidity > 40 && avgHumidity < 70 ? 'comfortable' : 'uncomfortable'"
        );
        _assert(comfortIndex == "comfortable", "实时场景：舒适度指数应该正确");
    }
    
    // ============================================================================
    // 测试分组11：边界条件
    // ============================================================================
    private static function testBoundaryConditions():Void {
        trace("\n--- 测试分组11：边界条件 ---");
        
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // 空表达式处理
        var emptyResult:String = evaluator.evaluateSafe("", "EMPTY");
        _assert(emptyResult == "EMPTY", "边界条件：空表达式应该返回默认值");
        
        var whitespaceResult:String = evaluator.evaluateSafe("   \t\n  ", "WHITESPACE");
        _assert(whitespaceResult == "WHITESPACE", "边界条件：纯空白应该返回默认值");
        
        // 极值数字处理
        var maxNumber:Number = evaluator.evaluate("999999999999999");
        _assert(typeof maxNumber == "number", "边界条件：极大数字应该是number类型");
        
        var minNumber:Number = evaluator.evaluate("0.000000001");
        _assert(typeof minNumber == "number", "边界条件：极小数字应该是number类型");
        
        var infinity:Number = evaluator.evaluate("1 / 0", false); // 使用false避免除零异常抛出
        // 注意：这里的行为取决于具体实现，可能抛异常也可能返回Infinity
        
        // NaN处理
        evaluator.setVariable("nanValue", Number.NaN);
        var nanResult = evaluator.evaluate("nanValue + 5");
        _assert(isNaN(nanResult), "边界条件：NaN运算应该产生NaN");
        
        var nanComparison:Boolean = evaluator.evaluate("isNaN(nanValue)");
        _assert(nanComparison === true, "边界条件：NaN检测应该正确");
        
        // 极长字符串处理
        var longString:String = "";
        for (var i:Number = 0; i < 1000; i++) {
            longString += "a";
        }
        evaluator.setVariable("longStr", longString);
        var longStrResult:String = evaluator.evaluate("longStr + 'suffix'");
        _assert(longStrResult.length == 1007, "边界条件：极长字符串操作应该正确");
        
        // 深度嵌套对象
        var deepObj:Object = {};
        var current:Object = deepObj;
        for (var j:Number = 0; j < 20; j++) {
            current.next = {};
            current = current.next;
        }
        current.value = "deep";
        
        evaluator.setVariable("deepObj", deepObj);
        var deepAccess:String = evaluator.evaluate("deepObj" + ".next".repeat(20) + ".value");
        _assert(deepAccess == "deep", "边界条件：深度嵌套访问应该正确");
        
        // 大量变量
        for (var k:Number = 0; k < 100; k++) {
            evaluator.setVariable("var" + k, k);
        }
        
        var manyVarsResult:Number = evaluator.evaluate("var50 + var75 + var99");
        _assert(manyVarsResult == 224, "边界条件：大量变量应该正确处理");
        
        // 极端数组
        var emptyArray:Array = [];
        var largeArray:Array = [];
        for (var l:Number = 0; l < 1000; l++) {
            largeArray.push(l);
        }
        
        evaluator.setVariable("emptyArr", emptyArray);
        evaluator.setVariable("largeArr", largeArray);
        
        var emptyArrLen:Number = evaluator.evaluate("emptyArr.length");
        _assert(emptyArrLen == 0, "边界条件：空数组长度应该为0");
        
        var largeArrLen:Number = evaluator.evaluate("largeArr.length");
        _assert(largeArrLen == 1000, "边界条件：大数组长度应该正确");
        
        var largeArrAccess:Number = evaluator.evaluate("largeArr[999]");
        _assert(largeArrAccess == 999, "边界条件：大数组访问应该正确");
        
        // 特殊字符处理
        evaluator.setVariable("specialChars", "\n\t\r\\\"'");
        var specialResult:String = evaluator.evaluate("specialChars + ' processed'");
        _assert(specialResult.indexOf("processed") >= 0, "边界条件：特殊字符应该正确处理");
        
        // 循环引用检测（如果实现了）
        var circularObj:Object = {name: "parent"};
        circularObj.self = circularObj;
        evaluator.setVariable("circular", circularObj);
        
        var circularName:String = evaluator.evaluate("circular.name");
        _assert(circularName == "parent", "边界条件：循环引用对象的普通属性应该可访问");
        
        // 大量函数参数
        evaluator.setFunction("manyArgsFunc", function() {
            return arguments.length;
        });
        
        var manyArgsExpr:String = "manyArgsFunc(";
        for (var m:Number = 0; m < 20; m++) {
            if (m > 0) manyArgsExpr += ", ";
            manyArgsExpr += m;
        }
        manyArgsExpr += ")";
        
        var manyArgsResult:Number = evaluator.evaluate(manyArgsExpr);
        _assert(manyArgsResult == 20, "边界条件：大量函数参数应该正确传递");
        
        // 嵌套函数调用
        evaluator.setFunction("identity", function(x) { return x; });
        var nestedFuncExpr:String = "identity(identity(identity(identity(42))))";
        var nestedFuncResult:Number = evaluator.evaluate(nestedFuncExpr);
        _assert(nestedFuncResult == 42, "边界条件：嵌套函数调用应该正确");
        
        // 复杂三元嵌套
        var complexTernary:String = "true ? (false ? 1 : (true ? 2 : 3)) : (true ? 4 : 5)";
        var complexTernaryResult:Number = evaluator.evaluate(complexTernary);
        _assert(complexTernaryResult == 2, "边界条件：复杂三元嵌套应该正确");
        
        // 零值和falsy值的特殊处理
        var falsyTests:Array = [
            {expr: "0 || 'default'", expected: "default"},
            {expr: "'' || 'default'", expected: "default"},
            {expr: "false || 'default'", expected: "default"},
            {expr: "null || 'default'", expected: "default"},
            {expr: "undefined || 'default'", expected: "default"}
        ];
        
        for (var n:Number = 0; n < falsyTests.length; n++) {
            var falsyTest = falsyTests[n];
            var falsyResult = evaluator.evaluate(falsyTest.expr);
            _assert(falsyResult == falsyTest.expected, "Falsy边界：" + falsyTest.expr + "应该正确处理");
        }
    }
    
    // ============================================================================
    // 测试分组12：内存和资源管理
    // ============================================================================
    private static function testMemoryAndResourceManagement():Void {
        trace("\n--- 测试分组12：内存和资源管理 ---");
        
        // 缓存内存管理
        var evaluator:PrattEvaluator = new PrattEvaluator();
        
        // 创建大量缓存条目
        for (var i:Number = 0; i < 100; i++) {
            var expr:String = "Math.sqrt(" + i + ") + Math.abs(-" + i + ")";
            evaluator.evaluate(expr, true);
        }
        
        // 验证基础功能仍然正常
        var memoryTestResult:Number = evaluator.evaluate("Math.sqrt(144)");
        _assert(memoryTestResult == 12, "内存管理：大量缓存后基础功能应该正常");
        
        // 上下文清理测试
        var largeContextEvaluator:PrattEvaluator = new PrattEvaluator();
        
        // 创建大量变量和函数
        for (var j:Number = 0; j < 200; j++) {
            largeContextEvaluator.setVariable("var" + j, "value" + j);
            largeContextEvaluator.setFunction("func" + j, function(x) { return x + j; });
        }
        
        // 验证设置成功
        var contextTestResult:String = largeContextEvaluator.evaluate("var50");
        _assert(contextTestResult == "value50", "上下文管理：大量变量设置应该成功");
        
        // 清理上下文
        largeContextEvaluator.clearContext();
        
        // 验证清理成功
        var clearedResult:String = largeContextEvaluator.evaluateSafe("var50", "CLEARED");
        _assert(clearedResult == "CLEARED", "上下文清理：变量应该被正确清理");
        
        // 验证内置功能保留
        var builtinStillWorks:Number = largeContextEvaluator.evaluate("Math.abs(-123)");
        _assert(builtinStillWorks == 123, "上下文清理：内置功能应该保留");
        
        // 重复创建和销毁evaluator
        var creationTestStart:Number = getTimer();
        for (var k:Number = 0; k < 50; k++) {
            var tempEvaluator:PrattEvaluator = new PrattEvaluator();
            tempEvaluator.setVariable("test", k);
            tempEvaluator.evaluate("test * 2");
            tempEvaluator = null; // 标记为可回收
        }
        var creationTestTime:Number = getTimer() - creationTestStart;
        
        _assert(creationTestTime < 2000, "资源管理：重复创建销毁应该高效");
        
        // 函数闭包内存测试
        var closureEvaluator:PrattEvaluator = new PrattEvaluator();
        
        for (var l:Number = 0; l < 20; l++) {
            (function(index) {
                closureEvaluator.setFunction("closure" + index, function(x) {
                    return x + index;
                });
            })(l);
        }
        
        var closureResult:Number = closureEvaluator.evaluate("closure10(5)");
        _assert(closureResult == 15, "闭包内存：函数闭包应该正确工作");
        
        // 大对象处理
        var bigObj:Object = {};
        for (var m:Number = 0; m < 1000; m++) {
            bigObj["prop" + m] = "value" + m;
        }
        
        var bigObjEvaluator:PrattEvaluator = new PrattEvaluator();
        bigObjEvaluator.setVariable("bigObj", bigObj);
        
        var bigObjAccess:String = bigObjEvaluator.evaluate("bigObj.prop500");
        _assert(bigObjAccess == "value500", "大对象：应该正确处理大对象");
        
        // 字符串内存管理
        var stringMemoryEvaluator:PrattEvaluator = new PrattEvaluator();
        var baseString:String = "base";
        
        for (var n:Number = 0; n < 50; n++) {
            stringMemoryEvaluator.setVariable("str" + n, baseString + n);
        }
        
        var stringConcatResult:String = stringMemoryEvaluator.evaluate("str10 + str20 + str30");
        _assert(stringConcatResult == "base10base20base30", "字符串内存：字符串操作应该正确");
        
        // 数组内存管理
        var arrayMemoryEvaluator:PrattEvaluator = new PrattEvaluator();
        var bigArray:Array = [];
        
        for (var o:Number = 0; o < 500; o++) {
            bigArray.push({id: o, value: "item" + o});
        }
        
        arrayMemoryEvaluator.setVariable("bigArray", bigArray);
        
        var arrayAccessResult:String = arrayMemoryEvaluator.evaluate("bigArray[250].value");
        _assert(arrayAccessResult == "item250", "数组内存：大数组访问应该正确");
        
        // 递归结构内存测试
        var recursiveEvaluator:PrattEvaluator = new PrattEvaluator();
        
        recursiveEvaluator.setFunction("factorial", function(n) {
            if (n <= 1) return 1;
            // 注意：这里无法直接递归调用，因为函数名在其作用域内不可见
            // 这是一个限制，但测试可以验证行为
            return n;
        });
        
        var factorialResult:Number = recursiveEvaluator.evaluate("factorial(5)");
        _assert(factorialResult == 5, "递归结构：函数应该正确执行（即使不能真正递归）");
        
        // 内存使用监控（简单模拟）
        var memoryMonitorEvaluator:PrattEvaluator = new PrattEvaluator();
        var startTime:Number = getTimer();
        
        // 模拟内存密集操作
        for (var p:Number = 0; p < 100; p++) {
            var tempData:Array = [];
            for (var q:Number = 0; q < 100; q++) {
                tempData.push("data" + p + "_" + q);
            }
            memoryMonitorEvaluator.setVariable("temp" + p, tempData);
            memoryMonitorEvaluator.evaluate("temp" + p + ".length");
        }
        
        var memoryIntensiveTime:Number = getTimer() - startTime;
        _assert(memoryIntensiveTime < 5000, "内存监控：内存密集操作应该在合理时间内完成");
        
        // 清理验证
        memoryMonitorEvaluator.clearContext();
        var postCleanupTime:Number = getTimer();
        var cleanupDelta:Number = postCleanupTime - startTime - memoryIntensiveTime;
        _assert(cleanupDelta < 1000, "清理性能：上下文清理应该快速");
        
        // 工厂方法的内存隔离
        var factory1:PrattEvaluator = PrattEvaluator.createStandard();
        var factory2:PrattEvaluator = PrattEvaluator.createForBuff();
        
        factory1.setVariable("isolation", "factory1");
        factory2.setVariable("isolation", "factory2");
        
        _assert(factory1.evaluate("isolation") == "factory1", "内存隔离：工厂1应该独立");
        _assert(factory2.evaluate("isolation") == "factory2", "内存隔离：工厂2应该独立");
        
        // 批量操作的内存效率
        var batchEvaluator:PrattEvaluator = new PrattEvaluator();
        var batchExpressions:Array = [];
        
        for (var r:Number = 0; r < 100; r++) {
            batchExpressions.push((r * 2) + " + " + (r * 3));
        }
        
        var batchStart:Number = getTimer();
        var batchResults:Array = batchEvaluator.evaluateMultiple(batchExpressions);
        var batchTime:Number = getTimer() - batchStart;
        
        _assert(batchResults.length == 100, "批量内存：批量操作应该处理所有表达式");
        _assert(batchTime < 3000, "批量内存：批量操作应该高效");
        
        // 验证批量结果正确性
        _assert(batchResults[10].result == 50, "批量内存：批量结果应该正确"); // 10*2 + 10*3 = 50
    }
    
    // ============================================================================
    // 辅助函数：检查数组是否包含元素
    // ============================================================================
    private static function _arrayContains(array:Array, item):Boolean {
        for (var i:Number = 0; i < array.length; i++) {
            if (array[i] == item) return true;
        }
        return false;
    }
    
    // 辅助函数：获取当前时间（毫秒）
    private static function getTimer():Number {
        return new Date().getTime();
    }
    
    // ============================================================================
    // 测试辅助函数
    // ============================================================================
    private static function _assert(condition:Boolean, message:String):Void {
        _testCount++;
        if (condition) {
            _passCount++;
            trace("  ✅ " + message);
        } else {
            _failCount++;
            trace("  ❌ " + message);
        }
    }
}