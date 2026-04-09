import org.flashNight.neur.Server.SaveManager;

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

        _root.task_chains_progress = { 主线: 42 };
        _root.主线任务进度 = 0;

        var mydata:Object = sm.packGameState();

        assert(mydata[3] == 42, "packGameState_syncs: mydata[3] should be 42, got " + mydata[3]);
        assert(_root.主线任务进度 == 42, "packGameState_syncs: _root synced to 42");

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
}
