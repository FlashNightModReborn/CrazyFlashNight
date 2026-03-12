import org.flashNight.gesh.tooltip.test.TestDataBootstrap;
import org.flashNight.gesh.tooltip.test.MockItemFactory;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.builder.EquipmentStatsComposer;
import org.flashNight.gesh.tooltip.builder.CommonStatsBuilder;
import org.flashNight.gesh.tooltip.builder.GunStatsBuilder;
import org.flashNight.gesh.tooltip.builder.MeleeStatsBuilder;
import org.flashNight.gesh.tooltip.builder.GrenadeStatsBuilder;
import org.flashNight.gesh.tooltip.builder.CriticalBlockBuilder;
import org.flashNight.gesh.tooltip.builder.DamageTypeBuilder;
import org.flashNight.gesh.tooltip.builder.ResistanceBlockBuilder;
import org.flashNight.gesh.tooltip.builder.SlayEffectBuilder;
import org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipComposer;

/**
 * BuilderContractTest - Builder 结构性契约测试
 * 不测具体文案，只测结构性不变量。
 */
class org.flashNight.gesh.tooltip.test.BuilderContractTest {

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
        if (haystack.indexOf(needle) >= 0) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " '" + needle + "' not found"); }
    }

    private static function assertNotContains(haystack:String, needle:String, msg:String):Void {
        testsRun++;
        if (haystack.indexOf(needle) < 0) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg + " '" + needle + "' was found but should not be"); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- BuilderContractTest ---");

        TestDataBootstrap.init();

        test_EquipmentStatsComposer_melee();
        test_EquipmentStatsComposer_gun();
        test_EquipmentStatsComposer_grenade();
        test_EquipmentStatsComposer_armor();
        test_CommonStatsBuilder_melee();
        test_CommonStatsBuilder_gun();
        test_GunStatsBuilder();
        test_GunStatsBuilder_fireMode();
        test_GunStatsBuilder_reloadType();
        test_MeleeStatsBuilder();
        test_GrenadeStatsBuilder();
        test_GrenadeStatsBuilder_zeroPower();
        test_CriticalBlockBuilder();
        test_CriticalBlockBuilder_none();
        test_DamageTypeBuilder();
        test_DamageTypeBuilder_none();
        test_ResistanceBlockBuilder();
        test_ResistanceBlockBuilder_none();
        test_SlayEffectBuilder();
        test_SilenceEffectBuilder();
        test_DrugTooltipComposer_null();

        trace("--- BuilderContractTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    // === EquipmentStatsComposer ===

    private static function test_EquipmentStatsComposer_melee():Void {
        var f:Object = MockItemFactory.meleeWeapon();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = EquipmentStatsComposer.compose(bi, f.item, f.data, f.equipData);
        var joined:String = result.join("");
        assertContains(joined, TooltipConstants.PROPERTY_DICT["force"], "ESC melee has force label");
        assertContains(joined, "9", "ESC melee has level 9");
    }

    private static function test_EquipmentStatsComposer_gun():Void {
        var f:Object = MockItemFactory.gun();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = EquipmentStatsComposer.compose(bi, f.item, f.data, f.equipData);
        var joined:String = result.join("");
        assertContains(joined, "手枪通用弹药", "ESC gun has clipname displayname");
    }

    private static function test_EquipmentStatsComposer_grenade():Void {
        var f:Object = MockItemFactory.grenade();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = EquipmentStatsComposer.compose(bi, f.item, f.data, f.equipData);
        var joined:String = result.join("");
        assertContains(joined, "200", "ESC grenade has power 200");
    }

    private static function test_EquipmentStatsComposer_armor():Void {
        var f:Object = MockItemFactory.armor();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = EquipmentStatsComposer.compose(bi, f.item, f.data, f.equipData);
        var joined:String = result.join("");
        assertContains(joined, "50", "ESC armor has defence 50");
    }

    // === CommonStatsBuilder ===

    private static function test_CommonStatsBuilder_melee():Void {
        var f:Object = MockItemFactory.meleeWeapon();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        CommonStatsBuilder.build(result, bi, f.item, f.data, f.equipData);
        var joined:String = result.join("");
        assertContains(joined, TooltipConstants.PROPERTY_DICT["force"], "Common melee has force");
        assertContains(joined, "10", "Common melee has force value 10");
        assertContains(joined, TooltipConstants.LBL_ACTION, "Common melee has ACTION label");
    }

    private static function test_CommonStatsBuilder_gun():Void {
        var f:Object = MockItemFactory.gun();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        CommonStatsBuilder.build(result, bi, f.item, f.data, f.equipData);
        var joined:String = result.join("");
        assertNotContains(joined, TooltipConstants.LBL_ACTION, "Common gun has NO ACTION label");
    }

    // === GunStatsBuilder ===

    private static function test_GunStatsBuilder():Void {
        var f:Object = MockItemFactory.gun();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        GunStatsBuilder.build(result, bi, f.item, f.data, f.equipData);
        assert(result.length > 0, "GunStats produces output");
        var joined:String = result.join("");
        assertContains(joined, "手枪通用弹药", "GunStats has clipname");
    }

    private static function test_GunStatsBuilder_fireMode():Void {
        var bi = MockItemFactory.mockBaseItem();

        // singleshoot=false → 全自动（每次使用新 fixture 避免状态泄漏）
        var fAuto:Object = MockItemFactory.gun();
        var result:Array = [];
        GunStatsBuilder.build(result, bi, fAuto.item, fAuto.data, null);
        var joined:String = result.join("");
        assertContains(joined, TooltipConstants.TIP_FIRE_MODE_AUTO, "GunStats auto mode");

        // singleshoot=true → 半自动
        var fSemi:Object = MockItemFactory.gun();
        fSemi.data.singleshoot = true;
        result = [];
        GunStatsBuilder.build(result, bi, fSemi.item, fSemi.data, null);
        joined = result.join("");
        assertContains(joined, TooltipConstants.TIP_FIRE_MODE_SEMI, "GunStats semi mode");
    }

    private static function test_GunStatsBuilder_reloadType():Void {
        var bi = MockItemFactory.mockBaseItem();

        // reloadType="clip" → 整匣换弹
        var fClip:Object = MockItemFactory.gun();
        var result:Array = [];
        GunStatsBuilder.build(result, bi, fClip.item, fClip.data, null);
        var joined:String = result.join("");
        assertContains(joined, TooltipConstants.TIP_RELOAD_TYPE_MAG, "GunStats mag reload");

        // reloadType="tube" → 逐发装填
        var fTube:Object = MockItemFactory.gun();
        fTube.data.reloadType = "tube";
        result = [];
        GunStatsBuilder.build(result, bi, fTube.item, fTube.data, null);
        joined = result.join("");
        assertContains(joined, TooltipConstants.TIP_RELOAD_TYPE_TUBE, "GunStats tube reload");
    }

    // === MeleeStatsBuilder ===

    private static function test_MeleeStatsBuilder():Void {
        var f:Object = MockItemFactory.meleeWeapon();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        MeleeStatsBuilder.build(result, bi, f.item, f.data, f.equipData);
        var joined:String = result.join("");
        // data.power=100 → 锋利度相关内容
        assertContains(joined, "100", "Melee has power 100");
        // data.bladeCount=3 → 判定数
        assertContains(joined, "3", "Melee has bladeCount 3");
    }

    // === GrenadeStatsBuilder ===

    private static function test_GrenadeStatsBuilder():Void {
        var f:Object = MockItemFactory.grenade();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        GrenadeStatsBuilder.build(result, bi, f.item, f.data, f.equipData);
        var joined:String = result.join("");
        assertContains(joined, "200", "Grenade has power 200");
    }

    private static function test_GrenadeStatsBuilder_zeroPower():Void {
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        GrenadeStatsBuilder.build(result, bi, {use: "手雷"}, {power: 0}, null);
        assert(result.length == 0, "Grenade zero power produces nothing");
    }

    // === CriticalBlockBuilder ===

    private static function test_CriticalBlockBuilder():Void {
        var f:Object = MockItemFactory.weaponWithCrit();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        CriticalBlockBuilder.build(result, bi, f.item, f.data, null);
        var joined:String = result.join("");
        assertContains(joined, TooltipConstants.SUF_PERCENT, "CritBlock has percent");
        assertContains(joined, "10", "CritBlock has value 10");
    }

    private static function test_CriticalBlockBuilder_none():Void {
        var f:Object = MockItemFactory.meleeWeapon();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        CriticalBlockBuilder.build(result, bi, f.item, f.data, null);
        assert(result.length == 0, "CritBlock no crit produces nothing");
    }

    // === DamageTypeBuilder ===

    private static function test_DamageTypeBuilder():Void {
        var f:Object = MockItemFactory.weaponWithMagic();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        DamageTypeBuilder.build(result, bi, f.item, f.data, null);
        var joined:String = result.join("");
        assertContains(joined, "热", "DamageType has magictype 热");
    }

    private static function test_DamageTypeBuilder_none():Void {
        var f:Object = MockItemFactory.meleeWeapon();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        DamageTypeBuilder.build(result, bi, f.item, f.data, null);
        assert(result.length == 0, "DamageType no damagetype produces nothing");
    }

    // === ResistanceBlockBuilder ===

    private static function test_ResistanceBlockBuilder():Void {
        var f:Object = MockItemFactory.weaponWithResistance();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        ResistanceBlockBuilder.build(result, bi, f.item, f.data, null);
        var joined:String = result.join("");
        assertContains(joined, "10", "Resistance has value 10");
    }

    private static function test_ResistanceBlockBuilder_none():Void {
        var f:Object = MockItemFactory.meleeWeapon();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        ResistanceBlockBuilder.build(result, bi, f.item, f.data, null);
        assert(result.length == 0, "Resistance no magicdefence produces nothing");
    }

    // === SlayEffectBuilder ===

    private static function test_SlayEffectBuilder():Void {
        var result:Array = [];
        SlayEffectBuilder.buildFlat(result, 8);
        var joined:String = result.join("");
        assertContains(joined, TooltipConstants.SUF_BLOOD, "Slay flat has SUF_BLOOD");
        assertContains(joined, "8", "Slay flat has value 8");

        // buildFlat val=0 → skip
        result = [];
        SlayEffectBuilder.buildFlat(result, 0);
        assert(result.length == 0, "Slay flat val=0 skips");

        // buildOverride
        result = [];
        SlayEffectBuilder.buildOverride(result, 8);
        joined = result.join("");
        assertContains(joined, TooltipConstants.SUF_BLOOD, "Slay override has SUF_BLOOD");
        assertContains(joined, " -> ", "Slay override has arrow");

        // getShortDescription
        var desc:String = SlayEffectBuilder.getShortDescription(8);
        assert(desc.length > 0, "Slay shortDesc non-empty");
        assertContains(desc, "8", "Slay shortDesc has value");

        var emptyDesc:String = SlayEffectBuilder.getShortDescription(0);
        assert(emptyDesc == "", "Slay shortDesc val=0 empty");
    }

    // === SilenceEffectBuilder ===

    private static function test_SilenceEffectBuilder():Void {
        // 百分比消音
        var f:Object = MockItemFactory.weaponWithSilencePercent();
        var bi = MockItemFactory.mockBaseItem();
        var result:Array = [];
        SilenceEffectBuilder.build(result, bi, f.item, f.data, null);
        var joined:String = result.join("");
        assertContains(joined, "90", "Silence percent has 90");

        // 距离消音
        f = MockItemFactory.weaponWithSilenceDistance();
        result = [];
        SilenceEffectBuilder.build(result, bi, f.item, f.data, null);
        joined = result.join("");
        assertContains(joined, "300", "Silence distance has 300");

        // getShortDescription
        var desc1:String = SilenceEffectBuilder.getShortDescription("90%");
        assert(desc1.length > 0, "Silence shortDesc percent non-empty");

        var desc2:String = SilenceEffectBuilder.getShortDescription("300");
        assert(desc2.length > 0, "Silence shortDesc distance non-empty");
    }

    // === DrugTooltipComposer ===

    private static function test_DrugTooltipComposer_null():Void {
        var r1:Array = DrugTooltipComposer.compose(null);
        assert(r1.length == 0, "DrugComposer null returns []");

        var r2:Array = DrugTooltipComposer.compose({});
        assert(r2.length == 0, "DrugComposer {} returns []");

        var r3:Array = DrugTooltipComposer.compose({data: {}});
        assert(r3.length == 0, "DrugComposer {data:{}} returns []");
    }
}
