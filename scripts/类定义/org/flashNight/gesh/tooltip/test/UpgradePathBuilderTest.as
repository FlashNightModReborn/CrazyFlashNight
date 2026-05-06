import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.builder.UpgradePathBuilder;

/**
 * UpgradePathBuilderTest - 装备升阶路线 builder 测试
 *
 * 覆盖范围：
 *   - 三段全空时不输出标题区块
 *   - 单段输出（升自 / 可升）的 HTML 结构
 *   - to-products 截断（>3 显示前 3 + 计数）
 *
 * Tier 段依赖 TierSystem + EquipmentConfigManager + BaseItem 实例，
 * mock 成本远高于收益，留给游戏内目视。这里只测 crafting 段。
 *
 * 隔离策略：每个 test 直接 save → swap → run → restore，不用闭包/try-finally
 * （AS2 1.0 编译器对闭包词法作用域和 try/finally 行为不稳定）。
 */
class org.flashNight.gesh.tooltip.test.UpgradePathBuilderTest {

    public static var testsRun:Number = 0;
    public static var testsPassed:Number = 0;
    public static var testsFailed:Number = 0;

    private static function assert(cond:Boolean, msg:String):Void {
        testsRun++;
        if (cond) { testsPassed++; trace("[PASS] " + msg); }
        else { testsFailed++; trace("[FAIL] " + msg); }
    }

    public static function runAllTests():Void {
        testsRun = testsPassed = testsFailed = 0;
        trace("--- UpgradePathBuilderTest ---");

        test_allEmpty_returnsEmptyArray();
        test_fromOnly_rendersFromSection();
        test_toOnly_rendersToSection();
        test_to_truncation_above3();
        test_to_exactly3_noTruncation();
        test_titleNotRendered_whenAllEmpty();

        trace("--- UpgradePathBuilderTest: " + testsPassed + "/" + testsRun + " passed, " + testsFailed + " failed ---");
    }

    // ──────────────── helpers ────────────────

    /** 注入 mock 字典；调用方负责 restore（用 restoreSynthDict） */
    private static function installSynthDict(dict:Object):Object {
        var saved = _root.改装清单对象;
        _root.改装清单对象 = dict;
        TooltipBridge.resetCraftToIndex();
        return saved;
    }

    private static function restoreSynthDict(saved):Void {
        _root.改装清单对象 = saved;
        TooltipBridge.resetCraftToIndex();
    }

    // ──────────────── tests ────────────────

    private static function test_allEmpty_returnsEmptyArray():Void {
        var saved = installSynthDict({});
        var item:Object = { name: "孤立装备", synthesis: null };
        var result:Array = UpgradePathBuilder.build(item, null);
        assert(result != null, "allEmpty: result not null");
        assert(result.length == 0, "allEmpty: result.length=0 actual=" + result.length);
        restoreSynthDict(saved);
    }

    private static function test_fromOnly_rendersFromSection():Void {
        // item 的 synthesis key 指向一个配方；item 名不作为任何配方的输入
        var dict:Object = {
            "升阶配方A": {
                name: "升阶产物A",
                materials: ["测试材料Q##2", "测试材料R##3"]   // ## = 数量模式
            }
        };
        var saved = installSynthDict(dict);
        var item:Object = { name: "升阶产物A", synthesis: "升阶配方A" };
        var result:Array = UpgradePathBuilder.build(item, null);
        var html:String = result.join("");

        assert(html.indexOf(TooltipConstants.LBL_UPGRADE_PATH) >= 0,
               "fromOnly: contains title");
        assert(html.indexOf(TooltipConstants.TIP_UPGRADE_FROM) >= 0,
               "fromOnly: contains 升自 label");
        assert(html.indexOf("测试材料Q") >= 0, "fromOnly: contains material Q");
        assert(html.indexOf("测试材料R") >= 0, "fromOnly: contains material R");
        // 不应出现"可升"段（item 名不作为任何配方输入）
        assert(html.indexOf(TooltipConstants.TIP_UPGRADE_TO) < 0,
               "fromOnly: no 可升 section");
        restoreSynthDict(saved);
    }

    private static function test_toOnly_rendersToSection():Void {
        // item 不作为产物（synthesis 无对应配方），但作为输入出现在多个配方里
        var dict:Object = {
            "进阶产品1": { name: "进阶产品1", materials: ["测试输入P##1"] },
            "进阶产品2": { name: "进阶产品2", materials: ["测试输入P##1"] }
        };
        var saved = installSynthDict(dict);
        var item:Object = { name: "测试输入P", synthesis: null };
        var result:Array = UpgradePathBuilder.build(item, null);
        var html:String = result.join("");

        assert(html.indexOf(TooltipConstants.LBL_UPGRADE_PATH) >= 0,
               "toOnly: contains title");
        assert(html.indexOf(TooltipConstants.TIP_UPGRADE_TO) >= 0,
               "toOnly: contains 可升 label");
        assert(html.indexOf("进阶产品1") >= 0, "toOnly: contains 进阶产品1");
        assert(html.indexOf("进阶产品2") >= 0, "toOnly: contains 进阶产品2");
        assert(html.indexOf(TooltipConstants.TIP_UPGRADE_FROM) < 0,
               "toOnly: no 升自 section");
        restoreSynthDict(saved);
    }

    private static function test_to_truncation_above3():Void {
        // 5 个产物都用同一输入 → to-list 长度=5 > UPGRADE_MAX_TO_PRODUCTS(3)
        var dict:Object = {
            "P1": { name: "P1", materials: ["共同输入##1"] },
            "P2": { name: "P2", materials: ["共同输入##1"] },
            "P3": { name: "P3", materials: ["共同输入##1"] },
            "P4": { name: "P4", materials: ["共同输入##1"] },
            "P5": { name: "P5", materials: ["共同输入##1"] }
        };
        var saved = installSynthDict(dict);
        var item:Object = { name: "共同输入", synthesis: null };
        var result:Array = UpgradePathBuilder.build(item, null);
        var html:String = result.join("");

        assert(html.indexOf(TooltipConstants.TIP_ETC) >= 0,
               "truncation: contains TIP_ETC marker - html=" + html);
        assert(html.indexOf("共5") >= 0,
               "truncation: shows total count 5 - html=" + html);
        restoreSynthDict(saved);
    }

    private static function test_to_exactly3_noTruncation():Void {
        // 恰好 3 个产物 → 不应触发截断
        var dict:Object = {
            "P1": { name: "P1", materials: ["边界输入##1"] },
            "P2": { name: "P2", materials: ["边界输入##1"] },
            "P3": { name: "P3", materials: ["边界输入##1"] }
        };
        var saved = installSynthDict(dict);
        var item:Object = { name: "边界输入", synthesis: null };
        var result:Array = UpgradePathBuilder.build(item, null);
        var html:String = result.join("");

        assert(html.indexOf("共3") < 0,
               "exactly3: no truncation count - html=" + html);
        assert(html.indexOf("P1") >= 0 && html.indexOf("P2") >= 0 && html.indexOf("P3") >= 0,
               "exactly3: all 3 products listed");
        restoreSynthDict(saved);
    }

    private static function test_titleNotRendered_whenAllEmpty():Void {
        var saved = installSynthDict({});
        var item:Object = { name: "完全无关物品", synthesis: null };
        var result:Array = UpgradePathBuilder.build(item, null);
        var html:String = result.join("");
        assert(html.indexOf(TooltipConstants.LBL_UPGRADE_PATH) < 0,
               "allEmpty: title NOT rendered");
        restoreSynthDict(saved);
    }
}
