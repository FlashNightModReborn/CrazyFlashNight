import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.spatial.animation.FragmentAnimator;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DeathEventComponent;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.unit.Action.Melee.Cf6RobotCombatTest;

/** Published SWF behavior under isolated damage / template fixtures; no save access. */
class org.flashNight.arki.unit.Action.Melee.Cf6HeadbotAssetTest {
    private static var library:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var passed:Number,failed:Number,ticks:Number,fxCount:Number;
    private static var ready:Boolean,finished:Boolean;
    private static var cases:Array,r8Cases:Array,probes:Array;
    private static var cleanupProbes:Array;
    private static var nativeKnockback:Function;
    private static var link:String="敌人-CF6大头机器人";
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6HeadbotAssetTest: "+label);}
    }
    private static function record():Object {
        return {shots:0,deathBursts:0,frames:[],moves:0,done:0,kills:0,deathChecks:0,removed:false,
            physics:0,powerOk:true,areaOk:true,contractOk:true,frontOk:true,fallingShellOk:true};
    }
    public static function runAllTests():Void {
        passed=failed=ticks=fxCount=0;ready=finished=false;cases=[];r8Cases=[];probes=[];cleanupProbes=[];
        Cf6RobotCombatTest.reset("headbot");nativeKnockback=_root.敌人函数.被击移动;
        library=_root.createEmptyMovieClip("__headbotLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__headbotTestDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;_root.暂停=false;
        _root.add2map=function(unit:MovieClip,layer:Number):Void {
            var rec:Object=unit.fixtureRecord;rec.stamps=(rec.stamps|0)+1;
            rec.stampLayer=layer;rec.stampSettled=unit.man.尸体碎片.cf6Settled;
            rec.corpseBounds=unit.man.尸体碎片.getBounds(unit);
            var scope:MovieClip=unit.man.尸体碎片,ground:Object={x:0,y:0};
            unit.localToGlobal(ground);scope.globalToLocal(ground);
            rec.allDebrisGrounded=true;rec.debrisCount=0;
            for(var fragmentIndex:Number=1;scope["碎片"+fragmentIndex]!=null;fragmentIndex++){
                rec.debrisCount++;
                if(Math.abs(scope["碎片"+fragmentIndex]._y-ground.y)>0.1)rec.allDebrisGrounded=false;
            }
            trace("[CF6_CORPSE_STAMP] unit="+unit._name+" stamps="+rec.stamps+" settled="+rec.stampSettled
                +" grounded="+rec.allDebrisGrounded+" pieces="+rec.debrisCount+" bounds="+rec.corpseBounds.xMin+","+rec.corpseBounds.yMin+","+rec.corpseBounds.xMax+","+rec.corpseBounds.yMax);

        };
        _root.控制目标="__none";_root.控制目标全自动=false;_root.是否阴影=true;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};
        _root.效果=function(name:String):Void {Cf6HeadbotAssetTest.fxCount++;};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.敌人函数={配置音效:function():Void {},行走:function():Void {this.fixtureManualWalk=true;},
            标准击杀:function(u:MovieClip):Void {
                u.fixtureRecord.kills++;u.状态改变("血腥死");u._killed=true;DeathEventComponent.onDeath(u);
            }};
        _root.子弹区域shoot传递=function(data:Object):Void {Cf6HeadbotAssetTest.capture(data);};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.空手攻击力=100;this.等级=40;
            this.shield=AdaptiveShield.createDormant("headbot-fixture");this.shield.setOwner(this);
            this.状态="空手站立";this.攻击模式="空手";this.方向="右";this.攻击目标="无";
            this.Z轴坐标=this._y=200;this._x=200;this.myxscale=100;this.是否为敌人=true;
            this.倒地=this.浮空=this.硬直中=this.刚体=this.免疫击退=false;
            this.unitAI={data:{xrange:100,zrange:10,xdistance:50}};
            this.swapDepths=function():Void {};
            this.行走X速度=6;this.行走Y速度=4;this.跑X速度=12;this.跑Y速度=8;
            this.移动=function(dir:String,speed:Number):Void {
                this._x+=dir=="右"?speed:dir=="左"?-speed:0;
                this.Z轴坐标+=dir=="下"?speed:dir=="上"?-speed:0;
                this._y=this.Z轴坐标;this.fixtureRecord.moves++;this.fixtureRecord.maxStep=Math.max(this.fixtureRecord.maxStep|0,speed);
            };
            this.方向改变=function(dir:String):Void {this.方向=dir;this._xscale=dir=="左"?-100:100;};
            this.动画完毕=function():Void {
                this.fixtureRecord.done++;this.fixtureRecord.lastRecoveryFrame=this.man._currentframe;this.攻击目标="无";this.状态改变(this.hp>0?"空手站立":"血腥死");
            };
            this.击飞浮空=function():Void {this.fixtureRecord.physics++;this.浮空=true;};
            this.击飞倒地=function():Void {this.fixtureRecord.physics++;this.倒地=true;};
            this.死亡检测=function(options:Object):Void {
                var rec:Object=this.fixtureRecord;rec.deathChecks++;rec.deathOptions=options;
                if(this.hp<=0){
                    this.计算经验值=function():Void {this.已加经验值=true;this.fixtureRecord.experience=(this.fixtureRecord.experience|0)+1;};
                    _root.cf6ProductionDeathCheck.call(this,options);rec.removed=true;
                }
            };
            this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {Cf6HeadbotAssetTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6HeadbotAssetTest.check(false,"load "+error);Cf6HeadbotAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip(_root.cf6HeadbotAssetUnderTest==undefined?"../flashswf/arts/new/Codex大头机器人素材.swf":_root.cf6HeadbotAssetUnderTest,library),"load published SWF");
        driver.onEnterFrame=function():Void {Cf6HeadbotAssetTest.tick();};
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();mc._visible=false;
        var states:Array=["空手站立","空手行走","空手跑","空手跳","近战","空手攻击","拾取","躲闪","被击","击倒","倒地","被投","血腥死","消失"];
        for(var side:Number=0;side<2;side++)for(var s:Number=0;s<states.length;s++) {
            var p:MovieClip=library.attachMovie(link,"headbotProbe"+probes.length,library.getNextHighestDepth(),{fixtureRecord:record()});
            check(p!=null,"attach state "+states[s]);probes.push({actor:p,state:states[s],side:side});
        }
        var moves:Array=["beam","thrust","hit0","hit1","down","knockdown","throw","death","interruptBeam","interruptThrust","deadBeam","deadThrust"];
        for(var j:Number=0;j<2;j++)for(var m:Number=0;m<moves.length;m++) {
            var rec:Object=record();
            var u:MovieClip=library.attachMovie(link,"headbotCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:rec});
            check(u!=null,"attach "+moves[m]+" "+j);cases.push({actor:u,move:moves[m],side:j,record:rec});
        }
        var r8Moves:Array=["antiair","retreat_blast","shield"];
        for(j=0;j<2;j++)for(m=0;m<r8Moves.length;m++) {
            rec=record();
            u=library.attachMovie(link,"headbotR8Case"+r8Cases.length,library.getNextHighestDepth(),{fixtureRecord:rec});
            check(u!=null,"attach "+r8Moves[m]+" "+j);r8Cases.push({actor:u,move:r8Moves[m],side:j,record:rec});
        }
        ready=true;ticks=0;
    }
    private static function capture(data:Object):Void {
        var u:MovieClip=library[data.发射者],rec:Object=u.fixtureRecord;
        if(rec==undefined)return;
        if(data.cf6DeathBurst===true){
            rec.deathBursts++;check(rec.deathBursts==1,"one death burst "+u._name);
            if(rec.deathBursts==1)Cf6RobotCombatTest.captureDeath(data,u);return;
        }
        if(data.cf6FallingShell===true){
            rec.fallingShells=(rec.fallingShells|0)+1;
            var shellBounds:Object=data.区域定位area.getBounds(library);
            rec.fallingShellOk=rec.fallingShellOk && data.区域定位area!=null
                && data.子弹种类=="近战子弹" && data.子弹速度==0
                && data.伤害类型=="魔法" && data.魔法伤害属性=="波"
                && Math.abs(data.子弹威力-150)<0.001 && data.Z轴攻击范围==42
                && Math.abs(shellBounds.xMax-shellBounds.xMin-180)<0.3
                && Math.abs(shellBounds.yMax-shellBounds.yMin-120)<0.3
                && (data.shootX-u._x)*(u.方向=="右"?1:-1)>0;
            return;
        }
        var action:String=u.headbotAttackOwner.action,frame:Number=u.man._currentframe;
        if(action=="thrust" && rec.thrustData==undefined)rec.thrustData=data;
        rec.shots++;rec.frames.push(frame);
        var expectedPower:Number=action=="retreat_blast"?180:action=="thrust"?100:150;
        var expectedVy:Number=action=="antiair"?-6:0;
        var isMagic:Boolean=action!="thrust";
        rec.powerOk=rec.powerOk && Math.abs(data.子弹威力-expectedPower)<0.001;
        rec.contractOk=rec.contractOk && data.子弹种类=="近战子弹" && data.子弹速度==0
            && data.霰弹值==1 && data.Z轴攻击范围==24 && data.shootZ==u.Z轴坐标
            && data.击倒率==10 && data.垂直击退速度==expectedVy && data.百分比伤害==undefined
            && data.伤害类型==(isMagic?"魔法":"物理")
            && (isMagic?data.魔法伤害属性=="波":data.魔法伤害属性==undefined);
        var width:Number=action=="beam"?(frame==15?564.9035616:597.7502118):
            action=="antiair"?120:action=="retreat_blast"?250:
            frame==3?165.4662934:frame==5?214.9662934:frame==8?280.8162934:298.0369264;
        var height:Number=action=="beam"?36:action=="antiair"?190:action=="retreat_blast"?165:50;
        var bounds:Object=data.区域定位area.getBounds(library);
        rec.areaOk=rec.areaOk && Math.abs(bounds.xMax-bounds.xMin-width)<0.3
            && Math.abs(bounds.yMax-bounds.yMin-height)<0.3;
        if(action=="antiair"){
            var marker:MovieClip=frame==45?u.man.headbotAntiairMuzzleRear:u.man.headbotAntiairMuzzleFront;
            var origin:Object={x:0,y:0};marker.localToGlobal(origin);library.globalToLocal(origin);
            var expected:Object={x:frame==45?-54.7:27.1,y:(frame==45?-59:-62.45)-66*0.549988};
            u.man.localToGlobal(expected);library.globalToLocal(expected);
            check(Math.abs(origin.x-expected.x)<0.15 && Math.abs(origin.y-expected.y)<0.15,"native muzzle follows visible cannon "+u._name+"/"+frame);
            check(Math.abs(data.shootX-origin.x)<0.15 && Math.abs(bounds.yMax-origin.y)<0.15,
                "upper hit volume begins at its own cannon tip "+u._name+"/"+frame);
            trace("[HEADBOT_MUZZLE] unit="+u._name+" frame="+frame+" x="+origin.x+" y="+origin.y+" bottom="+bounds.yMax);
            if(_root.cf6HeadbotCapture===true)captureMuzzle(u,frame);
        }else rec.frontOk=rec.frontOk && (data.shootX-u._x)*(u.方向=="右"?1:-1)>0;
        // Reentrant duplicate delivery must not produce a second contact.
        u.headbotStrike(u.man,u.man.攻击点,1);
    }
    private static function shadowCheck(u:MovieClip,label:String):Void {
        var shadow:MovieClip=u.man.headbotShadow;
        check(shadow!=null && shadow._visible,"body-owned shadow "+label);
        var p:Object={x:0,y:0};shadow.localToGlobal(p);library.globalToLocal(p);
        check(Math.abs(p.y-u.Z轴坐标)<0.2,"ground position "+label);
        check(library.shadow==undefined && u.shadow==undefined,"private shadow namespace "+label);
    }
    private static function waveCounter():Void {
        var levels:Array=[30,60,99];
        var handler:UniversalDamageHandle=UniversalDamageHandle.getInstance();
        for(var i:Number=0;i<levels.length;i++){
            var resistance:Number=10+levels[i]*0.2;
            var target:Object={防御力:1300,等级:levels[i],魔法抗性:{基础:resistance,波:resistance}};
            var result:DamageResult=DamageResult.getIMPACT();
            handler.handleBulletDamage({伤害类型:"魔法",魔法伤害属性:"波",破坏力:100},null,target,null,result);
            var wave:Number=target.损伤值;
            check(Math.abs(wave-(100-resistance))<0.001,"real wave handler uses Arkclaw resistance at "+levels[i]);
            handler.handleBulletDamage({伤害类型:"物理",破坏力:100},null,target,null,result);
            check(Math.abs(target.损伤值-18.75)<0.001 && wave>target.损伤值*3,"wave bypasses high physical defense at "+levels[i]);
        }
    }
    private static function decisions():Void {
        var u:MovieClip=probes[0].actor;
        u.headbotClock=100;u.headbotReadyAt=0;
        check(u.headbotChooseAttack(120,0,0)=="thrust","close thrust");
        check(u.headbotChooseAttack(300,0,0)=="beam","far beam");
        check(u.headbotChooseAttack(120,0,75)=="beam","air target uses upper beam");
        check(u.headbotSelectBeamSubmode(120,75)=="antiair","air target selects antiair submode");
        check(u.headbotSelectBeamSubmode(120,0)=="retreat_blast","close target selects retreat_blast submode when off cooldown");
        check(u.headbotSelectBeamSubmode(175,0)=="retreat_blast","close-mid target selects retreat_blast submode");
        u.headbotNextRetreatBlast=200;
        check(u.headbotSelectBeamSubmode(175,0)=="beam","retreat_blast cooldown falls back to standard beam");
        u.headbotNextRetreatBlast=0;
        check(u.headbotSelectBeamSubmode(260,0)=="beam","far target selects standard beam submode");
        u.headbotNextAntiair=0;
        check(u.headbotSelectBeamSubmode(295,0)=="antiair","stop-range ground target selects antiair bombardment when off cooldown");
        check(u.headbotBombardReady(420,60,0)===true,"extended cross-lane target selects delayed ground bombardment");
        u.headbotNextAntiair=200;
        check(u.headbotSelectBeamSubmode(295,0)=="beam","cooldown falls back to standard beam");
        check(u.headbotBombardReady(420,60,0)===false,"cooldown blocks extended bombardment");
        check(u.headbotSelectBeamSubmode(120,75)=="beam","airborne target cannot bypass bombardment cooldown");
        u.headbotNextAntiair=0;
        check(u.headbotChooseAttack(331,0,0)=="none","outside beam reach");
        check(u.headbotChooseAttack(120,25,0)=="none","lane mismatch");
        check(u.headbotChooseAttack(120,0,101)=="none","high target rejected");
        check(u.headbotChooseAttack(Number("bad"),0,0)=="none","invalid distance rejected");
        u.headbotReadyAt=101;check(u.headbotChooseAttack(120,0,0)=="none","reaction delay");u.headbotReadyAt=0;
        var target:MovieClip=library.createEmptyMovieClip("headbotDecisionTarget",library.getNextHighestDepth());
        target.hp=1000;target._x=700;target._y=target.Z轴坐标=250;target.createEmptyMovieClip("area",1);
        u.攻击目标=target._name;u.headbotUpdateMovement();
        check(u.右行===true && u.下行===true,"approach and align");
        u.行走();check(u._x>200 && u.Z轴坐标>200,"movement consumes private policy");
        target._x=u._x+280;target.Z轴坐标=u.Z轴坐标+10;u.headbotUpdateMovement();
        check(!u.左行 && !u.右行 && !u.上行 && !u.下行,"hysteresis stops close to lane");
        target._x=u._x+320;target.Z轴坐标=u.Z轴坐标+20;u.headbotUpdateMovement();
        check(!u.右行 && !u.下行,"hysteresis does not oscillate");
        _root.控制目标=u._name;u.行走();check(u.fixtureManualWalk===true,"manual input delegates");_root.控制目标="__none";
        var savedChange:Function=u.状态改变;
        u.状态改变=function(state:String):Void {this.requestedState=state;};
        u.headbotCancelAttack();u.状态="空手站立";u.headbotTargetName=target._name;
        target._x=u._x+339;target._y=target.Z轴坐标=u.Z轴坐标;target.__headbotActionIdentity={};
        u.headbotCombo={target:target._name,identity:target.__headbotActionIdentity,expires:200};
        u.headbotNextAntiair=0;u.headbotReadyAt=0;u.headbotClock=99;u.headbotTick();
        check(u.requestedState=="空手攻击" && u.headbotPendingBeamSubmode=="","actual AI preserves hit-confirmed beam while bombardment is available");
        u.headbotCombo=null;u.headbotNextAntiair=200;u.headbotClock=99;
        target._x=u._x+200;target._y=target.Z轴坐标-60;u.headbotTick();
        check(u.requestedState=="空手攻击" && u.headbotPendingBeamSubmode=="","actual AI respects airborne bombardment cooldown");
        u.状态改变=savedChange;u.headbotNextAntiair=0;target._y=target.Z轴坐标;
        u.状态="空手攻击";u.headbotBeginAttack(u.man,"beam");var old:Object=u.man.headbotToken;
        u.headbotBeginAttack(u.man,"beam");var token:Object=u.man.headbotToken;u.man.headbotToken=old;
        check(!u.headbotCanAct(u.man),"stale attack identity rejected");u.man.headbotToken=token;
        check(u.headbotCanAct(u.man),"current attack identity accepted");
        _root.暂停=true;check(!u.headbotCanAct(u.man),"paused attack blocked");_root.暂停=false;
        u.硬直中=true;check(!u.headbotCanAct(u.man),"hitstop blocks contact");u.硬直中=false;
        u.headbotCancelAttack();check(!u.headbotCanAct(u.man),"cancelled attack blocked");
        u.攻击目标="无";u.状态="空手站立";target.removeMovieClip();
        _root.是否阴影=false;u.man.headbotShadow.updateHeadbotShadow();check(!u.man.headbotShadow._visible,"shadow option off");
        _root.是否阴影=true;u._y=u.Z轴坐标-40;u._xscale=-160;u._yscale=160;
        u.man.headbotShadow.updateHeadbotShadow();shadowCheck(u,"lifted mirrored");
        u.浮空=true;u.倒地=true;u.垂直速度=-6;u.headbotTick();
        check(!u.浮空 && !u.倒地 && u.垂直速度==0 && u._y==u.Z轴坐标,"hover ownership clears forced airborne state");
        u._xscale=u._yscale=100;
    }
    private static function tick():Void {
        if(finished)return;ticks++;
        if(!ready){if(ticks>300){check(false,"load timeout");finish();}return;}
        if(ticks==3){
            for(var s:Number=0;s<probes.length;s++) {
                var pr:Object=probes[s];pr.actor.方向改变(pr.side==0?"右":"左");pr.actor.状态改变(pr.state);
            }
            for(var i:Number=0;i<cases.length;i++) {
                var c:Object=cases[i],u:MovieClip=c.actor;u.方向改变(c.side==0?"右":"左");
                if(c.move=="death")u.hp=0;
                var state:String=c.move=="thrust" || c.move=="interruptThrust" || c.move=="deadThrust"?"近战":
                    c.move=="beam" || c.move=="interruptBeam" || c.move=="deadBeam"?"空手攻击":
                    c.move=="down"?"倒地":c.move=="knockdown"?"击倒":c.move=="throw"?"被投":c.move=="death"?"血腥死":"被击";
                u.状态改变(state);
            }
            for(var r8i:Number=0;r8i<r8Cases.length;r8i++) {
                var r8c:Object=r8Cases[r8i],r8u:MovieClip=r8c.actor;r8u.方向改变(r8c.side==0?"右":"左");
                r8u.攻击目标="headbotActiveTarget";
                if(r8c.move=="antiair" || r8c.move=="retreat_blast")r8u.headbotPendingBeamSubmode=r8c.move;
                if(r8c.move=="shield")r8u.headbotPendingShield=true;
                r8u.状态改变(r8c.move=="shield"?"被击":"空手攻击");
            }
        }
        if(ticks==4)for(i=0;i<cases.length;i++) {
            c=cases[i];u=c.actor;
            if(c.move=="hit0" || c.move=="hit1" || c.move=="down" || c.move=="knockdown" || c.move=="throw")u.攻击目标="headbotActiveTarget";
            if(c.move=="hit0")u.man.gotoAndStop("a0");
            if(c.move=="hit1")u.man.gotoAndStop("a1");
            if(c.move=="interruptBeam" || c.move=="interruptThrust")u.状态改变("被击");
            if(c.move=="deadBeam" || c.move=="deadThrust")u.hp=0;
            if(c.move=="beam")check(u.headbotBeamShield>=0 && u.shield.getCapacity()==200,"laser owns shield during windup "+i);
            if(c.move=="interruptBeam")check(u.headbotBeamShield==-1 && u.shield.getCapacity()==0,"interrupt removes laser shield "+i);
        }
        if(ticks==5){
            _root.暂停=true;
            for(i=0;i<cases.length;i++){c=cases[i];c.pausedFrame=c.actor.man._currentframe;c.pausedClock=c.actor.headbotClock;c.pausedShots=c.record.shots;}
        }
        if(ticks==10){
            for(i=0;i<cases.length;i++) {
                c=cases[i];check(c.actor.man._currentframe==c.pausedFrame,"pause body "+i);
                check(c.actor.headbotClock==c.pausedClock,"pause clock "+i);
                check(c.record.shots==c.pausedShots,"pause blocks damage "+i);
            }
            _root.暂停=false;
            for(s=0;s<probes.length;s++) {
                pr=probes[s];if(pr.state=="消失")continue;
                check(pr.actor.man!=null,"body exists "+pr.state+" "+pr.side);shadowCheck(pr.actor,pr.state+" "+pr.side);
            }
        }
        if(ticks==35){
            _root.暂停=true;
            for(i=0;i<cases.length;i++){
                c=cases[i];var debris:MovieClip=c.actor.man.尸体碎片;
                if(debris!=null)c.fragmentPause={x:debris.碎片1._x,y:debris.碎片1._y,frame:c.actor.man._currentframe};
            }
        }
        if(ticks==40){
            for(i=0;i<cases.length;i++){
                c=cases[i];if(c.fragmentPause!=null){
                    debris=c.actor.man.尸体碎片;
                    check(debris.碎片1._x==c.fragmentPause.x && debris.碎片1._y==c.fragmentPause.y
                        && c.actor.man._currentframe==c.fragmentPause.frame,"pause freezes physical corpse fragments "+i);
                }
            }
            _root.暂停=false;
        }
        if(ticks==20)for(i=0;i<cases.length;i++) {
            c=cases[i];if(c.move=="death" || c.move=="deadBeam" || c.move=="deadThrust"){
                check(c.actor.man.headbotBodyDriver!=null && c.actor.man._currentframe>1,"death driver survives standard cleanup "+i);
                shadowCheck(c.actor,"death "+i);
            }
        }
        if(ticks==34 || ticks==60 || ticks==119){
            var fragmentScope:MovieClip=cases[7].actor.man.尸体碎片;
            var animator:Object=FragmentAnimator,instance:Object=animator._animationInstances[fragmentScope.cf6AnimationId];
            trace("[CF6_CORPSE_DIAGNOSTIC] tick="+ticks+" bodyFrame="+cases[7].actor.man._currentframe
                +" id="+fragmentScope.cf6AnimationId+" settled="+fragmentScope.cf6Settled+" step="+typeof fragmentScope.cf6EngineStep
                +" handler="+typeof fragmentScope.onEnterFrame+" x="+fragmentScope.碎片1._x+" y="+fragmentScope.碎片1._y
                +" ground="+instance._config.groundY+" running="+instance._isRunning
                +" vx="+instance._velocityX+" vy="+instance._velocityY+" scope="+instance._scope._target);
        }
        if(ticks==82)for(var cleanupIndex:Number=0;cleanupIndex<2;cleanupIndex++){
            var cleanupRecord:Object=record();
            var cleanupActor:MovieClip=library.attachMovie(link,"cleanupCorpse"+cleanupIndex,library.getNextHighestDepth(),{fixtureRecord:cleanupRecord});
            cleanupProbes.push({actor:cleanupActor,record:cleanupRecord});
        }
        if(ticks==85)for(cleanupIndex=0;cleanupIndex<cleanupProbes.length;cleanupIndex++){
            cleanupProbes[cleanupIndex].actor.hp=0;cleanupProbes[cleanupIndex].actor.headbotTick();
        }
        if(ticks==106)for(cleanupIndex=0;cleanupIndex<cleanupProbes.length;cleanupIndex++){
            var cleanupCase:Object=cleanupProbes[cleanupIndex];
            var cleanupScope:MovieClip=cleanupCase.actor.man.尸体碎片;
            cleanupCase.animationId=cleanupScope.cf6AnimationId;
            check(_root.地图元件.地图元件破碎动画运行中(cleanupCase.animationId),"cleanup probe has active physical debris "+cleanupIndex);
            if(cleanupIndex==0){
                var otherScope:MovieClip=cleanupProbes[1].actor.man.尸体碎片;
                var otherX:Number=otherScope.碎片1._x,otherY:Number=otherScope.碎片1._y;
                cleanupScope.onEnterFrame.call(otherScope);
                check(otherScope.碎片1._x==otherX && otherScope.碎片1._y==otherY,"stale fragment update cannot advance a replacement scope");
                cleanupScope.onUnload.call(otherScope);
                check(_root.地图元件.地图元件破碎动画运行中(otherScope.cf6AnimationId)
                    && typeof otherScope.cf6EngineStep=="function","stale unload cannot stop or clear replacement fragments");
            }
            if(cleanupIndex==1){
                var savedWorld:MovieClip=_root.gameworld;
                var replacementWorld:MovieClip=_root.createEmptyMovieClip("__corpseReplacementWorld",_root.getNextHighestDepth());
                _root.gameworld=replacementWorld;cleanupScope.onEnterFrame();_root.gameworld=savedWorld;
                replacementWorld.removeMovieClip();
                check(!_root.地图元件.地图元件破碎动画运行中(cleanupCase.animationId),"world replacement cancels only the owned debris instance");
            }
            cleanupCase.actor.removeMovieClip();
        }
        if(ticks==108)for(cleanupIndex=0;cleanupIndex<cleanupProbes.length;cleanupIndex++){
            cleanupCase=cleanupProbes[cleanupIndex];
            check(!_root.地图元件.地图元件破碎动画运行中(cleanupCase.animationId),"forced unload releases debris instance "+cleanupIndex);
            check((cleanupCase.record.stamps|0)==0,"abandoned corpse cannot stamp into the next scene "+cleanupIndex);
        }
        if(ticks==120){
            decisions();waveCounter();
            for(i=0;i<cases.length;i++) {
                c=cases[i];var rec:Object=c.record;var dead:Boolean=c.move=="death" || c.move=="deadBeam" || c.move=="deadThrust";
                var count:Number=(c.move=="beam" || c.move=="antiair")?2:c.move=="retreat_blast"?5:c.move=="thrust"?4:0;
                check(rec.shots==count,"contact count "+c.move+" "+c.side+" got "+rec.shots);
                if(count>0){
                    var expectedFrames:String=c.move=="beam"?"15,23":c.move=="antiair"?"45,49":c.move=="retreat_blast"?"83,86,89,92,95":"3,5,8,12";
                    check(rec.frames.join(",")==expectedFrames,"authored contact frames "+i+" got "+rec.frames.join(","));
                    check(rec.areaOk && rec.powerOk && rec.contractOk && rec.frontOk,"damage geometry contract "+i);
                }
                if(c.move=="retreat_blast")check(rec.moves>0,"retreat_blast recoils backward "+i);
                if(c.move=="shield")check(c.actor.headbotShieldSkillId>=0 && c.actor.shield.getCapacity()==250,"shield action grants temporary shield "+i);
                check(rec.physics==0,"no airborne physics "+i);
                if(dead){
                    check(rec.kills==1,"standard kill once "+i);
                    check(rec.removed && rec.deathChecks==1 && rec.deathOptions.noCorpse!==true,"death retirement once "+i);
                    check(rec.stamps==1 && rec.stampLayer==2 && rec.stampSettled===true && rec.allDebrisGrounded===true && rec.debrisCount==14,"fourteen grounded corpse pieces stamped exactly once "+i);
                    check(rec.deathBursts==1,"death explosion settles once "+i);
                }else{
                    check(c.actor.状态=="空手站立" && rec.done>=1,"action recovery "+i);
                    if(c.move=="hit0" || c.move=="hit1" || c.move=="down" || c.move=="knockdown" || c.move=="throw")
                        check(rec.lastRecoveryFrame==25,"ordinary hit completes full 25-frame R8 recovery "+c.move+" "+i+" got "+rec.lastRecoveryFrame);
                }
                if(!dead && c.move!="shield")check(c.actor.headbotBeamShield==-1 && c.actor.shield.getCapacity()==0,"finished action retains no laser shield "+i);
            }
            for(r8i=0;r8i<r8Cases.length;r8i++) {
                r8c=r8Cases[r8i];rec=r8c.record;
                count=r8c.move=="antiair"?2:r8c.move=="retreat_blast"?5:0;
                check(rec.shots==count,"r8 contact count "+r8c.move+" "+r8c.side+" got "+rec.shots);
                if(count>0){
                    expectedFrames=r8c.move=="antiair"?"45,49":"83,86,89,92,95";
                    check(rec.frames.join(",")==expectedFrames,"r8 authored contact frames "+r8i+" got "+rec.frames.join(","));
                    check(rec.areaOk && rec.powerOk && rec.contractOk && rec.frontOk,"r8 damage geometry contract "+r8i);
                }
                if(r8c.move=="antiair"){
                    check(rec.fallingShells==2 && rec.fallingShellOk===true,"r8 antiair spawns 2 delayed ground bombardment shells "+r8i+" got "+rec.fallingShells+" ok="+rec.fallingShellOk);
                    check(rec.lastRecoveryFrame==70,"r8 antiair completes full 70-frame recovery under active target "+r8i+" got "+rec.lastRecoveryFrame);
                }
                if(r8c.move=="retreat_blast"){
                    check(rec.moves==77 && Math.abs(r8c.actor._x-200)==320 && rec.maxStep<=6,
                        "retreat_blast executes bounded 320px retreat in collision-safe steps "+r8i+" moves="+rec.moves+" dx="+Math.abs(r8c.actor._x-200));
                    check(r8c.actor.headbotLastRetreatDistance==320,"completed retreat records actual distance "+r8i);
                    trace("[HEADBOT_RETREAT] side="+r8c.side+" distance="+Math.abs(r8c.actor._x-200)+" steps="+rec.moves+" maxStep="+rec.maxStep);
                    check(rec.lastRecoveryFrame==109,"r8 retreat_blast completes full 109-frame recovery under active target "+r8i+" got "+rec.lastRecoveryFrame);
                }
                if(r8c.move=="shield"){
                    check(r8c.actor.headbotShieldSkillId>=0 && r8c.actor.shield.getCapacity()==250,"shield action grants temporary shield "+r8i);
                    check(rec.lastRecoveryFrame==88,"r8 shield completes full 88-frame retract animation under active target "+r8i+" got "+rec.lastRecoveryFrame);
                }
                check(r8c.actor.状态=="空手站立" && rec.done>=1,"r8 action recovery "+r8i);
            }
            Cf6RobotCombatTest.headCombo(cases[1].actor,cases[1].record.thrustData,nativeKnockback);
            Cf6RobotCombatTest.headCombo(cases[13].actor,cases[13].record.thrustData,nativeKnockback);
            Cf6RobotCombatTest.headShield(cases[0].actor);
            finish();
        }
    }
    private static function captureMuzzle(unit:MovieClip,frame:Number):Void {
        var key:String="head-"+unit.方向+"-"+frame,width:Number=360,height:Number=400;
        var pixels:BitmapData=new BitmapData(width,height,true,0);
        var matrix:Matrix=new Matrix(unit.方向=="左"?-1.1:1.1,0,0,1.1,180,325);
        pixels.draw(unit.man,matrix);
        trace("[HEADBOT_CAPTURE_BEGIN] "+key+" "+width+" "+height);
        for(var y:Number=0;y<height;y++){
            var line:String="",previous:Number=pixels.getPixel32(0,y),count:Number=1;
            for(var x:Number=1;x<width;x++){
                var color:Number=pixels.getPixel32(x,y);
                if(color==previous)count++;
                else {line+=previous.toString(16)+":"+count+",";previous=color;count=1;}
            }
            line+=previous.toString(16)+":"+count;
            trace("[HEADBOT_CAPTURE_ROW] "+key+" "+y+" "+line);
        }
        trace("[HEADBOT_CAPTURE_END] "+key);pixels.dispose();
    }
    private static function retreatBoundaries():Void {
        var unit:MovieClip=r8Cases[1].actor;
        var target:MovieClip=library.createEmptyMovieClip("headbotRetreatRecoveryTarget",library.getNextHighestDepth());
        target.area=target.createEmptyMovieClip("area",1);
        unit.攻击目标=target._name;target.hp=1000;target._x=unit._x+600;target.Z轴坐标=unit.Z轴坐标;
        unit.headbotRetreatHoldUntil=unit.headbotClock+24;unit.headbotUpdateMovement();
        check(!unit.左行 && !unit.右行,"retreat recovery preserves firing space before re-approach");
        unit.headbotClock+=24;unit.headbotUpdateMovement();check(unit.右行,"normal approach resumes after bounded recovery");
        var saved:Function=unit.移动;unit.fixtureWallX=unit._x-10;
        unit.移动=function(dir:String,speed:Number):Void {this._x=Math.max(this.fixtureWallX,this._x-speed);};
        var owner:Object={retreatSign:-1,retreatMoved:0},start:Number=unit._x;
        for(var i:Number=0;i<26;i++)unit.headbotRetreatStep(owner);
        check(Math.abs(start-unit._x-10)<0.1 && Math.abs(owner.retreatMoved-10)<0.1,"retreat honors blocked travel and records actual distance");
        unit.移动=saved;
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        check(FragmentAnimator.getActiveAnimationCount()==0,"all completed fragment instances released");
        check(Cf6RobotCombatTest.finish(),"real robot combat contracts");
        loader.removeListener(listener);library.removeMovieClip();driver.removeMovieClip();
        retreatBoundaries();
        trace("Cf6HeadbotAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        _root.cf6HeadbotAssetComplete();
    }
}
