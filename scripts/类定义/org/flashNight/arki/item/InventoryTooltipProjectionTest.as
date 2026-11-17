import org.flashNight.arki.item.InventoryPanelService;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;

/**
 * Producer contract only: real instance reads, detached values, display identity,
 * and stack quantities. Content/Document assertions run in the Launcher engine
 * suite; this runner must not compile an old AS2 content engine back into boot.
 * Windows execution is still required to validate these probes under AVM1.
 */
class org.flashNight.arki.item.InventoryTooltipProjectionTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== InventoryTooltipProjectionTest start ===");

        testEquipmentInstanceDocument();
        testHandEquipmentActionRail();
        testStackItemDocument();

        trace("InventoryTooltipProjectionTest Tests Passed: " + _passed);
        trace("InventoryTooltipProjectionTest Tests Failed: " + _failed);
        trace("=== InventoryTooltipProjectionTest end ===");
    }

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
        var previousClip:Object = ItemUtil.itemDataDict["手枪通用弹药"];
        var previousBalance:Object = ItemUtil.balanceDataDict[name];
        var previousEquipFlag:Object = ItemUtil.equipmentDict[name];
        var previousModDict:Object = EquipmentUtil.modDict;

        // ItemUtil.isEquipment 只认 equipmentDict：只读 producer 的装备分支
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
        // 弹夹条目注入使 magazine 部件确定产出（显示名/图标走 clipData，与生产同源）。
        ItemUtil.itemDataDict["手枪通用弹药"] = {
            name:"手枪通用弹药", displayname:"GateNI通用手枪弹夹", icon:"GateNI弹夹图标",
            type:"消耗品", use:"弹药", price:1
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

        var input:Object = r.tooltipInput;
        assertTrue(input != null && input.version == 1 && input.kind == "item"
                && input.itemName == name && input.presentation == "inventory",
            "返回版本化实例输入，由 Host 生成文档");
        assertTrue(r.document == undefined && r.descHTML == "" && r.introHTML == "",
            "AS2 不再生成 Document 或 HTML");
        assertTrue(input.projection.displayName == r.displayname
                && input.projection.iconName == r.iconName
                && input.projection.calculated.displayname == "GateNI涂装名",
            "真实 getData 身份进入展示投影，不由名称猜测");
        assertTrue(input.value.level == 3 && input.value.tier == "二阶"
                && input.value.mods.length == 2,
            "强化、进阶和实际配件完整投影");
        assertTrue(input.projection.baselineData.power == 100
                && input.projection.calculated.data.modslot == 2,
            "原始比较数据与最终计算数据保留独立来源");
        assertTrue(input.projection.mods["插件A"].useCases instanceof Array
                && input.projection.mods["插件A"].bulletCases instanceof Array,
            "每个插件都有权威匹配结果，空数组表示没有匹配");
        input.value.mods.push("仅修改投影");
        assertTrue(equipment.value.mods.length == 2,
            "返回值与真实实例没有可变数组别名");

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
        if (previousClip == undefined) delete ItemUtil.itemDataDict["手枪通用弹药"];
        else ItemUtil.itemDataDict["手枪通用弹药"] = previousClip;
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
     * 手部装备的 actiontype 必须进入 rail 书签，而不是只留在属性区的动作行。
     * 这条覆盖兽王虎甲手套这类套装手套在 character-build / merc 面板的富注释。
     */
    private static function testHandEquipmentActionRail():Void {
        var name:String = "GateNI手部动作装备";
        var itemDictWasUndefined:Boolean = ItemUtil.itemDataDict == undefined;
        if (itemDictWasUndefined) ItemUtil.itemDataDict = {};
        var equipDictWasUndefined:Boolean = ItemUtil.equipmentDict == undefined;
        if (equipDictWasUndefined) ItemUtil.equipmentDict = {};
        var previousMeta:Object = ItemUtil.itemDataDict[name];
        var previousEquipFlag:Object = ItemUtil.equipmentDict[name];
        var itemData:Object = {
            name: name, displayname: name, icon: name,
            type: "防具", use: "手部装备", actiontype: "兽形拳",
            price: 1,
            data: {
                level: 40, weight: 4, damage: 0, punch: 200,
                hp: 0, mp: 0, defence: 1
            }
        };
        ItemUtil.itemDataDict[name] = itemData;
        ItemUtil.equipmentDict[name] = true;
        var equipment:Object = {
            name: name, value: {level: 1, mods: []}, lastUpdate: 1,
            getData: function():Object { return itemData; }
        };

        var r:Object = InventoryPanelService.buildTooltipProjection(equipment);
        assertTrue(r != null && r.success === true && r.tooltipInput != null,
            "手部装备产出 TooltipInput");
        assertTrue(r.tooltipInput.projection.calculated.use == "手部装备"
                && r.tooltipInput.projection.calculated.actiontype == "兽形拳",
            "手部动作读取真实计算结果，TS 可据此生成 rail");

        if (previousMeta == undefined) delete ItemUtil.itemDataDict[name];
        else ItemUtil.itemDataDict[name] = previousMeta;
        if (previousEquipFlag == undefined) delete ItemUtil.equipmentDict[name];
        else ItemUtil.equipmentDict[name] = previousEquipFlag;
        if (itemDictWasUndefined) ItemUtil.itemDataDict = undefined;
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
        assertTrue(r != null && r.success === true && r.tooltipInput != null,
            "stack 物品产出输入");
        assertTrue(r.tooltipInput.projection.calculated == null
                && r.tooltipInput.value.level == 1 && r.tooltipInput.value.count == 42,
            "stack 数量完整保留，不冒充装备计算实例");
        assertTrue(r.tooltipInput.projection.displayName == "GateNI材料名"
                && r.tooltipInput.projection.iconName == "GateNI材料图标",
            "stack 图标名称与原展示投影同源");
        var bare:Object = {name:name, value:2, lastUpdate:1};
        var rb:Object = InventoryPanelService.buildTooltipProjection(bare);
        assertTrue(rb != null && rb.success === true && rb.tooltipInput != null
                && rb.displayname == name && rb.tooltipInput.projection.displayName == name
                && rb.tooltipInput.projection.iconName == name,
            "无 getData 的裸对象按原规则回落内部名");

        if (previousMeta == undefined) delete ItemUtil.itemDataDict[name];
        else ItemUtil.itemDataDict[name] = previousMeta;
        if (itemDictWasUndefined) ItemUtil.itemDataDict = undefined;
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
