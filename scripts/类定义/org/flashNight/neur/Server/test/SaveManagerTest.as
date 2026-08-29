import org.flashNight.neur.Server.SaveManager;
import org.flashNight.neur.Server.ServerManager;
import org.flashNight.arki.render.FrameBroadcaster;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.item.obtain.ItemObtainIndex;
import JSON;

/**
 * SaveManager 单元测试
 * 测试约定：static runAllTests() 入口，trace [PASS]/[FAIL]
 */
class org.flashNight.neur.Server.test.SaveManagerTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;

    public static function runAllTests():Void {
        trace("========== SaveManagerTest START ==========");
        testCount = 0;
        passedCount = 0;
        failedCount = 0;

        var itemCatalogReceipt:Object = beginDrugItemCatalogFixture();
        try {
            runMigrationAndCoreTests();
            runSaveFlowTests();
            runLoadFromMydataTests();
            runPrefetchTests();
            runLoadAllTests();
            runRecoveryAndTombstoneTests();
        } finally {
            endDrugItemCatalogFixture(itemCatalogReceipt);
        }

        trace("========== SaveManagerTest END: " + passedCount + "/" + testCount + " passed, " + failedCount + " failed ==========");
    }

    private static function runMigrationAndCoreTests():Void {
        test_migrate_undefined_to_3_0();
        test_migrate_2_6_to_3_0();
        test_migrate_2_7_to_3_0();
        test_migrate_2_7_to_3_0_preserves_legacy_mainline();
        test_migrate_2_7_to_3_0_null_legacy_mainline_defaults_zero();
        test_migrate_3_0_noop();
        test_syncTopLevel_overwrite();
        test_syncTopLevel_from_empty();
        test_import_overwrite_clears_stale();
        test_tasks_finished_is_object();
        test_packGameState_syncs_mainline_progress();
        test_easterEgg_roundtrip();
        test_ensureShopNode_null_safe();
        test_loadShopCart_empty_top_level_keeps_nested_shop();
        test_loadShopPurchased_empty_top_level_keeps_nested_shop();
        test_ext_namespace_roundtrip();
        test_drug_schema_unmarked_discards_ghost_and_is_idempotent();
        test_drug_schema_v2_preserves_eight_and_cleans_out_of_range();
        test_drug_schema_future_version_fails_closed();
        test_migrate_drug_schema_sets_pending();
    }

    private static function runSaveFlowTests():Void {
        test_save_flow_restores_missing_save_system();
        test_hasPendingChanges_combines_both_latches();
        test_flushNow_success_clears_both_latches();
        test_flushNow_repeated_early_failure_publishes_attempt_edges();
        test_flushNow_save_disabled_preserves_dirty();
        test_flushNow_in_flight_preserves_dirty();
        test_flushNow_write_gate_rejection_preserves_dirty();
        test_flushNow_storage_false_preserves_dirty_and_retries();
        test_flushNow_storage_pending_preserves_dirty_and_retries();
        test_flushNow_drug_migration_pending_survives_failure();
        test_flushNow_precommit_throw_resets_in_flight();
        test_debounce_precommit_throw_resets_in_flight();
        test_debounce_exception_publishes_failed_state();
        test_flushNow_postcommit_notification_throw_keeps_success();
    }

    private static function runLoadFromMydataTests():Void {
        test_loadFromMydata_v3_succeeds();
        test_loadFromMydata_rejects_non_3_0();
        test_loadFromMydata_rejects_missing_inventory();
        test_loadFromMydata_rejects_short_slot0();
        test_loadFromMydata_rejects_missing_mainline();
        test_loadFromMydata_rejects_missing_tasks();
        test_loadFromMydata_rejects_missing_pets();
        test_loadFromMydata_rejects_missing_shop();
        test_loadFromMydata_sets_lastsave();
        test_loadFromMydata_resets_dirty();
        test_loadFromMydata_populates_tasks_pets_shop();
        test_loadFromMydata_drug_schema_success_resets_session();
        test_loadFromMydata_future_drug_schema_preserves_session();
        test_launcher_snapshot_migrates_drug_schema();
    }

    private static function runPrefetchTests():Void {
        test_getPrefetchStatus_after_clear();
        test_clearPrefetch_invalidates_late_callback();
        test_receiveSavePush_string_data();
        test_receiveSavePush_rejects_non_3_0();
        test_receiveSavePush_rejects_broken_json();
        test_receiveSavePush_rejects_truncated_tail();
        test_receiveSavePush_increments_gen();
    }

    private static function runLoadAllTests():Void {
        test_loadAll_prefers_json_when_newer();
        test_loadAll_json_future_drug_schema_does_not_fallback();
        test_loadAll_sol_future_drug_schema_fails_closed_non_destructive();
        test_loadAll_json_overlays_sol_shop();
        test_loadAll_json_overlays_sol_tasks();
        test_loadAll_sol_empty_top_level_keeps_nested_tasks();
        test_loadAll_sol_repairs_mainline_from_slot3();
        test_loadAll_json_overlays_sol_pets();
        test_loadAll_sol_empty_top_level_keeps_nested_pets();
        test_loadAll_sol_empty_top_level_keeps_nested_shop();
        test_loadAll_sol_resets_previous_settings_migration_latch();
        test_loadAll_rejects_stale_json();
        test_loadAll_clearPrefetch_blocks_late_callback();
        test_loadAll_recovers_from_missing_sol();
        test_loadAll_sanitize_slot_match();
        test_loadAll_sol_migrates_drug_schema();
    }

    private static function runRecoveryAndTombstoneTests():Void {
        test_deleteSlot_clears_prefetch();
        test_deleteSlot_tombstone_blocks_json_recovery();
        test_hasSaveData_with_prefetch();
        test_hasSaveData_respects_tombstone();
        test_isRecoveryPending();
        test_isRecoveryPending_false_after_delete();
        test_handlePreloadTombstoned_sets_sol_deleted();
        test_newCharacter_resets_drug_session_and_writes_v2_marker();
    }

    // ── helpers ──

    /**
     * TestLoader 不加载生产 items XML；为真实 BaseItem 反序列化路径安装最小药剂目录，
     * 并在本 suite 结束时恢复共享静态索引，避免污染后续 focused tests。
     */
    private static function beginDrugItemCatalogFixture():Object {
        var receipt:Object = {
            itemData:ItemUtil.itemDataDict,
            equipment:ItemUtil.equipmentDict,
            getItemData:_root.getItemData
        };
        var itemData:Object = copyDictionary(receipt.itemData);
        itemData["普通hp药剂"] = drugItemData("普通hp药剂");
        itemData["普通mp药剂"] = drugItemData("普通mp药剂");
        itemData["抗生素"] = drugItemData("抗生素");
        itemData["测试初始上装"] = equipmentItemData("测试初始上装", "上装装备");
        itemData["测试初始下装"] = equipmentItemData("测试初始下装", "下装装备");
        itemData["测试初始鞋"] = equipmentItemData("测试初始鞋", "脚部装备");
        ItemUtil.itemDataDict = itemData;
        var equipment:Object = copyDictionary(receipt.equipment);
        equipment["测试初始上装"] = true;
        equipment["测试初始下装"] = true;
        equipment["测试初始鞋"] = true;
        ItemUtil.equipmentDict = equipment;
        // TestLoader 不加载时间轴上的生产桥；装备栏仍按生产契约经
        // _root.getItemData 校验 use，因此 focused fixture 显式接到同一真源。
        _root.getItemData = function(index) {
            return ItemUtil.getItemData(index);
        };
        return receipt;
    }

    private static function endDrugItemCatalogFixture(receipt:Object):Void {
        ItemUtil.itemDataDict = receipt.itemData;
        ItemUtil.equipmentDict = receipt.equipment;
        _root.getItemData = receipt.getItemData;
    }

    private static function copyDictionary(source:Object):Object {
        var copy:Object = {};
        if (source == undefined || source == null) return copy;
        for (var key:String in source) copy[key] = source[key];
        return copy;
    }

    private static function drugItemData(name:String):Object {
        return {
            name:name, displayname:name, icon:name,
            type:"消耗品", use:"药剂", data:{level:1}
        };
    }

    private static function equipmentItemData(name:String, use:String):Object {
        return {
            name:name, displayname:name, icon:name,
            type:"装备", use:use, data:{level:1}
        };
    }

    private static function ownKeyCount(value:Object):Number {
        var count:Number = 0;
        for (var key:String in value) {
            if (value.hasOwnProperty(key)) count++;
        }
        return count;
    }

    private static function assert(condition:Boolean, msg:String):Void {
        testCount++;
        if (condition) {
            passedCount++;
            trace("[PASS] " + msg);
        } else {
            failedCount++;
            trace("[FAIL] " + msg);
        }
    }

    private static function beginFrameUiCapture():Object {
        var capture:Object = {
            hadServer: (_root.server != undefined),
            server: _root.server,
            hadGameworld: (_root.gameworld != undefined),
            gameworld: _root.gameworld,
            messages: []
        };
        _root.server = {
            isSocketConnected: true,
            sendSocketMessage: function(message:String):Void {
                capture.messages.push(message);
            }
        };
        _root.gameworld = {_x:0, _y:0, _xscale:100};
        // 清掉前一测试尚未被帧末消费的通用 UI 状态，保证本次序列可精确断言。
        FrameBroadcaster.send();
        capture.messages = [];
        return capture;
    }

    private static function takeFrameUiPayload(capture:Object):String {
        FrameBroadcaster.send();
        if (capture.messages.length == 0) return "";
        var message:String = String(capture.messages[capture.messages.length - 1]);
        capture.messages = [];
        var uiIndex:Number = message.indexOf("\x03");
        if (uiIndex < 0) return "";
        var payload:String = message.substring(uiIndex + 1);
        var inputIndex:Number = payload.indexOf("\x04");
        return inputIndex >= 0 ? payload.substring(0, inputIndex) : payload;
    }

    private static function endFrameUiCapture(capture:Object):Void {
        if (capture.hadServer) _root.server = capture.server;
        else delete _root.server;
        if (capture.hadGameworld) _root.gameworld = capture.gameworld;
        else delete _root.gameworld;
    }

    private static function beginSaveFlowTest():Object {
        var hadSaveSystem:Boolean = (_root.存档系统 != undefined);
        if (!hadSaveSystem) _root.存档系统 = {};

        var server:ServerManager = ServerManager.getInstance();
        var saved:Object = {
            hadSaveSystem: hadSaveSystem,
            savePath: _root.savePath,
            allowSave: _root.允许存档,
            roleName: _root.角色名,
            level: _root.等级,
            baseWorth: _root.基础身价值,
            calibrationNoSave: _root.斗兽标定禁存档,
            agentCalibrationNoSave: _root._agentCalibrationNoSave,
            internalDirty: SaveManager.getInstance().isDirty(),
            externalDirty: _root.存档系统.dirtyMark,
            updateTaskProgress: _root.UpdateTaskProgress,
            socketConnected: server.isSocketConnected,
            mydata: _root.mydata,
            saveFlag: _root.存盘标志,
            mainlineProgress: _root.主线任务进度,
            worth: _root.身价,
            saveExt: _root._saveExt,
            killStats: _root.killStats
        };

        _root.savePath = TEST_SLOT;
        SharedObject.getLocal(TEST_SLOT).clear();
        _root.允许存档 = true;
        _root.角色名 = "SaveManagerTest";
        _root.等级 = 1;
        _root.基础身价值 = 1000;
        _root.斗兽标定禁存档 = false;
        _root._agentCalibrationNoSave = false;
        _root.存档系统.dirtyMark = false;
        _root.存盘标志 = 0;
        _root.UpdateTaskProgress = function():Void {};
        server.isSocketConnected = false;
        SaveManager.getInstance()._configureSaveFlowForTest({
            saveInFlight:false,
            beforeLocalCommit:null,
            flushResult:undefined,
            resetDirty:true
        });
        SaveManager.getInstance().clearPendingDrugLoadoutMigration();
        return saved;
    }

    private static function endSaveFlowTest(saved:Object):Void {
        SharedObject.getLocal(TEST_SLOT).clear();
        SaveManager.getInstance()._configureSaveFlowForTest({
            saveInFlight:false,
            beforeLocalCommit:null,
            flushResult:undefined,
            resetDirty:true
        });
        SaveManager.getInstance().clearPendingDrugLoadoutMigration();
        _root.savePath = saved.savePath;
        _root.允许存档 = saved.allowSave;
        _root.角色名 = saved.roleName;
        _root.等级 = saved.level;
        _root.基础身价值 = saved.baseWorth;
        _root.斗兽标定禁存档 = saved.calibrationNoSave;
        _root._agentCalibrationNoSave = saved.agentCalibrationNoSave;
        if (saved.internalDirty === true) SaveManager.getInstance().markDirty();
        if (saved.hadSaveSystem === true) {
            _root.存档系统.dirtyMark = saved.externalDirty;
        } else {
            delete _root.存档系统;
        }
        _root.UpdateTaskProgress = saved.updateTaskProgress;
        _root.mydata = saved.mydata;
        _root.存盘标志 = saved.saveFlag;
        _root.主线任务进度 = saved.mainlineProgress;
        _root.身价 = saved.worth;
        _root._saveExt = saved.saveExt;
        _root.killStats = saved.killStats;
        ServerManager.getInstance().isSocketConnected = saved.socketConnected;
    }

    // ── test cases ──

    private static function test_save_flow_restores_missing_save_system():Void {
        var hadSaveSystem:Boolean = (_root.存档系统 != undefined);
        var originalSaveSystem:Object = _root.存档系统;
        delete _root.存档系统;
        var saved:Object = beginSaveFlowTest();
        endSaveFlowTest(saved);
        assert(_root.存档系统 == undefined,
               "save_flow_fixture: removes the temporary save system when none existed");
        if (hadSaveSystem) _root.存档系统 = originalSaveSystem;
    }

    private static function test_hasPendingChanges_combines_both_latches():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            assert(sm.hasPendingChanges() == false,
                   "hasPendingChanges: clean when both latches are false");

            _root.存档系统.dirtyMark = true;
            assert(sm.hasPendingChanges() == true,
                   "hasPendingChanges: observes external dirtyMark");
            assert(sm.isDirty() == false,
                   "hasPendingChanges: query has no write side effect and isDirty compatibility remains");

            _root.存档系统.dirtyMark = false;
            sm.markDirty();
            assert(sm.hasPendingChanges() == true,
                   "hasPendingChanges: observes private dirty latch");
            assert(sm.isDirty() == true,
                   "hasPendingChanges: isDirty still exposes private latch");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_success_clears_both_latches():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            _root.存档系统.dirtyMark = true;

            var ok:Boolean = sm.flushNow();
            assert(ok == true, "flushNow_success: returns true after local SharedObject commit");
            assert(sm.hasPendingChanges() == false,
                   "flushNow_success: clears private and external dirty latches");
            assert(SharedObject.getLocal(TEST_SLOT).data["test"] != undefined,
                   "flushNow_success: committed save payload exists");
            assert(_root.存盘标志 == 1,
                   "flushNow_success: publishes the saved flag only after local commit");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_repeated_early_failure_publishes_attempt_edges():Void {
        var saved:Object = beginSaveFlowTest();
        var capture:Object = beginFrameUiCapture();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            _root.允许存档 = false;

            assert(sm.flushNow() == false,
                   "flushNow_repeated_early_failure: first attempt is rejected");
            assert(takeFrameUiPayload(capture) == "sv:1|sv:3",
                   "flushNow_repeated_early_failure: first attempt publishes Saving then Failed");

            assert(sm.flushNow() == false,
                   "flushNow_repeated_early_failure: retry with the same cause is rejected");
            assert(takeFrameUiPayload(capture) == "sv:1|sv:3",
                   "flushNow_repeated_early_failure: retry still crosses a dedup-safe state edge");
        } finally {
            endFrameUiCapture(capture);
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_save_disabled_preserves_dirty():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            _root.允许存档 = false;

            assert(sm.flushNow() == false,
                   "flushNow_save_disabled: returns false");
            assert(sm.hasPendingChanges() == true,
                   "flushNow_save_disabled: dirty remains pending");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_in_flight_preserves_dirty():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            sm._configureSaveFlowForTest({saveInFlight:true});

            assert(sm.flushNow() == false,
                   "flushNow_in_flight: returns false");
            assert(sm.hasPendingChanges() == true,
                   "flushNow_in_flight: dirty remains pending");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_write_gate_rejection_preserves_dirty():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            _root.角色名 = "";

            assert(sm.flushNow() == false,
                   "flushNow_write_gate: invalid role is rejected");
            assert(sm.hasPendingChanges() == true,
                   "flushNow_write_gate: dirty remains pending");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_storage_false_preserves_dirty_and_retries():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            sm._configureSaveFlowForTest({flushResult:false});

            assert(sm.flushNow() == false,
                   "flushNow_storage_false: explicit storage failure returns false");
            assert(sm.hasPendingChanges() == true,
                   "flushNow_storage_false: dirty remains pending");
            assert(_root.存盘标志 == 0,
                   "flushNow_storage_false: failed local commit never publishes the saved flag");

            sm._configureSaveFlowForTest({flushResult:undefined});
            assert(sm.flushNow() == true,
                   "flushNow_storage_false: retry succeeds because in-flight resets");
            assert(_root.存盘标志 == 1,
                   "flushNow_storage_false: successful retry publishes the saved flag");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_storage_pending_preserves_dirty_and_retries():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            sm._configureSaveFlowForTest({flushResult:"pending"});

            assert(sm.flushNow() == false,
                   "flushNow_storage_pending: pending is not committed success");
            assert(sm.hasPendingChanges() == true,
                   "flushNow_storage_pending: dirty remains pending");
            assert(_root.存盘标志 == 0,
                   "flushNow_storage_pending: pending local commit never publishes the saved flag");

            sm._configureSaveFlowForTest({flushResult:undefined});
            assert(sm.flushNow() == true,
                   "flushNow_storage_pending: retry succeeds because in-flight resets");
            assert(_root.存盘标志 == 1,
                   "flushNow_storage_pending: successful retry publishes the saved flag");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_drug_migration_pending_survives_failure():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            var md:Object = buildValidMydata();
            var legacyGhosts:Object = {};
            legacyGhosts["4"] = {name:"旧ghost", value:1};
            md.inventory.药剂栏 = legacyGhosts;
            sm.migrate(md, {});
            assert(sm.hasPendingDrugLoadoutMigration(),
                "flushNow_drug_migration: fixture starts with feature migration pending");

            sm._configureSaveFlowForTest({flushResult:false});
            assert(!sm.flushNow() && sm.hasPendingDrugLoadoutMigration()
                    && sm.hasPendingChanges(),
                "flushNow_drug_migration: failed storage commit cannot clear feature pending");

            sm._configureSaveFlowForTest({flushResult:undefined});
            assert(sm.flushNow() && !sm.hasPendingDrugLoadoutMigration(),
                "flushNow_drug_migration: only a successful full save clears feature pending");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_precommit_throw_resets_in_flight():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            sm._configureSaveFlowForTest({
                beforeLocalCommit:function():Void {
                    throw new Error("injected pre-commit failure");
                }
            });

            var threw:Boolean = false;
            try {
                sm.flushNow();
            } catch (error:Error) {
                threw = true;
            }
            assert(threw == true,
                   "flushNow_precommit_throw: injected exception propagates");
            assert(sm.hasPendingChanges() == true,
                   "flushNow_precommit_throw: dirty remains pending");

            sm._configureSaveFlowForTest({beforeLocalCommit:null});
            assert(sm.flushNow() == true,
                   "flushNow_precommit_throw: retry succeeds because in-flight resets");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_debounce_precommit_throw_resets_in_flight():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            sm._configureSaveFlowForTest({
                beforeLocalCommit:function():Void {
                    throw new Error("injected debounce pre-commit failure");
                }
            });

            var threw:Boolean = false;
            try {
                sm._triggerDebounceForTest();
            } catch (error:Error) {
                threw = true;
            }
            assert(threw == true,
                   "debounce_precommit_throw: injected exception propagates");
            assert(sm.hasPendingChanges() == true,
                   "debounce_precommit_throw: dirty remains pending");

            sm._configureSaveFlowForTest({beforeLocalCommit:null});
            assert(sm.flushNow() == true,
                   "debounce_precommit_throw: retry succeeds because in-flight resets");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_debounce_exception_publishes_failed_state():Void {
        var saved:Object = beginSaveFlowTest();
        var capture:Object = beginFrameUiCapture();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            sm._configureSaveFlowForTest({
                beforeLocalCommit:function():Void {
                    throw new Error("injected debounce UI failure");
                }
            });

            var threw:Boolean = false;
            try {
                sm._triggerDebounceForTest();
            } catch (error:Error) {
                threw = true;
            }
            assert(threw == true,
                   "debounce_ui_failure: injected exception still propagates");
            assert(takeFrameUiPayload(capture) == "sv:1|sv:3",
                   "debounce_ui_failure: background failure closes the generic Saving state");
        } finally {
            endFrameUiCapture(capture);
            endSaveFlowTest(saved);
        }
    }

    private static function test_flushNow_postcommit_notification_throw_keeps_success():Void {
        var saved:Object = beginSaveFlowTest();
        try {
            var sm:SaveManager = SaveManager.getInstance();
            sm.markDirty();
            _root.存档系统.dirtyMark = true;
            _root.UpdateTaskProgress = function():Void {
                throw new Error("injected post-commit notification failure");
            };

            var ok:Boolean = sm.flushNow();
            assert(ok == true,
                   "flushNow_postcommit_throw: local commit remains successful");
            assert(sm.hasPendingChanges() == false,
                   "flushNow_postcommit_throw: committed dirty latches stay clear");
            assert(SharedObject.getLocal(TEST_SLOT).data["test"] != undefined,
                   "flushNow_postcommit_throw: local payload remains committed");
        } finally {
            endSaveFlowTest(saved);
        }
    }

    private static function test_migrate_undefined_to_3_0():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = {};
        mydata[0] = ["角色A", "男"];
        mydata[3] = 5;
        mydata.infrastructure = {};
        mydata.inventory = { 背包:{}, 装备栏:{}, 药剂栏:{}, 仓库:{}, 战备箱:{} };
        mydata.collection = { 材料:{}, 情报:{} };
        var soData:Object = {};
        soData["test"] = mydata;
        soData.tasks_to_do = [{id:"t1"}];
        soData.tasks_finished = {};
        soData.tasks_finished["t0"] = 1;
        soData.task_chains_progress = {};
        soData.战宠 = [["pet1"]];
        soData.宠物领养限制 = 3;

        // 确保旧迁移函数存在（测试环境 mock）
        if (_root.存档系统 == undefined) _root.存档系统 = {};
        if (_root.存档系统.convert_2_6 == undefined) {
            _root.存档系统.convert_2_6 = function(data) {};
        }

        var changed:Boolean = sm.migrate(mydata, soData);
        assert(changed == true, "migrate_undefined_to_3_0: changed should be true");
        assert(mydata.version == "3.0", "migrate_undefined_to_3_0: version should be 3.0, got " + mydata.version);
        assert(mydata.tasks != undefined, "migrate_undefined_to_3_0: mydata.tasks should exist");
        assert(mydata.tasks.tasks_to_do[0].id == "t1", "migrate_undefined_to_3_0: tasks_to_do preserved");
        assert(mydata.pets.宠物信息[0][0] == "pet1", "migrate_undefined_to_3_0: pets preserved");
        assert(mydata.pets.宠物领养限制 == 3, "migrate_undefined_to_3_0: 宠物领养限制 preserved");
    }

    private static function test_migrate_2_6_to_3_0():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = {};
        mydata.version = "2.6";
        mydata.inventory = { 背包:{}, 装备栏:{}, 药剂栏:{}, 仓库:{}, 战备箱:{} };
        mydata.collection = { 材料:{}, 情报:{} };
        var soData:Object = {};
        soData["test"] = mydata;
        soData.tasks_to_do = [];
        soData.tasks_finished = {};
        soData.task_chains_progress = {};

        if (_root.存档系统 == undefined) _root.存档系统 = {};
        if (_root.存档系统.convert_2_6 == undefined) {
            _root.存档系统.convert_2_6 = function(data) {};
        }

        var changed:Boolean = sm.migrate(mydata, soData);
        assert(changed == true, "migrate_2_6_to_3_0: changed");
        assert(mydata.version == "3.0", "migrate_2_6_to_3_0: version 3.0");
    }

    private static function test_migrate_2_7_to_3_0():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = {};
        mydata.version = "2.7";
        mydata.inventory = {药剂栏:{}};
        var soData:Object = {};
        soData["test"] = mydata;
        soData.tasks_to_do = ["a", "b"];
        soData.tasks_finished = {};
        soData.task_chains_progress = {};
        soData.战宠 = [[], [], [], [], []];
        soData.宠物领养限制 = 5;
        soData.商城已购买物品 = ["item1"];
        soData.商城购物车 = [];

        var changed:Boolean = sm.migrate(mydata, soData);
        assert(changed == true, "migrate_2_7_to_3_0: changed");
        assert(mydata.version == "3.0", "migrate_2_7_to_3_0: version 3.0");
        assert(mydata.tasks.tasks_to_do.length == 2, "migrate_2_7_to_3_0: tasks_to_do length");
        assert(mydata.shop.商城已购买物品[0] == "item1", "migrate_2_7_to_3_0: shop preserved");
    }

    private static function test_migrate_2_7_to_3_0_preserves_legacy_mainline():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = {};
        mydata.version = "2.7";
        mydata[3] = 17;
        mydata.inventory = {药剂栏:{}};
        var soData:Object = {};
        soData["test"] = mydata;
        soData.tasks_to_do = [];
        soData.tasks_finished = {};
        soData.task_chains_progress = {};
        soData.战宠 = [[], [], [], [], []];
        soData.宠物领养限制 = 5;
        soData.商城已购买物品 = [];
        soData.商城购物车 = [];

        var changed:Boolean = sm.migrate(mydata, soData);
        assert(changed == true, "migrate_2_7_to_3_0_preserves_legacy_mainline: changed");
        assert(mydata.tasks.task_chains_progress.主线 == 17,
               "migrate_2_7_to_3_0_preserves_legacy_mainline: mainline preserved");
    }

    private static function test_migrate_2_7_to_3_0_null_legacy_mainline_defaults_zero():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = buildValidMydata();
        mydata.version = "2.7";
        mydata[3] = null;
        delete mydata.tasks;
        delete mydata.pets;
        delete mydata.shop;

        var soData:Object = {};
        soData["test"] = mydata;
        soData.tasks_to_do = [];
        soData.tasks_finished = {};
        soData.task_chains_progress = {};
        soData.战宠 = [[], [], [], [], []];
        soData.宠物领养限制 = 5;
        soData.商城已购买物品 = [];
        soData.商城购物车 = [];

        var changed:Boolean = sm.migrate(mydata, soData);
        assert(changed == true, "migrate_2_7_to_3_0_null_legacy_mainline_defaults_zero: changed");
        assert(mydata[3] == 0,
               "migrate_2_7_to_3_0_null_legacy_mainline_defaults_zero: slot3 defaults to 0");
        assert(mydata.tasks.task_chains_progress.主线 == 0,
               "migrate_2_7_to_3_0_null_legacy_mainline_defaults_zero: mainline defaults to 0");
    }

    private static function test_migrate_3_0_noop():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = buildValidMydata();
        mydata.ext = {drugLoadout:{version:2}};
        var soData:Object = {};
        soData["test"] = mydata;

        var changed:Boolean = sm.migrate(mydata, soData);
        assert(changed == false, "migrate_3_0_noop: should not change");
        assert(mydata.version == "3.0", "migrate_3_0_noop: version still 3.0");
    }

    private static function test_syncTopLevel_overwrite():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = {};
        mydata.tasks = { tasks_to_do:["new"], tasks_finished:{}, task_chains_progress:{} };
        mydata.pets = { 宠物信息:[["newpet"]], 宠物领养限制:7 };
        mydata.shop = { 商城已购买物品:["new_item"], 商城购物车:[] };

        var soData:Object = {};
        soData.tasks_to_do = ["old"];
        soData.战宠 = [["oldpet"]];
        soData.商城已购买物品 = ["old_item"];

        sm.syncTopLevelFromMydata(mydata, soData);

        assert(soData.tasks_to_do[0] == "new", "syncTopLevel_overwrite: tasks overwritten");
        assert(soData.战宠[0][0] == "newpet", "syncTopLevel_overwrite: pets overwritten");
        assert(soData.商城已购买物品[0] == "new_item", "syncTopLevel_overwrite: shop overwritten");
        assert(soData.宠物领养限制 == 7, "syncTopLevel_overwrite: 宠物领养限制 overwritten");
    }

    private static function test_syncTopLevel_from_empty():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = {};
        mydata.tasks = { tasks_to_do:["x"], tasks_finished:{}, task_chains_progress:{} };
        mydata.pets = { 宠物信息:[], 宠物领养限制:5 };
        mydata.shop = { 商城已购买物品:[], 商城购物车:[] };

        var soData:Object = {};
        sm.syncTopLevelFromMydata(mydata, soData);

        assert(soData.tasks_to_do[0] == "x", "syncTopLevel_from_empty: tasks written");
        assert(soData.宠物领养限制 == 5, "syncTopLevel_from_empty: 宠物领养限制 written");
    }

    private static function test_import_overwrite_clears_stale():Void {
        var sm:SaveManager = SaveManager.getInstance();

        var soData:Object = {};
        soData.tasks_to_do = ["old_task"];
        soData.tasks_finished = {};
        soData.tasks_finished["old"] = 1;
        soData.task_chains_progress = { 主线:5 };
        soData.战宠 = [["old_pet"]];
        soData.宠物领养限制 = 3;
        soData.商城已购买物品 = ["old_shop"];
        soData.商城购物车 = ["old_cart"];

        // 模拟导入脚本的 delete
        delete soData.tasks_to_do;
        delete soData.tasks_finished;
        delete soData.task_chains_progress;
        delete soData.战宠;
        delete soData.宠物领养限制;
        delete soData.商城已购买物品;
        delete soData.商城购物车;

        // 写入新导入数据
        var importedMydata:Object = {};
        importedMydata.version = "3.0";
        importedMydata.inventory = {药剂栏:{}};
        importedMydata.ext = {drugLoadout:{version:2}};
        importedMydata.tasks = { tasks_to_do:["new_task"], tasks_finished:{}, task_chains_progress:{ 主线:10 } };
        importedMydata.pets = { 宠物信息:[["new_pet"]], 宠物领养限制:8 };
        importedMydata.shop = { 商城已购买物品:["new_shop"], 商城购物车:[] };
        soData["test"] = importedMydata;

        sm.migrateAndSync(importedMydata, soData);

        assert(soData.tasks_to_do[0] == "new_task", "import_overwrite: tasks_to_do is new");
        assert(soData.task_chains_progress.主线 == 10, "import_overwrite: progress is new");
        assert(soData.战宠[0][0] == "new_pet", "import_overwrite: pets is new");
        assert(soData.宠物领养限制 == 8, "import_overwrite: 宠物领养限制 is new");
        assert(soData.商城已购买物品[0] == "new_shop", "import_overwrite: shop is new");
    }

    private static function test_tasks_finished_is_object():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = {};
        mydata.version = "2.7";
        mydata.inventory = {药剂栏:{}};
        var soData:Object = {};
        soData["test"] = mydata;

        sm.migrate(mydata, soData);

        var tf:Object = mydata.tasks.tasks_finished;
        assert(tf.length == undefined, "tasks_finished_is_object: no .length (not array)");
        tf["123"] = 1;
        assert(tf["123"] == 1, "tasks_finished_is_object: string key works");
    }

    private static function test_packGameState_syncs_mainline_progress():Void {
        var sm:SaveManager = SaveManager.getInstance();

        var oldProgress = _root.主线任务进度;
        var oldChains = _root.task_chains_progress;

        // packGameState 不再有同步副作用，只是读取 _root.主线任务进度
        _root.task_chains_progress = { 主线: 42 };
        _root.主线任务进度 = 99;

        var mydata:Object = sm.packGameState();

        // mydata[3] 应该是 _root.主线任务进度 的值（99），而非 task_chains_progress 的值
        assert(mydata[3] == 99, "packGameState_no_sideeffect: mydata[3] should be 99 (from _root), got " + mydata[3]);
        assert(_root.主线任务进度 == 99, "packGameState_no_sideeffect: _root NOT modified by pack");

        _root.主线任务进度 = oldProgress;
        _root.task_chains_progress = oldChains;
    }

    private static function test_easterEgg_roundtrip():Void {
        var sm:SaveManager = SaveManager.getInstance();

        var oldEgg = _root.easterEgg;
        _root.easterEgg = "test_egg_value";

        var mydata:Object = sm.packGameState();
        assert(mydata[0][13] == "test_egg_value", "easterEgg_roundtrip: packed correctly");

        _root.easterEgg = undefined;
        sm.unpackGameState(mydata);
        assert(_root.easterEgg == "test_egg_value", "easterEgg_roundtrip: unpacked correctly");

        _root.easterEgg = oldEgg;
    }

    private static function test_ensureShopNode_null_safe():Void {
        // 模拟空 SO data（删档后或新槽位）
        var soData:Object = {};

        // 模拟 ensureShopNode 逻辑（private，通过观察验证）
        if (soData["test"] == undefined) soData["test"] = {};
        if (soData["test"].shop == undefined) soData["test"].shop = {};
        soData["test"].shop.商城购物车 = ["cart_item"];
        soData.商城购物车 = ["cart_item"];

        assert(soData["test"].shop.商城购物车[0] == "cart_item", "ensureShopNode: shop node created");
        assert(soData.商城购物车[0] == "cart_item", "ensureShopNode: dual-write top level ok");
    }

    private static function test_loadShopCart_empty_top_level_keeps_nested_shop():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        so.clear();
        so.data["test"] = buildValidMydata();
        so.data["test"].shop.商城购物车 = ["nested_cart"];
        so.data.商城购物车 = [];
        so.flush();

        _root.商城购物车 = ["stale"];
        sm.loadShopCart();
        assert(_root.商城购物车[0] == "nested_cart",
               "loadShopCart_empty_top_level_keeps_nested_shop: nested cart preserved");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadShopPurchased_empty_top_level_keeps_nested_shop():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        so.clear();
        so.data["test"] = buildValidMydata();
        so.data["test"].shop.商城已购买物品 = ["nested_item"];
        so.data.商城已购买物品 = [];
        so.flush();

        _root.商城已购买物品 = ["stale"];
        sm.loadShopPurchased();
        assert(_root.商城已购买物品[0] == "nested_item",
               "loadShopPurchased_empty_top_level_keeps_nested_shop: nested purchased preserved");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_ext_namespace_roundtrip():Void {
        var sm:SaveManager = SaveManager.getInstance();

        var oldExt = _root._saveExt;

        // 设置 ext 数据
        _root._saveExt = { modA: { enabled: true }, customData: 42 };

        var mydata:Object = sm.packGameState();
        assert(mydata.ext != undefined, "ext_roundtrip: ext exists in packed data");
        assert(mydata.ext.customData == 42, "ext_roundtrip: ext.customData preserved");
        assert(mydata.ext.drugLoadout.version == 2,
            "ext_roundtrip: pack defensively writes drugLoadout v2 without persisting active bank");
        assert(mydata.ext.drugLoadout.activeBank == undefined,
            "ext_roundtrip: active drug bank remains session-only");
        assert(mydata.reserved != undefined, "ext_roundtrip: reserved exists in packed data");

        // 清空后解包恢复
        _root._saveExt = undefined;
        sm.unpackGameState(mydata);
        assert(_root._saveExt != undefined, "ext_roundtrip: _saveExt restored after unpack");
        assert(_root._saveExt.customData == 42, "ext_roundtrip: _saveExt.customData restored");

        _root._saveExt = oldExt;
    }

    private static function test_drug_schema_unmarked_discards_ghost_and_is_idempotent():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var md:Object = buildValidMydata();
        md.ext = {};
        var legacySlots:Object = {};
        legacySlots["0"] = {name:"旧槽0", value:1};
        legacySlots["3"] = {name:"旧槽3", value:1};
        legacySlots["4"] = {name:"历史ghost4", value:1};
        legacySlots["7"] = {name:"历史ghost7", value:1};
        legacySlots["01"] = {name:"非规范键", value:1};
        md.inventory.药剂栏 = legacySlots;

        var first:Object = sm.normalizeDrugLoadoutSchema(md);
        assert(first.ok && first.changed && md.ext.drugLoadout.version == 2,
            "drug_schema_unmarked: installs feature marker and reports one migration");
        assert(md.inventory.药剂栏["0"].name == "旧槽0"
                && md.inventory.药剂栏["3"].name == "旧槽3",
            "drug_schema_unmarked: preserves canonical legacy slots 0..3");
        assert(md.inventory.药剂栏["4"] == undefined
                && md.inventory.药剂栏["7"] == undefined
                && md.inventory.药剂栏["01"] == undefined,
            "drug_schema_unmarked: deletes every hidden or noncanonical legacy key");

        var second:Object = sm.normalizeDrugLoadoutSchema(md);
        assert(second.ok && !second.changed,
            "drug_schema_unmarked: a second normalization is idempotent");
    }

    private static function test_drug_schema_v2_preserves_eight_and_cleans_out_of_range():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var md:Object = buildValidMydata();
        md.ext = {drugLoadout:{version:2, activeBank:1}};
        var v2Drugs:Object = {};
        v2Drugs["0"] = {name:"I-0", value:1};
        v2Drugs["4"] = {name:"II-0", value:1};
        v2Drugs["7"] = {name:"II-3", value:1};
        v2Drugs["8"] = {name:"越界", value:1};
        md.inventory.药剂栏 = v2Drugs;

        var result:Object = sm.normalizeDrugLoadoutSchema(md);
        assert(result.ok && result.changed
                && md.inventory.药剂栏["0"].name == "I-0"
                && md.inventory.药剂栏["4"].name == "II-0"
                && md.inventory.药剂栏["7"].name == "II-3",
            "drug_schema_v2: preserves all eight canonical physical positions");
        assert(md.inventory.药剂栏["8"] == undefined,
            "drug_schema_v2: removes out-of-range data without touching 0..7");
        assert(md.ext.drugLoadout.activeBank == undefined,
            "drug_schema_v2: strips legacy activeBank because bank selection is session-only");
        assert(sm.initInventory().药剂栏.capacity == 8,
            "drug_schema_v2: newly initialized drug inventory owns eight physical slots");
        assert(!sm.normalizeDrugLoadoutSchema(md).changed,
            "drug_schema_v2: cleaned v2 payload remains stable on roundtrip");
    }

    private static function test_drug_schema_future_version_fails_closed():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var md:Object = buildValidMydata();
        var futureItem:Object = {name:"未来槽", value:1};
        md.ext = {drugLoadout:{version:3}};
        var futureDrugs:Object = {};
        futureDrugs["7"] = futureItem;
        futureDrugs["8"] = {name:"未来扩展", value:1};
        md.inventory.药剂栏 = futureDrugs;

        var result:Object = sm.normalizeDrugLoadoutSchema(md);
        assert(!result.ok && !result.changed
                && result.error == "future_drug_loadout_version",
            "drug_schema_future: future feature versions fail closed");
        assert(md.inventory.药剂栏["7"] === futureItem
                && md.inventory.药剂栏["8"] != undefined
                && md.ext.drugLoadout.version == 3,
            "drug_schema_future: rejection is non-destructive and never downgrades data");
    }

    private static function test_migrate_drug_schema_sets_pending():Void {
        var sm:SaveManager = SaveManager.getInstance();
        sm.clearPendingDrugLoadoutMigration();
        var md:Object = buildValidMydata();
        var legacyDrugs:Object = {};
        legacyDrugs["0"] = {name:"保留", value:1};
        legacyDrugs["4"] = {name:"ghost", value:1};
        md.inventory.药剂栏 = legacyDrugs;
        var changed:Boolean = sm.migrate(md, {});
        assert(changed && sm.hasPendingDrugLoadoutMigration()
                && sm.hasPendingChanges(),
            "drug_schema_migrate: SOL migration joins the durable-save pending contract");
        assert(md.inventory.药剂栏["0"] != undefined
                && md.inventory.药剂栏["4"] == undefined,
            "drug_schema_migrate: SOL path performs the same old-ghost cleanup");
        sm.clearPendingDrugLoadoutMigration();
    }

    // ── Phase 1: loadFromMydata 测试 helpers ──

    private static function setUpForLoadTest():Void {
        // 环境 stub
        if (_root.存档系统 == undefined) _root.存档系统 = {};
        if (typeof _root.发布消息 != "function") _root.发布消息 = function(s) {};
        // unpackGameState 依赖
        if (typeof _root.根据等级得升级所需经验 != "function") _root.根据等级得升级所需经验 = function(lv) { return 999999; };
        if (typeof _root.更新主角被动技能 != "function") _root.更新主角被动技能 = function() {};
        if (typeof _root.初始化主角技能表 != "function") _root.初始化主角技能表 = function() {};
        if (_root.基建系统 == undefined) _root.基建系统 = { infrastructure: {} };
        // loadFromMydata 副作用链
        if (typeof _root.UpdateTaskProgress != "function") _root.UpdateTaskProgress = function() {};
        if (typeof _root.检查任务数据完整性 != "function") _root.检查任务数据完整性 = function() {};
        if (_root.UI系统 == undefined) _root.UI系统 = {};
        if (typeof _root.载入新佣兵库数据 != "function") _root.载入新佣兵库数据 = function() {};
        if (typeof _root.是否达成任务检测 != "function") _root.是否达成任务检测 = function() {};
        // 单例状态重置
        var sm:SaveManager = SaveManager.getInstance();
        sm.clearPrefetch();
        sm.clearPendingDrugLoadoutMigration();
        // _root 状态隔离
        _root.mydata = undefined;
        _root.角色名 = undefined;
        _root.lastsave = undefined;
    }

    private static function armBankTwoAndAllDrugCooldowns():Void {
        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void {});
        DrugInputService.resetSession();
        DrugInputService.updateSwitch(
            {hp:100}, true, true, {药剂组切换冷却时间:3000}, null);
        for (var lane:Number = 0; lane < 4; lane++) {
            ManualCooldownService.start(ManualCooldownService.drugKey(lane), 3000);
        }
    }

    private static function allDrugCooldownsReady(expected:Boolean):Boolean {
        if (ManualCooldownService.isReady(ManualCooldownService.drugSwitchKey()) != expected) {
            return false;
        }
        for (var lane:Number = 0; lane < 4; lane++) {
            if (ManualCooldownService.isReady(ManualCooldownService.drugKey(lane)) != expected) {
                return false;
            }
        }
        return true;
    }

    private static function buildValidMydata():Object {
        var md:Object = {};
        md.version = "3.0";
        md.lastSaved = "2026-01-01 00:00:00";
        md[0] = ["测试角色", "男", 1000, 10, 500, 170, 5, "无", 10000, 0, [], 0, [], ""];
        md[1] = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0];
        md[2] = null;
        md[3] = 0;
        md[4] = [[], 0];
        md[5] = [];
        md[6] = null;
        md[7] = [0, 0, 0, 0, 0];
        md.inventory = { 背包:[], 装备栏:{}, 药剂栏:[], 仓库:[], 战备箱:[] };
        md.collection = { 材料:{}, 情报:{} };
        md.infrastructure = {};
        md.others = {};
        md.tasks = { tasks_to_do:[], tasks_finished:{}, task_chains_progress:{} };
        md.pets = { 宠物信息:[[], [], [], [], []], 宠物领养限制:5 };
        md.shop = { 商城已购买物品:[], 商城购物车:[] };
        md.ext = {};
        md.reserved = {};
        return md;
    }

    // ── Phase 1: loadFromMydata 测试用例 ──

    private static function test_loadFromMydata_v3_succeeds():Void {
        setUpForLoadTest();
        var md:Object = buildValidMydata();
        md[0][0] = "成功角色";
        var sm:SaveManager = SaveManager.getInstance();
        var ok:Boolean = sm.loadFromMydata(md);
        assert(ok == true, "loadFromMydata_v3_succeeds: should return true");
        assert(_root.角色名 == "成功角色", "loadFromMydata_v3_succeeds: 角色名 set");
    }

    private static function test_loadFromMydata_rejects_non_3_0():Void {
        setUpForLoadTest();
        var md:Object = buildValidMydata();
        md.version = "2.7";
        var sm:SaveManager = SaveManager.getInstance();
        var ok:Boolean = sm.loadFromMydata(md);
        assert(ok == false, "loadFromMydata_rejects_non_3_0: should return false");
    }

    private static function test_loadFromMydata_rejects_missing_inventory():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();

        // 缺 背包
        var md1:Object = buildValidMydata();
        delete md1.inventory.背包;
        assert(sm.loadFromMydata(md1) == false, "loadFromMydata_rejects_missing_inventory: 背包");

        // 缺 装备栏
        var md2:Object = buildValidMydata();
        delete md2.inventory.装备栏;
        assert(sm.loadFromMydata(md2) == false, "loadFromMydata_rejects_missing_inventory: 装备栏");

        // 缺 药剂栏
        var md3:Object = buildValidMydata();
        delete md3.inventory.药剂栏;
        assert(sm.loadFromMydata(md3) == false, "loadFromMydata_rejects_missing_inventory: 药剂栏");

        // 缺 仓库
        var md4:Object = buildValidMydata();
        delete md4.inventory.仓库;
        assert(sm.loadFromMydata(md4) == false, "loadFromMydata_rejects_missing_inventory: 仓库");

        // 缺 战备箱
        var md5:Object = buildValidMydata();
        delete md5.inventory.战备箱;
        assert(sm.loadFromMydata(md5) == false, "loadFromMydata_rejects_missing_inventory: 战备箱");
    }

    private static function test_loadFromMydata_rejects_short_slot0():Void {
        setUpForLoadTest();
        var md:Object = buildValidMydata();
        md[0] = ["角色", "男", 1000]; // length=3 < 14
        var sm:SaveManager = SaveManager.getInstance();
        assert(sm.loadFromMydata(md) == false, "loadFromMydata_rejects_short_slot0: length < 14");
    }

    private static function test_loadFromMydata_rejects_missing_mainline():Void {
        setUpForLoadTest();
        var md:Object = buildValidMydata();
        delete md[3];
        var sm:SaveManager = SaveManager.getInstance();
        assert(sm.loadFromMydata(md) == false, "loadFromMydata_rejects_missing_mainline: mydata[3] undefined");
    }

    private static function test_loadFromMydata_rejects_missing_tasks():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();

        // 整体缺失
        var md1:Object = buildValidMydata();
        delete md1.tasks;
        assert(sm.loadFromMydata(md1) == false, "rejects_missing_tasks: tasks undefined");

        // 缺 tasks_to_do
        var md2:Object = buildValidMydata();
        delete md2.tasks.tasks_to_do;
        assert(sm.loadFromMydata(md2) == false, "rejects_missing_tasks: tasks_to_do undefined");

        // 缺 tasks_finished
        var md3:Object = buildValidMydata();
        delete md3.tasks.tasks_finished;
        assert(sm.loadFromMydata(md3) == false, "rejects_missing_tasks: tasks_finished undefined");

        // 缺 task_chains_progress
        var md4:Object = buildValidMydata();
        delete md4.tasks.task_chains_progress;
        assert(sm.loadFromMydata(md4) == false, "rejects_missing_tasks: task_chains_progress undefined");
    }

    private static function test_loadFromMydata_rejects_missing_pets():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();

        var md1:Object = buildValidMydata();
        delete md1.pets;
        assert(sm.loadFromMydata(md1) == false, "rejects_missing_pets: pets undefined");

        var md2:Object = buildValidMydata();
        delete md2.pets.宠物信息;
        assert(sm.loadFromMydata(md2) == false, "rejects_missing_pets: 宠物信息 undefined");

        var md3:Object = buildValidMydata();
        delete md3.pets.宠物领养限制;
        assert(sm.loadFromMydata(md3) == false, "rejects_missing_pets: 宠物领养限制 undefined");
    }

    private static function test_loadFromMydata_rejects_missing_shop():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();

        var md1:Object = buildValidMydata();
        delete md1.shop;
        assert(sm.loadFromMydata(md1) == false, "rejects_missing_shop: shop undefined");

        var md2:Object = buildValidMydata();
        delete md2.shop.商城已购买物品;
        assert(sm.loadFromMydata(md2) == false, "rejects_missing_shop: 商城已购买物品 undefined");

        var md3:Object = buildValidMydata();
        delete md3.shop.商城购物车;
        assert(sm.loadFromMydata(md3) == false, "rejects_missing_shop: 商城购物车 undefined");
    }

    private static function test_loadFromMydata_sets_lastsave():Void {
        setUpForLoadTest();
        _root.当前玩家总数 = 1;
        var md:Object = buildValidMydata();
        var sm:SaveManager = SaveManager.getInstance();
        sm.loadFromMydata(md);
        assert(_root.lastsave != undefined, "loadFromMydata_sets_lastsave: lastsave not undefined");
        _root.当前玩家总数 = undefined;
    }

    private static function test_loadFromMydata_resets_dirty():Void {
        setUpForLoadTest();
        _root.存档系统.dirtyMark = true;
        var md:Object = buildValidMydata();
        var sm:SaveManager = SaveManager.getInstance();
        sm.loadFromMydata(md);
        assert(_root.存档系统.dirtyMark == false, "loadFromMydata_resets_dirty: dirtyMark cleared");
    }

    private static function test_loadFromMydata_populates_tasks_pets_shop():Void {
        setUpForLoadTest();
        var md:Object = buildValidMydata();
        md.tasks.tasks_to_do = [{id:"t1"}];
        md.tasks.tasks_finished = {t0:1};
        md.tasks.task_chains_progress = {主线:7};
        md.pets.宠物信息 = [["petA"]];
        md.pets.宠物领养限制 = 3;
        md.shop.商城已购买物品 = ["itemX"];
        md.shop.商城购物车 = ["cartY"];

        var sm:SaveManager = SaveManager.getInstance();
        sm.loadFromMydata(md);

        assert(_root.tasks_to_do[0].id == "t1", "populates_tasks: tasks_to_do");
        assert(_root.tasks_finished.t0 == 1, "populates_tasks: tasks_finished");
        assert(_root.task_chains_progress.主线 == 7, "populates_tasks: task_chains_progress");
        assert(_root.宠物信息[0][0] == "petA", "populates_pets: 宠物信息");
        assert(_root.宠物领养限制 == 3, "populates_pets: 宠物领养限制");
        assert(_root.商城已购买物品[0] == "itemX", "populates_shop: 商城已购买物品");
        assert(_root.商城购物车[0] == "cartY", "populates_shop: 商城购物车");
    }

    private static function test_loadFromMydata_drug_schema_success_resets_session():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void {});
        DrugInputService.resetSession();
        var unit:Object = {hp:100};
        DrugInputService.updateSwitch(
            unit, true, true, {药剂组切换冷却时间:3000}, null);
        assert(DrugInputService.getActiveBank() == 1,
            "loadFromMydata_drug_success: fixture begins in bank II");

        var md:Object = buildValidMydata();
        md.ext = {drugLoadout:{version:2}};
        var v2Drugs:Object = {};
        v2Drugs["0"] = {name:"普通hp药剂", value:1};
        v2Drugs["4"] = {name:"普通mp药剂", value:2};
        v2Drugs["7"] = {name:"抗生素", value:3};
        md.inventory.药剂栏 = v2Drugs;
        assert(sm.loadFromMydata(md, "launcher_snapshot:test"),
            "loadFromMydata_drug_success: launcher-style core load succeeds");
        assert(_root.物品栏.药剂栏.getItem("4").name == "普通mp药剂"
                && _root.物品栏.药剂栏.getItem("7").name == "抗生素"
                && _root.物品栏.药剂栏.capacity == 8,
            "loadFromMydata_drug_success: v2 roundtrip preserves bank-II physical slots");
        assert(DrugInputService.getActiveBank() == 0
                && ManualCooldownService.isReady(ManualCooldownService.drugSwitchKey()),
            "loadFromMydata_drug_success: only successful unpack resets bank and drug cooldowns");
        ManualCooldownService.resetForTests();
    }

    private static function test_loadFromMydata_future_drug_schema_preserves_session():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        ManualCooldownService.resetForTests();
        ManualCooldownService.setSchedulerForTests(function(callback:Function):Void {});
        DrugInputService.resetSession();
        var unit:Object = {hp:100};
        DrugInputService.updateSwitch(
            unit, true, true, {药剂组切换冷却时间:3000}, null);
        var md:Object = buildValidMydata();
        md.ext = {drugLoadout:{version:3}};
        var futureDrugs:Object = {};
        futureDrugs["7"] = {name:"未来药剂", value:1};
        md.inventory.药剂栏 = futureDrugs;

        assert(!sm.loadFromMydata(md, "launcher_snapshot:future"),
            "loadFromMydata_drug_future: future feature schema rejects the load");
        assert(DrugInputService.getActiveBank() == 1
                && !ManualCooldownService.isReady(ManualCooldownService.drugSwitchKey()),
            "loadFromMydata_drug_future: failed load cannot reset live session bank or cooldown");
        DrugInputService.resetSession();
        ManualCooldownService.resetForTests();
    }

    private static function test_launcher_snapshot_migrates_drug_schema():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        sm._resetProtocol2ForTest();
        var md:Object = buildValidMydata();
        md.ext = {};
        var legacyDrugs:Object = {};
        legacyDrugs["0"] = {name:"普通hp药剂", value:1};
        legacyDrugs["4"] = {name:"launcher ghost", value:1};
        md.inventory.药剂栏 = legacyDrugs;
        _root._launcherSaveDecision = "snapshot";
        _root._launcherSnapshot = md;
        _root._launcherSnapshotSource = "json_shadow";

        sm.preload();
        var ok:Boolean = sm.loadAll();
        assert(ok && md.ext.drugLoadout.version == 2,
            "launcher_snapshot_drug_schema: protocol-2 snapshot uses shared v2 normalization");
        assert(_root.物品栏.药剂栏.getItem("0").name == "普通hp药剂"
                && _root.物品栏.药剂栏.getItem("4") == null,
            "launcher_snapshot_drug_schema: old snapshot keeps 0..3 and drops hidden 4..7");
        assert(sm.hasPendingDrugLoadoutMigration() && sm.hasPendingChanges(),
            "launcher_snapshot_drug_schema: in-memory snapshot migration remains pending until full save");
        sm._resetProtocol2ForTest();
        sm.clearPendingDrugLoadoutMigration();
    }

    // ── Phase 2: prefetch / receiveSavePush 测试 helpers ──

    private static var _testJsonParser:JSON;

    private static function getTestJsonParser():JSON {
        if (_testJsonParser == undefined) _testJsonParser = new JSON(false);
        return _testJsonParser;
    }

    private static function buildValidJsonString():String {
        var md:Object = buildValidMydata();
        md[0][0] = "JSON测试角色";
        return getTestJsonParser().stringify(md);
    }

    // ── Phase 2: prefetch / receiveSavePush 测试用例 ──

    private static function test_getPrefetchStatus_after_clear():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var gen0:Number = sm.getPrefetchStatus().gen;
        sm.clearPrefetch();
        var st:Object = sm.getPrefetchStatus();
        assert(st.hasPrefetch == false, "getPrefetchStatus_after_clear: hasPrefetch false");
        assert(st.gen == gen0 + 1, "getPrefetchStatus_after_clear: gen incremented");
    }

    private static function test_clearPrefetch_invalidates_late_callback():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        // 模拟 preload 闭包捕获的 gen
        var capturedGen:Number = sm.getPrefetchStatus().gen;
        // 模拟中间发生了 clearPrefetch（如 loadAll 放弃了 JSON）
        sm.clearPrefetch();
        // 验证捕获的 gen 已经过期
        var currentGen:Number = sm.getPrefetchStatus().gen;
        assert(capturedGen != currentGen, "clearPrefetch_invalidates: captured gen != current gen");
    }

    private static function test_receiveSavePush_string_data():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var jsonStr:String = buildValidJsonString();
        sm.receiveSavePush({ data: jsonStr, slot: "testSlot" });
        var st:Object = sm.getPrefetchStatus();
        assert(st.hasPrefetch == true, "receiveSavePush_string: hasPrefetch true");
        assert(st.slot == "testSlot", "receiveSavePush_string: slot correct");
    }

    private static function test_receiveSavePush_rejects_non_3_0():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var md:Object = buildValidMydata();
        md.version = "2.7";
        var jsonStr:String = getTestJsonParser().stringify(md);
        sm.receiveSavePush({ data: jsonStr, slot: "testSlot" });
        assert(sm.getPrefetchStatus().hasPrefetch == false, "receiveSavePush_rejects_non_3_0: rejected");
    }

    private static function test_receiveSavePush_rejects_broken_json():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        sm.receiveSavePush({ data: "{broken json!!!", slot: "testSlot" });
        assert(sm.getPrefetchStatus().hasPrefetch == false, "receiveSavePush_rejects_broken: rejected");
    }

    private static function test_receiveSavePush_rejects_truncated_tail():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        // 构建一个缺少 tasks 的 mydata — 模拟边界截断
        var md:Object = buildValidMydata();
        delete md.tasks;
        delete md.pets;
        delete md.shop;
        var jsonStr:String = getTestJsonParser().stringify(md);
        sm.receiveSavePush({ data: jsonStr, slot: "testSlot" });
        assert(sm.getPrefetchStatus().hasPrefetch == false, "receiveSavePush_rejects_truncated: validate rejected");
    }

    private static function test_receiveSavePush_increments_gen():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var gen0:Number = sm.getPrefetchStatus().gen;
        sm.receiveSavePush({ data: "irrelevant", slot: "x" });
        assert(sm.getPrefetchStatus().gen == gen0 + 1, "receiveSavePush_increments_gen: gen incremented");
    }

    // ── Phase 3: loadAll JSON+SO overlay 测试 helpers ──

    private static var TEST_SLOT:String = "__sm_test__";

    /**
     * seed 真实 SO 用于 loadAll 测试。
     * 写入一份最小可用存档到 SO，使 SOL 路径可以成功返回 true。
     */
    private static function seedTestSO(solLastSaved:String, extraTop:Object):Void {
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;
        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        var md:Object = buildValidMydata();
        md.lastSaved = solLastSaved;
        md[0][0] = "SOL角色";
        so.data["test"] = md;

        // 顶层 key（loadAll SOL 路径读取权威源）
        so.data.tasks_to_do = [];
        so.data.tasks_finished = {};
        so.data.task_chains_progress = {};

        // extraTop 允许测试覆盖特定顶层 key
        if (extraTop != undefined) {
            for (var k:String in extraTop) {
                so.data[k] = extraTop[k];
            }
        }

        so.flush();
        // preload 在帧63设 _root.mydata，这里模拟
        _root.mydata = md;
        _root.savePath = oldPath;
    }

    private static function cleanTestSO():Void {
        SharedObject.getLocal(TEST_SLOT).clear();
    }

    // ── Phase 3: loadAll 测试用例 ──

    private static function test_loadAll_sol_resets_previous_settings_migration_latch():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        seedTestSO("2026-01-01 00:00:00", undefined);
        _root.savePath = TEST_SLOT;
        sm.markSettingsMigrationPending();
        assert(sm.hasPendingSettingsMigration(),
            "loadAll_sol_resets_settings_latch: fixture starts with previous-save latch");

        var ok:Boolean = sm.loadAll();
        assert(ok == true,
            "loadAll_sol_resets_settings_latch: native SOL load succeeds");
        assert(!sm.hasPendingSettingsMigration(),
            "loadAll_sol_resets_settings_latch: clean SOL does not inherit previous-save latch");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_prefers_json_when_newer():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        // seed SO with old timestamp
        seedTestSO("2020-01-01 00:00:00", undefined);
        _root.savePath = TEST_SLOT;
        // _root.mydata.lastSaved 是 preload 缓存的 SOL 时间戳
        _root.mydata = { lastSaved: "2020-01-01 00:00:00" };

        // receiveSavePush 注入 newer JSON
        var md:Object = buildValidMydata();
        md.lastSaved = "2099-01-01 00:00:00";
        md[0][0] = "JSON角色";
        md.ext = {};
        var jsonDrugs:Object = {};
        jsonDrugs["0"] = {name:"普通hp药剂", value:1};
        jsonDrugs["4"] = {name:"JSON ghost", value:1};
        md.inventory.药剂栏 = jsonDrugs;
        var jsonStr:String = getTestJsonParser().stringify(md);
        sm.receiveSavePush({ data: jsonStr, slot: TEST_SLOT });

        var ok:Boolean = sm.loadAll();
        assert(ok == true, "loadAll_prefers_json: returned true");
        assert(_root.角色名 == "JSON角色", "loadAll_prefers_json: 角色名 from JSON, got " + _root.角色名);
        assert(_root.物品栏.药剂栏.getItem("0").name == "普通hp药剂"
                && _root.物品栏.药剂栏.getItem("4") == null,
            "loadAll_prefers_json: JSON shadow uses shared legacy ghost cleanup");
        assert(sm.hasPendingDrugLoadoutMigration(),
            "loadAll_prefers_json: JSON in-memory migration remains pending for full save");

        cleanTestSO();
        sm.clearPendingDrugLoadoutMigration();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_json_future_drug_schema_does_not_fallback():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath:Object = _root.savePath;
        var oldRestoreError:Object = _root._saveRestoreError;
        try {
            seedTestSO("2020-01-01 00:00:00", undefined);
            _root.savePath = TEST_SLOT;
            _root.mydata = {lastSaved:"2020-01-01 00:00:00"};
            _root.角色名 = "切换前角色";

            var future:Object = buildValidMydata();
            future.lastSaved = "2099-01-01 00:00:00";
            future[0][0] = "未来JSON角色";
            future.ext = {drugLoadout:{version:3}};
            var futureDrugs:Object = {};
            futureDrugs["7"] = {name:"未来药剂", value:1};
            future.inventory.药剂栏 = futureDrugs;
            sm.receiveSavePush({
                data:getTestJsonParser().stringify(future),
                slot:TEST_SLOT
            });

            var ok:Boolean = sm.loadAll();
            assert(!ok && _root._saveRestoreError === true,
                "loadAll_json_future_drug_schema: future marker fails closed with restore error");
            assert(_root.角色名 == "切换前角色",
                "loadAll_json_future_drug_schema: rejected JSON never silently falls back to older SOL");
        } finally {
            cleanTestSO();
            sm.clearPendingDrugLoadoutMigration();
            _root.savePath = oldPath;
            if (oldRestoreError === undefined) delete _root._saveRestoreError;
            else _root._saveRestoreError = oldRestoreError;
        }
    }

    private static function test_loadAll_sol_future_drug_schema_fails_closed_non_destructive():Void {
        var oldPath:Object = _root.savePath;
        var oldRole:Object = _root.角色名;
        var oldMydata:Object = _root.mydata;
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        try {
            seedTestSO("2026-01-01 00:00:00", undefined);
            _root.savePath = TEST_SLOT;
            var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
            so.data["test"].ext = {drugLoadout:{version:3}};
            var futureDrugs:Object = {};
            futureDrugs["7"] = {name:"未来SOL药剂", value:1};
            futureDrugs["8"] = {name:"未来扩展槽", value:2};
            so.data["test"].inventory.药剂栏 = futureDrugs;
            so.flush();

            _root.角色名 = "切换前角色";
            armBankTwoAndAllDrugCooldowns();
            var ok:Boolean = sm.loadAll();
            assert(!ok && _root.角色名 == "切换前角色"
                    && DrugInputService.getActiveBank() == 1
                    && allDrugCooldownsReady(false),
                "loadAll_sol_future_drug_schema: native SOL fails closed without resetting the live drug session");

            var after:SharedObject = SharedObject.getLocal(TEST_SLOT);
            assert(after.data["test"].ext.drugLoadout.version == 3
                    && after.data["test"].inventory.药剂栏["7"].name == "未来SOL药剂"
                    && after.data["test"].inventory.药剂栏["8"].name == "未来扩展槽",
                "loadAll_sol_future_drug_schema: rejected future SOL remains byte-shape non-destructive");
        } finally {
            DrugInputService.resetSession();
            ManualCooldownService.resetForTests();
            sm.clearPendingDrugLoadoutMigration();
            cleanTestSO();
            _root.savePath = oldPath;
            _root.角色名 = oldRole;
            _root.mydata = oldMydata;
        }
    }

    private static function test_loadAll_json_overlays_sol_shop():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        // seed SO: 顶层 shop 有"新物品"（模拟 saveShopPurchased 的 SO-only 写入）
        seedTestSO("2020-01-01 00:00:00", {
            商城已购买物品: ["新物品"],
            商城购物车: ["新车"]
        });
        _root.savePath = TEST_SLOT;
        _root.mydata = { lastSaved: "2020-01-01 00:00:00" };

        // JSON 中的 shop 是旧的
        var md:Object = buildValidMydata();
        md.lastSaved = "2099-01-01 00:00:00";
        md.shop.商城已购买物品 = ["旧物品"];
        md.shop.商城购物车 = ["旧车"];
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });

        sm.loadAll();
        assert(_root.商城已购买物品[0] == "新物品", "loadAll_overlays_shop: 商城已购买物品 from SO, got " + _root.商城已购买物品[0]);
        assert(_root.商城购物车[0] == "新车", "loadAll_overlays_shop: 商城购物车 from SO, got " + _root.商城购物车[0]);

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_json_overlays_sol_tasks():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        seedTestSO("2020-01-01 00:00:00", {
            tasks_to_do: [{id:"so_task"}],
            tasks_finished: {},
            task_chains_progress: {主线: 10}
        });
        _root.savePath = TEST_SLOT;
        _root.mydata = { lastSaved: "2020-01-01 00:00:00" };

        var md:Object = buildValidMydata();
        md.lastSaved = "2099-01-01 00:00:00";
        md.tasks.task_chains_progress = {主线: 5};
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });

        sm.loadAll();
        assert(_root.task_chains_progress.主线 == 10, "loadAll_overlays_tasks: task_chains_progress from SO, got " + _root.task_chains_progress.主线);

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_sol_empty_top_level_keeps_nested_tasks():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        var md:Object = buildValidMydata();
        md.lastSaved = "2026-02-02 12:00:00";
        md[0][0] = "Nested任务角色";
        md[3] = 12;
        md.tasks.tasks_to_do = [{id:"nested_task"}];
        md.tasks.tasks_finished = {};
        md.tasks.tasks_finished["500"] = 1;
        md.tasks.task_chains_progress = { 主线: 12, 挑战: 3 };
        so.data["test"] = md;
        so.data.tasks_to_do = [];
        so.data.tasks_finished = {};
        so.data.task_chains_progress = {};
        so.flush();
        _root.mydata = md;

        sm.loadAll();
        assert(_root.task_chains_progress.主线 == 12,
               "loadAll_sol_empty_top_level_keeps_nested_tasks: mainline from nested");
        assert(_root.task_chains_progress.挑战 == 3,
               "loadAll_sol_empty_top_level_keeps_nested_tasks: extra chains from nested");
        assert(_root.tasks_to_do[0].id == "nested_task",
               "loadAll_sol_empty_top_level_keeps_nested_tasks: tasks_to_do from nested");
        assert(_root.tasks_finished["500"] == 1,
               "loadAll_sol_empty_top_level_keeps_nested_tasks: tasks_finished from nested");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_sol_repairs_mainline_from_slot3():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        var md:Object = buildValidMydata();
        md.lastSaved = "2026-03-03 12:00:00";
        md[0][0] = "LegacyMainline角色";
        md[3] = 9;
        md.tasks.task_chains_progress = {};
        so.data["test"] = md;
        so.data.tasks_to_do = [];
        so.data.tasks_finished = {};
        so.data.task_chains_progress = {};
        so.flush();
        _root.mydata = md;

        sm.loadAll();
        assert(_root.task_chains_progress.主线 == 9,
               "loadAll_sol_repairs_mainline_from_slot3: repair from mydata[3]");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_json_overlays_sol_pets():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        seedTestSO("2020-01-01 00:00:00", {
            战宠: [["SO宠物"]],
            宠物领养限制: 8
        });
        _root.savePath = TEST_SLOT;
        _root.mydata = { lastSaved: "2020-01-01 00:00:00" };

        var md:Object = buildValidMydata();
        md.lastSaved = "2099-01-01 00:00:00";
        md.pets.宠物领养限制 = 3;
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });

        sm.loadAll();
        assert(_root.宠物领养限制 == 8, "loadAll_overlays_pets: 宠物领养限制 from SO, got " + _root.宠物领养限制);

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_sol_empty_top_level_keeps_nested_pets():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        var md:Object = buildValidMydata();
        md.lastSaved = "2026-03-04 12:00:00";
        md[0][0] = "Nested宠物角色";
        md.pets.宠物信息 = [["petA"], [], [], [], []];
        md.pets.宠物领养限制 = 9;
        so.data["test"] = md;
        so.data.战宠 = [[], [], [], [], []];
        so.data.宠物领养限制 = 5;
        so.flush();
        _root.mydata = md;

        sm.loadAll();
        assert(_root.宠物信息[0][0] == "petA",
               "loadAll_sol_empty_top_level_keeps_nested_pets: pets from nested");
        assert(_root.宠物领养限制 == 9,
               "loadAll_sol_empty_top_level_keeps_nested_pets: adopt limit from nested");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_sol_empty_top_level_keeps_nested_shop():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        var md:Object = buildValidMydata();
        md.lastSaved = "2026-03-05 12:00:00";
        md[0][0] = "Nested商城角色";
        md.shop.商城已购买物品 = ["nested_item"];
        md.shop.商城购物车 = ["nested_cart"];
        so.data["test"] = md;
        so.data.商城已购买物品 = [];
        so.data.商城购物车 = [];
        so.flush();
        _root.mydata = md;

        sm.loadAll();
        assert(_root.商城已购买物品[0] == "nested_item",
               "loadAll_sol_empty_top_level_keeps_nested_shop: purchased from nested");
        assert(_root.商城购物车[0] == "nested_cart",
               "loadAll_sol_empty_top_level_keeps_nested_shop: cart from nested");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_rejects_stale_json():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        // SOL has newer timestamp
        seedTestSO("2026-04-10 12:00:00", undefined);
        _root.savePath = TEST_SLOT;
        _root.mydata = { lastSaved: "2026-04-10 12:00:00" };

        // JSON is older
        var md:Object = buildValidMydata();
        md.lastSaved = "2020-01-01 00:00:00";
        md[0][0] = "StaleJSON角色";
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });

        sm.loadAll();
        // Should have rejected JSON and used SOL
        assert(_root.角色名 != "StaleJSON角色", "loadAll_rejects_stale: 角色名 not from stale JSON");
        assert(_root.角色名 == "SOL角色", "loadAll_rejects_stale: 角色名 from SOL, got " + _root.角色名);

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_clearPrefetch_blocks_late_callback():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        seedTestSO("2026-04-10 12:00:00", undefined);
        _root.savePath = TEST_SLOT;
        _root.mydata = { lastSaved: "2026-04-10 12:00:00" };

        // 注入 stale JSON（会被时间戳检查拒绝）
        var md:Object = buildValidMydata();
        md.lastSaved = "2020-01-01 00:00:00";
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });

        var gen0:Number = sm.getPrefetchStatus().gen;
        sm.loadAll();
        // loadAll 放弃 JSON 时应已调用 clearPrefetch → gen 递增
        assert(sm.getPrefetchStatus().gen > gen0, "clearPrefetch_blocks: gen incremented after rejection");
        assert(sm.getPrefetchStatus().hasPrefetch == false, "clearPrefetch_blocks: prefetch cleared");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_recovers_from_missing_sol():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        // 确保 SO 是空的（模拟本地存档被删）
        _root.savePath = TEST_SLOT;
        SharedObject.getLocal(TEST_SLOT).clear();
        _root.mydata = undefined;  // preload 在 SO 空时会设为 undefined

        // receiveSavePush 注入有效 JSON（模拟 Launcher 有备份）
        var md:Object = buildValidMydata();
        md.lastSaved = "2026-04-10 12:00:00";
        md[0][0] = "恢复角色";
        md.tasks.tasks_to_do = [{id:"recovered"}];
        var jsonStr:String = getTestJsonParser().stringify(md);
        sm.receiveSavePush({ data: jsonStr, slot: TEST_SLOT });

        var ok:Boolean = sm.loadAll();
        assert(ok == true, "recovers_from_missing_sol: returned true");
        assert(_root.角色名 == "恢复角色", "recovers_from_missing_sol: 角色名 from JSON, got " + _root.角色名);
        // SO 空 → 无顶层 key → fallback 到 mydata.tasks
        assert(_root.tasks_to_do[0].id == "recovered", "recovers_from_missing_sol: tasks from JSON fallback");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_sanitize_slot_match():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;

        // 模拟含特殊字符的 savePath
        var specialSlot:String = "test slot!@#";
        _root.savePath = specialSlot;
        SharedObject.getLocal(specialSlot).clear();
        _root.mydata = undefined;

        // receiveSavePush 返回规范化后的 slot（ArchiveTask 会把特殊字符→_）
        // 这模拟了 Launcher 返回 "test_slot___" 而 savePath 是 "test slot!@#"
        var md:Object = buildValidMydata();
        md.lastSaved = "2026-04-10 12:00:00";
        md[0][0] = "特殊槽位角色";
        var jsonStr:String = getTestJsonParser().stringify(md);
        // receiveSavePush 存的是 resp.slot（可能是规范化后的）
        sm.receiveSavePush({ data: jsonStr, slot: "test_slot___" });

        // loadAll 应该通过 sanitizeSlot 比较匹配
        var ok:Boolean = sm.loadAll();
        assert(ok == true, "sanitize_slot_match: returned true, got " + ok);
        assert(_root.角色名 == "特殊槽位角色", "sanitize_slot_match: 角色名 from JSON, got " + _root.角色名);

        SharedObject.getLocal(specialSlot).clear();
        _root.savePath = oldPath;
    }

    private static function test_loadAll_sol_migrates_drug_schema():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath:Object = _root.savePath;
        var oldAllow:Object = _root.允许存档;
        try {
            seedTestSO("2026-01-01 00:00:00", undefined);
            _root.savePath = TEST_SLOT;
            _root.允许存档 = true;
            var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
            so.data["test"].ext = {};
            var solDrugs:Object = {};
            solDrugs["0"] = {name:"普通hp药剂", value:1};
            solDrugs["4"] = {name:"SOL ghost", value:1};
            so.data["test"].inventory.药剂栏 = solDrugs;
            so.flush();

            sm._configureSaveFlowForTest({flushResult:true});
            var ok:Boolean = sm.loadAll();
            assert(ok && _root.mydata.ext.drugLoadout.version == 2
                    && _root.物品栏.药剂栏.getItem("0").name == "普通hp药剂"
                    && _root.物品栏.药剂栏.getItem("4") == null,
                "loadAll_sol_drug_schema: native SOL migration installs v2 and removes old ghost");
            assert(sm.hasPendingDrugLoadoutMigration(),
                "loadAll_sol_drug_schema: immediate SOL flush success cannot clear full-save pending");
            assert(sm.flushNow() && !sm.hasPendingDrugLoadoutMigration(),
                "loadAll_sol_drug_schema: subsequent successful full save clears pending");

            cleanTestSO();
            sm.clearPendingDrugLoadoutMigration();
            seedTestSO("2026-01-02 00:00:00", undefined);
            _root.savePath = TEST_SLOT;
            so = SharedObject.getLocal(TEST_SLOT);
            so.data["test"].ext = {};
            var failedFlushGhosts:Object = {};
            failedFlushGhosts["4"] = {name:"失败flush ghost", value:1};
            so.data["test"].inventory.药剂栏 = failedFlushGhosts;
            so.flush();
            sm._configureSaveFlowForTest({flushResult:false});
            assert(sm.loadAll() && sm.hasPendingDrugLoadoutMigration(),
                "loadAll_sol_drug_schema: immediate SOL flush failure also keeps pending");
            sm._configureSaveFlowForTest({flushResult:true});
            assert(sm.flushNow() && !sm.hasPendingDrugLoadoutMigration(),
                "loadAll_sol_drug_schema: retrying the full save is the only clear boundary");
        } finally {
            sm._configureSaveFlowForTest({
                saveInFlight:false,
                beforeLocalCommit:null,
                flushResult:undefined,
                resetDirty:true
            });
            sm.clearPendingDrugLoadoutMigration();
            cleanTestSO();
            _root.savePath = oldPath;
            _root.允许存档 = oldAllow;
        }
    }

    private static function test_deleteSlot_clears_prefetch():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        // 先注入预取数据
        var md:Object = buildValidMydata();
        md[0][0] = "即将删除";
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });
        assert(sm.getPrefetchStatus().hasPrefetch == true, "deleteSlot_clears: prefetch exists before delete");
        armBankTwoAndAllDrugCooldowns();
        assert(DrugInputService.getActiveBank() == 1 && allDrugCooldownsReady(false),
            "deleteSlot_clears: fixture starts in bank II with all five drug cooldowns active");

        // 删档
        sm.deleteSlot();

        // 验证预取被清理
        assert(sm.getPrefetchStatus().hasPrefetch == false, "deleteSlot_clears: prefetch cleared after delete");

        // 验证 hasSaveData 返回 false（SOL 空 + 预取已清）
        assert(sm.hasSaveData() == false, "deleteSlot_clears: hasSaveData false after delete");
        assert(DrugInputService.getActiveBank() == 0 && allDrugCooldownsReady(true),
            "deleteSlot_clears: successful delete resets active bank and all five drug cooldowns");

        ManualCooldownService.resetForTests();
        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_hasSaveData_with_prefetch():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        // SOL 空
        SharedObject.getLocal(TEST_SLOT).clear();
        _root.mydata = undefined;

        // 无预取时
        assert(sm.hasSaveData() == false, "hasSaveData_prefetch: false without prefetch");

        // 注入预取
        var md:Object = buildValidMydata();
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });

        // SOL 空 + 预取可用 → true
        assert(sm.hasSaveData() == true, "hasSaveData_prefetch: true with prefetch");

        cleanTestSO();
        sm.clearPrefetch();
        _root.savePath = oldPath;
    }

    private static function test_isRecoveryPending():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();

        // SOL 正常 → 不需要恢复
        _root.mydata = { version: "3.0" };
        assert(sm.isRecoveryPending() == false, "isRecoveryPending: false when SOL present");

        // SOL 缺失 + 预取已到 → 不再 pending
        _root.mydata = undefined;
        var md:Object = buildValidMydata();
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: "x" });
        assert(sm.isRecoveryPending() == false, "isRecoveryPending: false when prefetch arrived");

        sm.clearPrefetch();
    }

    private static function test_deleteSlot_tombstone_blocks_json_recovery():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        // 先 seed 一份有效 SO，然后删档
        seedTestSO("2026-01-01 00:00:00", undefined);
        sm.deleteSlot();

        // 注入 JSON 预取（模拟 Launcher 还有旧 shadow）
        var md:Object = buildValidMydata();
        md.lastSaved = "2099-01-01 00:00:00";
        md[0][0] = "复活角色";
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });
        assert(sm.getPrefetchStatus().hasPrefetch == true, "tombstone_blocks: prefetch injected");

        // loadAll 应该因为墓碑而拒绝 JSON 恢复
        _root.mydata = undefined;
        var ok:Boolean = sm.loadAll();
        assert(ok == false, "tombstone_blocks: loadAll returns false despite JSON available");
        assert(_root.角色名 != "复活角色", "tombstone_blocks: 角色名 not from revived JSON");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_hasSaveData_respects_tombstone():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        // 清 SO 并写墓碑
        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        so.clear();
        so.data._deleted = true;
        so.flush();

        // 注入预取
        var md:Object = buildValidMydata();
        sm.receiveSavePush({ data: getTestJsonParser().stringify(md), slot: TEST_SLOT });

        // 有预取但有墓碑 → false
        assert(sm.hasSaveData() == false, "hasSaveData_tombstone: false despite prefetch");

        cleanTestSO();
        sm.clearPrefetch();
        _root.savePath = oldPath;
    }

    private static function test_isRecoveryPending_false_after_delete():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        // 删档（设墓碑 + 清 prefetch）
        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        so.clear();
        so.data._deleted = true;
        so.flush();
        sm.clearPrefetch();
        _root.mydata = undefined;

        // 即使 SOL 缺失，墓碑存在 → 不应该 pending
        assert(sm.isRecoveryPending() == false, "isRecoveryPending_after_delete: false with tombstone");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    // Phase 1b（10a-2 红阶段）：preload 收到 launcher tombstoned 响应时自清 SOL 墓碑
    // 10a-1 stub 下 handlePreloadTombstoned 是空方法 → 断言 SOL _deleted 未设置 → FAIL
    private static function test_handlePreloadTombstoned_sets_sol_deleted():Void {
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        var oldPath = _root.savePath;
        _root.savePath = TEST_SLOT;

        // 前置：SOL 存在有效数据，无墓碑
        seedTestSO("2026-01-01 00:00:00", undefined);
        var so:SharedObject = SharedObject.getLocal(TEST_SLOT);
        delete so.data._deleted;
        so.flush();
        assert(so.data._deleted != true, "preload_tombstoned_setup: no tombstone before");

        // 调用 launcher 响应 handler
        sm.handlePreloadTombstoned(TEST_SLOT);

        // 预期：SOL 墓碑已设；10b 绿阶段满足；10a-1 stub 下此断言失败
        var soAfter:SharedObject = SharedObject.getLocal(TEST_SLOT);
        assert(soAfter.data._deleted == true, "preload_tombstoned: SOL _deleted set after handler");

        cleanTestSO();
        _root.savePath = oldPath;
    }

    private static function test_newCharacter_resets_drug_session_and_writes_v2_marker():Void {
        var oldPath:Object = _root.savePath;
        var oldSound:Object = _root.soundEffectManager;
        var oldTimer:Object = _root.帧计时器;
        var oldLoadStage:Object = _root.载入关卡数据;
        var oldFade:Object = _root.淡出动画;
        var oldUpper:Object = _root.上装装备;
        var oldLower:Object = _root.下装装备;
        var oldFeet:Object = _root.脚部装备;
        var oldDifficulty:Object = _root.难度;
        var oldBattleMap:Object = _root.当前为战斗地图;
        var oldCalibration:Object = _root.斗兽标定模式;
        var oldCurrentStageName:Object = _root.当前关卡名;
        var oldCurrentStageDifficulty:Object = _root.当前关卡难度;
        var oldBaseWorth:Object = _root.基础身价值;
        setUpForLoadTest();
        var sm:SaveManager = SaveManager.getInstance();
        try {
            _root.savePath = TEST_SLOT;
            _root.基础身价值 = 1000;
            var fixtureLoaded:Boolean = sm.loadFromMydata(buildValidMydata(), "new_character_fixture");
            var bgmStops:Number = 0;
            _root.soundEffectManager = {
                getGlobalVolume:function():Number { return 100; },
                getBGMVolume:function():Number { return 100; },
                getJukeboxOverride:function():Boolean { return false; },
                getTrueRandom:function():Boolean { return false; },
                getPlayMode:function():String { return "loop"; },
                stopBGMForTransition:function():Void { bgmStops++; }
            };
            var scheduledSceneReady:Number = 0;
            _root.帧计时器 = {
                性能等级上限:1,
                添加单次任务:function(callback:Function, delay:Number):Void {
                    scheduledSceneReady++;
                }
            };
            var capturedLoaded:Function;
            var capturedError:Function;
            var capturedToken:String = "";
            _root.载入关卡数据 = function(stageName:String, path:String,
                    onLoaded:Function, onError:Function, stageStartToken:String):Void {
                capturedLoaded = onLoaded;
                capturedError = onError;
                capturedToken = String(stageStartToken || "");
            };
            _root.淡出动画 = {
                fadeCount:0,
                淡出跳转帧:function(frameName:String):Void { this.fadeCount++; }
            };
            _root.上装装备 = "";
            _root.下装装备 = "";
            _root.脚部装备 = "";
            _root.难度 = "";
            StageRunSession.testOnlyReset();
            _root.当前为战斗地图 = false;
            _root.斗兽标定模式 = false;

            armBankTwoAndAllDrugCooldowns();
            assert(fixtureLoaded && DrugInputService.getActiveBank() == 1
                    && allDrugCooldownsReady(false),
                "newCharacter_drug_session: fixture starts in bank II with all five cooldowns active");

            // 转场依赖缺失必须在任何新角色写入/reservation 之前 fail closed。
            var validTimer:Object = _root.帧计时器;
            var preflightExt:Object = {sentinel:"preflight_ext"};
            var preflightMydata:Object = _root.mydata;
            var preflightMoney:Number = Number(_root.金钱);
            _root._saveExt = preflightExt;
            _root.金钱 = 314159;
            _root.帧计时器 = undefined;
            var ok:Boolean = sm.newCharacter();
            _root.帧计时器 = validTimer;
            assert(!ok && _root._saveExt === preflightExt
                    && _root.mydata === preflightMydata && _root.金钱 == 314159
                    && DrugInputService.getActiveBank() == 1
                    && allDrugCooldownsReady(false)
                    && StageRunSession.canStartStage(),
                "newCharacter_preflight: missing dependency preserves sentinels/session and creates no reservation");
            _root.金钱 = preflightMoney;

            // reservation 已拿到后的同步初始化异常必须 exact release，且不启动 XML。
            var obtainIndex:ItemObtainIndex = ItemObtainIndex.getInstance();
            var savedExportToSave:Function = obtainIndex.exportToSave;
            var initializationProbeCalls:Number = 0;
            obtainIndex.exportToSave = function():Object {
                initializationProbeCalls++;
                throw new Error("injected new-character initialization failure");
                return null;
            };
            capturedLoaded = undefined;
            capturedError = undefined;
            capturedToken = "";
            try {
                ok = sm.newCharacter();
            } finally {
                obtainIndex.exportToSave = savedExportToSave;
            }
            assert(!ok && initializationProbeCalls == 1
                    && capturedLoaded == undefined && capturedError == undefined
                    && capturedToken == "" && StageRunSession.canStartStage(),
                "newCharacter_initialization: synchronous exception exact-releases reservation before XML start");

            // 同步异常允许留下已发生的初始化写入；重载 fixture 隔离后续成功路径。
            fixtureLoaded = sm.loadFromMydata(buildValidMydata(), "new_character_after_sync_failure");
            StageRunSession.testOnlyReset();
            _root.当前为战斗地图 = false;
            _root.斗兽标定模式 = false;
            armBankTwoAndAllDrugCooldowns();
            assert(fixtureLoaded && DrugInputService.getActiveBank() == 1
                    && allDrugCooldownsReady(false),
                "newCharacter_initialization: fixture restored after injected synchronous failure");

            // 模拟 Web 在 frame 81 直接重建：所有旧角色领域都被污染，且 SOL
            // 仍保留一个可观察引用。prepare 必须只清内存，不得 clear/flush SO。
            var retainedSol:Object = {sentinel:"old_sol_must_survive_prepare"};
            var soData:Object = sm.getSOData();
            soData["test"] = retainedSol;
            soData.memoryResetSentinel = "keep";
            _root.主角技能表 = [["旧技能", 9, true, "", true]];
            _root.主角被动技能 = {旧被动:{等级:9}};
            _root.快捷技能栏1 = "旧技能";
            _root.快捷技能栏12 = "旧技能";
            _root.快捷物品栏4 = "旧药剂";
            _root.玩家称号 = "旧称号";
            _root.物品栏 = {polluted:true};
            _root.收集品栏 = {polluted:true};
            _root.同伴数据 = [["旧同伴"]];
            _root.同伴数 = 1;
            _root.佣兵是否出战信息 = [1, 1, 1, 1, 1];
            _root.killStats = {total:99, byType:{旧敌人:99}};
            _root.宠物信息 = [["旧宠物"]];
            _root.宠物领养限制 = 99;
            _root.tasks_to_do = [{id:"旧任务"}];
            _root.tasks_finished = {旧任务:true};
            _root.task_chains_progress = {主线:77};
            _root.主线任务进度 = 77;
            _root.基建系统.infrastructure = {旧设施:9};
            _root.商城已购买物品 = ["旧购买"];
            _root.商城购物车 = ["旧购物车"];
            _root.easterEgg = "旧彩蛋";
            _root._saveExt = {oldDomain:true, drugLoadout:{version:1, activeBank:1}};
            _root.金钱 = 99999;
            _root.等级 = 88;
            _root.经验值 = 77777;
            _root.技能点数 = 66;
            _root.difficultyMode = 2;
            _root.虚拟币 = 98765;
            _root.全局健身HP加成 = 10;
            _root.全局健身MP加成 = 20;
            _root.全局健身空攻加成 = 30;
            _root.全局健身内力加成 = 40;
            _root.全局健身防御加成 = 50;
            _root.playerData = ["旧玩家缓存"];
            _root.lastsave = "旧缓存";
            _root.lastsave2 = ["旧缓存"];
            _root._saveRuntimeLoaded = true;
            _root._saveRuntimeLoadedAttemptId = "old-attempt";
            _root.存盘标志 = 1;
            _root.存档系统.dirtyMark = true;
            sm.markDirty();
            obtainIndex.loadFromSave({
                discoveredStages:["旧关卡"],
                discoveredEnemies:["旧敌人"],
                discoveredQuests:["旧任务"]
            });
            var prepared:Object = sm.prepareNewCharacter({
                characterName:"Web新角色",
                genderText:"女",
                height:165,
                faceIdentifier:"测试女脸",
                hairIdentifier:"测试女发",
                upperIdentifier:"测试初始上装",
                lowerIdentifier:"测试初始下装",
                footwearIdentifier:"测试初始鞋",
                difficultyText:"平衡模式（困难）"
            }, "new_character_web_test");
            var liveEquipment:Object = _root.物品栏.装备栏.toObject();
            var packed:Object = _root.mydata;
            var packedSources:Object = packed.others.物品来源缓存;
            assert(prepared.success && soData["test"] === retainedSol
                    && soData.memoryResetSentinel == "keep"
                    && soData._deleted != true && capturedLoaded == undefined,
                "prepareNewCharacter_memory_reset: keeps SOL untouched and starts no XML");
            assert(ownKeyCount(liveEquipment) == 3
                    && liveEquipment.上装装备.name == "测试初始上装"
                    && liveEquipment.下装装备.name == "测试初始下装"
                    && liveEquipment.脚部装备.name == "测试初始鞋"
                    && ownKeyCount(_root.物品栏.背包.toObject()) == 0
                    && ownKeyCount(_root.物品栏.药剂栏.toObject()) == 0
                    && ownKeyCount(_root.物品栏.仓库.toObject()) == 0
                    && ownKeyCount(_root.物品栏.战备箱.toObject()) == 0
                    && ownKeyCount(_root.收集品栏.材料.toObject()) == 0
                    && ownKeyCount(_root.收集品栏.情报.toObject()) == 0,
                "prepareNewCharacter_memory_reset: replaces every container and keeps only initial equipment");
            assert(_root.主角技能表.length == 80
                    && _root.主角技能表[0][0] == ""
                    && ownKeyCount(_root.主角被动技能) == 0
                    && _root.快捷技能栏1 == "" && _root.快捷技能栏12 == ""
                    && _root.快捷物品栏4 == "" && _root.玩家称号 == ""
                    && _root.同伴数据.length == 0 && _root.同伴数 == 0
                    && _root.佣兵是否出战信息.join(",") == "0,0,0,0,0",
                "prepareNewCharacter_memory_reset: clears skill, quick-slot and companion domains");
            assert(_root.tasks_to_do.length == 0
                    && ownKeyCount(_root.tasks_finished) == 0
                    && ownKeyCount(_root.task_chains_progress) == 0
                    && _root.主线任务进度 == 0
                    && _root.宠物信息.length == 5 && _root.宠物信息[0].length == 0
                    && _root.宠物领养限制 == 5
                    && _root.商城已购买物品.length == 0
                    && _root.商城购物车.length == 0
                    && ownKeyCount(_root.基建系统.infrastructure) == 0
                    && _root.killStats.total == 0
                    && _root.easterEgg == undefined
                    && _root._saveExt.oldDomain == undefined,
                "prepareNewCharacter_memory_reset: clears task, pet, shop, infrastructure, kill and ext domains");
            assert(_root.虚拟币 == 0
                    && _root.金钱 == 0 && _root.等级 == 1
                    && _root.经验值 == 0 && _root.技能点数 == 0
                    && _root.difficultyMode == 0 && _root.允许存档 === true
                    && _root.全局健身HP加成 == 0
                    && _root.全局健身MP加成 == 0
                    && _root.全局健身空攻加成 == 0
                    && _root.全局健身内力加成 == 0
                    && _root.全局健身防御加成 == 0
                    && _root.playerData[0] == undefined
                    && _root.lastsave == "" && _root.lastsave2.length == 0
                    && _root._saveRuntimeLoaded === false
                    && _root._saveRuntimeLoadedAttemptId == undefined
                    && _root.存盘标志 == 0 && !_root.存档系统.dirtyMark,
                "prepareNewCharacter_memory_reset: clears value, cache and dirty runtime state");
            assert(packed[0][0] == "Web新角色"
                    && packed[0][1] == "女" && packed[0][2] == 0
                    && packed[0][3] == 1 && packed[0][4] == 0
                    && packed[0][5] == 165 && packed[0][6] == 0
                    && packed[0][7] == ""
                    && packed[0][8] == _root.基础身价值
                    && packed[0][9] == 0 && packed[0][11] == 0
                    && packed[0][12].join(",") == "0,0,0,0,0"
                    && packed[1][0] == "测试女脸"
                    && packed[1][1] == "测试女发"
                    && packed[1][16] == "" && packed[1][27] == ""
                    && packed[1][28] == ""
                    && ownKeyCount(packed.inventory.装备栏) == 3
                    && packed.tasks.tasks_to_do.length == 0
                    && packed.pets.宠物信息.length == 5
                    && packed.shop.商城购物车.length == 0
                    && packed.ext.oldDomain == undefined
                    && packedSources.discoveredStages.length == 0
                    && packedSources.discoveredEnemies.length == 0
                    && packedSources.discoveredQuests.length == 0,
                "prepareNewCharacter_memory_reset: packs only the clean post-reset authority snapshot");

            ok = prepared.success && sm.startNewCharacterTutorial(
                String(prepared.startToken), true, null, null);
            assert(ok && DrugInputService.getActiveBank() == 0 && allDrugCooldownsReady(true),
                "newCharacter_drug_session: successful new-character boundary resets bank and five cooldowns");
            assert(_root._saveExt.drugLoadout.version == 2
                    && _root._saveExt.drugLoadout.activeBank == undefined
                    && _root.mydata.ext.drugLoadout.version == 2
                    && _root.mydata.ext.drugLoadout.activeBank == undefined,
                "newCharacter_drug_session: live ext and packed snapshot carry v2 without session bank");
            assert(ok && capturedToken != ""
                    && StageRunSession.isStageStartReservationValid(capturedToken),
                "newCharacter_stage_entry: tutorial load owns an exact reservation");
            assert(_root.淡出动画.fadeCount == 0 && scheduledSceneReady == 0
                    && bgmStops == 0,
                "newCharacter_stage_entry: no fade, SceneReady, or BGM transition before XML success");

            // 真实第一次请求仍持有 reservation 时立即再调一次，模拟双击。
            // 对象引用/sentinel、装备 add 与 pack 读取计数必须全部为零变化。
            var pendingExt:Object = _root._saveExt;
            var pendingMydata:Object = _root.mydata;
            var pendingMoney:Number = 271828;
            var equipmentContainer:Object = _root.物品栏.装备栏;
            var backpackContainer:Object = _root.物品栏.背包;
            var equipmentBefore:String = getTestJsonParser().stringify(
                equipmentContainer.toObject());
            var originalEquipmentAdd:Function = equipmentContainer.add;
            var originalBackpackToObject:Function = backpackContainer.toObject;
            var blockedItemWrites:Number = 0;
            var blockedPackReads:Number = 0;
            var secondCallThrew:Boolean = false;
            var secondOk:Boolean = true;
            _root.金钱 = pendingMoney;
            _root.上装装备 = "__reservation_item_probe__";
            equipmentContainer.add = function():Object {
                blockedItemWrites++;
                return originalEquipmentAdd.apply(equipmentContainer, arguments);
            };
            backpackContainer.toObject = function():Object {
                blockedPackReads++;
                return originalBackpackToObject.apply(backpackContainer, arguments);
            };
            try {
                secondOk = sm.newCharacter();
            } catch (secondCallError) {
                secondCallThrew = true;
            } finally {
                equipmentContainer.add = originalEquipmentAdd;
                backpackContainer.toObject = originalBackpackToObject;
            }
            var equipmentAfter:String = getTestJsonParser().stringify(
                equipmentContainer.toObject());
            assert(!secondCallThrew && !secondOk
                    && _root._saveExt === pendingExt && _root.mydata === pendingMydata
                    && _root.金钱 == pendingMoney
                    && blockedItemWrites == 0 && blockedPackReads == 0
                    && equipmentAfter == equipmentBefore
                    && StageRunSession.isStageStartReservationValid(capturedToken),
                "newCharacter_double_click: second call preserves sentinels/items and performs zero pack reads");
            _root.金钱 = 0;
            _root.上装装备 = "";
            _root.下装装备 = "";
            _root.脚部装备 = "";
            _root.难度 = "";

            capturedLoaded({});
            assert(_root.淡出动画.fadeCount == 1 && scheduledSceneReady == 1
                    && bgmStops == 1 && _root.当前关卡名 == "教学关卡",
                "newCharacter_stage_entry: XML success commits globals and one transition");
            capturedLoaded({});
            capturedError();
            assert(_root.淡出动画.fadeCount == 1 && scheduledSceneReady == 1,
                "newCharacter_stage_entry: duplicate callbacks cannot repeat transition");
            StageRunSession.cancelStageStart(capturedToken);

            StageRunSession.testOnlyReset();
            _root.当前为战斗地图 = false;
            _root.斗兽标定模式 = false;
            _root.淡出动画.fadeCount = 0;
            scheduledSceneReady = 0;
            bgmStops = 0;
            capturedLoaded = undefined;
            capturedError = undefined;
            ok = sm.newCharacter();
            var deferredFailureExt:Object = _root._saveExt;
            var deferredFailureMydata:Object = _root.mydata;
            capturedError();
            capturedError();
            capturedLoaded({});
            assert(ok && _root.淡出动画.fadeCount == 0
                    && scheduledSceneReady == 0 && bgmStops == 0
                    && _root._saveExt === deferredFailureExt
                    && _root.mydata === deferredFailureMydata,
                "newCharacter_stage_entry: deferred XML error preserves initialization and blocks late transition");
            assert(StageRunSession.canStartStage(),
                "newCharacter_stage_entry: deferred error exact-cancels tutorial reservation");

            StageRunSession.testOnlyReset();
            _root.当前为战斗地图 = false;
            _root.斗兽标定模式 = false;
            scheduledSceneReady = 0;
            bgmStops = 0;
            capturedLoaded = undefined;
            capturedError = undefined;
            _root.淡出动画 = {
                fadeCount:0,
                淡出跳转帧:function(frameName:String):Void {
                    this.fadeCount++;
                    throw new Error("injected tutorial fade failure");
                }
            };
            ok = sm.newCharacter();
            capturedLoaded({});
            assert(ok && _root.淡出动画.fadeCount == 1
                    && scheduledSceneReady == 0 && bgmStops == 1,
                "newCharacter_stage_entry: fade failure schedules no stale SceneReady task");
            assert(StageRunSession.canStartStage(),
                "newCharacter_stage_entry: fade failure exact-cancels tutorial reservation");
        } finally {
            StageRunSession.testOnlyReset();
            DrugInputService.resetSession();
            ManualCooldownService.resetForTests();
            cleanTestSO();
            _root.savePath = oldPath;
            _root.soundEffectManager = oldSound;
            _root.帧计时器 = oldTimer;
            _root.载入关卡数据 = oldLoadStage;
            _root.淡出动画 = oldFade;
            _root.上装装备 = oldUpper;
            _root.下装装备 = oldLower;
            _root.脚部装备 = oldFeet;
            _root.难度 = oldDifficulty;
            _root.当前为战斗地图 = oldBattleMap;
            _root.斗兽标定模式 = oldCalibration;
            _root.当前关卡名 = oldCurrentStageName;
            _root.当前关卡难度 = oldCurrentStageDifficulty;
            _root.基础身价值 = oldBaseWorth;
        }
    }
}
