import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.PlayerAssetWireProjector;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.achievement.AchievementService;
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.arki.task.TaskPanelService;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/**
 * PlayerAssetTransaction 的提交回执契约测试。
 */
class org.flashNight.arki.item.PlayerAssetTransactionTest {

    private var testPassed:Number;
    private var testFailed:Number;

    public function PlayerAssetTransactionTest() {
        testPassed = 0;
        testFailed = 0;
    }

    public static function runAllTests():Void {
        var suite:PlayerAssetTransactionTest = new PlayerAssetTransactionTest();
        trace("=== PlayerAssetTransactionTest start ===");
        suite.testImplicitCommit();
        suite.testExplicitRollback();
        suite.testAggregateAndDirection();
        suite.testNestedCommit();
        suite.testEquipmentQuantitySemantics();
        suite.testOwnershipDeltaProjection();
        suite.testInvalidEffects();
        suite.testDetachedReceipt();
        suite.testProgressionExcluded();
        suite.testOperationScopedMerge();
        suite.testCurrencyDeltas();
        suite.testWireProjection();
        suite.testStrongSaveFinality();
        suite.testConsumerFailureIsolated();
        suite.testImplicitExceptionDoesNotPoisonStack();
        suite.testAcquireExceptionOwnsOnlyImplicitFrame();
        suite.testSubmitMissingSaveFailsBeforeWrite();
        suite.testSubmitListenerFaultCommitsExactPartialAndRecovers();
        suite.testAcquireItemAddedFaultRecoversDispatchAndFrame();
        suite.testAchievementListenerFaultLatchesClaimAndRecovers();
        suite.testQuestExactFinalityAndRecovery();
        suite.testTaskFinishPostCommitProjectionFailureResponds();
        suite.testExplicitExceptionSettlement();
        PlayerAssetTransaction.resetForTests();
        trace("PlayerAssetTransactionTest Tests Passed: " + suite.testPassed);
        trace("PlayerAssetTransactionTest Tests Failed: " + suite.testFailed);
        trace("=== PlayerAssetTransactionTest end ===");
    }

    private function captureInto(target:Array):Function {
        return function(receipt:Object):Void {
            target.push(receipt);
        };
    }

    private function testImplicitCommit():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        PlayerAssetTransaction.recordEffect("gain", "item", "急救包", 2,
            {source:"npc_shop_purchase", reason:"purchase"});

        assert(receipts.length == 1, "隐式事务只发布一张回执", "count=" + receipts.length);
        var receipt:Object = receipts[0];
        assert(receipt.version == 1, "提交回执显式携带 v1 版本");
        assert(receipt.effects.length == 1, "隐式事务包含唯一 effect", "effects=" + receipt.effects.length);
        assert(receipt.effects[0].direction == "gain", "获得方向被保留");
        assert(receipt.effects[0].source == "npc_shop_purchase", "来源被保留");
        assert(receipt.effects[0].count == 2, "正数 magnitude 被保留");
    }

    private function testExplicitRollback():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        var transaction:Object = PlayerAssetTransaction.begin(
            {source:"crafting", reason:"craft"});
        PlayerAssetTransaction.recordEffect("loss", "material", "强化石", 3, null);
        assert(receipts.length == 0, "显式事务提交前不发布");
        assert(PlayerAssetTransaction.rollback(transaction), "显式事务可以回滚");
        assert(receipts.length == 0, "回滚事务零播报");
        assert(PlayerAssetTransaction.current() == null, "回滚后事务栈为空");
    }

    private function testAggregateAndDirection():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        var transaction:Object = PlayerAssetTransaction.begin(
            {operationId:"craft-7", source:"crafting", reason:"craft"});
        PlayerAssetTransaction.recordEffect("loss", "material", "强化石", 2, null);
        PlayerAssetTransaction.recordEffect("loss", "material", "强化石", 3, null);
        PlayerAssetTransaction.recordEffect("gain", "item", "急救包", 1, null);
        var receipt:Object = PlayerAssetTransaction.commit(transaction);

        assert(receipts.length == 1, "复合事务只发布一次");
        assert(receipt.operationId == "craft-7", "调用方 operationId 被保留");
        assert(receipt.effects.length == 2, "同方向同资产聚合，反方向分离");
        assert(receipt.effects[0].count == 5, "重复材料损失在事务内精确聚合");
        assert(receipt.effects[1].direction == "gain", "产物获得与材料损失并存");
    }

    private function testNestedCommit():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        var outer:Object = PlayerAssetTransaction.begin(
            {source:"npc_shop_purchase", reason:"checkout"});
        var inner:Object = PlayerAssetTransaction.begin(
            {source:"npc_shop_purchase", reason:"purchase"});
        PlayerAssetTransaction.recordEffect("gain", "item", "绷带", 2, null);
        PlayerAssetTransaction.commit(inner);
        assert(receipts.length == 0, "内层提交只合并到外层");
        PlayerAssetTransaction.recordEffect("loss", "money", "金钱", 100, null);
        PlayerAssetTransaction.commit(outer);
        assert(receipts.length == 1, "最外层提交才发布");
        assert(receipts[0].effects.length == 2, "父事务收到内层 effect");
    }

    private function testEquipmentQuantitySemantics():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        var transaction:Object = PlayerAssetTransaction.begin(
            {source:"quest_reward", reason:"reward"});
        PlayerAssetTransaction.recordItems("gain", [
            {name:"测试装备", value:13, kind:"equip"},
            {name:"测试装备", value:2, kind:"equip", isQuantity:true}
        ], null);
        PlayerAssetTransaction.commit(transaction);

        assert(receipts[0].effects.length == 1, "同名装备 effect 聚合");
        assert(receipts[0].effects[0].count == 3,
            "装备强化值按一件、数量语法按件数解释");
    }

    private function testOwnershipDeltaProjection():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        PlayerAssetTransaction.recordItems("gain", [
            {name:"测试配件", value:5, kind:"material", ownershipDelta:2},
            {name:"归还配件", value:3, kind:"material", ownershipDelta:0}
        ], {source:"npc_shop_purchase", reason:"trade_commit"});

        assert(receipts.length == 1 && receipts[0].effects.length == 1,
            "纯位置迁移不生成获得 effect");
        assert(receipts[0].effects[0].count == 2,
            "复合写入只发布真实所有权增量");
    }

    private function testInvalidEffects():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        PlayerAssetTransaction.recordEffect("sideways", "item", "急救包", 1, null);
        PlayerAssetTransaction.recordEffect("gain", "item", "急救包", 0, null);
        PlayerAssetTransaction.recordEffect("loss", "item", "急救包", -1, null);
        PlayerAssetTransaction.recordEffect("gain", "item", "急救包", 1.5, null);
        assert(receipts.length == 0, "非法方向或 magnitude 不发布");
    }

    private function testDetachedReceipt():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        var entry:Object = {name:"能量电池", value:2, kind:"item"};
        var context:Object = {source:"skill_cost", reason:"skill"};
        PlayerAssetTransaction.recordItems("loss", [entry], context);
        entry.name = "被篡改";
        entry.value = 999;
        context.source = "被篡改";

        assert(receipts[0].effects[0].name == "能量电池", "回执不持有输入对象引用");
        assert(receipts[0].effects[0].count == 2, "回执数量不受输入后改写影响");
        assert(receipts[0].effects[0].source == "skill_cost", "回执上下文已脱离可变对象");
    }

    private function testProgressionExcluded():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        PlayerAssetTransaction.recordItems("gain", [
            {name:"经验值", value:500},
            {name:"技能点", value:3},
            {name:"金币", value:20}
        ], {source:"level_reward", reason:"reward"});

        assert(receipts.length == 1, "含物资的进度奖励仍发布一张回执");
        assert(receipts[0].effects.length == 1, "经验与技能点不混入物资聚合");
        assert(receipts[0].effects[0].kind == "money", "金币归一为货币 kind");
        assert(receipts[0].effects[0].name == "金钱", "金币展示名归一为金钱");
    }

    private function testOperationScopedMerge():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        var transaction:Object = PlayerAssetTransaction.begin(
            {operationId:"reload-11", source:"reload", reason:"reload",
                mergeScope:"operation"});
        PlayerAssetTransaction.recordEffect("loss", "item", "步枪弹匣", 1, null);
        PlayerAssetTransaction.commit(transaction);

        assert(receipts[0].effects[0].mergeScope == "reload-11",
            "operation mergeScope 绑定实际事务 id");
        assert(receipts[0].source == "reload", "回执保留事务级来源");
        assert(PlayerAssetTransaction.getLastCommittedReceiptForTest().operationId == "reload-11",
            "最后提交回执测试钩子返回 detached receipt");
    }

    private function testCurrencyDeltas():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        PlayerAssetTransaction.recordCurrencyDeltas(125, -7,
            {source:"npc_shop_purchase", reason:"checkout"});

        assert(receipts.length == 1, "两种货币变化共用一张回执");
        assert(receipts[0].effects.length == 2, "金钱与K点分别成为 effect");
        assert(receipts[0].effects[0].direction == "gain"
                && receipts[0].effects[0].count == 125,
            "正数 delta 归一为获得的正数 magnitude");
        assert(receipts[0].effects[1].direction == "loss"
                && receipts[0].effects[1].count == 7,
            "负数 delta 归一为失去的正数 magnitude");
        assert(receipts[0].effects[1].kind == "kpoint",
            "K点保留独立的货币 kind");
    }

    private function testWireProjection():Void {
        var message:Object = PlayerAssetWireProjector.buildMessage({
            version:1,
            direction:"loss",
            kind:"item",
            itemKey:"5.56mm弹匣",
            name:"步枪弹匣",
            count:1,
            source:"reload",
            icon:"步枪弹匣",
            tier:"二阶",
            operationId:"reload-31",
            mergeScope:"reload-31",
            reason:"reload",
            eliteLevel:2
        });
        assert(message.v == 1, "wire payload 保留 v1 版本");
        assert(message.direction == "loss" && message.count == 1,
            "wire payload 以正数 magnitude 表达 loss");
        assert(message.itemKey == "5.56mm弹匣" && message.name == "步枪弹匣",
            "wire payload 分离权威物品键与展示名");
        assert(message.operationId == "reload-31"
                && message.mergeScope == "reload-31" && message.reason == "reload",
            "wire payload 保留幂等与合并身份");
        assert(message.eliteLevel == undefined,
            "非击杀 payload 不误带精英等级");

        var consumed:Array = [];
        var failedIndexes:Array = [];
        PlayerAssetWireProjector.forEachEffect({effects:[
            {name:"坏投影"}, {name:"后续事实"}
        ]}, function(effect:Object, index:Number):Void {
            if (index == 0) throw "projection_failed";
            consumed.push(effect.name);
        }, function(error, index:Number):Void {
            failedIndexes.push(index);
        });
        assert(failedIndexes.length == 1 && failedIndexes[0] == 0,
            "逐 effect 投影单独报告失败下标");
        assert(consumed.length == 1 && consumed[0] == "后续事实",
            "单个 effect 异常不吞掉后续已提交事实");
    }

    private function testStrongSaveFinality():Void {
        PlayerAssetTransaction.resetForTests();
        var saveCount:Number = 0;
        var sequence:Array = [];
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            sequence.push("receipt");
        });
        PlayerAssetTransaction.setTestStrongSaveSink(function():Boolean {
            saveCount++;
            sequence.push("save");
            return true;
        });

        var transaction:Object = PlayerAssetTransaction.begin(
            {source:"quest_reward", reason:"quest_complete"});
        PlayerAssetTransaction.requestStrongSave();
        PlayerAssetTransaction.recordEffect("gain", "money", "金钱", 10, null);
        assert(saveCount == 0, "事务内升级不会提前强制存盘");
        PlayerAssetTransaction.commit(transaction);
        assert(saveCount == 1, "最外层领域提交后只强制存盘一次");
        assert(sequence.length == 2 && sequence[0] == "save"
                && sequence[1] == "receipt",
            "升级强存盘先于可选消费者回执");
        assert(transaction.strongSaveFlushed === true,
            "事务记录强存盘已经完成");

        var rolledBack:Object = PlayerAssetTransaction.begin(
            {source:"quest_reward", reason:"invalid_reward"});
        PlayerAssetTransaction.requestStrongSave();
        PlayerAssetTransaction.rollback(rolledBack);
        assert(saveCount == 1, "回滚事务丢弃尚未生效的强存盘请求");

        var outer:Object = PlayerAssetTransaction.begin(
            {source:"achievement_reward", reason:"claim"});
        var inner:Object = PlayerAssetTransaction.begin(
            {source:"achievement_reward", reason:"reward"});
        PlayerAssetTransaction.requestStrongSave();
        PlayerAssetTransaction.commit(inner);
        assert(saveCount == 1, "嵌套提交只把强存盘请求交给父事务");
        PlayerAssetTransaction.commit(outer);
        assert(saveCount == 2, "父事务最终提交后执行嵌套强存盘请求");

        PlayerAssetTransaction.requestStrongSave();
        assert(saveCount == 3, "无事务升级保持立即强制存盘行为");

        PlayerAssetTransaction.setTestStrongSaveSink(function():Boolean {
            saveCount++;
            return false;
        });
        var failedSave:Object = PlayerAssetTransaction.begin(
            {source:"quest_reward", reason:"save_retry"});
        PlayerAssetTransaction.requestStrongSave();
        PlayerAssetTransaction.recordEffect("gain", "money", "金钱", 1, null);
        PlayerAssetTransaction.commit(failedSave);
        assert(failedSave.strongSaveFlushed === false,
            "flushNow false 不会被误标为 durable success");
        assert(saveCount == 4,
            "强存盘失败只执行一次并交给既有 dirty 重试链");

        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        PlayerAssetTransaction.setTestStrongSaveSink(function() {
            throw "save_failed";
        });
        var thrownSave:Object = PlayerAssetTransaction.begin(
            {source:"quest_reward", reason:"save_exception"});
        PlayerAssetTransaction.requestStrongSave();
        PlayerAssetTransaction.recordEffect("gain", "money", "金钱", 2, null);
        PlayerAssetTransaction.commit(thrownSave);
        assert(PlayerAssetTransaction.current() == null,
            "强存盘异常不泄漏事务栈");
        assert(thrownSave.strongSaveFlushed === false,
            "强存盘异常保留为未耐久状态");
        assert(receipts.length == 1 && receipts[0].effects[0].count == 2,
            "强存盘异常不吞掉已经提交的资产回执");
    }

    private function testConsumerFailureIsolated():Void {
        PlayerAssetTransaction.resetForTests();
        PlayerAssetTransaction.setTestSink(function(receipt:Object):Void {
            throw "consumer_failed";
        });

        PlayerAssetTransaction.recordEffect("gain", "item", "急救包", 1,
            {source:"pickup", reason:"pickup"});

        assert(PlayerAssetTransaction.current() == null,
            "消费者异常不泄漏事务栈");
        var committed:Object = PlayerAssetTransaction.getLastCommittedReceiptForTest();
        assert(committed != null && committed.effects.length == 1,
            "消费者异常不撤销已提交回执");
        assert(committed.effects[0].name == "急救包",
            "消费者故障时仍保留权威变化事实");
    }

    private function testImplicitExceptionDoesNotPoisonStack():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));

        var poison:Object = {};
        poison.addProperty("name", function() {
            throw "bad_asset_name";
        }, null);
        var threw:Boolean = false;
        try {
            PlayerAssetTransaction.recordItems("gain", [poison],
                {source:"pickup", reason:"bad_fixture"});
        } catch (error) {
            threw = true;
        }

        assert(threw, "隐式事务保留原始输入异常，不静默伪装成功");
        assert(PlayerAssetTransaction.current() == null,
            "隐式事务中途异常会立即清理自身栈帧");
        assert(receipts.length == 0, "失败的隐式事务不发布部分回执");

        PlayerAssetTransaction.recordEffect("gain", "item", "后续急救包", 1,
            {source:"pickup", reason:"recovery"});
        assert(receipts.length == 1
                && receipts[0].effects[0].name == "后续急救包",
            "异常后的下一条隐式事务仍可独立提交");
    }

    private function testAcquireExceptionOwnsOnlyImplicitFrame():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));

        var oldInventory:Object = _root.物品栏;
        var oldCollections:Object = _root.收集品栏;
        var oldSave:Object = _root.存档系统;
        var oldMoney = _root.金钱;
        var oldKpoint = _root.虚拟币;
        var emptyInventory:Object = {
            getIndexes:function():Array { return []; },
            getItemArray:function():Array { return []; },
            getVacancies:function(count:Number):Array { return []; }
        };
        var throwKpointSetter:Function = function(value:Number):Void {
            throw "acquire_kpoint_write_failed";
        };
        var fixedKpointGetter:Function = function():Number { return 50; };

        try {
            _root.物品栏 = {
                装备栏:{getItem:function(key:String) { return null; }},
                药剂栏:emptyInventory,
                背包:emptyInventory
            };
            _root.收集品栏 = {材料:{}, 情报:{}};
            _root.存档系统 = {dirtyMark:false};
            _root.金钱 = 100;
            delete _root.虚拟币;
            _root.addProperty("虚拟币", fixedKpointGetter, throwKpointSetter);

            var implicitError = null;
            try {
                ItemUtil.acquire([
                    {name:"金币", value:5},
                    {name:"K点", value:1}
                ], {source:"pickup", reason:"implicit_acquire_failure"});
            } catch (error) {
                implicitError = error;
            }
            assert(implicitError == "acquire_kpoint_write_failed",
                "acquire 隐式事务原样传播首个权威写后异常");
            assert(PlayerAssetTransaction.current() == null,
                "acquire 中途异常只清理自身隐式事务栈帧");
            assert(_root.金钱 == 105 && _root.存档系统.dirtyMark === true,
                "acquire 在首写前标脏，后续异常不会留下未标脏的部分权威状态");
            assert(receipts.length == 1 && receipts[0].effects.length == 1
                    && receipts[0].effects[0].name == "金钱"
                    && receipts[0].effects[0].count == 5
                    && receipts[0].effects[0].kind == "money",
                "acquire 中途异常只发布已实写金币，未发生 K点不进 receipt");

            delete _root.虚拟币;
            _root.虚拟币 = 50;
            _root.存档系统.dirtyMark = false;
            var outer:Object = PlayerAssetTransaction.begin(
                {source:"crafting", reason:"explicit_outer"});
            PlayerAssetTransaction.recordEffect("loss", "material", "外层既有材料", 1,
                {source:"crafting", reason:"explicit_outer"});
            delete _root.虚拟币;
            _root.addProperty("虚拟币", fixedKpointGetter, throwKpointSetter);
            var explicitError = null;
            try {
                ItemUtil.acquire([
                    {name:"金币", value:5},
                    {name:"K点", value:1}
                ], {source:"crafting", reason:"explicit_acquire_failure"});
            } catch (outerError) {
                explicitError = outerError;
            }
            assert(explicitError == "acquire_kpoint_write_failed"
                    && PlayerAssetTransaction.current() === outer
                    && outer.state == "open",
                "acquire 异常不越权回滚调用方显式外层事务");
            assert(outer.effects.length == 2
                    && outer.effects[0].name == "外层既有材料"
                    && outer.effects[1].name == "金钱"
                    && outer.effects[1].count == 5
                    && receipts.length == 1
                    && _root.金钱 == 110 && _root.存档系统.dirtyMark === true,
                "显式外层保留既有 effect 与已实写金币，不注入未发生 K点");
            assert(PlayerAssetTransaction.rollback(outer)
                    && PlayerAssetTransaction.current() == null,
                "显式领域调用方仍拥有外层事务的恢复与回滚决定权");

            delete _root.虚拟币;
            _root.虚拟币 = 50;
            _root.存档系统.dirtyMark = false;
            var recovered:Boolean = ItemUtil.acquire(
                [{name:"金币", value:1}],
                {source:"pickup", reason:"post_failure_recovery"});
            assert(recovered && PlayerAssetTransaction.current() == null
                    && receipts.length == 2
                    && receipts[1].effects.length == 1
                    && receipts[1].effects[0].name == "金钱"
                    && receipts[1].effects[0].count == 1,
                "异常后的下一次 acquire 仍能建立、提交并清空独立隐式事务");
        } finally {
            PlayerAssetTransaction.resetForTests();
            delete _root.虚拟币;
            _root.虚拟币 = oldKpoint;
            _root.金钱 = oldMoney;
            _root.物品栏 = oldInventory;
            _root.收集品栏 = oldCollections;
            _root.存档系统 = oldSave;
        }
    }

    private function testSubmitMissingSaveFailsBeforeWrite():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        var oldInventory:Object = _root.物品栏;
        var oldCollections:Object = _root.收集品栏;
        var oldSave:Object = _root.存档系统;
        var bag:ArrayInventory = new ArrayInventory({}, 4);
        var drugs:ArrayInventory = new ArrayInventory({}, 4);
        bag.add(0, new BaseItem("无存档扣除物", 2, 1));

        try {
            _root.物品栏 = {
                装备栏:{getItem:function(key:String) { return null; }},
                药剂栏:drugs,
                背包:bag
            };
            _root.收集品栏 = {材料:{}, 情报:{}};
            delete _root.存档系统;

            var submitError = null;
            try {
                ItemUtil.submit([{name:"无存档扣除物", value:1}],
                    {source:"quest_turn_in", reason:"missing_save_system"});
            } catch (error) {
                submitError = error;
            }
            assert(submitError != null,
                "submit 在存档系统缺失时于首个资产写前 fail-fast");
            assert(bag.getItem("0") != null && bag.getItem("0").value == 2,
                "存档系统缺失不会留下未标脏的真实扣除");
            assert(PlayerAssetTransaction.current() == null && receipts.length == 0,
                "首写前失败会清理隐式 frame 且不发布幽灵 loss");
        } finally {
            PlayerAssetTransaction.resetForTests();
            _root.物品栏 = oldInventory;
            _root.收集品栏 = oldCollections;
            _root.存档系统 = oldSave;
        }
    }

    private function testSubmitListenerFaultCommitsExactPartialAndRecovers():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));

        var oldInventory:Object = _root.物品栏;
        var oldCollections:Object = _root.收集品栏;
        var oldSave:Object = _root.存档系统;
        var bag:ArrayInventory = new ArrayInventory({}, 4);
        var drugs:ArrayInventory = new ArrayInventory({}, 4);
        bag.add(0, new BaseItem("监听扣除物", 3, 1));
        bag.add(1, new BaseItem("后续独立物", 2, 1));
        bag.add(2, new BaseItem("监听移除物", 1, 1));
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__assetSubmitListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        bag.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemValueChanged", function():Void {
            throw "submit_listener_failed";
        });

        try {
            _root.物品栏 = {
                装备栏:{getItem:function(key:String) { return null; }},
                药剂栏:drugs,
                背包:bag
            };
            _root.收集品栏 = {材料:{}, 情报:{}};
            _root.存档系统 = {dirtyMark:false};

            var submitError = null;
            try {
                ItemUtil.submit([{name:"监听扣除物", value:1}],
                    {source:"quest_turn_in", reason:"listener_fault"});
            } catch (error) {
                submitError = error;
            }
            assert(submitError == "submit_listener_failed",
                "submit 保留同步监听器 let-it-crash 原始异常");
            assert(bag.getItem("0").value == 2 && _root.存档系统.dirtyMark === true,
                "submit 在监听器可见首写前标脏并保留已经发生的扣除");
            assert(PlayerAssetTransaction.current() == null,
                "监听器异常后的隐式 submit frame 已完成清栈");
            assert(receipts.length == 1 && receipts[0].effects.length == 1
                    && receipts[0].effects[0].direction == "loss"
                    && receipts[0].effects[0].name == "监听扣除物"
                    && receipts[0].effects[0].count == 1,
                "listener-fault receipt 只包含 before/after 证明的真实扣除");

            bag.setDispatcher(null);
            dispatcher = new LifecycleEventDispatcher(holder);
            bag.setDispatcher(dispatcher);
            dispatcher.subscribe("ItemRemoved", function():Void {
                throw "submit_removed_listener_failed";
            });
            _root.存档系统.dirtyMark = false;
            var removedError = null;
            try {
                ItemUtil.submit([{name:"监听移除物", value:1}],
                    {source:"quest_turn_in", reason:"removed_listener_fault"});
            } catch (removeError) {
                removedError = removeError;
            }
            var repairedIndexes:Array = bag.getIndexes();
            assert(removedError == "submit_removed_listener_failed"
                    && bag.getItem("2") == null
                    && repairedIndexes.length == 2
                    && repairedIndexes[0] == 0 && repairedIndexes[1] == 1
                    && _root.存档系统.dirtyMark === true
                    && PlayerAssetTransaction.current() == null,
                "ItemRemoved 监听器异常保留实扣并立即修复派生索引/事务栈");
            assert(receipts.length == 2 && receipts[1].effects.length == 1
                    && receipts[1].effects[0].direction == "loss"
                    && receipts[1].effects[0].name == "监听移除物"
                    && receipts[1].effects[0].count == 1,
                "ItemRemoved fault receipt 只包含已真实移除的一件物品");

            bag.setDispatcher(null);
            _root.存档系统.dirtyMark = false;
            var recovered:Boolean = ItemUtil.submit(
                [{name:"后续独立物", value:1}],
                {source:"skill_cost", reason:"post_listener_recovery"});
            assert(recovered && bag.getItem("1").value == 1
                    && _root.存档系统.dirtyMark === true
                    && PlayerAssetTransaction.current() == null,
                "监听器故障后的下一次 submit 独立写入、标脏并清栈");
            assert(receipts.length == 3 && receipts[2].effects.length == 1
                    && receipts[2].effects[0].name == "后续独立物"
                    && receipts[2].effects[0].source == "skill_cost",
                "下一事务不与故障 frame 的 effect 合并");
        } finally {
            bag.setDispatcher(null);
            holder.removeMovieClip();
            PlayerAssetTransaction.resetForTests();
            _root.物品栏 = oldInventory;
            _root.收集品栏 = oldCollections;
            _root.存档系统 = oldSave;
        }
    }

    private function testAcquireItemAddedFaultRecoversDispatchAndFrame():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        var oldInventory:Object = _root.物品栏;
        var oldCollections:Object = _root.收集品栏;
        var oldSave:Object = _root.存档系统;
        var oldItemData:Object = ItemUtil.itemDataDict;
        var oldEquipment:Object = ItemUtil.equipmentDict;
        var oldMaterials:Object = ItemUtil.materialDict;
        var oldInformation:Object = ItemUtil.informationMaxValueDict;
        var bag:ArrayInventory = new ArrayInventory({}, 4);
        var drugs:ArrayInventory = new ArrayInventory({}, 4);
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__assetAcquireListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        bag.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemAdded", function():Void {
            throw "acquire_item_added_failed";
        });

        try {
            ItemUtil.itemDataDict = {监听获得物:{name:"监听获得物", use:"消耗品"}};
            ItemUtil.equipmentDict = {};
            ItemUtil.materialDict = {};
            ItemUtil.informationMaxValueDict = {};
            _root.物品栏 = {
                装备栏:{getItem:function(key:String) { return null; }},
                药剂栏:drugs,
                背包:bag
            };
            _root.收集品栏 = {材料:{}, 情报:{}};
            _root.存档系统 = {dirtyMark:false};

            var acquireError = null;
            try {
                ItemUtil.acquire([{name:"监听获得物", value:1}],
                    {source:"pickup", reason:"listener_fault"});
            } catch (error) {
                acquireError = error;
            }
            assert(acquireError == "acquire_item_added_failed",
                "acquire 保留 ItemAdded 监听器原始异常");
            assert(bag.getItem("0") != null && bag.getItem("0").name == "监听获得物"
                    && _root.存档系统.dirtyMark === true,
                "ItemAdded 异常时实际获得已先标脏且不伪装资产回滚");
            assert(PlayerAssetTransaction.current() == null,
                "ItemAdded 异常恢复 EventBus depth 并只清理 acquire 自有隐式 frame");
            assert(receipts.length == 1 && receipts[0].effects.length == 1
                    && receipts[0].effects[0].direction == "gain"
                    && receipts[0].effects[0].name == "监听获得物"
                    && receipts[0].effects[0].count == 1,
                "ItemAdded 异常的 gain receipt 只包含 before/after 证明的已入包事实");

            bag.setDispatcher(null);
            var afterFault:Boolean = ItemUtil.submit(
                [{name:"监听获得物", value:1}],
                {source:"item_use", reason:"post_item_added_fault"});
            assert(afterFault && bag.getItem("0") == null
                    && PlayerAssetTransaction.current() == null,
                "ItemAdded 故障后的下一次容器事件与资产事务均可正常完成");
            assert(receipts.length == 2 && receipts[1].effects.length == 1
                    && receipts[1].effects[0].direction == "loss"
                    && receipts[1].effects[0].source == "item_use",
                "ItemAdded 故障后的下一事务拥有独立 receipt");
        } finally {
            bag.setDispatcher(null);
            holder.removeMovieClip();
            PlayerAssetTransaction.resetForTests();
            ItemUtil.itemDataDict = oldItemData;
            ItemUtil.equipmentDict = oldEquipment;
            ItemUtil.materialDict = oldMaterials;
            ItemUtil.informationMaxValueDict = oldInformation;
            _root.物品栏 = oldInventory;
            _root.收集品栏 = oldCollections;
            _root.存档系统 = oldSave;
        }
    }

    private function testAchievementListenerFaultLatchesClaimAndRecovers():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));

        var oldInventory:Object = _root.物品栏;
        var oldCollections:Object = _root.收集品栏;
        var oldSave:Object = _root.存档系统;
        var oldSaveExt:Object = _root._saveExt;
        var oldRoleName = _root.角色名;
        var oldKillStats:Object = _root.killStats;
        var oldServer:Object = _root.server;
        var oldMoney = _root.金钱;
        var oldKpoints = _root.虚拟币;
        var oldItemData:Object = ItemUtil.itemDataDict;
        var oldEquipment:Object = ItemUtil.equipmentDict;
        var oldMaterials:Object = ItemUtil.materialDict;
        var oldInformation:Object = ItemUtil.informationMaxValueDict;
        var bag:ArrayInventory = new ArrayInventory({}, 4);
        var drugs:ArrayInventory = new ArrayInventory({}, 4);
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__achievementAssetListenerFault", _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher = new LifecycleEventDispatcher(holder);
        bag.setDispatcher(dispatcher);
        dispatcher.subscribe("ItemAdded", function():Void {
            throw "achievement_reward_listener_failed";
        });

        try {
            ItemUtil.itemDataDict = {
                成就监听奖励:{name:"成就监听奖励", icon:"成就监听奖励", use:"消耗品"},
                成就回包奖励:{name:"成就回包奖励", icon:"成就回包奖励", use:"消耗品"}
            };
            ItemUtil.equipmentDict = {};
            ItemUtil.materialDict = {};
            ItemUtil.informationMaxValueDict = {};
            _root.物品栏 = {
                装备栏:{getItem:function(key:String) { return null; }},
                药剂栏:drugs,
                背包:bag
            };
            _root.收集品栏 = {材料:{}, 情报:{}};
            _root.存档系统 = {dirtyMark:false};
            _root.角色名 = "asset-transaction-test";
            _root.killStats = {total:0};
            var unlockedFixture:Object = {};
            unlockedFixture["asset.listener"] = 1;
            unlockedFixture["asset.response"] = 1;
            _root._saveExt = {成就:{
                v:1, base:{kt:0}, cnt:{},
                unl:unlockedFixture, claimed:{}
            }};
            _root.金钱 = 0;
            _root.虚拟币 = 0;
            _root.server = {sent:null};
            _root.server.sendSocketMessage = function(message:String):Boolean {
                this.sent = message;
                return true;
            };
            AchievementService.testOnlySetCatalog([{
                id:"asset.listener", title:"资产监听成就", description:"fixture",
                hidden:false,
                objective:{type:"killTotal", target:1, params:{}},
                rewards:["成就监听奖励#1"]
            }, {
                id:"asset.response", title:"回包隔离成就", description:"fixture",
                hidden:false,
                objective:{type:"killTotal", target:1, params:{}},
                rewards:["成就回包奖励#1"]
            }]);

            var validInventory:Object = _root.物品栏;
            _root.物品栏 = {
                装备栏:{getItem:function(key:String) { return null; }},
                药剂栏:null, 背包:null
            };
            var prewriteError = null;
            try {
                AchievementService.handleClaim({
                    callId:0, achievementId:"asset.listener"
                });
            } catch (error) {
                prewriteError = error;
            }
            _root.物品栏 = validInventory;
            assert(prewriteError != null
                    && _root._saveExt.成就.claimed["asset.listener"] == undefined
                    && _root.存档系统.dirtyMark === false
                    && receipts.length == 0
                    && PlayerAssetTransaction.current() == null,
                "成就奖励首个资产写前异常撤销 one-shot/dirty 并先清理 frame");

            var claimError = null;
            try {
                AchievementService.handleClaim({
                    callId:1, achievementId:"asset.listener"
                });
            } catch (error) {
                claimError = error;
            }
            var firstReward:Object = bag.getItem("0");
            assert(claimError == "achievement_reward_listener_failed"
                    && firstReward != null && firstReward.value == 1
                    && _root._saveExt.成就.claimed["asset.listener"] == 1
                    && _root.存档系统.dirtyMark === true
                    && PlayerAssetTransaction.current() == null
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0
                    && receipts.length == 1 && receipts[0].effects.length == 1
                    && receipts[0].effects[0].name == "成就监听奖励"
                    && receipts[0].effects[0].count == 1,
                "成就奖励 listener fault 保留实写、先锁 claimed 并清理 PAT/EventBus");

            bag.setDispatcher(null);
            _root.server.sent = null;
            AchievementService.handleClaim({
                callId:2, achievementId:"asset.listener"
            });
            assert(bag.getItem("0").value == 1
                    && String(_root.server.sent).indexOf("already_claimed") >= 0
                    && receipts.length == 1
                    && PlayerAssetTransaction.current() == null,
                "成就领取异常后的客户端重试命中 claimed one-shot 且不复制奖励");

            var responseAttempts:Number = 0;
            _root.server.sent = null;
            _root.server.sendSocketMessage = function(message:String):Boolean {
                responseAttempts++;
                if(responseAttempts == 1) throw "achievement_response_failed";
                this.sent = message;
                return true;
            };
            var committedResponseError = null;
            try {
                AchievementService.handleClaim({
                    callId:3, achievementId:"asset.response"
                });
            } catch(responseError) {
                committedResponseError = responseError;
            }
            assert(committedResponseError == null && responseAttempts == 1
                    && _root._saveExt.成就.claimed["asset.response"] == 1
                    && bag.getItem("1") != null
                    && bag.getItem("1").name == "成就回包奖励"
                    && receipts.length == 2
                    && PlayerAssetTransaction.current() == null,
                "成就已提交后的 stringify/socket 回包异常被隔离且不反转奖励/claimed");

            AchievementService.handleClaim({
                callId:4, achievementId:"asset.response"
            });
            assert(responseAttempts == 2
                    && String(_root.server.sent).indexOf("already_claimed") >= 0
                    && String(_root.server.sent).indexOf("claimed") >= 0
                    && bag.getItem("1").value == 1
                    && receipts.length == 2
                    && PlayerAssetTransaction.current() == null,
                "首次回包未知后下一 callId 以既有 already_claimed overlay 收敛且不重复发奖");

            var recovered:Boolean = ItemUtil.singleAcquire(
                "成就监听奖励", 1,
                {source:"pickup", reason:"post_achievement_fault"});
            assert(recovered && bag.getItem("0").value == 2
                    && receipts.length == 3
                    && receipts[2].effects.length == 1
                    && receipts[2].effects[0].source == "pickup"
                    && PlayerAssetTransaction.current() == null
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "成就 listener fault 后的下一独立物资事务正常提交");
        } finally {
            bag.setDispatcher(null);
            holder.removeMovieClip();
            AchievementService.testOnlyResetCatalog();
            PlayerAssetTransaction.resetForTests();
            ItemUtil.itemDataDict = oldItemData;
            ItemUtil.equipmentDict = oldEquipment;
            ItemUtil.materialDict = oldMaterials;
            ItemUtil.informationMaxValueDict = oldInformation;
            _root.物品栏 = oldInventory;
            _root.收集品栏 = oldCollections;
            _root.存档系统 = oldSave;
            _root._saveExt = oldSaveExt;
            _root.角色名 = oldRoleName;
            _root.killStats = oldKillStats;
            _root.server = oldServer;
            _root.金钱 = oldMoney;
            _root.虚拟币 = oldKpoints;
        }
    }

    private function testQuestExactFinalityAndRecovery():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        PlayerAssetTransaction.setTestSink(captureInto(receipts));

        var oldInventory:Object = _root.物品栏;
        var oldCollections:Object = _root.收集品栏;
        var oldSave:Object = _root.存档系统;
        var oldMoney = _root.金钱;
        var oldKpoints = _root.虚拟币;
        var oldExperience = _root.经验值;
        var oldSkillPoints = _root.技能点数;
        var oldLevel = _root.等级;
        var oldTasksToDo:Object = _root.tasks_to_do;
        var oldTasksFinished:Object = _root.tasks_finished;
        var oldChainProgress:Object = _root.task_chains_progress;
        var oldIsChallenge:Function = _root.isChallengeMode;
        var oldPublish:Function = _root.发布消息;
        var oldLevelProjection:Function = _root.主角是否升级;
        var oldSound:Function = _root.播放音效;
        var oldUpdateProgress:Function = _root.UpdateTaskProgress;
        var oldDialogue:Function = _root.SetDialogue;
        var oldCompletionProjection:Function = _root.是否达成任务检测;
        var oldTasks:Object = TaskUtil.tasks;
        var oldTaskChains:Object = TaskUtil.task_chains;
        var oldTaskSequences:Object = TaskUtil.task_in_chains_by_sequence;
        var oldTaskTexts:Object = TaskUtil.task_texts;
        var oldItemData:Object = ItemUtil.itemDataDict;
        var oldEquipment:Object = ItemUtil.equipmentDict;
        var oldMaterials:Object = ItemUtil.materialDict;
        var oldInformation:Object = ItemUtil.informationMaxValueDict;

        var bag:ArrayInventory = new ArrayInventory({}, 8);
        var drugs:ArrayInventory = new ArrayInventory({}, 4);
        var materials:DictCollection = new DictCollection(null);
        var information:DictCollection = new DictCollection(null);
        var rewardHolder:MovieClip = _root.createEmptyMovieClip(
            "__questRewardListenerFault", _root.getNextHighestDepth());
        var materialHolder:MovieClip = _root.createEmptyMovieClip(
            "__questSubmitReentry", _root.getNextHighestDepth());
        var lastQuestMessage:String = "";

        var installTask:Function = function(id:Number, rewards:Array,
                                            turnIn:Array):Void {
            TaskUtil.tasks = {};
            TaskUtil.tasks[id] = {
                id:id, title:"资产事务测试任务", rewards:rewards,
                challenge:{rewards:[]}, finish_submit_items:turnIn,
                finish_conversation:"完成", finish_npc:"测试NPC",
                chain:["资产事务测试链", id]
            };
            TaskUtil.task_chains = {资产事务测试链:{}};
            TaskUtil.task_in_chains_by_sequence = {资产事务测试链:[]};
            TaskUtil.task_texts = {};
            _root.tasks_to_do = [{id:id,
                requirements:{challenge:{finished:false}}}];
            _root.tasks_finished = {};
            _root.task_chains_progress = {};
        };

        var describeQuestState:Function = function(taskId:Number):String {
            var indexes:Array = bag.getIndexes();
            var firstItem:Object = bag.getItem("0");
            var secondItem:Object = bag.getItem("1");
            var transaction:Object = PlayerAssetTransaction.current();
            var firstEffect:Object = null;
            if (receipts.length > 0 && receipts[0] != null
                    && receipts[0].effects != null
                    && receipts[0].effects.length > 0) {
                firstEffect = receipts[0].effects[0];
            }
            var todoId = "none";
            if (_root.tasks_to_do != null && _root.tasks_to_do.length > 0
                    && _root.tasks_to_do[0] != null) {
                todoId = String(_root.tasks_to_do[0].id);
            }
            return "task=" + taskId
                + ",materialTask=" + materials.getValue("任务交付材料")
                + ",materialA=" + materials.getValue("交付甲")
                + ",materialB=" + materials.getValue("交付乙")
                + ",bagIndexes=" + String(indexes)
                + ",bag0=" + (firstItem == null ? "null"
                    : String(firstItem.name) + "#" + String(firstItem.value))
                + ",bag1=" + (secondItem == null ? "null"
                    : String(secondItem.name) + "#" + String(secondItem.value))
                + ",money=" + _root.金钱
                + ",xp=" + _root.经验值
                + ",sp=" + _root.技能点数
                + ",todoLength=" + (_root.tasks_to_do == null
                    ? "null" : String(_root.tasks_to_do.length))
                + ",todoId=" + todoId
                + ",finished=" + (_root.tasks_finished == null
                    ? "owner-null" : String(_root.tasks_finished[String(taskId)]))
                + ",dirty=" + (_root.存档系统 == null
                    ? "owner-null" : String(_root.存档系统.dirtyMark))
                + ",receipts=" + receipts.length
                + ",effect=" + (firstEffect == null ? "null"
                    : String(firstEffect.direction) + ":"
                        + String(firstEffect.name) + "#"
                        + String(firstEffect.count))
                + ",tx=" + (transaction == null ? "null"
                    : String(transaction.state))
                + ",dispatchDepth="
                    + String(EventBus.getInstance()["_dispatchDepth"]);
        };

        var describeRequirements:Function = function(items:Array):String {
            if (items == null) return "null";
            var descriptions:Array = [];
            for (var requirementIndex:Number = 0;
                    requirementIndex < items.length; requirementIndex++) {
                var requirement:Object = items[requirementIndex];
                descriptions.push(requirement == null ? "null"
                    : String(requirement.name) + "#" + String(requirement.value));
            }
            return descriptions.join("|");
        };

        var describeQuestPreflight:Function = function(index:Number):String {
            try {
                var currentTaskId = _root.tasks_to_do[index].id;
                var rawTask:Object = TaskUtil.getRawTaskData(currentTaskId);
                var clonedTask:Object = TaskUtil.getTaskData(currentTaskId);
                var rewardItems:Array = ItemUtil.getRequirementFromTask(
                    clonedTask.rewards);
                var submitItems:Array = clonedTask.finish_submit_items
                    ? ItemUtil.getRequirementFromTask(
                        clonedTask.finish_submit_items) : null;
                var containResult:Object = submitItems == null
                    ? {} : ItemUtil.contain(submitItems);
                var plan:Object = ItemUtil.planRewardAcquire(rewardItems);
                var reversible:Array = [];
                var progress:Array = [];
                if (plan != null) {
                    for (var planIndex:Number = 0;
                            planIndex < plan.items.length; planIndex++) {
                        var planned:Object = plan.items[planIndex];
                        if (planned.name == "经验值" || planned.name == "技能点") {
                            progress.push(planned);
                        } else {
                            reversible.push(planned);
                        }
                    }
                }
                var progressResult:Object = progress.length == 0
                    ? {} : ItemUtil.require(progress);
                var reversibleResult:Object = reversible.length == 0
                    ? {} : ItemUtil.require(reversible);
                return "rawRewards=" + (rawTask == null || rawTask.rewards == null
                        ? "null" : String(rawTask.rewards.length))
                    + ",cloneRewards=" + (clonedTask == null
                        || clonedTask.rewards == null
                        ? "null" : String(clonedTask.rewards.length))
                    + ",rewardItems=" + describeRequirements(rewardItems)
                    + ",submitItems=" + describeRequirements(submitItems)
                    + ",contain=" + (containResult == null ? "null" : "ok")
                    + ",plan=" + (plan == null ? "null"
                        : describeRequirements(plan.items))
                    + ",progress=" + (progressResult == null ? "null" : "ok")
                    + ",reversible=" + (reversibleResult == null ? "null" : "ok");
            } catch (preflightDetailError) {
                return "detailError=" + String(preflightDetailError);
            }
        };

        try {
            ItemUtil.itemDataDict = {
                任务首段奖励:{name:"任务首段奖励", use:"消耗品"},
                任务后段奖励:{name:"任务后段奖励", use:"消耗品"},
                重入占槽物:{name:"重入占槽物", use:"消耗品"}
            };
            ItemUtil.equipmentDict = {};
            ItemUtil.materialDict = {
                任务交付材料:true, 交付甲:true, 交付乙:true
            };
            ItemUtil.informationMaxValueDict = {};
            _root.物品栏 = {
                装备栏:{getItem:function(key:String) { return null; }},
                药剂栏:drugs,
                背包:bag
            };
            _root.收集品栏 = {材料:materials, 情报:information};
            _root.存档系统 = {dirtyMark:false};
            _root.金钱 = 0;
            _root.虚拟币 = 0;
            _root.经验值 = 100;
            _root.技能点数 = 3;
            _root.等级 = 1;
            _root.isChallengeMode = function():Boolean { return false; };
            _root.发布消息 = function(message:String):Void {
                lastQuestMessage = String(message);
            };
            _root.播放音效 = function(name:String):Void {};
            _root.UpdateTaskProgress = function():Void {};
            _root.SetDialogue = function(message:String):Void {};
            _root.是否达成任务检测 = function():Void {};

            installTask(7001, ["经验值#坏值"], []);
            var invalidResult:Boolean = _root.FinishTask(0);
            assert(invalidResult === false && _root.tasks_to_do.length == 1
                    && _root.经验值 == 100 && _root.技能点数 == 3
                    && _root.存档系统.dirtyMark === false
                    && receipts.length == 0
                    && PlayerAssetTransaction.current() == null,
                "Quest 非 finite/正整数 XP 奖励在事务与首写前 fail closed");

            materials.add("任务交付材料", 2);
            installTask(7002, ["金币#10", "经验值#5", "技能点#2",
                "任务后段奖励#1"], ["任务交付材料#1"]);
            var rewardDispatcher:LifecycleEventDispatcher =
                new LifecycleEventDispatcher(rewardHolder);
            bag.setDispatcher(rewardDispatcher);
            rewardDispatcher.subscribe("ItemAdded", function():Void {
                throw "quest_late_reward_listener_fault";
            });
            var preflight7002:String = describeQuestPreflight(0);
            lastQuestMessage = "";
            var questFault = null;
            try {
                _root.FinishTask(0);
            } catch (questError) {
                questFault = questError;
            }
            assert(questFault == "quest_late_reward_listener_fault"
                    && materials.getValue("任务交付材料") == 2
                    && bag.getIndexes().length == 0
                    && _root.金钱 == 0 && _root.经验值 == 100
                    && _root.技能点数 == 3
                    && _root.tasks_to_do.length == 1
                    && _root.tasks_finished["7002"] == undefined
                    && _root.存档系统.dirtyMark === false
                    && receipts.length == 0
                    && PlayerAssetTransaction.current() == null
                    && Number(EventBus.getInstance()["_dispatchDepth"]) == 0,
                "Quest 多奖励后段 listener fault exact 恢复交付物/奖励/进度/任务/dirty",
                "fault=" + String(questFault)
                    + ",message=" + lastQuestMessage
                    + ",preflight=" + preflight7002 + ","
                    + describeQuestState(7002));

            bag.setDispatcher(null);
            var levelProjectionCalls:Number = 0;
            _root.主角是否升级 = function(level:Number, experience:Number):Void {
                levelProjectionCalls++;
                throw "quest_level_projection_fault";
            };
            var retryPreflight7002:String = describeQuestPreflight(0);
            lastQuestMessage = "";
            var recoveredResult:Boolean = _root.FinishTask(0);
            assert(recoveredResult === true
                    && materials.getValue("任务交付材料") == 1
                    && bag.getItem("0") != null
                    && bag.getItem("0").name == "任务后段奖励"
                    && _root.金钱 == 10 && _root.经验值 == 105
                    && _root.技能点数 == 5 && levelProjectionCalls == 1
                    && _root.tasks_to_do.length == 0
                    && _root.tasks_finished["7002"] == 1
                    && receipts.length == 1
                    && PlayerAssetTransaction.current() == null,
                "Quest fault 后重试完整交付并提交全部奖励；升级回调抛错不反转完成状态",
                "result=" + String(recoveredResult)
                    + ",levelCalls=" + levelProjectionCalls
                    + ",message=" + lastQuestMessage
                    + ",preflight=" + retryPreflight7002 + ","
                    + describeQuestState(7002));

            PlayerAssetTransaction.resetForTests();
            receipts = [];
            PlayerAssetTransaction.setTestSink(captureInto(receipts));
            bag.setItems({});
            materials.setItems({交付甲:1, 交付乙:1});
            _root.金钱 = 0;
            _root.经验值 = 100;
            _root.技能点数 = 3;
            _root.存档系统.dirtyMark = false;
            installTask(7003, ["金币#1"], ["交付甲#1", "交付乙#1"]);
            var submitDispatcher:LifecycleEventDispatcher =
                new LifecycleEventDispatcher(materialHolder);
            materials.setDispatcher(submitDispatcher);
            var submitReentered:Boolean = false;
            submitDispatcher.subscribe("ItemRemoved",
                function(collection:Object, removedName:String):Void {
                    if (submitReentered) return;
                    submitReentered = true;
                    var otherName:String = removedName == "交付甲" ? "交付乙" : "交付甲";
                    materials.addValue(otherName, -1);
                });
            var preflight7003:String = describeQuestPreflight(0);
            lastQuestMessage = "";
            var staleSubmitResult:Boolean = _root.FinishTask(0);
            assert(staleSubmitResult === false && submitReentered
                    && materials.getValue("交付甲") == 1
                    && materials.getValue("交付乙") == 1
                    && _root.金钱 == 0 && _root.tasks_to_do.length == 1
                    && _root.tasks_finished["7003"] == undefined
                    && _root.存档系统.dirtyMark === false
                    && receipts.length == 0
                    && PlayerAssetTransaction.current() == null,
                "Quest submit 预检后重入少扣会返回 false 并 exact 恢复，不带病完成",
                "result=" + String(staleSubmitResult)
                    + ",reentered=" + String(submitReentered)
                    + ",message=" + lastQuestMessage
                    + ",preflight=" + preflight7003 + ","
                    + describeQuestState(7003));

            materials.setDispatcher(null);
            var retryPreflight7003:String = describeQuestPreflight(0);
            lastQuestMessage = "";
            var nextResult:Boolean = _root.FinishTask(0);
            assert(nextResult === true
                    && materials.getValue("交付甲") == 0
                    && materials.getValue("交付乙") == 0
                    && _root.金钱 == 1 && _root.tasks_to_do.length == 0
                    && _root.tasks_finished["7003"] == 1
                    && receipts.length == 1
                    && PlayerAssetTransaction.current() == null,
                "Quest submit 重入故障后的下一事务独立消费全部交付物并只发一次奖励",
                "result=" + String(nextResult)
                    + ",message=" + lastQuestMessage
                    + ",preflight=" + retryPreflight7003 + ","
                    + describeQuestState(7003));

            PlayerAssetTransaction.resetForTests();
            receipts = [];
            PlayerAssetTransaction.setTestSink(captureInto(receipts));
            bag.setItems({});
            materials.setItems({});
            _root.金钱 = 0;
            _root.存档系统.dirtyMark = false;
            installTask(7004, ["任务首段奖励#1", "任务后段奖励#1"], []);
            var acquireDispatcher:LifecycleEventDispatcher =
                new LifecycleEventDispatcher(rewardHolder);
            bag.setDispatcher(acquireDispatcher);
            var acquireReentered:Boolean = false;
            acquireDispatcher.subscribe("ItemAdded",
                function(collection:Object, addedIndex):Void {
                    if(acquireReentered) return;
                    acquireReentered = true;
                    var occupiedIndex:Number = bag.getItem("0") == null ? 0 : 1;
                    bag.add(occupiedIndex,
                        new BaseItem("重入占槽物", 1, 1));
                });
            var preflight7004:String = describeQuestPreflight(0);
            lastQuestMessage = "";
            var staleAcquireResult:Boolean = _root.FinishTask(0);
            assert(staleAcquireResult === false && acquireReentered
                    && bag.getIndexes().length == 0
                    && _root.tasks_to_do.length == 1
                    && _root.tasks_finished["7004"] == undefined
                    && _root.存档系统.dirtyMark === false
                    && receipts.length == 0
                    && PlayerAssetTransaction.current() == null,
                "Quest 奖励监听器非抛错重入占用预留槽时少发返回 false 并 exact 恢复",
                "result=" + String(staleAcquireResult)
                    + ",reentered=" + String(acquireReentered)
                    + ",message=" + lastQuestMessage
                    + ",preflight=" + preflight7004 + ","
                    + describeQuestState(7004));

            bag.setDispatcher(null);
            var retryPreflight7004:String = describeQuestPreflight(0);
            lastQuestMessage = "";
            var nextAcquireResult:Boolean = _root.FinishTask(0);
            var recoveredBag0:Object = bag.getItem("0");
            var recoveredBag1:Object = bag.getItem("1");
            assert(nextAcquireResult === true
                    && bag.getIndexes().length == 2
                    && recoveredBag0 != null && recoveredBag1 != null
                    && recoveredBag0.value == 1 && recoveredBag1.value == 1
                    && ((recoveredBag0.name == "任务首段奖励"
                            && recoveredBag1.name == "任务后段奖励")
                        || (recoveredBag0.name == "任务后段奖励"
                            && recoveredBag1.name == "任务首段奖励"))
                    && recoveredBag0.name != "重入占槽物"
                    && recoveredBag1.name != "重入占槽物"
                    && _root.tasks_to_do.length == 0
                    && _root.tasks_finished["7004"] == 1
                    && receipts.length == 1
                    && PlayerAssetTransaction.current() == null,
                "Quest acquire 重入失败后的下一事务完整发放且不残留异名占槽物",
                "result=" + String(nextAcquireResult)
                    + ",message=" + lastQuestMessage
                    + ",preflight=" + retryPreflight7004 + ","
                    + describeQuestState(7004));

            PlayerAssetTransaction.resetForTests();
            receipts = [];
            PlayerAssetTransaction.setTestSink(captureInto(receipts));
            bag.setItems({});
            _root.存档系统.dirtyMark = false;
            installTask(7005, ["任务首段奖励#1"], []);
            var overAcquireDispatcher:LifecycleEventDispatcher =
                new LifecycleEventDispatcher(rewardHolder);
            bag.setDispatcher(overAcquireDispatcher);
            var overAcquired:Boolean = false;
            overAcquireDispatcher.subscribe("ItemAdded",
                function(collection:Object, addedKey:String):Void {
                    if(overAcquired) return;
                    overAcquired = true;
                    bag.addValue(addedKey, 1);
                });
            var preflight7005:String = describeQuestPreflight(0);
            lastQuestMessage = "";
            var overAcquireResult:Boolean = _root.FinishTask(0);
            assert(overAcquireResult === false && overAcquired
                    && bag.getIndexes().length == 0
                    && _root.tasks_to_do.length == 1
                    && _root.tasks_finished["7005"] == undefined
                    && _root.存档系统.dirtyMark === false
                    && receipts.length == 0
                    && PlayerAssetTransaction.current() == null,
                "Quest 同槽 over-acquire raw delta 不被 receipt cap 掩盖并 exact 恢复",
                "result=" + String(overAcquireResult)
                    + ",overAcquired=" + String(overAcquired)
                    + ",message=" + lastQuestMessage
                    + ",preflight=" + preflight7005 + ","
                    + describeQuestState(7005));

            bag.setDispatcher(null);
            var retryPreflight7005:String = describeQuestPreflight(0);
            lastQuestMessage = "";
            var overAcquireRecovered:Boolean = _root.FinishTask(0);
            assert(overAcquireRecovered === true
                    && bag.getItem("0") != null
                    && bag.getItem("0").name == "任务首段奖励"
                    && bag.getItem("0").value == 1
                    && _root.tasks_to_do.length == 0
                    && _root.tasks_finished["7005"] == 1
                    && receipts.length == 1
                    && receipts[0].effects[0].count == 1
                    && PlayerAssetTransaction.current() == null,
                "over-acquire 恢复后的下一任务只发请求数量并发布 truthful receipt",
                "result=" + String(overAcquireRecovered)
                    + ",message=" + lastQuestMessage
                    + ",preflight=" + retryPreflight7005 + ","
                    + describeQuestState(7005));
        } finally {
            bag.setDispatcher(null);
            materials.setDispatcher(null);
            rewardHolder.removeMovieClip();
            materialHolder.removeMovieClip();
            PlayerAssetTransaction.resetForTests();
            ItemUtil.itemDataDict = oldItemData;
            ItemUtil.equipmentDict = oldEquipment;
            ItemUtil.materialDict = oldMaterials;
            ItemUtil.informationMaxValueDict = oldInformation;
            _root.物品栏 = oldInventory;
            _root.收集品栏 = oldCollections;
            _root.存档系统 = oldSave;
            _root.金钱 = oldMoney;
            _root.虚拟币 = oldKpoints;
            _root.经验值 = oldExperience;
            _root.技能点数 = oldSkillPoints;
            _root.等级 = oldLevel;
            _root.tasks_to_do = oldTasksToDo;
            _root.tasks_finished = oldTasksFinished;
            _root.task_chains_progress = oldChainProgress;
            _root.isChallengeMode = oldIsChallenge;
            _root.发布消息 = oldPublish;
            _root.主角是否升级 = oldLevelProjection;
            _root.播放音效 = oldSound;
            _root.UpdateTaskProgress = oldUpdateProgress;
            _root.SetDialogue = oldDialogue;
            _root.是否达成任务检测 = oldCompletionProjection;
            TaskUtil.tasks = oldTasks;
            TaskUtil.task_chains = oldTaskChains;
            TaskUtil.task_in_chains_by_sequence = oldTaskSequences;
            TaskUtil.task_texts = oldTaskTexts;
        }
    }

    /** FinishTask 成功后的列表构建只是投影；失败必须 success+deferred，且下一读取独立。 */
    private function testTaskFinishPostCommitProjectionFailureResponds():Void {
        var oldTasks:Object = TaskUtil.tasks;
        var oldTasksToDo:Array = _root.tasks_to_do;
        var oldCompleteCheck:Function = _root.taskCompleteCheck;
        var oldFinishTask:Function = _root.FinishTask;
        var oldServer:Object = _root.server;
        var oldGameCommands:Object = _root.gameCommands;
        var payloads:Array = [];
        var finishCalls:Number = 0;
        var completeChecks:Number = 0;

        try {
            TaskUtil.tasks = {};
            TaskUtil.tasks[91001] = {
                title:"已提交任务", chain:["支线"], finish_remote:true
            };
            TaskUtil.tasks[91002] = {
                title:"后续任务", chain:["支线"], finish_remote:true
            };
            _root.tasks_to_do = [{id:91001}, {id:91002}];
            _root.taskCompleteCheck = function(index:Number):Boolean {
                completeChecks++;
                if (completeChecks == 1) return true;
                throw "mock post-commit task projection failure";
                return false;
            };
            _root.FinishTask = function(index:Number):Boolean {
                finishCalls++;
                _root.tasks_to_do.splice(index, 1);
                return true;
            };
            _root.server = {sendSocketMessage:function(payload):Void {
                payloads.push(payload);
            }};
            _root.gameCommands = {};
            TaskPanelService.install();

            TaskPanelService.handleFinish({callId:"finish_projection", taskId:91001});
            var firstPayload:String = payloads.length > 0 ? String(payloads[0]) : "";
            assert(finishCalls == 1 && _root.tasks_to_do.length == 1
                    && _root.tasks_to_do[0].id == 91002
                    && firstPayload.indexOf("\"success\":true") >= 0
                    && firstPayload.indexOf("\"refreshDeferred\":true") >= 0,
                "任务已提交后的列表投影异常仍返回 success+refreshDeferred，不重放权威写",
                "finishCalls=" + finishCalls + " payload=" + firstPayload);

            _root.taskCompleteCheck = function(index:Number):Boolean { return true; };
            TaskPanelService.handleSnapshot({callId:"finish_projection_reconcile"});
            var secondPayload:String = payloads.length > 1 ? String(payloads[1]) : "";
            assert(payloads.length == 2
                    && secondPayload.indexOf("\"success\":true") >= 0
                    && secondPayload.indexOf("\"tasks\":[") >= 0,
                "提交后投影故障不污染下一次权威 snapshot",
                "payloadCount=" + payloads.length + " payload=" + secondPayload);
        } finally {
            TaskUtil.tasks = oldTasks;
            _root.tasks_to_do = oldTasksToDo;
            _root.taskCompleteCheck = oldCompleteCheck;
            _root.FinishTask = oldFinishTask;
            _root.server = oldServer;
            _root.gameCommands = oldGameCommands;
        }
    }

    private function testExplicitExceptionSettlement():Void {
        PlayerAssetTransaction.resetForTests();
        var receipts:Array = [];
        var saveCount:Number = 0;
        PlayerAssetTransaction.setTestSink(captureInto(receipts));
        PlayerAssetTransaction.setTestStrongSaveSink(function():Boolean {
            saveCount++;
            return true;
        });

        var outer:Object = PlayerAssetTransaction.begin(
            {source:"quest_reward", reason:"quest_fault"});
        PlayerAssetTransaction.recordEffect(
            "gain", "item", "已入账奖励", 1, null);
        PlayerAssetTransaction.requestStrongSave();
        var child:Object = PlayerAssetTransaction.begin(
            {source:"quest_turn_in", reason:"listener_fault"});
        PlayerAssetTransaction.recordEffect(
            "loss", "item", "已扣交付物", 2, null);
        var settled:Object = PlayerAssetTransaction.settleAfterException(outer, true);

        assert(settled != null && settled.effects.length == 2,
            "保留事实的异常结算合并本领域遗留子 frame");
        assert(PlayerAssetTransaction.current() == null
                && outer.state == "committed" && child.state == "exception_merged",
            "异常结算完整关闭目标及其子 frame，不越权残留栈顶");
        assert(receipts.length == 1 && saveCount == 1,
            "保留事实的异常结算只发布一次 receipt 并兑现一次强存盘请求");

        var next:Object = PlayerAssetTransaction.begin(
            {source:"pickup", reason:"post_explicit_fault"});
        PlayerAssetTransaction.recordEffect(
            "gain", "item", "下一事务", 1, null);
        PlayerAssetTransaction.commit(next);
        assert(receipts.length == 2 && receipts[1].effects.length == 1
                && receipts[1].effects[0].name == "下一事务" && saveCount == 1,
            "显式异常结算后的下一事务不继承旧 effects/强存盘请求");

        var restoredOuter:Object = PlayerAssetTransaction.begin(
            {source:"crafting", reason:"restored_snapshot"});
        PlayerAssetTransaction.recordEffect(
            "loss", "material", "已由快照恢复", 3, null);
        PlayerAssetTransaction.requestStrongSave();
        var discarded:Object = PlayerAssetTransaction.settleAfterException(
            restoredOuter, false);
        assert(discarded == null && restoredOuter.state == "rolled_back"
                && PlayerAssetTransaction.current() == null,
            "exact snapshot 恢复后只丢弃未发布回执 frame");
        assert(receipts.length == 2 && saveCount == 1,
            "丢弃回执结算不发布幽灵 loss，也不执行已恢复事务的强存盘请求");
    }

    /**
     * 断言函数
     * @param condition 条件
     * @param message 测试描述
     * @param details 错误详情（可选）
     */
    private function assert(condition:Boolean, message:String, details:String):Void {
        if (condition) {
            trace("PASS: " + message);
            testPassed++;
        } else {
            trace("FAIL: " + message);
            if (details) trace("DETAILS: " + details);
            testFailed++;
        }
    }

}
