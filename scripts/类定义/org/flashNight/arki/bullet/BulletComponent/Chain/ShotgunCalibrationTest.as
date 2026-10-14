import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.render.ChainVisualBridge;
import org.flashNight.naki.RandomNumberEngine.*;

/** 单体标定：同出生 RNG、旧生产更新作 oracle、真实伤害链；不写存档。
 * 数据夹具由 runner 在编译前后对照当前两份霰弹 XML。特殊穿刺/非横向不纳入。 */
class org.flashNight.arki.bullet.BulletComponent.Chain.ShotgunCalibrationTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var seed:Number;
    private static var randomCalls:Number;
    private static var cases:Number;
    private static var oldHits:Number;
    private static var newHits:Number;
    private static var oldSegments:Number;
    private static var newSegments:Number;
    private static var oldDamage:Number;
    private static var newDamage:Number;
    private static var groundedCases:Number;
    private static var clipId:Number;
    private static var profileIndex:Number;
    private static var saved:Object;
    private static function check(ok:Boolean, name:String):Void {
        if (ok) passed++;
        else { failed++; trace("[TEST_FAIL] ShotgunCalibrationTest: " + name); }
    }
    private static function profiles():Array {
        return [
            ["单管霰弹枪",8,16,50],
            ["DBHshotgun",15,6,30],
            ["雷明登870",7,10,15],
            ["勃朗宁725双管霰弹枪",12,17,15],
            ["雷明登870急速型",4,7,45],
            ["雷明登870警用型",8,10,30],
            ["XM1014",7,20,30],
            ["FNSLP半自动霰弹枪",8,20,15],
            ["白火铳",11,15,35],
            ["ZUX197",3,8,50],
            ["TTI Benelli M4",5,10,40],
            ["SPAS12",10,14,35],
            ["Jackhammer",8,20,30],
            ["TTI Gen 12",5,9,39],
            ["黄金QBZ",9,9,39],
            ["双管白火铳",13,12,39],
            ["黄金QBZ的Andy版",10,11,39],
            ["SHRAPNEL",10,11,39],
            ["AA12",5,10,40],
            ["AA12战术版",5,10,40],
            ["杠杆式霰弹枪",7,10,15],
            ["超级矮子",8,30,30],
            ["HDBHshotgun",15,12,20],
            ["双管猎枪",9,11,20],
            ["Mossberg500",10,17,25],
            ["ASSKICKER",6,15,50],
            ["无枪托ZUX197",3,10,50],
            ["SPAS12-B2",20,14,35],
            ["Origin12",5,10,40],
            ["Origin12战术版",5,10,40]
        ];
    }
    private static function randomOffset(span:Number):Number {
        seed=(seed*1664525+1013904223)|0;
        var unsigned:Number=seed<0 ? seed+4294967296 : seed;
        randomCalls++;
        return (unsigned/4294967296*2-1)*span;
    }
    private static function acquireClip(type:String):MovieClip {
        var zone:MovieClip=_root.gameworld.子弹区域;
        return zone.createEmptyMovieClip("calUnit"+(++clipId),zone.getNextHighestDepth());
    }
    private static function releaseClip(clip:MovieClip):Void { clip.removeMovieClip(); }
    private static function caps():Object {
        return {version:1,mode:"native",maxUnits:15360,
            styles:[{gunChainUnitLinkage:"单元体-普通子弹"}],
            gunChainPrefixes:["横向联弹"]};
    }
    private static function makeGroup(p:Array, marker:Number, nativeMode:Boolean, left:Boolean):ChainGroup {
        var b:Object={子弹种类:"横向联弹-普通子弹",baseAsset:"横向联弹",flags:66,
            霰弹分配模式:marker,霰弹值:p[1],子弹散射度:p[2],xmov:left ? -p[3] : p[3],ymov:0,
            _x:0,_y:-100,_rotation:left ? 180 : 0,_xscale:100,_yscale:100,_alpha:100,_visible:true,
            Z轴坐标:1000000,stateFlags:0,子弹威力:300,最小霰弹值:1,固伤:0,百分比伤害:0,
            伤害类型:"物理",命中率:100,hitCount:0};
        b.removeMovieClip=function():Void { this.__chainDead=true; ChainUnitManager.removeGroup(this.chainGroup); };
        var g:ChainGroup=new ChainGroup(null,b,_root.联弹系统.横向联弹更新,_root.联弹系统.渲染组);
        b.chainGroup=g; g.isObject=true;
        g.盒x=-5; g.盒y=-5; g.盒宽=10; g.盒高=10;
        g.盒固有半宽=12.5; g.盒固有半高=12.5;
        if (nativeMode) ChainVisualBridge.reserveGroup(g);
        _root.联弹系统.横向联弹组装(g);
        return g;
    }
    private static function target(kind:Number):Object {
        var t:Object={hp:10000000,hp满血值:10000000,防御力:100,重量:38,等级:70,
            懒闪避:0,_x:0,_y:0,Z轴坐标:0,魔法抗性:{基础:20,冰:20},shieldAmount:0};
        if (kind==1) { t.防御力=300; t.shieldAmount=17; }
        if (kind==2) { t.hp=97; t.hp满血值=97; t.防御力=1200; }
        if (kind==3) t.懒闪避=5;
        t.shield={owner:t,absorbDamage:function(d:Number,bypass:Boolean,n:Number):Number {
            var remain:Number=d-this.owner.shieldAmount*n;
            return remain>0 ? remain : 0;
        }};
        return t;
    }
    /** 只冻结外部伤害波动。段内 RNG 用真实引擎相同 seed，核对消费后的状态。 */
    private static function measure(g:ChainGroup, cap:Number, hit:Boolean, kind:Number, rngSeed:Number):Object {
        var b:Object=g.bullet;
        var sc:Number=b.霰弹值;
        if (!hit) return {segments:0,damage:0,rng:rngSeed};
        var t:Object=target(kind); var initialHp:Number=t.hp;
        var rng:LinearCongruentialEngine=LinearCongruentialEngine.getInstance();
        rng.restoreState(rngSeed);
        b.flags=kind==3 ? 2 : 66;
        b.伤害类型=kind==3 ? "魔法" : "物理"; b.魔法伤害属性="冰";
        b.damageManager=DamageManagerFactory.resolveForBullet(b);
        if (g.shotgun!=null) g.shotgun.hitCap=cap;
        // 同一首接触的影子窗口；恢复夹具，不提交视觉删弹，供其他独立目标样本复用。
        b.霰弹值=-((sc<<16)|sc);
        var result:DamageResult=DamageCalculator.calculateDamage(b,{伤害加成:0},t,1,kind==1 ? "躲闪" : "未躲闪");
        var output:Object={segments:result.actualScatterUsed,damage:initialHp-t.hp,rng:rng.captureState()};
        if (kind==0) check(output.damage==225*output.segments,"controlled physical damage stays 225 per effective segment");
        b.霰弹值=sc; b.flags=66; b.伤害类型="物理";
        return output;
    }
    private static function compareContact(old:ChainGroup, current:ChainGroup, area:Object, kind:Number, label:String):Void {
        var box:AABBCollider=new AABBCollider(0,0,0,0);
        box.updateFromChainObject(old.bullet);
        var oldHit:Boolean=box.right>area.left && box.left<area.right && box.bottom>area.top && box.top<area.bottom;
        var cap:Number=current.__removed ? 0 : current.shotgun.calculateCap(current,area,0);
        var newHit:Boolean=cap>0;
        cases++;
        if (current.__removed) {
            // 旧保底单元已经触地的历史幽灵不纳入时间衰减等价；新模式必须自然退休。
            groundedCases++;
            check(!newHit && current.bullet.__chainDead, label+" naturally retired physical group");
            return;
        }
        check(oldHit===newHit && (!oldHit || cap===old.bullet.霰弹值),label+" old eligibility and effective segments");
        var rs:Number=2718281+cases*7919;
        var a:Object=measure(old,old.bullet.霰弹值,oldHit,kind,rs);
        var b:Object=measure(current,cap,newHit,kind,rs);
        check(a.segments===b.segments && a.damage===b.damage && a.rng===b.rng,label+" real damage, shield, dodge and RNG parity");
        if (oldHit) oldHits++; if (newHit) newHits++;
        oldSegments+=a.segments; newSegments+=b.segments;
        oldDamage+=a.damage; newDamage+=b.damage;
    }
    private static function matrixProfile(pi:Number):Void {
        var list:Array=profiles();
        ChainVisualBridge.configure(caps());
            var p:Array=list[pi];
            for (var si:Number=0;si<8;si++) {
                for (var mode:Number=0;mode<2;mode++) {
                    for (var ground:Number=0;ground<2;ground++) {
                        var birthSeed:Number=(137+si*271828183)|0;
                        seed=birthSeed; randomCalls=0;
                        var old:ChainGroup=makeGroup(p,0,false,(si&1)==1);
                        var oldCalls:Number=randomCalls,oldSeed:Number=seed;
                        seed=birthSeed; randomCalls=0;
                        var current:ChainGroup=makeGroup(p,1,mode==1,(si&1)==1);
                        check(randomCalls===oldCalls && seed===oldSeed,p[0]+" no extra birth RNG");
                        if (ground==1) { old.bullet.Z轴坐标=0; current.bullet.Z轴坐标=0; }
                        var rangeTicks:Number=(900/p[3])|0;
                        for (var tick:Number=0;tick<rangeTicks+1;tick++) {
                            if (tick>0) {
                                _root.帧计时器.当前帧数++;
                                old.bullet._x+=old.bullet.xmov;
                                current.bullet._x+=current.bullet.xmov;
                                _root.联弹系统.横向联弹更新(old);
                                if (!current.__removed) _root.联弹系统.横向联弹更新(current);
                            }
                            if (tick!=0 && tick!=2 && tick!=5 && tick!=8 && tick!=12
                                && tick!=14 && tick!=20 && tick!=25 && tick!=rangeTicks) continue;
                            if (!current.__removed) {
                                var ref:ChainGroup=current.shotgun.reference;
                                check(ref.盒y===old.盒y && ref.盒高===old.盒高
                                    && ref.bullet.霰弹值===old.bullet.霰弹值,p[0]+" exact legacy reference tick "+tick);
                            }
                            var x:Number=old.bullet._x;
                            var label:String=p[0]+" seed="+si+" native="+mode+" ground="+ground+" tick="+tick;
                            // 真实沙袋宽高及其脚底；另外覆盖窄目标和上下偏移。
                            compareContact(old,current,{left:x-27.96993256,right:x+27.96993256,top:-158.8,bottom:1.01407166},0,label+" bag");
                            compareContact(old,current,{left:x-6,right:x+6,top:-112,bottom:-88},1,label+" narrow dodge shield");
                            compareContact(old,current,{left:x-15,right:x+15,top:-180,bottom:-150},2,label+" upper low hp");
                            compareContact(old,current,{left:x-15,right:x+15,top:-50,bottom:-20},3,label+" lower magic lazy dodge");
                        }
                        ChainUnitManager.removeGroup(old); ChainUnitManager.removeGroup(current);
                        ChainVisualBridge.flush();
                        check(ChainVisualBridge.getStats().reserved==0 && ChainVisualBridge.getStats().groups==0,p[0]+" no reference visual ownership");
                    }
                }
            }
    }
    private static function reportMatrix():Void {
        var list:Array=profiles();
        check(oldHits===newHits && oldSegments===newSegments && oldDamage===newDamage,"all paired aggregate expectations identical");
        trace("[SHOTGUN_CALIBRATION] profiles="+list.length+" seeds=8 modes=2 groundModes=2 ages=rangeBounded targets=4 cases="+cases
            +" naturalRetireCases="+groundedCases+" oldHits="+oldHits+" newHits="+newHits
            +" oldSegments="+oldSegments+" newSegments="+newSegments+" oldDamage="+oldDamage+" newDamage="+newDamage);
    }
    private static function curveAndBudget():Void {
        var p:Array=["SPAS12",10,14,35]; seed=19471;
        var g:ChainGroup=makeGroup(p,1,true,false);
        var expected:Array=[10,10,10,9,9,8,7,6,5,4,4,3,2,2,1];
        var output:String="";
        for (var tick:Number=0;tick<15;tick++) {
            if (tick>0) { g.bullet._x+=35; _root.联弹系统.横向联弹更新(g); }
            check(g.shotgun.reference.bullet.霰弹值==expected[tick],"SPAS12 old time curve tick "+tick);
            if (tick==2 || tick==5 || tick==8 || tick==12 || tick==14)
                output+=(output=="" ? "" : ",")+(tick*35)+":"+g.shotgun.reference.bullet.霰弹值;
        }
        var x:Number=g.bullet._x;
        var area:Object={left:x-30,right:x+30,top:-10000,bottom:10000};
        check(g.bullet.霰弹值==10 && g.单元体列表.length==10,"actual birth budget survives virtual decay");
        for (var i:Number=0;i<10;i++) {
            var target:Object={dispatcher:{}};
            check(g.shotgun.prepareContact(g,target,area,0) && g.shotgun.hitCap==1,"far distinct target limited to one old-effective segment");
            var r:Object=measure(g,1,true,0,12345+i);
            check(r.segments==1,"far actual damage uses one segment");
            g.bullet.霰弹值--;
            check(!g.shotgun.prepareContact(g,target,area,0),"same numeric target cannot retry");
        }
        check(!g.shotgun.prepareContact(g,{dispatcher:{}},area,0),"eleventh distinct target rejected by finite shared budget");
        ChainUnitManager.removeGroup(g);
        trace("[SHOTGUN_SPAS12_CURVE] distance:segments="+output);
        // 异常变速/负推进覆盖聚合退出后的旧逐单元公式，仍不增加显示对象。
        seed=5191; var old:ChainGroup=makeGroup(p,0,false,false);
        seed=5191; g=makeGroup(p,1,true,false);
        for (tick=0;tick<20;tick++) {
            if (tick==5) { old.bullet.xmov=-17; g.bullet.xmov=-17; }
            if (tick==11) { old.bullet.xmov=27; g.bullet.xmov=27; }
            _root.联弹系统.横向联弹更新(old); _root.联弹系统.横向联弹更新(g);
            check(g.shotgun.reference.盒y===old.盒y && g.shotgun.reference.盒高===old.盒高
                && g.shotgun.reference.bullet.霰弹值===old.bullet.霰弹值,"negative motion exact reference tick "+tick);
        }
        ChainUnitManager.removeGroup(old); ChainUnitManager.removeGroup(g);
    }
    public static function stepMatrix():Void {
        trace("[SHOTGUN_CALIBRATION_BATCH] profile="+profileIndex+" cases="+cases);
        try {
            matrixProfile(profileIndex);
            profileIndex++;
            if (profileIndex==profiles().length) finish(true);
        } catch (error) {
            check(false,"runtime exception profile="+profileIndex+" cases="+cases+" error="+error);
            finish(false);
        }
    }
    private static function finish(success:Boolean):Void {
        delete _root.gameworld.onEnterFrame;
        if (success) {
            try { reportMatrix(); curveAndBudget(); }
            catch (error) { check(false,"curve exception "+error); }
        }
        ChainVisualBridge.disconnect();
        var manager:Object=ChainUnitManager;
        manager.acquireUnit=saved.acquire; manager.releaseUnit=saved.release;
        saved.noise.randomFluctuation=saved.fluctuation; saved.rng.restoreState(saved.rngState);
        _root.随机偏移=saved.random; _root.帧计时器=saved.timer;
        var world:MovieClip=_root.gameworld; _root.gameworld=saved.world; world.removeMovieClip();
        AABBCollider.zoneFrame=-1; saved=null;
        trace("ShotgunCalibrationTest Tests Passed: "+passed);
        trace("ShotgunCalibrationTest Tests Failed: "+failed);
        _root.shotgunCalibrationComplete();
    }
    public static function runAllTests():Void {
        passed=0; failed=0; cases=0; groundedCases=0; oldHits=0; newHits=0;
        oldSegments=0; newSegments=0; oldDamage=0; newDamage=0; clipId=0; profileIndex=0;
        var manager:Object=ChainUnitManager;
        var noise:Object=PinkNoiseEngine.getInstance();
        var rng:LinearCongruentialEngine=LinearCongruentialEngine.getInstance();
        saved={world:_root.gameworld,timer:_root.帧计时器,random:_root.随机偏移,
            acquire:manager.acquireUnit,release:manager.releaseUnit,
            noise:noise,fluctuation:noise.randomFluctuation,rng:rng,rngState:rng.captureState()};
        var world:MovieClip=_root.createEmptyMovieClip("shotgunCalibrationWorld",76546);
        world.createEmptyMovieClip("子弹区域",1); _root.gameworld=world; _root.帧计时器={当前帧数:1};
        AABBCollider.zoneFrame=-1;
        _root.随机偏移=randomOffset; manager.acquireUnit=acquireClip; manager.releaseUnit=releaseClip;
        noise.randomFluctuation=function():Number { return 1; };
        DamageManagerFactory.init();
        world.onEnterFrame=function():Void {
            org.flashNight.arki.bullet.BulletComponent.Chain.ShotgunCalibrationTest.stepMatrix();
        };
    }
}
