import org.flashNight.arki.item.CharacterBuildService;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.item.itemCollection.DictCollection;
import org.flashNight.arki.item.itemCollection.DrugInventory;
import org.flashNight.arki.item.itemCollection.EquipmentInventory;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.UnitComponent.Initializer.RuntimeEquipmentProjection;
import org.flashNight.gesh.object.ObjectUtil;

/** CharacterBuildService 会话、只读 wire/projection、barrier 与 finalize 反例。 */
class org.flashNight.arki.item.CharacterBuildServiceTest {
    private static var _passed:Number = 0;
    private static var _failed:Number = 0;
    private static var SLOT_KEYS:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"
    ];
    private static var SLOT_DATA_KEYS:Array = [
        "头部装备数据", "上装装备数据", "下装装备数据", "手部装备数据",
        "脚部装备数据", "颈部装备数据", "长枪数据", "手枪数据",
        "手枪2数据", "刀数据", "手雷数据"
    ];
    // 仅在同步 focused 测试 helper 调用栈内设置，生产类不读取。
    private static var __activeMutationRoot:Object = null;

    public static function runAllTests():Void {
        _passed = 0;
        _failed = 0;
        trace("=== CharacterBuildServiceTest start ===");

        testInstallAndWireIdentity();
        testReadinessProbeIsPure();
        testSnapshotProjectionAndCooldown();
        testLoadoutTooltipAuthority();
        testCandidateProjectionAndUseAuthority();
        testCandidateEligibilityAndCooldownAuthority();
        testEffectiveInstanceQualificationFamilies();
        testDrugInputWriterPersistence();
        testItemSubmitWriterPersistence();
        testLongGunGrenadeWriterPersistence();
        testLootAcquireProjectsOnNewSession();
        testEquipmentMutationMoveSwapAndUnequip();
        testGrenadeMutationMergeAndFullBackpackUnequip();
        testDrugMutationMoveSwapMergeAndUnequip();
        testMutationPreflightFailuresAndNoSideEffects();
        testMutationRollbackAndDispatcherReentry();
        testMutationReconcileSnapshot();
        testMutationResponseLossAfterCommit();
        testMutationDegradedProjectionRequiresReconcile();
        testStatsCleanBarrierAndWireShape();
        testExactPauseAndDisconnectBarrier();
        testHostOnlyDetachRecovery();
        testNotReadyGenerationAndOrder();
        testOpenRejectsUnavailableLiveContext();
        testInitialTransientStateDoesNotDirty();
        testRuntimeSlotAliasStaysClean();
        testExternalDressupAdoptionAvoidsDuplicateRefresh();
        testInvalidProjectionFailsClosed();
        testOpenDetectsStaleLive();
        testStateOnlyDriftKeepsLiveMatched();
        testSemanticSignatureAndExactRefs();
        testFlushLiveBarrier();
        testCombatStateExcluded();
        testModifierCanonicalization();
        testDrugIsolationAndStaleContainers();
        testFinalizeGenerationAndCleanClose();
        testFinalizeDirtySuccessBranches();
        testFinalizeReceiptIdempotency();
        testFinalizeFailureAndUnknown();

        CharacterBuildService.testOnlyReset();
        trace("CharacterBuildServiceTest Tests Passed: " + _passed);
        trace("CharacterBuildServiceTest Tests Failed: " + _failed);
        trace("=== CharacterBuildServiceTest end ===");
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

    private static function sameFinalizeProof(left:Object,
                                               right:Object):Boolean {
        return left.success === right.success
            && left.v === right.v
            && left.active === right.active
            && left.sessionGeneration === right.sessionGeneration
            && left.loadoutRevision === right.loadoutRevision
            && left.liveRevision === right.liveRevision
            && left.liveRefreshDirty === right.liveRefreshDirty
            && left.drugRevision === right.drugRevision
            && left.loadoutChanged === right.loadoutChanged
            && left.drugChanged === right.drugChanged
            && left.slotKeys.join("|") == right.slotKeys.join("|")
            && left.operation === right.operation
            && left.closed === right.closed
            && left.liveChanged === right.liveChanged
            && left.persistence.success === right.persistence.success
            && left.persistence.changed === right.persistence.changed;
    }

    private static function equipment(name:String, level:Number,
                                       tier:String, mods, lastUpdate:Number):Object {
        var item:Object = {
            name:name,
            value:{
                level:level,
                tier:tier,
                mods:mods,
                shot:1,
                reloadCount:2,
                subweaponShot:3,
                subweaponReloadCount:4,
                当前战技:0,
                wa90变形:false,
                长柄形态:true
            },
            lastUpdate:lastUpdate
        };
        item.getData = function():Object {
            if (this.__effectiveDataSet === true) {
                if (this.__effectiveData == null) return null;
                var effectiveCopy:Object = {};
                for (var effectiveKey:String in this.__effectiveData) {
                    var effectiveValue = this.__effectiveData[effectiveKey];
                    if (effectiveValue instanceof Array) {
                        effectiveCopy[effectiveKey] = effectiveValue.slice();
                    } else if (effectiveValue != null
                            && typeof effectiveValue == "object") {
                        var nestedCopy:Object = {};
                        for (var nestedKey:String in effectiveValue) {
                            nestedCopy[nestedKey] = effectiveValue[nestedKey];
                        }
                        effectiveCopy[effectiveKey] = nestedCopy;
                    } else {
                        effectiveCopy[effectiveKey] = effectiveValue;
                    }
                }
                return effectiveCopy;
            }
            // 未显式绑定有效数据就是测试准备错误；不得把强化度静默冒充需求等级。
            return null;
        };
        return item;
    }

    private static function stack(name:String, quantity:Number):Object {
        var item:Object = {name:name, value:quantity, lastUpdate:1};
        item.getData = function():Object {
            if (this.__effectiveDataSet === true) {
                if (this.__effectiveData == null) return null;
                var effectiveCopy:Object = {};
                for (var effectiveKey:String in this.__effectiveData) {
                    var effectiveValue = this.__effectiveData[effectiveKey];
                    if (effectiveValue instanceof Array) {
                        effectiveCopy[effectiveKey] = effectiveValue.slice();
                    } else if (effectiveValue != null
                            && typeof effectiveValue == "object") {
                        var nestedCopy:Object = {};
                        for (var nestedKey:String in effectiveValue) {
                            nestedCopy[nestedKey] = effectiveValue[nestedKey];
                        }
                        effectiveCopy[effectiveKey] = nestedCopy;
                    } else {
                        effectiveCopy[effectiveKey] = effectiveValue;
                    }
                }
                return effectiveCopy;
            }
            return null;
        };
        return item;
    }

    private static function catalog(majorType:String, useName:String,
                                    requiredLevel):Object {
        return {
            type:majorType,
            use:useName,
            data:{level:requiredLevel}
        };
    }

    private static function setInstanceData(item:Object, data:Object):Object {
        item.__effectiveDataSet = true;
        item.__effectiveData = data;
        return item;
    }

    private static function bindInstanceData(container:Object,
                                             itemName:String,
                                             data:Object):Void {
        if (container == null || container.items == null) return;
        for (var key:String in container.items) {
            var item:Object = container.items[key];
            if (item != null && String(item.name) == itemName) {
                setInstanceData(item, data);
            }
        }
    }

    private static function setCatalogData(root:Object, itemName:String,
                                           data:Object):Void {
        root.itemCatalog[itemName] = data;
        if (data != null && typeof data.use == "string") {
            root.itemUses[itemName] = String(data.use);
        }
        bindInstanceData(root.物品栏.装备栏, itemName, data);
        bindInstanceData(root.物品栏.药剂栏, itemName, data);
        bindInstanceData(root.物品栏.背包, itemName, data);
    }

    private static function makeEquipmentContainer(items:Object):Object {
        var container:Object = {items:items, revision:1};
        container.getItem = function(key:String):Object {
            var item:Object = this.items[key];
            return item == undefined ? null : item;
        };
        installTransactionalFixture(container);
        return container;
    }

    private static function makeDrugContainer(revision:Number):Object {
        var container:Object = {revision:revision, items:{}};
        container.getMutationRevision = function():Number {
            return Number(this.revision);
        };
        container.getItem = function(key:String):Object {
            var item:Object = this.items[key];
            return item == undefined ? null : item;
        };
        installTransactionalFixture(container);
        return container;
    }

    private static function makeBackpackContainer(items:Object):Object {
        var container:Object = {
            revision:1,
            capacity:50,
            items:items == null ? {} : items
        };
        container.getMutationRevision = function():Number {
            return Number(this.revision);
        };
        container.getItem = function(key:String):Object {
            var item:Object = this.items[key];
            return item == undefined ? null : item;
        };
        installTransactionalFixture(container);
        return container;
    }

    private static function containerRevision(
        container:Object):Number {
        if (container != null
                && typeof container.getMutationRevision
                    == "function") {
            return Number(container.getMutationRevision());
        }
        return Number(container.revision);
    }

    private static function installTransactionalFixture(
        container:Object):Void {
        container.writeCount = 0;
        container.publishCount = 0;
        container.writeModes = [];
        container.publishObserver = null;
        if (typeof container.getMutationRevision != "function") {
            container.getMutationRevision = function():Number {
                return Number(this.revision);
            };
        }
        container.transactionWrite = function(key, item:Object):Boolean {
            var mode:String = this.writeModes[this.writeCount] == undefined
                ? "" : String(this.writeModes[this.writeCount]);
            this.writeCount++;
            if (mode == "false_before_write") return false;
            if (item == null) delete this.items[String(key)];
            else this.items[String(key)] = item;
            this.revision++;
            if (mode == "corrupt_after_write"
                    && item != null && typeof item.value == "object"
                    && item.value != null) {
                item.value.level = Number(item.value.level) + 1;
            }
            if (mode == "false_after_write") return false;
            if (mode == "throw_after_write") {
                throw "fixture_transaction_throw";
            }
            return true;
        };
        container.publishTransactionChange =
            function(key, changeKind:String):Void {
                this.publishCount++;
                if (typeof this.publishObserver == "function") {
                    this.publishObserver(this, key, changeKind);
                }
            };
    }

    private static function fixtureRoot(drugRevision:Number):Object {
        var items:Object = {};
        items["头部装备"] = equipment("观察头盔", 1, "一阶", ["导轨", "瞄具"], 10);
        items["长枪"] = equipment("观察长枪", 2, "", [], 20);
        items["手雷"] = stack("观察手雷", 5);
        var root:Object = {
            物品栏:{
                装备栏:makeEquipmentContainer(items),
                药剂栏:makeDrugContainer(drugRevision),
                背包:makeBackpackContainer({})
            },
            性别:"男",
            脸型:"男变装-基本脸型",
            发型:"发型-男式-黑韩式头",
            等级:10,
            快捷物品栏键1:49,
            快捷物品栏键2:50,
            快捷物品栏键3:51,
            快捷物品栏键4:52,
            药剂组切换键:54,
            _webPanelPauseLease:"lease.fixture.character-build",
            itemUses:{},
            itemCatalog:{}
        };
        root.存档系统 = {dirtyMark:false};
        root.keyshow = function(keyCode:Number):String {
            return "K" + keyCode;
        };
        root.getItemData = function(name):Object {
            var key:String = String(name);
            if (root.itemCatalog.hasOwnProperty(key)) {
                return root.itemCatalog[key];
            }
            return {
                type:"材料",
                use:String(root.itemUses[key] || ""),
                data:{level:1}
            };
        };
        setCatalogData(root, "观察头盔",
            catalog("防具", "头部装备", 1));
        setCatalogData(root, "观察长枪",
            catalog("武器", "长枪", 1));
        setCatalogData(root, "观察手雷",
            catalog("消耗品", "手雷", 1));
        installLiveFixture(root);
        return root;
    }

    private static function makeDispatcher(serial:Number):Object {
        return {
            serial:serial,
            publish:function():Void {},
            subscribe:function():String { return "fixture"; },
            destroy:function():Void {}
        };
    }

    private static function makeBuffManager(serial:Number):Object {
        return {
            serial:serial,
            update:function():Void {},
            addBuff:function():String { return "fixture"; },
            removeBuff:function():Boolean { return true; },
            destroy:function():Void {}
        };
    }

    private static function installLiveFixture(root:Object):Void {
        var gameworld:Object = {};
        var hero:Object = {
            _name:"fixtureHero",
            _parent:gameworld,
            version:1,
            性别:root.性别,
            脸型:root.脸型,
            发型:root.发型,
            aabbCollider:{},
            新版人物文字信息:{},
            dispatcher:makeDispatcher(0),
            buffManager:makeBuffManager(0),
            buff:{初始:function():Void {}, 更新:function():Void {}},
            读取基础被动效果:function():Void {},
            gotoAndStop:function():Void {},
            根据模式重新读取武器加成:function():Void {},
            装载主动战技:function():Void {},
            装载生命周期函数:function():Void {},
            完成生命周期函数装载:function():Void {},
            syncRefs:{},
            dressupRegistry:{},
            dressupRefreshing:false,
            重量:3,
            行走X速度:4,
            hp满血值:100,
            mp满血值:50,
            防御力:10,
            魔法抗性:{基础:10},
            主动战技:{},
            生命周期函数列表:[],
            格斗架势:false
        };
        root.控制目标 = hero._name;
        root.gameworld = gameworld;
        gameworld[hero._name] = hero;
        root.refreshCalls = 0;
        root.refreshSerial = 0;
        root.refreshMode = "success";
        root.refreshAlias = "";
        root.装备引用配置 = {刷新所有装扮:function():Void {}};
        root.根据等级计算值 = function():Number { return 1; };
        root.主角函数 = {
            创建主动战技槽位表:function():Object { return {}; },
            获取装备主动战技种类:function():String { return ""; }
        };
        root.敌人函数 = {魔法伤害种类:[]};
        root.玩家信息界面 = {刷新攻击模式:function():Void {}};
        root.UI系统 = {iconBar:{initialize:function():Void {}}};

        for (var i:Number = 0; i < SLOT_KEYS.length; i++) {
            var item:Object = root.物品栏.装备栏.getItem(SLOT_KEYS[i]);
            hero[SLOT_KEYS[i]] = item;
            hero[SLOT_DATA_KEYS[i]] = item == null ? null : item.getData();
        }
        RuntimeEquipmentProjection.beginCanonical(hero);
        RuntimeEquipmentProjection.completeCanonical(hero);
        root.刷新人物装扮 = function(targetName:String):Void {
            root.refreshCalls++;
            if (root.refreshMode == "throw") throw "fixture_refresh";
            var target:Object = root.gameworld[targetName];
            var oldHeadData:Object = target.头部装备数据;
            RuntimeEquipmentProjection.releaseAliases(target);
            if (root.refreshMode != "same_dispatcher") {
                target.dispatcher = makeDispatcher(++root.refreshSerial);
            }
            if (root.refreshMode != "same_buff") {
                target.buffManager = makeBuffManager(++root.refreshSerial);
            }
            for (var j:Number = 0; j < SLOT_KEYS.length; j++) {
                var next:Object = root.物品栏.装备栏.getItem(SLOT_KEYS[j]);
                target[SLOT_KEYS[j]] = next;
                target[SLOT_DATA_KEYS[j]] = next == null ? null : next.getData();
            }
            RuntimeEquipmentProjection.beginCanonical(target);
            if (root.refreshAlias == "longgun_to_knife") {
                var aliasOwner:Object = {
                    自机:target,
                    装备类型:"长枪",
                    装备名称:target.长枪.name,
                    版本号:target.version
                };
                var aliasIntent:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
                    aliasOwner, "刀");
                RuntimeEquipmentProjection.commitSlotAlias(aliasIntent);
            }
            RuntimeEquipmentProjection.completeCanonical(target);
            if (root.refreshMode == "reuse_data") target.头部装备数据 = oldHeadData;
            if (root.refreshMode == "slot_mismatch") target.头部装备 = {};
            if (root.refreshMode == "missing_data") target.头部装备数据 = null;
            target.重量 = root.refreshMode == "bad_number" ? Number.NaN : 3;
            target.行走X速度 = 4;
            target.hp满血值 = 100;
            target.mp满血值 = 50;
            target.防御力 = 10;
            target.魔法抗性 = root.refreshMode == "bad_shape" ? null : {基础:10};
            target.主动战技 = {};
            target.生命周期函数列表 = [];
            target.格斗架势 = root.refreshMode == "bad_tail";
            target.dressupRefreshing = root.refreshMode == "bad_tail";
            if (root.refreshMode == "wrong_parent") target._parent = {};
            if (root.refreshMode == "replace_hero") {
                root.lastRefreshHero = target;
                root.gameworld[targetName] = {_parent:root.gameworld};
            }
        };
    }

    private static function callbacks(globalResult, saveResult):Object {
        var state:Object = {
            globalResult:globalResult,
            saveResult:saveResult,
            globalDirty:globalResult === true,
            globalCalls:0,
            saveCalls:0
        };
        var value:Object = {state:state};
        value.isGlobalDirty = function() {
            state.globalCalls++;
            return state.globalResult;
        };
        value.flushNow = function() {
            state.saveCalls++;
            var result = state.saveResult;
            if (result === true) {
                state.globalDirty = false;
                state.globalResult = false;
            }
            return result;
        };
        return value;
    }

    private static function protocolCallbacks(root:Object,
                                              globalResult,
                                              saveResult):Object {
        var value:Object = callbacks(globalResult, saveResult);
        value.state.statsCalls = 0;
        value.state.releaseCalls = 0;
        value.state.projectCalls = 0;
        value.state.backpackSnapshotCalls = 0;
        value.state.drugCooldownCalls = 0;
        value.state.drugCooldownKey = "";
        value.state.drugReady = true;
        value.state.drugCooldownThrows = false;
        value.state.leaseInvalidations = 0;
        value.state.releasedLease = "";
        value.projectItem = function(item:Object):Object {
            value.state.projectCalls++;
            return fixtureItemProjection(root, item);
        };
        value.buildBackpackSnapshot = function():Object {
            value.state.backpackSnapshotCalls++;
            var bag:Object = root.物品栏.背包;
            var rows:Array = [];
            var facets:Array = [];
            var occupiedCount:Number = 0;
            for (var slot:Number = 0; slot < 50; slot++) {
                var item:Object = bag.getItem(String(slot));
                var row:Object = {
                    physicalSlot:slot,
                    occupied:item != null,
                    slotLease:"fixture.bag."
                        + containerRevision(bag) + "." + slot
                };
                if (item != null) {
                    occupiedCount++;
                    var effectiveData:Object = null;
                    try {
                        effectiveData = item.getData();
                    } catch (itemDataError) {
                        effectiveData = null;
                    }
                    var majorType:String = effectiveData == null
                            || effectiveData.type == undefined
                        ? "" : String(effectiveData.type);
                    var majorId:String = "other";
                    var majorLabel:String = "其他";
                    if (majorType == "武器") {
                        majorId = "weapon";
                        majorLabel = "武器";
                    } else if (majorType == "防具") {
                        majorId = "armor";
                        majorLabel = "防具";
                    } else if (majorType == "消耗品") {
                        majorId = "consumable";
                        majorLabel = "消耗品";
                    } else if (majorType == "材料") {
                        majorId = "material";
                        majorLabel = "材料";
                    } else if (majorType == "收集品") {
                        majorId = "collection";
                        majorLabel = "收集品";
                    }
                    var useName:String = effectiveData == null
                            || effectiveData.use == undefined
                            || String(effectiveData.use) == ""
                        ? "其他" : String(effectiveData.use);
                    var majorFacet:Object = fixtureFacetNode(
                        facets, majorId, majorLabel);
                    majorFacet.count++;
                    fixtureFacetNode(
                        majorFacet.children, useName, useName).count++;
                    var projection:Object =
                        fixtureItemProjection(root, item);
                    row.item = projection;
                    row.confirmProjection =
                        fixtureConfirmProjection(item, projection);
                }
                rows.push(row);
            }
            return {
                containerId:"背包",
                capacity:50,
                accessibleCapacity:50,
                viewCapacity:50,
                filterKey:"all",
                pageSizeHint:50,
                locked:false,
                snapshotSeq:value.state.backpackSnapshotCalls,
                containerEpoch:1,
                containerVersion:bag.getMutationRevision(),
                offset:0,
                limit:50,
                slots:rows,
                filterFacets:facets,
                filterItemCount:occupiedCount,
                setFacets:[],
                setFilterItemCount:0
            };
        };
        value.validateExternalSlotRef =
            function(ref:Object, checkCount:Boolean):Object {
                var bag:Object = root.物品栏.背包;
                var slot:Number = Number(ref.slot);
                var expected:String = "fixture.bag."
                    + containerRevision(bag) + "." + slot;
                var item:Object = bag.getItem(String(slot));
                if (ref.containerId != "背包"
                        || String(ref.expectedLease) != expected
                        || item == null) {
                    return {success:false, error:"stale_state"};
                }
                if (checkCount && (typeof item.value != "number"
                        || isNaN(item.value))) {
                    return {success:false, error:"stale_state"};
                }
                return {
                    success:true,
                    containerId:"背包",
                    inventory:bag,
                    slot:slot,
                    item:item
                };
            };
        value.invalidateExternalSlot =
            function(containerId:String, slot:Number):Void {
                value.state.leaseInvalidations++;
            };
        value.drugCooldownReady = function(key:String):Boolean {
            value.state.drugCooldownCalls++;
            value.state.drugCooldownKey = key;
            if (value.state.drugCooldownThrows) {
                throw "fixture_candidate_cooldown";
            }
            return value.state.drugReady === true;
        };
        value.statsSnapshot = function():Object {
            value.state.statsCalls++;
            return root.statsFixture;
        };
        value.releasePauseLease = function(leaseId):Boolean {
            value.state.releaseCalls++;
            value.state.releasedLease = String(leaseId);
            return value.state.releaseResult !== false;
        };
        value.state.releaseResult = true;
        return value;
    }

    private static function writerPersistenceCallbacks(root:Object):Object {
        var value:Object = protocolCallbacks(root, false, true);
        value.isGlobalDirty = function():Boolean {
            value.state.globalCalls++;
            return root.存档系统 != null
                && root.存档系统.dirtyMark === true;
        };
        value.flushNow = function():Boolean {
            value.state.saveCalls++;
            if (root.存档系统 == null
                    || root.存档系统.dirtyMark !== true) {
                return false;
            }
            root.存档系统.dirtyMark = false;
            return true;
        };
        return value;
    }

    private static function bindItemUtilFixture(root:Object,
                                                itemData:Object,
                                                materialNames:Object):Object {
        var receipt:Object = {
            inventory:_root.物品栏,
            collections:_root.收集品栏,
            save:_root.存档系统,
            itemData:ItemUtil.itemDataDict,
            equipment:ItemUtil.equipmentDict,
            materials:ItemUtil.materialDict,
            information:ItemUtil.informationMaxValueDict
        };
        _root.物品栏 = root.物品栏;
        _root.收集品栏 = root.收集品栏;
        _root.存档系统 = root.存档系统;
        ItemUtil.itemDataDict = itemData;
        ItemUtil.equipmentDict = {};
        ItemUtil.materialDict =
            materialNames == null ? {} : materialNames;
        ItemUtil.informationMaxValueDict = {};
        return receipt;
    }

    private static function restoreItemUtilFixture(receipt:Object):Void {
        ItemUtil.itemDataDict = receipt.itemData;
        ItemUtil.equipmentDict = receipt.equipment;
        ItemUtil.materialDict = receipt.materials;
        ItemUtil.informationMaxValueDict = receipt.information;
        _root.物品栏 = receipt.inventory;
        _root.收集品栏 = receipt.collections;
        _root.存档系统 = receipt.save;
    }

    private static function fixtureItemProjection(root:Object,
                                                  item:Object):Object {
        var equipmentLike:Boolean = typeof item.value == "object"
            && item.value != null;
        var data:Object = null;
        try {
            data = item.getData();
        } catch (itemDataError) {
            data = null;
        }
        var majorType:String = data == null || data.type == undefined
            ? "" : String(data.type);
        var useName:String = data == null || data.use == undefined
            ? String(root.itemUses[String(item.name)] || "")
            : String(data.use);
        var enhancementLevel:Number = equipmentLike
            ? Math.max(0, Math.floor(Number(item.value.level))) : 0;
        var maximum:Number = equipmentLike ? 15 : 0;
        return {
            name:String(item.name),
            displayName:String(item.name),
            icon:String(item.name),
            majorType:majorType,
            use:useName,
            actionType:"",
            weaponType:"",
            setId:"",
            setName:"",
            setOrder:0,
            itemKind:equipmentLike ? "equipment" : "stack",
            quantity:equipmentLike ? 1 : Number(item.value),
            enhancementLevel:enhancementLevel,
            maxEnhancementLevel:maximum,
            isMaxEnhancement:equipmentLike
                && enhancementLevel >= maximum,
            tierSlotAvailable:false,
            tierSlotUsed:false,
            modSlotCapacity:0,
            modSlotUsed:0,
            modSlots:[],
            modMeta:null,
            rarity:""
        };
    }

    private static function fixtureFacetNode(
        nodes:Array, id:String, label:String):Object {
        for (var i:Number = 0; i < nodes.length; i++) {
            if (String(nodes[i].id) == id) return nodes[i];
        }
        var node:Object = {
            id:id, label:label, order:0, count:0, children:[]
        };
        nodes.push(node);
        return node;
    }

    private static function facetUseCount(
        facets:Array, useName:String):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < facets.length; i++) {
            var children:Array = facets[i].children;
            for (var j:Number = 0; j < children.length; j++) {
                if (String(children[j].id) == useName) {
                    count += Number(children[j].count);
                }
            }
        }
        return count;
    }

    private static function fixtureConfirmProjection(
        item:Object, projection:Object):Object {
        var equipmentLike:Boolean =
            projection.itemKind == "equipment";
        var tier:String = equipmentLike
                && item.value.tier != undefined
            ? String(item.value.tier) : "";
        var mods = equipmentLike ? item.value.mods : null;
        var modSignature:String = mods instanceof Array
            ? mods.join("|") : (mods == null ? "" : String(mods));
        var lastUpdate:Number = Number(item.lastUpdate);
        if (isNaN(lastUpdate) || lastUpdate < 0) lastUpdate = 0;
        return {
            itemKind:String(projection.itemKind),
            name:String(projection.name),
            displayName:String(projection.displayName),
            quantity:Number(projection.quantity),
            enhancementLevel:Number(projection.enhancementLevel),
            rarity:String(projection.rarity),
            tier:tier,
            modSignature:modSignature,
            lastUpdate:lastUpdate
        };
    }

    private static function wireParams(panelId:String,
                                       requestId:String):Object {
        return {
            v:1,
            callId:7001,
            requestCallId:requestId,
            panelInstanceId:panelId,
            writeEpoch:19
        };
    }

    private static function tooltipWireParams(panelId:String,
                                              requestId:String):Object {
        var params:Object = wireParams(panelId, requestId);
        params.task = "cmd";
        params.action = "characterBuildTooltip";
        return params;
    }

    private static function hasOnlyKeys(value:Object,
                                        allowed:Object):Boolean {
        var seen:Object = {};
        for (var key:String in value) {
            if (allowed[key] !== true) return false;
            seen[key] = true;
        }
        for (var required:String in allowed) {
            if (seen[required] !== true) return false;
        }
        return true;
    }

    private static function commonWireKeys(extra:Object):Object {
        var allowed:Object = {
            task:true, v:true, success:true, callId:true, requestCallId:true,
            command:true, panelInstanceId:true, writeEpoch:true,
            sessionGeneration:true, loadoutRevision:true, liveRevision:true,
            drugRevision:true, liveRefreshDirty:true, active:true
        };
        for (var key:String in extra) allowed[key] = true;
        return allowed;
    }

    private static function itemProjectionWireKeys():Object {
        return {
            name:true, displayName:true, icon:true, majorType:true,
            use:true, actionType:true, weaponType:true, setId:true,
            setName:true, setOrder:true, itemKind:true, quantity:true,
            enhancementLevel:true, maxEnhancementLevel:true,
            isMaxEnhancement:true, tierSlotAvailable:true,
            tierSlotUsed:true, modSlotCapacity:true, modSlotUsed:true,
            modSlots:true, modMeta:true, rarity:true
        };
    }

    private static function openFixture(root:Object):Object {
        CharacterBuildService.testOnlyUseRoot(root);
        return CharacterBuildService.open();
    }

    private static function testReadinessProbeIsPure():Void {
        var root:Object = fixtureRoot(2);
        delete root._webPanelPauseLease;
        CharacterBuildService.testOnlyUseRoot(root);
        var ready:Boolean = CharacterBuildService.canOpenPanel();
        var beforeOpen:Object = CharacterBuildService.snapshot(0);
        root._webPanelPauseLease =
            "lease.fixture.character-build.readiness";
        var opened:Object = CharacterBuildService.open();
        check(ready && !beforeOpen.success
                && beforeOpen.error == "session_not_active"
                && opened.success
                && opened.sessionGeneration == 1,
            "canOpenPanel 不要求 pause lease，且不铸造 session/revision/authority");

        root = fixtureRoot(2);
        CharacterBuildService.testOnlyUseRoot(root);
        root.物品栏.药剂栏 = {};
        check(!CharacterBuildService.canOpenPanel()
                && !CharacterBuildService.snapshot(0).success,
            "canOpenPanel 对缺失容器能力 fail-closed 且保持只读");

        root = fixtureRoot(2);
        CharacterBuildService.testOnlyUseRoot(root);
        root.物品栏.装备栏.items["头部装备"] = {
            name:"畸形装备",
            value:"bad"
        };
        check(!CharacterBuildService.canOpenPanel()
                && !CharacterBuildService.snapshot(0).success,
            "canOpenPanel 执行 loadout scan 并拒绝畸形装配");

        root = fixtureRoot(2);
        CharacterBuildService.testOnlyUseRoot(root);
        root.gameworld = null;
        check(!CharacterBuildService.canOpenPanel()
                && !CharacterBuildService.snapshot(0).success,
            "canOpenPanel 验证 live context，不以容器存在冒充可打开");
    }

    private static function testInstallAndWireIdentity():Void {
        var root:Object = fixtureRoot(2);
        var callback:Object = protocolCallbacks(root, false, true);
        root.gameCommands = {};
        var captured:String = "";
        root.server = {
            sendSocketMessage:function(message:String):Boolean {
                captured = message;
                return true;
            }
        };
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        CharacterBuildService.install();

        check(typeof root.gameCommands.characterBuildSnapshot == "function"
                && typeof root.gameCommands.characterBuildCandidates == "function"
                && typeof root.gameCommands.characterBuildTooltip == "function"
                && typeof root.gameCommands.characterBuildEquipEquipment == "function"
                && typeof root.gameCommands.characterBuildUnequipEquipment == "function"
                && typeof root.gameCommands.characterBuildEquipDrug == "function"
                && typeof root.gameCommands.characterBuildUnequipDrug == "function"
                && typeof root.gameCommands.characterBuildFlushLive == "function"
                && typeof root.gameCommands.characterBuildStatsSnapshot == "function"
                && typeof root.gameCommands.characterBuildFinalize == "function",
            "install Web domain 注册 tooltip 及完整只读/四 mutation actions");
        check(typeof root.gameCommands.characterBuildRecoverDetach == "function",
            "install 另注册 Host-only orphan recovery action");
        check(root.gameCommands.characterBuildOpen == undefined,
            "install 仍不增加绕过 snapshot generation 的 open action");
        var webRecovery:Object = CharacterBuildService.execute(
            "recoverDetach", wireParams("workbench.instance.1",
                "character-build.web.recovery"));
        check(!webRecovery.success && webRecovery.error == "unsupported_cmd",
            "Web execute 业务命令路径不暴露 Host-only recoverDetach");

        var initialParams:Object = wireParams("workbench.instance.1",
            "character-build.fixture.1");
        var initial:Object = CharacterBuildService.execute(
            "snapshot", initialParams);
        check(initial.success && initial.task == "loadout_response"
                && initial.command == "snapshot"
                && initial.callId === initialParams.callId
                && initial.requestCallId === initialParams.requestCallId
                && initial.panelInstanceId === initialParams.panelInstanceId
                && initial.writeEpoch === initialParams.writeEpoch
                && initial.sessionGeneration > 0 && initial.active
                && initial.payload.equipment.length == 11
                && initial.payload.drugs.length == 8
                && initial.payload.drugLayout.v == 2
                && initial.payload.drugLayout.physicalSlotCount == 8,
            "首次无 generation snapshot 建立 session 并只回显 Host identity");
        check(hasOnlyKeys(initial, commonWireKeys({payload:true}))
                && initial.loadoutChanged == undefined
                && initial.drugChanged == undefined
                && initial.slotKeys == undefined,
            "snapshot wire 白名单化根字段，不泄漏 B0 internal state");

        var repeatedParams:Object = wireParams("workbench.instance.1",
            "character-build.fixture.retry");
        var repeated:Object = CharacterBuildService.execute(
            "snapshot", repeatedParams);
        check(repeated.success
                && repeated.sessionGeneration == initial.sessionGeneration
                && repeated.requestCallId == repeatedParams.requestCallId,
            "同 exact panel 的无 generation snapshot 幂等复用 generation");

        var conflicting:Object = CharacterBuildService.execute(
            "snapshot", wireParams("workbench.instance.2",
                "character-build.fixture.other"));
        check(!conflicting.success && conflicting.error == "session_active"
                && conflicting.panelInstanceId == "workbench.instance.2"
                && conflicting.sessionGeneration == initial.sessionGeneration,
            "active session 拒绝不同 panelInstanceId 的首次 snapshot");

        var exactParams:Object = wireParams("workbench.instance.1",
            "character-build.fixture.exact");
        exactParams.sessionGeneration = initial.sessionGeneration;
        var exact:Object = CharacterBuildService.execute("snapshot", exactParams);
        exactParams.sessionGeneration = initial.sessionGeneration + 1;
        var stale:Object = CharacterBuildService.execute("snapshot", exactParams);
        check(exact.success && !stale.success
                && stale.error == "stale_session",
            "后续 snapshot 必须携 exact panel 与 generation");

        var mutation:Object = CharacterBuildService.execute(
            "equipEquipment", {
                v:1, callId:9, requestCallId:"mutation", panelInstanceId:
                    "workbench.instance.1", writeEpoch:20
            });
        check(!mutation.success && mutation.error == "invalid_payload"
                && hasOnlyKeys(mutation, commonWireKeys({error:true})),
            "B2 mutation 已接线但严格拒绝缺 frozen 必填字段的请求");

        root.gameCommands.characterBuildSnapshot(exactParams);
        check(captured.indexOf('"task":"loadout_response"') >= 0
                && captured.indexOf('"command":"snapshot"') >= 0
                && captured.indexOf('"panelInstanceId":"workbench.instance.1"') >= 0,
            "安装 action 统一发送 task=loadout_response");
    }

    private static function testSnapshotProjectionAndCooldown():Void {
        var root:Object = fixtureRoot(4);
        var drug:Object = stack("观察药剂", 3);
        root.物品栏.药剂栏.items["0"] = drug;
        root.itemUses["观察药剂"] = "药剂";
        var callback:Object = protocolCallbacks(root, false, true);
        DrugInputService.resetSession();
        org.flashNight.arki.unit.Action.Skill.ManualCooldownService
            .resetForTests();
        org.flashNight.arki.unit.Action.Skill.ManualCooldownService
            .setSchedulerForTests(function(next:Function):Void {});
        org.flashNight.arki.unit.Action.Skill.ManualCooldownService.start(
            org.flashNight.arki.unit.Action.Skill.ManualCooldownService
                .drugKey(0), 90);

        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var snapshot:Object = CharacterBuildService.execute(
            "snapshot", wireParams("workbench.projection.1",
                "character-build.projection.1"));
        var payload:Object = snapshot.payload;
        var cooldown:Object = payload.drugs[0];
        var expectedRemaining:Number = cooldown.totalSteps
            * org.flashNight.arki.unit.Action.Skill.ManualCooldownService.FRAME_MS;
        check(snapshot.success && payload.equipment.length == 11
                && payload.equipment[0].slotKey == "头部装备"
                && payload.equipment[8].slotKey == "手枪2"
                && payload.equipment[8].label == "副手手枪"
                && payload.equipment[1].occupied === false
                && payload.drugs.length == 8
                && payload.drugLayout.v == 2
                && payload.drugLayout.bankCount == 2
                && payload.drugLayout.laneCount == 4
                && payload.drugLayout.physicalSlotCount == 8
                && payload.drugLayout.activeBank == 0
                && payload.drugLayout.switchKeyLabel == "K54",
            "snapshot 投影固定有序 11 装备 + 双组八药剂且空槽显式");
        check(payload.candidateFacets.scope == "all"
                && payload.candidateFacets.filterItemCount == 0
                && payload.candidateFacets.filterFacets.length == 0,
            "空背包仍显式投影已知 0 的构筑 facet counts");
        check(cooldown.occupied && cooldown.quantity == 3
                && cooldown.slot == 0 && cooldown.bank == 0
                && cooldown.lane == 0 && cooldown.active
                && cooldown.keyLabel == "K49" && !cooldown.ready
                && cooldown.remainingMs == expectedRemaining
                && cooldown.remainingMs
                    == (cooldown.totalSteps - cooldown.currentStep)
                        * org.flashNight.arki.unit.Action.Skill
                            .ManualCooldownService.FRAME_MS,
            "药剂 keyLabel 沿现役键链且 remainingMs 由 FRAME_MS 推算");
        var paired:Object = payload.drugs[4];
        check(paired.slot == 4 && paired.bank == 1 && paired.lane == 0
                && !paired.active && !paired.occupied && paired.quantity == 0
                && paired.item == undefined && paired.keyLabel == cooldown.keyLabel
                && paired.ready === cooldown.ready
                && paired.totalSteps === cooldown.totalSteps
                && paired.currentStep === cooldown.currentStep
                && paired.progressPercent === cooldown.progressPercent
                && paired.animationFrame === cooldown.animationFrame
                && paired.remainingMs === cooldown.remainingMs,
            "0/4 同 lane 槽共享完整冷却投影但保留独立物品与 active 归属");
        check(payload.drugLayout.switchCooldown.ready
                && payload.drugLayout.switchCooldown.remainingMs == 0,
            "组切换冷却以独立六字段快照投影且 ready 时 remainingMs 为零");
        check(payload.portrait.gender == "男"
                && payload.portrait.equipment["头部装备"] == "观察头盔"
                && payload.portrait.appearance["脸型"] == root.脸型
                && payload.portrait.appearance["发型"] == root.发型
                && payload.stateHealth == "ok"
                && payload.diagnostics.length == 0,
            "portrait 只投影 gender/equipment/appearance");

        var normalProjectItem:Function = callback.projectItem;
        callback.projectItem = function(item:Object):Object {
            var projected:Object = fixtureItemProjection(root, item);
            if (String(item.name) == "观察头盔") {
                projected.displayName = 73;
                projected.icon = {legacy:"bad"};
            }
            return projected;
        };
        var wrongTypeParams:Object = wireParams("workbench.projection.1",
            "character-build.projection.identity-wrong-type");
        wrongTypeParams.sessionGeneration = snapshot.sessionGeneration;
        var wrongType:Object = CharacterBuildService.execute(
            "snapshot", wrongTypeParams);
        callback.projectItem = function(item:Object):Object {
            var projected:Object = fixtureItemProjection(root, item);
            if (String(item.name) == "观察头盔") {
                projected.displayName = " Undefined ";
                projected.icon = "\t";
            }
            return projected;
        };
        var sentinelParams:Object = wireParams("workbench.projection.1",
            "character-build.projection.identity-sentinel");
        sentinelParams.sessionGeneration = snapshot.sessionGeneration;
        var sentinel:Object = CharacterBuildService.execute(
            "snapshot", sentinelParams);
        callback.projectItem = normalProjectItem;
        check(wrongType.success && sentinel.success
                && wrongType.payload.equipment[0].item.name == "观察头盔"
                && wrongType.payload.equipment[0].item.displayName == "观察头盔"
                && wrongType.payload.equipment[0].item.icon == "观察头盔"
                && sentinel.payload.equipment[0].item.displayName == "观察头盔"
                && sentinel.payload.equipment[0].item.icon == "观察头盔",
            "Character AS2 authority rejects wrong-type, blank and wrapped undefined identity projections");

        root.gameworld[root.控制目标].性别 = "未知";
        var degradedParams:Object = wireParams("workbench.projection.1",
            "character-build.projection.2");
        degradedParams.sessionGeneration = snapshot.sessionGeneration;
        var degraded:Object = CharacterBuildService.execute(
            "snapshot", degradedParams);
        check(degraded.success && degraded.payload.portrait.gender == "男"
                && degraded.payload.stateHealth == "degraded"
                && degraded.payload.diagnostics.join("|")
                    .indexOf("unknown_gender") >= 0,
            "未知性别可读降级，不使完整 snapshot 失败");

        callback.cooldownSnapshot = function(slot:Number):Void {
            throw "fixture_cooldown_getter";
        };
        degradedParams.requestCallId = "character-build.projection.cooldown";
        var cooldownFailure:Object = CharacterBuildService.execute(
            "snapshot", degradedParams);
        check(cooldownFailure.success
                && cooldownFailure.payload.drugs.length == 8
                && cooldownFailure.payload.stateHealth == "degraded"
                && cooldownFailure.payload.diagnostics.join("|")
                    .indexOf("drug_cooldown_unavailable:0") >= 0,
            "cooldown getter 异常降级为 diagnostics，仍返回完整 loadout_response");
        org.flashNight.arki.unit.Action.Skill.ManualCooldownService
            .resetForTests();
    }

    private static function testLoadoutTooltipAuthority():Void {
        var root:Object = fixtureRoot(3);
        var equipped:Object = equipment(
            "注释头盔", 3, "", [], 101);
        var drug:Object = stack("注释药剂", 4);
        var upperDrug:Object = stack("注释药剂", 2);
        root.物品栏.装备栏.items["头部装备"] = equipped;
        root.物品栏.药剂栏.items["1"] = drug;
        root.物品栏.药剂栏.items["7"] = upperDrug;

        var equipmentBase:Object = {
            name:"注释头盔", displayname:"注释头盔基础名",
            icon:"注释头盔基础图标", type:"防具", use:"头部装备",
            price:1200, description:"基础装备注释",
            data:{level:20, weight:2, defence:8, hp:12}
        };
        var equipmentEffective:Object = {
            name:"注释头盔", displayname:"注释头盔实例名",
            icon:"注释头盔实例图标", type:"防具", use:"头部装备",
            price:1200, description:"实例装备富注释",
            data:{level:20, weight:2, defence:11, hp:18}
        };
        var drugData:Object = {
            name:"注释药剂", displayname:"注释药剂显示名",
            icon:"注释药剂图标", type:"消耗品", use:"药剂",
            price:100, description:"药剂富注释",
            data:{heal:{value:50, target:"hp"}}
        };
        setCatalogData(root, "注释头盔", equipmentEffective);
        setCatalogData(root, "注释药剂", drugData);
        var itemData:Object = {};
        itemData["注释头盔"] = equipmentBase;
        itemData["注释药剂"] = drugData;
        var binding:Object = bindItemUtilFixture(root, itemData, {});
        var callback:Object = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);

        var panelId:String = "workbench.tooltip.1";
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(panelId,
                "character-build.tooltip.open"));
        var equipmentParams:Object = tooltipWireParams(
            panelId, "character-build.tooltip.equipment");
        equipmentParams.sessionGeneration = opened.sessionGeneration;
        equipmentParams.expectedLoadoutRevision = opened.loadoutRevision;
        equipmentParams.expectedDrugRevision = opened.drugRevision;
        equipmentParams.writeEpoch = 0;
        equipmentParams.slotKey = "头部装备";
        var equipmentTooltip:Object = CharacterBuildService.execute(
            "tooltip", equipmentParams);
        check(equipmentTooltip.success
                && equipmentTooltip.payload.target.kind == "equipment"
                && equipmentTooltip.payload.target.slotKey == "头部装备"
                && equipmentTooltip.payload.itemName == "注释头盔"
                && equipmentTooltip.payload.displayName == "注释头盔实例名"
                && equipmentTooltip.payload.iconName == "注释头盔实例图标"
                && equipmentTooltip.payload.itemType == "防具"
                && equipmentTooltip.payload.descHTML
                    .indexOf("实例装备富注释") >= 0
                && equipmentTooltip.payload.introHTML.length > 0
                && hasOnlyKeys(equipmentTooltip.payload, {
                    v:true, target:true, itemName:true, displayName:true,
                    iconName:true, itemType:true, descHTML:true,
                    introHTML:true
                })
                && hasOnlyKeys(equipmentTooltip.payload.target, {
                    kind:true, slotKey:true
                }),
            "tooltip 初始 writeEpoch=0 时返回 exact 实例富注释与 canonical shape");

        var extraParams:Object = {};
        for (var extraKey:String in equipmentParams) {
            extraParams[extraKey] = equipmentParams[extraKey];
        }
        extraParams.forgedSelector = "手枪";
        var extraEnvelope:Object = CharacterBuildService.execute(
            "tooltip", extraParams);
        check(!extraEnvelope.success
                && extraEnvelope.error == "invalid_payload",
            "tooltip AS2 权威入口独立拒绝多余键，不依赖 Host 预清洗");

        var stringRevisionParams:Object = {};
        var negativeEpochParams:Object = {};
        var missingRevisionParams:Object = {};
        var missingSelectorParams:Object = {};
        var bothSelectorParams:Object = {};
        for (var strictKey:String in equipmentParams) {
            stringRevisionParams[strictKey] = equipmentParams[strictKey];
            negativeEpochParams[strictKey] = equipmentParams[strictKey];
            if (strictKey != "expectedDrugRevision") {
                missingRevisionParams[strictKey] = equipmentParams[strictKey];
            }
            if (strictKey != "slotKey") {
                missingSelectorParams[strictKey] = equipmentParams[strictKey];
            }
            bothSelectorParams[strictKey] = equipmentParams[strictKey];
        }
        stringRevisionParams.expectedLoadoutRevision =
            String(equipmentParams.expectedLoadoutRevision);
        negativeEpochParams.writeEpoch = -1;
        bothSelectorParams.drugSlot = 1;
        var stringRevision:Object = CharacterBuildService.execute(
            "tooltip", stringRevisionParams);
        var negativeEpoch:Object = CharacterBuildService.execute(
            "tooltip", negativeEpochParams);
        var missingRevision:Object = CharacterBuildService.execute(
            "tooltip", missingRevisionParams);
        var missingSelector:Object = CharacterBuildService.execute(
            "tooltip", missingSelectorParams);
        var bothSelectors:Object = CharacterBuildService.execute(
            "tooltip", bothSelectorParams);
        check(!stringRevision.success
                && stringRevision.error == "invalid_payload"
                && !negativeEpoch.success
                && negativeEpoch.error == "invalid_payload"
                && !missingRevision.success
                && missingRevision.error == "invalid_payload"
                && !missingSelector.success
                && missingSelector.error == "invalid_payload"
                && !bothSelectors.success
                && bothSelectors.error == "invalid_payload",
            "tooltip AS2 exact envelope 接受 epoch 0，并拒绝负 epoch、字符串 revision、缺 revision 与零/双 selector");

        var drugParams:Object = tooltipWireParams(
            panelId, "character-build.tooltip.drug");
        drugParams.sessionGeneration = opened.sessionGeneration;
        drugParams.expectedLoadoutRevision = opened.loadoutRevision;
        drugParams.expectedDrugRevision = opened.drugRevision;
        drugParams.writeEpoch = 0;
        drugParams.drugSlot = 1;
        var drugTooltip:Object = CharacterBuildService.execute(
            "tooltip", drugParams);
        check(drugTooltip.success
                && drugTooltip.payload.target.kind == "drug"
                && drugTooltip.payload.target.drugSlot == 1
                && drugTooltip.payload.itemName == "注释药剂"
                && drugTooltip.payload.displayName == "注释药剂显示名"
                && drugTooltip.payload.iconName == "注释药剂图标"
                && drugTooltip.payload.itemType == "药剂"
                && drugTooltip.payload.descHTML.indexOf("药剂富注释") >= 0
                && drugTooltip.payload.introHTML.length > 0
                && hasOnlyKeys(drugTooltip.payload.target, {
                    kind:true, drugSlot:true
                }),
            "tooltip 初始 writeEpoch=0 的药剂槽复用 canonical composer 并保留药剂类型");

        drugParams.requestCallId = "character-build.tooltip.drug-upper";
        drugParams.drugSlot = 7;
        var upperDrugTooltip:Object = CharacterBuildService.execute(
            "tooltip", drugParams);
        drugParams.requestCallId = "character-build.tooltip.drug-invalid";
        drugParams.drugSlot = 8;
        var invalidDrugTooltip:Object = CharacterBuildService.execute(
            "tooltip", drugParams);
        check(upperDrugTooltip.success
                && upperDrugTooltip.payload.target.drugSlot == 7
                && upperDrugTooltip.payload.itemName == "注释药剂"
                && !invalidDrugTooltip.success
                && invalidDrugTooltip.error == "invalid_payload",
            "tooltip accepts physical drug slot 7 and rejects the ninth slot at the exact envelope gate");
        drugParams.drugSlot = 1;

        var emptyParams:Object = tooltipWireParams(
            panelId, "character-build.tooltip.empty");
        emptyParams.sessionGeneration = opened.sessionGeneration;
        emptyParams.expectedLoadoutRevision = opened.loadoutRevision;
        emptyParams.expectedDrugRevision = opened.drugRevision;
        emptyParams.slotKey = "上装装备";
        var empty:Object = CharacterBuildService.execute(
            "tooltip", emptyParams);
        check(!empty.success && empty.error == "stale_state",
            "tooltip 空槽 fail closed，不生成名称级猜测注释");

        root.物品栏.药剂栏.revision++;
        drugParams.requestCallId = "character-build.tooltip.old-revision";
        var oldRevision:Object = CharacterBuildService.execute(
            "tooltip", drugParams);
        check(!oldRevision.success && oldRevision.error == "stale_state"
                && oldRevision.drugRevision > opened.drugRevision,
            "tooltip 容器推进后拒绝旧 drug revision");

        var refreshParams:Object = wireParams(
            panelId, "character-build.tooltip.refresh");
        refreshParams.sessionGeneration = opened.sessionGeneration;
        var refreshed:Object = CharacterBuildService.execute(
            "snapshot", refreshParams);
        var replacement:Object = equipment(
            "注释头盔", 3, "", [], 101);
        setInstanceData(replacement, equipmentEffective);
        var originalGetData:Function = equipped.getData;
        var drifted:Boolean = false;
        equipped.getData = function():Object {
            var data:Object = originalGetData.call(this);
            if (!drifted) {
                drifted = true;
                root.物品栏.装备栏.items["头部装备"] = replacement;
            }
            return data;
        };
        equipmentParams.requestCallId =
            "character-build.tooltip.composer-drift";
        equipmentParams.sessionGeneration = refreshed.sessionGeneration;
        equipmentParams.expectedLoadoutRevision =
            refreshed.loadoutRevision;
        equipmentParams.expectedDrugRevision = refreshed.drugRevision;
        var composerDrift:Object = CharacterBuildService.execute(
            "tooltip", equipmentParams);
        check(drifted && !composerDrift.success
                && composerDrift.error == "stale_state"
                && root.物品栏.装备栏.getItem("头部装备")
                    === replacement
                && composerDrift.loadoutRevision
                    > refreshed.loadoutRevision,
            "TooltipComposer 期间同签名实例换 ref 仍被 post-compose exact fence 拒绝");

        CharacterBuildService.testOnlyReset();
        restoreItemUtilFixture(binding);
    }

    private static function testCandidateProjectionAndUseAuthority():Void {
        var root:Object = fixtureRoot(1);
        var headA:Object = equipment("候选头盔A", 1, "", [], 1);
        var pistol:Object = equipment("候选手枪", 1, "", [], 1);
        var drug:Object = stack("候选药剂", 5);
        var spoofed:Object = equipment("实例伪造头盔", 1, "", [], 1);
        var headB:Object = equipment("候选头盔B", 1, "", [], 1);
        var unknownUse:Object = equipment("未知用途装备", 1, "", [], 1);
        headA.use = "药剂";
        spoofed.use = "头部装备";
        root.物品栏.背包.items["1"] = headA;
        root.物品栏.背包.items["3"] = pistol;
        root.物品栏.背包.items["4"] = drug;
        root.物品栏.背包.items["6"] = spoofed;
        root.物品栏.背包.items["7"] = headB;
        root.物品栏.背包.items["8"] = unknownUse;
        setCatalogData(root, "候选头盔A",
            catalog("防具", "头部装备", 1));
        setCatalogData(root, "候选手枪",
            catalog("武器", "手枪", 1));
        setCatalogData(root, "候选药剂",
            catalog("消耗品", "药剂", 1));
        setCatalogData(root, "实例伪造头盔",
            catalog("材料", "材料", 1));
        setCatalogData(root, "候选头盔B",
            catalog("防具", "头部装备", 11));
        setCatalogData(root, "未知用途装备",
            catalog("武器", "未知用途", 1));
        var callback:Object = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams("workbench.candidates.1",
                "character-build.candidates.open"));
        check(opened.payload.candidateFacets.scope == "all"
                && opened.payload.candidateFacets.filterItemCount == 6
                && facetUseCount(
                    opened.payload.candidateFacets.filterFacets,
                    "头部装备") == 2
                && facetUseCount(
                    opened.payload.candidateFacets.filterFacets,
                    "手枪") == 1
                && facetUseCount(
                    opened.payload.candidateFacets.filterFacets,
                    "药剂") == 1
                && facetUseCount(
                    opened.payload.candidateFacets.filterFacets,
                    "未知用途") == 1
                && facetUseCount(
                    opened.payload.candidateFacets.filterFacets,
                    "刀") == 0,
            "初始 snapshot 复用完整背包 facets，分别保留非零与显式零候选类别");
        var projectionCallsBeforeMissing:Number =
            callback.state.projectCalls;
        var backpackCallsBeforeMissing:Number =
            callback.state.backpackSnapshotCalls;
        var missingExpected:Object = wireParams(
            "workbench.candidates.1",
            "character-build.candidates.missing-expected");
        missingExpected.sessionGeneration = opened.sessionGeneration;
        missingExpected.slotKey = "头部装备";
        var missingRejected:Object = CharacterBuildService.execute(
            "candidates", missingExpected);
        check(!missingRejected.success
                && missingRejected.error == "stale_state"
                && callback.state.projectCalls
                    == projectionCallsBeforeMissing
                && callback.state.backpackSnapshotCalls
                    == backpackCallsBeforeMissing,
            "candidates 缺 exact loadout/drug revisions 时零 projection 副作用");

        var headParams:Object = wireParams("workbench.candidates.1",
            "character-build.candidates.head");
        headParams.sessionGeneration = opened.sessionGeneration;
        headParams.expectedLoadoutRevision = opened.loadoutRevision;
        headParams.expectedDrugRevision = opened.drugRevision;
        headParams.candidateScope = "compatible";
        headParams.slotKey = "头部装备";
        var heads:Object = CharacterBuildService.execute(
            "candidates", headParams);
        check(heads.success && heads.payload.candidateScope == "compatible"
                && heads.payload.target.kind == "equipment"
                && heads.payload.candidates.length == 2
                && heads.payload.candidates[0].physicalSlot == 1
                && heads.payload.candidates[1].physicalSlot == 7
                && heads.payload.candidates[1].disabled
                && heads.payload.candidates[1].blockedReason
                    == "level_locked"
                && heads.payload.candidates[0].source.containerId == "背包"
                && heads.payload.candidates[0].source.slot == 1
                && heads.payload.candidates[0].source.expectedLease
                    == "fixture.bag.1.1",
            "装备候选按背包 physicalSlot 稳定排序并携 external source lease");
        check(heads.payload.candidates[0].item.name == "候选头盔A"
                && heads.payload.candidates[0].item.use == "头部装备"
                && heads.payload.candidates[0].item !== headA,
            "候选过滤读取实例 getData().use，不信临时 item.use 或泄漏引用");
        check(hasOnlyKeys(heads.payload.candidates[0], {
                    physicalSlot:true, disabled:true, blockedReason:true,
                    item:true, source:true, equipmentEligibility:true
                })
                && hasOnlyKeys(
                    heads.payload.candidates[0].equipmentEligibility, {
                        slots:true, blockedReason:true
                    })
                && heads.payload.candidates[0]
                    .equipmentEligibility.slots.length == 1
                && heads.payload.candidates[0]
                    .equipmentEligibility.slots[0] == "头部装备"
                && heads.payload.candidates[1]
                    .equipmentEligibility.blockedReason == "level_locked"
                && hasOnlyKeys(heads.payload.candidates[0].source, {
                    containerId:true, slot:true, expectedLease:true
                })
                && hasOnlyKeys(heads.payload.candidates[0].item,
                    itemProjectionWireKeys()),
            "compatible 装备候选携跨槽资格，row/资格/source/item 保持 exact 6/2/3/22 字段");

        var backpackParams:Object = wireParams("workbench.candidates.1",
            "character-build.candidates.backpack");
        backpackParams.sessionGeneration = opened.sessionGeneration;
        backpackParams.expectedLoadoutRevision = opened.loadoutRevision;
        backpackParams.expectedDrugRevision = opened.drugRevision;
        backpackParams.candidateScope = "backpack";
        backpackParams.slotKey = "头部装备";
        var backpack:Object = CharacterBuildService.execute(
            "candidates", backpackParams);
        check(backpack.success
                && backpack.payload.candidateScope == "backpack"
                && backpack.payload.candidates.length == 4
                && backpack.payload.candidates[0].physicalSlot == 1
                && !backpack.payload.candidates[0].disabled
                && backpack.payload.candidates[1].physicalSlot == 3
                && backpack.payload.candidates[1].disabled
                && backpack.payload.candidates[1].blockedReason
                    == "incompatible_item"
                && backpack.payload.candidates[2].physicalSlot == 4
                && backpack.payload.candidates[2].disabled
                && backpack.payload.candidates[3].physicalSlot == 7
                && backpack.payload.candidates[3].disabled
                && backpack.payload.candidates[3].blockedReason
                    == "level_locked"
                && backpack.payload.stateHealth == "degraded"
                && backpack.payload.diagnostics.indexOf(
                    "candidate_use_incompatible:6") >= 0
                && backpack.payload.diagnostics.indexOf(
                    "candidate_use_incompatible:8") >= 0,
            "backpack scope 返回全部结构有效物品、将数值型异类标成只读阻断，并拒绝伪装或未知 use 的装备实例");
        check(hasOnlyKeys(backpack.payload.candidates[0], {
                    physicalSlot:true, disabled:true, blockedReason:true,
                    item:true, source:true, equipmentEligibility:true
                })
                && hasOnlyKeys(
                    backpack.payload.candidates[0].equipmentEligibility, {
                        slots:true, blockedReason:true
                    })
                && backpack.payload.candidates[0]
                    .equipmentEligibility.slots.length == 1
                && backpack.payload.candidates[0]
                    .equipmentEligibility.slots[0] == "头部装备"
                && backpack.payload.candidates[0]
                    .equipmentEligibility.blockedReason == ""
                && backpack.payload.candidates[1]
                    .equipmentEligibility.slots.length == 2
                && backpack.payload.candidates[1]
                    .equipmentEligibility.slots[0] == "手枪"
                && backpack.payload.candidates[1]
                    .equipmentEligibility.slots[1] == "手枪2"
                && backpack.payload.candidates[2]
                    .equipmentEligibility.slots.length == 0
                && backpack.payload.candidates[3]
                    .equipmentEligibility.blockedReason == "level_locked",
            "装备 backpack row 携 AS2 盖章的 canonical 跨槽 eligibility，异类为空且等级锁定不下沉 Web");

        var overviewParams:Object = wireParams(
            "workbench.candidates.1",
            "character-build.candidates.overview");
        overviewParams.sessionGeneration = opened.sessionGeneration;
        overviewParams.expectedLoadoutRevision = opened.loadoutRevision;
        overviewParams.expectedDrugRevision = opened.drugRevision;
        overviewParams.candidateScope = "backpack";
        var overview:Object = CharacterBuildService.execute(
            "candidates", overviewParams);
        check(overview.success
                && hasOnlyKeys(overview.payload.target, {kind:true})
                && overview.payload.target.kind == "backpack"
                && overview.payload.candidates.length == 4
                && !overview.payload.candidates[0].disabled
                && !overview.payload.candidates[1].disabled
                && !overview.payload.candidates[2].disabled
                && overview.payload.candidates[3].disabled
                && overview.payload.candidates[3].blockedReason
                    == "level_locked"
                && overview.payload.candidates[1]
                    .equipmentEligibility.slots.length == 2
                && overview.payload.candidates[2]
                    .equipmentEligibility.slots.length == 0,
            "无 selector 的 backpack scope 返回 target=backpack 总览，并区分可装备、药剂与等级阻断");
        overviewParams.candidateScope = "compatible";
        overviewParams.requestCallId =
            "character-build.candidates.overview-compatible";
        var invalidOverview:Object = CharacterBuildService.execute(
            "candidates", overviewParams);
        check(!invalidOverview.success
                && invalidOverview.error == "invalid_payload",
            "无目标 candidates 只允许显式 backpack scope，不产生隐式 compatible 目标");

        var missingScopeParams:Object = wireParams("workbench.candidates.1",
            "character-build.candidates.scope-missing");
        missingScopeParams.sessionGeneration = opened.sessionGeneration;
        missingScopeParams.expectedLoadoutRevision = opened.loadoutRevision;
        missingScopeParams.expectedDrugRevision = opened.drugRevision;
        missingScopeParams.slotKey = "头部装备";
        var missingScope:Object = CharacterBuildService.execute(
            "candidates", missingScopeParams);
        missingScopeParams.candidateScope = "everything";
        missingScopeParams.requestCallId =
            "character-build.candidates.scope-invalid";
        var invalidScope:Object = CharacterBuildService.execute(
            "candidates", missingScopeParams);
        check(!missingScope.success && missingScope.error == "invalid_payload"
                && !invalidScope.success && invalidScope.error == "invalid_payload",
            "candidateScope 缺失或越出 compatible/backpack 闭集时拒绝");

        var pistolParams:Object = wireParams("workbench.candidates.1",
            "character-build.candidates.pistol");
        pistolParams.sessionGeneration = opened.sessionGeneration;
        pistolParams.expectedLoadoutRevision = opened.loadoutRevision;
        pistolParams.expectedDrugRevision = opened.drugRevision;
        pistolParams.candidateScope = "compatible";
        pistolParams.slotKey = "手枪2";
        var pistols:Object = CharacterBuildService.execute(
            "candidates", pistolParams);
        check(pistols.success && pistols.payload.candidates.length == 1
                && pistols.payload.candidates[0].physicalSlot == 3
                && pistols.payload.candidates[0]
                    .equipmentEligibility.slots.length == 2
                && pistols.payload.candidates[0]
                    .equipmentEligibility.slots[0] == "手枪"
                && pistols.payload.candidates[0]
                    .equipmentEligibility.slots[1] == "手枪2",
            "手枪2 接受实例有效 use=手枪，并在 compatible scope 签发双手枪槽白名单");

        var drugParams:Object = wireParams("workbench.candidates.1",
            "character-build.candidates.drug");
        drugParams.sessionGeneration = opened.sessionGeneration;
        drugParams.expectedLoadoutRevision = opened.loadoutRevision;
        drugParams.expectedDrugRevision = opened.drugRevision;
        drugParams.candidateScope = "compatible";
        drugParams.drugSlot = 2;
        var drugs:Object = CharacterBuildService.execute(
            "candidates", drugParams);
        check(drugs.success && drugs.payload.target.kind == "drug"
                && drugs.payload.target.drugSlot == 2
                && drugs.payload.candidates.length == 1
                && drugs.payload.candidates[0].physicalSlot == 4
                && callback.state.drugCooldownCalls == 1
                && callback.state.drugCooldownKey == "drug:2",
            "药剂候选只接受实例有效 use=药剂且单次读取 drugKey 冷却权威");

        drugParams.requestCallId = "character-build.candidates.drug-upper";
        drugParams.drugSlot = 6;
        var upperDrugs:Object = CharacterBuildService.execute(
            "candidates", drugParams);
        drugParams.requestCallId = "character-build.candidates.drug-invalid";
        drugParams.drugSlot = 8;
        var invalidDrugSlot:Object = CharacterBuildService.execute(
            "candidates", drugParams);
        check(upperDrugs.success
                && upperDrugs.payload.target.drugSlot == 6
                && callback.state.drugCooldownCalls == 2
                && callback.state.drugCooldownKey == "drug:2"
                && !invalidDrugSlot.success
                && invalidDrugSlot.error == "invalid_slot",
            "候选 physical slot 6 maps to shared lane 2 cooldown while slot 8 fails closed");
        drugParams.drugSlot = 2;

        var buildSnapshot:Function = callback.buildBackpackSnapshot;
        callback.buildBackpackSnapshot = function():Object {
            var drifted:Object = buildSnapshot();
            drifted.containerVersion++;
            return drifted;
        };
        var driftedSnapshot:Object = CharacterBuildService.execute(
            "snapshot", wireParams("workbench.candidates.1",
                "character-build.candidates.drifted-facets"));
        callback.buildBackpackSnapshot = buildSnapshot;
        check(driftedSnapshot.success
                && driftedSnapshot.payload.candidateFacets == undefined,
            "facet 与资格双扫描被 containerVersion fence 绑定，版本漂移降级 unknown");

        headParams.expectedLoadoutRevision = opened.loadoutRevision + 1;
        var stale:Object = CharacterBuildService.execute(
            "candidates", headParams);
        drugParams.slotKey = "头部装备";
        var ambiguous:Object = CharacterBuildService.execute(
            "candidates", drugParams);
        check(!stale.success && stale.error == "stale_state"
                && !ambiguous.success && ambiguous.error == "invalid_payload",
            "候选拒绝 stale revision 与装备/药剂双 selector");
    }

    private static function testCandidateEligibilityAndCooldownAuthority():Void {
        var root:Object = fixtureRoot(1);
        root.职业 = "枪手";
        var bag:Object = root.物品栏.背包;
        bag.capacity = 18;

        bag.items["0"] = equipment("强化高但目录低级", 99, "", [], 1);
        bag.items["1"] = equipment("强化低但目录高级", 0, "", [], 1);
        bag.items["2"] = equipment("头部错误目录类型", 1, "", [], 1);
        bag.items["3"] = stack("头部错误实例形状", 2);
        bag.items["4"] = equipment("目录缺失", 1, "", [], 1);
        bag.items["5"] = equipment("目录等级畸形", 1, "", [], 1);
        bag.items["6"] = equipment("正常其他部位", 1, "", [], 1);
        bag.items["7"] = stack("半枚手雷", 0.5);
        bag.items["8"] = stack("零手雷", 0);
        bag.items["9"] = stack("无限手雷", Number.POSITIVE_INFINITY);
        bag.items["10"] = equipment("对象手雷", 1, "", [], 1);
        bag.items["11"] = stack("等级阻断手雷", 1);
        bag.items["12"] = stack("四分之一药剂", 0.25);
        bag.items["13"] = stack("零药剂", 0);
        bag.items["14"] = stack("无限药剂", Number.POSITIVE_INFINITY);
        bag.items["15"] = equipment("对象药剂", 1, "", [], 1);
        bag.items["16"] = stack("负数药剂", -1);

        var enhancedLowRequirement:Object =
            catalog("防具", "头部装备", 2);
        enhancedLowRequirement.profession = "刀客";
        setCatalogData(root, "强化高但目录低级", enhancedLowRequirement);
        setCatalogData(root, "强化低但目录高级",
            catalog("防具", "头部装备", 11));
        setCatalogData(root, "头部错误目录类型",
            catalog("材料", "头部装备", 1));
        setCatalogData(root, "头部错误实例形状",
            catalog("防具", "头部装备", 1));
        setCatalogData(root, "目录缺失", null);
        setCatalogData(root, "目录等级畸形",
            catalog("防具", "头部装备", "1"));
        setCatalogData(root, "正常其他部位",
            catalog("防具", "上装装备", 1));
        setCatalogData(root, "半枚手雷",
            catalog("材料", "手雷", 1));
        setCatalogData(root, "零手雷",
            catalog("消耗品", "手雷", 1));
        setCatalogData(root, "无限手雷",
            catalog("消耗品", "手雷", 1));
        setCatalogData(root, "对象手雷",
            catalog("武器", "手雷", 1));
        setCatalogData(root, "等级阻断手雷",
            catalog("消耗品", "手雷", 11));
        setCatalogData(root, "四分之一药剂",
            catalog("材料", "药剂", 1));
        setCatalogData(root, "零药剂",
            catalog("消耗品", "药剂", 1));
        setCatalogData(root, "无限药剂",
            catalog("消耗品", "药剂", 1));
        setCatalogData(root, "对象药剂",
            catalog("防具", "药剂", 1));
        setCatalogData(root, "负数药剂",
            catalog("消耗品", "药剂", 1));

        var callback:Object = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams("workbench.candidates.rules",
                "character-build.candidates.rules.open"));
        check(opened.payload.candidateFacets == undefined,
            "相关 use 含畸形 type/value/level 时整组 counts 降级 unknown 而不伪造 0");

        var headParams:Object = wireParams(
            "workbench.candidates.rules",
            "character-build.candidates.rules.head");
        headParams.sessionGeneration = opened.sessionGeneration;
        headParams.expectedLoadoutRevision = opened.loadoutRevision;
        headParams.expectedDrugRevision = opened.drugRevision;
        headParams.candidateScope = "compatible";
        headParams.slotKey = "头部装备";
        var heads:Object = CharacterBuildService.execute(
            "candidates", headParams);
        var headDiagnostics:String = heads.payload.diagnostics.join("|");
        check(heads.success && heads.payload.candidates.length == 2
                && heads.payload.candidates[0].physicalSlot == 0
                && !heads.payload.candidates[0].disabled
                && heads.payload.candidates[0].blockedReason == ""
                && heads.payload.candidates[1].physicalSlot == 1
                && heads.payload.candidates[1].disabled
                && heads.payload.candidates[1].blockedReason
                    == "level_locked",
            "普通装备按实例有效需求等级阻断，绝不把强化度当角色等级门或追加职业门");
        check(headDiagnostics.indexOf("candidate_type_incompatible:2") >= 0
                && headDiagnostics.indexOf(
                    "candidate_value_incompatible:3") >= 0
                && headDiagnostics.indexOf(
                    "candidate_catalog_invalid:4") >= 0
                && headDiagnostics.indexOf(
                    "candidate_level_invalid:5") >= 0
                && headDiagnostics.indexOf(":6") < 0
                && heads.payload.stateHealth == "degraded"
                && callback.state.drugCooldownCalls == 0,
            "命中目标后的畸形 type/value/effective data/level 被排除并诊断，正常其他 use 静默过滤");

        var grenadeParams:Object = wireParams(
            "workbench.candidates.rules",
            "character-build.candidates.rules.grenade");
        grenadeParams.sessionGeneration = opened.sessionGeneration;
        grenadeParams.expectedLoadoutRevision = opened.loadoutRevision;
        grenadeParams.expectedDrugRevision = opened.drugRevision;
        grenadeParams.candidateScope = "compatible";
        grenadeParams.slotKey = "手雷";
        var grenades:Object = CharacterBuildService.execute(
            "candidates", grenadeParams);
        var grenadeDiagnostics:String =
            grenades.payload.diagnostics.join("|");
        check(grenades.success
                && grenades.payload.target.kind == "equipment"
                && grenades.payload.target.slotKey == "手雷"
                && grenades.payload.candidates.length == 2
                && grenades.payload.candidates[0].physicalSlot == 7
                && grenades.payload.candidates[0].item.itemKind == "stack"
                && grenades.payload.candidates[0].item.quantity == 0.5
                && !grenades.payload.candidates[0].disabled
                && grenades.payload.candidates[1].physicalSlot == 11
                && grenades.payload.candidates[1].disabled
                && grenades.payload.candidates[1].blockedReason
                    == "level_locked",
            "手雷只要求实例有效 use 与正有限数，允许非整数 stack 并保留等级阻断");
        check(grenadeDiagnostics.indexOf(
                    "candidate_value_incompatible:8") >= 0
                && grenadeDiagnostics.indexOf(
                    "candidate_value_incompatible:9") >= 0
                && grenadeDiagnostics.indexOf(
                    "candidate_value_incompatible:10") >= 0,
            "手雷零值、Infinity 与对象 value 均排除并诊断");

        var drugParams:Object = wireParams(
            "workbench.candidates.rules",
            "character-build.candidates.rules.drug-locked");
        drugParams.sessionGeneration = opened.sessionGeneration;
        drugParams.expectedLoadoutRevision = opened.loadoutRevision;
        drugParams.expectedDrugRevision = opened.drugRevision;
        drugParams.candidateScope = "compatible";
        drugParams.drugSlot = 3;
        callback.state.drugReady = false;
        var lockedDrugs:Object = CharacterBuildService.execute(
            "candidates", drugParams);
        var drugDiagnostics:String =
            lockedDrugs.payload.diagnostics.join("|");
        check(lockedDrugs.success
                && lockedDrugs.payload.candidates.length == 1
                && lockedDrugs.payload.candidates[0].physicalSlot == 12
                && lockedDrugs.payload.candidates[0].item.itemKind == "stack"
                && lockedDrugs.payload.candidates[0].item.quantity == 0.25
                && lockedDrugs.payload.candidates[0].disabled
                && lockedDrugs.payload.candidates[0].blockedReason
                    == "cooldown_active"
                && callback.state.drugCooldownCalls == 1
                && callback.state.drugCooldownKey == "drug:3",
            "药剂正有限数候选在单次 cooldown read 未就绪时保留 disabled row");
        check(drugDiagnostics.indexOf(
                    "candidate_value_incompatible:13") >= 0
                && drugDiagnostics.indexOf(
                    "candidate_value_incompatible:14") >= 0
                && drugDiagnostics.indexOf(
                    "candidate_value_incompatible:15") >= 0
                && drugDiagnostics.indexOf(
                    "candidate_value_incompatible:16") >= 0,
            "药剂零值、Infinity、对象与负数 value 均排除并诊断");

        callback.state.drugReady = true;
        drugParams.requestCallId =
            "character-build.candidates.rules.drug-ready";
        var readyDrugs:Object = CharacterBuildService.execute(
            "candidates", drugParams);
        check(readyDrugs.success
                && readyDrugs.payload.candidates.length == 1
                && !readyDrugs.payload.candidates[0].disabled
                && readyDrugs.payload.candidates[0].blockedReason == ""
                && callback.state.drugCooldownCalls == 2,
            "每次 fresh 药剂 candidates 恰好重读一次 cooldown，不按候选数量重复读取");

        callback.state.drugCooldownThrows = true;
        drugParams.requestCallId =
            "character-build.candidates.rules.drug-unavailable";
        var unavailableDrugs:Object = CharacterBuildService.execute(
            "candidates", drugParams);
        check(unavailableDrugs.success
                && unavailableDrugs.payload.candidates.length == 1
                && unavailableDrugs.payload.candidates[0].disabled
                && unavailableDrugs.payload.candidates[0].blockedReason
                    == "cooldown_unavailable"
                && unavailableDrugs.payload.diagnostics.join("|")
                    .indexOf("drug_cooldown_unavailable:3") >= 0
                && callback.state.drugCooldownCalls == 3,
            "cooldown getter 异常只读一次并降级为不可提交候选，不误判 ready");
    }

    private static function effectiveQualificationCatalog():Object {
        // 仅保留资格计算所需字段；PowerShell runner 会把这些值与生产 XML 锁在一起。
        var data:Object = {};
        data["M4A1"] = {
            name:"M4A1", displayname:"M4A1", icon:"M4A1",
            type:"武器", use:"长枪", weapontype:"突击步枪",
            data:{level:10, weight:4, power:95},
            data_ice:{level:41, power:420},
            data_fire:{level:41, power:420}
        };
        data["巨兽"] = {
            name:"巨兽", displayname:"巨兽", icon:"巨兽",
            type:"武器", use:"长枪", weapontype:"突击步枪",
            inherentTags:"下导轨挂点,侧导轨挂点,电力",
            data:{level:30, weight:7, power:165}
        };
        data["远古诛神剑"] = {
            name:"远古诛神剑", displayname:"牙狼剑", icon:"远古诛神剑",
            type:"武器", use:"刀", actiontype:"刀剑",
            data:{level:60, weight:10, power:1200}
        };
        data["沙漠军装背心"] = {
            name:"沙漠军装背心", displayname:"沙漠军装背心",
            icon:"沙漠军装背心", type:"防具", use:"上装装备",
            data:{level:10, weight:6, defence:60},
            data_3:{level:25, defence:180}
        };
        return data;
    }

    private static function effectiveQualificationConfig():Object {
        var tierNameToKey:Object = {};
        tierNameToKey["三阶"] = "data_3";
        tierNameToKey["墨冰"] = "data_ice";
        tierNameToKey["狱火"] = "data_fire";
        return {
            levelStatList:[1, 1, 1.06, 1.14, 1.24, 1.36, 1.5,
                1.66, 1.84, 2.04, 2.26, 2.5, 2.76, 3.04],
            decimalPropDict:{weight:1, rout:1, vampirism:1},
            tierNameToKeyDict:tierNameToKey,
            tierToMaterialDict:{},
            defaultTierDataDict:{},
            tierDataList:["data_3", "data_ice", "data_fire"]
        };
    }

    private static function bindEffectiveQualificationFixture(
        root:Object, itemData:Object):Object {
        var receipt:Object = bindItemUtilFixture(root, itemData, {});
        ItemUtil.equipmentDict = {};
        ItemUtil.equipmentDict["M4A1"] = true;
        ItemUtil.equipmentDict["巨兽"] = true;
        ItemUtil.equipmentDict["远古诛神剑"] = true;
        ItemUtil.equipmentDict["沙漠军装背心"] = true;
        return receipt;
    }

    private static function installEffectiveRootCatalog(
        root:Object, itemData:Object):Void {
        for (var itemName:String in itemData) {
            setCatalogData(root, itemName, itemData[itemName]);
        }
    }

    private static function testEffectiveInstanceQualificationFamilies():Void {
        var savedConfig:Object = ObjectUtil.cloneFast(
            EquipmentConfigManager.getFullConfig());
        EquipmentUtil.loadEquipmentConfig(effectiveQualificationConfig());
        var modDict:Object = ModRegistry.getModDict();
        var savedChip:Object = modDict["电脑芯片"];
        var savedEquipmentModDict:Object = EquipmentUtil.modDict;
        modDict["电脑芯片"] = {
            name:"电脑芯片",
            use:"头部装备,上装装备,下装装备,手部装备,脚部装备,刀,手枪,长枪",
            stats:{flat:{level:-3}},
            requireTags:"电力",
            tag:"等级校正"
        };
        EquipmentUtil.modDict = modDict;
        var itemData:Object = effectiveQualificationCatalog();

        var root:Object = fixtureRoot(1);
        root.等级 = 27;
        __activeMutationRoot = root;
        var bag:Object = root.物品栏.背包;
        var ordinary:BaseItem = new BaseItem(
            "M4A1", {level:13, tier:"", mods:[]}, 21);
        var chipped:BaseItem = new BaseItem(
            "巨兽", {level:4, tier:"", mods:["电脑芯片"]}, 22);
        bag.items["0"] = ordinary;
        bag.items["1"] = chipped;
        var binding:Object = bindEffectiveQualificationFixture(root, itemData);
        installEffectiveRootCatalog(root, itemData);
        check(ordinary.getData().data.level == 10
                && new BaseItem("巨兽", {
                    level:4, tier:"", mods:[]}, 20).getData().data.level == 30
                && chipped.getData().data.level == 27,
            "真实 BaseItem/EquipmentCalculator：强化 +13 不改需求 10，电脑芯片把巨兽 30 降为 27");

        var panelId:String = "workbench.effective.chip";
        var fixture:Object = mutationFixture(root, panelId);
        var opened:Object = fixture.opened;
        var candidateParams:Object = wireParams(
            panelId, "character-build.effective.chip.candidates");
        candidateParams.sessionGeneration = opened.sessionGeneration;
        candidateParams.expectedLoadoutRevision = opened.loadoutRevision;
        candidateParams.expectedDrugRevision = opened.drugRevision;
        candidateParams.candidateScope = "backpack";
        candidateParams.slotKey = "长枪";
        var candidates:Object = CharacterBuildService.execute(
            "candidates", candidateParams);
        var ordinaryRow:Object = findCandidate(candidates, "M4A1", 0);
        var chipRow:Object = findCandidate(candidates, "巨兽", 1);
        check(candidates.success && ordinaryRow != null
                && !ordinaryRow.disabled && chipRow != null
                && !chipRow.disabled
                && chipRow.equipmentEligibility.slots.length == 1
                && chipRow.equipmentEligibility.slots[0] == "长枪"
                && chipRow.equipmentEligibility.blockedReason == "",
            "通用装备背包中普通强化与芯片实例均按 getData 的有效需求等级盖章");
        var chipParams:Object = equipmentMutationParams(
            "equipEquipment", panelId, opened, "长枪", 1);
        chipParams.requestCallId =
            "character-build.effective.chip.allowed";
        var chipEquipped:Object = CharacterBuildService.execute(
            "equipEquipment", chipParams);
        check(chipEquipped.success
                && root.物品栏.装备栏.getItem("长枪") === chipped,
            "27 级角色可装备真实实例计算为 27 的电脑芯片巨兽");
        restoreItemUtilFixture(binding);

        root = fixtureRoot(1);
        root.等级 = 27;
        __activeMutationRoot = root;
        bag = root.物品栏.背包;
        var iceCoated:BaseItem = new BaseItem(
            "M4A1", {level:3, tier:"墨冰", mods:[]}, 23);
        var fireCoated:BaseItem = new BaseItem(
            "M4A1", {level:2, tier:"狱火", mods:[]}, 24);
        var garo:BaseItem = new BaseItem(
            "远古诛神剑", {level:1, tier:"", mods:[]}, 25);
        bag.items["0"] = iceCoated;
        bag.items["1"] = fireCoated;
        bag.items["2"] = garo;
        binding = bindEffectiveQualificationFixture(root, itemData);
        installEffectiveRootCatalog(root, itemData);
        check(iceCoated.getData().data.level == 41
                && fireCoated.getData().data.level == 41
                && garo.getData().data.level == 60,
            "真实 BaseItem/EquipmentCalculator：墨冰/狱火 M4A1 为 41，普通牙狼为 60");

        panelId = "workbench.effective.coating";
        fixture = mutationFixture(root, panelId);
        opened = fixture.opened;
        candidateParams = wireParams(
            panelId, "character-build.effective.coating.candidates");
        candidateParams.sessionGeneration = opened.sessionGeneration;
        candidateParams.expectedLoadoutRevision = opened.loadoutRevision;
        candidateParams.expectedDrugRevision = opened.drugRevision;
        candidateParams.candidateScope = "backpack";
        candidateParams.slotKey = "长枪";
        candidates = CharacterBuildService.execute(
            "candidates", candidateParams);
        var iceRow:Object = findCandidate(candidates, "M4A1", 0);
        var fireRow:Object = findCandidate(candidates, "M4A1", 1);
        var garoRow:Object = findCandidate(
            candidates, "远古诛神剑", 2);
        check(iceRow != null && iceRow.disabled
                && iceRow.blockedReason == "level_locked"
                && iceRow.equipmentEligibility.blockedReason
                    == "level_locked"
                && fireRow != null && fireRow.disabled
                && fireRow.blockedReason == "level_locked"
                && fireRow.equipmentEligibility.blockedReason
                    == "level_locked"
                && garoRow != null && garoRow.disabled
                && garoRow.blockedReason == "incompatible_item"
                && garoRow.equipmentEligibility.slots.length == 1
                && garoRow.equipmentEligibility.slots[0] == "刀"
                && garoRow.equipmentEligibility.blockedReason
                    == "level_locked",
            "一份通用装备背包同时盖章墨冰/狱火长枪与普通牙狼的实例有效等级");
        var bagWrites:Number = bag.writeCount;
        var equipmentWrites:Number = root.物品栏.装备栏.writeCount;
        var blockedParams:Object = equipmentMutationParams(
            "equipEquipment", panelId, opened, "长枪", 0);
        blockedParams.requestCallId =
            "character-build.effective.coating.blocked";
        var blocked:Object = CharacterBuildService.execute(
            "equipEquipment", blockedParams);
        check(!blocked.success && blocked.error == "level_locked"
                && bag.writeCount == bagWrites
                && root.物品栏.装备栏.writeCount == equipmentWrites
                && bag.getItem("0") === iceCoated,
            "涂层有效需求超限在 mutation 前 fail closed 且零写入");
        restoreItemUtilFixture(binding);

        root = fixtureRoot(1);
        root.等级 = 22;
        __activeMutationRoot = root;
        bag = root.物品栏.背包;
        var desertTier:BaseItem = new BaseItem(
            "沙漠军装背心", {level:5, tier:"三阶", mods:[]}, 31);
        bag.items["0"] = desertTier;
        binding = bindEffectiveQualificationFixture(root, itemData);
        installEffectiveRootCatalog(root, itemData);
        check(desertTier.getData().data.level == 25,
            "真实 BaseItem/EquipmentCalculator 将沙漠军装背心基础 10 投影为三阶 25");
        panelId = "workbench.effective.desert.blocked";
        fixture = mutationFixture(root, panelId);
        opened = fixture.opened;
        candidateParams = wireParams(
            panelId, "character-build.effective.desert.candidates");
        candidateParams.sessionGeneration = opened.sessionGeneration;
        candidateParams.expectedLoadoutRevision = opened.loadoutRevision;
        candidateParams.expectedDrugRevision = opened.drugRevision;
        candidateParams.candidateScope = "backpack";
        candidateParams.slotKey = "上装装备";
        candidates = CharacterBuildService.execute(
            "candidates", candidateParams);
        var desertRow:Object = findCandidate(
            candidates, "沙漠军装背心", 0);
        bagWrites = bag.writeCount;
        equipmentWrites = root.物品栏.装备栏.writeCount;
        blockedParams = equipmentMutationParams(
            "equipEquipment", panelId, opened, "上装装备", 0);
        blockedParams.requestCallId =
            "character-build.effective.desert.blocked";
        blocked = CharacterBuildService.execute(
            "equipEquipment", blockedParams);
        check(desertRow != null && desertRow.disabled
                && desertRow.blockedReason == "level_locked"
                && desertRow.equipmentEligibility.slots.length == 1
                && desertRow.equipmentEligibility.slots[0] == "上装装备"
                && desertRow.equipmentEligibility.blockedReason
                    == "level_locked"
                && !blocked.success && blocked.error == "level_locked"
                && bag.writeCount == bagWrites
                && root.物品栏.装备栏.writeCount == equipmentWrites,
            "22 级角色对基础 10/三阶有效 25 的真实沙漠军装实例一致阻断");
        restoreItemUtilFixture(binding);

        root = fixtureRoot(1);
        root.等级 = 25;
        __activeMutationRoot = root;
        bag = root.物品栏.背包;
        desertTier = new BaseItem(
            "沙漠军装背心", {level:5, tier:"三阶", mods:[]}, 32);
        bag.items["0"] = desertTier;
        binding = bindEffectiveQualificationFixture(root, itemData);
        installEffectiveRootCatalog(root, itemData);
        panelId = "workbench.effective.desert.allowed";
        fixture = mutationFixture(root, panelId);
        opened = fixture.opened;
        var allowedParams:Object = equipmentMutationParams(
            "equipEquipment", panelId, opened, "上装装备", 0);
        allowedParams.requestCallId =
            "character-build.effective.desert.allowed";
        var desertEquipped:Object = CharacterBuildService.execute(
            "equipEquipment", allowedParams);
        check(desertEquipped.success
                && root.物品栏.装备栏.getItem("上装装备") === desertTier,
            "25 级角色可装备实例有效需求 25 的真实三阶沙漠军装");
        restoreItemUtilFixture(binding);

        if (savedChip == undefined) delete modDict["电脑芯片"];
        else modDict["电脑芯片"] = savedChip;
        EquipmentUtil.modDict = savedEquipmentModDict;
        EquipmentUtil.loadEquipmentConfig(savedConfig);
        __activeMutationRoot = null;
    }

    private static function findCandidate(
        response:Object,
        itemName:String,
        physicalSlot:Number):Object {
        if (response == null || response.payload == null
                || !(response.payload.candidates
                    instanceof Array)) {
            return null;
        }
        var rows:Array = response.payload.candidates;
        for (var i:Number = 0; i < rows.length; i++) {
            var row:Object = rows[i];
            if (row != null && row.item != null
                    && String(row.item.name) == itemName
                    && (physicalSlot < 0
                        || Number(row.physicalSlot)
                            == physicalSlot)) {
                return row;
            }
        }
        return null;
    }

    private static function countCandidates(
        response:Object,
        itemName:String):Number {
        if (response == null || response.payload == null
                || !(response.payload.candidates
                    instanceof Array)) {
            return 0;
        }
        var count:Number = 0;
        var rows:Array = response.payload.candidates;
        for (var i:Number = 0; i < rows.length; i++) {
            if (rows[i] != null && rows[i].item != null
                    && String(rows[i].item.name)
                        == itemName) {
                count++;
            }
        }
        return count;
    }

    private static function testDrugInputWriterPersistence():Void {
        var drugName:String = "B4消费落盘药剂";
        var root:Object = fixtureRoot(1);
        var drugs:DrugInventory = new DrugInventory(null, 8);
        drugs.transactionWrite(0, new BaseItem(drugName, 1, 1));
        root.物品栏.药剂栏 = drugs;
        registerCatalog(root, drugName, "消耗品", "药剂", 1);
        root.快捷物品栏0 = drugName;
        root.吃药冷却时间 = 100;
        root.使用药剂 = function(itemName:String):Void {};
        root.发布消息 = function(message:String):Void {};
        root.存档系统.dirtyMark = false;

        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(
            function(next:Function):Void {});
        var callback:Object =
            writerPersistenceCallbacks(root);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.writer.drug.1",
                "character-build.writer.drug.open"));

        var consumed:Object = DrugInputService.updateSlot(
            {hp:100}, 0, true, true,
            drugs, root, null);
        check(opened.success && consumed.used
                && consumed.depleted
                && drugs.getItem("0") == null
                && root.存档系统.dirtyMark,
            "DrugInputService 成功耗尽真实 DrugInventory 后独立标记 dirty");

        var finalized:Object = CharacterBuildService.finalize(
            opened.sessionGeneration,
            opened.loadoutRevision);
        var reopened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.writer.drug.2",
                "character-build.writer.drug.reopen"));
        check(finalized.success && finalized.closed
                && finalized.persistence.success
                && finalized.persistence.changed
                && callback.state.globalCalls == 1
                && callback.state.saveCalls == 1
                && !root.存档系统.dirtyMark
                && reopened.success
                && reopened.sessionGeneration
                    > opened.sessionGeneration
                && reopened.drugRevision
                    == drugs.getMutationRevision()
                && !reopened.payload.drugs[0].occupied,
            "DrugInputService writer 经 finalize flush changed，并由新 session 建立耗尽 baseline");

        CharacterBuildService.testOnlyReset();
        ManualCooldownService.resetForTests();
    }

    private static function testItemSubmitWriterPersistence():Void {
        var materialName:String = "B4提交材料";
        var bagName:String = "B4提交背包药剂";
        var drugName:String = "B4提交药剂栏药剂";
        var root:Object = fixtureRoot(1);
        var backpack:ArrayInventory =
            new ArrayInventory(null, 50);
        var drugs:DrugInventory =
            new DrugInventory(null, 8);
        backpack.transactionWrite(
            0, new BaseItem(bagName, 3, 1));
        drugs.transactionWrite(
            0, new BaseItem(drugName, 3, 1));
        root.物品栏.背包 = backpack;
        root.物品栏.药剂栏 = drugs;
        var initialMaterials:Object = {};
        initialMaterials[materialName] = 3;
        root.收集品栏 = {
            材料:new DictCollection(
                initialMaterials),
            情报:new DictCollection({})
        };
        registerCatalog(
            root, bagName, "消耗品", "药剂", 1);
        registerCatalog(
            root, drugName, "消耗品", "药剂", 1);
        root.存档系统.dirtyMark = false;

        var itemData:Object = {};
        itemData[materialName] = {
            name:materialName,
            type:"材料",
            use:"材料",
            data:{level:1}
        };
        itemData[bagName] = {
            name:bagName,
            type:"消耗品",
            use:"药剂",
            data:{level:1}
        };
        itemData[drugName] = {
            name:drugName,
            type:"消耗品",
            use:"药剂",
            data:{level:1}
        };
        var materialNames:Object = {};
        materialNames[materialName] = true;
        var binding:Object = bindItemUtilFixture(
            root, itemData, materialNames);
        var callback:Object =
            writerPersistenceCallbacks(root);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.writer.submit.1",
                "character-build.writer.submit.open"));

        var rejectedSubmit:Boolean = ItemUtil.submit([
            {name:materialName, value:99}
        ]);
        var emptySubmit:Boolean = ItemUtil.submit([]);
        var cleanAfterNoWrite:Boolean =
            !root.存档系统.dirtyMark;
        var submitted:Boolean = ItemUtil.submit([
            {name:materialName, value:1},
            {name:bagName, value:1},
            {name:drugName, value:1}
        ]);
        check(opened.success
                && !rejectedSubmit && emptySubmit
                && cleanAfterNoWrite && submitted
                && root.收集品栏.材料
                    .getValue(materialName) == 2
                && backpack.getItem("0").value == 2
                && drugs.getItem("0").value == 2
                && root.存档系统.dirtyMark,
            "ItemUtil.submit 同次真实扣材料/背包/药剂栏后独立标记 dirty");

        var finalized:Object = CharacterBuildService.finalize(
            opened.sessionGeneration,
            opened.loadoutRevision);
        var reopened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.writer.submit.2",
                "character-build.writer.submit.reopen"));
        var candidatesParams:Object = wireParams(
            "workbench.writer.submit.2",
            "character-build.writer.submit.candidates");
        candidatesParams.sessionGeneration =
            reopened.sessionGeneration;
        candidatesParams.expectedLoadoutRevision =
            reopened.loadoutRevision;
        candidatesParams.expectedDrugRevision =
            reopened.drugRevision;
        candidatesParams.candidateScope = "compatible";
        candidatesParams.drugSlot = 1;
        var candidates:Object = CharacterBuildService.execute(
            "candidates", candidatesParams);
        var submittedBag:Object = findCandidate(
            candidates, bagName, 0);
        check(finalized.success
                && finalized.persistence.changed
                && callback.state.saveCalls == 1
                && !root.存档系统.dirtyMark
                && reopened.success
                && reopened.sessionGeneration
                    > opened.sessionGeneration
                && reopened.payload.drugs[0].occupied
                && reopened.payload.drugs[0]
                    .item.quantity == 2
                && submittedBag != null
                && submittedBag.item.quantity == 2,
            "ItemUtil.submit writer 经 finalize flush changed，新 session 读取三类扣除后的 baseline");

        CharacterBuildService.testOnlyReset();
        restoreItemUtilFixture(binding);
    }

    /**
     * 完整长枪战技依赖 battle/XFL；这里执行源码的 exact fallback primitive，
     * runner 同时静态钉住 singleSubmit 失败后的受控自机条件、两条 dirty 写和 remove。
     */
    private static function applyLongGunFallbackPrimitive(
        root:Object, unit:Object):Boolean {
        if (root.控制目标 !== unit._name) return false;
        var equipment:Object = root.物品栏.装备栏;
        var grenade:Object = equipment.getItem("手雷");
        if (grenade == null
                || grenade.name != unit.其他消耗物品) {
            return false;
        }
        if (!isNaN(grenade.value) && grenade.value > 1) {
            grenade.value -= 1;
            if (root.存档系统) {
                root.存档系统.dirtyMark = true;
            }
            return true;
        }
        equipment.remove("手雷");
        if (root.存档系统) {
            root.存档系统.dirtyMark = true;
        }
        root.刷新人物装扮(unit._name);
        return true;
    }

    private static function testLongGunGrenadeWriterPersistence():Void {
        var root:Object = fixtureRoot(1);
        var previousEquipment:Object =
            root.物品栏.装备栏;
        var realEquipment:EquipmentInventory =
            new EquipmentInventory(null);
        var equipmentItems:Object =
            realEquipment.getItems();
        for (var slotIndex:Number = 0;
                slotIndex < SLOT_KEYS.length;
                slotIndex++) {
            var slotKey:String =
                String(SLOT_KEYS[slotIndex]);
            var equipped:Object =
                previousEquipment.getItem(slotKey);
            if (equipped != null) {
                equipmentItems[slotKey] = equipped;
            }
        }
        root.物品栏.装备栏 = realEquipment;
        installLiveFixture(root);
        var grenade:Object =
            root.物品栏.装备栏.getItem("手雷");
        var unit:Object = {
            _name:root.控制目标,
            其他消耗物品:grenade.name
        };
        var callback:Object =
            writerPersistenceCallbacks(root);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.writer.grenade.stack.1",
                "character-build.writer.grenade.stack.open"));

        root.存档系统.dirtyMark = false;
        var originalTarget:String = root.控制目标;
        root.控制目标 = "otherHero";
        var blocked:Boolean =
            applyLongGunFallbackPrimitive(root, unit);
        var cleanAfterBlocked:Boolean =
            !root.存档系统.dirtyMark
            && grenade.value == 5;
        root.控制目标 = originalTarget;
        var consumed:Boolean =
            applyLongGunFallbackPrimitive(root, unit);
        var synchronized:Object =
            CharacterBuildService.synchronize(
                opened.sessionGeneration);
        check(!blocked && cleanAfterBlocked
                && consumed
                && grenade.value == 4
                && root.存档系统.dirtyMark
                && synchronized.success
                && synchronized.loadoutRevision
                    == opened.loadoutRevision + 1,
            "长枪 fallback 仅受控自机 direct decrement，并独立标记 dirty");

        var finalized:Object = CharacterBuildService.finalize(
            opened.sessionGeneration,
            synchronized.loadoutRevision);
        var reopened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.writer.grenade.stack.2",
                "character-build.writer.grenade.stack.reopen"));
        check(finalized.success
                && finalized.persistence.changed
                && callback.state.saveCalls == 1
                && reopened.success
                && reopened.payload.equipment[10]
                    .item.quantity == 4,
            "手雷 direct decrement 经 finalize flush changed，新 session 读取数量 baseline");

        root.存档系统.dirtyMark = false;
        grenade.value = 1;
        var removalSync:Object =
            CharacterBuildService.synchronize(
                reopened.sessionGeneration);
        root.存档系统.dirtyMark = false;
        var removed:Boolean =
            applyLongGunFallbackPrimitive(root, unit);
        var removedState:Object =
            CharacterBuildService.synchronize(
                reopened.sessionGeneration);
        check(removalSync.success && removed
                && root.物品栏.装备栏
                    .getItem("手雷") == null
                && root.存档系统.dirtyMark
                && removedState.success,
            "长枪 fallback 单件 remove 成功后标记 dirty 并保持现役刷新路径");
        var removalFinalized:Object =
            CharacterBuildService.finalize(
                reopened.sessionGeneration,
                removedState.loadoutRevision);
        var removalReopened:Object =
            CharacterBuildService.execute(
                "snapshot", wireParams(
                    "workbench.writer.grenade.remove.3",
                    "character-build.writer.grenade.remove.reopen"));
        check(removalFinalized.success
                && removalFinalized.persistence.changed
                && callback.state.saveCalls == 2
                && removalReopened.success
                && !removalReopened.payload
                    .equipment[10].occupied,
            "手雷 remove 经 finalize flush changed，新 session 读取空槽 baseline");

        CharacterBuildService.testOnlyReset();
    }

    private static function testLootAcquireProjectsOnNewSession():Void {
        var acquireName:String = "B4拾取新会话投影药剂";
        var equippedDrugName:String = "B4拾取补充已装药剂";
        var grenadeName:String = "B4拾取补充已装备手雷";
        var root:Object = fixtureRoot(1);
        var backpack:ArrayInventory =
            new ArrayInventory(null, 1);
        root.物品栏.背包 = backpack;
        root.收集品栏 = {
            材料:new DictCollection({}),
            情报:new DictCollection({})
        };
        registerCatalog(
            root, acquireName, "消耗品", "药剂", 1);
        registerCatalog(
            root, equippedDrugName, "消耗品", "药剂", 1);
        registerCatalog(
            root, grenadeName, "消耗品", "手雷", 1);
        var itemData:Object = {};
        itemData[acquireName] = {
            name:acquireName,
            displayname:acquireName,
            type:"消耗品",
            use:"药剂",
            data:{level:1}
        };
        itemData[equippedDrugName] = {
            name:equippedDrugName,
            displayname:equippedDrugName,
            type:"消耗品",
            use:"药剂",
            data:{level:1}
        };
        itemData[grenadeName] = {
            name:grenadeName,
            displayname:grenadeName,
            type:"消耗品",
            use:"手雷",
            data:{level:1}
        };
        var binding:Object = bindItemUtilFixture(
            root, itemData, {});
        var equippedDrug:BaseItem =
            BaseItem.create(equippedDrugName, 3, 1);
        root.物品栏.药剂栏 =
            new DrugInventory(null, 8);
        // Fixture 用 transactionWrite 保留 exact ref，避免 DrugInventory.add
        // 走全局 _root.getItemData（本测试只绑定隔离 root 的目录）。
        root.物品栏.药剂栏.transactionWrite(0, equippedDrug);
        var equippedGrenade:BaseItem =
            BaseItem.create(grenadeName, 5, 1);
        root.物品栏.装备栏 =
            new EquipmentInventory(null);
        // EquipmentInventory 无数字索引树；直接布置隔离 fixture
        // 可保留 exact ref，生产写入仍由 addValue 走真实容器。
        root.物品栏.装备栏.getItems().手雷 = equippedGrenade;
        root.gameworld[root.控制目标].手雷 = equippedGrenade;
        var callback:Object =
            writerPersistenceCallbacks(root);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.writer.acquire.1",
                "character-build.writer.acquire.open"));

        var acquired:Boolean =
            ItemUtil.singleAcquire(acquireName, 4);
        var drugAcquired:Boolean =
            ItemUtil.singleAcquire(equippedDrugName, 4);
        var grenadeAcquired:Boolean =
            ItemUtil.singleAcquire(grenadeName, 4);
        var synchronized:Object = CharacterBuildService.synchronize(
            opened.sessionGeneration);
        var finalized:Object = CharacterBuildService.finalize(
            opened.sessionGeneration,
            synchronized.loadoutRevision);
        var reopened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.writer.acquire.2",
                "character-build.writer.acquire.reopen"));
        var params:Object = wireParams(
            "workbench.writer.acquire.2",
            "character-build.writer.acquire.candidates");
        params.sessionGeneration =
            reopened.sessionGeneration;
        params.expectedLoadoutRevision =
            reopened.loadoutRevision;
        params.expectedDrugRevision =
            reopened.drugRevision;
        params.candidateScope = "compatible";
        params.drugSlot = 0;
        var candidates:Object =
            CharacterBuildService.execute(
                "candidates", params);
        var acquiredRow:Object = findCandidate(
            candidates, acquireName, 0);
        check(acquired && synchronized.success && finalized.success
                && reopened.success
                && acquiredRow != null
                && acquiredRow.item.quantity == 4
                && countCandidates(
                    candidates, acquireName) == 1,
            "既有正确 dirty 的 ItemUtil.acquire 仅补新 session 真实背包投影，无复制/复活");
        check(drugAcquired
                && root.物品栏.药剂栏.getItem("0")
                    === equippedDrug
                && equippedDrug.value == 7
                && backpack.getTotal(equippedDrugName) == 0
                && reopened.payload.drugs[0].item.quantity == 7,
            "ItemUtil.acquire 满包获取同名药剂优先补充已装药剂原对象");
        check(grenadeAcquired
                && root.物品栏.装备栏.getItem("手雷")
                    === equippedGrenade
                && equippedGrenade.value == 9
                && backpack.getTotal(grenadeName) == 0,
            "ItemUtil.acquire 获取同名手雷优先补充已装备原对象，不占背包空位");

        CharacterBuildService.testOnlyReset();
        restoreItemUtilFixture(binding);
    }

    private static function mutationFixture(root:Object,
                                             panelId:String):Object {
        var callback:Object = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(panelId, panelId + ".open"));
        return {opened:opened, callback:callback};
    }

    private static function equipmentMutationParams(
        commandName:String, panelId:String, current:Object,
        slotKey:String, sourceSlot):Object {
        var params:Object = wireParams(
            panelId, panelId + "." + commandName);
        params.task = "cmd";
        params.action = commandName == "equipEquipment"
            ? "characterBuildEquipEquipment"
            : "characterBuildUnequipEquipment";
        params.sessionGeneration = current.sessionGeneration;
        params.expectedLoadoutRevision = current.loadoutRevision;
        params.slotKey = slotKey;
        if (sourceSlot != undefined) {
            params.source = backpackSourceRef(
                __activeMutationRoot,
                Number(sourceSlot));
        }
        return params;
    }

    private static function drugMutationParams(
        commandName:String, panelId:String, current:Object,
        drugSlot:Number, sourceSlot):Object {
        var params:Object = wireParams(
            panelId, panelId + "." + commandName);
        params.task = "cmd";
        params.action = commandName == "equipDrug"
            ? "characterBuildEquipDrug"
            : "characterBuildUnequipDrug";
        params.sessionGeneration = current.sessionGeneration;
        params.expectedDrugRevision = current.drugRevision;
        params.drugSlot = drugSlot;
        if (sourceSlot != undefined) {
            params.source = backpackSourceRef(
                __activeMutationRoot,
                Number(sourceSlot));
        }
        return params;
    }

    private static function backpackSourceRef(root:Object,
                                              slot:Number):Object {
        return {
            containerId:"背包",
            slot:slot,
            expectedLease:"fixture.bag."
                + containerRevision(
                    root.物品栏.背包) + "." + slot
        };
    }

    private static function registerCatalog(root:Object, name:String,
                                            majorType:String,
                                            useName:String,
                                            requiredLevel:Number):Void {
        setCatalogData(root, name,
            catalog(majorType, useName, requiredLevel));
    }

    private static function testEquipmentMutationMoveSwapAndUnequip():Void {
        var root:Object = fixtureRoot(5);
        __activeMutationRoot = root;
        var bag:Object = root.物品栏.背包;
        var moving:Object = equipment(
            "事务上装", 3, "二阶", ["护板"], 31);
        var swapping:Object = equipment(
            "事务头盔", 4, "", [], 32);
        bag.items["0"] = moving;
        bag.items["1"] = swapping;
        registerCatalog(root, moving.name, "防具", "上装装备", 2);
        registerCatalog(root, swapping.name, "防具", "头部装备", 2);

        var fixture:Object = mutationFixture(
            root, "workbench.mutation.equipment");
        var opened:Object = fixture.opened;
        var originalHead:Object =
            root.物品栏.装备栏.getItem("头部装备");
        var bagRevisionBefore:Number = bag.revision;
        var equipmentRevisionBefore:Number =
            root.物品栏.装备栏.revision;

        var moveParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.equipment",
            opened, "上装装备", 0);
        var moved:Object = CharacterBuildService.execute(
            "equipEquipment", moveParams);
        check(moved.success && moved.changed
                && moved.operation == "equipEquipment"
                && moved.affectedBackpackSlot == 0
                && root.物品栏.装备栏.getItem("上装装备") === moving
                && bag.getItem("0") == null,
            "equipEquipment 空目标以 exact ref move，成功响应固定 operation/affected 槽");
        check(moved.loadoutRevision == opened.loadoutRevision + 1
                && moved.drugRevision == opened.drugRevision
                && moved.liveRefreshDirty && root.存档系统.dirtyMark
                && bag.revision > bagRevisionBefore
                && root.物品栏.装备栏.revision
                    > equipmentRevisionBefore,
            "装备真实 move 精确推进一次 loadout domain、raw revisions、save/live dirty");
        check(moved.payload.equipment.length == 11
                && moved.payload.drugs.length == 8
                && moved.payload.stateHealth == "ok"
                && moved.inventorySnapshots.length == 1
                && moved.inventorySnapshots[0].containerId == "背包"
                && fixture.callback.state.leaseInvalidations == 1,
            "装备 mutation 成功返回完整 loadout 与单个 full 背包窗口并失效旧 lease");
        var fullBag:Object = moved.inventorySnapshots[0];
        check(hasOnlyKeys(moved, commonWireKeys({
                    changed:true, operation:true,
                    affectedBackpackSlot:true, payload:true,
                    inventorySnapshots:true
                }))
                && hasOnlyKeys(fullBag, {
                    containerId:true, capacity:true,
                    accessibleCapacity:true, viewCapacity:true,
                    filterKey:true, pageSizeHint:true, locked:true,
                    snapshotSeq:true, containerEpoch:true,
                    containerVersion:true, offset:true, limit:true,
                    slots:true, filterFacets:true,
                    filterItemCount:true, setFacets:true,
                    setFilterItemCount:true
                })
                && fullBag.capacity == 50
                && fullBag.accessibleCapacity == 50
                && fullBag.viewCapacity == 50
                && fullBag.pageSizeHint == 50
                && fullBag.offset == 0 && fullBag.limit == 50
                && fullBag.slots.length == 50
                && hasOnlyKeys(fullBag.slots[0], {
                    physicalSlot:true, occupied:true, slotLease:true
                })
                && hasOnlyKeys(fullBag.slots[1], {
                    physicalSlot:true, occupied:true, slotLease:true,
                    item:true, confirmProjection:true
                })
                && hasOnlyKeys(fullBag.slots[1].item,
                    itemProjectionWireKeys())
                && hasOnlyKeys(fullBag.slots[1].confirmProjection, {
                    itemKind:true, name:true, displayName:true,
                    quantity:true, enhancementLevel:true, rarity:true,
                    tier:true, modSignature:true, lastUpdate:true
                }),
            "mutation success 与 Host strict contract 同形：exact 顶层、50 槽及 occupied 确认投影");

        var swapParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.equipment",
            moved, "头部装备", 1);
        var swapped:Object = CharacterBuildService.execute(
            "equipEquipment", swapParams);
        check(swapped.success
                && root.物品栏.装备栏.getItem("头部装备")
                    === swapping
                && bag.getItem("1") === originalHead
                && swapped.loadoutRevision
                    == moved.loadoutRevision + 1,
            "equipEquipment 占用目标以两个原对象 swap，old target 回 exact source 槽");
        var identityCount:Number = 0;
        if (root.物品栏.装备栏.getItem("头部装备")
                === swapping) identityCount++;
        if (bag.getItem("1") === swapping) identityCount++;
        check(identityCount == 1,
            "装备 swap 后 source 物品身份只存在一次，零复制/丢失");

        root.存档系统.dirtyMark = false;
        var unequipParams:Object = equipmentMutationParams(
            "unequipEquipment", "workbench.mutation.equipment",
            swapped, "头部装备", undefined);
        var unequipped:Object = CharacterBuildService.execute(
            "unequipEquipment", unequipParams);
        check(unequipped.success
                && unequipped.affectedBackpackSlot == 0
                && root.物品栏.装备栏.getItem("头部装备") == null
                && bag.getItem("0") === swapping
                && unequipped.loadoutRevision
                    == swapped.loadoutRevision + 1
                && root.存档系统.dirtyMark,
            "unequipEquipment 稳定选择首个背包空位并精确推进一次");
        __activeMutationRoot = null;
    }

    private static function testGrenadeMutationMergeAndFullBackpackUnequip():Void {
        var root:Object = fixtureRoot(4);
        __activeMutationRoot = root;
        var bag:Object = root.物品栏.背包;
        bag.capacity = 2;
        var equipped:Object = root.物品栏.装备栏.getItem("手雷");
        var same:Object = stack("观察手雷", 4);
        var other:Object = stack("事务异名手雷", 3);
        bag.items["0"] = same;
        bag.items["1"] = other;
        registerCatalog(root, "事务异名手雷", "消耗品", "手雷", 1);
        setInstanceData(same, catalog("消耗品", "手雷", 1));

        var fixture:Object = mutationFixture(
            root, "workbench.mutation.grenade");
        var opened:Object = fixture.opened;
        var mergeParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.grenade",
            opened, "手雷", 0);
        var merged:Object = CharacterBuildService.execute(
            "equipEquipment", mergeParams);
        check(merged.success
                && root.物品栏.装备栏.getItem("手雷") === equipped
                && equipped.value == 9 && bag.getItem("0") == null,
            "equipEquipment 手雷同名装入保留已装备 target ref 并合并数量");

        var backpackSame:Object = stack("观察手雷", 2);
        setInstanceData(backpackSame,
            catalog("消耗品", "手雷", 1));
        bag.transactionWrite(0, backpackSame);
        var unequipParams:Object = equipmentMutationParams(
            "unequipEquipment", "workbench.mutation.grenade",
            merged, "手雷", undefined);
        var unequipped:Object = CharacterBuildService.execute(
            "unequipEquipment", unequipParams);
        check(unequipped.success
                && unequipped.affectedBackpackSlot == 0
                && root.物品栏.装备栏.getItem("手雷") == null
                && bag.getItem("0") === backpackSame
                && backpackSame.value == 11,
            "满包卸下手雷仍优先合并物理序号最小的同名背包堆");

        var equipOtherParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.grenade",
            unequipped, "手雷", 1);
        var equippedOther:Object = CharacterBuildService.execute(
            "equipEquipment", equipOtherParams);
        var swapParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.grenade",
            equippedOther, "手雷", 0);
        var swapped:Object = CharacterBuildService.execute(
            "equipEquipment", swapParams);
        check(equippedOther.success && swapped.success
                && root.物品栏.装备栏.getItem("手雷")
                    === backpackSame
                && bag.getItem("0") === other,
            "手雷异名装入保持原有 exact ref swap 语义，不跨名称合并");
        __activeMutationRoot = null;
    }

    private static function testDrugMutationMoveSwapMergeAndUnequip():Void {
        var root:Object = fixtureRoot(8);
        __activeMutationRoot = root;
        var bag:Object = root.物品栏.背包;
        var first:Object = stack("事务药剂A", 2);
        var mergeSource:Object = stack("事务药剂A", 4);
        var other:Object = stack("事务药剂B", 3);
        bag.items["0"] = first;
        bag.items["1"] = mergeSource;
        bag.items["2"] = other;
        registerCatalog(root, first.name, "消耗品", "药剂", 1);
        registerCatalog(root, other.name, "消耗品", "药剂", 1);

        var fixture:Object = mutationFixture(
            root, "workbench.mutation.drug");
        var opened:Object = fixture.opened;
        var targetDrugSlot:Number = 4;
        var loadoutBefore:Number = opened.loadoutRevision;
        var moveParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.drug",
            opened, targetDrugSlot, 0);
        var moved:Object = CharacterBuildService.execute(
            "equipDrug", moveParams);
        check(moved.success
                && root.物品栏.药剂栏.getItem(String(targetDrugSlot)) === first
                && bag.getItem("0") == null
                && moved.drugRevision == opened.drugRevision + 1
                && moved.loadoutRevision == loadoutBefore
                && !moved.liveRefreshDirty
                && moved.payload.stateHealth == "ok"
                && hasOnlyKeys(moved.payload.drugs[targetDrugSlot], {
                    slot:true, bank:true, lane:true, active:true,
                    keyLabel:true, ready:true,
                    totalSteps:true, currentStep:true,
                    progressPercent:true, animationFrame:true,
                    remainingMs:true, occupied:true, quantity:true,
                    item:true
                }),
            "equipDrug 空目标 move 只推进 drug revision，不推进 loadout/live dirty");

        var mergeParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.drug",
            moved, targetDrugSlot, 1);
        var merged:Object = CharacterBuildService.execute(
            "equipDrug", mergeParams);
        check(merged.success
                && root.物品栏.药剂栏.getItem(String(targetDrugSlot)) === first
                && first.value == 6 && bag.getItem("1") == null
                && merged.drugRevision == moved.drugRevision + 1,
            "equipDrug 同名正有限 stack 保留 target ref 合并数量并移除 source");

        var swapParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.drug",
            merged, targetDrugSlot, 2);
        var swapped:Object = CharacterBuildService.execute(
            "equipDrug", swapParams);
        check(swapped.success
                && root.物品栏.药剂栏.getItem(String(targetDrugSlot)) === other
                && bag.getItem("2") === first
                && swapped.drugRevision == merged.drugRevision + 1,
            "equipDrug 异名 stack 复刻现役 swap，old target 回 source 槽");

        bag.capacity = 3;
        var backpackOther:Object = stack("事务药剂B", 2);
        var filler:Object = stack("事务药剂填充", 1);
        setInstanceData(backpackOther,
            catalog("消耗品", "药剂", 1));
        setInstanceData(filler,
            catalog("消耗品", "药剂", 1));
        bag.transactionWrite(0, backpackOther);
        bag.transactionWrite(1, filler);

        var unequipParams:Object = drugMutationParams(
            "unequipDrug", "workbench.mutation.drug",
            swapped, targetDrugSlot, undefined);
        var unequipped:Object = CharacterBuildService.execute(
            "unequipDrug", unequipParams);
        check(unequipped.success
                && unequipped.affectedBackpackSlot == 0
                && root.物品栏.药剂栏.getItem(String(targetDrugSlot)) == null
                && bag.getItem("0") === backpackOther
                && backpackOther.value == 5
                && unequipped.drugRevision
                    == swapped.drugRevision + 1,
            "unequipDrug 在满包中仍优先合并物理序号最小的同名背包堆");
        check(fixture.callback.state.drugCooldownCalls == 4
                && fixture.callback.state.drugCooldownKey == "drug:0"
                && fixture.callback.state.leaseInvalidations == 4
                && unequipped.loadoutRevision == loadoutBefore
                && !unequipped.liveRefreshDirty
                && root.存档系统.dirtyMark,
            "后组 slot 4 的四次药剂 mutation 共用 lane 0 lock/cooldown，且药剂-only 零 live refresh");
        __activeMutationRoot = null;
    }

    private static function testMutationPreflightFailuresAndNoSideEffects():Void {
        var root:Object = fixtureRoot(3);
        __activeMutationRoot = root;
        var bag:Object = root.物品栏.背包;
        var locked:Object = equipment(
            "等级锁上装", 1, "", [], 1);
        var drug:Object = stack("预检药剂", 2);
        bag.items["0"] = locked;
        bag.items["1"] = drug;
        registerCatalog(root, locked.name, "防具", "上装装备", 99);
        registerCatalog(root, drug.name, "消耗品", "药剂", 1);
        var fixture:Object = mutationFixture(
            root, "workbench.mutation.preflight");
        var opened:Object = fixture.opened;
        var bagRevision:Number = bag.revision;
        var loadoutRevision:Number = opened.loadoutRevision;
        var drugRevision:Number = opened.drugRevision;

        var malformedEnvelopes:Array = [];
        var malformed:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        delete malformed.callId;
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        malformed.callId = "7001";
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        delete malformed.requestCallId;
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        malformed.requestCallId = 7001;
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        delete malformed.panelInstanceId;
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        malformed.panelInstanceId = 19;
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        delete malformed.writeEpoch;
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        malformed.writeEpoch = "19";
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        delete malformed.task;
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        malformed.v = "1";
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        malformed.sessionGeneration =
            String(opened.sessionGeneration);
        malformedEnvelopes.push(malformed);
        malformed = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        malformed.action = "characterBuildEquipDrug";
        malformedEnvelopes.push(malformed);
        var envelopesRejected:Boolean = true;
        for (var malformedIndex:Number = 0;
                malformedIndex < malformedEnvelopes.length;
                malformedIndex++) {
            var malformedResult:Object = CharacterBuildService.execute(
                "equipEquipment",
                malformedEnvelopes[malformedIndex]);
            if (malformedResult.success
                    || malformedResult.error != "invalid_payload") {
                envelopesRejected = false;
            }
        }
        check(envelopesRejected && bag.revision == bagRevision
                && root.物品栏.装备栏.writeCount == 0
                && !root.存档系统.dirtyMark,
            "mutation exact Host→AS2 envelope 拒绝缺失/错型 identity、错误 action 与宽松字符串数字，零写");

        var ninthDrugSlotParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.preflight",
            opened, 8, 1);
        var ninthDrugSlot:Object = CharacterBuildService.execute(
            "equipDrug", ninthDrugSlotParams);
        check(!ninthDrugSlot.success
                && ninthDrugSlot.error == "invalid_payload"
                && fixture.callback.state.drugCooldownCalls == 0
                && bag.revision == bagRevision,
            "mutation rejects physical drug slot 8 before cooldown reads or inventory writes");

        var lockedParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            opened, "上装装备", 0);
        var levelLocked:Object = CharacterBuildService.execute(
            "equipEquipment", lockedParams);
        check(!levelLocked.success && levelLocked.error == "level_locked"
                && levelLocked.changed == undefined
                && levelLocked.operation == undefined
                && levelLocked.affectedBackpackSlot == undefined
                && bag.revision == bagRevision
                && levelLocked.loadoutRevision == loadoutRevision
                && !root.存档系统.dirtyMark,
            "装备等级门在任何写入前重验，失败仅 common+error 且零副作用");

        var staleParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.preflight",
            opened, 0, 1);
        staleParams.source.expectedLease = "stale";
        var staleSource:Object = CharacterBuildService.execute(
            "equipDrug", staleParams);
        check(!staleSource.success && staleSource.error == "stale_state"
                && fixture.callback.state.drugCooldownCalls == 1
                && staleSource.drugRevision == drugRevision
                && bag.revision == bagRevision,
            "药剂 stale source lease 确定失败且每个有效请求仍只重验一次 cooldown");

        fixture.callback.state.drugReady = false;
        var cooldownParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.preflight",
            opened, 0, 1);
        var cooldown:Object = CharacterBuildService.execute(
            "equipDrug", cooldownParams);
        check(!cooldown.success && cooldown.error == "cooldown_active"
                && fixture.callback.state.drugCooldownCalls == 2
                && bag.revision == bagRevision,
            "药剂 cooldown active 在 source 写前确定拒绝");

        fixture.callback.state.drugReady = true;
        fixture.callback.state.drugCooldownThrows = true;
        var unavailableParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.preflight",
            opened, 0, 1);
        var unavailable:Object = CharacterBuildService.execute(
            "equipDrug", unavailableParams);
        check(!unavailable.success
                && unavailable.error == "cooldown_unavailable"
                && fixture.callback.state.drugCooldownCalls == 3
                && bag.revision == bagRevision,
            "药剂 cooldown getter 抛错只读一次并在任何写入前 fail-closed");
        fixture.callback.state.drugCooldownThrows = false;

        var extraParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.preflight",
            opened, 0, 1);
        extraParams.opId = "forbidden";
        var extra:Object = CharacterBuildService.execute(
            "equipDrug", extraParams);
        check(!extra.success && extra.error == "invalid_payload"
                && fixture.callback.state.drugCooldownCalls == 3,
            "mutation 明确拒绝 opId/reconcileAfter 等冻结形状外字段");

        var alias:Object = equipment(
            "别名头盔", 1, "", [], 1);
        root.物品栏.装备栏.items["头部装备"] = alias;
        bag.items["2"] = alias;
        registerCatalog(root, alias.name, "防具", "头部装备", 1);
        var aliasCurrent:Object = CharacterBuildService.synchronize(
            opened.sessionGeneration);
        var aliasBagRevision:Number = bag.revision;
        root.存档系统.dirtyMark = false;
        var aliasParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.preflight",
            aliasCurrent, "头部装备", 2);
        var noOpAlias:Object = CharacterBuildService.execute(
            "equipEquipment", aliasParams);
        check(!noOpAlias.success && noOpAlias.error == "stale_state"
                && bag.revision == aliasBagRevision
                && noOpAlias.loadoutRevision
                    == aliasCurrent.loadoutRevision
                && !root.存档系统.dirtyMark,
            "同一物品引用同时占两端的 corrupt no-op fail-closed，零 dirty/推进");

        root = fixtureRoot(2);
        __activeMutationRoot = root;
        fixture = mutationFixture(
            root, "workbench.mutation.target-stale");
        opened = fixture.opened;
        var drifted:Object = equipment(
            "服务外漂移头盔", 2, "", [], 2);
        root.物品栏.装备栏.transactionWrite(
            "头部装备", drifted);
        var staleTargetParams:Object = equipmentMutationParams(
            "unequipEquipment", "workbench.mutation.target-stale",
            opened, "头部装备", undefined);
        var staleTarget:Object = CharacterBuildService.execute(
            "unequipEquipment", staleTargetParams);
        check(!staleTarget.success && staleTarget.error == "stale_state"
                && staleTarget.loadoutRevision
                    == opened.loadoutRevision + 1
                && root.物品栏.装备栏.getItem("头部装备")
                    === drifted
                && !root.存档系统.dirtyMark,
            "target ref/signature 服务外漂移先同步新 revision，再以旧 expected target fail-closed");

        root = fixtureRoot(2);
        __activeMutationRoot = root;
        root.物品栏.背包.capacity = 4;
        for (var i:Number = 0; i < 4; i++) {
            root.物品栏.背包.items[String(i)] =
                stack("满包" + i, i + 1);
        }
        fixture = mutationFixture(
            root, "workbench.mutation.full");
        opened = fixture.opened;
        var equippedBefore:Object =
            root.物品栏.装备栏.getItem("头部装备");
        var fullParams:Object = equipmentMutationParams(
            "unequipEquipment", "workbench.mutation.full",
            opened, "头部装备", undefined);
        var full:Object = CharacterBuildService.execute(
            "unequipEquipment", fullParams);
        check(!full.success && full.error == "backpack_full"
                && root.物品栏.装备栏.getItem("头部装备")
                    === equippedBefore
                && full.loadoutRevision == opened.loadoutRevision
                && !root.存档系统.dirtyMark,
            "满背包卸下确定失败，装备引用/domain/dirty 零副作用");
        __activeMutationRoot = null;
    }

    private static function rollbackFixture(mode:String,
                                             rollbackMode:String):Object {
        var root:Object = fixtureRoot(4);
        __activeMutationRoot = root;
        var panelId:String =
            "workbench.mutation.rollback." + mode + rollbackMode;
        var source:Object = equipment(
            "回滚头盔", 2, "", ["回滚"], 44);
        root.物品栏.背包.items["0"] = source;
        registerCatalog(root, source.name, "防具", "头部装备", 1);
        var fixture:Object = mutationFixture(
            root, panelId);
        var opened:Object = fixture.opened;
        var targetBefore:Object =
            root.物品栏.装备栏.getItem("头部装备");
        root.物品栏.装备栏.writeModes = [mode];
        if (rollbackMode != "") {
            root.物品栏.装备栏.writeModes.push(rollbackMode);
        }
        var params:Object = equipmentMutationParams(
            "equipEquipment", panelId,
            opened, "头部装备", 0);
        var result:Object = CharacterBuildService.execute(
            "equipEquipment", params);
        return {
            root:root,
            fixture:fixture,
            opened:opened,
            panelId:panelId,
            params:params,
            source:source,
            targetBefore:targetBefore,
            result:result
        };
    }

    private static function testMutationRollbackAndDispatcherReentry():Void {
        var falseCase:Object = rollbackFixture(
            "false_after_write", "");
        var throwCase:Object = rollbackFixture(
            "throw_after_write", "");
        check(!falseCase.result.success
                && falseCase.result.error == "write_failed"
                && falseCase.root.物品栏.背包.getItem("0")
                    === falseCase.source
                && falseCase.root.物品栏.装备栏.getItem("头部装备")
                    === falseCase.targetBefore
                && falseCase.result.loadoutRevision
                    == falseCase.opened.loadoutRevision
                && !falseCase.root.存档系统.dirtyMark,
            "第二写 false_after_write 后两槽 exact rollback，领域 revision/dirty 不推进");
        check(!throwCase.result.success
                && throwCase.result.error == "write_failed"
                && throwCase.root.物品栏.背包.getItem("0")
                    === throwCase.source
                && throwCase.root.物品栏.装备栏.getItem("头部装备")
                    === throwCase.targetBefore
                && throwCase.root.物品栏.装备栏.publishCount == 0
                && throwCase.root.物品栏.背包.publishCount == 0,
            "第二写 throw_after_write exact rollback 且失败路径零 publish");

        var rollbackFalse:Object = rollbackFixture(
            "false_after_write", "false_after_write");
        var rollbackThrow:Object = rollbackFixture(
            "throw_after_write", "throw_after_write");
        var rollbackSignature:Object = rollbackFixture(
            "false_after_write", "corrupt_after_write");
        check(!rollbackFalse.result.success
                && rollbackFalse.result.error == "needs_reconcile"
                && rollbackFalse.root.物品栏.背包.getItem("0")
                    === rollbackFalse.source
                && rollbackFalse.root.物品栏.装备栏
                    .getItem("头部装备")
                    === rollbackFalse.targetBefore,
            "rollback 返回 false 即使引用已恢复也 poison/needs_reconcile");
        check(!rollbackThrow.result.success
                && rollbackThrow.result.error == "needs_reconcile",
            "rollback 抛错固定 poison/needs_reconcile，绝不伪成功");
        check(!rollbackSignature.result.success
                && rollbackSignature.result.error == "needs_reconcile",
            "rollback 返回 true 但 exact signature 不一致仍固定 poison/needs_reconcile");

        var recoveryCase:Object = rollbackFixture(
            "false_after_write", "false_after_write");
        var ordinaryPoisonParams:Object = wireParams(
            recoveryCase.panelId,
            recoveryCase.panelId + ".ordinary-poison");
        ordinaryPoisonParams.sessionGeneration =
            recoveryCase.opened.sessionGeneration;
        var ordinaryPoison:Object = CharacterBuildService.execute(
            "snapshot", ordinaryPoisonParams);
        var poisonReconcileParams:Object = wireParams(
            recoveryCase.panelId,
            recoveryCase.panelId + ".explicit-reconcile");
        poisonReconcileParams.sessionGeneration =
            recoveryCase.opened.sessionGeneration;
        poisonReconcileParams.reconcileAfterCallId =
            String(recoveryCase.params.requestCallId);
        var poisonReconciled:Object = CharacterBuildService.execute(
            "snapshot", poisonReconcileParams);
        var resumedParams:Object = wireParams(
            recoveryCase.panelId,
            recoveryCase.panelId + ".resumed");
        resumedParams.sessionGeneration =
            recoveryCase.opened.sessionGeneration;
        var resumed:Object = CharacterBuildService.execute(
            "snapshot", resumedParams);
        check(!ordinaryPoison.success
                && ordinaryPoison.error == "needs_reconcile"
                && poisonReconciled.success
                && poisonReconciled.reconcileAfterCallId
                    == String(recoveryCase.params.requestCallId)
                && poisonReconciled.inventorySnapshots.length == 1
                && recoveryCase.root.物品栏.背包.getItem("0")
                    === recoveryCase.source
                && resumed.success
                && resumed.reconcileAfterCallId == undefined,
            "rollback poison 仅由同 session 显式 full reconcile 解封，普通 snapshot 前后分别阻断/恢复");

        var root:Object = fixtureRoot(6);
        __activeMutationRoot = root;
        var source:Object = equipment(
            "重入上装", 2, "", [], 45);
        root.物品栏.背包.items["0"] = source;
        registerCatalog(root, source.name, "防具", "上装装备", 1);
        var fixture:Object = mutationFixture(
            root, "workbench.mutation.reentry");
        var opened:Object = fixture.opened;
        var observed:Object = null;
        var nested:Object = null;
        var nestedFinalize:Object = null;
        root.物品栏.装备栏.publishObserver =
            function(container:Object, key, kind:String):Void {
                var readParams:Object = wireParams(
                    "workbench.mutation.reentry",
                    "workbench.mutation.reentry.read");
                readParams.sessionGeneration = opened.sessionGeneration;
                observed = CharacterBuildService.execute(
                    "snapshot", readParams);
                var nestedParams:Object = equipmentMutationParams(
                    "unequipEquipment", "workbench.mutation.reentry",
                    observed, "上装装备", undefined);
                nested = CharacterBuildService.execute(
                    "unequipEquipment", nestedParams);
                var finalizeParams:Object = wireParams(
                    "workbench.mutation.reentry",
                    "workbench.mutation.reentry.finalize");
                finalizeParams.sessionGeneration =
                    observed.sessionGeneration;
                finalizeParams.expectedLoadoutRevision =
                    observed.loadoutRevision;
                nestedFinalize = CharacterBuildService.execute(
                    "finalize", finalizeParams);
            };
        var writeParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.reentry",
            opened, "上装装备", 0);
        var committed:Object = CharacterBuildService.execute(
            "equipEquipment", writeParams);
        check(committed.success && observed.success
                && observed.loadoutRevision == committed.loadoutRevision
                && observed.payload.equipment[1].item.name
                    == source.name
                && root.物品栏.背包.getItem("0") == null,
            "同步 dispatcher 重入 snapshot 只观察最终两端与已推进领域水位");
        check(!nested.success && nested.error == "write_busy"
                && !nestedFinalize.success
                && nestedFinalize.error == "write_busy"
                && root.物品栏.装备栏.getItem("上装装备")
                    === source,
            "dispatcher 重入 mutation/finalize 均被单闸拒绝，不穿越 publish 阶段");

        root = fixtureRoot(9);
        __activeMutationRoot = root;
        var targetDrug:Object = stack("回滚药剂", 2);
        var sourceDrug:Object = stack("回滚药剂", 3);
        root.物品栏.药剂栏.items["0"] = targetDrug;
        root.物品栏.背包.items["0"] = sourceDrug;
        registerCatalog(root, targetDrug.name, "消耗品", "药剂", 1);
        fixture = mutationFixture(
            root, "workbench.mutation.stackrollback");
        opened = fixture.opened;
        root.物品栏.药剂栏.writeModes = ["false_after_write"];
        var mergeParams:Object = drugMutationParams(
            "equipDrug", "workbench.mutation.stackrollback",
            opened, 0, 0);
        var mergeFailed:Object = CharacterBuildService.execute(
            "equipDrug", mergeParams);
        check(!mergeFailed.success && mergeFailed.error == "write_failed"
                && targetDrug.value == 2 && sourceDrug.value == 3
                && root.物品栏.药剂栏.getItem("0") === targetDrug
                && root.物品栏.背包.getItem("0") === sourceDrug
                && mergeFailed.drugRevision == opened.drugRevision
                && !root.存档系统.dirtyMark,
            "stack merge 第二写失败恢复两数量与 exact refs，drug domain/dirty 不推进");
        __activeMutationRoot = null;
    }

    private static function testMutationResponseLossAfterCommit():Void {
        var root:Object = fixtureRoot(3);
        __activeMutationRoot = root;
        var source:Object = equipment(
            "丢包上装", 2, "", [], 47);
        root.物品栏.背包.items["0"] = source;
        registerCatalog(root, source.name, "防具", "上装装备", 1);
        var fixture:Object = mutationFixture(
            root, "workbench.mutation.response-loss");
        var opened:Object = fixture.opened;

        root.gameCommands = {};
        root.server = {
            sendSocketMessage:function(message:String):Boolean {
                throw "fixture_response_send_failed";
                return false;
            }
        };
        CharacterBuildService.install();
        var params:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.response-loss",
            opened, "上装装备", 0);
        var responseLost:Boolean = false;
        try {
            root.gameCommands.characterBuildEquipEquipment(params);
        } catch (sendError) {
            responseLost = true;
        }

        var reconcileParams:Object = wireParams(
            "workbench.mutation.response-loss",
            "workbench.mutation.response-loss.reconcile");
        reconcileParams.sessionGeneration = opened.sessionGeneration;
        reconcileParams.reconcileAfterCallId =
            String(params.requestCallId);
        var reconciled:Object = CharacterBuildService.execute(
            "snapshot", reconcileParams);
        check(responseLost && reconciled.success
                && root.物品栏.装备栏.getItem("上装装备")
                    === source
                && root.物品栏.背包.getItem("0") == null
                && reconciled.loadoutRevision
                    == opened.loadoutRevision + 1
                && reconciled.reconcileAfterCallId
                    == String(params.requestCallId)
                && root.存档系统.dirtyMark,
            "响应发送阶段失败不回滚已提交权威；调用方须以 post-write full snapshot 对账");
        __activeMutationRoot = null;
    }

    private static function testMutationDegradedProjectionRequiresReconcile():Void {
        var root:Object = fixtureRoot(3);
        __activeMutationRoot = root;
        var source:Object = equipment(
            "降级投影上装", 2, "", [], 48);
        root.物品栏.背包.items["0"] = source;
        root.gameworld[root.控制目标].性别 = "未知";
        registerCatalog(root, source.name, "防具", "上装装备", 1);
        var fixture:Object = mutationFixture(
            root, "workbench.mutation.degraded");
        var opened:Object = fixture.opened;
        var writeParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.degraded",
            opened, "上装装备", 0);
        var degradedWrite:Object = CharacterBuildService.execute(
            "equipEquipment", writeParams);
        check(!degradedWrite.success
                && degradedWrite.error == "needs_reconcile"
                && degradedWrite.changed == undefined
                && root.物品栏.装备栏.getItem("上装装备")
                    === source
                && root.物品栏.背包.getItem("0") == null
                && root.存档系统.dirtyMark,
            "已提交 mutation 若只产出 degraded 投影，不伪造 Host 不接受的 success");

        var reconcileParams:Object = wireParams(
            "workbench.mutation.degraded",
            "workbench.mutation.degraded.reconcile");
        reconcileParams.sessionGeneration = opened.sessionGeneration;
        reconcileParams.reconcileAfterCallId =
            String(writeParams.requestCallId);
        var reconciled:Object = CharacterBuildService.execute(
            "snapshot", reconcileParams);
        check(reconciled.success
                && reconciled.payload.stateHealth == "degraded"
                && reconciled.inventorySnapshots.length == 1
                && reconciled.reconcileAfterCallId
                    == String(writeParams.requestCallId),
            "显式 reconcile 可携 degraded 只读投影与 full 背包快照收敛 unknown write");
        __activeMutationRoot = null;
    }

    private static function testMutationReconcileSnapshot():Void {
        var root:Object = fixtureRoot(2);
        __activeMutationRoot = root;
        var source:Object = equipment(
            "对账上装", 2, "", [], 46);
        root.物品栏.背包.items["0"] = source;
        registerCatalog(root, source.name, "防具", "上装装备", 1);
        var fixture:Object = mutationFixture(
            root, "workbench.mutation.reconcile");
        var opened:Object = fixture.opened;
        var writeParams:Object = equipmentMutationParams(
            "equipEquipment", "workbench.mutation.reconcile",
            opened, "上装装备", 0);
        writeParams.callId = 7041;
        var written:Object = CharacterBuildService.execute(
            "equipEquipment", writeParams);

        var reconcileParams:Object = wireParams(
            "workbench.mutation.reconcile",
            "character-build.reconcile.42");
        reconcileParams.sessionGeneration = opened.sessionGeneration;
        reconcileParams.reconcileAfterCallId =
            String(writeParams.requestCallId);
        var reconciled:Object = CharacterBuildService.execute(
            "snapshot", reconcileParams);
        check(written.success && reconciled.success
                && reconciled.reconcileAfterCallId
                    == String(writeParams.requestCallId)
                && reconciled.inventorySnapshots.length == 1
                && reconciled.inventorySnapshots[0].containerId
                    == "背包"
                && reconciled.payload.equipment[1].item.name
                    == source.name,
            "unknown mutation 只由显式 reconcile snapshot 回显原 callId + full 背包收敛");

        var ordinaryParams:Object = wireParams(
            "workbench.mutation.reconcile",
            "character-build.snapshot.43");
        ordinaryParams.sessionGeneration = opened.sessionGeneration;
        var ordinary:Object = CharacterBuildService.execute(
            "snapshot", ordinaryParams);
        check(ordinary.success
                && ordinary.reconcileAfterCallId == undefined
                && ordinary.inventorySnapshots == undefined,
            "ordinary snapshot 不携 reconcile watermark，不能误清 unknown write");
        __activeMutationRoot = null;
    }

    private static function testStatsCleanBarrierAndWireShape():Void {
        var root:Object = fixtureRoot(3);
        root.statsFixture = {
            v:1,
            stateHealth:"ok",
            diagnostics:[],
            groups:[{key:"core", label:"核心", rows:[
                {key:"level", label:"等级", value:12, valueType:"number"}
            ]}]
        };
        var callback:Object = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams("workbench.stats.1",
                "character-build.stats.open"));
        var statsParams:Object = wireParams("workbench.stats.1",
            "character-build.stats.clean");
        statsParams.sessionGeneration = opened.sessionGeneration;
        statsParams.expectedLoadoutRevision = opened.loadoutRevision;
        statsParams.expectedLiveRevision = opened.liveRevision;
        var clean:Object = CharacterBuildService.execute(
            "statsSnapshot", statsParams);
        check(clean.success && clean.payload === root.statsFixture
                && clean.payload.success == undefined
                && clean.payload.groups[0].rows[0].key == "level"
                && callback.state.statsCalls == 1
                && hasOnlyKeys(clean, commonWireKeys({payload:true})),
            "statsSnapshot 直接返回不含 success 的 PlayerInfo payload 且 wire 无二级 stats");

        var missingStatsParams:Object = wireParams("workbench.stats.1",
            "character-build.stats.missing-expected");
        missingStatsParams.sessionGeneration = opened.sessionGeneration;
        var missingStats:Object = CharacterBuildService.execute(
            "statsSnapshot", missingStatsParams);
        check(!missingStats.success && missingStats.error == "stale_state"
                && callback.state.statsCalls == 1,
            "statsSnapshot 缺 exact loadout/live revisions 时零 stats projection");

        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        var dirtyStateParams:Object = wireParams("workbench.stats.1",
            "character-build.stats.dirty-state");
        dirtyStateParams.sessionGeneration = opened.sessionGeneration;
        var dirtyState:Object = CharacterBuildService.execute(
            "snapshot", dirtyStateParams);
        var dirtyParams:Object = wireParams("workbench.stats.1",
            "character-build.stats.dirty");
        dirtyParams.sessionGeneration = opened.sessionGeneration;
        dirtyParams.expectedLoadoutRevision = dirtyState.loadoutRevision;
        dirtyParams.expectedLiveRevision = dirtyState.liveRevision;
        var dirty:Object = CharacterBuildService.execute(
            "statsSnapshot", dirtyParams);
        check(!dirty.success && dirty.error == "live_not_clean"
                && callback.state.statsCalls == 1,
            "live dirty 时 stats fail-closed 且不调用 PlayerInfoProvider");

        var refreshParams:Object = wireParams("workbench.stats.1",
            "character-build.stats.refresh");
        refreshParams.sessionGeneration = opened.sessionGeneration;
        var refreshedState:Object = CharacterBuildService.execute(
            "snapshot", refreshParams);
        var flushParams:Object = wireParams("workbench.stats.1",
            "character-build.stats.flush");
        flushParams.sessionGeneration = opened.sessionGeneration;
        flushParams.expectedLoadoutRevision =
            refreshedState.loadoutRevision;
        var flushed:Object = CharacterBuildService.execute(
            "flushLive", flushParams);
        statsParams.expectedLoadoutRevision = flushed.loadoutRevision;
        statsParams.expectedLiveRevision = flushed.liveRevision;
        var afterFlush:Object = CharacterBuildService.execute(
            "statsSnapshot", statsParams);
        check(flushed.success && flushed.changed
                && hasOnlyKeys(flushed, commonWireKeys({changed:true}))
                && afterFlush.success && callback.state.statsCalls == 2,
            "flushLive clean proof 后才开放 stats projection");

        var healthyStats:Object = root.statsFixture;
        root.statsFixture = {
            v:1,
            stateHealth:"unavailable",
            diagnostics:["hero_not_found"],
            groups:[]
        };
        var unavailable:Object = CharacterBuildService.execute(
            "statsSnapshot", statsParams);
        check(!unavailable.success
                && unavailable.error == "stats_unavailable"
                && callback.state.statsCalls == 3
                && hasOnlyKeys(unavailable, commonWireKeys({error:true})),
            "PlayerInfo stateHealth 非 ok 时显式返回 stats_unavailable");
        root.statsFixture = healthyStats;

        var finalizeParams:Object = wireParams("workbench.stats.1",
            "character-build.stats.finalize");
        finalizeParams.sessionGeneration = opened.sessionGeneration;
        finalizeParams.expectedLoadoutRevision = flushed.loadoutRevision;
        var finalized:Object = CharacterBuildService.execute(
            "finalize", finalizeParams);
        check(finalized.success && finalized.closed && !finalized.active
                && finalized.persistence.success
                && !finalized.persistence.changed
                && finalized.persistenceSucceeded == undefined
                && hasOnlyKeys(finalized, commonWireKeys({
                    closed:true, liveChanged:true, persistence:true
                })),
            "finalize wire 只附 closed/liveChanged/嵌套 persistence");
    }

    private static function testExactPauseAndDisconnectBarrier():Void {
        var root:Object = fixtureRoot(1);
        root._webPanelPauseLease = "lease.character.exact";
        var callback:Object = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.pause.1", "character-build.pause.open"));
        var genericBlocked:Object =
            CharacterBuildService.releasePauseForClose();
        check(CharacterBuildService.blocksGenericPauseRelease()
                && genericBlocked.handled
                && !genericBlocked.success
                && genericBlocked.error == "host_recovery_required"
                && genericBlocked.pauseRetained
                && root._webPanelPauseLease
                    == "lease.character.exact"
                && callback.state.releaseCalls == 0
                && callback.state.globalCalls == 0,
            "foreign generic close 只命中纯 fence，不凭 finalized A 副作用释放 pause");
        var closeParams:Object = wireParams(
            "workbench.pause.1", "host.recover.normal-close.1");
        closeParams.knownGeneration =
            opened.sessionGeneration;
        var exactClosed:Object =
            CharacterBuildService.recoverDetach(closeParams);
        check(exactClosed.success && exactClosed.pauseReleased
                && root._webPanelPauseLease == undefined
                && callback.state.releaseCalls == 1
                && callback.state.releasedLease
                    == "lease.character.exact"
                && !CharacterBuildService
                    .blocksGenericPauseRelease(),
            "正常 CharacterBuild close 只由 Host-only exact recoverDetach 释放一次");

        root = fixtureRoot(1);
        root._webPanelPauseLease = "lease.character.old";
        callback = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        CharacterBuildService.execute("snapshot", wireParams(
            "workbench.pause.2", "character-build.pause.old"));
        root._webPanelPauseLease = "lease.panel.later";
        var mismatch:Object = CharacterBuildService.reconcileSocketDetach();
        check(mismatch.handled && !mismatch.success
                && mismatch.error == "stale_pause_lease"
                && mismatch.pauseRetained
                && root._webPanelPauseLease == "lease.panel.later"
                && callback.state.releaseCalls == 0
                && callback.state.globalCalls == 0,
            "socket detach 遇到后来 panel lease 时零 finalize/零释放并 fail-closed");

        root = fixtureRoot(1);
        root._webPanelPauseLease = "lease.character.retry";
        callback = protocolCallbacks(root, true, false);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        opened = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.pause.3",
                "character-build.pause.retry"));
        var failed:Object = CharacterBuildService.reconcileSocketDetach();
        var leaseAfterFailure = root._webPanelPauseLease;
        callback.state.saveResult = true;
        var retried:Object = CharacterBuildService.reconcileSocketDetach();
        check(failed.handled && !failed.success
                && failed.error == "flush_failed"
                && failed.pauseRetained
                && leaseAfterFailure == "lease.character.retry"
                && root._webPanelPauseLease
                    == "lease.character.retry"
                && callback.state.saveCalls == 2
                && callback.state.releaseCalls == 0
                && retried.success && retried.pauseRetained
                && CharacterBuildService
                    .blocksGenericPauseRelease(),
            "socket detach 可重试 finalize/persist，但成功后仍保留 lease 等待 Host visual proof");
        var retryCloseParams:Object = wireParams(
            "workbench.pause.3", "host.recover.socket-close.1");
        retryCloseParams.knownGeneration =
            opened.sessionGeneration;
        var retryClosed:Object =
            CharacterBuildService.recoverDetach(
                retryCloseParams);
        check(retryClosed.success
                && root._webPanelPauseLease == undefined
                && callback.state.releaseCalls == 1
                && !CharacterBuildService
                    .blocksGenericPauseRelease(),
            "socket detach retain 后由重连 Host exact recovery 完成唯一释放");

        CharacterBuildService.testOnlyUseRoot(fixtureRoot(1));
        var absent:Object = CharacterBuildService.reconcileSocketDetach();
        check(!absent.handled && absent.success
                && !CharacterBuildService
                    .blocksGenericPauseRelease(),
            "无 CharacterBuild pause authority 时不拦 generic close");
    }

    private static function testHostOnlyDetachRecovery():Void {
        var root:Object = fixtureRoot(1);
        root._webPanelPauseLease = "lease.character.host-recover";
        var callback:Object = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var opened:Object = CharacterBuildService.execute(
            "snapshot", wireParams("workbench.recover.1",
                "character-build.recover.open"));
        var params:Object = wireParams("workbench.recover.1",
            "host.recover.1.1");
        params.knownGeneration = opened.sessionGeneration;
        var recovered:Object = CharacterBuildService.recoverDetach(params);
        check(recovered.success && recovered.command == "recoverDetach"
                && recovered.recoveryState == "settled"
                && recovered.closed && recovered.pauseReleased
                && !recovered.active
                && recovered.sessionGeneration == opened.sessionGeneration
                && recovered.loadoutRevision == recovered.liveRevision
                && !recovered.liveRefreshDirty
                && recovered.persistence.success
                && root._webPanelPauseLease == undefined
                && callback.state.releaseCalls == 1
                && !CharacterBuildService
                    .blocksGenericPauseRelease()
                && hasOnlyKeys(recovered, commonWireKeys({
                    recoveryState:true, closed:true, pauseReleased:true,
                    persistence:true
                })),
            "Host knownGeneration recovery 仅凭 exact finalize/persistence/live/pause proof 结算");

        var replay:Object = CharacterBuildService.recoverDetach(params);
        check(replay.success && replay.recoveryState == "settled"
                && replay.sessionGeneration == recovered.sessionGeneration
                && callback.state.releaseCalls == 1,
            "已完成 socket detach 可按 frozen receipt 幂等查询且不重复释放");

        root = fixtureRoot(1);
        root._webPanelPauseLease =
            "lease.character.retained-old";
        callback = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        opened = CharacterBuildService.execute(
            "snapshot", wireParams(
                "workbench.recover.retained",
                "character-build.recover.retained.open"));
        var retained:Object =
            CharacterBuildService.reconcileSocketDetach();
        root._webPanelPauseLease = "lease.panel.later-l2";
        params = wireParams(
            "workbench.recover.retained",
            "host.recover.retained.1");
        params.knownGeneration = opened.sessionGeneration;
        var laterMismatch:Object =
            CharacterBuildService.recoverDetach(params);
        check(retained.success && retained.pauseRetained
                && !laterMismatch.success
                && laterMismatch.error == "stale_pause_lease"
                && !laterMismatch.pauseReleased
                && root._webPanelPauseLease
                    == "lease.panel.later-l2"
                && callback.state.releaseCalls == 0
                && CharacterBuildService
                    .blocksGenericPauseRelease(),
            "retained A 遇到后来 L2 时 exact recovery 零释放、零清 authority");
        root._webPanelPauseLease =
            "lease.character.retained-old";
        params.requestCallId = "host.recover.retained.2";
        var retainedRetry:Object =
            CharacterBuildService.recoverDetach(params);
        check(retainedRetry.success
                && retainedRetry.pauseReleased
                && callback.state.releaseCalls == 1
                && root._webPanelPauseLease == undefined
                && !CharacterBuildService
                    .blocksGenericPauseRelease(),
            "stale_pause_lease 不消费 A；恢复 exact captured lease 后仍可安全结算一次");

        root = fixtureRoot(1);
        root._webPanelPauseLease = "lease.character.unknown-exact";
        callback = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        opened = CharacterBuildService.execute(
            "snapshot", wireParams("workbench.recover.unknown-exact",
                "character-build.recover.unknown-exact.open"));
        params = wireParams("workbench.recover.unknown-exact",
            "host.recover.unknown-exact.1");
        var unknownExact:Object = CharacterBuildService.recoverDetach(params);
        check(unknownExact.success
                && unknownExact.recoveryState == "settled"
                && unknownExact.sessionGeneration == opened.sessionGeneration
                && unknownExact.closed && unknownExact.pauseReleased
                && callback.state.releaseCalls == 1,
            "Host 未知 generation 仍可凭 exact old panel 查询并结算真实 AS2 session");

        root = fixtureRoot(1);
        root._webPanelPauseLease = "lease.character.authority-absent";
        callback = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        params = wireParams("workbench.recover.unknown",
            "host.recover.unknown.1");
        var absent:Object = CharacterBuildService.recoverDetach(params);
        check(absent.success
                && absent.recoveryState == "authority_absent"
                && absent.sessionGeneration == 0
                && absent.loadoutRevision == 0
                && absent.liveRevision == 0
                && absent.drugRevision == 0
                && absent.closed && absent.pauseReleased
                && absent.persistence.success
                && !absent.persistence.changed
                && callback.state.releaseCalls == 1
                && root._webPanelPauseLease == undefined,
            "首次响应未知且 AS2 确无 authority 时才释放遗留 pause 并证明 authority_absent");

        root = fixtureRoot(1);
        root._webPanelPauseLease = "lease.character.conflict";
        callback = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        CharacterBuildService.execute("snapshot", wireParams(
            "workbench.recover.owner", "character-build.recover.owner"));
        params = wireParams("workbench.recover.foreign",
            "host.recover.foreign.1");
        var conflict:Object = CharacterBuildService.recoverDetach(params);
        check(!conflict.success && conflict.error == "authority_conflict"
                && conflict.recoveryState == "unsettled"
                && !conflict.closed && !conflict.pauseReleased
                && root._webPanelPauseLease == "lease.character.conflict"
                && callback.state.releaseCalls == 0,
            "未知 generation 查询遇到其他 CharacterBuild authority 时绝不冒充 absent");

        CharacterBuildService.testOnlyUseRoot(fixtureRoot(1));
        params = wireParams("workbench.recover.never-opened",
            "host.recover.known-without-authority");
        params.knownGeneration = 9;
        var staleKnown:Object = CharacterBuildService.recoverDetach(params);
        check(!staleKnown.success && staleKnown.error == "stale_session"
                && staleKnown.recoveryState == "unsettled",
            "knownGeneration 在无 authority 时 fail-closed，不降级为 authority_absent");
    }

    private static function testOpenRejectsUnavailableLiveContext():Void {
        var root:Object = fixtureRoot(1);
        root.刷新人物装扮 = null;
        var callback:Object = protocolCallbacks(root, false, true);
        CharacterBuildService.testOnlyUseRoot(root);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var params:Object = wireParams("workbench.live.unavailable",
            "character-build.live.unavailable");
        var rejected:Object = CharacterBuildService.execute(
            "snapshot", params);
        check(!rejected.success && rejected.error == "live_unavailable"
                && !rejected.active && rejected.sessionGeneration == 0
                && root._webPanelPauseLease != undefined,
            "open 缺可结算 live hero context 时直接 live_unavailable，不创建永久 flush_failed session");

        var recovered:Object = CharacterBuildService.recoverDetach(params);
        check(recovered.success
                && recovered.recoveryState == "authority_absent"
                && recovered.pauseReleased
                && root._webPanelPauseLease == undefined
                && callback.state.releaseCalls == 1,
            "live_unavailable 的首次响应即使丢失，Host unknown recovery 仍可证明无 authority 并释放 pause");
    }

    private static function testInitialTransientStateDoesNotDirty():Void {
        var root:Object = fixtureRoot(1);
        var hero:Object = root.gameworld[root.控制目标];
        var originalBuffManager:Object = hero.buffManager;
        originalBuffManager.buffCount = 4;
        hero.hp = 23;
        hero.mp = 17;
        hero.格斗架势 = true;
        hero.攻击模式 = "兵器";
        hero.重量 = Number.NaN;
        hero.hp满血值 = Number.NaN;
        hero.魔法抗性 = null;
        hero.主动战技 = null;
        hero.生命周期函数列表 = null;
        var opened:Object = openFixture(root);
        var flushed:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, opened.loadoutRevision);
        check(opened.success && opened.loadoutRevision == 0
                && opened.liveRevision == 0 && !opened.liveRefreshDirty
                && flushed.success && !flushed.changed
                && root.refreshCalls == 0
                && hero.buffManager === originalBuffManager
                && hero.buffManager.buffCount == 4
                && hero.hp == 23 && hero.mp == 17
                && hero.格斗架势 && hero.攻击模式 == "兵器"
                && isNaN(hero.重量) && isNaN(hero.hp满血值)
                && hero.魔法抗性 == null && hero.主动战技 == null
                && hero.生命周期函数列表 == null,
            "HP/MP、Buff、姿态、攻击模式及刷新后验字段不参与初始 dirty，查看构筑零刷新");
    }

    private static function testRuntimeSlotAliasStaysClean():Void {
        var root:Object = fixtureRoot(1);
        var hero:Object = root.gameworld[root.控制目标];
        RuntimeEquipmentProjection.releaseAliases(hero);
        RuntimeEquipmentProjection.beginCanonical(hero);
        var aliasOwner:Object = {
            自机:hero,
            装备类型:"长枪",
            装备名称:hero.长枪.name,
            版本号:hero.version
        };
        var intent:Object = RuntimeEquipmentProjection.reserveEmptySlotAlias(
            aliasOwner, "刀");
        var committed:Boolean = RuntimeEquipmentProjection.commitSlotAlias(intent);
        var completed:Boolean = RuntimeEquipmentProjection.completeCanonical(hero);
        var opened:Object = openFixture(root);
        check(committed && completed && opened.success
                && opened.loadoutRevision == 0 && !opened.liveRefreshDirty
                && hero.刀 === hero.长枪
                && RuntimeEquipmentProjection.getCanonicalRef(hero, "刀") == null
                && RuntimeEquipmentProjection.hasActiveAlias(hero, "刀", "长枪"),
            "已登记的长枪到刀空槽借用被规范化为 canonical clean，不制造伪换装");

        root.物品栏.装备栏.items["长枪"].value.level = 3;
        var dirty:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        root.refreshAlias = "longgun_to_knife";
        var flushed:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(dirty.success && dirty.liveRefreshDirty
                && flushed.success && flushed.changed && root.refreshCalls == 1
                && !flushed.liveRefreshDirty
                && hero.刀 === hero.长枪
                && RuntimeEquipmentProjection.hasActiveAlias(hero, "刀", "长枪"),
            "真实长枪语义变化仍恰好刷新一次，并在刷新后重建合法复合武器 alias");
    }

    private static function testExternalDressupAdoptionAvoidsDuplicateRefresh():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        var dirty:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        root.刷新人物装扮(root.控制目标);
        var adopted:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        var flushed:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, adopted.loadoutRevision);
        check(dirty.success && dirty.liveRefreshDirty
                && adopted.success && !adopted.loadoutChanged
                && !adopted.liveRefreshDirty
                && adopted.liveRevision == adopted.loadoutRevision
                && flushed.success && !flushed.changed
                && root.refreshCalls == 1,
            "其他授权流程已完成 Dressup 时采信 applied stamp，构筑不重复刷新");
    }

    private static function testInvalidProjectionFailsClosed():Void {
        var root:Object = fixtureRoot(1);
        var hero:Object = root.gameworld[root.控制目标];
        RuntimeEquipmentProjection.releaseAliases(hero);
        CharacterBuildService.testOnlyUseRoot(root);
        var missing:Object = CharacterBuildService.open();
        check(!missing.success && missing.error == "live_unavailable"
                && !missing.active && root.refreshCalls == 0,
            "缺失 applied projection stamp 时 fail-closed，不把未知状态伪装成 dirty 后清 Buff");

        root = fixtureRoot(1);
        hero = root.gameworld[root.控制目标];
        hero.头部装备数据 = null;
        CharacterBuildService.testOnlyUseRoot(root);
        var malformed:Object = CharacterBuildService.open();
        check(!malformed.success && malformed.error == "live_unavailable"
                && !malformed.active && root.refreshCalls == 0,
            "装备派生数据损坏时拒绝建立会话，未知状态不触发猜测式刷新");
    }

    private static function testNotReadyGenerationAndOrder():Void {
        CharacterBuildService.testOnlyUseRoot({});
        var missing:Object = CharacterBuildService.open();
        check(!missing.success && missing.error == "service_not_ready"
                && missing.active == false,
            "open 缺容器时 fail-closed 且不创建 session");

        var root:Object = fixtureRoot(7);
        root._webPanelPauseLease = undefined;
        CharacterBuildService.testOnlyUseRoot(root);
        var missingLease:Object = CharacterBuildService.open();
        check(!missingLease.success
                && missingLease.error == "pause_lease_missing"
                && missingLease.active == false
                && missingLease.sessionGeneration == 0,
            "open 缺现役 exact pause lease 时 fail-closed 且不创建 session");

        root = fixtureRoot(7);
        var first:Object = openFixture(root);
        check(first.success && first.active && first.sessionGeneration == 1
                && first.loadoutRevision == 0 && first.liveRevision == 0
                && first.drugRevision == 7 && !first.liveRefreshDirty
                && first.slotKeys.join("|") == SLOT_KEYS.join("|"),
            "open 建立零 revision 基线并返回固定有序 11 槽");

        var second:Object = CharacterBuildService.open();
        check(second.success && second.sessionGeneration == 2
                && second.sessionGeneration > first.sessionGeneration
                && second.loadoutRevision == 0 && !second.liveRefreshDirty,
            "重复 open 铸造新 generation 并重建观察基线");

        root.物品栏.装备栏 = null;
        var rejected:Object = CharacterBuildService.open();
        var oldSnapshot:Object = CharacterBuildService.snapshot(second.sessionGeneration);
        check(!rejected.success && rejected.error == "service_not_ready"
                && !rejected.active && !oldSnapshot.success
                && oldSnapshot.error == "session_not_active",
            "active session 上的 open 失败会失效旧 generation");

        root = fixtureRoot(1);
        root.物品栏.装备栏.getItem = function(key:String):Void {
            throw "fixture_getItem";
        };
        var corruptOpen:Object = openFixture(root);
        check(!corruptOpen.success && corruptOpen.error == "invalid_loadout"
                && !corruptOpen.active,
            "open 遇到 getItem 异常时显式 fail-closed");
    }

    private static function testOpenDetectsStaleLive():Void {
        var root:Object = fixtureRoot(1);
        var hero:Object = root.gameworld[root.控制目标];
        hero.头部装备 = equipment("旧 live 头盔", 1, "", [], 1);
        var opened:Object = openFixture(root);
        check(opened.success && opened.loadoutRevision == 1
                && opened.liveRevision == 0 && opened.liveRefreshDirty
                && root.refreshCalls == 0,
            "open 发现 stale hero exact ref 时保守建立 dirty baseline");

        var flushed:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, opened.loadoutRevision);
        check(flushed.success && flushed.changed && root.refreshCalls == 1
                && !flushed.liveRefreshDirty
                && flushed.liveRevision == flushed.loadoutRevision
                && hero.头部装备 === root.物品栏.装备栏.items["头部装备"],
            "stale hero fresh open 后由 flushLive 恰好刷新一次");
    }

    private static function testStateOnlyDriftKeepsLiveMatched():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        root.物品栏.装备栏.items["手雷"].value -= 1;
        var stackDrift:Object = CharacterBuildService.synchronize(
            opened.sessionGeneration);
        root.物品栏.装备栏.items["头部装备"].lastUpdate = 11;
        var timestampDrift:Object = CharacterBuildService.synchronize(
            opened.sessionGeneration);
        var repeated:Object = CharacterBuildService.synchronize(
            opened.sessionGeneration);
        var callback:Object = callbacks(false, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var closed:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, timestampDrift.loadoutRevision);
        check(stackDrift.success && stackDrift.loadoutRevision == 1
                && stackDrift.liveRevision == 1 && !stackDrift.liveRefreshDirty
                && timestampDrift.loadoutRevision == 2
                && timestampDrift.liveRevision == 2 && !timestampDrift.liveRefreshDirty
                && repeated.loadoutRevision == 2 && !repeated.loadoutChanged
                && closed.success && !closed.liveChanged
                && root.refreshCalls == 0,
            "数量/lastUpdate 漂移推进 state revision，但 live 已匹配且零刷新");
    }

    private static function testSemanticSignatureAndExactRefs():Void {
        var root:Object = fixtureRoot(3);
        var opened:Object = openFixture(root);
        var generation:Number = opened.sessionGeneration;
        var items:Object = root.物品栏.装备栏.items;
        var baseline:Object = CharacterBuildService.synchronize(generation);
        check(baseline.success && baseline.loadoutRevision == 0
                && !baseline.loadoutChanged && !baseline.liveRefreshDirty,
            "未变化 synchronize 保持 loadout revision 与 live latch");

        items["头部装备"].value.level = 2;
        var levelDrift:Object = CharacterBuildService.synchronize(generation);
        check(levelDrift.loadoutRevision == 1 && levelDrift.loadoutChanged
                && levelDrift.liveRefreshDirty,
            "装备 level 原地变化进入语义签名");

        items["头部装备"].value.tier = "二阶";
        var tierDrift:Object = CharacterBuildService.synchronize(generation);
        check(tierDrift.loadoutRevision == 2 && tierDrift.loadoutChanged,
            "装备 tier 原地变化进入语义签名");

        items["头部装备"].lastUpdate = 11;
        var timestampDrift:Object = CharacterBuildService.synchronize(generation);
        check(timestampDrift.loadoutRevision == 3 && timestampDrift.loadoutChanged,
            "装备 item.lastUpdate 原地变化进入语义签名");

        var oldHead:Object = items["头部装备"];
        items["头部装备"] = equipment(
            oldHead.name,
            oldHead.value.level,
            oldHead.value.tier,
            ["导轨", "瞄具"],
            oldHead.lastUpdate
        );
        var refDrift:Object = CharacterBuildService.synchronize(generation);
        check(refDrift.loadoutRevision == 4 && refDrift.loadoutChanged,
            "语义相同的 item 引用替换仍推进 loadout revision");

        var stable:Object = CharacterBuildService.synchronize(generation);
        check(stable.loadoutRevision == 4 && !stable.loadoutChanged
                && stable.liveRefreshDirty,
            "引用基线更新后重复同步稳定且 dirty 只保持不重复推进");
    }

    private static function testFlushLiveBarrier():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        var clean:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, 0);
        check(clean.success && !clean.changed && root.refreshCalls == 0
                && clean.liveRevision == 0 && !clean.liveRefreshDirty,
            "flushLive clean fast path 零刷新");

        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        var dirty:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        var wrongGeneration:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration + 1, dirty.loadoutRevision);
        var wrongRevision:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, dirty.loadoutRevision + 1);
        check(!wrongGeneration.success && wrongGeneration.error == "stale_session"
                && !wrongRevision.success && wrongRevision.error == "stale_state"
                && root.refreshCalls == 0 && dirty.liveRefreshDirty,
            "flushLive 要求 exact generation/revision，拒绝时零刷新");

        var dressupDependency:Object = root.装备引用配置;
        root.装备引用配置 = null;
        var preFailed:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, dirty.loadoutRevision);
        root.装备引用配置 = dressupDependency;
        check(!preFailed.success && preFailed.error == "flush_failed"
                && preFailed.liveRevision == 0 && preFailed.liveRefreshDirty
                && root.refreshCalls == 0,
            "flushLive 缺必要装扮依赖时 preflight fail-closed");

        root.refreshMode = "throw";
        var thrown:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(!thrown.success && thrown.error == "flush_failed"
                && thrown.liveRevision == 0 && thrown.liveRefreshDirty
                && root.refreshCalls == 1,
            "刷新函数抛异常保留 live revision/dirty");

        var modes:Array = [
            "same_dispatcher", "same_buff", "slot_mismatch", "reuse_data",
            "missing_data", "bad_number", "bad_shape", "bad_tail", "wrong_parent",
            "replace_hero"
        ];
        for (var i:Number = 0; i < modes.length; i++) {
            root.refreshMode = modes[i];
            var failed:Object = CharacterBuildService.flushLive(
                opened.sessionGeneration, dirty.loadoutRevision);
            check(!failed.success && failed.error == "flush_failed"
                    && failed.liveRevision == 0 && failed.liveRefreshDirty,
                "flushLive postcondition 反例: " + modes[i]);
            if (modes[i] == "replace_hero") {
                root.gameworld[root.控制目标] = root.lastRefreshHero;
            }
            var hero:Object = root.gameworld[root.控制目标];
            hero._parent = root.gameworld;
            hero.格斗架势 = false;
            hero.dressupRefreshing = false;
        }

        root.refreshMode = "success";
        var beforeSuccessCalls:Number = root.refreshCalls;
        var flushed:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(flushed.success && flushed.changed
                && flushed.liveRevision == flushed.loadoutRevision
                && !flushed.liveRefreshDirty
                && root.refreshCalls == beforeSuccessCalls + 1,
            "全部后置条件成立后恰好一次刷新并清 live dirty");

        var afterSuccessCalls:Number = root.refreshCalls;
        var repeated:Object = CharacterBuildService.flushLive(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(repeated.success && !repeated.changed
                && root.refreshCalls == afterSuccessCalls,
            "已证明 live clean 后重复 flushLive 零刷新");
    }

    private static function testCombatStateExcluded():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        var gun:Object = root.物品栏.装备栏.items["长枪"];
        gun.value.shot = 9;
        gun.value.reloadCount = 8;
        gun.value.subweaponShot = 7;
        gun.value.subweaponReloadCount = 6;
        gun.value.当前战技 = 5;
        gun.value.wa90变形 = true;
        gun.value.长柄形态 = false;
        var sync:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(sync.success && sync.loadoutRevision == 0
                && !sync.loadoutChanged && !sync.liveRefreshDirty,
            "shot/reload/subweapon/当前战技/形态字段全部排除于构筑签名");
    }

    private static function testModifierCanonicalization():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        var head:Object = root.物品栏.装备栏.items["头部装备"];
        head.value.mods = ["瞄具", "导轨"];
        var arrayOrder:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(arrayOrder.loadoutRevision == 1 && arrayOrder.loadoutChanged,
            "mods Array 保序，顺序变化视为装配漂移");

        root = fixtureRoot(1);
        var firstMods:Object = {};
        firstMods.slotA = "导轨";
        firstMods.slotB = "瞄具";
        root.物品栏.装备栏.items["头部装备"].value.mods = firstMods;
        var baselineHero:Object = root.gameworld[root.控制目标];
        RuntimeEquipmentProjection.beginCanonical(baselineHero);
        RuntimeEquipmentProjection.completeCanonical(baselineHero);
        opened = openFixture(root);
        var secondMods:Object = {};
        secondMods.slotB = "瞄具";
        secondMods.slotA = "导轨";
        root.物品栏.装备栏.items["头部装备"].value.mods = secondMods;
        var objectOrder:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(objectOrder.loadoutRevision == 0 && !objectOrder.loadoutChanged,
            "legacy mods Object 按 key 排序，不受枚举顺序影响");

        var changedKeys:Object = {};
        changedKeys.slotB = "瞄具";
        changedKeys.slotC = "导轨";
        root.物品栏.装备栏.items["头部装备"].value.mods = changedKeys;
        var objectKey:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(objectKey.loadoutRevision == 1 && objectKey.loadoutChanged,
            "legacy mods Object 编码 key 与 value，等值改 key 仍可见");

        changedKeys.slotB = "弹匣";
        var objectValue:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(objectValue.loadoutRevision == 2 && objectValue.loadoutChanged,
            "legacy mods Object 的语义内容变化仍可见");
    }

    private static function testDrugIsolationAndStaleContainers():Void {
        var root:Object = fixtureRoot(5);
        var opened:Object = openFixture(root);
        root.物品栏.药剂栏.revision = 6;
        var advanced:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        var repeated:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(advanced.success && advanced.drugRevision == 6 && advanced.drugChanged
                && advanced.loadoutRevision == 0 && !advanced.liveRefreshDirty
                && repeated.drugRevision == 6 && !repeated.drugChanged,
            "药剂 revision 前进只更新 drugRevision，不点亮 live dirty");

        root.物品栏.药剂栏.revision = 4;
        var rollback:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(!rollback.success && rollback.error == "stale_drug_revision"
                && rollback.active && rollback.loadoutRevision == 0,
            "药剂 revision 倒退毒化当前 session 并 fail-closed");

        root.物品栏.药剂栏.revision = 6;
        var poisoned:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(!poisoned.success && poisoned.error == "stale_drug_revision"
                && poisoned.active,
            "倒退后的 session 不因 revision 恢复而自行解毒");

        root = fixtureRoot(2);
        opened = openFixture(root);
        root.物品栏.药剂栏 = makeDrugContainer(2);
        var drugReplaced:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        check(!drugReplaced.success && drugReplaced.error == "stale_container"
                && drugReplaced.active,
            "DrugInventory 引用替换即使 revision 相同也 stale");

        root = fixtureRoot(2);
        opened = openFixture(root);
        root.物品栏.装备栏 = makeEquipmentContainer(
            root.物品栏.装备栏.items);
        var equipmentReplaced:Object = CharacterBuildService.synchronize(
            opened.sessionGeneration);
        check(!equipmentReplaced.success && equipmentReplaced.error == "stale_container"
                && equipmentReplaced.loadoutRevision == 0,
            "EquipmentInventory 引用替换即使 items 相同也 stale");

        root = fixtureRoot(2);
        opened = openFixture(root);
        root.物品栏.装备栏.getItem = function(key:String):Void {
            throw "fixture_getItem";
        };
        var corruptSync:Object = CharacterBuildService.synchronize(
            opened.sessionGeneration);
        check(!corruptSync.success && corruptSync.error == "invalid_loadout"
                && corruptSync.active,
            "同步扫描异常毒化 session 并显式 fail-closed");
    }

    private static function testFinalizeGenerationAndCleanClose():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        var callback:Object = callbacks(false, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);

        var wrongGeneration:Object = CharacterBuildService.finalize(
            opened.sessionGeneration + 1, 0);
        check(!wrongGeneration.success && wrongGeneration.error == "stale_session"
                && wrongGeneration.active && !wrongGeneration.closed
                && !wrongGeneration.persistence.success
                && !wrongGeneration.persistence.changed && root.refreshCalls == 0
                && callback.state.globalCalls == 0 && callback.state.saveCalls == 0,
            "finalize 缺失 exact generation 时零回调且 session 保持 active");

        var wrongRevision:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, 1);
        check(!wrongRevision.success && wrongRevision.error == "stale_state"
                && wrongRevision.active && !wrongRevision.closed
                && !wrongRevision.persistence.success
                && !wrongRevision.persistence.changed
                && callback.state.globalCalls == 0,
            "finalize expected loadout revision stale 时零副作用");

        var closed:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, 0);
        check(closed.success && closed.closed && !closed.active
                && !closed.liveChanged && closed.persistence.success
                && !closed.persistence.changed
                && root.refreshCalls == 0 && callback.state.globalCalls == 1
                && callback.state.saveCalls == 0,
            "live/global 均 clean 的 close 零刷新、零 flushNow");

        var cleanRetry:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, 0);
        check(sameFinalizeProof(closed, cleanRetry)
                && cleanRetry.closed && !cleanRetry.active
                && cleanRetry.persistence.success
                && !cleanRetry.persistence.changed
                && root.refreshCalls == 0 && callback.state.globalCalls == 1
                && callback.state.saveCalls == 0,
            "global clean finalize exact retry 返回同 proof 且零 save");

        var afterClose:Object = CharacterBuildService.snapshot(opened.sessionGeneration);
        check(!afterClose.success && afterClose.error == "session_not_active",
            "finalize success 后同 generation 不可继续使用");
    }

    private static function testFinalizeDirtySuccessBranches():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        var dirty:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        var callback:Object = callbacks(false, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var globalClean:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(globalClean.success && globalClean.liveChanged
                && globalClean.liveRevision == globalClean.loadoutRevision
                && !globalClean.liveRefreshDirty && !globalClean.persistence.changed
                && root.refreshCalls == 1 && callback.state.saveCalls == 0,
            "dirty live 刷新成功且 global clean 时不调用 flushNow");

        root = fixtureRoot(1);
        opened = openFixture(root);
        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        dirty = CharacterBuildService.synchronize(opened.sessionGeneration);
        callback = callbacks(true, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var globalDirty:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(globalDirty.success && globalDirty.liveChanged
                && globalDirty.persistence.changed && !callback.state.globalDirty
                && root.refreshCalls == 1 && callback.state.globalCalls == 1
                && callback.state.saveCalls == 1,
            "dirty live 成功后仅在 global dirty 时调用一次 flushNow");

        root = fixtureRoot(1);
        opened = openFixture(root);
        callback = callbacks(true, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var persistenceOnly:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, 0);
        check(persistenceOnly.success && !persistenceOnly.liveChanged
                && persistenceOnly.persistence.changed
                && root.refreshCalls == 0 && callback.state.saveCalls == 1,
            "live clean 但 global dirty 时只执行持久化阶段");
    }

    private static function testFinalizeReceiptIdempotency():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        var dirty:Object = CharacterBuildService.synchronize(
            opened.sessionGeneration);
        var callback:Object = callbacks(true, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);

        // 模拟首次成功回包在跨层投递中丢失。
        var first:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        var refreshAfterFirst:Number = root.refreshCalls;
        var globalAfterFirst:Number = callback.state.globalCalls;
        var saveAfterFirst:Number = callback.state.saveCalls;
        var retry:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(first.success && first.closed && !first.active
                && first.liveChanged && first.persistence.success
                && first.persistence.changed
                && sameFinalizeProof(first, retry)
                && root.refreshCalls == refreshAfterFirst
                && callback.state.globalCalls == globalAfterFirst
                && callback.state.saveCalls == saveAfterFirst
                && refreshAfterFirst == 1 && globalAfterFirst == 1
                && saveAfterFirst == 1,
            "finalize 成功回包丢失后的 exact retry 复用完整 proof 且零副作用");

        var staleGeneration:Object = CharacterBuildService.finalize(
            opened.sessionGeneration + 1, dirty.loadoutRevision);
        var staleRevision:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision + 1);
        check(!staleGeneration.success && !staleGeneration.closed
                && !staleGeneration.active
                && !staleGeneration.persistence.success
                && !staleRevision.success && !staleRevision.closed
                && !staleRevision.active
                && !staleRevision.persistence.success
                && root.refreshCalls == refreshAfterFirst
                && callback.state.globalCalls == globalAfterFirst
                && callback.state.saveCalls == saveAfterFirst,
            "recent finalize receipt 只匹配 exact generation/revision");

        var reopened:Object = CharacterBuildService.open();
        var oldRetry:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        var current:Object = CharacterBuildService.snapshot(
            reopened.sessionGeneration);
        check(reopened.success
                && reopened.sessionGeneration != opened.sessionGeneration
                && !oldRetry.success && oldRetry.error == "stale_session"
                && !oldRetry.closed && oldRetry.active
                && !oldRetry.persistence.success
                && current.success && current.active
                && current.sessionGeneration == reopened.sessionGeneration
                && root.refreshCalls == refreshAfterFirst
                && callback.state.globalCalls == globalAfterFirst
                && callback.state.saveCalls == saveAfterFirst,
            "新 open 铸造 generation 后旧 receipt 不能结束新 session");
    }

    private static function testFinalizeFailureAndUnknown():Void {
        var root:Object = fixtureRoot(1);
        var opened:Object = openFixture(root);
        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        var dirty:Object = CharacterBuildService.synchronize(opened.sessionGeneration);
        root.refreshMode = "throw";
        var callback:Object = callbacks(true, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var liveFailed:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(!liveFailed.success && liveFailed.error == "flush_failed"
                && liveFailed.active && !liveFailed.closed
                && !liveFailed.persistence.success
                && !liveFailed.persistence.changed
                && liveFailed.liveRefreshDirty
                && root.refreshCalls == 1 && callback.state.globalCalls == 0
                && callback.state.saveCalls == 0,
            "live flush 明确失败保留 live dirty 与 active session");

        root.refreshMode = "success";
        var liveRetry:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(liveRetry.success && liveRetry.closed
                && root.refreshCalls == 2 && callback.state.saveCalls == 1,
            "live 明确失败不写 receipt，可在同 generation 显式重试");

        root = fixtureRoot(1);
        opened = openFixture(root);
        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        dirty = CharacterBuildService.synchronize(opened.sessionGeneration);
        callback = callbacks(true, false);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var saveFailed:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(!saveFailed.success && saveFailed.error == "flush_failed"
                && saveFailed.active && !saveFailed.closed
                && !saveFailed.persistence.success
                && !saveFailed.persistence.changed
                && !saveFailed.liveRefreshDirty
                && saveFailed.liveRevision == saveFailed.loadoutRevision
                && callback.state.globalDirty && root.refreshCalls == 1
                && callback.state.saveCalls == 1,
            "flushNow 明确失败保留 global dirty/session，但不重复已成功 live flush");

        callback.state.saveResult = true;
        var saveRetry:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(saveRetry.success && saveRetry.closed
                && root.refreshCalls == 1 && callback.state.saveCalls == 2
                && !callback.state.globalDirty,
            "持久化失败不写 receipt，重试跳过已证明成功的 live 阶段");

        root = fixtureRoot(1);
        opened = openFixture(root);
        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        dirty = CharacterBuildService.synchronize(opened.sessionGeneration);
        callback = callbacks(undefined, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var unknownGlobal:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(!unknownGlobal.success && unknownGlobal.error == "needs_reconcile"
                && unknownGlobal.active && !unknownGlobal.liveRefreshDirty
                && root.refreshCalls == 1 && callback.state.saveCalls == 0,
            "global dirty 判定 unknown 时即使 live clean 也不关闭");

        var unknownRetry:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(!unknownRetry.success && unknownRetry.error == "needs_reconcile"
                && unknownRetry.active && root.refreshCalls == 1,
            "unknown finalize 重试不凭 fresh live clean 冒充持久化成功");

        root = fixtureRoot(1);
        opened = openFixture(root);
        callback = callbacks(true, undefined);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var unknownSave:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, 0);
        check(!unknownSave.success && unknownSave.error == "needs_reconcile"
                && unknownSave.active && root.refreshCalls == 0
                && callback.state.saveCalls == 1 && callback.state.globalDirty,
            "flushNow 非 Boolean unknown 保留 active/global dirty");

        root = fixtureRoot(1);
        opened = openFixture(root);
        root.物品栏.装备栏.items["头部装备"].value.level = 2;
        dirty = CharacterBuildService.synchronize(opened.sessionGeneration);
        root.refreshMode = "throw";
        callback = callbacks(true, true);
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var thrownLive:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, dirty.loadoutRevision);
        check(!thrownLive.success && thrownLive.error == "flush_failed"
                && thrownLive.active && thrownLive.liveRefreshDirty
                && root.refreshCalls == 1 && callback.state.globalCalls == 0,
            "finalize 复用真实 flushLive wrapper，刷新抛错不进入 persistence");

        root = fixtureRoot(1);
        opened = openFixture(root);
        callback = callbacks(true, true);
        callback.flushNow = function() {
            callback.state.saveCalls++;
            throw "fixture_flushNow";
        };
        CharacterBuildService.testOnlyUseCallbacks(callback);
        var thrownSave:Object = CharacterBuildService.finalize(
            opened.sessionGeneration, 0);
        check(!thrownSave.success && thrownSave.error == "needs_reconcile"
                && thrownSave.active && callback.state.globalDirty
                && root.refreshCalls == 0 && callback.state.saveCalls == 1,
            "flushNow 抛异常时保留 active/global dirty 并要求 reconcile");
    }
}
