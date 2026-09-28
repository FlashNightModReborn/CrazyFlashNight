import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.arki.item.equipment.EquipmentLifecyclePolicy;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.equipment.TagManager;
import org.flashNight.arki.item.equipment.EquipmentCalculator;

class org.flashNight.arki.item.equipment.EquipmentLifecyclePolicyTest {
    private static var passed:Number, failed:Number;
    private static function check(value:Boolean, label:String):Void {
        if (value) passed++; else { failed++; trace("EquipmentLifecyclePolicyTest FAIL: " + label); }
    }
    private static function attr():Object {
        return {skillInteraction:"independent", init:{initRoutines:"装备光源初始化", initParam:{kind:"laser", energy:0.7}},
            cycle:{cycleRoutines:"装备光源周期"}};
    }
    private static function count(value:Object):Number {
        var total:Number = 0;
        for (var key:String in value) if (value.hasOwnProperty(key)) total++;
        return total;
    }
    private static function fromMod(value:Object, name:String):Object {
        for (var key:String in value) if (value[key].__modName === name) return value[key];
        return null;
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var oldMods:Array = ModRegistry.getModList();
        try {
            var light:Object = {name:"测试灯", use:"长枪", lifecycle:{attr_0:attr(), attr_1:attr()}};
            var other:Object = {name:"另一灯", use:"长枪", lifecycle:{attr_0:attr()}};
            var old:Object = {name:"旧配件", use:"长枪", stats:{flat:{power:2}}};
            var skill:Object = {name:"测试战技", use:"长枪", skill:{skillname:"fixture"}};
            var bad:Object = {name:"错误灯", use:"长枪", lifecycle:{attr_0:{skillInteraction:"managed"}}};
            ModRegistry.loadModData([light, other, old, skill, bad]);
            var registry:Object = ModRegistry.getModDict();
            check(EquipmentLifecyclePolicy.isIndependentLifecycle(light.lifecycle), "多独立绑定合法");
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle(undefined), "缺失不能当作独立声明");
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle({}), "空声明拒绝");
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle([attr()]), "数组声明拒绝");
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle({wrong:attr()}), "装载器不认识的键拒绝");
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle({attr_0:{init:{initRoutines:"x"}}}), "缺标签拒绝");
            var invalid:Object = attr(); invalid.skillInteraction = "bound";
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle({attr_0:invalid}), "指定战技耦合插件拒绝");
            invalid = attr(); invalid.skill = {skillname:"x"};
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle({attr_0:invalid}), "独立标签不掩盖直接战技声明");
            invalid = attr(); invalid.setGate = {setId:"x"};
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle({attr_0:invalid}), "套装门不冒充独立插件");
            check(!EquipmentLifecyclePolicy.isIndependentLifecycle({attr_0:{skillInteraction:"independent"}}), "没有回调的空功能拒绝");
            var base:Object = {attr_0:{skillInteraction:"managed", init:{initRoutines:"原功能"}}};
            var merged:Object = EquipmentLifecyclePolicy.merge(base, ["测试灯", "另一灯"], registry);
            check(count(merged) == 4 && merged.attr_0.init.initRoutines == "原功能", "与本体同名attr及多个插件并存");
            check(fromMod(merged, "测试灯") != null && fromMod(merged, "另一灯") != null, "来源标记可供loader使用");
            fromMod(merged, "测试灯").init.initParam.energy = 1.9;
            merged.attr_0.init.initRoutines = "修改副本";
            check(light.lifecycle.attr_0.init.initParam.energy == 0.7 && base.attr_0.init.initRoutines == "原功能", "深拷贝不污染模板");
            merged = EquipmentLifecyclePolicy.merge(merged, ["另一灯", "测试灯"], registry);
            check(count(merged) == 4, "重算与重排不累积绑定");
            merged = EquipmentLifecyclePolicy.merge(merged, ["另一灯"], registry);
            check(count(merged) == 2 && fromMod(merged, "测试灯") == null, "移除插件删除旧投影");
            merged = EquipmentLifecyclePolicy.merge(merged, [], registry);
            check(count(merged) == 1 && fromMod(merged, "另一灯") == null, "移除全部插件保留本体");
            check(count(EquipmentLifecyclePolicy.merge(base, ["测试灯", "测试灯"], registry)) == 3, "重复输入不重复注册");
            check(count(EquipmentLifecyclePolicy.merge(base, ["错误灯"], registry)) == 1, "无效插件整段不执行");
            var item = {name:"fixture", value:{level:1, mods:[]}};
            var data:Object = {type:"武器", use:"长枪", data:{power:10, capacity:5, modslot:8, bullet:"普通子弹"},
                skill:{skillname:"原战技", skillLocked:true}, lifecycle:base};
            check(TagManager.checkModAvailability(item, data, "测试灯") == 1, "独立灯可与锁定本体战技并存");
            check(TagManager.checkModAvailability(item, data, "旧配件") == 1, "无生命周期旧配件保持准入");
            check(TagManager.checkModAvailability(item, data, "测试战技") == -4, "战技插件仍受原锁保护");
            check(TagManager.checkModAvailability(item, data, "错误灯") == -1024, "不支持的插件生命周期明确拒绝");
            data.subweapon = {fixture:true};
            check(TagManager.checkModAvailability(item, data, "测试灯") == 1, "独立灯不争夺副武器槽");
            delete data.subweapon;
            var config:Object = {levelStatList:[1,1], tierNameToKeyDict:{测试阶:"data_test"}, defaultTierDataDict:{}};
            var calc:Object = EquipmentCalculator.calculatePure(data, {level:1, mods:["测试灯","旧配件"]}, config, registry);
            check(calc.data.power == 12 && count(calc.lifecycle) == 3, "真实计算器同时合成数值和生命周期");
            check(data.data.power == 10 && count(data.lifecycle) == 1, "纯计算保留源物品");
            EquipmentCalculator.calculateInPlace(calc, {level:1, mods:[]}, config, registry);
            check(count(calc.lifecycle) == 1, "无插件早退也会清掉旧合成绑定");
            data.data_test = {power:20, lifecycle:{attr_tier:{skillInteraction:"bound", init:{initRoutines:"进阶功能"}}}};
            calc = EquipmentCalculator.calculatePure(data, {level:1, tier:"测试阶", mods:["测试灯"]}, config, registry);
            check(calc.lifecycle.attr_0 == undefined && calc.lifecycle.attr_tier != undefined && count(calc.lifecycle) == 3,
                "进阶覆盖之后再合成插件");
            check(data.data_test != null && count(data.data_test.lifecycle) == 1, "进阶模板保持原样");
        } catch (error:Error) { check(false, "意外异常 " + error); }
        if (oldMods.length > 0) ModRegistry.loadModData(oldMods);
        trace("EquipmentLifecyclePolicyTest Tests Passed: " + passed);
        trace("EquipmentLifecyclePolicyTest Tests Failed: " + failed);
    }
}
