import org.flashNight.arki.scene.LeeAssaultRules;
/** 真实命中累计、跨场景进阶资格、电伤预算与复活的边界。 */
class org.flashNight.arki.scene.LeeAssaultRulesTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] LeeAssault: " + message); }
    }
    private static function room(state:Object, index:Number, hits:Number):Void {
        state.rooms[index].cleared = true;
        for (var i:Number=0; i<hits; i++) LeeAssaultRules.recordHit(state,index,i,250);
        state.rooms[index].fired = 12;
    }
    private static function finalLightingLifecycle():Void {
        var api:Object = org.flashNight.arki.scene.LeeAssaultService;
        var priorRoom:Object = api["_room"], priorWatch:Object = api["_watch"];
        var priorAllow:Object = api["_allowClear"];
        var priorExt:Object = _root._saveExt, priorWorld:Object = _root.gameworld;
        var priorSlot = _root.savePath;
        var owner:Object = {}, run:Object = {outcome:"victory"};
        var ws:Object = {minLight:0,maxLight:0.8,pauseDayNightCycle:true};
        var mark:Object = {removeMovieClip:function():Void {}};
        var world:Object = {__stageReturnWorldIdentity:owner,__leeLightningMark:mark,__leeTrapEmitter:mark};
        var room:Object = {phase:"finished",run:run,slot:"lee.lighting.fixture",owner:owner,world:world,
            lighting:{ws:ws,min:3,max:7,pause:false}};
        var watch:Object = {onEnterFrame:function():Void {}};
        _root._saveExt = {bookRun:run}; _root.gameworld = world; _root.savePath = room.slot;
        api["_room"] = room; api["_watch"] = watch;
        api.tick();
        check(ws.minLight==0 && ws.maxLight==0.8 && api["_room"] === room
            && watch.onEnterFrame == undefined,"completed finale keeps its outage until actual scene exit");
        _root.gameworld = {__stageReturnWorldIdentity:{}};
        api.tick();
        check(ws.minLight==3 && ws.maxLight==7 && ws.pauseDayNightCycle === false
            && api["_room"] == null,"retired world returns its weather configuration exactly once");
        api["_room"] = priorRoom; api["_watch"] = priorWatch; api["_allowClear"] = priorAllow;
        _root._saveExt = priorExt; _root.gameworld = priorWorld; _root.savePath = priorSlot;
    }
    private static function finalBattleRecovery():Void {
        var api:Object = org.flashNight.arki.scene.LeeAssaultService;
        var session:Object = org.flashNight.arki.scene.StageRunSession;
        var saved:Object = {room:api["_room"],watch:api["_watch"],ext:_root._saveExt,world:_root.gameworld,
            slot:_root.savePath,control:_root.控制目标,pause:_root.暂停,transition:_root.场景转换中,run:session["_run"]};
        var owner:Object = {}, run:Object = {outcome:"active"}, clock:Object = {activeFrames:0};
        var actor:Object = {__enemyActionPlayer:true,hp:100,hp满血值:17881};
        var world:Object = {__stageReturnWorldIdentity:owner,hero:actor};
        var room:Object = {phase:"battle",index:3,run:run,slot:"lee.regen.fixture",owner:owner,world:world,
            config:{finalRecoveryFrames:3000},lastFrame:-1};
        _root._saveExt = {bookRun:run}; _root.gameworld = world; _root.savePath = room.slot;
        _root.控制目标 = "hero"; _root.暂停 = _root.场景转换中 = false;
        api["_room"] = room; session["_run"] = clock;
        api.tick(); api.tick();
        check(actor.hp == 106,"final battle heals six HP per unique active frame, about one percent per second");
        _root.暂停 = true; clock.activeFrames++; api.tick();
        check(actor.hp == 106,"paused combat grants no healing");
        _root.暂停 = false; _root.场景转换中 = true; clock.activeFrames++; api.tick();
        check(actor.hp == 106,"scene transitions grant no healing");
        _root.场景转换中 = false; room.index = 2; clock.activeFrames++; api.tick();
        check(actor.hp == 106,"earlier rooms receive no battle regeneration");
        room.index = 3; room.phase = "dialogue"; clock.activeFrames++; api.tick();
        check(actor.hp == 106,"dialogue cannot bank battle healing");
        room.phase = "battle"; actor.hp = 0; clock.activeFrames++; api.tick();
        check(actor.hp == 0,"battle healing cannot revive a dead player");
        actor.hp = actor.hp满血值 - 2; clock.activeFrames++; api.tick();
        check(actor.hp == actor.hp满血值,"battle healing caps at maximum HP");
        api["_room"] = saved.room; api["_watch"] = saved.watch; session["_run"] = saved.run;
        _root._saveExt = saved.ext; _root.gameworld = saved.world; _root.savePath = saved.slot;
        _root.控制目标 = saved.control; _root.暂停 = saved.pause; _root.场景转换中 = saved.transition;
    }
    private static function powerAndLootScope():Void {
        var half:Object = LeeAssaultRules.powerBounds(7,.8,.5);
        check(Math.abs(half.min-3.5)<.00001 && Math.abs(half.max-3.9)<.00001,"half the discharges drains half the lighting range");
        var low:Object = LeeAssaultRules.powerBounds(7,.8,-1), high:Object = LeeAssaultRules.powerBounds(7,.8,2);
        check(low.min==7 && low.max==7 && high.min==0 && Math.abs(high.max-.8)<.00001,"lighting progress clamps to normal and exact outage bounds");
        var previous:Object = low, monotone:Boolean = true;
        for(var n:Number=1;n<=12;n++) {
            var value:Object=LeeAssaultRules.powerBounds(7,.8,n/12);
            monotone=monotone && value.min < previous.min && value.max < previous.max;
            previous=value;
        }
        check(monotone,"all twelve discharges lower both weather bounds");
        var api:Object = org.flashNight.arki.scene.LeeAssaultService;
        var session:Object = org.flashNight.arki.scene.StageRunSession;
        var saved:Object={room:api["_room"],watch:api["_watch"],ext:_root._saveExt,world:_root.gameworld,
            slot:_root.savePath,control:_root.控制目标,pause:_root.暂停,transition:_root.场景转换中,run:session["_run"]};
        var owner:Object={},run:Object={bookId:"lee-trial",outcome:"active"},clock:Object={activeFrames:0};
        var ws:Object={minLight:7,maxLight:7,pauseDayNightCycle:true};
        var actor:Object={__enemyActionPlayer:true,hp:100,hp满血值:100};
        var world:Object={__stageReturnWorldIdentity:owner,hero:actor};
        var room:Object={phase:"gap",index:0,run:run,slot:"lee.power.fixture",owner:owner,world:world,
            config:{battleLight:7,outageLight:.8,gapFrames:6},lastFrame:-1,wait:100,
            lighting:{ws:ws},lightProgress:0};
        api["_room"]=room;session["_run"]=clock;
        _root._saveExt={bookRun:run};_root.gameworld=world;_root.savePath=room.slot;
        _root.控制目标="hero";_root.暂停=_root.场景转换中=false;
        check(api.suppressesEnemyDrops(),"owned Lee world suppresses catalog and equipment loot including transformed units");
        run.outcome="victory";check(api.suppressesEnemyDrops(),"late deaths after the ending still have no loot");run.outcome="active";
        _root.savePath="other.slot";check(!api.suppressesEnemyDrops(),"a different save slot cannot inherit no-loot");_root.savePath=room.slot;
        _root._saveExt.bookRun={};check(!api.suppressesEnemyDrops(),"a replacement journey cannot inherit old no-loot");_root._saveExt.bookRun=run;
        _root.gameworld={__stageReturnWorldIdentity:{}};check(!api.suppressesEnemyDrops(),"ordinary replacement worlds keep their own loot rules");_root.gameworld=world;
        run.bookId="cf1";check(!api.suppressesEnemyDrops(),"other roguelike books keep their intended loot");run.bookId="lee-trial";
        var pickupApi:Object=org.flashNight.arki.unit.Action.PickUp.PickUpManager;
        var validationApi:Object=org.flashNight.arki.unit.UnitComponent.Initializer.ElementComponent.ProgressValidator;
        var originalValidation:Function=validationApi.meetsRequirements;
        var reached:Number=0;
        validationApi.meetsRequirements=function():Boolean { reached++; return false; };
        var manager:Object={count:0};
        pickupApi.prototype.createCollectible.call(manager,"金钱",1,0,0,true,{});
        check(reached==0 && manager.count==0,"Lee blocks direct native collectible creation before any allocation or item validation");
        run.bookId="cf1";
        pickupApi.prototype.createCollectible.call(manager,"金钱",1,0,0,true,{});
        check(reached==1 && manager.count==0,"other books still enter the normal collectible creation pipeline");
        validationApi.meetsRequirements=originalValidation;run.bookId="lee-trial";
        api["drainPower"](room,1/12,6);clock.activeFrames++;api.tick();
        check(room.lightProgress>0 && room.lightProgress<1/12 && ws.minLight<7,"each discharge fades across frames instead of snapping");
        var held:Number=ws.minLight;_root.暂停=true;clock.activeFrames++;api.tick();
        check(ws.minLight==held && room.lightStep==1,"pausing holds the in-flight lighting fade");_root.暂停=false;
        for(n=1;n<6;n++){clock.activeFrames++;api.tick();}
        check(room.lightProgress==1/12 && Math.abs(ws.minLight-7*11/12)<.00001,"first discharge stops at its share of the outage");
        api["drainPower"](room,1,6);
        for(n=0;n<6;n++){clock.activeFrames++;api.tick();}
        check(room.lightProgress==1 && ws.minLight==0 && Math.abs(ws.maxLight-.8)<.00001,"last discharge reaches exact outage with no tail jump");
        api["_room"]=saved.room;api["_watch"]=saved.watch;session["_run"]=saved.run;
        _root._saveExt=saved.ext;_root.gameworld=saved.world;_root.savePath=saved.slot;
        _root.控制目标=saved.control;_root.暂停=saved.pause;_root.场景转换中=saved.transition;
    }
    private static function storyDialogueRoutes():Void {
        var api:Object = org.flashNight.arki.scene.LeeAssaultService;
        var state:Object = LeeAssaultRules.create(4,12,24);
        var sample:Object = {index:0,state:state};
        check(api["entryPage"](sample)=="lee-entry-0" && api["clearedPage"](sample)=="lee-clear-0",
            "first room danger precedes any training speculation");
        check(api["awakenedPage"](sample)=="lee-after-0-dodged","perfect dodge uses observation rather than a bodily sensation");
        room(state,0,1); LeeAssaultRules.resolve(state,0,true);
        check(api["awakenedPage"](sample)=="lee-after-0","actual first-room hit unlocks the training thought only after lightning");
        sample.index=1;
        check(api["clearedPage"](sample)=="lee-clear-1","past contact permits a deliberate second-room attempt");
        room(state,1,12); LeeAssaultRules.resolve(state,1,true);
        check(api["awakenedPage"](sample)=="lee-after-1","partial progress does not speak as awakened");
        sample.index=2; room(state,2,11); LeeAssaultRules.resolve(state,2,true);
        check(api["awakenedPage"](sample)=="lee-awaken-late","1+12+11 hits resolves the third-room awakening line");
        sample.index=3;
        check(api["entryPage"](sample)=="lee-entry-3-late","late awakening remembers the restraint at boss entry");
        state=LeeAssaultRules.create(4,12,24); sample.state=state; sample.index=1;
        check(api["clearedPage"](sample)=="lee-clear-1-observe" && api["awakenedPage"](sample)=="lee-after-1-dodged",
            "zero-hit player does not claim to feel power gathering");
        room(state,0,12); LeeAssaultRules.resolve(state,0,true); room(state,1,12); LeeAssaultRules.resolve(state,1,true);
        check(api["awakenedPage"](sample)=="lee-awaken-early","full first two traps produce the early awakening line");
        LeeAssaultRules.respawn(state); sample.index=2;
        check(api["entryPage"](sample)=="lee-entry-2-awakened" && api["clearedPage"](sample)=="lee-clear-2-awakened"
            && api["awakenedPage"](sample)=="lee-after-2-awakened","later revive preserves all earned confident third-room dialogue");
        sample.index=3;
        check(api["entryPage"](sample)=="lee-entry-3-early","early boss entry never claims Lee just broke restraints");
        state=LeeAssaultRules.create(4,12,24); sample.state=state; LeeAssaultRules.respawn(state);
        sample.index=0;
        check(api["awakenedPage"](sample)=="lee-after-0-revived","pre-awakening revival never promises a breakthrough");
        sample.index=1;
        check(api["entryPage"](sample)=="lee-entry-1-revived" && api["clearedPage"](sample)=="lee-clear-1-revived"
            && api["awakenedPage"](sample)=="lee-after-1-revived","revival route stays consistent through room two");
        sample.index=2;
        check(api["entryPage"](sample)=="lee-entry-2-revived" && api["clearedPage"](sample)=="lee-clear-2-revived"
            && api["awakenedPage"](sample)=="lee-after-2","unawakened survivor keeps defiance through the historical ending");
    }
    private static function storyComicContinuations():Void {
        var api:Object=org.flashNight.arki.scene.LeeAssaultService;
        var comics:Object=org.flashNight.arki.scene.BookComicService;
        var session:Object=org.flashNight.arki.scene.StageRunSession;
        var saved:Object={room:api["_room"],watch:api["_watch"],allow:api["_allowClear"],begin:comics.begin,
            ext:_root._saveExt,world:_root.gameworld,slot:_root.savePath,control:_root.控制目标,
            pause:_root.暂停,transition:_root.场景转换中,run:session["_run"]};
        var selected:String, follow:Function, clears:Number=0, advances:Number=0, finishes:Number=0;
        comics.begin=function(id:String, continuation:Function):Boolean { selected=id; follow=continuation; return true; };
        var owner:Object={}, run:Object={outcome:"active"}, clock:Object={activeFrames:0};
        var actor:Object={__enemyActionPlayer:true,hp:100,hp满血值:100};
        var world:Object={__stageReturnWorldIdentity:owner,hero:actor};
        var state:Object=LeeAssaultRules.create(4,12,24);
        var sample:Object={phase:"recover",index:2,run:run,slot:"lee.story.fixture",owner:owner,world:world,
            state:state,config:{dialogues:{},recoveryFrames:180},lastFrame:-1,serial:0,
            manager:{clearStage:function():Void { clears++; },nextStage:function():Void { advances++; },
                finishStage:function():Void { finishes++; run.outcome="victory"; }}};
        api["_room"]=sample; session["_run"]=clock;
        _root._saveExt={bookRun:run}; _root.gameworld=world; _root.savePath=sample.slot;
        _root.控制目标="hero"; _root.暂停=_root.场景转换中=false;
        state.awakened=true; state.awakeningRoom=1; state.revives=1;
        api.tick();
        check(selected=="lee-ambush" && sample.phase=="comic" && advances==0,"early route opens interception page and waits for its real continuation");
        follow(); follow(); clock.activeFrames++; api.tick();
        check(clears==1 && advances==1 && finishes==0 && state.revives==1,"duplicate comic confirmation advances early route once without synthetic revive");
        clock.activeFrames++; api.tick();
        check(advances==1,"open phase cannot replay the chapter advance");
        sample.phase="recover"; state.awakeningRoom=2; clock.activeFrames++; api.tick();
        check(selected=="lee-breakout","late route plays one combined capture-and-breakout page");
        var lateFollow:Function=follow;
        _root.gameworld={__stageReturnWorldIdentity:{}}; lateFollow();
        check(sample.phase=="comic" && advances==1,"retired world's continuation cannot move the replacement scene");
        _root.gameworld=world; lateFollow(); clock.activeFrames++; api.tick();
        check(advances==2 && state.awakened,"late route continues with its existing ability, not a comic-granted awakening");
        sample.phase="recover"; state.awakened=false; state.awakeningRoom=-1; clock.activeFrames++; api.tick();
        check(selected=="lee-ending-normal" && finishes==0,"normal route plays its own capture once and waits before completion");
        follow(); follow(); clock.activeFrames++; api.tick();
        check(finishes==1 && advances==2 && state.ending=="normal" && state.revives==1,
            "normal comic ends in room three once, without opening the boss or consuming a coin");
        api["_room"]=saved.room; api["_watch"]=saved.watch; api["_allowClear"]=saved.allow; comics.begin=saved.begin;
        session["_run"]=saved.run; _root._saveExt=saved.ext; _root.gameworld=saved.world; _root.savePath=saved.slot;
        _root.控制目标=saved.control; _root.暂停=saved.pause; _root.场景转换中=saved.transition;
    }

    public static function runAllTests():Void {
        passed=0; failed=0;
        var state:Object=LeeAssaultRules.create(4,12,24);
        check(!LeeAssaultRules.recordHit(state,0,0,250),"cannot count a pre-clear hit");
        room(state,0,12);
        check(state.hits==12 && state.damage==3000,"one complete trap costs 3000 actual HP");
        check(!LeeAssaultRules.recordHit(state,0,0,250) && state.hits==12,"duplicate callback cannot grant progress");
        check(!LeeAssaultRules.resolve(state,0,true) && state.rooms[0].powerOff,"first trap cuts power without awakening");
        check(!LeeAssaultRules.recordHit(state,0,1,250),"retired trap rejects late hits");
        room(state,1,12);
        check(LeeAssaultRules.resolve(state,1,true) && state.awakened && state.awakeningRoom==1,"full first two rooms awaken exactly at second end");
        check(!LeeAssaultRules.resolve(state,1,true),"repeat completion cannot awaken twice");
        LeeAssaultRules.respawn(state);
        check(state.awakened && state.revives==1,"later revive preserves an earned awakening");
        state=LeeAssaultRules.create(4,12,24); room(state,0,11); LeeAssaultRules.resolve(state,0,true); room(state,1,12);
        check(!LeeAssaultRules.resolve(state,1,true) && state.hits==23,"dodging one bolt does not get topped up");
        state=LeeAssaultRules.create(4,12,24); room(state,0,12); LeeAssaultRules.resolve(state,0,true); room(state,1,12);
        check(!LeeAssaultRules.resolve(state,1,false),"lethal final bolt cannot awaken a dead player");
        state=LeeAssaultRules.create(4,12,24); room(state,0,12); LeeAssaultRules.resolve(state,0,true); LeeAssaultRules.respawn(state); room(state,1,12);
        check(!LeeAssaultRules.resolve(state,1,true),"revive before awakening loses eligibility");
        var actor:Object={等级:35,魔法抗性:{冲:70},damageTakenMultiplier:1};
        var solid:Number=LeeAssaultRules.lightningSolid(actor,250);
        check(Math.floor(solid*.73)==250,"canonical Lee uses fallback electric resistance, not his 70 impact resistance");
        actor.魔法抗性.电=300;
        check(LeeAssaultRules.lightningSolid(actor,250)==0,"electric immunity remains immune");
        actor.魔法抗性.电=20; actor.damageTakenMultiplier=.5;
        check(Math.floor(LeeAssaultRules.lightningSolid(actor,250)*.8*.5)==250,"damage multiplier is calibrated without bypassing resistance");
        var fresh:Object=LeeAssaultRules.create(4,12,24);
        check(fresh.hits==0 && fresh.revives==0 && !fresh.awakened,"a new journey inherits no prior run state");
        storyDialogueRoutes();
        storyComicContinuations();
        finalLightingLifecycle();
        finalBattleRecovery();
        powerAndLootScope();
        trace("LeeAssaultRulesTest Tests Passed: "+passed);
        trace("LeeAssaultRulesTest Tests Failed: "+failed);
    }
}
