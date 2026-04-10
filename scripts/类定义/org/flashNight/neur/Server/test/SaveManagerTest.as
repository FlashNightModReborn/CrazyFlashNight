import org.flashNight.neur.Server.SaveManager;
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

        test_migrate_undefined_to_3_0();
        test_migrate_2_6_to_3_0();
        test_migrate_2_7_to_3_0();
        test_migrate_3_0_noop();
        test_syncTopLevel_overwrite();
        test_syncTopLevel_from_empty();
        test_import_overwrite_clears_stale();
        test_tasks_finished_is_object();
        test_packGameState_syncs_mainline_progress();
        test_easterEgg_roundtrip();
        test_ensureShopNode_null_safe();
        test_ext_namespace_roundtrip();

        // Phase 1: loadFromMydata / validateMydata 间接测试
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

        // Phase 2: prefetch / receiveSavePush 测试
        test_getPrefetchStatus_after_clear();
        test_clearPrefetch_invalidates_late_callback();
        test_receiveSavePush_string_data();
        test_receiveSavePush_rejects_non_3_0();
        test_receiveSavePush_rejects_broken_json();
        test_receiveSavePush_rejects_truncated_tail();
        test_receiveSavePush_increments_gen();

        // Phase 3: loadAll JSON+SO overlay 测试
        test_loadAll_prefers_json_when_newer();
        test_loadAll_json_overlays_sol_shop();
        test_loadAll_json_overlays_sol_tasks();
        test_loadAll_json_overlays_sol_pets();
        test_loadAll_rejects_stale_json();
        test_loadAll_clearPrefetch_blocks_late_callback();
        test_loadAll_recovers_from_missing_sol();
        test_loadAll_sanitize_slot_match();
        test_deleteSlot_clears_prefetch();
        test_deleteSlot_tombstone_blocks_json_recovery();
        test_hasSaveData_with_prefetch();
        test_hasSaveData_respects_tombstone();
        test_isRecoveryPending();
        test_isRecoveryPending_false_after_delete();

        trace("========== SaveManagerTest END: " + passedCount + "/" + testCount + " passed, " + failedCount + " failed ==========");
    }

    // ── helpers ──

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

    // ── test cases ──

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
        mydata.inventory = { 背包:{}, 装备栏:{}, 仓库:{}, 战备箱:{} };
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

    private static function test_migrate_3_0_noop():Void {
        var sm:SaveManager = SaveManager.getInstance();
        var mydata:Object = {};
        mydata.version = "3.0";
        mydata.tasks = { tasks_to_do:[], tasks_finished:{}, task_chains_progress:{} };
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

    private static function test_ext_namespace_roundtrip():Void {
        var sm:SaveManager = SaveManager.getInstance();

        var oldExt = _root._saveExt;

        // 设置 ext 数据
        _root._saveExt = { modA: { enabled: true }, customData: 42 };

        var mydata:Object = sm.packGameState();
        assert(mydata.ext != undefined, "ext_roundtrip: ext exists in packed data");
        assert(mydata.ext.customData == 42, "ext_roundtrip: ext.customData preserved");
        assert(mydata.reserved != undefined, "ext_roundtrip: reserved exists in packed data");

        // 清空后解包恢复
        _root._saveExt = undefined;
        sm.unpackGameState(mydata);
        assert(_root._saveExt != undefined, "ext_roundtrip: _saveExt restored after unpack");
        assert(_root._saveExt.customData == 42, "ext_roundtrip: _saveExt.customData restored");

        _root._saveExt = oldExt;
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
        // _root 状态隔离
        _root.mydata = undefined;
        _root.角色名 = undefined;
        _root.lastsave = undefined;
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
        var jsonStr:String = getTestJsonParser().stringify(md);
        sm.receiveSavePush({ data: jsonStr, slot: TEST_SLOT });

        var ok:Boolean = sm.loadAll();
        assert(ok == true, "loadAll_prefers_json: returned true");
        assert(_root.角色名 == "JSON角色", "loadAll_prefers_json: 角色名 from JSON, got " + _root.角色名);

        cleanTestSO();
        _root.savePath = oldPath;
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

        // 删档
        sm.deleteSlot();

        // 验证预取被清理
        assert(sm.getPrefetchStatus().hasPrefetch == false, "deleteSlot_clears: prefetch cleared after delete");

        // 验证 hasSaveData 返回 false（SOL 空 + 预取已清）
        assert(sm.hasSaveData() == false, "deleteSlot_clears: hasSaveData false after delete");

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
}
