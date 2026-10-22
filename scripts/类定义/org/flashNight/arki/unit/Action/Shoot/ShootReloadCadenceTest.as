import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.FireEventComponent;
import org.flashNight.neur.Event.EventDispatcher;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/** 隔离真实 AVM1/时间轮/生产射击与弹药提交；子弹出口不生成战场对象，不读写存档。 */
class org.flashNight.arki.unit.Action.Shoot.ShootReloadCadenceTest {
    private static var passed:Number, failed:Number, frame:Number, serial:Number;
    private static var shots:Array, caseName:String;
    private static var packs:Number;
    private static function check(ok:Boolean, label:String):Void {
        if(ok) passed++; else {failed++; trace("[TEST_FAIL] ShootReloadCadenceTest: " + label);}
    }
    private static function capture(props:Object):Void {shots.push(frame);}
    private static function ticks():Void {frame++; _root.帧计时器.当前帧数=frame; EnhancedCooldownWheel.I().tick();}
    private static function fixture(semi:Boolean, gs:Boolean):MovieClip {
        EnhancedCooldownWheel.I().reset(); ShootCore._lastShotTimes={}; frame=0; shots=[]; packs=10;
        var u:MovieClip=_root.createEmptyMovieClip("__cadence"+(++serial),_root.getNextHighestDepth());
        _root.控制目标=u._name;
        u.攻击模式="长枪";u.状态="长枪站立";u.hp=100;u.Z轴坐标=0;
        u.长枪={name:"cadence",value:{shot:2,level:1}};u.长枪弹匣容量=80;
        u.长枪属性={capacity:80,interval:400,singleshoot:semi,reloadType:"tube",clipname:"probe",diffusion:1,split:1};
        u.被动技能={枪械师:{启用:gs,等级:10}};u.动作A=false;u.动作B=false;u.动作C=false;
        u.dispatcher=new EventDispatcher();u.dispatcher.subscribe("processShot",FireEventComponent.processShot,u);
        u.长枪射击=WeaponFireCore.LONG_GUN_SHOOT;
        var m:MovieClip=u.createEmptyMovieClip("man",1);
        m.gotoAndPlay=function(label):Void {this.lastLabel=label;};
        m.gotoAndStop=function(label):Void {this.lastLabel=label;};
        m.射击许可标签=true;m.枪={枪:{装扮:{枪口位置:{}}}};
        ShootInitCore.initWeaponSystem(m,u,{weaponType:"长枪",isDualGun:false,weaponData:u.长枪属性});
        return u;
    }
    private static function finishCase(u:MovieClip):Void {
        trace("[CADENCE] case="+caseName+" shots="+shots.join(",")+" tasks="+EnhancedCooldownWheel.I().getActiveTaskCount()+" loop="+u.keepshooting+" chain="+u._gunslingerChain_keepshooting);
        ShootCore.cleanup(u);removeMovieClip(u);EnhancedCooldownWheel.I().reset();
    }
    private static function scenario(semi:Boolean, gs:Boolean, priorShot:Boolean, holdR:Boolean):Void {
        caseName=(semi?(gs?"gunslinger":"semi"):"auto")+"-prior="+priorShot+"-holdR="+holdR;
        var u:MovieClip=fixture(semi,gs);var m:MovieClip=u.man;
        if(priorShot){u.动作A=true;m.开始射击();ticks();u.动作A=false;}
        m.开始换弹();u.动作A=true;
        for(var i:Number=0;i<65;i++){
            u.动作C=holdR;
            if(holdR)m.开始换弹();else m.开始射击();
            ReloadManager.controlReloadFrameRate(m);
            ticks();
        }
        var minimum:Number=semi&&gs?11:12;
        for(var j:Number=1;j<shots.length;j++)check(shots[j]-shots[j-1]>=minimum,caseName+" interval "+shots[j-1]+"->"+shots[j]);
        u.动作A=false;u.动作C=false;for(var k:Number=0;k<20;k++)ticks();
        check(u.keepshooting==undefined&&u._gunslingerChain_keepshooting==undefined,caseName+" releases continuation");
        finishCase(u);
    }
    private static function repeatedTapCancellation():Void {
        caseName="semi-priorShot-cancel-rapidTap";
        var u:MovieClip=fixture(true,false),m:MovieClip=u.man;
        u.动作A=true;m.开始射击();u.动作A=false;for(var warm:Number=0;warm<6;warm++)ticks();m.开始换弹();
        for(var i:Number=0;i<130;i++){
            u.动作A=(i%2)==0;if(u.动作A)m.开始射击();ticks();
        }
        var shortAfterFirst:Number=0;
        for(var j:Number=2;j<shots.length;j++)if(shots[j]-shots[j-1]<12)shortAfterFirst++;
        trace("[SUSTAINED_REPRO] shots="+shots.join(",")+" shortAfterFirst="+shortAfterFirst);
        check(shortAfterFirst==0,"rapid taps never inherit an earlier shot's unlock callback");
        u.动作A=false;for(var k:Number=0;k<30;k++)ticks();finishCase(u);
    }
    private static function testRejectionAndLateOwners():Void {
        for(var mode:Number=0;mode<2;mode++) {
            caseName="no-stock-"+mode;var u:MovieClip=fixture(mode==1,false);var m:MovieClip=u.man;
            u.动作A=true;m.开始射击();var key:String=u._name+"_keepshooting";
            var rate:Object=ShootCore._lastShotTimes[key];var before:Number=u.长枪.value.shot;packs=0;
            m.开始换弹();
            check(ShootCore._lastShotTimes[key]===rate,"rejected reload preserves rate owner");
            check(u.主手射击中&&m.lastLabel=="射击","rejected reload preserves active shot and pose");
            check(u.长枪.value.shot==before&&!m.换弹标签,"rejected reload cannot mutate ammo or enter reload");
            u.动作A=false;for(var t:Number=0;t<15;t++)ticks();finishCase(u);
        }
        caseName="stale-owners";u=fixture(true,false);m=u.man;u.动作A=true;m.开始射击();
        key=u._name+"_keepshooting";var oldRate:Object=ShootCore._lastShotTimes[key];
        var oldSemi:Object=u._semiLock_keepshooting_owner;
        var oldUnit:MovieClip=u;
        removeMovieClip(u);serial--;u=fixture(true,false);m=u.man;u.动作A=true;m.开始射击();
        check(oldUnit===u,"stale callbacks exercise actual same-path MovieClip rebinding");
        var fresh:Object=ShootCore._lastShotTimes[key];
        ShootCore._clearRateLimit(key,oldRate);
        ShootCore._onSemiCooldownDone(oldUnit,"_semiLock_keepshooting","动作A",null,oldSemi);
        ShootCore._pollRelease(oldUnit,"_semiLock_keepshooting","动作A",null,oldSemi);
        check(ShootCore._lastShotTimes[key]===fresh,"late prior shot cannot clear replacement cooldown");
        check(u._semiLock_keepshooting===true,"late prior semi callback cannot replace the new press lock");
        ShootCore.cleanup(u);check(EnhancedCooldownWheel.I().getActiveTaskCount()==0,"teardown cancels rate, pending unlock and polling tasks");
        finishCase(u);
        caseName="pause";u=fixture(false,false);m=u.man;u.动作A=true;_root.暂停=true;m.开始射击();m.开始换弹();
        check(shots.length==0&&!m.换弹标签,"pause rejects both fire and reload before commit");
        check(!ShootCore._lastShotTimes[u._name+"_keepshooting"],"failed paused shot does not spend a fire interval");
        _root.暂停=false;m.开始射击();check(shots.length==1,"resume accepts a real shot");finishCase(u);
    }
    public static function runAllTests():Void {
        passed=failed=serial=0;
        var saved:Object={world:_root.gameworld,control:_root.控制目标,pause:_root.暂停,clock:_root.帧计时器,save:_root.存档系统,
            ui:_root.玩家信息界面,sound:_root.soundEffectManager,bullet:_root.子弹区域shoot传递,
            contain:ItemUtil.singleContain,total:ItemUtil.getTotal,submit:ItemUtil.singleSubmit};
        _root.gameworld=_root;_root.暂停=false;_root.帧计时器={当前帧数:0};_root.存档系统={};
        _root.玩家信息界面={玩家必要信息界面:{}};_root.soundEffectManager={playSound:function():Void {}};
        _root.子弹区域shoot传递=capture;
        ItemUtil.singleContain=function(name:String,amount:Number):Object {return ShootReloadCadenceTest.packs>=amount?{}:null;};
        ItemUtil.getTotal=function(name:String):Number {return ShootReloadCadenceTest.packs;};
        ItemUtil.singleSubmit=function(name:String,amount:Number):Boolean {if(ShootReloadCadenceTest.packs<amount)return false;ShootReloadCadenceTest.packs-=amount;return true;};
        try {
            testRejectionAndLateOwners();repeatedTapCancellation();
            for(var mode:Number=0;mode<3;mode++)for(var prior:Number=0;prior<2;prior++)for(var held:Number=0;held<2;held++)scenario(mode>0,mode==2,prior==1,held==1);
        }catch(error){check(false,"unexpected exception: "+error);}
        _root.gameworld=saved.world;_root.控制目标=saved.control;_root.暂停=saved.pause;_root.帧计时器=saved.clock;
        _root.存档系统=saved.save;_root.玩家信息界面=saved.ui;_root.soundEffectManager=saved.sound;_root.子弹区域shoot传递=saved.bullet;
        ItemUtil.singleContain=saved.contain;ItemUtil.getTotal=saved.total;ItemUtil.singleSubmit=saved.submit;
        trace("--- ShootReloadCadenceTest: "+passed+"/"+(passed+failed)+" passed, "+failed+" failed ---");
    }
}
