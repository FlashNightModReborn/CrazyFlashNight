import org.flashNight.gesh.regexp.*;

/**
 * RegExpTest 类用于测试 RegExp 引擎的各种功能和特性。
 */
class org.flashNight.gesh.regexp.RegExpTest {
    
    // 静态变量用于记录测试结果
    private static var totalTests:Number = 0;
    private static var passedTests:Number = 0;
    private static var failedTests:Number = 0;
    
    public static function runTests():Void {
        runSuite(false);
    }

    public static function runAllTests():Void {
        runSuite(true);
    }

    private static function runSuite(includeBenchmarks:Boolean):Void {
        trace("=====================================");
        trace("开始运行 RegExp 引擎测试...");
        trace("=====================================");
        trace("");

        // 初始化测试计数
        totalTests = 0;
        passedTests = 0;
        failedTests = 0;

        // 运行特性支持测试
        runFeatureSupportTests();
        trace("");
        
        // 运行实战复杂项目测试
        runComplexProjectTests();
        trace("");
        
        // 运行阶段0 Bug修复测试
        runPhase0BugFixTests();
        trace("");
        
        // 运行阶段1 基础语法扩展测试
        runPhase1BasicExtensionTests();
        trace("");

        // 运行阶段2 命名捕获组测试
        runPhase2NamedCaptureTests();
        trace("");

        // 运行阶段3 API/语义回归测试
        runPhase3ApiSemanticsTests();
        trace("");

        if (includeBenchmarks) {
            // 运行阶段P 性能基准测试
            runPerformanceBenchmarks();
            trace("");
        }
        
        // 运行注入原型链测试
        runPrototypeInjectionTests();
        trace("");
        
        // 输出测试汇总
        trace("=====================================");
        trace("测试汇总：");
        trace("总测试数：" + totalTests);
        trace("通过测试：" + passedTests);
        trace("失败测试：" + failedTests);
        trace("=====================================");
    }

    /**
     * 断言函数：比较预期值和实际值
     * @param description 测试描述
     * @param expected 预期值
     * @param actual 实际值
     */
    private static function assertEquals(description:String, expected, actual):Void {
        totalTests++;
        if (expected === actual) {
            passedTests++;
            trace("[PASS] " + description);
        } else {
            failedTests++;
            trace("[FAIL] " + description);
            trace("       Expected: " + expected);
            trace("       Actual  : " + actual);
        }
    }

    /**
     * 断言函数：检查条件是否为真
     * @param description 测试描述
     * @param condition 条件
     */
    private static function assertTrue(description:String, condition:Boolean):Void {
        totalTests++;
        if (condition) {
            passedTests++;
            trace("[PASS] " + description);
        } else {
            failedTests++;
            trace("[FAIL] " + description);
            trace("       Condition is not true.");
        }
    }

    /**
     * 断言函数：检查条件是否为假
     * @param description 测试描述
     * @param condition 条件
     */
    private static function assertFalse(description:String, condition:Boolean):Void {
        totalTests++;
        if (!condition) {
            passedTests++;
            trace("[PASS] " + description);
        } else {
            failedTests++;
            trace("[FAIL] " + description);
            trace("       Condition is not false.");
        }
    }

    /**
     * 特性支持测试
     */
    private static function runFeatureSupportTests():Void {
        trace("========== 特性支持测试 ==========");
        
        // 测试1：基础字符匹配
        var regex1:RegExp = new RegExp("a*b", "");
        assertTrue("测试1：/a*b/ 匹配 'aaab'", regex1.test("aaab") === true);
        
        // 测试2：分组与量词
        var regex2:RegExp = new RegExp("(abc)+", "");
        assertTrue("测试2：/(abc)+/ 匹配 'abcabc'", regex2.test("abcabc") === true);
        
        // 测试3：字符集与量词
        var regex3:RegExp = new RegExp("[a-z]{3}", "");
        assertTrue("测试3：/[a-z]{3}/ 匹配 'abc'", regex3.test("abc") === true);
        
        // 测试4：逻辑或
        var regex4:RegExp = new RegExp("a|b", "");
        assertTrue("测试4：/a|b/ 匹配 'a'", regex4.test("a") === true);
        assertTrue("测试4：/a|b/ 匹配 'b'", regex4.test("b") === true);
        
        // 测试5：量词 +
        var regex5:RegExp = new RegExp("a+", "");
        assertTrue("测试5：/a+/ 匹配 'aa'", regex5.test("aa") === true);
        
        // 测试6：量词 + 不匹配
        var regex6:RegExp = new RegExp("a+", "");
        assertFalse("测试6：/a+/ 匹配 ''", regex6.test("") === true);
        
        // 测试7：捕获组与 exec
        var regex7:RegExp = new RegExp("(a)(b)(c)", "");
        var result7:Array = regex7.exec("abc");
        if (result7 != null) {
            assertEquals("测试7：/(a)(b)(c)/ 匹配 'abc'，捕获组1", "a", result7[1]);
            assertEquals("测试7：/(a)(b)(c)/ 匹配 'abc'，捕获组2", "b", result7[2]);
            assertEquals("测试7：/(a)(b)(c)/ 匹配 'abc'，捕获组3", "c", result7[3]);
        } else {
            failedTests++;
            totalTests++;
            trace("[FAIL] 测试7：/(a)(b)(c)/ 匹配 'abc' 未匹配");
        }
        
        // 测试8：字符集否定
        var regex8:RegExp = new RegExp("[^a-z]", "");
        assertTrue("测试8：/[^a-z]/ 匹配 '1'", regex8.test("1") === true);
        assertFalse("测试8：/[^a-z]/ 匹配 'a'", regex8.test("a") === true);
        
        // 测试9：嵌套分组与量词组合
        var regex9:RegExp = new RegExp("(ab(c|d))*", "");
        assertTrue("测试9：/(ab(c|d))*/ 匹配 'abcdabcdabcc'", regex9.test("abcdabcdabcc") === true);
        
        // 测试10：量词 {0}
        var regex10:RegExp = new RegExp("a{0}", "");
        assertTrue("测试10：/a{0}/ 匹配 'abc'", regex10.test("abc") === true);
        
        // 测试11：量词 {n,m}，n > m
        try {
            var regex11:RegExp = new RegExp("a{3,1}", "");
            failedTests++;
            totalTests++;
            trace("[FAIL] 测试11：/a{3,1}/ 应该解析失败但成功解析");
        } catch (e:Error) {
            passedTests++;
            totalTests++;
            trace("[PASS] 测试11：/a{3,1}/ 解析失败如预期");
        }
        
        // 测试12：匹配空字符串
        var regex12:RegExp = new RegExp("^$", "");
        assertTrue("测试12：/^$/ 匹配 ''", regex12.test("") === true);
        
        // 测试13：量词允许零次匹配
        var regex13:RegExp = new RegExp("a*", "");
        assertTrue("测试13：/a*/ 匹配 ''", regex13.test("") === true);
        
        // 测试14：任意字符匹配
        var regex14:RegExp = new RegExp("a.c", "");
        assertTrue("测试14：/a.c/ 匹配 'abc'", regex14.test("abc") === true);
        assertTrue("测试14：/a.c/ 匹配 'a c'", regex14.test("a c") === true);
        assertFalse("测试14：/a.c/ 匹配 'abbc'", regex14.test("abbc") === true); // 预期为 false
        
        // 测试15：字符集与量词组合
        var regex15:RegExp = new RegExp("[abc]+", "");
        assertTrue("测试15：/[abc]+/ 匹配 'aaabbbcccabc'", regex15.test("aaabbbcccabc") === true);
        
        // 测试16：否定字符集与量词组合
        var regex16:RegExp = new RegExp("[^abc]+", "");
        assertTrue("测试16：/[^abc]+/ 匹配 'defg'", regex16.test("defg") === true);
        
        // 测试17：多个选择的组合
        var regex17:RegExp = new RegExp("a|b|c", "");
        assertTrue("测试17：/a|b|c/ 匹配 'b'", regex17.test("b") === true);
        assertFalse("测试17：/a|b|c/ 匹配 'd'", regex17.test("d") === true); // 预期为 false
        
        // 测试18：量词嵌套
        var regex18:RegExp = new RegExp("(a+)+", "");
        assertTrue("测试18：/(a+)+/ 匹配 'aaa'", regex18.test("aaa") === true);
        
        // 测试19：无法匹配的情况
        var regex19:RegExp = new RegExp("a{4}", "");
        assertFalse("测试19：/a{4}/ 匹配 'aaa'", regex19.test("aaa") === true); // 预期为 false
        
        // 测试20：匹配长字符串
        var longString:String = "";
        for (var i:Number = 0; i < 1000; i++) {
            longString += "a";
        }
        var regex20:RegExp = new RegExp("a{1000}", "");
        assertTrue("测试20：/a{1000}/ 匹配 1000 个 'a'", regex20.test(longString) === true);
        
        // 新增测试21：正向前瞻
        var regex21:RegExp = new RegExp("foo(?=bar)", "");
        assertTrue("测试21：/foo(?=bar)/ 匹配 'foobar'", regex21.test("foobar") === true);
        assertFalse("测试21：/foo(?=bar)/ 匹配 'foobaz'", regex21.test("foobaz") === true); // 预期为 false
        
        // 新增测试22：负向前瞻
        var regex22:RegExp = new RegExp("foo(?!bar)", "");
        assertTrue("测试22：/foo(?!bar)/ 匹配 'foobaz'", regex22.test("foobaz") === true);
        assertFalse("测试22：/foo(?!bar)/ 匹配 'foobar'", regex22.test("foobar") === true); // 预期为 false
        
        // 新增测试23：正向后顾
        var regex23:RegExp = new RegExp("(?<=foo)bar", "");
        assertTrue("测试23：/(?<=foo)bar/ 匹配 'foobar'", regex23.test("foobar") === true);
        assertFalse("测试23：/(?<=foo)bar/ 匹配 'foobaz'", regex23.test("foobaz") === true); // 预期为 false
        
        // 新增测试24：负向后顾
        var regex24:RegExp = new RegExp("(?<!foo)bar", "");
        assertTrue("测试24：/(?<!foo)bar/ 匹配 'bazbar'", regex24.test("bazbar") === true);
        assertFalse("测试24：/(?<!foo)bar/ 匹配 'foobar'", regex24.test("foobar") === true); // 预期为 false
        
        trace("========== 特性支持测试结束 ==========");
    }

    /**
     * 实战复杂项目测试
     */
    private static function runComplexProjectTests():Void {
        trace("========== 实战复杂项目测试 ==========");
        
        // 测试25：数字验证
        var numberRegExp:RegExp = new RegExp("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$", "");
        assertTrue("测试25：numberRegExp 匹配 '123'", numberRegExp.test("123") === true);
        assertTrue("测试25：numberRegExp 匹配 '-123.45'", numberRegExp.test("-123.45") === true);
        assertTrue("测试25：numberRegExp 匹配 '1e10'", numberRegExp.test("1e10") === true);
        assertFalse("测试25：numberRegExp 匹配 '12a'", numberRegExp.test("12a") === true); // 预期为 false
        
        // 测试26：日期时间验证
        var dateTimeRegExp:RegExp = new RegExp("^\\d{4}-\\d{2}-\\d{2}[Tt ][0-2]\\d:[0-5]\\d:[0-5]\\d(\\.\\d+)?([Zz]|([+-][0-2]\\d:[0-5]\\d))?$", "");
        assertTrue("测试26：dateTimeRegExp 匹配 '2024-10-09T08:30:00Z'", dateTimeRegExp.test("2024-10-09T08:30:00Z") === true);
        assertTrue("测试26：dateTimeRegExp 匹配 '2024-10-09 08:30:00+02:00'", dateTimeRegExp.test("2024-10-09 08:30:00+02:00") === true);
        assertFalse("测试26：dateTimeRegExp 匹配 '2024-13-40T25:61:61Z'", dateTimeRegExp.test("2024-13-40T25:61:61Z") === true); // 预期为 false
        
        // 测试27：布尔值验证
        var booleanRegExp:RegExp = new RegExp("^(true|false)$", "i");
        assertTrue("测试27：booleanRegExp 匹配 'true'", booleanRegExp.test("true") === true);
        assertTrue("测试27：booleanRegExp 匹配 'FALSE'", booleanRegExp.test("FALSE") === true);
        assertFalse("测试27：booleanRegExp 匹配 'yes'", booleanRegExp.test("yes") === true); // 预期为 false
        
        // 测试28：特殊浮点数验证
        var specialFloatRegExp:RegExp = new RegExp("^(nan|inf|-inf)$", "i");
        assertTrue("测试28：specialFloatRegExp 匹配 'NaN'", specialFloatRegExp.test("NaN") === true);
        assertTrue("测试28：specialFloatRegExp 匹配 'inf'", specialFloatRegExp.test("inf") === true);
        assertTrue("测试28：specialFloatRegExp 匹配 '-INF'", specialFloatRegExp.test("-INF") === true);
        assertFalse("测试28：specialFloatRegExp 匹配 '1.23'", specialFloatRegExp.test("1.23") === true); // 预期为 false
        
        // 测试29：电子邮件验证
        var emailRegExp:RegExp = new RegExp("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", "");
        assertTrue("测试29：emailRegExp 匹配 'test@example.com'", emailRegExp.test("test@example.com") === true);
        assertFalse("测试29：emailRegExp 匹配 'invalid-email@'", emailRegExp.test("invalid-email@") === true); // 预期为 false
        
        // 测试30：URL验证
        var urlRegExp:RegExp = new RegExp("^(https?:\\/\\/)?([\\w.-]+)\\.([a-z\\.]{2,6})([\\/\\w .-]*)*\\/?$", "i");
        assertTrue("测试30：urlRegExp 匹配 'https://www.example.com/path'", urlRegExp.test("https://www.example.com/path") === true);
        assertFalse("测试30：urlRegExp 匹配 'htp:/invalid-url'", urlRegExp.test("htp:/invalid-url") === true); // 预期为 false
        
        trace("========== 实战复杂项目测试结束 ==========");
    }

    /**
     * 阶段0 Bug修复测试
     */
    public static function runPhase0BugFixTests():Void {
        trace("========== 阶段0 Bug修复测试 ==========");
        
        // Bug 0-1: Multiline 模式下 ^ $ 应识别行边界
        var re1:RegExp = new RegExp("^abc", "m");
        assertTrue("Bug 0-1: /^abc/m 应匹配 'xyz\\nabc'", re1.test("xyz\nabc") === true);
        assertFalse("Bug 0-1: /^abc/m 不应匹配 'xyzabc'", re1.test("xyzabc") === true);
        
        var re2:RegExp = new RegExp("abc$", "m");
        assertTrue("Bug 0-1: /abc$/m 应匹配 'abc\\nxyz'", re2.test("abc\nxyz") === true);
        assertFalse("Bug 0-1: /abc$/m 不应匹配 'abcxyz'", re2.test("abcxyz") === true);
        
        // 非 multiline 模式下 ^ $ 只匹配字符串起止
        var re3:RegExp = new RegExp("^abc", "");
        assertFalse("Bug 0-1: /^abc/ 不应匹配 'xyz\\nabc'", re3.test("xyz\nabc") === true);
        
        var re4:RegExp = new RegExp("abc$", "");
        assertFalse("Bug 0-1: /abc$/ 不应匹配 'abc\\nxyz'", re4.test("abc\nxyz") === true);
        
        // Bug 0-2: 非贪婪量词应与后续模式协作
        var re3:RegExp = new RegExp(".*?b", "");
        var m3:Array = re3.exec("aab");
        if (m3 != null) {
            assertEquals("Bug 0-2: /.*?b/ 应匹配 'aab'", "aab", m3[0]);
        } else {
            assertTrue("Bug 0-2: /.*?b/ 未匹配 'aab'", false);
        }
        
        var re4:RegExp = new RegExp("a+?b", "");
        assertTrue("Bug 0-2: /a+?b/ 应匹配 'aab'", re4.test("aab") === true);
        
        var re5:RegExp = new RegExp("<.*?>", "");
        var m5:Array = re5.exec("<div>content</div>");
        if (m5 != null) {
            assertEquals("Bug 0-2: /<.*?>/ 应匹配 '<div>'", "<div>", m5[0]);
        } else {
            assertTrue("Bug 0-2: /<.*?>/ 未匹配", false);
        }
        
        // Bug 0-3: 字符类内 \D \W \S 处理
        var re6:RegExp = new RegExp("[\\D]+", "");
        assertTrue("Bug 0-3: /[\\D]+/ 应匹配 'abc'", re6.test("abc") === true);
        assertFalse("Bug 0-3: /[\\D]+/ 不应匹配 '123'", re6.test("123") === true);
        
        var re7:RegExp = new RegExp("[a\\D]+", "");
        assertTrue("Bug 0-3: /[a\\D]+/ 应匹配 'a!@#'", re7.test("a!@#") === true);
        
        var re8:RegExp = new RegExp("[\\d\\D]+", "");
        assertTrue("Bug 0-3: /[\\d\\D]+/ 应匹配 'a1b2'", re8.test("a1b2") === true);
        
        trace("========== 阶段0 Bug修复测试结束 ==========");
    }

    /**
     * 阶段1 基础语法扩展测试
     */
    public static function runPhase1BasicExtensionTests():Void {
        trace("========== 阶段1 基础语法扩展测试 ==========");
        
        // 1-1: \b 和 \B 单词边界
        var re1:RegExp = new RegExp("\\bword\\b", "");
        assertTrue("1-1: /\\bword\\b/ 应匹配 'a word here'", re1.test("a word here") === true);
        assertFalse("1-1: /\\bword\\b/ 不应匹配 'awordhere'", re1.test("awordhere") === true);
        assertTrue("1-1: /\\bword\\b/ 应匹配 'word'", re1.test("word") === true);
        
        var re2:RegExp = new RegExp("\\bcat\\b", "");
        var m2:Array = re2.exec("the cat sat");
        if (m2 != null) {
            assertEquals("1-1: /\\bcat\\b/ exec 匹配", "cat", m2[0]);
        } else {
            assertTrue("1-1: /\\bcat\\b/ exec 未匹配", false);
        }
        assertFalse("1-1: /\\bcat\\b/ 不应匹配 'concatenate'", re2.test("concatenate") === true);
        
        var re3:RegExp = new RegExp("\\B-\\B", "");
        assertFalse("1-1: /\\B-\\B/ 不应匹配 'a-b'", re3.test("a-b") === true);
        assertTrue("1-1: /\\B-\\B/ 应匹配 '--'", re3.test("--") === true);
        
        // 1-2: \xHH 和 \uHHHH 转义
        var re4:RegExp = new RegExp("\\x41\\x42\\x43", "");
        assertTrue("1-2: /\\x41\\x42\\x43/ 应匹配 'ABC'", re4.test("ABC") === true);
        
        var re5:RegExp = new RegExp("[\\x30-\\x39]+", "");
        assertTrue("1-2: /[\\x30-\\x39]+/ 应匹配 '12345'", re5.test("12345") === true);
        assertFalse("1-2: /[\\x30-\\x39]+/ 不应匹配 'abc'", re5.test("abc") === true);
        
        var re6:RegExp = new RegExp("\\u4e2d\\u6587", "");
        assertTrue("1-2: /\\u4e2d\\u6587/ 应匹配 '中文'", re6.test("中文") === true);
        
        // 1-3: s (dotAll) 标志
        var re7:RegExp = new RegExp("a.b", "");
        assertFalse("1-3: /a.b/ 不应匹配 'a\\nb'", re7.test("a\nb") === true);
        
        var re8:RegExp = new RegExp("a.b", "s");
        assertTrue("1-3: /a.b/s 应匹配 'a\\nb'", re8.test("a\nb") === true);
        
        trace("========== 阶段1 基础语法扩展测试结束 ==========");
    }

    /**
     * 阶段P 性能基准测试
     */
    public static function runPerformanceBenchmarks():Void {
        trace("========== 阶段P 性能基准测试 ==========");
        
        var startTime:Number;
        var endTime:Number;
        var elapsed:Number;
        var i:Number;
        var N:Number;
        var re:RegExp;
        var input:String;
        var result:Boolean;
        var match:Array;
        
        // 基准1：简单字面量匹配
        re = new RegExp("hello", "");
        input = "this is a test string with hello world in the middle";
        N = 10000;
        startTime = getTimer();
        for (i = 0; i < N; i++) {
            result = re.test(input);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("[PERF] 基准1-简单字面量: " + (elapsed/N) + "ms/op (" + N + " ops in " + elapsed + "ms)");
        
        // 基准2：字符类匹配
        re = new RegExp("[a-zA-Z0-9]+", "");
        input = "abc123DEF";
        N = 5000;
        startTime = getTimer();
        for (i = 0; i < N; i++) {
            result = re.test(input);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("[PERF] 基准2-字符类匹配: " + (elapsed/N) + "ms/op (" + N + " ops in " + elapsed + "ms)");
        
        // 基准3：复杂模式 - 邮箱验证
        re = new RegExp("^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$", "");
        input = "test@example.com";
        N = 2000;
        startTime = getTimer();
        for (i = 0; i < N; i++) {
            result = re.test(input);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("[PERF] 基准3-邮箱验证: " + (elapsed/N) + "ms/op (" + N + " ops in " + elapsed + "ms)");
        
        // 基准4：ReDoS 抗性 - (a+)+b
        re = new RegExp("(a+)+b", "");
        input = "aaaaaaaaaaaaaaaaaaaaaaaaa"; // 25个a，无b，应快速失败
        startTime = getTimer();
        result = re.test(input);
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("[PERF] 基准4-ReDoS抗性(25a): " + elapsed + "ms (单次，应<1000ms)");
        
        // 基准5：captures 密集 - 多捕获组
        re = new RegExp("(a)(b)(c)(d)(e)", "");
        input = "abcde";
        N = 3000;
        startTime = getTimer();
        for (i = 0; i < N; i++) {
            match = re.exec(input);
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("[PERF] 基准5-多捕获组: " + (elapsed/N) + "ms/op (" + N + " ops in " + elapsed + "ms)");
        
        // 基准6：全局匹配 - exec 循环
        re = new RegExp("\\d+", "g");
        input = "a1b22c333d4444";
        N = 2000;
        startTime = getTimer();
        for (i = 0; i < N; i++) {
            re.lastIndex = 0;
            while ((match = re.exec(input)) != null) {
                // 空循环体
            }
        }
        endTime = getTimer();
        elapsed = endTime - startTime;
        trace("[PERF] 基准6-全局匹配循环: " + (elapsed/N) + "ms/op (" + N + " ops in " + elapsed + "ms)");
        
        trace("========== 阶段P 性能基准测试结束 ==========");
    }

    /**
     * 阶段2 命名捕获组测试
     */
    public static function runPhase2NamedCaptureTests():Void {
        trace("========== 阶段2 命名捕获组测试 ==========");
        
        // 2-1: (?<name>...) 命名捕获组
        try {
            var re1:RegExp = new RegExp("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})", "");
            var m1:Array = re1.exec("2026-03-11");
            if (m1 != null) {
                assertEquals("2-1: 编号引用 m[1]", "2026", m1[1]);
                assertEquals("2-1: 编号引用 m[2]", "03", m1[2]);
                assertEquals("2-1: 编号引用 m[3]", "11", m1[3]);
                assertTrue("2-1: groups 对象存在", m1.groups != undefined);
                if (m1.groups != undefined) {
                    assertEquals("2-1: 命名引用 m.groups.year", "2026", m1.groups.year);
                    assertEquals("2-1: 命名引用 m.groups.month", "03", m1.groups.month);
                    assertEquals("2-1: 命名引用 m.groups.day", "11", m1.groups.day);
                }
            } else {
                assertTrue("2-1: 命名捕获组未匹配", false);
            }
        } catch (e1:Error) {
            assertTrue("2-1: 命名捕获组不应抛异常", false);
        }

        try {
            var re2:RegExp = new RegExp("^(?<word>cat)$", "i");
            assertTrue("2-2: 命名捕获组应支持 ignoreCase", re2.test("CAT") === true);
        } catch (e2:Error) {
            assertTrue("2-2: 命名捕获组 ignoreCase 不应抛异常", false);
        }
        
        trace("========== 阶段2 命名捕获组测试结束 ==========");
    }

    public static function runPhase3ApiSemanticsTests():Void {
        trace("========== 阶段3 API/语义回归测试 ==========");

        var re1:RegExp = new RegExp("^abc$", "m");
        assertTrue("3-1: /^abc$/m 应匹配中间整行", re1.test("xyz\nabc\n123") === true);

        var re2:RegExp = new RegExp("^$", "m");
        assertTrue("3-1: /^$/m 应匹配空行", re2.test("a\n\nb") === true);

        var re3:RegExp = new RegExp("^abc\\$", "");
        assertTrue("3-2: /^abc\\$/ 应匹配 'abc$y' 的前缀", re3.test("abc$y") === true);

        var re4:RegExp = new RegExp("a*", "g");
        var z1:Array = re4.exec("b");
        var z2:Array = re4.exec("b");
        var z3:Array = re4.exec("b");
        assertTrue("3-3: /a*/g 第1次 exec 应返回空匹配", z1 != null);
        if (z1 != null) {
            assertEquals("3-3: /a*/g 第1次 exec 匹配内容", "", z1[0]);
            assertEquals("3-3: /a*/g 第1次 exec 索引", 0, z1.index);
        }
        assertTrue("3-3: /a*/g 第2次 exec 应推进到末尾", z2 != null);
        if (z2 != null) {
            assertEquals("3-3: /a*/g 第2次 exec 匹配内容", "", z2[0]);
            assertEquals("3-3: /a*/g 第2次 exec 索引", 1, z2.index);
        }
        assertTrue("3-3: /a*/g 第3次 exec 应返回 null", z3 == null);

        RegExp.injectMethods();

        var zeroWidthStr:Object = "b";
        var zeroMatches:Array = zeroWidthStr.regexp_match(new RegExp("a*", "g"));
        assertTrue("3-4: regexp_match 应保留两个零宽匹配", zeroMatches != null && zeroMatches.length === 2);
        if (zeroMatches != null && zeroMatches.length === 2) {
            assertEquals("3-4: regexp_match 第1个零宽匹配", "", zeroMatches[0]);
            assertEquals("3-4: regexp_match 第2个零宽匹配", "", zeroMatches[1]);
        }

        var csv:Object = "a,b,c";
        var splitResult:Array = csv.regexp_split(new RegExp(",", ""));
        assertTrue("3-5: regexp_split 非 g 模式也应拆分全部命中", splitResult != null && splitResult.length === 3);
        if (splitResult != null && splitResult.length === 3) {
            assertEquals("3-5: regexp_split 第1段", "a", splitResult[0]);
            assertEquals("3-5: regexp_split 第2段", "b", splitResult[1]);
            assertEquals("3-5: regexp_split 第3段", "c", splitResult[2]);
        }

        var isoDate:Object = "2026-03-11";
        var numberedReplace:String = isoDate.regexp_replace(new RegExp("(\\d{4})-(\\d{2})-(\\d{2})", ""), "$2/$3/$1");
        assertEquals("3-6: regexp_replace 应支持 $1/$2/$3", "03/11/2026", numberedReplace);

        try {
            var namedReplace:String = isoDate.regexp_replace(new RegExp("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})", ""), "$<day>/$<month>/$<year>");
            assertEquals("3-6: regexp_replace 应支持 $<name>", "11/03/2026", namedReplace);
        } catch (e3:Error) {
            assertTrue("3-6: 命名替换不应抛异常", false);
        }

        var escapedDollar:String = isoDate.regexp_replace(new RegExp("2026", ""), "$$YEAR");
        assertEquals("3-6: regexp_replace 应支持 $$ 转义", "$YEAR-03-11", escapedDollar);

        RegExp.removeMethods();

        var re5:Object = new RegExp("abc", "im");
        assertEquals("3-7: source 应暴露原始模式", "abc", re5.source);
        assertEquals("3-7: flags 应暴露原始标志", "im", re5.flags);

        trace("========== 阶段3 API/语义回归测试结束 ==========");
    }

    /**
     * 注入原型链测试
     */
    private static function runPrototypeInjectionTests():Void {
        trace("========== 注入原型链测试 ==========");

        // 注入方法
        RegExp.injectMethods();  // 确保注入正确执行
        trace("注入 regexp_* 方法到 String.prototype");

        var re:RegExp = new RegExp("\\d+", "g");
        var str:Object = "This is 123 and 456.";  // 使用 Object 类型来避免静态检查

        // 测试 regexp_match
        if (typeof(str.regexp_match) == "function") {  // 在调用之前检查函数是否存在
            var matchResult:Array = str.regexp_match(re);
            assertTrue("测试31：regexp_match 返回数组长度为 2", matchResult != null && matchResult.length === 2);
            if (matchResult != null) {
                assertEquals("测试31：regexp_match 第1个匹配项", "123", matchResult[0]);
                assertEquals("测试31：regexp_match 第2个匹配项", "456", matchResult[1]);
            }
        } else {
            trace("[FAIL] regexp_match 方法不存在");
            failedTests++;
            totalTests++;
        }

        // 测试 regexp_replace
        if (typeof(str.regexp_replace) == "function") {
            var replaceResult:String = str.regexp_replace(re, "#");
            assertEquals("测试32：regexp_replace 结果", "This is # and #.", replaceResult);
        } else {
            trace("[FAIL] regexp_replace 方法不存在");
            failedTests++;
            totalTests++;
        }

        // 测试 regexp_search
        if (typeof(str.regexp_search) == "function") {
            var searchResult:Number = str.regexp_search(re);
            assertEquals("测试33：regexp_search 结果", 8, searchResult);
        } else {
            trace("[FAIL] regexp_search 方法不存在");
            failedTests++;
            totalTests++;
        }

        // 测试 regexp_split
        if (typeof(str.regexp_split) == "function") {
            var splitResult:Array = str.regexp_split(re);
            assertTrue("测试34：regexp_split 返回数组长度为 3", splitResult != null && splitResult.length === 3);
            if (splitResult != null) {
                assertEquals("测试34：regexp_split 第1部分", "This is ", splitResult[0]);
                assertEquals("测试34：regexp_split 第2部分", " and ", splitResult[1]);
                assertEquals("测试34：regexp_split 第3部分", ".", splitResult[2]);
            }
        } else {
            trace("[FAIL] regexp_split 方法不存在");
            failedTests++;
            totalTests++;
        }

        // 移除方法
        RegExp.removeMethods();
        trace("移除 regexp_* 方法从 String.prototype");

        trace("========== 注入原型链测试结束 ==========");
    }

    /**
     * 辅助函数：将数组转换为逗号分隔的字符串
     */
    private static function arrayToString(arr:Array):String {
        if (arr == null) return "null";
        var s:String = "";
        for (var i:Number = 0; i < arr.length; i++) {
            if (i > 0) s += ", ";
            s += arr[i];
        }
        return s;
    }
}
