import org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ProgressValidator;
import org.flashNight.arki.unit.Action.PickUp.PickUpManager;

/**
 * 地图元件任务门控与一次性拾取标记测试。
 */
class org.flashNight.arki.unit.UnitComponent.Initializer.test.ProgressValidatorTest {

    public static function runAllTests():Void {
        trace("=== ProgressValidator Test Suite ===");
        testMainProgressCompatibility();
        testTaskChainAndActiveTaskGate();
        testOneTimePickupClaim();
        trace("ProgressValidatorTest: 所有测试完成");
    }

    private static function testMainProgressCompatibility():Void {
        var oldProgress = _root.主线任务进度;
        var config:Object = {最小主线进度: 5, 最大主线进度: 5};

        _root.主线任务进度 = 5;
        var exact:Boolean = ProgressValidator.meetsRequirements(config);
        _root.主线任务进度 = 6;
        var above:Boolean = ProgressValidator.meetsRequirements(config);
        var unrestricted:Boolean = ProgressValidator.meetsRequirements({});
        _root.主线任务进度 = oldProgress;

        assertTrue(exact, "主线进度位于闭区间时应通过");
        assertTrue(!above, "主线进度超过上限时应拒绝");
        assertTrue(unrestricted, "无门控字段时应保持兼容并通过");
    }

    private static function testTaskChainAndActiveTaskGate():Void {
        var oldChains = _root.task_chains_progress;
        var oldTasks = _root.tasks_to_do;
        var config:Object = {
            任务链名称: "铁枪会",
            最小任务链进度: 1,
            最大任务链进度: 1,
            要求进行中任务ID: 70002
        };

        _root.task_chains_progress = {};
        _root.task_chains_progress["铁枪会"] = 1;
        _root.tasks_to_do = [{id: 70002}];
        var firstRun:Boolean = ProgressValidator.meetsRequirements(config);

        _root.task_chains_progress["铁枪会"] = 2;
        var replay:Boolean = ProgressValidator.meetsRequirements(config);

        _root.task_chains_progress["铁枪会"] = 1;
        _root.tasks_to_do = [];
        var inactive:Boolean = ProgressValidator.meetsRequirements(config);

        var invalidConfig:Object = {最小任务链进度: 1};
        var missingChainName:Boolean = ProgressValidator.meetsRequirements(invalidConfig);

        _root.task_chains_progress = oldChains;
        _root.tasks_to_do = oldTasks;

        assertTrue(firstRun, "任务链进度为1且70002进行中时应通过");
        assertTrue(!replay, "任务链进度推进到2后应拒绝复盘掉落");
        assertTrue(!inactive, "70002未处于进行中时应拒绝");
        assertTrue(!missingChainName, "配置任务链区间但缺少链名时应失败关闭");
    }

    private static function testOneTimePickupClaim():Void {
        var oldExt = _root._saveExt;
        var oldSaveSystem = _root.存档系统;
        _root._saveExt = {};
        _root.存档系统 = {dirtyMark: false};

        var claimId:String = "test_unique_pickup";
        var before:Boolean = PickUpManager.isOneTimeClaimed(claimId);
        PickUpManager.claimOneTimePickup(claimId);
        var after:Boolean = PickUpManager.isOneTimeClaimed(claimId);
        var markedDirty:Boolean = _root.存档系统.dirtyMark == true;

        _root.存档系统.dirtyMark = false;
        PickUpManager.claimOneTimePickup(claimId);
        var duplicateWrite:Boolean = _root.存档系统.dirtyMark == true;

        _root._saveExt = oldExt;
        _root.存档系统 = oldSaveSystem;

        assertTrue(!before, "未领取的一次性掉落不应命中标记");
        assertTrue(after, "登记后应能查询到一次性领取标记");
        assertTrue(markedDirty, "首次登记应标记存档为脏");
        assertTrue(!duplicateWrite, "重复登记不应反复标脏存档");
    }

    private static function assertTrue(value:Boolean, message:String):Void {
        if (!value) throw new Error("ProgressValidatorTest: " + message);
    }
}

