import org.flashNight.arki.unit.UnitComponent.Initializer.SetEffectController;

import org.flashNight.arki.item.ItemUtil;

/** 套装控制器纯契约与显式失败回滚测试。 */
class org.flashNight.arki.unit.UnitComponent.Initializer.test.SetEffectControllerTest {

    private static function assertTrue(condition:Boolean, message:String):Void {
        if (!condition) throw new Error(message);
    }

    public static function runAllTests():Void {
        trace("=== SetEffectController Test Suite ===");
        testCountUsesUniqueSlots();
        testResistanceSemantics();
        testExplicitFailureRollsBackResources();
        testActivationSchedulingAndTeardown();
        trace("SetEffectControllerTest: all tests passed");
    }

    private static function testCountUsesUniqueSlots():Void {
        var slots:Object = {};
        slots["头部装备"] = {setId:"sword_saint_armor"};
        slots["上装装备"] = {setId:"sword_saint_armor"};
        slots["下装装备"] = {setId:"other"};
        assertTrue(SetEffectController.countSetSlots(slots, "sword_saint_armor") == 2,
            "Set count must use occupied equipment slots, not lifecycle attribute count");
    }

    private static function testResistanceSemantics():Void {
        assertTrue(SetEffectController.calculateAdditiveResistance(undefined, 10, 75) == 85,
            "Missing resistance must use baseIfMissing=10 before add 75");
        assertTrue(SetEffectController.calculateAdditiveResistance(null, 10, 75) == 85,
            "Null resistance must use baseIfMissing");
        assertTrue(SetEffectController.calculateAdditiveResistance(0, 10, 75) == 75,
            "Existing zero resistance must remain a real base");
        assertTrue(SetEffectController.calculateAdditiveResistance(10, 10, 75) == 85,
            "Existing resistance must be incremented");
        assertTrue(SetEffectController.calculateAdditiveResistance("bad", 10, 75) == undefined,
            "Non-finite existing resistance must fail closed");
    }

    private static function testExplicitFailureRollsBackResources():Void {
        var order:Array = [];
        var group:Object = {
            failed:false,
            status:"candidate",
            effects:{},
            rollbackPlan:{stopStack:[], resourceStack:[]},
            teardownPlan:{stopStack:[], resourceStack:[]}
        };
        var ref:Object = {套装事务:group, 套装组件ID:"test_component"};
        assertTrue(SetEffectController.registerResource(ref, function():Void { order.push("first"); }),
            "First resource must register");
        assertTrue(SetEffectController.registerResource(ref, function():Void { order.push("second"); }),
            "Second resource must register");

        SetEffectController.failRef(ref, "injected failure");
        assertTrue(order.join(",") == "second,first", "Rollback must be LIFO");
        assertTrue(group.status == "rolledBack", "Failed group must end rolledBack");
        assertTrue(group.teardownPlan.resourceStack.length == 0,
            "Rolled-back group must retain no runtime cleanup handle");
    }

    private static function makeSwordConfig():Object {
        return {id:"sword_saint_armor", effects:{
            effect_0:{id:"proto_resistance_entry", threshold:5,
                activationGroup:"sword_saint_full_set", kind:"template", template:"resistance_entry",
                params:{attribute:"原体", calculation:"add", baseIfMissing:10, value:75}},
            effect_1:{id:"combat_suite", threshold:5,
                activationGroup:"sword_saint_full_set", kind:"routine",
                prepareRoutine:"test_set_prepare", cycleRoutine:"test_set_context",
                components:{
                    component_0:{id:"head_scan", slot:"头部装备"},
                    component_1:{id:"chest_cannon", slot:"上装装备"},
                    component_2:{id:"leg_sword_case", slot:"下装装备"},
                    component_3:{id:"foot_skill_boost", slot:"脚部装备"},
                    component_4:{id:"hand_wrist_blade", slot:"手部装备"}
                }}
        }};
    }

    private static function equipSwordSlots(target:Object, count:Number):Void {
        var slots:Array = ["头部装备", "上装装备", "下装装备", "脚部装备", "手部装备"];
        for (var i:Number = 0; i < slots.length; i++) {
            target[slots[i] + "数据"] = i < count ? {setId:"sword_saint_armor"} : {};
        }
    }

    private static function testActivationSchedulingAndTeardown():Void {
        var oldConfigs:Object = ItemUtil.itemSetConfigDict;
        var oldRoutines:Object = _root.装备生命周期函数;
        var oldTimer:Object = _root.帧计时器;
        var scheduled:Array = [];
        var removed:Array = [];
        var four:MovieClip;
        var five:MovieClip;

        ItemUtil.itemSetConfigDict = {sword_saint_armor:makeSwordConfig()};
        _root.装备生命周期函数 = {
            test_set_prepare:function(effect:Object, target:Object):Object {
                return {target:target, frameStamp:-1};
            },
            test_set_context:function(effect:Object, context:Object):Void {},
            test_component_cycle:function(ref:Object, context:Object):Void {}
        };
        _root.帧计时器 = {
            taskManager:{addLifecycleTask:function(owner:Object, label:String, action:Function,
                interval:Number, parameters:Array):String {
                scheduled.push(label);
                return String(scheduled.length);
            }},
            移除生命周期任务:function(owner:Object, label:String):Void { removed.push(label); }
        };

        try {
            four = _root.createEmptyMovieClip("__set_effect_test_four", _root.getNextHighestDepth());
            four.生命周期函数列表 = [];
            four.魔法抗性 = {};
            equipSwordSlots(four, 4);
            SetEffectController.prepare(four);
            assertTrue(!SetEffectController.isGateActive(four, "sword_saint_armor", "combat_suite",
                "头部装备", "head_scan"), "Four unique slots must not activate the five-piece gate");
            SetEffectController.finalize(four);
            assertTrue(four.魔法抗性.原体 == undefined, "Four pieces must not create proto resistance");
            assertTrue(scheduled.length == 0, "Four pieces must not schedule set tasks");

            five = _root.createEmptyMovieClip("__set_effect_test_five", _root.getNextHighestDepth());
            five.生命周期函数列表 = [];
            five.魔法抗性 = {};
            equipSwordSlots(five, 5);
            SetEffectController.prepare(five);
            var gateKeys:Array = [];
            for (var gateKey:String in five.__setEffectController.activeGates) gateKeys.push(gateKey);
            var parts:Array = [
                ["头部装备", "head_scan", SetEffectController.READY_CYCLE],
                ["上装装备", "chest_cannon", SetEffectController.READY_CYCLE],
                ["下装装备", "leg_sword_case", SetEffectController.READY_CYCLE],
                ["脚部装备", "foot_skill_boost", SetEffectController.READY_STATIC],
                ["手部装备", "hand_wrist_blade", SetEffectController.READY_CYCLE]
            ];
            for (var i:Number = 0; i < parts.length; i++) {
                var part:Array = parts[i];
                assertTrue(SetEffectController.isGateActive(five, "sword_saint_armor", "combat_suite",
                    part[0], part[1]), "Five pieces must expose gate " + part[1] + "; actual=" + gateKeys.join("|"));
                var ref:Object = {装备类型:part[0], 生命周期参数:{}};
                assertTrue(SetEffectController.bindRef(five, ref, "sword_saint_armor", "combat_suite",
                    part[0], part[1]) != null, "Gate must bind ref " + part[1]);
                assertTrue(SetEffectController.registerComponent(ref, part[2],
                    part[2] == SetEffectController.READY_CYCLE
                        ? _root.装备生命周期函数.test_component_cycle : null),
                    "Component must enter activation group " + part[1]);
            }

            SetEffectController.finalize(five);
            assertTrue(five.魔法抗性.原体 == 85, "Five pieces must commit proto resistance 85");
            assertTrue(scheduled.length == 5, "One context and four ready_cycle tasks must be scheduled");
            assertTrue(String(scheduled[0]).indexOf(":context") > 0,
                "Context producer must be scheduled before every child cycle");
            assertTrue(five.生命周期函数列表.length == 1,
                "Committed group must install one aggregate teardown entry");
            five.生命周期函数列表[0].动作(five.生命周期函数列表[0].额外参数);
            assertTrue(removed.length == 5, "Aggregate teardown must remove context and all child tasks");
        } finally {
            ItemUtil.itemSetConfigDict = oldConfigs;
            _root.装备生命周期函数 = oldRoutines;
            _root.帧计时器 = oldTimer;
            if (four) four.removeMovieClip();
            if (five) five.removeMovieClip();
        }
    }
}
