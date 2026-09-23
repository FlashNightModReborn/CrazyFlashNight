import org.flashNight.arki.ui.GymTrainingPanelService;

/** 健身付费边界的 TestLoader 回归；所有存档、货币播报均为内存替身。 */
class org.flashNight.arki.ui.GymTrainingPanelServiceTest {
    private static var passed:Number = 0;
    private static var failed:Number = 0;

    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var saved:Object = capture();
        try {
            testStartCancelAndClock();
            testAttributeAndDuplicate();
            testSkillAndCapExperience();
            testInsufficientAndGateChange();
            testNoWriteRefusalsAndLevelGrowth();
            testPendingSaveOnlyRetriesSave();
            testOtherStationsAndContext();
            testLiveAttributeProjection();
        } catch (error:Error) {
            failed++;
            trace("[FAIL] GymTraining: unexpected exception: " + error.message);
        } finally {
            restore(saved);
            GymTrainingPanelService._resetForTests();
        }
        trace("GymTrainingPanelServiceTest Tests Passed: " + passed);
        trace("GymTrainingPanelServiceTest Tests Failed: " + failed);
    }

    private static function setup():Void {
        GymTrainingPanelService._resetForTests();
        GymTrainingPanelService._setNowForTests(1000);
        _root.gameworld = {hero:{}};
        _root.控制目标 = "hero";
        _root.savePath = "gym-test-slot";
        _root.关卡地图帧值 = "gym-test-map";
        _root.允许存档 = true;
        _root.主线任务进度 = 120;
        _root.等级 = 50;
        _root.等级限制 = 100;
        _root.基础身价值 = 100;
        _root.身价 = 5000;
        _root.性别 = "男";
        _root.发型 = "测试发型";
        _root.脸型 = "测试脸型";
        _root.金钱 = 5000000;
        _root.虚拟币 = 1000000;
        _root.经验值 = 100;
        _root.技能点数 = 50;
        _root.全局健身HP加成 = 0;
        _root.全局健身MP加成 = 0;
        _root.全局健身空攻加成 = 0;
        _root.全局健身防御加成 = 0;
        _root.全局健身内力加成 = 0;
        _root.根据等级得升级所需经验 = function(level):Number { return 1000000000000; };
        _root.根据等级计算获得技能点 = function(level):Number { return 25; };
        _root.存档系统 = {
            dirtyMark:false,
            markDirty:function():Void { _root.__gymDirty++; this.dirtyMark = true; },
            flushDurableNow:function(reason):Boolean {
                _root.__gymFlush++;
                _root.__gymReason = reason;
                return _root.__gymSaveSucceeds;
            }
        };
        _root.记录玩家货币变化 = function(money, kpoint, context):Void {
            _root.__gymFeed++;
            _root.__gymMoneyDelta += Number(money);
            _root.__gymKpointDelta += Number(kpoint);
        };
        _root.__gymDirty = 0;
        _root.__gymFlush = 0;
        _root.__gymFeed = 0;
        _root.__gymMoneyDelta = 0;
        _root.__gymKpointDelta = 0;
        _root.__gymSaveSucceeds = true;
    }

    private static function open(stationId:String):Object {
        return GymTrainingPanelService.prepareOpen(stationId);
    }
    private static function start(preview:Object, projectId:String):Object {
        return GymTrainingPanelService.execute("start", {v:1,openToken:preview.openToken,
            stationId:preview.stationId,projectId:projectId});
    }
    private static function invoke(operation:String, token:String):Object {
        return GymTrainingPanelService.execute(operation, {v:1,sessionToken:token});
    }

    private static function testStartCancelAndClock():Void {
        setup();
        var preview:Object = open("dummy");
        check(preview.v == 2 && typeof preview.openToken == "string"
            && preview.projects[0].baseExperience == 10000,
            "open gives versioned token and source-based experience terms");
        var running:Object = start(preview, "dummy.0");
        check(running.success && running.phase == "running" && running.durationMs == 10000
            && running.award.kind == "stat" && running.award.amount == 3,
            "start returns a bounded zero-write session and expected reward");
        check(_root.__gymDirty == 0 && _root.__gymFlush == 0 && _root.__gymFeed == 0,
            "start has no business or save write");
        var early:Object = invoke("finish", running.sessionToken);
        check(!early.success && early.error == "not_ready" && early.phase == "running"
            && _root.金钱 == 5000000 && _root.经验值 == 100,
            "early finish cannot award or charge");
        var cancelled:Object = invoke("cancel", running.sessionToken);
        check(cancelled.success && cancelled.phase == "cancelled"
            && _root.__gymDirty == 0 && _root.__gymFeed == 0,
            "cancel preserves all business values");
        check(invoke("finish", running.sessionToken).phase == "cancelled"
            && _root.__gymFlush == 0, "cancelled token cannot later finish");
    }

    private static function testAttributeAndDuplicate():Void {
        setup();
        _root.全局健身空攻加成 = 498;
        var running:Object = start(open("dummy"), "dummy.0");
        GymTrainingPanelService._setNowForTests(11000);
        var done:Object = invoke("finish", running.sessionToken);
        check(done.success && done.saved && done.phase == "applied"
            && done.award.kind == "stat" && done.award.amount == 2
            && done.current == 500 && done.cap == 500,
            "partial final training reports actual applied amount");
        check(_root.金钱 == 4940000 && _root.全局健身空攻加成 == 500
            && _root.经验值 == 10100 && _root.__gymDirty == 1
            && _root.__gymFlush == 1 && _root.__gymFeed == 1
            && _root.__gymReason == "ui.gym_training_paid",
            "completion charges, awards, marks dirty and durably saves once");
        var duplicate:Object = invoke("finish", running.sessionToken);
        var queried:Object = invoke("query", running.sessionToken);
        check(duplicate.saved && queried.saved && duplicate.current == 500
            && _root.__gymDirty == 1 && _root.__gymFlush == 1
            && _root.__gymFeed == 1, "duplicate finish and query replay only the receipt");
    }

    private static function testSkillAndCapExperience():Void {
        setup();
        var running:Object = start(open("dumbbell"), "dumbbell.7");
        GymTrainingPanelService._setNowForTests(2000);
        var done:Object = invoke("finish", running.sessionToken);
        check(done.saved && done.award.kind == "skillPoints" && done.award.amount == 25
            && _root.技能点数 == 75 && _root.经验值 == 100
            && _root.虚拟币 == 998750 && _root.__gymKpointDelta == -1250,
            "skill project spends K points only at finish and grants no EXP");

        setup();
        _root.经验值 = 1000000;
        _root.根据等级得升级所需经验 = function(level):Number { return 1; };
        running = start(open("dumbbell"), "dumbbell.7");
        GymTrainingPanelService._setNowForTests(2000);
        done = invoke("finish", running.sessionToken);
        check(done.saved && done.level == 50 && done.skillPoints == 75,
            "skill-only training does not trigger old pending EXP level growth");

        setup();
        _root.全局健身空攻加成 = 500;
        running = start(open("dummy"), "dummy.1");
        check(running.award.kind == "experience" && running.award.amount == 50000,
            "at-cap preview tells player reward converts to extra experience");
        GymTrainingPanelService._setNowForTests(11000);
        done = invoke("finish", running.sessionToken);
        check(done.saved && done.award.capExperience == 50000
            && _root.经验值 == 60100 && _root.全局健身空攻加成 == 500
            && _root.虚拟币 == 994000,
            "at-cap K training completes with 60,000 EXP and no stat increase");
    }

    private static function testInsufficientAndGateChange():Void {
        setup();
        var running:Object = start(open("dummy"), "dummy.0");
        _root.金钱 = 1;
        GymTrainingPanelService._setNowForTests(11000);
        var rejected:Object = invoke("finish", running.sessionToken);
        check(!rejected.success && rejected.error == "insufficient_funds"
            && rejected.phase == "cancelled" && _root.__gymDirty == 0
            && _root.全局健身空攻加成 == 0 && _root.经验值 == 100,
            "completion rechecks balance and rejects without a partial award");

        setup();
        running = start(open("dummy"), "dummy.4");
        _root.主线任务进度 = 67;
        GymTrainingPanelService._setNowForTests(11000);
        rejected = invoke("finish", running.sessionToken);
        check(!rejected.success && rejected.error == "stale_project"
            && rejected.phase == "cancelled" && _root.__gymDirty == 0,
            "newly unavailable gated row cannot finish");
    }

    private static function testPendingSaveOnlyRetriesSave():Void {
        setup();
        _root.__gymSaveSucceeds = false;
        var running:Object = start(open("dummy"), "dummy.0");
        GymTrainingPanelService._setNowForTests(11000);
        var pending:Object = invoke("finish", running.sessionToken);
        check(!pending.success && pending.phase == "save_pending" && !pending.saved
            && _root.__gymDirty == 1 && _root.__gymFlush == 1
            && _root.金钱 == 4940000 && _root.全局健身空攻加成 == 3,
            "save failure retains applied live state behind pending status");
        check(invoke("query", running.sessionToken).phase == "save_pending"
            && invoke("finish", running.sessionToken).phase == "save_pending"
            && _root.__gymDirty == 1 && _root.__gymFlush == 1,
            "query and duplicate finish do not repeat business or save");
        var recovered:Object = open("squat");
        check(recovered.v == 2 && recovered.stationId == "dummy"
            && recovered.pendingSession.phase == "save_pending"
            && recovered.pendingSession.sessionToken == running.sessionToken
            && recovered.pendingSession.projectId == "dummy.0",
            "same-slot reopen restores the original paid session even from another station");
        var blocked:Object = start(recovered, "dummy.0");
        check(!blocked.success && blocked.error == "save_pending" && _root.__gymDirty == 1,
            "new business start stays blocked during pending save");
        _root.savePath = "other-slot";
        blocked = open("dummy");
        check(blocked.error == "context_changed", "other save slot cannot recover pending write");
        _root.savePath = "gym-test-slot";
        _root.__gymSaveSucceeds = true;
        var saved:Object = invoke("retrySave", running.sessionToken);
        check(saved.success && saved.saved && saved.phase == "applied"
            && _root.__gymDirty == 1 && _root.__gymFlush == 2
            && _root.__gymFeed == 1, "retrySave repeats only the durable fence");
    }

    private static function testNoWriteRefusalsAndLevelGrowth():Void {
        setup();
        var preview:Object = open("dummy");
        var badStart:Object = GymTrainingPanelService.execute("start", {v:1,
            openToken:"gym.open.foreign",stationId:"dummy",projectId:"dummy.0"});
        check(!badStart.success && badStart.phase == "preview" && !badStart.saved
            && badStart.openToken == "gym.open.foreign", "start refusal is an exact preview-phase response");
        _root.金钱 = 1;
        var poorStart:Object = start(preview, "dummy.0");
        check(!poorStart.success && poorStart.error == "insufficient_funds"
            && poorStart.phase == "preview" && _root.__gymDirty == 0,
            "start rechecks live balance before beginning a doomed timer");
        _root.金钱 = 5000000;
        var running:Object = start(preview, "dummy.0");
        GymTrainingPanelService._setNowForTests(11000);
        _root.存档系统.flushDurableNow = undefined;
        var refused:Object = invoke("finish", running.sessionToken);
        check(!refused.success && refused.error == "save_unavailable"
            && refused.phase == "cancelled" && refused.sessionToken == running.sessionToken
            && _root.__gymDirty == 0 && _root.金钱 == 5000000,
            "missing durable save cancels without charging");

        setup();
        running = start(open("dummy"), "dummy.0");
        GymTrainingPanelService._setNowForTests(11000);
        _root.经验值 = 9007199254740991;
        refused = invoke("finish", running.sessionToken);
        check(!refused.success && refused.error == "state_unavailable"
            && refused.phase == "cancelled" && _root.__gymDirty == 0
            && _root.全局健身空攻加成 == 0 && _root.金钱 == 5000000,
            "unsafe experience balance rejects atomically");

        setup();
        running = start(open("dummy"), "dummy.0");
        GymTrainingPanelService._setNowForTests(11000);
        _root.存档系统.markDirty = function():Void { throw new Error("stub"); };
        refused = invoke("finish", running.sessionToken);
        check(!refused.success && refused.error == "save_unavailable"
            && refused.phase == "cancelled" && _root.金钱 == 5000000
            && _root.经验值 == 100 && _root.__gymFeed == 0,
            "dirty-mark exception cannot leave a partial gym settlement");

        setup();
        _root.根据等级得升级所需经验 = function(level):Number {
            return level == 50 ? 10100 : 1000000000000;
        };
        running = start(open("dummy"), "dummy.0");
        GymTrainingPanelService._setNowForTests(11000);
        var done:Object = invoke("finish", running.sessionToken);
        check(done.saved && done.level == 51 && done.experience == 10100
            && done.skillPoints == 75 && _root.身价 == 5100,
            "attribute training experience and resulting level/SP gain share one save");
    }

    private static function testOtherStationsAndContext():Void {
        setup();
        _root.全局健身HP加成 = 1995;
        var running:Object = start(open("dumbbell"), "dumbbell.1");
        GymTrainingPanelService._setNowForTests(11000);
        var done:Object = invoke("finish", running.sessionToken);
        check(done.saved && done.current == 2000 && done.award.amount == 5,
            "dumbbell HP cap uses source row and actual gain");

        setup();
        _root.全局健身MP加成 = 1995;
        running = start(open("squat"), "squat.0");
        GymTrainingPanelService._setNowForTests(11000);
        done = invoke("finish", running.sessionToken);
        check(done.saved && done.current == 2000 && done.award.amount == 5,
            "squat MP cap uses source row and actual gain");

        setup();
        running = start(open("dummy"), "dummy.0");
        _root.gameworld = {hero:{}};
        GymTrainingPanelService._setNowForTests(11000);
        var invalid:Object = invoke("finish", running.sessionToken);
        check(invalid.phase == "cancelled" && _root.__gymDirty == 0,
            "actor or world replacement cancels unfinished training without writes");
        setup();
        running = start(open("dummy"), "dummy.0");
        _root.关卡地图帧值 = "another-scene";
        GymTrainingPanelService._setNowForTests(11000);
        invalid = invoke("finish", running.sessionToken);
        check(invalid.phase == "cancelled" && _root.__gymDirty == 0
            && _root.金钱 == 5000000,
            "scene stamp change cancels even if the world and actor references persist");
        check(!invoke("finish", "gym.session.foreign").success,
            "foreign session token never commits");
    }

    private static function testLiveAttributeProjection():Void {
        setup();
        var actor:MovieClip = _root.createEmptyMovieClip("hero", _root.getNextHighestDepth());
        _root.gameworld.hero = actor;
        _root.根据等级计算值 = function(minimum:Number, maximum:Number, level:Number):Number {
            return minimum + (maximum - minimum) * level / 100;
        };
        actor.hasDressup = true;
        actor.等级 = 50;
        actor.体重 = 70;
        actor.是否为敌人 = false;
        actor.hp基本满血值 = 1000;
        actor.mp基本满血值 = 100;
        actor.基本防御力 = 300;
        actor.基础命中率 = 10;
        actor.基础韧性系数 = 1.2;
        actor.基础躲闪率 = 5;
        actor.空手攻击力_min = 100;
        actor.空手攻击力_max = 200;
        actor.攻击模式 = "空手";
        actor.area = {_height:1};
        actor._yscale = 100;
        actor.根据模式重新读取武器加成 = function(mode:String):Void {};
        var keys:Array = ["头部装备数据", "上装装备数据", "手部装备数据",
            "下装装备数据", "脚部装备数据", "颈部装备数据", "长枪数据",
            "手枪数据", "手枪2数据", "刀数据", "手雷数据"];
        for (var i:Number = 0; i < keys.length; i++) actor[keys[i]] = {data:{}};
        actor.上装装备数据 = {data:{hp:100, mp:20}};
        actor.buffManager = {syncAllPathBindings:function():Void { _root.__gymBuffSync++; }};
        actor.shield = {refreshStanceResistance:function():Void { _root.__gymShieldSync++; }};
        _root.__gymBuffSync = 0;
        _root.__gymShieldSync = 0;
        _root.__gymHudHp = 0;
        _root.__gymHudMp = 0;
        _root.玩家信息界面 = {
            刷新hp显示:function():Void { _root.__gymHudHp++; },
            刷新mp显示:function():Void { _root.__gymHudMp++; },
            刷新经验值显示:function():Void {}
        };
        org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer.updateProperties(actor);
        actor.hp = 700;
        actor.mp = 40;
        var beforeAttack:Number = Number(actor.空手攻击力);
        var beforeInner:Number = Number(actor.内力);
        var beforeDefense:Number = Number(actor.防御力);
        var cases:Array = [
            {station:"dummy", project:"dummy.0", property:"空手攻击力", gain:3},
            {station:"dummy", project:"dummy.3", property:"内力", gain:20},
            {station:"dumbbell", project:"dumbbell.0", property:"hp满血值", gain:10},
            {station:"squat", project:"squat.0", property:"mp满血值", gain:10},
            {station:"dumbbell", project:"dumbbell.2", property:"防御力", gain:5}
        ];
        var expected:Object = {空手攻击力:beforeAttack, 内力:beforeInner,
            hp满血值:1100, mp满血值:120, 防御力:beforeDefense};
        for (i = 0; i < cases.length; i++) {
            var item:Object = cases[i];
            var startAt:Number = 1000 + i * 30000;
            GymTrainingPanelService._setNowForTests(startAt);
            var running:Object = start(open(item.station), item.project);
            check(running.success && running.phase == "running", "live stat fixture starts " + item.project);
            GymTrainingPanelService._setNowForTests(startAt + 30000);
            var saved:Object = invoke("finish", running.sessionToken);
            expected[item.property] += item.gain;
            check(saved.saved && saved.award.kind == "stat"
                && Number(actor[item.property]) == expected[item.property]
                && actor.hp == 700 && actor.mp == 40,
                "durably saved " + item.project + " updates current actor without healing");
        }
        check(_root.__gymBuffSync == 6 && _root.__gymShieldSync == 6
            && _root.__gymHudHp == 5 && _root.__gymHudMp == 5,
            "five live projections preserve equipment, Buff/shield bindings and refresh HUD");
        check(actor.hp满血值 == 1110 && actor.mp满血值 == 130
            && actor.空手攻击力 == beforeAttack + 3
            && actor.内力 == beforeInner + 20
            && actor.防御力 == beforeDefense + 5,
            "live values match all five persisted gym bonuses without compounding");

        _root.__gymSaveSucceeds = false;
        GymTrainingPanelService._setNowForTests(160000);
        var pendingRun:Object = start(open("dummy"), "dummy.0");
        GymTrainingPanelService._setNowForTests(170000);
        var pending:Object = invoke("finish", pendingRun.sessionToken);
        check(pending.phase == "save_pending" && actor.空手攻击力 == beforeAttack + 3
            && _root.__gymBuffSync == 6, "failed durable save does not project an unconfirmed live reward");
        _root.__gymSaveSucceeds = true;
        var retried:Object = invoke("retrySave", pendingRun.sessionToken);
        check(retried.saved && actor.空手攻击力 == beforeAttack + 6
            && _root.__gymBuffSync == 7, "retry projects saved stat exactly once");
        invoke("finish", pendingRun.sessionToken);
        invoke("query", pendingRun.sessionToken);
        check(actor.空手攻击力 == beforeAttack + 6 && _root.__gymBuffSync == 7,
            "duplicate receipts never reproject live stats");
        actor.removeMovieClip();
    }

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++;
        else { failed++; trace("[FAIL] GymTraining: " + message); }
    }

    private static function capture():Object {
        return {
            gameworld:_root.gameworld, actorKey:_root.控制目标, savePath:_root.savePath,
            mapFrame:_root.关卡地图帧值,
            canSave:_root.允许存档, progress:_root.主线任务进度,
            level:_root.等级, levelLimit:_root.等级限制,
            baseWorth:_root.基础身价值, worth:_root.身价,
            gender:_root.性别, hair:_root.发型, face:_root.脸型,
            money:_root.金钱, kpoint:_root.虚拟币, experience:_root.经验值,
            skills:_root.技能点数, hp:_root.全局健身HP加成,
            mp:_root.全局健身MP加成, attack:_root.全局健身空攻加成,
            defense:_root.全局健身防御加成, inner:_root.全局健身内力加成,
            threshold:_root.根据等级得升级所需经验,
            levelSkills:_root.根据等级计算获得技能点,
            save:_root.存档系统, currencyFeed:_root.记录玩家货币变化,
            catalog:_root.健身房训练类型,
            levelValue:_root.根据等级计算值, playerInfo:_root.玩家信息界面
        };
    }
    private static function restore(s:Object):Void {
        _root.gameworld=s.gameworld; _root.控制目标=s.actorKey;
        _root.savePath=s.savePath; _root.关卡地图帧值=s.mapFrame;
        _root.允许存档=s.canSave;
        _root.主线任务进度=s.progress; _root.等级=s.level;
        _root.等级限制=s.levelLimit; _root.基础身价值=s.baseWorth;
        _root.身价=s.worth; _root.性别=s.gender;
        _root.发型=s.hair; _root.脸型=s.face;
        _root.金钱=s.money; _root.虚拟币=s.kpoint;
        _root.经验值=s.experience; _root.技能点数=s.skills;
        _root.全局健身HP加成=s.hp; _root.全局健身MP加成=s.mp;
        _root.全局健身空攻加成=s.attack;
        _root.全局健身防御加成=s.defense;
        _root.全局健身内力加成=s.inner;
        _root.根据等级得升级所需经验=s.threshold;
        _root.根据等级计算获得技能点=s.levelSkills;
        _root.存档系统=s.save; _root.记录玩家货币变化=s.currencyFeed;
        _root.健身房训练类型=s.catalog;
        _root.根据等级计算值=s.levelValue;
        _root.玩家信息界面=s.playerInfo;
    }
}
