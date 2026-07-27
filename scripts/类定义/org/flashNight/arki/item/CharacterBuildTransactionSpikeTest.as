/**
 * 角色构筑 B0 双容器 swap 可行性测试。
 *
 * 这是测试内最小算法，不是生产 Coordinator。真实目标端使用
 * EquipmentInventory.transactionWrite；背包端使用可故障注入 fixture，
 * 只证明 §4.3 的预检、无事件双写、exact rollback 与统一 publish 顺序。
 */
import org.flashNight.arki.item.itemCollection.EquipmentInventory;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

class org.flashNight.arki.item.CharacterBuildTransactionSpikeTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var _previousGetItemData:Function;
    private static var _itemData:Object;
    private static var _slotKeys:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"
    ];

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== CharacterBuildTransactionSpikeTest start ===");
        installItemDataFixture();
        try {
            testAllSlotPreflight();
            testRevisionRefAndSignaturePreflight();
            testSuccessfulSwapPublishesOnlyFinalState();
            testSecondWriteFalseAndThrowRollback();
            testRollbackFalseAndThrowPoison();
        } finally {
            restoreItemDataFixture();
        }
        trace("CharacterBuildTransactionSpikeTest Tests Passed: " + _passed);
        trace("CharacterBuildTransactionSpikeTest Tests Failed: " + _failed);
        trace("=== CharacterBuildTransactionSpikeTest end ===");
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

    private static function installItemDataFixture():Void {
        _previousGetItemData = _root.getItemData;
        _itemData = {};
        _root.__characterBuildTransactionSpikeData = _itemData;
        _root.getItemData = function(name):Object {
            var key:String = String(name);
            if (_root.__characterBuildTransactionSpikeThrowName === key) {
                throw "CharacterBuildTransactionSpikeTest/second_write_throw";
            }
            if (_root.__characterBuildTransactionSpikeFalseName === key) {
                return {use:"CharacterBuildTransactionSpikeTest/非法槽"};
            }
            return _root.__characterBuildTransactionSpikeData[key];
        };
    }

    private static function restoreItemDataFixture():Void {
        clearSecondWriteGate();
        if (_previousGetItemData == undefined) delete _root.getItemData;
        else _root.getItemData = _previousGetItemData;
        delete _root.__characterBuildTransactionSpikeData;
        _itemData = null;
    }

    private static function clearSecondWriteGate():Void {
        delete _root.__characterBuildTransactionSpikeFalseName;
        delete _root.__characterBuildTransactionSpikeThrowName;
    }

    private static function itemFor(slotKey:String,
                                    identity:String,
                                    marker:Number):Object {
        var itemName:String = "CharacterBuildTransactionSpikeTest/"
            + identity + "/" + slotKey;
        _itemData[itemName] = {use:slotKey == "手枪2" ? "手枪" : slotKey};
        return {
            name:itemName,
            value:slotKey == "手雷"
                ? marker + 1
                : {level:marker, signatureTag:identity},
            lastUpdate:marker
        };
    }

    private static function cloneWithSameSignature(item:Object):Object {
        var clonedValue;
        if (typeof item.value == "number") {
            clonedValue = Number(item.value);
        } else {
            clonedValue = {
                level:Number(item.value.level),
                signatureTag:String(item.value.signatureTag)
            };
        }
        return {
            name:String(item.name),
            value:clonedValue,
            lastUpdate:Number(item.lastUpdate)
        };
    }

    private static function signature(item:Object):String {
        if (item == null) return "null";
        var valuePart:String;
        if (typeof item.value == "number") {
            valuePart = "number:" + String(Number(item.value));
        } else {
            valuePart = "equipment:"
                + String(Number(item.value.level)) + ":"
                + String(item.value.signatureTag);
        }
        return String(item.name) + "|" + valuePart
            + "|updated:" + String(Number(item.lastUpdate));
    }

    /**
     * 可故障注入背包。transactionWrite 的第二次调用只用于 rollback。
     * false_after_write / throw_after_write 会先恢复 exact before，再报告不可信结果，
     * 使算法必须保守返回 needs_reconcile/poison。
     */
    private static function makeBackpack(slot:Number, item:Object):Object {
        var backpack:Object = {
            items:{},
            revision:1,
            writeCount:0,
            publishCount:0,
            rollbackMode:"",
            secondWriteMode:"",
            beforePublishEventCount:-1,
            beforePublishLoadoutRevision:-1,
            beforePublishDirty:true,
            beforePublishTarget:null,
            beforePublishSource:null,
            probe:null,
            observer:null
        };
        backpack.items[String(slot)] = item;
        backpack.getItem = function(key):Object {
            return this.items[String(key)];
        };
        backpack.getMutationRevision = function():Number {
            return Number(this.revision);
        };
        backpack.canAccept = function(key:Number, candidate:Object):Boolean {
            return !isNaN(key) && Math.floor(key) == key && key >= 0
                && candidate != null && candidate.name != undefined
                && candidate.name != "" && candidate.value != null;
        };
        backpack.transactionWrite = function(key:Number, candidate:Object):Boolean {
            this.writeCount++;
            if (candidate == null) delete this.items[String(key)];
            else this.items[String(key)] = candidate;
            this.revision++;

            if (this.writeCount == 1) {
                var probe:Object = this.probe;
                if (probe != null) {
                    this.beforePublishEventCount = Number(probe.events.count);
                    this.beforePublishLoadoutRevision =
                        Number(probe.domain.loadoutRevision);
                    this.beforePublishDirty = probe.domain.globalDirty === true;
                    this.beforePublishTarget =
                        probe.target.getItem(probe.targetSlot);
                    this.beforePublishSource = this.getItem(key);
                }
                if (this.secondWriteMode == "false") {
                    _root.__characterBuildTransactionSpikeFalseName =
                        String(this.expectedCandidate.name);
                } else if (this.secondWriteMode == "throw") {
                    _root.__characterBuildTransactionSpikeThrowName =
                        String(this.expectedCandidate.name);
                }
                return true;
            }

            if (this.rollbackMode == "false_after_write") return false;
            if (this.rollbackMode == "throw_after_write") {
                throw "CharacterBuildTransactionSpikeTest/rollback_throw";
            }
            return true;
        };
        backpack.publishTransactionChange =
            function(key:Number, changeKind:String):Void {
                this.publishCount++;
                if (typeof this.observer == "function") {
                    this.observer(this, key, changeKind);
                }
            };
        return backpack;
    }

    private static function makeContext(slotKey:String):Object {
        var targetBefore:Object = itemFor(slotKey, "target-before", 10);
        var sourceBefore:Object = itemFor(slotKey, "source-before", 20);
        var target:EquipmentInventory = new EquipmentInventory(null);
        var seeded:Boolean = target.transactionWrite(slotKey, targetBefore);
        var sourceSlot:Number = 2;
        var source:Object = makeBackpack(sourceSlot, sourceBefore);
        var domain:Object = {
            loadoutRevision:41,
            globalDirty:false
        };
        var events:Object = {count:0, finalOnly:true, order:""};
        var request:Object = {
            target:target,
            targetSlot:slotKey,
            source:source,
            sourceSlot:sourceSlot,
            expectedTargetRevision:target.getMutationRevision(),
            expectedSourceRevision:source.getMutationRevision(),
            expectedTargetRef:targetBefore,
            expectedSourceRef:sourceBefore,
            expectedTargetSignature:signature(targetBefore),
            expectedSourceSignature:signature(sourceBefore),
            domain:domain
        };
        source.expectedCandidate = sourceBefore;
        source.probe = {
            target:target,
            targetSlot:slotKey,
            domain:domain,
            events:events
        };
        return {
            seeded:seeded,
            target:target,
            targetSlot:slotKey,
            targetBefore:targetBefore,
            source:source,
            sourceSlot:sourceSlot,
            sourceBefore:sourceBefore,
            domain:domain,
            events:events,
            request:request
        };
    }

    private static function readRevision(container:Object):Number {
        try {
            var revision:Number = Number(container.getMutationRevision());
            if (isNaN(revision) || Math.floor(revision) != revision
                    || revision < 0) return -1;
            return revision;
        } catch (error) {
            return -1;
        }
    }

    private static function preflightSwap(request:Object):Object {
        var source:Object = request.source;
        var target:EquipmentInventory = request.target;
        var sourceSlot:Number = Number(request.sourceSlot);
        var targetSlot:String = String(request.targetSlot);
        if (source == null || target == null
                || typeof source.getItem != "function"
                || typeof source.getMutationRevision != "function"
                || typeof source.transactionWrite != "function"
                || typeof source.canAccept != "function") {
            return {success:false, error:"service_not_ready"};
        }

        var sourceRevision:Number = readRevision(source);
        var targetRevision:Number = readRevision(target);
        if (sourceRevision != Number(request.expectedSourceRevision)) {
            return {success:false, error:"source_revision"};
        }
        if (targetRevision != Number(request.expectedTargetRevision)) {
            return {success:false, error:"target_revision"};
        }

        var sourceBefore:Object = source.getItem(sourceSlot);
        var targetBefore:Object = target.getItem(targetSlot);
        if (sourceBefore !== request.expectedSourceRef) {
            return {success:false, error:"source_ref"};
        }
        if (targetBefore !== request.expectedTargetRef) {
            return {success:false, error:"target_ref"};
        }
        if (signature(sourceBefore) != String(request.expectedSourceSignature)) {
            return {success:false, error:"source_signature"};
        }
        if (signature(targetBefore) != String(request.expectedTargetSignature)) {
            return {success:false, error:"target_signature"};
        }
        if (sourceBefore == null || targetBefore == null
                || sourceBefore === targetBefore) {
            return {success:false, error:"invalid_identity"};
        }
        if (!target.isAddable(targetSlot, sourceBefore)) {
            return {success:false, error:"target_use"};
        }
        if (!source.canAccept(sourceSlot, targetBefore)) {
            return {success:false, error:"source_rejected"};
        }
        return {
            success:true,
            sourceRevision:sourceRevision,
            targetRevision:targetRevision,
            sourceBefore:sourceBefore,
            targetBefore:targetBefore
        };
    }

    private static function outcome(request:Object,
                                    gate:Object,
                                    success:Boolean,
                                    errorCode:String):Object {
        return {
            success:success,
            error:errorCode,
            sourceRevision:readRevision(request.source),
            targetRevision:readRevision(request.target),
            sourceBefore:gate.sourceBefore,
            targetBefore:gate.targetBefore,
            loadoutRevision:Number(request.domain.loadoutRevision),
            globalDirty:request.domain.globalDirty === true,
            rolledBack:false,
            needsReconcile:false,
            poison:false
        };
    }

    /**
     * 最小测试算法。背包第一写、真实 EquipmentInventory 第二写；任何 publish、
     * domain revision 与 dirty 都只能发生在两个 exact after 已证明之后。
     */
    private static function executeSwap(request:Object):Object {
        var gate:Object = preflightSwap(request);
        if (!gate.success) {
            return {
                success:false,
                error:gate.error,
                sourceRevision:readRevision(request.source),
                targetRevision:readRevision(request.target),
                loadoutRevision:Number(request.domain.loadoutRevision),
                globalDirty:request.domain.globalDirty === true
            };
        }

        var source:Object = request.source;
        var target:EquipmentInventory = request.target;
        var firstWrite:Boolean = false;
        try {
            firstWrite = source.transactionWrite(
                Number(request.sourceSlot), gate.targetBefore) === true;
        } catch (firstError) {
            firstWrite = false;
        }
        if (!firstWrite || source.getItem(request.sourceSlot) !== gate.targetBefore) {
            var firstFailure:Object = outcome(
                request, gate, false, "first_write_failed");
            firstFailure.needsReconcile =
                source.getItem(request.sourceSlot) !== gate.sourceBefore;
            firstFailure.poison = firstFailure.needsReconcile;
            return firstFailure;
        }

        var secondWrite:Boolean = false;
        var secondThrew:Boolean = false;
        try {
            secondWrite = target.transactionWrite(
                String(request.targetSlot), gate.sourceBefore) === true;
        } catch (secondError) {
            secondThrew = true;
            secondWrite = false;
        }
        clearSecondWriteGate();

        if (secondWrite
                && target.getItem(request.targetSlot) === gate.sourceBefore
                && source.getItem(request.sourceSlot) === gate.targetBefore) {
            request.domain.loadoutRevision =
                Number(request.domain.loadoutRevision) + 1;
            request.domain.globalDirty = true;
            target.publishTransactionChange(
                String(request.targetSlot), "replaced");
            source.publishTransactionChange(
                Number(request.sourceSlot), "replaced");
            var committed:Object = outcome(request, gate, true, "");
            committed.changed = true;
            committed.secondWrite = "true";
            return committed;
        }

        var rollbackReturned:Boolean = false;
        var rollbackThrew:Boolean = false;
        try {
            rollbackReturned = source.transactionWrite(
                Number(request.sourceSlot), gate.sourceBefore) === true;
        } catch (rollbackError) {
            rollbackThrew = true;
            rollbackReturned = false;
        }
        var exactBefore:Boolean =
            source.getItem(request.sourceSlot) === gate.sourceBefore
            && target.getItem(request.targetSlot) === gate.targetBefore
            && signature(source.getItem(request.sourceSlot))
                == String(request.expectedSourceSignature)
            && signature(target.getItem(request.targetSlot))
                == String(request.expectedTargetSignature);
        var failed:Object = outcome(
            request, gate, false,
            rollbackReturned && exactBefore
                ? "second_write_failed" : "needs_reconcile");
        failed.secondWrite = secondThrew ? "throw" : "false";
        failed.rollbackOutcome = rollbackThrew
            ? "throw" : rollbackReturned ? "true" : "false";
        failed.rolledBack = rollbackReturned && exactBefore;
        if (!rollbackReturned || rollbackThrew || !exactBefore) {
            failed.error = "needs_reconcile";
            failed.needsReconcile = true;
            failed.poison = true;
            failed.authorityState = "poison";
        }
        return failed;
    }

    private static function identityCounts(context:Object):Object {
        var first:Object = context.target.getItem(context.targetSlot);
        var second:Object = context.source.getItem(context.sourceSlot);
        var targetBeforeCount:Number = 0;
        var sourceBeforeCount:Number = 0;
        if (first === context.targetBefore) targetBeforeCount++;
        if (second === context.targetBefore) targetBeforeCount++;
        if (first === context.sourceBefore) sourceBeforeCount++;
        if (second === context.sourceBefore) sourceBeforeCount++;
        return {
            targetBefore:targetBeforeCount,
            sourceBefore:sourceBeforeCount
        };
    }

    private static function testAllSlotPreflight():Void {
        var accepted:Number = 0;
        var allFixturesOmitUse:Boolean = true;
        var allSeeded:Boolean = true;
        for (var i:Number = 0; i < _slotKeys.length; i++) {
            var slotKey:String = String(_slotKeys[i]);
            var context:Object = makeContext(slotKey);
            allSeeded = allSeeded && context.seeded;
            allFixturesOmitUse = allFixturesOmitUse
                && context.sourceBefore.use == undefined;
            if (preflightSwap(context.request).success) accepted++;
        }
        check(allSeeded && accepted == 11,
            "真实 EquipmentInventory 预检接受精确 11 槽");
        check(allFixturesOmitUse,
            "预检通过 getItemData(item.name).use 而非 item.use");

        var pistol2:Object = makeContext("手枪2");
        check(_root.getItemData(pistol2.sourceBefore.name).use == "手枪"
                && preflightSwap(pistol2.request).success,
            "手枪 use 对手枪2目标走现役额外兼容预检");

        var mismatch:Object = makeContext("上装装备");
        var wrong:Object = itemFor("头部装备", "wrong-use", 30);
        mismatch.source.items[String(mismatch.sourceSlot)] = wrong;
        mismatch.request.expectedSourceRef = wrong;
        mismatch.request.expectedSourceSignature = signature(wrong);
        var beforeSourceRevision:Number = mismatch.source.getMutationRevision();
        var beforeTargetRevision:Number = mismatch.target.getMutationRevision();
        var rejected:Object = preflightSwap(mismatch.request);
        check(!rejected.success && rejected.error == "target_use"
                && mismatch.source.getMutationRevision() == beforeSourceRevision
                && mismatch.target.getMutationRevision() == beforeTargetRevision,
            "use 不匹配在任何写入前被拒绝");
    }

    private static function testRevisionRefAndSignaturePreflight():Void {
        var sourceRevision:Object = makeContext("头部装备");
        sourceRevision.source.revision++;
        var sourceRevisionGate:Object = preflightSwap(sourceRevision.request);

        var targetRevision:Object = makeContext("上装装备");
        targetRevision.target.transactionWrite(
            targetRevision.targetSlot,
            itemFor(targetRevision.targetSlot, "revision-drift", 11));
        var targetRevisionGate:Object = preflightSwap(targetRevision.request);
        check(!sourceRevisionGate.success
                && sourceRevisionGate.error == "source_revision"
                && !targetRevisionGate.success
                && targetRevisionGate.error == "target_revision",
            "source/target raw revision 必须 exact 命中");

        var sourceRef:Object = makeContext("手部装备");
        var equalSource:Object = cloneWithSameSignature(sourceRef.sourceBefore);
        sourceRef.source.items[String(sourceRef.sourceSlot)] = equalSource;
        var sourceRefGate:Object = preflightSwap(sourceRef.request);

        var targetRef:Object = makeContext("下装装备");
        var equalTarget:Object = cloneWithSameSignature(targetRef.targetBefore);
        targetRef.target.transactionWrite(targetRef.targetSlot, equalTarget);
        targetRef.request.expectedTargetRevision =
            targetRef.target.getMutationRevision();
        var targetRefGate:Object = preflightSwap(targetRef.request);
        check(!sourceRefGate.success && sourceRefGate.error == "source_ref"
                && !targetRefGate.success && targetRefGate.error == "target_ref",
            "同签名替代对象仍被 source/target exact ref 预检拒绝");

        var sourceSignature:Object = makeContext("脚部装备");
        sourceSignature.sourceBefore.value.level++;
        var sourceSignatureGate:Object = preflightSwap(sourceSignature.request);

        var targetSignature:Object = makeContext("颈部装备");
        targetSignature.targetBefore.value.level++;
        var targetSignatureGate:Object = preflightSwap(targetSignature.request);
        check(!sourceSignatureGate.success
                && sourceSignatureGate.error == "source_signature"
                && !targetSignatureGate.success
                && targetSignatureGate.error == "target_signature",
            "同引用语义漂移由 source/target signature 预检拒绝");

        var stackSignature:Object = makeContext("手雷");
        stackSignature.sourceBefore.value++;
        var stackGate:Object = preflightSwap(stackSignature.request);
        check(!stackGate.success && stackGate.error == "source_signature",
            "手雷 stack 数量属于签名且直接字段漂移可见");
    }

    private static function testSuccessfulSwapPublishesOnlyFinalState():Void {
        var context:Object = makeContext("长枪");
        var holder:MovieClip = _root.createEmptyMovieClip(
            "__characterBuildTransactionSpikeSuccess",
            _root.getNextHighestDepth());
        var dispatcher:LifecycleEventDispatcher =
            new LifecycleEventDispatcher(holder);
        context.target.setDispatcher(dispatcher);
        var expectedDomainRevision:Number =
            Number(context.domain.loadoutRevision) + 1;

        var observeFinal:Function = function(label:String):Void {
            context.events.count++;
            context.events.order += label;
            context.events.finalOnly = context.events.finalOnly
                && context.target.getItem(context.targetSlot)
                    === context.sourceBefore
                && context.source.getItem(context.sourceSlot)
                    === context.targetBefore
                && context.domain.loadoutRevision == expectedDomainRevision
                && context.domain.globalDirty === true;
        };
        dispatcher.subscribe("ItemRemoved",
            function(source:Object, key:String):Void {
                observeFinal("R");
            });
        dispatcher.subscribe("ItemAdded",
            function(source:Object, key:String):Void {
                observeFinal("A");
            });
        context.source.observer =
            function(source:Object, key:Number, kind:String):Void {
                observeFinal("B");
            };

        var sourceRevisionBefore:Number =
            context.source.getMutationRevision();
        var targetRevisionBefore:Number =
            context.target.getMutationRevision();
        var result:Object = executeSwap(context.request);
        var counts:Object = identityCounts(context);

        check(result.success
                && context.target.getItem(context.targetSlot)
                    === context.sourceBefore
                && context.source.getItem(context.sourceSlot)
                    === context.targetBefore,
            "两次无事件写均 exact after 后 swap 才成功");
        check(context.source.beforePublishEventCount == 0
                && context.source.beforePublishLoadoutRevision
                    == expectedDomainRevision - 1
                && context.source.beforePublishDirty === false
                && context.source.beforePublishTarget
                    === context.targetBefore
                && context.source.beforePublishSource
                    === context.targetBefore,
            "第一写半状态不派发事件、不推进领域 revision/dirty");
        check(context.events.count == 3
                && context.events.order == "RAB"
                && context.events.finalOnly,
            "统一 publish 同步重入只观察最终两槽与最终领域状态");
        check(context.domain.loadoutRevision == expectedDomainRevision
                && context.domain.globalDirty === true
                && context.source.getMutationRevision()
                    > sourceRevisionBefore
                && context.target.getMutationRevision()
                    > targetRevisionBefore,
            "全部成功后才推进领域 revision/dirty，raw revisions 同调前进");
        check(counts.targetBefore == 1 && counts.sourceBefore == 1,
            "成功 swap 两个物品身份各出现一次，零复制/丢失");

        context.target.setDispatcher(null);
        holder.removeMovieClip();
    }

    private static function runSecondWriteFailure(mode:String):Object {
        var context:Object = makeContext("手枪2");
        context.source.secondWriteMode = mode;
        var sourceRevisionBefore:Number =
            context.source.getMutationRevision();
        var targetRevisionBefore:Number =
            context.target.getMutationRevision();
        var domainRevisionBefore:Number =
            context.domain.loadoutRevision;
        var result:Object = executeSwap(context.request);
        return {
            context:context,
            result:result,
            sourceRevisionBefore:sourceRevisionBefore,
            targetRevisionBefore:targetRevisionBefore,
            domainRevisionBefore:domainRevisionBefore,
            counts:identityCounts(context)
        };
    }

    private static function testSecondWriteFalseAndThrowRollback():Void {
        var falseCase:Object = runSecondWriteFailure("false");
        var throwCase:Object = runSecondWriteFailure("throw");
        check(!falseCase.result.success
                && falseCase.result.error == "second_write_failed"
                && falseCase.result.secondWrite == "false"
                && falseCase.result.rolledBack
                && !falseCase.result.needsReconcile,
            "真实 EquipmentInventory 第二写 false 后 exact before 回滚");
        check(!throwCase.result.success
                && throwCase.result.error == "second_write_failed"
                && throwCase.result.secondWrite == "throw"
                && throwCase.result.rolledBack
                && !throwCase.result.needsReconcile,
            "真实 EquipmentInventory 第二写 throw 后 exact before 回滚");

        var cases:Array = [falseCase, throwCase];
        var cleanFailure:Boolean = true;
        for (var i:Number = 0; i < cases.length; i++) {
            var sample:Object = cases[i];
            var context:Object = sample.context;
            cleanFailure = cleanFailure
                && context.target.getItem(context.targetSlot)
                    === context.targetBefore
                && context.source.getItem(context.sourceSlot)
                    === context.sourceBefore
                && context.source.getMutationRevision()
                    > sample.sourceRevisionBefore
                && context.target.getMutationRevision()
                    == sample.targetRevisionBefore
                && context.domain.loadoutRevision
                    == sample.domainRevisionBefore
                && context.domain.globalDirty === false
                && context.source.publishCount == 0
                && sample.counts.targetBefore == 1
                && sample.counts.sourceBefore == 1;
        }
        check(cleanFailure,
            "失败回滚允许 raw revision 单调推进，但领域 revision/dirty/publish 保持前值且零复制/丢失");
    }

    private static function runRollbackPoison(mode:String):Object {
        var context:Object = makeContext("刀");
        context.source.secondWriteMode = "false";
        context.source.rollbackMode = mode;
        var sourceRevisionBefore:Number =
            context.source.getMutationRevision();
        var targetRevisionBefore:Number =
            context.target.getMutationRevision();
        var domainRevisionBefore:Number =
            context.domain.loadoutRevision;
        var result:Object = executeSwap(context.request);
        return {
            context:context,
            result:result,
            sourceRevisionBefore:sourceRevisionBefore,
            targetRevisionBefore:targetRevisionBefore,
            domainRevisionBefore:domainRevisionBefore,
            counts:identityCounts(context)
        };
    }

    private static function testRollbackFalseAndThrowPoison():Void {
        var falseCase:Object = runRollbackPoison("false_after_write");
        var throwCase:Object = runRollbackPoison("throw_after_write");
        check(!falseCase.result.success
                && falseCase.result.error == "needs_reconcile"
                && falseCase.result.needsReconcile
                && falseCase.result.poison
                && falseCase.result.authorityState == "poison"
                && falseCase.result.rollbackOutcome == "false",
            "rollback false 保守返回 needs_reconcile/poison，绝不伪报成功");
        check(!throwCase.result.success
                && throwCase.result.error == "needs_reconcile"
                && throwCase.result.needsReconcile
                && throwCase.result.poison
                && throwCase.result.authorityState == "poison"
                && throwCase.result.rollbackOutcome == "throw",
            "rollback throw 保守返回 needs_reconcile/poison，绝不伪报成功");

        var cases:Array = [falseCase, throwCase];
        var conservative:Boolean = true;
        for (var i:Number = 0; i < cases.length; i++) {
            var sample:Object = cases[i];
            var context:Object = sample.context;
            conservative = conservative
                && context.target.getItem(context.targetSlot)
                    === context.targetBefore
                && context.source.getItem(context.sourceSlot)
                    === context.sourceBefore
                && context.source.getMutationRevision()
                    > sample.sourceRevisionBefore
                && context.target.getMutationRevision()
                    == sample.targetRevisionBefore
                && context.domain.loadoutRevision
                    == sample.domainRevisionBefore
                && context.domain.globalDirty === false
                && context.source.publishCount == 0
                && sample.counts.targetBefore == 1
                && sample.counts.sourceBefore == 1;
        }
        check(conservative,
            "rollback 返回值不可信时仍保留 exact before 身份与 journal，领域状态不被误提交");
    }
}
