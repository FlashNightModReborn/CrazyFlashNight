import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/** 真实 AVM1/生产双枪入口/时间轮/弹药提交；隔离动画、库存与弹体出口，不接触玩家存档。 */
class org.flashNight.arki.unit.Action.Shoot.GunslingerDualCadenceTest {
    private static var passed:Number, failed:Number, frame:Number, serial:Number;
    private static var shots:Array, stamps:Array, caseName:String;
    private static var active:MovieClip;

    private static function check(ok:Boolean, message:String):Void {
        if(ok) passed++; else {failed++; trace("[TEST_FAIL] GunslingerDualCadenceTest: "+caseName+" "+message);}
    }
    private static function near(actual:Number, expected:Number):Boolean {
        return !isNaN(actual) && Math.abs(actual-expected)<0.000001;
    }
    private static function capture(props:Object):Void {
        var side:Number=props.子弹种类=="off-probe"?1:0;
        shots[side].push(frame);stamps[side].push(props.发射间隔毫秒);
    }
    private static function start(side:Number):Void {
        active[side==0?"动作A":"动作B"]=true;
        active.man[side==0?"主手开始射击":"副手开始射击"]();
    }
    private static function release(side:Number):Void {active[side==0?"动作A":"动作B"]=false;}
    private static function ticks(count:Number):Void {
        while(count-- > 0) {
            frame++;_root.帧计时器.当前帧数=frame;
            EnhancedCooldownWheel.I().tick();
            if(active.动作A) active.man.主手开始射击();
            if(active.动作B) active.man.副手开始射击();
        }
    }
    private static function weaponData(side:Number, semi:Boolean):Object {
        return {capacity:100,interval:side==0?600:1200,singleshoot:semi,clipname:"probe-magazine",split:1,
            diffusion:1,sound:"",muzzle:"",bullet:side==0?"main-probe":"off-probe",velocity:30,
            bullethit:"",power:100,bulletsize:50,impact:5,targethit:""};
    }
    private static function fixture(level:Number, mainSemi:Boolean, offSemi:Boolean, enabled:Boolean):Void {
        EnhancedCooldownWheel.I().reset();frame=0;shots=[[],[]];stamps=[[],[]];
        var u:MovieClip=_root.createEmptyMovieClip("__gunslingerCadence"+(++serial),_root.getNextHighestDepth());
        active=u;_root.控制目标=u._name;
        u.攻击模式="双枪";u.状态="双枪站立";u.hp=100;u.Z轴坐标=0;
        u.动作A=u.动作B=u.动作C=false;u.主手射击中=u.副手射击中=false;
        u.手枪={name:"main-probe",value:{shot:0,level:1}};
        u.手枪2={name:"off-probe",value:{shot:0,level:1}};
        u.手枪弹匣容量=u.手枪2弹匣容量=100;
        u.手枪属性=weaponData(0,mainSemi);u.手枪2属性=weaponData(1,offSemi);
        u.被动技能={枪械师:{启用:enabled,等级:level}};
        u.dispatcher=new EventDispatcher();u.dispatcher.subscribe("processShot",FireEventComponent.processShot,u);
        u.手枪射击=WeaponFireCore.PISTOL_SHOOT;u.手枪2射击=WeaponFireCore.PISTOL2_SHOOT;
        var m:MovieClip=u.createEmptyMovieClip("man",1);
        m.gotoAndPlay=function(label:String):Void {this.lastLabel=label;};
        m.射击许可标签=true;m.枪={枪:{装扮:{枪口位置:{}}}};m.枪2={枪:{装扮:{枪口位置:{}}}};
        ShootInitCore.initWeaponSystem(m,u,{weaponType:"双枪",isDualGun:true,
            mainWeaponData:u.手枪属性,subWeaponData:u.手枪2属性,extraParams:{}});
    }
    private static function finish():Void {
        trace("[GUNSLINGER_CADENCE] case="+caseName+" main="+shots[0].join(",")+" off="+shots[1].join(",")
            +" mainMs="+stamps[0].join(",")+" offMs="+stamps[1].join(","));
        check(active.手枪.value.shot==shots[0].length&&active.手枪2.value.shot==shots[1].length,
            "each captured shot consumes exactly one round in its own hand");
        ShootCore.cleanup(active);
        check(EnhancedCooldownWheel.I().getActiveTaskCount()==0,"cleanup retires both hands' timers");
        removeMovieClip(active);active=null;EnhancedCooldownWheel.I().reset();
    }
    private static function testTapToHold(spec:Object, side:Number):Void {
        caseName="level"+spec.level+"-"+(side==0?"main":"off")+"-tap-to-hold";
        fixture(spec.level,true,true,true);
        var tapTicks:Number=spec.tapTicks[side],holdTicks:Number=spec.holdTicks[side];
        var tapMs:Number=spec.tapMs[side],holdMs:Number=spec.holdMs[side];
        start(side);
        check(shots[side].length==1&&near(stamps[side][0],tapMs),"initial press carries current-level tap interval");
        for(var press:Number=1;press<3;press++) {
            release(side);ticks(tapTicks-1);start(side);
            check(shots[side].length==press,"repeated press cannot fire one tick before tap cooldown");
            ticks(1);
            check(shots[side].length==press+1&&shots[side][press]==press*tapTicks,
                "repeated press fires exactly at its current-level boundary");
            check(near(stamps[side][press],tapMs),"every fresh press carries the current-level tap interval");
        }
        ticks(holdTicks-1);
        check(shots[side].length==3,"tap-to-hold cannot use an earlier full-level first continuation");
        ticks(1);
        check(shots[side].length==4&&shots[side][3]==2*tapTicks+holdTicks,"tap-to-hold uses the same hold interval as later shots");
        check(near(stamps[side][3],holdMs),"held continuation carries current-level hold interval");
        release(side);ticks(holdTicks+2);
        check(shots[side].length==4&&shots[1-side].length==0,"release stops continuation without firing the other hand");
        finish();
    }
    private static function testHoldToTap(spec:Object, side:Number):Void {
        caseName="level"+spec.level+"-"+(side==0?"main":"off")+"-hold-to-tap";
        fixture(spec.level,true,true,true);
        var tapTicks:Number=spec.tapTicks[side],holdTicks:Number=spec.holdTicks[side];
        var tapMs:Number=spec.tapMs[side],holdMs:Number=spec.holdMs[side];
        start(side);ticks(holdTicks-1);
        check(shots[side].length==1,"first held gap cannot run at full-level speed");
        ticks(1);ticks(holdTicks);
        check(shots[side].length==3&&shots[side][1]==holdTicks&&shots[side][2]==2*holdTicks,
            "first and later held gaps are equal for this level");
        check(near(stamps[side][1],holdMs)&&near(stamps[side][2],holdMs),"both held shots publish the level-aware interval");
        release(side);ticks(tapTicks-1);start(side);
        check(shots[side].length==3,"release-and-repress still respects the last shot's tap cooldown");
        ticks(1);
        check(shots[side].length==4&&shots[side][3]==2*holdTicks+tapTicks,"hold-to-tap rearms at the tap boundary");
        check(near(stamps[side][3],tapMs),"hold-to-tap changes the bullet interval back to tap");
        ticks(holdTicks);
        check(shots[side].length==5&&shots[side][4]==2*holdTicks+tapTicks+holdTicks,"repress-and-hold resumes the current-level hold cadence");
        release(side);ticks(holdTicks+2);
        check(shots[side].length==5&&shots[1-side].length==0,"released chain stays retired and other hand stays idle");
        finish();
    }
    private static function testMixed(spec:Object, semiSide:Number):Void {
        caseName="level"+spec.level+"-mixed-semi-"+(semiSide==0?"main":"off");
        fixture(spec.level,semiSide==0,semiSide==1,true);start(0);start(1);ticks(108);
        for(var side:Number=0;side<2;side++) {
            var gap:Number=side==semiSide?spec.holdTicks[side]:(side==0?18:36);
            var expected:Number=Math.floor(108/gap)+1;
            check(shots[side].length==expected,"mixed hand "+side+" keeps its independent firing count");
            for(var i:Number=0;i<shots[side].length;i++) {
                check(shots[side][i]==i*gap,"mixed hand "+side+" has no extra or early shot "+i);
                var ms:Number=side==semiSide?(i==0?spec.tapMs[side]:spec.holdMs[side]):(side==0?600:1200);
                check(near(stamps[side][i],ms),"mixed hand "+side+" publishes its own interval "+i);
            }
        }
        release(0);release(1);ticks(60);finish();
    }
    private static function testDisabled():Void {
        caseName="disabled-ordinary-semi";fixture(1,true,true,false);start(0);start(1);ticks(90);
        check(shots[0].length==1&&shots[1].length==1,"disabled skill does not enable held semi-auto fire");
        check(stamps[0][0]==600&&stamps[1][0]==1200,"disabled skill retains both base intervals");
        release(0);release(1);ticks(2);start(0);start(1);
        check(shots[0].length==2&&shots[1].length==2,"disabled skill still accepts separate presses");
        release(0);release(1);ticks(60);finish();
    }
    public static function runAllTests():Void {
        passed=failed=serial=0;
        var saved:Object={world:_root.gameworld,control:_root.控制目标,pause:_root.暂停,clock:_root.帧计时器,save:_root.存档系统,
            ui:_root.玩家信息界面,sound:_root.soundEffectManager,bullet:_root.子弹区域shoot传递,inventory:_root.物品栏,
            contain:ItemUtil.singleContain,total:ItemUtil.getTotal,submit:ItemUtil.singleSubmit,rates:ShootCore._lastShotTimes};
        _root.gameworld=_root;_root.暂停=false;_root.帧计时器={当前帧数:0};_root.存档系统={};
        _root.玩家信息界面={玩家必要信息界面:{}};_root.soundEffectManager={playSound:function():Void {}};
        _root.物品栏={背包:{getIndexes:function():Array {return [];}}};_root.子弹区域shoot传递=capture;ShootCore._lastShotTimes={};
        ItemUtil.singleContain=function(name:String,amount:Number):Object {return {};};
        ItemUtil.getTotal=function(name:String):Number {return 10;};
        ItemUtil.singleSubmit=function(name:String,amount:Number):Boolean {return true;};
        // 独立预期表：主手基础 600ms、副手 1200ms；tick 为 30fps 调度后的最早可接受时刻。
        var levels:Array=[
            {level:1,tapMs:[600,1200],holdMs:[900,1800],tapTicks:[18,36],holdTicks:[27,54]},
            {level:5,tapMs:[560,1120],holdMs:[833.333333333333,1666.666666666667],tapTicks:[17,34],holdTicks:[25,50]},
            {level:10,tapMs:[510,1020],holdMs:[750,1500],tapTicks:[16,31],holdTicks:[23,45]}
        ];
        try {
            for(var l:Number=0;l<levels.length;l++)for(var side:Number=0;side<2;side++) {
                testTapToHold(levels[l],side);testHoldToTap(levels[l],side);testMixed(levels[l],side);
            }
            testDisabled();
        }catch(error){check(false,"unexpected exception: "+error);if(active!=null)finish();}
        EnhancedCooldownWheel.I().reset();
        _root.gameworld=saved.world;_root.控制目标=saved.control;_root.暂停=saved.pause;_root.帧计时器=saved.clock;_root.存档系统=saved.save;
        _root.玩家信息界面=saved.ui;_root.soundEffectManager=saved.sound;_root.子弹区域shoot传递=saved.bullet;_root.物品栏=saved.inventory;
        ItemUtil.singleContain=saved.contain;ItemUtil.getTotal=saved.total;ItemUtil.singleSubmit=saved.submit;ShootCore._lastShotTimes=saved.rates;
        trace("--- GunslingerDualCadenceTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
    }
}
