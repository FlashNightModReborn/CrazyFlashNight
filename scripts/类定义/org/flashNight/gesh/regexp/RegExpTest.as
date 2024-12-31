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
