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
            var encoder:FNTLEncoder = new FNTLEncoder();
            var FNTLOutput:String = encoder.encode(testObj, true); // true for pretty formatting

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
            {type: "KEY", value: "complex_structure"},
            {type: "EQUALS", value: "="},
            {type: "LBRACKET", value: "["},
            {type: "LBRACKET", value: "["},
            {type: "STRING", value: "item1"},
            {type: "COMMA", value: ","},
            {type: "LBRACE", value: "{"},
            {type: "INTEGER", value: "1"},
            {type: "EQUALS", value: "="},
            {type: "STRING", value: "a"},
            {type: "RBRACE", value: "}"},
            {type: "COMMA", value: ","},
            {type: "LBRACKET", value: "["},
            {type: "INTEGER", value: "1"},
            {type: "COMMA", value: ","},
            {type: "INTEGER", value: "2"},
            {type: "COMMA", value: ","},
            {type: "INTEGER", value: "3"},
            {type: "RBRACKET", value: "]"},
            {type: "RBRACKET", value: "]"},
            {type: "COMMA", value: ","},
            {type: "STRING", value: "end"},
            {type: "RBRACKET", value: "]"},
            {type: "NEWLINE", value: "\n"}
        ];
        testCase18.description = "测试嵌套数组中包含内联表。";
        cases.push(testCase18);
        
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

        // 预期解析错误，解析器应返回 null，因为缺少等号
        var expected13:Object = null;
        testCase13.expected = expected13;
        testCase13.description = "解析缺少等号的错误输入。";
        cases.push(testCase13);


        // Test case 14: Unclosed string
        var testCase14:Object = new Object();
        testCase14.text = 'unclosed_string = "This string never ends...\n';

        // 预期结果为 null 或者不包含 'unclosed_string' 键
        var expected14:Object = null; // 解析器在错误时返回 null
        testCase14.expected = expected14;
        testCase14.description = "解析未闭合字符串的错误输入。";
        cases.push(testCase14);

        // Test case 15: Invalid date-time format
        var testCase15:Object = new Object();
        testCase15.text = 'invalid_date = 2024-13-40T25:61:61Z\n';
        var expected15:Object = {
            invalid_date: "2024-13-40T25:61:61Z" // Depending on parser's handling
        };
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
                        '"上键", "上键", 87], ["下键", "下键", 83], ["左键", "左键", 65], ["右键", "右键", 68]]], "测试"],\n' +
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

        // 设置 task_chains_progress
        expected16.task_chains_progress = new Object();
        expected16.task_chains_progress["主线"] = "1";

        // 设置 task_history
        expected16.task_history = new Array();
        expected16.task_history.push(0);

        // 设置 tasks_finished
        expected16.tasks_finished = new Object();
        expected16.tasks_finished["0"] = 1;

        // 设置 test 数组
        expected16.test = new Array();

        // 创建嵌套数组
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

        // 创建内部的按键数组
        var keys:Array = new Array();
        keys.push(new Array("上键", "上键", 87));
        keys.push(new Array("下键", "下键", 83));
        keys.push(new Array("左键", "左键", 65));
        keys.push(new Array("右键", "右键", 68));

        // 将按键数组添加到 testItem1
        testItem1.push(keys);

        // 将 testItem1 添加到 expected16.test
        expected16.test.push(testItem1);

        // 添加 "测试" 字符串
        expected16.test.push("测试");

        // 设置商城已购买物品和战宠数组
        expected16["商城已购买物品"] = new Array();
        expected16["战宠"] = new Array();
        expected16["战宠"].push(new Array());

        // 设置 tasks_to_do 数组
        expected16.tasks_to_do = new Array();

        // 创建第一个任务对象
        var task1:Object = new Object();
        task1.id = 1;

        // 设置 requirements 对象
        task1.requirements = new Object();
        task1.requirements.items = new Array(); // 空数组

        // 设置 stages 数组
        task1.requirements.stages = new Array();

        // 创建第一个 stage 对象
        var stage1:Object = new Object();
        stage1.difficulty = "简单";
        stage1.name = "测试任务";

        // 将 stage1 添加到 stages 数组
        task1.requirements.stages.push(stage1);

        // 将 task1 添加到 tasks_to_do 数组
        expected16.tasks_to_do.push(task1);

        testCase16.expected = expected16;
        testCase16.description = "解析项目特定的复杂结构，包括Unicode字符和嵌套表数组。";
        cases.push(testCase16);

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
        testCase8.expected = '[[servers]]\n' +
                              'database = { enabled = true, port = 3306, type = "MySQL" }\n' +
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
        var testCase13:Object = new Object();
        testCase13.input = {
            invalid_line: "No equals sign"
        };
        testCase13.expected = null; // Encoder should skip or handle invalid entries
        testCase13.description = "编码缺少等号的错误输入。";
        cases.push(testCase13);

        // Test case 14: Unclosed string
        var testCase14:Object = new Object();
        testCase14.input = {
            unclosed_string: "This string never ends..."
        };
        testCase14.expected = null; // Encoder should handle invalid strings appropriately
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
        // 项目特定的复杂结构编码测试
        // ==========================
        // Test case 16: Project-specific complex structure
        var testCase16:Object = new Object();
        testCase16.input = new Object();

        // 设置 task_chains_progress
        testCase16.input.task_chains_progress = new Object();
        testCase16.input.task_chains_progress["主线"] = "1";

        // 设置 task_history
        testCase16.input.task_history = new Array();
        testCase16.input.task_history.push(0);

        // 设置 tasks_finished
        testCase16.input.tasks_finished = new Object();
        testCase16.input.tasks_finished["0"] = 1;

        // 设置 test 数组
        testCase16.input.test = new Array();

        // 创建嵌套数组
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

        // 创建内部的按键数组
        var keys:Array = new Array();
        keys.push(new Array("上键", "上键", 87));
        keys.push(new Array("下键", "下键", 83));
        keys.push(new Array("左键", "左键", 65));
        keys.push(new Array("右键", "右键", 68));

        // 将按键数组添加到 testItem1
        testItem1.push(keys);

        // 将 testItem1 添加到 test 数组中
        testCase16.input.test.push(testItem1);

        // 添加 "测试" 字符串到 test 数组中
        testCase16.input.test.push("测试");

        // 设置商城已购买物品和战宠
        testCase16.input["商城已购买物品"] = new Array();
        testCase16.input["战宠"] = new Array();
        testCase16.input["战宠"].push(new Array());

        // 设置 tasks_to_do 数组
        testCase16.input.tasks_to_do = new Array();

        // 创建第一个任务对象
        var task1:Object = new Object();
        task1.id = 1;

        // 设置 requirements 对象
        task1.requirements = new Object();
        task1.requirements.items = new Array(); // 空数组

        // 设置 stages 数组
        task1.requirements.stages = new Array();

        // 创建第一个 stage 对象
        var stage1:Object = new Object();
        stage1.difficulty = "简单";
        stage1.name = "测试任务";

        // 将 stage1 添加到 stages 数组
        task1.requirements.stages.push(stage1);

        // 将 task1 添加到 tasks_to_do 数组
        testCase16.input.tasks_to_do.push(task1);
        testCase16.expected = '[[tasks_to_do]]\n' +
                               'id = 1\n' +
                               '[tasks_to_do.requirements]\n' +
                               'items = []\n' +
                               '[[tasks_to_do.requirements.stages]]\n' +
                               'difficulty = "简单"\n' +
                               'name = "测试任务"\n' +
                               'task_chains_progress = { 主线 = "1" }\n' +
                               'task_history = [0]\n' +
                               'tasks_finished = { 0 = 1 }\n' +
                               'test = [["fs", "男", 1000, 50, 1000000, 175, 300, "新手", 50000, 500000, [[' +
                               '"上键", "上键", 87], ["下键", "下键", 83], ["左键", "左键", 65], ["右键", "右键", 68]]], "测试"]]\n' +
                               '商城已购买物品 = []\n' +
                               '战宠 = [[]]\n';
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

}
