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
    private static function setup(p:Object):Void {
        Cf6BossEncounter.cancel(); _root.gameworld.removeMovieClip();
        _root.gameworld=_root.createEmptyMovieClip("cf6BossFixture",9286);
        _root.gameworld.dispatcher=new LifecycleEventDispatcher(_root.gameworld);
        _root.savePath="bookrun.fixture"; _root.当前关卡名="书中历险-毒刺行动";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",slot:_root.savePath,seed:17,startedAt:100,outcome:"active"}};
        _root.暂停=false; _root.场景转换中=false; actor("hero",100); actor(p.instanceName,100);
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
        check(spawned.length==4,"second HP group releases a ranged actor");
        death(spawned[2].name); frames(20);
        check(spawned.length==4,"ranged cap blocks second ranged even with free slot");
        death(spawned[3].name); frames(2);
        check(spawned.length==5,"ranged death releases final finite entry");
        death(spawned[4].name); frames(100);
        check(spawned.length==5,"queue never refills after full exhaustion");
        death(p.instanceName); frames(10);
        check(clears==1 && closes==1,"boss clear and spawner close happen once");
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
    public static function runAllTests():Void {
        passed=0; failed=0;
        var keys:Array=["gameworld","savePath","当前关卡名","_saveExt","暂停","场景转换中","兵种库"];
        var saved:Object={}; for (var i:Number=0;i<keys.length;i++) saved[keys[i]]=_root[keys[i]];
        var manager:Object=StageManager,wheel:Object=WaveSpawner;
        var beforeManager:Object=manager.instance,beforeWheel:Object=wheel.instance;
        var target:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var beforeFind:Function=target.findHero; target.findHero=function():MovieClip { return _root.gameworld.hero; };
        _root.gameworld=undefined;
        try { lifecycle(); boundaries(); scopes(); guards(); }
        finally {
            Cf6BossEncounter.cancel(); _root.gameworld.removeMovieClip();
            manager.instance=beforeManager; wheel.instance=beforeWheel; target.findHero=beforeFind;
            for (i=0;i<keys.length;i++) _root[keys[i]]=saved[keys[i]];
        }
        trace("Cf6BossEncounterTest Tests Passed: "+passed);
        trace("Cf6BossEncounterTest Tests Failed: "+failed);
    }
}
