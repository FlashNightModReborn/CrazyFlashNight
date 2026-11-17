import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.test.TestDataBootstrap;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.ItemUtil;

/**
 * TooltipRegressionTest - 注释系统关键回归点
 * 重点覆盖：
 * 1. 评分结果对象不能被后续调用篡改
 * 2. 基于评分的宽度估算应与 HTML 真实换行规则一致
 */
class org.flashNight.gesh.tooltip.test.TooltipRegressionTest {

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

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- TooltipRegressionTest ---");

        test_htmlScoresBoth_returnsSnapshot();
        test_htmlScoresBoth_writesIntoProvidedObject();
        test_shouldSplitSmartWithScores_returnsSnapshot();
        test_shouldSplitSmartWithScores_writesIntoProvidedObject();
        test_estimateMainWidthFromScores_handlesLowercaseBr();
        test_estimateMainWidthFromScores_handlesNativeNewline();
        test_estimateMainWidthFromMetrics_matchesFromScores();
        test_testDataBootstrap_sandboxRestoresPreviousState();

        trace("--- TooltipRegressionTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_htmlScoresBoth_returnsSnapshot():Void {
        var first:Object = StringUtils.htmlScoresBoth("ABC", null);
        var firstTotal:Number = first.total;
        var firstMaxLine:Number = first.maxLine;

        var second:Object = StringUtils.htmlScoresBoth("中<BR>文", null);

        assertEq(3, firstTotal, "htmlScoresBoth snapshot total before second call");
        assertEq(3, firstMaxLine, "htmlScoresBoth snapshot maxLine before second call");
        assertEq(3, first.total, "htmlScoresBoth snapshot total after second call");
        assertEq(3, first.maxLine, "htmlScoresBoth snapshot maxLine after second call");
        assert(first !== second, "htmlScoresBoth returns independent result objects");
    }

    private static function test_htmlScoresBoth_writesIntoProvidedObject():Void {
        var out:Object = {seed: true};
        var result:Object = StringUtils.htmlScoresBoth("A<br>B\nC", null, out);

        assert(result === out, "htmlScoresBoth returns provided output object");
        assertEq(3, result.total, "htmlScoresBoth provided object total");
        assertEq(1, result.maxLine, "htmlScoresBoth provided object maxLine");
        assertEq(3, result.lineCount, "htmlScoresBoth provided object lineCount");
    }

    private static function test_shouldSplitSmartWithScores_returnsSnapshot():Void {
        var first:Object = TooltipLayout.shouldSplitSmartWithScores("短", "简", null);
        var firstNeedSplit:Boolean = first.needSplit;
        var firstDescTotal:Number = first.descTotal;
        var firstDescMaxLine:Number = first.descMaxLine;

        var longDesc:String = "";
        for (var i:Number = 0; i < 80; i++) longDesc += "测试内容";
        var second:Object = TooltipLayout.shouldSplitSmartWithScores(longDesc, "简介", null);

        assertEq(false, firstNeedSplit, "shouldSplitSmartWithScores snapshot needSplit before second call");
        assertEq(2, firstDescTotal, "shouldSplitSmartWithScores snapshot descTotal before second call");
        assertEq(2, firstDescMaxLine, "shouldSplitSmartWithScores snapshot descMaxLine before second call");
        assertEq(false, first.needSplit, "shouldSplitSmartWithScores snapshot needSplit after second call");
        assertEq(2, first.descTotal, "shouldSplitSmartWithScores snapshot descTotal after second call");
        assertEq(2, first.descMaxLine, "shouldSplitSmartWithScores snapshot descMaxLine after second call");
        assert(first !== second, "shouldSplitSmartWithScores returns independent result objects");
    }

    private static function test_shouldSplitSmartWithScores_writesIntoProvidedObject():Void {
        var out:Object = {};
        var result:Object = TooltipLayout.shouldSplitSmartWithScores("短\n长长", "简", {threshold: 999}, out);

        assert(result === out, "shouldSplitSmartWithScores returns provided output object");
        assertEq(false, result.needSplit, "shouldSplitSmartWithScores provided object needSplit");
        assertEq(2, result.descLineCount, "shouldSplitSmartWithScores provided object descLineCount");
        assertEq(2, result.introTotal, "shouldSplitSmartWithScores provided object introTotal");
    }

    private static function test_estimateMainWidthFromScores_handlesLowercaseBr():Void {
        var upper:String = "短<BR>短<BR>这是很长很长很长的一行描述文本";
        var lower:String = "短<br>短<br>这是很长很长很长的一行描述文本";

        var upperScores:Object = StringUtils.htmlScoresBoth(upper, null);
        var lowerScores:Object = StringUtils.htmlScoresBoth(lower, null);
        var upperWidth:Number = TooltipLayout.estimateMainWidthFromScores(upperScores.total, upperScores.maxLine, upper, undefined, undefined);
        var lowerWidth:Number = TooltipLayout.estimateMainWidthFromScores(lowerScores.total, lowerScores.maxLine, lower, undefined, undefined);

        assertEq(upperWidth, lowerWidth, "estimateMainWidthFromScores lower-case <br> matches <BR>");
    }

    private static function test_estimateMainWidthFromScores_handlesNativeNewline():Void {
        var html:String = "短<BR>短<BR>这是很长很长很长的一行描述文本";
        var plain:String = "短\n短\n这是很长很长很长的一行描述文本";

        var htmlScores:Object = StringUtils.htmlScoresBoth(html, null);
        var plainScores:Object = StringUtils.htmlScoresBoth(plain, null);
        var htmlWidth:Number = TooltipLayout.estimateMainWidthFromScores(htmlScores.total, htmlScores.maxLine, html, undefined, undefined);
        var plainWidth:Number = TooltipLayout.estimateMainWidthFromScores(plainScores.total, plainScores.maxLine, plain, undefined, undefined);

        assertEq(htmlWidth, plainWidth, "estimateMainWidthFromScores native newline matches <BR>");
    }

    private static function test_estimateMainWidthFromMetrics_matchesFromScores():Void {
        var html:String = "短<BR>短<BR>这是很长很长很长的一行描述文本";
        var scores:Object = StringUtils.htmlScoresBoth(html, null);
        var fromScores:Number = TooltipLayout.estimateMainWidthFromScores(scores.total, scores.maxLine, html, undefined, undefined);
        var fromMetrics:Number = TooltipLayout.estimateMainWidthFromMetrics(scores.total, scores.maxLine, scores.lineCount, undefined, undefined);

        assertEq(fromScores, fromMetrics, "estimateMainWidthFromMetrics matches fromScores");
    }

    private static function test_testDataBootstrap_sandboxRestoresPreviousState():Void {
        var originalTierNameToKey:Object = {};
        originalTierNameToKey["测试品阶"] = "data_test";
        var originalTierToMat:Object = {};
        originalTierToMat["data_test"] = "原始材料";
        var originalTierData:Object = {};
        originalTierData["测试品阶"] = {level: 3, defence: 7};
        var originalItemList:Array = [
            {name: "原始药水", displayname: "原始药水", type: "消耗品", use: "药剂", price: 1, data: {heal: {value: 1, target: "hp"}}}
        ];
        var pollutedItemList:Array = [
            {name: "污染样本", displayname: "污染样本", type: "消耗品", use: "药剂", price: 2, data: {heal: {value: 2, target: "hp"}}}
        ];

        TestDataBootstrap.beginSandbox();

        EquipmentUtil.loadEquipmentConfig({
            levelStatList: [1, 1.5, 2],
            decimalPropDict: {testProp: 1},
            tierNameToKeyDict: originalTierNameToKey,
            tierToMaterialDict: originalTierToMat,
            defaultTierDataDict: originalTierData,
            tierDataList: ["data_test"]
        });
        ItemUtil.loadItemData(originalItemList);

        TestDataBootstrap.beginSandbox();
        assert(ItemUtil.isItem("测试军刀"), "sandbox injects fixture items");
        assertEq("data_2", EquipmentUtil.tierNameToKeyDict["二阶"], "sandbox injects fixture config");
        ItemUtil.loadItemData(pollutedItemList);
        TestDataBootstrap.endSandbox();

        assert(ItemUtil.isItem("原始药水"), "sandbox restores original item set");
        assert(!ItemUtil.isItem("测试军刀"), "sandbox removes fixture item after restore");
        assert(!ItemUtil.isItem("污染样本"), "sandbox discards sandbox mutations");
        assertEq("data_test", EquipmentUtil.tierNameToKeyDict["测试品阶"], "sandbox restores original config");

        TestDataBootstrap.beginSandbox();
        assert(ItemUtil.isItem("测试军刀"), "sandbox starts from clean fixture on next run");
        assert(!ItemUtil.isItem("污染样本"), "sandbox does not retain prior mutations");
        TestDataBootstrap.endSandbox();

        assert(ItemUtil.isItem("原始药水"), "sandbox second restore keeps original item set");
        TestDataBootstrap.endSandbox();
    }
}
