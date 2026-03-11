import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * TooltipFormatterTest - 纯函数格式化方法测试
 * 严格从 TooltipFormatter.as 代码反推断言。
 */
class org.flashNight.gesh.tooltip.test.TooltipFormatterTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    private static function assertEq(expected, actual, msg:String):Void {
        testsRun++;
        if (expected === actual) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " expected=" + expected + " actual=" + actual); }
    }

    private static function assertContains(haystack:String, needle:String, msg:String):Void {
        testsRun++;
        if (haystack.indexOf(needle) >= 0) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " '" + needle + "' not found in '" + haystack + "'"); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- TooltipFormatterTest ---");

        test_bold();
        test_color();
        test_br();
        test_kv();
        test_numLine();
        test_upgradeLine();
        test_statLine();
        test_enhanceLine();
        test_normalizeDescription();
        test_colorLine();

        trace("--- TooltipFormatterTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_bold():Void {
        assertEq("<B>x</B>", TooltipFormatter.bold("x"), "bold");
    }

    private static function test_color():Void {
        assertEq("<FONT COLOR='#FF0000'>x</FONT>", TooltipFormatter.color("x", "#FF0000"), "color");
    }

    private static function test_br():Void {
        assertEq("<BR>", TooltipFormatter.br(), "br");
    }

    private static function test_kv():Void {
        assertEq("标签：100%", TooltipFormatter.kv("标签", 100, "%"), "kv with suffix");
        assertEq("标签：值", TooltipFormatter.kv("标签", "值", undefined), "kv default suffix");
    }

    private static function test_numLine():Void {
        // 正常数值
        var buf:Array = [];
        TooltipFormatter.numLine(buf, "标签", 100, "%");
        assertEq(5, buf.length, "numLine val=100 pushes 5 elements");
        assertEq("标签", buf[0], "numLine[0] is label");
        assertEq("：", buf[1], "numLine[1] is colon");
        assertEq(100, buf[2], "numLine[2] is 100");
        assertEq("%", buf[3], "numLine[3] is suffix");
        assertEq("<BR>", buf[4], "numLine[4] is BR");

        // val=0 跳过
        buf = [];
        TooltipFormatter.numLine(buf, "标签", 0, "%");
        assertEq(0, buf.length, "numLine val=0 skips");

        // val=undefined 跳过
        buf = [];
        TooltipFormatter.numLine(buf, "标签", undefined, "%");
        assertEq(0, buf.length, "numLine val=undefined skips");

        // val=null 跳过
        buf = [];
        TooltipFormatter.numLine(buf, "标签", null, "%");
        assertEq(0, buf.length, "numLine val=null skips");

        // val="" 跳过
        buf = [];
        TooltipFormatter.numLine(buf, "标签", "", "%");
        assertEq(0, buf.length, "numLine val='' skips");

        // val="0" 跳过
        buf = [];
        TooltipFormatter.numLine(buf, "标签", "0", "%");
        assertEq(0, buf.length, "numLine val='0' skips");

        // val="abc" 保留原始字符串
        buf = [];
        TooltipFormatter.numLine(buf, "标签", "abc", null);
        assert(buf.length > 0, "numLine val='abc' produces output");
        assertEq("abc", buf[2], "numLine val='abc' keeps original string");
    }

    private static function test_upgradeLine():Void {
        // 无 equipData
        var buf:Array = [];
        TooltipFormatter.upgradeLine(buf, {power: 100}, null, "power", "威力", null);
        var joined:String = buf.join("");
        assertContains(joined, "100", "upgradeLine base-only contains value");
        assertContains(joined, "威力", "upgradeLine base-only contains label");

        // equipData == base，无高亮
        buf = [];
        TooltipFormatter.upgradeLine(buf, {power: 100}, {power: 100}, "power", "威力", null);
        joined = buf.join("");
        assertContains(joined, "100", "upgradeLine equal contains value");
        assert(joined.indexOf(TooltipConstants.COL_HL) < 0, "upgradeLine equal no highlight");

        // equipData > base，显示高亮 + 增幅
        buf = [];
        TooltipFormatter.upgradeLine(buf, {power: 100}, {power: 150}, "power", "威力", null);
        joined = buf.join("");
        assertContains(joined, TooltipConstants.COL_HL, "upgradeLine enhanced has COL_HL");
        assertContains(joined, "150", "upgradeLine enhanced has final value");
        assertContains(joined, "100", "upgradeLine enhanced has base value");
        assertContains(joined, " + ", "upgradeLine enhanced has plus sign");
        assertContains(joined, "50", "upgradeLine enhanced has delta");

        // equipData < base，显示减少
        buf = [];
        TooltipFormatter.upgradeLine(buf, {power: 100}, {power: 80}, "power", "威力", null);
        joined = buf.join("");
        assertContains(joined, " - ", "upgradeLine reduced has minus sign");
        assertContains(joined, "20", "upgradeLine reduced has delta 20");

        // 非数字覆盖
        buf = [];
        TooltipFormatter.upgradeLine(buf, {power: 100}, {power: "物理"}, "power", "威力", null);
        joined = buf.join("");
        assertContains(joined, TooltipConstants.TXT_OVERRIDE, "upgradeLine override has TXT_OVERRIDE");

        // 两端都无值，跳过
        buf = [];
        TooltipFormatter.upgradeLine(buf, {}, {}, "power", "威力", null);
        assertEq(0, buf.length, "upgradeLine both empty skips");

        // label=null → 从 PROPERTY_DICT 自动查找
        buf = [];
        TooltipFormatter.upgradeLine(buf, {force: 10}, null, "force", null, null);
        joined = buf.join("");
        assertContains(joined, TooltipConstants.PROPERTY_DICT["force"], "upgradeLine auto label");
    }

    private static function test_statLine():Void {
        // type="add", val=5 → " + 5" 无 %
        var buf:Array = [];
        TooltipFormatter.statLine(buf, "add", "force", 5, "力量");
        var joined:String = buf.join("");
        assertContains(joined, " + ", "statLine add positive sign");
        assertContains(joined, "5", "statLine add value");
        assert(joined.indexOf("%") < 0, "statLine add NO percent");

        // type="add", val=-3 → " - 3"
        buf = [];
        TooltipFormatter.statLine(buf, "add", "force", -3, "力量");
        joined = buf.join("");
        assertContains(joined, " - ", "statLine add negative sign");
        assertContains(joined, "3", "statLine add negative value");

        // type="add", val=0 → 跳过
        buf = [];
        TooltipFormatter.statLine(buf, "add", "force", 0, "力量");
        assertEq(0, buf.length, "statLine add val=0 skips");

        // type="multiply", val=0.35 → " + 35%"
        buf = [];
        TooltipFormatter.statLine(buf, "multiply", "force", 0.35, "力量");
        joined = buf.join("");
        assertContains(joined, "35", "statLine multiply value");
        assertContains(joined, "%", "statLine multiply has percent");

        // type="multiply", val=-0.2 → " - 20%"
        buf = [];
        TooltipFormatter.statLine(buf, "multiply", "force", -0.2, "力量");
        joined = buf.join("");
        assertContains(joined, " - ", "statLine multiply negative sign");
        assertContains(joined, "20", "statLine multiply negative value");

        // type="override" → " -> "
        buf = [];
        TooltipFormatter.statLine(buf, "override", "force", "魔法", "力量");
        joined = buf.join("");
        assertContains(joined, " -> ", "statLine override arrow");
        assertContains(joined, "魔法", "statLine override value");

        // type="merge" → TAG_MERGE + COL_INFO + " -> "
        buf = [];
        TooltipFormatter.statLine(buf, "merge", "force", "热", "力量");
        joined = buf.join("");
        assertContains(joined, TooltipConstants.TAG_MERGE, "statLine merge has TAG_MERGE");
        assertContains(joined, TooltipConstants.COL_INFO, "statLine merge has COL_INFO");
        assertContains(joined, " -> ", "statLine merge has arrow");

        // val=undefined → 跳过
        buf = [];
        TooltipFormatter.statLine(buf, "add", "force", undefined, "力量");
        assertEq(0, buf.length, "statLine undefined skips");
    }

    private static function test_enhanceLine():Void {
        // type="add", val=0.5
        var buf:Array = [];
        TooltipFormatter.enhanceLine(buf, "add", {force: 10}, "force", 0.5, null);
        var joined:String = buf.join("");
        assertContains(joined, " + ", "enhanceLine add positive");
        assertContains(joined, "0.5", "enhanceLine add value");

        // type="multiply", data has base, val=0.3 → +30%
        buf = [];
        TooltipFormatter.enhanceLine(buf, "multiply", {force: 10}, "force", 0.3, null);
        joined = buf.join("");
        assertContains(joined, "30", "enhanceLine multiply value");
        assertContains(joined, "%", "enhanceLine multiply percent");

        // type="multiply", no base → skips
        buf = [];
        TooltipFormatter.enhanceLine(buf, "multiply", {}, "force", 0.3, null);
        assertEq(0, buf.length, "enhanceLine multiply no base skips");

        // type="override"
        buf = [];
        TooltipFormatter.enhanceLine(buf, "override", {force: 10}, "force", "物理", null);
        joined = buf.join("");
        assertContains(joined, " -> ", "enhanceLine override arrow");
        assertContains(joined, "物理", "enhanceLine override value");

        // val=0 → skips
        buf = [];
        TooltipFormatter.enhanceLine(buf, "add", {force: 10}, "force", 0, null);
        assertEq(0, buf.length, "enhanceLine val=0 skips");
    }

    private static function test_normalizeDescription():Void {
        assertEq("abc<BR>def", TooltipFormatter.normalizeDescription("abc\r\ndef"), "normalizeDescription CRLF");
        assertEq("abc<BR>def", TooltipFormatter.normalizeDescription("  abc\n  def"), "normalizeDescription trim indent");
        assertEq("abc<BR>def", TooltipFormatter.normalizeDescription("abc\n<BR>def"), "normalizeDescription no double BR");
        assertEq("abc", TooltipFormatter.normalizeDescription("abc"), "normalizeDescription no newline");
    }

    private static function test_colorLine():Void {
        var buf:Array = [];
        TooltipFormatter.colorLine(buf, "#FF0000", "文本");
        var joined:String = buf.join("");
        assertContains(joined, "#FF0000", "colorLine has color");
        assertContains(joined, "文本", "colorLine has text");

        // empty text → skip
        buf = [];
        TooltipFormatter.colorLine(buf, "#FF0000", "");
        assertEq(0, buf.length, "colorLine empty skips");

        // undefined text → skip
        buf = [];
        TooltipFormatter.colorLine(buf, "#FF0000", undefined);
        assertEq(0, buf.length, "colorLine undefined skips");
    }
}
