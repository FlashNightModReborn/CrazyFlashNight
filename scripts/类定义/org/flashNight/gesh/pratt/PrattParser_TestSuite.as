import org.flashNight.gesh.pratt.*;

/**
 * PrattParser + PrattParselet 100%覆盖测试套件
 * 
 * 测试策略：
 * 1. 验证Token序列到AST结构的正确转换
 * 2. 运算符优先级和结合性的完整测试
 * 3. 所有语法结构的解析验证
 * 4. 语法错误检测和错误信息质量
 * 5. 自定义扩展功能测试
 * 6. 复杂嵌套和边界条件
 * 
 * 核心验证方法：
 * - AST结构检查（toString()）
 * - 最终求值结果验证（利用已验证的evaluate()）
 * - 错误场景的异常捕获和分析
 */
class org.flashNight.gesh.pratt.PrattParser_TestSuite {
    
    private static var _testCount:Number = 0;
    private static var _passCount:Number = 0;
    private static var _failCount:Number = 0;
    
    public static function runAllTests():Void {
        trace("========== PrattParser 100%覆盖测试开始 ==========");
        
        _testCount = 0;
        _passCount = 0;
        _failCount = 0;
        
        // 按功能模块分组测试
        testParserAPI();                    // 解析器API基础功能
        testOperatorPrecedence();           // 运算符优先级
        testOperatorAssociativity();        // 运算符结合性
        testPrefixExpressions();            // 前缀表达式解析
        testInfixExpressions();             // 中缀表达式解析
        testComplexNestedParsing();         // 复杂嵌套解析
        testSyntaxErrorHandling();          // 语法错误处理
        testParserStateManagement();        // 解析器状态管理
        testCustomExtensions();             // 自定义扩展
        testBoundaryConditions();           // 边界条件
        testParsingAccuracy();              // 解析精度验证
        testPerformanceEdgeCases();         // 性能边界情况
        
        // 输出测试结果
        trace("\n========== PrattParser 测试结果 ==========");
        trace("总计: " + _testCount + " 个测试");
        trace("通过: " + _passCount + " 个");
        trace("失败: " + _failCount + " 个");
        trace("覆盖率: " + Math.round((_passCount / _testCount) * 100) + "%");
        
        if (_failCount == 0) {
            trace("✅ PrattParser 所有测试通过！");
        } else {
            trace("❌ 存在 " + _failCount + " 个失败的测试");
        }
        trace("==========================================");
    }
    
    // ============================================================================
    // 测试分组1：解析器API基础功能
    // ============================================================================
    private static function testParserAPI():Void {
        trace("\n--- 测试分组1：解析器API基础功能 ---");
        
        // 基础parseExpression()测试
        var lexer1:PrattLexer = new PrattLexer("42");
        var parser1:PrattParser = new PrattParser(lexer1);
        var expr1:PrattExpression = parser1.parseExpression(0);
        
        _assert(expr1.type == PrattExpression.LITERAL, "基础parseExpression：应该解析字面量");
        _assert(expr1.value == 42, "基础parseExpression：字面量值应该正确");
        
        // 基础parse()测试
        var lexer2:PrattLexer = new PrattLexer("123");
        var parser2:PrattParser = new PrattParser(lexer2);
        var expr2:PrattExpression = parser2.parse();
        
        _assert(expr2.type == PrattExpression.LITERAL, "基础parse：应该解析字面量");
        _assert(expr2.value == 123, "基础parse：字面量值应该正确");
        
        // 测试getCurrentToken()
        var lexer3:PrattLexer = new PrattLexer("abc + def");
        var parser3:PrattParser = new PrattParser(lexer3);
        var currentToken:PrattToken = parser3.getCurrentToken();
        _assert(currentToken.type == PrattToken.T_IDENTIFIER && currentToken.text == "abc", 
                "getCurrentToken：应该返回当前token");
        
        // 测试consume()
        var consumedToken:PrattToken = parser3.consume();
        _assert(consumedToken.text == "abc", "consume：应该返回并消费当前token");
        
        var nextToken:PrattToken = parser3.getCurrentToken();
        _assert(nextToken.text == "+", "consume后：当前token应该前进");
        
        // 测试match()
        _assert(parser3.match(PrattToken.T_OPERATOR), "match：应该正确匹配token类型");
        _assert(!parser3.match(PrattToken.T_NUMBER), "match：应该正确识别不匹配的类型");
        
        // 测试matchText()
        _assert(parser3.matchText("+"), "matchText：应该正确匹配token文本");
        _assert(!parser3.matchText("-"), "matchText：应该正确识别不匹配的文本");
        
        // 测试consumeExpected()
        var expectedToken:PrattToken = parser3.consumeExpected(PrattToken.T_OPERATOR);
        _assert(expectedToken.text == "+", "consumeExpected：应该返回期望的token");
        
        // 测试getPrecedence()
        var precLexer:PrattLexer = new PrattLexer("*");
        var precParser:PrattParser = new PrattParser(precLexer);
        var precedence:Number = precParser.getPrecedence();
        _assert(precedence > 0, "getPrecedence：乘法运算符应该有非零优先级");
        
        // 测试空输入的EOF处理
        var eofLexer:PrattLexer = new PrattLexer("");
        var eofParser:PrattParser = new PrattParser(eofLexer);
        var eofToken:PrattToken = eofParser.getCurrentToken();
        _assert(eofToken.type == PrattToken.T_EOF, "空输入：应该立即返回EOF");
        
        // 测试解析后的EOF检查
        var completeExprLexer:PrattLexer = new PrattLexer("42");
        var completeExprParser:PrattParser = new PrattParser(completeExprLexer);
        var completeExpr:PrattExpression = completeExprParser.parse();
        _assert(completeExpr != null, "完整解析：应该成功解析表达式");
        
        // 验证toString()可以被调用（用于调试）
        var toStringResult:String = completeExpr.toString();
        _assert(toStringResult.length > 0, "AST toString：应该生成非空字符串表示");
    }
    
    // ============================================================================
    // 测试分组2：运算符优先级
    // ============================================================================
    private static function testOperatorPrecedence():Void {
        trace("\n--- 测试分组2：运算符优先级 ---");
        
        // 基础算术优先级：乘除 > 加减
        var precedenceTest1:String = "2 + 3 * 4";
        var result1:Number = _parseAndEvaluate(precedenceTest1, {});
        _assert(result1 == 14, "乘法优先级：2 + 3 * 4应该等于14，不是20");
        
        var precedenceTest2:String = "10 - 6 / 2";
        var result2:Number = _parseAndEvaluate(precedenceTest2, {});
        _assert(result2 == 7, "除法优先级：10 - 6 / 2应该等于7，不是2");
        
        var precedenceTest3:String = "8 / 2 + 3";
        var result3:Number = _parseAndEvaluate(precedenceTest3, {});
        _assert(result3 == 7, "除法优先级2：8 / 2 + 3应该等于7");
        
        // 幂运算优先级：幂 > 乘除
        var powerTest1:String = "2 * 3 ** 2";
        var powerResult1:Number = _parseAndEvaluate(powerTest1, {});
        _assert(powerResult1 == 18, "幂运算优先级：2 * 3 ** 2应该等于18，不是36");
        
        var powerTest2:String = "12 / 2 ** 2";
        var powerResult2:Number = _parseAndEvaluate(powerTest2, {});
        _assert(powerResult2 == 3, "幂运算优先级2：12 / 2 ** 2应该等于3");
        
        // 一元运算符优先级：一元 > 幂 > 乘除
        var unaryTest1:String = "-2 ** 2";
        var unaryResult1:Number = _parseAndEvaluate(unaryTest1, {});
        _assert(unaryResult1 == -4, "一元运算符优先级：-2 ** 2应该等于-4");
        
        var unaryTest2:String = "!false && true";
        var unaryResult2:Boolean = _parseAndEvaluate(unaryTest2, {});
        _assert(unaryResult2 === true, "逻辑非优先级：!false && true应该为true");
        
        // 比较运算符优先级：算术 > 比较
        var comparisonTest1:String = "5 + 3 > 7";
        var compResult1:Boolean = _parseAndEvaluate(comparisonTest1, {});
        _assert(compResult1 === true, "比较优先级：5 + 3 > 7应该为true");
        
        var comparisonTest2:String = "10 - 5 == 5";
        var compResult2:Boolean = _parseAndEvaluate(comparisonTest2, {});
        _assert(compResult2 === true, "相等比较优先级：10 - 5 == 5应该为true");
        
        // 逻辑运算符优先级：比较 > 逻辑与 > 逻辑或
        var logicalTest1:String = "true || false && false";
        var logicalResult1:Boolean = _parseAndEvaluate(logicalTest1, {});
        _assert(logicalResult1 === true, "逻辑运算符优先级：true || false && false应该为true");
        
        var logicalTest2:String = "5 > 3 && 2 < 4";
        var logicalResult2:Boolean = _parseAndEvaluate(logicalTest2, {});
        _assert(logicalResult2 === true, "逻辑与优先级：5 > 3 && 2 < 4应该为true");
        
        var logicalTest3:String = "5 > 10 || 3 < 4";
        var logicalResult3:Boolean = _parseAndEvaluate(logicalTest3, {});
        _assert(logicalResult3 === true, "逻辑或优先级：5 > 10 || 3 < 4应该为true");
        
        // 三元运算符优先级：最低优先级
        var ternaryTest1:String = "true ? 5 + 3 : 2 * 4";
        var ternaryResult1:Number = _parseAndEvaluate(ternaryTest1, {});
        _assert(ternaryResult1 == 8, "三元运算符优先级：true ? 5 + 3 : 2 * 4应该等于8");
        
        var ternaryTest2:String = "2 + 3 > 4 ? 10 : 20";
        var ternaryResult2:Number = _parseAndEvaluate(ternaryTest2, {});
        _assert(ternaryResult2 == 10, "三元运算符优先级2：2 + 3 > 4 ? 10 : 20应该等于10");
        
        // 空值合并运算符优先级
        var nullishTest1:String = "null ?? 5 + 3";
        var nullishResult1:Number = _parseAndEvaluate(nullishTest1, {});
        _assert(nullishResult1 == 8, "空值合并优先级：null ?? 5 + 3应该等于8");
        
        // 复杂混合优先级测试
        var complexTest1:String = "2 + 3 * 4 ** 2 - 1";
        var complexResult1:Number = _parseAndEvaluate(complexTest1, {});
        // 计算：2 + 3 * (4 ** 2) - 1 = 2 + 3 * 16 - 1 = 2 + 48 - 1 = 49
        _assert(complexResult1 == 49, "复杂优先级：2 + 3 * 4 ** 2 - 1应该等于49");
        
        var complexTest2:String = "!false && 5 > 3 || 2 == 3";
        var complexResult2:Boolean = _parseAndEvaluate(complexTest2, {});
        // 计算：(!false) && (5 > 3) || (2 == 3) = true && true || false = true
        _assert(complexResult2 === true, "复杂逻辑优先级：!false && 5 > 3 || 2 == 3应该为true");
    }
    
    // ============================================================================
    // 测试分组3：运算符结合性
    // ============================================================================
    private static function testOperatorAssociativity():Void {
        trace("\n--- 测试分组3：运算符结合性 ---");
        
        // 左结合测试：加减法
        var leftAssocTest1:String = "10 - 5 - 2";
        var leftResult1:Number = _parseAndEvaluate(leftAssocTest1, {});
        _assert(leftResult1 == 3, "左结合减法：10 - 5 - 2应该等于3，不是7");
        
        var leftAssocTest2:String = "2 + 3 + 4";
        var leftResult2:Number = _parseAndEvaluate(leftAssocTest2, {});
        _assert(leftResult2 == 9, "左结合加法：2 + 3 + 4应该等于9");
        
        var leftAssocTest3:String = "20 / 4 / 2";
        var leftResult3:Number = _parseAndEvaluate(leftAssocTest3, {});
        _assert(leftResult3 == 2.5, "左结合除法：20 / 4 / 2应该等于2.5，不是10");
        
        var leftAssocTest4:String = "2 * 3 * 4";
        var leftResult4:Number = _parseAndEvaluate(leftAssocTest4, {});
        _assert(leftResult4 == 24, "左结合乘法：2 * 3 * 4应该等于24");
        
        // 右结合测试：幂运算
        var rightAssocTest1:String = "2 ** 3 ** 2";
        var rightResult1:Number = _parseAndEvaluate(rightAssocTest1, {});
        _assert(rightResult1 == 512, "右结合幂运算：2 ** 3 ** 2应该等于512，不是64");
        
        var rightAssocTest2:String = "3 ** 2 ** 2";
        var rightResult2:Number = _parseAndEvaluate(rightAssocTest2, {});
        _assert(rightResult2 == 81, "右结合幂运算2：3 ** 2 ** 2应该等于81");
        
        // 三元运算符右结合
        var ternaryRightTest:String = "true ? false ? 1 : 2 : 3";
        var ternaryRightResult:Number = _parseAndEvaluate(ternaryRightTest, {});
        _assert(ternaryRightResult == 2, "三元运算符右结合：true ? false ? 1 : 2 : 3应该等于2");
        
        var ternaryRightTest2:String = "false ? 1 : true ? 2 : 3";
        var ternaryRightResult2:Number = _parseAndEvaluate(ternaryRightTest2, {});
        _assert(ternaryRightResult2 == 2, "三元运算符右结合2：false ? 1 : true ? 2 : 3应该等于2");
        
        // 比较运算符左结合
        var compLeftTest:String = "5 > 3 > 1";
        var compLeftResult:Boolean = _parseAndEvaluate(compLeftTest, {});
        // (5 > 3) > 1 = true > 1，在JS中true转换为1，所以1 > 1为false
        _assert(compLeftResult === false, "比较运算符左结合：5 > 3 > 1应该为false");
        
        // 逻辑运算符左结合
        var logicalLeftTest1:String = "true && false && true";
        var logicalLeftResult1:Boolean = _parseAndEvaluate(logicalLeftTest1, {});
        _assert(logicalLeftResult1 === false, "逻辑与左结合：true && false && true应该为false");
        
        var logicalLeftTest2:String = "false || false || true";
        var logicalLeftResult2:Boolean = _parseAndEvaluate(logicalLeftTest2, {});
        _assert(logicalLeftResult2 === true, "逻辑或左结合：false || false || true应该为true");
        
        // 混合结合性测试
        var mixedAssocTest1:String = "2 ** 3 * 4";
        var mixedAssocResult1:Number = _parseAndEvaluate(mixedAssocTest1, {});
        _assert(mixedAssocResult1 == 32, "混合结合性：2 ** 3 * 4应该等于32");
        
        var mixedAssocTest2:String = "16 / 2 ** 3";
        var mixedAssocResult2:Number = _parseAndEvaluate(mixedAssocTest2, {});
        _assert(mixedAssocResult2 == 2, "混合结合性2：16 / 2 ** 3应该等于2");
        
        // 复杂结合性测试
        var complexAssocTest:String = "10 - 5 + 3 - 2";
        var complexAssocResult:Number = _parseAndEvaluate(complexAssocTest, {});
        // ((10 - 5) + 3) - 2 = (5 + 3) - 2 = 8 - 2 = 6
        _assert(complexAssocResult == 6, "复杂左结合：10 - 5 + 3 - 2应该等于6");
        
        var complexRightAssocTest:String = "2 ** (3 ** 2) == 2 ** 3 ** 2";
        var complexRightAssocResult:Boolean = _parseAndEvaluate(complexRightAssocTest, {});
        _assert(complexRightAssocResult === true, "复杂右结合验证：显式分组应该等于隐式右结合");
    }
    
    // ============================================================================
    // 测试分组4：前缀表达式解析
    // ============================================================================
    private static function testPrefixExpressions():Void {
        trace("\n--- 测试分组4：前缀表达式解析 ---");
        
        // 字面量解析
        testLiteralParsing();
        
        // 标识符解析
        testIdentifierParsing();
        
        // 分组表达式解析
        testGroupParsing();
        
        // 一元运算符解析
        testUnaryOperatorParsing();
    }
    
    private static function testLiteralParsing():Void {
        // 数字字面量
        var numberTests:Array = ["42", "3.14", "0", "123.456"];
        for (var i:Number = 0; i < numberTests.length; i++) {
            var numResult:Number = _parseAndEvaluate(numberTests[i], {});
            _assert(numResult == parseFloat(numberTests[i]), "数字字面量：" + numberTests[i] + "应该正确解析");
        }
        
        // 字符串字面量
        var stringTests:Array = ["\"hello\"", "'world'", "\"\"", "'test'"];
        var expectedStrings:Array = ["hello", "world", "", "test"];
        for (var j:Number = 0; j < stringTests.length; j++) {
            var strResult:String = _parseAndEvaluate(stringTests[j], {});
            _assert(strResult == expectedStrings[j], "字符串字面量：" + stringTests[j] + "应该正确解析");
        }
        
        // 布尔字面量
        var boolTrueResult:Boolean = _parseAndEvaluate("true", {});
        _assert(boolTrueResult === true, "布尔字面量：true应该解析为true");
        
        var boolFalseResult:Boolean = _parseAndEvaluate("false", {});
        _assert(boolFalseResult === false, "布尔字面量：false应该解析为false");
        
        // null和undefined字面量
        var nullResult = _parseAndEvaluate("null", {});
        _assert(nullResult === null, "null字面量：null应该解析为null");
        
        var undefinedResult = _parseAndEvaluate("undefined", {});
        _assert(undefinedResult === undefined, "undefined字面量：undefined应该解析为undefined");
    }
    
    private static function testIdentifierParsing():Void {
        var context:Object = {
            myVar: 42,
            _private: "private",
            $special: "special",
            camelCase: "camel",
            under_score: "underscore"
        };
        
        var identifierTests:Array = ["myVar", "_private", "$special", "camelCase", "under_score"];
        var expectedValues:Array = [42, "private", "special", "camel", "underscore"];
        
        for (var i:Number = 0; i < identifierTests.length; i++) {
            var identResult = _parseAndEvaluate(identifierTests[i], context);
            _assert(identResult == expectedValues[i], "标识符解析：" + identifierTests[i] + "应该正确解析");
        }
    }
    
    private static function testGroupParsing():Void {
        // 基础分组
        var groupTest1:Number = _parseAndEvaluate("(42)", {});
        _assert(groupTest1 == 42, "基础分组：(42)应该等于42");
        
        var groupTest2:Number = _parseAndEvaluate("(2 + 3)", {});
        _assert(groupTest2 == 5, "分组运算：(2 + 3)应该等于5");
        
        // 改变优先级的分组
        var priorityGroupTest1:Number = _parseAndEvaluate("(2 + 3) * 4", {});
        _assert(priorityGroupTest1 == 20, "分组优先级：(2 + 3) * 4应该等于20");
        
        var priorityGroupTest2:Number = _parseAndEvaluate("2 * (3 + 4)", {});
        _assert(priorityGroupTest2 == 14, "分组优先级2：2 * (3 + 4)应该等于14");
        
        // 嵌套分组
        var nestedGroupTest:Number = _parseAndEvaluate("((2 + 3) * (4 + 1))", {});
        _assert(nestedGroupTest == 25, "嵌套分组：((2 + 3) * (4 + 1))应该等于25");
        
        // 复杂嵌套分组
        var complexGroupTest:Number = _parseAndEvaluate("(2 + (3 * (4 + 1)))", {});
        _assert(complexGroupTest == 17, "复杂嵌套分组：(2 + (3 * (4 + 1)))应该等于17");
        
        // 分组与一元运算符
        var groupUnaryTest:Number = _parseAndEvaluate("-(2 + 3)", {});
        _assert(groupUnaryTest == -5, "分组一元运算：-(2 + 3)应该等于-5");
        
        var groupUnaryTest2:Boolean = _parseAndEvaluate("!(true && false)", {});
        _assert(groupUnaryTest2 === true, "分组逻辑非：!(true && false)应该为true");
    }
    
    private static function testUnaryOperatorParsing():Void {
        // 正号运算符
        var plusTest1:Number = _parseAndEvaluate("+42", {});
        _assert(plusTest1 == 42, "正号运算符：+42应该等于42");
        
        var plusTest2:Number = _parseAndEvaluate("+(-5)", {});
        _assert(plusTest2 == -5, "正号嵌套：+(-5)应该等于-5");
        
        // 负号运算符
        var minusTest1:Number = _parseAndEvaluate("-42", {});
        _assert(minusTest1 == -42, "负号运算符：-42应该等于-42");
        
        var minusTest2:Number = _parseAndEvaluate("-(-5)", {});
        _assert(minusTest2 == 5, "负号嵌套：-(-5)应该等于5");
        
        // 逻辑非运算符
        var notTest1:Boolean = _parseAndEvaluate("!true", {});
        _assert(notTest1 === false, "逻辑非：!true应该为false");
        
        var notTest2:Boolean = _parseAndEvaluate("!false", {});
        _assert(notTest2 === true, "逻辑非：!false应该为true");
        
        var notTest3:Boolean = _parseAndEvaluate("!!true", {});
        _assert(notTest3 === true, "双重逻辑非：!!true应该为true");
        
        // typeof运算符
        var typeofTest1:String = _parseAndEvaluate("typeof 42", {});
        _assert(typeofTest1 == "number", "typeof运算符：typeof 42应该为'number'");
        
        var typeofTest2:String = _parseAndEvaluate("typeof true", {});
        _assert(typeofTest2 == "boolean", "typeof运算符：typeof true应该为'boolean'");
        
        var typeofTest3:String = _parseAndEvaluate("typeof \"hello\"", {});
        _assert(typeofTest3 == "string", "typeof运算符：typeof \"hello\"应该为'string'");
        
        // 一元运算符与其他表达式组合
        var unaryBinaryTest1:Number = _parseAndEvaluate("-5 + 3", {});
        _assert(unaryBinaryTest1 == -2, "一元二元组合：-5 + 3应该等于-2");
        
        var unaryBinaryTest2:Boolean = _parseAndEvaluate("!true || false", {});
        _assert(unaryBinaryTest2 === false, "一元逻辑组合：!true || false应该为false");
        
        var unaryGroupTest:Number = _parseAndEvaluate("-(2 + 3) * 2", {});
        _assert(unaryGroupTest == -10, "一元分组组合：-(2 + 3) * 2应该等于-10");
    }
    
    // ============================================================================
    // 测试分组5：中缀表达式解析
    // ============================================================================
    private static function testInfixExpressions():Void {
        trace("\n--- 测试分组5：中缀表达式解析 ---");
        
        // 二元运算符解析
        testBinaryOperatorParsing();
        
        // 三元运算符解析
        testTernaryOperatorParsing();
        
        // 函数调用解析
        testFunctionCallParsing();
        
        // 属性访问解析
        testPropertyAccessParsing();
        
        // 数组访问解析
        testArrayAccessParsing();
    }
    
    private static function testBinaryOperatorParsing():Void {
        // 算术运算符
        var addTest:Number = _parseAndEvaluate("5 + 3", {});
        _assert(addTest == 8, "加法运算符：5 + 3应该等于8");
        
        var subTest:Number = _parseAndEvaluate("10 - 4", {});
        _assert(subTest == 6, "减法运算符：10 - 4应该等于6");
        
        var mulTest:Number = _parseAndEvaluate("6 * 7", {});
        _assert(mulTest == 42, "乘法运算符：6 * 7应该等于42");
        
        var divTest:Number = _parseAndEvaluate("15 / 3", {});
        _assert(divTest == 5, "除法运算符：15 / 3应该等于5");
        
        var modTest:Number = _parseAndEvaluate("10 % 3", {});
        _assert(modTest == 1, "取模运算符：10 % 3应该等于1");
        
        var powTest:Number = _parseAndEvaluate("2 ** 3", {});
        _assert(powTest == 8, "幂运算符：2 ** 3应该等于8");
        
        // 比较运算符
        var eqTest:Boolean = _parseAndEvaluate("5 == 5", {});
        _assert(eqTest === true, "相等运算符：5 == 5应该为true");
        
        var neqTest:Boolean = _parseAndEvaluate("5 != 3", {});
        _assert(neqTest === true, "不等运算符：5 != 3应该为true");
        
        var strictEqTest:Boolean = _parseAndEvaluate("5 === 5", {});
        _assert(strictEqTest === true, "严格相等：5 === 5应该为true");
        
        var strictNeqTest:Boolean = _parseAndEvaluate("5 !== \"5\"", {});
        _assert(strictNeqTest === true, "严格不等：5 !== \"5\"应该为true");
        
        var ltTest:Boolean = _parseAndEvaluate("3 < 5", {});
        _assert(ltTest === true, "小于运算符：3 < 5应该为true");
        
        var gtTest:Boolean = _parseAndEvaluate("7 > 4", {});
        _assert(gtTest === true, "大于运算符：7 > 4应该为true");
        
        var lteTest:Boolean = _parseAndEvaluate("5 <= 5", {});
        _assert(lteTest === true, "小于等于：5 <= 5应该为true");
        
        var gteTest:Boolean = _parseAndEvaluate("6 >= 6", {});
        _assert(gteTest === true, "大于等于：6 >= 6应该为true");
        
        // 逻辑运算符
        var andTest:Boolean = _parseAndEvaluate("true && true", {});
        _assert(andTest === true, "逻辑与：true && true应该为true");
        
        var orTest:Boolean = _parseAndEvaluate("false || true", {});
        _assert(orTest === true, "逻辑或：false || true应该为true");
        
        // 空值合并运算符
        var nullishTest:String = _parseAndEvaluate("null ?? \"default\"", {});
        _assert(nullishTest == "default", "空值合并：null ?? \"default\"应该为'default'");
        
        var nullishTest2:Number = _parseAndEvaluate("42 ?? \"default\"", {});
        _assert(nullishTest2 == 42, "空值合并非null：42 ?? \"default\"应该为42");
    }
    
    private static function testTernaryOperatorParsing():Void {
        // 基础三元运算符
        var ternaryTest1:String = _parseAndEvaluate("true ? \"yes\" : \"no\"", {});
        _assert(ternaryTest1 == "yes", "基础三元：true ? \"yes\" : \"no\"应该为'yes'");
        
        var ternaryTest2:String = _parseAndEvaluate("false ? \"yes\" : \"no\"", {});
        _assert(ternaryTest2 == "no", "基础三元假：false ? \"yes\" : \"no\"应该为'no'");
        
        // 条件为表达式的三元运算符
        var ternaryExprTest:Number = _parseAndEvaluate("5 > 3 ? 10 : 20", {});
        _assert(ternaryExprTest == 10, "表达式条件三元：5 > 3 ? 10 : 20应该为10");
        
        var ternaryExprTest2:Number = _parseAndEvaluate("2 + 2 == 5 ? 100 : 200", {});
        _assert(ternaryExprTest2 == 200, "表达式条件三元2：2 + 2 == 5 ? 100 : 200应该为200");
        
        // 分支为表达式的三元运算符
        var ternaryBranchTest:Number = _parseAndEvaluate("true ? 5 + 3 : 2 * 4", {});
        _assert(ternaryBranchTest == 8, "表达式分支三元：true ? 5 + 3 : 2 * 4应该为8");
        
        var ternaryBranchTest2:Number = _parseAndEvaluate("false ? 5 + 3 : 2 * 4", {});
        _assert(ternaryBranchTest2 == 8, "表达式分支三元2：false ? 5 + 3 : 2 * 4应该为8");
        
        // 嵌套三元运算符
        var nestedTernaryTest:Number = _parseAndEvaluate("true ? (false ? 1 : 2) : 3", {});
        _assert(nestedTernaryTest == 2, "嵌套三元：true ? (false ? 1 : 2) : 3应该为2");
        
        var chainedTernaryTest:Number = _parseAndEvaluate("false ? 1 : true ? 2 : 3", {});
        _assert(chainedTernaryTest == 2, "链式三元：false ? 1 : true ? 2 : 3应该为2");
        
        // 三元运算符与其他运算符组合
        var ternaryComplexTest:Number = _parseAndEvaluate("5 > 3 ? 10 + 5 : 20 - 5", {});
        _assert(ternaryComplexTest == 15, "三元复杂表达式：5 > 3 ? 10 + 5 : 20 - 5应该为15");
        
        var ternaryLogicalTest:Boolean = _parseAndEvaluate("true && false ? true : false || true", {});
        _assert(ternaryLogicalTest === true, "三元逻辑组合：true && false ? true : false || true应该为true");
    }
    
    private static function testFunctionCallParsing():Void {
        var context:Object = {
            add: function(a, b) { return a + b; },
            multiply: function(a, b, c) { return a * b * c; },
            noArgs: function() { return "no arguments"; },
            identity: function(x) { return x; },
            Math: {
                max: function(a, b) { return a > b ? a : b; },
                min: function(a, b) { return a < b ? a : b; }
            },
            obj: {
                method: function(x) { return x * 2; }
            }
        };
        
        // 无参数函数调用
        var noArgsTest:String = _parseAndEvaluate("noArgs()", context);
        _assert(noArgsTest == "no arguments", "无参数函数调用：noArgs()应该正确调用");
        
        // 单参数函数调用
        var singleArgTest:Number = _parseAndEvaluate("identity(42)", context);
        _assert(singleArgTest == 42, "单参数函数调用：identity(42)应该返回42");
        
        // 多参数函数调用
        var multiArgTest:Number = _parseAndEvaluate("add(5, 3)", context);
        _assert(multiArgTest == 8, "多参数函数调用：add(5, 3)应该返回8");
        
        var threeArgTest:Number = _parseAndEvaluate("multiply(2, 3, 4)", context);
        _assert(threeArgTest == 24, "三参数函数调用：multiply(2, 3, 4)应该返回24");
        
        // 参数为表达式的函数调用
        var exprArgTest:Number = _parseAndEvaluate("add(2 + 3, 4 * 2)", context);
        _assert(exprArgTest == 13, "表达式参数：add(2 + 3, 4 * 2)应该返回13");
        
        var complexArgTest:Number = _parseAndEvaluate("add(5 > 3 ? 10 : 5, 2 ** 3)", context);
        _assert(complexArgTest == 18, "复杂表达式参数：add(5 > 3 ? 10 : 5, 2 ** 3)应该返回18");
        
        // 对象方法调用
        var methodTest:Number = _parseAndEvaluate("Math.max(10, 20)", context);
        _assert(methodTest == 20, "对象方法调用：Math.max(10, 20)应该返回20");
        
        var methodTest2:Number = _parseAndEvaluate("obj.method(5)", context);
        _assert(methodTest2 == 10, "对象方法调用2：obj.method(5)应该返回10");
        
        // 嵌套函数调用
        var nestedCallTest:Number = _parseAndEvaluate("add(identity(5), identity(3))", context);
        _assert(nestedCallTest == 8, "嵌套函数调用：add(identity(5), identity(3))应该返回8");
        
        var deepNestedTest:Number = _parseAndEvaluate("add(add(1, 2), add(3, 4))", context);
        _assert(deepNestedTest == 10, "深度嵌套调用：add(add(1, 2), add(3, 4))应该返回10");
        
        // 函数调用与其他表达式组合
        var callBinaryTest:Number = _parseAndEvaluate("add(5, 3) * 2", context);
        _assert(callBinaryTest == 16, "函数调用二元组合：add(5, 3) * 2应该返回16");
        
        var callTernaryTest:Number = _parseAndEvaluate("add(5, 3) > 7 ? 100 : 200", context);
        _assert(callTernaryTest == 100, "函数调用三元组合：add(5, 3) > 7 ? 100 : 200应该返回100");
    }
    
    private static function testPropertyAccessParsing():Void {
        var context:Object = {
            user: {
                name: "Alice",
                age: 25,
                profile: {
                    email: "alice@example.com",
                    settings: {
                        theme: "dark"
                    }
                }
            },
            config: {
                version: "1.0",
                debug: true
            }
        };
        
        // 基础属性访问
        var basicPropTest:String = _parseAndEvaluate("user.name", context);
        _assert(basicPropTest == "Alice", "基础属性访问：user.name应该返回'Alice'");
        
        var numPropTest:Number = _parseAndEvaluate("user.age", context);
        _assert(numPropTest == 25, "数字属性访问：user.age应该返回25");
        
        var boolPropTest:Boolean = _parseAndEvaluate("config.debug", context);
        _assert(boolPropTest === true, "布尔属性访问：config.debug应该返回true");
        
        // 嵌套属性访问
        var nestedPropTest:String = _parseAndEvaluate("user.profile.email", context);
        _assert(nestedPropTest == "alice@example.com", "嵌套属性访问：user.profile.email应该正确");
        
        var deepNestedTest:String = _parseAndEvaluate("user.profile.settings.theme", context);
        _assert(deepNestedTest == "dark", "深度嵌套属性：user.profile.settings.theme应该返回'dark'");
        
        // 属性访问与其他表达式组合
        var propBinaryTest:Number = _parseAndEvaluate("user.age + 5", context);
        _assert(propBinaryTest == 30, "属性访问二元组合：user.age + 5应该返回30");
        
        var propComparisonTest:Boolean = _parseAndEvaluate("user.age > 20", context);
        _assert(propComparisonTest === true, "属性访问比较：user.age > 20应该为true");
        
        var propTernaryTest:String = _parseAndEvaluate("config.debug ? \"debug\" : \"production\"", context);
        _assert(propTernaryTest == "debug", "属性访问三元：config.debug ? \"debug\" : \"production\"应该返回'debug'");
        
        // 属性访问作为函数调用的一部分
        context.greet = function(name) { return "Hello, " + name; };
        var propFuncTest:String = _parseAndEvaluate("greet(user.name)", context);
        _assert(propFuncTest == "Hello, Alice", "属性访问函数参数：greet(user.name)应该返回'Hello, Alice'");
    }
    
    private static function testArrayAccessParsing():Void {
        var context:Object = {
            numbers: [1, 2, 3, 4, 5],
            strings: ["hello", "world"],
            nested: [[1, 2], [3, 4]],
            objects: [
                {name: "Alice", age: 25},
                {name: "Bob", age: 30}
            ],
            index: 1
        };
        
        // 基础数组访问
        var basicArrayTest:Number = _parseAndEvaluate("numbers[0]", context);
        _assert(basicArrayTest == 1, "基础数组访问：numbers[0]应该返回1");
        
        var arrayTest2:Number = _parseAndEvaluate("numbers[2]", context);
        _assert(arrayTest2 == 3, "数组访问：numbers[2]应该返回3");
        
        var stringArrayTest:String = _parseAndEvaluate("strings[1]", context);
        _assert(stringArrayTest == "world", "字符串数组访问：strings[1]应该返回'world'");
        
        // 使用变量作为索引
        var varIndexTest:Number = _parseAndEvaluate("numbers[index]", context);
        _assert(varIndexTest == 2, "变量索引：numbers[index]应该返回2");
        
        // 使用表达式作为索引
        var exprIndexTest:Number = _parseAndEvaluate("numbers[1 + 1]", context);
        _assert(exprIndexTest == 3, "表达式索引：numbers[1 + 1]应该返回3");
        
        var complexIndexTest:Number = _parseAndEvaluate("numbers[5 - 3]", context);
        _assert(complexIndexTest == 3, "复杂表达式索引：numbers[5 - 3]应该返回3");
        
        // 嵌套数组访问
        var nestedArrayTest:Number = _parseAndEvaluate("nested[0][1]", context);
        _assert(nestedArrayTest == 2, "嵌套数组访问：nested[0][1]应该返回2");
        
        var nestedArrayTest2:Number = _parseAndEvaluate("nested[1][0]", context);
        _assert(nestedArrayTest2 == 3, "嵌套数组访问2：nested[1][0]应该返回3");
        
        // 对象数组的属性访问
        var objArrayPropTest:String = _parseAndEvaluate("objects[0].name", context);
        _assert(objArrayPropTest == "Alice", "对象数组属性：objects[0].name应该返回'Alice'");
        
        var objArrayPropTest2:Number = _parseAndEvaluate("objects[1].age", context);
        _assert(objArrayPropTest2 == 30, "对象数组属性2：objects[1].age应该返回30");
        
        // 数组访问与其他表达式组合
        var arrayBinaryTest:Number = _parseAndEvaluate("numbers[0] + numbers[1]", context);
        _assert(arrayBinaryTest == 3, "数组访问二元组合：numbers[0] + numbers[1]应该返回3");
        
        var arrayComparisonTest:Boolean = _parseAndEvaluate("numbers[4] > numbers[0]", context);
        _assert(arrayComparisonTest === true, "数组访问比较：numbers[4] > numbers[0]应该为true");
        
        var arrayTernaryTest:Number = _parseAndEvaluate("numbers[0] > 0 ? numbers[1] : numbers[2]", context);
        _assert(arrayTernaryTest == 2, "数组访问三元：numbers[0] > 0 ? numbers[1] : numbers[2]应该返回2");
    }
    
    // ============================================================================
    // 测试分组6：复杂嵌套解析
    // ============================================================================
    private static function testComplexNestedParsing():Void {
        trace("\n--- 测试分组6：复杂嵌套解析 ---");
        
        var context:Object = {
            users: [
                {name: "Alice", scores: [85, 92, 78], active: true},
                {name: "Bob", scores: [90, 88, 95], active: false},
                {name: "Charlie", scores: [75, 80, 85], active: true}
            ],
            config: {
                passing: 80,
                bonus: 5,
                multiplier: 1.1
            },
            Math: {
                max: function(a, b, c) {
                    var result = a;
                    if (b > result) result = b;
                    if (arguments.length > 2 && c > result) result = c;
                    return result;
                },
                avg: function(arr) {
                    var sum = 0;
                    for (var i = 0; i < arr.length; i++) {
                        sum += arr[i];
                    }
                    return sum / arr.length;
                }
            }
        };
        
        // 复杂属性和数组访问组合
        var complexAccessTest:Number = _parseAndEvaluate("users[0].scores[1]", context);
        _assert(complexAccessTest == 92, "复杂访问：users[0].scores[1]应该返回92");
        
        var complexAccessTest2:String = _parseAndEvaluate("users[1].name", context);
        _assert(complexAccessTest2 == "Bob", "复杂访问2：users[1].name应该返回'Bob'");
        
        // 函数调用与复杂访问
        var funcComplexTest:Number = _parseAndEvaluate("Math.max(users[0].scores[0], users[0].scores[1], users[0].scores[2])", context);
        _assert(funcComplexTest == 92, "函数复杂访问：Math.max(users[0].scores[0], users[0].scores[1], users[0].scores[2])应该返回92");
        
        var funcComplexTest2:Number = _parseAndEvaluate("Math.avg(users[1].scores)", context);
        _assert(Math.abs(funcComplexTest2 - 91) < 0.001, "函数复杂访问2：Math.avg(users[1].scores)应该约等于91");
        
        // 复杂条件表达式
        var complexConditionTest:String = _parseAndEvaluate("users[0].active && users[0].scores[0] > config.passing ? \"pass\" : \"fail\"", context);
        _assert(complexConditionTest == "pass", "复杂条件：users[0].active && users[0].scores[0] > config.passing ? \"pass\" : \"fail\"应该返回'pass'");
        
        var complexConditionTest2:String = _parseAndEvaluate("!users[1].active ? \"inactive\" : users[1].scores[0] > config.passing ? \"active pass\" : \"active fail\"", context);
        _assert(complexConditionTest2 == "inactive", "复杂嵌套条件应该返回'inactive'");
        
        // 复杂算术表达式
        var complexArithTest:Number = _parseAndEvaluate("(users[0].scores[0] + users[0].scores[1] + users[0].scores[2]) / 3", context);
        _assert(Math.abs(complexArithTest - 85) < 0.001, "复杂算术：平均分计算应该约等于85");
        
        var complexArithTest2:Number = _parseAndEvaluate("Math.avg(users[0].scores) * config.multiplier + (users[0].active ? config.bonus : 0)", context);
        var expectedResult = 85 * 1.1 + 5; // 93.5 + 5 = 98.5
        _assert(Math.abs(complexArithTest2 - expectedResult) < 0.001, "复杂算术2：应该约等于98.5");
        
        // 超复杂嵌套表达式
        var superComplexTest:Boolean = _parseAndEvaluate("Math.avg(users[users[0].active ? 0 : 1].scores) > config.passing && users[0].scores[Math.max(0, 1, 2) > 1 ? 2 : 0] >= config.passing", context);
        // 分解：Math.avg(users[0].scores) > 80 && users[0].scores[2] >= 80
        // 85 > 80 && 78 >= 80 = true && false = false
        _assert(superComplexTest === false, "超复杂嵌套表达式应该返回false");
        
        // 多层函数调用嵌套
        var nestedFuncTest:Number = _parseAndEvaluate("Math.max(Math.avg(users[0].scores), Math.avg(users[1].scores))", context);
        // Math.max(85, 91) = 91
        _assert(Math.abs(nestedFuncTest - 91) < 0.001, "多层函数嵌套：应该返回较大的平均分91");
        
        // 复杂三元嵌套
        var complexTernaryTest:Number = _parseAndEvaluate(
            "users[0].active ? " +
            "  (Math.avg(users[0].scores) > config.passing ? " +
            "    Math.avg(users[0].scores) * config.multiplier : " +
            "    Math.avg(users[0].scores)) : " +
            "  0"
        , context);
        // 用户激活且平均分>80，所以85*1.1=93.5
        _assert(Math.abs(complexTernaryTest - 93.5) < 0.001, "复杂三元嵌套：应该返回93.5");
        
        // 综合所有语法结构的超级复杂表达式
        var megaComplexTest:Number = _parseAndEvaluate(
            "Math.max(" +
            "  users[0].active ? Math.avg(users[0].scores) + config.bonus : 0," +
            "  users[1].active ? Math.avg(users[1].scores) + config.bonus : 0," +
            "  users[2].active ? Math.avg(users[2].scores) + config.bonus : 0" +
            ") * (config.multiplier > 1.0 ? config.multiplier : 1.0)"
        , context);
        // 用户0激活：85+5=90，用户1不激活：0，用户2激活：80+5=85
        // Math.max(90, 0, 85) = 90
        // 90 * 1.1 = 99
        _assert(Math.abs(megaComplexTest - 99) < 0.001, "超级复杂表达式：应该返回99");
    }

    // ============================================================================
    // 测试分组7：语法错误处理
    // ============================================================================
    private static function testSyntaxErrorHandling():Void {
        trace("\n--- 测试分组7：语法错误处理 ---");

        // 连续运算符错误
        _assertThrows(
            function() { _parseAndEvaluate("5 + * 3", {}); },
            "Could not parse token", // 期望的错误信息
            "连续运算符错误：5 + * 3应该抛出语法错误"
        );

        // 不匹配的括号（缺少右括号）
        _assertThrows(
            function() { _parseAndEvaluate("(5 + 3", {}); },
            "Expected T_RPAREN",
            "不匹配括号错误：(5 + 3应该抛出语法错误"
        );

        // 表达式后多余的token
        _assertThrows(
            function() { _parseAndEvaluate("5 + 3)", {}); },
            "Unexpected token after expression",
            "多余括号错误：5 + 3)应该抛出语法错误"
        );
        
        // 不完整的三元运算符（缺少冒号）
        _assertThrows(
            function() { _parseAndEvaluate("true ? 5", {}); },
            "Expected T_COLON",
            "不完整三元1：true ? 5应该抛出语法错误"
        );

        // 不完整的三元运算符（冒号后缺少表达式）
        _assertThrows(
            function() { _parseAndEvaluate("true ? 5 :", {}); },
            "Could not parse token",
            "不完整三元运算符错误2：true ? 5 :应该抛出语法错误"
        );

        // 不匹配的方括号
        _assertThrows(
            function() { _parseAndEvaluate("arr[5", {arr:[1,2,3,4,5,6]}); },
            "Expected T_RBRACKET",
            "不匹配方括号错误：arr[5应该抛出语法错误"
        );

        // 函数调用参数错误（末尾逗号）
        _assertThrows(
            function() { _parseAndEvaluate("func(5,)", {func:function(){}}); },
            "Unexpected token",
            "函数参数错误：func(5,)应该抛出语法错误"
        );

        // 函数调用参数错误（连续逗号）
        _assertThrows(
            function() { _parseAndEvaluate("func(5,, 3)", {func:function(){}}); },
            "Could not parse token",
            "函数参数错误2：func(5,, 3)应该抛出语法错误"
        );

        // 空的分组表达式
        _assertThrows(
            function() { _parseAndEvaluate("()", {}); },
            "Could not parse token",
            "空分组错误：()应该抛出语法错误"
        );

        // 表达式后多余的token
        _assertThrows(
            function() { _parseAndEvaluate("5 + 3 4", {}); },
            "Unexpected token after expression",
            "多余token错误：5 + 3 4应该抛出语法错误"
        );
        
        // 以非法的二元运算符开头
        _assertThrows(
            function() { _parseAndEvaluate("* 5", {}); },
            "Could not parse token",
            "二元运算符开头错误：* 5应该抛出语法错误"
        );

        // 以运算符结尾
        _assertThrows(
            function() { _parseAndEvaluate("5 +", {}); },
            "Could not parse token",
            "运算符结尾错误：5 +应该抛出语法错误"
        );
        
        // 错误的属性访问（点号后为数字）
        _assertThrows(
            function() { _parseAndEvaluate("obj.123", {obj:{}}); },
            "Unexpected token after expression", // 修正预期的错误消息
            "数字属性名错误：obj.123应该抛出语法错误"
        );
    }
    
    // ============================================================================
    // 测试分组8：解析器状态管理
    // ============================================================================
    private static function testParserStateManagement():Void {
        trace("\n--- 测试分组8：解析器状态管理 ---");
        
        // 测试consumeExpected的错误处理
        var lexer1:PrattLexer = new PrattLexer("5 + 3");
        var parser1:PrattParser = new PrattParser(lexer1);
        
        // 消费第一个token (5)
        var token1:PrattToken = parser1.consume();
        _assert(token1.text == "5", "状态管理：第一个token应该是5");
        
        // 测试consumeExpected成功的情况
        var opToken:PrattToken = parser1.consumeExpected(PrattToken.T_OPERATOR);
        _assert(opToken.text == "+", "状态管理：consumeExpected应该返回+运算符");
        
        // 测试consumeExpected失败的情况
        var expectedError:Boolean = false;
        try {
            parser1.consumeExpected(PrattToken.T_STRING); // 期望字符串但得到数字
        } catch (e) {
            expectedError = true;
            _assert(e.message.indexOf("Expected") >= 0, "consumeExpected错误：应该包含Expected");
        }
        _assert(expectedError, "consumeExpected错误：期望类型不匹配应该抛出错误");
        
        // 测试match和matchText的准确性
        var lexer2:PrattLexer = new PrattLexer("identifier + 42");
        var parser2:PrattParser = new PrattParser(lexer2);
        
        _assert(parser2.match(PrattToken.T_IDENTIFIER), "状态管理：match应该正确识别标识符");
        _assert(!parser2.match(PrattToken.T_NUMBER), "状态管理：match应该正确识别非数字");
        _assert(parser2.matchText("identifier"), "状态管理：matchText应该正确匹配文本");
        _assert(!parser2.matchText("other"), "状态管理：matchText应该正确识别不匹配");
        
        // 测试getPrecedence的正确性
        var lexer3:PrattLexer = new PrattLexer("+ * **");
        var parser3:PrattParser = new PrattParser(lexer3);
        
        var addPrec:Number = parser3.getPrecedence();
        parser3.consume();
        var mulPrec:Number = parser3.getPrecedence();
        parser3.consume();
        var powPrec:Number = parser3.getPrecedence();
        
        _assert(addPrec < mulPrec, "优先级管理：加法优先级应该低于乘法");
        _assert(mulPrec < powPrec, "优先级管理：乘法优先级应该低于幂运算");
        
        // 测试parseExpression的minPrecedence参数
        var lexer4:PrattLexer = new PrattLexer("2 + 3 * 4");
        var parser4:PrattParser = new PrattParser(lexer4);
        
        var expr1:PrattExpression = parser4.parseExpression(0); // 解析整个表达式
        var result1:Number = expr1.evaluate({});
        _assert(result1 == 14, "parseExpression(0)：应该解析完整表达式");
        
        // 重新开始，测试更高的minPrecedence
        var lexer5:PrattLexer = new PrattLexer("2 + 3 * 4");
        var parser5:PrattParser = new PrattParser(lexer5);
        
        var expr2:PrattExpression = parser5.parseExpression(7); // 只解析第一个数字，因为+的优先级低于7
        _assert(expr2.type == PrattExpression.LITERAL && expr2.value == 2, "parseExpression(7)：应该只解析第一个字面量");
        
        // 测试EOF状态处理
        var lexer6:PrattLexer = new PrattLexer("");
        var parser6:PrattParser = new PrattParser(lexer6);
        
        _assert(parser6.getCurrentToken().type == PrattToken.T_EOF, "EOF状态：空输入应该立即是EOF");
        _assert(parser6.getPrecedence() == 0, "EOF优先级：EOF的优先级应该是0");
        
        // 测试解析器的重复使用
        var parser7:PrattParser = new PrattParser(new PrattLexer("42"));
        var result7a:Number = parser7.parse().evaluate({});
        _assert(result7a == 42, "解析器重用：第一次解析应该正确");
        
        // 重新初始化同一个解析器
        parser7 = new PrattParser(new PrattLexer("24"));
        var result7b:Number = parser7.parse().evaluate({});
        _assert(result7b == 24, "解析器重用：重新初始化后应该正确");
    }
    
    // ============================================================================
    // 测试分组9：自定义扩展
    // ============================================================================
    private static function testCustomExtensions():Void {
        trace("\n--- 测试分组9：自定义扩展 ---");
        
        // 测试addBuffOperators方法存在性
        var lexer1:PrattLexer = new PrattLexer("a + b");
        var parser1:PrattParser = new PrattParser(lexer1);
        
        // 验证addBuffOperators方法可以被调用
        try {
            parser1.addBuffOperators();
            _assert(true, "自定义扩展：addBuffOperators方法应该存在且可调用");
        } catch (e) {
            _assert(false, "自定义扩展：addBuffOperators方法调用失败：" + e.message);
        }
        
        // 测试自定义运算符注册
        var lexer2:PrattLexer = new PrattLexer("test");
        var parser2:PrattParser = new PrattParser(lexer2);
        
        // 测试registerPrefix和registerInfix方法的存在
        try {
            // 这些方法应该存在，即使我们不能直接调用它们
            _assert(typeof parser2.registerPrefix != "undefined", "自定义扩展：registerPrefix方法应该存在");
            _assert(typeof parser2.registerInfix != "undefined", "自定义扩展：registerInfix方法应该存在");
        } catch (e) {
            // 如果方法不存在或无法访问，这也是需要注意的
            trace("注意：registerPrefix/registerInfix方法可能是私有的");
        }
        
        // 测试解析器的可扩展性架构
        var baseLexer:PrattLexer = new PrattLexer("a + b - c");
        var baseParser:PrattParser = new PrattParser(baseLexer);
        var baseResult:Number = baseParser.parse().evaluate({a: 10, b: 5, c: 3});
        _assert(baseResult == 12, "扩展基础：基本运算符应该正常工作");
        
        // 验证解析器架构支持扩展（通过检查内部结构）
        _assert(typeof PrattParselet != "undefined", "扩展架构：PrattParselet类应该存在");
        
        // 测试PrattParselet的工厂方法
        try {
            var literalParselet:PrattParselet = PrattParselet.literal();
            _assert(literalParselet != null, "Parselet工厂：literal()应该创建有效的parselet");
            
            var binaryParselet:PrattParselet = PrattParselet.binaryOperator(5, false);
            _assert(binaryParselet != null, "Parselet工厂：binaryOperator()应该创建有效的parselet");
            
            var prefixParselet:PrattParselet = PrattParselet.prefixOperator(8);
            _assert(prefixParselet != null, "Parselet工厂：prefixOperator()应该创建有效的parselet");
            
        } catch (e) {
            _assert(false, "Parselet工厂方法测试失败：" + e.message);
        }
        
        // 测试parselet类型检查
        try {
            var testParselet:PrattParselet = PrattParselet.identifier();
            _assert(testParselet.isPrefix(), "Parselet类型：identifier应该是前缀类型");
            _assert(!testParselet.isInfix(), "Parselet类型：identifier不应该是中缀类型");
            
            var infixTestParselet:PrattParselet = PrattParselet.binaryOperator(5, false);
            _assert(!infixTestParselet.isPrefix(), "Parselet类型：binaryOperator不应该是前缀类型");
            _assert(infixTestParselet.isInfix(), "Parselet类型：binaryOperator应该是中缀类型");
            
        } catch (e) {
            _assert(false, "Parselet类型检查失败：" + e.message);
        }
        
        // 测试优先级获取
        try {
            var precTestParselet:PrattParselet = PrattParselet.binaryOperator(7, false);
            _assert(precTestParselet.getPrecedence() == 7, "Parselet优先级：应该返回正确的优先级值");
            
        } catch (e) {
            _assert(false, "Parselet优先级测试失败：" + e.message);
        }
        
        // 验证扩展不会破坏现有功能
        var postExtensionLexer:PrattLexer = new PrattLexer("2 + 3 * 4");
        var postExtensionParser:PrattParser = new PrattParser(postExtensionLexer);
        postExtensionParser.addBuffOperators(); // 添加Buff运算符
        
        var postExtensionResult:Number = postExtensionParser.parse().evaluate({});
        _assert(postExtensionResult == 14, "扩展兼容性：添加自定义运算符后基础功能应该仍然正常");
    }
    
    // ============================================================================
    // 测试分组10：边界条件
    // ============================================================================
    private static function testBoundaryConditions():Void {
        trace("\n--- 测试分组10：边界条件 ---");
        
        // 空输入处理
        _assertThrows(
            function() { _parseAndEvaluate("", {}); },
            "Could not parse token",
            "空输入：应该产生解析错误"
        );

        // 只有空白的输入
        _assertThrows(
            function() { _parseAndEvaluate("   \t\n  ", {}); },
            "Could not parse token",
            "纯空白输入：应该产生解析错误"
        );
        
        // 单个token
        var singleTokenResult:Number = _parseAndEvaluate("42", {});
        _assert(singleTokenResult == 42, "单token：应该正确解析");
        
        // 极长的表达式
        var longExpr:String = "1";
        for (var i:Number = 0; i < 100; i++) {
            longExpr += " + " + (i + 2);
        }
        var longResult:Number = _parseAndEvaluate(longExpr, {});
        var expectedLong:Number = 0;
        for (var j:Number = 1; j <= 101; j++) {
            expectedLong += j;
        }
        _assert(longResult == expectedLong, "极长表达式：应该正确计算长加法链");
        
        // 深度嵌套的括号
        var deepNested:String = "";
        for (var k:Number = 0; k < 50; k++) {
            deepNested += "(";
        }
        deepNested += "42";
        for (var l:Number = 0; l < 50; l++) {
            deepNested += ")";
        }
        var deepResult:Number = _parseAndEvaluate(deepNested, {});
        _assert(deepResult == 42, "深度嵌套括号：应该正确解析");
        
        // 深度嵌套的属性访问
        var deepPropContext:Object = {a: {b: {c: {d: {e: {f: {value: 123}}}}}}};
        var deepPropResult:Number = _parseAndEvaluate("a.b.c.d.e.f.value", deepPropContext);
        _assert(deepPropResult == 123, "深度嵌套属性：应该正确访问");
        
        // 深度嵌套的数组访问
        var deepArrayContext:Object = {
            arr: [
                [
                    [
                        [
                            [42]
                        ]
                    ]
                ]
            ]
        };
        var deepArrayResult:Number = _parseAndEvaluate("arr[0][0][0][0][0]", deepArrayContext);
        _assert(deepArrayResult == 42, "深度嵌套数组：应该正确访问");
        
        // 大量参数的函数调用
        var manyArgsContext:Object = {
            sum: function() {
                var total = 0;
                for (var i = 0; i < arguments.length; i++) {
                    total += arguments[i];
                }
                return total;
            }
        };
        
        var manyArgsExpr:String = "sum(";
        for (var m:Number = 1; m <= 20; m++) {
            if (m > 1) manyArgsExpr += ", ";
            manyArgsExpr += m.toString();
        }
        manyArgsExpr += ")";
        
        var manyArgsResult:Number = _parseAndEvaluate(manyArgsExpr, manyArgsContext);
        var expectedSum:Number = 20 * 21 / 2; // 1+2+...+20 = 210
        _assert(manyArgsResult == expectedSum, "大量参数函数：应该正确传递所有参数");
        
        // 极值数字处理
        var maxNumberResult:Number = _parseAndEvaluate("999999999999999", {});
        _assert(typeof maxNumberResult == "number", "极大数字：应该被解析为数字类型");
        
        var tinyNumberResult:Number = _parseAndEvaluate("0.000000001", {});
        _assert(typeof tinyNumberResult == "number", "极小数字：应该被解析为数字类型");
        
        // 极长的字符串
        var longStringExpr:String = "\"";
        for (var n:Number = 0; n < 1000; n++) {
            longStringExpr += "a";
        }
        longStringExpr += "\"";
        var longStringResult:String = _parseAndEvaluate(longStringExpr, {});
        _assert(longStringResult.length == 1000, "极长字符串：应该保持完整长度");
        
        // 复杂标识符名称
        var complexIdentContext:Object = {};
        complexIdentContext["_$very_Complex$Identifier_123"] = "complex";
        var complexIdentResult:String = _parseAndEvaluate("_$very_Complex$Identifier_123", complexIdentContext);
        _assert(complexIdentResult == "complex", "复杂标识符：应该正确解析复杂名称");
        
        // 混合所有语法元素的复杂表达式
        var mixedComplexContext:Object = {
            obj: {
                method: function(x) { return x * 2; },
                arr: [1, 2, 3],
                nested: {value: 10}
            },
            factor: 3
        };
        
        var mixedComplexExpr:String = "obj.method(obj.arr[1]) + (obj.nested.value > 5 ? factor * 2 : factor)";
        var mixedComplexResult:Number = _parseAndEvaluate(mixedComplexExpr, mixedComplexContext);
        // obj.method(2) + (10 > 5 ? 3 * 2 : 3) = 4 + 6 = 10
        _assert(mixedComplexResult == 10, "混合复杂表达式：应该正确处理所有语法元素");
    }
    
    // ============================================================================
    // 测试分组11：解析精度验证
    // ============================================================================
    private static function testParsingAccuracy():Void {
        trace("\n--- 测试分组11：解析精度验证 ---");
        
        // AST结构验证（通过toString检查）
        var ast1:PrattExpression = _parseToAST("2 + 3");
        var ast1Str:String = ast1.toString();
        _assert(ast1Str.indexOf("Binary") >= 0 && ast1Str.indexOf("+") >= 0, "AST结构：二元表达式应该产生正确的AST");
        
        var ast2:PrattExpression = _parseToAST("(2 + 3) * 4");
        var ast2Str:String = ast2.toString();
        _assert(ast2Str.indexOf("Binary") >= 0 && ast2Str.indexOf("*") >= 0, "AST结构：分组应该影响AST结构");
        
        // 运算符优先级的AST验证
        var precedenceAST:PrattExpression = _parseToAST("2 + 3 * 4");
        var precedenceStr:String = precedenceAST.toString();
        // 应该是：[Binary:[Literal:2] + [Binary:[Literal:3] * [Literal:4]]]
        // 验证乘法是右操作数的子表达式
        _assert(precedenceStr.indexOf("3] * [") >= 0, "优先级AST：乘法应该是加法的右操作数");
        
        // 结合性的AST验证
        var assocAST:PrattExpression = _parseToAST("10 - 5 - 2");
        var assocStr:String = assocAST.toString();
        // 左结合：[Binary:[Binary:[Literal:10] - [Literal:5]] - [Literal:2]]
        _assert(assocStr.indexOf("10] - [") >= 0 && assocStr.indexOf("5]] -") >= 0, "结合性AST：应该体现左结合");
        
        // 函数调用的AST验证
        var funcAST:PrattExpression = _parseToAST("func(1, 2)");
        var funcStr:String = funcAST.toString();
        _assert(funcStr.indexOf("FunctionCall") >= 0, "函数调用AST：应该产生FunctionCall节点");
        
        // 属性访问的AST验证
        var propAST:PrattExpression = _parseToAST("obj.prop");
        var propStr:String = propAST.toString();
        _assert(propStr.indexOf("PropertyAccess") >= 0, "属性访问AST：应该产生PropertyAccess节点");
        
        // 数组访问的AST验证
        var arrayAST:PrattExpression = _parseToAST("arr[0]");
        var arrayStr:String = arrayAST.toString();
        _assert(arrayStr.indexOf("ArrayAccess") >= 0, "数组访问AST：应该产生ArrayAccess节点");
        
        // 三元运算符的AST验证
        var ternaryAST:PrattExpression = _parseToAST("true ? 1 : 2");
        var ternaryStr:String = ternaryAST.toString();
        _assert(ternaryStr.indexOf("Ternary") >= 0, "三元运算符AST：应该产生Ternary节点");
        
        // 一元运算符的AST验证
        var unaryAST:PrattExpression = _parseToAST("-5");
        var unaryStr:String = unaryAST.toString();
        _assert(unaryStr.indexOf("Unary") >= 0 && unaryStr.indexOf("-") >= 0, "一元运算符AST：应该产生Unary节点");
        
        // 复杂嵌套的AST一致性验证
        var complexExpr:String = "func(obj.prop[0] + 1, !flag ? 2 : 3)";
        var complexAST:PrattExpression = _parseToAST(complexExpr);
        var complexResult = complexAST.evaluate({
            func: function(a, b) { return a + b; },
            obj: {prop: [5]},
            flag: false
        });
        _assert(complexResult == 8, "复杂AST求值：func(5+1, !false ? 2 : 3) = 8");
        
        // 验证解析和直接构建的AST产生相同结果
        var parsedAST:PrattExpression = _parseToAST("2 + 3 * 4");
        var manualAST:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(2),
            "+",
            PrattExpression.binary(
                PrattExpression.literal(3),
                "*",
                PrattExpression.literal(4)
            )
        );
        
        var parsedResult:Number = parsedAST.evaluate({});
        var manualResult:Number = manualAST.evaluate({});
        _assert(parsedResult == manualResult, "解析精度：解析的AST应该与手动构建的AST产生相同结果");
        
        // 边界情况的精度验证
        var edgeCases:Array = [
            {expr: "0", expected: 0},
            {expr: "false", expected: false},
            {expr: "null", expected: null},
            {expr: "\"\"", expected: ""},
            {expr: "true", expected: true}
        ];
        
        for (var i:Number = 0; i < edgeCases.length; i++) {
            var edgeCase = edgeCases[i];
            var edgeResult = _parseAndEvaluate(edgeCase.expr, {});
            _assert(edgeResult === edgeCase.expected, "边界精度：" + edgeCase.expr + "应该精确解析");
        }
    }
    
    // ============================================================================
    // 测试分组12：性能边界情况
    // ============================================================================
    private static function testPerformanceEdgeCases():Void {
        trace("\n--- 测试分组12：性能边界情况 ---");
        
        // 大量重复运算符的表达式
        var manyOpsExpr:String = "1";
        for (var i:Number = 0; i < 100; i++) {
            manyOpsExpr += " + 1";
        }
        
        var startTime:Number = getTimer();
        var manyOpsResult:Number = _parseAndEvaluate(manyOpsExpr, {});
        var manyOpsTime:Number = getTimer() - startTime;
        
        _assert(manyOpsResult == 101, "大量运算符：应该正确计算结果");
        _assert(manyOpsTime < 1000, "大量运算符性能：解析时间应该在合理范围内");
        
        // 深度递归的表达式
        var deepExpr:String = "1";
        for (var j:Number = 0; j < 50; j++) {
            deepExpr = "(" + deepExpr + " + 1)";
        }
        
        var deepStartTime:Number = getTimer();
        var deepResult:Number = _parseAndEvaluate(deepExpr, {});
        var deepTime:Number = getTimer() - deepStartTime;
        
        _assert(deepResult == 51, "深度递归：应该正确计算结果");
        _assert(deepTime < 2000, "深度递归性能：解析时间应该在合理范围内");
        
        // 大量标识符的表达式
        var manyVarsContext:Object = {};
        var manyVarsExpr:String = "";
        
        for (var k:Number = 0; k < 50; k++) {
            var varName:String = "var" + k;
            manyVarsContext[varName] = k;
            if (k > 0) manyVarsExpr += " + ";
            manyVarsExpr += varName;
        }
        
        var manyVarsStartTime:Number = getTimer();
        var manyVarsResult:Number = _parseAndEvaluate(manyVarsExpr, manyVarsContext);
        var manyVarsTime:Number = getTimer() - manyVarsStartTime;
        
        var expectedVarsSum:Number = 49 * 50 / 2; // 0+1+...+49
        _assert(manyVarsResult == expectedVarsSum, "大量变量：应该正确计算结果");
        _assert(manyVarsTime < 1000, "大量变量性能：解析时间应该在合理范围内");
        
        // 复杂混合表达式的性能
        var complexPerfExpr:String = "Math.max(a + b * c, Math.min(d / e, f ** g)) > threshold ? result1 * factor : result2 + offset";
        var complexPerfContext:Object = {
            Math: {
                max: function(x, y) { return x > y ? x : y; },
                min: function(x, y) { return x < y ? x : y; }
            },
            a: 10, b: 5, c: 2, d: 20, e: 4, f: 2, g: 3,
            threshold: 15, result1: 100, factor: 1.5, result2: 50, offset: 25
        };
        
        var complexPerfStartTime:Number = getTimer();
        var complexPerfResult:Number = _parseAndEvaluate(complexPerfExpr, complexPerfContext);
        var complexPerfTime:Number = getTimer() - complexPerfStartTime;
        
        _assert(typeof complexPerfResult == "number", "复杂性能：应该产生数字结果");
        _assert(complexPerfTime < 500, "复杂性能：解析时间应该高效");
        
        // 内存使用测试（通过重复解析）
        var memTestExpr:String = "a + b * c - d / e";
        var memTestContext:Object = {a: 1, b: 2, c: 3, d: 4, e: 5};
        
        var memTestStartTime:Number = getTimer();
        for (var l:Number = 0; l < 100; l++) {
            _parseAndEvaluate(memTestExpr, memTestContext);
        }
        var memTestTime:Number = getTimer() - memTestStartTime;
        
        _assert(memTestTime < 2000, "内存使用：重复解析应该保持高效");
        
        // 解析器创建和销毁的开销
        var createStartTime:Number = getTimer();
        for (var m:Number = 0; m < 50; m++) {
            var tempLexer:PrattLexer = new PrattLexer("42");
            var tempParser:PrattParser = new PrattParser(tempLexer);
            tempParser.parse();
        }
        var createTime:Number = getTimer() - createStartTime;
        
        _assert(createTime < 1000, "创建开销：解析器创建应该高效");
        
        trace("性能测试总结：");
        trace("  大量运算符: " + manyOpsTime + "ms");
        trace("  深度递归: " + deepTime + "ms");
        trace("  大量变量: " + manyVarsTime + "ms");
        trace("  复杂表达式: " + complexPerfTime + "ms");
        trace("  重复解析: " + memTestTime + "ms");
        trace("  创建开销: " + createTime + "ms");
    }
    
    // ============================================================================
    // 辅助函数：解析并求值
    // ============================================================================
    private static function _parseAndEvaluate(expression:String, context:Object) {
        var lexer:PrattLexer = new PrattLexer(expression);
        var parser:PrattParser = new PrattParser(lexer);
        var ast:PrattExpression = parser.parse();
        return ast.evaluate(context);
    }
    
    // 辅助函数：安全解析并求值（返回错误信息）
    private static function _parseAndEvaluateGraceful(expression:String, context:Object):Object {
        try {
            var result = _parseAndEvaluate(expression, context);
            return {result: result, error: null};
        } catch (e) {
            return {result: null, error: e.message};
        }
    }
    
    // 辅助函数：仅解析到AST
    private static function _parseToAST(expression:String):PrattExpression {
        var lexer:PrattLexer = new PrattLexer(expression);
        var parser:PrattParser = new PrattParser(lexer);
        return parser.parse();
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

    /**
     * 断言一个函数会抛出异常。
     * @param funcToTest 一个不带参数的函数，其内部会执行预期抛出异常的操作。
     * @param expectedErrorMessage (可选) 预期错误消息中应包含的子字符串。
     * @param message 测试描述信息。
     */
    private static function _assertThrows(funcToTest:Function, expectedErrorMessage:String, message:String):Void {
        _testCount++;
        var didThrow:Boolean = false;
        var errorMessage:String = "";

        try {
            funcToTest();
        } catch (e) {
            didThrow = true;
            errorMessage = e.message;
        }

        if (didThrow) {
            if (expectedErrorMessage == null || errorMessage.indexOf(expectedErrorMessage) >= 0) {
                _passCount++;
                trace("  ✅ " + message);
            } else {
                _failCount++;
                trace("  ❌ " + message + " (错误消息不匹配: 期望包含 '" + expectedErrorMessage + "', 实际为 '" + errorMessage + "')");
            }
        } else {
            _failCount++;
            trace("  ❌ " + message + " (错误: 未按预期抛出异常)");
        }
    }
}