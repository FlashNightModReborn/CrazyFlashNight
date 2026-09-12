import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;

/**
 * InventoryTooltipProjectionTest — buildTooltipProjection 的 COMMON v1 document 接线回归。
 *
 * 覆盖：
 * - 真实装备实例（强化等级 + 配件 mods）的 document 与 intro/desc 同源生成；
 * - document.title / icon 与 projection.displayName / iconName 严格同源（getData 覆盖）；
 * - 简介首行标题去重只发生在 document 边界：introHTML 原字段不变，
 *   [tier] 前缀提升进 title，类型/价格/强化/词条行全保留；
 * - stack 物品（无 getData 覆盖）也带一致 document。
 *
 * 运行入口：runAllTests()（由 test-runners/item-panels 或主控指定 runner 调用；
 * 本文件自身不注册 runner）。
 */
class org.flashNight.arki.item.InventoryTooltipProjectionTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== InventoryTooltipProjectionTest start ===");

        testEquipmentInstanceDocument();
        testStackItemDocument();
        testDocumentTitleDedupBoundary();

        trace("InventoryTooltipProjectionTest Tests Passed: " + _passed);
        trace("InventoryTooltipProjectionTest Tests Failed: " + _failed);
        trace("=== InventoryTooltipProjectionTest end ===");
    }

    /** 在 runs 数组中查找包含子串的 run 文本（纯文本，不含标记）。 */
    private static function findRunText(runs:Array, needle:String):String {
        if (runs == null) return null;
        for (var i:Number = 0; i < runs.length; i++) {
            var t:String = String(runs[i].text);
            if (t != null && t.indexOf(needle) >= 0) return t;
        }
        return null;
    }

    private static function sectionByRole(doc:Object, role:String):Object {
        if (doc == null || doc.sections == null) return null;
        for (var i:Number = 0; i < doc.sections.length; i++) {
            if (doc.sections[i].role == role) return doc.sections[i];
        }
        return null;
    }

    /** 所有 section 的 runs 拼成一个数组，便于全文档查找。 */
    private static function allRuns(doc:Object):Array {
        var out:Array = [];
        if (doc == null || doc.sections == null) return out;
        for (var i:Number = 0; i < doc.sections.length; i++) {
            var runs:Array = doc.sections[i].runs;
            if (runs == null) continue;
            for (var j:Number = 0; j < runs.length; j++) out.push(runs[j]);
        }
        return out;
    }

    /**
     * 装备实例：value.level=3、tier=二阶、mods=[插件A,插件B]，
     * getData() 覆盖 displayname/icon（涂装场景）。
     * 断言 document 与回包 displayname/iconName 同源、强化与配件文本进入 runs、
     * 标题去重后 intro 首 run 不再是名称、旧 introHTML 不变。
     */
    private static function testEquipmentInstanceDocument():Void {
        var name:String = "GateNI实例注释装备";
        var itemDictWasUndefined:Boolean = ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) ItemUtil.itemDataDict = {};
        var balanceDictWasUndefined:Boolean = ItemUtil.balanceDataDict == undefined;
        if (balanceDictWasUndefined) ItemUtil.balanceDataDict = {};
        var equipDictWasUndefined:Boolean = ItemUtil.equipmentDict == undefined;
        if (equipDictWasUndefined) ItemUtil.equipmentDict = {};
        var previousMeta:Object = ItemUtil.itemDataDict[name];
        var previousModA:Object = ItemUtil.itemDataDict["插件A"];
        var previousModB:Object = ItemUtil.itemDataDict["插件B"];
        var previousBalance:Object = ItemUtil.balanceDataDict[name];
        var previousEquipFlag:Object = ItemUtil.equipmentDict[name];
        var previousModDict:Object = EquipmentUtil.modDict;

        // ItemUtil.isEquipment 只认 equipmentDict：TooltipComposer 的装备分支
        // （含 ModsBlockBuilder 配件块）由它门控，不注册则 descHTML 不含配件行。
        ItemUtil.equipmentDict[name] = true;
        ItemUtil.itemDataDict[name] = {
            name: name, displayname: "GateNI原始名称", type: "武器", use: "手枪", price: 1,
            icon: "GateNI基础图标",
            data: {
                level:1, power:100, interval:400, capacity:8, weight:1, impact:2, modslot:2,
                bullet:"普通子弹", clipname:"手枪通用弹药", split:1, singleshoot:true
            }
        };
        ItemUtil.itemDataDict["插件A"] = {
            name:"插件A", displayname:"插件A展示名", type:"收集品", use:"装备插件", price:1
        };
        ItemUtil.itemDataDict["插件B"] = {
            name:"插件B", displayname:"插件B展示名", type:"收集品", use:"装备插件", price:1
        };
        // value.mods 存的是模组条目 ID；ModsBlockBuilder 逐条推 "  • "+ID，
        // 展示用字段是 modDict[ID].tagValue / stats.percentage（不是 displayname）。
        EquipmentUtil.modDict = {
            插件A: {name:"插件A", tagValue:"瞄具", stats:{percentage:{power:0.15}}},
            插件B: {name:"插件B", tagValue:"枪口", stats:{}}
        };

        var equipment:Object = {
            name: name,
            value: {level: 3, tier: "二阶", mods: ["插件A", "插件B"]},
            lastUpdate: 1,
            getData: function():Object {
                // 涂装覆盖：displayname/icon 与基础 itemData 不同
                return {name: name, displayname: "GateNI涂装名", type: "武器",
                    use: "手枪", icon: "GateNI涂装图标", data: {modslot: 2}};
            }
        };

        var r:Object = InventoryPanelService.buildTooltipProjection(equipment);
        assertTrue(r != null && r.success === true,
            "buildTooltipProjection 接受真实装备实例");

        // ── 回包基础字段：displayname/iconName 走 getData 覆盖（与既有 projection 一致）
        assertTrue(r.displayname == "GateNI涂装名" && r.iconName == "GateNI涂装图标",
            "回包 displayname/iconName 使用 getData 涂装覆盖");

        // ── document 存在且与投影同源
        var doc:Object = r.document;
        assertTrue(doc != null && doc.version == 1 && doc.profile == "dense",
            "document 为 v1 dense 文档");
        assertTrue(doc != null && doc.icon != null
            && doc.icon.kind == "item" && doc.icon.name == "GateNI涂装图标",
            "document.icon.name 与回包 iconName 同源（涂装图标）");
        assertTrue(doc != null && String(doc.title).indexOf("GateNI涂装名") >= 0
            && String(doc.title).indexOf("二阶") >= 0,
            "document.title 保留 [tier] 前缀与涂装显示名");

        // ── 标题去重：intro 首 run 不再是名称行，但 [tier] 进了 title
        var intro:Object = sectionByRole(doc, "intro");
        assertTrue(intro != null && intro.runs.length > 0,
            "document.intro 段存在");
        assertTrue(intro != null && intro.runs[0].text != null
            && String(intro.runs[0].text).indexOf("涂装名") < 0,
            "intro 首行名称已提升为 title，不再重复绘制");
        assertTrue(findRunText(intro.runs, "武器") != null
            && findRunText(intro.runs, "手枪") != null,
            "intro 保留类型/用途行");

        // ── 真实实例强化：level=3 的强化等级行进入 runs（不是 level1 冒充）
        assertTrue(findRunText(allRuns(doc), "强化等级") != null
            && findRunText(allRuns(doc), "强化等级").indexOf("3") >= 0,
            "document 含真实实例强化等级 3");

        // ── 配件 mods：descHTML 与 document 都含配件条目（同源输出）
        // ModsBlockBuilder 输出 "  • "+条目ID+" [tagValue] (+15%)"；断言的是
        // 条目 ID 与真实 schema 字段（tagValue/增幅），不是模组 displayname。
        assertTrue(String(r.descHTML).indexOf("插件A") >= 0
            && String(r.descHTML).indexOf("插件B") >= 0
            && String(r.descHTML).indexOf("瞄具") >= 0
            && String(r.descHTML).indexOf("15%") >= 0,
            "descHTML 保留配件条目与 tagValue/增幅");
        var desc:Object = sectionByRole(doc, "description");
        assertTrue(desc != null && findRunText(desc.runs, "插件A") != null
            && findRunText(desc.runs, "插件B") != null
            && findRunText(desc.runs, "瞄具") != null,
            "document.description 段保留配件名与 tagValue runs");

        // ── 旧字段不变：introHTML 仍含完整标题行（去重只在 document 边界发生）
        assertTrue(String(r.introHTML).indexOf("GateNI涂装名") >= 0
            && String(r.introHTML).indexOf("二阶") >= 0,
            "旧 introHTML 字段保留原始标题行，未被 document 去重影响");

        // ── 源对象未被修改
        assertTrue(equipment.value.level == 3 && equipment.value.tier == "二阶"
            && equipment.value.mods.length == 2,
            "buildTooltipProjection 不突变 value/Buff/装备状态");

        if (previousMeta == undefined) delete ItemUtil.itemDataDict[name];
        else ItemUtil.itemDataDict[name] = previousMeta;
        if (previousModA == undefined) delete ItemUtil.itemDataDict["插件A"];
        else ItemUtil.itemDataDict["插件A"] = previousModA;
        if (previousModB == undefined) delete ItemUtil.itemDataDict["插件B"];
        else ItemUtil.itemDataDict["插件B"] = previousModB;
        if (previousBalance == undefined) delete ItemUtil.balanceDataDict[name];
        else ItemUtil.balanceDataDict[name] = previousBalance;
        if (previousEquipFlag == undefined) delete ItemUtil.equipmentDict[name];
        else ItemUtil.equipmentDict[name] = previousEquipFlag;
        EquipmentUtil.modDict = previousModDict;
        if (itemDictWasUndefined) ItemUtil.itemDataDict = undefined;
        if (balanceDictWasUndefined) ItemUtil.balanceDataDict = undefined;
        if (equipDictWasUndefined) ItemUtil.equipmentDict = undefined;
    }

    /**
     * stack 物品（value 为数字）：document 仍存在，title/icon 与 projection 同源。
     * 真实库存 stack 也是带 getData() 的 BaseItem：buildItemProjectionInternal
     * 的显示身份统一来自 item.getData()（不读 itemData），仅无 getData 时
     * 回落内部 name——两个用例分别钉住这两条真实规则。
     */
    private static function testStackItemDocument():Void {
        var name:String = "GateNI堆叠注释材料";
        var itemDictWasUndefined:Boolean = ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) ItemUtil.itemDataDict = {};
        var previousMeta:Object = ItemUtil.itemDataDict[name];
        ItemUtil.itemDataDict[name] = {
            name: name, displayname: "GateNI材料名", type: "收集品", use: "材料",
            price: 7, icon: "GateNI材料图标",
            description: "<FONT COLOR=\"#FF00FF\">材料描述</FONT>"
        };

        // 主用例：与真实 BaseItem 一致带 getData()，身份经它进 projection。
        var stackItem:Object = {
            name: name, value: 42, lastUpdate: 1,
            getData: function():Object {
                return {name: name, displayname: "GateNI材料名",
                    icon: "GateNI材料图标", type: "收集品", use: "材料"};
            }
        };
        var r:Object = InventoryPanelService.buildTooltipProjection(stackItem);
        assertTrue(r != null && r.success === true && r.document != null,
            "stack 物品也产出 document");
        assertTrue(r.document != null && r.document.title == "GateNI材料名"
            && r.document.icon.name == "GateNI材料图标",
            "stack document title/icon 与 getData 身份同源");
        assertTrue(r.document != null && r.displayname == r.document.title
            && r.iconName == r.document.icon.name,
            "stack document 与回包 displayname/iconName 同源");
        // instanceValue 固定 {level:1}：不产生"强化等级"行，证明未把 stack 冒充强化实例
        assertTrue(findRunText(allRuns(r.document), "强化等级") == null,
            "stack document 无强化等级行（未冒充实例）");
        assertTrue(findRunText(allRuns(r.document), "材料描述") != null,
            "stack document.description 保留描述文本");

        // 次用例：无 getData 的裸对象——真实回落规则是 item.name（不是 itemData），
        // 回包 displayname 与 document.title 仍严格同源。
        var bare:Object = {name: name, value: 2, lastUpdate: 1};
        var rb:Object = InventoryPanelService.buildTooltipProjection(bare);
        assertTrue(rb != null && rb.success === true && rb.document != null
            && rb.displayname == name && rb.document.title == name
            && rb.document.icon.name == name,
            "无 getData 时身份回落 item.name，document/回包仍同源");

        if (previousMeta == undefined) delete ItemUtil.itemDataDict[name];
        else ItemUtil.itemDataDict[name] = previousMeta;
        if (itemDictWasUndefined) ItemUtil.itemDataDict = undefined;
    }

    /**
     * 标题去重反例：intro 首行与 title 无关时不得剥除；
     * 以名称结尾但前缀非 [tier] 形态的首行也不得误剥。
     * （文档级行为，直接走 buildItem 验证边界）
     */
    private static function testDocumentTitleDedupBoundary():Void {
        var NTD = org.flashNight.gesh.tooltip.NativeTooltipDocument;

        // 反例 A：首行是内容文本（不以 title 结尾）→ 不剥
        var docA:Object = NTD.buildItem("m1", {displayname:"甲"}, null,
            "<B>属性说明</B><BR>正文", "");
        assertTrue(String(docA.title) == "甲"
            && docA.sections.length == 1
            && docA.sections[0].runs[0].text == "属性说明",
            "首行与 title 无关时原样保留，不剥除");

        // 反例 B：首行以 title 结尾但前缀不是 [x] 形态 → 不剥
        var docB:Object = NTD.buildItem("m2", {displayname:"刀"}, null,
            "<B>传说之刀</B><BR>正文", "");
        assertTrue(String(docB.title) == "刀"
            && docB.sections[0].runs[0].text == "传说之刀",
            "非 [tier] 前缀的首行不误剥（传说之刀 != [x]刀）");

        // 正例 C：[tier]名 首行 → 提升整行进 title，intro 从第二行开始
        var docC:Object = NTD.buildItem("m3", {displayname:"军刀"}, null,
            "<B>[三阶]军刀</B><BR><FONT COLOR=\"#FF0000\">特效行</FONT><BR>", "");
        assertTrue(String(docC.title) == "[三阶]军刀",
            "[tier] 前缀随首行整体提升进 title");
        var introC:Object = sectionByRole(docC, "intro");
        assertTrue(introC != null && introC.runs.length > 0
            && introC.runs[0].text == "特效行"
            && introC.runs[0].color == "#FF0000",
            "去重后 intro 首个 run 保留特效行与其颜色");

        // 反例 D：title 行后无换行（与内容同行粘合）→ 不剥
        var docD:Object = NTD.buildItem("m4", {displayname:"乙"}, null,
            "<B>乙</B>紧随内容<BR>", "");
        assertTrue(docD.sections[0].runs[0].text == "乙"
            && docD.sections[0].runs[1].text == "紧随内容",
            "标题行与内容粘合时不剥除首 run");
    }

    private static function assertTrue(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
        } else {
            _failed++;
            trace("  FAILED: " + message);
        }
    }
}
