import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;

/** RuntimeEquipmentProjection 的 canonical、alias intent 与 fail-closed 回归。 */
class org.flashNight.arki.unit.UnitComponent.Initializer.test.RuntimeEquipmentProjectionTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var SLOT_KEYS:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"
    ];

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== RuntimeEquipmentProjectionTest start ===");
        testCanonicalAndSemanticDrift();
        testForwardAndReverseAliases();
        testIntentGuardsAndCleanup();
        trace("RuntimeEquipmentProjectionTest Tests Passed: " + _passed);
        trace("RuntimeEquipmentProjectionTest Tests Failed: " + _failed);
        trace("=== RuntimeEquipmentProjectionTest end ===");
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
            trace("[PASS] " + message);
        } else {
            _failed++;
            trace("[FAIL] " + message);
        }
    }

    private static function equipment(name:String, level:Number,
                                      tier:String, mods):Object {
        return {
            name:name,
            value:{
                level:level,
                tier:tier,
                mods:mods,
                shot:7,
                reloadCount:2,
                当前战技:0,
                长柄形态:true
            },
            lastUpdate:1
        };
    }

    private static function stack(name:String, quantity:Number):Object {
        return {name:name, value:quantity, lastUpdate:1};
    }

    private static function target(version:Number):Object {
        var result:Object = {version:version};
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            result[SLOT_KEYS[i]] = null;
        }
        return result;
    }

    private static function refsOf(value:Object):Array {
        var refs:Array = [];
        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            refs[i] = value[SLOT_KEYS[i]];
        }
        return refs;
    }

    private static function owner(value:Object, sourceSlot:String):Object {
        return {
            自机:value,
            装备类型:sourceSlot,
            装备名称:value[sourceSlot].name,
            版本号:value.version
        };
    }

    private static function testCanonicalAndSemanticDrift():Void {
        var value:Object = target(1);
        value.头部装备 = equipment("投影头盔", 1, "一阶", ["导轨", "瞄具"]);
        value.长枪 = equipment("投影长枪", 2, "", []);
        value.手雷 = stack("投影手雷", 5);
        var refs:Array = refsOf(value);
        var begun:Object = RuntimeEquipmentProjection.beginCanonical(value);
        var completed:Boolean = RuntimeEquipmentProjection.completeCanonical(value);
        check(begun != null && completed
                && RuntimeEquipmentProjection.getStatus(value, refs)
                    == RuntimeEquipmentProjection.STATUS_ALIGNED,
            "完整 canonical 投影提交后为 aligned");

        value.手雷.value = 2;
        value.头部装备.lastUpdate = 99;
        value.头部装备.value.shot = 1;
        value.头部装备.value.当前战技 = 3;
        value.头部装备.value.长柄形态 = false;
        check(RuntimeEquipmentProjection.getStatus(value, refs)
                == RuntimeEquipmentProjection.STATUS_ALIGNED,
            "堆叠数量、lastUpdate、弹药、战技与形态不属于 live projection identity");

        value.头部装备.value.level = 2;
        check(RuntimeEquipmentProjection.getStatus(value, refs)
                == RuntimeEquipmentProjection.STATUS_MISMATCH,
            "level 原地变化使 applied semantic stamp mismatch");
        value.头部装备.value.level = 1;
        value.头部装备.value.tier = "二阶";
        check(RuntimeEquipmentProjection.getStatus(value, refs)
                == RuntimeEquipmentProjection.STATUS_MISMATCH,
            "tier 原地变化使 applied semantic stamp mismatch");
        value.头部装备.value.tier = "一阶";
        value.头部装备.value.mods.push("芯片");
        check(RuntimeEquipmentProjection.getStatus(value, refs)
                == RuntimeEquipmentProjection.STATUS_MISMATCH,
            "mods 原地变化使 applied semantic stamp mismatch");

        value = target(2);
        value.长枪 = equipment("同语义长枪", 1, "", []);
        refs = refsOf(value);
        RuntimeEquipmentProjection.beginCanonical(value);
        RuntimeEquipmentProjection.completeCanonical(value);
        var replacement:Object = equipment("同语义长枪", 1, "", []);
        value.长枪 = replacement;
        refs[6] = replacement;
        check(RuntimeEquipmentProjection.getStatus(value, refs)
                == RuntimeEquipmentProjection.STATUS_MISMATCH,
            "语义相同但 exact item ref 替换仍是 canonical mismatch");

        value = target(3);
        value.长枪 = equipment("裸写长枪", 1, "", []);
        refs = refsOf(value);
        RuntimeEquipmentProjection.beginCanonical(value);
        RuntimeEquipmentProjection.completeCanonical(value);
        value.刀 = value.长枪;
        check(RuntimeEquipmentProjection.getStatus(value, refs)
                == RuntimeEquipmentProjection.STATUS_MISMATCH,
            "未登记的运行态槽位裸写不会被别名规范化");
    }

    private static function testForwardAndReverseAliases():Void {
        var value:Object = target(10);
        value.长枪 = equipment("复合长枪", 2, "", []);
        var refs:Array = refsOf(value);
        RuntimeEquipmentProjection.beginCanonical(value);
        var intent:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            owner(value, "长枪"), "刀");
        // 生产中的刀配置/长枪配置会先把兼容配置名写进目标槽，commit 必须把它
        // 收敛为 source exact ref；reservation 才是覆盖该临时写的所有权证明。
        value.刀 = "fixture-blade-config";
        var committed:Boolean = RuntimeEquipmentProjection.commitSlotAlias(intent);
        var completed:Boolean = RuntimeEquipmentProjection.completeCanonical(value);
        check(intent != null && committed && completed
                && value.刀 === value.长枪
                && RuntimeEquipmentProjection.getCanonicalRef(value, "刀") == null
                && RuntimeEquipmentProjection.hasActiveAlias(value, "刀", "长枪")
                && RuntimeEquipmentProjection.getStatus(value, refs)
                    == RuntimeEquipmentProjection.STATUS_ALIGNED,
            "长枪到刀的空槽借用保留 canonical 空槽并提交 aligned 投影");

        RuntimeEquipmentProjection.releaseAliases(value);
        check(value.刀 == null
                && RuntimeEquipmentProjection.getStatus(value, refs)
                    == RuntimeEquipmentProjection.STATUS_INVALID,
            "teardown 幂等回收 alias 并删除过期 applied stamp");

        value = target(11);
        value.刀 = equipment("复合刀", 3, "", []);
        refs = refsOf(value);
        RuntimeEquipmentProjection.beginCanonical(value);
        intent = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            owner(value, "刀"), "长枪");
        value.长枪 = "fixture-longgun-config";
        committed = RuntimeEquipmentProjection.commitSlotAlias(intent);
        completed = RuntimeEquipmentProjection.completeCanonical(value);
        check(committed && completed && value.长枪 === value.刀
                && RuntimeEquipmentProjection.getCanonicalRef(value, "长枪") == null
                && RuntimeEquipmentProjection.hasActiveAlias(value, "长枪", "刀")
                && RuntimeEquipmentProjection.getStatus(value, refs)
                    == RuntimeEquipmentProjection.STATUS_ALIGNED,
            "刀到长枪的反向空槽借用使用同一 intent API");
    }

    private static function testIntentGuardsAndCleanup():Void {
        var value:Object = target(20);
        var refs:Array;
        value.长枪 = equipment("占用长枪", 1, "", []);
        value.刀 = equipment("占用刀", 1, "", []);
        RuntimeEquipmentProjection.beginCanonical(value);
        var rejected:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            owner(value, "长枪"), "刀");
        check(rejected == null && RuntimeEquipmentProjection.completeCanonical(value),
            "目标 canonical 非空时拒绝借用且不破坏正常投影");

        value = target(21);
        value.长枪 = equipment("版本长枪", 1, "", []);
        RuntimeEquipmentProjection.beginCanonical(value);
        var wrongOwner:Object = owner(value, "长枪");
        wrongOwner.版本号 = 20;
        rejected = RuntimeEquipmentProjection.reserveEmptySlotAlias(wrongOwner, "刀");
        check(rejected == null && RuntimeEquipmentProjection.completeCanonical(value),
            "owner version 不匹配时拒绝借用");

        value = target(211);
        value.长枪 = equipment("提交后版本漂移长枪", 1, "", []);
        RuntimeEquipmentProjection.beginCanonical(value);
        var versionIntent:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            owner(value, "长枪"), "刀");
        RuntimeEquipmentProjection.commitSlotAlias(versionIntent);
        value.version = 212;
        check(!RuntimeEquipmentProjection.completeCanonical(value),
            "commit 后单位 version 漂移使整轮投影 fail-closed");

        value = target(22);
        value.长枪 = equipment("冲突长枪", 1, "", []);
        RuntimeEquipmentProjection.beginCanonical(value);
        var first:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            owner(value, "长枪"), "刀");
        var second:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            owner(value, "长枪"), "刀");
        RuntimeEquipmentProjection.commitSlotAlias(first);
        check(first != null && second == null
                && !RuntimeEquipmentProjection.completeCanonical(value),
            "同一目标槽多 owner 竞争使本轮投影 fail-closed");

        value = target(23);
        value.长枪 = equipment("回滚长枪", 1, "", []);
        RuntimeEquipmentProjection.beginCanonical(value);
        var cancellable:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            owner(value, "长枪"), "刀");
        value.刀 = "fixture-configured";
        RuntimeEquipmentProjection.cancelSlotAlias(cancellable);
        check(value.刀 == null && RuntimeEquipmentProjection.completeCanonical(value),
            "配置阶段失败可取消 reservation 并恢复 canonical 空槽");

        value = target(24);
        value.长枪 = equipment("过期长枪", 1, "", []);
        RuntimeEquipmentProjection.beginCanonical(value);
        var stale:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            owner(value, "长枪"), "刀");
        RuntimeEquipmentProjection.beginCanonical(value);
        check(!RuntimeEquipmentProjection.commitSlotAlias(stale)
                && RuntimeEquipmentProjection.completeCanonical(value)
                && value.刀 == null,
            "新 generation 使旧 intent lease 失效且不能覆盖新投影");

        value = target(25);
        value.长枪 = equipment("未提交长枪", 1, "", []);
        refs = refsOf(value);
        RuntimeEquipmentProjection.beginCanonical(value);
        RuntimeEquipmentProjection.reserveEmptySlotAlias(owner(value, "长枪"), "刀");
        check(!RuntimeEquipmentProjection.completeCanonical(value)
                && RuntimeEquipmentProjection.getStatus(value, refs)
                    == RuntimeEquipmentProjection.STATUS_INVALID,
            "遗留未提交 reservation 会使 applied projection 失效");
    }
}
