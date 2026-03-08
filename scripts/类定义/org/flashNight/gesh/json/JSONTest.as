/**
 * JSONTest - JSON 解析器正确性、差异行为与性能基准
 */
class org.flashNight.gesh.json.JSONTest {

    private var passCount:Number;
    private var failCount:Number;
    private var totalCount:Number;

    private var jsonParser:JSON;
    private var liteParser:LiteJSON;
    private var fastParser:FastJSON;

    private var parserNames:Array;
    private var parsers:Array;
    private var benchSink;

    public function JSONTest() {
        this.passCount = 0;
        this.failCount = 0;
        this.totalCount = 0;
        this.benchSink = null;

        this.jsonParser = new JSON(false);
        this.liteParser = new LiteJSON();
        this.fastParser = new FastJSON();
        this.parserNames = ["JSON", "LiteJSON", "FastJSON"];
        this.parsers = [this.jsonParser, this.liteParser, this.fastParser];

        trace("╔══════════════════════════════════════════════════╗");
        trace("║      JSON 解析器正确性、差异行为与性能测试       ║");
        trace("╚══════════════════════════════════════════════════╝");

        trace("\n========== 正确性与差异行为 ==========");
        this.testParsePrimitives();
        this.testParseContainers();
        this.testParseEscapes();
        this.testParseNumbersAndWhitespace();
        this.testParseEdgeCases();
        this.testStringifyBasics();
        this.testStringifyFiltering();
        this.testStringifyEscapes();
        this.testRoundTrip();
        this.testReferenceSemantics();
        this.testMalformedNumberBehavior();
        this.testParserSpecificDifferences();
        this.testErrorHandling();
        this.testCrossParserConsistency();
        this.testBenchmarkWorkloadAssumptions();

        trace("\n---------- 正确性汇总 ----------");
        trace("通过: " + this.passCount + " / " + this.totalCount + "  失败: " + this.failCount);

        trace("\n========== 性能基准 ==========");
        this.benchParseMultiScale();
        this.benchStringifyMultiScale();
        this.benchFastJSONCache();

        trace("\n========== 测试结束 ==========");
    }

    private function toFixed2(n:Number):String {
        var rounded:Number = Math.round(n * 100) / 100;
        var s:String = String(rounded);
        if (s.indexOf(".") < 0) {
            s += ".00";
        } else {
            var dotPos:Number = s.indexOf(".");
            var decimals:Number = length(s) - dotPos - 1;
            while (decimals < 2) {
                s += "0";
                decimals++;
            }
        }
        return s;
    }

    private function toFixed3(n:Number):String {
        var rounded:Number = Math.round(n * 1000) / 1000;
        var s:String = String(rounded);
        if (s.indexOf(".") < 0) {
            s += ".000";
        } else {
            var dotPos:Number = s.indexOf(".");
            var decimals:Number = length(s) - dotPos - 1;
            while (decimals < 3) {
                s += "0";
                decimals++;
            }
        }
        return s;
    }

    private function median(arr:Array):Number {
        var n:Number = arr.length;
        var sorted:Array = [];
        var i:Number = 0;
        while (i < n) {
            sorted[i] = arr[i];
            i++;
        }
        i = 1;
        while (i < n) {
            var v:Number = sorted[i];
            var j:Number = i - 1;
            while (j >= 0 && sorted[j] > v) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = v;
            i++;
        }
        if (n % 2 == 1) {
            return sorted[(n - 1) / 2];
        }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
    }

    private function minValue(arr:Array):Number {
        var v:Number = arr[0];
        var i:Number = 1;
        while (i < arr.length) {
            if (arr[i] < v) {
                v = arr[i];
            }
            i++;
        }
        return v;
    }

    private function maxValue(arr:Array):Number {
        var v:Number = arr[0];
        var i:Number = 1;
        while (i < arr.length) {
            if (arr[i] > v) {
                v = arr[i];
            }
            i++;
        }
        return v;
    }

    private function createRepeatedString(unit:String, count:Number):String {
        var s:String = "";
        var i:Number = 0;
        while (i < count) {
            s += unit;
            i++;
        }
        return s;
    }

    private function buildDeepObjectJSON(depth:Number):String {
        var s:String = "1";
        var i:Number = 0;
        while (i < depth) {
            s = "{\"a\":" + s + "}";
            i++;
        }
        return s;
    }

    private function unwrapDeepObject(root, depth:Number) {
        var value = root;
        var i:Number = 0;
        while (i < depth) {
            value = value.a;
            i++;
        }
        return value;
    }

    private function assert(condition:Boolean, desc:String):Void {
        this.totalCount++;
        if (condition) {
            this.passCount++;
            trace("[PASS] " + desc);
        } else {
            this.failCount++;
            trace("[FAIL] " + desc);
        }
    }

    private function note(desc:String):Void {
        trace("[INFO] " + desc);
    }

    private function assertEqual(desc:String, expected, actual):Void {
        if (expected == null && actual == null) {
            this.assert(typeof expected == typeof actual, desc + " (expected type=" + typeof expected + ", actual type=" + typeof actual + ")");
            return;
        }
        this.assert(expected === actual, desc + " (expected=" + expected + ", actual=" + actual + ")");
    }

    private function assertContains(desc:String, haystack:String, needle:String):Void {
        this.assert(haystack.indexOf(needle) >= 0, desc + " (needle=" + needle + ")");
    }

    private function assertSameReference(desc:String, a, b):Void {
        this.assert(a === b, desc);
    }

    private function assertNotSameReference(desc:String, a, b):Void {
        this.assert(a !== b, desc);
    }

    private function deepEqual(a, b):Boolean {
        if (a === b) {
            return true;
        }
        if (a == null || b == null) {
            return typeof a == typeof b;
        }
        if (typeof a != typeof b) {
            return false;
        }
        if (typeof a != "object") {
            return a === b;
        }
        if (a instanceof Array) {
            if (!(b instanceof Array) || a.length != b.length) {
                return false;
            }
            var ai:Number = 0;
            while (ai < a.length) {
                if (!this.deepEqual(a[ai], b[ai])) {
                    return false;
                }
                ai++;
            }
            return true;
        }
        var keysA:Array = [];
        var keysB:Array = [];
        var k:String;
        for (k in a) {
            keysA.push(k);
        }
        for (k in b) {
            keysB.push(k);
        }
        if (keysA.length != keysB.length) {
            return false;
        }
        var i:Number = 0;
        while (i < keysA.length) {
            if (!this.deepEqual(a[keysA[i]], b[keysA[i]])) {
                return false;
            }
            i++;
        }
        return true;
    }

    private function assertDeepEqual(desc:String, expected, actual):Void {
        this.assert(this.deepEqual(expected, actual), desc);
    }

    private function captureCall(fn:Function):Object {
        var out:Object = {};
        try {
            out.ok = true;
            out.value = fn();
        } catch (e) {
            out.ok = false;
            out.error = e;
        }
        return out;
    }

    private function assertFastJSONThrows(desc:String, input:String):Void {
        var fp:FastJSON = new FastJSON();
        var result:Object = this.captureCall(function() {
            return fp.parse(input);
        });
        this.assert(!result.ok, desc);
    }

    private function assertLiteJSONNoThrow(desc:String, input:String):Void {
        var lp:LiteJSON = new LiteJSON();
        var result:Object = this.captureCall(function() {
            return lp.parse(input);
        });
        this.assert(result.ok, desc);
    }

    private function assertLiteJSONUndefined(desc:String, input:String):Void {
        var lp:LiteJSON = new LiteJSON();
        var result:Object = this.captureCall(function() {
            return lp.parse(input);
        });
        this.assert(result.ok, desc + " 不应抛错");
        this.assert(typeof result.value == "undefined", desc + " 应返回 undefined");
    }

    private function assertFastJSONNoThrow(desc:String, input:String):Object {
        var fp:FastJSON = new FastJSON();
        var result:Object = this.captureCall(function() {
            return fp.parse(input);
        });
        this.assert(result.ok, desc);
        return result;
    }

    private function assertJSONHasErrors(desc:String, input:String):Object {
        var jp:JSON = new JSON(true);
        var value = jp.parse(input);
        this.assert(jp.errors.length > 0, desc + " (errors=" + jp.errors.length + ")");
        return {parser: jp, value: value};
    }

    private function forEachParser(handler:Function):Void {
        var i:Number = 0;
        while (i < this.parsers.length) {
            handler(IJSON(this.parsers[i]), this.parserNames[i]);
            i++;
        }
    }

    private function testParsePrimitives():Void {
        trace("\n--- parse: 基本类型 ---");
        var cases:Array = [
            {input: "null", expected: null, desc: "null"},
            {input: "true", expected: true, desc: "true"},
            {input: "false", expected: false, desc: "false"},
            {input: "42", expected: 42, desc: "整数 42"},
            {input: "3.14", expected: 3.14, desc: "浮点数 3.14"},
            {input: "-7", expected: -7, desc: "负整数 -7"},
            {input: "0", expected: 0, desc: "零"},
            {input: "\"hello\"", expected: "hello", desc: "字符串 hello"},
            {input: "\"\"", expected: "", desc: "空字符串"}
        ];
        var self:JSONTest = this;
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var i:Number = 0;
            while (i < cases.length) {
                var c:Object = cases[i];
                self.assertEqual(name + " parse " + c.desc, c.expected, parser.parse(c.input));
                i++;
            }
        });
    }

    private function testParseContainers():Void {
        trace("\n--- parse: 容器与深层结构 ---");
        var arrayCases:Array = [
            {input: "[]", expected: [], desc: "空数组"},
            {input: "[1,2,3]", expected: [1,2,3], desc: "数字数组"},
            {input: "[\"a\",\"b\"]", expected: ["a","b"], desc: "字符串数组"},
            {input: "[true,false,null]", expected: [true,false,null], desc: "混合数组"},
            {input: "[[1,2],[3,4]]", expected: [[1,2],[3,4]], desc: "嵌套数组"},
            {input: "[[[]]]", expected: [[[]]], desc: "三层空嵌套"}
        ];
        var self:JSONTest = this;
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var i:Number = 0;
            while (i < arrayCases.length) {
                var c:Object = arrayCases[i];
                self.assertDeepEqual(name + " parse " + c.desc, c.expected, parser.parse(c.input));
                i++;
            }
            self.assertDeepEqual(name + " parse 空对象", {}, parser.parse("{}"));
            var obj:Object = parser.parse("{\"name\":\"Alice\",\"age\":30}");
            self.assertEqual(name + " 对象.name", "Alice", obj.name);
            self.assertEqual(name + " 对象.age", 30, obj.age);
        });
        var nested:String = "{\"user\":{\"name\":\"Bob\",\"scores\":[95,88,76],\"address\":{\"city\":\"NYC\"}}}";
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var r:Object = parser.parse(nested);
            self.assertEqual(name + " 嵌套 user.name", "Bob", r.user.name);
            self.assertDeepEqual(name + " 嵌套 user.scores", [95, 88, 76], r.user.scores);
            self.assertEqual(name + " 嵌套 user.address.city", "NYC", r.user.address.city);
        });
        var depth:Number = 32;
        var deepJSON:String = this.buildDeepObjectJSON(depth);
        this.forEachParser(function(parser:IJSON, name:String):Void {
            self.assertEqual(name + " 32层深嵌套", 1, self.unwrapDeepObject(parser.parse(deepJSON), depth));
        });
    }

    private function testParseEscapes():Void {
        trace("\n--- parse: 转义字符 ---");
        // \n\t\r — JSON/FastJSON 正常转义，LiteJSON 无转义原样输出
        var escJSON:String = "{\"msg\":\"line1\\nline2\\ttab\\rret\"}";
        this.assertEqual("JSON \\n\\t\\r", "line1\nline2\ttab\rret", this.jsonParser.parse(escJSON).msg);
        this.assertEqual("FastJSON \\n\\t\\r", "line1\nline2\ttab\rret", this.fastParser.parse(escJSON).msg);
        this.assertEqual("LiteJSON \\n\\t\\r raw", "line1\\nline2\\ttab\\rret", this.liteParser.parse(escJSON).msg);
        // \\ 和 \" — LiteJSON 遇 \" 字符串提前闭合导致整体失败
        var escJSON2:String = "{\"path\":\"C:\\\\Users\\\\test\",\"say\":\"He said \\\"hi\\\"\"}";
        this.assertEqual("JSON 反斜杠", "C:\\Users\\test", this.jsonParser.parse(escJSON2).path);
        this.assertEqual("JSON 引号转义", "He said \"hi\"", this.jsonParser.parse(escJSON2).say);
        this.assertEqual("FastJSON 反斜杠", "C:\\Users\\test", this.fastParser.parse(escJSON2).path);
        this.assertEqual("FastJSON 引号转义", "He said \"hi\"", this.fastParser.parse(escJSON2).say);
        this.assertLiteJSONUndefined("LiteJSON 含 \\\" 解析失败", escJSON2);
        // \/ — LiteJSON 原样保留
        var slashJSON:String = "{\"url\":\"http:\\/\\/example.com\"}";
        this.assertEqual("JSON \\/ 转义", "http://example.com", this.jsonParser.parse(slashJSON).url);
        this.assertEqual("FastJSON \\/ 转义", "http://example.com", this.fastParser.parse(slashJSON).url);
        this.assertEqual("LiteJSON \\/ raw", "http:\\/\\/example.com", this.liteParser.parse(slashJSON).url);
        // Unicode — LiteJSON 原样含反斜杠
        this.assertEqual("JSON Unicode \\u002C", "Hello,World", this.jsonParser.parse("{\"text\":\"Hello\\u002CWorld\"}").text);
        this.assertEqual("LiteJSON Unicode \\u002C raw", "Hello\\u002CWorld", this.liteParser.parse("{\"text\":\"Hello\\u002CWorld\"}").text);
        this.assertEqual("FastJSON Unicode \\u002C", "Hello,World", this.fastParser.parse("{\"text\":\"Hello\\u002CWorld\"}").text);
        this.assertEqual("JSON 连续 Unicode", "Hi", this.jsonParser.parse("\"\\u0048\\u0069\""));
        this.assertEqual("LiteJSON 连续 Unicode raw", "\\u0048\\u0069", this.liteParser.parse("\"\\u0048\\u0069\""));
        this.assertEqual("FastJSON 连续 Unicode", "Hi", this.fastParser.parse("\"\\u0048\\u0069\""));
        // \b\f — LiteJSON 原样含反斜杠
        this.assertEqual("JSON parse \\b\\f", "\b\f", this.jsonParser.parse("\"\\b\\f\""));
        this.assertEqual("LiteJSON parse \\b\\f raw", "\\b\\f", this.liteParser.parse("\"\\b\\f\""));
        this.assertEqual("FastJSON parse \\b\\f", "\b\f", this.fastParser.parse("\"\\b\\f\""));
        // 连续转义序列 — LiteJSON 原样含反斜杠
        this.assertEqual("JSON 连续转义序列", "\n\t\r\\", this.jsonParser.parse("\"\\n\\t\\r\\\\\""));
        this.assertEqual("LiteJSON 连续转义序列 raw", "\\n\\t\\r\\\\", this.liteParser.parse("\"\\n\\t\\r\\\\\""));
        this.assertEqual("FastJSON 连续转义序列", "\n\t\r\\", this.fastParser.parse("\"\\n\\t\\r\\\\\""));
    }

    private function testParseNumbersAndWhitespace():Void {
        trace("\n--- parse: 数字与空白 ---");
        var self:JSONTest = this;
        var normalCases:Array = [
            {input: "0", expected: 0, desc: "零"},
            {input: "0.5", expected: 0.5, desc: "0.5"},
            {input: "-3.14", expected: -3.14, desc: "-3.14"},
            {input: "999", expected: 999, desc: "999"},
            {input: "-0", expected: 0, desc: "-0"},
            {input: "123456789", expected: 123456789, desc: "大整数"},
            {input: "0.001", expected: 0.001, desc: "极小小数"}
        ];
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var i:Number = 0;
            while (i < normalCases.length) {
                var c:Object = normalCases[i];
                self.assertEqual(name + " parse " + c.desc, c.expected, parser.parse(c.input));
                i++;
            }
        });
        this.assertEqual("JSON parse 1e2", 100, this.jsonParser.parse("1e2"));
        this.assertLiteJSONUndefined("LiteJSON 不支持科学计数法 1e2", "1e2");
        this.assertEqual("FastJSON parse 1e2", 100, this.fastParser.parse("1e2"));
        var spaced:String = " \t\n\r{ \t\"a\" \n: \r1 , \"b\" : [ 2 , 3 ] } ";
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var r:Object = parser.parse(spaced);
            self.assertEqual(name + " 空白字符 a", 1, r.a);
            self.assertDeepEqual(name + " 空白字符 b", [2, 3], r.b);
        });
    }

    private function testParseEdgeCases():Void {
        trace("\n--- parse: 边界行为 ---");
        var self:JSONTest = this;
        this.forEachParser(function(parser:IJSON, name:String):Void {
            self.assertEqual(name + " 空白字符串值", "   ", parser.parse("\"   \""));
        });
        // 字符串含 \" — JSON/FastJSON 正常，LiteJSON 因 \" 解析失败
        this.assertEqual("JSON 字符串含 JSON 语法", "{ \"a\": [1,2] }", this.jsonParser.parse("{\"v\":\"{ \\\"a\\\": [1,2] }\"}").v);
        this.assertEqual("FastJSON 字符串含 JSON 语法", "{ \"a\": [1,2] }", this.fastParser.parse("{\"v\":\"{ \\\"a\\\": [1,2] }\"}").v);
        this.assertLiteJSONUndefined("LiteJSON 含 \\\" 的字符串值", "{\"v\":\"{ \\\"a\\\": [1,2] }\"}");
        var longStr:String = "\"" + this.createRepeatedString("abcd", 200) + "\"";
        this.forEachParser(function(parser:IJSON, name:String):Void {
            self.assertEqual(name + " 长字符串长度", 800, length(parser.parse(longStr)));
            self.assertEqual(name + " 重复键后者覆盖", 2, parser.parse("{\"k\":1,\"k\":2}").k);
        });
        var bigArray:String = "[";
        var i:Number = 0;
        while (i < 100) {
            if (i > 0) {
                bigArray += ",";
            }
            bigArray += String(i);
            i++;
        }
        bigArray += "]";
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var arr:Array = parser.parse(bigArray);
            self.assertEqual(name + " 100 元素数组长度", 100, arr.length);
            self.assertEqual(name + " 100 元素数组首", 0, arr[0]);
            self.assertEqual(name + " 100 元素数组末", 99, arr[99]);
        });
    }

    private function testStringifyBasics():Void {
        trace("\n--- stringify: 基本行为 ---");
        var self:JSONTest = this;
        this.forEachParser(function(parser:IJSON, name:String):Void {
            self.assertEqual(name + " stringify null", "null", parser.stringify(null));
            self.assertEqual(name + " stringify true", "true", parser.stringify(true));
            self.assertEqual(name + " stringify false", "false", parser.stringify(false));
            self.assertEqual(name + " stringify 42", "42", parser.stringify(42));
            self.assertEqual(name + " stringify string", "\"hello\"", parser.stringify("hello"));
            self.assertEqual(name + " stringify []", "[]", parser.stringify([]));
            self.assertEqual(name + " stringify {}", "{}", parser.stringify({}));
            self.assertEqual(name + " stringify undefined", "null", parser.stringify(undefined));
            self.assertEqual(name + " stringify NaN", "null", parser.stringify(NaN));
            self.assertEqual(name + " stringify Infinity", "null", parser.stringify(Infinity));
            self.assertEqual(name + " stringify -Infinity", "null", parser.stringify(-Infinity));
            self.assertEqual(name + " stringify 空串", "\"\"", parser.stringify(""));
            self.assertEqual(name + " stringify 0", "0", parser.stringify(0));
        });

        var specialKeys:Object = {};
        specialKeys["a b"] = 1;
        specialKeys["c\"d"] = 2;
        // JSON/FastJSON: stringify→parse 往返正常
        this.assertEqual("JSON 特殊键名空格", 1, this.jsonParser.parse(this.jsonParser.stringify(specialKeys))["a b"]);
        this.assertEqual("JSON 特殊键名引号", 2, this.jsonParser.parse(this.jsonParser.stringify(specialKeys))["c\"d"]);
        this.assertEqual("FastJSON 特殊键名空格", 1, this.fastParser.parse(this.fastParser.stringify(specialKeys))["a b"]);
        this.assertEqual("FastJSON 特殊键名引号", 2, this.fastParser.parse(this.fastParser.stringify(specialKeys))["c\"d"]);
        // LiteJSON: stringify 含 \" 的键名后 parse 失败
        this.assertLiteJSONUndefined("LiteJSON 含引号键名往返失败", this.liteParser.stringify(specialKeys));
    }

    private function testStringifyFiltering():Void {
        trace("\n--- stringify: undefined / function 过滤 ---");
        var self:JSONTest = this;
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var obj:Object = {};
            obj.keep = 1;
            obj.skip = undefined;
            obj.fn = function() {
                return 1;
            };
            var reparsed:Object = parser.parse(parser.stringify(obj));
            self.assertEqual(name + " 保留普通属性", 1, reparsed.keep);
            self.assert(typeof reparsed.skip == "undefined", name + " 跳过 undefined 属性");
            self.assert(typeof reparsed.fn == "undefined", name + " 跳过 function 属性");
        });
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var arr:Array = [1, undefined, null, 4];
            var reparsed:Array = parser.parse(parser.stringify(arr));
            self.assertEqual(name + " 数组元素 0", 1, reparsed[0]);
            self.assertEqual(name + " 数组 undefined -> null", null, reparsed[1]);
            self.assertEqual(name + " 数组 null 保留", null, reparsed[2]);
            self.assertEqual(name + " 数组元素 3", 4, reparsed[3]);
        });
    }

    private function testStringifyEscapes():Void {
        trace("\n--- stringify: 转义与控制字符 ---");
        var self:JSONTest = this;
        // JSON / FastJSON 转义控制字符
        var jsonEsc:String = this.jsonParser.stringify("a\nb\tc\rd");
        this.assertContains("JSON stringify 含 \\n", jsonEsc, "\\n");
        this.assertContains("JSON stringify 含 \\t", jsonEsc, "\\t");
        this.assertContains("JSON stringify 含 \\r", jsonEsc, "\\r");
        var fastEsc:String = this.fastParser.stringify("a\nb\tc\rd");
        this.assertContains("FastJSON stringify 含 \\n", fastEsc, "\\n");
        this.assertContains("FastJSON stringify 含 \\t", fastEsc, "\\t");
        this.assertContains("FastJSON stringify 含 \\r", fastEsc, "\\r");
        // LiteJSON 不转义控制字符（与 parse 不处理转义序列对齐，原样输出）
        var liteEsc:String = this.liteParser.stringify("a\nb\tc\rd");
        this.assert(liteEsc.indexOf("\\n") < 0, "LiteJSON stringify 不转义 \\n");
        this.assert(liteEsc.indexOf("\\t") < 0, "LiteJSON stringify 不转义 \\t");
        this.assert(liteEsc.indexOf("\\r") < 0, "LiteJSON stringify 不转义 \\r");
        // \ 和 " 结构性转义 — 三套实现一致
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var quoted:String = parser.stringify("\"\\\\");
            self.assertContains(name + " stringify 引号转义", quoted, "\\\"");
            self.assertContains(name + " stringify 反斜杠转义", quoted, "\\\\");
        });
        this.assertContains("JSON stringify 含 \\b", this.jsonParser.stringify("\b\f"), "\\b");
        this.assertContains("JSON stringify 含 \\f", this.jsonParser.stringify("\b\f"), "\\f");
        this.assertContains("FastJSON stringify 含 \\b", this.fastParser.stringify("\b\f"), "\\b");
        this.assertContains("FastJSON stringify 含 \\f", this.fastParser.stringify("\b\f"), "\\f");
        var control:String = String.fromCharCode(1);
        this.assertContains("JSON stringify 控制字符转 \\u", this.jsonParser.stringify(control), "\\u0001");
        // LiteJSON 不转义控制字符，原样输出
        this.assert(this.liteParser.stringify(control).indexOf("\\u0001") < 0, "LiteJSON stringify 不转义控制字符");
        this.assertContains("FastJSON stringify 控制字符转 \\u", this.fastParser.stringify(control), "\\u0001");
    }

    private function testRoundTrip():Void {
        trace("\n--- roundtrip: 往返一致性 ---");
        var self:JSONTest = this;
        var testObj:Object = {};
        testObj.name = "测试";
        testObj.value = 3.14;
        testObj.active = true;
        testObj.tags = ["a", "b", "c"];
        testObj.nested = {x: 1, y: 2};
        testObj.arr = [1, [2, 3], {k: "v"}];
        testObj.nullVal = null;
        testObj.zero = 0;
        testObj.emptyStr = "";
        testObj.emptyArr = [];
        this.forEachParser(function(parser:IJSON, name:String):Void {
            var reparsed:Object = parser.parse(parser.stringify(testObj));
            self.assertEqual(name + " RT name", testObj.name, reparsed.name);
            self.assertEqual(name + " RT value", testObj.value, reparsed.value);
            self.assertEqual(name + " RT active", testObj.active, reparsed.active);
            self.assertDeepEqual(name + " RT tags", testObj.tags, reparsed.tags);
            self.assertDeepEqual(name + " RT nested", testObj.nested, reparsed.nested);
            self.assertDeepEqual(name + " RT arr", testObj.arr, reparsed.arr);
            self.assertEqual(name + " RT nullVal", null, reparsed.nullVal);
            self.assertEqual(name + " RT zero", 0, reparsed.zero);
            self.assertEqual(name + " RT emptyStr", "", reparsed.emptyStr);
            self.assertDeepEqual(name + " RT emptyArr", [], reparsed.emptyArr);
        });
    }

    private function testReferenceSemantics():Void {
        trace("\n--- 差异: 引用语义与缓存副作用 ---");
        var jsonText:String = "{\"a\":1,\"nested\":{\"b\":2}}";
        var jsonA:Object = (new JSON(false)).parse(jsonText);
        var jsonB:Object = (new JSON(false)).parse(jsonText);
        this.assertNotSameReference("JSON 重复 parse 返回新对象", jsonA, jsonB);
        var liteA:Object = (new LiteJSON()).parse(jsonText);
        var liteB:Object = (new LiteJSON()).parse(jsonText);
        this.assertNotSameReference("LiteJSON 重复 parse 返回新对象", liteA, liteB);
        var fastP:FastJSON = new FastJSON();
        var fastA:Object = fastP.parse(jsonText);
        var fastB:Object = fastP.parse(jsonText);
        this.assertSameReference("FastJSON 重复 parse 返回同一引用", fastA, fastB);
        fastA.nested.b = 99;
        this.assertEqual("FastJSON parse 缓存共享已修改对象", 99, fastP.parse(jsonText).nested.b);

        var jsonObj:Object = {value: 1};
        var liteObj:Object = {value: 1};
        var fastObj:Object = {value: 1};
        var jsonLocal:JSON = new JSON(false);
        var liteLocal:LiteJSON = new LiteJSON();
        var fastLocal:FastJSON = new FastJSON();
        var fastBefore:String = fastLocal.stringify(fastObj);
        jsonObj.value = 2;
        liteObj.value = 2;
        fastObj.value = 2;
        this.assertEqual("JSON stringify 反映对象变更", "{\"value\":2}", jsonLocal.stringify(jsonObj));
        this.assertEqual("LiteJSON stringify 反映对象变更", "{\"value\":2}", liteLocal.stringify(liteObj));
        this.assertEqual("FastJSON stringify 使用旧缓存结果", fastBefore, fastLocal.stringify(fastObj));
    }

    private function testMalformedNumberBehavior():Void {
        trace("\n--- 差异: 非法数字 fallback ---");

        var jsonP:JSON = new JSON(true);
        var jsonValue = jsonP.parse("1e");
        this.assertEqual("JSON 解析不完整指数 1e", 1, jsonValue);
        this.assertEqual("JSON 不完整指数 1e 不记录错误", 0, jsonP.errors.length);

        this.assertLiteJSONUndefined("LiteJSON 拒绝 trailing 字母 1e", "1e");
        this.assertLiteJSONUndefined("LiteJSON 拒绝缺失小数位 1.", "1.");

        var fastResult:Object = this.assertFastJSONNoThrow("FastJSON 接受不完整指数 1e", "1e");
        if (fastResult.ok) {
            this.assertEqual("FastJSON 解析不完整指数 1e", 1, fastResult.value);
        }
    }

    private function testParserSpecificDifferences():Void {
        trace("\n--- 差异: LiteJSON / FastJSON 当前行为 ---");
        // LiteJSON 精简模式：无转义处理，原样输出含反斜杠（实际数据从未使用转义）
        this.assertEqual("LiteJSON \\uXXXX raw 含反斜杠", "\\u0041\\u4E2D", this.liteParser.parse("\"\\u0041\\u4E2D\""));
        this.assertEqual("LiteJSON \\b\\f raw 含反斜杠", "\\b\\f", this.liteParser.parse("\"\\b\\f\""));
        this.assertLiteJSONUndefined("LiteJSON 不支持科学记数法", "1e2");
        this.assertLiteJSONUndefined("LiteJSON 拒绝根值后的 trailing token", "1xyz");
        var jsonResult:Object = this.assertJSONHasErrors("JSON 记录 trailing token 错误", "{\"a\":1}xyz");
        this.assertEqual("JSON 仍保留已解析根对象", 1, jsonResult.value.a);
        this.assertFastJSONThrows("FastJSON trailing token 直接抛错", "{\"a\":1}xyz");
        var liteEncoded:String = this.liteParser.stringify("\b\f");
        // LiteJSON 不转义控制字符，原样包裹引号
        this.assertEqual("LiteJSON stringify 输出 \\b\\f raw", "\"\b\f\"", liteEncoded);
        // round-trip: parse 读回原始控制字符
        this.assertEqual("LiteJSON parse 自身 stringify 后 \\b\\f", "\b\f", this.liteParser.parse(liteEncoded));
    }

    private function testErrorHandling():Void {
        trace("\n--- 错误处理: 非法输入 ---");
        var badCases:Array = [
            {desc: "缺少冒号", input: "{\"a\" 1}", jsonErrors: true, fastThrows: true, liteUndefined: true},
            {desc: "对象尾逗号", input: "{\"a\":1,}", jsonErrors: false, fastThrows: false, liteUndefined: true, jsonExpected: 1, jsonExtract: function(v) { return v.a; }},
            {desc: "数组尾逗号", input: "[1,]", jsonErrors: false, fastThrows: true, liteUndefined: true, jsonExpected: 1, jsonExtract: function(v) { return v[0]; }},
            {desc: "数组未闭合", input: "[1,2", jsonErrors: true, fastThrows: true, liteUndefined: true},
            {desc: "非法 Unicode", input: "\"\\u12G4\"", jsonErrors: true, fastThrows: true, liteUndefined: false}
        ];
        var i:Number = 0;
        while (i < badCases.length) {
            var c:Object = badCases[i];
            if (c.jsonErrors) {
                this.assertJSONHasErrors("JSON 记录错误: " + c.desc, c.input);
            } else {
                var tolerantJSON:JSON = new JSON(true);
                var tolerantValue = tolerantJSON.parse(c.input);
                this.assertEqual("JSON 容错: " + c.desc, 0, tolerantJSON.errors.length);
                if (c.jsonExpected != undefined) {
                    this.assertEqual("JSON " + c.desc + " 仍保留已解析值", c.jsonExpected, c.jsonExtract(tolerantValue));
                }
            }
            if (c.fastThrows) {
                this.assertFastJSONThrows("FastJSON 抛错: " + c.desc, c.input);
            } else {
                var fastResult:Object = this.assertFastJSONNoThrow("FastJSON 容错: " + c.desc, c.input);
                if (fastResult.ok && c.jsonExpected != undefined) {
                    this.assertEqual("FastJSON " + c.desc + " 仍保留已解析值", c.jsonExpected, c.jsonExtract(fastResult.value));
                }
            }
            if (c.liteUndefined) {
                this.assertLiteJSONUndefined("LiteJSON 拒绝非法输入: " + c.desc, c.input);
            } else {
                this.assertLiteJSONNoThrow("LiteJSON 当前容错: " + c.desc, c.input);
            }
            i++;
        }
    }

    private function testCrossParserConsistency():Void {
        trace("\n--- 跨解析器一致性 ---");
        var testObj:Object = {a: 1, b: "hello", c: [true, null, 3.14], d: {e: "world"}};
        var jsonStr:String = this.jsonParser.stringify(testObj);
        this.assertDeepEqual("JSON -> LiteJSON 一致", testObj, this.liteParser.parse(jsonStr));
        this.assertDeepEqual("JSON -> FastJSON 一致", testObj, this.fastParser.parse(jsonStr));
        var liteStr:String = this.liteParser.stringify(testObj);
        this.assertDeepEqual("LiteJSON -> JSON 一致", testObj, this.jsonParser.parse(liteStr));
        this.assertDeepEqual("LiteJSON -> FastJSON 一致", testObj, this.fastParser.parse(liteStr));
        var fastStr:String = this.fastParser.stringify(testObj);
        this.assertDeepEqual("FastJSON -> JSON 一致", testObj, this.jsonParser.parse(fastStr));
        this.assertDeepEqual("FastJSON -> LiteJSON 一致", testObj, this.liteParser.parse(fastStr));
    }

    private function testBenchmarkWorkloadAssumptions():Void {
        trace("\n--- benchmark: 负载自校验 ---");
        var variants:Array = this.generateVariants(6, 4);
        this.assertEqual("生成 benchmark 变体数量", 4, variants.length);
        this.assert(variants[0] !== variants[1], "benchmark 相邻字符串变体不同");

        var variantObjA:Object = this.liteParser.parse(variants[0]);
        var variantObjB:Object = this.liteParser.parse(variants[1]);
        this.assertEqual("benchmark 对象变体 A seed", 0, variantObjA.metadata.seed);
        this.assertEqual("benchmark 对象变体 B seed", 1, variantObjB.metadata.seed);
        this.assertEqual("benchmark 对象变体 A items 长度", 6, variantObjA.items.length);
        this.assertEqual("benchmark 对象变体 B items 长度", 6, variantObjB.items.length);
        this.assertEqual("benchmark 对象变体 A 首项 id", 0, variantObjA.items[0].id);
        this.assertEqual("benchmark 对象变体 A 首项 tags 长度", 2, variantObjA.items[0].tags.length);
        this.assertNotSameReference("benchmark 对象变体互不共享引用", variantObjA, variantObjB);

        var fastMiss:FastJSON = new FastJSON();
        var missA:Object = fastMiss.parse(variants[0]);
        var missB:Object = fastMiss.parse(variants[1]);
        this.assertNotSameReference("FastJSON 失配路径不复用不同字符串的 parse 引用", missA, missB);
        this.assertEqual("FastJSON 失配路径保留 A seed", 0, missA.metadata.seed);
        this.assertEqual("FastJSON 失配路径保留 B seed", 1, missB.metadata.seed);

        var strictParseA:FastJSON = new FastJSON();
        var strictParseB:FastJSON = new FastJSON();
        this.assertNotSameReference("FastJSON 严格冷启动 parse 不共享引用", strictParseA.parse(variants[0]), strictParseB.parse(variants[0]));

        var strictObj:Object = {metadata: {seed: 0}, items: [1, 2], enabled: true};
        var strictStringifyA:FastJSON = new FastJSON();
        var strictBefore:String = strictStringifyA.stringify(strictObj);
        strictObj.metadata.seed = 77;
        var strictStringifyB:FastJSON = new FastJSON();
        var strictAfter:String = strictStringifyB.stringify(strictObj);
        this.assert(strictBefore !== strictAfter, "FastJSON 严格冷启动 stringify 不复用旧缓存");
    }

    private function generateBenchJSON(itemCount:Number, seed:Number):String {
        if (seed == undefined) {
            seed = 0;
        }
        var s:String = "{\"metadata\":{\"version\":\"1.0\",\"count\":" + itemCount + ",\"seed\":" + seed + ",\"active\":true},\"items\":[";
        var i:Number = 0;
        while (i < itemCount) {
            if (i > 0) {
                s += ",";
            }
            s += "{\"id\":" + (i + seed) + ",\"name\":\"item_" + i + "\",\"value\":" + (i * 1.5 + seed) + ",\"enabled\":" + ((i % 2 == 0) ? "true" : "false") + ",\"tags\":[\"t" + i + "\",\"common\"]}";
            i++;
        }
        s += "],\"config\":{\"maxRetry\":3,\"timeout\":5000,\"debug\":false,\"label\":\"benchmark\"}}";
        return s;
    }

    private function generateVariants(itemCount:Number, count:Number):Array {
        var variants:Array = [];
        var i:Number = 0;
        while (i < count) {
            variants[i] = this.generateBenchJSON(itemCount, i);
            i++;
        }
        return variants;
    }

    private function parseVariants(variants:Array):Array {
        var objs:Array = [];
        var lite:LiteJSON = new LiteJSON();
        var i:Number = 0;
        while (i < variants.length) {
            objs[i] = lite.parse(variants[i]);
            i++;
        }
        return objs;
    }

    private function timeReadStringLoop(jsonStr:String, iterations:Number):Number {
        var sink:String = "";
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = jsonStr;
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeReadVariantLoop(variants:Array, iterations:Number, batchSize:Number):Number {
        var sink:String = "";
        var vLen:Number = variants.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = variants[idx];
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeReadObjectLoop(obj:Object, iterations:Number):Number {
        var sink:Object = null;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = obj;
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeReadObjectVariantLoop(objects:Array, iterations:Number, batchSize:Number):Number {
        var sink:Object = null;
        var vLen:Number = objects.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = objects[idx];
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeJSONParseLoop(parser:JSON, jsonStr:String, iterations:Number):Number {
        var sink:Object = null;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = parser.parse(jsonStr);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeLiteParseLoop(parser:LiteJSON, jsonStr:String, iterations:Number):Number {
        var sink:Object = null;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = parser.parse(jsonStr);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeFastParseColdLoop(variants:Array, iterations:Number, batchSize:Number):Number {
        var parser:FastJSON = new FastJSON();
        var sink:Object = null;
        var vLen:Number = variants.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = parser.parse(variants[idx]);
                idx++;
                if (idx >= vLen) {
                    parser = new FastJSON();
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeFastParseStrictColdLoop(variants:Array, iterations:Number, batchSize:Number):Number {
        var parser:FastJSON = null;
        var sink:Object = null;
        var vLen:Number = variants.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                parser = new FastJSON();
                sink = parser.parse(variants[idx]);
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeFastParseHotLoop(parser:FastJSON, jsonStr:String, iterations:Number):Number {
        var sink:Object = null;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = parser.parse(jsonStr);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeJSONStringifyLoop(parser:JSON, obj:Object, iterations:Number):Number {
        var sink:String = "";
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = parser.stringify(obj);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeLiteStringifyLoop(parser:LiteJSON, obj:Object, iterations:Number):Number {
        var sink:String = "";
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = parser.stringify(obj);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeFastStringifyColdLoop(objects:Array, iterations:Number, batchSize:Number):Number {
        var parser:FastJSON = new FastJSON();
        var sink:String = "";
        var vLen:Number = objects.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = parser.stringify(objects[idx]);
                idx++;
                if (idx >= vLen) {
                    parser = new FastJSON();
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeFastStringifyStrictColdLoop(objects:Array, iterations:Number, batchSize:Number):Number {
        var parser:FastJSON = null;
        var sink:String = "";
        var vLen:Number = objects.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                parser = new FastJSON();
                sink = parser.stringify(objects[idx]);
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function timeFastStringifyHotLoop(parser:FastJSON, obj:Object, iterations:Number):Number {
        var sink:String = "";
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = parser.stringify(obj);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    private function buildBenchStats(totalTimes:Array, baselineTimes:Array, iterations:Number, payloadChars:Number, opsPerIteration:Number):Object {
        var adjustedTimes:Array = [];
        var i:Number = 0;
        while (i < totalTimes.length) {
            var adjusted:Number = Number(totalTimes[i]) - Number(baselineTimes[i]);
            if (adjusted < 0) {
                adjusted = 0;
            }
            adjustedTimes[i] = adjusted;
            i++;
        }

        var stats:Object = {};
        stats.iterations = iterations;
        stats.opsPerIteration = opsPerIteration;
        stats.totalOps = iterations * opsPerIteration;
        stats.rawTotalMedianMs = this.median(totalTimes);
        stats.rawBaselineMedianMs = this.median(baselineTimes);
        stats.totalMedianMs = this.median(adjustedTimes);
        stats.perOpMs = (stats.totalOps > 0) ? (stats.totalMedianMs / stats.totalOps) : 0;
        stats.minTotalMs = this.minValue(adjustedTimes);
        stats.maxTotalMs = this.maxValue(adjustedTimes);
        stats.rawTotalRangeMs = this.maxValue(totalTimes) - this.minValue(totalTimes);
        stats.rawBaselineRangeMs = this.maxValue(baselineTimes) - this.minValue(baselineTimes);
        var stableRawWindow:Boolean = stats.rawTotalMedianMs >= 80 &&
            stats.rawBaselineMedianMs >= 20 &&
            stats.rawTotalRangeMs <= (stats.rawTotalMedianMs * 0.08 + 2) &&
            stats.rawBaselineRangeMs <= (stats.rawBaselineMedianMs * 0.10 + 2);
        stats.reliable = stats.totalMedianMs >= 30 || (stats.totalMedianMs >= 12 && stableRawWindow);
        stats.timerFloor = (stats.totalMedianMs <= 0) ||
            (!stats.reliable && stats.rawTotalMedianMs < 30);
        if (payloadChars > 0 && stats.totalMedianMs > 0) {
            stats.mbPerSec = (payloadChars * stats.totalOps / 1048576) / (stats.totalMedianMs / 1000);
        } else {
            stats.mbPerSec = 0;
        }
        return stats;
    }

    private function sampleBenchStats(timedFn:Function, baselineFn:Function, iterations:Number, repeats:Number, payloadChars:Number, opsPerIteration:Number):Object {
        timedFn(iterations);
        baselineFn(iterations);

        var totalTimes:Array = [];
        var baselineTimes:Array = [];
        var r:Number = 0;
        while (r < repeats) {
            baselineTimes[r] = Number(baselineFn(iterations));
            totalTimes[r] = Number(timedFn(iterations));
            r++;
        }
        return this.buildBenchStats(totalTimes, baselineTimes, iterations, payloadChars, opsPerIteration);
    }

    private function computeIterationGrowth(stats:Object, targetAdjustedMs:Number, targetRawTotalMs:Number):Number {
        var adjustedScale:Number = 1;
        var rawScale:Number = 1;
        if (targetAdjustedMs > 0) {
            if (stats.totalMedianMs > 0) {
                adjustedScale = targetAdjustedMs / stats.totalMedianMs;
            } else {
                adjustedScale = 8;
            }
        }
        if (targetRawTotalMs > 0) {
            if (stats.rawTotalMedianMs > 0) {
                rawScale = targetRawTotalMs / stats.rawTotalMedianMs;
            } else {
                rawScale = 8;
            }
        }
        var scale:Number = Math.ceil(Math.max(adjustedScale, rawScale));
        if (scale < 2) {
            scale = 2;
        } else if (scale > 8) {
            scale = 8;
        }
        return scale;
    }

    private function calibrateIterations(timedFn:Function, baselineFn:Function, targetAdjustedMs:Number, targetRawTotalMs:Number, startIterations:Number, maxIterations:Number, opsPerIteration:Number):Number {
        var iterations:Number = startIterations;
        if (iterations < 1) {
            iterations = 1;
        }
        var round:Number = 0;
        while (round < 8) {
            var probe:Object = this.sampleBenchStats(timedFn, baselineFn, iterations, 3, 0, opsPerIteration);
            if ((probe.totalMedianMs >= targetAdjustedMs && probe.rawTotalMedianMs >= targetRawTotalMs) || iterations >= maxIterations) {
                break;
            }
            var growth:Number = this.computeIterationGrowth(probe, targetAdjustedMs, targetRawTotalMs);
            var scaled:Number = iterations * growth;
            if (scaled <= iterations) {
                scaled = iterations * 2;
            }
            iterations = scaled;
            if (iterations > maxIterations) {
                iterations = maxIterations;
            }
            round++;
        }
        return iterations;
    }

    private function measureBenchStats(timedFn:Function, baselineFn:Function, targetAdjustedMs:Number, targetRawTotalMs:Number, startIterations:Number, maxIterations:Number, repeats:Number, payloadChars:Number, opsPerIteration:Number):Object {
        if (opsPerIteration == undefined || opsPerIteration < 1) {
            opsPerIteration = 1;
        }
        var iterations:Number = this.calibrateIterations(timedFn, baselineFn, targetAdjustedMs, targetRawTotalMs, startIterations, maxIterations, opsPerIteration);
        var stats:Object = this.sampleBenchStats(timedFn, baselineFn, iterations, repeats, payloadChars, opsPerIteration);
        var refineRound:Number = 0;
        while (refineRound < 4 &&
               iterations < maxIterations &&
               (stats.totalMedianMs < targetAdjustedMs || stats.rawTotalMedianMs < targetRawTotalMs)) {
            var growth:Number = this.computeIterationGrowth(stats, targetAdjustedMs, targetRawTotalMs);
            var nextIterations:Number = iterations * growth;
            if (nextIterations <= iterations) {
                nextIterations = iterations * 2;
            }
            if (nextIterations > maxIterations) {
                nextIterations = maxIterations;
            }
            if (nextIterations == iterations) {
                break;
            }
            iterations = nextIterations;
            stats = this.sampleBenchStats(timedFn, baselineFn, iterations, repeats, payloadChars, opsPerIteration);
            refineRound++;
        }
        return stats;
    }

    private function reportBenchStats(label:String, stats:Object):Void {
        var line:String = "    " + label;
        if (stats.timerFloor) {
            line += "低于计时分辨率";
        } else if (stats.perOpMs < 0.1) {
            line += this.toFixed2(stats.perOpMs * 1000) + " us/次";
        } else {
            line += this.toFixed3(stats.perOpMs) + " ms/次";
        }
        if (stats.opsPerIteration > 1) {
            line += " | " + stats.iterations + " 批/轮 x" + stats.opsPerIteration + " = " + stats.totalOps + " 次";
        } else {
            line += " | " + stats.iterations + " 次/轮";
        }
        line += " | 中位总 " + this.toFixed2(stats.totalMedianMs) + " ms";
        if (stats.mbPerSec > 0) {
            line += " | " + this.toFixed2(stats.mbPerSec) + " MB/s";
        }
        if (stats.minTotalMs > 0) {
            line += " | 波动 " + this.toFixed2(stats.maxTotalMs / stats.minTotalMs) + "x";
        }
        if (!stats.reliable && stats.rawTotalMedianMs > 0) {
            line += " | 原始/基线 " + this.toFixed2(stats.rawTotalMedianMs) + "/" + this.toFixed2(stats.rawBaselineMedianMs) + " ms";
        }
        if (!stats.reliable) {
            line += " | 低置信度";
        }
        trace(line);
    }

    private function reportRatio(label:String, numerator:Object, denominator:Object):Void {
        if (numerator.perOpMs > 0 && denominator.perOpMs > 0 &&
            numerator.reliable && denominator.reliable &&
            !numerator.timerFloor && !denominator.timerFloor) {
            trace("    " + label + this.toFixed2(numerator.perOpMs / denominator.perOpMs) + "x");
        } else {
            trace("    " + label + "n/a（低置信度）");
        }
    }

    private function benchParseMultiScale():Void {
        trace("\n--- parse 性能基准（等价路径 + 基线扣除） ---");
        trace("  说明: FastJSON 失配 = 同实例不同 payload；严冷 = 每次操作新建实例；热 = 缓存命中。");
        trace("  冷路径: 使用有限变体循环并按批次聚合多次冷操作，避免缓存复用同时维持计时置信度。");
        var scales:Array = [
            {items: 10, desc: "小(10项)", parseStart: 8, parseMax: 256, coldVariants: 128, coldBatch: 32, coldStart: 8, coldMaxIters: 4096, hotStart: 512, hotMax: 50000},
            {items: 50, desc: "中(50项)", parseStart: 2, parseMax: 96, coldVariants: 128, coldBatch: 64, coldStart: 4, coldMaxIters: 2048, hotStart: 256, hotMax: 30000},
            {items: 200, desc: "大(200项)", parseStart: 1, parseMax: 24, coldVariants: 32, coldBatch: 64, coldStart: 2, coldMaxIters: 1024, hotStart: 128, hotMax: 10000}
        ];
        var repeats:Number = 5;
        var targetAdjustedMs:Number = 120;
        var coldTargetAdjustedMs:Number = 240;
        var self:JSONTest = this;
        var si:Number = 0;
        while (si < scales.length) {
            var scale:Object = scales[si];
            var jsonStr:String = this.generateBenchJSON(scale.items, 0);
            var variants:Array = this.generateVariants(scale.items, scale.coldVariants);
            var payloadChars:Number = length(jsonStr);
            trace("\n  " + scale.desc + " | " + payloadChars + " 字符");

            var jp:JSON = new JSON(false);
            var jsonStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeJSONParseLoop(jp, jsonStr, iterations);
            }, function(iterations:Number):Number {
                return self.timeReadStringLoop(jsonStr, iterations);
            }, targetAdjustedMs, 0, scale.parseStart, scale.parseMax, repeats, payloadChars, 1);
            this.reportBenchStats("JSON:         ", jsonStats);

            var lp:LiteJSON = new LiteJSON();
            var liteStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeLiteParseLoop(lp, jsonStr, iterations);
            }, function(iterations:Number):Number {
                return self.timeReadStringLoop(jsonStr, iterations);
            }, targetAdjustedMs, 0, scale.parseStart, scale.parseMax, repeats, payloadChars, 1);
            this.reportBenchStats("LiteJSON:     ", liteStats);

            var fastMissStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeFastParseColdLoop(variants, iterations, scale.coldBatch);
            }, function(iterations:Number):Number {
                return self.timeReadVariantLoop(variants, iterations, scale.coldBatch);
            }, coldTargetAdjustedMs, 120, scale.coldStart, scale.coldMaxIters, repeats, payloadChars, scale.coldBatch);
            this.reportBenchStats("FastJSON(失配): ", fastMissStats);

            var fastStrictStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeFastParseStrictColdLoop(variants, iterations, scale.coldBatch);
            }, function(iterations:Number):Number {
                return self.timeReadVariantLoop(variants, iterations, scale.coldBatch);
            }, coldTargetAdjustedMs, 120, scale.coldStart, scale.coldMaxIters, repeats, payloadChars, scale.coldBatch);
            this.reportBenchStats("FastJSON(严冷): ", fastStrictStats);

            var fpHot:FastJSON = new FastJSON();
            fpHot.parse(jsonStr);
            var fastHotStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeFastParseHotLoop(fpHot, jsonStr, iterations);
            }, function(iterations:Number):Number {
                return self.timeReadStringLoop(jsonStr, iterations);
            }, targetAdjustedMs, 0, scale.hotStart, scale.hotMax, repeats, payloadChars, 1);
            this.reportBenchStats("FastJSON(热): ", fastHotStats);

            trace("    --");
            this.reportRatio("JSON / LiteJSON = ", jsonStats, liteStats);
            this.reportRatio("LiteJSON / FastJSON(严冷) = ", liteStats, fastStrictStats);
            this.reportRatio("FastJSON 严冷 / 失配 = ", fastStrictStats, fastMissStats);
            this.reportRatio("FastJSON 失配 / 热 = ", fastMissStats, fastHotStats);
            this.reportRatio("FastJSON 严冷 / 热 = ", fastStrictStats, fastHotStats);
            si++;
        }
    }

    private function benchStringifyMultiScale():Void {
        trace("\n--- stringify 性能基准（等价路径 + 基线扣除） ---");
        trace("  说明: FastJSON 失配 = 同实例不同对象；严冷 = 每次操作新建实例；热 = 同对象命中身份缓存。");
        trace("  冷路径: 使用有限对象变体循环并按批次聚合多次冷操作，避免缓存复用同时维持计时置信度。");
        var scales:Array = [
            {items: 10, desc: "小(10项)", stringifyStart: 512, stringifyMax: 65536, coldVariants: 128, coldBatch: 32, coldStart: 8, coldMaxIters: 4096, hotStart: 512, hotMax: 50000},
            {items: 50, desc: "中(50项)", stringifyStart: 512, stringifyMax: 65536, coldVariants: 128, coldBatch: 64, coldStart: 4, coldMaxIters: 2048, hotStart: 256, hotMax: 30000},
            {items: 200, desc: "大(200项)", stringifyStart: 512, stringifyMax: 131072, coldVariants: 32, coldBatch: 64, coldStart: 2, coldMaxIters: 1024, hotStart: 128, hotMax: 12000}
        ];
        var repeats:Number = 5;
        var targetAdjustedMs:Number = 120;
        var coldTargetAdjustedMs:Number = 240;
        var self:JSONTest = this;
        var si:Number = 0;
        while (si < scales.length) {
            var scale:Object = scales[si];
            var jsonStr:String = this.generateBenchJSON(scale.items, 0);
            var testObj:Object = this.liteParser.parse(jsonStr);
            var variants:Array = this.generateVariants(scale.items, scale.coldVariants);
            var objectVariants:Array = this.parseVariants(variants);
            var payloadChars:Number = length(jsonStr);
            trace("\n  " + scale.desc + " | 约 " + payloadChars + " 输出字符");

            var jp:JSON = new JSON(false);
            var jsonStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeJSONStringifyLoop(jp, testObj, iterations);
            }, function(iterations:Number):Number {
                return self.timeReadObjectLoop(testObj, iterations);
            }, targetAdjustedMs, 0, scale.stringifyStart, scale.stringifyMax, repeats, payloadChars, 1);
            this.reportBenchStats("JSON:         ", jsonStats);

            var lp:LiteJSON = new LiteJSON();
            var liteStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeLiteStringifyLoop(lp, testObj, iterations);
            }, function(iterations:Number):Number {
                return self.timeReadObjectLoop(testObj, iterations);
            }, targetAdjustedMs, 0, scale.stringifyStart, scale.stringifyMax, repeats, payloadChars, 1);
            this.reportBenchStats("LiteJSON:     ", liteStats);

            var fastMissStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeFastStringifyColdLoop(objectVariants, iterations, scale.coldBatch);
            }, function(iterations:Number):Number {
                return self.timeReadObjectVariantLoop(objectVariants, iterations, scale.coldBatch);
            }, coldTargetAdjustedMs, 120, scale.coldStart, scale.coldMaxIters, repeats, payloadChars, scale.coldBatch);
            this.reportBenchStats("FastJSON(失配): ", fastMissStats);

            var fastStrictStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeFastStringifyStrictColdLoop(objectVariants, iterations, scale.coldBatch);
            }, function(iterations:Number):Number {
                return self.timeReadObjectVariantLoop(objectVariants, iterations, scale.coldBatch);
            }, coldTargetAdjustedMs, 120, scale.coldStart, scale.coldMaxIters, repeats, payloadChars, scale.coldBatch);
            this.reportBenchStats("FastJSON(严冷): ", fastStrictStats);

            var fpHot:FastJSON = new FastJSON();
            fpHot.stringify(testObj);
            var fastHotStats:Object = this.measureBenchStats(function(iterations:Number):Number {
                return self.timeFastStringifyHotLoop(fpHot, testObj, iterations);
            }, function(iterations:Number):Number {
                return self.timeReadObjectLoop(testObj, iterations);
            }, targetAdjustedMs, 0, scale.hotStart, scale.hotMax, repeats, payloadChars, 1);
            this.reportBenchStats("FastJSON(热): ", fastHotStats);

            trace("    --");
            this.reportRatio("JSON / LiteJSON = ", jsonStats, liteStats);
            this.reportRatio("LiteJSON / FastJSON(严冷) = ", liteStats, fastStrictStats);
            this.reportRatio("FastJSON 严冷 / 失配 = ", fastStrictStats, fastMissStats);
            this.reportRatio("FastJSON 失配 / 热 = ", fastMissStats, fastHotStats);
            this.reportRatio("FastJSON 严冷 / 热 = ", fastStrictStats, fastHotStats);
            si++;
        }
    }

    private function benchFastJSONCache():Void {
        trace("\n--- FastJSON 缓存专项（中规模） ---");
        trace("  说明: 失配 = 同实例不同 payload；严冷 = 每次新实例；热 = 同 payload / 同对象命中缓存。");
        trace("  风险: parse 热共享对象引用；stringify 热可能返回旧缓存字符串。");
        var itemCount:Number = 50;
        var jsonStr:String = this.generateBenchJSON(itemCount, 0);
        var variants:Array = this.generateVariants(itemCount, 128);
        var objectVariants:Array = this.parseVariants(variants);
        var payloadChars:Number = length(jsonStr);
        var repeats:Number = 5;
        var targetAdjustedMs:Number = 120;
        var coldTargetAdjustedMs:Number = 240;
        var coldBatch:Number = 64;
        var self:JSONTest = this;

        var parseMiss:Object = this.measureBenchStats(function(iterations:Number):Number {
            return self.timeFastParseColdLoop(variants, iterations, coldBatch);
        }, function(iterations:Number):Number {
            return self.timeReadVariantLoop(variants, iterations, coldBatch);
        }, coldTargetAdjustedMs, 120, 4, 2048, repeats, payloadChars, coldBatch);

        var parseStrict:Object = this.measureBenchStats(function(iterations:Number):Number {
            return self.timeFastParseStrictColdLoop(variants, iterations, coldBatch);
        }, function(iterations:Number):Number {
            return self.timeReadVariantLoop(variants, iterations, coldBatch);
        }, coldTargetAdjustedMs, 120, 4, 2048, repeats, payloadChars, coldBatch);

        var fpHotParse:FastJSON = new FastJSON();
        fpHotParse.parse(jsonStr);
        var parseHot:Object = this.measureBenchStats(function(iterations:Number):Number {
            return self.timeFastParseHotLoop(fpHotParse, jsonStr, iterations);
        }, function(iterations:Number):Number {
            return self.timeReadStringLoop(jsonStr, iterations);
        }, targetAdjustedMs, 0, 256, 30000, repeats, payloadChars, 1);

        var stringifyMiss:Object = this.measureBenchStats(function(iterations:Number):Number {
            return self.timeFastStringifyColdLoop(objectVariants, iterations, coldBatch);
        }, function(iterations:Number):Number {
            return self.timeReadObjectVariantLoop(objectVariants, iterations, coldBatch);
        }, coldTargetAdjustedMs, 120, 4, 2048, repeats, payloadChars, coldBatch);

        var stringifyStrict:Object = this.measureBenchStats(function(iterations:Number):Number {
            return self.timeFastStringifyStrictColdLoop(objectVariants, iterations, coldBatch);
        }, function(iterations:Number):Number {
            return self.timeReadObjectVariantLoop(objectVariants, iterations, coldBatch);
        }, coldTargetAdjustedMs, 120, 4, 2048, repeats, payloadChars, coldBatch);

        var hotObj:Object = this.liteParser.parse(jsonStr);
        var fpHotStringify:FastJSON = new FastJSON();
        fpHotStringify.stringify(hotObj);
        var stringifyHot:Object = this.measureBenchStats(function(iterations:Number):Number {
            return self.timeFastStringifyHotLoop(fpHotStringify, hotObj, iterations);
        }, function(iterations:Number):Number {
            return self.timeReadObjectLoop(hotObj, iterations);
        }, targetAdjustedMs, 0, 256, 30000, repeats, payloadChars, 1);

        trace("  parse");
        this.reportBenchStats("失配: ", parseMiss);
        this.reportBenchStats("严冷: ", parseStrict);
        this.reportBenchStats("热: ", parseHot);
        this.reportRatio("严冷 / 失配 = ", parseStrict, parseMiss);
        this.reportRatio("失配 / 热 = ", parseMiss, parseHot);
        this.reportRatio("严冷 / 热 = ", parseStrict, parseHot);

        trace("  stringify");
        this.reportBenchStats("失配: ", stringifyMiss);
        this.reportBenchStats("严冷: ", stringifyStrict);
        this.reportBenchStats("热: ", stringifyHot);
        this.reportRatio("严冷 / 失配 = ", stringifyStrict, stringifyMiss);
        this.reportRatio("失配 / 热 = ", stringifyMiss, stringifyHot);
        this.reportRatio("严冷 / 热 = ", stringifyStrict, stringifyHot);
    }
}
