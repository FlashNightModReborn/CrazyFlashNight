import org.flashNight.arki.ui.GymPreviewProjection;

/** 健身房只读目录投影的 TestLoader 回归；仅改测试 root fixture，不访问玩家存档。 */
class org.flashNight.arki.ui.GymPreviewProjectionTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;
    private static var EQUIPMENT_SLOTS:Array = [
        "头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备",
        "长枪", "手枪", "手枪2", "刀", "手雷"
    ];

    public static function runAllTests():Void {
        passed = 0;
        failed = 0;
        var saved:Object = captureRootState();
        try {
            testProgressBoundaries();
            testLevelBoundaries();
            testSourceValuesAndKpointMapping();
            testPortraitUsesExactSlotsAndRootIdentity();
            testMalformedCatalogRestoresPriorReference();
            testUnsupportedStationHasNoCatalogEffect();
        } catch (error:Error) {
            failed++;
            trace("[FAIL] GymPreview: unexpected exception: " + error.message);
        } finally {
            restoreRootState(saved);
        }
        trace("GymPreviewProjectionTest Tests Passed: " + passed);
        trace("GymPreviewProjectionTest Tests Failed: " + failed);
    }

    private static function testProgressBoundaries():Void {
        assertPreview("dummy", 0, 34, "0,1,2,3,7,8,9", "dummy progress 0");
        assertPreview("dummy", 67, 34, "0,1,2,3,7,8,9", "dummy before progress 68");
        assertPreview("dummy", 68, 34, "0,1,2,3,4,5,7,8,9", "dummy at progress 68");
        assertPreview("dummy", 119, 34, "0,1,2,3,4,5,7,8,9", "dummy before progress 120");
        assertPreview("dummy", 120, 34, "0,1,2,3,4,5,6,7,8,9", "dummy at progress 120");

        assertPreview("dumbbell", 0, 34, "0,1,2,7,8,9", "dumbbell progress 0");
        assertPreview("dumbbell", 67, 34, "0,1,2,7,8,9", "dumbbell before progress 68");
        assertPreview("dumbbell", 68, 34, "0,1,2,3,4,5,7,8,9", "dumbbell at progress 68");
        assertPreview("dumbbell", 119, 34, "0,1,2,3,4,5,7,8,9", "dumbbell before progress 120");
        assertPreview("dumbbell", 120, 34, "0,1,2,3,4,5,6,7,8,9", "dumbbell at progress 120");

        assertPreview("squat", 0, 34, "0,1,2,7,8,9", "squat progress 0");
        assertPreview("squat", 67, 34, "0,1,2,7,8,9", "squat before progress 68");
        assertPreview("squat", 68, 34, "0,1,2,3,4,7,8,9", "squat at progress 68");
        assertPreview("squat", 119, 34, "0,1,2,3,4,7,8,9", "squat before progress 120");
        assertPreview("squat", 120, 34, "0,1,2,3,4,5,6,7,8,9", "squat at progress 120");
    }

    private static function testLevelBoundaries():Void {
        assertPreview("dummy", 0, 35, "0,1,2,3,7,8,9,10,11", "dummy at level 35");
        assertPreview("dummy", 0, 49, "0,1,2,3,7,8,9,10,11", "dummy before level 50");
        assertPreview("dummy", 0, 50, "0,1,2,3,7,8,9,10,11,12", "dummy at level 50");

        assertPreview("dumbbell", 0, 35, "0,1,2,7,8,9,10,11", "dumbbell at level 35");
        assertPreview("dumbbell", 0, 49, "0,1,2,7,8,9,10,11", "dumbbell before level 50");
        assertPreview("dumbbell", 0, 50, "0,1,2,7,8,9,10,11,12", "dumbbell at level 50");

        assertPreview("squat", 0, 35, "0,1,2,7,8,9,10,11", "squat at level 35");
        assertPreview("squat", 0, 49, "0,1,2,7,8,9,10,11", "squat before level 50");
        assertPreview("squat", 0, 50, "0,1,2,7,8,9,10,11,12", "squat at level 50");
    }

    private static function assertPreview(stationId:String, progress:Number, level:Number,
            expectedIndices:String, label:String):Void {
        var previous:Array = prepareFixture(progress, level);
        var result:Object = GymPreviewProjection.buildPreview(stationId);
        check(result.error == undefined && result.v == 1 && result.stationId == stationId,
            label + ": preview succeeds for the selected station");
        if (result.error != undefined || result.projects == undefined) return;
        check(indexList(result.projects) == expectedIndices, label + ": projects match the source gates");
        for (var i:Number = 0; i < result.projects.length; i++) {
            var project:Object = result.projects[i];
            check(project.id == stationId + "." + project.index,
                label + ": project id preserves station and source index " + project.index);
        }
        check(_root.健身房训练类型 === previous,
            label + ": prior catalog reference is restored after a successful preview");
    }

    private static function testSourceValuesAndKpointMapping():Void {
        var previous:Array = prepareFixture(0, 34);
        var dummy:Object = GymPreviewProjection.buildPreview("dummy");
        var dummyGold:Object = projectAt(dummy, 0);
        var dummyKpoint:Object = projectAt(dummy, 1);
        check(dummyGold.rewardLabel == "空手攻击力" && dummyGold.rewardAmount == 3
                && dummyGold.currency == "money" && dummyGold.cost == 60000
                && dummyGold.durationMs == 10000 && dummyGold.current == 34 && dummyGold.cap == 500,
            "dummy row 0 projects source values without a copied price table");
        check(dummyKpoint.currency == "kpoint" && dummyKpoint.cost == 6000
                && dummy.balances.money == 1234567 && dummy.balances.kpoint == 7654321
                && dummyKpoint.balance == undefined,
            "K-point rows use virtual coin in the top-level balance snapshot");
        check(_root.健身房训练类型 === previous,
            "source values preview restores the prior catalog reference");

        prepareFixture(0, 34);
        var dumbbell:Object = GymPreviewProjection.buildPreview("dumbbell");
        var dumbbellFirst:Object = projectAt(dumbbell, 0);
        check(dumbbellFirst.rewardLabel == "HP上限" && dumbbellFirst.rewardAmount == 10
                && dumbbellFirst.cost == 50000 && dumbbellFirst.cap == 2000,
            "dumbbell opener uses the actual HP catalog");

        prepareFixture(0, 34);
        var squat:Object = GymPreviewProjection.buildPreview("squat");
        var squatFirst:Object = projectAt(squat, 0);
        check(squatFirst.rewardLabel == "MP上限" && squatFirst.rewardAmount == 10
                && squatFirst.cost == 50000 && squatFirst.cap == 2000,
            "squat opener uses the actual MP catalog");
    }

    private static function testPortraitUsesExactSlotsAndRootIdentity():Void {
        var previous:Array = prepareFixture(0, 34);
        var result:Object = GymPreviewProjection.buildPreview("dummy");
        var equipment:Object = result.portrait.equipment;
        var keyCount:Number = 0;
        for (var key:String in equipment) keyCount++;
        check(result.portrait.gender == "female" && result.portrait.hair == "根级测试发型"
                && result.portrait.face == "根级测试脸型",
            "portrait converts root gender and reads root hair and face");
        check(keyCount == 11, "portrait projects the exact eleven allowed equipment slots");
        for (var i:Number = 0; i < EQUIPMENT_SLOTS.length; i++) {
            check(equipment[EQUIPMENT_SLOTS[i]] == "测试装备" + i,
                "portrait maps equipment slot " + EQUIPMENT_SLOTS[i]);
        }
        check(_root.健身房训练类型 === previous,
            "portrait preview restores the prior catalog reference");

        var actor:Object = _root.gameworld[_root.控制目标];
        actor["上装装备"] = {name:""};
        actor["手枪"] = {name:7};
        result = GymPreviewProjection.buildPreview("dummy");
        equipment = result.portrait.equipment;
        keyCount = 0;
        for (var sparseKey:String in equipment) keyCount++;
        check(keyCount == 9 && equipment["上装装备"] == undefined
                && equipment["手枪"] == undefined,
            "portrait omits empty and non-string equipment names");
    }

    private static function testMalformedCatalogRestoresPriorReference():Void {
        var previous:Array = prepareFixture(0, 34);
        var originalGetter:Function = _root.获取木人桩训练项;
        var result:Object;
        try {
            _root.获取木人桩训练项 = function():Void {
                originalGetter();
                _root.健身房训练类型[0].消耗 = 0;
            };
            result = GymPreviewProjection.buildPreview("dummy");
        } finally {
            _root.获取木人桩训练项 = originalGetter;
        }
        check(result.error == "catalog_unavailable",
            "malformed source row rejects the whole preview");
        check(_root.健身房训练类型 === previous,
            "malformed preview restores the exact prior catalog reference");
    }

    private static function testUnsupportedStationHasNoCatalogEffect():Void {
        var previous:Array = prepareFixture(0, 34);
        var result:Object = GymPreviewProjection.buildPreview("barbell");
        check(result.error == "unsupported_station",
            "unsupported station id is rejected");
        check(_root.健身房训练类型 === previous,
            "unsupported station does not replace the current catalog reference");
    }

    private static function prepareFixture(progress:Number, level:Number):Array {
        var actor:Object = {
            性别:"男", 发型:"actor发型", 脸型:"actor脸型"
        };
        for (var i:Number = 0; i < EQUIPMENT_SLOTS.length; i++) {
            actor[EQUIPMENT_SLOTS[i]] = {name:"测试装备" + i};
        }
        _root.gameworld = {};
        _root.控制目标 = "gymPreviewActor";
        _root.gameworld[_root.控制目标] = actor;
        _root.主线任务进度 = progress;
        _root.等级 = level;
        _root.性别 = "女";
        _root.发型 = "根级测试发型";
        _root.脸型 = "根级测试脸型";
        _root.金钱 = 1234567;
        _root.虚拟币 = 7654321;
        _root.技能点数 = 67;
        _root.全局健身HP加成 = 12;
        _root.全局健身MP加成 = 23;
        _root.全局健身空攻加成 = 34;
        _root.全局健身防御加成 = 45;
        _root.全局健身内力加成 = 56;
        var previous:Array = [{marker:"prior-catalog"}];
        _root.健身房训练类型 = previous;
        return previous;
    }

    private static function indexList(projects:Array):String {
        var result:String = "";
        for (var i:Number = 0; i < projects.length; i++) {
            if (i > 0) result += ",";
            result += String(projects[i].index);
        }
        return result;
    }

    private static function projectAt(preview:Object, index:Number):Object {
        if (preview == undefined || preview.projects == undefined) return undefined;
        for (var i:Number = 0; i < preview.projects.length; i++) {
            if (preview.projects[i].index == index) return preview.projects[i];
        }
        return undefined;
    }

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++;
        else {
            failed++;
            trace("[FAIL] GymPreview: " + message);
        }
    }

    private static function captureRootState():Object {
        return {
            gameworld:_root.gameworld,
            target:_root.控制目标,
            progress:_root.主线任务进度,
            level:_root.等级,
            gender:_root.性别,
            hair:_root.发型,
            face:_root.脸型,
            money:_root.金钱,
            kpoint:_root.虚拟币,
            skillPoints:_root.技能点数,
            hp:_root.全局健身HP加成,
            mp:_root.全局健身MP加成,
            attack:_root.全局健身空攻加成,
            defense:_root.全局健身防御加成,
            inner:_root.全局健身内力加成,
            catalog:_root.健身房训练类型
        };
    }

    private static function restoreRootState(saved:Object):Void {
        _root.gameworld = saved.gameworld;
        _root.控制目标 = saved.target;
        _root.主线任务进度 = saved.progress;
        _root.等级 = saved.level;
        _root.性别 = saved.gender;
        _root.发型 = saved.hair;
        _root.脸型 = saved.face;
        _root.金钱 = saved.money;
        _root.虚拟币 = saved.kpoint;
        _root.技能点数 = saved.skillPoints;
        _root.全局健身HP加成 = saved.hp;
        _root.全局健身MP加成 = saved.mp;
        _root.全局健身空攻加成 = saved.attack;
        _root.全局健身防御加成 = saved.defense;
        _root.全局健身内力加成 = saved.inner;
        _root.健身房训练类型 = saved.catalog;
    }
}
