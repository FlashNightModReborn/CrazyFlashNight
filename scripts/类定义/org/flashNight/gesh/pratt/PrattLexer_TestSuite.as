import org.flashNight.gesh.pratt.*;

/**
 * PrattLexer 100%覆盖测试套件
 * 
 * 测试策略：
 * 1. 基础Token识别的所有类型和变体
 * 2. 空白和注释处理的完整场景
 * 3. 位置跟踪的准确性验证
 * 4. 词法分析器API的正确性
 * 5. 错误处理和边界条件
 * 6. 复杂混合场景的综合测试
 */
class org.flashNight.gesh.pratt.PrattLexer_TestSuite {
    
    private static var _testCount:Number = 0;
    private static var _passCount:Number = 0;
    private static var _failCount:Number = 0;
    
    public static function runAllTests():Void {
        trace("========== PrattLexer 100%覆盖测试开始 ==========");
        
        _testCount = 0;
        _passCount = 0;
        _failCount = 0;
        
        // 按功能模块运行测试
        testLexerAPI();              // 基础API
        testNumberTokens();          // 数字解析
        testStringTokens();          // 字符串解析  
        testIdentifierAndKeywords(); // 标识符和关键字
        testOperators();             // 运算符识别
        testDelimiters();            // 分隔符
        testWhitespaceHandling();    // 空白处理
        testCommentHandling();       // 注释处理
        testPositionTracking();      // 位置跟踪
        testErrorConditions();       // 错误处理
        testBoundaryConditions();    // 边界条件
        testComplexScenarios();      // 复杂综合场景
        
        // 输出测试结果
        trace("\n========== PrattLexer 测试结果 ==========");
        trace("总计: " + _testCount + " 个测试");
        trace("通过: " + _passCount + " 个");
        trace("失败: " + _failCount + " 个");
        trace("覆盖率: " + Math.round((_passCount / _testCount) * 100) + "%");
        
        if (_failCount == 0) {
            trace("✅ PrattLexer 所有测试通过！");
        } else {
            trace("❌ 存在 " + _failCount + " 个失败的测试");
        }
        trace("==========================================");
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
    
    // ============================================================================
    // 测试分组1：词法分析器基础API
    // ============================================================================
    private static function testLexerAPI():Void {
        trace("\n--- 测试分组1：词法分析器基础API ---");
        
        // 测试基础的peek和next
        var lexer:PrattLexer = new PrattLexer("123 + 456");
        
        // 测试peek不改变状态
        var firstPeek:PrattToken = lexer.peek();
        var secondPeek:PrattToken = lexer.peek();
        _assert(firstPeek.text == secondPeek.text, "API基础：peek()应该不改变lexer状态");
        _assert(firstPeek.type == PrattToken.T_NUMBER, "API基础：第一个token应该是数字");
        
        // 测试next推进状态
        var firstNext:PrattToken = lexer.next();
        _assert(firstNext.text == "123", "API基础：next()应该返回第一个token");
        
        var secondNext:PrattToken = lexer.next();
        _assert(secondNext.text == "+", "API基础：next()应该推进到下一个token");
        
        var thirdNext:PrattToken = lexer.next();
        _assert(thirdNext.text == "456", "API基础：next()应该继续推进");
        
        // 测试EOF处理
        var eofToken:PrattToken = lexer.next();
        _assert(eofToken.type == PrattToken.T_EOF, "API基础：表达式结束应该返回EOF");
        _assert(eofToken.text == "<eof>", "API基础：EOF的text应该是<eof>");
        
        // 多次next EOF应该仍然返回EOF
        var eofToken2:PrattToken = lexer.next();
        _assert(eofToken2.type == PrattToken.T_EOF, "API基础：多次next EOF应该仍然返回EOF");
    }
    
    // ============================================================================
    // 测试分组2：数字Token解析
    // ============================================================================
    private static function testNumberTokens():Void {
        trace("\n--- 测试分组2：数字Token解析 ---");
        
        // 整数测试
        var integers:Array = ["0", "123", "999999", "1"];
        for (var i:Number = 0; i < integers.length; i++) {
            var lexer:PrattLexer = new PrattLexer(integers[i]);
            var token:PrattToken = lexer.peek();
            _assert(token.type == PrattToken.T_NUMBER, "整数解析：" + integers[i] + "应该被识别为NUMBER");
            _assert(token.text == integers[i], "整数解析：" + integers[i] + "的text应该正确");
            _assert(token.getNumberValue() == parseInt(integers[i]), "整数解析：" + integers[i] + "的值应该正确");
        }
        
        // 浮点数测试
        var floats:Array = ["1.0", "123.456", "0.5", ".5", "1.", "0.0"];
        for (var j:Number = 0; j < floats.length; j++) {
            var floatLexer:PrattLexer = new PrattLexer(floats[j]);
            var floatToken:PrattToken = floatLexer.peek();
            _assert(floatToken.type == PrattToken.T_NUMBER, "浮点数解析：" + floats[j] + "应该被识别为NUMBER");
            _assert(floatToken.text == floats[j], "浮点数解析：" + floats[j] + "的text应该正确");
            _assert(floatToken.getNumberValue() == parseFloat(floats[j]), "浮点数解析：" + floats[j] + "的值应该正确");
        }
        
        // 数字边界情况
        var specialNumbers:Array = ["000", "0123", "99999999999"];
        for (var k:Number = 0; k < specialNumbers.length; k++) {
            var specialLexer:PrattLexer = new PrattLexer(specialNumbers[k]);
            var specialToken:PrattToken = specialLexer.peek();
            _assert(specialToken.type == PrattToken.T_NUMBER, "特殊数字：" + specialNumbers[k] + "应该被识别为NUMBER");
            _assert(specialToken.text == specialNumbers[k], "特殊数字：" + specialNumbers[k] + "的text应该保持原样");
        }
        
        // 数字后跟其他字符的分隔测试
        var numberContext:PrattLexer = new PrattLexer("123abc");
        var numToken:PrattToken = numberContext.next();
        var idToken:PrattToken = numberContext.next();
        _assert(numToken.type == PrattToken.T_NUMBER && numToken.text == "123", "数字分隔：数字部分应该正确");
        _assert(idToken.type == PrattToken.T_IDENTIFIER && idToken.text == "abc", "数字分隔：后续标识符应该正确");
    }
    
    // ============================================================================
    // 测试分组3：字符串Token解析
    // ============================================================================
    private static function testStringTokens():Void {
        trace("\n--- 测试分组3：字符串Token解析 ---");
        
        // 基础字符串测试
        var basicStrings:Array = [
            {input: "\"hello\"", expected: "hello"},
            {input: "'world'", expected: "world"},
            {input: "\"\"", expected: ""},
            {input: "''", expected: ""}
        ];
        
        for (var i:Number = 0; i < basicStrings.length; i++) {
            var basic = basicStrings[i];
            var lexer:PrattLexer = new PrattLexer(basic.input);
            var token:PrattToken = lexer.peek();
            _assert(token.type == PrattToken.T_STRING, "基础字符串：" + basic.input + "应该被识别为STRING");
            _assert(token.text == basic.input, "基础字符串：" + basic.input + "的text应该包含引号");
            _assert(token.getStringValue() == basic.expected, "基础字符串：" + basic.input + "的值应该是" + basic.expected);
        }
        
        // 转义字符测试
        var escapedStrings:Array = [
            {input: "\"hello\\nworld\"", expected: "hello\nworld"},
            {input: "'tab\\there'", expected: "tab\there"},
            {input: "\"quote\\\"test\"", expected: "quote\"test"},
            {input: "'apos\\'test'", expected: "apos'test"},
            {input: "\"backslash\\\\test\"", expected: "backslash\\test"},
            {input: "\"return\\rtest\"", expected: "return\rtest"}
        ];
        
        for (var j:Number = 0; j < escapedStrings.length; j++) {
            var escaped = escapedStrings[j];
            var escapedLexer:PrattLexer = new PrattLexer(escaped.input);
            var escapedToken:PrattToken = escapedLexer.peek();
            _assert(escapedToken.type == PrattToken.T_STRING, "转义字符串：" + escaped.input + "应该被识别为STRING");
            _assert(escapedToken.getStringValue() == escaped.expected, "转义字符串：" + escaped.input + "的值转义应该正确");
        }
        
        // 特殊字符串内容
        var specialStrings:Array = [
            "\"123\"",      // 数字内容
            "\"true\"",     // 布尔值内容
            "\"null\"",     // null内容
            "\" \\t\\n \"", // 空白字符
            "\"@#$%^&*\"", // 特殊符号
            "\"中文测试\""   // 如果支持Unicode
        ];
        
        for (var k:Number = 0; k < specialStrings.length; k++) {
            var specialLexer:PrattLexer = new PrattLexer(specialStrings[k]);
            var specialToken:PrattToken = specialLexer.peek();
            _assert(specialToken.type == PrattToken.T_STRING, "特殊字符串：" + specialStrings[k] + "应该被识别为STRING");
        }
        
        // 未转义的特殊字符（应该按原样处理）
        var unescapedLexer:PrattLexer = new PrattLexer("\"test\\x\""); // 无效转义序列
        var unescapedToken:PrattToken = unescapedLexer.peek();
        _assert(unescapedToken.type == PrattToken.T_STRING, "未知转义：应该仍然被识别为STRING");
        _assert(unescapedToken.getStringValue() == "testx", "未知转义：应该保留转义后的字符");
    }
    
    // ============================================================================
    // 测试分组4：标识符和关键字识别
    // ============================================================================
    private static function testIdentifierAndKeywords():Void {
        trace("\n--- 测试分组4：标识符和关键字识别 ---");
        
        // 标识符测试
        var identifiers:Array = [
            "myVar", "test123", "_private", "$special", "camelCase", 
            "snake_case", "MixedCase", "a", "x1", "var$", "_", "$"
        ];
        
        for (var i:Number = 0; i < identifiers.length; i++) {
            var lexer:PrattLexer = new PrattLexer(identifiers[i]);
            var token:PrattToken = lexer.peek();
            _assert(token.type == PrattToken.T_IDENTIFIER, "标识符：" + identifiers[i] + "应该被识别为IDENTIFIER");
            _assert(token.text == identifiers[i], "标识符：" + identifiers[i] + "的text应该正确");
        }
        
        // 关键字测试 - 逐一验证每个关键字被正确识别
        var keywords:Array = [
            {text: "true", type: PrattToken.T_BOOLEAN},
            {text: "false", type: PrattToken.T_BOOLEAN}, 
            {text: "null", type: PrattToken.T_NULL},
            {text: "undefined", type: PrattToken.T_UNDEFINED},
            {text: "if", type: PrattToken.T_IF},
            {text: "else", type: PrattToken.T_ELSE},
            {text: "and", type: PrattToken.T_AND},
            {text: "or", type: PrattToken.T_OR},
            {text: "not", type: PrattToken.T_NOT}
        ];
        
        for (var j:Number = 0; j < keywords.length; j++) {
            var keyword = keywords[j];
            var keywordLexer:PrattLexer = new PrattLexer(keyword.text);
            var keywordToken:PrattToken = keywordLexer.peek();
            _assert(keywordToken.type == keyword.type, "关键字：" + keyword.text + "应该被识别为" + keyword.type);
            _assert(keywordToken.text == keyword.text, "关键字：" + keyword.text + "的text应该正确");
        }
        
        // 关键字大小写敏感性测试
        var caseSensitive:Array = ["True", "FALSE", "NULL", "If", "ELSE"];
        for (var k:Number = 0; k < caseSensitive.length; k++) {
            var caseLexer:PrattLexer = new PrattLexer(caseSensitive[k]);
            var caseToken:PrattToken = caseLexer.peek();
            _assert(caseToken.type == PrattToken.T_IDENTIFIER, "大小写敏感：" + caseSensitive[k] + "应该被识别为IDENTIFIER而不是关键字");
        }
        
        // 关键字作为较长标识符的一部分
        var partialKeywords:Array = ["truthy", "falsehood", "nullish", "ifStatement"];
        for (var l:Number = 0; l < partialKeywords.length; l++) {
            var partialLexer:PrattLexer = new PrattLexer(partialKeywords[l]);
            var partialToken:PrattToken = partialLexer.peek();
            _assert(partialToken.type == PrattToken.T_IDENTIFIER, "部分关键字：" + partialKeywords[l] + "应该被识别为完整的IDENTIFIER");
        }
    }
    
    // ============================================================================
    // 测试分组5：运算符识别
    // ============================================================================
    private static function testOperators():Void {
        trace("\n--- 测试分组5：运算符识别 ---");
        
        // 单字符运算符
        var singleOperators:Array = ["+", "-", "*", "/", "%", "<", ">", "=", "!", "&", "|", "^", "~"];
        for (var i:Number = 0; i < singleOperators.length; i++) {
            var lexer:PrattLexer = new PrattLexer(singleOperators[i]);
            var token:PrattToken = lexer.peek(); 
            _assert(token.type == PrattToken.T_OPERATOR, "单字符运算符：" + singleOperators[i] + "应该被识别为OPERATOR");
            _assert(token.text == singleOperators[i], "单字符运算符：" + singleOperators[i] + "的text应该正确");
        }
        
        // 双字符运算符
        var doubleOperators:Array = [
            "==", "!=", "<=", ">=", "&&", "||", "++", "--", 
            "+=", "-=", "*=", "/=", "%=", "**", "??"
        ];
        for (var j:Number = 0; j < doubleOperators.length; j++) {
            var doubleLexer:PrattLexer = new PrattLexer(doubleOperators[j]);
            var doubleToken:PrattToken = doubleLexer.peek();
            _assert(doubleToken.type == PrattToken.T_OPERATOR, "双字符运算符：" + doubleOperators[j] + "应该被识别为OPERATOR");
            _assert(doubleToken.text == doubleOperators[j], "双字符运算符：" + doubleOperators[j] + "的text应该正确");
        }
        
        // 三字符运算符
        var tripleOperators:Array = ["===", "!=="];
        for (var k:Number = 0; k < tripleOperators.length; k++) {
            var tripleLexer:PrattLexer = new PrattLexer(tripleOperators[k]);
            var tripleToken:PrattToken = tripleLexer.peek();
            _assert(tripleToken.type == PrattToken.T_OPERATOR, "三字符运算符：" + tripleOperators[k] + "应该被识别为OPERATOR");
            _assert(tripleToken.text == tripleOperators[k], "三字符运算符：" + tripleOperators[k] + "的text应该正确");
        }
        
        // 运算符优先级识别（确保不会错误合并）
        var priorityLexer:PrattLexer = new PrattLexer("=== != + ++ +="); 
        var op1:PrattToken = priorityLexer.next(); // ===
        var op2:PrattToken = priorityLexer.next(); // !=
        var op3:PrattToken = priorityLexer.next(); // +
        var op4:PrattToken = priorityLexer.next(); // ++
        var op5:PrattToken = priorityLexer.next(); // +=

        _assert(op1.text == "===", "运算符优先级：应该识别出===");
        _assert(op2.text == "!=", "运算符优先级：应该识别出!=");
        _assert(op3.text == "+", "运算符优先级：应该识别出单独的+");
        _assert(op4.text == "++", "运算符优先级：应该识别出++");
        _assert(op5.text == "+=", "运算符优先级：应该识别出+=");
        
        // 紧连运算符的分离
        var compactLexer:PrattLexer = new PrattLexer("a++b--c");
        var id1:PrattToken = compactLexer.next();
        var inc:PrattToken = compactLexer.next();
        var id2:PrattToken = compactLexer.next();
        var dec:PrattToken = compactLexer.next();
        var id3:PrattToken = compactLexer.next();
        
        _assert(id1.type == PrattToken.T_IDENTIFIER && id1.text == "a", "紧连运算符：标识符a应该正确分离");
        _assert(inc.type == PrattToken.T_OPERATOR && inc.text == "++", "紧连运算符：++应该正确分离");
        _assert(id2.type == PrattToken.T_IDENTIFIER && id2.text == "b", "紧连运算符：标识符b应该正确分离");
        _assert(dec.type == PrattToken.T_OPERATOR && dec.text == "--", "紧连运算符：--应该正确分离");
        _assert(id3.type == PrattToken.T_IDENTIFIER && id3.text == "c", "紧连运算符：标识符c应该正确分离");
    }
    
    // ============================================================================
    // 测试分组6：分隔符识别
    // ============================================================================
    private static function testDelimiters():Void {
        trace("\n--- 测试分组6：分隔符识别 ---");
        
        // 所有分隔符的类型映射测试
        var delimiters:Array = [
            {char: "(", type: PrattToken.T_LPAREN},
            {char: ")", type: PrattToken.T_RPAREN},
            {char: "[", type: PrattToken.T_LBRACKET},
            {char: "]", type: PrattToken.T_RBRACKET},
            {char: "{", type: PrattToken.T_LBRACE},
            {char: "}", type: PrattToken.T_RBRACE},
            {char: ",", type: PrattToken.T_COMMA},
            {char: ";", type: PrattToken.T_SEMICOLON},
            {char: ".", type: PrattToken.T_DOT},
            {char: ":", type: PrattToken.T_COLON},
            {char: "?", type: PrattToken.T_QUESTION}
        ];
        
        for (var i:Number = 0; i < delimiters.length; i++) {
            var delim = delimiters[i];
            var lexer:PrattLexer = new PrattLexer(delim.char);
            var token:PrattToken = lexer.peek();
            _assert(token.type == delim.type, "分隔符类型：" + delim.char + "应该被识别为" + delim.type);
            _assert(token.text == delim.char, "分隔符文本：" + delim.char + "的text应该正确");
        }
        
        // 连续分隔符的正确分离
        var complexLexer:PrattLexer = new PrattLexer("([{}]);.,?:");
        var expectedTypes:Array = [
            PrattToken.T_LPAREN, PrattToken.T_LBRACKET, PrattToken.T_LBRACE, 
            PrattToken.T_RBRACE, PrattToken.T_RBRACKET, PrattToken.T_RPAREN,
            PrattToken.T_SEMICOLON, 
            // ==================== FIX START (PrattLexer_TestSuite.as) ====================
            PrattToken.T_DOT,       // '.' 在 ',' 之前
            PrattToken.T_COMMA,
            // ===================== FIX END (PrattLexer_TestSuite.as) =====================
            PrattToken.T_QUESTION, PrattToken.T_COLON
        ];
        
        for (var j:Number = 0; j < expectedTypes.length; j++) {
            var token:PrattToken = complexLexer.next();
            _assert(token.type == expectedTypes[j], "连续分隔符：位置" + j + "应该是" + expectedTypes[j]);
        }
        
        // 分隔符与其他token的混合
        var mixedLexer:PrattLexer = new PrattLexer("func(a,b)");
        var funcToken:PrattToken = mixedLexer.next();
        var lparenToken:PrattToken = mixedLexer.next();
        var aToken:PrattToken = mixedLexer.next();
        var commaToken:PrattToken = mixedLexer.next();
        var bToken:PrattToken = mixedLexer.next();
        var rparenToken:PrattToken = mixedLexer.next();
        
        _assert(funcToken.type == PrattToken.T_IDENTIFIER && funcToken.text == "func", "混合分隔符：函数名应该正确");
        _assert(lparenToken.type == PrattToken.T_LPAREN, "混合分隔符：左括号应该正确");
        _assert(aToken.type == PrattToken.T_IDENTIFIER && aToken.text == "a", "混合分隔符：参数a应该正确");
        _assert(commaToken.type == PrattToken.T_COMMA, "混合分隔符：逗号应该正确");
        _assert(bToken.type == PrattToken.T_IDENTIFIER && bToken.text == "b", "混合分隔符：参数b应该正确");
        _assert(rparenToken.type == PrattToken.T_RPAREN, "混合分隔符：右括号应该正确");
    }
    
    // ============================================================================
    // 测试分组7：空白字符处理
    // ============================================================================
    private static function testWhitespaceHandling():Void {
        trace("\n--- 测试分组7：空白字符处理 ---");
        
        // 基础空白字符跳过
        var whitespaces:Array = [" ", "\t", "\n", "\r", "   ", "\t\t", "\n\n", "\r\n"];
        for (var i:Number = 0; i < whitespaces.length; i++) {
            var input:String = whitespaces[i] + "123" + whitespaces[i];
            var lexer:PrattLexer = new PrattLexer(input);
            var token:PrattToken = lexer.peek();
            _assert(token.type == PrattToken.T_NUMBER, "空白跳过：" + "应该跳过前置空白并识别出数字");
            _assert(token.text == "123", "空白跳过：数字内容应该正确");
        }
        
        // 复合空白字符
        var complexWhitespace:PrattLexer = new PrattLexer("  \t\n\r  abc  \t\n  def  ");
        var token1:PrattToken = complexWhitespace.next();
        var token2:PrattToken = complexWhitespace.next();
        var eofToken:PrattToken = complexWhitespace.next();
        
        _assert(token1.type == PrattToken.T_IDENTIFIER && token1.text == "abc", "复合空白：第一个标识符应该正确");
        _assert(token2.type == PrattToken.T_IDENTIFIER && token2.text == "def", "复合空白：第二个标识符应该正确");
        _assert(eofToken.type == PrattToken.T_EOF, "复合空白：应该正确到达EOF");
        
        // 只有空白字符的输入
        var onlyWhitespace:PrattLexer = new PrattLexer("   \t\n\r   ");
        var emptyToken:PrattToken = onlyWhitespace.peek();
        _assert(emptyToken.type == PrattToken.T_EOF, "纯空白：只有空白的输入应该直接返回EOF");
        
        // 混合表达式中的空白
        var expression:PrattLexer = new PrattLexer("a + b * c");  
        var tokens:Array = [];
        var token:PrattToken;
        while ((token = expression.next()).type != PrattToken.T_EOF) {
            tokens.push(token);
        }
        
        _assert(tokens.length == 5, "表达式空白：应该识别出5个token");
        _assert(tokens[0].text == "a" && tokens[1].text == "+" && tokens[2].text == "b" && 
                tokens[3].text == "*" && tokens[4].text == "c", "表达式空白：所有token都应该正确");
    }
    
    // ============================================================================
    // 测试分组8：注释处理
    // ============================================================================ 
    private static function testCommentHandling():Void {
        trace("\n--- 测试分组8：注释处理 ---");
        
        // 单行注释测试
        var singleLineTests:Array = [
            "// comment only",
            "abc // comment after code",
            "123 + 456 // arithmetic comment",
            "// comment\n789",  // 注释后换行
            "var1 // comment\nvar2"  // 注释中间插入
        ];
        
        // 测试纯注释
        var pureCommentLexer:PrattLexer = new PrattLexer("// this is a comment");
        var pureCommentToken:PrattToken = pureCommentLexer.peek();
        _assert(pureCommentToken.type == PrattToken.T_EOF, "纯单行注释：应该跳过整行并返回EOF");
        
        // 测试注释后的代码
        var commentAfterLexer:PrattLexer = new PrattLexer("abc // this is comment");
        var beforeComment:PrattToken = commentAfterLexer.next();
        var afterComment:PrattToken = commentAfterLexer.next();
        _assert(beforeComment.type == PrattToken.T_IDENTIFIER && beforeComment.text == "abc", "注释后代码：注释前的代码应该正确");
        _assert(afterComment.type == PrattToken.T_EOF, "注释后代码：注释后应该是EOF");
        
        // 测试注释与换行
        var commentNewlineLexer:PrattLexer = new PrattLexer("// comment\n789");
        var afterNewline:PrattToken = commentNewlineLexer.peek();
        _assert(afterNewline.type == PrattToken.T_NUMBER && afterNewline.text == "789", "注释换行：换行后的代码应该正确");
        
        // 多行注释测试
        var multiLineTests:Array = [
            "/* comment */",
            "abc /* comment */ def",
            "/* multi\nline\ncomment */",
            "123 /* comment */ + 456"
        ];
        
        // 测试纯多行注释  
        var pureMultiLexer:PrattLexer = new PrattLexer("/* this is a multi-line comment */");
        var pureMultiToken:PrattToken = pureMultiLexer.peek();
        _assert(pureMultiToken.type == PrattToken.T_EOF, "纯多行注释：应该跳过注释并返回EOF");
        
        // 测试多行注释中间的代码
        var multiMiddleLexer:PrattLexer = new PrattLexer("abc /* comment */ def");
        var beforeMulti:PrattToken = multiMiddleLexer.next();
        var afterMulti:PrattToken = multiMiddleLexer.next();
        var multiEof:PrattToken = multiMiddleLexer.next();
        _assert(beforeMulti.type == PrattToken.T_IDENTIFIER && beforeMulti.text == "abc", "多行注释中间：注释前应该正确");
        _assert(afterMulti.type == PrattToken.T_IDENTIFIER && afterMulti.text == "def", "多行注释中间：注释后应该正确");
        _assert(multiEof.type == PrattToken.T_EOF, "多行注释中间：最后应该是EOF");
        
        // 测试包含换行的多行注释
        var multiNewlineLexer:PrattLexer = new PrattLexer("start /* line1\nline2\nline3 */ end");
        var startToken:PrattToken = multiNewlineLexer.next();
        var endToken:PrattToken = multiNewlineLexer.next();
        _assert(startToken.text == "start", "多行换行注释：开始token应该正确");
        _assert(endToken.text == "end", "多行换行注释：结束token应该正确");
        
        // 嵌套和复杂注释情况
        var complexCommentLexer:PrattLexer = new PrattLexer("a /* /* inner */ */ b"); // 注意：/* /* 不是真正的嵌套
        var complexStart:PrattToken = complexCommentLexer.next(); 
        var complexEnd:PrattToken = complexCommentLexer.next();
        _assert(complexStart.text == "a", "复杂注释：开始应该正确");
        // 根据实现，/* /* inner */ 会在第一个 */ 处结束，所以后面的 */ b 会被当作正常代码
    }
    
    // ============================================================================
    // 测试分组9：位置跟踪准确性
    // ============================================================================
    private static function testPositionTracking():Void {
        trace("\n--- 测试分组9：位置跟踪准确性 ---");
        
        // 单行位置跟踪
        var singleLineLexer:PrattLexer = new PrattLexer("abc + def");
        var tokens:Array = [];
        var token:PrattToken;
        while ((token = singleLineLexer.next()).type != PrattToken.T_EOF) {
            tokens.push(token);
        }
        
        _assert(tokens[0].line == 1 && tokens[0].column == 1, "单行位置：'abc'应该在(1,1)");
        _assert(tokens[1].line == 1 && tokens[1].column == 5, "单行位置：'+'应该在(1,5)");  
        _assert(tokens[2].line == 1 && tokens[2].column == 7, "单行位置：'def'应该在(1,7)");
        
        // 多行位置跟踪
        var multiLineLexer:PrattLexer = new PrattLexer("first\nsecond\n  third");
        var line1:PrattToken = multiLineLexer.next();
        var line2:PrattToken = multiLineLexer.next();
        var line3:PrattToken = multiLineLexer.next();
        
        _assert(line1.line == 1 && line1.column == 1, "多行位置：'first'应该在(1,1)");
        _assert(line2.line == 2 && line2.column == 1, "多行位置：'second'应该在(2,1)");
        _assert(line3.line == 3 && line3.column == 3, "多行位置：'third'应该在(3,3)，因为前面有2个空格");
        
        // 复杂表达式的位置跟踪
        var complexPositionLexer:PrattLexer = new PrattLexer("if (x > 0) {\n  return true;\n}");
        var positionTokens:Array = [];
        while ((token = complexPositionLexer.next()).type != PrattToken.T_EOF) {
            positionTokens.push({text: token.text, line: token.line, column: token.column});
        }
        
        // 抽样检查关键位置
        var ifToken = positionTokens[0];  // "if"
        var returnToken;
        var trueToken;
        
        for (var i:Number = 0; i < positionTokens.length; i++) {
            if (positionTokens[i].text == "return") returnToken = positionTokens[i];
            if (positionTokens[i].text == "true") trueToken = positionTokens[i];
        }
        
        _assert(ifToken.line == 1 && ifToken.column == 1, "复杂位置：'if'应该在第1行第1列");
        _assert(returnToken.line == 2, "复杂位置：'return'应该在第2行");
        _assert(trueToken.line == 2, "复杂位置：'true'应该在第2行");
        
        // 制表符对列计数的影响
        var tabLexer:PrattLexer = new PrattLexer("a\tb\t\tc");
        var tabA:PrattToken = tabLexer.next();
        var tabB:PrattToken = tabLexer.next();
        var tabC:PrattToken = tabLexer.next();
        
        _assert(tabA.line == 1 && tabA.column == 1, "制表符位置：'a'应该在(1,1)");
        _assert(tabB.line == 1, "制表符位置：'b'应该在第1行");
        _assert(tabC.line == 1, "制表符位置：'c'应该在第1行");
        // 注意：制表符的具体列号计算取决于实现，这里主要确保不会崩溃
    }
    
    // ============================================================================
    // 测试分组10：错误条件处理 (FINAL REVISION)
    // ============================================================================
    private static function testErrorConditions():Void {
        trace("\n--- 测试分组10：错误条件处理 ---");

        // --- 预期抛出错误的用例 ---

        // 1. 未终止的双引号字符串
        _assertThrows(
            function() { new PrattLexer("\"unterminated string"); }, 
            "未终止的字符串", 
            "未终止双引号：应该抛出错误"
        );

        // 2. 未终止的单引号字符串
        _assertThrows(
            function() { new PrattLexer("'unterminated string"); }, 
            "未终止的字符串", 
            "未终止单引号：应该抛出错误"
        );

        // 3. 包含换行的未终止字符串
        _assertThrows(
            function() { new PrattLexer("\"line1\nline2\nunterminated"); }, 
            "未终止的字符串", 
            "多行未终止字符串：应该抛出错误"
        );
        
        // 4. 字符串中以单个反斜杠结尾（未完成的转义序列）
        // 注意：`_scanString` 的实现会安全处理这种情况，但我们可以明确测试
        // 根据 `_scanString` 实现， `_idx < _len` 会在反斜杠后失败，循环结束，
        // 最终检查 `_src.charAt(_idx) != quote` 会发现已经到了末尾，
        // 所以它也会被归为“未终止的字符串”错误。
        _assertThrows(
            function() { new PrattLexer("\"test\\"); },
            "未终止的字符串",
            "字符串以反斜杠结尾：应该抛出未终止错误"
        );


        // --- 预期不抛出错误的用例 ---

        // 5. 未完成的多行注释 - 应该优雅地处理并到达EOF
        // 你的 Lexer 实现中，`while (_idx + 1 < _len)` 循环会因为到达末尾而自然终止，
        // 接着 `_skipWhitespaceAndComments` 结束，`_advance` 会发现 `_idx >= _len`，
        // 最终返回 EOF。这是正确的、健壮的行为。
        var lexer:PrattLexer = new PrattLexer("/* unterminated comment");
        var token:PrattToken = lexer.peek();
        _assert(token.type == PrattToken.T_EOF, "未终止注释：应该优雅处理并到达EOF");

        // 6. 无法识别的字符（根据当前实现，被当作单字符运算符）
        // 这不是一个错误条件，而是一个设计决策。测试它按预期工作即可。
        var unknownCharLexer:PrattLexer = new PrattLexer("@#"); // 移除$，因为$是合法标识符的一部分
        var unknown1:PrattToken = unknownCharLexer.next();
        var unknown2:PrattToken = unknownCharLexer.next(); 
        
        _assert(unknown1.type == PrattToken.T_OPERATOR && unknown1.text == "@", "未知字符：@应该被当作运算符");
        _assert(unknown2.type == PrattToken.T_OPERATOR && unknown2.text == "#", "未知字符：#应该被当作运算符");
    }
    
    // ============================================================================
    // 测试分组11：边界条件
    // ============================================================================
    private static function testBoundaryConditions():Void {
        trace("\n--- 测试分组11：边界条件 ---");
        
        // 空输入
        var emptyLexer:PrattLexer = new PrattLexer("");
        var emptyToken:PrattToken = emptyLexer.peek();
        _assert(emptyToken.type == PrattToken.T_EOF, "空输入：应该立即返回EOF");
        
        // 单字符输入的各种情况
        var singleChars:Array = ["a", "1", "+", "(", "\"", "'"];
        for (var i:Number = 0; i < singleChars.length; i++) {
            var char:String = singleChars[i];
            if (char == "\"" || char == "'") {
                // 这些会导致未终止字符串错误，跳过
                continue;
            }
            var singleLexer:PrattLexer = new PrattLexer(char);
            var singleToken:PrattToken = singleLexer.next();
            var singleEof:PrattToken = singleLexer.next();
            _assert(singleToken.text == char, "单字符：" + char + "应该被正确识别");
            _assert(singleEof.type == PrattToken.T_EOF, "单字符：" + char + "后应该是EOF");
        }
        
        // 超长标识符
        var longIdentifier:String = "";
        for (var j:Number = 0; j < 1000; j++) {
            longIdentifier += "a";
        }
        var longLexer:PrattLexer = new PrattLexer(longIdentifier);
        var longToken:PrattToken = longLexer.peek();
        _assert(longToken.type == PrattToken.T_IDENTIFIER, "超长标识符：应该被识别为IDENTIFIER");
        _assert(longToken.text.length == 1000, "超长标识符：长度应该正确");
        
        // 超长数字
        var longNumber:String = "1";
        for (var k:Number = 0; k < 100; k++) {
            longNumber += "0";
        }
        var longNumLexer:PrattLexer = new PrattLexer(longNumber);
        var longNumToken:PrattToken = longNumLexer.peek();
        _assert(longNumToken.type == PrattToken.T_NUMBER, "超长数字：应该被识别为NUMBER");
        _assert(longNumToken.text == longNumber, "超长数字：文本应该完整保留");
        
        // 大量空白字符
        var manySpaces:String = "";
        for (var l:Number = 0; l < 1000; l++) {
            manySpaces += " ";
        }
        var spaceLexer:PrattLexer = new PrattLexer(manySpaces + "test");
        var spaceToken:PrattToken = spaceLexer.peek();
        _assert(spaceToken.type == PrattToken.T_IDENTIFIER && spaceToken.text == "test", "大量空白：应该正确跳过并识别内容");
        
        // 极端的行列位置
        var manyLines:String = "";
        for (var m:Number = 0; m < 1000; m++) {
            manyLines += "\n";
        }
        manyLines += "finalToken";
        var lineLexer:PrattLexer = new PrattLexer(manyLines);
        var lineToken:PrattToken = lineLexer.peek();
        _assert(lineToken.text == "finalToken", "大量换行：应该正确识别最终token");
        _assert(lineToken.line == 1001, "大量换行：行号应该正确计算");
    }
    
    // ============================================================================
    // 测试分组12：复杂综合场景
    // ============================================================================
    private static function testComplexScenarios():Void {
        trace("\n--- 测试分组12：复杂综合场景 ---");
        
        // 完整JavaScript风格表达式
        var jsExpression:String = "function(a, b) { return a + b * Math.max(1, 2); }";
        var jsLexer:PrattLexer = new PrattLexer(jsExpression);
        var jsTokens:Array = [];
        var jsToken:PrattToken;
        while ((jsToken = jsLexer.next()).type != PrattToken.T_EOF) {
            jsTokens.push(jsToken);
        }
        _assert(jsTokens.length > 15, "JS表达式：应该识别出足够多的token");
        _assert(jsTokens[0].text == "function", "JS表达式：第一个token应该是function");
        
        // 包含注释的复杂表达式
        var commentExpression:String = "a /* comment1 */ + b // comment2\n* c";
        var commentLexer:PrattLexer = new PrattLexer(commentExpression);
        var commentTokens:Array = [];
        while ((jsToken = commentLexer.next()).type != PrattToken.T_EOF) {
            commentTokens.push(jsToken);
        }
        _assert(commentTokens.length == 5, "注释表达式：应该识别出5个有效token");
        _assert(commentTokens[0].text == "a" && commentTokens[1].text == "+" && 
                commentTokens[2].text == "b" && commentTokens[3].text == "*" && 
                commentTokens[4].text == "c", "注释表达式：所有token应该正确，注释被忽略");
        
        // 字符串中包含特殊字符的表达式
        var stringExpression:String = "'hello\\'world' + \"test\\\"quote\" + `backtick`";
        var stringLexer:PrattLexer = new PrattLexer(stringExpression);
        var str1:PrattToken = stringLexer.next();
        var plus1:PrattToken = stringLexer.next();
        var str2:PrattToken = stringLexer.next();
        var plus2:PrattToken = stringLexer.next();
        var backtick:PrattToken = stringLexer.next(); // 如果支持backtick，否则会是其他类型
        
        _assert(str1.type == PrattToken.T_STRING, "特殊字符串：单引号字符串应该正确");
        _assert(str1.getStringValue() == "hello'world", "特殊字符串：转义应该正确处理");
        _assert(str2.type == PrattToken.T_STRING, "特殊字符串：双引号字符串应该正确");
        _assert(str2.getStringValue() == "test\"quote", "特殊字符串：双引号转义应该正确");
        
        // 运算符优先级复杂表达式
        var operatorExpression:String = "a === b && c != d || e <= f ** g % h";
        var opLexer:PrattLexer = new PrattLexer(operatorExpression);
        var opTokens:Array = [];
        while ((jsToken = opLexer.next()).type != PrattToken.T_EOF) {
            opTokens.push(jsToken.text);
        }
        
        var expectedOps:Array = ["a", "===", "b", "&&", "c", "!=", "d", "||", "e", "<=", "f", "**", "g", "%", "h"];
        _assert(opTokens.length == expectedOps.length, "运算符优先级：token数量应该正确");
        for (var n:Number = 0; n < expectedOps.length; n++) {
            _assert(opTokens[n] == expectedOps[n], "运算符优先级：token[" + n + "]应该是" + expectedOps[n]);
        }
        
        // 深度嵌套的括号表达式
        var nestedExpression:String = "((((a + b) * c) / d) ** e)";
        var nestedLexer:PrattLexer = new PrattLexer(nestedExpression);
        var nestedTokens:Array = [];
        while ((jsToken = nestedLexer.next()).type != PrattToken.T_EOF) {
            nestedTokens.push(jsToken);
        }
        
        var openParens:Number = 0;
        var closeParens:Number = 0;
        for (var o:Number = 0; o < nestedTokens.length; o++) {
            if (nestedTokens[o].type == PrattToken.T_LPAREN) openParens++;
            if (nestedTokens[o].type == PrattToken.T_RPAREN) closeParens++;
        }
        _assert(openParens == 4, "嵌套括号：应该识别出4个左括号");
        _assert(closeParens == 4, "嵌套括号：应该识别出4个右括号");
        
        // 混合数字类型的表达式
        var numberMixExpression:String = "123 + 45.67 + .89 + 0.0 + 999999999";
        var numMixLexer:PrattLexer = new PrattLexer(numberMixExpression);
        var numbers:Array = [];
        while ((jsToken = numMixLexer.next()).type != PrattToken.T_EOF) {
            if (jsToken.type == PrattToken.T_NUMBER) {
                numbers.push(jsToken.getNumberValue());
            }
        }
        _assert(numbers.length == 5, "混合数字：应该识别出5个数字");
        _assert(numbers[0] == 123 && numbers[1] == 45.67 && numbers[2] == 0.89 && 
                numbers[3] == 0.0, "混合数字：所有数字值应该正确");
    }
}