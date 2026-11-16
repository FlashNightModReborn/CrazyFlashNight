import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * TooltipConstantsTest - 常量快照测试
 * 这些值如果变更，意味着数据兼容性问题。
 */
class org.flashNight.gesh.tooltip.test.TooltipConstantsTest {

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
        trace("--- TooltipConstantsTest ---");

        test_colors();
        test_suffixes();
        test_layout();
        test_naming();
        test_propertyDict();
        test_propertyPriorities();
        test_bulletTypeNames();

        trace("--- TooltipConstantsTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_colors():Void {
        assertEq("#FFCC00", TooltipConstants.COL_HL, "COL_HL");
        assertEq("#00FF00", TooltipConstants.COL_HP, "COL_HP");
        assertEq("#00FFFF", TooltipConstants.COL_MP, "COL_MP");
        assertEq("#DD4455", TooltipConstants.COL_CRIT, "COL_CRIT");
        assertEq("#66dd00", TooltipConstants.COL_POISON, "COL_POISON");
        assertEq("#bb00aa", TooltipConstants.COL_VAMP, "COL_VAMP");
        assertEq("#FF3333", TooltipConstants.COL_ROUT, "COL_ROUT");
        assertEq("#0099FF", TooltipConstants.COL_DMG, "COL_DMG");
        assertEq("#FFCC00", TooltipConstants.COL_INFO, "COL_INFO");
        assertEq("#88FF88", TooltipConstants.COL_ENHANCE, "COL_ENHANCE");
        assertEq("#9999FF", TooltipConstants.COL_SILENCE, "COL_SILENCE");
    }

    private static function test_suffixes():Void {
        assertEq("%", TooltipConstants.SUF_PERCENT, "SUF_PERCENT");
        assertEq("HP", TooltipConstants.SUF_HP, "SUF_HP");
        assertEq("MP", TooltipConstants.SUF_MP, "SUF_MP");
        assertEq("%血量", TooltipConstants.SUF_BLOOD, "SUF_BLOOD");
        assertEq("秒", TooltipConstants.SUF_SECOND, "SUF_SECOND");
        assertEq("发/秒", TooltipConstants.SUF_FIRE_RATE, "SUF_FIRE_RATE");
        assertEq("kg", TooltipConstants.SUF_KG, "SUF_KG");
    }

    private static function test_layout():Void {
        assertEq(150, TooltipConstants.MIN_W, "MIN_W");
        assertEq(650, TooltipConstants.MAX_W, "MAX_W");
        assertEq(200, TooltipConstants.BASE_NUM, "BASE_NUM");
        assertEq(210, TooltipConstants.TEXT_Y_EQUIPMENT, "TEXT_Y_EQUIPMENT");
        assertEq(96, TooltipConstants.SPLIT_THRESHOLD, "SPLIT_THRESHOLD");
        assertEq(10, TooltipConstants.TEXT_PAD, "TEXT_PAD");
        assertEq(20, TooltipConstants.BG_HEIGHT_OFFSET, "BG_HEIGHT_OFFSET");
    }

    private static function test_naming():Void {
        assertEq("文本框", TooltipConstants.SUFFIX_TEXTBOX, "SUFFIX_TEXTBOX");
        assertEq("背景", TooltipConstants.SUFFIX_BG, "SUFFIX_BG");
        assertEq("图标-", TooltipConstants.ICON_PREFIX, "ICON_PREFIX");
    }

    private static function test_propertyDict():Void {
        var d:Object = TooltipConstants.PROPERTY_DICT;
        assert(d["force"] != undefined, "PROPERTY_DICT has force");
        assert(d["defence"] != undefined, "PROPERTY_DICT has defence");
        assert(d["hp"] != undefined, "PROPERTY_DICT has hp");
        assert(d["mp"] != undefined, "PROPERTY_DICT has mp");
        assert(d["level"] != undefined, "PROPERTY_DICT has level");
        assert(d["weight"] != undefined, "PROPERTY_DICT has weight");
        assert(d["power"] != undefined, "PROPERTY_DICT has power");
        assert(d["accuracy"] != undefined, "PROPERTY_DICT has accuracy");
        assert(d["evasion"] != undefined, "PROPERTY_DICT has evasion");
        assert(d["slay"] != undefined, "PROPERTY_DICT has slay");
    }

    private static function test_propertyPriorities():Void {
        var p:Object = TooltipConstants.PROPERTY_PRIORITIES;
        // level < weight < power
        assert(p["level"] < p["weight"], "priority: level < weight");
        assert(p["weight"] < p["power"], "priority: weight < power");
        // force < defence < hp < mp
        assert(p["force"] < p["defence"], "priority: force < defence");
        assert(p["defence"] < p["hp"], "priority: defence < hp");
        assert(p["hp"] < p["mp"], "priority: hp < mp");
    }

    private static function test_bulletTypeNames():Void {
        var b:Object = TooltipConstants.BULLET_TYPE_NAMES;
        assertEq("穿刺", b["pierce"], "BULLET_TYPE_NAMES pierce");
        assertEq("近战", b["melee"], "BULLET_TYPE_NAMES melee");
        assertEq("联弹", b["chain"], "BULLET_TYPE_NAMES chain");
        assertEq("手雷", b["grenade"], "BULLET_TYPE_NAMES grenade");
        assertEq("爆炸", b["explosive"], "BULLET_TYPE_NAMES explosive");
        assertEq("普通", b["normal"], "BULLET_TYPE_NAMES normal");
        assertEq("纵向", b["vertical"], "BULLET_TYPE_NAMES vertical");
    }
}
