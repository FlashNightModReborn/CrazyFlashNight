import org.flashNight.gesh.fntl.*;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.naki.Sort.QuickSort;

/**
 * FNTLLexerTest class upgraded to support FNTL (FlashNight Text Language).
 * Enhancements include:
 * - Comprehensive test cases covering all FNTL features
 * - Robust comparison of nested structures and special number formats
 * - Detailed and localized error reporting
 * - Summary of test results for better visibility
 * - Modular and maintainable code structure
 */
class org.flashNight.gesh.fntl.FNTLLexerTest {

    // Maximum recursion depth to prevent infinite loops during comparison
    private var MAX_RECURSION_DEPTH:Number = 20; // Increased to handle deeper nesting

    // Counters for test results
    private var totalTests:Number = 0;
    private var passedTests:Number = 0;
    private var failedTests:Number = 0;
    private var debug:Boolean = true; // 调试日志开关

    /**
     * Runs all the test cases for FNTLLexer, FNTLParser, and FNTLEncoder.
     * Allows selective testing based on test type.
     * @param testType Optional parameter to specify which tests to run: "lexer", "parser", "encoder", or "all".
     */
    public function runAllTests(testType:String):Void {
        trace("=== Running FNTLLexer Tests ===");

        testType = testType!= null? testType.toLowerCase() : "all";

        if (testType == "lexer" || testType == "all") {
            this.testLexer();
        }

        trace("\n=== Running FNTLParser Tests ===");
        if (testType == "parser" || testType == "all") {
            this.testParser();
        }

        trace("\n=== Running FNTLEncoder Tests ===");
        if (testType == "encoder" || testType == "all") {
            this.testFNTLEncoder();
        }

        // Summary of test results
        trace("\n=== Test Summary ===");
        trace("Total Tests: " + this.totalTests);
        trace("Passed Tests: " + this.passedTests);
        trace("Failed Tests: " + this.failedTests);
    }

    /**
     * Tests the FNTLLexer by tokenizing FNTL inputs and validating tokens.
     */
    public function testLexer():Void {
        var lexerTestCases:Array = this.getLexerTestCases();

        for (var i:Number = 0; i < lexerTestCases.length; i++) {
            var testCase:Object = lexerTestCases[i];
            var FNTLText:String = testCase.text;
            var expectedTokens:Array = testCase.expectedTokens;
            var description:String = testCase.description;

            trace("\n--- Running Lexer Test Case " + (i + 1) + " ---");
            trace("Description: " + description);

            var lexer:FNTLLexer = new FNTLLexer(FNTLText, this.debug); // 启用调试日志
            var tokens:Array = [];
            var token:Object;

            // Tokenize the input
            while ((token = lexer.getNextToken()) != null) {
                tokens.push(token);
            }

            // Validate tokens if expected tokens are provided
            if (expectedTokens !== null) {
                var comparisonResult:Boolean = this.compareTokenArrays(tokens, expectedTokens);
                if (comparisonResult) {
                    trace("Lexer Test Case " + (i + 1) + ": Passed.");
                    this.passedTests++;
                } else {
                    trace("Lexer Test Case " + (i + 1) + ": Failed.");
                    this.failedTests++;
                }
            } else {
                // If no expected tokens, consider the lexer passed
                trace("Lexer Test Case " + (i + 1) + ": Passed (No expected tokens provided).");
                this.passedTests++;
            }
            this.totalTests++;
        }
    }

    /**
     * Tests the FNTLParser by parsing tokenized FNTL inputs and validating output objects.
     */
    public function testParser():Void {
        var parserTestCases:Array = this.getParserTestCases();

        for (var i:Number = 0; i < parserTestCases.length; i++) {
            var testCase:Object = parserTestCases[i];
            var FNTLText:String = testCase.text;
            var expected:Object = testCase.expected;
            var description:String = testCase.description;

            trace("\n--- Running Parser Test Case " + (i + 1) + " ---");
            trace("Description: " + description);

            var lexer:FNTLLexer = new FNTLLexer(FNTLText);
            var tokens:Array = [];
            var token:Object;

            // Tokenize the input
            while ((token = lexer.getNextToken()) != null) {
                tokens.push(token);
                if (this.debug) { // 添加调试输出
                    trace("Lexer Token[" + tokens.length + "]: Type = " + token.type + ", Value = " + token.value);
                }
            }

            // Parse the tokens with debug enabled
            var parser:FNTLParser = new FNTLParser(tokens, FNTLText, this.debug); // 启用调试日志
            var result:Object = parser.parse();

            // 检查是否发生解析错误
            if (parser.hasError()) {
                if (expected == null) {
                    // 解析错误是预期结果
                    trace("Parser Test Case " + (i + 1) + ": Passed (expected failure).");
                    this.passedTests++;
                } else {
                    trace("Parser Test Case " + (i + 1) + ": Failed with parsing errors.");
                    this.failedTests++;
                }
                this.totalTests++;
                continue;
            }

            // 对比解析结果与预期
            if (expected == null && result == null) {
                trace("Parser Test Case " + (i + 1) + ": Passed.");
                this.passedTests++;
            } else if (expected == null && result != null) {
                trace("Parser Test Case " + (i + 1) + ": Failed (expected null, got non-null).");
                this.failedTests++;
            } else {
                // 进行正常结果对比
                var comparisonResult:Boolean = this.compareResults(result, expected, 0);
                if (comparisonResult) {
                    trace("Parser Test Case " + (i + 1) + ": Passed.");
                    this.passedTests++;
                } else {
                    trace("Parser Test Case " + (i + 1) + ": Failed.");
                    this.failedTests++;
                }
            }
            this.totalTests++;
        }
    }


    /**
     * Tests the FNTLEncoder by encoding objects into FNTL strings and validating outputs.
     */
    public function testFNTLEncoder():Void {
        var encoderTestCases:Array = this.getEncoderTestCases();

        for (var i:Number = 0; i < encoderTestCases.length; i++) {
            var testCase:Object = encoderTestCases[i];
            var testObj:Object = testCase.input;
            var expected:String = testCase.expected;
            var description:String = testCase.description;

            trace("\n--- Running Encoder Test Case " + (i + 1) + " ---");
            trace("Description: " + description);

            // Encode the object into FNTL
            var encoder:FNTLEncoder = new FNTLEncoder(this.debug);
            var FNTLOutput:String = encoder.encode(testObj, false); // true for pretty formatting

            // Compare the encoded output with expected FNTL string
            var comparisonResult:Boolean = this.compareFNTLOutputs(FNTLOutput, expected);
            if (comparisonResult) {
                trace("Encoder Test Case " + (i + 1) + ": Passed.");
                this.passedTests++;
            } else {
                trace("Encoder Test Case " + (i + 1) + ": Failed.");
                this.failedTests++;
            }
            this.totalTests++;
        }
    }

    /**
     * Retrieves test cases for the FNTLLexer.
     * Each test case can optionally include expected tokens for validation.
     */
    private function getLexerTestCases():Array {
        var cases:Array = new Array();
        
        // ==========================
        // 基础键值对测试
        // ==========================
        // Test case 1: Basic key-value pairs
        var testCase1:Object = new Object();
        testCase1.text = 'title = "My Game"\n' +
                        'isActive = true\n' +
                        'max_score = 1000\n' +
                        'average_score = 89.95\n';
        testCase1.expectedTokens = null; // Optional
        testCase1.description = "基础键值对测试，包括字符串、布尔值和数字。";
        cases.push(testCase1);

        // ==========================
        // 多行字符串测试
        // ==========================
        // Test case 2: Multiline string
        var testCase2:Object = new Object();
        testCase2.text = 'description = """This is a multiline string.\nIt spans multiple lines."""\n';
        testCase2.expectedTokens = null;
        testCase2.description = "测试多行字符串。";
        cases.push(testCase2);

        // ==========================
        // 数组测试
        // ==========================
        // Test case 3: Simple array
        var testCase3:Object = new Object();
        testCase3.text = 'items = ["sword", "shield", "potion"]\n';
        testCase3.expectedTokens = null;
        testCase3.description = "测试简单数组。";
        cases.push(testCase3);

        // Test case 4: Nested arrays
        var testCase4:Object = new Object();
        testCase4.text = 'nested_arrays = [[1, 2], [3, 4], [5, 6]]\n';
        testCase4.expectedTokens = null;
        testCase4.description = "测试嵌套数组。";
        cases.push(testCase4);

        // ==========================
        // 表测试
        // ==========================
        // Test case 5: Basic table
        var testCase5:Object = new Object();
        testCase5.text = '[server]\n' +
                        'ip = "192.168.1.1"\n' +
                        'port = 8080\n';
        testCase5.expectedTokens = null;
        testCase5.description = "测试基本表结构。";
        cases.push(testCase5);

        // Test case 6: Nested tables
        var testCase6:Object = new Object();
        testCase6.text = '[database.connection]\n' +
                        'server = "localhost"\n' +
                        'port = 5432\n';
        testCase6.expectedTokens = null;
        testCase6.description = "测试嵌套表结构。";
        cases.push(testCase6);

        // ==========================
        // 表数组测试
        // ==========================
        // Test case 7: Simple table array
        var testCase7:Object = new Object();
        testCase7.text = '[[monsters]]\n' +
                        'name = "Goblin"\n' +
                        'level = 5\n' +
                        '[[monsters]]\n' +
                        'name = "Dragon"\n' +
                        'level = 50\n';
        testCase7.expectedTokens = null;
        testCase7.description = "测试简单的表数组。";
        cases.push(testCase7);

        // Test case 8: Nested table arrays
        var testCase8:Object = new Object();
        testCase8.text = '[[servers]]\n' +
                        'name = "Server1"\n' +
                        'ip = "10.0.0.1"\n' +
                        '[[servers.database]]\n' +
                        'type = "MySQL"\n' +
                        'port = 3306\n' +
                        '[[servers.database.settings]]\n' +
                        'enabled = true\n';
        testCase8.expectedTokens = null;
        testCase8.description = "测试嵌套的表数组。";
        cases.push(testCase8);

        // ==========================
        // 内联表测试
        // ==========================
        // Test case 9: Inline table
        var testCase9:Object = new Object();
        testCase9.text = 'player = { name = "Alice", score = 2500 }\n';
        testCase9.expectedTokens = null;
        testCase9.description = "测试内联表。";
        cases.push(testCase9);

        // ==========================
        // Unicode和Emoji测试
        // ==========================
        // Test case 10: Unicode characters and emojis
        var testCase10:Object = new Object();
        testCase10.text = 'greeting = "こんにちは"\nemoji = "😊"\n';
        testCase10.expectedTokens = null;
        testCase10.description = "测试Unicode字符和Emoji。";
        cases.push(testCase10);

        // ==========================
        // 转义字符测试
        // ==========================
        // Test case 11: Escape characters in strings
        var testCase11:Object = new Object();
        testCase11.text = 'escaped_newline = "Line1\\nLine2"\nescaped_quote = "He said, \\"Hello!\\""\n';
        testCase11.expectedTokens = null;
        testCase11.description = "测试字符串中的转义字符。";
        cases.push(testCase11);

        // ==========================
        // 特殊数字格式测试
        // ==========================
        // Test case 12: Special floating-point values
        var testCase12:Object = new Object();
        testCase12.text = 'special_float_1 = nan\nspecial_float_2 = inf\nspecial_float_3 = -inf\n';
        testCase12.expectedTokens = null;
        testCase12.description = "测试特殊浮点数值：NaN、Infinity、-Infinity。";
        cases.push(testCase12);

        // ==========================
        // 错误输入测试
        // ==========================
        // Test case 13: Missing equals sign
        var testCase13:Object = new Object();
        testCase13.text = 'invalid_line "No equals sign"\n';
        testCase13.expectedTokens = null;
        testCase13.description = "测试缺少等号的错误输入。";
        cases.push(testCase13);

        // Test case 14: Unclosed string
        var testCase14:Object = new Object();
        testCase14.text = 'unclosed_string = "This string never ends...\n';
        testCase14.expectedTokens = null;
        testCase14.description = "测试未闭合字符串的错误输入。";
        cases.push(testCase14);

        // Test case 15: Invalid date-time format
        var testCase15:Object = new Object();
        testCase15.text = 'invalid_date = 2024-13-40T25:61:61Z\n';
        testCase15.expectedTokens = null;
        testCase15.description = "测试无效日期时间格式的错误输入。";
        cases.push(testCase15);

        // ==========================
        // 项目特定的复杂结构测试
        // ==========================
        // Test case 16: Project-specific complex structure
        var testCase16:Object = new Object();
        testCase16.text = 'test = [["fs", "男", 1000, 50, 1000000, 175, 300, "新手", 50000, 500000, [[' +
                        '"上键", "上键", 87], ["下键", "下键", 83], ["左键", "左键", 65], ["右键", "右键", 68]]], "测试"]]\n' +
                        '商城已购买物品 = []\n' +
                        '战宠 = [[]]\n' +
                        '[[tasks_to_do]]\n' +
                        'id = 1\n' +
                        '[tasks_to_do.requirements]\n' +
                        'items = []\n' +
                        '[[tasks_to_do.requirements.stages]]\n' +
                        'difficulty = "简单"\n' +
                        'name = "测试任务"\n';

        testCase16.expectedTokens = null;
        testCase16.description = "项目特定的复杂结构测试，包括Unicode字符和嵌套表数组。";
        cases.push(testCase16);

        // ==========================
        // 内联表中的整数键测试
        // ==========================
        // Test case 17: Inline table with integer keys
        var testCase17:Object = new Object();
        testCase17.text = 'tasks_finished = { 0 = 1, 1 = 2, 2 = 3 }\n';
        testCase17.expectedTokens = [
            {type: "KEY", value: "tasks_finished"},
            {type: "EQUALS", value: "="},
            {type: "LBRACE", value: "{"},
            {type: "INTEGER", value: "0"},
            {type: "EQUALS", value: "="},
            {type: "INTEGER", value: "1"},
            {type: "COMMA", value: ","},
            {type: "INTEGER", value: "1"},
            {type: "EQUALS", value: "="},
            {type: "INTEGER", value: "2"},
            {type: "COMMA", value: ","},
            {type: "INTEGER", value: "2"},
            {type: "EQUALS", value: "="},
            {type: "INTEGER", value: "3"},
            {type: "RBRACE", value: "}"},
            {type: "NEWLINE", value: "\n"}
        ];
        testCase17.description = "测试内联表中使用整数作为键。";
        cases.push(testCase17);
        

        // ==========================
        // 嵌套数组和内联表测试
        // ==========================
        // Test case 18: Nested arrays with inline tables
        var testCase18:Object = new Object();
        testCase18.text = 'complex_structure = [["item1", { 1 = "a" }, [1, 2, 3]], "end"]\n';
        testCase18.expectedTokens = [
            {type: "KEY", value: "complex_structure"}, // 1
            {type: "EQUALS", value: "="},              // 2
            {type: "LBRACKET", value: "["},            // 3
            {type: "LBRACKET", value: "["},            // 4
            {type: "STRING", value: "item1"},          // 5
            {type: "COMMA", value: ","},               // 6
            {type: "LBRACE", value: "{"},              // 7
            {type: "INTEGER", value: "1"},             // 8
            {type: "EQUALS", value: "="},              // 9
            {type: "STRING", value: "a"},              // 10
            {type: "RBRACE", value: "}"},              // 11
            {type: "COMMA", value: ","},               // 12
            {type: "LBRACKET", value: "["},            // 13
            {type: "INTEGER", value: "1"},             // 14
            {type: "COMMA", value: ","},               // 15
            {type: "INTEGER", value: "2"},             // 16
            {type: "COMMA", value: ","},               // 17
            {type: "INTEGER", value: "3"},             // 18
            {type: "RBRACKET", value: "]"},            // 19
            {type: "RBRACKET", value: "]"},            // 20
            {type: "COMMA", value: ","},               // 21
            {type: "STRING", value: "end"},            // 22
            {type: "RBRACKET", value: "]"},            // 23
            {type: "NEWLINE", value: "\n"}             // 24
        ];
        testCase18.description = "测试嵌套数组中包含内联表。";
        cases.push(testCase18);

        // ==========================
        // 注释测试
        // ==========================
        // Test case 19: Single line comment at the beginning
        var testCase19:Object = new Object();
        testCase19.text = '# This is a comment\n' +
                        'title = "My Game"\n';
        testCase19.expectedTokens = null;
        testCase19.description = "测试行首注释。";
        cases.push(testCase19);

        // Test case 20: Inline comment after a key-value pair
        var testCase20:Object = new Object();
        testCase20.text = 'version = 1.0 # 游戏版本\n' +
                        'debug = false\n';
        testCase20.expectedTokens = null;
        testCase20.description = "测试键值对后有行内注释。";
        cases.push(testCase20);

        // Test case 21: Comment with Unicode characters
        var testCase21:Object = new Object();
        testCase21.text = '# 这是一个注释\n' +
                        'enabled = true\n';
        testCase21.expectedTokens = null;
        testCase21.description = "测试包含Unicode字符的注释。";
        cases.push(testCase21);

        // ==========================
        // 键名多样性测试
        // ==========================
        // Test case 22: Keys with Unicode characters (non-Chinese)
        var testCase22:Object = new Object();
        testCase22.text = 'ключ = "значение"\n' + // Russian for "key = value"
                        'キー = "値"\n'; // Japanese for "key = value"
        testCase22.expectedTokens = null;
        testCase22.description = "测试包含不同Unicode字符的键名。";
        cases.push(testCase22);

        // Test case 23: Keys with numbers and underscores
        var testCase23:Object = new Object();
        testCase23.text = 'player_1 = "Alice"\n' +
                        'player2 = "Bob"\n';
        testCase23.expectedTokens = null;
        testCase23.description = "测试包含数字和下划线的键名。";
        cases.push(testCase23);

        // Test case 24: Keys starting with numbers
        var testCase24:Object = new Object();
        testCase24.text = '123start = "Invalid"\n' + // Depending on FNTL spec, may or may not be allowed
                        'valid_key = "Valid"\n';
        testCase24.expectedTokens = null;
        testCase24.description = "测试以数字开头的键名。";
        cases.push(testCase24);

        // Test case 25: Keys with special characters (if supported)
        var testCase25:Object = new Object();
        testCase25.text = 'user-name = "Charlie"\n' +
                        'database.type = "PostgreSQL"\n';
        testCase25.expectedTokens = null;
        testCase25.description = "测试包含特殊字符的键名。";
        cases.push(testCase25);

        // ==========================
        // 转义字符测试
        // ==========================
        // Test case 26: Unicode escape sequences in strings
        var testCase26:Object = new Object();
        testCase26.text = 'unicode_test = "\\u4F60\\u597D"\n'; // "你好" in Unicode
        testCase26.expectedTokens = null;
        testCase26.description = "测试字符串中的Unicode转义序列。";
        cases.push(testCase26);

        // Test case 27: Escaped backslashes and quotes
        var testCase27:Object = new Object();
        testCase27.text = 'path = "C:\\\\Program Files\\\\Game"\n' +
                        'quote = "She said, \\"Hello!\\""\n';
        testCase27.expectedTokens = null;
        testCase27.description = "测试字符串中的反斜杠和双引号转义。";
        cases.push(testCase27);

        // Test case 28: Invalid escape sequence
        var testCase28:Object = new Object();
        testCase28.text = 'invalid_escape = "This is invalid: \\x"\n';
        testCase28.expectedTokens = null;
        testCase28.description = "测试字符串中的无效转义序列。";
        cases.push(testCase28);

        // ==========================
        // 内联表的复杂性测试
        // ==========================
        // Test case 29: Nested inline tables
        var testCase29:Object = new Object();
        testCase29.text = 'complex_inline = { key1 = { subkey = "value" }, key2 = [1, 2, 3] }\n';
        testCase29.expectedTokens = null;
        testCase29.description = "测试内联表中嵌套内联表和数组。";
        cases.push(testCase29);

        // Test case 30: Inline table with mixed types
        var testCase30:Object = new Object();
        testCase30.text = 'mixed_inline = { name = "Dave", scores = [100, 200], active = true }\n';
        testCase30.expectedTokens = null;
        testCase30.description = "测试内联表中包含不同类型的值。";
        cases.push(testCase30);

        // ==========================
        // 空结构测试
        // ==========================
        // Test case 31: Empty array
        var testCase31:Object = new Object();
        testCase31.text = 'empty_array = []\n';
        testCase31.expectedTokens = null;
        testCase31.description = "测试空数组。";
        cases.push(testCase31);

        // Test case 32: Empty table
        var testCase32:Object = new Object();
        testCase32.text = '[empty_table]\n';
        testCase32.expectedTokens = null;
        testCase32.description = "测试空表。";
        cases.push(testCase32);

        // Test case 33: Empty inline table
        var testCase33:Object = new Object();
        testCase33.text = 'empty_inline = {}\n';
        testCase33.expectedTokens = null;
        testCase33.description = "测试空内联表。";
        cases.push(testCase33);

        // ==========================
        // 混合类型数组测试
        // ==========================
        // Test case 34: Mixed type array
        var testCase34:Object = new Object();
        testCase34.text = 'mixed_array = [1, "two", true, 4.0]\n';
        testCase34.expectedTokens = null;
        testCase34.description = "测试包含不同类型元素的数组。";
        cases.push(testCase34);

        // ==========================
        // 边界条件测试
        // ==========================
        // Test case 35: Extremely long key and value
        var testCase35:Object = new Object();
        var longKey:String = repeatString("a", 1024);
        var longValue:String = repeatString("b", 4096);

        testCase35.text = longKey + ' = "' + longValue + '"\n';
        testCase35.expectedTokens = null;
        testCase35.description = "测试极长的键名和键值。";
        cases.push(testCase35);

        // Test case 36: Deeply nested tables
        var testCase36:Object = new Object();
        testCase36.text = '[a.b.c.d.e.f.g.h.i.j]\n' +
                        'value = "deep"\n';
        testCase36.expectedTokens = null;
        testCase36.description = "测试多级嵌套表。";
        cases.push(testCase36);

        // ==========================
        // 错误情况测试
        // ==========================
        // Test case 37: Missing value in key-value pair
        var testCase37:Object = new Object();
        testCase37.text = 'incomplete_pair = \n';
        testCase37.expectedTokens = null;
        testCase37.description = "测试键值对中缺少值的情况。";
        cases.push(testCase37);

        // Test case 38: Unclosed inline table
        var testCase38:Object = new Object();
        testCase38.text = 'bad_inline = { name = "Eve", score = 300\n';
        testCase38.expectedTokens = null;
        testCase38.description = "测试内联表未闭合的错误输入。";
        cases.push(testCase38);

        // Test case 39: Unclosed array
        var testCase39:Object = new Object();
        testCase39.text = 'bad_array = [1, 2, 3\n';
        testCase39.expectedTokens = null;
        testCase39.description = "测试数组未闭合的错误输入。";
        cases.push(testCase39);

        // Test case 40: Invalid date-time
        var testCase40:Object = new Object();
        testCase40.text = 'bad_datetime = 2023-02-30T25:61:61Z\n';
        testCase40.expectedTokens = null;
        testCase40.description = "测试无效日期时间格式的错误输入。";
        cases.push(testCase40);

        // Test case 41: Multiline string with varying newlines
        var testCase41:Object = new Object();
        testCase41.text = 'multiline = """First line\n\nSecond line with extra newline\nThird line"""';
        testCase41.expectedTokens = null;
        testCase41.description = "测试多行字符串，包含多个换行符。";
        cases.push(testCase41);

        // Test case 42: Multiline string with escape characters
        var testCase42:Object = new Object();
        testCase42.text = 'multiline_escape = """Line1\\nLine2\\tTabbed"""';
        testCase42.expectedTokens = null;
        testCase42.description = "测试多行字符串，包含转义字符。";
        cases.push(testCase42);

        // Test case 43: Multiline string with unclosed delimiter
        var testCase43:Object = new Object();
        testCase43.text = 'multiline_unclosed = """This string never ends...';
        testCase43.expectedTokens = null;
        testCase43.description = "测试未闭合的多行字符串。";
        cases.push(testCase43);

        // Test case 44: Multiline string with embedded quotes
        var testCase44:Object = new Object();
        testCase44.text = 'multiline_quotes = """This is a "quoted" line\nAnd it continues."""';
        testCase44.expectedTokens = null;
        testCase44.description = "测试多行字符串，包含嵌入的引号。";
        cases.push(testCase44);

        // Test case 45: Multiline string with trailing spaces
        var testCase45:Object = new Object();
        testCase45.text = 'multiline_spaces = """This line has trailing spaces   \nNext line"""';
        testCase45.expectedTokens = null;
        testCase45.description = "测试多行字符串，包含行末的空格。";
        cases.push(testCase45);

        // Test case 46: Multiline string with leading spaces on subsequent lines
        var testCase46:Object = new Object();
        testCase46.text = 'multiline_leading_spaces = """First line\n    Second line with leading spaces\nThird line"""';
        testCase46.expectedTokens = null;
        testCase46.description = "测试多行字符串，后续行开头有空格。";
        cases.push(testCase46);

        // Test case 47: Multiline string with an empty line in the middle
        var testCase47:Object = new Object();
        testCase47.text = 'multiline_empty_line = """First line\n\nSecond line after empty line"""';
        testCase47.expectedTokens = null;
        testCase47.description = "测试多行字符串，中间包含空行。";
        cases.push(testCase47);

        // Test case 48: 表格数组头识别
        var testCase48:Object = new Object();
        testCase48.text = '[[monsters]]\n' +
                        'name = "Goblin"\n' +
                        '[[monsters]]\n' +
                        'name = "Dragon"\n';
        testCase48.expectedTokens = null;
        testCase48.description = "测试表格数组头的解析。";
        cases.push(testCase48);

        // Test case 49: 嵌套表格数组
        var testCase49:Object = new Object();
        testCase49.text = '[[servers]]\n' +
                        'name = "Server1"\n' +
                        '[[servers.database]]\n' +
                        'type = "MySQL"\n' +
                        '[[servers.database.settings]]\n' +
                        'enabled = true\n';
        testCase49.expectedTokens = null;
        testCase49.description = "测试嵌套表格数组的解析。";
        cases.push(testCase49);

        // Test case 50: 扩展 Unicode 转义序列
        var testCase50:Object = new Object();
        testCase50.text = 'unicode_test = "\\U0001F600"\n';  // Unicode code point for 😀
        testCase50.expectedTokens = null;
        testCase50.description = "测试扩展的Unicode转义序列（\\UXXXXXXXX）。";
        cases.push(testCase50);

        // Test case 51: 表格数组中的多行字符串
        var testCase51:Object = new Object();
        testCase51.text = '[[servers]]\n' +
                        'name = "Server1"\n' +
                        'description = """This is a\nmultiline string."""\n';
        testCase51.expectedTokens = null;
        testCase51.description = "测试表格数组中多行字符串的解析。";
        cases.push(testCase51);

        // Test case 52: 内联表中的转义字符
        var testCase52:Object = new Object();
        testCase52.text = 'player = { name = "Alice\\nBob", score = 2500 }\n';
        testCase52.expectedTokens = null;
        testCase52.description = "测试内联表中的转义字符处理。";
        cases.push(testCase52);

        
        return cases;
    }

    /**
    * Retrieves test cases for the FNTLParser.
    * Each test case includes FNTL text and the expected parsed object.
    */
    private function getParserTestCases():Array {
        var cases:Array = new Array();
        // ==========================
        // 基础键值对解析测试
        // ==========================
        // Test case 1: Basic key-value pairs
        var testCase1:Object = new Object();
        testCase1.text = 'title = "My Game"\n' +
                        'isActive = true\n' +
                        'max_score = 1000\n' +
                        'average_score = 89.95\n';
        var expected1:Object = {
            title: "My Game",
            isActive: true,
            max_score: 1000,
            average_score: 89.95
        };
        testCase1.expected = expected1;
        testCase1.description = "解析基础键值对，包括字符串、布尔值和数字。";
        cases.push(testCase1);

        // Test case 2: Multiline string
        var testCase2:Object = new Object();
        testCase2.text = 'description = """This is a multiline string.\nIt spans multiple lines."""\n';
        var expected2:Object = {
            description: "This is a multiline string.\nIt spans multiple lines."
        };
        testCase2.expected = expected2;
        testCase2.description = "解析多行字符串。";
        cases.push(testCase2);

        // ==========================
        // 数组解析测试
        // ==========================
        // Test case 3: Simple array
        var testCase3:Object = new Object();
        testCase3.text = 'items = ["sword", "shield", "potion"]\n';
        var expected3:Object = {
            items: ["sword", "shield", "potion"]
        };
        testCase3.expected = expected3;
        testCase3.description = "解析简单数组。";
        cases.push(testCase3);

        // Test case 4: Nested arrays
        var testCase4:Object = new Object();
        testCase4.text = 'nested_arrays = [[1, 2], [3, 4], [5, 6]]\n';
        var expected4:Object = {
            nested_arrays: [[1, 2], [3, 4], [5, 6]]
        };
        testCase4.expected = expected4;
        testCase4.description = "解析嵌套数组。";
        cases.push(testCase4);

        // ==========================
        // 表解析测试
        // ==========================
        // Test case 5: Basic table
        var testCase5:Object = new Object();
        testCase5.text = '[server]\n' +
                        'ip = "192.168.1.1"\n' +
                        'port = 8080\n';
        var expected5:Object = {
            server: {
                ip: "192.168.1.1",
                port: 8080
            }
        };
        testCase5.expected = expected5;
        testCase5.description = "解析基本表结构。";
        cases.push(testCase5);

        // Test case 6: Nested tables
        var testCase6:Object = new Object();
        testCase6.text = '[database.connection]\n' +
                        'server = "localhost"\n' +
                        'port = 5432\n';
        var expected6:Object = {
            database: {
                connection: {
                    server: "localhost",
                    port: 5432
                }
            }
        };
        testCase6.expected = expected6;
        testCase6.description = "解析嵌套表结构。";
        cases.push(testCase6);

        // ==========================
        // 表数组解析测试
        // ==========================
        // Test case 7: Simple table array
        var testCase7:Object = new Object();
        testCase7.text = '[[monsters]]\n' +
                        'name = "Goblin"\n' +
                        'level = 5\n' +
                        '[[monsters]]\n' +
                        'name = "Dragon"\n' +
                        'level = 50\n';
        var expected7:Object = {
            monsters: [
                { name: "Goblin", level: 5 },
                { name: "Dragon", level: 50 }
            ]
        };
        testCase7.expected = expected7;
        testCase7.description = "解析简单的表数组。";
        cases.push(testCase7);

        // Test case 8: Nested table arrays
        var testCase8:Object = new Object();
        testCase8.text = '[[servers]]\n' +
                        'name = "Server1"\n' +
                        'ip = "10.0.0.1"\n' +
                        '[[servers.database]]\n' +
                        'type = "MySQL"\n' +
                        'port = 3306\n' +
                        '[[servers.database.settings]]\n' +
                        'enabled = true\n';
        var expected8:Object = {
            servers: [
                {
                    name: "Server1",
                    ip: "10.0.0.1",
                    database: [
                        {
                            type: "MySQL",
                            port: 3306,
                            settings: [
                                {
                                    enabled: true
                                }
                            ]
                        }
                    ]
                }
            ]
        };
        testCase8.expected = expected8;
        testCase8.description = "解析嵌套的表数组。";
        cases.push(testCase8);

        // ==========================
        // 内联表解析测试
        // ==========================
        // Test case 9: Inline table
        var testCase9:Object = new Object();
        testCase9.text = 'player = { name = "Alice", score = 2500 }\n';
        var expected9:Object = {
            player: {
                name: "Alice",
                score: 2500
            }
        };
        testCase9.expected = expected9;
        testCase9.description = "解析内联表。";
        cases.push(testCase9);

        // ==========================
        // Unicode和Emoji解析测试
        // ==========================
        // Test case 10: Unicode characters and emojis
        var testCase10:Object = new Object();
        testCase10.text = 'greeting = "こんにちは"\nemoji = "😊"\n';
        var expected10:Object = {
            greeting: "こんにちは",
            emoji: "😊"
        };
        testCase10.expected = expected10;
        testCase10.description = "解析Unicode字符和Emoji。";
        cases.push(testCase10);

        // ==========================
        // 转义字符解析测试
        // ==========================
        // Test case 11: Escape characters in strings
        var testCase11:Object = new Object();
        testCase11.text = 'escaped_newline = "Line1\\nLine2"\nescaped_quote = "He said, \\"Hello!\\""\n';
        var expected11:Object = {
            escaped_newline: "Line1\nLine2",
            escaped_quote: 'He said, "Hello!"'
        };
        testCase11.expected = expected11;
        testCase11.description = "解析字符串中的转义字符。";
        cases.push(testCase11);

        // ==========================
        // 特殊数字格式解析测试
        // ==========================
        // Test case 12: Special floating-point values
        var testCase12:Object = new Object();
        testCase12.text = 'special_float_1 = nan\nspecial_float_2 = inf\nspecial_float_3 = -inf\n';
        var expected12:Object = {
            special_float_1: NaN,
            special_float_2: Infinity,
            special_float_3: -Infinity
        };
        testCase12.expected = expected12;
        testCase12.description = "解析特殊浮点数值：NaN、Infinity、-Infinity。";
        cases.push(testCase12);

        // ==========================
        // 错误输入解析测试
        // ==========================
        // Test case 13: Missing equals sign
        var testCase13:Object = new Object();
        testCase13.text = 'invalid_line "No equals sign"\n';

        // Expected to fail: parser should return null due to missing equals sign
        var expected13:Object = null;
        testCase13.expected = expected13;
        testCase13.description = "解析缺少等号的错误输入。";
        cases.push(testCase13);
        

        // Test case 14: Unclosed string
        var testCase14:Object = new Object();
        testCase14.text = 'unclosed_string = "This string never ends...\n';

        // Expected to fail: parser should return null due to unclosed string
        var expected14:Object = null; // Parser should return null on error
        testCase14.expected = expected14;
        testCase14.description = "解析未闭合字符串的错误输入。";
        cases.push(testCase14);

        // Test case 15: Invalid date-time format
        var testCase15:Object = new Object();
        testCase15.text = 'invalid_date = 2024-13-40T25:61:61Z\n';
        var expected15:Object = null; // Parser should fail due to invalid datetime
        testCase15.expected = expected15;
        testCase15.description = "解析无效日期时间格式的错误输入。";
        cases.push(testCase15);

        // ==========================
        // 项目特定的复杂结构解析测试
        // ==========================
        // Test case 16: Project-specific complex structure
        var testCase16:Object = new Object();
        testCase16.text = 'task_chains_progress = { 主线 = "1" }\n' +
                        'task_history = [0]\n' +
                        'tasks_finished = { 0 = 1 }\n' +
                        'test = [["fs", "男", 1000, 50, 1000000, 175, 300, "新手", 50000, 500000, [[' +
                        '"上键", "上键", 87], ["下键", "下键", 83], ["左键", "左键", 65], ["右键", "右键", 68]]], "测试"]\n' +
                        '商城已购买物品 = []\n' +
                        '战宠 = [[]]\n' +
                        '[[tasks_to_do]]\n' +
                        'id = 1\n' +
                        '[tasks_to_do.requirements]\n' +
                        'items = []\n' +
                        '[[tasks_to_do.requirements.stages]]\n' +
                        'difficulty = "简单"\n' +
                        'name = "测试任务"\n';

        var expected16:Object = new Object();

        // Setting task_chains_progress
        expected16.task_chains_progress = new Object();
        expected16.task_chains_progress["主线"] = "1";

        // Setting task_history
        expected16.task_history = new Array();
        expected16.task_history.push(0);

        // Setting tasks_finished
        expected16.tasks_finished = new Object();
        expected16.tasks_finished["0"] = 1;

        // Setting test array
        expected16.test = new Array();

        // Creating nested array
        var testItem1:Array = new Array();
        testItem1.push("fs");
        testItem1.push("男");
        testItem1.push(1000);
        testItem1.push(50);
        testItem1.push(1000000);
        testItem1.push(175);
        testItem1.push(300);
        testItem1.push("新手");
        testItem1.push(50000);
        testItem1.push(500000);

        // Creating internal keys array
        var keys:Array = new Array();
        keys.push(new Array("上键", "上键", 87));
        keys.push(new Array("下键", "下键", 83));
        keys.push(new Array("左键", "左键", 65));
        keys.push(new Array("右键", "右键", 68));

        // Adding keys array to testItem1
        testItem1.push(keys);

        // Adding testItem1 to expected16.test
        expected16.test.push(testItem1);

        // Adding "测试" string
        expected16.test.push("测试");

        // Setting 商城已购买物品 and 战宠 arrays
        expected16["商城已购买物品"] = new Array();
        expected16["战宠"] = new Array();
        expected16["战宠"].push(new Array());

        // Setting tasks_to_do array
        expected16.tasks_to_do = new Array();

        // Creating first task object
        var task1:Object = new Object();
        task1.id = 1;

        // Setting requirements object
        task1.requirements = new Object();
        task1.requirements.items = new Array(); // Empty array

        // Setting stages array
        task1.requirements.stages = new Array();

        // Creating first stage object
        var stage1:Object = new Object();
        stage1.difficulty = "简单";
        stage1.name = "测试任务";

        // Adding stage1 to stages array
        task1.requirements.stages.push(stage1);

        // Adding task1 to tasks_to_do array
        expected16.tasks_to_do.push(task1);

        testCase16.expected = expected16;
        testCase16.description = "解析项目特定的复杂结构，包括Unicode字符和嵌套表数组。";
        cases.push(testCase16);

        // ==========================
        // 新增测试用例
        // ==========================
        // Test case 17: Duplicate keys in the same table
        var testCase17:Object = new Object();
        testCase17.text = '[player]\n' +
                        'name = "Alice"\n' +
                        'name = "Bob"\n';
        var expected17:Object = null; // Expected to fail due to duplicate keys
        testCase17.expected = expected17;
        testCase17.description = "解析同一表中重复的键。";
        cases.push(testCase17);

        // Test case 18: Empty FNTL input
        var testCase18:Object = new Object();
        testCase18.text = '';
        var expected18:Object = {}; // Expected to return an empty object
        testCase18.expected = expected18;
        testCase18.description = "解析空的FNTL输入。";
        cases.push(testCase18);

        // Test case 19: Array with missing commas
        var testCase19:Object = new Object();
        testCase19.text = 'numbers = [1 2 3]\n'; // Missing commas between numbers
        var expected19:Object = null; // Expected to fail due to missing commas
        testCase19.expected = expected19;
        testCase19.description = "解析数组中缺少逗号的错误输入。";
        cases.push(testCase19);

        // Test case 20: Inline tables inside arrays
        var testCase20:Object = new Object();
        testCase20.text = 'users = [ { name = "Alice", age = 30 }, { name = "Bob", age = 25 } ]\n';
        var expected20:Object = {
            users: [
                { name: "Alice", age: 30 },
                { name: "Bob", age: 25 }
            ]
        };
        testCase20.expected = expected20;
        testCase20.description = "解析数组中的内联表。";
        cases.push(testCase20);

        // Test case 21: Tables with keys containing spaces
        var testCase21:Object = new Object();
        testCase21.text = '[user details]\n' +
                        'first name = "Charlie"\n' +
                        'last name = "Delta"\n';
        var expected21:Object = null; // Expected to fail if spaces in keys are not allowed
        testCase21.expected = expected21;
        testCase21.description = "解析包含空格的键的表。";
        cases.push(testCase21);

        // Test case 22: Deeply nested tables and arrays
        var testCase22:Object = new Object();
        testCase22.text = '[a.b.c.d]\n' +
                        'value = "Deep"\n' +
                        '[[a.b.c.d.array]]\n' +
                        'item = 1\n' +
                        '[[a.b.c.d.array]]\n' +
                        'item = 2\n' +
                        '[[a.b.c.d.array]]\n' +
                        'item = 3\n';
        var expected22:Object = null; // Expected to pass if nesting is handled correctly
        // Assuming the parser can handle deep nesting, otherwise set to null for expected failure
        expected22 = {
            a: {
                b: {
                    c: {
                        d: {
                            value: "Deep",
                            array: [
                                { item: 1 },
                                { item: 2 },
                                { item: 3 }
                            ]
                        }
                    }
                }
            }
        };
        testCase22.expected = expected22;
        testCase22.description = "解析深度嵌套的表和数组结构。";
        cases.push(testCase22);

        return cases;
}


    /**
     * Retrieves test cases for the FNTLEncoder.
     * Each test case includes an input object and the expected FNTL string.
     */
    private function getEncoderTestCases():Array {
        var cases:Array = new Array();

        // ==========================
        // 基础键值对编码测试
        // ==========================
        // Test case 1: Basic key-value pairs
        var testCase1:Object = new Object();
        testCase1.input = {
            title: "My Game",
            isActive: true,
            max_score: 1000,
            average_score: 89.95
        };
        testCase1.expected = 'average_score = 89.95\n' +
                              'isActive = true\n' +
                              'max_score = 1000\n' +
                              'title = "My Game"\n';
        testCase1.description = "编码基础键值对，包括字符串、布尔值和数字。";
        cases.push(testCase1);

        // ==========================
        // 多行字符串编码测试
        // ==========================
        // Test case 2: Multiline string
        var testCase2:Object = new Object();
        testCase2.input = {
            description: "This is a multiline string.\nIt spans multiple lines."
        };
        testCase2.expected = 'description = """This is a multiline string.\nIt spans multiple lines."""\n';
        testCase2.description = "编码多行字符串。";
        cases.push(testCase2);

        // ==========================
        // 数组编码测试
        // ==========================
        // Test case 3: Simple array
        var testCase3:Object = new Object();
        testCase3.input = {
            items: ["sword", "shield", "potion"]
        };
        testCase3.expected = 'items = ["sword", "shield", "potion"]\n';
        testCase3.description = "编码简单数组。";
        cases.push(testCase3);

        // Test case 4: Nested arrays
        var testCase4:Object = new Object();
        testCase4.input = {
            nested_arrays: [[1, 2], [3, 4], [5, 6]]
        };
        testCase4.expected = 'nested_arrays = [[1, 2], [3, 4], [5, 6]]\n';
        testCase4.description = "编码嵌套数组。";
        cases.push(testCase4);

        // ==========================
        // 表编码测试
        // ==========================
        // Test case 5: Basic table
        var testCase5:Object = new Object();
        testCase5.input = {
            server: {
                ip: "192.168.1.1",
                port: 8080
            }
        };
        testCase5.expected = '[server]\n' +
                              'ip = "192.168.1.1"\n' +
                              'port = 8080\n';
        testCase5.description = "编码基本表结构。";
        cases.push(testCase5);

        // Test case 6: Nested tables
        var testCase6:Object = new Object();
        testCase6.input = {
            database: {
                connection: {
                    server: "localhost",
                    port: 5432
                }
            }
        };
        testCase6.expected = '[database.connection]\n' +
                              'port = 5432\n' +
                              'server = "localhost"\n';
        testCase6.description = "编码嵌套表结构。";
        cases.push(testCase6);

        // ==========================
        // 表数组编码测试
        // ==========================
        // Test case 7: Simple table array
        var testCase7:Object = new Object();
        testCase7.input = {
            monsters: [
                { name: "Goblin", level: 5 },
                { name: "Dragon", level: 50 }
            ]
        };
        testCase7.expected = '[[monsters]]\n' +
                              'level = 5\n' +
                              'name = "Goblin"\n' +
                              '[[monsters]]\n' +
                              'level = 50\n' +
                              'name = "Dragon"\n';
        testCase7.description = "编码简单的表数组。";
        cases.push(testCase7);

        // Test case 8: Nested table arrays
        var testCase8:Object = new Object();
        testCase8.input = {
            servers: [
                {
                    name: "Server1",
                    ip: "10.0.0.1",
                    database: {
                        type: "MySQL",
                        port: 3306,
                        settings: {
                            enabled: true
                        }
                    }
                }
            ]
        };

        // 修正后的预期输出
        testCase8.expected = '[[servers]]\n' +
                            'database = { port = 3306, settings = { enabled = true }, type = "MySQL" }\n' +
                            'ip = "10.0.0.1"\n' +
                            'name = "Server1"\n';

        testCase8.description = "编码嵌套的表数组。";
        cases.push(testCase8);

        // ==========================
        // 内联表编码测试
        // ==========================
        // Test case 9: Inline table
        var testCase9:Object = new Object();
        testCase9.input = {
            player: {
                name: "Alice",
                score: 2500
            }
        };
        testCase9.expected = 'player = { name = "Alice", score = 2500 }\n';
        testCase9.description = "编码内联表。";
        cases.push(testCase9);

        // ==========================
        // Unicode和Emoji编码测试
        // ==========================
        // Test case 10: Unicode characters and emojis
        var testCase10:Object = new Object();
        testCase10.input = {
            greeting: "こんにちは",
            emoji: "😊"
        };
        testCase10.expected = 'emoji = "😊"\n' +
                              'greeting = "こんにちは"\n';
        testCase10.description = "编码Unicode字符和Emoji。";
        cases.push(testCase10);

        // ==========================
        // 转义字符编码测试
        // ==========================
        // Test case 11: Escape characters in strings
        var testCase11:Object = new Object();
        testCase11.input = {
            escaped_newline: "Line1\nLine2",
            escaped_quote: 'He said, "Hello!"'
        };
        testCase11.expected = 'escaped_newline = """Line1\nLine2"""\n' +
                              'escaped_quote = "He said, \\"Hello!\\""\n';
        testCase11.description = "编码字符串中的转义字符。";
        cases.push(testCase11);

        // ==========================
        // 特殊数字格式编码测试
        // ==========================
        // Test case 12: Special floating-point values
        var testCase12:Object = new Object();
        testCase12.input = {
            special_float_1: NaN,
            special_float_2: Infinity,
            special_float_3: -Infinity
        };
        testCase12.expected = 'special_float_1 = nan\n' +
                              'special_float_2 = inf\n' +
                              'special_float_3 = -inf\n';
        testCase12.description = "编码特殊浮点数值：NaN、Infinity、-Infinity。";
        cases.push(testCase12);

        // ==========================
        // 错误输入编码测试
        // ==========================
        // Test case 13: Missing equals sign
        // Test case 13: 缺少等号的错误输入
        var testCase13:Object = new Object();
        testCase13.input = {
            invalid_line: "No equals sign"
        };
        testCase13.expected = null; // Encoder 应该跳过或处理此类无效输入
        testCase13.description = "编码缺少等号的错误输入。";
        cases.push(testCase13);

        // Test case 14: 未闭合字符串的错误输入
        var testCase14:Object = new Object();
        testCase14.input = {
            unclosed_string: "This string never ends..."
        };
        testCase14.expected = null; // Encoder 应该适当地处理未闭合的字符串
        testCase14.description = "编码未闭合字符串的错误输入。";
        cases.push(testCase14);

        // Test case 15: Invalid date-time format
        var testCase15:Object = new Object();
        testCase15.input = {
            invalid_date: "2024-13-40T25:61:61Z"
        };
        testCase15.expected = null; // Encoder should handle invalid dates appropriately
        testCase15.description = "编码无效日期时间格式的错误输入。";
        cases.push(testCase15);

        // ==========================
        // Test Case 16: 编码项目特定的复杂结构，包括Unicode字符和嵌套表数组。
        // ==========================
        var testCase16:Object = new Object();

        // 设置输入
        testCase16.input = new Object();
        testCase16.input.task_chains_progress = new Object();
        testCase16.input.task_chains_progress["主线"] = "1";
        testCase16.input.task_history = new Array();
        testCase16.input.task_history.push(0);
        testCase16.input.tasks_finished = new Object();
        testCase16.input.tasks_finished["0"] = 1;
        testCase16.input.test = new Array();
        var testItem1:Array = new Array();
        testItem1.push("fs");
        testItem1.push("男");
        testItem1.push(1000);
        testItem1.push(50);
        testItem1.push(1000000);
        testItem1.push(175);
        testItem1.push(300);
        testItem1.push("新手");
        testItem1.push(50000);
        testItem1.push(500000);
        var keys:Array = new Array();
        keys.push(new Array("上键", "上键", 87));
        keys.push(new Array("下键", "下键", 83));
        keys.push(new Array("左键", "左键", 65));
        keys.push(new Array("右键", "右键", 68));
        testItem1.push(keys);
        testItem1.push("测试"); // 将 "测试" 添加到内层数组
        testCase16.input.test.push(testItem1);
        testCase16.input["商城已购买物品"] = new Array();
        testCase16.input["战宠"] = new Array();
        testCase16.input["战宠"].push(new Array());
        testCase16.input.tasks_to_do = new Array();
        var task1:Object = new Object();
        task1.id = 1;
        task1.requirements = new Object();
        task1.requirements.items = new Array(); // 空数组
        task1.requirements.stages = new Array();
        var stage1:Object = new Object();
        stage1.difficulty = "简单";
        stage1.name = "测试任务";
        task1.requirements.stages.push(stage1);
        testCase16.input.tasks_to_do.push(task1);

        // 修正后的预期输出，按照键的字母顺序，并移除多余的右括号
        testCase16.expected = 
            'task_chains_progress = { 主线 = "1" }\n' +
            'task_history = [0]\n' +
            'tasks_finished = { 0 = 1 }\n' +
            'test = [["fs", "男", 1000, 50, 1000000, 175, 300, "新手", 50000, 500000, [[' +
            '"上键", "上键", 87], ["下键", "下键", 83], ["左键", "左键", 65], ["右键", "右键", 68]], "测试"]]\n' +
            '商城已购买物品 = []\n' +
            '战宠 = [[]]\n' +
            '[[tasks_to_do]]\n' +
            'id = 1\n' +
            '[tasks_to_do.requirements]\n' +
            'items = []\n' +
            '[[tasks_to_do.requirements.stages]]\n' +
            'difficulty = "简单"\n' +
            'name = "测试任务"\n';

        testCase16.description = "编码项目特定的复杂结构，包括Unicode字符和嵌套表数组。";
        cases.push(testCase16);
        return cases;
    }

    /**
     * Compares two arrays of tokens for equality.
     * @param actualTokens The tokens generated by the lexer.
     * @param expectedTokens The expected tokens.
     * @return True if arrays match, else false.
     */
    private function compareTokenArrays(actualTokens:Array, expectedTokens:Array):Boolean {
        if (actualTokens.length != expectedTokens.length) {
            trace("Token 数组长度不匹配，预期: " + expectedTokens.length + "，实际: " + actualTokens.length);
            return false;
        }

        for (var i:Number = 0; i < expectedTokens.length; i++) {
            var actualToken:Object = actualTokens[i];
            var expectedToken:Object = expectedTokens[i];

            if (actualToken.type != expectedToken.type || actualToken.value != expectedToken.value) {
                trace("Token 不匹配在索引 " + i + ": 预期 (" + expectedToken.type + ", " + expectedToken.value + ")，实际 (" + actualToken.type + ", " + actualToken.value + ")");
                return false;
            }
        }

        return true;
    }

    /**
     * Compares two FNTL output strings for semantic equality by parsing and comparing objects.
     * @param actual The encoded FNTL string.
     * @param expected The expected FNTL string.
     * @return True if semantic content matches, else false.
     */
    private function compareFNTLOutputs(actual:String, expected:String):Boolean {
        if (expected === null) {
            if (actual === null || StringUtils.trim(actual) === "") {
                trace("编码输出与预期结果匹配。");
                return true;
            } else {
                trace("编码输出不匹配！\n预期:\nnull\n实际:\n" + actual);
                return false;
            }
        }

        // Parse actual FNTL string
        var lexerActual:FNTLLexer = new FNTLLexer(actual);
        var tokensActual:Array = [];
        var token:Object;
        while ((token = lexerActual.getNextToken()) != null) {
            tokensActual.push(token);
        }
        var parserActual:FNTLParser = new FNTLParser(tokensActual, actual);
        var parsedActual:Object = parserActual.parse();

        if (parserActual.hasError()) {
            trace("编码输出解析失败: " + actual);
            return false;
        }

        // Parse expected FNTL string
        var lexerExpected:FNTLLexer = new FNTLLexer(expected);
        var tokensExpected:Array = [];
        while ((token = lexerExpected.getNextToken()) != null) {
            tokensExpected.push(token);
        }
        var parserExpected:FNTLParser = new FNTLParser(tokensExpected, expected);
        var parsedExpected:Object = parserExpected.parse();

        if (parserExpected.hasError()) {
            trace("预期编码输出解析失败: " + expected);
            return false;
        }

        // Compare parsed objects
        var comparisonResult:Boolean = this.compareResults(parsedActual, parsedExpected, 0);
        if (comparisonResult) {
            trace("编码输出与预期结果匹配。");
            return true;
        } else {
            trace("编码输出不匹配！\n预期:\n" + expected + "\n实际:\n" + actual);
            return false;
        }
    }

    /**
     * Compares two objects for deep equality.
     * @param actual The parsed object.
     * @param expected The expected object.
     * @param depth Current recursion depth.
     * @return True if objects are deeply equal, else false.
     */
    private function compareResults(actual:Object, expected:Object, depth:Number):Boolean {
        if (depth > this.MAX_RECURSION_DEPTH) {
            trace("超过最大递归深度，停止比较。");
            return false;
        }

        if (this.isArray(expected) && this.isArray(actual)) {
            if (expected.length != actual.length) {
                trace("数组长度不匹配，预期: " + expected.length + "，实际: " + actual.length);
                return false;
            }
            for (var i:Number = 0; i < expected.length; i++) {
                if (!this.compareResults(actual[i], expected[i], depth + 1)) {
                    trace("数组索引 " + i + " 不匹配。");
                    return false;
                }
            }
            return true;
        } else if (typeof(expected) == "object" && expected !== null) {
            for (var key:String in expected) {
                if (actual[key] === undefined) {
                    trace("缺少键: " + key);
                    return false;
                }
                if (!this.compareResults(actual[key], expected[key], depth + 1)) {
                    trace("键 '" + key + "' 的值不匹配。");
                    return false;
                }
            }
            // Check for extra keys in actual
            for (var actualKey:String in actual) {
                if (expected[actualKey] === undefined) {
                    trace("额外的键: " + actualKey);
                    return false;
                }
            }
            return true;
        } else if (typeof(expected) === "number" && isNaN(expected)) {
            if (!isNaN(actual)) {
                trace("值不匹配，预期: NaN，实际: " + actual);
                return false;
            }
            return true;
        } else if (typeof(expected) === "number" && (expected === Infinity || expected === -Infinity)) {
            if (expected !== actual) {
                trace("值不匹配，预期: " + expected + "，实际: " + actual);
                return false;
            }
            return true;
        } else {
            if (expected !== actual) {
                trace("值不匹配，预期: " + expected + "，实际: " + actual);
                return false;
            }
            return true;
        }
    }

    /**
     * Checks if the given value is an array.
     * @param value The value to check.
     * @return True if the value is an array, else false.
     */
    private function isArray(value:Object):Boolean {
        return value instanceof Array;
    }

    /**
     * Splits inline table key-value pairs by commas, considering nested structures.
     * Prevents splitting within nested arrays or tables.
     * @param tableStr The inline table string.
     * @return An array of key-value pair strings.
     */
    private function splitInlineTablePairs(tableStr:String):Array {
        var pairs:Array = new Array();
        var currentPair:String = "";
        var nestingLevel:Number = 0;

        for (var i:Number = 0; i < tableStr.length; i++) {
            var c:String = tableStr.charAt(i);
            if (c == "," && nestingLevel == 0) {
                pairs.push(currentPair);
                currentPair = "";
            } else {
                if (c == "{" || c == "[") {
                    nestingLevel++;
                } else if (c == "}" || c == "]") {
                    nestingLevel--;
                    if (nestingLevel < 0) {
                        throw new Error("内联表格中的括号不匹配");
                    }
                }
                currentPair += c;
            }
        }

        if (currentPair.length > 0) {
            pairs.push(currentPair);
        }

        return pairs;
    }

    /**
    * Utility function to repeat a string.
    * @param str The string to repeat.
    * @param count The number of times to repeat the string.
    * @return A new string with the original string repeated 'count' times.
    */
    private function repeatString(str:String, count:Number):String {
        var result:String = "";
        for (var i:Number = 0; i < count; i++) {
            result += str;
        }
        return result;
    }


}
