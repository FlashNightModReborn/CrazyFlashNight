import org.flashNight.gesh.tooltip.test.TestDataBootstrap;
import org.flashNight.gesh.tooltip.test.MockItemFactory;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipTextBuilder;
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
import org.flashNight.gesh.tooltip.builder.ObtainMethodsBuilder;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import org.flashNight.gesh.tooltip.builder.ModStatBuilder;
import org.flashNight.gesh.tooltip.builder.ModsBlockBuilder;

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

    /** 逐项严格比较数组；用于 rail 文本这类顺序敏感的契约。 */
    private static function assertArray(expected:Array, actual:Object, msg:String):Void {
        testsRun++;
        if (!(actual instanceof Array) || actual.length != expected.length) {
            testsFailed++;
            trace("[FAIL] " + msg + " expected length " + expected.length
                + " actual=" + (actual instanceof Array ? actual.length : String(actual)));
            return;
        }
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] !== actual[i]) {
                testsFailed++;
                trace("[FAIL] " + msg + " index " + i + " expected=" + expected[i]
                    + " actual=" + actual[i]);
                return;
            }
        }
        testsPassed++;
        trace("[PASS] " + msg);
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
        test_GunStatsBuilder_fireMode_mod_shows_arrow();
        test_GunStatsBuilder_reloadType();
        test_GunStatsBuilder_reloadType_mod_shows_arrow();
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
        test_ObtainMethodsBuilder_no_index();
        test_ObtainMethodsBuilder_rows();
        test_ModStatBuilder_unknown_item();
        test_ModStatBuilder_curve();
        test_ModStatBuilder_conditionalRequireTags();
        test_ModStatBuilder_hitBehavior_useSwitch();
        test_ModStatBuilder_skillSwitch();
        test_ModsBlockBuilder_hitBehavior_useSwitch();
        test_ModsBlockBuilder_skillSwitch();

        test_getRailText();
        test_getMagazineInfo();
        test_buildIntroHeader_omitTypeLines();
        test_gunStats_omitClipName();
        test_commonStats_omitCritSlay();
        test_equipmentStatsComposer_omitCrit();
        test_generateIntroPanelContent_nativeOpt();

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

        // singleshoot=false → 全自动：默认值不显示（R1 信息密度优化）
        var fAuto:Object = MockItemFactory.gun();
        var result:Array = [];
        GunStatsBuilder.build(result, bi, fAuto.item, fAuto.data, null);
        var joined:String = result.join("");
        assertNotContains(joined, TooltipConstants.LBL_FIRE_MODE, "GunStats auto mode hidden");

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

        // reloadType="clip" → 整匣换弹：默认值不显示（R1 信息密度优化）
        var fClip:Object = MockItemFactory.gun();
        var result:Array = [];
        GunStatsBuilder.build(result, bi, fClip.item, fClip.data, null);
        var joined:String = result.join("");
        assertNotContains(joined, TooltipConstants.LBL_RELOAD_TYPE, "GunStats mag reload hidden");

        // reloadType="tube" → 逐发装填
        var fTube:Object = MockItemFactory.gun();
        fTube.data.reloadType = "tube";
        result = [];
        GunStatsBuilder.build(result, bi, fTube.item, fTube.data, null);
        joined = result.join("");
        assertContains(joined, TooltipConstants.TIP_RELOAD_TYPE_TUBE, "GunStats tube reload");
    }

    // R1: 配件修改默认值属性时应显示箭头格式
    private static function test_GunStatsBuilder_fireMode_mod_shows_arrow():Void {
        var bi = MockItemFactory.mockBaseItem();
        var f:Object = MockItemFactory.gun(); // singleshoot=false (全自动)
        var equipData:Object = {singleshoot: true}; // 配件改为半自动
        var result:Array = [];
        GunStatsBuilder.build(result, bi, f.item, f.data, equipData);
        var joined:String = result.join("");
        assertContains(joined, TooltipConstants.TIP_FIRE_MODE_SEMI, "GunStats mod auto→semi shows semi");
        assertContains(joined, TooltipConstants.TIP_FIRE_MODE_AUTO, "GunStats mod auto→semi shows base auto");
    }

    private static function test_GunStatsBuilder_reloadType_mod_shows_arrow():Void {
        var bi = MockItemFactory.mockBaseItem();
        var f:Object = MockItemFactory.gun(); // reloadType="clip" (整匣换弹)
        var equipData:Object = {reloadType: "tube"}; // 配件改为逐发装填
        var result:Array = [];
        GunStatsBuilder.build(result, bi, f.item, f.data, equipData);
        var joined:String = result.join("");
        assertContains(joined, TooltipConstants.TIP_RELOAD_TYPE_TUBE, "GunStats mod clip→tube shows tube");
        assertContains(joined, TooltipConstants.TIP_RELOAD_TYPE_MAG, "GunStats mod clip→tube shows base mag");
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

    // === P3a: 提取后的独立 builder 契约测试 ===

    private static function test_ObtainMethodsBuilder_no_index():Void {
        // 索引未构建时应返回空数组
        var result:Array = ObtainMethodsBuilder.build("不存在的物品");
        assert(result.length == 0, "ObtainMethodsBuilder no index: empty result");
        // buildWithRows 同路径：null 且不动输出缓冲
        var buf:Array = [];
        var entry:Object = ObtainMethodsBuilder.buildWithRows(buf, "不存在的物品");
        assert(entry == null && buf.length == 0,
            "ObtainMethodsBuilder no index: buildWithRows null & 不动缓冲");
    }

    private static function test_ObtainMethodsBuilder_rows():Void {
        // acquisition 结构化条目：商店来源逐 NPC 一行且 icon=NPC 头像键，
        // 旧 HTML 输出与旧 build 同源保留。共享单例已被其他套件构建过时跳过正例，
        // 避免 reset 破坏既有索引状态。
        var index:ItemObtainIndex = ItemObtainIndex.getInstance();
        if (index.isIndexBuilt()) {
            assert(true, "ObtainMethodsBuilder rows: 索引已被其他套件构建，跳过正例");
            return;
        }
        var shopA:Object = new Object();
        shopA["0"] = "测试物品X";
        var shopB:Object = new Object();
        shopB["0"] = "测试物品X";
        var shopFixture:Object = new Object();
        shopFixture["测试商人甲"] = shopA;
        shopFixture["测试商人乙"] = shopB;
        index.buildIndex(null, shopFixture, null, null);
        var html:Array = [];
        var entry:Object = ObtainMethodsBuilder.buildWithRows(html, "测试物品X");
        assert(entry != null && entry.kind == "acquisition",
            "buildWithRows: kind=acquisition");
        assert(entry != null && entry.title == "获取方式",
            "buildWithRows: 子框标题去【】");
        assert(entry != null && entry.rows.length == 3
            && entry.rows[0].name == "NPC商店" && entry.rows[0].depth == undefined,
            "buildWithRows: NPC商店类别独占父级行");
        assert(entry != null && entry.rows[1].icon != undefined
            && entry.rows[1].icon == entry.rows[1].name
            && entry.rows[1].depth === 1 && entry.rows[2].depth === 1,
            "buildWithRows: NPC 名称与头像逐行作为子级");
        var joined:String = html.join("");
        assert(joined.indexOf("【获取方式】") >= 0
            && joined.indexOf("商店：") >= 0
            && joined.indexOf("测试商人甲") >= 0
            && joined.indexOf("测试商人乙") >= 0,
            "buildWithRows: 旧 HTML 与旧输出同源保留");
        index.reset(false);
    }

    private static function test_ModStatBuilder_unknown_item():Void {
        // 未知物品名应返回空数组
        var result:Array = ModStatBuilder.build("完全不存在的配件名");
        assert(result.length == 0, "ModStatBuilder unknown item: empty result");
    }

    private static function test_ModStatBuilder_curve():Void {
        var oldDict:Object = EquipmentUtil.modDict;
        var dict:Object = {};
        dict["曲线插件"] = {
            name: "曲线插件",
            use: "长枪",
            tagValue: "下导轨",
            stats: {
                curve: {
                    diffusion: 1.414
                }
            }
        };
        EquipmentUtil.modDict = dict;

        var result:Array = ModStatBuilder.build("曲线插件");
        var joined:String = result.join("");

        EquipmentUtil.modDict = oldDict;

        assertContains(joined, TooltipConstants.TAG_CURVE, "ModStatBuilder curve has curve tag");
        assertContains(joined, TooltipConstants.LBL_CURVE_COMPRESSION_LEVEL, "ModStatBuilder curve has compression level label");
        assertContains(joined, "20", "ModStatBuilder curve maps coefficient 1.414 to level 20");
        assertNotContains(joined, "√当前值", "ModStatBuilder curve hides sqrt formula");
        assertContains(joined, TooltipConstants.PROPERTY_DICT["diffusion"], "ModStatBuilder curve has diffusion label");
    }

    private static function test_ModStatBuilder_conditionalRequireTags():Void {
        var oldDict:Object = EquipmentUtil.modDict;
        var dict:Object = {};
        dict["条件供电注释插件"] = {
            name: "条件供电注释插件",
            use: "长枪",
            tagValue: "下导轨",
            stats: {
                useSwitch: {
                    useCases: [{
                        name: "weapontype:机枪,weapontype:压制机枪",
                        requireTagDict: {电力: true}
                    }]
                }
            }
        };
        EquipmentUtil.modDict = dict;

        var result:Array = ModStatBuilder.build("条件供电注释插件");
        var joined:String = result.join("");

        EquipmentUtil.modDict = oldDict;

        assertContains(joined, TooltipConstants.LBL_COND_REQUIRE_TAGS,
                       "ModStatBuilder shows conditional requireTags label");
        assertContains(joined, "电力", "ModStatBuilder shows conditional required tag");
        assertContains(joined, "武器子类：机枪/武器子类：压制机枪",
                       "ModStatBuilder translates conditional branch qualifiers");
        assertNotContains(joined, "weapontype:机枪",
                          "ModStatBuilder hides conditional branch qualifier tokens");
    }

    private static function test_ModStatBuilder_hitBehavior_useSwitch():Void {
        var oldDict:Object = EquipmentUtil.modDict;
        var dict:Object = {};
        dict["行为弹药插件"] = buildHitBehaviorUseSwitchFixture();
        EquipmentUtil.modDict = dict;

        var result:Array = ModStatBuilder.build("行为弹药插件");
        var joined:String = result.join("");

        EquipmentUtil.modDict = oldDict;

        assertContains(joined, TooltipConstants.LBL_GRAY_GOO_BEHAVIOR, "ModStatBuilder uses compact gray-goo label");
        assertContains(joined, "18格，每格易伤+1%", "ModStatBuilder combines cap and vulnerability");
        assertContains(joined, "命中/破韧+1格；每6格击溃0.1%", "ModStatBuilder combines base triggers");
        assertContains(joined, "满层斩杀5%；停火3秒后衰减", "ModStatBuilder combines sustain rules");
        assertContains(joined, "武器子类：手枪", "ModStatBuilder translates qualified useSwitch label");
        assertContains(joined, "命中/破韧+3格；节点击溃0.3%；满层斩杀8%；停火5秒后衰减",
                       "ModStatBuilder compresses handgun overrides to one line");
        assertNotContains(joined, TooltipConstants.LBL_DECAY_INTERVAL,
                          "ModStatBuilder hides internal per-layer decay interval");
        assertNotContains(joined, "weapontype:手枪", "ModStatBuilder hides qualified token");
        assertNotContains(joined, "[object Object]", "ModStatBuilder never stringifies hitBehavior object");
    }

    private static function test_ModsBlockBuilder_hitBehavior_useSwitch():Void {
        var oldDict:Object = EquipmentUtil.modDict;
        var dict:Object = {};
        dict["行为弹药插件"] = buildHitBehaviorUseSwitchFixture();
        EquipmentUtil.modDict = dict;

        var handgunResult:Array = [];
        ModsBlockBuilder.build(
            handgunResult,
            null,
            {use: "手枪", weapontype: "手枪"},
            {mods: ["行为弹药插件"]}
        );
        var handgunJoined:String = handgunResult.join("");

        var machinePistolResult:Array = [];
        ModsBlockBuilder.build(
            machinePistolResult,
            null,
            {use: "手枪", weapontype: "冲锋枪"},
            {mods: ["行为弹药插件"]}
        );
        var machinePistolJoined:String = machinePistolResult.join("");

        EquipmentUtil.modDict = oldDict;

        assertContains(handgunJoined, "武器子类：手枪", "ModsBlockBuilder shows matched qualified handgun branch");
        assertContains(handgunJoined, "命中/破韧+3格；节点击溃0.3%；满层斩杀8%；停火5秒后衰减",
                       "ModsBlockBuilder uses one semantic handgun summary");
        assertNotContains(machinePistolJoined, "武器子类：手枪", "ModsBlockBuilder does not match handgun branch for machine pistol");
        assertNotContains(machinePistolJoined, "命中/破韧+3格", "ModsBlockBuilder does not leak handgun bonus to machine pistol");
    }

    private static function test_ModStatBuilder_skillSwitch():Void {
        var oldDict:Object = EquipmentUtil.modDict;
        var dict:Object = {};
        dict["条件战技插件"] = buildSkillSwitchFixture();
        EquipmentUtil.modDict = dict;

        var result:Array = ModStatBuilder.build("条件战技插件");
        var joined:String = result.join("");

        EquipmentUtil.modDict = oldDict;

        assertContains(joined, "按装备类型切换", "ModStatBuilder skillSwitch has mapping header");
        assertContains(joined, "其他情况", "ModStatBuilder skillSwitch has default label");
        assertContains(joined, "黑刀斩术", "ModStatBuilder skillSwitch has default skill name");
        assertContains(joined, "手枪", "ModStatBuilder skillSwitch has use label");
        assertContains(joined, "装备类型：手枪", "ModStatBuilder skillSwitch translates qualified use label");
        assertContains(joined, "闪现", "ModStatBuilder skillSwitch has skill name");
        assertNotContains(joined, "对手枪", "ModStatBuilder skillSwitch avoids additive wording");
        assertNotContains(joined, "use:手枪", "ModStatBuilder skillSwitch hides qualified token");
    }

    private static function test_ModsBlockBuilder_skillSwitch():Void {
        var oldDict:Object = EquipmentUtil.modDict;
        var dict:Object = {};
        dict["条件战技插件"] = buildSkillSwitchFixture();
        EquipmentUtil.modDict = dict;

        var result:Array = [];
        ModsBlockBuilder.build(result, null, {use: "手枪"}, {mods: ["条件战技插件"]});
        var joined:String = result.join("");

        EquipmentUtil.modDict = oldDict;

        assertContains(joined, "条件战技插件", "ModsBlockBuilder skillSwitch has mod name");
        assertContains(joined, "闪现", "ModsBlockBuilder skillSwitch has resolved skill");
    }

    // === 原生注释专属取数：左侧插条 rail ===

    private static function test_getRailText():Void {
        assertArray(["长枪", "突击步枪"],
            TooltipComposer.getRailText({type: "武器", use: "长枪", weapontype: "突击步枪"}, null),
            "rail: 大类+子类产出上下两块");
        assertArray(["手枪"],
            TooltipComposer.getRailText({type: "武器", use: "手枪"}, null),
            "rail: 无子类时只出大类块");
        assertArray(["手枪"],
            TooltipComposer.getRailText({type: "武器", use: "手枪", weapontype: "手枪"}, null),
            "rail: 大类与子类同名时去重为一块");
        assert(TooltipComposer.getRailText({type: "防具", use: "防具", weapontype: "胸甲"}, null) == null,
            "rail: 非武器不产插条（简介面板保留类型行）");
        assert(TooltipComposer.getRailText(null, null) == null,
            "rail: 空物品不产插条");

        assertArray(["长枪", "精确射手步枪"],
            TooltipComposer.getRailText({type: "武器", use: "手枪", weapontype: "突击步枪"},
                calcBaseItem(1, {use: "长枪", weapontype: "精确射手步枪"})),
            "rail: 计算后数据（进阶/涂装）覆盖原始字段");
        assertArray(["手枪", "突击步枪"],
            TooltipComposer.getRailText({type: "武器", use: "手枪", weapontype: "突击步枪"},
                calcBaseItem(1, {})),
            "rail: 计算数据缺字段时回落 item 原始字段");
        assertArray(["刀", "斩击"],
            TooltipComposer.getRailText({type: "武器", use: "刀", actiontype: "斩击"}, null),
            "rail: 冷兵器动作模组写成书签");
        assertArray(["手部装备", "默认"],
            TooltipComposer.getRailText({type: "防具", use: "手部装备"}, null),
            "rail: 手部装备缺省动作写成默认书签");
        assertArray(["手部装备", "重拳"],
            TooltipComposer.getRailText({type: "防具", use: "手部装备", actiontype: "默认"},
                calcBaseItem(1, {actiontype: "重拳"})),
            "rail: 计算后的动作覆盖进入书签");

        var actionText:Array = [];
        CommonStatsBuilder.build(actionText, null,
            {use: "手部装备", actiontype: "重拳"}, {}, {}, null);
        assertContains(actionText.join(""), TooltipConstants.LBL_ACTION,
            "action: 旧属性区保留动作行");
        actionText = [];
        CommonStatsBuilder.build(actionText, null,
            {use: "手部装备", actiontype: "重拳"}, {}, {}, {omitActionType: true});
        assertNotContains(actionText.join(""), TooltipConstants.LBL_ACTION,
            "action: rail 承载后属性区省略动作行");
    }

    /** 原生取数用的最小实例：getData() 返回指定计算结果。
     *  不标注返回类型是刻意的 —— AS2 会把无类型函数结果按宽松类型接受，
     *  直接把对象字面量写进 BaseItem 形参会报"类型不匹配"。 */
    private static function calcBaseItem(level:Number, calc:Object) {
        return {value: {level: level}, getData: function() { return calc; }};
    }

    // === 原生注释专属取数：弹夹独立框 ===

    private static function test_getMagazineInfo():Void {
        var gunItem:Object = ItemUtil.getItemData("测试手枪");
        assert(gunItem != null, "mag: 手枪 fixture 可用");

        var mag:Object = TooltipComposer.getMagazineInfo(
            MockItemFactory.mockBaseItem(), gunItem, {level: 1});
        assert(mag != null, "mag: 枪械产出弹夹信息");
        assert(mag != null && mag.name == "手枪通用弹药",
            "mag: name 取弹夹物品 displayname");
        assert(mag != null && mag.icon == undefined,
            "mag: 弹夹物品无 icon 字段时省略该键");
        assert(mag != null && mag.ammo == "普通",
            "mag: 子弹类型取 data.bullet，作弹夹框第二行");

        assert(TooltipComposer.getMagazineInfo(MockItemFactory.mockBaseItem(),
            ItemUtil.getItemData("测试军刀"), {level: 1}) == null,
            "mag: 非枪械不产弹夹框");
        assert(TooltipComposer.getMagazineInfo(null,
            {type: "武器", use: "手枪", data: {capacity: 12}}, {level: 1}) == null,
            "mag: 无 clipname 不产弹夹框");
        assert(TooltipComposer.getMagazineInfo(null,
            {type: "武器", use: "手枪", data: {clipname: "完全不存在的弹夹"}}, {level: 1}) == null,
            "mag: clipname 查不到物品时不产弹夹框");

        var upgraded:Object = TooltipComposer.getMagazineInfo(
            calcBaseItem(3, {data: {clipname: "手枪通用弹药"}}),
            gunItem, {level: 3});
        assert(upgraded != null && upgraded.name == "手枪通用弹药",
            "mag: 强化后以计算数据里的 clipname 为准");
        assert(upgraded != null && upgraded.ammo == "普通",
            "mag: 计算数据缺 bullet 时回落到物品原字段");

        var renamed:Object = TooltipComposer.getMagazineInfo(null,
            {type: "武器", use: "手枪", data: {clipname: "手枪通用弹药",
                bullet: "普通", bulletrename: "改装弹"}}, {level: 1});
        assert(renamed != null && renamed.ammo == "改装弹",
            "mag: bulletrename 优先于 bullet");
    }

    // === nativeOpt 省略开关：正文只减不丢 ===

    private static function test_buildIntroHeader_omitTypeLines():Void {
        var item:Object = {displayname: "测试步枪", type: "武器", use: "长枪",
                           weapontype: "突击步枪", price: 20000, data: {}};
        var legacyJoined:String = TooltipTextBuilder
            .buildIntroHeader(null, item, {level: 1}, null).join("");
        assertContains(legacyJoined, "武器    长枪", "introHeader: 默认输出大类行");
        assertContains(legacyJoined, TooltipConstants.LBL_WEAPON_TYPE, "introHeader: 默认输出子类行");

        var nativeJoined:String = TooltipTextBuilder
            .buildIntroHeader(null, item, {level: 1}, {omitTypeLines: true}).join("");
        assertNotContains(nativeJoined, "武器    长枪", "introHeader: omitTypeLines 去掉大类行");
        assertNotContains(nativeJoined, TooltipConstants.LBL_WEAPON_TYPE,
            "introHeader: omitTypeLines 去掉子类行");
        assertContains(nativeJoined, "测试步枪", "introHeader: 省略类型行不影响标题行");
        assertContains(nativeJoined, "$20000", "introHeader: 省略类型行不影响价格行");
    }

    private static function test_gunStats_omitClipName():Void {
        var f:Object = MockItemFactory.gun();
        var bi = MockItemFactory.mockBaseItem();

        var legacy:Array = [];
        GunStatsBuilder.build(legacy, bi, f.item, f.data, null, null);
        assertContains(legacy.join(""), TooltipConstants.LBL_CLIP_NAME,
            "gunStats: 默认输出使用弹夹行");

        var native:Array = [];
        GunStatsBuilder.build(native, bi, f.item, f.data, null, {omitClipName: true});
        var nativeJoined:String = native.join("");
        assertNotContains(nativeJoined, TooltipConstants.LBL_CLIP_NAME,
            "gunStats: omitClipName 把该行交给独立弹夹框");
        // 「使用弹夹」行是 4 个片段；只允许这一行消失，其余属性片段不得连带丢失。
        assert(native.length == legacy.length - 4,
            "gunStats: 只删弹夹一行，其余片段数不变 (legacy=" + legacy.length
            + " native=" + native.length + ")");
    }

    private static function test_commonStats_omitCritSlay():Void {
        var f:Object = MockItemFactory.meleeWeapon();
        f.data.slay = 8;
        var bi = MockItemFactory.mockBaseItem();

        var legacy:Array = [];
        CommonStatsBuilder.build(legacy, bi, f.item, f.data, null, null);
        assertContains(legacy.join(""), TooltipConstants.SUF_BLOOD,
            "critSlay: 默认斩杀行留在属性块");

        var buffer:Array = [];
        var native:Array = [];
        CommonStatsBuilder.build(native, bi, f.item, f.data, null,
            {omitCritSlay: true, critSlay: buffer});
        assertNotContains(native.join(""), TooltipConstants.SUF_BLOOD,
            "critSlay: omitCritSlay 把斩杀行移出属性块");
        assertContains(buffer.join(""), TooltipConstants.SUF_BLOOD,
            "critSlay: 斩杀行写入子框缓冲区");
        assertContains(native.join(""), TooltipConstants.PROPERTY_DICT["force"],
            "critSlay: 其余通用属性保留");
    }

    private static function test_equipmentStatsComposer_omitCrit():Void {
        var f:Object = MockItemFactory.weaponWithCrit();
        var bi = MockItemFactory.mockBaseItem();

        var legacy:Array = EquipmentStatsComposer.compose(bi, f.item, f.data, null, null);
        assertContains(legacy.join(""), TooltipConstants.LBL_CRIT,
            "critBlock: 默认暴击块在属性编排结果里");

        var buffer:Array = [];
        var native:Array = EquipmentStatsComposer.compose(bi, f.item, f.data, null,
            {omitCritSlay: true, critSlay: buffer});
        assertNotContains(native.join(""), TooltipConstants.LBL_CRIT,
            "critBlock: omitCritSlay 把暴击块移出属性编排结果");
        assertContains(buffer.join(""), TooltipConstants.LBL_CRIT,
            "critBlock: 暴击块写入子框缓冲区");
    }

    private static function test_generateIntroPanelContent_nativeOpt():Void {
        var gunItem:Object = ItemUtil.getItemData("测试手枪");
        var bi = MockItemFactory.mockBaseItem();

        var legacy:String = TooltipComposer.generateIntroPanelContent(bi, gunItem, {level: 1}, null);
        assertContains(legacy, "武器    手枪", "introPanel: 默认含类型行");
        assertContains(legacy, TooltipConstants.LBL_CLIP_NAME, "introPanel: 默认含使用弹夹行");

        var native:String = TooltipComposer.generateIntroPanelContent(bi, gunItem, {level: 1}, {
            omitTypeLines: true, omitClipName: true, omitCritSlay: true, critSlay: []
        });
        assertNotContains(native, "武器    手枪", "introPanel: 原生路径省略类型行（移交插条）");
        assertNotContains(native, TooltipConstants.LBL_CLIP_NAME,
            "introPanel: 原生路径省略弹夹行（移交独立框）");
        assert(native.length > 0, "introPanel: 原生路径仍有属性正文");
    }

    private static function buildSkillSwitchFixture():Object {
        return {
            name: "条件战技插件",
            use: "刀,手枪",
            tagValue: "挂饰",
            skillSwitch: {
                use: [
                    {
                        skillname: "黑刀斩术",
                        description: "默认分支战技说明。",
                        cd: 6000,
                        mp: 45
                    },
                    {
                        name: "use:手枪",
                        skillname: "闪现",
                        description: "条件分支战技说明。",
                        cd: 6000,
                        mp: 15,
                        level: 1
                    }
                ]
            }
        };
    }

    private static function buildHitBehaviorUseSwitchFixture():Object {
        return {
            name: "行为弹药插件",
            use: "手枪",
            tagValue: "弹药",
            stats: {
                merge: {
                    hitBehavior: {
                        type: "grayGooPrimer",
                        decayDelay: 90,
                        decayInterval: 10,
                        maxStacks: 18,
                        hitStacks: 1,
                        breakStacks: 1,
                        milestoneInterval: 6,
                        damagePerStack: 0.01,
                        crumblePerMilestone: 0.1,
                        executeAtMax: 5,
                        sameSourceOnly: true
                    }
                },
                useSwitch: {
                    useCases: [{
                        name: "weapontype:手枪",
                        merge: {
                            hitBehavior: {
                                decayDelay: 150,
                                decayInterval: 15,
                                hitStacks: 3,
                                breakStacks: 3,
                                crumblePerMilestone: 0.3,
                                executeAtMax: 8
                            }
                        }
                    }]
                }
            }
        };
    }
}
