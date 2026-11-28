import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypesetter;
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
    private static function makeGroup(count:Number, marker:Number, nativeMode:Boolean, flags:Number, bulletType:String):ChainGroup {
        var b:Object = {子弹种类:"横向联弹-普通子弹", baseAsset:"横向联弹", 霰弹值:count,
            霰弹分配模式:marker, flags:flags, 子弹散射度:20, xmov:25, ymov:0,
            _x:0, _y:-100, _rotation:0, _xscale:100, _yscale:100, _alpha:100, _visible:true,
            Z轴坐标:0, stateFlags:0, 子弹威力:100, 最小霰弹值:1, 固伤:0, 百分比伤害:0,
            伤害类型:"物理", 命中率:100, hitCount:0};
        if (bulletType != undefined) {
            b.子弹种类 = bulletType;
            BulletTypesetter.setTypeFlags(b);
        }
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
        sampleBand(g);
    }
    private static function sampleBand(g:ChainGroup):Void {
        var hull:AABBCollider=new AABBCollider(0,0,0,0);
        hull.updateFromChainObject(g.bullet);
        g.shotCoverage.sample(g,hull);
    }
    private static function setFarTwoSegmentBand(g:ChainGroup):Void {
        // 接触距离 150px 处于 100px 对群阈值之外且在存速平台内，[-12.5, 12.5] 稳定分摊 2 段。
        setBand(g);
        g.shotCoverage.travel = 150;
    }
    private static function geometryAndScope():Void {
        var g:ChainGroup = makeGroup(8, 1, false, 66);
        setBand(g);
        var p:ShotgunPattern = g.shotgun;
        check(p != null, "standard player shotgun opts in");
        check(p.calculateCap(g, {left:-5,right:5,top:-50,bottom:50},0) == 8, "close full envelope can use all eight");
        check(p.calculateCap(g, {left:-5,right:5,top:-12.5,bottom:12.5},0) == 2, "partial spread coverage receives two of eight");
        check(p.calculateCap(g, {left:-5,right:5,top:0,bottom:0.001},0) == 1, "thin overlap retains eligibility with one segment");
        check(p.calculateCap(g, {left:6,right:9,top:-50,bottom:50},0) == 0, "local flight-axis separation rejects broad false positive");
        check(p.calculateCap(g, {left:-5,right:5,top:51,bottom:70},0) == 0, "scatter-axis separation rejects");
        check(p.calculateCap(g, {left:NaN,right:5,top:-5,bottom:5},0) == 0, "invalid target geometry rejects");
        check(g.shotCoverage.travel == 0, "target queries do not advance the shared flight distance");
        g.ma = 0; g.mb = 1; g.mc2 = -1; g.md = 0; p.age++; sampleBand(g);
        check(p.calculateCap(g, {left:-12.5,right:12.5,top:-5,bottom:5},0) == 2, "90 degree shot preserves projected coverage");
        g.ma = -2; g.mb = 0; g.mc2 = 0; g.md = 1; p.age++; sampleBand(g);
        check(p.calculateCap(g, {left:-10,right:10,top:-12.5,bottom:12.5},0) == 2, "mirrored scale preserves target coverage");
        g.ma = 0; g.md = 0; p.age++; sampleBand(g);
        check(p.calculateCap(g, {left:-10,right:10,top:-5,bottom:5},0) == 0, "singular group transform rejects");
        g.ma = 1; g.md = 1; p.age++; sampleBand(g);
        var zone:MovieClip = _root.gameworld.子弹区域;
        zone._rotation = 90; zone._x = 50; zone._y = 20;
        AABBCollider.zoneFrame = -1; sampleBand(g);
        check(p.calculateCap(g, {left:37.5,right:62.5,top:15,bottom:25},0) == 2, "real transformed bullet zone composes correctly");
        zone._rotation = 0; zone._x = 0; zone._y = 0;
        AABBCollider.zoneFrame = -1;
        var diagonal:Number=Math.sqrt(0.5);
        g.ma=diagonal; g.mb=diagonal; g.mc2=-diagonal; g.md=diagonal; p.age++; sampleBand(g);
        check(p.calculateCap(g,{left:-100,right:100,top:16,bottom:17},0)>=1,
            "angled actual band is eligible without a virtual pellet");
        check(p.calculateCap(g,{left:37,right:39,top:20,bottom:23},0)==0,
            "angled outside-corner contact rejects a broad false positive");
        g.shotCoverage.travel=720;
        var clipTarget:Object=makeTarget();
        check(p.prepareContact(g,clipTarget,{left:-100,right:100,top:16,bottom:17},0) && p.hitCap==1,
            "distant actual-only graze receives one ordinary attempt");
        check(!p.prepareContact(g,clipTarget,{left:-100,right:100,top:16,bottom:17},0),
            "distant graze does not repeat on one target");
        g.ma=1; g.mb=0; g.mc2=0; g.md=1; p.age++; sampleBand(g);
        g.shotCoverage.travel=95;
        check(p.calculateCap(g,{left:-5,right:5,top:-50,bottom:50},0)==8,
            "point-blank under 100px contactDist allows full eight segments");
        g.shotCoverage.travel=100;
        check(p.calculateCap(g,{left:-5,right:5,top:-50,bottom:50},0)==7,
            "100px contactDist reserves one pellet for crowd follow-up");
        g.shotCoverage.travel=260;
        check(p.calculateCap(g,{left:-5,right:5,top:-50,bottom:50},0)==7,
            "260px fast shot remains strong while still reserving one for crowd");
        g.shotCoverage.travel=450; g.bullet.xmov=15;
        var slowLongCap:Number=p.calculateCap(g,{left:-5,right:5,top:-50,bottom:50},0);
        g.bullet.xmov=45;
        var fastLongCap:Number=p.calculateCap(g,{left:-5,right:5,top:-50,bottom:50},0);
        g.bullet.xmov=25;
        check(slowLongCap>=1 && fastLongCap>slowLongCap && fastLongCap<=7,
            "higher bullet velocity retains more segments at long range");
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
        actor.长枪数据.weapontype="霰弹枪";
        wd.split=5; wd.diffusion=10; wd.bullet="横向联弹-加强普通子弹";
        props = ShootInitCore.generateBulletProps(actor,"长枪",wd,{});
        check(BulletTypesetter.setTypeFlags(props) == 66, "normal shotgun bullet resolves to FLAG_CHAIN|FLAG_NORMAL");
        g = makeGroup(props.霰弹值, props.霰弹分配模式, false, props.flags);
        check(g.shotgun != null, "normal shotgun bullet opts into ShotgunPattern");
        ChainUnitManager.removeGroup(g);
        wd.bullet="横向联弹-次级穿刺子弹";
        props = ShootInitCore.generateBulletProps(actor,"长枪",wd,{});
        check(BulletTypesetter.setTypeFlags(props) == 6, "secondary-pierce tactical shotgun bullet resolves to FLAG_CHAIN|FLAG_PIERCE");
        g = makeGroup(props.霰弹值, props.霰弹分配模式, false, props.flags);
        check(g.shotgun == null && g.horizontalPierce === true, "secondary-pierce tactical shotgun routes to horizontalPierce instead of ShotgunPattern");
        ChainUnitManager.removeGroup(g);
        wd.split=1; wd.bullet="高爆子弹";
        props = ShootInitCore.generateBulletProps(actor,"手枪",wd,{});
        check(BulletTypesetter.setTypeFlags(props) == 0, "high-explosive shotgun bullet resolves to non-chain non-pierce");
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
        setFarTwoSegmentBand(g); counters(); forcedDodge="未躲闪";
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
        var g:ChainGroup = makeGroup(8,1,false,66); setFarTwoSegmentBand(g); counters(); forcedDodge="躲闪";
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
        var costBox:AABBCollider=new AABBCollider(0,0,0,0);
        costBox.updateFromChainObject(g.bullet);
        g.shotCoverage.sample(g,costBox);
        var farCap:Number=g.shotgun.calculateCap(g,{left:g.bullet._x-5,right:g.bullet._x+5,top:-100000,bottom:100000},0);
        check(farCap >= 1 && farCap < 4096, "kinetic falloff reduces distant cap while keeping floor >= 1");
        check(ChainVisualBridge.getStats().groups == 1 && ChainVisualBridge.getStats().reserved == 4096,
            "reference has no native group or visual reservation");
        trace("[SHOTGUN_COST] units=4096 ticks=120 boundVisits=" + (g.aggregateVisits-visits)
            + " farCap=" + farCap + " maxWire=" + maxWire);
        g.bullet.霰弹值=3; ChainUnitManager.commitShotgunBudget(g);
        check(g.单元体列表.length == 3 && g.aggregateMin != null && g.aggregateMax != null, "large positive commit preserves sorted endpoints");
        ChainVisualBridge.flush();
        g.bullet._y=2000000; _root.联弹系统.横向联弹更新(g);
        var retired:String=ChainVisualBridge.flush();
        check(g.__removed && g.单元体列表.length == 0 && g.bullet.__chainDead, "native final grounded pellet retires whole group");
        check(g.shotCoverage == null, "retirement releases shared coverage");
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
        ChainUnitManager.resetAll();
        check(g.__removed && g.shotgun == null, "scene reset releases per-shot contact state");
        check(g.shotCoverage==null, "scene reset releases scalar coverage");
    }
    private static function queueDamage(b,s,t,m,ds):Object {
        damages++;
        var r:Object = realDamage(b,s,t,m,ds);
        if (t.attempts != undefined) {
            t.attempts += r.actualScatterUsed;
            if (r.scatterMissCount > 0) t.misses += r.scatterMissCount;
        }
        return r;
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
    private static function pierceClipBindings():Void {
        var names:Array = ["横向联弹-穿刺子弹","横向拖尾追踪联弹-无壳穿刺子弹"];
        for (var i:Number = 0; i < names.length; i++) {
            var b:MovieClip = _root.gameworld.createEmptyMovieClip("pierceShell" + i, _root.gameworld.getNextHighestDepth());
            b.子弹种类 = names[i]; b.霰弹值 = 3; b.xmov = 10; b.子弹散射度 = 10;
            BulletTypesetter.setTypeFlags(b);
            var area:MovieClip = b.createEmptyMovieClip("area",1);
            if (i == 0) _root.联弹系统.横向联弹初始化(area);
            else _root.联弹系统.横向拖尾联弹初始化(area);
            var group:ChainGroup = ChainUnitManager.findGroupByBullet(b);
            check(group != null && b.chainGroup === group && (i == 0 ? group.horizontalPierce === true : group.pierceRemaining != null),
                names[i] + " real MC initializer binds the same group used by the queue");
            if (i != 0) {
                var fixedTarget:Object = {};
                check(group.takePierceSegments(fixedTarget,3,3) == 3 && group.takePierceSegments(fixedTarget,2,2) == 2
                && group.takePierceSegments(fixedTarget,2,2) == 1 && !group.canJudgePierce(fixedTarget),
                names[i] + " dispatcher-less target uses a stable identity and clips partial remainder");
            }
            if(i==0) {
                _root.联弹系统.联弹消失(b);
                check(group.__removed && group.单元体列表.length==0, "MC pierce range exit recycles a full group");
            }
            ChainUnitManager.removeGroup(group);
            b.removeMovieClip();
        }
    }

    private static function runPierceFrame(api:Object, g:ChainGroup, targets:Array):Void {
        var b:Object = g.bullet;
        _root.帧计时器.当前帧数++;
        b._x += b.xmov;
        _root.联弹系统.横向联弹更新(g);
        if (g.__removed || b.__chainDead) return;
        b.aabbCollider.updateFromChainObject(b);
        setQueueTargets(targets);
        api.add(b);
        api.processQueue();
    }

    private static function runVelocityProbe(api:Object, shooter:MovieClip, speed:Number):Number {
        var target:MovieClip = queueTarget("pierceVel" + speed, true);
        target.Z轴坐标 = 1000;
        target.aabbCollider = new AABBCollider(20, 76, -200, 200);
        target.attempts = 0;
        var g:ChainGroup = makeGroup(6, 1, false, 0, "横向联弹-穿刺子弹");
        var b:Object = g.bullet;
        b.发射者名 = shooter._name;
        b.Z轴攻击范围 = 100;
        b.Z轴坐标 = 1000;
        b._x = -speed; b._y = 0; b.xmov = speed;
        b.aabbCollider = new AABBCollider(-5, 5, -50, 50);
        makeCtx(g);
        for (var tick:Number = 0; tick < 10; tick++) {
            runPierceFrame(api, g, [target]);
        }
        var total:Number = target.attempts;
        ChainUnitManager.removeGroup(g);
        target.removeMovieClip();
        return total;
    }

    private static function pierceQueue(api:Object, shooter:MovieClip, bulletType:String):Void {
        var isSecondary:Boolean = bulletType.indexOf("次级") >= 0;
        var first:MovieClip = queueTarget("pierceFront", true);
        var rear:MovieClip = queueTarget("pierceRear", true);
        first.aabbCollider = new AABBCollider(20, 76, -200, 200);
        rear.aabbCollider = new AABBCollider(110, 166, -200, 200);
        first.attempts = rear.attempts = 0;
        first.misses = rear.misses = 0;
        var g:ChainGroup = makeGroup(6, 1, false, 0, bulletType);
        var b:Object = g.bullet;
        b.发射者名 = shooter._name;
        b.Z轴攻击范围 = 100;
        b.aabbCollider = new AABBCollider(-5,5,-50,50);
        if (isSecondary) b.pierceLimit = 18;
        makeCtx(g);
        // 即使旧衰竭计数器极深，横穿实弹不因时间枯竭；两排均按扫掠和 5/9 系数连续结算。
        b._y = 0; b._x = -30; b.xmov = 30; b.Z轴坐标 = first.Z轴坐标 = rear.Z轴坐标 = 1000;
        g.衰竭计数器 = 1000000;
        check(b.flags == 6 && g.horizontalPierce === true, bulletType + " binds unified horizontalPierce route");
        counters();
        for (var tick:Number = 0; tick < 8; tick++) {
            runPierceFrame(api, g, [first, rear]);
        }
        if (!isSecondary) {
            check(b.霰弹值 == 6 && g.单元体列表.length == 6 && !g.__removed,
                bulletType + " true pierce keeps all six live pellets alive after passing targets");
            check(first.attempts == 15 && rear.attempts == 15 && first.hp < 5000 && rear.hp < 5000 && b.hitCount == 30,
                bulletType + " 5/9 applies on each swept frame (front=15 rear=15)");
            var oldDice:Number = dice;
            var oldDamages:Number = damages;
            var oldEvents:Number = events;
            var oldShields:Number = shields;
            var oldHooks:Number = hooks;
            runPierceFrame(api, g, [first, rear]);
            check(dice == oldDice && damages == oldDamages && events == oldEvents && shields == oldShields && hooks == oldHooks,
                bulletType + " swept past targets triggers zero extra checks");

            // 验证全段 MISS（躲闪）不触发 hit 事件与旧钩子且不扣减霰弹值，同时验证慢速增益 > 中速 > 高速且高速不隧穿。
            var missTarget:MovieClip = queueTarget("pierceMiss", true);
            missTarget.Z轴坐标 = b.Z轴坐标;
            missTarget.aabbCollider = new AABBCollider(220, 276, -200, 200);
            missTarget.attempts = 0; missTarget.misses = 0; missTarget.等级 = 100; missTarget.重量 = 0;
            forcedDodge = "躲闪";
            runPierceFrame(api, g, [missTarget]);
            check(missTarget.attempts == 5 && missTarget.misses == 5 && missTarget.hp == 5000
                && hooks == oldHooks && events == oldEvents && b.霰弹值 == 6,
                bulletType + " full-frame MISS stays zero-damage with zero hook/event and keeps all pellets ("
                + missTarget.attempts + " attempts, " + missTarget.misses + " misses)");
            forcedDodge = "未躲闪";
            missTarget.removeMovieClip();

            var slowHits:Number = runVelocityProbe(api, shooter, 15);
            var midHits:Number = runVelocityProbe(api, shooter, 30);
            var fastHits:Number = runVelocityProbe(api, shooter, 45);
            check(slowHits > midHits && midHits > fastHits && fastHits > 6,
                bulletType + " preserves slow-pierce linger buff while swept collision prevents fast tunneling ("
                + slowHits + ">" + midHits + ">" + fastHits + ")");
            trace("[HORIZONTAL_PIERCE] type=" + bulletType + " birth=6 frontLive=6 frontAttempts=" + first.attempts
                + " rearLive=6 rearAttempts=" + rear.attempts + " slow=" + slowHits + " mid=" + midHits
                + " fast=" + fastHits + " dead=false");
        } else {
            check(first.attempts == 15 && rear.attempts == 5 && b.hitCount == 20 && b.__chainDead && g.__removed,
                bulletType + " secondary pierce settles uniformly then retires on pierceLimit");
            trace("[HORIZONTAL_PIERCE] type=" + bulletType + " birth=6 frontLive=6 frontAttempts=" + first.attempts
                + " rearLive=6 rearAttempts=" + rear.attempts + " totalJudged=" + b.hitCount + " dead=true");
        }
        ChainUnitManager.removeGroup(g);
        check(g.pierceRemaining == null && !g.horizontalPierce, bulletType + " group teardown clears pierce state");
        first.removeMovieClip();
        rear.removeMovieClip();
    }

    private static function pierceGroundRetirement():Void {
        for(var mode:Number=0;mode<2;mode++) {
            if(mode==1)ChainVisualBridge.configure(caps());
            var g:ChainGroup=makeGroup(8,1,mode==1,0,"横向联弹-穿刺子弹");
            var b:Object=g.bullet;b.Z轴坐标=1000000;
            if(mode==1)check(g.nativeGroupOwned && g.aggregate, "native pierce tests use the aggregate branch");
            var hull:Object={left:-5,right:5,top:-105,bottom:-95};
            _root.帧计时器.当前帧数++; g.shotCoverage.sample(g,hull);
            var areaNear:Object={left:b._x,right:b._x+50,top:-300,bottom:100};
            var nearCover:Number=g.shotCoverage.contact(g,areaNear,0,false);
            var lastCount:Number=b.霰弹值;
            for(var i:Number=0;i<40;i++){
                b._x+=b.xmov;_root.帧计时器.当前帧数++;_root.联弹系统.横向联弹更新(g);
                hull.left=b._x-5;hull.right=b._x+5;
                hull.top=b._y+g.盒y;hull.bottom=hull.top+g.盒高;
                g.shotCoverage.sample(g,hull);
            }
            check(b.霰弹值==lastCount && g.单元体列表.length==lastCount && g.horizontalPierce,
                "pierce keeps all physical pellets airborne until ground exit, native=" + mode);
            var area:Object={left:b._x,right:b._x+50,top:hull.top-10,bottom:hull.bottom+10};
            var farCover:Number=g.shotCoverage.contact(g,area,0,false);
            check(farCover>=1 && farCover<nearCover,
                "distant pierce contact scales down by kinetic(tau) with floor >= 1, native=" + mode);
            b.Z轴坐标=-1000000;
            _root.联弹系统.横向联弹更新(g);
            check(b.__chainDead && g.__removed && g.单元体列表.length==0,
                "last actual pellet retires on ground, native=" + mode);
            if(mode==1)ChainVisualBridge.disconnect();
        }
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
        forcedDodge = "未躲闪";
        dodge.calculateDodgeState=function():String { return forcedDodge; };
        _root.collisionLayer={hitTest:function():Boolean { return false; }};
        _root.Xmin=-2000; _root.Xmax=2000; _root.Ymin=-2000; _root.Ymax=2000; _root.暂停=false;
        FactionManager.initialize(); api.initialize();
        var shooter:MovieClip=_root.gameworld.createEmptyMovieClip("queueShooter",_root.gameworld.getNextHighestDepth());
        shooter.hp=1000; shooter.是否为敌人=false; shooter.伤害加成=0; shooter.dispatcher={publish:function():Void { events++; }};
        var first:MovieClip=queueTarget("queueFirst",false),second:MovieClip=queueTarget("queueSecond",false);
        var g:ChainGroup=makeGroup(8,1,false,66); setFarTwoSegmentBand(g);
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
        first.removeMovieClip(); first=queueTarget("queueFirst",true);
        var extra:MovieClip=queueTarget("queueExtra",true);
        setQueueTargets([first,extra]); _root.帧计时器.当前帧数++; g.shotgun.age++;
        api.add(g.bullet); api.processQueue();
        check(first.hp < 5000 && extra.hp == 5000 && dice == 3 && damages == 3 && events == 3,
            "same-path replacement gets a new identity and exhausted tail never enters damage");
        check(g.bullet.霰弹值 == 0 && g.__removed && g.bullet.__chainDead,
            "real queue commits zero and vanishes in its single normal exit");
        g=makeGroup(8,1,false,66); setFarTwoSegmentBand(g);
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
        // 贴身（contactDist<100）时首个完整命中目标拿满，后目标没有副作用。
        g = makeGroup(8,1,false,66);
        setBand(g);
        first.aabbCollider = new AABBCollider(-5,5,-50,50);
        g.bullet.发射者名 = shooter._name; g.bullet.Z轴攻击范围 = 100;
        g.bullet.aabbCollider = new AABBCollider(-5,5,-50,50);
        g.bullet.gotoAndPlay = function():Void { _root.联弹系统.对象联弹消失(this); };
        makeCtx(g); counters(); firstHp = first.hp;
        setQueueTargets([first,extra]); _root.帧计时器.当前帧数++;
        api.add(g.bullet); api.processQueue();
        check(first.hp < firstHp && extra.hp == 5000 && g.bullet.霰弹值 == 0 && g.__removed
            && dice == 1 && damages == 1 && events == 1, "point-blank queue spends all eight on one eligible target");
        // 中距（contactDist>=100）全覆盖前排封顶 N-1，稳定漏至少 1 发打中后排并耗尽退场。
        first.removeMovieClip(); second.removeMovieClip();
        g = makeGroup(8,1,false,66);
        setFarTwoSegmentBand(g);
        first = queueTarget("crowdFront", true); first.aabbCollider = new AABBCollider(-5,5,-50,50);
        second = queueTarget("crowdRear", true); second.aabbCollider = new AABBCollider(-5,5,-50,50);
        g.bullet.发射者名 = shooter._name; g.bullet.Z轴攻击范围 = 100;
        g.bullet.aabbCollider = new AABBCollider(-5,5,-50,50);
        g.bullet.gotoAndPlay = function():Void { _root.联弹系统.对象联弹消失(this); };
        makeCtx(g); counters();
        setQueueTargets([first, second]); _root.帧计时器.当前帧数++;
        api.add(g.bullet); api.processQueue();
        check(first.hp < 5000 && second.hp < 5000 && g.bullet.霰弹值 == 0 && g.__removed
            && dice == 2 && damages == 2 && events == 2,
            "mid-range queue reserves one pellet from full-cover front target to hit rear");
        pierceQueue(api,shooter,"横向联弹-穿刺子弹");
        pierceQueue(api,shooter,"横向联弹-次级穿刺子弹");
        api.activeQueues=saved.queues; api.fakeUnits=saved.fake; api.queueUIDs=saved.uids;
        cache.acquireEnemyCache=saved.enemies; damage.calculateDamage=saved.damage;
        dodge.calcDodgeResult=saved.roll; dodge.calculateDodgeState=saved.state;
        _root.collisionLayer=saved.collision; _root.Xmin=saved.xmin; _root.Xmax=saved.xmax;
        _root.Ymin=saved.ymin; _root.Ymax=saved.ymax; _root.暂停=saved.paused;
        first.removeMovieClip(); second.removeMovieClip(); extra.removeMovieClip(); shooter.removeMovieClip();
        queueCache=null; realDamage=null;
    }
    private static function dualGunAttributeIsolation():Void {
        var oldSuccessRate:Function = _root.成功率;
        _root.成功率 = function(rate:Number):Boolean { return rate >= 100; };
        try {
            var factoryApi:Object = org.flashNight.arki.bullet.Factory.BulletFactory;
            var initApi:Object = org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
            var actor:Object = {
                _name: "dualActor", hasDressup: true, 是否为敌人: false, 攻击模式: "双枪",
                被动技能: {}, 基础命中率: 100, 基础命中加成: 0, 命中率: 100, 伤害加成: 0,
                手枪: {name: "Mossberg500"}, 手枪2: {name: "Mossberg500"},
                基础伤害类型: "物理", 基础魔法伤害属性: undefined,
                基础毒: 0, 基础吸血: 0, 基础击溃: 0, 基础斩杀: 0,
                手枪伤害类型: "破击", 手枪魔法伤害属性: null,
                手枪毒: 8, 手枪吸血: 5, 手枪击溃: 0.1, 手枪斩杀: 6, 手枪暴击: "满血暴击", 手枪命中加成: 0,
                手枪2伤害类型: "物理", 手枪2魔法伤害属性: null,
                手枪2毒: 0, 手枪2吸血: 0, 手枪2击溃: 0, 手枪2斩杀: 0, 手枪2暴击: null, 手枪2命中加成: 0,
                // 模拟切换双枪时单位共享通用字段被主手覆盖后的污染状态
                伤害类型: "破击", 魔法伤害属性: null, 毒: 8, 吸血: 5, 击溃: 0.1, 斩杀: 6,
                暴击: ShootInitCore.createCritLogic("满血暴击"),
                手枪属性: {split: 10, diffusion: 17, bullet: "横向联弹-普通子弹", power: 84, impact: 15, velocity: 25, interval: 330, clipname: "12号霰弹弹药", bulletsize: 35, weapontype: "霰弹枪"},
                手枪2属性: {split: 10, diffusion: 17, bullet: "横向联弹-次级穿刺子弹", power: 84, impact: 15, velocity: 25, interval: 330, clipname: "12号霰弹弹药", bulletsize: 35, weapontype: "霰弹枪"},
                手枪数据: {weapontype: "霰弹枪"}, 手枪2数据: {weapontype: "霰弹枪"}
            };

            // 验证 initDualGun 不再因 mainExtra/subExtra 遮蔽非武器 基础* 加成，且副手不被主手污染
            // AS2 中 MovieClip(plainObject) 强转运行时为 null，测试桩需保持无类型传参
            var manMock = {刷新弹匣数显示: function():Void {}};
            ShootInitCore.initDualGun(manMock, actor);
            var mainProps:Object = manMock.子弹属性;
            var subProps:Object = manMock.子弹属性2;
            factoryApi.prepareBulletData(mainProps, actor);
            initApi.initializeNanoToxicfunction(mainProps, mainProps, actor);
            factoryApi.prepareBulletData(subProps, actor);
            initApi.initializeNanoToxicfunction(subProps, subProps, actor);

            var lowHpTarget:Object = {hp: 100, hp满血值: 1000};
            var fullHpTarget:Object = {hp: 1000, hp满血值: 1000};
            check(Math.abs(mainProps.击溃 - 0.1) < 0.0001 && mainProps.吸血 == 5 && mainProps.毒 == 8
                && mainProps.nanoToxic == 8 && mainProps.伤害类型 == "破击" && mainProps.斩杀 == 6
                && typeof mainProps.暴击 == "function" && mainProps.暴击({hitTarget: fullHpTarget}) == 1.5
                && mainProps.暴击({hitTarget: lowHpTarget}) == 1,
                "dual-gun main hand retains its own crumble, lifesteal, poison, damage type, execute and crit");
            check(subProps.击溃 === 0 && subProps.吸血 === 0 && subProps.毒 === 0 && !(subProps.nanoToxic > 0)
                && subProps.伤害类型 == "物理" && subProps.魔法伤害属性 == undefined && subProps.斩杀 === 0
                && subProps.暴击 == null,
                "dual-gun off-hand does not inherit main-hand crumble, lifesteal, poison, execute or crit via shooter");

            // 非武器防具/饰品基础词条须通过 initDualGun 等量叠加到双手，副手仍不沾染主手击溃/吸血
            actor.基础毒 = 2; actor.基础吸血 = 3; actor.基础击溃 = 0.5; actor.基础斩杀 = 4;
            ShootInitCore.initDualGun(manMock, actor);
            var baseMain:Object = manMock.子弹属性;
            var baseSub:Object = manMock.子弹属性2;
            factoryApi.prepareBulletData(baseMain, actor);
            initApi.initializeNanoToxicfunction(baseMain, baseMain, actor);
            factoryApi.prepareBulletData(baseSub, actor);
            initApi.initializeNanoToxicfunction(baseSub, baseSub, actor);
            check(Math.abs(baseMain.击溃 - 0.6) < 0.0001 && baseMain.吸血 == 8 && baseMain.毒 == 10 && baseMain.斩杀 == 10
                && Math.abs(baseSub.击溃 - 0.5) < 0.0001 && baseSub.吸血 == 3 && baseSub.毒 == 2
                && baseSub.nanoToxic == 2 && baseSub.斩杀 == 4,
                "non-weapon base traits stack identically into both dual-gun hands without cross-hand leak");

            // 可复用模板上的药剂暴击率/淬毒须对双手生效，并在药效归零后下一发干净复原
            actor.基础毒 = 0; actor.基础吸血 = 0; actor.基础击溃 = 0; actor.基础斩杀 = 0;
            actor.暴击率 = 100; actor.淬毒 = 25;
            var reusedSub:Object = ShootInitCore.generateBulletProps(actor, "手枪2", actor.手枪2属性, {});
            var shot1:Object = {flags: 0};
            factoryApi.prepareBulletData(reusedSub, actor);
            initApi.initializeNanoToxicfunction(reusedSub, shot1, actor);
            check(typeof reusedSub.暴击 == "function" && reusedSub.暴击({hitTarget: lowHpTarget}) == 1.5
                && shot1.nanoToxic == 25 && reusedSub.毒 == 0,
                "dual-gun off-hand reused template receives active potion crit and coating poison");
            actor.暴击率 = 0; actor.淬毒 = 0;
            var shot2:Object = {flags: 0};
            factoryApi.prepareBulletData(reusedSub, actor);
            initApi.initializeNanoToxicfunction(reusedSub, shot2, actor);
            check(reusedSub.暴击 == null && !(shot2.nanoToxic > 0) && reusedSub.击溃 === 0 && reusedSub.毒 === 0,
                "dual-gun off-hand reused template cleanly reverts potion crit and poison once expired");

            // 无换装与槽位前缀的纯旧版敌人仍保留 legacy 继承行为
            var legacyShooter:Object = {_name: "legacyBot", 被动技能: {}, 命中率: 50, 是否为敌人: true,
                伤害类型: "魔法", 魔法伤害属性: "热", 吸血: 7, 击溃: 2, 斩杀: 9, 毒: 4};
            var legacyProps:Object = ShootInitCore.generateBulletProps(legacyShooter, "手枪", actor.手枪2属性, {});
            factoryApi.prepareBulletData(legacyProps, legacyShooter);
            initApi.initializeNanoToxicfunction(legacyProps, legacyProps, legacyShooter);
            check(legacyProps.slotWeaponProjected !== true && legacyProps.击溃 == 2 && legacyProps.吸血 == 7
                && legacyProps.毒 == 4 && legacyProps.nanoToxic == 4 && legacyProps.伤害类型 == "魔法"
                && legacyProps.魔法伤害属性 == "热" && legacyProps.斩杀 == 9,
                "legacy non-dressup enemy without slot projection preserves shooter inheritance");
        } finally {
            _root.成功率 = oldSuccessRate;
        }
    }

    // Issue #367：纵向联弹按霰弹值扣淬毒须保底 10，11~14 层不得被扣穿纳米毒性门槛。
    private static function verticalChainPoisonFloor():Void {
        var initApi:Object = org.flashNight.arki.bullet.BulletComponent.Init.BulletInitializer;
        var actor:Object = {_name:"verticalActor", 是否为敌人:false, hasDressup:false,
            被动技能:{}, 命中率:100, 伤害加成:0, 伤害类型:"物理", 基础毒:0, 毒:0, 淬毒:14};

        var shot1:Object = {子弹种类:"纵向联弹-普通子弹", flags:128, 霰弹值:5, 最小霰弹值:1,
            毒:0, 子弹威力:100, stateFlags:0};
        initApi.initializeNanoToxicfunction(shot1, shot1, actor);
        check(actor.淬毒 == 10 && shot1.nanoToxic == 14,
            "vertical chain clamps coating poison at 10 and keeps pre-shot nano snapshot");

        actor.淬毒 = 11;
        var shot2:Object = {子弹种类:"纵向联弹-普通子弹", flags:128, 霰弹值:6, 最小霰弹值:1,
            毒:0, 子弹威力:100, stateFlags:0};
        initApi.initializeNanoToxicfunction(shot2, shot2, actor);
        check(actor.淬毒 == 10 && shot2.nanoToxic == 11,
            "vertical chain clamps 11 with six pellets instead of dropping below 10");

        actor.淬毒 = 25;
        var shot3:Object = {子弹种类:"纵向联弹-普通子弹", flags:128, 霰弹值:5, 最小霰弹值:1,
            毒:0, 子弹威力:100, stateFlags:0};
        initApi.initializeNanoToxicfunction(shot3, shot3, actor);
        check(actor.淬毒 == 20 && shot3.nanoToxic == 25,
            "vertical chain keeps proportional consumption above the floor");
    }

    public static function runAllTests():Void {
        passed=0; failed=0; clipId=0; createdClips=0;
        var oldWorld:MovieClip=_root.gameworld; var oldTimer:Object=_root.帧计时器; var oldRandom:Function=_root.随机偏移;
        var manager:Object=ChainUnitManager; var oldAcquire:Function=manager.acquireUnit; var oldRelease:Function=manager.releaseUnit;
        var world:MovieClip=_root.createEmptyMovieClip("shotgunPatternTestWorld",76545);
        world.createEmptyMovieClip("子弹区域",1); _root.gameworld=world; _root.帧计时器={当前帧数:1};
        _root.随机偏移=randomOffset; manager.acquireUnit=acquireClip; manager.releaseUnit=releaseClip;
        DamageManagerFactory.init();
        geometryAndScope(); budgetAndContacts(false); budgetAndContacts(true); missAndLastPellet(); pierceClipBindings(); queueIntegration(); lifecycleAndCost(); pierceGroundRetirement(); dualGunAttributeIsolation(); verticalChainPoisonFloor();
        ChainVisualBridge.disconnect(); manager.acquireUnit=oldAcquire; manager.releaseUnit=oldRelease;
        _root.随机偏移=oldRandom; _root.帧计时器=oldTimer; _root.gameworld=oldWorld; world.removeMovieClip();
        trace("ShotgunPatternTest Tests Passed: " + passed);
        trace("ShotgunPatternTest Tests Failed: " + failed);
    }
}
