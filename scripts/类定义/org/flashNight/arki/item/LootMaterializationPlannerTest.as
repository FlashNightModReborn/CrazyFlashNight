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
            testQuantityPairContract();
            testSharedRuleValidationForDirectDrops();
            testQuantitySpanBoundary();
            testLuckBonusFrozenBeforeRetry();
            testRollRollbackAndResume();
            testCreateResumeKeepsExactItem();
            testAddResumeIsIdempotent();
            testTotalsCommitRollback();
            testInformationCapFilter();
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
            informationMaxValueDict:ItemUtil.informationMaxValueDict,
            collectibles:_root.收集品栏,
            dropPRDEngine:_root.dropPRDEngine,
            passive:_root.主角被动技能,
            rngState:rng.captureState()
        };
        ItemUtil.itemDataDict = {};
        ItemUtil.informationMaxValueDict = {};
        _root.收集品栏 = undefined;
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
        ItemUtil.informationMaxValueDict = _backup.informationMaxValueDict;
        _root.收集品栏 = _backup.collectibles;
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

    private static function testQuantityPairContract():Void {
        resetEntropy(1201, {});
        var minOnly:Object = {名字:ITEM, 最小数量:1};
        var maxOnly:Object = {名字:ITEM, 最大数量:1};
        var malformed:Object = {名字:ITEM, 最小数量:"1", 最大数量:2};
        var unparsable:Object = {名字:ITEM, 最小数量:"bad", 最大数量:2};
        var explicitUndefined:Object = {名字:ITEM};
        explicitUndefined.最小数量 = undefined;
        explicitUndefined.最大数量 = undefined;
        var before:Number = LinearCongruentialEngine.getInstance().captureState();
        var minOnlyResult:Object = LootMaterializationPlanner.materialize(
            target("mat.min-only", minOnly));
        var maxOnlyResult:Object = LootMaterializationPlanner.materialize(
            target("mat.max-only", maxOnly));
        var malformedResult:Object = LootMaterializationPlanner.materialize(
            target("mat.numeric-string", malformed));
        var unparsableResult:Object = LootMaterializationPlanner.materialize(
            target("mat.unparsable", unparsable));
        var explicitUndefinedResult:Object = LootMaterializationPlanner.materialize(
            target("mat.explicit-undefined", explicitUndefined));
        check(!minOnlyResult.success && minOnlyResult.terminalFailure
                && minOnlyResult.error == "invalid_drop_rule"
                && !maxOnlyResult.success && maxOnlyResult.terminalFailure
                && maxOnlyResult.error == "invalid_drop_rule"
                && !malformedResult.success && malformedResult.terminalFailure
                && malformedResult.error == "invalid_drop_rule"
                && !unparsableResult.success && unparsableResult.terminalFailure
                && unparsableResult.error == "invalid_drop_rule"
                && !explicitUndefinedResult.success
                && explicitUndefinedResult.terminalFailure
                && explicitUndefinedResult.error == "invalid_drop_rule"
                && LinearCongruentialEngine.getInstance().captureState() == before,
            "数量仅允许两端同时缺省或同时提供严格数字；半缺省/字符串/显式 undefined 均在随机前 fail closed");
    }

    private static function testSharedRuleValidationForDirectDrops():Void {
        resetEntropy(1301, {});
        var defaultRule:Object = {名字:ITEM};
        var minOnly:Object = {名字:ITEM, 最小数量:1};
        var numericString:Object = {名字:ITEM, 最小数量:"1", 最大数量:2};
        var invalidProbability:Object = {名字:ITEM, 概率:0};
        var duplicate:Object = {名字:ITEM, 最小数量:1, 最大数量:1};
        var before:Number = LinearCongruentialEngine.getInstance().captureState();
        var accepted:Object = LootMaterializationPlanner.validateDropRules([defaultRule]);
        var minOnlyResult:Object = LootMaterializationPlanner.validateDropRules([minOnly]);
        var stringResult:Object = LootMaterializationPlanner.validateDropRules([numericString]);
        var probabilityResult:Object = LootMaterializationPlanner.validateDropRules(
            [invalidProbability]);
        var duplicateResult:Object = LootMaterializationPlanner.validateDropRules(
            [duplicate, duplicate]);
        check(accepted.success && accepted.ruleCount == 1
                && !minOnlyResult.success && minOnlyResult.error == "invalid_drop_rule"
                && !stringResult.success && stringResult.error == "invalid_drop_rule"
                && !probabilityResult.success
                && probabilityResult.error == "invalid_drop_probability"
                && !duplicateResult.success
                && duplicateResult.error == "duplicate_drop_rule_reference"
                && !defaultRule.hasOwnProperty("最小数量")
                && !defaultRule.hasOwnProperty("最大数量")
                && LinearCongruentialEngine.getInstance().captureState() == before,
            "direct/break 复用 Web 同一规则校验；失败不归一源数据且不推进随机");
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

    private static function testInformationCapFilter():Void {
        var intel:String = "S1物化测试情报";
        ItemUtil.itemDataDict[intel] = {
            name:intel, displayname:intel, icon:intel, type:"收集品", use:"情报",
            price:0, description:"物化测试情报", data:{level:1}
        };
        ItemUtil.informationMaxValueDict[intel] = 1;
        var owned:Object = {};
        _root.收集品栏 = {
            情报:{
                getValue:function(name:String):Number {
                    var value:Number = Number(owned[name]);
                    return isNaN(value) ? 0 : value;
                }
            }
        };

        resetEntropy(6001, {});
        owned[intel] = 1;
        var capped:Object = {名字:intel, 最小数量:1, 最大数量:1, 总数:3};
        var normal:Object = {名字:ITEM, 最小数量:1, 最大数量:1, 总数:2};
        var cappedResult:Object = LootMaterializationPlanner.materialize(
            target("mat.intel-capped", [capped, normal]));
        var cappedEntry:Object = cappedResult.entries[0];
        check(cappedResult.success && cappedResult.inventory.size() == 1
                && cappedEntry.hit && cappedEntry.quantity == 1
                && cappedEntry.generateQuantity == 0 && cappedEntry.item == null
                && cappedResult.inventory.getItem(String(cappedEntry.slot)) == null
                && capped.总数 == 2 && normal.总数 == 1,
            "已满零价情报不生成：槽位留空，掷骰量仍按原语义扣减 总数，非情报规则照常生成");

        resetEntropy(6002, {});
        ItemUtil.informationMaxValueDict[intel] = 5;
        owned[intel] = 3;
        var partial:Object = {名字:intel, 最小数量:4, 最大数量:4, 总数:4};
        var partialResult:Object = LootMaterializationPlanner.materialize(
            target("mat.intel-partial", partial));
        var partialEntry:Object = partialResult.entries[0];
        check(partialResult.success && partialResult.inventory.size() == 1
                && partialEntry.quantity == 4 && partialEntry.generateQuantity == 2
                && partialResult.inventory.getItem(String(partialEntry.slot)).value == 2,
            "情报剩余容量 2 时按请求 4 截断为 2 生成");

        resetEntropy(6003, {});
        owned[intel] = 0;
        var full:Object = {名字:intel, 最小数量:2, 最大数量:2, 总数:2};
        var fullResult:Object = LootMaterializationPlanner.materialize(
            target("mat.intel-full", full));
        var fullEntry:Object = fullResult.entries[0];
        check(fullResult.success && fullResult.inventory.size() == 1
                && fullEntry.generateQuantity == 2
                && fullResult.inventory.getItem(String(fullEntry.slot)).value == 2,
            "情报容量充足时请求量全额生成");
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
