import org.flashNight.arki.scene.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.LinearBulletMovement;

/**
 * Must run in real CS6/TestLoader. Adoption mode uses createEmptyMovieClip fixtures;
 * load mode drives the public MovieClipLoader handlers synchronously instead of
 * waiting for real network/file callbacks.
 * r15: 归属凭据(adoptToken/token)+一次性加载票据+暂停冻结时钟回归。
 */
class org.flashNight.arki.scene.Cf6TutorialTurretServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var pendingRemovals:Array;
    private static var completion:Function;
    private static var aimShotFresh:Boolean;
    private static function check(value:Boolean,message:String):Void {
        if(value) passed++;else {failed++;trace("[FAIL] Cf6TutorialTurret: "+message);}
    }
    private static function near(a:Number,b:Number):Boolean {return Math.abs(a-b)<0.2;}
    private static function movementEndNear(projectile:MovieClip,screenY:Number,groundZ:Number,
                                            ticks:Number,ratio:Number):Boolean {
        // Real MovieClip positions use 1/20px twips. Repeated fractional writes
        // can lose less than one twip per step; Z consumes that quantized Y.
        // Keep ideal target coordinates and derive the bound from step count,
        // rather than loosening the shared assertion tolerance or the motion.
        var actualY:Number=projectile._y,actualZ:Number=projectile.Z轴坐标;
        if((actualY-actualY)!=0 || (actualZ-actualZ)!=0 || (ratio-ratio)!=0) return false;
        var screenBound:Number=ticks/20+0.0001;
        return Math.abs(actualY-screenY)<screenBound
            && Math.abs(actualZ-groundZ)<screenBound*Math.abs(ratio)+0.0001;
    }
    private static function BQP():Object {return org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;}
    private static function spec2():Object {
        return {assetUrl:"flashswf/backgrounds/cf6/CF6_A01_Turret.swf",adoptToken:"test-adopt",turrets:[
            {x:133.8,y:202.4,facing:"right",name:"turretA"},
            {x:249.8,y:430.9,facing:"right",name:"turretB"}]};
    }
    private static function loadSpec():Object {
        return {assetUrl:"cf6/__nonexistent__/turret.swf",turrets:[
            {x:133.8,y:202.4,facing:"right"},
            {x:249.8,y:430.9,facing:"right"}]};
    }
    private static function fixture(uniqueName:String):MovieClip {
        // Deferred removal checks keep their own parent alive; same-path tests use the fixed name.
        var w:MovieClip=_root.createEmptyMovieClip(
            uniqueName == undefined ? "__cf6TurretFixtureWorld" : uniqueName,
            uniqueName == undefined ? 9399 : _root.getNextHighestDepth());
        _root.gameworld=w;
        _root.savePath="cf6.turret.fixture";
        _root.当前关卡名="书中历险-毒刺行动";
        _root.暂停=false;
        _root._saveExt={bookRun:{bookId:"cf6-sting",routeId:"historical",outcome:"active",
            slot:String(_root.savePath),seed:123,startedAt:1792550000000}};
        _root.__turretTestShots=0;_root.__turretTestLast=null;
        BQP().targetFilterEnabled=true;
        _root.子弹区域shoot传递=function(Obj:Object):Void {
            _root.__turretTestShots++;_root.__turretTestLast=Obj;};
        return w;
    }
    private static function adopted(w:MovieClip,name:String,x:Number,y:Number,depth:Number):MovieClip {
        var mc:MovieClip=w.createEmptyMovieClip(name,depth);
        mc._x=x;mc._y=y;mc.__cf6TurretAdoptToken="test-adopt";
        return mc;
    }
    private static function findHolder(w:MovieClip,index:Number):MovieClip {
        var suffix:String="_"+index;
        for(var k:String in w) {
            if(k.indexOf("__cf6TurretAsset")==0
                && k.substr(k.length-suffix.length)==suffix) return w[k];
        }
        return undefined;
    }
    private static function testNormalizeSpec():Void {
        check(Cf6TutorialTurretService.normalizeSpec(null)==null,"null spec rejected");
        check(Cf6TutorialTurretService.normalizeSpec({})==null,"missing assetUrl rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"a..b.swf",turrets:[{x:1,y:2,facing:"right"}]})==null,"dotdot assetUrl rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.png",turrets:[{x:1,y:2,facing:"right"}]})==null,"non-swf assetUrl rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",linkage:"a..b",turrets:[{x:1,y:2,facing:"right"}]})==null,"dotdot linkage rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",filterMarker:123,turrets:[{x:1,y:2,facing:"right"}]})==null,"non-string filterMarker rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",turrets:[]})==null,"empty turrets rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",turrets:[{x:Number.NaN,y:2,facing:"right"}]})==null,"NaN coordinate rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",turrets:[{x:6000,y:2,facing:"right"}]})==null,"absurd coordinate rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",turrets:[{x:1,y:2,facing:"up"}]})==null,"unknown facing rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",fireIntervalFrames:1,turrets:[{x:1,y:2,facing:"right"}]})==null,"sub-2 interval rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",fireFrameOffset:18,turrets:[{x:1,y:2,facing:"right"}]})==null,"offset beyond interval rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",bulletSpeed:0,turrets:[{x:1,y:2,facing:"right"}]})==null,"zero bullet speed rejected");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",bulletType:"射线子弹",turrets:[{x:1,y:2,facing:"right"}]})==null,"ray bullet type rejected: filter covers only the normal main-queue channel");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",bulletType:"穿刺子弹",turrets:[{x:1,y:2,facing:"right"}]})==null,"pierce bullet type rejected explicitly");
        check(Cf6TutorialTurretService.normalizeSpec({assetUrl:"x.swf",turrets:[{x:1,y:2,facing:"right",name:"turretA"}]})==null,"adoption without adoptToken rejected");
        var norm:Object=Cf6TutorialTurretService.normalizeSpec(spec2());
        check(norm!=null && norm.fireIntervalFrames==18 && norm.fireFrameOffset==11 && norm.scatterDeg==15
            && norm.power==10 && norm.bulletSpeed==20 && norm.zRange==300
            && norm.bulletType=="普通子弹" && norm.hitMapEffect=="无声火花"
            && norm.linkage=="CF6教学炮塔-A01自动炮" && norm.filterMarker=="cf6-a01-turret-zombie"
            && norm.adoptToken=="test-adopt"
            && norm.assetUrl=="flashswf/backgrounds/cf6/CF6_A01_Turret.swf"
            && norm.turrets.length==2 && norm.turrets[0].x==133.8,"original defaults normalized exactly");
        var s:Object={spec:norm};
        var b:Object=Cf6TutorialTurretService.makeBullet(s,{name:"turretA",groundY:202.4},239.05,189.85);
        check(b.子弹种类=="普通子弹" && b.子弹威力==10 && b.子弹速度==20 && b.子弹散射度==15
            && b.发射者=="turretA" && b.shootX==239.05 && b.shootY==189.85 && b.shootZ==202.4
            && b.声音=="无" && b.击中地图效果=="无声火花","bullet config carries original parameters without scaling");
        check(b.仅命中目标标记=="cf6-a01-turret-zombie","bullet carries per-shot target marker for the wired filter");
    }
    private static function testGuards():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        check(!Cf6TutorialTurretService.beginRoom(w,identity,"A02",spec2()),"non-A01 map rejected");
        check(!Cf6TutorialTurretService.beginRoom(w,identity,"教学关",spec2()),"tutorial room has no turrets and is rejected");
        check(Cf6TutorialTurretService.debugState()==null,"guard rejections leave no session");
        Cf6TutorialTurretService.teardown();w.removeMovieClip();
    }
    private static function testGuardsFull():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        check(!Cf6TutorialTurretService.beginRoom(w,{},"A01",spec2()),"stale world identity rejected");
        var other:MovieClip=_root.createEmptyMovieClip("__cf6TurretOtherWorld",9398);
        check(!Cf6TutorialTurretService.beginRoom(other,identity,"A01",spec2()),"non-gameworld container rejected");
        other.removeMovieClip();
        _root._saveExt.bookRun.bookId="repair-campus";
        check(!Cf6TutorialTurretService.beginRoom(w,identity,"A01",spec2()),"foreign book rejected");
        _root._saveExt.bookRun.bookId="cf6-sting";
        _root.当前关卡名="训练场";
        check(!Cf6TutorialTurretService.beginRoom(w,identity,"A01",spec2()),"foreign stage rejected");
        _root.当前关卡名="书中历险-毒刺行动";
        check(Cf6TutorialTurretService.debugState()==null,"rejected binds leave no session");
        Cf6TutorialTurretService.teardown();w.removeMovieClip();
    }
    private static function testAdoptAndFire():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        var a:MovieClip=adopted(w,"turretA",133.8,202.4,101);
        var b:MovieClip=adopted(w,"turretB",249.8,430.9,102);
        check(Cf6TutorialTurretService.beginRoom(w,identity,"A01",spec2()),"adopt pre-placed turrets");
        var st:Object=Cf6TutorialTurretService.debugState();
        check(st!=null && st.count==2 && st.loaded==2 && st.failed!==true,"two turrets adopted without failure");
        check(a.是否为敌人===false && a.方向==="右" && b.是否为敌人===false,"adoption forces friendly faction and facing");
        check(a.等级==35 && a.命中率==100000 && a.伤害加成==0
            && a.Z轴坐标==a._y && typeof a.dispatcher.publish=="function",
            "emitter supplies finite damage pipeline attributes and an owned event dispatcher");
        check(a.__cf6TurretOwner!=undefined && b.__cf6TurretOwner!=undefined
            && a.__cf6TurretOwner!==b.__cf6TurretOwner,"each adopted instance gets its own ownership token");
        check(near(a._x,133.8) && near(a._y,202.4),"adoption never rewrites placed transform");
        for(var i:Number=0;i<10;i++) a.onEnterFrame();
        check(_root.__turretTestShots==0,"no shot before original frame-12 cadence");
        a.onEnterFrame();
        check(_root.__turretTestShots==1,"first shot on eleventh enterFrame like original twelfth timeline frame");
        var shot:Object=_root.__turretTestLast;
        traceAimState("adopt baseline",w,a,shot);
        check(near(shot.shootX,133.8+112.45) && near(shot.shootY,202.4-70.5),"CF7 muzzle uses the original visual flash anchor without rewriting the marker");
        check(shot.发射者=="turretA" && shot.子弹威力==10 && shot.子弹速度==20
            && near(shot.shootZ,a._y),"shot payload binds turret name original power and actual ground row");
        for(i=0;i<17;i++) a.onEnterFrame();
        check(_root.__turretTestShots==1,"no early second shot inside eighteen-frame interval");
        a.onEnterFrame();
        check(_root.__turretTestShots==2,"second shot exactly eighteen frames later");
        for(i=0;i<18;i++) b.onEnterFrame();
        check(_root.__turretTestShots==3,"second turret cycles independently");
        check(Cf6TutorialTurretService.beginRoom(w,identity,"A01",spec2())
            && Cf6TutorialTurretService.debugState().count==2,"duplicate binding never duplicates turrets");
        Cf6TutorialTurretService.teardown();
        check(w.turretA===a && w.turretB===b && w.__cf6TutorialTurrets==undefined
            && a.onEnterFrame==undefined && a.__cf6TurretOwner==undefined
            && Cf6TutorialTurretService.debugState()==null,"teardown preserves adopted clips, removes own callbacks/tokens and clears session marker");
        w.removeMovieClip();
    }
    private static function testPauseClock():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        var a:MovieClip=adopted(w,"turretA",133.8,202.4,101);
        Cf6TutorialTurretService.beginRoom(w,identity,"A01",
            {assetUrl:"x.swf",adoptToken:"test-adopt",turrets:[{x:133.8,y:202.4,facing:"right",name:"turretA"}]});
        for(var i:Number=0;i<11;i++) a.onEnterFrame();
        check(_root.__turretTestShots==1,"baseline shot before pause");
        _root.暂停=true;
        for(i=0;i<25;i++) a.onEnterFrame();
        check(_root.__turretTestShots==1,"paused clock never advances: no shot across 25 paused frames");
        _root.暂停=false;
        for(i=0;i<17;i++) a.onEnterFrame();
        check(_root.__turretTestShots==1,"resume keeps phase: no early or double shot");
        a.onEnterFrame();
        check(_root.__turretTestShots==2,"resume fires exactly eighteen live frames after the previous shot");
        _root.暂停=true;
        for(i=0;i<40;i++) a.onEnterFrame();
        check(_root.__turretTestShots==2,"second pause window stays frozen");
        Cf6TutorialTurretService.teardown();w.removeMovieClip();
    }
    private static function testAdoptionCredential():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        var a:MovieClip=w.createEmptyMovieClip("turretA",101);a._x=133.8;a._y=202.4;
        var foreignMark:Boolean=false;
        a.onEnterFrame=function():Void {foreignMark=true;};
        check(Cf6TutorialTurretService.beginRoom(w,identity,"A01",spec2()),"bind owned even when adoption refused");
        var st:Object=Cf6TutorialTurretService.debugState();
        check(st!=null && st.failed===true,"same-name clip without ownership credential is never adopted");
        a.onEnterFrame();
        check(foreignMark===true && _root.__turretTestShots==0,"foreign callback preserved, never erased, never fires for us");
        check(w.turretA===a,"foreign clip left in place");
        Cf6TutorialTurretService.teardown();w.removeMovieClip();
    }
    private static function testFilterGate():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        BQP().targetFilterEnabled=false;
        var a:MovieClip=adopted(w,"turretA",133.8,202.4,101);
        check(Cf6TutorialTurretService.beginRoom(w,identity,"A01",spec2()),"unwired filter bind is owned then disabled");
        var st:Object=Cf6TutorialTurretService.debugState();
        check(st!=null && st.failed===true && st.count==0,"unwired filter fails closed without entering shooting state");
        for(var i:Number=0;i<40;i++) a.onEnterFrame();
        check(_root.__turretTestShots==0,"unwired filter never fires a single bullet");
        Cf6TutorialTurretService.teardown();
        BQP().targetFilterEnabled=true;
        check(Cf6TutorialTurretService.beginRoom(w,identity,"A01",spec2()),"wired filter adopts after recovery");
        for(i=0;i<11;i++) a.onEnterFrame();
        check(_root.__turretTestShots==1,"wired filter fires normally");
        BQP().targetFilterEnabled=false;
        for(i=0;i<18;i++) a.onEnterFrame();
        check(_root.__turretTestShots==1
            && Cf6TutorialTurretService.debugState().failed===true,"mid-room filter disconnect stops firing immediately");
        BQP().targetFilterEnabled=true;
        Cf6TutorialTurretService.teardown();w.removeMovieClip();
    }
    private static function testLoadMode():Void {
        var w:MovieClip=fixture("__cf6TurretLoadTransformWorld");var identity:Object=StageReturnFlow.worldIdentity(w);
        check(Cf6TutorialTurretService.beginRoom(w,identity,"A01",loadSpec()),"load-mode bind succeeds before asset arrives");
        var st:Object=Cf6TutorialTurretService.debugState();
        check(st!=null && st.count==2 && st.loaded==0 && st.failed!==true,"holders created, waiting for asset");
        var holderA:MovieClip=findHolder(w,0);
        check(holderA!=undefined && holderA.onEnterFrame==undefined && holderA.是否为敌人===undefined,
            "owned wrapper waits for its payload before enabling fire");
        check(near(holderA._x,133.8) && near(holderA._y,202.4),"holder placed at original coordinates");
        var s:Object=w.__cf6TutorialTurrets;
        var t0:Object=s.turrets[0];
        var payloadA:MovieClip=t0.payload;
        var ticket0:Object=t0.loadTicket;
        check(ticket0!=undefined,"one-shot load ticket issued before loadClip");
        check(holderA.__cf6TurretOwner===t0.token && payloadA._parent===holderA,
            "wrapper owns its token before a separate payload is loaded");
        check(t0.loader!==s.turrets[1].loader,"each turret has an independent loader");
        var foreign:MovieClip=_root.createEmptyMovieClip("__cf6ForeignTarget",9400);
        Cf6TutorialTurretService.onAssetInit(s,t0,ticket0,foreign);
        check(Cf6TutorialTurretService.debugState().loaded==0 && t0.loadTicket===ticket0,
            "foreign load target cannot claim the session and the ticket survives");
        foreign.removeMovieClip();
        var staleTicket:Object={};
        payloadA.createEmptyMovieClip("turret",1);
        Cf6TutorialTurretService.onAssetInit(s,t0,staleTicket,payloadA);
        check(Cf6TutorialTurretService.debugState().loaded==0,"forged ticket cannot claim the load");
        Cf6TutorialTurretService.onAssetInit(s,t0,ticket0,payloadA);
        check(Cf6TutorialTurretService.debugState().loaded==1 && t0.loadTicket==null,
            "real ticket marks exactly its own holder loaded and is consumed");
        check(holderA.__cf6TurretOwner===t0.token && holderA.是否为敌人===false && holderA.方向==="右"
            && holderA.onEnterFrame!=undefined,"ownership token, faction and frame callback installed after load");
        Cf6TutorialTurretService.onAssetInit(s,t0,ticket0,payloadA);
        check(Cf6TutorialTurretService.debugState().loaded==1,"consumed ticket makes duplicate onLoadInit a no-op");
        for(var i:Number=0;i<11;i++) holderA.onEnterFrame();
        check(_root.__turretTestShots==1,"loaded turret fires on original cadence");
        var shot:Object=_root.__turretTestLast;
        traceAimState("load-mode baseline",w,holderA,shot);
        check(shot.发射者==holderA._name && shot.仅命中目标标记=="cf6-a01-turret-zombie"
            && near(shot.shootX,133.8+112.45) && near(shot.shootY,202.4-70.5),
            "load-mode shot resolves holder as shooter with target marker and visual muzzle offset");
        delete holderA.__cf6TurretOwner;
        for(i=0;i<40;i++) holderA.onEnterFrame();
        check(_root.__turretTestShots==1,"holder without the instance token cannot advance the clock");
        var holderName:String=holderA._name;
        Cf6TutorialTurretService.teardown();
        check(w[holderName]!=undefined && w.__cf6TutorialTurrets==undefined,
            "teardown cannot delete a wrapper whose ownership credential was revoked");
        Cf6TutorialTurretService.onAssetInit(s,t0,ticket0,payloadA);
        check(Cf6TutorialTurretService.debugState()==null,"late onLoadInit after teardown claims nothing");
        w.removeMovieClip();
    }
    private static function testOwnedLoadCleanup():Void {
        var w:MovieClip=fixture("__cf6TurretCleanupWorld");var identity:Object=StageReturnFlow.worldIdentity(w);
        Cf6TutorialTurretService.beginRoom(w,identity,"A01",loadSpec());
        var s:Object=w.__cf6TutorialTurrets;
        var t:Object=s.turrets[0];var other:Object=s.turrets[1];
        var name:String=t.name;var otherName:String=other.name;
        var ticket:Object=t.loadTicket;
        Cf6TutorialTurretService.onAssetError(s,t,ticket,other.payload,"wrong-target");
        check(s.failed!==true && t.loadTicket===ticket,"another loader target cannot consume a ticket or fail the room");
        Cf6TutorialTurretService.teardown();
        queueRemovalCheck(w,[name,otherName],"pending owned wrappers are removed after the real unload phase");
        check(t.loadTicket==null && t.listener==null && t.loader==null,"pending cleanup retires ticket listener and loader");

        Cf6TutorialTurretService.beginRoom(w,identity,"A01",loadSpec());
        s=w.__cf6TutorialTurrets;t=s.turrets[0];name=t.name;
        t.payload.createEmptyMovieClip("turret",1);
        Cf6TutorialTurretService.onAssetInit(s,t,t.loadTicket,t.payload);
        check(t.loaded===true,"owned cleanup fixture reaches loaded state");
        Cf6TutorialTurretService.teardown();
        queueRemovalCheck(w,[name],"loaded wrapper is removed without deleting its token too early");

        Cf6TutorialTurretService.beginRoom(w,identity,"A01",loadSpec());
        s=w.__cf6TutorialTurrets;t=s.turrets[0];name=t.name;ticket=t.loadTicket;
        var oldPayload:MovieClip=t.payload;
        var oldHolder:MovieClip=w[name];var oldDepth:Number=oldHolder.getDepth();
        oldHolder.removeMovieClip();
        var replacement:MovieClip=w.createEmptyMovieClip(name,oldDepth);
        replacement.createEmptyMovieClip(t.payloadName,1).createEmptyMovieClip("turret",1);
        var foreignCallback:Function=function():Void {};
        replacement.onEnterFrame=foreignCallback;
        Cf6TutorialTurretService.onAssetInit(s,t,ticket,oldPayload);
        check(t.loaded!==true && replacement.__cf6TurretOwner==undefined,
            "late init cannot claim a same-world same-path replacement wrapper");
        Cf6TutorialTurretService.onAssetError(s,t,ticket,oldPayload,"late-error");
        check(s.failed!==true,"late error cannot claim replacement wrapper ownership");
        Cf6TutorialTurretService.teardown();
        check(w[name]===replacement && replacement.onEnterFrame===foreignCallback,
            "cleanup preserves replacement wrapper and its callback");
        // Keep this parent alive until the deferred checks prove its owned children disappeared.
    }
    private static function testLateLoadCrossRoom():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        Cf6TutorialTurretService.beginRoom(w,identity,"A01",loadSpec());
        var s1:Object=w.__cf6TutorialTurrets;
        var t1:Object=s1.turrets[0];
        var ticket1:Object=t1.loadTicket;
        Cf6TutorialTurretService.teardown();
        w.removeMovieClip();
        var w2:MovieClip=fixture();var identity2:Object=StageReturnFlow.worldIdentity(w2);
        check(Cf6TutorialTurretService.beginRoom(w2,identity2,"A01",loadSpec()),"same-path replacement world binds fresh session");
        var holderA2:MovieClip=findHolder(w2,0);
        var payloadA2:MovieClip=w2.__cf6TutorialTurrets.turrets[0].payload;
        payloadA2.createEmptyMovieClip("turret",1);
        Cf6TutorialTurretService.onAssetInit(s1,t1,ticket1,payloadA2);
        check(Cf6TutorialTurretService.debugState().loaded==0,"late load from torn-down session cannot claim same-path new room");
        Cf6TutorialTurretService.onAssetError(s1,t1,ticket1,payloadA2,"URLNotFound");
        check(Cf6TutorialTurretService.debugState().failed!==true,"late load error from torn-down session cannot fail new room");
        Cf6TutorialTurretService.teardown();w2.removeMovieClip();
    }
    private static function testSamePathRebuild():Void {
        var w:MovieClip=fixture();var identity:Object=StageReturnFlow.worldIdentity(w);
        var a:MovieClip=adopted(w,"turretA",133.8,202.4,101);
        Cf6TutorialTurretService.beginRoom(w,identity,"A01",
            {assetUrl:"x.swf",adoptToken:"test-adopt",turrets:[{x:133.8,y:202.4,facing:"right",name:"turretA"}]});
        var staleCallback:Function=a.onEnterFrame;
        for(var i:Number=0;i<11;i++) a.onEnterFrame();
        check(_root.__turretTestShots==1,"baseline shot before rebuild");
        w.removeMovieClip();
        var replacement:MovieClip=fixture();
        var replacementShots:Number=_root.__turretTestShots;
        var ra:MovieClip=replacement.createEmptyMovieClip("turretA",101);
        for(i=0;i<40;i++) staleCallback();
        check(_root.__turretTestShots==replacementShots,"stale callback cannot fire into a same-path replacement world");
        check(ra.onEnterFrame==undefined,"replacement clip untouched by stale session");
        check(Cf6TutorialTurretService.beginRoom(replacement,StageReturnFlow.worldIdentity(replacement),"A01",
            {assetUrl:"x.swf",adoptToken:"test-adopt",turrets:[{x:133.8,y:202.4,facing:"right",name:"turretA"}]})==true,
            "fresh session owns the rejected bind without adopting the foreign clip");
        check(Cf6TutorialTurretService.debugState()!=null
            && Cf6TutorialTurretService.debugState().failed===true,"credential-less rebind fails closed");
        ra.__cf6TurretAdoptToken="test-adopt";
        Cf6TutorialTurretService.teardown();
        check(Cf6TutorialTurretService.beginRoom(replacement,StageReturnFlow.worldIdentity(replacement),"A01",
            {assetUrl:"x.swf",adoptToken:"test-adopt",turrets:[{x:133.8,y:202.4,facing:"right",name:"turretA"}]}),
            "credentialed replacement binds fresh session");
        for(i=0;i<11;i++) ra.onEnterFrame();
        check(_root.__turretTestShots==replacementShots+1,"fresh session fires on the credentialed replacement");
        Cf6TutorialTurretService.teardown();replacement.removeMovieClip();
    }
    private static function testFailurePaths():Void {
        var w:MovieClip=fixture("__cf6TurretFailedLoadWorld");var identity:Object=StageReturnFlow.worldIdentity(w);
        check(Cf6TutorialTurretService.beginRoom(w,identity,"A01",loadSpec()),"load-mode bind owned before asset error");
        var s:Object=w.__cf6TutorialTurrets;
        var t0:Object=s.turrets[0];
        var holderA:MovieClip=findHolder(w,0);
        var holderName:String=holderA._name;
        Cf6TutorialTurretService.onAssetError(s,t0,t0.loadTicket,t0.payload,"URLNotFound");
        var st:Object=Cf6TutorialTurretService.debugState();
        check(st!=null && st.failed===true && st.count==0,"asset load error fails closed");
        queueRemovalCheck(w,[holderName],"failed load removes owned holder");
        Cf6TutorialTurretService.onAssetError(s,t0,t0.loadTicket,holderA,"URLNotFound");
        check(Cf6TutorialTurretService.debugState().failed===true,"consumed ticket cannot re-fail the session");
        Cf6TutorialTurretService.teardown();
        var a:MovieClip=adopted(w,"turretA",133.8,202.4,101);a.是否为敌人=true;
        Cf6TutorialTurretService.beginRoom(w,identity,"A01",spec2());
        st=Cf6TutorialTurretService.debugState();
        check(st!=null && st.failed===true,"enemy-faction clip cannot be adopted as a friendly turret");
        Cf6TutorialTurretService.teardown();
    }
    // Temporary numeric evidence for field-repair AVM1 failures; no production state changes.
    private static function traceAimState(label:String,w:MovieClip,holder:MovieClip,shot:Object):Void {
        var s:Object=w.__cf6TutorialTurrets;
        var t:Object=s.turrets[0];
        var inner:MovieClip=t.inner;
        var origin:MovieClip=inner!=undefined ? inner : holder;
        var point:Object={x:t.muzzleLocal.x,y:t.muzzleLocal.y};
        origin.localToGlobal(point);w.globalToLocal(point);
        trace("[CF6_AIM_DIAG] "+label+" shots="+_root.__turretTestShots+" fresh="+aimShotFresh
            +" shot="+shot.shootX+","+shot.shootY+","+shot.shootZ
            +" velocity="+shot.速度X+","+shot.速度Y+" ratio="+shot.ZY比例
            +" marker="+shot.仅命中目标标记+" bullet="+shot.子弹种类+" emitter="+shot.发射者);
        trace("[CF6_AIM_TRANSFORM] world="+String(w)+" current="+(_root.gameworld===w)
            +" worldIdentity="+(w.__stageReturnWorldIdentity===s.owner)
            +" worldXYScale="+w._x+","+w._y+","+w._xscale+","+w._yscale
            +" holder="+String(holder)+" depth="+holder.getDepth()
            +" holderXYScaleRot="+holder._x+","+holder._y+","+holder._xscale+","+holder._yscale+","+holder._rotation
            +" token="+(holder.__cf6TurretOwner===t.token)+" inner="+String(inner)
            +" innerIsHolder="+(inner===holder)+" innerParent="+String(inner._parent)
            +" innerXYScaleRot="+inner._x+","+inner._y+","+inner._xscale+","+inner._yscale+","+inner._rotation
            +" local="+t.muzzleLocal.x+","+t.muzzleLocal.y+" recomputedWorld="+point.x+","+point.y);
        for(var key:String in w) {
            var candidate=w[key];
            if(typeof candidate=="movieclip" && candidate.hp!==undefined) {
                trace("[CF6_AIM_TARGET] key="+key+" path="+String(candidate)+" parentMatches="+(candidate._parent===w)
                    +" xyZ="+candidate._x+","+candidate._y+","+candidate.Z轴坐标
                    +" hp="+candidate.hp+" enemy="+candidate.是否为敌人+" marker="+candidate.目标标记
                    +" center="+org.flashNight.arki.unit.UnitUtil.calculateCenterOffset(candidate));
            }
        }
    }
    private static function aimTarget(w:MovieClip,name:String,x:Number,z:Number):MovieClip {
        var enemy:MovieClip=w.createEmptyMovieClip(name,w.getNextHighestDepth());
        enemy._x=x;enemy._y=z;enemy.Z轴坐标=z;enemy.hp=100;
        enemy.是否为敌人=true;enemy.目标标记="cf6-a01-turret-zombie";
        enemy.中心高度=50;enemy.身高=175;
        return enemy;
    }
    private static function shotAfter(holder:MovieClip,ticks:Number):Object {
        var before:Number=_root.__turretTestShots;
        for(var i:Number=0;i<ticks;i++) holder.onEnterFrame();
        aimShotFresh=_root.__turretTestShots==before+1;
        traceAimState("shotAfter ticks="+ticks,holder._parent,holder,_root.__turretTestLast);
        return _root.__turretTestLast;
    }
    private static function advanceAim(w:MovieClip,shot:Object,ticks:Number):MovieClip {
        var projectile:MovieClip=w.createEmptyMovieClip("__crossRowProjectile",w.getNextHighestDepth());
        projectile._x=shot.shootX;projectile._y=shot.shootY;projectile.Z轴坐标=shot.shootZ;
        Cf6TutorialTurretService.bindFlight(w,StageReturnFlow.worldIdentity(w),projectile,shot);
        for(var i:Number=0;i<ticks;i++) projectile.updateMovement(projectile);
        trace("[CF6_AIM_MOVEMENT] ticks="+ticks+" endpoint="+projectile._x+","+projectile._y+","+projectile.Z轴坐标
            +" initial="+shot.shootX+","+shot.shootY+","+shot.shootZ
            +" velocity="+shot.速度X+","+shot.速度Y+" ratio="+shot.ZY比例);
        return projectile;
    }
    private static function testCrossRowAim():Void {
        var w:MovieClip=fixture("__cf6TurretCrossRowRightWorld");var identity:Object=StageReturnFlow.worldIdentity(w);
        var a:MovieClip=adopted(w,"turretA",133.8,202.4,101);
        Cf6TutorialTurretService.beginRoom(w,identity,"A01",
            {assetUrl:"x.swf",adoptToken:"test-adopt",turrets:[{x:133.8,y:202.4,facing:"right",name:"turretA"}]});
        var enemy:MovieClip=aimTarget(w,"marked",446.25,102.4);
        var shot:Object=shotAfter(a,11);
        check(near(shot.shootX,246.25) && near(shot.shootY,131.9) && near(shot.shootZ,202.4),
            "cross-row shot starts at visual muzzle with the actual source ground row");
        check(near(shot.速度X,20) && shot.速度Y<0 && shot.ZY比例>0
            && shot.仅命中目标标记=="cf6-a01-turret-zombie" && shot.子弹种类=="普通子弹",
            "upper-row aim keeps the normal bullet and exact target filter");
        var projectile:MovieClip=advanceAim(w,shot,10);
        check(near(projectile._x,enemy._x) && movementEndNear(projectile,enemy._y-50,enemy.Z轴坐标,10,shot.ZY比例),
            "local affine flight reaches upper-row center and ground Z together");
        projectile.removeMovieClip();
        enemy._y=352.4;enemy.Z轴坐标=352.4;
        shot=shotAfter(a,18);
        check(shot.速度Y>0 && Math.abs(shot.速度Y)<=20 && Math.abs(shot.速度X)<=20,
            "lower-row aiming supplies bounded positive screen-Y velocity");
        projectile=advanceAim(w,shot,10);
        check(near(projectile._x,enemy._x) && movementEndNear(projectile,enemy._y-50,enemy.Z轴坐标,10,shot.ZY比例),
            "real LinearBulletMovement reaches lower-row center and ground Z together");
        check(projectile._y<projectile.Z轴坐标,"lower-row aimed bullet remains above its ground row at the target");
        projectile.removeMovieClip();
        enemy.目标标记=undefined;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined && shot.速度Y===undefined && shot.ZY比例===undefined,
            "same unit without the exact 630 marker falls back to horizontal scatter");
        enemy.目标标记="other-marker";
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"a different target marker cannot acquire cross-row aim");
        enemy.目标标记="cf6-a01-turret-zombie";enemy.hp=0;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"dead marked target is not aimed at");
        enemy.hp=100;enemy._x=200;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"marked target behind the muzzle is not aimed at");
        enemy._x=1300;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"target outside the finite 900px world range is rejected");
        enemy._x=446.25;enemy.是否为敌人=false;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"friendly marked clip is never a targeting candidate");
        enemy.是否为敌人=true;enemy._x=246.25;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"zero horizontal distance is rejected before division");
        enemy._x=446.25;enemy._y=50;enemy.Z轴坐标=50;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"zero target center denominator is rejected");
        enemy.中心高度=Number.NaN;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"non-finite target center is rejected before trajectory calculation");
        enemy.中心高度=50;
        enemy._y=352.4;enemy.Z轴坐标=Number.POSITIVE_INFINITY;
        shot=shotAfter(a,18);
        check(aimShotFresh && shot.速度X===undefined,"non-finite target ground coordinate is rejected");
        enemy._x=266.25;enemy._y=581.9;enemy.Z轴坐标=581.9;
        shot=shotAfter(a,18);
        check(near(shot.速度X,1) && near(shot.速度Y,20),"steep cross-row trajectory caps its largest speed component");
        projectile=advanceAim(w,shot,20);
        check(near(projectile._x,enemy._x) && movementEndNear(projectile,531.9,581.9,20,shot.ZY比例),
            "real movement reaches the steep target after speed capping");
        projectile.removeMovieClip();
        enemy._x=446.25;enemy._y=352.4;enemy.Z轴坐标=352.4;
        var closer:MovieClip=aimTarget(w,"closer",346.25,252.4);
        shot=shotAfter(a,18);
        check(near(shot.速度Y,20*(202.4-131.9)/100),"nearest eligible current-world target is selected");
        closer.removeMovieClip();enemy.removeMovieClip();
        var shotsBefore:Number=_root.__turretTestShots;
        shot=shotAfter(a,18);
        check(aimShotFresh && _root.__turretTestShots==shotsBefore+1 && shot.速度X===undefined && shot.子弹散射度==15,
            "target removal preserves one original-cadence horizontal-scatter shot without stale aim fields");
        var stale:Function=a.onEnterFrame;
        w.removeMovieClip();
        var replacement:MovieClip=fixture();
        aimTarget(replacement,"marked",446.25,352.4);
        shotsBefore=_root.__turretTestShots;
        for(var i:Number=0;i<40;i++) stale();
        check(_root.__turretTestShots==shotsBefore,"old-world aim callback cannot shoot at marked targets in a replacement world");
        Cf6TutorialTurretService.teardown();replacement.removeMovieClip();

        w=fixture("__cf6TurretCrossRowLeftWorld");identity=StageReturnFlow.worldIdentity(w);
        a=adopted(w,"turretA",600,202.4,101);a._xscale=-100;
        Cf6TutorialTurretService.beginRoom(w,identity,"A01",
            {assetUrl:"x.swf",adoptToken:"test-adopt",turrets:[{x:600,y:202.4,facing:"left",name:"turretA"}]});
        aimTarget(w,"marked",287.55,302.4);
        shot=shotAfter(a,11);
        check(near(shot.shootX,487.55) && shot.速度X<0,"left-facing wrapper mirrors visual muzzle and aims only forward");
        var inner:MovieClip=a.createEmptyMovieClip("visual",1);
        inner._x=5;inner._y=-7;inner._xscale=50;inner._yscale=125;
        inner.createEmptyMovieClip("枪口位置2",1)._y=999;
        w.__cf6TutorialTurrets.turrets[0].inner=inner;
        shot=shotAfter(a,18);
        check(near(shot.shootX,600-(5+112.45*0.5)) && near(shot.shootY,202.4-7-70.5*1.25),
            "visual muzzle uses real nested transforms and ignores the retained original marker");
        Cf6TutorialTurretService.teardown();w.removeMovieClip();
    }
    private static function queueRemovalCheck(world:MovieClip,names:Array,message:String):Void {
        pendingRemovals.push({worldName:world._name,owner:StageReturnFlow.worldIdentity(world),
            names:names,message:message});
    }
    public static function finishPendingRemovals():Void {
        // These removals were requested in script phase. This real enterFrame follows load flush.
        for(var i:Number=0;i<pendingRemovals.length;i++) {
            var row:Object=pendingRemovals[i];
            var world:MovieClip=_root[row.worldName];
            var removed:Boolean=world!=undefined && world._parent===_root
                && StageReturnFlow.worldIdentity(world)===row.owner;
            for(var j:Number=0;j<row.names.length;j++)
                if(world[row.names[j]]!=undefined) removed=false;
            check(removed,row.message);
        }
        // Parents are removed only after every child-removal assertion; no parent deletion can pass one.
        for(i=0;i<pendingRemovals.length;i++) {
            row=pendingRemovals[i];world=_root[row.worldName];
            if(world!=undefined && StageReturnFlow.worldIdentity(world)===row.owner) world.removeMovieClip();
        }
        pendingRemovals=[];
        var probe:MovieClip=_root.__cf6TurretCleanupCheck;
        delete probe.onEnterFrame;
        trace("Cf6TutorialTurretServiceTest Tests Passed: "+passed);
        trace("Cf6TutorialTurretServiceTest Tests Failed: "+failed);
        var done:Function=completion;completion=null;
        if(typeof done=="function") done();
        probe.removeMovieClip();
    }
    public static function setCompletionCallback(done:Function):Void { completion=done; }
    public static function runAllTests():Void {
        passed=0;failed=0;pendingRemovals=[];
        var keys:Array=["gameworld","_saveExt","savePath","当前关卡名","暂停","发布消息","子弹区域shoot传递",
            "子弹目标过滤启用","__turretTestShots","__turretTestLast"];
        var saved:Object={};
        for(var i:Number=0;i<keys.length;i++) saved[keys[i]]=_root[keys[i]];
        var savedFilter:Boolean=BQP().targetFilterEnabled;
        _root.发布消息=function(message:String):Void {trace(message);};
        try {testNormalizeSpec();testGuards();testGuardsFull();testAdoptAndFire();testPauseClock();
            testAdoptionCredential();testFilterGate();
            testLoadMode();testOwnedLoadCleanup();testLateLoadCrossRoom();testSamePathRebuild();testFailurePaths();testCrossRowAim();}
        finally {
            Cf6TutorialTurretService.teardown();
            BQP().targetFilterEnabled=savedFilter;
            for(i=0;i<keys.length;i++) _root[keys[i]]=saved[keys[i]];
        }
        var probe:MovieClip=_root.createEmptyMovieClip("__cf6TurretCleanupCheck",_root.getNextHighestDepth());
        probe.onEnterFrame=function():Void {
            org.flashNight.arki.scene.Cf6TutorialTurretServiceTest.finishPendingRemovals();
        };
    }
}
