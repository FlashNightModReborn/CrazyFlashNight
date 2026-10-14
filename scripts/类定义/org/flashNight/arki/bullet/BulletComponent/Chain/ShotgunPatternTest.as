import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.render.ChainVisualBridge;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.StatHandler.DodgeHandler;

/** 真实 CS6：新分配入口、真实伤害链、自然退场与聚合成本；不写玩家存档。 */
class org.flashNight.arki.bullet.BulletComponent.Chain.ShotgunPatternTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var clipId:Number;
    private static var dice:Number;
    private static var damages:Number;
    private static var shields:Number;
    private static var hooks:Number;
    private static var events:Number;
    private static var displays:Number;
    private static var createdClips:Number;
    private static var savedDisplay:Function;
    private static var lastResult:Object;
    private static var forcedDodge:String;
    private static var queueCache:Object;
    private static var realDamage:Function;
    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] ShotgunPatternTest: " + name); }
    }
    private static function acquireClip(type:String):MovieClip {
        createdClips++;
        var zone:MovieClip = _root.gameworld.子弹区域;
        return zone.createEmptyMovieClip("shotUnit" + (++clipId), zone.getNextHighestDepth());
    }
    private static function releaseClip(clip:MovieClip):Void { clip.removeMovieClip(); }
    private static function randomOffset(span:Number):Number {
        // 均匀且固定的生成角度，只用于可重复的自然运动/包围盒用例。
        return ((clipId++ % 17) / 16 * 2 - 1) * span;
    }
    private static function caps():Object {
        return {version:1, mode:"native", maxUnits:15360,
            styles:[{gunChainUnitLinkage:"单元体-普通子弹"}, {gunChainUnitLinkage:"单元体-加强普通子弹"},
                {gunChainUnitLinkage:null}, {gunChainUnitLinkage:null}, {gunChainUnitLinkage:null},
                {gunChainUnitLinkage:"单元体-穿刺子弹"}, {gunChainUnitLinkage:"单元体-次级穿刺子弹"},
                {gunChainUnitLinkage:"单元体-无壳穿刺子弹"}],
            gunChainPrefixes:["横向联弹", "横向机枪联弹", "横向手枪联弹",
                "纵向联弹", "纵向机枪联弹", "纵向手枪联弹"]};
    }
    private static function makeGroup(count:Number, marker:Number, nativeMode:Boolean, flags:Number):ChainGroup {
        var b:Object = {子弹种类:"横向联弹-普通子弹", baseAsset:"横向联弹", 霰弹值:count,
            霰弹分配模式:marker, flags:flags, 子弹散射度:20, xmov:25, ymov:0,
            _x:0, _y:-100, _rotation:0, _xscale:100, _yscale:100, _alpha:100, _visible:true,
            Z轴坐标:0, stateFlags:0, 子弹威力:100, 最小霰弹值:1, 固伤:0, 百分比伤害:0,
            伤害类型:"物理", 命中率:100, hitCount:0};
        b.removeMovieClip = function():Void {
            this.__chainDead = true;
            ChainUnitManager.removeGroup(this.chainGroup);
        };
        var g:ChainGroup = new ChainGroup(null, b, _root.联弹系统.横向联弹更新, _root.联弹系统.渲染组);
        b.chainGroup = g;
        g.isObject = true;
        g.盒x = -5; g.盒y = -5; g.盒宽 = 10; g.盒高 = 10;
        g.盒固有半宽 = 12.5; g.盒固有半高 = 12.5;
        if (nativeMode) ChainVisualBridge.reserveGroup(g);
        _root.联弹系统.横向联弹组装(g);
        return g;
    }
    private static function setBand(g:ChainGroup):Void {
        g.bullet._x = 0; g.bullet._y = 0;
        g.盒x = -5; g.盒宽 = 10; g.盒y = -50; g.盒高 = 100;
        g.ma = 1; g.mb = 0; g.mc2 = 0; g.md = 1;
        // 几何/记账夹具；真实衰减推进另由 Calibration suite 对照旧生产更新。
        g.shotgun.reference.盒x=-5; g.shotgun.reference.盒宽=10;
        g.shotgun.reference.盒y=-50; g.shotgun.reference.盒高=100;
    }
    private static function geometryAndScope():Void {
        var g:ChainGroup = makeGroup(8, 1, false, 66);
        setBand(g);
        var p:ShotgunPattern = g.shotgun;
        check(p != null, "standard player shotgun opts in");
        check(p.calculateCap(g, {left:-5,right:5,top:-50,bottom:50},0) == 8, "close full envelope can use all eight");
        check(p.calculateCap(g, {left:-5,right:5,top:-12.5,bottom:12.5},0) == 8, "old effective envelope overlap retains eight at birth");
        check(p.calculateCap(g, {left:-5,right:5,top:0,bottom:0.001},0) == 8, "thin positive overlap retains old group-level rule");
        check(p.calculateCap(g, {left:6,right:9,top:-50,bottom:50},0) == 0, "local flight-axis separation rejects broad false positive");
        check(p.calculateCap(g, {left:-5,right:5,top:51,bottom:70},0) == 0, "scatter-axis separation rejects");
        check(p.calculateCap(g, {left:NaN,right:5,top:-5,bottom:5},0) == 0, "invalid target geometry rejects");
        check(p.projectionBuilds == 1, "one inverse projection shared by all candidates in one update");
        g.ma = 0; g.mb = 1; g.mc2 = -1; g.md = 0; p.age++;
        check(p.calculateCap(g, {left:-12.5,right:12.5,top:-5,bottom:5},0) == 8, "90 degree shot uses expanded group rather than fixed OBB");
        g.ma = -2; g.mb = 0; g.mc2 = 0; g.md = 1; p.age++;
        check(p.calculateCap(g, {left:-10,right:10,top:-12.5,bottom:12.5},0) == 8, "mirrored scale preserves target coverage");
        g.ma = 0; g.md = 0; p.age++;
        check(p.calculateCap(g, {left:-10,right:10,top:-5,bottom:5},0) == 0, "singular group transform rejects");
        g.ma = 1; g.md = 1; p.age++;
        var zone:MovieClip = _root.gameworld.子弹区域;
        zone._rotation = 90; zone._x = 50; zone._y = 20;
        AABBCollider.zoneFrame = -1;
        check(p.calculateCap(g, {left:37.5,right:62.5,top:15,bottom:25},0) == 8, "real transformed bullet zone composes correctly");
        zone._rotation = 0; zone._x = 0; zone._y = 0;
        AABBCollider.zoneFrame = -1;
        var diagonal:Number=Math.sqrt(0.5);
        g.ma=diagonal; g.mb=diagonal; g.mc2=-diagonal; g.md=diagonal; p.age++;
        p.reference.盒y=-10; p.reference.盒高=20;
        check(p.calculateCap(g,{left:-100,right:100,top:16,bottom:17},0)==0,
            "world SAT rejects reference corner false positive within the wider actual envelope");
        ChainUnitManager.removeGroup(g);
        var masks:Array = [4,8,1,32];
        for (var i:Number=0; i<masks.length; i++) {
            g = makeGroup(8,1,false,2 | masks[i]);
            check(g.shotgun == null, "legacy special mask " + masks[i] + " excluded");
            ChainUnitManager.removeGroup(g);
        }
        g = makeGroup(8,0,false,66);
        check(g.shotgun == null, "unmarked NPC and old producers retain legacy mode");
        ChainUnitManager.removeGroup(g);
        var actor:Object = {被动技能:{}, 是否为敌人:false, 长枪数据:{weapontype:"霰弹枪"}, 手枪数据:{weapontype:"霰弹枪"}};
        var wd:Array = [];
        wd.split=8; wd.diffusion=20; wd.bullet="横向联弹-普通子弹"; wd.power=100; wd.impact=15;
        var props:Object = ShootInitCore.generateBulletProps(actor,"长枪",wd,{});
        check(props.霰弹分配模式 == 1, "real long-gun initialization supplies marker");
        props = ShootInitCore.generateBulletProps(actor,"手枪",wd,{});
        check(props.霰弹分配模式 == 1, "real pistol initialization supplies marker");
        actor.是否为敌人=true;
        props = ShootInitCore.generateBulletProps(actor,"长枪",wd,{});
        check(props.霰弹分配模式 == 0, "enemy shotgun never opts in");
        actor.是否为敌人=false; actor.长枪数据.weapontype="步枪";
        props = ShootInitCore.generateBulletProps(actor,"长枪",wd,{});
        check(props.霰弹分配模式 == 0, "other weapon families never opt in");
    }
    private static function counters():Void { dice=0; damages=0; shields=0; hooks=0; events=0; displays=0; }
    private static function makeTarget():Object {
        var t:Object = {hp:5000,hp满血值:5000,防御力:300,重量:50,等级:50,懒闪避:0,
            _x:0,_y:0,_name:"samePath",Z轴坐标:0,魔法抗性:{基础:0,冰:0}};
        t.dispatcher = {publish:function():Void { events++; }};
        t.shield = {absorbDamage:function(d:Number,bypass:Boolean,n:Number):Number { shields++; return d; }};
        return t;
    }
    private static function makeCtx(g:ChainGroup):Object {
        var dodge:Object = {calcDodgeResult:function():Number { dice++; return 0; },
            calculateDodgeState:function():String { return forcedDodge; }};
        var damage:Object = {calculateDamage:function(b,s,t,m,ds):Object {
            damages++;
            lastResult = DamageCalculator.calculateDamage(b,s,t,m,ds);
            savedDisplay = lastResult.triggerDisplay;
            lastResult.triggerDisplay = function():Void { displays++; };
            return lastResult;
        }};
        g.bullet.damageManager = DamageManagerFactory.resolveForBullet(g.bullet);
        g.bullet.击中时触发函数 = function():Void { hooks++; };
        return {bullet:g.bullet,shooter:{伤害加成:0,dispatcher:{publish:function():Void { events++; }}},
            Dodge:dodge,Damage:damage,flags:g.bullet.flags,meleeMask:33};
    }
    private static function settle(ctx:Object,t:Object,area:Object):Object {
        var api:Object = org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var r:Object = api.settleShotgunHit(ctx,t,{overlapCenter:{x:0,y:0}},area,0);
        if (r != null) r.triggerDisplay = savedDisplay;
        return r;
    }
    private static function budgetAndContacts(magic:Boolean):Void {
        var api:Object = org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var g:ChainGroup = makeGroup(8,1,false,magic ? 2 : 66);
        if (magic) { g.bullet.伤害类型="魔法"; g.bullet.魔法伤害属性="冰"; }
        setBand(g); g.shotgun.reference.bullet.霰弹值=2; counters(); forcedDodge="未躲闪";
        var ctx:Object = makeCtx(g);
        var area:Object = {left:-5,right:5,top:-12.5,bottom:12.5};
        var first:Object = makeTarget();
        api.__initDeferScatter(g.bullet);
        var used:Number = 0;
        for (var i:Number=0;i<4;i++) {
            var t:Object = i == 0 ? first : makeTarget();
            var r:Object = settle(ctx,t,area);
            check(r.actualScatterUsed == 2 && t.hp < 5000, "real " + (magic?"magic":"physical") + " contact limited to two");
            used += r.actualScatterUsed;
            check(g.bullet.霰弹值 < -65535, "segment cap never overwrites encoded shadow window");
            if (i == 0) {
                var oldHp:Number = first.hp;
                g.shotgun.age++;
                check(settle(ctx,first,area) == null && first.hp == oldHp && dice == 1 && damages == 1,
                    "same target in a later update rejected before dodge and damage");
            }
        }
        check(used == 8 && !ShotgunPattern.hasBudget(g.bullet), "four distinct numeric identities share exactly eight segments");
        check(settle(ctx,makeTarget(),area) == null && dice == 4 && damages == 4 && shields == 4 && hooks == 4 && events == 4 && displays == 4,
            "exhausted fifth candidate has no RNG shield hook event or display");
        api.__commitDeferScatter(g.bullet);
        check(g.bullet.霰弹值 == 0, "shadow commit records exact zero");
        _root.联弹系统.对象联弹消失(g.bullet);
        check(g.__removed && g.bullet.__chainDead && g.单元体列表.length == 0, "normal queue vanish retires zero-budget whole group");
    }
    private static function missAndLastPellet():Void {
        var api:Object = org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var g:ChainGroup = makeGroup(8,1,false,66); setBand(g); g.shotgun.reference.bullet.霰弹值=2; counters(); forcedDodge="躲闪";
        var ctx:Object = makeCtx(g); var t:Object=makeTarget(); t.等级=100; t.重量=0;
        api.__initDeferScatter(g.bullet);
        var r:Object=settle(ctx,t,{left:-5,right:5,top:-12.5,bottom:12.5});
        check(r.actualScatterUsed == 2 && r.scatterModelEnabled && r.scatterMissCount == 2 && t.hp == 5000 && !ctx.actualHit, "all-segment MISS still consumes two attempts");
        check(hooks == 0 && events == 0 && settle(ctx,t,{left:-5,right:5,top:-50,bottom:50}) == null && dice == 1 && damages == 1,
            "MISS cannot retry or publish impact in next contact");
        api.__commitDeferScatter(g.bullet);
        check(g.bullet.霰弹值 == 6 && g.单元体列表.length == 6, "positive commit trims visual units exactly once");
        ChainUnitManager.removeGroup(g);
        g=makeGroup(1,1,false,66); setBand(g); counters(); forcedDodge="未躲闪"; ctx=makeCtx(g);
        _root.联弹系统.对象联弹消失(g.bullet);
        check(!g.__removed && !g.bullet.__chainDead, "remaining one survives vanish request");
        api.__initDeferScatter(g.bullet);
        r=settle(ctx,makeTarget(),{left:-5,right:5,top:-50,bottom:50});
        api.__commitDeferScatter(g.bullet);
        check(r.actualScatterUsed == 1 && g.bullet.霰弹值 == 0, "last pellet produces one actual segment");
        _root.联弹系统.对象联弹消失(g.bullet);
        check(g.__removed, "last pellet consumed retires immediately");
    }
    private static function lifecycleAndCost():Void {
        ChainVisualBridge.configure(caps());
        var before:Number=createdClips;
        var g:ChainGroup=makeGroup(4096,1,true,66);
        check(g.nativeGroupOwned && g.aggregate && createdClips == before, "native shotgun uses no hidden pellet MC");
        g.bullet.Z轴坐标=1000000; g.衰竭计数器=1000000;
        ChainVisualBridge.flush();
        var ref:ChainGroup=g.shotgun.reference;
        var referenceVisits:Number=ref.aggregateVisits;
        var visits:Number=g.aggregateVisits; var maxWire:Number=0;
        for (var i:Number=0;i<120;i++) {
            _root.帧计时器.当前帧数++;
            g.bullet._x+=g.bullet.xmov;
            _root.联弹系统.横向联弹更新(g);
            var packet:String=ChainVisualBridge.flush();
            if (packet.length>maxWire) maxWire=packet.length;
        }
        check(g.单元体列表.length == 4096 && g.bullet.霰弹值 == 4096, "no artificial time decay over 120 updates");
        check(g.aggregateVisits-visits == 240 && maxWire < 512, "steady aggregate visits two endpoints with bounded group packet");
        check(ref.aggregateVisits-referenceVisits == 240, "old-decay reference adds two scalar endpoints per steady update");
        check(ChainVisualBridge.getStats().groups == 1 && ChainVisualBridge.getStats().reserved == 4096,
            "reference has no native group or visual reservation");
        trace("[SHOTGUN_COST] units=4096 ticks=120 boundVisits=" + (g.aggregateVisits-visits)
            + " referenceVisits=" + (ref.aggregateVisits-referenceVisits) + " maxWire=" + maxWire);
        g.bullet.霰弹值=3; ChainUnitManager.commitShotgunBudget(g);
        check(g.单元体列表.length == 3 && g.aggregateMin != null && g.aggregateMax != null, "large positive commit preserves sorted endpoints");
        ChainVisualBridge.flush();
        g.bullet._y=2000000; _root.联弹系统.横向联弹更新(g);
        var retired:String=ChainVisualBridge.flush();
        check(g.__removed && g.单元体列表.length == 0 && g.bullet.__chainDead, "native final grounded pellet retires whole group");
        check(ref.单元体列表.length == 0 && ref.aggregateMin == null, "retirement returns reference data to pool");
        check(retired.indexOf("G,") < 0, "retirement never sends a live group with zero units");
        ChainVisualBridge.disconnect();
        g=makeGroup(1,1,false,66); g.bullet._y=1000;
        _root.联弹系统.横向联弹更新(g);
        check(g.__removed && g.bullet.霰弹值 == 0, "fallback final grounded pellet also retires");
        g=makeGroup(1,0,false,66); _root.联弹系统.对象联弹消失(g.bullet);
        check(g.__removed, "legacy one-pellet vanish unchanged");
        g=makeGroup(8,1,false,66); g.bullet.Z轴坐标=1000000;
        for (i=0;i<180;i++) _root.联弹系统.横向联弹更新(g);
        check(!g.__removed && g.shotgun.age == 180, "TTL allows full 180 actual updates");
        _root.联弹系统.横向联弹更新(g);
        check(g.__removed && g.shotgun == null, "TTL safety retires stopped or exceptional shots");
        g=makeGroup(8,1,false,66); ChainUnitManager.registerGroup(g);
        var oldPause:Boolean=_root.暂停; _root.暂停=true;
        ChainUnitManager.tick();
        check(g.shotgun.age == 0, "global pause never advances shotgun TTL");
        _root.暂停=oldPause;
        ref=g.shotgun.reference;
        ChainUnitManager.resetAll();
        check(g.__removed && g.shotgun == null, "scene reset releases per-shot contact state");
        check(ref.__removed && ref.单元体列表.length==0 && ref.aggregateMin==null,
            "scene reset returns remaining legacy-reference data exactly once");
    }
    private static function queueDamage(b,s,t,m,ds):Object {
        damages++;
        return realDamage(b,s,t,m,ds);
    }
    private static function queueTargets(unit:Object,interval:Number):Object { return queueCache; }
    private static function queueTarget(name:String,full:Boolean):MovieClip {
        var t:MovieClip=_root.gameworld.createEmptyMovieClip(name,_root.gameworld.getNextHighestDepth());
        var fields:Object=makeTarget();
        for (var key:String in fields) if (key != "_name") t[key]=fields[key];
        t.flags=0; t.是否为敌人=true;
        t.aabbCollider=new AABBCollider(-5,5,full ? -50 : -12.5,full ? 50 : 12.5);
        return t;
    }
    private static function setQueueTargets(targets:Array):Void {
        var left:Array=[],right:Array=[],maxRight:Array=[];
        for (var i:Number=0;i<targets.length;i++) {
            left[i]=targets[i].aabbCollider.left;
            right[i]=maxRight[i]=targets[i].aabbCollider.right;
        }
        queueCache={data:targets,leftValues:left,rightValues:right,rightMaxValues:maxRight};
    }
    private static function queueIntegration():Void {
        var api:Object=org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor;
        var cache:Object=TargetCacheManager,damage:Object=DamageCalculator,dodge:Object=DodgeHandler;
        var saved:Object={queues:api.activeQueues,fake:api.fakeUnits,uids:api.queueUIDs,
            enemies:cache.acquireEnemyCache,damage:damage.calculateDamage,roll:dodge.calcDodgeResult,state:dodge.calculateDodgeState,
            collision:_root.collisionLayer,xmin:_root.Xmin,xmax:_root.Xmax,ymin:_root.Ymin,ymax:_root.Ymax,paused:_root.暂停};
        realDamage=damage.calculateDamage;
        damage.calculateDamage=queueDamage; cache.acquireEnemyCache=queueTargets;
        dodge.calcDodgeResult=function():Number { dice++; return 0; };
        dodge.calculateDodgeState=function():String { return "未躲闪"; };
        _root.collisionLayer={hitTest:function():Boolean { return false; }};
        _root.Xmin=-2000; _root.Xmax=2000; _root.Ymin=-2000; _root.Ymax=2000; _root.暂停=false;
        FactionManager.initialize(); api.initialize();
        var shooter:MovieClip=_root.gameworld.createEmptyMovieClip("queueShooter",_root.gameworld.getNextHighestDepth());
        shooter.hp=1000; shooter.是否为敌人=false; shooter.伤害加成=0; shooter.dispatcher={publish:function():Void { events++; }};
        var first:MovieClip=queueTarget("queueFirst",false),second:MovieClip=queueTarget("queueSecond",false);
        var g:ChainGroup=makeGroup(8,1,false,66); setBand(g); g.shotgun.reference.bullet.霰弹值=2;
        g.bullet.发射者名=shooter._name; g.bullet.Z轴攻击范围=100;
        g.bullet.aabbCollider=new AABBCollider(-5,5,-50,50);
        g.bullet.gotoAndPlay=function():Void { _root.联弹系统.对象联弹消失(this); };
        makeCtx(g); counters(); setQueueTargets([first,second]);
        api.add(g.bullet); api.processQueue();
        check(g.bullet.霰弹值 == 4 && g.单元体列表.length == 4 && dice == 2 && damages == 2 && events == 2,
            "real queue settles two targets and commits a shared four-segment remainder");
        var firstHp:Number=first.hp; _root.帧计时器.当前帧数++; g.shotgun.age++;
        api.add(g.bullet); api.processQueue();
        check(first.hp == firstHp && g.bullet.霰弹值 == 4 && dice == 2 && damages == 2 && events == 2,
            "real next-frame queue rejects both prior contacts");
        // AVM1 可以复用同路径 MC；数字 dispatcher 身份必须允许新出生目标。
        g.shotgun.reference.bullet.霰弹值=4;
        first.removeMovieClip(); first=queueTarget("queueFirst",true);
        var extra:MovieClip=queueTarget("queueExtra",true);
        setQueueTargets([first,extra]); _root.帧计时器.当前帧数++; g.shotgun.age++;
        api.add(g.bullet); api.processQueue();
        check(first.hp < 5000 && extra.hp == 5000 && dice == 3 && damages == 3 && events == 3,
            "same-path replacement gets a new identity and exhausted tail never enters damage");
        check(g.bullet.霰弹值 == 0 && g.__removed && g.bullet.__chainDead,
            "real queue commits zero and vanishes in its single normal exit");
        g=makeGroup(8,1,false,66); setBand(g); g.shotgun.reference.bullet.霰弹值=2;
        g.ma=0; g.mb=1; g.mc2=-1; g.md=0; g.bullet._rotation=90;
        g.bullet.发射者名=shooter._name; g.bullet.Z轴攻击范围=100;
        g.bullet.aabbCollider=new AABBCollider(-50,50,-5,5);
        g.bullet.gotoAndPlay=function():Void { _root.联弹系统.对象联弹消失(this); };
        makeCtx(g); counters();
        first.aabbCollider=new AABBCollider(-12.5,12.5,-5,5); setQueueTargets([first]);
        api.add(g.bullet); api.processQueue();
        check(g.bullet.霰弹值 == 6 && dice == 1 && damages == 1 && g.bullet.polygonCollider == undefined,
            "angled real queue uses scalar group coverage without allocating old fixed OBB");
        ChainUnitManager.removeGroup(g);
        api.activeQueues=saved.queues; api.fakeUnits=saved.fake; api.queueUIDs=saved.uids;
        cache.acquireEnemyCache=saved.enemies; damage.calculateDamage=saved.damage;
        dodge.calcDodgeResult=saved.roll; dodge.calculateDodgeState=saved.state;
        _root.collisionLayer=saved.collision; _root.Xmin=saved.xmin; _root.Xmax=saved.xmax;
        _root.Ymin=saved.ymin; _root.Ymax=saved.ymax; _root.暂停=saved.paused;
        first.removeMovieClip(); second.removeMovieClip(); extra.removeMovieClip(); shooter.removeMovieClip();
        queueCache=null; realDamage=null;
    }
    public static function runAllTests():Void {
        passed=0; failed=0; clipId=0; createdClips=0;
        var oldWorld:MovieClip=_root.gameworld; var oldTimer:Object=_root.帧计时器; var oldRandom:Function=_root.随机偏移;
        var manager:Object=ChainUnitManager; var oldAcquire:Function=manager.acquireUnit; var oldRelease:Function=manager.releaseUnit;
        var world:MovieClip=_root.createEmptyMovieClip("shotgunPatternTestWorld",76545);
        world.createEmptyMovieClip("子弹区域",1); _root.gameworld=world; _root.帧计时器={当前帧数:1};
        _root.随机偏移=randomOffset; manager.acquireUnit=acquireClip; manager.releaseUnit=releaseClip;
        DamageManagerFactory.init();
        geometryAndScope(); budgetAndContacts(false); budgetAndContacts(true); missAndLastPellet(); queueIntegration(); lifecycleAndCost();
        ChainVisualBridge.disconnect(); manager.acquireUnit=oldAcquire; manager.releaseUnit=oldRelease;
        _root.随机偏移=oldRandom; _root.帧计时器=oldTimer; _root.gameworld=oldWorld; world.removeMovieClip();
        trace("ShotgunPatternTest Tests Passed: " + passed);
        trace("ShotgunPatternTest Tests Failed: " + failed);
    }
}
