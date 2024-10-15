import org.flashNight.aven.test.*;

class org.flashNight.aven.test.ExampleTest {
    public static function main():Void {
        var config:TestConfig = new TestConfig(false, 1, false, ["lexer"], []);
        var reporter:ConsoleTestReporter = new ConsoleTestReporter(config);
        var runner:TestRunner = new TestRunner(config, reporter);

        // 创建测试套件
        var lexerSuite:TestSuite = new TestSuite("FNTLLexer Tests");

        // 创建测试用例
        var lexerTestCase1:TestCase = new TestCase(
            "基础键值对测试",
            { text: 'title = "My Game"\nisActive = true\nmax_score = 1000\naverage_score = 89.95\n' },
            { title: "My Game", isActive: true, max_score: 1000, average_score: 89.95 },
            function(input:Object):Object {
                // 实现测试函数
                var lexer:FNTLLexer = new FNTLLexer(input.text);
                var tokens:Array = [];
                var token:Object;
                while ((token = lexer.getNextToken()) != null) {
                    tokens.push(token);
                }
                var parser:FNTLParser = new FNTLParser(tokens, input.text);
                return parser.parse();
            },
            ["basic", "lexer"]
        );

        // 将测试用例添加到测试套件
        lexerSuite.addTestCase(lexerTestCase1);

        // 将测试套件添加到测试运行器
        runner.addSuite(lexerSuite);

        // 运行测试
        runner.run();
    }
}
