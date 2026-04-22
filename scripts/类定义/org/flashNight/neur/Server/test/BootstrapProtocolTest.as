import org.flashNight.neur.Server.SaveManager;

/**
 * Bootstrap Protocol v2 (launcher 存档决议) 集成测试
 * 覆盖 SaveManager.preload / loadAll / hasSaveData / isRecoveryPending 的
 * Protocol 2 快路径 + 幂等 + DeferToFlash 双重失败升格闭环
 *
 * 测试约定：static runAllTests() 入口，trace [PASS]/[FAIL]
 *
 * 注意：SaveManager 是单例，_protocol2Consumed 幂等锁一旦拉起 preload 就短路。
 * 为让 snapshot / deleted / empty / corrupt / needs_migration 五条分支都跑完，
 * 每个场景前调用 SaveManager._resetProtocol2ForTest() 复位内部状态。产品代码
 * 绝不调用该后门 — 它是这个 test class 私有的一个契约。
 */
class org.flashNight.neur.Server.test.BootstrapProtocolTest {

    private static var testCount:Number = 0;
    private static var passedCount:Number = 0;
    private static var failedCount:Number = 0;
    private static var currentTest:String;

    public static function runAllTests():Void {
        trace("========== BootstrapProtocolTest START ==========");
        testCount = 0;
        passedCount = 0;
        failedCount = 0;

        // snapshot 快路径
        test_preload_snapshot_sets_mydata();
        test_hasSaveData_with_snapshot_returns_true();
        test_isRecoveryPending_with_snapshot_returns_false();
        test_preload_idempotent_second_call_skips();

        // 其他四条决议分支（复位幂等锁后独立测试）
        test_preload_empty_clears_mydata();
        test_preload_deleted_tombstones_SOL();
        test_preload_corrupt_sets_deferred_flag();
        test_preload_needs_migration_sets_deferred_flag();

        // DeferToFlash 双重失败升格：两条 source 都要独立跑一次，防止未来分流改动回归
        test_hasSaveData_deferred_double_failure_escalates_needs_migration();
        test_hasSaveData_deferred_double_failure_escalates_corrupt();

        trace("========== RESULT: " + passedCount + " passed, " + failedCount + " failed / " + testCount + " total ==========");
    }

    // ==================== snapshot 分支 ====================

    private static function test_preload_snapshot_sets_mydata():Void {
        beginTest("preload_snapshot_sets_mydata");
        prepareRoot();

        var snap:Object = buildValidSnapshot();
        _root._launcherSaveDecision = "snapshot";
        _root._launcherSnapshot = snap;
        _root._launcherSnapshotSource = "sol";

        var sm:SaveManager = SaveManager.getInstance();
        sm.preload();

        assert(_root.mydata == snap, "_root.mydata references snapshot");
        assert(_root._launcherSaveDecision == undefined, "_launcherSaveDecision deleted");
        assert(_root._launcherSnapshot == undefined, "_launcherSnapshot deleted");
        assert(_root._launcherSnapshotSource == undefined, "_launcherSnapshotSource deleted");
    }

    private static function test_hasSaveData_with_snapshot_returns_true():Void {
        beginTest("hasSaveData_with_snapshot_returns_true");
        // 上一个测试已把 snapshot 灌入; 此处期望 hasSaveData 仍返回 true
        assert(SaveManager.getInstance().hasSaveData() == true, "hasSaveData true with active snapshot");
    }

    private static function test_isRecoveryPending_with_snapshot_returns_false():Void {
        beginTest("isRecoveryPending_with_snapshot_returns_false");
        assert(SaveManager.getInstance().isRecoveryPending() == false, "isRecoveryPending false with snapshot");
    }

    private static function test_preload_idempotent_second_call_skips():Void {
        beginTest("preload_idempotent_second_call_skips");
        var firstMydata:Object = _root.mydata;
        // 再次注入"错误"决议; preload 应因幂等锁忽略
        _root._launcherSaveDecision = "empty";
        delete _root._launcherSnapshot;
        SaveManager.getInstance().preload();
        assert(_root.mydata == firstMydata, "mydata must not be overwritten on second preload");
        assert(_root._launcherSaveDecision == "empty", "second-call launcher field NOT consumed (idempotent skip)");
        // 清残留以免污染宿主
        delete _root._launcherSaveDecision;
    }

    // ==================== empty 分支 ====================

    private static function test_preload_empty_clears_mydata():Void {
        beginTest("preload_empty_clears_mydata");
        prepareRoot();
        SaveManager.getInstance()._resetProtocol2ForTest();

        _root._launcherSaveDecision = "empty";
        // 预置 mydata 非 undefined，期望 preload 清掉
        _root.mydata = { dirty: true };

        SaveManager.getInstance().preload();

        assert(_root.mydata == undefined, "empty decision must clear _root.mydata");
        assert(_root._launcherSaveDecision == undefined, "_launcherSaveDecision consumed");
        // empty 分支不应该触发 _saveRestoreError
        assert(_root._saveRestoreError != true, "empty decision must not set _saveRestoreError");
    }

    // ==================== deleted 分支 ====================

    private static function test_preload_deleted_tombstones_SOL():Void {
        beginTest("preload_deleted_tombstones_SOL");
        prepareRoot();
        SaveManager.getInstance()._resetProtocol2ForTest();

        // 预置 SOL 有内容，期望 deleted 决议把它清空并写 _deleted=true
        var so:SharedObject = SharedObject.getLocal(_root.savePath);
        so.data.test = { version: "3.0", foo: "bar" };
        so.flush();

        _root._launcherSaveDecision = "deleted";
        _root.mydata = { stale: true };

        SaveManager.getInstance().preload();

        var soPost:SharedObject = SharedObject.getLocal(_root.savePath);
        assert(soPost.data._deleted == true, "SOL._deleted must be true after deleted decision");
        assert(soPost.data.test == undefined, "SOL.test must be cleared by so.clear()");
        assert(_root.mydata == undefined, "deleted decision must clear _root.mydata");
    }

    // ==================== corrupt 分支 ====================

    private static function test_preload_corrupt_sets_deferred_flag():Void {
        beginTest("preload_corrupt_sets_deferred_flag");
        prepareRoot();
        SaveManager.getInstance()._resetProtocol2ForTest();

        _root._launcherSaveDecision = "corrupt";
        _root._launcherCorruptDetail = "v3.0_structure_invalid";

        SaveManager.getInstance().preload();

        // corrupt 是穿透分支：launcher 字段被消费，但 preload 继续走 SOL 读取。
        // 可观测副作用：_launcherCorruptDetail 被删除（字段已清理）。
        assert(_root._launcherSaveDecision == undefined, "_launcherSaveDecision consumed");
        assert(_root._launcherCorruptDetail == undefined, "_launcherCorruptDetail consumed");
        // _deferredResolutionAttempted 是私有字段，通过 hasSaveData 双重失败升格间接验证
        // (见 test_hasSaveData_deferred_double_failure_escalates)
    }

    // ==================== needs_migration 分支 ====================

    private static function test_preload_needs_migration_sets_deferred_flag():Void {
        beginTest("preload_needs_migration_sets_deferred_flag");
        prepareRoot();
        SaveManager.getInstance()._resetProtocol2ForTest();

        _root._launcherSaveDecision = "needs_migration";

        SaveManager.getInstance().preload();

        assert(_root._launcherSaveDecision == undefined, "_launcherSaveDecision consumed");
    }

    // ==================== DeferToFlash 双重失败升格 ====================
    // 两条 source (needs_migration / corrupt) 走 SaveManager.preload 里的不同分支
    // (见 SaveManager.as 第 ~230-260 行), 但都必须统一升格为 _saveRestoreError。
    // 单独覆盖可以在未来有人修改 corrupt 分支逻辑时立刻捕获回归。

    private static function test_hasSaveData_deferred_double_failure_escalates_needs_migration():Void {
        beginTest("hasSaveData_deferred_escalates_needs_migration");
        runDeferredDoubleFailureScenario("needs_migration");
    }

    private static function test_hasSaveData_deferred_double_failure_escalates_corrupt():Void {
        beginTest("hasSaveData_deferred_escalates_corrupt");
        runDeferredDoubleFailureScenario("corrupt");
    }

    private static function runDeferredDoubleFailureScenario(decision:String):Void {
        prepareRoot();
        SaveManager.getInstance()._resetProtocol2ForTest();

        // 确保 SOL 本地彻底无数据
        var so:SharedObject = SharedObject.getLocal(_root.savePath);
        so.clear();
        so.flush();

        _root._launcherSaveDecision = decision;
        if (decision == "corrupt") {
            _root._launcherCorruptDetail = "synthetic_test_detail";
        }
        SaveManager.getInstance().preload();

        // _deferredResolutionAttempted=true 且 SOL 空 → hasSaveData 升格为
        // _saveRestoreError=true，防止 UI 错误提示"重新游戏确认"。
        var hasSave:Boolean = SaveManager.getInstance().hasSaveData();
        assert(hasSave == false, "hasSaveData false when deferred(" + decision + ") + SOL empty");
        assert(_root._saveRestoreError == true, "_saveRestoreError escalated by double failure (" + decision + ")");
    }

    // ========== helpers ==========

    private static function prepareRoot():Void {
        delete _root._launcherSaveDecision;
        delete _root._launcherSnapshot;
        delete _root._launcherSnapshotSource;
        delete _root._launcherCorruptDetail;
        delete _root._saveRestoreError;
        _root.savePath = "crazyflasher7_saves_bootstrap_test";
        _root.mydata = undefined;
        var so:SharedObject = SharedObject.getLocal(_root.savePath);
        so.clear();
        so.flush();
    }

    private static function buildValidSnapshot():Object {
        var snap:Object = new Object();
        snap.version = "3.0";
        snap.lastSaved = "2026-04-18 00:00:00";
        snap["0"] = ["fs", "男", 1000, 99, 50000, 180, 10, "勇者", 5000, 0,
                     ["键", "键", 0], 0, [0,0,0,0,0], 0];
        var a1:Array = new Array();
        for (var i:Number = 0; i < 28; i++) a1.push(i);
        snap["1"] = a1;
        snap["3"] = 0;
        snap["4"] = [0, 0];
        snap["5"] = [];
        snap["7"] = [0, 0, 0, 0, 0];
        snap.inventory = { 背包: [], 装备栏: [], 药剂栏: [], 仓库: [], 战备箱: [] };
        snap.collection = { 材料: [], 情报: [] };
        snap.infrastructure = {};
        snap.tasks = { tasks_to_do: [], tasks_finished: {}, task_chains_progress: {} };
        snap.pets = { 宠物信息: [[],[],[],[],[]], 宠物领养限制: 5 };
        snap.shop = { 商城已购买物品: [], 商城购物车: [] };
        return snap;
    }

    private static function beginTest(name:String):Void {
        currentTest = name;
        testCount++;
    }

    private static function assert(condition:Boolean, message:String):Void {
        if (condition) {
            passedCount++;
            trace("[PASS] " + currentTest + ": " + message);
        } else {
            failedCount++;
            trace("[FAIL] " + currentTest + ": " + message);
        }
    }
}
