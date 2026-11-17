import org.flashNight.gesh.tooltip.ItemUseTypes;

/**
 * ItemUseTypesTest - 物品使用类型常量 + 工具函数测试
 */
class org.flashNight.gesh.tooltip.test.ItemUseTypesTest {

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
        trace("--- ItemUseTypesTest ---");

        test_useConstants();
        test_typeConstants();
        test_isGun();
        test_isWeapon();

        trace("--- ItemUseTypesTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    private static function test_useConstants():Void {
        assertEq("刀", ItemUseTypes.MELEE, "MELEE");
        assertEq("手枪", ItemUseTypes.PISTOL, "PISTOL");
        assertEq("长枪", ItemUseTypes.RIFLE, "RIFLE");
        assertEq("手雷", ItemUseTypes.GRENADE, "GRENADE");
        assertEq("防具", ItemUseTypes.ARMOR, "ARMOR");
        assertEq("药剂", ItemUseTypes.POTION, "POTION");
        assertEq("技能", ItemUseTypes.SKILL, "SKILL");
        assertEq("材料", ItemUseTypes.MATERIAL, "MATERIAL");
        assertEq("情报", ItemUseTypes.INFORMATION, "INFORMATION");
    }

    private static function test_typeConstants():Void {
        assertEq("武器", ItemUseTypes.TYPE_WEAPON, "TYPE_WEAPON");
        assertEq("防具", ItemUseTypes.TYPE_ARMOR, "TYPE_ARMOR");
        assertEq("技能", ItemUseTypes.TYPE_SKILL, "TYPE_SKILL");
        assertEq("消耗品", ItemUseTypes.TYPE_CONSUMABLE, "TYPE_CONSUMABLE");
    }

    private static function test_isGun():Void {
        assert(ItemUseTypes.isGun("手枪") == true, "isGun 手枪");
        assert(ItemUseTypes.isGun("长枪") == true, "isGun 长枪");
        assert(ItemUseTypes.isGun("刀") == false, "isGun 刀");
        assert(ItemUseTypes.isGun("手雷") == false, "isGun 手雷");
        assert(ItemUseTypes.isGun("防具") == false, "isGun 防具");
    }

    private static function test_isWeapon():Void {
        assert(ItemUseTypes.isWeapon("刀") == true, "isWeapon 刀");
        assert(ItemUseTypes.isWeapon("手枪") == true, "isWeapon 手枪");
        assert(ItemUseTypes.isWeapon("长枪") == true, "isWeapon 长枪");
        assert(ItemUseTypes.isWeapon("手雷") == true, "isWeapon 手雷");
        assert(ItemUseTypes.isWeapon("防具") == false, "isWeapon 防具");
        assert(ItemUseTypes.isWeapon("药剂") == false, "isWeapon 药剂");
    }
}
