import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.item.PlayerAssetWireProjector;
import org.flashNight.arki.item.ItemUtil;

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
            assert(receipts.length == 0,
                "acquire 中途异常不按原请求发布虚假全量获得回执");

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
            assert(outer.effects.length == 1
                    && outer.effects[0].name == "外层既有材料"
                    && receipts.length == 0
                    && _root.金钱 == 110 && _root.存档系统.dirtyMark === true,
                "显式外层保留既有 effect 与部分写 dirty，但 acquire 不注入虚假完整 effects");
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
                    && receipts.length == 1
                    && receipts[0].effects.length == 1
                    && receipts[0].effects[0].name == "金钱"
                    && receipts[0].effects[0].count == 1,
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
