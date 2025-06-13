import org.flashNight.gesh.pratt.*;

/**
 * PrattToken 100%覆盖测试套件
 * 
 * 测试策略：
 * 1. 构造函数的所有分支和类型转换逻辑
 * 2. 所有辅助方法的正确和错误情况  
 * 3. 边界情况和异常处理
 * 4. 字符串表示和错误信息格式
 */
class org.flashNight.gesh.pratt.PrattToken_TestSuite {
    
    private static var _testCount:Number = 0;
    private static var _passCount:Number = 0;
    private static var _failCount:Number = 0;
    
    public static function runAllTests():Void {
        trace("========== PrattToken 100%覆盖测试开始 ==========");
        
        _testCount = 0;
        _passCount = 0;
        _failCount = 0;
        
        // 按逻辑分组运行测试
        testConstructorBasics();
        testValueAutoConversion();
        testManualValueOverride();  
        testPositionTracking();
        testTypeChecking();
        testValueGetters();
        testErrorHandling();
        testStringRepresentation();
        testBoundaryConditions();
        
        // 输出测试结果
        trace("\n========== PrattToken 测试结果 ==========");
        trace("总计: " + _testCount + " 个测试");
        trace("通过: " + _passCount + " 个");
        trace("失败: " + _failCount + " 个");
        trace("覆盖率: " + Math.round((_passCount / _testCount) * 100) + "%");
        
        if (_failCount == 0) {
            trace("✅ PrattToken 所有测试通过！");
        } else {
            trace("❌ 存在 " + _failCount + " 个失败的测试");
        }
        trace("==========================================");
    }
    
    // ============================================================================
    // 测试分组1：构造函数基础功能
    // ============================================================================
    private static function testConstructorBasics():Void {
        trace("\n--- 测试分组1：构造函数基础功能 ---");
        
        // 测试最基本的构造
        var token1:PrattToken = new PrattToken("IDENTIFIER", "myVar", 1, 5);
        _assert(token1.type == "IDENTIFIER", "基础构造：type应该正确设置");
        _assert(token1.text == "myVar", "基础构造：text应该正确设置");
        _assert(token1.line == 1, "基础构造：line应该正确设置");
        _assert(token1.column == 5, "基础构造：column应该正确设置");
        
        // 测试所有Token类型常量的构造
        var types:Array = [
            PrattToken.T_EOF, PrattToken.T_NUMBER, PrattToken.T_IDENTIFIER, 
            PrattToken.T_STRING, PrattToken.T_BOOLEAN, PrattToken.T_NULL, 
            PrattToken.T_UNDEFINED, PrattToken.T_OPERATOR, PrattToken.T_LPAREN,
            PrattToken.T_RPAREN, PrattToken.T_COMMA, PrattToken.T_DOT
        ];
        
        for (var i:Number = 0; i < types.length; i++) {
            var token:PrattToken = new PrattToken(types[i], "test", 0, 0);
            _assert(token.type == types[i], "所有Token类型构造：" + types[i] + "应该正确设置");
        }
    }
    
    // ============================================================================
    // 测试分组2：值的自动转换逻辑（核心逻辑）
    // ============================================================================
    private static function testValueAutoConversion():Void {
        trace("\n--- 测试分组2：值的自动转换逻辑 ---");
        
        // T_NUMBER 类型的自动转换
        var intToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "123", 0, 0);
        _assert(intToken.value == 123, "T_NUMBER整数：value应该转换为数字123");
        _assert(typeof intToken.value == "number", "T_NUMBER整数：value类型应该是number");
        
        var floatToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "123.45", 0, 0);
        _assert(floatToken.value == 123.45, "T_NUMBER浮点数：value应该转换为123.45");
        _assert(typeof floatToken.value == "number", "T_NUMBER浮点数：value类型应该是number");
        
        var zeroToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "0", 0, 0);
        _assert(zeroToken.value == 0, "T_NUMBER零：value应该转换为0");
        
        var negativeToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "-42", 0, 0);
        _assert(negativeToken.value == -42, "T_NUMBER负数：value应该转换为-42");
        
        // T_BOOLEAN 类型的自动转换
        var trueToken:PrattToken = new PrattToken(PrattToken.T_BOOLEAN, "true", 0, 0);
        _assert(trueToken.value === true, "T_BOOLEAN真值：value应该转换为true");
        _assert(typeof trueToken.value == "boolean", "T_BOOLEAN真值：value类型应该是boolean");
        
        var falseToken:PrattToken = new PrattToken(PrattToken.T_BOOLEAN, "false", 0, 0);
        _assert(falseToken.value === false, "T_BOOLEAN假值：value应该转换为false");
        _assert(typeof falseToken.value == "boolean", "T_BOOLEAN假值：value类型应该是boolean");
        
        // T_NULL 类型的自动转换
        var nullToken:PrattToken = new PrattToken(PrattToken.T_NULL, "null", 0, 0);
        _assert(nullToken.value === null, "T_NULL：value应该转换为null");
        
        // T_UNDEFINED 类型的自动转换
        var undefinedToken:PrattToken = new PrattToken(PrattToken.T_UNDEFINED, "undefined", 0, 0);
        _assert(undefinedToken.value === undefined, "T_UNDEFINED：value应该转换为undefined");
        
        // 其他类型应该保持text值
        var identifierToken:PrattToken = new PrattToken(PrattToken.T_IDENTIFIER, "myVar", 0, 0);
        _assert(identifierToken.value == "myVar", "T_IDENTIFIER：value应该等于text");
        
        var operatorToken:PrattToken = new PrattToken(PrattToken.T_OPERATOR, "+", 0, 0);
        _assert(operatorToken.value == "+", "T_OPERATOR：value应该等于text");
    }
    
    // ============================================================================
    // 测试分组3：手动值覆盖
    // ============================================================================
    private static function testManualValueOverride():Void {
        trace("\n--- 测试分组3：手动值覆盖 ---");
        
        // 当显式传入tokenValue时，应该覆盖自动转换
        var numberToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "123", 0, 0, 999);
        _assert(numberToken.value == 999, "手动值覆盖：显式传入的value应该覆盖自动转换");
        
        var booleanToken:PrattToken = new PrattToken(PrattToken.T_BOOLEAN, "true", 0, 0, "custom");
        _assert(booleanToken.value == "custom", "手动值覆盖：即使是布尔类型也应该被覆盖");
        
        // 传入null和undefined作为显式值
        var explicitNull:PrattToken = new PrattToken(PrattToken.T_STRING, "test", 0, 0, null);
        _assert(explicitNull.value === null, "手动值覆盖：显式传入null应该保留");
        
        var explicitUndef:PrattToken = new PrattToken(PrattToken.T_STRING, "test", 0, 0, undefined);
        _assert(explicitUndef.value === undefined, "手动值覆盖：显式传入undefined应该保留");
        
        // 传入0作为显式值（测试falsy值）
        var explicitZero:PrattToken = new PrattToken(PrattToken.T_STRING, "test", 0, 0, 0);
        _assert(explicitZero.value === 0, "手动值覆盖：显式传入0应该保留");
    }
    
    // ============================================================================
    // 测试分组4：位置跟踪
    // ============================================================================
    private static function testPositionTracking():Void {
        trace("\n--- 测试分组4：位置跟踪 ---");
        
        // 测试位置参数的默认值
        var tokenNoPos:PrattToken = new PrattToken("TEST", "test");
        _assert(tokenNoPos.line == 0, "位置默认值：line应该默认为0");
        _assert(tokenNoPos.column == 0, "位置默认值：column应该默认为0");
        
        // 测试各种位置值
        var positions:Array = [
            {line: 1, column: 1},
            {line: 999, column: 999},
            {line: 0, column: 0},
            {line: -1, column: -1}  // 边界情况：负数位置
        ];
        
        for (var i:Number = 0; i < positions.length; i++) {
            var pos = positions[i];
            var token:PrattToken = new PrattToken("TEST", "test", pos.line, pos.column);
            _assert(token.line == pos.line, "位置跟踪：line=" + pos.line + "应该正确设置");
            _assert(token.column == pos.column, "位置跟踪：column=" + pos.column + "应该正确设置");
        }
    }
    
    // ============================================================================
    // 测试分组5：类型检查方法
    // ============================================================================
    private static function testTypeChecking():Void {
        trace("\n--- 测试分组5：类型检查方法 ---");
        
        // 测试is()方法
        var numberToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "123", 0, 0);
        _assert(numberToken.is(PrattToken.T_NUMBER) == true, "is()方法：应该正确识别匹配的类型");
        _assert(numberToken.is(PrattToken.T_STRING) == false, "is()方法：应该正确识别不匹配的类型");
        _assert(numberToken.is("NONEXISTENT") == false, "is()方法：应该正确处理不存在的类型");
        
        // 测试isLiteral()方法 - 所有字面量类型
        var literalTypes:Array = [
            PrattToken.T_NUMBER, PrattToken.T_STRING, PrattToken.T_BOOLEAN, 
            PrattToken.T_NULL, PrattToken.T_UNDEFINED
        ];
        
        for (var i:Number = 0; i < literalTypes.length; i++) {
            var literalToken:PrattToken = new PrattToken(literalTypes[i], "test", 0, 0);
            _assert(literalToken.isLiteral() == true, "isLiteral()方法：" + literalTypes[i] + "应该被识别为字面量");
        }
        
        // 测试isLiteral()方法 - 非字面量类型
        var nonLiteralTypes:Array = [
            PrattToken.T_IDENTIFIER, PrattToken.T_OPERATOR, PrattToken.T_LPAREN, 
            PrattToken.T_EOF, PrattToken.T_COMMA
        ];
        
        for (var j:Number = 0; j < nonLiteralTypes.length; j++) {
            var nonLiteralToken:PrattToken = new PrattToken(nonLiteralTypes[j], "test", 0, 0);
            _assert(nonLiteralToken.isLiteral() == false, "isLiteral()方法：" + nonLiteralTypes[j] + "不应该被识别为字面量");
        }
    }
    
    // ============================================================================
    // 测试分组6：值获取方法（包括错误情况）
    // ============================================================================
    private static function testValueGetters():Void {
        trace("\n--- 测试分组6：值获取方法 ---");
        
        // 测试getNumberValue() - 正确情况
        var numberToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "123.45", 0, 0);
        var numberValue:Number = numberToken.getNumberValue();
        _assert(numberValue == 123.45, "getNumberValue()正确：应该返回正确的数字值");
        _assert(typeof numberValue == "number", "getNumberValue()正确：返回值类型应该是number");
        
        // 测试getNumberValue() - 错误情况
        var stringToken:PrattToken = new PrattToken(PrattToken.T_STRING, "hello", 0, 0);
        var numberError:Boolean = false;
        try {
            stringToken.getNumberValue();
        } catch (e) {
            numberError = true;
            _assert(e.message.indexOf("不是数字类型") >= 0, "getNumberValue()错误：错误信息应该包含类型提示");
        }
        _assert(numberError == true, "getNumberValue()错误：非数字Token应该抛出错误");
        
        // 测试getStringValue() - 正确情况
        var stringToken2:PrattToken = new PrattToken(PrattToken.T_STRING, "test", 0, 0, "actual_value");
        var stringValue:String = stringToken2.getStringValue();
        _assert(stringValue == "actual_value", "getStringValue()正确：应该返回正确的字符串值");
        _assert(typeof stringValue == "string", "getStringValue()正确：返回值类型应该是string");
        
        // 测试getStringValue() - 错误情况
        var stringError:Boolean = false;
        try {
            numberToken.getStringValue();
        } catch (e) {
            stringError = true;
            _assert(e.message.indexOf("不是字符串类型") >= 0, "getStringValue()错误：错误信息应该包含类型提示");
        }
        _assert(stringError == true, "getStringValue()错误：非字符串Token应该抛出错误");
        
        // 测试getBooleanValue() - 正确情况
        var boolToken:PrattToken = new PrattToken(PrattToken.T_BOOLEAN, "true", 0, 0);
        var boolValue:Boolean = boolToken.getBooleanValue();
        _assert(boolValue === true, "getBooleanValue()正确：应该返回正确的布尔值");
        _assert(typeof boolValue == "boolean", "getBooleanValue()正确：返回值类型应该是boolean");
        
        // 测试getBooleanValue() - 错误情况
        var boolError:Boolean = false;
        try {
            numberToken.getBooleanValue();
        } catch (e) {
            boolError = true;
            _assert(e.message.indexOf("不是布尔类型") >= 0, "getBooleanValue()错误：错误信息应该包含类型提示");
        }
        _assert(boolError == true, "getBooleanValue()错误：非布尔Token应该抛出错误");
    }
    
    // ============================================================================
    // 测试分组7：错误处理和消息格式
    // ============================================================================
    private static function testErrorHandling():Void {
        trace("\n--- 测试分组7：错误处理和消息格式 ---");
        
        // 测试createError()方法的格式
        var token:PrattToken = new PrattToken(PrattToken.T_IDENTIFIER, "myVar", 5, 10);
        var errorMsg:String = token.createError("Test error message");
        
        _assert(errorMsg.indexOf("Test error message") >= 0, "createError()格式：应该包含错误消息");
        _assert(errorMsg.indexOf("line 5") >= 0, "createError()格式：应该包含行号");
        _assert(errorMsg.indexOf("column 10") >= 0, "createError()格式：应该包含列号");
        _assert(errorMsg.indexOf("myVar") >= 0, "createError()格式：应该包含token文本");
        
        // 测试不同位置的错误信息
        var token0:PrattToken = new PrattToken(PrattToken.T_EOF, "<eof>", 0, 0);
        var error0:String = token0.createError("EOF error");
        _assert(error0.indexOf("line 0") >= 0, "createError()边界：应该正确处理0位置");
        
        var tokenLarge:PrattToken = new PrattToken(PrattToken.T_OPERATOR, "+", 9999, 9999);
        var errorLarge:String = tokenLarge.createError("Large position");
        _assert(errorLarge.indexOf("line 9999") >= 0, "createError()边界：应该正确处理大位置值");
        
        // 测试空消息
        var emptyError:String = token.createError("");
        _assert(emptyError.indexOf("line 5") >= 0, "createError()空消息：即使消息为空也应该包含位置信息");
    }
    
    // ============================================================================
    // 测试分组8：字符串表示（toString方法）
    // ============================================================================
    private static function testStringRepresentation():Void {
        trace("\n--- 测试分组8：字符串表示 ---");
        
        // 基础toString测试
        var simpleToken:PrattToken = new PrattToken(PrattToken.T_IDENTIFIER, "myVar", 1, 5);
        var simpleStr:String = simpleToken.toString();
        _assert(simpleStr.indexOf("IDENTIFIER") >= 0, "toString()基础：应该包含类型");
        _assert(simpleStr.indexOf("myVar") >= 0, "toString()基础：应该包含文本");
        _assert(simpleStr.indexOf("@1:5") >= 0, "toString()基础：应该包含位置信息");
        
        // 测试value与text不同时的toString
        var numberToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "123", 0, 0);
        var numberStr:String = numberToken.toString();
        _assert(numberStr.indexOf("123") >= 0, "toString()值转换：应该包含原始文本");
        _assert(numberStr.indexOf("= 123") >= 0, "toString()值转换：应该显示转换后的值");
        
        // 测试null值的toString
        var nullToken:PrattToken = new PrattToken(PrattToken.T_NULL, "null", 0, 0);
        var nullStr:String = nullToken.toString();
        _assert(nullStr.indexOf("NULL") >= 0, "toString()null：应该包含NULL类型");
        
        // 测试没有位置信息的toString
        var noPositionToken:PrattToken = new PrattToken(PrattToken.T_OPERATOR, "+");
        var noPositionStr:String = noPositionToken.toString();
        _assert(noPositionStr.indexOf("OPERATOR") >= 0, "toString()无位置：应该包含类型");
        _assert(noPositionStr.indexOf("+") >= 0, "toString()无位置：应该包含文本");
        
        // 测试复杂情况：手动值与特殊字符
        var complexToken:PrattToken = new PrattToken(PrattToken.T_STRING, "\"hello\"", 2, 8, "hello");
        var complexStr:String = complexToken.toString();
        _assert(complexStr.indexOf("STRING") >= 0, "toString()复杂：应该包含类型");
        _assert(complexStr.indexOf("\"hello\"") >= 0, "toString()复杂：应该包含原始文本");
        _assert(complexStr.indexOf("= hello") >= 0, "toString()复杂：应该显示实际值");
        _assert(complexStr.indexOf("@2:8") >= 0, "toString()复杂：应该包含位置");
    }
    
    // ============================================================================
    // 测试分组9：边界条件和异常情况
    // ============================================================================
    private static function testBoundaryConditions():Void {
        trace("\n--- 测试分组9：边界条件和异常情况 ---");
        
        // 测试空字符串和null
        var emptyToken:PrattToken = new PrattToken(PrattToken.T_STRING, "", 0, 0);
        _assert(emptyToken.text == "", "边界条件：应该正确处理空字符串");
        _assert(emptyToken.value == "", "边界条件：空字符串的value应该也是空字符串");
        
        // 测试特殊字符
        var specialToken:PrattToken = new PrattToken(PrattToken.T_STRING, "\n\t\r\\\"", 0, 0);
        _assert(specialToken.text == "\n\t\r\\\"", "边界条件：应该正确处理特殊字符");
        
        // 测试超长字符串
        var longText:String = "";
        for (var i:Number = 0; i < 1000; i++) {
            longText += "a";
        }
        var longToken:PrattToken = new PrattToken(PrattToken.T_IDENTIFIER, longText, 0, 0);
        _assert(longToken.text.length == 1000, "边界条件：应该正确处理超长字符串");
        
        // 测试数字边界值
        var maxNumberToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "999999999999999", 0, 0);
        _assert(typeof maxNumberToken.value == "number", "边界条件：超大数字应该仍然是number类型");
        
        var scientificToken:PrattToken = new PrattToken(PrattToken.T_NUMBER, "1.23e-10", 0, 0);
        _assert(scientificToken.value == 1.23e-10, "边界条件：应该正确处理科学计数法");
        
        // 测试undefined和null作为参数的边界情况
        var undefTextToken:PrattToken = new PrattToken(PrattToken.T_IDENTIFIER, undefined, 0, 0);
        _assert(undefTextToken.text === undefined, "边界条件：应该接受undefined作为text");
        
        // 测试类型检查的边界情况
        _assert(emptyToken.is("") == false, "边界条件：空字符串类型检查应该返回false");
        _assert(emptyToken.is(null) == false, "边界条件：null类型检查应该返回false");
        _assert(emptyToken.is(undefined) == false, "边界条件：undefined类型检查应该返回false");
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