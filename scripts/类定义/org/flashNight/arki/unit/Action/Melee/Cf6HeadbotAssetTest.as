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
    private static var cases:Array,probes:Array;
    private static var cleanupProbes:Array;
    private static var nativeKnockback:Function;
    private static var link:String="敌人-CF6大头机器人";
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6HeadbotAssetTest: "+label);}
    }
    private static function record():Object {
        return {shots:0,deathBursts:0,frames:[],moves:0,done:0,kills:0,deathChecks:0,removed:false,
            physics:0,powerOk:true,areaOk:true,contractOk:true,frontOk:true};
    }
    public static function runAllTests():Void {
        passed=failed=ticks=fxCount=0;ready=finished=false;cases=[];probes=[];cleanupProbes=[];
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
                this._y=this.Z轴坐标;this.fixtureRecord.moves++;
            };
            this.方向改变=function(dir:String):Void {this.方向=dir;this._xscale=dir=="左"?-100:100;};
            this.动画完毕=function():Void {
                this.fixtureRecord.done++;this.攻击目标="无";this.状态改变(this.hp>0?"空手站立":"血腥死");
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
        check(loader.loadClip("../flashswf/arts/new/Codex大头机器人素材.swf",library),"load published SWF");
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
        ready=true;ticks=0;
    }
    private static function capture(data:Object):Void {
        var u:MovieClip=library[data.发射者],rec:Object=u.fixtureRecord;
        if(rec==undefined)return;
        if(data.cf6DeathBurst===true){
            rec.deathBursts++;check(rec.deathBursts==1,"one death burst "+u._name);
            if(rec.deathBursts==1)Cf6RobotCombatTest.captureDeath(data,u);return;
        }
        var action:String=u.headbotAttackOwner.action,frame:Number=u.man._currentframe;
        if(action=="thrust" && rec.thrustData==undefined)rec.thrustData=data;
        rec.shots++;rec.frames.push(frame);
        rec.powerOk=rec.powerOk && data.子弹威力==(action=="beam"?150:100);
        rec.contractOk=rec.contractOk && data.子弹种类=="近战子弹" && data.子弹速度==0
            && data.霰弹值==1 && data.Z轴攻击范围==24 && data.shootZ==u.Z轴坐标
            && data.击倒率==10 && data.垂直击退速度==0 && data.百分比伤害==undefined
            && data.伤害类型==(action=="beam"?"魔法":"物理")
            && (action=="beam"?data.魔法伤害属性=="波":data.魔法伤害属性==undefined);
        var width:Number=action=="beam"?(frame==15?304.16436767578125:339.1916198730469):
            frame==3?160.11163330078125:frame==5?207.03753662109375:frame==8?249.0428466796875:295.9677429199219;
        var bounds:Object=data.区域定位area.getBounds(library);
        rec.areaOk=rec.areaOk && Math.abs(bounds.xMax-bounds.xMin-width)<0.3
            && Math.abs(bounds.yMax-bounds.yMin-(action=="beam"?30:50))<0.3;
        rec.frontOk=rec.frontOk && (data.shootX-u._x)*(u.方向=="右"?1:-1)>0;
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
        }
        if(ticks==4)for(i=0;i<cases.length;i++) {
            c=cases[i];u=c.actor;
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
                var count:Number=c.move=="beam"?2:c.move=="thrust"?4:0;
                check(rec.shots==count,"contact count "+c.move+" "+c.side+" got "+rec.shots);
                if(count>0){
                    check(rec.frames.join(",")==(c.move=="beam"?"15,23":"3,5,8,12"),"authored contact frames "+i);
                    check(rec.areaOk && rec.powerOk && rec.contractOk && rec.frontOk,"damage geometry contract "+i);
                }
                check(rec.physics==0,"no airborne physics "+i);
                if(dead){
                    check(rec.kills==1,"standard kill once "+i);
                    check(rec.removed && rec.deathChecks==1 && rec.deathOptions.noCorpse!==true,"death retirement once "+i);
                    check(rec.stamps==1 && rec.stampLayer==2 && rec.stampSettled===true && rec.allDebrisGrounded===true && rec.debrisCount==14,"fourteen grounded corpse pieces stamped exactly once "+i);
                    check(rec.deathBursts==1,"death explosion settles once "+i);
                }else check(c.actor.状态=="空手站立" && rec.done>=1,"action recovery "+i);
                if(!dead)check(c.actor.headbotBeamShield==-1 && c.actor.shield.getCapacity()==0,"finished action retains no laser shield "+i);
            }
            Cf6RobotCombatTest.headCombo(cases[1].actor,cases[1].record.thrustData,nativeKnockback);
            Cf6RobotCombatTest.headCombo(cases[13].actor,cases[13].record.thrustData,nativeKnockback);
            Cf6RobotCombatTest.headShield(cases[0].actor);
            finish();
        }
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        check(FragmentAnimator.getActiveAnimationCount()==0,"all completed fragment instances released");
        check(Cf6RobotCombatTest.finish(),"real robot combat contracts");
        loader.removeListener(listener);library.removeMovieClip();driver.removeMovieClip();
        trace("Cf6HeadbotAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        _root.cf6HeadbotAssetComplete();
    }
}
