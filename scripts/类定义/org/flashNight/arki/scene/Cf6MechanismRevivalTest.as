import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.gesh.depth.DepthManager;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/** Actual room/life methods and MovieClips; memory run, clear, resource and bake ports. No coins or save writes. */
class org.flashNight.arki.scene.Cf6MechanismRevivalTest {
    private static var passed:Number,failed:Number,index:Number,waitFrames:Number;
    private static var cases:Array,currentCase:Object,saved:Object,savedManager:Object,savedRun:Object,savedReturn:Object,savedPush:Object;
    private static var driver:MovieClip;
    private static var savedDepth:DepthManager;
    private static var keys:Array=["gameworld","控制目标","存档系统","savePath","_saveExt","当前关卡名","当前为战斗地图","贴背景图","发布消息","暂停","场景转换中"];
    private static function check(value:Boolean,label:String):Void {
        if(value) passed++;else {failed++;trace("[FAIL] Cf6MechanismRevival: "+label);}
    }
    private static function noop():Void {}
    private static function allow():Boolean {return true;}
    private static function path(mode:String):Object {
        return {mode:mode,fps:30,durationFrames:4,actorReleaseFrame:mode=="arrive"?4:null,
            gate:{x:10,z:20,radius:12},exit:{x:60,z:30},samples:[
            {frame:1,x:10,z:20,visible:true,action:"walk"},
            {frame:2,x:20,z:20,visible:true,action:"walk"},
            {frame:3,x:30,z:20,visible:false,action:"stand"},
            {frame:4,x:40,z:20,visible:false,action:"stand"}]};
    }
    private static function actor(world:MovieClip):MovieClip {
        var h:MovieClip=world.createEmptyMovieClip("hero",world.getNextHighestDepth());
        h.createEmptyMovieClip("man",1);h.createEmptyMovieClip("控制块",2);h.控制块.onEnterFrame=noop;
        h.hp=h.hp满血值=100;h.mp=h.mp满血值=40;h._x=10;h._y=h.Z轴坐标=20;
        h.方向="右";h.攻击模式="长枪";h.状态="长枪站立";h.锁定方向=false;
        h.行走=noop;h.按键控制攻击模式=noop;h.按键检测=allow;
        h.状态改变=function(value:String):Void {this.状态=value;};
        h.方向改变=function(value:String):Void {if(!this.锁定方向)this.方向=value;};
        return h;
    }
    private static function bake(force:Boolean):Void {
        var w:MovieClip=_root.gameworld;
        w.__cf6BackgroundBake={drawCompleted:true,worldIdentity:w.__stageReturnWorldIdentity,sourceUrl:w.场景背景url,background:w.背景};
        w.背景.clear();
    }
    private static function fixture(c:Object):Object {
        var w:MovieClip=_root.createEmptyMovieClip("__cf6RevivalWorld",_root.getNextHighestDepth());
        _root.gameworld=w;w.__stageReturnWorldIdentity={};
        w.createEmptyMovieClip("deadbody",1);w.deadbody.layers=[{}];w.createEmptyMovieClip("效果",2);
        w.createEmptyMovieClip("背景",3);w.背景.beginFill(0);w.背景.moveTo(0,0);w.背景.lineTo(100,0);w.背景.lineTo(100,100);w.背景.lineTo(0,100);w.背景.endFill();
        w.场景背景url="flashswf/backgrounds/cf6/CF6_"+c.map+"_BG.swf";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",slot:String(_root.savePath),seed:23,startedAt:1792550000000}};
        var h:MovieClip=actor(w);
        var manager:Object={gameworld:w,currentStage:0,isActive:true,isFailed:false,isFinished:false,isCleared:false,calls:0};
        manager.clearStage=function():Void {
            if(this.isCleared || org.flashNight.arki.scene.Cf6MapMechanism.interceptClear(this,this.gameworld))return;
            this.calls++;this.isCleared=true;this.gameworld.允许通行=true;
        };
        var managerApi:Object=StageManager;managerApi.instance=manager;
        var life:Object={life:"alive",outcome:"active",revision:1};var lifeApi:Object=StageRunSession;lifeApi._run=life;lifeApi._returnRequested=false;
        var config:Object={layers:[]};
        if(c.map=="A03")config.kind="door";
        if(c.map=="A03" || c.mode=="depart")config.traversal={depart:path("depart")};
        if(c.mode=="arrive")config.traversal={arrive:path("arrive")};
        if(c.sorted===true) {
            config.traversal.arrive.actorSortY=70;
            var dynamicDepth:Number=900000;w.getNextHighestDepth=function():Number {return dynamicDepth++;};
            DepthManager.instance=new DepthManager(w,0,870655,8);DepthManager.instance.calibrate(0,100);
        }
        if(c.map=="A10" || c.map=="A13")config.layers=[{id:"elevator-scroll",role:"elevator-scroll",url:"flashswf/backgrounds/cf6/CF6_"+c.map+"_elevator-scroll.swf",x:0,y:0,depth:0,loopHeight:924.928,clip:[0,0,1024,597.3333]}];
        check(Cf6MapMechanism.beginRoom(w,w.__stageReturnWorldIdentity,c.map,config),c.label+" beginRoom admitted");
        // The test owns deterministic ticks; MovieClipLoader remains real and asynchronous.
        var mechanism:Object=Cf6MapMechanism;delete mechanism.watch.onEnterFrame;
        return {world:w,hero:h,manager:manager,life:life,room:w.__cf6Mechanism,spec:c};
    }
    private static function ticks(count:Number):Void {for(var n:Number=0;n<count;n++)Cf6MapMechanism.tick();}
    private static function execute(f:Object):Void {
        var c:Object=f.spec,s:Object=f.room,h:MovieClip=f.hero,api:Object=Cf6MapMechanism;
        check(!s.failed && s.pending==0,c.label+" actual layer admission complete");
        if(c.mode=="arrive")Cf6MapMechanism.tick();
        else {
            ticks(c.map=="A10" || c.map=="A13"?30:1);
            if(c.mode=="depart") {f.manager.clearStage();Cf6MapMechanism.tick();}
        }
        var t:Object=c.mode=="arrive"?s.arrival:c.mode=="depart"?s.departure:null;
        if(t!=null)check(t.acquired===true,c.label+" actor lease acquired before interruption");
        else check(s.phase==(s.kind=="elevator"?"moving":"combat"),c.label+" normal combat phase reached");
        var beforeLease:Object=t.token;
        if(c.sorted===true)check(t.depthManager===DepthManager.instance && h.__cf6TraversalDepthOwner===beforeLease && h.Z轴坐标==20,
            c.label+" first lease uses real fixed-sort depth without replacing foot coordinates");
        var peer:String=PauseManager.lease(true,"revival-fixture-peer");
        if(c.replace===true) {
            h.removeMovieClip();var replacement:MovieClip=actor(f.world);replacement._visible=false;replacement.状态="foreign";
            var replacementWalk:Function=replacement.行走;Cf6MapMechanism.tick();ticks(8);
            check(replacement._visible===false && replacement.状态=="foreign" && replacement.行走===replacementWalk,c.label+" replacement actor untouched");
            check(replacement.__cf6TraversalOwner==undefined && !f.manager.isCleared,c.label+" replacement cannot inherit traversal or clear");
            check(t.acquired!==true,c.label+" obsolete actor lease released");
            check(PauseManager.isPaused(),c.label+" foreign pause survives replacement cleanup");
            PauseManager.releaseLease(peer);return;
        }
        var frozenRules:Object=t.rules;
        if(c.frozen===true) {
            // Mutate before suspension as well as while dead: the old implementation reread sourceSpec at suspension.
            t.sourceSpec.samples[0].x=999;t.sourceSpec.actorReleaseFrame=1;
        }
        h.hp=0;h.状态="血腥死";StageRunSession.onHeroDeath();Cf6MapMechanism.tick();
        if(c.frozen===true) {
            check(t.rules===frozenRules && t.rules.samples[0].x==10 && t.rules.releaseAt==4 && t.rules.duration==4,
                c.label+" death retains admitted samples, timing and rules identity");
            t.sourceSpec.samples[0].x=777;t.sourceSpec.durationFrames=2;
        }
        check(f.life.life=="dead" && f.life.outcome=="active",c.label+" death changes life only");
        check(PauseManager.isPaused(),c.label+" foreign pause survives death cleanup");
        if(t!=null)check(!t.acquired && h.__cf6TraversalOwner==undefined,c.label+" death releases owned actor lease");
        if(c.sorted===true)check(h.__cf6TraversalDepthOwner==undefined,c.label+" death retires the former depth owner");
        check(h.状态=="血腥死",c.label+" cleanup preserves actual death pose");
        PauseManager.releaseLease(peer);
        h.hp=100;h.mp=40;h._visible=true;h.状态="长枪站立";StageRunSession.onHeroRespawn(h);
        check(f.life.life=="alive" && h===f.world.hero,c.label+" real life authority confirms same actor revival");
        // No beginRoom, SceneReady, spawn replay or persistence reset is allowed here.
        if(c.frozen===true || c.sorted===true) {
            Cf6MapMechanism.tick();
            if(c.frozen===true)check(t.acquired && t.rules.frame==1 && h._x==10 && h.Z轴坐标==20,
                c.label+" revived actor follows frozen first sample after source mutation");
            if(c.sorted===true)check(t.acquired && t.token!==beforeLease && t.depthManager===DepthManager.instance
                    && h.__cf6TraversalDepthOwner===t.token && t.rules.frame==1 && h.Z轴坐标==20,
                c.label+" revived lease owns real depth with a fresh token");
            ticks(7);
        } else ticks(8);
        check(api.active===s && !s.failed,c.label+" same room remains serviceable after revival");
        h._x=10;h._y=h.Z轴坐标=20;f.manager.clearStage();ticks(100);
        check(f.manager.calls==1 && f.manager.isCleared,c.label+" revived room clears exactly once");
        ticks(12);check(f.manager.calls==1,c.label+" late ticks cannot duplicate clear");
        trace("CF6_REVIVAL_CASE "+c.label+" life="+f.life.life+" roomActive="+(api.active===s)+" phase="+s.phase+" clearCalls="+f.manager.calls);
    }
    private static function closeCase():Void {
        Cf6MapMechanism.teardown();
        if(currentCase.world!=undefined)currentCase.world.removeMovieClip();currentCase=null;
        DepthManager.instance=savedDepth;
    }
    public static function poll():Void {
        try {
            if(currentCase==null) {
                if(index>=cases.length){finish();return;}
                currentCase=fixture(cases[index]);waitFrames=0;
            }
            if(currentCase.room.pending>0 && !currentCase.room.failed && waitFrames++<600)return;
            execute(currentCase);closeCase();index++;
        }catch(error){check(false,"case exception "+index+" "+error);closeCase();index++;}
    }
    private static function finish():Void {
        delete driver.onEnterFrame;driver.removeMovieClip();closeCase();
        var managerApi:Object=StageManager;managerApi.instance=savedManager;
        var lifeApi:Object=StageRunSession;lifeApi._run=savedRun;lifeApi._returnRequested=savedReturn;lifeApi.pushState=savedPush;
        for(var i:Number=0;i<keys.length;i++)_root[keys[i]]=saved[keys[i]];
        trace("Cf6MechanismRevivalTest Tests Passed: "+passed);trace("Cf6MechanismRevivalTest Tests Failed: "+failed);
        _root.cf6MechanismRevivalComplete();
    }
    public static function runAllTests():Void {
        savedDepth=DepthManager.instance;
        passed=failed=index=0;saved={};for(var i:Number=0;i<keys.length;i++)saved[keys[i]]=_root[keys[i]];
        var managerApi:Object=StageManager;savedManager=managerApi.instance;
        var lifeApi:Object=StageRunSession;savedRun=lifeApi._run;savedReturn=lifeApi._returnRequested;savedPush=lifeApi.pushState;lifeApi.pushState=noop;
        _root.控制目标="hero";_root.存档系统={};_root.savePath="cf6-revival-memory";_root.当前关卡名="书中历险-毒刺行动";_root.当前为战斗地图=true;
        _root.贴背景图=bake;_root.发布消息=function(value:String):Void {trace(value);};_root.场景转换中=false;
        PauseManager.install();_root.暂停=false;
        cases=[{map:"A01",mode:"combat",label:"ordinary-combat"},{map:"A03",mode:"combat",label:"door-combat"},
            {map:"A10",mode:"combat",label:"elevator10-combat"},{map:"A13",mode:"combat",label:"elevator13-combat"},
            {map:"A04",mode:"arrive",label:"arrive-death",sorted:true},{map:"A03",mode:"depart",label:"depart-death"},
            {map:"A04",mode:"arrive",label:"arrive-replacement",replace:true},{map:"A03",mode:"depart",label:"depart-replacement",replace:true},
            {map:"A04",mode:"arrive",label:"arrive-frozen-spec",frozen:true}];
        currentCase=null;driver=_root.createEmptyMovieClip("__cf6RevivalDriver",_root.getNextHighestDepth());
        driver.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6MechanismRevivalTest.poll();};
    }
}