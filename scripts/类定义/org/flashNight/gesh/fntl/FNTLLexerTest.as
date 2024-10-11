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

    /**
     * Runs all the test cases for FNTLLexer, FNTLParser, and FNTLEncoder.
     */
    public function runAllTests():Void {
        trace("=== Running FNTLLexer Tests ===");
        this.testLexer();

        trace("\n=== Running FNTLParser Tests ===");
        this.testParser();

        trace("\n=== Running FNTLEncoder Tests ===");
        this.testFNTLEncoder();

        // Summary of test results
        trace("\n=== Test Summary ===");
        trace("Total Tests: " + this.totalTests);
        trace("Passed Tests: " + this.passedTests);
        trace("Failed Tests: " + this.failedTests);
    }

    /**
     * Tests the FNTLLexer by tokenizing FNTL/FNTL inputs and validating tokens.
     */
    private function testLexer():Void {
        var FNTLSamples:Array = this.getLexerTestCases();

        for (var i:Number = 0; i < FNTLSamples.length; i++) {
            var FNTLText:String = FNTLSamples[i].text;
            var expectedTokens:Array = FNTLSamples[i].expectedTokens;
            var description:String = FNTLSamples[i].description;

            trace("\n--- Running Lexer Test Case " + (i + 1) + " ---");
            trace("Description: " + description);

            var lexer:FNTLLexer = new FNTLLexer(FNTLText);
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
     * Tests the FNTLParser by parsing tokenized FNTL/FNTL inputs and validating output objects.
     */
    private function testParser():Void {
        var FNTLSamples:Array = this.getParserTestCases();

        for (var i:Number = 0; i < FNTLSamples.length; i++) {
            var FNTLText:String = FNTLSamples[i].text;
            var expected:Object = FNTLSamples[i].expected;
            var description:String = FNTLSamples[i].description;

            trace("\n--- Running Parser Test Case " + (i + 1) + " ---");
            trace("Description: " + description);

            var lexer:FNTLLexer = new FNTLLexer(FNTLText);
            var tokens:Array = [];
            var token:Object;

            // Tokenize the input
            while ((token = lexer.getNextToken()) != null) {
                tokens.push(token);
            }

            // Parse the tokens
            var parser:FNTLParser = new FNTLParser(tokens, FNTLText);
            var result:Object = parser.parse();

            // Check for parsing errors
            if (parser.hasError()) {
                trace("Parser Test Case " + (i + 1) + ": Failed with parsing errors.");
                this.failedTests++;
                this.totalTests++;
                continue;
            }

            // Compare the parsed result with expected output
            var comparisonResult:Boolean = this.compareResults(result, expected, 0);
            if (comparisonResult) {
                trace("Parser Test Case " + (i + 1) + ": Passed.");
                this.passedTests++;
            } else {
                trace("Parser Test Case " + (i + 1) + ": Failed.");
                this.failedTests++;
            }
            this.totalTests++;
        }
    }

    /**
     * Tests the FNTLEncoder by encoding objects into FNTL/FNTL strings and validating outputs.
     */
    private function testFNTLEncoder():Void {
        var testCases:Array = this.getEncoderTestCases();

        for (var i:Number = 0; i < testCases.length; i++) {
            var testObj:Object = testCases[i].input;
            var expected:String = testCases[i].expected;
            var description:String = testCases[i].description;

            trace("\n--- Running Encoder Test Case " + (i + 1) + " ---");
            trace("Description: " + description);

            // Encode the object into FNTL/FNTL
            var encoder:FNTLEncoder = new FNTLEncoder();
            var FNTLOutput:String = encoder.encode(testObj, true); // true for pretty formatting

            // Compare the encoded output with expected FNTL/FNTL string
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

        // Test case 1: Basic FNTL structure
        var testCase1:Object = new Object();
        testCase1.text = 'title = "My Game" # Comment\n' +
                        'isActive = true\n' +
                        'max_score = 1000\n' +
                        'average_score = 89.95\n' +
                        'launch_time = 2024-10-09T08:30:00Z\n' +
                        'items = ["sword", "shield", "potion"]\n' +
                        'description = """This is a multiline string.\nIt has multiple lines."""\n';
        testCase1.expectedTokens = null; // Optional: Define expected tokens for this test
        testCase1.description = "Basic FNTL structure with various data types and a multiline string.";
        cases.push(testCase1);

        // Test case 2: Boolean values
        var testCase2:Object = new Object();
        testCase2.text = 'boolean_true = true\nboolean_false = false\n';
        testCase2.expectedTokens = null;
        testCase2.description = "Testing boolean values: true and false.";
        cases.push(testCase2);

        // Test case 3: Numbers
        var testCase3:Object = new Object();
        testCase3.text = 'integer = 42\nnegative_integer = -42\nfloat = 3.14\nnegative_float = -3.14\n';
        testCase3.expectedTokens = null;
        testCase3.description = "Testing integer and float numbers, including negative values.";
        cases.push(testCase3);

        // Test case 4: Empty values
        var testCase4:Object = new Object();
        testCase4.text = 'empty_string = ""\nempty_array = []\nnull_value = null\n';
        testCase4.expectedTokens = null;
        testCase4.description = "Testing empty string, empty array, and null value.";
        cases.push(testCase4);

        // Test case 5: Date and time
        var testCase5:Object = new Object();
        testCase5.text = 'date_time = 2024-10-09T08:30:00Z\n';
        testCase5.expectedTokens = null;
        testCase5.description = "Testing date and time in ISO8601 format.";
        cases.push(testCase5);

        // Test case 6: Nested tables
        var testCase6:Object = new Object();
        testCase6.text = '[server]\n' +
                        'ip = "192.168.1.1"\n' +
                        '[server.database]\n' +
                        'type = "PostgreSQL"\n' +
                        'ports = [5432, 5433, 5434]\n' +
                        '[server.database.settings]\n' +
                        'enabled = true\n';
        testCase6.expectedTokens = null;
        testCase6.description = "Testing nested tables with multiple levels.";
        cases.push(testCase6);

        // Test case 7: Table arrays
        var testCase7:Object = new Object();
        testCase7.text = '[[products]]\n' +
                        'name = "Hammer"\n' +
                        'sku = 738594937\n' +
                        '[[products]]\n' +
                        'name = "Nail"\n' +
                        'sku = 284758393\n';
        testCase7.expectedTokens = null;
        testCase7.description = "Testing table arrays with multiple entries.";
        cases.push(testCase7);

        // Test case 8: Complex nested tables and table arrays
        var testCase8:Object = new Object();
        testCase8.text = 'title = "FNTL Example"\n' +
                        'owner = { name = "Tom", dob = 1979-05-27 }\n' +
                        '[[products]]\n' +
                        'name = "Hammer"\n' +
                        'sku = 738594937\n' +
                        '[[products]]\n' +
                        'name = "Nail"\n' +
                        'sku = 284758393\n' +
                        '[database]\n' +
                        'server = "192.168.1.1"\n' +
                        'ports = [8001, 8001, 8002]\n' +
                        'connection_max = 5000\n' +
                        'enabled = true\n';
        testCase8.expectedTokens = null;
        testCase8.description = "Testing complex nested tables and table arrays.";
        cases.push(testCase8);

        // Test case 9: Unicode characters
        var testCase9:Object = new Object();
        testCase9.text = 'greeting = "こんにちは"\nemoji = "😊"\n';
        testCase9.expectedTokens = null;
        testCase9.description = "Testing Unicode characters and emojis.";
        cases.push(testCase9);

        // Test case 10: Escape characters
        var testCase10:Object = new Object();
        testCase10.text = 'escaped_newline = "Line1\\nLine2"\nescaped_quote = "He said, \\"Hello!\\""\n';
        testCase10.expectedTokens = null;
        testCase10.description = "Testing escape characters in strings.";
        cases.push(testCase10);

        // Test case 11: Mixed complex structures
        var testCase11:Object = new Object();
        testCase11.text = '[server]\n' +
                        'host = "localhost"\n' +
                        'ports = [8000, 8001, 8002]\n' +
                        'connection_max = 5000\n' +
                        'enabled = true\n' +
                        '[[owners]]\n' +
                        'name = "Alice"\n' +
                        'dob = "1990-01-01"\n' +
                        '[[owners]]\n' +
                        'name = "Bob"\n' +
                        'dob = "1985-05-12"\n' +
                        '[database]\n' +
                        'server = "192.168.1.100"\n' +
                        'ports = [3306]\n' +
                        'connection_max = 10000\n' +
                        'enabled = false\n' +
                        '[[users]]\n' +
                        'name = "user1"\n' +
                        'active = true\n' +
                        '[[users]]\n' +
                        'name = "user2"\n' +
                        'active = false\n';
        testCase11.expectedTokens = null;
        testCase11.description = "Testing mixed complex structures with multiple table arrays.";
        cases.push(testCase11);

        // Test case 12: Special number formats
        var testCase12:Object = new Object();
        testCase12.text = 'special_float_1 = nan\nspecial_float_2 = inf\nspecial_float_3 = -inf\n';
        testCase12.expectedTokens = null;
        testCase12.description = "Testing special floating-point values: NaN, Infinity, -Infinity.";
        cases.push(testCase12);

        // Test case 13: Malformed FNTL (missing equals)
        var testCase13:Object = new Object();
        testCase13.text = 'invalid_line "No equals sign"\n';
        testCase13.expectedTokens = null;
        testCase13.description = "Testing malformed FNTL input with missing equals sign.";
        cases.push(testCase13);

        // Test case 14: Unclosed string
        var testCase14:Object = new Object();
        testCase14.text = 'unclosed_string = "This string never ends...\n';
        testCase14.expectedTokens = null;
        testCase14.description = "Testing malformed FNTL input with unclosed string.";
        cases.push(testCase14);

        // Test case 15: Invalid date-time format
        var testCase15:Object = new Object();
        testCase15.text = 'invalid_date = 2024-13-40T25:61:61Z\n';
        testCase15.expectedTokens = null;
        testCase15.description = "Testing malformed FNTL input with invalid date-time format.";
        cases.push(testCase15);

        // Test case 16: Nested arrays
        var testCase16:Object = new Object();
        testCase16.text = 'nested_arrays = [[1, 2], [3, 4], [5, 6]]\n';
        testCase16.expectedTokens = null;
        testCase16.description = "Testing nested arrays within FNTL.";
        cases.push(testCase16);

        // Test case 17: Project-specific sample with Unicode and complex structures
        var testCase17:Object = new Object();
        testCase17.text = 'task_chains_progress = { 主线 = "1" }\n' +
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
        testCase17.expectedTokens = null;
        testCase17.description = "Project-specific test case with Unicode characters and complex nested structures.";
        cases.push(testCase17);

        return cases;
    }

    /**
     * Retrieves test cases for the FNTLParser.
     * Each test case includes FNTL/FNTL text and the expected parsed object.
     */
    private function getParserTestCases():Array {
        var cases:Array = this.getLexerTestCases();

        // Adding additional Parser-specific test cases
        var testCase18:Object = new Object();
        testCase18.text = 'owner = { name = "Tom", dob = 1979-05-27 }\n';
        var expected18:Object = new Object();
        expected18.owner = new Object();
        expected18.owner.name = "Tom";
        expected18.owner.dob = "1979-05-27";
        testCase18.expected = expected18;
        testCase18.description = "Testing inline table parsing with simple key-value pairs.";
        cases.push(testCase18);

        var testCase19:Object = new Object();
        testCase19.text = 'settings = { theme = { color = "blue", font = "Arial" }, notifications = true }\n';
        var expected19:Object = new Object();
        expected19.settings = new Object();
        expected19.settings.theme = new Object();
        expected19.settings.theme.color = "blue";
        expected19.settings.theme.font = "Arial";
        expected19.settings.notifications = true;
        testCase19.expected = expected19;
        testCase19.description = "Testing nested inline tables within inline tables.";
        cases.push(testCase19);

        return cases;
    }

    /**
     * Retrieves test cases for the FNTLEncoder.
     * Each test case includes an input object and the expected FNTL/FNTL string.
     */
    private function getEncoderTestCases():Array {
        var cases:Array = new Array();

        // Test case 1: Simple object
        var testCase1:Object = new Object();
        testCase1.input = new Object();
        testCase1.input.title = "My Game";
        testCase1.input.isActive = true;
        testCase1.input.max_score = 1000;
        testCase1.input.average_score = 89.95;
        testCase1.input.launch_time = "2024-10-09T08:30:00Z";
        testCase1.input.items = new Array("sword", "shield", "potion");
        testCase1.expected = 'average_score = 89.95\n' +
                              'isActive = true\n' +
                              'items = ["sword", "shield", "potion"]\n' +
                              'launch_time = 2024-10-09T08:30:00Z\n' +
                              'max_score = 1000\n' +
                              'title = "My Game"\n';
        testCase1.description = "Encoding a simple object with various data types.";
        cases.push(testCase1);

        // Test case 2: Boolean values
        var testCase2:Object = new Object();
        testCase2.input = new Object();
        testCase2.input.boolean_true = true;
        testCase2.input.boolean_false = false;
        testCase2.expected = 'boolean_false = false\n' +
                              'boolean_true = true\n';
        testCase2.description = "Encoding boolean values: true and false.";
        cases.push(testCase2);

        // Test case 3: Numbers
        var testCase3:Object = new Object();
        testCase3.input = new Object();
        testCase3.input.integer = 42;
        testCase3.input.negative_integer = -42;
        testCase3.input.float = 3.14;
        testCase3.input.negative_float = -3.14;
        testCase3.expected = 'float = 3.14\n' +
                              'integer = 42\n' +
                              'negative_float = -3.14\n' +
                              'negative_integer = -42\n';
        testCase3.description = "Encoding integer and float numbers, including negative values.";
        cases.push(testCase3);

        // Test case 4: Empty values
        var testCase4:Object = new Object();
        testCase4.input = new Object();
        testCase4.input.empty_string = "";
        testCase4.input.empty_array = new Array();
        testCase4.input.null_value = null;
        testCase4.expected = 'empty_array = []\n' +
                              'empty_string = ""\n' +
                              'null_value = null\n';
        testCase4.description = "Encoding empty string, empty array, and null value.";
        cases.push(testCase4);

        // Test case 5: Date and time
        var testCase5:Object = new Object();
        testCase5.input = new Object();
        testCase5.input.date_time = "2024-10-09T08:30:00Z";
        testCase5.expected = 'date_time = 2024-10-09T08:30:00Z\n';
        testCase5.description = "Encoding date and time in ISO8601 format.";
        cases.push(testCase5);

        // Test case 6: Nested tables
        var testCase6:Object = new Object();
        testCase6.input = new Object();
        testCase6.input.server = new Object();
        testCase6.input.server.ip = "192.168.1.1";
        testCase6.input.server.database = new Object();
        testCase6.input.server.database.type = "PostgreSQL";
        testCase6.input.server.database.ports = new Array(5432, 5433, 5434);
        testCase6.input.server.database.settings = new Object();
        testCase6.input.server.database.settings.enabled = true;
        testCase6.expected = '[server]\n' +
                              'ip = "192.168.1.1"\n' +
                              '[server.database]\n' +
                              'ports = [5432, 5433, 5434]\n' +
                              'type = "PostgreSQL"\n' +
                              '[server.database.settings]\n' +
                              'enabled = true\n';
        testCase6.description = "Encoding nested tables with multiple levels.";
        cases.push(testCase6);

        // Test case 7: Table arrays
        var testCase7:Object = new Object();
        testCase7.input = new Object();
        testCase7.input.products = new Array();

        var product1:Object = new Object();
        product1.name = "Hammer";
        product1.sku = 738594937;
        testCase7.input.products.push(product1);

        var product2:Object = new Object();
        product2.name = "Nail";
        product2.sku = 284758393;
        testCase7.input.products.push(product2);

        testCase7.expected = '[[products]]\n' +
                              'name = "Hammer"\n' +
                              'sku = 738594937\n' +
                              '[[products]]\n' +
                              'name = "Nail"\n' +
                              'sku = 284758393\n';
        testCase7.description = "Encoding table arrays with multiple entries.";
        cases.push(testCase7);

        // Test case 8: Complex nested tables and table arrays
        var testCase8:Object = new Object();
        testCase8.input = new Object();
        testCase8.input.title = "FNTL Example";

        testCase8.input.owner = new Object();
        testCase8.input.owner.name = "Tom";
        testCase8.input.owner.dob = "1979-05-27";

        testCase8.input.products = new Array();

        var product3:Object = new Object();
        product3.name = "Hammer";
        product3.sku = 738594937;
        testCase8.input.products.push(product3);

        var product4:Object = new Object();
        product4.name = "Nail";
        product4.sku = 284758393;
        testCase8.input.products.push(product4);

        testCase8.input.database = new Object();
        testCase8.input.database.server = "192.168.1.1";
        testCase8.input.database.ports = new Array(8001, 8001, 8002);
        testCase8.input.database.connection_max = 5000;
        testCase8.input.database.enabled = true;

        testCase8.expected = '[owner]\n' +
                              'dob = "1979-05-27"\n' +
                              'name = "Tom"\n' +
                              '[database]\n' +
                              'connection_max = 5000\n' +
                              'enabled = true\n' +
                              'ports = [8001, 8001, 8002]\n' +
                              'server = "192.168.1.1"\n' +
                              '[[products]]\n' +
                              'name = "Hammer"\n' +
                              'sku = 738594937\n' +
                              '[[products]]\n' +
                              'name = "Nail"\n' +
                              'sku = 284758393\n' +
                              'title = "FNTL Example"\n';
        testCase8.description = "Encoding complex nested tables and table arrays.";
        cases.push(testCase8);

        // Test case 9: Unicode characters
        var testCase9:Object = new Object();
        testCase9.input = new Object();
        testCase9.input.greeting = "こんにちは";
        testCase9.input.emoji = "😊";
        testCase9.expected = 'emoji = "😊"\n' +
                              'greeting = "こんにちは"\n';
        testCase9.description = "Encoding Unicode characters and emojis.";
        cases.push(testCase9);

        // Test case 10: Escape characters
        var testCase10:Object = new Object();
        testCase10.input = new Object();
        testCase10.input.escaped_newline = "Line1\nLine2";
        testCase10.input.escaped_quote = 'He said, "Hello!"';
        testCase10.expected = 'escaped_newline = """Line1\nLine2"""\n' +
                              'escaped_quote = "He said, \\"Hello!\\""\n';
        testCase10.description = "Encoding strings with escape characters.";
        cases.push(testCase10);

        // Test case 11: Mixed complex structures
        var testCase11:Object = new Object();
        testCase11.input = new Object();

        // server
        testCase11.input.server = new Object();
        testCase11.input.server.host = "localhost";
        testCase11.input.server.ports = new Array(8000, 8001, 8002);
        testCase11.input.server.connection_max = 5000;
        testCase11.input.server.enabled = true;

        // owners
        testCase11.input.owners = new Array();
        var owner1:Object = new Object();
        owner1.name = "Alice";
        owner1.dob = "1990-01-01";
        testCase11.input.owners.push(owner1);

        var owner2:Object = new Object();
        owner2.name = "Bob";
        owner2.dob = "1985-05-12";
        testCase11.input.owners.push(owner2);

        // database
        testCase11.input.database = new Object();
        testCase11.input.database.server = "192.168.1.100";
        testCase11.input.database.ports = new Array(3306);
        testCase11.input.database.connection_max = 10000;
        testCase11.input.database.enabled = false;

        // users
        testCase11.input.users = new Array();
        var user1:Object = new Object();
        user1.name = "user1";
        user1.active = true;
        testCase11.input.users.push(user1);

        var user2:Object = new Object();
        user2.name = "user2";
        user2.active = false;
        testCase11.input.users.push(user2);

        testCase11.expected = '[server]\n' +
                               'connection_max = 5000\n' +
                               'enabled = true\n' +
                               'host = "localhost"\n' +
                               'ports = [8000, 8001, 8002]\n' +
                               '[database]\n' +
                               'connection_max = 10000\n' +
                               'enabled = false\n' +
                               'ports = [3306]\n' +
                               'server = "192.168.1.100"\n' +
                               '[[owners]]\n' +
                               'dob = "1990-01-01"\n' +
                               'name = "Alice"\n' +
                               '[[owners]]\n' +
                               'dob = "1985-05-12"\n' +
                               'name = "Bob"\n' +
                               '[[users]]\n' +
                               'active = true\n' +
                               'name = "user1"\n' +
                               '[[users]]\n' +
                               'active = false\n' +
                               'name = "user2"\n';
        testCase11.description = "Encoding mixed complex structures with multiple table arrays.";
        cases.push(testCase11);

        // Test case 12: Special number formats
        var testCase12:Object = new Object();
        testCase12.input = new Object();
        testCase12.input.special_float_1 = Number.NaN;
        testCase12.input.special_float_2 = Number.POSITIVE_INFINITY;
        testCase12.input.special_float_3 = Number.NEGATIVE_INFINITY;
        testCase12.expected = 'special_float_1 = nan\n' +
                              'special_float_2 = inf\n' +
                              'special_float_3 = -inf\n';
        testCase12.description = "Encoding special floating-point values: NaN, Infinity, -Infinity.";
        cases.push(testCase12);

        // Test case 13: Malformed FNTL (missing equals)
        var testCase13:Object = new Object();
        testCase13.input = new Object();
        testCase13.input.invalid_line = "No equals sign";
        testCase13.expected = null; // Encoder should skip or handle invalid entries
        testCase13.description = "Encoding malformed FNTL input with missing equals sign.";
        cases.push(testCase13);

        // Test case 14: Malformed or unclosed string (simulated)
        var testCase14:Object = new Object();
        testCase14.input = new Object();
        testCase14.input.unclosed_string = "This string never ends...";
        testCase14.expected = null; // Expected output is null because the parser should flag this as an error
        testCase14.description = "Encoding malformed FNTL input with unclosed string.";
        cases.push(testCase14);

        // Test case 15: Invalid date-time format
        var testCase15:Object = new Object();
        testCase15.input = new Object();
        testCase15.input.invalid_date = "2024-13-40T25:61:61Z";
        testCase15.expected = null; // Encoder should handle invalid dates or escape
        testCase15.description = "Encoding malformed FNTL input with invalid date-time format.";
        cases.push(testCase15);

        // Test case 16: Nested arrays
        var testCase16:Object = new Object();
        testCase16.input = new Object();
        var nestedArray1:Array = new Array(1, 2);
        var nestedArray2:Array = new Array(3, 4);
        var nestedArray3:Array = new Array(5, 6);
        var nestedArrays:Array = new Array(nestedArray1, nestedArray2, nestedArray3);
        testCase16.input.nested_arrays = nestedArrays;
        testCase16.expected = 'nested_arrays = [[1, 2], [3, 4], [5, 6]]\n';
        testCase16.description = "Encoding nested arrays within FNTL.";
        cases.push(testCase16);

        // Test case 17: Project-specific sample with Unicode and complex structures
        var testCase17:Object = new Object();
        testCase17.input = new Object();
        testCase17.input.task_chains_progress = new Object();
        testCase17.input.task_chains_progress["主线"] = "1";

        testCase17.input.task_history = [0];

        testCase17.input.tasks_finished = new Object();
        testCase17.input.tasks_finished["0"] = 1; // Manually adding the key-value pair

        testCase17.input.test = [
            ["fs", "男", 1000, 50, 1000000, 175, 300, "新手", 50000, 500000, [
                ["上键", "上键", 87], ["下键", "下键", 83], ["左键", "左键", 65], ["右键", "右键", 68]
            ]],
            "测试"
        ];

        testCase17.input.商城已购买物品 = new Array();
        testCase17.input.战宠 = new Array(new Array());
        testCase17.input.tasks_to_do = new Array();

        var task_to_do1:Object = new Object();
        task_to_do1.id = 1;
        task_to_do1.requirements = new Object();
        task_to_do1.requirements.items = new Array();
        task_to_do1.requirements.stages = new Array();

        var stage1:Object = new Object();
        stage1.difficulty = "简单";
        stage1.name = "测试任务";
        task_to_do1.requirements.stages.push(stage1);

        testCase17.input.tasks_to_do.push(task_to_do1);

        testCase17.expected = '[task_chains_progress]\n' +
                               '主线 = "1"\n' +
                               '[tasks_finished]\n' +
                               '0 = 1\n' +
                               '[task_history]\n' +
                               '0 = 0\n' +
                               '[[tasks_to_do]]\n' +
                               'id = 1\n' +
                               '[tasks_to_do.requirements]\n' +
                               'items = []\n' +
                               '[tasks_to_do.requirements.stages]\n' +
                               'difficulty = "简单"\n' +
                               'name = "测试任务"\n' +
                               '[[tasks_to_do.requirements.stages]]\n' +
                               'difficulty = "简单"\n' +
                               'name = "测试任务"\n' +
                               'test = [["fs", "男", 1000, 50, 1000000, 175, 300, "新手", 50000, 500000, [[' +
                               '"上键", "上键", 87], ["下键", "下键", 83], ["左键", "左键", 65], ["右键", "右键", 68]]], "测试"]]\n' +
                               '商城已购买物品 = []\n' +
                               '战宠 = [[]]\n';
        testCase17.description = "Encoding project-specific FNTL with Unicode characters and complex nested structures.";
        cases.push(testCase17);

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
     * Compares two FNTL/FNTL output strings for semantic equality by parsing and comparing objects.
     * @param actual The encoded FNTL/FNTL string.
     * @param expected The expected FNTL/FNTL string.
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
     * Trims trailing newline characters from a string.
     * @param input The input string.
     * @return The trimmed string.
     */
    private function trimTrailingNewlines(input:String):String {
        while (input.length > 0) {
            var lastChar:String = input.charAt(input.length - 1);
            if (lastChar == "\n" || lastChar == "\r") {
                input = input.substring(0, input.length - 1);
            } else {
                break;
            }
        }
        return input;
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


/*

var test:org.flashNight.gesh.fntl.FNTLLexerTest = new org.flashNight.gesh.fntl.FNTLLexerTest();

// 调用测试方法，运行所有测试用例
test.runAllTests();

*/