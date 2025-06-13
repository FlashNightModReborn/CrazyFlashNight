import org.flashNight.gesh.pratt.*;

/**
 * PrattExpression 100%覆盖测试套件
 * 
 * 测试策略：
 * 1. 手动构建AST结构，隔离测试求值逻辑
 * 2. 覆盖所有表达式类型和运算符
 * 3. 全面测试错误处理和边界条件
 * 4. 验证toString()方法用于调试支持
 * 5. 确保AST结构正确时求值100%可靠
 */
class org.flashNight.gesh.pratt.PrattExpression_TestSuite {
    
    private static var _testCount:Number = 0;
    private static var _passCount:Number = 0;
    private static var _failCount:Number = 0;
    
    public static function runAllTests():Void {
        trace("========== PrattExpression 100%覆盖测试开始 ==========");
        
        _testCount = 0;
        _passCount = 0;
        _failCount = 0;
        
        // 首先验证表达式类型常量
        testExpressionConstants();
        
        // 按表达式类型分组测试
        testLiteralExpressions();      // 字面量表达式
        testIdentifierExpressions();   // 标识符表达式
        testUnaryExpressions();        // 一元表达式
        testBinaryExpressions();       // 二元表达式
        testTernaryExpressions();      // 三元表达式
        testFunctionCallExpressions(); // 函数调用表达式
        testPropertyAccessExpressions(); // 属性访问表达式
        testArrayAccessExpressions();  // 数组访问表达式
        testComplexNestedExpressions(); // 复杂嵌套表达式
        testErrorHandling();           // 错误处理
        testToStringMethod();          // toString方法
        testBoundaryConditions();      // 边界条件
        
        // 输出测试结果
        trace("\n========== PrattExpression 测试结果 ==========");
        trace("总计: " + _testCount + " 个测试");
        trace("通过: " + _passCount + " 个");
        trace("失败: " + _failCount + " 个");
        trace("覆盖率: " + Math.round((_passCount / _testCount) * 100) + "%");
        
        if (_failCount == 0) {
            trace("✅ PrattExpression 所有测试通过！");
        } else {
            trace("❌ 存在 " + _failCount + " 个失败的测试");
        }
        trace("==========================================");
    }
    
    // ============================================================================
    // 测试分组0：表达式类型常量验证
    // ============================================================================
    private static function testExpressionConstants():Void {
        trace("\n--- 测试分组0：表达式类型常量验证 ---");
        
        // 验证所有表达式类型常量都已定义且唯一
        var expectedTypes:Array = [
            "BINARY", "UNARY", "TERNARY", "LITERAL", "IDENTIFIER",
            "FUNCTION_CALL", "PROPERTY_ACCESS", "ARRAY_ACCESS"
        ];
        
        var actualTypes:Array = [
            PrattExpression.BINARY, PrattExpression.UNARY, PrattExpression.TERNARY, 
            PrattExpression.LITERAL, PrattExpression.IDENTIFIER, PrattExpression.FUNCTION_CALL,
            PrattExpression.PROPERTY_ACCESS, PrattExpression.ARRAY_ACCESS
        ];
        
        for (var i:Number = 0; i < expectedTypes.length; i++) {
            _assert(actualTypes[i] == expectedTypes[i], "表达式类型常量：" + expectedTypes[i] + "应该正确定义");
        }
        
        // 验证类型常量的唯一性
        var uniqueTypes:Object = {};
        var duplicateFound:Boolean = false;
        for (var j:Number = 0; j < actualTypes.length; j++) {
            if (uniqueTypes[actualTypes[j]]) {
                duplicateFound = true;
                break;
            }
            uniqueTypes[actualTypes[j]] = true;
        }
        _assert(!duplicateFound, "表达式类型常量：所有类型常量应该是唯一的");
        
        // 验证静态工厂方法能创建正确类型的表达式
        var literalFactoryExpr:PrattExpression = PrattExpression.literal(42);
        _assert(literalFactoryExpr.type == PrattExpression.LITERAL, "工厂方法：literal()应该创建LITERAL类型");
        
        var identifierFactoryExpr:PrattExpression = PrattExpression.identifier("test");
        _assert(identifierFactoryExpr.type == PrattExpression.IDENTIFIER, "工厂方法：identifier()应该创建IDENTIFIER类型");
        
        var binaryFactoryExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(1), "+", PrattExpression.literal(2));
        _assert(binaryFactoryExpr.type == PrattExpression.BINARY, "工厂方法：binary()应该创建BINARY类型");
        
        var unaryFactoryExpr:PrattExpression = PrattExpression.unary("-", PrattExpression.literal(1));
        _assert(unaryFactoryExpr.type == PrattExpression.UNARY, "工厂方法：unary()应该创建UNARY类型");
        
        var ternaryFactoryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(true), PrattExpression.literal(1), PrattExpression.literal(2));
        _assert(ternaryFactoryExpr.type == PrattExpression.TERNARY, "工厂方法：ternary()应该创建TERNARY类型");
        
        var functionCallFactoryExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("func"), []);
        _assert(functionCallFactoryExpr.type == PrattExpression.FUNCTION_CALL, "工厂方法：functionCall()应该创建FUNCTION_CALL类型");
        
        var propertyAccessFactoryExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("obj"), "prop");
        _assert(propertyAccessFactoryExpr.type == PrattExpression.PROPERTY_ACCESS, "工厂方法：propertyAccess()应该创建PROPERTY_ACCESS类型");
        
        var arrayAccessFactoryExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("arr"), PrattExpression.literal(0));
        _assert(arrayAccessFactoryExpr.type == PrattExpression.ARRAY_ACCESS, "工厂方法：arrayAccess()应该创建ARRAY_ACCESS类型");
    }
    
    // ============================================================================
    // 测试分组1：字面量表达式
    // ============================================================================ 
    private static function testLiteralExpressions():Void {
        trace("\n--- 测试分组1：字面量表达式 ---");
        
        var context:Object = {}; // 空上下文，字面量不需要上下文
        
        // 数字字面量
        var numberLiteral:PrattExpression = PrattExpression.literal(42);
        _assert(numberLiteral.type == PrattExpression.LITERAL, "数字字面量：类型应该是LITERAL");
        _assert(numberLiteral.evaluate(context) == 42, "数字字面量：求值应该返回42");
        
        var floatLiteral:PrattExpression = PrattExpression.literal(3.14);
        _assert(floatLiteral.evaluate(context) == 3.14, "浮点字面量：求值应该返回3.14");
        
        var zeroLiteral:PrattExpression = PrattExpression.literal(0);
        _assert(zeroLiteral.evaluate(context) == 0, "零字面量：求值应该返回0");
        
        var negativeLiteral:PrattExpression = PrattExpression.literal(-123);
        _assert(negativeLiteral.evaluate(context) == -123, "负数字面量：求值应该返回-123");
        
        // 字符串字面量
        var stringLiteral:PrattExpression = PrattExpression.literal("hello");
        _assert(stringLiteral.evaluate(context) == "hello", "字符串字面量：求值应该返回hello");
        
        var emptyStringLiteral:PrattExpression = PrattExpression.literal("");
        _assert(emptyStringLiteral.evaluate(context) == "", "空字符串字面量：求值应该返回空字符串");
        
        var specialStringLiteral:PrattExpression = PrattExpression.literal("test\nwith\tspecial");
        _assert(specialStringLiteral.evaluate(context) == "test\nwith\tspecial", "特殊字符串字面量：应该保持原样");
        
        // 布尔字面量
        var trueLiteral:PrattExpression = PrattExpression.literal(true);
        _assert(trueLiteral.evaluate(context) === true, "真值字面量：求值应该返回true");
        
        var falseLiteral:PrattExpression = PrattExpression.literal(false);
        _assert(falseLiteral.evaluate(context) === false, "假值字面量：求值应该返回false");
        
        // null和undefined字面量
        var nullLiteral:PrattExpression = PrattExpression.literal(null);
        _assert(nullLiteral.evaluate(context) === null, "null字面量：求值应该返回null");
        
        var undefinedLiteral:PrattExpression = PrattExpression.literal(undefined);
        _assert(undefinedLiteral.evaluate(context) === undefined, "undefined字面量：求值应该返回undefined");
        
        // 复杂对象字面量
        var objLiteral:PrattExpression = PrattExpression.literal({name: "test", value: 42});
        var objResult = objLiteral.evaluate(context);
        _assert(objResult.name == "test" && objResult.value == 42, "对象字面量：求值应该返回完整对象");
        
        // 数组字面量
        var arrayLiteral:PrattExpression = PrattExpression.literal([1, 2, 3]);
        var arrayResult = arrayLiteral.evaluate(context);
        _assert(arrayResult.length == 3 && arrayResult[0] == 1 && arrayResult[1] == 2 && arrayResult[2] == 3, 
                "数组字面量：求值应该返回完整数组");
    }
    
    // ============================================================================
    // 测试分组2：标识符表达式
    // ============================================================================
    private static function testIdentifierExpressions():Void {
        trace("\n--- 测试分组2：标识符表达式 ---");
        
        // 准备测试上下文
        var context:Object = {
            myVar: 123,
            myString: "hello",
            myBool: true,
            myNull: null,
            myUndefined: undefined,
            myZero: 0,
            myEmptyString: "",
            myObject: {prop: "value"},
            myArray: [1, 2, 3]
        };
        
        // 基础标识符求值
        var numberIdExpr:PrattExpression = PrattExpression.identifier("myVar");
        _assert(numberIdExpr.type == PrattExpression.IDENTIFIER, "数字标识符：类型应该是IDENTIFIER");
        _assert(numberIdExpr.evaluate(context) == 123, "数字标识符：求值应该返回123");
        
        var stringIdExpr:PrattExpression = PrattExpression.identifier("myString");
        _assert(stringIdExpr.evaluate(context) == "hello", "字符串标识符：求值应该返回hello");
        
        var boolIdExpr:PrattExpression = PrattExpression.identifier("myBool");
        _assert(boolIdExpr.evaluate(context) === true, "布尔标识符：求值应该返回true");
        
        // 特殊值标识符
        var nullIdExpr:PrattExpression = PrattExpression.identifier("myNull");
        _assert(nullIdExpr.evaluate(context) === null, "null标识符：求值应该返回null");
        
        var undefIdExpr:PrattExpression = PrattExpression.identifier("myUndefined");
        _assert(undefIdExpr.evaluate(context) === undefined, "undefined标识符：求值应该返回undefined");
        
        var zeroIdExpr:PrattExpression = PrattExpression.identifier("myZero");
        _assert(zeroIdExpr.evaluate(context) === 0, "零标识符：求值应该返回0");
        
        var emptyStrIdExpr:PrattExpression = PrattExpression.identifier("myEmptyString");
        _assert(emptyStrIdExpr.evaluate(context) === "", "空字符串标识符：求值应该返回空字符串");
        
        // 复杂类型标识符
        var objIdExpr:PrattExpression = PrattExpression.identifier("myObject");
        var objResult = objIdExpr.evaluate(context);
        _assert(objResult.prop == "value", "对象标识符：求值应该返回完整对象");
        
        var arrayIdExpr:PrattExpression = PrattExpression.identifier("myArray");
        var arrayResult = arrayIdExpr.evaluate(context);
        _assert(arrayResult.length == 3 && arrayResult[0] == 1, "数组标识符：求值应该返回完整数组");
        
        // 标识符名称边界情况
        var underscoreExpr:PrattExpression = PrattExpression.identifier("_");
        context["_"] = "underscore";
        _assert(underscoreExpr.evaluate(context) == "underscore", "下划线标识符：应该正确求值");
        
        var dollarExpr:PrattExpression = PrattExpression.identifier("$");
        context["$"] = "dollar";
        _assert(dollarExpr.evaluate(context) == "dollar", "美元符号标识符：应该正确求值");
        
        var mixedExpr:PrattExpression = PrattExpression.identifier("my_Var$123");
        context["my_Var$123"] = "mixed";
        _assert(mixedExpr.evaluate(context) == "mixed", "混合标识符：应该正确求值");

        // 测试未定义标识符的错误处理
        _assertThrows(
            function() {
                var undefinedIdentifierExpr:PrattExpression = PrattExpression.identifier("thisDoesNotExist");
                undefinedIdentifierExpr.evaluate(context);
            },
            "Undefined variable",
            "未定义标识符错误：应该抛出错误"
        );
    }
    
    // ============================================================================
    // 测试分组3：一元表达式
    // ============================================================================
    private static function testUnaryExpressions():Void {
        trace("\n--- 测试分组3：一元表达式 ---");
        
        var context:Object = {
            num: 42,
            negNum: -17,
            str: "hello",
            bool: true,
            falseBool: false,
            zero: 0,
            emptyStr: ""
        };
        
        // 正号运算符 +
        var plusExpr:PrattExpression = PrattExpression.unary("+", PrattExpression.literal(42));
        _assert(plusExpr.type == PrattExpression.UNARY, "正号表达式：类型应该是UNARY");
        _assert(plusExpr.evaluate(context) == 42, "正号表达式：+42应该等于42");
        
        var plusStrExpr:PrattExpression = PrattExpression.unary("+", PrattExpression.literal("123"));
        _assert(plusStrExpr.evaluate(context) == 123, "正号字符串：+'123'应该转换为123");
        
        var plusVarExpr:PrattExpression = PrattExpression.unary("+", PrattExpression.identifier("num"));
        _assert(plusVarExpr.evaluate(context) == 42, "正号变量：+num应该等于42");
        
        // 负号运算符 -
        var minusExpr:PrattExpression = PrattExpression.unary("-", PrattExpression.literal(42));
        _assert(minusExpr.evaluate(context) == -42, "负号表达式：-42应该等于-42");
        
        var minusNegExpr:PrattExpression = PrattExpression.unary("-", PrattExpression.literal(-17));
        _assert(minusNegExpr.evaluate(context) == 17, "负号负数：-(-17)应该等于17");
        
        var minusZeroExpr:PrattExpression = PrattExpression.unary("-", PrattExpression.literal(0));
        _assert(minusZeroExpr.evaluate(context) == 0, "负号零：-0应该等于0");
        
        var minusVarExpr:PrattExpression = PrattExpression.unary("-", PrattExpression.identifier("negNum"));
        _assert(minusVarExpr.evaluate(context) == 17, "负号变量：-negNum应该等于17");
        
        // 逻辑非运算符 !
        var notTrueExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(true));
        _assert(notTrueExpr.evaluate(context) === false, "逻辑非真：!true应该等于false");
        
        var notFalseExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(false));
        _assert(notFalseExpr.evaluate(context) === true, "逻辑非假：!false应该等于true");
        
        var notNumExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(42));
        _assert(notNumExpr.evaluate(context) === false, "逻辑非数字：!42应该等于false");
        
        var notZeroExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(0));
        _assert(notZeroExpr.evaluate(context) === true, "逻辑非零：!0应该等于true");
        
        var notStrExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal("hello"));
        _assert(notStrExpr.evaluate(context) === false, "逻辑非字符串：!'hello'应该等于false");
        
        var notEmptyStrExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(""));
        _assert(notEmptyStrExpr.evaluate(context) === true, "逻辑非空字符串：!''应该等于true");
        
        var notNullExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(null));
        _assert(notNullExpr.evaluate(context) === true, "逻辑非null：!null应该等于true");
        
        var notUndefExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(undefined));
        _assert(notUndefExpr.evaluate(context) === true, "逻辑非undefined：!undefined应该等于true");
        
        var notVarExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.identifier("bool"));
        _assert(notVarExpr.evaluate(context) === false, "逻辑非变量：!bool应该等于false");
        
        // typeof运算符
        var typeofNumExpr:PrattExpression = PrattExpression.unary("typeof", PrattExpression.literal(42));
        _assert(typeofNumExpr.evaluate(context) == "number", "typeof数字：typeof 42应该等于'number'");
        
        var typeofStrExpr:PrattExpression = PrattExpression.unary("typeof", PrattExpression.literal("hello"));
        _assert(typeofStrExpr.evaluate(context) == "string", "typeof字符串：typeof 'hello'应该等于'string'");
        
        var typeofBoolExpr:PrattExpression = PrattExpression.unary("typeof", PrattExpression.literal(true));
        _assert(typeofBoolExpr.evaluate(context) == "boolean", "typeof布尔：typeof true应该等于'boolean'");
        
        var typeofNullExpr:PrattExpression = PrattExpression.unary("typeof", PrattExpression.literal(null));
        _assert(typeofNullExpr.evaluate(context) == "object", "typeof null：typeof null应该等于'object'");
        
        var typeofUndefExpr:PrattExpression = PrattExpression.unary("typeof", PrattExpression.literal(undefined));
        _assert(typeofUndefExpr.evaluate(context) == "undefined", "typeof undefined：typeof undefined应该等于'undefined'");
        
        // 嵌套一元表达式
        var doubleNegExpr:PrattExpression = PrattExpression.unary("-", 
            PrattExpression.unary("-", PrattExpression.literal(42)));
        _assert(doubleNegExpr.evaluate(context) == 42, "双重负号：--42应该等于42");
        
        var notNotExpr:PrattExpression = PrattExpression.unary("!", 
            PrattExpression.unary("!", PrattExpression.literal(true)));
        _assert(notNotExpr.evaluate(context) === true, "双重逻辑非：!!true应该等于true");
        
        var mixedUnaryExpr:PrattExpression = PrattExpression.unary("!", 
            PrattExpression.unary("-", PrattExpression.literal(42)));
        _assert(mixedUnaryExpr.evaluate(context) === false, "混合一元：!(-42)应该等于false");
    }
    
    // ============================================================================
    // 测试分组4：二元表达式
    // ============================================================================
    private static function testBinaryExpressions():Void {
        trace("\n--- 测试分组4：二元表达式 ---");
        
        var context:Object = {
            a: 10,
            b: 3,
            c: 0,
            str1: "hello",
            str2: "world",
            bool1: true,
            bool2: false,
            nullVal: null,
            undefVal: undefined
        };
        
        // 算术运算符测试
        testArithmeticOperators(context);
        testComparisonOperators(context);
        testLogicalOperators(context);
        testSpecialOperators(context);
    }
    
    private static function testArithmeticOperators(context:Object):Void {
        // 加法运算符 +
        var addExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "+", PrattExpression.literal(3));
        _assert(addExpr.type == PrattExpression.BINARY, "加法表达式：类型应该是BINARY");
        _assert(addExpr.evaluate(context) == 8, "加法表达式：5 + 3应该等于8");
        
        var addVarExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("a"), "+", PrattExpression.identifier("b"));
        _assert(addVarExpr.evaluate(context) == 13, "变量加法：a + b应该等于13");
        
        var addZeroExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(42), "+", PrattExpression.literal(0));
        _assert(addZeroExpr.evaluate(context) == 42, "加零：42 + 0应该等于42");
        
        // 减法运算符 -
        var subExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(10), "-", PrattExpression.literal(3));
        _assert(subExpr.evaluate(context) == 7, "减法表达式：10 - 3应该等于7");
        
        var subNegExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "-", PrattExpression.literal(-3));
        _assert(subNegExpr.evaluate(context) == 8, "减负数：5 - (-3)应该等于8");
        
        var subVarExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("a"), "-", PrattExpression.identifier("b"));
        _assert(subVarExpr.evaluate(context) == 7, "变量减法：a - b应该等于7");
        
        // 乘法运算符 *
        var mulExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(6), "*", PrattExpression.literal(7));
        _assert(mulExpr.evaluate(context) == 42, "乘法表达式：6 * 7应该等于42");
        
        var mulZeroExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(42), "*", PrattExpression.literal(0));
        _assert(mulZeroExpr.evaluate(context) == 0, "乘零：42 * 0应该等于0");
        
        var mulNegExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(-4), "*", PrattExpression.literal(3));
        _assert(mulNegExpr.evaluate(context) == -12, "负数乘法：-4 * 3应该等于-12");
        
        var mulVarExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("a"), "*", PrattExpression.identifier("b"));
        _assert(mulVarExpr.evaluate(context) == 30, "变量乘法：a * b应该等于30");
        
        // 除法运算符 /
        var divExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(15), "/", PrattExpression.literal(3));
        _assert(divExpr.evaluate(context) == 5, "除法表达式：15 / 3应该等于5");
        
        var divFloatExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(10), "/", PrattExpression.literal(3));
        _assert(Math.abs(divFloatExpr.evaluate(context) - 3.333333333333333) < 0.0001, "浮点除法：10 / 3应该约等于3.333");
        
        var divVarExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("a"), "/", PrattExpression.identifier("b"));
        _assert(Math.abs(divVarExpr.evaluate(context) - 3.333333333333333) < 0.0001, "变量除法：a / b应该约等于3.333");
        
        // 取模运算符 %
        var modExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(10), "%", PrattExpression.literal(3));
        _assert(modExpr.evaluate(context) == 1, "取模表达式：10 % 3应该等于1");
        
        var modZeroResultExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(15), "%", PrattExpression.literal(5));
        _assert(modZeroResultExpr.evaluate(context) == 0, "取模零结果：15 % 5应该等于0");
        
        var modVarExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("a"), "%", PrattExpression.identifier("b"));
        _assert(modVarExpr.evaluate(context) == 1, "变量取模：a % b应该等于1");
        
        // 幂运算符 **
        var powExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(2), "**", PrattExpression.literal(3));
        _assert(powExpr.evaluate(context) == 8, "幂运算表达式：2 ** 3应该等于8");
        
        var powZeroExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "**", PrattExpression.literal(0));
        _assert(powZeroExpr.evaluate(context) == 1, "零次幂：5 ** 0应该等于1");
        
        var powOneExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(42), "**", PrattExpression.literal(1));
        _assert(powOneExpr.evaluate(context) == 42, "一次幂：42 ** 1应该等于42");
        
        var powVarExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("b"), "**", PrattExpression.literal(2));
        _assert(powVarExpr.evaluate(context) == 9, "变量幂运算：b ** 2应该等于9");
    }
    
    private static function testComparisonOperators(context:Object):Void {
        // 等于运算符 ==
        var eqNumExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "==", PrattExpression.literal(5));
        _assert(eqNumExpr.evaluate(context) === true, "数字相等：5 == 5应该为true");
        
        var eqNumStrExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "==", PrattExpression.literal("5"));
        _assert(eqNumStrExpr.evaluate(context) === true, "数字字符串相等：5 == '5'应该为true");
        
        var eqVarExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("a"), "==", PrattExpression.literal(10));
        _assert(eqVarExpr.evaluate(context) === true, "变量相等：a == 10应该为true");
        
        // 不等于运算符 !=
        var neqExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "!=", PrattExpression.literal(3));
        _assert(neqExpr.evaluate(context) === true, "不等于：5 != 3应该为true");
        
        var neqFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "!=", PrattExpression.literal(5));
        _assert(neqFalseExpr.evaluate(context) === false, "相等不等于：5 != 5应该为false");
        
        // 严格等于运算符 ===
        var strictEqExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "===", PrattExpression.literal(5));
        _assert(strictEqExpr.evaluate(context) === true, "严格相等：5 === 5应该为true");
        
        var strictEqFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "===", PrattExpression.literal("5"));
        _assert(strictEqFalseExpr.evaluate(context) === false, "严格不等：5 === '5'应该为false");
        
        // 严格不等于运算符 !==
        var strictNeqExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "!==", PrattExpression.literal("5"));
        _assert(strictNeqExpr.evaluate(context) === true, "严格不等于：5 !== '5'应该为true");
        
        var strictNeqFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "!==", PrattExpression.literal(5));
        _assert(strictNeqFalseExpr.evaluate(context) === false, "严格相等不等于：5 !== 5应该为false");
        
        // 小于运算符 <
        var ltExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(3), "<", PrattExpression.literal(5));
        _assert(ltExpr.evaluate(context) === true, "小于：3 < 5应该为true");
        
        var ltFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "<", PrattExpression.literal(3));
        _assert(ltFalseExpr.evaluate(context) === false, "不小于：5 < 3应该为false");
        
        var ltEqualExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "<", PrattExpression.literal(5));
        _assert(ltEqualExpr.evaluate(context) === false, "等于不小于：5 < 5应该为false");
        
        // 大于运算符 >
        var gtExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), ">", PrattExpression.literal(3));
        _assert(gtExpr.evaluate(context) === true, "大于：5 > 3应该为true");
        
        var gtFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(3), ">", PrattExpression.literal(5));
        _assert(gtFalseExpr.evaluate(context) === false, "不大于：3 > 5应该为false");
        
        // 小于等于运算符 <=
        var lteExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(3), "<=", PrattExpression.literal(5));
        _assert(lteExpr.evaluate(context) === true, "小于等于：3 <= 5应该为true");
        
        var lteEqualExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "<=", PrattExpression.literal(5));
        _assert(lteEqualExpr.evaluate(context) === true, "等于小于等于：5 <= 5应该为true");
        
        var lteFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), "<=", PrattExpression.literal(3));
        _assert(lteFalseExpr.evaluate(context) === false, "不小于等于：5 <= 3应该为false");
        
        // 大于等于运算符 >=
        var gteExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), ">=", PrattExpression.literal(3));
        _assert(gteExpr.evaluate(context) === true, "大于等于：5 >= 3应该为true");
        
        var gteEqualExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(5), ">=", PrattExpression.literal(5));
        _assert(gteEqualExpr.evaluate(context) === true, "等于大于等于：5 >= 5应该为true");
        
        var gteFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(3), ">=", PrattExpression.literal(5));
        _assert(gteFalseExpr.evaluate(context) === false, "不大于等于：3 >= 5应该为false");
    }
    
    private static function testLogicalOperators(context:Object):Void {
        // 逻辑与运算符 &&
        var andTrueExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(true), "&&", PrattExpression.literal(true));
        _assert(andTrueExpr.evaluate(context) === true, "逻辑与真：true && true应该为true");
        
        var andFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(true), "&&", PrattExpression.literal(false));
        _assert(andFalseExpr.evaluate(context) === false, "逻辑与假：true && false应该为false");
        
        var andBothFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(false), "&&", PrattExpression.literal(false));
        _assert(andBothFalseExpr.evaluate(context) === false, "逻辑与都假：false && false应该为false");
        
        var andTruthyExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(1), "&&", PrattExpression.literal("hello"));
        _assert(andTruthyExpr.evaluate(context) == "hello", "逻辑与真值：1 && 'hello'应该返回'hello'");
        
        var andFalsyExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(0), "&&", PrattExpression.literal("hello"));
        _assert(andFalsyExpr.evaluate(context) === 0, "逻辑与假值：0 && 'hello'应该返回0");
        
        // 逻辑或运算符 ||
        var orTrueExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(true), "||", PrattExpression.literal(false));
        _assert(orTrueExpr.evaluate(context) === true, "逻辑或真：true || false应该为true");
        
        var orBothTrueExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(true), "||", PrattExpression.literal(true));
        _assert(orBothTrueExpr.evaluate(context) === true, "逻辑或都真：true || true应该为true");
        
        var orFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(false), "||", PrattExpression.literal(false));
        _assert(orFalseExpr.evaluate(context) === false, "逻辑或都假：false || false应该为false");
        
        var orTruthyExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal("hello"), "||", PrattExpression.literal("world"));
        _assert(orTruthyExpr.evaluate(context) == "hello", "逻辑或真值：'hello' || 'world'应该返回'hello'");
        
        var orFalsyExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(null), "||", PrattExpression.literal("default"));
        _assert(orFalsyExpr.evaluate(context) == "default", "逻辑或假值：null || 'default'应该返回'default'");
    }
    
    private static function testSpecialOperators(context:Object):Void {
        // 空值合并运算符 ??
        var nullishNullExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(null), "??", PrattExpression.literal("default"));
        _assert(nullishNullExpr.evaluate(context) == "default", "空值合并null：null ?? 'default'应该返回'default'");
        
        var nullishUndefExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(undefined), "??", PrattExpression.literal("default"));
        _assert(nullishUndefExpr.evaluate(context) == "default", "空值合并undefined：undefined ?? 'default'应该返回'default'");
        
        var nullishValidExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal("value"), "??", PrattExpression.literal("default"));
        _assert(nullishValidExpr.evaluate(context) == "value", "空值合并有值：'value' ?? 'default'应该返回'value'");
        
        var nullishZeroExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(0), "??", PrattExpression.literal("default"));
        _assert(nullishZeroExpr.evaluate(context) === 0, "空值合并零：0 ?? 'default'应该返回0");
        
        var nullishEmptyStrExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(""), "??", PrattExpression.literal("default"));
        _assert(nullishEmptyStrExpr.evaluate(context) === "", "空值合并空字符串：'' ?? 'default'应该返回''");
        
        var nullishFalseExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(false), "??", PrattExpression.literal("default"));
        _assert(nullishFalseExpr.evaluate(context) === false, "空值合并false：false ?? 'default'应该返回false");
    }
    
    // ============================================================================
    // 测试分组5：三元表达式
    // ============================================================================
    private static function testTernaryExpressions():Void {
        trace("\n--- 测试分组5：三元表达式 ---");
        
        var context:Object = {
            x: 10,
            y: 5,
            isTrue: true,
            isFalse: false,
            zero: 0,
            emptyStr: "",
            nullVal: null
        };
        
        // 基础三元表达式
        var basicTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(true),
            PrattExpression.literal("yes"),
            PrattExpression.literal("no")
        );
        _assert(basicTernaryExpr.type == PrattExpression.TERNARY, "基础三元：类型应该是TERNARY");
        _assert(basicTernaryExpr.evaluate(context) == "yes", "基础三元真：true ? 'yes' : 'no'应该返回'yes'");
        
        var falseTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(false),
            PrattExpression.literal("yes"),
            PrattExpression.literal("no")
        );
        _assert(falseTernaryExpr.evaluate(context) == "no", "基础三元假：false ? 'yes' : 'no'应该返回'no'");
        
        // 使用变量的三元表达式
        var varTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.identifier("isTrue"),
            PrattExpression.identifier("x"),
            PrattExpression.identifier("y")
        );
        _assert(varTernaryExpr.evaluate(context) == 10, "变量三元真：isTrue ? x : y应该返回10");
        
        var varFalseTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.identifier("isFalse"),
            PrattExpression.identifier("x"),
            PrattExpression.identifier("y")
        );
        _assert(varFalseTernaryExpr.evaluate(context) == 5, "变量三元假：isFalse ? x : y应该返回5");
        
        // 比较表达式作为条件
        var comparisonTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.binary(PrattExpression.identifier("x"), ">", PrattExpression.identifier("y")),
            PrattExpression.literal("x is greater"),
            PrattExpression.literal("y is greater or equal")
        );
        _assert(comparisonTernaryExpr.evaluate(context) == "x is greater", "比较三元：x > y ? 'x is greater' : 'y is greater or equal'应该返回'x is greater'");
        
        // Truthy/Falsy值测试
        var truthyTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(1),
            PrattExpression.literal("truthy"),
            PrattExpression.literal("falsy")
        );
        _assert(truthyTernaryExpr.evaluate(context) == "truthy", "真值三元：1 ? 'truthy' : 'falsy'应该返回'truthy'");
        
        var falsyZeroTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(0),
            PrattExpression.literal("truthy"),
            PrattExpression.literal("falsy")
        );
        _assert(falsyZeroTernaryExpr.evaluate(context) == "falsy", "假值零三元：0 ? 'truthy' : 'falsy'应该返回'falsy'");
        
        var falsyEmptyTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(""),
            PrattExpression.literal("truthy"),
            PrattExpression.literal("falsy")
        );
        _assert(falsyEmptyTernaryExpr.evaluate(context) == "falsy", "假值空字符串三元：'' ? 'truthy' : 'falsy'应该返回'falsy'");
        
        var falsyNullTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(null),
            PrattExpression.literal("truthy"),
            PrattExpression.literal("falsy")
        );
        _assert(falsyNullTernaryExpr.evaluate(context) == "falsy", "假值null三元：null ? 'truthy' : 'falsy'应该返回'falsy'");
        
        var falsyUndefTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(undefined),
            PrattExpression.literal("truthy"),
            PrattExpression.literal("falsy")
        );
        _assert(falsyUndefTernaryExpr.evaluate(context) == "falsy", "假值undefined三元：undefined ? 'truthy' : 'falsy'应该返回'falsy'");
        
        // 嵌套三元表达式
        var nestedTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.identifier("x"),
            PrattExpression.ternary(
                PrattExpression.binary(PrattExpression.identifier("x"), ">", PrattExpression.literal(20)),
                PrattExpression.literal("very big"),
                PrattExpression.literal("medium")
            ),
            PrattExpression.literal("small")
        );
        _assert(nestedTernaryExpr.evaluate(context) == "medium", "嵌套三元：x ? (x > 20 ? 'very big' : 'medium') : 'small'应该返回'medium'");
        
        // 三元表达式的各部分都是复杂表达式
        var complexTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.binary(
                PrattExpression.identifier("x"),
                ">",
                PrattExpression.binary(PrattExpression.identifier("y"), "*", PrattExpression.literal(2))
            ),
            PrattExpression.binary(PrattExpression.identifier("x"), "+", PrattExpression.identifier("y")),
            PrattExpression.binary(PrattExpression.identifier("x"), "-", PrattExpression.identifier("y"))
        );
        _assert(complexTernaryExpr.evaluate(context) == 5, "复杂三元：(x > y * 2) ? (x + y) : (x - y)应该返回5");
    }
    
    // ============================================================================
    // 测试分组6：函数调用表达式
    // ============================================================================
    private static function testFunctionCallExpressions():Void {
        trace("\n--- 测试分组6：函数调用表达式 ---");
        
        var context:Object = {
            // 简单函数
            add: function(a, b) { return a + b; },
            multiply: function(a, b) { return a * b; },
            greet: function(name) { return "Hello, " + name; },
            noArgs: function() { return "no arguments"; },
            
            // 数学对象（模拟）
            Math: {
                max: function(a, b, c) {
                    var result = a;
                    if (b > result) result = b;
                    if (arguments.length > 2 && c > result) result = c;
                    return result;
                },
                min: function(a, b) {
                    return a < b ? a : b;
                },
                abs: function(x) {
                    return x < 0 ? -x : x;
                },
                sqrt: function(x) {
                    return Math.sqrt(x);
                }
            },
            
            // 变量
            x: 10,
            y: 5,
            name: "World"
        };
        
        // 无参数函数调用
        var noArgsCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("noArgs"),
            []
        );
        _assert(noArgsCallExpr.type == PrattExpression.FUNCTION_CALL, "无参函数调用：类型应该是FUNCTION_CALL");
        _assert(noArgsCallExpr.evaluate(context) == "no arguments", "无参函数调用：noArgs()应该返回'no arguments'");
        
        // 单参数函数调用
        var singleArgCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("greet"),
            [PrattExpression.literal("Alice")]
        );
        _assert(singleArgCallExpr.evaluate(context) == "Hello, Alice", "单参函数调用：greet('Alice')应该返回'Hello, Alice'");
        
        var singleArgVarCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("greet"),
            [PrattExpression.identifier("name")]
        );
        _assert(singleArgVarCallExpr.evaluate(context) == "Hello, World", "单参变量函数调用：greet(name)应该返回'Hello, World'");
        
        // 多参数函数调用
        var multiArgCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("add"),
            [PrattExpression.literal(3), PrattExpression.literal(7)]
        );
        _assert(multiArgCallExpr.evaluate(context) == 10, "多参函数调用：add(3, 7)应该返回10");
        
        var multiArgVarCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("multiply"),
            [PrattExpression.identifier("x"), PrattExpression.identifier("y")]
        );
        _assert(multiArgVarCallExpr.evaluate(context) == 50, "多参变量函数调用：multiply(x, y)应该返回50");
        
        // 参数是表达式的函数调用
        var exprArgCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("add"),
            [
                PrattExpression.binary(PrattExpression.literal(2), "*", PrattExpression.literal(3)),
                PrattExpression.binary(PrattExpression.literal(10), "/", PrattExpression.literal(2))
            ]
        );
        _assert(exprArgCallExpr.evaluate(context) == 11, "表达式参数函数调用：add(2 * 3, 10 / 2)应该返回11");
        
        // 对象方法调用
        var objMethodCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.propertyAccess(PrattExpression.identifier("Math"), "max"),
            [PrattExpression.literal(5), PrattExpression.literal(10), PrattExpression.literal(3)]
        );
        _assert(objMethodCallExpr.evaluate(context) == 10, "对象方法调用：Math.max(5, 10, 3)应该返回10");
        
        var objMethodVarCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.propertyAccess(PrattExpression.identifier("Math"), "min"),
            [PrattExpression.identifier("x"), PrattExpression.identifier("y")]
        );
        _assert(objMethodVarCallExpr.evaluate(context) == 5, "对象方法变量调用：Math.min(x, y)应该返回5");
        
        var objMethodAbsExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.propertyAccess(PrattExpression.identifier("Math"), "abs"),
            [PrattExpression.literal(-42)]
        );
        _assert(objMethodAbsExpr.evaluate(context) == 42, "对象方法绝对值：Math.abs(-42)应该返回42");
        
        // 嵌套函数调用
        var nestedCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("add"),
            [
                PrattExpression.functionCall(
                    PrattExpression.identifier("multiply"),
                    [PrattExpression.literal(2), PrattExpression.literal(3)]
                ),
                PrattExpression.literal(4)
            ]
        );
        _assert(nestedCallExpr.evaluate(context) == 10, "嵌套函数调用：add(multiply(2, 3), 4)应该返回10");
        
        // 函数调用作为三元表达式的一部分
        var ternaryFuncCallExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.binary(PrattExpression.identifier("x"), ">", PrattExpression.identifier("y")),
            PrattExpression.functionCall(
                PrattExpression.identifier("add"),
                [PrattExpression.identifier("x"), PrattExpression.identifier("y")]
            ),
            PrattExpression.functionCall(
                PrattExpression.identifier("multiply"),
                [PrattExpression.identifier("x"), PrattExpression.identifier("y")]
            )
        );
        _assert(ternaryFuncCallExpr.evaluate(context) == 15, "三元函数调用：x > y ? add(x, y) : multiply(x, y)应该返回15");
    }
    
    // ============================================================================
    // 测试分组7：属性访问表达式
    // ============================================================================
    private static function testPropertyAccessExpressions():Void {
        trace("\n--- 测试分组7：属性访问表达式 ---");
        
        var context:Object = {
            user: {
                name: "Alice",
                age: 25,
                profile: {
                    email: "alice@example.com",
                    settings: {
                        theme: "dark",
                        notifications: true
                    }
                }
            },
            config: {
                version: "1.0.0",
                debug: false,
                features: {
                    newUI: true,
                    betaFeatures: false
                }
            },
            emptyObj: {},
            nullObj: null
        };
        
        // 基础属性访问
        var basicPropExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("user"),
            "name"
        );
        _assert(basicPropExpr.type == PrattExpression.PROPERTY_ACCESS, "基础属性访问：类型应该是PROPERTY_ACCESS");
        _assert(basicPropExpr.evaluate(context) == "Alice", "基础属性访问：user.name应该返回'Alice'");
        
        var numPropExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("user"),
            "age"
        );
        _assert(numPropExpr.evaluate(context) == 25, "数字属性访问：user.age应该返回25");
        
        var boolPropExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("config"),
            "debug"
        );
        _assert(boolPropExpr.evaluate(context) === false, "布尔属性访问：config.debug应该返回false");
        
        // 嵌套属性访问
        var nestedPropExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.propertyAccess(
                PrattExpression.identifier("user"),
                "profile"
            ),
            "email"
        );
        _assert(nestedPropExpr.evaluate(context) == "alice@example.com", "嵌套属性访问：user.profile.email应该返回'alice@example.com'");
        
        var deepNestedPropExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.propertyAccess(
                PrattExpression.propertyAccess(
                    PrattExpression.identifier("user"),
                    "profile"
                ),
                "settings"
            ),
            "theme"
        );
        _assert(deepNestedPropExpr.evaluate(context) == "dark", "深度嵌套属性访问：user.profile.settings.theme应该返回'dark'");
        
        var deepNestedBoolExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.propertyAccess(
                PrattExpression.propertyAccess(
                    PrattExpression.identifier("config"),
                    "features"
                ),
                "newUI"
            )
        );
        // 注意：这里应该是四个参数，但实际调用只有三个，说明PrattExpression.propertyAccess需要property参数
        var deepBoolExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.propertyAccess(
                PrattExpression.identifier("config"),
                "features"
            ),
            "newUI"
        );
        _assert(deepBoolExpr.evaluate(context) === true, "深度嵌套布尔属性：config.features.newUI应该返回true");
        
        // 不存在的属性访问
        var undefinedPropExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("user"),
            "nonexistent"
        );
        _assert(undefinedPropExpr.evaluate(context) === undefined, "不存在属性访问：user.nonexistent应该返回undefined");
        
        var undefinedNestedExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("emptyObj"),
            "anything"
        );
        _assert(undefinedNestedExpr.evaluate(context) === undefined, "空对象属性访问：emptyObj.anything应该返回undefined");
        
        // 属性访问与其他表达式结合
        var propInBinaryExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.propertyAccess(PrattExpression.identifier("user"), "age"),
            "+",
            PrattExpression.literal(5)
        );
        _assert(propInBinaryExpr.evaluate(context) == 30, "属性访问二元表达式：user.age + 5应该返回30");
        
        var propInTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.propertyAccess(PrattExpression.identifier("config"), "debug"),
            PrattExpression.literal("debug mode"),
            PrattExpression.literal("production mode")
        );
        _assert(propInTernaryExpr.evaluate(context) == "production mode", "属性访问三元表达式：config.debug ? 'debug mode' : 'production mode'应该返回'production mode'");
        
        // 属性访问作为函数调用的一部分（这将在函数调用测试中体现）
        var propAsArgExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("greet"),
            [PrattExpression.propertyAccess(PrattExpression.identifier("user"), "name")]
        );
        // 注意：这里需要在context中定义greet函数
        context.greet = function(name) { return "Hello, " + name; };
        _assert(propAsArgExpr.evaluate(context) == "Hello, Alice", "属性访问作为参数：greet(user.name)应该返回'Hello, Alice'");
    }
    
    // ============================================================================
    // 测试分组8：数组访问表达式
    // ============================================================================
    private static function testArrayAccessExpressions():Void {
        trace("\n--- 测试分组8：数组访问表达式 ---");
        
        var context:Object = {
            numbers: [1, 2, 3, 4, 5],
            strings: ["hello", "world", "test"],
            mixed: [1, "two", true, null, undefined],
            nested: [[1, 2], [3, 4], [5, 6]],
            objects: [
                {name: "Alice", age: 25},
                {name: "Bob", age: 30},
                {name: "Charlie", age: 35}
            ],
            emptyArray: [],
            index0: 0,
            index1: 1,
            index2: 2,
            negativeIndex: -1
        };
        
        // 基础数组访问
        var basicArrayExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("numbers"),
            PrattExpression.literal(0)
        );
        _assert(basicArrayExpr.type == PrattExpression.ARRAY_ACCESS, "基础数组访问：类型应该是ARRAY_ACCESS");
        _assert(basicArrayExpr.evaluate(context) == 1, "基础数组访问：numbers[0]应该返回1");
        
        var arrayAccessExpr2:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("numbers"),
            PrattExpression.literal(2)
        );
        _assert(arrayAccessExpr2.evaluate(context) == 3, "数组访问：numbers[2]应该返回3");
        
        var arrayAccessLastExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("numbers"),
            PrattExpression.literal(4)
        );
        _assert(arrayAccessLastExpr.evaluate(context) == 5, "数组访问最后：numbers[4]应该返回5");
        
        // 字符串数组访问
        var stringArrayExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("strings"),
            PrattExpression.literal(1)
        );
        _assert(stringArrayExpr.evaluate(context) == "world", "字符串数组访问：strings[1]应该返回'world'");
        
        // 混合类型数组访问
        var mixedNumExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("mixed"),
            PrattExpression.literal(0)
        );
        _assert(mixedNumExpr.evaluate(context) == 1, "混合数组数字：mixed[0]应该返回1");
        
        var mixedStrExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("mixed"),
            PrattExpression.literal(1)
        );
        _assert(mixedStrExpr.evaluate(context) == "two", "混合数组字符串：mixed[1]应该返回'two'");
        
        var mixedBoolExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("mixed"),
            PrattExpression.literal(2)
        );
        _assert(mixedBoolExpr.evaluate(context) === true, "混合数组布尔：mixed[2]应该返回true");
        
        var mixedNullExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("mixed"),
            PrattExpression.literal(3)
        );
        _assert(mixedNullExpr.evaluate(context) === null, "混合数组null：mixed[3]应该返回null");
        
        var mixedUndefExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("mixed"),
            PrattExpression.literal(4)
        );
        _assert(mixedUndefExpr.evaluate(context) === undefined, "混合数组undefined：mixed[4]应该返回undefined");
        
        // 使用变量作为索引
        var varIndexExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("numbers"),
            PrattExpression.identifier("index1")
        );
        _assert(varIndexExpr.evaluate(context) == 2, "变量索引：numbers[index1]应该返回2");
        
        var varIndexExpr2:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("strings"),
            PrattExpression.identifier("index2")
        );
        _assert(varIndexExpr2.evaluate(context) == "test", "变量索引字符串：strings[index2]应该返回'test'");
        
        // 使用表达式作为索引
        var exprIndexExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("numbers"),
            PrattExpression.binary(PrattExpression.literal(1), "+", PrattExpression.literal(1))
        );
        _assert(exprIndexExpr.evaluate(context) == 3, "表达式索引：numbers[1 + 1]应该返回3");
        
        var exprIndexComplexExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("numbers"),
            PrattExpression.binary(
                PrattExpression.binary(PrattExpression.literal(2), "*", PrattExpression.literal(2)),
                "-",
                PrattExpression.literal(1)
            )
        );
        _assert(exprIndexComplexExpr.evaluate(context) == 4, "复杂表达式索引：numbers[2 * 2 - 1]应该返回4");
        
        // 嵌套数组访问
        var nestedArrayExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.arrayAccess(
                PrattExpression.identifier("nested"),
                PrattExpression.literal(0)
            ),
            PrattExpression.literal(1)
        );
        _assert(nestedArrayExpr.evaluate(context) == 2, "嵌套数组访问：nested[0][1]应该返回2");
        
        var nestedArrayExpr2:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.arrayAccess(
                PrattExpression.identifier("nested"),
                PrattExpression.literal(2)
            ),
            PrattExpression.literal(0)
        );
        _assert(nestedArrayExpr2.evaluate(context) == 5, "嵌套数组访问2：nested[2][0]应该返回5");
        
        // 对象数组的属性访问
        var objArrayPropExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.arrayAccess(
                PrattExpression.identifier("objects"),
                PrattExpression.literal(0)
            ),
            "name"
        );
        _assert(objArrayPropExpr.evaluate(context) == "Alice", "对象数组属性访问：objects[0].name应该返回'Alice'");
        
        var objArrayPropExpr2:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.arrayAccess(
                PrattExpression.identifier("objects"),
                PrattExpression.literal(1)
            ),
            "age"
        );
        _assert(objArrayPropExpr2.evaluate(context) == 30, "对象数组属性访问2：objects[1].age应该返回30");
        
        // 越界访问
        var outOfBoundsExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("numbers"),
            PrattExpression.literal(10)
        );
        _assert(outOfBoundsExpr.evaluate(context) === undefined, "越界访问：numbers[10]应该返回undefined");
        
        var negativeIndexExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("numbers"),
            PrattExpression.literal(-1)
        );
        _assert(negativeIndexExpr.evaluate(context) === undefined, "负索引访问：numbers[-1]应该返回undefined");
        
        // 空数组访问
        var emptyArrayExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("emptyArray"),
            PrattExpression.literal(0)
        );
        _assert(emptyArrayExpr.evaluate(context) === undefined, "空数组访问：emptyArray[0]应该返回undefined");
        
        // 数组访问与其他表达式结合
        var arrayInBinaryExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.arrayAccess(PrattExpression.identifier("numbers"), PrattExpression.literal(0)),
            "+",
            PrattExpression.arrayAccess(PrattExpression.identifier("numbers"), PrattExpression.literal(1))
        );
        _assert(arrayInBinaryExpr.evaluate(context) == 3, "数组访问二元表达式：numbers[0] + numbers[1]应该返回3");
    }
    
    // ============================================================================
    // 测试分组9：复杂嵌套表达式
    // ============================================================================
    private static function testComplexNestedExpressions():Void {
        trace("\n--- 测试分组9：复杂嵌套表达式 ---");
        
        var context:Object = {
            // 数据
            users: [
                {name: "Alice", age: 25, scores: [85, 90, 78]},
                {name: "Bob", age: 30, scores: [92, 88, 95]},
                {name: "Charlie", age: 35, scores: [78, 85, 82]}
            ],
            config: {
                passing: {
                    grade: 80,
                    bonus: 5
                },
                multiplier: 1.1
            },
            
            // 函数
            avg: function(arr) {
                var sum = 0;
                for (var i = 0; i < arr.length; i++) {
                    sum += arr[i];
                }
                return sum / arr.length;
            },
            
            max: function(a, b) {
                return a > b ? a : b;
            },
            
            // 变量
            currentUserIndex: 0,
            bonusThreshold: 90
        };
        
        // 复杂的嵌套属性和数组访问
        var complexAccessExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.propertyAccess(
                PrattExpression.arrayAccess(
                    PrattExpression.identifier("users"),
                    PrattExpression.literal(0)
                ),
                "scores"
            ),
            PrattExpression.literal(1)
        );
        _assert(complexAccessExpr.evaluate(context) == 90, "复杂访问：users[0].scores[1]应该返回90");
        
        // 嵌套函数调用与属性访问
        var nestedFuncAccessExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("avg"),
            [PrattExpression.propertyAccess(
                PrattExpression.arrayAccess(
                    PrattExpression.identifier("users"),
                    PrattExpression.identifier("currentUserIndex")
                ),
                "scores"
            )]
        );
        _assert(Math.abs(nestedFuncAccessExpr.evaluate(context) - 84.33333333333333) < 0.0001, "嵌套函数访问：avg(users[currentUserIndex].scores)应该约等于84.33");
        
        // 复杂的三元表达式
        var complexTernaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.binary(
                PrattExpression.propertyAccess(
                    PrattExpression.arrayAccess(
                        PrattExpression.identifier("users"),
                        PrattExpression.literal(1)
                    ),
                    "age"
                ),
                ">",
                PrattExpression.literal(25)
            ),
            PrattExpression.binary(
                PrattExpression.functionCall(
                    PrattExpression.identifier("avg"),
                    [PrattExpression.propertyAccess(
                        PrattExpression.arrayAccess(
                            PrattExpression.identifier("users"),
                            PrattExpression.literal(1)
                        ),
                        "scores"
                    )]
                ),
                "*",
                PrattExpression.propertyAccess(
                    PrattExpression.identifier("config"),
                    "multiplier"
                )
            ),
            PrattExpression.literal(0)
        );
        // Bob's age (30) > 25, so avg([92, 88, 95]) * 1.1 = 91.666... * 1.1 = 100.833...
        _assert(Math.abs(complexTernaryExpr.evaluate(context) - 100.83333333333333) < 0.0001, "复杂三元表达式应该约等于100.83");
        
        // 多层嵌套的二元表达式
        var multiLevelBinaryExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.binary(
                PrattExpression.functionCall(
                    PrattExpression.identifier("max"),
                    [
                        PrattExpression.arrayAccess(
                            PrattExpression.propertyAccess(
                                PrattExpression.arrayAccess(
                                    PrattExpression.identifier("users"),
                                    PrattExpression.literal(0)
                                ),
                                "scores"
                            ),
                            PrattExpression.literal(0)
                        ),
                        PrattExpression.arrayAccess(
                            PrattExpression.propertyAccess(
                                PrattExpression.arrayAccess(
                                    PrattExpression.identifier("users"),
                                    PrattExpression.literal(0)
                                ),
                                "scores"
                            ),
                            PrattExpression.literal(1)
                        )
                    ]
                ),
                "+",
                PrattExpression.propertyAccess(
                    PrattExpression.propertyAccess(
                        PrattExpression.identifier("config"),
                        "passing"
                    ),
                    "bonus"
                )
            ),
            ">",
            PrattExpression.propertyAccess(
                PrattExpression.propertyAccess(
                    PrattExpression.identifier("config"),
                    "passing"
                ),
                "grade"
            )
        );
        // max(85, 90) + 5 = 95, 95 > 80 = true
        _assert(multiLevelBinaryExpr.evaluate(context) === true, "多层嵌套二元表达式：(max(users[0].scores[0], users[0].scores[1]) + config.passing.bonus) > config.passing.grade应该为true");
        
        // 超复杂表达式：结合所有类型
        var superComplexExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.binary(
                PrattExpression.functionCall(
                    PrattExpression.identifier("avg"),
                    [PrattExpression.propertyAccess(
                        PrattExpression.arrayAccess(
                            PrattExpression.identifier("users"),
                            PrattExpression.ternary(
                                PrattExpression.binary(
                                    PrattExpression.identifier("currentUserIndex"),
                                    "<",
                                    PrattExpression.literal(2)
                                ),
                                PrattExpression.identifier("currentUserIndex"),
                                PrattExpression.literal(2)
                            )
                        ),
                        "scores"
                    )]
                ),
                ">=",
                PrattExpression.identifier("bonusThreshold")
            ),
            PrattExpression.binary(
                PrattExpression.literal("Excellent: "),
                "+",
                PrattExpression.propertyAccess(
                    PrattExpression.arrayAccess(
                        PrattExpression.identifier("users"),
                        PrattExpression.identifier("currentUserIndex")
                    ),
                    "name"
                )
            ),
            PrattExpression.binary(
                PrattExpression.literal("Needs improvement: "),
                "+",
                PrattExpression.propertyAccess(
                    PrattExpression.arrayAccess(
                        PrattExpression.identifier("users"),
                        PrattExpression.identifier("currentUserIndex")
                    ),
                    "name"
                )
            )
        );
        // currentUserIndex < 2 ? currentUserIndex : 2 = 0
        // users[0] = Alice, avg([85, 90, 78]) = 84.33, 84.33 >= 90 = false
        // So return "Needs improvement: Alice"
        _assert(superComplexExpr.evaluate(context) == "Needs improvement: Alice", "超复杂表达式应该返回'Needs improvement: Alice'");
        
        // 深度嵌套的一元表达式
        var deepUnaryExpr:PrattExpression = PrattExpression.unary("!",
            PrattExpression.unary("!",
                PrattExpression.binary(
                    PrattExpression.functionCall(
                        PrattExpression.identifier("avg"),
                        [PrattExpression.propertyAccess(
                            PrattExpression.arrayAccess(
                                PrattExpression.identifier("users"),
                                PrattExpression.literal(1)
                            ),
                            "scores"
                        )]
                    ),
                    ">",
                    PrattExpression.literal(90)
                )
            )
        );
        // avg([92, 88, 95]) = 91.666..., 91.666... > 90 = true, !!true = true
        _assert(deepUnaryExpr.evaluate(context) === true, "深度嵌套一元表达式：!!(avg(users[1].scores) > 90)应该为true");
    }

    // ============================================================================
    // 测试分组10：错误处理 (REVISED)
    // ============================================================================
    private static function testErrorHandling():Void {
        trace("\n--- 测试分组10：错误处理 ---");
        
        var context:Object = {
            x: 10,
            y: 0,
            obj: {prop: "value"},
            nullVar: null,
            undefVar: undefined,
            validFunc: function(a) { return a * 2; },
            notAFunc: "not a function"
        };

        // 未定义变量错误
        _assertThrows(function() { PrattExpression.identifier("nonexistent").evaluate(context); }, "Undefined variable", "未定义变量错误：应该抛出错误");

        // 除零错误
        _assertThrows(function() { PrattExpression.binary(PrattExpression.identifier("x"), "/", PrattExpression.identifier("y")).evaluate(context); }, "Division by zero", "除零错误：应该抛出错误");

        _assertThrows(function() { PrattExpression.binary(PrattExpression.literal(10), "/", PrattExpression.literal(0)).evaluate(context); }, "Division by zero", "直接除零错误：应该抛出错误");

        // null属性访问错误
        _assertThrows(function() { PrattExpression.propertyAccess(PrattExpression.identifier("nullVar"), "property").evaluate(context); }, "Cannot access property", "null属性访问错误：应该抛出错误");

        // undefined属性访问错误
        _assertThrows(function() { PrattExpression.propertyAccess(PrattExpression.identifier("undefVar"), "property").evaluate(context); }, "Cannot access property", "undefined属性访问错误：应该抛出错误");

        // null数组访问错误
        _assertThrows(function() { PrattExpression.arrayAccess(PrattExpression.identifier("nullVar"), PrattExpression.literal(0)).evaluate(context); }, "Cannot access index", "null数组访问错误：应该抛出错误");

        // undefined数组访问错误
        _assertThrows(function() { PrattExpression.arrayAccess(PrattExpression.identifier("undefVar"), PrattExpression.literal(0)).evaluate(context); }, "Cannot access index", "undefined数组访问错误：应该抛出错误");

        // 调用不存在的函数错误
        _assertThrows(function() { PrattExpression.functionCall(PrattExpression.identifier("nonexistentFunc"), []).evaluate(context); }, "Unknown function", "未定义函数错误：应该抛出错误");

        // 调用不是函数的变量
        _assertThrows(function() { PrattExpression.functionCall(PrattExpression.identifier("notAFunc"), []).evaluate(context); }, "is not a function", "非函数调用错误：应该抛出错误");

        // 对象方法不存在错误
        _assertThrows(function() { PrattExpression.functionCall(PrattExpression.propertyAccess(PrattExpression.identifier("obj"), "nonexistentMethod"), []).evaluate(context); }, "Method 'nonexistentMethod' not found", "不存在方法调用错误：应该抛出错误");
        
        // 方法非函数错误
        context.objWithoutMethod = { notAFunction: "I am not a function" };
        _assertThrows(function() { PrattExpression.functionCall(PrattExpression.propertyAccess(PrattExpression.identifier("objWithoutMethod"), "notAFunction"), []).evaluate(context); }, "is not a function", "方法非函数错误：调用非函数属性应该抛出错误");

        // 未知二元运算符错误
        _assertThrows(function() { PrattExpression.binary(PrattExpression.literal(1), "@invalid@", PrattExpression.literal(2)).evaluate(context); }, "Unknown binary operator", "未知二元运算符错误：应该抛出错误");

        // 未知一元运算符错误
        _assertThrows(function() { PrattExpression.unary("@invalid@", PrattExpression.literal(1)).evaluate(context); }, "Unknown unary operator", "未知一元运算符错误：应该抛出错误");

        // 未知表达式类型错误
        _assertThrows(function() { new PrattExpression("INVALID_TYPE").evaluate(context); }, "Unknown expression type", "未知表达式类型错误：应该抛出错误");

        // 测试函数调用中的arguments关键字冲突（这是代码中修复的一个bug）
        context.testArgsFunc = function() {
            var sum = 0;
            for (var i = 0; i < arguments.length; i++) {
                sum += arguments[i];
            }
            return sum;
        };
        var argsTestExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("testArgsFunc"),
            [PrattExpression.literal(1), PrattExpression.literal(2), PrattExpression.literal(3)]
        );
        _assert(argsTestExpr.evaluate(context) == 6, "Arguments关键字测试：函数应该正确处理多个参数");
    }
    
    // ============================================================================
    // 测试分组11：toString方法（调试支持）
    // ============================================================================
    private static function testToStringMethod():Void {
        trace("\n--- 测试分组11：toString方法 ---");
        
        // 字面量toString
        var literalExpr:PrattExpression = PrattExpression.literal(42);
        var literalStr:String = literalExpr.toString();
        _assert(literalStr.indexOf("Literal") >= 0 && literalStr.indexOf("42") >= 0, "字面量toString：应该包含Literal和值");
        
        // 标识符toString
        var identExpr:PrattExpression = PrattExpression.identifier("myVar");
        var identStr:String = identExpr.toString();
        _assert(identStr.indexOf("Identifier") >= 0 && identStr.indexOf("myVar") >= 0, "标识符toString：应该包含Identifier和名称");
        
        // 二元表达式toString
        var binaryExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal(1),
            "+",
            PrattExpression.literal(2)
        );
        var binaryStr:String = binaryExpr.toString();
        _assert(binaryStr.indexOf("Binary") >= 0 && binaryStr.indexOf("+") >= 0 && 
                binaryStr.indexOf("1") >= 0 && binaryStr.indexOf("2") >= 0, 
                "二元表达式toString：应该包含Binary、运算符和操作数");
        
        // 一元表达式toString
        var unaryExpr:PrattExpression = PrattExpression.unary("-", PrattExpression.literal(42));
        var unaryStr:String = unaryExpr.toString();
        _assert(unaryStr.indexOf("Unary") >= 0 && unaryStr.indexOf("-") >= 0 && unaryStr.indexOf("42") >= 0,
                "一元表达式toString：应该包含Unary、运算符和操作数");
        
        // 三元表达式toString
        var ternaryExpr:PrattExpression = PrattExpression.ternary(
            PrattExpression.literal(true),
            PrattExpression.literal("yes"),
            PrattExpression.literal("no")
        );
        var ternaryStr:String = ternaryExpr.toString();
        _assert(ternaryStr.indexOf("Ternary") >= 0 && ternaryStr.indexOf("?") >= 0 && ternaryStr.indexOf(":") >= 0,
                "三元表达式toString：应该包含Ternary、?和:");
        
        // 函数调用toString
        var funcCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("func"),
            [PrattExpression.literal(1), PrattExpression.literal(2)]
        );
        var funcCallStr:String = funcCallExpr.toString();
        _assert(funcCallStr.indexOf("FunctionCall") >= 0 && funcCallStr.indexOf("func") >= 0,
                "函数调用toString：应该包含FunctionCall和函数名");
        
        // 属性访问toString
        var propExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("obj"),
            "prop"
        );
        var propStr:String = propExpr.toString();
        _assert(propStr.indexOf("PropertyAccess") >= 0 && propStr.indexOf("obj") >= 0 && propStr.indexOf("prop") >= 0,
                "属性访问toString：应该包含PropertyAccess、对象和属性名");
        
        // 数组访问toString
        var arrayExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("arr"),
            PrattExpression.literal(0)
        );
        var arrayStr:String = arrayExpr.toString();
        _assert(arrayStr.indexOf("ArrayAccess") >= 0 && arrayStr.indexOf("arr") >= 0,
                "数组访问toString：应该包含ArrayAccess和数组名");
        
        // 复杂嵌套表达式toString
        var complexExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.functionCall(
                PrattExpression.identifier("func"),
                [PrattExpression.literal(1)]
            ),
            "+",
            PrattExpression.propertyAccess(
                PrattExpression.identifier("obj"),
                "prop"
            )
        );
        var complexStr:String = complexExpr.toString();
        _assert(complexStr.indexOf("Binary") >= 0 && complexStr.indexOf("FunctionCall") >= 0 && 
                complexStr.indexOf("PropertyAccess") >= 0,
                "复杂嵌套toString：应该包含所有表达式类型");
        
        // 测试toString的可读性和层次结构
        var nestedBinaryExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.binary(
                PrattExpression.literal(1),
                "+",
                PrattExpression.literal(2)
            ),
            "*",
            PrattExpression.literal(3)
        );
        var nestedStr:String = nestedBinaryExpr.toString();
        // 验证嵌套结构在字符串中是可见的
        _assert(nestedStr.indexOf("[Binary:") >= 0, "嵌套二元toString：应该显示嵌套的二元表达式结构");
    }
    
    // ============================================================================
    // 测试分组12：边界条件
    // ============================================================================
    private static function testBoundaryConditions():Void {
        trace("\n--- 测试分组12：边界条件 ---");
        
        var context:Object = {
            // 极值数据
            maxNumber: Number.MAX_VALUE,
            minNumber: Number.MIN_VALUE,
            infinity: Number.POSITIVE_INFINITY,
            negInfinity: Number.NEGATIVE_INFINITY,
            notANumber: Number.NaN,
            
            // 特殊字符串
            emptyString: "",
            longString: createLongString(),
            specialChars: "\n\t\r\\\"'",
            
            // 边界数组
            emptyArray: [],
            singleItemArray: [42],
            largeArray: createLargeArray(),
            
            // 深度嵌套对象
            deepObj: createDeepObject(),
            
            // 特殊函数
            identityFunc: function(x) { return x; },
            multiReturnFunc: function() { 
                if (arguments.length == 0) return null;
                if (arguments.length == 1) return arguments[0];
                return arguments;
            }
        };
        
        // 极大数值运算
        var maxNumberExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("maxNumber"),
            "+",
            PrattExpression.literal(1)
        );
        var maxResult = maxNumberExpr.evaluate(context);
        _assert(typeof maxResult == "number", "极大数值运算：结果应该仍然是数字类型");
        
        // 无穷大运算
        var infinityExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("infinity"),
            "+",
            PrattExpression.literal(1000)
        );
        _assert(infinityExpr.evaluate(context) == Number.POSITIVE_INFINITY, "无穷大运算：结果应该仍然是正无穷");
        
        var negInfinityExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("negInfinity"),
            "*",
            PrattExpression.literal(-1)
        );
        _assert(negInfinityExpr.evaluate(context) == Number.POSITIVE_INFINITY, "负无穷运算：-(-∞)应该是正无穷");
        
        // NaN运算
        var nanExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("notANumber"),
            "+",
            PrattExpression.literal(42)
        );
        var nanResult = nanExpr.evaluate(context);
        _assert(isNaN(nanResult), "NaN运算：NaN + 42应该仍然是NaN");
        
        // NaN比较
        var nanCompareExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("notANumber"),
            "==",
            PrattExpression.identifier("notANumber")
        );
        _assert(nanCompareExpr.evaluate(context) === false, "NaN比较：NaN == NaN应该为false");
        
        // 极小数值运算
        var minNumberExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("minNumber"),
            "/",
            PrattExpression.literal(2)
        );
        var minResult = minNumberExpr.evaluate(context);
        _assert(typeof minResult == "number", "极小数值运算：结果应该仍然是数字类型");
        
        // 空字符串运算
        var emptyStringExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("emptyString"),
            "+",
            PrattExpression.literal("test")
        );
        _assert(emptyStringExpr.evaluate(context) == "test", "空字符串运算：'' + 'test'应该等于'test'");
        
        // 超长字符串处理
        var longStringExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.identifier("longString"),
            "+",
            PrattExpression.literal("suffix")
        );
        var longResult = longStringExpr.evaluate(context);
        _assert(typeof longResult == "string" && longResult.length > 1000, "超长字符串运算：应该正确处理长字符串连接");
        
        // 特殊字符处理
        var specialCharsExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("specialChars"),
            "length"
        );
        _assert(specialCharsExpr.evaluate(context) == 6, "特殊字符处理：特殊字符字符串长度应该正确");
        
        // 空数组访问
        var emptyArrayLengthExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("emptyArray"),
            "length"
        );
        _assert(emptyArrayLengthExpr.evaluate(context) == 0, "空数组访问：空数组长度应该为0");
        
        // 单元素数组
        var singleArrayExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("singleItemArray"),
            PrattExpression.literal(0)
        );
        _assert(singleArrayExpr.evaluate(context) == 42, "单元素数组：应该正确访问唯一元素");
        
        // 大数组处理
        var largeArrayExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.identifier("largeArray"),
            "length"
        );
        _assert(largeArrayExpr.evaluate(context) >= 1000, "大数组处理：大数组长度应该正确");
        
        // 深度嵌套对象访问
        var deepObjExpr:PrattExpression = PrattExpression.propertyAccess(
            PrattExpression.propertyAccess(
                PrattExpression.propertyAccess(
                    PrattExpression.propertyAccess(
                        PrattExpression.propertyAccess(
                            PrattExpression.identifier("deepObj"),
                            "level1"
                        ),
                        "level2"
                    ),
                    "level3"
                ),
                "level4"
            ),
            "value"
        );
        _assert(deepObjExpr.evaluate(context) == "deep", "深度嵌套对象：应该能访问深层属性");
        
        // 函数参数边界情况
        var noArgsCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("multiReturnFunc"),
            []
        );
        _assert(noArgsCallExpr.evaluate(context) === null, "无参数函数调用：应该返回null");
        
        var singleArgCallExpr:PrattExpression = PrattExpression.functionCall(
            PrattExpression.identifier("multiReturnFunc"),
            [PrattExpression.literal(42)]
        );
        _assert(singleArgCallExpr.evaluate(context) == 42, "单参数函数调用：应该返回该参数");
        
        // 类型转换边界情况
        var typeConversionExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal("10"),
            "+",
            PrattExpression.literal(5)
        );
        _assert(typeConversionExpr.evaluate(context) == 15, "类型转换：字符串数字应该正确转换并相加");
        
        var stringNumberCompareExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal("10"),
            "==",
            PrattExpression.literal(10)
        );
        _assert(stringNumberCompareExpr.evaluate(context) === true, "字符串数字比较：'10' == 10应该为true");
        
        var strictStringNumberCompareExpr:PrattExpression = PrattExpression.binary(
            PrattExpression.literal("10"),
            "===",
            PrattExpression.literal(10)
        );
        _assert(strictStringNumberCompareExpr.evaluate(context) === false, "严格字符串数字比较：'10' === 10应该为false");
        
        // 复杂的falsy值测试
        var falsyValues:Array = [false, 0, "", null, undefined];
        for (var i:Number = 0; i < falsyValues.length; i++) {
            var falsyExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(falsyValues[i]));
            _assert(falsyExpr.evaluate(context) === true, "Falsy值测试：!" + falsyValues[i] + "应该为true");
        }
        
        // 复杂的truthy值测试
        var truthyValues:Array = [true, 1, "hello", [], {}];
        for (var j:Number = 0; j < truthyValues.length; j++) {
            var truthyExpr:PrattExpression = PrattExpression.unary("!", PrattExpression.literal(truthyValues[j]));
            _assert(truthyExpr.evaluate(context) === false, "Truthy值测试：!" + truthyValues[j] + "应该为false");
        }
        
        // 零和负零的处理
        var positiveZeroExpr:PrattExpression = PrattExpression.literal(0);
        var negativeZeroExpr:PrattExpression = PrattExpression.literal(-0);
        _assert(positiveZeroExpr.evaluate(context) === negativeZeroExpr.evaluate(context), "零值比较：0应该等于-0");
        
        // 非常大的数组索引
        var largeIndexExpr:PrattExpression = PrattExpression.arrayAccess(
            PrattExpression.identifier("singleItemArray"),
            PrattExpression.literal(999999)
        );
        _assert(largeIndexExpr.evaluate(context) === undefined, "大索引访问：访问超大索引应该返回undefined");
    }
    
    // ============================================================================
    // 辅助函数
    // ============================================================================
    private static function createLongString():String {
        var str:String = "";
        for (var i:Number = 0; i < 1000; i++) {
            str += "a";
        }
        return str;
    }
    
    private static function createLargeArray():Array {
        var arr:Array = [];
        for (var i:Number = 0; i < 1000; i++) {
            arr.push(i);
        }
        return arr;
    }
    
    private static function createDeepObject():Object {
        return {
            level1: {
                level2: {
                    level3: {
                        level4: {
                            value: "deep"
                        }
                    }
                }
            }
        };
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