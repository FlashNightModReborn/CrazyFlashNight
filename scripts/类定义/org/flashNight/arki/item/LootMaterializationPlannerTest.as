import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.LootMaterializationPlanner;
import org.flashNight.naki.PseudoRandom.PseudoRandomDistribution;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/** Web 箱物化 journal 的 roll/create/add/commit 故障注入回归。 */
class org.flashNight.arki.item.LootMaterializationPlannerTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _backup:Object;
    private static var ITEM:String = "S1物化测试补给";

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== LootMaterializationPlannerTest start ===");
        installWorld();
        try {
            testValidationBeforeRandomAdvance();
            testQuantitySpanBoundary();
            testLuckBonusFrozenBeforeRetry();
            testRollRollbackAndResume();
            testCreateResumeKeepsExactItem();
            testAddResumeIsIdempotent();
            testTotalsCommitRollback();
        } finally {
            restoreWorld();
        }
        trace("LootMaterializationPlannerTest Tests Passed: " + _passed);
        trace("LootMaterializationPlannerTest Tests Failed: " + _failed);
        trace("=== LootMaterializationPlannerTest end ===");
    }

    private static function installWorld():Void {
        var rng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        _backup = {
            itemDataDict:ItemUtil.itemDataDict,
            dropPRDEngine:_root.dropPRDEngine,
            passive:_root.主角被动技能,
            rngState:rng.captureState()
        };
        ItemUtil.itemDataDict = {};
        ItemUtil.itemDataDict[ITEM] = {
            name:ITEM, displayname:ITEM, icon:ITEM, type:"消耗品", use:"道具",
            price:1, description:"物化测试", data:{level:1}
        };
        _root.主角被动技能 = {};
        resetEntropy(1357911, {});
    }

    private static function restoreWorld():Void {
        LootMaterializationPlanner.testOnlyReset();
        ItemUtil.itemDataDict = _backup.itemDataDict;
        _root.dropPRDEngine = _backup.dropPRDEngine;
        _root.主角被动技能 = _backup.passive;
        LinearCongruentialEngine.getInstance().restoreState(_backup.rngState);
    }

    private static function resetEntropy(seed:Number, state:Object):Void {
        LootMaterializationPlanner.testOnlyReset();
        LinearCongruentialEngine.getInstance().restoreState(seed);
        _root.dropPRDEngine = new PseudoRandomDistribution(state);
    }

    private static function rule(probability, total:Number):Object {
        var value:Object = {名字:ITEM, 最小数量:1, 最大数量:2, 总数:total};
        if (probability != undefined) value.概率 = probability;
        return value;
    }

    private static function target(id:String, drops:Object):Object {
        return {
            presetName:"装备箱", row:2, col:4, 掉落物:drops
        };
    }

    private static function testValidationBeforeRandomAdvance():Void {
        resetEntropy(1001, {});
        var valid:Object = rule(undefined, 5);
        var invalid:Object = rule(0, 5);
        var fixture:Object = target("mat.validation", [valid, invalid]);
        var before:Number = LinearCongruentialEngine.getInstance().captureState();
        var result:Object = LootMaterializationPlanner.materialize(fixture);
        var state:Object = _root.dropPRDEngine.getState();
        var validationKeptEntropy:Boolean = LinearCongruentialEngine.getInstance().captureState() == before;
        var oversized:Object = rule(undefined, 5);
        oversized.最小数量 = 9007199254740992;
        oversized.最大数量 = 9007199254740992;
        delete oversized.总数;
        var oversizedResult:Object = LootMaterializationPlanner.materialize(
            target("mat.oversized", oversized));

        resetEntropy(1003, {});
        var defaultQuantity:Object = {名字:ITEM};
        var oneSlot:Object = target("mat.default-quantity", defaultQuantity);
        oneSlot.row = 1;
        oneSlot.col = 1;
        var defaulted:Object = LootMaterializationPlanner.materialize(oneSlot);

        resetEntropy(1004, {});
        var boundaryTarget:Object = target(
            "mat.capacity-boundary", {名字:ITEM, 最小数量:1, 最大数量:1});
        boundaryTarget.row = 8;
        boundaryTarget.col = 8;
        var boundary:Object = LootMaterializationPlanner.materialize(boundaryTarget);

        resetEntropy(1002, {});
        var first:Object = rule(undefined, 5);
        var second:Object = rule(undefined, 6);
        var frozenDrops:Array = [first, second];
        var frozenTarget:Object = target("mat.frozen", frozenDrops);
        LootMaterializationPlanner.testOnlyFailNext("after_create", 1);
        var retryable:Object = LootMaterializationPlanner.materialize(frozenTarget);
        frozenDrops[0] = second;
        frozenDrops[1] = first;
        var changed:Object = LootMaterializationPlanner.materialize(frozenTarget);
        check(!result.success && result.error == "invalid_drop_probability"
                && result.terminalFailure && validationKeptEntropy
                && ownKeyCount(state) == 0 && valid.总数 == 5 && fixture.掉落物 != null
                && !oversizedResult.success && oversizedResult.error == "invalid_drop_rule"
                && defaulted.success && defaulted.capacity == 1
                && defaulted.inventory.capacity == 1 && defaulted.inventory.size() == 1
                && defaulted.entries[0].quantity == 1
                && boundary.success && boundary.capacity == 64
                && boundary.inventory.capacity == 64 && boundary.inventory.size() == 1
                && retryable.error == "materialization_input_changed"
                && changed === retryable && changed.terminalFailure,
            "校验先于随机推进并拒绝超 safe-int；缺省数量归一为 1；接受 64 格能力边界；retry 冻结源数组顺序");
    }

    private static function testQuantitySpanBoundary():Void {
        resetEntropy(1501, {});
        var boundary:Object = rule(undefined, 2147483647);
        boundary.最小数量 = 1;
        boundary.最大数量 = 2147483647;
        var boundaryTarget:Object = target("mat.span-boundary", boundary);
        LootMaterializationPlanner.testOnlyFailNext("after_sample", -1);
        var accepted:Object = LootMaterializationPlanner.materialize(boundaryTarget);

        var tooWide:Object = rule(undefined, 2147483648);
        tooWide.最小数量 = 1;
        tooWide.最大数量 = 2147483648;
        var rejected:Object = LootMaterializationPlanner.materialize(
            target("mat.span-too-wide", tooWide));
        check(!accepted.success && accepted.error == "injected_after_sample"
                && !accepted.terminalFailure
                && !rejected.success && rejected.terminalFailure
                && rejected.error == "invalid_drop_quantity_span",
            "AVM1 random span 接受 2^31-1 边界并在 2^31 时于随机推进前 fail-closed");
    }

    private static function testLuckBonusFrozenBeforeRetry():Void {
        resetEntropy(1601, {});
        _root.主角被动技能 = {逆向:{启用:true, 等级:2}};
        var observed:Array = [];
        var state:Object = {};
        _root.dropPRDEngine = {
            getState:function():Object { return state; },
            roll:function(key:String, effectiveP:Number):Boolean {
                observed.push(effectiveP);
                return true;
            }
        };
        var source:Object = rule(50, 5);
        var fixture:Object = target("mat.luck-frozen", source);
        LootMaterializationPlanner.testOnlyFailNext("after_sample", -1);
        var failed:Object = LootMaterializationPlanner.materialize(fixture);
        var failedError:String = String(failed.error);
        var captured:Number = Number(failed.luckBonus);
        _root.主角被动技能.逆向.等级 = 10;
        var resumed:Object = LootMaterializationPlanner.materialize(fixture);
        check(failedError == "injected_after_sample" && captured == 0.1
                && resumed.success && observed.length == 1
                && Math.abs(Number(observed[0]) - 0.55) < 0.0000001,
            "retry 使用计划前冻结的逆向 bonus/PRD 引擎，不读取后改角色幸运状态");
        _root.主角被动技能 = {};
    }

    private static function testRollRollbackAndResume():Void {
        var state:Object = {};
        var key:String = "资源箱|装备箱|" + ITEM;
        state[key] = 3;
        resetEntropy(2002, state);
        var source:Object = rule(50, 5);
        var fixture:Object = target("mat.roll", source);
        LootMaterializationPlanner.testOnlyFailNext("after_roll", 0);
        var failed:Object = LootMaterializationPlanner.materialize(fixture);
        var failedError:String = String(failed.error);
        var rollWasUnrecorded:Boolean = failed.entries[0].rollRecorded !== true;
        var prdWasRestored:Boolean = state[key] == 3;
        var seedAfterRollback:Number = LinearCongruentialEngine.getInstance().captureState();
        var resumed:Object = LootMaterializationPlanner.materialize(fixture);
        var seedAfterCommit:Number = LinearCongruentialEngine.getInstance().captureState();
        var duplicate:Object = LootMaterializationPlanner.materialize(fixture);
        check(failedError == "injected_after_roll" && rollWasUnrecorded && prdWasRestored
                && failed.entries[0].rollRecorded === true
                && resumed === failed && resumed.success && resumed.inventory != null
                && duplicate === resumed && LinearCongruentialEngine.getInstance().captureState() == seedAfterCommit
                && seedAfterRollback != seedAfterCommit && source.总数 >= 3 && source.总数 <= 5,
            "roll 边界失败回滚 PRD/RNG 后可重入；最终 journal 命中记录只提交一次");
    }

    private static function testCreateResumeKeepsExactItem():Void {
        resetEntropy(3003, {});
        var source:Object = rule(undefined, 5);
        var fixture:Object = target("mat.create", source);
        LootMaterializationPlanner.testOnlyFailNext("after_create", 0);
        var failed:Object = LootMaterializationPlanner.materialize(fixture);
        var failedError:String = String(failed.error);
        var plannedItem:Object = failed.entries[0].item;
        var plannedQuantity:Number = failed.entries[0].quantity;
        var resumed:Object = LootMaterializationPlanner.materialize(fixture);
        check(failedError == "injected_after_create"
                && failed.entries[0].itemCreated && plannedItem != null
                && resumed.success && resumed.entries[0].item === plannedItem
                && resumed.inventory.getItem(String(resumed.entries[0].slot)) === plannedItem
                && source.总数 == 5 - plannedQuantity,
            "create 后故障保留 exact BaseItem；重试不重新创建且总数只扣一次");
    }

    private static function testAddResumeIsIdempotent():Void {
        resetEntropy(4004, {});
        var source:Object = rule(undefined, 6);
        var fixture:Object = target("mat.add", source);
        LootMaterializationPlanner.testOnlyFailNext("after_add", 0);
        var failed:Object = LootMaterializationPlanner.materialize(fixture);
        var failedError:String = String(failed.error);
        var entry:Object = failed.entries[0];
        var item:Object = failed.inventory.getItem(String(entry.slot));
        var sizeAfterFailure:Number = failed.inventory.size();
        var resumed:Object = LootMaterializationPlanner.materialize(fixture);
        var totalAfter:Number = source.总数;
        var duplicate:Object = LootMaterializationPlanner.materialize(fixture);
        check(failedError == "injected_after_add"
                && item === entry.item && sizeAfterFailure == 1
                && resumed.success && resumed.inventory.size() == 1
                && resumed.inventory.getItem(String(entry.slot)) === item
                && source.总数 == 6 - entry.quantity
                && duplicate === resumed && source.总数 == totalAfter,
            "add 后未记 applied 的故障由 exact slot/item 自愈，不复制物品、不重复扣总数");
    }

    private static function testTotalsCommitRollback():Void {
        resetEntropy(5005, {});
        var first:Object = rule(undefined, 7);
        var second:Object = rule(undefined, 9);
        var fixture:Object = target("mat.totals", [first, second]);
        LootMaterializationPlanner.testOnlyFailNext("during_totals", 0);
        var failed:Object = LootMaterializationPlanner.materialize(fixture);
        var failedError:String = String(failed.error);
        var totalsWereRolledBack:Boolean = first.总数 == 7 && second.总数 == 9;
        var firstQuantity:Number = failed.entries[0].quantity;
        var secondQuantity:Number = failed.entries[1].quantity;
        var resumed:Object = LootMaterializationPlanner.materialize(fixture);
        check(failedError == "totals_commit_failed" && totalsWereRolledBack
                && first.总数 == 7 - firstQuantity && second.总数 == 9 - secondQuantity
                && resumed.success && fixture.掉落物 == null
                && resumed.inventory.size() == 2,
            "总数批次故障先回滚，重试后两条规则与 source detach 一次提交");
    }

    private static function ownKeyCount(value:Object):Number {
        var count:Number = 0;
        for (var key:String in value) {
            if (typeof value.hasOwnProperty != "function" || value.hasOwnProperty(key)) count++;
        }
        return count;
    }

    private static function check(condition:Boolean, message:String):Void {
        if (condition) {
            _passed++;
            trace("PASS: " + message);
        } else {
            _failed++;
            trace("[TEST_FAIL] " + message);
        }
    }
}
