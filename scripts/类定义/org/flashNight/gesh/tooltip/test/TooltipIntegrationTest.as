import org.flashNight.gesh.tooltip.test.TestDataBootstrap;
import org.flashNight.gesh.tooltip.test.MockTooltipContainer;
import org.flashNight.gesh.tooltip.test.MockItemFactory;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipTextBuilder;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.SkillTooltipComposer;
import org.flashNight.arki.item.ItemUtil;

/**
 * TooltipIntegrationTest - 端到端集成测试
 * 使用 TestDataBootstrap 注入的真实数据 + MockTooltipContainer。
 */
class org.flashNight.gesh.tooltip.test.TooltipIntegrationTest {

    private static var testsRun:Number = 0;
    private static var testsPassed:Number = 0;
    private static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    private static function assertContains(haystack:String, needle:String, msg:String):Void {
        testsRun++;
        if (haystack != null && haystack.indexOf(needle) >= 0) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " '" + needle + "' not found"); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- TooltipIntegrationTest ---");

        TestDataBootstrap.init();

        test_buildBasicDescription();
        test_buildStoryTip();
        test_buildSkillInfo();
        test_buildSkillInfo_null();
        test_buildEquipmentTagInfo();
        test_buildEquipmentTagInfo_empty();
        test_quickBuildCriticalHit();
        test_quickBuildMagicDefence();
        test_getSortedAttrList();
        test_generateItemDescriptionText();
        test_generateIntroPanelContent();
        test_renderItemTooltipSmart_split();
        test_renderItemTooltipSmart_merge();
        test_SkillTooltipComposer_split();
        test_SkillTooltipComposer_merge();

        trace("--- TooltipIntegrationTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    // === TooltipTextBuilder 可测路径 ===

    private static function test_buildBasicDescription():Void {
        var result:Array = TooltipTextBuilder.buildBasicDescription({description: "测试描述"}, null);
        var joined:String = result.join("");
        assertContains(joined, "测试描述", "buildBasicDescription contains description");
    }

    private static function test_buildStoryTip():Void {
        var result1:Array = TooltipTextBuilder.buildStoryTip({use: "情报"});
        var joined1:String = result1.join("");
        assertContains(joined1, TooltipConstants.TIP_INFO_LOCATION, "buildStoryTip info has TIP_INFO_LOCATION");

        var result2:Array = TooltipTextBuilder.buildStoryTip({use: "刀"});
        assert(result2.length == 0, "buildStoryTip melee empty");
    }

    private static function test_buildSkillInfo():Void {
        var result:Array = TooltipTextBuilder.buildSkillInfo({description: "技能说明", cd: 9000, mp: 40});
        var joined:String = result.join("");
        assertContains(joined, "技能说明", "buildSkillInfo has description");
        assertContains(joined, "9", "buildSkillInfo has CD value");
    }

    private static function test_buildSkillInfo_null():Void {
        var result:Array = TooltipTextBuilder.buildSkillInfo(null);
        assert(result.length == 0, "buildSkillInfo null returns empty");
    }

    private static function test_buildEquipmentTagInfo():Void {
        var result:Array = TooltipTextBuilder.buildEquipmentTagInfo({inherentTags: "标签A,标签B"});
        var joined:String = result.join("");
        assertContains(joined, "标签A", "buildEquipmentTagInfo has 标签A");
        assertContains(joined, "标签B", "buildEquipmentTagInfo has 标签B");
    }

    private static function test_buildEquipmentTagInfo_empty():Void {
        var result:Array = TooltipTextBuilder.buildEquipmentTagInfo({});
        assert(result.length == 0, "buildEquipmentTagInfo empty returns empty");
    }

    private static function test_quickBuildCriticalHit():Void {
        var s1:String = TooltipTextBuilder.quickBuildCriticalHit(10);
        assertContains(s1, "10", "quickBuildCriticalHit numeric has value");
        assertContains(s1, TooltipConstants.SUF_PERCENT, "quickBuildCriticalHit has percent");

        var s2:String = TooltipTextBuilder.quickBuildCriticalHit(TooltipConstants.TIP_CRIT_FULL_HP);
        assertContains(s2, TooltipConstants.TIP_CRIT_FULL_HP_DESC, "quickBuildCriticalHit fullHP has desc");
    }

    private static function test_quickBuildMagicDefence():Void {
        var s:String = TooltipTextBuilder.quickBuildMagicDefence({热: 10}, null);
        assertContains(s, "热", "quickBuildMagicDefence has 热");
        assertContains(s, "10", "quickBuildMagicDefence has 10");
    }

    private static function test_getSortedAttrList():Void {
        var sorted:Array = TooltipTextBuilder.getSortedAttrList({force: 1, hp: 5, level: 3});
        // level priority=0, force=21, hp=102 → level should be first
        assert(sorted.length == 3, "getSortedAttrList has 3 items");
        var levelIdx:Number = -1;
        var forceIdx:Number = -1;
        for (var i:Number = 0; i < sorted.length; i++) {
            if (sorted[i] == "level") levelIdx = i;
            if (sorted[i] == "force") forceIdx = i;
        }
        assert(levelIdx < forceIdx, "getSortedAttrList level before force");
    }

    // === TooltipComposer 核心入口 ===

    private static function test_generateItemDescriptionText():Void {
        // 有 description 的 item
        var item:Object = ItemUtil.getItemData("测试军刀");
        var bi = MockItemFactory.mockBaseItem();
        var text:String = TooltipComposer.generateItemDescriptionText(item, bi);
        assert(text != null && text.length > 0, "generateItemDescriptionText non-empty");
        assertContains(text, "测试用近战武器", "generateItemDescriptionText has description");

        // 情报类
        var infoItem:Object = ItemUtil.getItemData("测试情报");
        var infoText:String = TooltipComposer.generateItemDescriptionText(infoItem, null);
        assertContains(infoText, TooltipConstants.TIP_INFO_LOCATION, "generateItemDescriptionText info has location tip");
    }

    private static function test_generateIntroPanelContent():Void {
        var item:Object = ItemUtil.getItemData("测试军刀");
        var bi = MockItemFactory.mockBaseItem();
        var text:String = TooltipComposer.generateIntroPanelContent(bi, item, bi.value);
        assert(text != null && text.length > 0, "generateIntroPanelContent non-empty");
        assertContains(text, "测试军刀", "generateIntroPanelContent has displayname");
        assertContains(text, "武器", "generateIntroPanelContent has type");
        assertContains(text, "刀", "generateIntroPanelContent has use");
        assertContains(text, "$", "generateIntroPanelContent has price prefix");
    }

    // === renderItemTooltipSmart ===

    private static function test_renderItemTooltipSmart_split():Void {
        MockTooltipContainer.install();
        var longDesc:String = "";
        for (var i:Number = 0; i < 100; i++) longDesc += "测试描述内容";
        var shortIntro:String = "简短简介";

        TooltipComposer.renderItemTooltipSmart("测试军刀", {level: 1}, longDesc, shortIntro, null, null);

        // 分栏模式：主框体可见
        var mainBg:MovieClip = TooltipBridge.getMainBackground();
        assert(mainBg._visible == true, "renderSmart split: mainBg visible");
        MockTooltipContainer.teardown();
    }

    private static function test_renderItemTooltipSmart_merge():Void {
        MockTooltipContainer.install();
        var shortDesc:String = "短";
        var shortIntro:String = "简";

        TooltipComposer.renderItemTooltipSmart("测试军刀", {level: 1}, shortDesc, shortIntro, null, null);

        // 合并模式：主框体不可见
        var mainBg:MovieClip = TooltipBridge.getMainBackground();
        assert(mainBg._visible == false, "renderSmart merge: mainBg hidden");
        MockTooltipContainer.teardown();
    }

    // === SkillTooltipComposer ===

    private static function test_SkillTooltipComposer_split():Void {
        MockTooltipContainer.install();
        var longDesc:String = "";
        for (var i:Number = 0; i < 100; i++) longDesc += "技能描述内容";

        SkillTooltipComposer.renderSkillTooltipSmart("测试技能", "技能简介", longDesc);

        // 分栏模式：主框体可见
        var mainBg:MovieClip = TooltipBridge.getMainBackground();
        assert(mainBg._visible == true, "SkillComposer split: mainBg visible");
        MockTooltipContainer.teardown();
    }

    private static function test_SkillTooltipComposer_merge():Void {
        MockTooltipContainer.install();
        SkillTooltipComposer.renderSkillTooltipSmart("测试技能", "简介", "短");

        // 合并模式：主框体不可见
        var mainBg:MovieClip = TooltipBridge.getMainBackground();
        assert(mainBg._visible == false, "SkillComposer merge: mainBg hidden");
        MockTooltipContainer.teardown();
    }
}
