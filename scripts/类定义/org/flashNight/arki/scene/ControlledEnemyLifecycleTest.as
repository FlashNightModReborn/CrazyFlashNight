import org.flashNight.arki.scene.ControlledEnemyLifecycle;
import org.flashNight.arki.scene.LeeTrialDefinition;
import org.flashNight.arki.scene.StageReturnFlow;

/** 只使用内存和独占影片剪辑的出生/回调身份回归，不读写用户存档。 */
class org.flashNight.arki.scene.ControlledEnemyLifecycleTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(ok:Boolean, label:String):Void {
        if (ok) passed++; else { failed++; trace("FAIL " + label); }
    }
    public static function runAllTests():Void {
        passed = failed = 0;
        var config:Object = {schema:"lee-trial.v1",id:"lee-trial",stageName:"Lee试战",actor:{identifier:"敌人-李小龙",name:"Lee",level:30,height:185,gender:"男"},stages:[{BasicInformation:{Background:"flashswf/backgrounds/gk15_1_BG.swf",EndFrame:"房间",PlayerX:230,PlayerY:470,BGM:{Command:"play",Title:"By Peace Or By Power",Loop:true}},Wave:{SubWave:[{WaveInformation:{Duration:0},EnemyGroup:{Enemy:[{Type:"兵种47",Level:20,Quantity:2,Interval:700,SpawnIndex:"right",Parameters:{不掉钱:true,不掉装备:true,最小经验值:0,最大经验值:0,掉落物:[]}}]}},{WaveInformation:{Duration:0},EnemyGroup:{Enemy:[{Type:"兵种64",Level:25,Quantity:2,Interval:700,SpawnIndex:"right",Parameters:{不掉钱:true,不掉装备:true,最小经验值:0,最大经验值:0,掉落物:[]}},{Type:"兵种65",Level:25,Quantity:1,Interval:700,SpawnIndex:"right",Parameters:{不掉钱:true,不掉装备:true,最小经验值:0,最大经验值:0,掉落物:[]}}]}},{WaveInformation:{Duration:0},EnemyGroup:{Enemy:[{Type:"兵种40",Level:30,Quantity:1,Interval:700,SpawnIndex:"right",Parameters:{不掉钱:true,不掉装备:true,最小经验值:0,最大经验值:0,掉落物:[]},InstanceName:"leeTrialOpponent"}]}}]},Event:[{EventName:"Start",Message:"Lee试战：三轮对战，最后一轮与同源AI Lee交手。通过书架按钮结束试战；本场不消耗原角色物资，也不发放通关奖励。"}],Instances:{Instance:[]},Pickups:{Pickup:[]}}]};
        config.actor.宠物属性 = {冲腿龙息:true};
        check(LeeTrialDefinition.valid(config), "the single-room fixture passes the real parser");
        var multi:Object = org.flashNight.gesh.object.PersistedSnapshot.clone(config);
        multi.stages = [];
        for (var n:Number = 0; n < 4; n++) multi.stages.push(org.flashNight.gesh.object.PersistedSnapshot.clone(config.stages[0]));
        delete multi.stages[0].BasicInformation.PlayerX;
        delete multi.stages[0].BasicInformation.PlayerY;
        check(LeeTrialDefinition.valid(multi), "four rooms accept canonical default spawn coordinates");
        multi.stages[3].Wave.SubWave[2].EnemyGroup.Enemy[0].Parameters.不掉钱 = false;
        check(!LeeTrialDefinition.valid(multi), "loot violation in the final wave of the final room is rejected");
        multi.stages[3].Wave.SubWave[2].EnemyGroup.Enemy[0].Parameters.不掉钱 = true;
        multi.stages[3].Wave.SubWave[2].EnemyGroup.Enemy[0].Parameters.不掉装备 = false;
        check(!LeeTrialDefinition.valid(multi), "native equipment drops must also be explicitly disabled");
        multi.stages[3].Wave.SubWave[2].EnemyGroup.Enemy[0].Parameters.不掉装备 = true;
        multi.stages[3].BasicInformation.Background = "../escape.swf";
        check(!LeeTrialDefinition.valid(multi), "unsafe background in the final room is rejected");
        multi.stages[3].BasicInformation.Background = config.stages[0].BasicInformation.Background;
        multi.stages[0].BasicInformation.PlayerX = 20;
        check(!LeeTrialDefinition.valid(multi), "partial spawn coordinates fail closed");
        delete multi.stages[0].BasicInformation.PlayerX;
        multi.stages.push(config.stages[0]);
        check(!LeeTrialDefinition.valid(multi), "the four-room bound is enforced");
        check(LeeTrialDefinition.accept(config), "trial definition becomes ready");
        var staged:Array = LeeTrialDefinition.stages();
        var opponent:Object = staged[0].Wave.SubWave[2].EnemyGroup.Enemy[0];
        check(opponent.Level == config.actor.level && opponent.Parameters.身高 == config.actor.height
            && opponent.Parameters.宠物属性.冲腿龙息 === true,
            "AI opponent and controlled actor derive the same level, body and promotion");
        opponent.Parameters.宠物属性.冲腿龙息 = false;
        check(LeeTrialDefinition.get().actor.宠物属性.冲腿龙息 === true,
            "opponent projection cannot mutate the actor definition");
        var root:Object = {_saveExt:{}, 特殊操作单位:"", 身高:175, 角色名:"Origin",
            等级:15, 性别:"女", accId:"fixture", savePath:"bookrun.lee.fixture", 控制目标:"hero", gameworld:{}};
        var normal:Object = ControlledEnemyLifecycle.createSpawn(root, 10, 20, false);
        check(normal.identifier == "主角-男" && normal.parameters.名字 == "Origin"
            && normal.parameters.等级 == 15 && normal.parameters.用户ID == undefined,
            "ordinary spawn retains profile identity and account scope");
        root.特殊操作单位 = "legacy-special";
        check(ControlledEnemyLifecycle.createSpawn(root,0,0,true).identifier == "legacy-special",
            "ordinary legacy special-unit entry is preserved");
        var run:Object = {bookId:"lee-trial",slot:root.savePath,outcome:"active"};
        root._saveExt.bookRun = run;
        var spawn:Object = ControlledEnemyLifecycle.createSpawn(root,230,470,true);
        check(spawn.parameters.宠物属性.冲腿龙息 === true
            && spawn.parameters.宠物属性 !== LeeTrialDefinition.get().actor.宠物属性,
            "trial grants cloned native promotion without sharing mutable actor configuration");
        check(spawn.identifier == "敌人-李小龙" && spawn.parameters.名字 == "Lee"
            && spawn.parameters.等级 == 30 && spawn.parameters.身高 == 185,
            "trial selects original Lee with fixed trial identity");
        check(spawn.parameters.__enemyActionPlayer === true && spawn.parameters.允许拾取 === false
            && spawn.parameters.mp == 0 && spawn.parameters.用户ID == "fixture",
            "trial owns player input without item pickup or profile resource inheritance");
        var actor:Object = spawn.parameters;
        actor._name = "hero"; actor._parent = root.gameworld;
        var context:Object = actor.__controlledEnemyContext;
        check(ControlledEnemyLifecycle.ownsContext(root, actor, context), "matching spawn context is owned");
        run.slot = "wrong";
        check(!ControlledEnemyLifecycle.ownsContext(root,actor,context), "changed run slot invalidates old callback");
        check(ControlledEnemyLifecycle.createSpawn(root,0,0,true) == null, "wrong slot fails closed before spawn");
        run.slot = root.savePath; run.outcome = "dead";
        check(ControlledEnemyLifecycle.createSpawn(root,0,0,true) == null, "completed run cannot respawn Lee");
        run.outcome = "active";
        root._saveExt.bookRun = {bookId:"lee-trial",slot:root.savePath,outcome:"active"};
        check(!ControlledEnemyLifecycle.ownsContext(root,actor,context), "old run object cannot claim a new run");
        root._saveExt.bookRun = run;
        root.gameworld = {};
        check(!ControlledEnemyLifecycle.ownsContext(root,actor,context), "new world cannot accept old callback");
        root.gameworld = actor._parent;
        actor.__controlledEnemyContext = {};
        check(!ControlledEnemyLifecycle.ownsContext(root,actor,context), "same-name replacement cannot inherit context");
        movieClipIdentity(config);
        baseSceneReentry();
        leeStageHandoff();
        canonicalLeeRunCopies();
        cooldownSessionOwnership();
        trace("ControlledEnemyLifecycleTest Tests Passed: " + passed);
        trace("ControlledEnemyLifecycleTest Tests Failed: " + failed);
    }
    private static function cooldownSessionOwnership():Void {
        var slot:String = "bookrun.cooldown.fixture";
        var run:Object = {bookId:"lee-trial",slot:slot,seed:11,startedAt:12,outcome:"active"};
        var stageRun:Object = {stageName:LeeTrialDefinition.get().stageName,activeFrames:10};
        var first:Object = ControlledEnemyLifecycle.actionCooldowns(run,stageRun,slot);
        first.deadlines.hop = 85;
        var copy:Object = org.flashNight.gesh.object.PersistedSnapshot.clone(run);
        var next:Object = ControlledEnemyLifecycle.actionCooldowns(copy,stageRun,slot);
        check(first === next && next.clock === stageRun && next.deadlines.hop == 85,
            "canonical same-run copy and next-map spawn retain the cooldown authority");
        check(ControlledEnemyLifecycle.actionCooldowns(run,stageRun,"other") == null,
            "a different active slot cannot inherit the trial cooldown session");
        check(ControlledEnemyLifecycle.actionCooldowns(run,{stageName:"other",activeFrames:10},slot) == null,
            "unrelated native stage cannot claim the trial cooldown clock");
        run.outcome = "victory";
        check(ControlledEnemyLifecycle.actionCooldowns(run,stageRun,slot) == null,
            "completed trial cannot bind a fresh player to the old cooldown session");
        run.outcome = "active";
        var fresh:Object = ControlledEnemyLifecycle.actionCooldowns(run,
            {stageName:stageRun.stageName,activeFrames:0},slot);
        check(fresh !== first && fresh.deadlines.hop == undefined,
            "a new native stage run starts with independent cooldowns even at the same slot");
        run.seed++;
        next = ControlledEnemyLifecycle.actionCooldowns(run,fresh.clock,slot);
        check(next !== fresh, "new persisted trial identity cannot inherit cooldowns by slot alone");
    }

    private static function canonicalLeeRunCopies():Void {
        var fixture:MovieClip = _root.createEmptyMovieClip("__leeRunCopyFixture",_root.getNextHighestDepth());
        var world:MovieClip = fixture.createEmptyMovieClip("world",1); world.场景名 = "wuxianguotu_1";
        var run:Object = {bookId:"lee-trial",slot:"bookrun.copy.fixture",originSlot:"origin.fixture",
            seed:17,startedAt:777,outcome:"active"};
        var root:Object = {_currentframe:210,savePath:run.slot,_saveExt:{bookRun:run},gameworld:world,
            淡出动画:{__transitionProjectionIdentity:{}},当前为战斗地图:false};
        var manager:Object = {isActive:true,isFailed:false,isFinished:false,currentStage:-1,calls:0,
            initStage:function():Void { this.calls++; this.currentStage++; }};
        var pending:Object = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        root.淡出动画 = {__transitionProjectionIdentity:{}};
        root._saveExt.bookRun = {bookId:run.bookId,slot:run.slot,originSlot:run.originSlot,
            seed:run.seed,startedAt:run.startedAt,outcome:"active"};
        check(org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending)
                && manager.calls == 1,
            "canonical same-run copy and rebuilt visual fade retain the accepted navigation");
        pending = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        root._saveExt.bookRun = {bookId:run.bookId,slot:run.slot,originSlot:run.originSlot,
            seed:18,startedAt:run.startedAt,outcome:"active"};
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending)
                && manager.calls == 1,"a different seed cannot inherit same-slot run authority");
        root._saveExt.bookRun = run;
        pending = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        root._saveExt.bookRun = {bookId:run.bookId,slot:run.slot,originSlot:"another.origin",
            seed:run.seed,startedAt:run.startedAt,outcome:"active"};
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "a different origin cannot inherit the same temporary slot authority");
        root._saveExt.bookRun = run;
        pending = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        root._saveExt.bookRun = {bookId:run.bookId,slot:run.slot,originSlot:run.originSlot,
            seed:run.seed,startedAt:778,outcome:"active"};
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "a different startedAt cannot inherit same-slot run authority");
        fixture.removeMovieClip();
    }
    private static function leeStageHandoff():Void {
        var fixture:MovieClip = _root.createEmptyMovieClip("__leeStageHandoffFixture", _root.getNextHighestDepth());
        var world:MovieClip = fixture.createEmptyMovieClip("world", 1);
        world.场景名 = "wuxianguotu_1";
        var run:Object = {bookId:"lee-trial", slot:"bookrun.handoff.fixture", outcome:"active"};
        var root:Object = {_currentframe:210, savePath:run.slot, _saveExt:{bookRun:run}, gameworld:world,
            淡出动画:{__transitionProjectionIdentity:{}}, 当前为战斗地图:false};
        var manager:Object = {isActive:true, isFailed:false, isFinished:false, currentStage:-1, calls:0,
            initStage:function():Void { this.calls++; this.currentStage++; }};
        var pending:Object = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        check(org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending)
                && manager.calls == 1 && manager.currentStage == 0,
            "persistent continuation initializes an existing empty Lee world exactly once");
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending)
                && manager.calls == 1, "consumed continuation cannot skip to the next room");
        pending = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        manager.currentStage++;
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "native initialization winning the race is never repeated");
        pending = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        root.savePath = "different";
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "slot switch invalidates the pending initialization");
        root.savePath = run.slot;
        root._saveExt.bookRun = {bookId:"lee-trial", slot:run.slot, outcome:"active"};
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "same-slot replacement run cannot inherit the previous run continuation");
        root._saveExt.bookRun = run;
        org.flashNight.arki.scene.SceneTransitionGuard.beginNavigation(root);
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "a new accepted navigation invalidates an old initialization");
        pending = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        world.removeMovieClip();
        world = fixture.createEmptyMovieClip("world", 1);
        world.场景名 = "wuxianguotu_1"; root.gameworld = world;
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "same-path real MovieClip replacement cannot inherit world authority");
        pending = org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager);
        manager.isFailed = true;
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending)
                && manager.calls == 1, "a failed native stage initialization is not retried");
        manager.isFailed = false;
        run.bookId = "repair-campus";
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "mutating the current run book cannot retain Lee initialization authority");
        run.bookId = "lee-trial"; run.slot = "changed.slot";
        check(!org.flashNight.arki.scene.SceneTransitionGuard.completeLeeStage(root,manager,pending),
            "mutating the run slot invalidates initialization even if root savePath is unchanged");
        run.slot = root.savePath; root.当前为战斗地图 = true;
        check(org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager) == undefined,
            "a live battle does not schedule recovery");
        root.当前为战斗地图 = false; run.bookId = "repair-campus";
        check(org.flashNight.arki.scene.SceneTransitionGuard.captureLeeStage(root,manager) == undefined,
            "other books never schedule the Lee-specific continuation");
        fixture.removeMovieClip();
    }
    private static function baseSceneReentry():Void {
        var root:Object = {_currentframe:146};
        check(!org.flashNight.arki.scene.SceneTransitionGuard.canReloadBaseScene(root,"基地地图"),
            "an unobserved timeline frame cannot claim a base reload");
        org.flashNight.arki.scene.SceneTransitionGuard.rememberBaseSceneFrame(root,"基地场景-房间");
        check(org.flashNight.arki.scene.SceneTransitionGuard.canReloadBaseScene(root,"基地地图"),
            "same base timeline frame recreates a world removed for character switching");
        root.gameworld = {};
        check(!org.flashNight.arki.scene.SceneTransitionGuard.canReloadBaseScene(root,"基地地图"),
            "an existing world is never duplicated");
        delete root.gameworld;
        root._currentframe = 210;
        check(!org.flashNight.arki.scene.SceneTransitionGuard.canReloadBaseScene(root,"基地地图"),
            "a different display frame cannot claim an in-place world rebuild");
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedBaseSceneFrame(root,"基地地图") == 146,
            "the verified base destination bypasses an intermediate loading frame without hardcoded timeline numbers");
        root._currentframe = 146;
        check(!org.flashNight.arki.scene.SceneTransitionGuard.canReloadBaseScene(root,"wuxianguotu_1"),
            "a battle route cannot use the base-only reload path");
        root.savePath = "bookrun.reentry.fixture";
        root._saveExt = {bookRun:{bookId:"lee-trial",slot:root.savePath,outcome:"active"}};
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(root,"wuxianguotu_1") == 0,
            "first Lee entry cannot invent an unobserved battle display frame");
        root._currentframe = 210;
        org.flashNight.arki.scene.SceneTransitionGuard.rememberSharedSceneFrame(root,"wuxianguotu_1");
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(root,"wuxianguotu_1") == 210,
            "repeated Lee entry uses the actually loaded battle display frame");
        root.gameworld = {};
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(root,"wuxianguotu_1") == 0,
            "battle reentry never duplicates an existing world");
        delete root.gameworld;
        root._saveExt.bookRun.slot = "wrong";
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(root,"wuxianguotu_1") == 0,
            "a mismatched temporary slot cannot use the Lee display frame");
        root._saveExt.bookRun.slot = root.savePath;
        root._saveExt.bookRun.bookId = "repair-campus";
        check(org.flashNight.arki.scene.SceneTransitionGuard.observedSharedSceneFrame(root,"wuxianguotu_1") == 0,
            "ordinary and other-book battle entries keep their existing navigation path");
        root.__baseSceneFrame = "146";
        check(!org.flashNight.arki.scene.SceneTransitionGuard.canReloadBaseScene(root,"基地地图"),
            "malformed frame observations fail closed");
    }
    private static function movieClipIdentity(config:Object):Void {
        var saved:Object = {world:_root.gameworld, ext:_root._saveExt, slot:_root.savePath,
            control:_root.控制目标, props:_root.敌人属性表};
        var fixture:MovieClip = _root.createEmptyMovieClip("__leeLifecycleFixture", _root.getNextHighestDepth());
        try {
            var world:MovieClip = fixture.createEmptyMovieClip("world",1);
            _root.gameworld = world; _root.savePath = "bookrun.lee.fixture"; _root.控制目标 = "hero";
            _root.敌人属性表 = {};
            _root._saveExt = {bookRun:{bookId:"lee-trial",slot:_root.savePath,outcome:"active"}};
            var spawn:Object = ControlledEnemyLifecycle.createSpawn(_root,0,0,false);
            var actor:MovieClip = world.createEmptyMovieClip("hero",1);
            for(var key:String in spawn.parameters) actor[key] = spawn.parameters[key];
            actor.兵种 = "敌人-李小龙"; actor.hp = 100;
            var context:Object = actor.__controlledEnemyContext;
            var callback:Function = actor.__enemyActionOnDeath;
            check(!callback(actor) && !context.handled, "live actor cannot enter death path");
            actor.hp = 0;
            check(callback(actor) && context.handled && actor.已加经验值 === true,
                "dead controlled Lee is retained and original drop path is intercepted");
            var record:Object = actor.__battleRecord;
            check(callback(actor) && actor.__battleRecord === record,
                "repeated death check preserves the same casualty record");
            actor.removeMovieClip();
            var next:MovieClip = world.createEmptyMovieClip("hero",1);
            next.hp = 0;
            check(!callback(next), "captured callback refuses same-path replacement MovieClip");
        } catch(error:Error) { failed++; trace("FAIL lifecycle fixture: " + error); }
        finally {
            fixture.removeMovieClip();
            _root.gameworld = saved.world; _root._saveExt = saved.ext; _root.savePath = saved.slot;
            _root.控制目标 = saved.control; _root.敌人属性表 = saved.props;
        }
    }
}
