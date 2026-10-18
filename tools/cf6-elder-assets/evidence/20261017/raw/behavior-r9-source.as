import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DeathEventComponent;
import org.flashNight.arki.component.Damage.*;

/** Published SWF behavior under isolated damage / template fixtures; no save access. */
class org.flashNight.arki.unit.Action.Melee.Cf6ElderAssetTest {
    private static var nativeKnockback:Function;
    private static var library:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var passed:Number,failed:Number,ticks:Number,fxCount:Number;
    private static var ready:Boolean,finished:Boolean;
    private static var cases:Array,probes:Array,phases:Array;
    private static var links:Array=["敌人-CF6老头人形","敌人-CF6老头机器人"];
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6ElderAssetTest: "+label);}
    }
    private static function record():Object {
        return {shots:0,frames:[],moves:0,done:0,kills:0,deathChecks:0,removed:false,
            physics:0,powerOk:true,areaOk:true,contractOk:true,frontOk:true};
    }
    public static function runAllTests():Void {
        passed=failed=ticks=fxCount=0;ready=finished=false;cases=[];probes=[];phases=[];
        library=_root.createEmptyMovieClip("__elderLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__elderTestDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;_root.暂停=false;
        _root.控制目标="__none";_root.控制目标全自动=false;_root.是否阴影=true;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};
        _root.效果=function(name:String):Void {Cf6ElderAssetTest.fxCount++;};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        nativeKnockback=_root.敌人函数.被击移动;
        check(typeof nativeKnockback=="function","exact production knockback bound for phase drift regression");
        _root.敌人函数={配置音效:function():Void {},行走:function():Void {this.fixtureManualWalk=true;},
            标准击杀:function(u:MovieClip):Void {
                u.fixtureRecord.kills++;u.状态改变("血腥死");u._killed=true;DeathEventComponent.onDeath(u);
            }};
        _root.子弹属性初始化=function(point:MovieClip,kind:String,u:MovieClip):Object {return {子弹种类:kind,霰弹值:1,发射者:u._name};};
        _root.子弹区域shoot传递=function(data:Object):Void {Cf6ElderAssetTest.capture(data);};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.空手攻击力=100;this.等级=40;
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
                this.fixtureRecord.done++;this.fixtureRecord.lastRecoveryFrame=this.man._currentframe;this.攻击目标="无";this.状态改变(this.hp>0?"空手站立":"血腥死");
            };
            this.移动钝感硬直=function():Void {};
            this.击飞浮空=function():Void {this.fixtureRecord.physics++;this.浮空=true;};
            this.击飞倒地=function():Void {this.fixtureRecord.physics++;this.倒地=true;};
            this.死亡检测=function(options:Object):Void {
                this.fixtureRecord.deathChecks++;this.fixtureRecord.deathOptions=options;
                if(this.hp<=0){this.fixtureRecord.removed=true;this.removeMovieClip();}
            };
            this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {Cf6ElderAssetTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6ElderAssetTest.check(false,"load "+error);Cf6ElderAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Codex老头素材.swf",library),"load published SWF");
        driver.onEnterFrame=function():Void {Cf6ElderAssetTest.tick();};
    }

    private static function loaded(mc:MovieClip):Void {
        mc.stop();mc._visible=false;
        var moves:Array=[["burst","stab","hit0","hit1","fall","death","interrupt","dead","knockdown"],
                         ["beam","kicks","slam","hit0","hit1","death","interrupt","dead"]];
        for(var form:Number=0;form<2;form++)for(var side:Number=0;side<2;side++)for(var m:Number=0;m<moves[form].length;m++){
            var rec:Object=record();
            var u:MovieClip=library.attachMovie(links[form],"elderCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:rec,老头变身:false});
            check(u!=null,"attach "+form+" "+moves[form][m]+" "+side);
            cases.push({actor:u,form:form,side:side,move:moves[form][m],record:rec});
        }
        createPhases();ready=true;ticks=0;
    }
    private static function createPhases():Void {
        var modes:Array=["ready","ready","ready","ready","ready","ready","empty","timeout","foreign","collision","wrong-token","wrong-context","ready-dead"];
        for(var i:Number=0;i<modes.length;i++){
            var rec:Object=record();rec.spawnCalls=0;
            var u:MovieClip=library.attachMovie(links[0],"phaseCase"+i,library.getNextHighestDepth(),{fixtureRecord:rec});
            phases.push({actor:u,record:rec,mode:modes[i],level:[30,60,99][i%3],side:i%2});
        }
        _root.加载游戏世界人物=function(kind:String,name:String,depth:Number,params:Object):MovieClip {
            var parent:MovieClip=Cf6ElderAssetTest.library[name.substr(0,name.indexOf("__elderbot"))];
            var rec:Object=parent.fixtureRecord;rec.spawnCalls++;rec.params=params;rec.kind=kind;
            Cf6ElderAssetTest.check(parent.man._currentframe==93,"spawn on authored local transition end");
            if(parent.fixtureMode=="empty")return null;
            var world:MovieClip=parent.fixtureMode=="foreign"?_root:Cf6ElderAssetTest.library;
            var child:MovieClip=world.createEmptyMovieClip(name,depth);
            for(var key:String in params)child[key]=params[key];
            child.兵种=kind;child.hp=child.hp满血值=9999;child.mp=333;child.version=7;
            if(parent.fixtureMode=="ready-dead")child.hp=0;
            if(parent.fixtureMode!="timeout")child.__unitInitializedVersion=7;
            if(parent.fixtureMode=="wrong-token")child.elderSpawnIdentity={};
            if(parent.fixtureMode=="wrong-context")child.等级++;
            child.方向改变=function(direction:String):Void {this.方向=direction;};
            rec.child=child;return child;
        };
    }
    private static function phaseTick():Void {
        if(ticks==3)for(var i:Number=0;i<phases.length;i++){
            var c:Object=phases[i],u:MovieClip=c.actor;
            check(u.老头变身===true,"human defaults to sequential phase "+i);
            nativeKnockback.call(u,"右",24,3);
            u.等级=c.level;u.是否为敌人=c.side==0;u.方向改变(c.side==0?"右":"左");
            u.名字="旧人形";u.产生源="phaseSource";u.hp=0;u.mp=42;u.hp满血值=17;u.oldBuff="not-transfer";
            u.fixtureMode=c.mode;
            if(c.mode=="collision")library.createEmptyMovieClip(u._name+"__elderbot",library.getNextHighestDepth());
            u.状态改变("血腥死");u._killed=true;DeathEventComponent.onDeath(u);
            // Flash mounts a newly selected body after this immediate callback returns.
        }
        if(ticks==5)for(i=0;i<phases.length;i++){
            u=phases[i].actor;
            check(u.elderDriver==null && u.man.elderBodyDriver!=null && u.man._currentframe>1,"actual death cleanup preserves running phase body "+i);
            check(u._x==200 && u.onEnterFrame==undefined,"phase cancels actual prior knockback without drift "+i);
            shadowCheck(u,"phase "+i);
            phases[i].pausedFrame=u.man._currentframe;
        }
        if(ticks==10)for(i=0;i<phases.length;i++)check(phases[i].actor.man._currentframe==phases[i].pausedFrame,"phase pause "+i);
        if(ticks==38)for(i=0;i<phases.length;i++){
            u=phases[i].actor;var before:Number=u.man._currentframe;
            u.状态改变("血腥死");u.状态改变("被击");DeathEventComponent.onDeath(u);
            check(u.状态=="变身" && u.man._currentframe==before,"duplicate death and hit preserve phase "+i);
        }
        if(ticks==160)for(i=0;i<phases.length;i++){
            c=phases[i];u=c.actor;var rec:Object=c.record;
            check(rec.spawnCalls==(c.mode=="collision"?0:1),"at most one spawn "+i);
            if(c.mode=="ready" || c.mode=="ready-dead"){
                check(rec.removed && rec.deathChecks==1,"source retires once "+i);
                check(rec.deathOptions.noCount===true && rec.deathOptions.noCorpse===true,"source count retained for successor "+i);
                check(rec.child.等级==c.level && rec.child.是否为敌人===(c.side==0),"level and faction inherited "+i);
                check(rec.child.方向==(c.side==0?"右":"左") && rec.child._visible,"facing and reveal after init "+i);
                check(rec.child.hp==(c.mode=="ready-dead"?0:9999) && rec.child.mp==333 && rec.child.oldBuff==undefined,"fresh successor combat values "+i);
                check(rec.params.hp==undefined && rec.params.mp==undefined && rec.params.空手攻击力==undefined,"old attributes never passed "+i);
                check(rec.kind==links[1] && rec.params.名字=="老头机器人" && rec.params.身高==190
                    && rec.params.产生源=="phaseSource" && rec.params._x==200 && rec.params._y==200,"canonical successor context "+i);
            }else{
                check(!rec.removed && rec.deathChecks==0,"failed handoff retains source count "+i);
                check(u.elderTransform.error!=undefined && !u.elderTransform.active,"failed handoff explicit "+i);
                u.elderSpawnRobot(u.man);u.elderTransformTick(u.man);
                check(rec.spawnCalls==(c.mode=="collision"?0:1),"unknown spawn never replayed "+i);
            }
            if(rec.child!=null)rec.child.removeMovieClip();
        }
    }


    private static function capture(data:Object):Void {
        var u:MovieClip=library[data.发射者],rec:Object=u.fixtureRecord;if(rec==undefined)return;
        var action:String=u.elderAttackOwner.action,frame:Number=u.man._currentframe;
        rec.shots++;rec.frames.push(frame);
        rec.powerOk=rec.powerOk && data.子弹威力==100;
        rec.contractOk=rec.contractOk && data.霰弹值==1 && data.Z轴攻击范围==30 && data.shootZ==u.Z轴坐标
            && data.百分比伤害==undefined && data.伤害类型==(action=="beam"?"魔法":"物理")
            && (action=="beam"?data.魔法伤害属性=="波":data.魔法伤害属性==undefined);
        if(action=="burst"){
            rec.areaOk=rec.areaOk && data.子弹种类=="普通子弹" && data.子弹速度==30
                && data.区域定位area==undefined && data.shootY<u.Z轴坐标-90;
        }else{
            var bounds:Object=data.区域定位area.getBounds(library);
            rec.areaOk=rec.areaOk && data.子弹种类=="近战子弹" && data.子弹速度==0
                && bounds.xMax>bounds.xMin && bounds.yMax>bounds.yMin;
            if(action=="beam")rec.areaOk=rec.areaOk && Math.abs(bounds.xMax-bounds.xMin-461.05)<0.3;
        }
        rec.frontOk=rec.frontOk && (data.shootX-u._x)*(u.方向=="右"?1:-1)>0;
        var before:Number=rec.shots;u.elderStrike(u.man,u.man.攻击点);
        check(rec.shots==before,"duplicate contact callback rejected "+action+" "+frame);
    }






    private static function shadowCheck(u:MovieClip,label:String):Void {
        var shadow:MovieClip=u.man.elderShadow;
        check(shadow!=null && shadow._visible,"body owns visible shadow "+label);
        var point:Object={x:0,y:0};shadow.localToGlobal(point);library.globalToLocal(point);
        if(Math.abs(point.x-u._x)>=.2 || Math.abs(point.y-u.Z轴坐标)>=.2)trace("[ELDER_SHADOW_DIAG] "+label+" x="+point.x+" y="+point.y+" unitX="+u._x+" z="+u.Z轴坐标+" state="+u.状态+" frame="+u.man._currentframe);
        check(Math.abs(point.x-u._x)<.2 && Math.abs(point.y-u.Z轴坐标)<.2,"shadow follows world ground "+label);
        check(library.shadow==undefined && u.shadow==undefined,"no shared shadow registration "+label);
    }
    private static function decisions():Void {
        var h:MovieClip=cases[0].actor,r:MovieClip=cases[18].actor;
        h.elderClock=r.elderClock=100;h.elderReadyAt=r.elderReadyAt=0;
        check(h.elderChooseAttack(120,0,0)=="stab","human close stab");
        check(h.elderChooseAttack(400,0,0)=="burst","human ranged burst");
        check(h.elderChooseAttack(501,0,0)=="none","human range bound");
        check(r.elderChooseAttack(120,0,0)=="slam","robot close slam");
        r.elderNextSlam=101;check(r.elderChooseAttack(120,0,0)=="kicks","robot kicks while slam cooling");
        check(r.elderChooseAttack(500,0,0)=="beam","robot beam range");
        check(r.elderChooseAttack(551,0,0)=="none","robot range bound");
        check(r.elderChooseAttack(100,31,0)=="none","lane mismatch");
        check(r.elderChooseAttack(100,0,141)=="none","high target rejected");
        check(r.elderChooseAttack(Number("bad"),0,0)=="none","invalid distance rejected");
        r.elderReadyAt=101;check(r.elderChooseAttack(100,0,0)=="none","reaction respected");r.elderReadyAt=0;
        var target:MovieClip=library.createEmptyMovieClip("decisionTarget",library.getNextHighestDepth());
        target.hp=1000;target._x=900;target._y=target.Z轴坐标=250;target.createEmptyMovieClip("area",1);
        r.攻击目标=target._name;r.elderUpdateMovement();check(r.右行 && r.下行,"move toward target and lane");
        r.行走();check(r._x>200 && r.Z轴坐标>200,"actual movement consumer");
        target._x=r._x+420;target.Z轴坐标=r.Z轴坐标+8;r.elderUpdateMovement();
        check(!r.右行 && !r.下行,"movement hysteresis stops");
        _root.控制目标=r._name;r.行走();check(r.fixtureManualWalk===true,"manual input delegates");_root.控制目标="__none";
        r.状态="空手攻击";r.elderBeginAttack(r.man,"beam");var old:Object=r.man.elderToken;
        r.elderBeginAttack(r.man,"beam");var token:Object=r.man.elderToken;r.man.elderToken=old;
        check(!r.elderCanAct(r.man),"old body token rejected");r.man.elderToken=token;
        check(r.elderCanAct(r.man),"current token accepted");
        check(r.免疫击退===true,"robot beam braces during charge");
        r.man.gotoAndStop(12);target._x=r._x-400;target.Z轴坐标=r.Z轴坐标+20;
        var trackX:Number=r._x,trackZ:Number=r.Z轴坐标;
        r.elderTrackBeam(r.man);
        check(r.方向=="左" && r._x==trackX && r.Z轴坐标==trackZ+3,"beam charge turns and moves at most three depth pixels");
        trackZ=r.Z轴坐标;_root.暂停=true;r.elderTrackBeam(r.man);_root.暂停=false;
        check(r.Z轴坐标==trackZ,"paused beam charge does not move");
        var targetToken:Object=target.__elderActionIdentity;target.__elderActionIdentity={};r.elderTrackBeam(r.man);
        check(r.Z轴坐标==trackZ,"replaced target cannot redirect charge");target.__elderActionIdentity=targetToken;
        r.man.gotoAndStop(23);target._x=r._x+400;r.elderTrackBeam(r.man);
        check(r.方向=="左" && r.Z轴坐标==trackZ,"last six windup frames lock direction and lane");
        r.man.gotoAndStop(1);
        r.硬直中=true;check(!r.elderCanAct(r.man),"hitstop blocks contact");r.硬直中=false;
        r.elderCancelAttack();check(!r.elderCanAct(r.man),"cancel invalidates contact");
        check(!r.刚体 && !r.免疫击退,"cancel releases bounded robot rigidity and beam brace");
        r.刚体=true;r.状态="空手攻击";r.elderBeginAttack(r.man,"beam");r.elderCancelAttack();
        check(r.刚体===true,"pre-existing external rigidity is preserved");r.刚体=false;
        r.免疫击退=true;r.状态="空手攻击";r.elderBeginAttack(r.man,"beam");r.elderCancelAttack();
        check(r.免疫击退===true,"pre-existing external knockback immunity is preserved");r.免疫击退=false;
        target.魔法抗性={波:90};check(r.elderWantsClose(target),"high wave resistance prefers physical contact");
        check(r.elderChooseAttack(400,0,0,true)=="none","high resistance does not waste distant beam");
        target.魔法抗性.波=0;check(!r.elderWantsClose(target),"zero wave resistance retains ranged beam");
        target.魔法抗性.波=Number("bad");check(!r.elderWantsClose(target),"invalid resistance does not force melee");
        r.状态="空手站立";r.攻击目标="无";target.removeMovieClip();
        r.浮空=r.倒地=true;r.垂直速度=-6;r.elderTick();
        check(!r.浮空 && !r.倒地 && r.垂直速度==0,"robot stays grounded");
        h.浮空=true;h.elderTick();check(h.浮空===true,"human keeps standard airborne behavior");h.浮空=false;
        _root.是否阴影=false;h.man.elderShadow.updateElderShadow();check(!h.man.elderShadow._visible,"shadow option off");
        _root.是否阴影=true;h._y=130;h._rotation=20;h._xscale=-150;h._yscale=150;
        h.man.elderShadow.updateElderShadow();shadowCheck(h,"airborne mirrored rotated");
        h._y=h.Z轴坐标;h._rotation=0;h._xscale=h._yscale=100;h.man.elderShadow.updateElderShadow();
        var handler:UniversalDamageHandle=UniversalDamageHandle.getInstance();
        var foe:Object={防御力:2000,等级:60,魔法抗性:{波:0}};var damage:DamageResult=DamageResult.getIMPACT();
        handler.handleBulletDamage({伤害类型:"魔法",魔法伤害属性:"波",破坏力:100},null,foe,null,damage);
        check(foe.损伤值==100,"real wave handler respects EXUSIAI zero resistance");
    }


    private static function tick():Void {
        if(finished)return;ticks++;
        if(!ready){if(ticks>300){check(false,"load timeout");finish();}return;}
        phaseTick();
        if(ticks==3)for(var i:Number=0;i<cases.length;i++){
            var c:Object=cases[i],u:MovieClip=c.actor;u.方向改变(c.side==0?"右":"左");
            check(u.老头变身===false,"isolated combat cases disable phase "+i);
            if(c.move=="death"){u.hp=0;u.elderTick();continue;}
            var action:String=c.move=="interrupt" || c.move=="dead"?(c.form==0?"burst":"beam"):c.move;
            var state:String=u.elderActions[action].state;
            if(state==undefined)state=c.move=="fall"?"倒地":c.move=="knockdown"?"击倒":"被击";
            u.状态改变(state);
        }
        if(ticks==7)for(i=0;i<cases.length;i++)shadowCheck(cases[i].actor,"case "+i);
        if(ticks==16 || ticks==80)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.form==1 && (c.move=="beam" || c.move=="kicks" || c.move=="slam"))
                check(c.actor.刚体===(ticks==16),"bounded robot attack rigidity "+c.move+" "+c.side+" at "+ticks);
                check(c.actor.免疫击退===(c.move=="beam" && ticks==16),"only robot beam has a bounded brace "+c.move+" "+c.side+" at "+ticks);
        }
        if(ticks==16)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.move=="knockdown"){
                check(c.record.physics==1 && c.actor.浮空===true,"human airborne delegates once "+i);
                c.actor.浮空=false;c.actor.状态改变("倒地");
            }
        }
        if(ticks==4)for(i=0;i<cases.length;i++){
            c=cases[i];u=c.actor;
            if(c.move=="hit0")u.man.gotoAndStop("a0");
            if(c.move=="hit1")u.man.gotoAndStop("a1");
            if(c.move=="interrupt")u.状态改变("被击");
            if(c.move=="dead")u.hp=0;
        }
        if(ticks==5){
            _root.暂停=true;
            for(i=0;i<cases.length;i++){c=cases[i];c.pausedFrame=c.actor.man._currentframe;c.pausedClock=c.actor.elderClock;c.pausedShots=c.record.shots;}
        }
        if(ticks==10){
            for(i=0;i<cases.length;i++){
                c=cases[i];check(c.actor.man._currentframe==c.pausedFrame,"pause body "+i);
                check(c.actor.elderClock==c.pausedClock,"pause clock "+i);check(c.record.shots==c.pausedShots,"pause damage "+i);
            }
            _root.暂停=false;
        }
        if(ticks==20)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.move=="death" || c.move=="dead")check(c.actor.man.elderBodyDriver!=null && c.actor.man._currentframe>1,"body driver survives actual death cleanup "+i);
        }
        if(ticks==160){
            decisions();
            var expected:Object={burst:"13,21,29,37",stab:"7",beam:"29",kicks:"9,26",slam:"37"};
            for(i=0;i<cases.length;i++){
                c=cases[i];var rec:Object=c.record;var dead:Boolean=c.move=="death" || c.move=="dead";
                var frames:String=expected[c.move];var count:Number=frames==undefined?0:frames.split(",").length;
                check(rec.shots==count,"contact count "+c.move+" "+c.side+" got "+rec.shots);
                if(count>0){check(rec.frames.join(",")==frames,"authored contact frames "+i);check(rec.areaOk && rec.powerOk && rec.contractOk && rec.frontOk,"damage geometry and authority "+i);}
                if(c.move=="hit0")check(rec.lastRecoveryFrame==12,"first authored hit branch ends at frame 12 "+i);
                if(c.move=="hit1")check(rec.lastRecoveryFrame==25,"second authored hit branch ends at frame 25 "+i);
                if(c.move=="fall")check(rec.physics==1,"human landing delegates once "+i);
                if(c.move=="knockdown")check(rec.physics==2 && !c.actor.倒地,"airborne then grounded recovery both delegate "+i);
                if(dead){check(rec.kills==1,"standard kill once "+i);check(rec.removed && rec.deathChecks==1 && rec.deathOptions.noCorpse===true,"death retirement once "+i);}
                else check(c.actor.状态=="空手站立" && rec.done>=1,"action recovery "+i);
            }
            finish();
        }
    }

    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        loader.removeListener(listener);library.removeMovieClip();driver.removeMovieClip();
        trace("Cf6ElderAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases; "+phases.length+" phase cases");
        _root.cf6ElderAssetComplete();
    }
}