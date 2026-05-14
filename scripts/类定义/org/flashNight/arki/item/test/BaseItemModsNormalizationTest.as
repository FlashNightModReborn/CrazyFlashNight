import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * BaseItem.createFromObject 装备 mods 字段归一化回归测试。
 *
 * 守住的不变量：装备入库时 value.mods 必须是 Array。
 * 老存档可能写入 mods:{} / null / 字符串 等非数组形态，
 * 必须在反序列化入口被归一化为 [] 或保留原 Array。
 */
class org.flashNight.arki.item.test.BaseItemModsNormalizationTest {

    private var passed:Number;
    private var failed:Number;
    private var savedItemDataDict:Object;
    private var savedEquipmentDict:Object;
    private var savedMultiTierDict:Object;

    public function BaseItemModsNormalizationTest() {
        passed = 0;
        failed = 0;
    }

    private function assert(condition:Boolean, message:String, details:String):Void {
        if (condition) {
            trace("PASS: " + message);
            passed++;
        } else {
            trace("FAIL: " + message);
            if (details != undefined && details != "") {
                trace("  DETAILS: " + details);
            }
            failed++;
        }
    }

    private function setup():Void {
        savedItemDataDict = ItemUtil.itemDataDict;
        savedEquipmentDict = ItemUtil.equipmentDict;
        savedMultiTierDict = ItemUtil.multiTierDict;

        ItemUtil.itemDataDict = {};
        ItemUtil.itemDataDict["枪-长枪-AK74"] = { type: "武器", use: "长枪" };
        ItemUtil.itemDataDict["牛肉罐头"]   = { type: "消耗品", use: "食品" };

        ItemUtil.equipmentDict = {};
        ItemUtil.equipmentDict["枪-长枪-AK74"] = true;
        ItemUtil.multiTierDict = {};
    }

    private function teardown():Void {
        ItemUtil.itemDataDict = savedItemDataDict;
        ItemUtil.equipmentDict = savedEquipmentDict;
        ItemUtil.multiTierDict = savedMultiTierDict;
    }

    public function runTests():Void {
        trace("===== BaseItemModsNormalizationTest 开始 =====");
        setup();

        try {
            testPollutedObjectModsBecomesArray();
            testUndefinedModsBecomesArray();
            testNullModsBecomesArray();
            testStringModsBecomesArray();
            testValidArrayModsPreserved();
            testValidArrayModsContentPreserved();
            testNonEquipmentNotTouched();
            testPollutedModsLengthSafe();
        } finally {
            teardown();
        }

        trace("===== BaseItemModsNormalizationTest 结束: " + passed + " PASS / " + failed + " FAIL =====");
        if (failed == 0) {
            trace("===== ALL BaseItemModsNormalization TESTS PASS =====");
        } else {
            trace("!!!!! BaseItemModsNormalization TESTS FAIL: " + failed + " !!!!!");
        }
    }

    /** 老存档污染：mods:{} 必须被归一化为 [] */
    private function testPollutedObjectModsBecomesArray():Void {
        var initObject:Object = {
            name: "枪-长枪-AK74",
            value: { level: 3, mods: {} },
            lastUpdate: 1700000000
        };
        var item:BaseItem = BaseItem.createFromObject(initObject);
        assert(item != null, "createFromObject 应返回 BaseItem", null);
        assert(item.value.mods instanceof Array,
               "polluted mods:{} 应归一化为 Array",
               "实际 mods = " + ObjectUtil.stringify(item.value.mods));
        assert(item.value.mods.length === 0,
               "归一化后 mods.length 应为 0",
               "实际 length = " + item.value.mods.length);
    }

    /** mods undefined → [] */
    private function testUndefinedModsBecomesArray():Void {
        var initObject:Object = {
            name: "枪-长枪-AK74",
            value: { level: 1 },
            lastUpdate: 1700000000
        };
        var item:BaseItem = BaseItem.createFromObject(initObject);
        assert(item.value.mods instanceof Array,
               "undefined mods 应归一化为 Array",
               "实际 mods = " + ObjectUtil.stringify(item.value.mods));
    }

    /** mods null → [] */
    private function testNullModsBecomesArray():Void {
        var initObject:Object = {
            name: "枪-长枪-AK74",
            value: { level: 1, mods: null },
            lastUpdate: 1700000000
        };
        var item:BaseItem = BaseItem.createFromObject(initObject);
        assert(item.value.mods instanceof Array,
               "null mods 应归一化为 Array",
               "实际 mods = " + ObjectUtil.stringify(item.value.mods));
    }

    /** mods 是字符串这种异常型 → [] */
    private function testStringModsBecomesArray():Void {
        var initObject:Object = {
            name: "枪-长枪-AK74",
            value: { level: 1, mods: "战术导轨" },
            lastUpdate: 1700000000
        };
        var item:BaseItem = BaseItem.createFromObject(initObject);
        assert(item.value.mods instanceof Array,
               "string mods 应归一化为 Array",
               "实际 mods = " + ObjectUtil.stringify(item.value.mods));
    }

    /** 空 Array 应直接保留，不被重新分配 */
    private function testValidArrayModsPreserved():Void {
        var originalArr:Array = [];
        var initObject:Object = {
            name: "枪-长枪-AK74",
            value: { level: 1, mods: originalArr },
            lastUpdate: 1700000000
        };
        var item:BaseItem = BaseItem.createFromObject(initObject);
        assert(item.value.mods === originalArr,
               "已是 Array 的 mods 应保留同一引用，不应被替换",
               "");
    }

    /** 已含元素的 Array 应原样保留 */
    private function testValidArrayModsContentPreserved():Void {
        var initObject:Object = {
            name: "枪-长枪-AK74",
            value: { level: 5, mods: ["战术导轨", "瞄准镜"] },
            lastUpdate: 1700000000
        };
        var item:BaseItem = BaseItem.createFromObject(initObject);
        assert(item.value.mods instanceof Array, "Array mods 应保持 Array 类型", "");
        assert(item.value.mods.length === 2,
               "已有内容的 mods 应保留长度",
               "实际 length = " + item.value.mods.length);
        assert(item.value.mods[0] === "战术导轨" && item.value.mods[1] === "瞄准镜",
               "已有内容的 mods 应保留元素",
               "实际 mods = " + ObjectUtil.stringify(item.value.mods));
    }

    /** 非装备物品的 value 是 Number，不应触发 mods 处理 */
    private function testNonEquipmentNotTouched():Void {
        var initObject:Object = {
            name: "牛肉罐头",
            value: 5,
            lastUpdate: 1700000000
        };
        var item:BaseItem = BaseItem.createFromObject(initObject);
        assert(item != null, "非装备 createFromObject 应成功", "");
        assert(typeof item.value == "number" && item.value === 5,
               "非装备 value 应保持 Number 原值",
               "实际 value = " + item.value + " (typeof " + typeof item.value + ")");
    }

    /** 归一化后下游 .length 调用必须安全（这是 fix 的真正动机） */
    private function testPollutedModsLengthSafe():Void {
        var initObject:Object = {
            name: "枪-长枪-AK74",
            value: { level: 2, mods: {} },
            lastUpdate: 1700000000
        };
        var item:BaseItem = BaseItem.createFromObject(initObject);

        var lengthOk:Boolean = (typeof item.value.mods.length == "number") && (item.value.mods.length === 0);
        assert(lengthOk,
               "归一化后下游 mods.length 必须返回 number 0（原 {} 会返回 undefined 击穿）",
               "实际 typeof = " + typeof item.value.mods.length + ", value = " + item.value.mods.length);

        var pushOk:Boolean = false;
        try {
            item.value.mods.push("战术导轨");
            pushOk = (item.value.mods.length === 1 && item.value.mods[0] === "战术导轨");
        } catch (e) {
            pushOk = false;
        }
        assert(pushOk,
               "归一化后下游 mods.push 必须正常工作",
               "push 后 mods = " + ObjectUtil.stringify(item.value.mods));
    }
}
