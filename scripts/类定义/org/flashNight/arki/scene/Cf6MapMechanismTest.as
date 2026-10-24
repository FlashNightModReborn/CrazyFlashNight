import org.flashNight.arki.scene.*;
import org.flashNight.gesh.object.PersistedSnapshot;
import flash.display.BitmapData;

/** Must run in real CS6/TestLoader. Pure steps are supplemented by same-path MovieClip replacement. */
class org.flashNight.arki.scene.Cf6MapMechanismTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var pixelProbe:Object,finished:Boolean,probeSerial:Number=0;
    private static function check(value:Boolean,message:String):Void {
        if(value) passed++;else {failed++;trace("[FAIL] Cf6MapMechanism: "+message);}
    }
    private static function steps(s:Object,count:Number):String {
        var cue:String="";
        for(var i:Number=0;i<count;i++) cue=Cf6MapMechanism.advance(s,false);
        return cue;
    }
    private static function testPhases():Void {
        check(Cf6MapMechanism.knownMap("A07") && !Cf6MapMechanism.knownMap("A21"),"authored vehicle room binds while cutscene stays outside the route");
        check(Cf6MapMechanism.knownMap("tutorial") && Cf6MapMechanism.knownMap("A22"),"tutorial and final map remain supported");
        var ordinary:Object=Cf6MapMechanism.createState("A01",{});
        check(steps(ordinary,1)=="start" && ordinary.phase=="combat","ordinary room begins combat");
        steps(ordinary,500);check(ordinary.phase=="combat","time cannot clear combat");
        ordinary.clearRequested=true;
        check(steps(ordinary,1)=="complete" && ordinary.phase=="ready","ordinary clear delegates once");
        check(steps(ordinary,500)=="","ready never reissues completion");
        var door:Object=Cf6MapMechanism.createState("A03",{kind:"door"});
        steps(door,1);door.clearRequested=true;
        check(steps(door,1)=="hold" && door.phase=="opening","door holds exit while opening");
        steps(door,23);check(door.phase=="opening","door does not finish early");
        check(steps(door,1)=="complete","door releases at frame 24");
        var ids:Array=["A10","A13"];
        for(var e:Number=0;e<ids.length;e++) {
            var lift:Object=Cf6MapMechanism.createState(ids[e],{});
            steps(lift,1);check(lift.phase=="closing",ids[e]+" closes before movement");
            steps(lift,23);check(lift.phase=="closing",ids[e]+" close boundary");
            check(steps(lift,1)=="release" && lift.phase=="moving",ids[e]+" combat during travel");
            var before:Number=lift.travelFrame;
            Cf6MapMechanism.advance(lift,true);
            check(lift.travelFrame==before,ids[e]+" paused travel stays still");
            steps(lift,100);check(lift.phase=="moving",ids[e]+" travel cannot auto-clear enemy waves");
            lift.clearRequested=true;check(steps(lift,1)=="hold",ids[e]+" clear triggers stopping");
            steps(lift,30);check(lift.phase=="opening",ids[e]+" arrival opens door");
            check(steps(lift,24)=="complete",ids[e]+" arrival delegates standard clear");
        }
        var transfer:Object=Cf6MapMechanism.createState("A06",{});
        steps(transfer,1);transfer.clearRequested=true;
        check(steps(transfer,1)=="complete" && transfer.phase=="ready","A06 clears without the obsolete driving text substitute");
        check(steps(transfer,90)=="","A06 does not repeat clear while the real A07 waits on its own route");
        var vehicle:Object=Cf6MapMechanism.createState("A07",{});vehicle.clearRequested=true;
        check(vehicle.kind=="vehicle" && steps(vehicle,1000)=="","empty wave and elapsed time cannot finish A07");
        check(vehicle.phase=="loading" && !vehicle.delivered,"only the live vehicle service can deliver its tail collision");
        var transform:Object=Cf6MapMechanism.createState("A20",{});
        steps(transform,1);transform.clearRequested=true;steps(transform,1);
        steps(transform,179);check(transform.phase=="transform","A21 keeps A20 gate closed");
        check(steps(transform,1)=="complete","A21 returns only once to standard A20 clear");
        var finalState:Object=Cf6MapMechanism.createState("A22",{});
        steps(finalState,1);finalState.clearRequested=true;
        check(steps(finalState,1)=="complete","A22 has no second transform branch");
        var failedState:Object=Cf6MapMechanism.createState("A10",{});
        failedState.failed=true;failedState.clearRequested=true;
        check(steps(failedState,1000)=="" && failedState.phase=="loading","failure never degrades to completion");
    }
    private static function fixture():MovieClip {
        var w:MovieClip=_root.createEmptyMovieClip("__cf6FixtureWorld",9289);
        _root.gameworld=w;
        w.createEmptyMovieClip("hero",10);w.hero.hp=100;
        w.createEmptyMovieClip("deadbody",1);w.createEmptyMovieClip("效果",20);
        w.deadbody.layers=[{}];
        w.场景背景url="flashswf/backgrounds/cf6/CF6_FIXTURE_BG.swf";
        var bg:MovieClip=w.createEmptyMovieClip("背景",0);
        bg.beginFill(0);bg.moveTo(0,0);bg.lineTo(100,0);bg.lineTo(100,100);bg.lineTo(0,100);bg.endFill();
        _root.savePath="cf6.mechanism.fixture";
        _root.当前关卡名="书中历险-毒刺行动";
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",
            slot:String(_root.savePath),seed:123,startedAt:1792550000000}};
        return w;
    }
    private static function testElevatorPoseOwnership():Void {
        var w:MovieClip=fixture(),s:Object={world:w,owner:StageReturnFlow.worldIdentity(w),kind:"elevator"};
        w.__cf6Mechanism=s;var hero:MovieClip=w.hero;
        hero.攻击模式="空手";hero.状态="空手行走";hero.transitions=0;
        hero.行走=function():Void {};hero.按键控制攻击模式=function():Void {};hero.按键检测=function():Boolean {return true;};
        hero.状态改变=function(value:String):Void {
            this.状态=value;this.transitions++;
            var block:MovieClip=this.createEmptyMovieClip("控制块",2);block.onEnterFrame=function():Void {};
        };
        var walk:Function=hero.行走,key:Function=hero.按键检测;
        check(Cf6MapMechanism.holdElevatorActor(s,hero) && hero.状态=="空手站立","elevator pause selects genuine standing state");
        var callback:Function=s.standingActor.callback;
        check(Cf6MapMechanism.holdElevatorActor(s,hero) && hero.transitions==1,"held pose is not reentered every frame");
        check(hero.控制块.onEnterFrame!==callback && hero.按键检测()===false,"held actor control is owned without stale walking input");
        Cf6MapMechanism.releaseElevatorActor(s);
        check(hero.行走===walk && hero.按键检测===key && hero.控制块.onEnterFrame===callback,"normal release restores exact input callbacks");
        check(hero.状态=="空手站立" && hero.__cf6ElevatorPoseOwner===undefined,"release does not restore stale walking pose");
        Cf6MapMechanism.holdElevatorActor(s,hero);
        var foreign:Function=function():Void {};hero.控制块.onEnterFrame=foreign;
        check(!Cf6MapMechanism.holdElevatorActor(s,hero) && hero.控制块.onEnterFrame===foreign,"foreign control callback cancels hold without overwrite");
        check(!Cf6MapMechanism.holdElevatorActor(s,hero),"abandoned ownership cannot reacquire within same hold");
        Cf6MapMechanism.releaseElevatorActor(s);hero.状态="空手行走";
        Cf6MapMechanism.holdElevatorActor(s,hero);hero.hp=0;hero.状态="血腥死";Cf6MapMechanism.releaseElevatorActor(s);
        check(hero.状态=="血腥死","release cannot replace a real death pose");
        hero.hp=100;hero.状态="空手行走";Cf6MapMechanism.holdElevatorActor(s,hero);
        hero.removeMovieClip();hero=w.createEmptyMovieClip("hero",10);hero.状态="foreign";hero.行走=foreign;
        Cf6MapMechanism.releaseElevatorActor(s);
        check(hero.状态=="foreign" && hero.行走===foreign && hero.__cf6ElevatorPoseOwner===undefined,"same-path replacement actor remains untouched");
        hero.hp=100;hero.状态改变=function(value:String):Void {this.状态=value;};
        s.arrival={rules:{phase:"playing"}};
        check(!Cf6MapMechanism.holdElevatorActor(s,hero),"boarding animation keeps its own walking presentation");
        s.arrival=null;s.kind="door";
        check(!Cf6MapMechanism.holdElevatorActor(s,hero),"non-elevator holds do not borrow standing adapter");
        s.kind="elevator";s.owner={};
        check(!Cf6MapMechanism.holdElevatorActor(s,hero),"stale room identity cannot acquire actor");
        w.removeMovieClip();
    }
    private static function testLifecycle():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        var manager:Object={calls:0,currentStage:0};
        var managerClass:Object=org.flashNight.arki.scene.StageManager;managerClass.instance=manager;
        manager.clearStage=function():Void {
            if(!org.flashNight.arki.scene.Cf6MapMechanism.interceptClear(this,_root.gameworld)) this.calls++;
        };
        check(Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]}),"bind current CF6 world");
        Cf6MapMechanism.tick();
        check(Cf6MapMechanism.interceptClear(manager,w),"intercept before ready");
        Cf6MapMechanism.tick();Cf6MapMechanism.tick();
        check(manager.calls==1,"production clear callback exactly once");
        check(!Cf6MapMechanism.interceptClear(manager,w),"ready reentry passes original clear");
        Cf6MapMechanism.teardown();
        check(Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]}),"bind second session");
        Cf6MapMechanism.tick();Cf6MapMechanism.interceptClear(manager,w);
        w.removeMovieClip();var replacement:MovieClip=fixture();
        StageReturnFlow.worldIdentity(replacement);
        Cf6MapMechanism.tick();
        check(manager.calls==1,"same-path replacement cannot complete old room");
        check(replacement.hero.hp==100,"stale teardown preserves replacement actors");
        _root._saveExt.bookRun.bookId="repair-campus";
        check(!Cf6MapMechanism.interceptClear(manager,replacement),"old books retain clear behavior");
        check(!Cf6MapMechanism.beginRoom(replacement,StageReturnFlow.worldIdentity(replacement),"A01",{}),"foreign book rejected");
        replacement.removeMovieClip();
    }
    private static function bake(force:Boolean):Void {
        if(force===true) _root.__cf6TestBakeCalls++;
        var w:MovieClip=_root.gameworld;
        w.__cf6BackgroundBake={drawCompleted:true,worldIdentity:StageReturnFlow.worldIdentity(w),
            sourceUrl:w.场景背景url,background:w.背景};
        _root.gameworld.背景.clear();
    }
    private static function testLogicalRunIdentity():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        var manager:Object={calls:0,currentStage:0};
        var managerClass:Object=org.flashNight.arki.scene.StageManager;managerClass.instance=manager;
        manager.clearStage=function():Void {
            if(!org.flashNight.arki.scene.Cf6MapMechanism.interceptClear(this,_root.gameworld)) this.calls++;
        };
        Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]});Cf6MapMechanism.tick();
        var before:Object=_root._saveExt.bookRun;
        _root._saveExt=PersistedSnapshot.clone(_root._saveExt);
        check(_root._saveExt.bookRun!==before,"persisted reward snapshot replaces the run object");
        check(Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]}) && w.__cf6Mechanism.phase=="combat","same logical run clone preserves the bound room");
        Cf6MapMechanism.interceptClear(manager,w);Cf6MapMechanism.tick();
        check(manager.calls==1 && w.__cf6Mechanism.phase=="ready","same logical run clone completes the existing gate once");
        Cf6MapMechanism.teardown();w.removeMovieClip();w=fixture();identity=StageReturnFlow.worldIdentity(w);
        Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]});Cf6MapMechanism.tick();
        Cf6MapMechanism.interceptClear(manager,w);_root._saveExt.bookRun.seed++;
        Cf6MapMechanism.tick();
        check(manager.calls==1 && w.允许通行===false,"new seed cannot complete an old room even when original object was mutated");
        w.removeMovieClip();w=fixture();identity=StageReturnFlow.worldIdentity(w);
        Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]});Cf6MapMechanism.tick();
        Cf6MapMechanism.interceptClear(manager,w);_root._saveExt=PersistedSnapshot.clone(_root._saveExt);_root._saveExt.bookRun.startedAt++;
        Cf6MapMechanism.tick();check(manager.calls==1,"different start timestamp rejects clone callback");
        w.removeMovieClip();w=fixture();identity=StageReturnFlow.worldIdentity(w);
        Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]});Cf6MapMechanism.tick();
        Cf6MapMechanism.interceptClear(manager,w);_root._saveExt.bookRun.planSeed=456;
        Cf6MapMechanism.tick();check(manager.calls==1,"different authored plan seed cannot take over room");
        w.removeMovieClip();w=fixture();identity=StageReturnFlow.worldIdentity(w);
        Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]});Cf6MapMechanism.tick();
        Cf6MapMechanism.interceptClear(manager,w);_root.当前关卡名="训练场";
        Cf6MapMechanism.tick();check(manager.calls==1,"stage change rejects a retained logical run");
        check(!Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]}),"foreign stage cannot bind CF6 mechanism");
        Cf6MapMechanism.teardown();w.removeMovieClip();
    }
    private static function testElevatorBake():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        _root.__cf6TestBakeCalls=0;_root.贴背景图=bake;
        _root._saveExt.bookRun.bookId="repair-campus";
        check(!Cf6MapMechanism.beginRoom(w,identity,"A10",{layers:[]}) && _root.__cf6TestBakeCalls==0,"foreign room never force-bakes");
        _root._saveExt.bookRun.bookId="cf6-sting";
        Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]});Cf6MapMechanism.tick();
        check(_root.__cf6TestBakeCalls==0,"ordinary CF6 map never force-bakes");
        Cf6MapMechanism.teardown();
        Cf6MapMechanism.beginRoom(w,identity,"A10",{layers:[]});
        check(_root.__cf6TestBakeCalls==1 && w.背景._width==0,"A10 loaded background uses production force bake");
        Cf6MapMechanism.teardown();
        check(!Cf6MapMechanism.beginRoom(w,{},"A10",{layers:[]}) && _root.__cf6TestBakeCalls==1,"stale world identity never force-bakes");
        delete w.__cf6BackgroundBake;
        Cf6MapMechanism.beginRoom(w,identity,"A13",{layers:[]});
        check(w.__cf6Mechanism.failed===true && _root.__cf6TestBakeCalls==1,"empty background fails without a force call");
        check(_root.暂停!==true,"failed background preparation releases its own pause");
        Cf6MapMechanism.teardown();w.removeMovieClip();w=fixture();identity=StageReturnFlow.worldIdentity(w);
        _root.贴背景图=function(force:Boolean):Void {if(force===true)_root.__cf6TestBakeCalls++;};
        Cf6MapMechanism.beginRoom(w,identity,"A13",{layers:[]});
        check(_root.__cf6TestBakeCalls==2 && w.__cf6Mechanism.failed===true,"old bake implementation cannot silently reverse layer ordering");
        Cf6MapMechanism.teardown();_root.贴背景图=bake;
        Cf6MapMechanism.beginRoom(w,identity,"A13",{layers:[]});
        check(_root.__cf6TestBakeCalls==3 && w.背景._width==0,"A13 uses the same bounded force-bake path");
        Cf6MapMechanism.teardown();w.removeMovieClip();
    }
    private static function testBakeReceipts():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        _root.__cf6TestBakeCalls=0;_root.贴背景图=bake;bake(false);
        Cf6MapMechanism.beginRoom(w,identity,"A10",{layers:[]});
        check(w.__cf6Mechanism.backgroundPrepared===true && _root.__cf6TestBakeCalls==0,"exact completed native background bake is reused without drawing again");
        Cf6MapMechanism.teardown();w.removeMovieClip();
        var invalid:Array=["worldIdentity","sourceUrl","background","drawCompleted"];
        for(var i:Number=0;i<invalid.length;i++) {
            w=fixture();identity=StageReturnFlow.worldIdentity(w);bake(false);
            if(invalid[i]=="worldIdentity") w.__cf6BackgroundBake.worldIdentity={};
            else if(invalid[i]=="sourceUrl") w.__cf6BackgroundBake.sourceUrl="flashswf/backgrounds/cf6/old.swf";
            else if(invalid[i]=="background") w.__cf6BackgroundBake.background=w.hero;
            else w.__cf6BackgroundBake.drawCompleted=false;
            Cf6MapMechanism.beginRoom(w,identity,"A13",{layers:[]});
            check(w.__cf6Mechanism.failed===true && w.__cf6Mechanism.backgroundPrepared!==true
                && _root.__cf6TestBakeCalls==0,"invalid bake "+invalid[i]+" never permits replay or layer attachment");
            Cf6MapMechanism.teardown();w.removeMovieClip();
        }
        w=fixture();identity=StageReturnFlow.worldIdentity(w);
        w.__cf6BackgroundBake={drawCompleted:true,worldIdentity:identity,sourceUrl:w.场景背景url,background:w.背景};
        Cf6MapMechanism.beginRoom(w,identity,"A10",{layers:[]});
        check(w.__cf6Mechanism.failed===true && _root.__cf6TestBakeCalls==0,"draw receipt with nonempty source waits for recovery without replay");
        Cf6MapMechanism.teardown();w.removeMovieClip();w=fixture();identity=StageReturnFlow.worldIdentity(w);
        _root.贴背景图=function(force:Boolean):Void {_root.__cf6TestBakeCalls++;_root.gameworld.背景.clear();};
        Cf6MapMechanism.beginRoom(w,identity,"A13",{layers:[]});
        check(w.__cf6Mechanism.failed===true && _root.__cf6TestBakeCalls==1,"empty clip without successful draw receipt is not completion evidence");
        Cf6MapMechanism.teardown();w.removeMovieClip();_root.贴背景图=bake;
    }
    private static function testDoorSequences():Void {
        var exitSpec:Object={role:"door-exit-sequence",frames:50};
        check(Cf6MapMechanism.sequenceFrame(exitSpec,"combat",50,-1)==1,"exit remains closed during combat");
        check(Cf6MapMechanism.sequenceFrame(exitSpec,"opening",0,-1)==1,"exit opens from original first frame");
        check(Cf6MapMechanism.sequenceFrame(exitSpec,"opening",23,-1)<50,"exit does not reach open terminal early");
        check(Cf6MapMechanism.sequenceFrame(exitSpec,"ready",0,-1)==50,"ready exit holds open terminal");
        var woodSpec:Object={role:"door-spawn-sequence",frames:9,spawnX:10,spawnY:20,spawnRadius:120};
        check(Cf6MapMechanism.sequenceFrame(woodSpec,"combat",0,-1)==1,"idle wood door is closed");
        check(Cf6MapMechanism.sequenceFrame(woodSpec,"combat",0,4)==5,"wood pulse follows source frame cursor");
        var pulse:Object={phase:"combat",layers:[{spec:woodSpec,pulseFrame:0}]};
        Cf6MapMechanism.advancePulses(pulse,true);
        check(pulse.layers[0].pulseFrame==0,"external pause freezes wood pulse");
        Cf6MapMechanism.advancePulses(pulse,false);
        check(pulse.layers[0].pulseFrame==1,"wood pulse advances while combat runs");
        for(var p:Number=0;p<8;p++) Cf6MapMechanism.advancePulses(pulse,false);
        check(pulse.layers[0].pulseFrame==-1,"wood pulse ends after nine frames");
        var w:MovieClip=fixture();
        Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A01",{layers:[]});Cf6MapMechanism.tick();
        var s:Object=w.__cf6Mechanism;
        var first:Object={spec:woodSpec,pulseFrame:-1,loads:[],holder:w.效果.createEmptyMovieClip("door1",1)};
        var second:Object={spec:{role:"door-spawn-sequence",frames:9,spawnX:100,spawnY:20,spawnRadius:120},
            pulseFrame:-1,loads:[],holder:w.效果.createEmptyMovieClip("door2",2)};
        s.layers=[first,second];
        var enemy:MovieClip=w.createEmptyMovieClip("doorEnemy",40);
        enemy.是否为敌人=true;enemy.hp=100;enemy._x=10;enemy._y=20;
        Cf6MapMechanism.unitSpawned(s,"doorEnemy");
        check(first.pulseFrame==0 && second.pulseFrame==-1,"one actual spawn opens only nearest door");
        first.pulseFrame=3;Cf6MapMechanism.unitSpawned(s,"doorEnemy");
        check(first.pulseFrame==3,"duplicate spawn notification cannot restart pulse");
        var other:MovieClip=w.createEmptyMovieClip("otherUnit",41);
        other.是否为敌人=false;other.hp=100;other._x=10;other._y=20;
        Cf6MapMechanism.unitSpawned(s,"otherUnit");
        check(first.pulseFrame==3,"friendly arrival does not operate enemy door");
        other.是否为敌人=true;other._x=500;Cf6MapMechanism.unitSpawned(s,"otherUnit");
        check(first.pulseFrame==3 && second.pulseFrame==-1,"remote enemy does not fake door spawn");
        w.removeMovieClip();w=fixture();StageReturnFlow.worldIdentity(w);
        Cf6MapMechanism.unitSpawned(s,"doorEnemy");
        check(first.pulseFrame==3,"old room spawn callback cannot reach replacement");
        Cf6MapMechanism.teardown();
        Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A01",{layers:[]});
        s=w.__cf6Mechanism;s.pending=1;
        var load:Object={ready:false,row:{spec:exitSpec,remaining:1}};
        Cf6MapMechanism.loaded(s,load,w.背景);
        check(s.failed===true && load.ready!==true,"actual one-frame bitmap cannot pass fifty-frame exit contract");
        check(_root.暂停!==true,"sequence contract failure releases only owned pause");
        Cf6MapMechanism.teardown();w.removeMovieClip();
    }
    private static function backdropFixture():MovieClip {
        var sky:MovieClip=_root.createEmptyMovieClip("__cf6FixtureSky",9288);
        _root.天空盒=sky;return sky;
    }
    private static function backdropConfig(mapId:String):Object {
        var layers:Array=[{id:"sky",role:"screen-fixed",coordinateSpace:"root-stage",
            url:"flashswf/backgrounds/cf6/CF6_"+mapId+"_sky.swf",x:0,y:mapId=="A06" ? -20 : 0,
            width:mapId=="A06" ? 800 : 600,height:187,depth:0}];
        if(mapId=="A02") layers.push({id:"city-parallax",role:"city-parallax",coordinateSpace:"root-stage",
            url:"flashswf/backgrounds/cf6/CF6_A02_city-parallax.swf",x:0,y:109,width:1441.4,height:66.45,depth:1});
        return {layers:layers};
    }
    private static function finishBackdropLoads(s:Object):Void {
        for(var i:Number=0;i<s.layers.length;i++) {
            var row:Object=s.layers[i], entry:Object=row.loads[0];
            var mc:MovieClip=entry.target;
            mc.beginFill(0x7799AA);mc.moveTo(0,0);mc.lineTo(row.spec.width,0);
            mc.lineTo(row.spec.width,row.spec.height);mc.lineTo(0,row.spec.height);mc.endFill();
            Cf6MapMechanism.loaded(s,entry,mc);
        }
    }
    private static function rootPoint(mc:MovieClip,x:Number,y:Number):Object {
        var point:Object={x:x,y:y};mc.localToGlobal(point);_root.globalToLocal(point);return point;
    }
    private static function near(a:Number,b:Number):Boolean {return Math.abs(a-b)<0.2;}
    private static function testBackdropLoading():Void {
        var sky:MovieClip=backdropFixture(),w:MovieClip=fixture();
        var calls:Object={count:0};var proto:Object=MovieClipLoader.prototype;var original:Function=proto.loadClip;
        proto.loadClip=function(url:String,target:MovieClip):Boolean {calls.count++;return true;};
        try {
            sky._x=12;sky._y=70;sky._xscale=150;sky._yscale=125;w._x=-240;w._y=-30;
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A02",backdropConfig("A02"));
            var s:Object=w.__cf6Mechanism;
            check(!s.failed && s.pending==2 && calls.count==2,"A02 independently loads fixed sky and city");
            check(s.backdropRoot._parent===sky && sky.getDepth()<w.getDepth(),"owned layers reuse the real back-plane below world");
            check(s.layers[0].holder.getDepth()==0 && s.layers[1].holder.getDepth()==1,"city sits above sky only inside owned container");
            check(s.backdropRoot._visible===false && w.允许通行===false,"partially loaded backdrop remains hidden and exit locked");
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A02",backdropConfig("A02"));
            check(w.__cf6Mechanism===s && calls.count==2,"duplicate room binding never duplicates sky loads");
            finishBackdropLoads(s);Cf6MapMechanism.tick();
            check(s.pending==0 && s.phase=="combat" && s.backdropRoot._visible===true,"all native layer callbacks unlock presentation together");
            var a:Object=rootPoint(s.layers[0].holder.art,0,0),b:Object=rootPoint(s.layers[0].holder.art,600,187);
            check(near(a.x,0) && near(a.y,0) && b.x+0.1>=Stage.width
                && near((b.x-a.x)/(b.y-a.y),600/187),"actual sky covers the viewport without changing aspect ratio despite parent zoom");
            var city:Object=rootPoint(s.layers[1].holder.art,0,0);
            check(near(city.x,-120) && near(city.y,79),"normalized city applies half world X and viewBox Y exactly once");
            sky._x=-20;sky._y=-40;sky._xscale=80;sky._yscale=80;w._x=-400;w._y=-10;
            _root.暂停=true;var frame:Number=s.frame;Cf6MapMechanism.tick();
            a=rootPoint(s.layers[0].holder.art,0,0);city=rootPoint(s.layers[1].holder.art,0,0);
            check(s.frame==frame && near(a.x,0) && near(a.y,0) && near(city.x,-200) && near(city.y,99),"external pause freezes mechanism while compensating actual camera pose");
            s.assetScale=128/75;w._xscale=w._yscale=125;
            Cf6MapMechanism.tick();
            city=rootPoint(s.layers[1].holder.art,0,0);
            check(near(city.x,-200) && near(city.y,-10+109*128/75*1.25),"city follows map scale and actual camera zoom with one world translation");
            a=rootPoint(s.layers[1].holder.art,100,20);
            check(near(a.x-city.x,100*128/75*1.25) && near(a.y-city.y,20*128/75*1.25),"city visual scale matches its transformed anchor");
            a=rootPoint(s.layers[0].holder.art,0,0);b=rootPoint(s.layers[0].holder.art,600,187);
            check(near(a.x,0) && near(a.y,0) && b.x+0.1>=Stage.width,"fixed sky stays full width when map scale and camera zoom change");
            _root.暂停=false;var parentName:String=s.backdropName;Cf6MapMechanism.teardown();
            check(sky[parentName]==undefined && near(sky._x,-20) && near(sky._yscale,80),"teardown removes owned backdrop without resetting shared sky camera");
        } finally {proto.loadClip=original;Cf6MapMechanism.teardown();w.removeMovieClip();sky.removeMovieClip();_root.暂停=false;}
    }
    private static function testBackdropFailuresAndIdentity():Void {
        var sky:MovieClip=backdropFixture(),w:MovieClip=fixture();
        var proto:Object=MovieClipLoader.prototype;var original:Function=proto.loadClip;
        proto.loadClip=function(url:String,target:MovieClip):Boolean {return true;};
        try {
            var invalid:Object=backdropConfig("A02");invalid.layers[0].coordinateSpace="world";
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A02",invalid);
            check(w.__cf6Mechanism.failed===true && w.允许通行===false,"world-space sky configuration cannot silently double-transform");
            Cf6MapMechanism.teardown();invalid=backdropConfig("A02");invalid.layers[1].x=Number.POSITIVE_INFINITY;
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A02",invalid);
            check(w.__cf6Mechanism.failed===true,"nonfinite root-space city coordinate is rejected");
            Cf6MapMechanism.teardown();invalid=backdropConfig("A02");invalid.layers.push(invalid.layers[0]);
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A02",invalid);
            check(w.__cf6Mechanism.failed===true && w.__cf6Mechanism.backdropRoot._visible===false,"duplicate fixed sky fails rather than stacking silently");
            Cf6MapMechanism.teardown();_root.天空盒=undefined;
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A06",backdropConfig("A06"));
            check(w.__cf6Mechanism.failed===true && _root.暂停!==true,"missing back-plane fails and releases only owned hold");
            Cf6MapMechanism.teardown();_root.天空盒=sky;
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A02",{layers:[]});
            check(w.__cf6Mechanism.failed===true,"A02 cannot omit both required backdrop resources");
            Cf6MapMechanism.teardown();Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A06",backdropConfig("A06"));
            var s:Object=w.__cf6Mechanism,entry:Object=s.layers[0].loads[0];
            Cf6MapMechanism.loadFailed(s,entry,"fixture-missing");
            check(s.failed===true && s.backdropRoot._visible===false && w.允许通行===false,"missing sky resource keeps exit closed and hides partial presentation");
            Cf6MapMechanism.teardown();Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A06",backdropConfig("A06"));
            s=w.__cf6Mechanism;s.loadFrames=900;Cf6MapMechanism.tick();
            check(s.failed===true && _root.暂停!==true,"sky timeout uses bounded failure and releases owned hold");
            Cf6MapMechanism.teardown();Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A06",backdropConfig("A06"));
            s=w.__cf6Mechanism;entry=s.layers[0].loads[0];var oldName:String=s.backdropName;
            w.removeMovieClip();w=fixture();StageReturnFlow.worldIdentity(w);
            Cf6MapMechanism.loaded(s,entry,w.背景);
            check(entry.ready!==true && s.pending==1,"late sky success cannot bind a replacement world");
            Cf6MapMechanism.tick();
            check(sky[oldName]==undefined && w.hero.hp==100,"identity invalidation cleans root backdrop while preserving replacement world");
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A06",backdropConfig("A06"));
            s=w.__cf6Mechanism;oldName=s.backdropName;var depth:Number=s.backdropRoot.getDepth();s.backdropRoot.removeMovieClip();
            var replacement:MovieClip=sky.createEmptyMovieClip(oldName,depth);replacement.__cf6BackdropOwner={};
            Cf6MapMechanism.teardown();
            check(sky[oldName]===replacement,"stale holder alias cannot remove another owner's root child");
            replacement.removeMovieClip();
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A06",backdropConfig("A06"));
            s=w.__cf6Mechanism;finishBackdropLoads(s);sky._xscale=0;Cf6MapMechanism.tick();
            check(s.failed===true && s.backdropRoot._visible===false,"degenerate parent zoom cannot produce NaN sky placement");sky._xscale=100;
        } finally {proto.loadClip=original;Cf6MapMechanism.teardown();w.removeMovieClip();sky.removeMovieClip();_root.暂停=false;}
    }
    private static function testBackdropTransfer():Void {
        var sky:MovieClip=backdropFixture(),w:MovieClip=fixture();
        var proto:Object=MovieClipLoader.prototype;var original:Function=proto.loadClip;
        proto.loadClip=function(url:String,target:MovieClip):Boolean {return true;};
        try {
            var manager:Object={calls:0,currentStage:0};
            var managerClass:Object=org.flashNight.arki.scene.StageManager;managerClass.instance=manager;
            manager.clearStage=function():Void {this.calls++;};
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A06",backdropConfig("A06"));
            var s:Object=w.__cf6Mechanism;finishBackdropLoads(s);Cf6MapMechanism.tick();
            var point:Object=rootPoint(s.layers[0].holder.art,0,0);
            check(near(point.x,0) && near(point.y,-20),"A06 uses original 1753 sky at root 0,-20");
            Cf6MapMechanism.interceptClear(manager,w);_root.暂停=true;Cf6MapMechanism.tick();
            check(s.phase=="combat" && manager.calls==0,"external pause still holds A06 clear");
            _root.暂停=false;Cf6MapMechanism.tick();
            check(s.phase=="ready" && s.card===undefined && s.backdropRoot._visible===true,"A06 keeps the rear sky without a substitute driving card");
            Cf6MapMechanism.tick();
            check(manager.calls==1 && _root.暂停!==true,"A06 delegates clear once and leaves standard story navigation available");
            var parentName:String=s.backdropName;Cf6MapMechanism.teardown();
            check(sky[parentName]==undefined && _root.暂停!==true,"A06 teardown removes only its sky and releases its hold");
        } finally {proto.loadClip=original;Cf6MapMechanism.teardown();w.removeMovieClip();sky.removeMovieClip();_root.暂停=false;}
    }
    /** Real production WaveSpawner/StageInfo/StageManager; only display/event sinks are fixtures. */
    private static function emptyWaveFixture():Object {
        Cf6MapMechanism.teardown();_root.暂停=false;
        var w:MovieClip=fixture();
        w.createEmptyMovieClip("地图",11);w.地图.僵尸型敌人总个数=0;w.允许通行=false;
        w.dispatcher={clears:0,waves:0,
            subscribe:function():Void {},
            publish:function(name:String):Void {if(name=="Clear") this.clears++;if(name=="WaveFinished") this.waves++;}};
        var scene:Object=SceneManager.getInstance();scene.gameworld=w;
        var manager:Object=StageManager.getInstance();
        manager.gameworld=w;manager.environment={};manager.spawnPoints=[];manager.currentStage=0;
        manager.isActive=true;manager.isFinished=false;manager.isFailed=false;manager.isCleared=false;
        manager.stageMode="legacy";manager.stageInfoList=[{},{}];manager.timePoolController=null;
        // Exact empty-wave shape used by A08/A16; no enemy/time/finish-state inference.
        var info:StageInfo=new StageInfo({BasicInformation:{Environment:{},Animation:{Load:-1}},
            Wave:{SubWave:[{WaveInformation:{Duration:0,FinishRequirement:0},EnemyGroup:{Enemy:[]}}]}});
        manager.currentStageInfo=info;
        WaveSpawnWheel.getInstance();
        var spawner:WaveSpawner=WaveSpawner.getInstance();manager.spawner=spawner;spawner.init(info);
        return {world:w,owner:StageReturnFlow.worldIdentity(w),manager:manager,spawner:spawner};
    }
    private static function emptyWaveTicks(f:Object,count:Number):Void {
        for(var i:Number=0;i<count;i++) f.spawner.tick();
    }
    private static function bindEmpty(f:Object,mapId:String):Void {
        Cf6MapMechanism.beginRoom(f.world,StageReturnFlow.worldIdentity(f.world),mapId,{layers:[]});
        Cf6MapMechanism.tick();Cf6MapMechanism.tick();
    }
    private static function testEarlyEmptyWave():Void {
        var managerClass:Object=org.flashNight.arki.scene.StageManager;
        var sceneClass:Object=org.flashNight.arki.scene.SceneManager;
        var spawnerClass:Object=org.flashNight.arki.scene.WaveSpawner;
        var wheelClass:Object=org.flashNight.arki.scene.WaveSpawnWheel;
        var saved:Object={manager:managerClass.instance,scene:sceneClass.instance,
            spawner:spawnerClass.instance,wheel:wheelClass.instance,server:_root.server};
        managerClass.instance=null;sceneClass.instance=null;spawnerClass.instance=null;wheelClass.instance=null;
        _root.server={isSocketConnected:false};
        var f:Object;
        try {
            var maps:Array=["A08","A16"];
            for(var m:Number=0;m<maps.length;m++) {
                f=emptyWaveFixture();emptyWaveTicks(f,29);
                check(!f.spawner.isFinished && !f.manager.isCleared,maps[m]+" real empty wave waits until tick 30");
                emptyWaveTicks(f,1);
                check(f.spawner.isFinished && f.world.dispatcher.waves==1 && !f.manager.isCleared
                    && f.world.允许通行===false,maps[m]+" tick 30 finishes wave but preserves closed unbound exit");
                emptyWaveTicks(f,90);
                check(f.world.dispatcher.waves==1 && f.world.dispatcher.clears==0,maps[m]+" finished wave never replays while presentation waits");
                check(Cf6MapMechanism.beginRoom(f.world,f.owner,maps[m],{layers:[]})
                    && f.world.__cf6Mechanism.clearRequested===true,maps[m]+" late binding consumes the actual deferred clear");
                Cf6MapMechanism.tick();Cf6MapMechanism.tick();
                check(f.manager.isCleared && f.world.允许通行===true && f.world.dispatcher.clears==1,
                    maps[m]+" original StageManager clear completes exactly once");
                for(var t:Number=0;t<60;t++) Cf6MapMechanism.tick();
                check(f.world.dispatcher.clears==1 && !f.world.__cf6Mechanism.failed && f.world.允许通行===true,
                    maps[m]+" consumed receipt does not close the successfully cleared exit");
            }
            f=emptyWaveFixture();emptyWaveTicks(f,30);
            check(Cf6MapMechanism.interceptClear(f.manager,f.world) && Cf6MapMechanism.interceptClear(f.manager,f.world),
                "duplicate early notifications remain intercepted");
            bindEmpty(f,"A08");check(f.world.dispatcher.clears==1,"duplicate early notifications have one delivery");

            f=emptyWaveFixture();emptyWaveTicks(f,30);Cf6MapMechanism.teardown();bindEmpty(f,"A08");
            check(!f.world.__cf6Mechanism.clearRequested && !f.manager.isCleared,"explicit teardown destroys an unconsumed receipt");
            Cf6MapMechanism.teardown();bindEmpty(f,"A08");
            check(!f.world.__cf6Mechanism.clearRequested,"a destroyed receipt cannot be resurrected by another bind");

            f=emptyWaveFixture();emptyWaveTicks(f,30);f.world.removeMovieClip();
            var replacement:MovieClip=fixture();f.manager.gameworld=replacement;
            Cf6MapMechanism.beginRoom(replacement,StageReturnFlow.worldIdentity(replacement),"A08",{layers:[]});
            Cf6MapMechanism.tick();Cf6MapMechanism.tick();
            check(!replacement.__cf6Mechanism.clearRequested && !f.manager.isCleared,"same-path MovieClip replacement rejects old owner token");

            f=emptyWaveFixture();emptyWaveTicks(f,30);f.manager.currentStage=1;bindEmpty(f,"A08");
            check(!f.world.__cf6Mechanism.clearRequested && !f.manager.isCleared,"same world next substage rejects old clear");
            f=emptyWaveFixture();emptyWaveTicks(f,30);managerClass.instance=null;
            var newManager:Object=StageManager.getInstance();newManager.gameworld=f.world;newManager.currentStage=0;
            newManager.isActive=true;newManager.isFailed=false;newManager.isFinished=false;newManager.isCleared=false;
            bindEmpty(f,"A08");
            check(!f.world.__cf6Mechanism.clearRequested && !f.manager.isCleared && !newManager.isCleared,"same world replacement manager rejects old clear");

            f=emptyWaveFixture();emptyWaveTicks(f,30);_root._saveExt=PersistedSnapshot.clone(_root._saveExt);bindEmpty(f,"A16");
            check(f.manager.isCleared && f.world.dispatcher.clears==1,"valid saveExt clone preserves scalar-bound deferred clear");
            var runKeys:Array=["seed","startedAt","planSeed"];
            for(var r:Number=0;r<runKeys.length;r++) {
                f=emptyWaveFixture();emptyWaveTicks(f,30);
                _root._saveExt.bookRun[runKeys[r]]=runKeys[r]=="planSeed" ? 999 : _root._saveExt.bookRun[runKeys[r]]+1;
                bindEmpty(f,"A08");
                check(!f.world.__cf6Mechanism.clearRequested && !f.manager.isCleared,"changed "+runKeys[r]+" cannot consume old clear");
            }
            // Invalid calls must not become deferred authority when the context later recovers.
            var invalid:Array=["manager","world","stage","inactive","failed","finished","route","slot","stageName","missingOwner"];
            for(var b:Number=0;b<invalid.length;b++) {
                f=emptyWaveFixture();var key:String=invalid[b];
                if(key=="manager") managerClass.instance=null;
                else if(key=="world") f.manager.gameworld=undefined;
                else if(key=="stage") f.manager.currentStage=Number.NaN;
                else if(key=="inactive") f.manager.isActive=false;
                else if(key=="failed") f.manager.isFailed=true;
                else if(key=="finished") f.manager.isFinished=true;
                else if(key=="route") _root._saveExt.bookRun.routeId="other";
                else if(key=="slot") _root.savePath="foreign.slot";
                else if(key=="stageName") _root.当前关卡名="foreign.stage";
                else if(key=="missingOwner") delete f.world.__stageReturnWorldIdentity;
                // Actual wave finish still occurs, including manager-level rejected attempts.
                emptyWaveTicks(f,30);
                managerClass.instance=f.manager;f.manager.gameworld=f.world;f.manager.currentStage=0;
                f.manager.isActive=true;f.manager.isFailed=false;f.manager.isFinished=false;
                _root._saveExt.bookRun.routeId="historical";_root.savePath=_root._saveExt.bookRun.slot;
                _root.当前关卡名="书中历险-毒刺行动";f.world.__stageReturnWorldIdentity=f.owner;
                bindEmpty(f,"A08");
                check(!f.world.__cf6Mechanism.clearRequested && !f.manager.isCleared,"invalid "+key+" registers no deferred clear");
            }
            f=emptyWaveFixture();emptyWaveTicks(f,30);
            Cf6MapMechanism.beginRoom(f.world,f.owner,"A08",{layers:[]});f.manager.currentStage=1;Cf6MapMechanism.tick();
            check(f.world.__cf6Mechanism.failed && !f.manager.isCleared && f.world.允许通行===false,
                "stage change after handoff cancels delivery before mechanism completion");
            f=emptyWaveFixture();emptyWaveTicks(f,30);
            Cf6MapMechanism.beginRoom(f.world,f.owner,"A08",{layers:[]});managerClass.instance=null;Cf6MapMechanism.tick();
            check(f.world.__cf6Mechanism.failed && !f.manager.isCleared,"manager replacement after handoff cancels delivery");
            f=emptyWaveFixture();emptyWaveTicks(f,30);
            Cf6MapMechanism.beginRoom(f.world,f.owner,"A08",{layers:[]});Cf6MapMechanism.teardown();bindEmpty(f,"A08");
            check(!f.world.__cf6Mechanism.clearRequested && !f.manager.isCleared,"teardown after handoff prevents receipt reuse");
            f=emptyWaveFixture();_root._saveExt.bookRun.bookId="repair-campus";emptyWaveTicks(f,30);
            check(f.manager.isCleared && f.world.dispatcher.clears==1,"ordinary old book empty wave still takes original clear path");
        } finally {
            Cf6MapMechanism.teardown();if(f.world!=undefined) f.world.removeMovieClip();
            if(spawnerClass.instance!=null) spawnerClass.instance.close();
            managerClass.instance=saved.manager;sceneClass.instance=saved.scene;
            spawnerClass.instance=saved.spawner;wheelClass.instance=saved.wheel;_root.server=saved.server;
            _root.暂停=false;
        }
    }
    private static function turretSpec():Object {
        // 装配后世界坐标（native×128/75 已由 build-chapter 完成），load 模式无 name 字段。
        return {assetUrl:"flashswf/backgrounds/cf6/CF6_A01_Turret.swf",turrets:[
            {x:228.352,y:345.4293,facing:"right"},
            {x:426.3253,y:735.4027,facing:"right"}]};
    }
    private static function testTurretWiring():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        var proto:Object=MovieClipLoader.prototype;var original:Function=proto.loadClip;
        proto.loadClip=function(url:String,target:MovieClip):Boolean {return true;};
        try {
            check(Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[],turrets:turretSpec()}),
                "A01 mechanism bind wires the turret service");
            var s:Object=w.__cf6Mechanism;
            var st:Object=Cf6TutorialTurretService.debugState();
            check(s.turretBound===true && st!=null && st.count==2 && st.loaded==0 && st.failed!==true,
                "turret session bound to this room with two pending holders");
            check(Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[],turrets:turretSpec()})
                && Cf6TutorialTurretService.debugState().count==2,"duplicate binding never duplicates turret session");
            Cf6MapMechanism.teardown();
            check(Cf6TutorialTurretService.debugState()==null,"mechanism teardown clears the turret session");

            check(Cf6MapMechanism.beginRoom(w,identity,"A02",{layers:[],turrets:turretSpec()})
                && w.__cf6Mechanism.failed===true,"non-A01 map carrying turrets fails the mechanism closed");
            check(Cf6TutorialTurretService.debugState()==null,"rejected turret config leaves no turret session");
            Cf6MapMechanism.teardown();

            Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[],turrets:turretSpec()});
            _root.当前关卡名="训练场";Cf6MapMechanism.tick();_root.当前关卡名="书中历险-毒刺行动";
            check(Cf6TutorialTurretService.debugState()==null,
                "stage change tears down mechanism and turret session together");
            w=fixture();identity=StageReturnFlow.worldIdentity(w);
            Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]});
            check(Cf6TutorialTurretService.debugState()==null,"A01 without turret config binds no turret session");
            Cf6MapMechanism.teardown();
        } finally {proto.loadClip=original;Cf6TutorialTurretService.teardown();Cf6MapMechanism.teardown();w.removeMovieClip();}
    }
    private static function testTraversalWiring():Void {
        var w:MovieClip=fixture(),identity:Object=StageReturnFlow.worldIdentity(w);
        _root.控制目标="hero";w.hero._x=100;w.hero._y=w.hero.Z轴坐标=20;
        // The wiring fixture needs a real upper-body MC for semantic idle ownership.
        // Native label/frame behavior is covered by Cf6TraversalNativeTest.
        w.hero.createEmptyMovieClip("man",1);
        w.hero.方向="右";w.hero.攻击模式="长枪";
        w.hero.状态改变=function(value:String):Void {this.状态=value;};
        w.hero.方向改变=function(value:String):Void {this.方向=value;};
        var manager:Object={calls:0,currentStage:0};
        var managerClass:Object=org.flashNight.arki.scene.StageManager;managerClass.instance=manager;
        manager.clearStage=function():Void {
            if(!org.flashNight.arki.scene.Cf6MapMechanism.interceptClear(this,_root.gameworld)) this.calls++;
        };
        var path:Object={mode:"depart",fps:30,durationFrames:4,gate:{x:10,z:20,radius:12},exit:{x:60,z:30},samples:[
            {frame:1,x:10,z:20,visible:true,action:"walk"},{frame:2,x:20,z:20,visible:true,action:"walk"},
            {frame:3,x:30,z:20,visible:true,action:"walk"},{frame:4,x:40,z:20,visible:false,action:"stand"}]};
        check(Cf6MapMechanism.beginRoom(w,identity,"A03",{kind:"door",layers:[],traversal:{depart:path}}),"production binds actor-owned departure");
        Cf6MapMechanism.tick();Cf6MapMechanism.interceptClear(manager,w);Cf6MapMechanism.tick();
        var s:Object=w.__cf6Mechanism;
        check(s.phase=="combat" && !_root.暂停 && manager.calls==0,"real clear away from gate retains player control");
        w.hero._x=10;Cf6MapMechanism.tick();
        check(s.phase=="traversal-depart" && s.departure.acquired,"at gate starts production actor traversal");
        var pauseId:String=org.flashNight.arki.pause.PauseManager.lease(true,"dialogue");
        Cf6MapMechanism.tick();check(s.departure.rules.frame==1,"production trajectory respects foreign pause");
        org.flashNight.arki.pause.PauseManager.releaseLease(pauseId);
        Cf6MapMechanism.tick();Cf6MapMechanism.tick();Cf6MapMechanism.tick();
        check(s.phase=="ready" && manager.calls==1 && w.hero._visible,"production traversal returns standard clear once");
        check(w.hero._x==60 && w.hero.Z轴坐标==30 && !_root.暂停,"production handoff places live actor at standard exit");
        Cf6MapMechanism.tick();check(manager.calls==1,"late production tick cannot duplicate clear");
        Cf6MapMechanism.teardown();
        path.mode="arrive";path.actorReleaseFrame=2;
        Cf6MapMechanism.beginRoom(w,identity,"A04",{layers:[],traversal:{arrive:path}});
        Cf6MapMechanism.tick();Cf6MapMechanism.tick();
        s=w.__cf6Mechanism;
        check(!s.arrival.acquired && !_root.暂停 && s.arrival.rules.frame==2,"arrival releases before remaining door frames");
        w.hero._x=77;Cf6MapMechanism.tick();Cf6MapMechanism.tick();
        check(w.hero._x==77 && s.phase=="combat","remaining arrival door frames never reclaim actor");
        Cf6MapMechanism.teardown();w.removeMovieClip();
    }
    private static function testTraversalAssetClosure():Void {
        var prefix:String="flashswf/backgrounds/cf6/preparation/";
        var p:Object={url:prefix+"CF6_Traversal1720_Front.swf",role:"traversal-layer",traversalMode:"depart",frames:174};
        check(Cf6MapMechanism.traversalAssetInfo(p).first==74,"1720 front has an authored empty opening");
        p.url=prefix+"CF6_Traversal1720_Mask.swf";p.role="actor-mask";
        check(Cf6MapMechanism.traversalAssetInfo(p).first==136,"1720 actor mask starts at exact source frame");
        p.url=prefix+"CF6_Traversal1729_Front.swf";p.role="traversal-layer";p.traversalMode="arrive";
        check(Cf6MapMechanism.traversalAssetInfo(p).last==101,"1729 front ends at exact source frame");
        p.url=prefix+"CF6_Traversal1729_Mask.swf";p.role="actor-mask";
        check(Cf6MapMechanism.traversalAssetInfo(p).last==39,"1729 mask empty tail is allowed only by source range");
        p.url=prefix+"CF6_Traversal1750_Front.swf";p.role="traversal-layer";p.traversalMode="depart";p.frames=40;
        check(Cf6MapMechanism.traversalAssetInfo(p).first==0,"1750 intentionally empty front is explicit");
        p.url=prefix+"CF6_Traversal1750_Mask.swf";p.role="actor-mask";
        check(Cf6MapMechanism.traversalAssetInfo(p)==null,"1750 empty actor mask is forbidden");
        p.url=prefix+"unknown.swf";p.role="traversal-layer";
        check(Cf6MapMechanism.traversalAssetInfo(p)==null,"unknown resource cannot bypass empty-asset check");
        p.url=prefix+"CF6_Traversal1720_Back.swf";p.frames=174;p.traversalMode="arrive";
        check(Cf6MapMechanism.traversalAssetInfo(p)==null,"departure asset cannot claim arrival contract");
        p.traversalMode="depart";p.frames=40;
        check(Cf6MapMechanism.traversalAssetInfo(p)==null,"frame count must match exact asset");
        p.url=prefix+"CF6_AuxDoor1430.swf";p.frames=59;
        check(Cf6MapMechanism.traversalAssetInfo(p).duration==58,"1430 preserves frame58 cut with full59 frame asset");
    }
    private static function testImmediateOwnershipAndArt():Void {
        var w:MovieClip=fixture(),managerClass:Object=org.flashNight.arki.scene.StageManager;
        var manager:Object={currentStage:0};managerClass.instance=manager;
        Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A01",{layers:[]});Cf6MapMechanism.tick();
        var s:Object=w.__cf6Mechanism;s.phase="ready";w.允许通行=true;
        managerClass.instance={currentStage:0};
        check(Cf6MapMechanism.interceptClear(manager,w) && w.允许通行===true,
            "retired ready manager cannot pass clear or write replacement owner before next tick");
        var pending:Object={ready:false,row:{spec:{id:"late",role:"foreground"},remaining:1}};
        s.pending=1;var art:MovieClip=w.createEmptyMovieClip("lateArt",30);
        Cf6MapMechanism.loaded(s,pending,art);
        check(!pending.ready && s.pending==1,"late loader rejects manager replacement immediately");
        Cf6MapMechanism.teardown();w.removeMovieClip();
        check(Cf6MapMechanism.artTransformValid({artMatrix:[1,0.25,0,1,-20,-30]}),"finite shear and pivot transform accepted once");
        check(!Cf6MapMechanism.artTransformValid({artMatrix:[1,1,1,1,0,0]}),"singular art matrix rejected");
        check(!Cf6MapMechanism.artTransformValid({artMatrix:[1,0,0,1,Number.NaN,0]}),"NaN art translation rejected");
        check(Cf6MapMechanism.artTransformValid({colorMult:[210,210,210,256]}),"original 256-unit instance tint accepted");
        check(!Cf6MapMechanism.artTransformValid({colorMult:["210",210,210,256]}),"coerced string tint rejected");
    }
    private static function testEarlyBirthWindow():Void {
        var w:MovieClip=fixture(),identity:Object=StageReturnFlow.worldIdentity(w);
        var managerClass:Object=org.flashNight.arki.scene.StageManager;managerClass.instance={currentStage:0,gameworld:w,isActive:true};
        w.dispatcher={subscriptions:0,removals:0,subscribe:function(e:String,f:Function,o:Object):Void {this.subscriptions++;},unsubscribe:function(e:String,f:Function,o:Object):Void {this.removals++;}};
        var p:Object=Cf6MapMechanism.captureSpawnWindow(w,null,identity);
        check(p!=null && w.dispatcher.subscriptions==1,"SceneReady opens exact early spawn window");
        check(Cf6MapMechanism.captureSpawnWindow(w,null,identity)===p && w.dispatcher.subscriptions==1,"duplicate SceneReady does not duplicate listener");
        var unit:MovieClip=w.createEmptyMovieClip("enemy",100);unit.hp=10;unit.是否为敌人=true;unit.publishStageEvent=true;unit._x=15;unit._y=25;
        Cf6MapMechanism.observeBirth(p,"enemy");Cf6MapMechanism.observeBirth(p,"enemy");
        check(p.records.length==1,"same instance duplicate birth suppressed");
        unit._x=90;unit._y=95;
        check(p.records[0].x==15 && p.records[0].y==25,"birth coordinates survive later movement");
        unit.removeMovieClip();unit=w.createEmptyMovieClip("enemy",100);unit.hp=10;unit.是否为敌人=true;unit.publishStageEvent=true;
        Cf6MapMechanism.observeBirth(p,"enemy");
        check(p.records.length==2,"same-name replacement has a distinct birth stamp");
        check(Cf6MapMechanism.beginRoom(w,identity,"A01",{layers:[]}),"precise room consumes early window");
        check(w.__cf6Mechanism.spawnSeen.enemy===true && p.closed && p.records.length==0,"transfer uses current stamped actor then disposes records");
        check(unit.__cf6DoorBirthStamp==undefined && w.dispatcher.removals==1,"transfer removes only own stamp and listener");
        Cf6MapMechanism.teardown();p=Cf6MapMechanism.captureSpawnWindow(w,null,identity);
        for(var i:Number=0;i<257;i++) {var u:MovieClip=w.createEmptyMovieClip("birth"+i,200+i);u.hp=1;u.是否为敌人=true;u.publishStageEvent=true;Cf6MapMechanism.observeBirth(p,u._name);}
        check(p.records.length==256 && p.truncated===true,"early cache has deterministic bounded capacity");
        managerClass.instance={currentStage:0,gameworld:w,isActive:true};Cf6MapMechanism.observeBirth(p,"enemy");
        check(p.records.length==256,"manager replacement cannot append retired births");
        Cf6MapMechanism.teardown();
        check(p.closed && p.records.length==0 && w.birth0.__cf6DoorBirthStamp==undefined,"teardown discards bounded cache and owned stamps");
        w.removeMovieClip();
    }
    private static function testLateSceneReadyArrival():Void {
        var w:MovieClip=fixture(),definition:Object=BookDefinition,previous=definition._cf6;
        w.dispatcher=new org.flashNight.neur.Event.EventDispatcher();
        var managerClass:Object=StageManager;managerClass.instance={gameworld:w,currentStage:0,isActive:true,isFailed:false,isFinished:false,isCleared:false};
        _root.控制目标="hero";var hero:MovieClip=w.hero;
        hero.攻击模式="长枪";hero.方向="右";hero._x=80;hero._y=hero.Z轴坐标=40;
        hero.createEmptyMovieClip("man",1);
        hero.状态改变=function(v:String):Void {this.状态=v;};
        hero.方向改变=function(v:String):Void {if(!this.锁定方向)this.方向=v;};
        var init:Object=Cf6ActorMaskState.prepare(w,StageReturnFlow.worldIdentity(w),"hero",{});
        for(var key:String in init) hero[key]=init[key];Cf6ActorMaskState.bind(hero,init);
        var config:Object={layers:[],traversal:{arrive:{mode:"arrive",fps:30,durationFrames:2,samples:[
            {frame:1,x:10,z:40,visible:true,action:"walk"},{frame:2,x:20,z:40,visible:true,action:"walk"}]}}};
        definition._cf6={maps:[{id:"A01",mechanism:config}]};
        try {
            Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A01",config);
            var state:Object=w.__cf6Mechanism;
            Cf6MapMechanism.captureSpawnWindow(w,null,w.__stageReturnWorldIdentity);
            check(state.arrival.rules.frame==0 && !hero._visible && hero.__cf6ArrivalPreparationOwner!=undefined,
                "real SceneReady handler prepares a room that was bound before the actor-ready event");
            Cf6MapMechanism.tick();Cf6MapMechanism.captureSpawnWindow(w,null,w.__stageReturnWorldIdentity);
            var playingVisible:Boolean=hero._visible && hero._x==10 && state.arrival.rules.frame==1;
            Cf6MapMechanism.tick();Cf6MapMechanism.captureSpawnWindow(w,null,w.__stageReturnWorldIdentity);
            check(playingVisible && hero._visible && hero._x==20 && state.arrival.rules.phase=="complete",
                "real repeated SceneReady neither re-hides a playing arrival nor restarts a completed one");
        } finally {Cf6MapMechanism.teardown();definition._cf6=previous;w.removeMovieClip();}
    }
    private static function testLoadedElevatorMask():Void {
        var w:MovieClip=fixture();
        Cf6MapMechanism.beginRoom(w,StageReturnFlow.worldIdentity(w),"A01",{layers:[]});Cf6MapMechanism.tick();
        var s:Object=w.__cf6Mechanism;s.assetScale=1;s.pending=1;
        // Root-owned isolated geometry survives the synchronous room teardown and
        // later suites. Real display-list commits require actual enterFrame turns.
        var name:String="__cf6LoadedMaskProbe"+(++probeSerial);
        while(_root[name]!=undefined) name="__cf6LoadedMaskProbe"+(++probeSerial);
        var holder:MovieClip=_root.createEmptyMovieClip(name,_root.getNextHighestDepth());
        var token:Object={};holder.__cf6LoadedMaskTestOwner=token;
        pixelProbe={holder:holder,name:name,token:token,turns:0,armed:false};
        var art:MovieClip=holder.createEmptyMovieClip("art",0);
        art.beginFill(0x00AA66);art.moveTo(0,0);art.lineTo(40,0);art.lineTo(40,40);art.lineTo(0,40);art.endFill();
        var mask:MovieClip=holder.createEmptyMovieClip("windowMask",2);
        mask.beginFill(0);mask.moveTo(0,0);mask.lineTo(20,0);mask.lineTo(20,20);mask.lineTo(0,20);mask.endFill();
        var layer:Object={holder:holder,spec:{id:"actual-loaded-mask",role:"elevator-scroll"},remaining:1,loads:[]};
        var entry:Object={ready:false,row:layer};
        Cf6MapMechanism.loaded(s,entry,art);
        check(entry.ready && layer.ready && s.pending==0 && layer.remaining==0,"production loaded callback completes owned elevator tile");
        Cf6MapMechanism.loaded(s,entry,art);
        check(s.pending==0 && layer.remaining==0,"duplicate loaded callback cannot consume completion twice");
        var foreign:MovieClip=holder.createEmptyMovieClip("foreign",8);
        check(!Cf6MapMechanism.bindLoadedElevatorMask(holder,foreign),"foreign child cannot borrow elevator mask");
        foreign.removeMovieClip();
        // Missing-mask negative control must not dismantle the deferred positive control.
        var missing:MovieClip=w.createEmptyMovieClip("missingMask",w.getNextHighestDepth());
        var missingArt:MovieClip=missing.createEmptyMovieClip("art",0);
        missingArt.beginFill(0x00AA66);missingArt.moveTo(0,0);missingArt.lineTo(40,0);missingArt.lineTo(40,40);missingArt.lineTo(0,40);missingArt.endFill();
        check(!Cf6MapMechanism.bindLoadedElevatorMask(missing,missingArt),"missing current mask cannot be accepted");
        entry={ready:false,row:{holder:missing,spec:{id:"missing-loaded-mask",role:"elevator-scroll"},remaining:1,loads:[]}};s.pending=1;
        Cf6MapMechanism.loaded(s,entry,missingArt);
        check(s.failed===true && !entry.ready,"production loaded callback fails closed when its mask is missing");
        var watchName:String=name+"Watch";
        while(_root[watchName]!=undefined) watchName+="_";
        var watch:MovieClip=_root.createEmptyMovieClip(watchName,_root.getNextHighestDepth());
        watch.__cf6LoadedMaskTestOwner=token;pixelProbe.driver=watch;pixelProbe.driverName=watchName;
        watch.onEnterFrame=function():Void {org.flashNight.arki.scene.Cf6MapMechanismTest.pixelTick();};
        pixelProbe.armed=true;
        Cf6MapMechanism.teardown();w.removeMovieClip();
    }
    public static function pixelTick():Void {
        if(finished || pixelProbe==null) return;
        if(++pixelProbe.turns<2) return;
        var pixels:BitmapData;
        try {
            var holder:MovieClip=pixelProbe.holder;
            if(holder._parent!==_root || _root[pixelProbe.name]!==holder || holder.__cf6LoadedMaskTestOwner!==pixelProbe.token)
                throw new Error("isolated pixel probe ownership replaced");
            pixels=new BitmapData(45,45,true,0);pixels.draw(holder);
            var inside:Number=pixels.getPixel32(10,10),outside:Number=pixels.getPixel32(30,30);
            trace("Cf6MapMechanism LoadedMaskPixels: turns="+pixelProbe.turns+" inside="+inside+" outside="+outside);
            check((inside&0xFFFFFF)==0x00AA66 && (inside>>>24)==255,"production loaded callback hides black mask and preserves actual art color");
            check((outside>>>24)==0,"production loaded callback actually clips outside its window");
        } catch(error) {
            check(false,"deferred loaded-mask color probe exception: "+error);
            check(false,"deferred loaded-mask clipping probe unavailable");
        } finally {
            if(pixels!=null) pixels.dispose();finishTests();
        }
    }
    private static function finishTests():Void {
        if(finished) return;finished=true;
        if(pixelProbe!=null && pixelProbe.holder._parent===_root && _root[pixelProbe.name]===pixelProbe.holder
                && pixelProbe.holder.__cf6LoadedMaskTestOwner===pixelProbe.token) {
            delete pixelProbe.holder.onEnterFrame;pixelProbe.holder.removeMovieClip();
        }
        if(pixelProbe!=null && pixelProbe.driver._parent===_root && _root[pixelProbe.driverName]===pixelProbe.driver
                && pixelProbe.driver.__cf6LoadedMaskTestOwner===pixelProbe.token) {
            delete pixelProbe.driver.onEnterFrame;pixelProbe.driver.removeMovieClip();
        }
        pixelProbe=null;
        trace("Cf6MapMechanismTest Tests Passed: "+passed);
        trace("Cf6MapMechanismTest Tests Failed: "+failed);
        if(typeof _root.cf6MapMechanismTestsComplete=="function") _root.cf6MapMechanismTestsComplete();
    }
    public static function runAllTests():Void {
        passed=0;failed=0;finished=false;pixelProbe=null;
        var savedManagerClass:Object=org.flashNight.arki.scene.StageManager;
        var savedManager:Object=savedManagerClass.instance;
        var keys:Array=["gameworld","_saveExt","savePath","当前关卡名","暂停","发布消息","贴背景图","__cf6TestBakeCalls","天空盒","控制目标"];
        var saved:Object={};
        for(var i:Number=0;i<keys.length;i++) saved[keys[i]]=_root[keys[i]];
        var targetClass:Object=org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
        var oldFind:Function=targetClass.findHero;
        targetClass.findHero=function():MovieClip {return _root.gameworld.hero;};
        _root.暂停=false;_root.发布消息=function(message:String):Void {trace(message);};
        try {testPhases();testElevatorPoseOwnership();testLifecycle();testLogicalRunIdentity();testElevatorBake();testBakeReceipts();testDoorSequences();testBackdropLoading();testBackdropFailuresAndIdentity();testBackdropTransfer();testEarlyEmptyWave();testTurretWiring();testTraversalWiring();testTraversalAssetClosure();testImmediateOwnershipAndArt();testEarlyBirthWindow();testLateSceneReadyArrival();testLoadedElevatorMask();}
        catch(error) {check(false,"synchronous suite exception: "+error);}
        finally {
            Cf6MapMechanism.teardown();Cf6TutorialTurretService.teardown();targetClass.findHero=oldFind;savedManagerClass.instance=savedManager;
            for(i=0;i<keys.length;i++) _root[keys[i]]=saved[keys[i]];
        }
        if(pixelProbe==null || !pixelProbe.armed) finishTests();
    }
}
