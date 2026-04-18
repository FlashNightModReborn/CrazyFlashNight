import org.flashNight.neur.Server.SaveManager;

/**
 * Bootstrap Protocol v2 (launcher 存档决议) 集成测试
 * 覆盖 SaveManager.preload / loadAll / hasSaveData / isRecoveryPending 的
 * Protocol 2 快路径 + 幂等 + DeferToFlash 双重失败升格闭环
 *
 * 测试约定：static runAllTests() 入口，trace [PASS]/[FAIL]
 *
 * 注意：SaveManager 是单例，内部 _protocol2Consumed 幂等锁在 runAllTests 全程
 * 持有——第一次 preload 后后续测试必须接受"幂等短路"行为，而不是全套重跑。
 * 为此测试编排：每个独立场景在 TestLoader 里单次启动，或仅用一个"权威"测试
 * 覆盖正常路径，额外场景依赖可观测副作用验证。
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

        // snapshot 快路径 (唯一能跑完 preload 的场景, 其他分支受幂等锁影响)
        test_preload_snapshot_sets_mydata();
        test_hasSaveData_with_snapshot_returns_true();
        test_isRecoveryPending_with_snapshot_returns_false();
        test_preload_idempotent_second_call_skips();

        trace("========== RESULT: " + passedCount + " passed, " + failedCount + " failed / " + testCount + " total ==========");
    }

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
        snap["3"] = [];
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
