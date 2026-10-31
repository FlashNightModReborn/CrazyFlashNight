import org.flashNight.arki.unit.Action.Melee.Cf6ElderCombatEffectsTest;
import org.flashNight.arki.spatial.animation.FragmentAnimator;
import org.flashNight.arki.unit.Action.Melee.Cf6RobotCombatTest;
import org.flashNight.arki.component.Buff.BuffManager;
import org.flashNight.arki.component.Buff.Effect.ElderBeamVulnerability;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DeathEventComponent;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.unit.UnitComponent.Status.ImpactStateHandler;

/** Published SWF behavior under isolated damage / template fixtures; no save access. */
class org.flashNight.arki.unit.Action.Melee.Cf6ElderAssetTest {
    private static var nativeKnockback:Function;
    private static var library:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var passed:Number,failed:Number,ticks:Number,fxCount:Number,muzzleChecks:Number;
    private static var ready:Boolean,finished:Boolean;
    private static var cases:Array,r8Cases:Array,probes:Array,phases:Array;
    private static var links:Array=["敌人-CF6老头人形","敌人-CF6老头机器人"];
    private static function check(ok:Boolean,label:String):Void {
        if(ok)passed++;else{failed++;trace("[TEST_FAIL] Cf6ElderAssetTest: "+label);}
    }
    private static function record():Object {
        return {shots:0,heavyShots:0,frames:[],moves:0,done:0,kills:0,deathChecks:0,removed:false,
            physics:0,powerOk:true,areaOk:true,contractOk:true,frontOk:true,slamAntiairOk:true,fallingShellOk:true};
    }
    public static function runAllTests():Void {
        passed=failed=ticks=fxCount=muzzleChecks=0;ready=finished=false;cases=[];r8Cases=[];probes=[];phases=[];
        Cf6ElderCombatEffectsTest.reset();
        Cf6RobotCombatTest.reset("elder");
        library=_root.createEmptyMovieClip("__elderLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__elderTestDriver",_root.getNextHighestDepth());
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
                this._y=this.Z轴坐标;if(this.fixtureRecord!=null)this.fixtureRecord.moves++;
            };
            this.方向改变=function(dir:String):Void {this.方向=dir;this._xscale=dir=="左"?-100:100;};
            this.动画完毕=function():Void {
                this.__doneCount=(this.__doneCount|0)+1;this.__lastRecoveryFrame=this.man._currentframe;
                if(this.fixtureRecord!=null){this.fixtureRecord.done++;this.fixtureRecord.lastRecoveryFrame=this.man._currentframe;}
                this.攻击目标="无";this.状态改变(this.hp>0?"空手站立":"血腥死");
            };
            this.移动钝感硬直=function():Void {};
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
        listener={onLoadInit:function(mc:MovieClip):Void {Cf6ElderAssetTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6ElderAssetTest.check(false,"load "+error);Cf6ElderAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        var source:String=typeof _root.cf6ElderAssetUnderTest=="string"?_root.cf6ElderAssetUnderTest:"../flashswf/arts/new/Codex老头素材.swf";
        check(loader.loadClip(source,library),"load published SWF");
        driver.onEnterFrame=function():Void {
            try{Cf6ElderAssetTest.tick();}
            catch(error){Cf6ElderAssetTest.check(false,"native fixture exception "+error);Cf6ElderAssetTest.finish();}
        };
    }

    private static function loaded(mc:MovieClip):Void {
        mc.stop();mc._visible=false;
        var moves:Array=[["burst","stab","hit0","hit1","fall","death","interrupt","dead","knockdown"],
                         ["beam","kicks","slam","hit0","hit1","death","interrupt","dead","heavyBeam","unmarkedHeavy","expiredHeavy","reusedHeavy","midExpiredHeavy","slamHeavy"]];
        for(var form:Number=0;form<2;form++)for(var side:Number=0;side<2;side++)for(var m:Number=0;m<moves[form].length;m++){
            var rec:Object=record();
            var u:MovieClip=library.attachMovie(links[form],"elderCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:rec,老头变身:false});
            check(u!=null,"attach "+form+" "+moves[form][m]+" "+side);
            cases.push({actor:u,form:form,side:side,move:moves[form][m],record:rec});
        }
        for(var r8Side:Number=0;r8Side<2;r8Side++){
            var r8Rec:Object=record();
            var r8u:MovieClip=library.attachMovie(links[0],"elderR8Case"+r8Cases.length,library.getNextHighestDepth(),{fixtureRecord:r8Rec,老头变身:false});
            check(r8u!=null,"attach r8 retreat_burst "+r8Side);
            r8Cases.push({actor:r8u,form:0,side:r8Side,move:"retreat_burst",record:r8Rec});
            var noFixRetreat:MovieClip=library.attachMovie(links[0],"elderR8Case"+r8Cases.length,library.getNextHighestDepth(),{老头变身:false});
            check(noFixRetreat!=null && noFixRetreat.fixtureRecord===undefined,"attach r8 retreat_burst_no_fixture "+r8Side);
            r8Cases.push({actor:noFixRetreat,form:0,side:r8Side,move:"retreat_burst_no_fixture",record:null});
            var noFixSlam:MovieClip=library.attachMovie(links[1],"elderR8Case"+r8Cases.length,library.getNextHighestDepth(),{老头变身:false});
            check(noFixSlam!=null && noFixSlam.fixtureRecord===undefined,"attach r8 slam_no_fixture "+r8Side);
            r8Cases.push({actor:noFixSlam,form:1,side:r8Side,move:"slam_no_fixture",record:null});
            var r8SlamMoves:Array=["slam_ruleA_shielded","slam_ruleA_broken","slam_ruleA_scaled","slam_ruleA_rotated","slam_ruleA_interrupt"];
            for(var sm:Number=0;sm<r8SlamMoves.length;sm++){
                var slamRec:Object=record();
                var slamUnit:MovieClip=library.attachMovie(links[1],"elderR8Case"+r8Cases.length,library.getNextHighestDepth(),{fixtureRecord:slamRec,老头变身:false});
                slamUnit.shield=AdaptiveShield.createDormant("r8-"+r8SlamMoves[sm]+"-"+r8Side);
                slamUnit.shield.setOwner(slamUnit);
                check(slamUnit!=null,"attach r8 "+r8SlamMoves[sm]+" "+r8Side);
                slamRec.muzzleVariant=r8SlamMoves[sm];
                r8Cases.push({actor:slamUnit,form:1,side:r8Side,move:sm>1?"slam_ruleA_shielded":r8SlamMoves[sm],record:slamRec});
            }
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


    private static function captureMuzzleImage(u:MovieClip):Void {
        var bitmap:flash.display.BitmapData=new flash.display.BitmapData(900,1000,false,0x18212d);
        bitmap.draw(u,new flash.geom.Matrix(1,0,0,1,450,850));
        trace("[ELDER_MUZZLE_IMAGE_BEGIN] 900 1000 frame="+u.man._currentframe);
        for(var row:Number=0;row<1000;row++){
            var parts:Array=[],last:Number=bitmap.getPixel(0,row),count:Number=1;
            for(var col:Number=1;col<900;col++){
                var value:Number=bitmap.getPixel(col,row);
                if(value==last)count++;else{parts.push(last.toString(16)+":"+count);last=value;count=1;}
            }
            parts.push(last.toString(16)+":"+count);
            trace("[ELDER_MUZZLE_IMAGE_ROW] "+row+" "+parts.join(","));
        }
        trace("[ELDER_MUZZLE_IMAGE_END]");bitmap.dispose();
    }
    private static function capture(data:Object):Void {
        var u:MovieClip=library[data.发射者],rec:Object=u.fixtureRecord;if(rec==undefined)return;
        if(data.cf6DeathBurst===true){
            rec.deathBursts=(rec.deathBursts|0)+1;check(rec.deathBursts==1,"one death burst "+u._name);
            if(rec.deathBursts==1)Cf6RobotCombatTest.captureDeath(data,u);return;
        }
        if(data.cf6ElderSlamAntiair===true){
            muzzleChecks++;
            rec.slamAntiairs=(rec.slamAntiairs|0)+1;
            var aaBounds:Object=data.区域定位area.getBounds(library);
            var marker:MovieClip=u.man.elderSlamMuzzle;
            check(marker._parent===u.man,"native cannon owns a muzzle anchor "+u.方向);
            var muzzle:Object={x:0,y:0},axis:Object={x:100,y:0};
            marker.localToGlobal(muzzle);marker.localToGlobal(axis);library.globalToLocal(muzzle);library.globalToLocal(axis);
            check(Math.abs(data.shootX-muzzle.x)<0.2 && Math.abs(data.shootY-muzzle.y)<0.2,"upward emission follows cannon anchor "+u.方向);
            check(Math.abs(aaBounds.yMax-data.shootY)<0.3 && Math.abs((aaBounds.xMin+aaBounds.xMax)/2-data.shootX)<0.3,"anti-air area begins at the actual muzzle "+u.方向);
            var fx:MovieClip=u["cf6ElderAaFx_"+(900+(u.elderClock&63))];
            check(fx!=null,"upward effect is instantiated "+u.方向);
            var origin:Object={x:0,y:0},front:Object={x:0,y:-100};
            fx.localToGlobal(origin);fx.localToGlobal(front);library.globalToLocal(origin);library.globalToLocal(front);
            check(Math.abs(origin.x-muzzle.x)<0.25 && Math.abs(origin.y-muzzle.y)<0.25,"effect origin matches scaled/mirrored cannon "+u.方向);
            var ex:Number=front.x-origin.x,ey:Number=front.y-origin.y,ax:Number=axis.x-muzzle.x,ay:Number=axis.y-muzzle.y;
            var cosine:Number=(ex*ax+ey*ay)/Math.sqrt((ex*ex+ey*ey)*(ax*ax+ay*ay));
            check(cosine>0.9999,"effect points along transformed cannon axis "+u.方向);
            rec.muzzleFxName=fx._name;rec.muzzleSeen=true;
            if(_root.cf6ElderMuzzleCapture===true && rec.muzzleVariant=="slam_ruleA_shielded" && u.方向=="右")
                rec.muzzleCaptureAt=ticks+2;
            trace("[CF6_ELDER_MUZZLE] unit="+u._name+" variant="+rec.muzzleVariant+" direction="+u.方向
                +" source="+u._url+" x="+data.shootX+" y="+data.shootY+" cosine="+cosine);
            if(rec.muzzleVariant=="slam_ruleA_interrupt")rec.muzzleInterruptRequested=true;
            rec.slamAntiairOk=rec.slamAntiairOk && data.区域定位area!=null
                && data.子弹种类=="近战子弹" && data.子弹速度==0
                && data.伤害类型=="魔法" && data.魔法伤害属性=="波"
                && Math.abs(data.子弹威力-300)<0.001 && data.垂直击退速度==-6
                && Math.abs(aaBounds.xMax-aaBounds.xMin-220)<0.3
                && Math.abs(aaBounds.yMax-aaBounds.yMin-165)<0.3;
            return;
        }
        if(data.cf6FallingShell===true){
            rec.fallingShells=(rec.fallingShells|0)+1;
            var shellBounds:Object=data.区域定位area.getBounds(library);
            rec.fallingShellOk=rec.fallingShellOk && data.区域定位area!=null
                && data.子弹种类=="近战子弹" && data.子弹速度==0
                && data.伤害类型=="魔法" && data.魔法伤害属性=="波"
                && Math.abs(data.子弹威力-400)<0.001 && data.Z轴攻击范围==45
                && data.hitBehavior.type=="cf6ElderBeam"
                && Math.abs(shellBounds.xMax-shellBounds.xMin-190)<0.3
                && Math.abs(shellBounds.yMax-shellBounds.yMin-125)<0.3
                && (data.shootX-u._x)*(u.方向=="右"?1:-1)>0;
            return;
        }
        var action:String=u.elderAttackOwner.action,frame:Number=u.man._currentframe;
        rec.shots++;rec.frames.push(frame);if(action=="heavyBeam")rec.heavyShots++;
        rec.powerOk=rec.powerOk && data.子弹威力==(action=="heavyBeam"?rec.heavyShots*50:action=="slam"?1800:action=="beam"?300:100);
        if(action=="heavyBeam")check(u.刚体===true && u.免疫击退===true,"continuous beam remains braced through every pulse "+frame);
        if(u.elderForm=="robot")Cf6ElderCombatEffectsTest.capture(action,data,u);
        rec.contractOk=rec.contractOk && u.elderAttackOwner.spec.totalFrames==u.man._totalframes && data.霰弹值==1 && data.Z轴攻击范围==30 && data.shootZ==u.Z轴坐标
            && data.击倒率==(action=="stab"?1:(action=="slam"?3:10)) && data.水平击退速度==(action=="stab"?24:(action=="slam"?18:3))
            && (action=="stab"?data.吸血==35:true) && (action=="retreat_burst"?typeof data.暴击=="function":true)
            && data.百分比伤害==undefined && data.伤害类型==((action=="beam" || action=="heavyBeam")?"魔法":"物理")
            && ((action=="beam" || action=="heavyBeam")?data.魔法伤害属性=="波":data.魔法伤害属性==undefined);
        if(action=="burst" || action=="retreat_burst"){
            rec.areaOk=rec.areaOk && data.子弹种类=="穿刺子弹" && data.子弹速度==30
                && data.区域定位area==undefined && data.shootY<u.Z轴坐标-90;
        }else{
            var bounds:Object=data.区域定位area.getBounds(library);
            rec.areaOk=rec.areaOk && data.子弹种类=="近战子弹" && data.子弹速度==0
                && bounds.xMax>bounds.xMin && bounds.yMax>bounds.yMin;
            if(action=="beam" || action=="heavyBeam")rec.areaOk=rec.areaOk && Math.abs(bounds.xMax-bounds.xMin-780.83)<0.5
                && Math.abs(bounds.yMax-bounds.yMin-(action=="heavyBeam"?96:32))<0.3;
            if(action=="kicks" && rec.reachTarget!=null){
                var targetBounds:Object=rec.reachTarget.getBounds(library);
                var overlap:Boolean=bounds.xMin<targetBounds.xMax && bounds.xMax>targetBounds.xMin
                    && bounds.yMin<targetBounds.yMax && bounds.yMax>targetBounds.yMin;
                if(overlap)rec.reachOverlaps++;
                check(overlap,"authored kick contact reaches target from 190 pixels "+frame+" "+u.方向);
                check(Math.abs(rec.reachTarget._x-u._x)>=90,"kick approach does not overshoot its stop bound "+frame+" "+u.方向);
            }
        }
        rec.frontOk=rec.frontOk && (data.shootX-u._x)*(u.方向=="右"?1:-1)>0;
        if(rec.followupTarget!=null){
            var followTarget:MovieClip=rec.followupTarget;
            if(action=="slam"){
                var followBounds:Object=followTarget.area.getBounds(library);
                check(bounds.xMin<followBounds.xMax && bounds.xMax>followBounds.xMin
                    && bounds.yMin<followBounds.yMax && bounds.yMax>followBounds.yMin,"slam follow-up starts from actual overlapping geometry");
                var beforeHp:Number=followTarget.hp;
                Cf6ElderCombatEffectsTest.settleFollowup(data,u,followTarget);
                check(followTarget.hp<beforeHp && u.elderHasSlamHeavyWindow(followTarget,72),"actual emitted slam settlement opens follow-up");
            }
            check(!u.elderHasBeamMark(followTarget) && followTarget.damageTakenMultiplier==1,"unmarked follow-up never manufactures vulnerability");
        }
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
        r.elderNextBeam=r.elderNextHeavyBeam=0;
        check(h.elderChooseAttack(120,0,0)=="stab","human close stab");
        check(h.elderChooseAttack(400,0,0)=="burst","human ranged burst");
        check(h.elderSelectBurstSubmode(300,0)=="retreat_burst","human close-mid burst submode selects retreat_burst");
        check(h.elderSelectBurstSubmode(350,0)=="burst","human far burst submode selects burst");
        h.elderRewardHumanStab(null);
        check(h.elderChooseAttack(360,0,0)=="burst" && h.elderSelectBurstSubmode(360,0)=="retreat_burst","stab hit arms immediate retreat_burst combo");
        h.elderHumanComboUntil=0;
        check(h.elderChooseAttack(501,0,0)=="none","human range bound");
        check(r.elderChooseAttack(120,0,0)=="slam","robot close slam");
        r.elderNextSlam=101;check(r.elderChooseAttack(120,0,0)=="kicks","robot kicks while slam cooling");
        check(r.elderChooseAttack(190,0,0)=="kicks","robot kick approach includes 190 pixel boundary");
        check(r.elderChooseAttack(191,0,0)=="beam","outside kick approach retains ranged beam");
        check(r.elderChooseAttack(500,0,0)=="beam","robot beam range");
        r.elderNextSlam=0;r.elderNextBeam=200;
        check(r.elderChooseAttack(400,0,0)=="slam","robot mid-range selects slam bombardment while beam cooling");
        r.elderNextBeam=0;r.elderNextSlam=101;
        var rangeChecks:Number=r.elderCombatStats.decisionChecks,outsideChecks:Number=r.elderCombatStats.rangeOutsideChecks;
        check(r.elderChooseAttack(750,0,0)=="beam","robot includes the authorized 750 pixel start boundary");
        check(r.elderChooseAttack(751,0,0)=="none","robot range remains bounded beyond 750 pixels");
        check(r.elderCombatStats.decisionChecks==rangeChecks+2 && r.elderCombatStats.rangeOutsideChecks==outsideChecks+1,"range diagnostics count actual selector calls and the exceeded bound without changing selection");
        check(r.elderChooseAttack(100,31,0)=="none","lane mismatch");
        check(r.elderChooseAttack(100,0,141)=="none","high target rejected");
        check(r.elderChooseAttack(Number("bad"),0,0)=="none","invalid distance rejected");
        r.elderReadyAt=101;check(r.elderChooseAttack(100,0,0)=="none","reaction respected");r.elderReadyAt=0;
        var target:MovieClip=library.createEmptyMovieClip("decisionTarget",library.getNextHighestDepth());
        target.hp=1000;target._x=1100;target._y=target.Z轴坐标=250;target.createEmptyMovieClip("area",1);
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
        r.elderNextBeam=0;
        target.魔法抗性={波:90};check(r.elderWantsClose(target),"high wave resistance prefers physical contact");
        check(r.elderChooseAttack(400,0,0,true)=="beam","high resistance still receives vulnerability primer");
        target.魔法抗性.波=0;check(!r.elderWantsClose(target),"zero wave resistance retains ranged beam");
        target.魔法抗性.波=Number("bad");check(!r.elderWantsClose(target),"invalid resistance does not force melee");
        r.攻击目标=target._name;r.elderNextHeavyBeam=r.elderNextBeam=0;
        target.buffManager=new BuffManager(target,{});target.damageTakenMultiplier=target.ti61CrumbleTakenMultiplier=1;
        check(r.elderChooseAttack(400,0,0,false)=="beam","unmarked AI target selects primer");
        ElderBeamVulnerability.applyToTarget(target,{peak:0.25,durationFrames:180});
        check(r.elderChooseAttack(400,0,0,false)=="heavyBeam","marked AI target selects heavy beam");
        r.elderNextHeavyBeam=r.elderClock+1;
        check(r.elderChooseAttack(400,0,0,false)=="beam","heavy cooldown does not bypass primer policy");
        r.elderNextHeavyBeam=0;target.buffManager.update(109);
        check(r.elderHasBeamMark(target) && r.elderChooseAttack(400,0,0,false)=="beam","short remaining mark cannot start an incomplete channel");
        target.buffManager.update(71);
        check(r.elderChooseAttack(400,0,0,false)=="beam","expired mark removes heavy selection");
        r.状态改变("空手站立");r.攻击目标="无";target.removeMovieClip();
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
            if(c.move=="unmarkedHeavy" || c.move=="expiredHeavy" || c.move=="reusedHeavy" || c.move=="midExpiredHeavy")action="heavyBeam";
            if(c.move=="slamHeavy"){
                action="slam";
                var followTarget:MovieClip=_root.cf6MakePlayerTarget(library,"slamFollowTarget"+i,175);
                followTarget._x=u._x+(c.side==0?180:-180);followTarget.buffManager=new BuffManager(followTarget,{});followTarget.createEmptyMovieClip("man",2);
                u.攻击目标=followTarget._name;c.record.followupTarget=followTarget;
            }
            if(action=="heavyBeam"){
                var heavyTarget:MovieClip=_root.cf6MakePlayerTarget(library,"heavyTarget"+i,175);
                heavyTarget._x=u._x+(c.side==0?400:-400);heavyTarget.buffManager=new BuffManager(heavyTarget,{});
                if(c.move!="unmarkedHeavy")ElderBeamVulnerability.applyToTarget(heavyTarget,{peak:0.25,durationFrames:180});
                c.heavyTarget=heavyTarget;u.攻击目标=heavyTarget._name;
            }
            var state:String=u.elderActions[action].state;
            if(state==undefined)state=c.move=="fall"?"倒地":c.move=="knockdown"?"击倒":"被击";
            if(c.move=="kicks"){
                var target:MovieClip=library.createEmptyMovieClip("kickReachTarget"+i,library.getNextHighestDepth());
                target.hp=1000;target._x=u._x+(c.side==0?190:-190);target._y=target.Z轴坐标=u.Z轴坐标;
                target.beginFill(0);target.moveTo(-20,-100);target.lineTo(20,-100);
                target.lineTo(20,0);target.lineTo(-20,0);target.lineTo(-20,-100);target.endFill();
                u.攻击目标=target._name;c.record.reachTarget=target;c.record.reachOverlaps=0;
            }
            u.状态改变(state);
        }
        if(ticks==3)for(var r8i:Number=0;r8i<r8Cases.length;r8i++){
            var r8c:Object=r8Cases[r8i],r8u:MovieClip=r8c.actor;r8u.方向改变(r8c.side==0?"右":"左");
            if(r8c.record.muzzleVariant=="slam_ruleA_scaled"){r8u._xscale*=1.45;r8u._yscale=80;}
            if(r8c.record.muzzleVariant=="slam_ruleA_rotated"){r8u._xscale*=0.85;r8u._yscale=130;r8u._rotation=17;}
            if(r8c.move=="retreat_burst" || r8c.move=="retreat_burst_no_fixture"){
                r8u.elderPendingBurstSubmode="retreat_burst";
                r8u.状态改变("空手攻击");
            }else{
                r8u.状态改变("重击");
            }
        }
        if(ticks==4)for(r8i=0;r8i<r8Cases.length;r8i++){
            r8c=r8Cases[r8i];r8u=r8c.actor;
            if(r8c.move=="slam_ruleA_shielded" || r8c.move=="slam_ruleA_broken"){
                check(r8u.shield.getCapacity()>0,"slam windup holds active shield for Rule A "+r8i+" cap="+r8u.shield.getCapacity());
                if(r8c.move=="slam_ruleA_broken"){
                    r8u.shield.absorbDamage(10000,false,1);
                    check(r8u.shield.getCapacity()==0,"broken windup shield removes capacity "+r8i+" cap="+r8u.shield.getCapacity());
                }
            }
        }
        for(r8i=0;r8i<r8Cases.length;r8i++){
            r8c=r8Cases[r8i];r8u=r8c.actor;
            if(r8c.record.muzzleCaptureAt==ticks)captureMuzzleImage(r8u);
            if(r8c.record.muzzleInterruptRequested===true){
                r8c.record.muzzleInterruptRequested=false;r8c.record.muzzleInterrupted=true;r8c.record.muzzleInterruptAt=ticks;
                r8u.状态改变("被击");
            }
            if(r8c.record.muzzleInterrupted===true && ticks==r8c.record.muzzleInterruptAt+3)
                check(r8u[r8c.record.muzzleFxName]==null,"interrupted action cannot retain a detached muzzle effect "+r8c.side);
        }
        if(ticks==7)for(i=0;i<cases.length;i++)shadowCheck(cases[i].actor,"case "+i);
        if(ticks==18)for(i=0;i<cases.length;i++){
            c=cases[i];
            if(c.move=="expiredHeavy")c.heavyTarget.buffManager.update(180);
            if(c.move=="reusedHeavy"){
                var reusedName:String=c.heavyTarget._name;c.heavyTarget.removeMovieClip();
                c.heavyTarget=_root.cf6MakePlayerTarget(library,reusedName,175);
                c.heavyTarget.buffManager=new BuffManager(c.heavyTarget,{});
                ElderBeamVulnerability.applyToTarget(c.heavyTarget,{peak:0.25,durationFrames:180});
            }
        }
        for(i=0;i<cases.length;i++){
            c=cases[i];
            if(c.move=="slamHeavy" && c.record.done==1 && !c.record.followupStarted
                && c.actor.elderClock>=c.actor.elderReadyAt){
                u=c.actor;var followTarget:MovieClip=c.record.followupTarget;
                followTarget._x=u._x+(c.side==0?400:-400);u.攻击目标=followTarget._name;
                check(u.elderChooseAttack(400,0,0,true)=="heavyBeam","post-slam AI selects unmarked heavy beam "+c.side);
                c.record.followupStarted=true;u.状态改变(u.elderActions.heavyBeam.state);
            }
            if(c.move=="midExpiredHeavy" && c.record.shots==1 && c.expiredDuringBeam!==true){
                c.heavyTarget.buffManager.update(180);c.expiredDuringBeam=true;
            }
        }
        if(ticks==27)for(i=0;i<cases.length;i++)if(cases[i].move=="heavyBeam")
            check(cases[i].record.shots==0 && cases[i].actor.man._currentframe<35,"heavy beam cannot fire during telegraph "+i);
        if(ticks==16 || ticks==80)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.form==1 && (c.move=="beam" || c.move=="kicks" || c.move=="slam")){
                check(c.actor.刚体===(ticks==16),"bounded robot attack rigidity "+c.move+" "+c.side+" at "+ticks);
                check(c.actor.免疫击退===(c.move=="beam" && ticks==16),"only robot beam has a bounded brace "+c.move+" "+c.side+" at "+ticks);
            }
        }
        if(ticks==39)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.form==1 && c.move=="beam"){
                u=c.actor;
                check(u.man._currentframe>29 && u.man._currentframe<44 && u.刚体===true && u.免疫击退===false,
                    "beam recovery retains rigidity but releases displacement brace "+c.side);
                var beamBody:MovieClip=u.man,beamOwner:Object=u.elderAttackOwner;
                var impact:MovieClip=library.createEmptyMovieClip("beamRecoveryImpact"+i,library.getNextHighestDepth());
                impact.伤害类型="物理";impact.破坏力=60;impact.击倒率=0;
                impact.水平击退速度=6;impact.垂直击退速度=0;
                u.防御力=300;u.韧性系数=40;u.躲闪率=50;u.remainingImpactForce=0;u.被击移动=nativeKnockback;
                var impactResult:DamageResult=DamageResult.getIMPACT(),hpBefore:Number=u.hp;
                UniversalDamageHandle.getInstance().handleBulletDamage(impact,null,u,null,impactResult);
                // Fixture settlement applies the production handler's result; production actor code never writes a target's HP.
                u.hp-=u.损伤值;
                check(u.hp==hpBefore-30,"recovery rigidity does not reduce physical damage "+c.side);
                c.record.recoveryImpactX=u._x;
                ImpactStateHandler.handleImpactState(u,impact,impactResult,c.side==0?"右":"左",true);
                check(u.状态=="空手攻击" && u.man===beamBody && u.elderAttackOwner===beamOwner,
                    "production forced impact preserves the committed beam recovery "+c.side);
                check(u.speed==6 && u.减速度==0.5,"post-shot knockback remains enabled "+c.side);
                impact.removeMovieClip();
            }
        }
        if(ticks==44)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.form==1 && c.move=="beam")
                check(Math.abs(c.actor._x-c.record.recoveryImpactX)>1 && c.actor.刚体===true && c.actor.免疫击退===false,
                    "actual production knockback moves the recovering beam actor "+c.side);
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
        if(ticks==55){
            _root.暂停=true;
            for(i=0;i<cases.length;i++){
                c=cases[i];var debris:MovieClip=c.actor.man.尸体碎片;
                if(debris!=null)c.fragmentPause={x:debris.碎片1._x,y:debris.碎片1._y,frame:c.actor.man._currentframe};
            }
        }
        if(ticks==60){
            for(i=0;i<cases.length;i++){
                c=cases[i];if(c.fragmentPause!=null){
                    debris=c.actor.man.尸体碎片;
                    check(debris.碎片1._x==c.fragmentPause.x && debris.碎片1._y==c.fragmentPause.y
                        && c.actor.man._currentframe==c.fragmentPause.frame,"pause freezes physical corpse fragments "+i);
                }
            }
            _root.暂停=false;
        }
        if(ticks==20)for(i=0;i<cases.length;i++){
            c=cases[i];if(c.move=="death" || c.move=="dead")check(c.actor.man.elderBodyDriver!=null && c.actor.man._currentframe>1,"body driver survives actual death cleanup "+i);
        }
        if(ticks==220){
            decisions();
            var expected:Object={burst:"13,21,29,37",stab:"7",beam:"29",kicks:"9,26",slam:"37",heavyBeam:"35,47,59,71",midExpiredHeavy:"35",slamHeavy:"37,35,47,59,71"};
            for(i=0;i<cases.length;i++){
                c=cases[i];var rec:Object=c.record;var dead:Boolean=c.move=="death" || c.move=="dead";
                var frames:String=expected[c.move];var count:Number=frames==undefined?0:frames.split(",").length;
                check(rec.shots==count,"contact count "+c.move+" "+c.side+" got "+rec.shots);
                if(count>0){check(rec.frames.join(",")==frames,"authored contact frames "+i);check(rec.areaOk && rec.powerOk && rec.contractOk && rec.frontOk,"damage geometry and authority "+i);}
                if(c.move=="heavyBeam" || c.move=="midExpiredHeavy")check(c.actor.刚体===false && c.actor.免疫击退===false,"continuous beam releases both owned braces "+i);
                if(c.move=="slamHeavy")check(rec.followupStarted && rec.heavyShots==4 && rec.done==2 && c.actor.elderCombatStats.slamHeavyStarts==1
                    && c.actor.刚体===false && c.actor.免疫击退===false,"slam then complete unmarked four-pulse recovery "+c.side);
                if(c.move=="heavyBeam")check(c.actor.elderCombatStats.slamHeavyStarts==0,"marked starts do not count as slam-only permission "+c.side);
                if(c.move=="kicks")check(rec.reachOverlaps==2 && rec.moves>0,"both authored kicks connect after bounded approach "+i);
                if(c.move=="hit0")check(rec.lastRecoveryFrame==12,"first authored hit branch ends at frame 12 "+i);
                if(c.move=="hit1")check(rec.lastRecoveryFrame==25,"second authored hit branch ends at frame 25 "+i);
                if(c.move=="fall")check(rec.physics==1,"human landing delegates once "+i);
                if(c.move=="knockdown")check(rec.physics==2 && !c.actor.倒地,"airborne then grounded recovery both delegate "+i);
                if(dead){if(c.form==1)check(rec.stamps==1 && rec.stampLayer==2 && rec.stampSettled===true && rec.allDebrisGrounded===true && rec.debrisCount==15,"settled robot corpse stamped once "+i);check(rec.kills==1,"standard kill once "+i);check(rec.removed && rec.deathChecks==1 && (c.form==0?rec.deathOptions.noCorpse===true:rec.deathOptions.noCorpse!==true),"death retirement once "+i);}
                else check(c.actor.状态=="空手站立" && rec.done>=1,"action recovery "+i);
            }
            for(var r8k:Number=0;r8k<r8Cases.length;r8k++){
                var r8Case:Object=r8Cases[r8k],r8Rec:Object=r8Case.record;
                if(r8Case.move=="retreat_burst"){
                    check(r8Rec.shots==4,"retreat_burst contact count "+r8Case.side+" got "+r8Rec.shots);
                    check(r8Rec.frames.join(",")=="63,65,68,70","retreat_burst authored frames "+r8Case.side);
                    check(r8Rec.moves>0,"retreat_burst backward displacement "+r8Case.side);
                    check(r8Rec.areaOk && r8Rec.powerOk && r8Rec.contractOk && r8Rec.frontOk,"retreat_burst contract "+r8Case.side);
                }else if(r8Case.move=="slam_ruleA_shielded" && r8Rec.muzzleInterrupted===true){
                    check(r8Rec.slamAntiairs==1 && r8Rec.shots==0 && r8Rec.muzzleSeen===true,"interrupt leaves the launched upward emission once and cancels the later hammer "+r8Case.side);
                    check(r8Case.actor[r8Rec.muzzleFxName]==null,"interrupted muzzle effect remains retired "+r8Case.side);
                }else if(r8Case.move=="slam_ruleA_shielded"){
                    check(r8Rec.shots==1 && r8Rec.frames.join(",")=="37","Rule A shielded slam primary contact "+r8Case.side+" shots="+r8Rec.shots+" frames="+r8Rec.frames.join(","));
                    check(r8Rec.slamAntiairs==1 && r8Rec.slamAntiairOk===true,"Rule A shielded slam emits upward anti-air wave hit "+r8Case.side+" aa="+r8Rec.slamAntiairs+" ok="+r8Rec.slamAntiairOk);
                    check(r8Rec.fallingShells==2 && r8Rec.fallingShellOk===true,"Rule A shielded slam spawns 2 delayed falling beam shells "+r8Case.side+" shells="+r8Rec.fallingShells+" ok="+r8Rec.fallingShellOk);
                    check(r8Rec.areaOk && r8Rec.powerOk && r8Rec.contractOk && r8Rec.frontOk,"Rule A shielded slam primary contract "+r8Case.side);
                }else if(r8Case.move=="slam_ruleA_broken"){
                    check(r8Rec.shots==1 && r8Rec.frames.join(",")=="37","Rule A broken-shield slam primary contact "+r8Case.side+" shots="+r8Rec.shots+" frames="+r8Rec.frames.join(","));
                    check((r8Rec.slamAntiairs|0)==0 && (r8Rec.fallingShells|0)==0,"Rule A broken-shield slam suppresses anti-air and falling shells "+r8Case.side+" aa="+r8Rec.slamAntiairs+" shells="+r8Rec.fallingShells);
                    check(r8Rec.areaOk && r8Rec.powerOk && r8Rec.contractOk && r8Rec.frontOk,"Rule A broken-shield slam primary contract "+r8Case.side);
                }else if(r8Case.move=="retreat_burst_no_fixture"){
                    check(r8Case.actor.fixtureRecord===undefined && r8Case.actor.__lastRecoveryFrame==94 && r8Case.actor.__doneCount==1,
                        "retreat_burst without fixtureRecord plays full 94 frames "+r8Case.side+" last="+r8Case.actor.__lastRecoveryFrame);
                }else if(r8Case.move=="slam_no_fixture"){
                    check(r8Case.actor.fixtureRecord===undefined && r8Case.actor.__lastRecoveryFrame==71 && r8Case.actor.__doneCount==1,
                        "slam without fixtureRecord plays full 71 frames "+r8Case.side+" last="+r8Case.actor.__lastRecoveryFrame);
                }
                check(r8Case.actor.状态=="空手站立" && (r8Rec!=null?r8Rec.done>=1:r8Case.actor.__doneCount>=1),"r8 case recovery "+r8Case.move+" "+r8Case.side);
            }
            r8Cases[0].actor.状态改变("空手跑");
            check(r8Cases[0].actor.man._totalframes==24,"human run state mounts dedicated 24f R8 run clip");
            r8Cases[0].actor.状态改变("空手站立");
            check(Cf6ElderCombatEffectsTest.runAllTests(nativeKnockback),"actual robot combat effect suite");
            finish();
        }
    }

    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        check(FragmentAnimator.getActiveAnimationCount()==0,"all completed fragment instances released");
        check(Cf6RobotCombatTest.finish(),"real death burst settlement");
        loader.removeListener(listener);library.removeMovieClip();driver.removeMovieClip();
        check(muzzleChecks>=8,"all native muzzle geometry variants emitted");
        trace("Cf6ElderMuzzle: "+muzzleChecks+" native emissions checked");
        trace("Cf6ElderAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases; "+phases.length+" phase cases");
        _root.cf6ElderAssetComplete();
    }
}
