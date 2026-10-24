import org.flashNight.arki.scene.*;
import org.flashNight.neur.Event.LifecycleEventDispatcher;

/** 真实 AVM1/MovieClip 夹具；不加载资源或写入档案。 */
class org.flashNight.arki.scene.Cf6BossEncounterTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var spawned:Array;
    private static var delayed:Boolean;
    private static var closes:Number;
    private static var clears:Number;
    private static function check(value:Boolean,label:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] Cf6BossEncounter: "+label); }
    }
    private static function actor(name:String,hp):MovieClip {
        var unit:MovieClip=_root.gameworld.createEmptyMovieClip(name,_root.gameworld.getNextHighestDepth());
        unit.hp=hp; unit.hp满血值=100; return unit;
    }
    private static function spawn(id:String,name:String,p:Object):Void {
        spawned.push({name:name,p:p}); if (delayed) return;
        arrive(spawned[spawned.length-1]);
    }
    private static function arrive(entry:Object):MovieClip {
        var unit:MovieClip=actor(entry.name,100);
        for (var key:String in entry.p) unit[key]=entry.p[key];
        _root.gameworld.dispatcher.publish("UnitSpawn",entry.name); return unit;
    }
    private static function frames(n:Number):Void {
        for (var i:Number=0;i<n;i++) _root.gameworld.__cf6BossEncounter.onEnterFrame();
    }
    private static function death(name:String):Void {
        _root.gameworld[name].hp=0; _root.gameworld.dispatcher.publish("UnitDeath",name);
    }
    private static function plan():Object {
        return {instanceName:"cf6Boss_A06",maxAlive:2,maxRanged:1,intervalFrames:1,groups:[
            {hpRatio:1,enemies:[{Type:"兵种461",Level:60,Quantity:3,ranged:false,SpawnIndex:"left",Parameters:{掉落物:[{名字:"药",概率:100}]}}]},
            {hpRatio:0.5,enemies:[{Type:"兵种466",Level:60,Quantity:2,ranged:true,SpawnIndex:"right",Parameters:{}}]}]};
    }
    private static function setup(p:Object,withoutBoss:Boolean):Void {
        Cf6BossEncounter.cancel(); _root.gameworld.removeMovieClip();
        _root.gameworld=_root.createEmptyMovieClip("cf6BossFixture",9286);
        _root.gameworld.dispatcher=new LifecycleEventDispatcher(_root.gameworld);
        _root.savePath="bookrun.fixture"; _root.当前关卡名="书中历险-毒刺行动";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",slot:_root.savePath,seed:17,startedAt:100,outcome:"active"}};
        _root.暂停=false; _root.场景转换中=false; actor("hero",100); if(withoutBoss!==true)actor(p.instanceName,100);
        spawned=[]; delayed=false; closes=0; clears=0;
        var manager:Object=StageManager, wheel:Object=WaveSpawner;
        manager.instance={currentStage:6,isActive:true,isFinished:false,isFailed:false,isCleared:false,
            clearStage:function():Void { clears++; this.isCleared=true; }};
        wheel.instance={spawnEnemy:spawn,close:function():Void { closes++; }};
        _root.兵种库={兵种461:{兵种名:"fixture",是否为敌人:true},兵种466:{兵种名:"fixture",是否为敌人:true},兵种469:{兵种名:"fixture",是否为敌人:true}};
        Cf6BossEncounter.start(_root.gameworld,StageReturnFlow.worldIdentity(_root.gameworld),p);
    }
    private static function lifecycle():Void {
        var p:Object=plan(); setup(p); frames(1);
        var focus:Object=org.flashNight.arki.hud.FocusTargetHudService.snapshot();
        check(focus.role=="boss" && focus.hp[0]===100 && focus.hp[1]===100,"encounter binds actual boss life to shared focus HUD");
        check(spawned.length==1,"initial finite queue emits one actor");
        check(spawned[0].p.产生源=="无" && spawned[0].p.publishStageEvent===true,"support excluded from native wave count with events enabled");
        check(typeof spawned[0].p.cf6BossOwnerToken=="string","ownership token survives StageEvent cloning");
        Cf6BossEncounter.start(_root.gameworld,StageReturnFlow.worldIdentity(_root.gameworld),p); frames(1);
        check(spawned.length==1,"same scope start is idempotent"); frames(10);
        check(spawned.length==2,"live cap holds expanded Quantity");
        var first:String=spawned[0].name; death(first); frames(1);
        check(spawned.length==3,"one normal death releases one slot");
        check(_root.gameworld[first].掉落物.length==1 && _root.gameworld[first].已加经验值!==true,"normal dead actor keeps normal loot and XP");
        check(spawned[0].name!=spawned[1].name && spawned[1].name!=spawned[2].name,"expanded quantities use unique names");
        _root.gameworld[p.instanceName].hp=40; death(spawned[1].name); frames(3);
        check(org.flashNight.arki.hud.FocusTargetHudService.snapshot().hp[0]===40,"focus HUD follows actual boss damage without a second life value");
        check(spawned.length==4,"second HP group releases a ranged actor");
        death(spawned[2].name); frames(20);
        check(spawned.length==4,"ranged cap blocks second ranged even with free slot");
        death(spawned[3].name); frames(2);
        check(spawned.length==5,"ranged death releases final finite entry");
        death(spawned[4].name); frames(100);
        check(spawned.length==5,"queue never refills after full exhaustion");
        death(p.instanceName); frames(10);
        check(clears==1 && closes==1,"boss clear and spawner close happen once");
        check(org.flashNight.arki.hud.FocusTargetHudService.snapshot()==null,"victory clears only encounter focus lease");
        check(_root.gameworld[first].掉落物.length==1,"victory preserves prior normal deaths and drops");
    }
    private static function boundaries():Void {
        var p:Object=plan(); setup(p); delayed=true; frames(30);
        check(spawned.length==2,"pending initialization consumes live slots");
        var late:Object=spawned[0]; death(p.instanceName); arrive(late);
        check(_root.gameworld[late.name]==undefined,"late owned spawn is retired after boss death");
        check(clears==1 && closes==1,"late spawn cannot produce another victory");
        setup(p); frames(1); var name:String=spawned[0].name;
        _root.gameworld[name].removeMovieClip(); var foreign:MovieClip=actor(name,100); foreign.掉落物=[1];
        death(p.instanceName);
        check(_root.gameworld[name]!=undefined && foreign.掉落物.length==1,"same pathname foreign replacement survives cleanup");
        setup(p); _root.gameworld[p.instanceName].hp=undefined; frames(10);
        check(clears==0 && spawned.length==0,"undefined boss HP is not death");
        _root.gameworld[p.instanceName].hp=NaN; _root.gameworld.dispatcher.publish("UnitDeath",p.instanceName); frames(10);
        check(clears==0 && spawned.length==0,"NaN HP and fake death event cannot win");
        _root.gameworld[p.instanceName].hp=100; _root.gameworld.dispatcher.publish("UnitDeath",p.instanceName);
        check(clears==0,"positive HP ignores fake boss death event");
        _root.gameworld[p.instanceName].removeMovieClip(); actor(p.instanceName,0); frames(10);
        check(clears==0,"replacement boss cannot borrow original binding");
        setup(p); _root.暂停=true; frames(10);
        check(spawned.length==0,"pause holds queue"); _root.暂停=false;
        _root.gameworld.hero.hp=NaN; frames(10); check(spawned.length==0,"unknown hero HP holds queue");
        _root.gameworld.hero.hp=0; frames(10); check(spawned.length==0,"dead hero holds queue");
        _root.gameworld.hero.hp=100; frames(1); check(spawned.length==1,"living hero resumes finite queue");
        setup(p); _root.场景转换中=true; frames(10); check(spawned.length==0,"transition holds queue");
    }
    private static function scopes():Void {
        var p:Object=plan(); setup(p); frames(1); var old:String=spawned[0].name;
        StageManager.instance.currentStage++; frames(1);
        check(clears==0 && closes==0 && _root.gameworld[old]==undefined,"stage change cancels only owned adds without victory");
        setup(p); frames(1); _root.savePath="foreign"; frames(1); check(clears==0 && closes==0,"slot change cannot win");
        setup(p); _root._saveExt.bookRun.routeId="foreign"; frames(1); check(spawned.length==0 && clears==0,"route mutation cancels");
        setup(p); _root._saveExt.bookRun.bookId="repair-campus"; frames(1); check(spawned.length==0 && clears==0,"book mutation cancels");
        setup(p); _root._saveExt.bookRun={bookId:"cf6-sting",routeId:"historical",slot:_root.savePath,outcome:"active"}; frames(1);
        check(spawned.length==0 && clears==0,"replacement run cannot inherit controller");
        setup(p); _root._saveExt=org.flashNight.gesh.object.PersistedSnapshot.clone(_root._saveExt); frames(1);
        check(spawned.length==1 && clears==0,"same-run reward commit clone retains finite reinforcement queue");
        setup(p); _root._saveExt.bookRun.seed=18; frames(1);
        check(spawned.length==0 && clears==0,"same-slot changed seed cannot inherit controller");
        setup(p); _root._saveExt.bookRun.startedAt=101; frames(1);
        check(spawned.length==0 && clears==0,"same-slot changed start time cannot inherit controller");
        setup(p); _root._saveExt.bookRun.planSeed=19; frames(1);
        check(spawned.length==0 && clears==0,"changed debug plan cannot inherit controller");
        setup(p); StageManager.instance.isActive=false; frames(1); check(clears==0 && closes==0,"retreat is cancellation");
        setup(p); var wheelClass:Object=WaveSpawner; wheelClass.instance={spawnEnemy:spawn,close:function():Void { closes++; }};
        frames(1); check(spawned.length==0 && closes==0 && clears==0,"replacement spawner cannot receive old queue or close");
        setup(p); frames(1); old=spawned[0].name;
        var oldClock:Function=_root.gameworld.__cf6BossEncounter.onEnterFrame;
        _root.gameworld.removeMovieClip(); _root.gameworld=_root.createEmptyMovieClip("cf6BossFixture",9286);
        _root.gameworld.dispatcher=new LifecycleEventDispatcher(_root.gameworld); var unit:MovieClip=actor(old,100); unit.掉落物=[1];
        var replacementClock:MovieClip=_root.gameworld.createEmptyMovieClip("__cf6BossEncounter",_root.gameworld.getNextHighestDepth());
        replacementClock.onEnterFrame=function():Void {};
        oldClock(); check(unit._name==old && unit.掉落物.length==1 && clears==0,"same-path world replacement is protected by ordinary identity");
        check(typeof replacementClock.onEnterFrame=="function","old cleanup cannot delete replacement world's frame handler");
        check(org.flashNight.arki.hud.FocusTargetHudService.snapshot()==null,"world retirement clears focus even before old world cleanup can run");
    }
    private static function guardSetup():Object {
        var p:Object=plan(); p.maxAlive=1; p.groups=[{hpRatio:1,enemies:[{Type:"兵种469",Level:60,Quantity:2,ranged:false,SpawnIndex:"left",Parameters:{光头保安变身:true}}]}];
        setup(p); frames(1); var name:String=spawned[0].name; var parent:MovieClip=_root.gameworld[name];
        parent.hp=0; parent.guardTransform={world:_root.gameworld,name:name+"__tyrant",active:true,attempted:true,level:60,side:true,source:"无"}; frames(1);
        return {plan:p,name:name,phase:parent.guardTransform};
    }
    private static function guardChild(g:Object, initialized:Boolean):MovieClip {
        var child:MovieClip=actor(g.phase.name,100);
        child.名字="暴君克隆兽"; child.等级=60; child.是否为敌人=true; child.产生源="无";
        if (initialized) child.兵种="敌人-完全体克隆兽";
        g.phase.child=child; return child;
    }
    private static function guards():Void {
        var g:Object=guardSetup(); frames(20); check(spawned.length==1,"transforming guard retains its live slot");
        var child:MovieClip=guardChild(g,true); frames(1);
        check(child.publishStageEvent===true && typeof child.cf6BossOwnerToken=="string","exact guard successor receives ownership and events");
        death(g.name); frames(10); check(spawned.length==1,"parent noCount death does not free logical slot");
        child.掉落物=[1]; death(g.phase.name); frames(2);
        check(spawned.length==2 && child.掉落物.length==1,"successor death frees one slot and preserves normal loot");
        g=guardSetup(); child=guardChild(g,true); frames(1);
        death(g.plan.instanceName);
        check(_root.gameworld[g.name]==undefined && _root.gameworld[g.phase.name]==undefined,"boss priority retires both transforming parent and child");
        g=guardSetup(); child=guardChild(g,true); frames(1);
        child.removeMovieClip(); var foreign:MovieClip=actor(g.phase.name,100); foreign.兵种="敌人-完全体克隆兽"; foreign.掉落物=[1];
        death(g.plan.instanceName);
        check(foreign._name==g.phase.name && foreign.掉落物.length==1,"replacement guard child is not claimed by name");
        g=guardSetup(); child=guardChild(g,false); death(g.plan.instanceName);
        check(_root.gameworld[g.phase.name]==undefined,"uninitialized exact successor is also retired at boss death");
        g=guardSetup(); child=actor(g.phase.name,100); child.名字="foreign"; g.phase.child=child; death(g.plan.instanceName);
        check(child._name==g.phase.name,"phase reference with foreign initialization context is not claimed");
        g=guardSetup(); Cf6BossEncounter.cancel(); frames(10);
        check(_root.gameworld[g.name]==undefined && clears==0 && closes==0,"cancel during transform removes owned parent without winning");
    }
    private static function podFixture():Object {
        var w:MovieClip=_root.gameworld,managerClass:Object=org.flashNight.arki.scene.StageManager;
        var room:Object={world:w,owner:StageReturnFlow.worldIdentity(w),stageManager:managerClass.instance,
            stageIndex:managerClass.instance.currentStage,slot:String(_root.savePath),stageName:_root.当前关卡名,
            runIdentity:_root._saveExt.bookRun,mapId:"A17",phase:"combat"};
        w.__cf6Mechanism=room;
        var session:Object={room:room,manager:org.flashNight.gesh.depth.DepthManager.instance,rows:[],closed:false,failed:false};
        room.interactivePropsSession=session;
        var h:MovieClip=w.createEmptyMovieClip("podFixture",w.getNextHighestDepth()),token:Object={};h.__cf6InteractiveOwner=token;
        var row:Object={spec:{id:"pod-a",kind:"pod",spawnAuthority:"boss"},name:h._name,holder:h,token:token,phase:"idle",attempted:false};
        session.rows.push(row);return row;
    }
    private static function pods():Void {
        var p:Object=plan();p.maxAlive=4;p.intervalFrames=1;
        p.groups=[{hpRatio:1,enemies:[{Type:"兵种461",Level:1,Quantity:1,ranged:false,podId:"pod-a"},
            {Type:"兵种461",Level:1,Quantity:4,ranged:false}]}];
        setup(p);var row:Object=podFixture();frames(10);
        check(spawned.length==4 && spawned[0].p.cf6PodId==undefined,"unready pod does not block ordinary support behind it");
        row.phase="ready-to-spawn";frames(5);
        check(spawned.length==4 && !row.attempted,"ready pod preserves original four-person live cap before claim");
        death(spawned[0].name);frames(2);
        check(spawned.length==5 && spawned[4].p.cf6PodId=="pod-a","reserved pod keeps exact id through original StageEvent");
        check(row.attempted && row.bossToken===spawned[4].p.cf6BossOwnerToken && row.spawnName===spawned[4].name,"pod claim binds original issued owner and unique actor name");
        death(spawned[4].name);frames(20);
        check(spawned.length==5,"consumed pod budget never refills");
        setup(p);row=podFixture();row.phase="ready-to-spawn";delayed=true;frames(1);
        check(row.attempted && spawned.length==1,"unknown attach reserves original live slot and pod claim once");
        death(p.instanceName);arrive(spawned[0]);frames(3);
        check(row.phase=="cancelled" && _root.gameworld[spawned[0].name]==undefined,"boss victory cancels pending pod and retires late owned actor");
        setup(p);row=podFixture();death(p.instanceName);frames(5);
        check(!row.attempted && row.phase=="cancelled" && spawned.length==0,"boss death before proximity consumes no pod spawn");
        setup(p);row=podFixture();row.phase="ready-to-spawn";
        row.holder.removeMovieClip();_root.gameworld.createEmptyMovieClip("podFixture",_root.gameworld.getNextHighestDepth());frames(1);
        check(spawned.length==1 && spawned[0].p.cf6PodId==undefined,"same-name pod replacement cannot borrow ready claim");
    }
    private static function elderPlan():Object {
        var p:Object=plan();p.instanceName="cf6Boss_A20";
        p.nextPhase={instanceName:"cf6Boss_A20__elderbot",maxAlive:1,maxRanged:1,intervalFrames:1,
            groups:[{hpRatio:1,enemies:[{Type:"兵种466",Level:60,Quantity:2,ranged:true,SpawnIndex:"right",Parameters:{}}]}]};
        return p;
    }
    private static function elderMetadata(p:Object):Object {
        var w:MovieClip=_root.gameworld,parent:MovieClip=w[p.instanceName];
        w.__elderWorldIdentity={};parent.elderIdentity={};parent.老头变身=true;
        var phase:Object={world:w,worldIdentity:w.__elderWorldIdentity,parentIdentity:parent.elderIdentity,
            spawnIdentity:{},name:p.nextPhase.instanceName,level:60,side:true,source:"fixture-main-wave",
            attempted:false,retired:false};
        parent.elderTransform=phase;return phase;
    }
    private static function elderChild(phase:Object):MovieClip {
        var child:MovieClip=actor(phase.name,100);phase.attempted=true;phase.child=child;
        child.elderSpawnIdentity=phase.spawnIdentity;child.兵种="敌人-CF6老头机器人";
        child.等级=phase.level;child.是否为敌人=phase.side;child.产生源=phase.source;
        child.死亡检测=function(options:Object):Void {
            _root.gameworld.dispatcher.publish("UnitRemoved",this._name);this.removeMovieClip();
        };
        child.version=51;child._visible=false;return child;
    }
    private static function elders():Void {
        var p:Object=elderPlan();setup(p);frames(1);
        var phase:Object=elderMetadata(p), first:Object=spawned[0];
        delayed=true;frames(2);var late:Object=spawned[1];delayed=false;
        check(Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),"two-form room rejects early clear while human is alive");
        check(Cf6MapMechanism.interceptClear(StageManager.instance,_root.gameworld),"actual map clear interceptor consumes the active finale gate");
        death(p.instanceName);frames(1);
        check(clears==0 && closes==0,"human death never clears room or closes main spawner");
        check(org.flashNight.arki.hud.FocusTargetHudService.snapshot()==null,"transform gap clears first form focus instead of showing stale HP");
        check(_root.gameworld[first.name]==undefined,"human supports retire before transformation without a second budget");
        arrive(late);check(_root.gameworld[late.name]==undefined,"late first-form support remains tombstoned through phase transition");
        var child:MovieClip=elderChild(phase);frames(5);
        check(spawned.length==2 && child.cf6BossIdentity==undefined,"initializing successor cannot activate robot support");
        child.__unitInitializedVersion=child.version;phase.retired=true;child._visible=true;
        _root.暂停=true;frames(5);
        check(child.cf6BossIdentity==undefined,"paused successor handoff waits without replay");
        _root.暂停=false;frames(2);
        check(child.cf6BossIdentity!=undefined && spawned.length==3,"native initialized visible successor binds and releases phase-two budget once");
        check(org.flashNight.arki.hud.FocusTargetHudService.snapshot().hp[0]===child.hp,"ready successor owns the second form focus binding");
        check(spawned[2].p.cf6BossOwnerToken==first.p.cf6BossOwnerToken && child.产生源=="fixture-main-wave",
            "support ownership stays local while native successor retains its counted source");
        _root.gameworld.dispatcher.publish("UnitDeath",p.instanceName);frames(4);
        check(clears==0 && closes==0 && spawned.length==3,"late parent death cannot clear robot phase or bypass ranged cap");
        death(spawned[2].name);frames(2);
        check(spawned.length==4,"robot support consumes its original finite second entry");
        death(phase.name);frames(10);
        check(clears==0 && closes==0,"robot HP death waits for native death presentation and removal");
        check(Cf6MapMechanism.interceptClear(StageManager.instance,_root.gameworld),"actual map interceptor holds the final death animation before terminal callback");
        // Logical completion receipt only; the field-native suite owns the actual 111-frame asset proof.
        var body:Object={_currentframe:111,_totalframes:111};child.man=body;
        body.elderMode="death";body.cf6CorpseFinished=true;body.尸体碎片={cf6Settled:true};
        var api:Object=org.flashNight.arki.scene.Cf6BossEncounter,c:Object=api.active;
        trace("[CF6_FINAL_DEATH_FIXTURE] current="+c.current()+" waiting="+c.elderWaiting
            +" identity="+(child.cf6BossIdentity===c.bossMark)+" frame="+body._currentframe+"/"+body._totalframes);
        child.死亡检测();frames(10);
        check(clears==1 && closes==1,"completed robot death presentation plus native removal clears exactly once");
        check(!Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),"finished finale releases the clear gate");
        p=elderPlan();setup(p);phase=elderMetadata(p);death(p.instanceName);frames(1);child=elderChild(phase);
        child.hp=0;child.__unitInitializedVersion=child.version;child._visible=true;phase.retired=true;frames(2);
        check(child.cf6BossIdentity!=undefined && clears==0,"successor killed during initialization still binds its pending native death presentation");
        p=elderPlan();setup(p);phase=elderMetadata(p);death(p.instanceName);frames(1);child=elderChild(phase);
        child.elderSpawnIdentity={};child.__unitInitializedVersion=child.version;child._visible=true;phase.retired=true;frames(2);
        check(clears==0 && child.cf6BossIdentity==undefined && Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),
            "wrong successor token cannot borrow completion or release the room");
        p=elderPlan();setup(p);phase=elderMetadata(p);death(p.instanceName);frames(1);child=elderChild(phase);
        child.removeMovieClip();var foreign:MovieClip=actor(phase.name,0);frames(3);
        check(clears==0 && foreign._name==phase.name,"same-name successor replacement is preserved and never counted as victory");
        p=elderPlan();setup(p);phase=elderMetadata(p);death(p.instanceName);phase.error="spawn-returned-empty";frames(10);
        check(clears==0 && spawned.length==0,"native unknown spawn result is held without retry or victory");
        StageManager.instance.currentStage++;frames(1);
        check(!Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance) && closes==0,
            "leaving the owning stage cancels the phase without closing another spawner");
    }
    /** UnitSpawn is a real one-argument world event; its production initialization latch is still null at publication. */
    private static function latePrimary(p:Object):MovieClip {
        var unit:MovieClip=actor(p.instanceName,100);
        unit.version=201;unit.__unitInitializedVersion=null;unit.publishStageEvent=true;
        unit.dispatcher=new LifecycleEventDispatcher(unit);
        _root.gameworld.dispatcher.publish("UnitSpawn",unit._name);
        return unit;
    }
    private static function finishPrimaryInitialization(unit:MovieClip):Void {
        // Mirror the exact ordering of StaticInitializer: local event first, completion latch second.
        // Actor/resource initialization itself is a fixture port, not a native-art acceptance claim.
        unit.dispatcher.publish("UnitInitialized",unit);unit.__unitInitializedVersion=unit.version;
    }
    private static function removePrimary(unit:MovieClip):Void {
        _root.gameworld.dispatcher.publish("UnitRemoved",unit._name);unit.removeMovieClip();
    }
    private static function latePrimaryBirth():Void {
        var p:Object=plan();setup(p,true);frames(700);
        check(clears==0 && closes==0 && spawned.length==0,"boss-less mandatory preludes have no boss-bind timeout or premature clear");
        var unit:MovieClip=latePrimary(p);
        check(unit.cf6BossIdentity==undefined && clears==0,"UnitSpawn before completed initialization cannot activate primary boss authority");
        finishPrimaryInitialization(unit);death(p.instanceName);
        check(clears==1 && closes==1 && spawned.length==0,"observed initialized primary dying before first controller tick clears once without support replay");
        removePrimary(unit);frames(5);
        check(clears==1 && closes==1,"same-stack primary death then removal cannot lose or duplicate confirmed victory");

        setup(p,true);unit=actor(p.instanceName,0);unit.version=201;unit.__unitInitializedVersion=201;
        death(p.instanceName);frames(5);
        check(clears==0 && unit.cf6BossIdentity==undefined,"unobserved old corpse cannot acquire primary boss identity");

        setup(p,true);unit=latePrimary(p);death(p.instanceName);frames(5);
        check(clears==0 && unit.cf6BossIdentity==undefined,"observed but unfinished primary cannot certify death");
        finishPrimaryInitialization(unit);frames(1);
        check(clears==1 && closes==1,"completed same birth can reconcile an earlier death without replaying UnitSpawn");

        setup(p,true);unit=latePrimary(p);unit.version=202;finishPrimaryInitialization(unit);death(p.instanceName);frames(5);
        check(clears==0 && unit.cf6BossIdentity==undefined,"changed initialization version cannot borrow a captured birth");

        setup(p,true);unit=latePrimary(p);unit.removeMovieClip();unit=actor(p.instanceName,0);
        unit.version=201;unit.__unitInitializedVersion=201;death(p.instanceName);frames(5);
        check(clears==0 && unit.cf6BossIdentity==undefined,"same-path replacement with copied version lacks the original plain birth token");

        setup(p,true);unit=latePrimary(p);unit.__cf6BossBirthOwner={};finishPrimaryInitialization(unit);death(p.instanceName);frames(5);
        check(clears==0 && unit.cf6BossIdentity==undefined,"foreign birth token cannot authorize the original pending candidate");
    }
    private static function lateElderBirth():Void {
        var p:Object=elderPlan();setup(p,true);frames(700);
        check(clears==0 && closes==0 && Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),
            "two-form boss-less preludes wait without consuming the native transform timeout");
        var parent:MovieClip=latePrimary(p);
        check(parent.cf6BossIdentity==undefined && clears==0,"late elder UnitSpawn remains initialization-pending");
        finishPrimaryInitialization(parent);var phase:Object=elderMetadata(p);death(p.instanceName);
        var api:Object=Cf6BossEncounter,c:Object=api.active;
        check(c.elderStarted && c.elderWaiting && clears==0 && closes==0,
            "same-stack late human death enters native successor wait without clearing the room");
        var child:MovieClip=elderChild(phase);child.__unitInitializedVersion=child.version;child._visible=true;phase.retired=true;
        removePrimary(parent);frames(2);
        check(child.cf6BossIdentity!=undefined && clears==0 && closes==0,
            "exact native phase captured before first controller tick survives parent removal");
        death(phase.name);frames(3);
        check(clears==0 && Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),
            "late-born robot HP death still waits for native final animation and removal");
        child.man={_currentframe:111,_totalframes:111,elderMode:"death",cf6CorpseFinished:true,尸体碎片:{cf6Settled:true}};
        child.死亡检测();frames(5);
        check(clears==1 && closes==1 && !Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),
            "late-born two-form encounter clears once only after the original native terminal receipt");

        setup(p,true);parent=latePrimary(p);finishPrimaryInitialization(parent);phase=elderMetadata(p);phase.parentIdentity={};death(p.instanceName);
        child=elderChild(phase);child.__unitInitializedVersion=child.version;child._visible=true;phase.retired=true;removePrimary(parent);frames(3);
        check(clears==0 && child.cf6BossIdentity==undefined && Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),
            "foreign native parent identity cannot be rescued by a late birth receipt");

        setup(p,true);parent=actor(p.instanceName,0);parent.version=201;parent.__unitInitializedVersion=201;
        phase=elderMetadata(p);death(p.instanceName);child=elderChild(phase);child.__unitInitializedVersion=child.version;child._visible=true;phase.retired=true;
        removePrimary(parent);frames(3);
        check(clears==0 && child.cf6BossIdentity==undefined && Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),
            "unobserved dead elder and successor metadata cannot manufacture a valid first form");

        setup(p,true);parent=latePrimary(p);finishPrimaryInitialization(parent);phase=elderMetadata(p);death(p.instanceName);
        child=elderChild(phase);child.elderSpawnIdentity={};child.__unitInitializedVersion=child.version;child._visible=true;phase.retired=true;
        removePrimary(parent);frames(3);
        check(clears==0 && child.cf6BossIdentity==undefined && Cf6BossEncounter.blocksClear(_root.gameworld,StageManager.instance),
            "late primary observation does not relax the successor spawn-token contract");
    }
    public static function runAllTests():Void {
        passed=0; failed=0;
        var keys:Array=["gameworld","savePath","当前关卡名","_saveExt","暂停","场景转换中","兵种库"];
        var saved:Object={}; for (var i:Number=0;i<keys.length;i++) saved[keys[i]]=_root[keys[i]];
        var manager:Object=StageManager,wheel:Object=WaveSpawner;
        var beforeManager:Object=manager.instance,beforeWheel:Object=wheel.instance;
        var target:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var beforeFind:Function=target.findHero; target.findHero=function():MovieClip { return _root.gameworld.hero; };
        _root.gameworld=undefined;
        try { lifecycle(); boundaries(); scopes(); guards(); pods(); elders(); latePrimaryBirth(); lateElderBirth(); }
        finally {
            Cf6BossEncounter.cancel(); _root.gameworld.removeMovieClip();
            manager.instance=beforeManager; wheel.instance=beforeWheel; target.findHero=beforeFind;
            for (i=0;i<keys.length;i++) _root[keys[i]]=saved[keys[i]];
        }
        trace("Cf6BossEncounterTest Tests Passed: "+passed);
        trace("Cf6BossEncounterTest Tests Failed: "+failed);
    }
}
