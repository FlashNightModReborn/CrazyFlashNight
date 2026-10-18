import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;
import org.flashNight.arki.unit.Action.Melee.Cf6RobotCombatTest;

/** Actual published vector timelines; isolated fixtures replace game state and damage. */
class org.flashNight.arki.unit.Action.Melee.Cf6BladebotAssetTest {
    private static var library:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var passed:Number,failed:Number,ticks:Number,fxCount:Number;
    private static var ready:Boolean,finished:Boolean;
    private static var cases:Array,probes:Array,images:Object,combos:Array;
    private static var link:String="敌人-CF6大刀机器人";

    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++; else {failed++;trace("[TEST_FAIL] Cf6BladebotAssetTest: "+label);}
    }
    private static function record():Object {
        return {shots:0,deathBursts:0,front:0,back:0,moves:0,done:0,deathChecks:0,removed:false,
            physics:0,powerOk:true,areaOk:true,contractOk:true};
    }
    public static function runAllTests():Void {
        passed=failed=ticks=fxCount=0;ready=finished=false;cases=[];probes=[];images={};combos=[];
        Cf6RobotCombatTest.reset("bladebot");
        library=_root.createEmptyMovieClip("__bladebotLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__bladebotTestDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;_root.暂停=false;
        _root.控制目标="__no_player";_root.控制目标全自动=false;_root.是否阴影=true;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};
        _root.add2map=function():Void {};_root.add2map2=function():Void {};
        _root.效果=function(name:String):Void {Cf6BladebotAssetTest.fxCount++;};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.子弹区域shoot传递=function(data:Object):Void {Cf6BladebotAssetTest.capture(data);};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.mp=0;this.空手攻击力=100;this.等级=30;
            this.状态="空手站立";this.攻击模式="空手";this.方向="右";this.攻击目标="无";
            this.Z轴坐标=this._y=200;this._x=200;this.myxscale=100;this.是否为敌人=true;
            this.倒地=this.浮空=this.硬直中=this.刚体=this.免疫击退=false;
            this.unitAI={data:{xrange:100,zrange:10,xdistance:50}};
            this.swapDepths=function():Void {};this.行走=function():Void {};
            this.移动=function(dir:String,speed:Number):Void {
                this._x+=dir=="右"?speed:dir=="左"?-speed:0;this.fixtureRecord.moves++;
            };
            this.方向改变=function(dir:String):Void {this.方向=dir;this._xscale=dir=="左"?-100:100;};
            this.状态改变=function(state:String):Void {
                if(this.状态==state) return;this.状态=state;this.gotoAndStop(state);
            };
            this.动画完毕=function():Void {
                this.fixtureRecord.done++;this.倒地=false;this.攻击目标="无";
                this.状态改变(this.hp>0?"空手站立":"血腥死");
            };
            this.击飞浮空=function():Void {this.fixtureRecord.physics++;this.浮空=true;};
            this.击飞倒地=function():Void {this.倒地=true;this._y=this.Z轴坐标;};
            this.死亡检测=function():Void {
                this.fixtureRecord.deathChecks++;
                if(this.hp<=0){this.fixtureRecord.removed=true;this.removeMovieClip();}
            };
            this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {Cf6BladebotAssetTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6BladebotAssetTest.check(false,"load "+error);Cf6BladebotAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Codex大刀机器人素材.swf",library),"load published SWF");
        driver.onEnterFrame=function():Void {Cf6BladebotAssetTest.tick();};
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        var states:Array=["空手站立","空手行走","空手跑","空手跳","近战","空手攻击","激光束","拾取","躲闪","被击","击倒","倒地","被投","血腥死","消失"];
        for(var side:Number=0;side<2;side++)for(var s:Number=0;s<states.length;s++) {
            var p:MovieClip=library.attachMovie(link,"bladebotProbe"+probes.length,library.getNextHighestDepth(),{fixtureRecord:record()});
            check(p!=null,"attach state "+states[s]);
            probes.push({actor:p,state:states[s],side:side,bodySeen:false});
        }
        var moves:Array=["cleave","sweep","hit0","hit1","down","knockdown","death","interrupt","dead","interruptSweep","deadSweep","beam","interruptBeam","deadBeam"];
        for(var j:Number=0;j<2;j++)for(var m:Number=0;m<moves.length;m++) {
            var rec:Object=record();
            var u:MovieClip=library.attachMovie(link,"bladebotCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:rec});
            check(u!=null,"attach "+moves[m]+" "+j);
            cases.push({actor:u,move:moves[m],side:j,record:rec});
        }
        for(var ci:Number=0;ci<3;ci++){
            var rec:Object=record();rec.comboShots=0;rec.impacts=0;rec.laserHits=0;
            var u:MovieClip=library.attachMovie(link,"comboActor"+ci,library.getNextHighestDepth(),{fixtureRecord:rec});
            combos.push({actor:u,record:rec,side:ci==1?1:0,immune:ci==2});
        }
        ready=true;ticks=0;
    }
    private static function capture(data:Object):Void {
        var u:MovieClip=library[data.发射者],rec:Object=u.fixtureRecord;
        if(rec==undefined)return;
        if(data.cf6DeathBurst===true){
            rec.deathBursts++;check(rec.deathBursts==1,"one death burst "+u._name);
            check(u.man._currentframe==32,"death burst covers the first broken-body atlas frame "+u._name);
            if(rec.deathBursts==1)Cf6RobotCombatTest.captureDeath(data,u);return;
        }
        rec.shots++;
        var heavy:Boolean=u.bladebotAttackOwner.action=="cleave",beam:Boolean=u.bladebotAttackOwner.action=="beam";
        rec.powerOk=rec.powerOk && data.子弹威力==(heavy?240:100);
        rec.contractOk=rec.contractOk && data.子弹种类=="近战子弹" && data.子弹速度==0
            && data.霰弹值==1 && data.Z轴攻击范围==30 && data.shootZ==u.Z轴坐标
            && data.击倒率==(heavy?3:10) && data.百分比伤害==undefined && data.血量上限击溃==undefined
            && data.水平击退速度==(heavy?24:beam?2:3) && data.垂直击退速度==(heavy || beam?0:2)
            && data.伤害类型==(beam?"魔法":"物理") && (beam?data.魔法伤害属性=="波":data.魔法伤害属性==undefined);
        var bounds:Object=data.区域定位area.getBounds(library);
        if(beam){
            var transform:Matrix=u.man.攻击点.transform.matrix;
            var length:Number=25*Math.sqrt(transform.a*transform.a+transform.b*transform.b);
            var thickness:Number=25*Math.sqrt(transform.c*transform.c+transform.d*transform.d);
            rec.areaOk=rec.areaOk && Math.abs(length-619.05)<0.3 && Math.abs(thickness-32)<0.3;
            trace("[BLADEBOT_BEAM_GEOMETRY] unit="+u._name+" angle="+u.bladebotAttackOwner.beamAngle
                +" length="+length+" thickness="+thickness+" bounds="+bounds.xMin+","+bounds.yMin+","+bounds.xMax+","+bounds.yMax);
        }else rec.areaOk=rec.areaOk && bounds.xMax-bounds.xMin>210 && bounds.xMax-bounds.xMin<240
            && Math.abs(bounds.yMax-bounds.yMin-(heavy?180:200))<0.3;
        var dx:Number=(data.shootX-u._x)*(u.方向=="右"?1:-1);
        if(dx>0)rec.front++;else if(dx<0)rec.back++;
        if(beam && u._name=="bladebotCase11" && !images["beam-right"])render(u,"beam-right");
        if(beam && u._name=="bladebotCase25" && !images["beam-left"])render(u,"beam-left");
        var before:Number=rec.shots;u.bladebotStrike(u.man,u.man.攻击点,heavy?2.4:1);
        check(rec.shots==before,"contact duplicate cannot replay damage");
        if(u._name.indexOf("comboActor")==0){
            var target:MovieClip=library[u.攻击目标];
            if(data.区域定位area.hitTest(target.area)){
                var bullet:MovieClip=library.createEmptyMovieClip("impactBullet"+ticks,library.getNextHighestDepth());
                for(var key:String in data)bullet[key]=data[key];
                bullet.破坏力=data.子弹威力;
                var result:DamageResult=DamageResult.getIMPACT();
                UniversalDamageHandle.getInstance().handleBulletDamage(bullet,u,target,null,result);
                target.hp-=target.损伤值;
                ImpactStateHandler.handleImpactState(target,bullet,result,u.方向,true);
                if(heavy)rec.impacts++;if(beam)rec.laserHits++;
                trace("[BLADEBOT_COMBO_CONTACT] actor="+u._name+" action="+u.bladebotAttackOwner.action+" dx="+Math.abs(target._x-u._x)+" speed="+target.speed+" decel="+target.减速度+" callback="+typeof target.onEnterFrame+" immune="+target.免疫击退);
                bullet.removeMovieClip();
            }
            if(beam)rec.comboShots++;
        }
    }
    private static function pixelHex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function render(u:MovieClip,key:String):Void {
        if(u==null)return;
        var info:Boolean=u.人物文字信息._visible;u.人物文字信息._visible=false;
        var wide:Boolean=key.indexOf("beam-")==0;
        var imageWidth:Number=wide?1300:640;
        var bd:BitmapData=new BitmapData(imageWidth,430,true,0xffe8e6e2);
        var matrix:Matrix=u.transform.matrix;
        var scale:Number=key=="airborne-shadow"?0.65:1.4;
        matrix.a*=scale;matrix.b*=scale;matrix.c*=scale;matrix.d*=scale;matrix.tx=wide?(u.方向=="左"?1050:250):320;matrix.ty=350;
        bd.draw(u,matrix);u.人物文字信息._visible=info;
        var visible:Number=0,edge:Number=0;
        for(var y:Number=0;y<430;y+=3)for(var x:Number=0;x<imageWidth;x+=3)if(bd.getPixel(x,y)!=0xe8e6e2)visible++;
        check(visible>200,"native pixels "+key+" "+visible);images[key]=true;
        if(_root.bladebotCapture===true) {
            trace("[BLADEBOT_IMAGE_BEGIN] "+key+" "+imageWidth+" 430");
            var chunk:String="";
            for(var row:Number=0;row<430;row++) {
                var parts:Array=[],last:Number=bd.getPixel32(0,row),count:Number=1;
                for(var col:Number=1;col<imageWidth;col++) {
                    var value:Number=bd.getPixel32(col,row);
                    if(value==last)count++;else{parts.push(pixelHex(last)+":"+count);last=value;count=1;}
                }
                parts.push(pixelHex(last)+":"+count);
                var encoded:String=row+"="+parts.join(",")+";";
                if(chunk.length>0 && chunk.length+encoded.length>8192){trace("[BLADEBOT_IMAGE_DATA] "+key+" "+chunk);chunk="";}
                chunk+=encoded;
            }
            if(chunk.length>0)trace("[BLADEBOT_IMAGE_DATA] "+key+" "+chunk);
            trace("[BLADEBOT_IMAGE_END] "+key);
        }
        bd.dispose();
    }
    private static function shadowCheck(u:MovieClip,label:String):Void {
        check(u.bladebotShadow!=null && u.bladebotShadow._visible,"shadow "+label);
        check(library.shadow==undefined && u.shadow==undefined,"shadow registration private "+label);
        var p:Object={x:0,y:0};u.bladebotShadow.localToGlobal(p);library.globalToLocal(p);
        check(Math.abs(p.y-u.Z轴坐标)<0.2,"shadow grounded "+label);
    }
    private static function decisions():Void {
        var u:MovieClip=probes[0].actor;
        check(u.命中率==30,"mechanical aim is applied at initialization");
        u.bladebotClock=100;u.bladebotReadyAt=0;u.bladebotNextSweep=0;
        check(u.bladebotChooseAttack(120,0,0)=="sweep","close sweep");
        check(u.bladebotChooseAttack(230,0,0)=="cleave","approaching heavy cleave");
        check(u.bladebotChooseAttack(180,0,110)=="sweep","overhead sweep can catch a reachable airborne target");
        check(u.bladebotChooseAttack(246,0,0)=="none","gap outside melee and before beam");
        check(u.bladebotChooseAttack(400,0,0)=="beam","beam covers displaced target");
        check(u.bladebotChooseAttack(601,0,0)=="none","beam finite end");
        u.bladebotNextBeam=101;check(u.bladebotChooseAttack(400,0,0)=="none","beam cooldown respected");u.bladebotNextBeam=0;
        check(u.bladebotChooseAttack(100,31,0)=="none","lane mismatch");
        check(u.bladebotChooseAttack(100,0,151)=="none","high target rejected");
        check(u.bladebotChooseAttack(Number("bad"),0,0)=="none","invalid coordinate rejected");
        u.bladebotReadyAt=101;check(u.bladebotChooseAttack(100,0,0)=="none","recovery");u.bladebotReadyAt=0;
        u.bladebotNextSweep=101;check(u.bladebotChooseAttack(100,0,0)=="cleave","sweep cooldown");u.bladebotNextSweep=0;
        var target:MovieClip=library.createEmptyMovieClip("bladebotDecisionTarget",library.getNextHighestDepth());
        target.hp=1000;target._x=400;target.Z轴坐标=target._y=200;
        target.createEmptyMovieClip("area",1);
        var change:Function=u.状态改变;
        u.状态改变=function(state:String):Void {this.requestedState=state;this.状态=state;};
        u.攻击目标=target._name;u.bladebotTargetName=target._name;
        var flags:Array=["暂停","manual","硬直中","倒地","浮空","dead","badTarget"];
        for(var i:Number=0;i<flags.length;i++) {
            u.状态="空手站立";u.requestedState="none";u.bladebotClock=99;
            var flag:String=flags[i];
            if(flag=="暂停")_root.暂停=true;else if(flag=="manual")_root.控制目标=u._name;
            else if(flag=="dead")u.hp=0;else if(flag=="badTarget")target.hp=0;else u[flag]=true;
            u.bladebotTick();
            check(u.requestedState==(flag=="dead"?"血腥死":"none"),"AI guard "+flag);
            _root.暂停=false;_root.控制目标="__no_player";u.hp=target.hp=1000;u.硬直中=u.倒地=u.浮空=false;
        }
        u.状态="空手站立";u.requestedState="none";u.bladebotClock=99;
        target.Z轴坐标=target._y=240;u.bladebotTick();
        check(u.requestedState=="none" && u.下行===true,"align before attack");
        target.Z轴坐标=target._y=200;u.bladebotClock=99;u.bladebotTick();
        check(u.requestedState=="空手攻击","private AI selects cleave");
        check(u.unitAI.data.xrange==0 && u.unitAI.data.zrange==30,"shared AI distance cache updated");
        target._x=u._x+180;target.浮空高度=120;
        u.状态="空手站立";u.requestedState="none";u.bladebotClock=99;u.bladebotTick();
        check(u.requestedState=="近战","authored airborne offset selects overhead sweep");
        target.浮空高度=270;
        u.状态="空手站立";u.requestedState="none";u.bladebotClock=99;u.bladebotTick();
        check(u.requestedState=="none","authored high airborne offset does not waste an attack");
        target.浮空高度=Number("bad");
        u.状态="空手站立";u.requestedState="none";u.bladebotClock=99;u.bladebotTick();
        check(u.requestedState=="空手攻击","invalid optional airborne offset preserves ground height");
        target.浮空高度=0;target._x=400;
        u.状态="空手攻击";u.bladebotBeginAttack(u.man,"cleave");
        var first:Object=u.man.bladebotToken;u.bladebotBeginAttack(u.man,"cleave");
        var current:Object=u.man.bladebotToken;u.man.bladebotToken=first;
        check(!u.bladebotCanAct(u.man),"stale action token rejected");u.man.bladebotToken=current;
        check(u.bladebotCanAct(u.man),"current action token accepted");
        _root.暂停=true;check(!u.bladebotCanAct(u.man),"paused action cannot strike or advance");_root.暂停=false;
        u.bladebotCancelAttack();check(!u.bladebotCanAct(u.man),"cancelled action cannot strike");
        u.刚体=u.免疫击退=true;u.bladebotBeginAttack(u.man,"cleave");u.bladebotAttackOwner.ownsRigid=true;
        u.bladebotCancelAttack();check(u.刚体===true && u.免疫击退===true,"external rigidity and displacement immunity preserved");u.刚体=u.免疫击退=false;
        target.__bladebotComboIdentity={};u.bladebotClock=100;u.bladebotReadyAt=u.bladebotNextBeam=0;
        var identity:Object=target.__bladebotComboIdentity;
        u.bladebotCombo={target:target._name,identity:identity,expires:145};
        check(u.bladebotComboReady(target,350,0,0),"live captured target can chain");
        check(!u.bladebotComboReady(target,249,0,0),"combo cannot force close target into range");
        check(!u.bladebotComboReady(target,350,31,0),"combo respects lane");
        u.bladebotNextBeam=101;check(!u.bladebotComboReady(target,350,0,0),"combo respects beam cooldown");u.bladebotNextBeam=0;
        target.__bladebotComboIdentity={};check(!u.bladebotComboReady(target,350,0,0) && u.bladebotCombo==null,"same-name replacement invalidates combo");
        u.bladebotCombo={target:target._name,identity:target.__bladebotComboIdentity,expires:99};
        check(!u.bladebotComboReady(target,350,0,0) && u.bladebotCombo==null,"expired combo cannot fire");
        u.状态改变=change;u.状态="空手站立";u.攻击目标="无";u.左行=u.右行=u.上行=u.下行=false;target.removeMovieClip();
        _root.是否阴影=false;u.bladebotShadow.updateBladebotShadow();check(!u.bladebotShadow._visible,"shadow option off");
        _root.是否阴影=true;u.bladebotShadow.updateBladebotShadow();check(u.bladebotShadow._visible,"shadow option on");
        u._y=160;u._rotation=25;u._xscale=-160;u._yscale=160;
        u.bladebotShadow.updateBladebotShadow();shadowCheck(u,"lifted rotated mirrored");render(u,"airborne-shadow");
        u._y=200;u._rotation=0;u._xscale=u._yscale=100;u.bladebotShadow.updateBladebotShadow();
    }

    private static function comboTick():Void {
        if(ticks==3)for(var i:Number=0;i<combos.length;i++){
            var c:Object=combos[i],u:MovieClip=c.actor;
            u.方向改变(c.side==0?"右":"左");u.bladebotNextSweep=10000;
            var target:MovieClip=library.createEmptyMovieClip("comboTarget"+i,library.getNextHighestDepth());
            target._x=u._x+(c.side==0?185:-185);target._y=target.Z轴坐标=u.Z轴坐标;
            target.hp=10000;target.防御力=300;target.等级=30;target.韧性系数=100;target.躲闪率=50;
            target.魔法抗性={波:0};target.刚体=true;target.免疫击退=c.immune;
            target.硬直中=target.浮空=target.倒地=false;target.remainingImpactForce=0;
            target.移动钝感硬直=function():Void {};
            target.移动=function(direction:String,speed:Number):Void {this._x+=direction=="右"?speed:-speed;};
            target.状态改变=function():Void {};
            target.被击移动=_root.敌人函数.被击移动;
            check(typeof target.被击移动=="function","production knockback function bound "+i);
            var area:MovieClip=target.createEmptyMovieClip("area",1);
            area.beginFill(0xff0000,0);area.moveTo(-25,-180);area.lineTo(25,-180);area.lineTo(25,0);area.lineTo(-25,0);area.lineTo(-25,-180);area.endFill();
            u.攻击目标=target._name;u.bladebotTargetName=target._name;
            u.动画完毕=function():Void {this.fixtureRecord.done++;this.状态改变("空手站立");};
            u.状态改变("空手攻击");c.target=target;
        }
        if(ticks==70)for(i=0;i<combos.length;i++){
            c=combos[i];u=c.actor;var dx:Number=Math.abs(c.target._x-u._x);
            trace("[BLADEBOT_COMBO_RESULT] case="+i+" x="+u._x+" targetX="+c.target._x+" dx="+dx+" impacts="+c.record.impacts+" beams="+c.record.comboShots+" beamHits="+c.record.laserHits+" combo="+u.bladebotComboCount);
            check(c.record.impacts>=1,"actual heavy geometry contacts target "+i);
            if(c.immune){check(dx<250 && c.record.comboShots==0,"immune target not forcibly displaced or laser-chained");}
            else {
                check(dx>=250 && dx<=600,"production knockback enters beam range "+i+" dx="+dx);
                check(u.bladebotComboCount==1 && c.record.comboShots==1 && c.record.laserHits==1,"real knockback then one actual wave contact "+i);
            }
            u.bladebotCancelAttack();u.攻击目标="无";c.target.removeMovieClip();u.removeMovieClip();
        }
    }
    private static function tick():Void {
        if(finished)return;ticks++;
        if(!ready){if(ticks>300){check(false,"load timeout");finish();}return;}
        comboTick();
        if(ticks==3) {
            for(var s:Number=0;s<probes.length;s++) {
                var pr:Object=probes[s];pr.actor.方向改变(pr.side==0?"右":"左");pr.actor.状态改变(pr.state);
            }
            for(var i:Number=0;i<cases.length;i++) {
                var c:Object=cases[i],u:MovieClip=c.actor;u.方向改变(c.side==0?"右":"左");
                var target:MovieClip=library.createEmptyMovieClip("bladebotTarget"+i,library.getNextHighestDepth());
                target.hp=1000;target._x=u._x+(c.side==0?230:-230);target.Z轴坐标=target._y=u.Z轴坐标;
                target.createEmptyMovieClip("area",1);u.攻击目标=target._name;
                if(c.move=="cleave" || c.move=="interrupt" || c.move=="dead")u.状态改变("空手攻击");
                else if(c.move=="sweep" || c.move=="interruptSweep" || c.move=="deadSweep")u.状态改变("近战");
                else if(c.move=="beam" || c.move=="interruptBeam" || c.move=="deadBeam")u.状态改变("激光束");
                else if(c.move.substr(0,3)=="hit"){u.状态改变("被击");u.man.gotoAndPlay("a"+c.move.substr(3));}
                else if(c.move=="down")u.状态改变("倒地");else if(c.move=="knockdown")u.状态改变("击倒");
                else if(c.move=="death"){u.hp=0;u.状态改变("血腥死");}
            }
        }
        if(ticks==5) {
            for(var k:Number=0;k<probes.length;k++) {
                var p:Object=probes[k];
                if(p.state=="消失") {check(p.actor.man==null && p.actor.bladebotShadow==null,"disappeared body and shadow");continue;}
                check(p.actor.man._width>0,"state has native body "+p.state);shadowCheck(p.actor,p.state+" "+p.side);
            }
            var standing:MovieClip=probes[0].actor;standing.man.gotoAndStop(1);render(standing,"stand");
            var dying:MovieClip=cases[6].actor;var df:Number=dying.man._currentframe;dying.man.gotoAndStop(1);
            var a:Object=standing.man.getBounds(library),b:Object=dying.man.getBounds(library);
            check(Math.abs((a.yMax-a.yMin)-(b.yMax-b.yMin))<0.25,"death initial body height");
            check(Math.abs(a.yMax-b.yMax)<0.25,"death initial ground");
            check(Math.abs(a.xMin-b.xMin)<0.25 && Math.abs(a.xMax-b.xMax)<0.25,"death initial horizontal placement");
            trace("[BLADEBOT_DEATH_SCALE] standing="+(a.yMax-a.yMin)+" death="+(b.yMax-b.yMin)+" groundDelta="+(b.yMax-a.yMax));
            render(dying,"death-start");dying.man.gotoAndStop(df);standing.man.play();decisions();
        }
        if(ticks==9) {
            for(var j:Number=0;j<cases.length;j++) {
                var q:Object=cases[j];
                if(q.move=="interrupt" || q.move=="interruptSweep" || q.move=="interruptBeam"){q.actor.状态改变("被击");q.actor.man.gotoAndPlay("a0");}
                else if(q.move=="dead" || q.move=="deadSweep" || q.move=="deadBeam")q.actor.hp=0;
                else if(q.move=="knockdown"){q.actor.浮空=false;q.actor.状态改变("倒地");}
            }
        }
        if(ticks==11){
            var beamActor:MovieClip=cases[11].actor;beamActor.硬直中=true;beamActor.fixtureFrozen=beamActor.man._currentframe;
        }
        if(ticks==14){
            beamActor=cases[11].actor;check(beamActor.man._currentframe==beamActor.fixtureFrozen,"beam hitstop freezes actual timeline");beamActor.硬直中=false;
        }
        if(ticks==16 || ticks==42 || ticks==48) {
            for(var r:Number=0;r<cases.length;r++) {
                var e:Object=cases[r];if(e.move=="cleave" || e.move=="sweep") {
                    var guarded:Boolean=ticks==16 || (ticks==42 && e.move=="sweep");
                    check(e.actor.刚体===guarded && e.actor.免疫击退===guarded,"bounded rigidity "+e.move+" "+e.side+" "+ticks);
                }
            }
        }
        if(ticks==23){render(cases[0].actor,"cleave-impact");render(cases[1].actor,"sweep-front");}
        if(ticks==26)render(cases[1].actor,"sweep-back");
        if(ticks==42)render(cases[6].actor,"death-fragments");
        if(ticks==54)render(cases[6].actor,"death-late");
        if(ticks==100) {
            for(var n:Number=0;n<cases.length;n++) {
                var entry:Object=cases[n],rec:Object=entry.record;var attack:Boolean=entry.move=="cleave" || entry.move=="sweep" || entry.move=="beam";
                var expected:Number=entry.move=="cleave"?2:entry.move=="sweep"?6:entry.move=="beam"?1:0;
                check(rec.shots==expected,"exact melee emissions "+entry.move+" "+entry.side+" got="+rec.shots);
                check(rec.powerOk && rec.contractOk && rec.areaOk,"real area and damage contract "+n);
                if(attack) {
                    check(rec.done==1,"attack completes once "+n);
                    check(rec.front==(entry.move=="cleave"?2:entry.move=="beam"?1:3) && rec.back==(entry.move=="sweep"?3:0),"front/back mirrored areas "+n);
                    check(entry.actor.bladebotAttackOwner==null && entry.actor.刚体===false && entry.actor.免疫击退===false,"attack ownership released "+n);
                    if(entry.move=="cleave")check(rec.moves==6,"bounded advance movements "+n+" got="+rec.moves);
                } else if(entry.move=="death" || entry.move=="dead" || entry.move=="deadSweep" || entry.move=="deadBeam") {
                    check(rec.removed && rec.deathChecks==1,"death settles once "+n);
                } else {
                    check(rec.done==1,"hit/down recovery "+n+" done="+rec.done);
                    if(entry.move=="knockdown")check(rec.physics==1,"airborne physics delegated once "+n);
                }
            }
            check(fxCount==20,"death presentation once per entered death clip, got="+fxCount);
            var required:Array=["stand","death-start","death-fragments","death-late","cleave-impact","sweep-front","sweep-back","airborne-shadow","beam-right","beam-left"];
            for(var h:Number=0;h<required.length;h++)check(images[required[h]]===true,"capture exists "+required[h]);
            finish();
        }
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        check(Cf6RobotCombatTest.finish(),"real death burst settlement");
        if(loader!=null)loader.removeListener(listener);
        trace("Cf6BladebotAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases");
        library.removeMovieClip();driver.removeMovieClip();_root.cf6BladebotAssetComplete();
    }
}
