import flash.display.BitmapData;
import flash.geom.Matrix;
import org.flashNight.arki.unit.UnitComponent.Initializer.DisplayNameInitializer;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.DeathEventComponent;

/** Actual published vector timelines; isolated fixtures replace game state and damage. */
class org.flashNight.arki.unit.Action.Melee.Cf6GuardAssetTest {
    private static var library:MovieClip,driver:MovieClip,loader:MovieClipLoader,listener:Object;
    private static var passed:Number,failed:Number,ticks:Number,fxCount:Number,pauseFrame:Number,pauseClock:Number;
    private static var ready:Boolean,finished:Boolean;
    private static var cases:Array,probes:Array,phases:Array,images:Object;
    private static var configs:Array,followups:Array;
    private static var link:String="敌人-CF6光头保安";

    private static function check(ok:Boolean,label:String):Void {
        if(ok) passed++; else {failed++;trace("[TEST_FAIL] Cf6GuardAssetTest: "+label);}
    }
    private static function record():Object {
        return {shots:0,meleeHits:0,front:0,back:0,moves:0,done:0,deathChecks:0,removed:false,
            physics:0,powerOk:true,areaOk:true,contractOk:true};
    }
    public static function runAllTests():Void {
        passed=failed=ticks=fxCount=0;ready=finished=false;cases=[];probes=[];phases=[];configs=[];followups=[];images={};
        library=_root.createEmptyMovieClip("__guardLibrary",_root.getNextHighestDepth());
        driver=_root.createEmptyMovieClip("__guardTestDriver",_root.getNextHighestDepth());
        library._visible=false;_root.gameworld=library;_root.暂停=false;
        _root.控制目标="__no_player";_root.控制目标全自动=false;_root.是否阴影=true;
        _root.播放音效=function():Void {};_root.发布消息=function():Void {};
        _root.add2map=function():Void {};_root.add2map2=function():Void {};
        _root.效果=function(name:String):Void {Cf6GuardAssetTest.fxCount++;};
        _root.初始化思考标签=function(mc:MovieClip):Void {mc._name="思考标签";mc.stop();mc._visible=false;};
        _root.敌人函数={配置音效:function():Void {},行走:function():Void {this.fixtureManualWalk=true;}};
        _root.子弹属性初始化=function(marker:MovieClip,kind:String,u:MovieClip):Object {
            return {子弹种类:kind,发射者:u._name,shootZ:u.Z轴坐标};
        };
        _root.子弹区域shoot传递=function(data:Object):Void {Cf6GuardAssetTest.capture(data);};
        _root.初始化敌人模板=function():Void {
            this.hp=this.hp满血值=1000;this.mp=0;this.空手攻击力=100;this.等级=30;
            this.状态="空手站立";this.攻击模式="空手";this.方向="右";this.攻击目标="无";
            this.Z轴坐标=this._y=200;this._x=200;this.myxscale=100;this.是否为敌人=true;
            this.倒地=this.浮空=this.硬直中=this.刚体=this.免疫击退=false;
            this.unitAI={data:{xrange:100,zrange:10,xdistance:50}};
            this.swapDepths=function():Void {};
            this.行走X速度=6;this.行走Y速度=4;this.跑X速度=12;this.跑Y速度=8;
            this.移动=function(dir:String,speed:Number):Void {
                this._x+=dir=="右"?speed:dir=="左"?-speed:0;
                this.Z轴坐标+=dir=="下"?speed:dir=="上"?-speed:0;this._y=this.Z轴坐标;this.fixtureRecord.moves++;
            };
            this.方向改变=function(dir:String):Void {this.方向=dir;this._xscale=dir=="左"?-100:100;};
            if(this.状态改变==undefined)this.状态改变=function(state:String):Void {
                if(this.状态==state) return;this.状态=state;this.gotoAndStop(state);
            };
            this.动画完毕=function():Void {
                this.fixtureRecord.done++;this.倒地=false;this.攻击目标="无";
                this.状态改变(this.hp>0?"空手站立":"血腥死");
            };
            this.击飞浮空=function():Void {this.fixtureRecord.physics++;this.浮空=true;};
            this.击飞倒地=function():Void {this.倒地=true;this._y=this.Z轴坐标;};
            this.死亡检测=function(options:Object):Void {
                this.fixtureRecord.deathOptions=options;
                this.fixtureRecord.deathChecks++;
                if(this.hp<=0){this.fixtureRecord.removed=true;this.removeMovieClip();}
            };
            this.stop();
        };
        listener={onLoadInit:function(mc:MovieClip):Void {Cf6GuardAssetTest.loaded(mc);},
            onLoadError:function(mc:MovieClip,error:String):Void {Cf6GuardAssetTest.check(false,"load "+error);Cf6GuardAssetTest.finish();}};
        loader=new MovieClipLoader();loader.addListener(listener);
        check(loader.loadClip("../flashswf/arts/new/Codex光头保安素材.swf",library),"load published SWF");
        driver.onEnterFrame=function():Void {Cf6GuardAssetTest.tick();};
    }
    private static function loaded(mc:MovieClip):Void {
        mc.stop();
        var states:Array=["空手站立","空手行走","空手跑","空手跳","近战","空手攻击","拾取","躲闪","被击","击倒","倒地","被投","血腥死","消失"];
        for(var side:Number=0;side<2;side++)for(var s:Number=0;s<states.length;s++) {
            var p:MovieClip=library.attachMovie(link,"guardProbe"+probes.length,library.getNextHighestDepth(),{fixtureRecord:record(),光头保安变身:false});
            check(p!=null,"attach state "+states[s]);probes.push({actor:p,state:states[s],side:side});
        }
        var moves:Array=["shoot","near","hit0","hit1","down","knockdown","death0","death1","death2","interrupt","dead"];
        for(var j:Number=0;j<2;j++)for(var m:Number=0;m<moves.length;m++) {
            var rec:Object=record();
            var u:MovieClip=library.attachMovie(link,"guardCase"+cases.length,library.getNextHighestDepth(),{fixtureRecord:rec,光头保安变身:false});
            check(u!=null,"attach "+moves[m]+" "+j);cases.push({actor:u,move:moves[m],side:j,record:rec});
        }
        createConfigs();createPhases();createFollowups();ready=true;ticks=0;
    }
    private static function createFollowups():Void {
        var modes:Array=["hit","miss","stale","dead","interrupt"];
        for(var side:Number=0;side<2;side++)for(var n:Number=0;n<modes.length;n++){
            var rec:Object=record();rec.followupMode=modes[n];rec.followupSide=side;
            var u:MovieClip=library.attachMovie(link,"guardFollowup"+followups.length,library.getNextHighestDepth(),{fixtureRecord:rec,光头保安变身:false});
            var target:MovieClip=library.createEmptyMovieClip("guardFollowTarget"+followups.length,library.getNextHighestDepth());
            target.hp=1000;target.createEmptyMovieClip("area",1);
            rec.followupTarget=target;followups.push({actor:u,record:rec,target:target,side:side});
        }
    }
    private static function followupTick():Void {
        for(var n:Number=0;n<followups.length;n++){
            var c:Object=followups[n],u:MovieClip=c.actor,rec:Object=c.record;
            if(ticks==3){
                u.方向改变(c.side==0?"右":"左");c.target._x=u._x+(c.side==0?60:-60);
                c.target._y=c.target.Z轴坐标=u.Z轴坐标;
                u.攻击目标=c.target._name;u.guardTargetName=c.target._name;u.状态改变("近战");
            }
            if(rec.interruptQueued===true){
                rec.interruptQueued=false;u.状态改变("被击");u.攻击目标="无";
                check(u.guardCombo==null && u.guardPendingFollowup==null,"interruption revokes earned followup "+n);
            }
            if(ticks==150){
                var armed:Boolean=rec.followupMode=="hit";
                check(rec.meleeHits==1 && rec.shots==(armed?1:0),"hit-confirmed followup emissions "+rec.followupMode+" side="+c.side);
                check(u.guardFollowupCount==(armed?1:0),"only eligible hit enters fast shot "+n);
                if(armed){
                    check(rec.followupShotClock-rec.followupHitClock>0 && rec.followupShotClock-rec.followupHitClock<=32,"melee hit to shotgun is bounded at 32 active frames "+n);
                    check(rec.powerOk && rec.contractOk && rec.areaOk,"followup preserves real shotgun payload and muzzle "+n);
                    check(u.guardAttackOwner==null && u.刚体===false && u.免疫击退===false,"followup releases stance after complete recoil "+n);
                    trace("[CF6_GUARD_FOLLOWUP] side="+c.side+" gap="+(rec.followupShotClock-rec.followupHitClock)+" shots="+rec.shots);
                }
                c.target.removeMovieClip();
            }
        }
    }
    private static function createConfigs():Void {
        var values:Array=[undefined,true,false,1,0,"true","false","1","0"];
        for(var variant:Number=0;variant<2;variant++)for(var n:Number=0;n<values.length;n++) {
            var params:Object={fixtureRecord:record()};
            if(n>0)params.光头保安变身=values[n];
            var actor:MovieClip=library.attachMovie(variant==0?link:"敌人-CF6变身光头保安","config"+configs.length,library.getNextHighestDepth(),params);
            configs.push({actor:actor,expected:n==0?variant==1:n%2==1});
        }
    }
    private static function createPhases():Void {
        var modes:Array=["ready","ready","ready","ready","ready","ready","empty","timeout","foreign","collision","ready-dead"];
        for(var i:Number=0;i<modes.length;i++) {
            var rec:Object=record();rec.spawnCalls=0;
            var u:MovieClip=library.attachMovie("敌人-CF6变身光头保安","phaseCase"+i,library.getNextHighestDepth(),{fixtureRecord:rec});
            phases.push({actor:u,record:rec,mode:modes[i],level:[30,60,99][i%3],side:i%2});
        }
        _root.加载游戏世界人物=function(kind:String,name:String,depth:Number,params:Object):MovieClip {
            var parent:MovieClip=Cf6GuardAssetTest.library[name.substr(0,name.indexOf("__tyrant"))];
            var rec:Object=parent.fixtureRecord;rec.spawnCalls++;rec.params=params;rec.kind=kind;
            Cf6GuardAssetTest.check(parent.man._currentframe==70,"successor spawned on frame 70");
            if(parent._name=="phaseCase0")Cf6GuardAssetTest.render(parent,"transform-end");
            if(parent._name=="phaseCase1")Cf6GuardAssetTest.render(parent,"transform-end-mirrored");
            if(parent.fixtureMode=="empty")return null;
            var world:MovieClip=parent.fixtureMode=="foreign"?_root:Cf6GuardAssetTest.library;
            var child:MovieClip=world.createEmptyMovieClip(name,depth);
            for(var key:String in params)child[key]=params[key];
            DisplayNameInitializer.initialize(child);
            child.兵种=kind;child.hp=child.hp满血值=9999;child.mp=333;
            if(parent.fixtureMode=="ready-dead")child.hp=0;
            child.version=7;
            if(parent.fixtureMode!="timeout")child.__unitInitializedVersion=7;
            child.方向改变=function(direction:String):Void {this.方向=direction;};
            rec.child=child;
            return child;
        };
    }
    private static function phaseTick():Void {
        if(ticks==2)for(var configIndex:Number=0;configIndex<configs.length;configIndex++) {
            var config:Object=configs[configIndex],configured:MovieClip=config.actor;
            check(configured.光头保安变身===config.expected,"variant default and explicit override "+configIndex);
            configured.hp=0;configured.状态改变("血腥死");
            check(configured.状态==(config.expected?"变身":"血腥死"),"configured death route "+configIndex);
            configured.removeMovieClip();
        }
        for(var captureIndex:Number=0;captureIndex<2;captureIndex++) {
            var captureCase:Object=phases[captureIndex];
            if(captureCase.actor.man._currentframe==52 && !captureCase.record.midCaptured) {
                captureCase.record.midCaptured=true;
                render(captureCase.actor,captureIndex==0?"transform-mid":"transform-mid-mirrored");
            }
        }
        if(ticks==3)for(var i:Number=0;i<phases.length;i++) {
            var c:Object=phases[i],u:MovieClip=c.actor;
            u.等级=c.level;u.是否为敌人=c.side==0;u.方向改变(c.side==0?"右":"左");
            u.名字="保安姓名继承"+i;u.称号="测试保安";u.产生源="phaseSource";u.hp=0;u.mp=42;u.hp满血值=17;u.oldBuff="must-not-transfer";
            u.fixtureMode=c.mode;
            if(c.mode=="collision")library.createEmptyMovieClip(u._name+"__tyrant",library.getNextHighestDepth());
            u.状态改变("血腥死");u._killed=true;DeathEventComponent.onDeath(u);
            check(u.guardDriver==null && u.guardShadow==null,"actual death cleanup removes root helpers "+i);
            check(u.man!=null,"actual death cleanup preserves transform body "+i);
        }
        if(ticks==5) {
            var p:MovieClip=phases[0].actor;p.man.gotoAndStop(1);render(p,"transform-start");
            var g:MovieClip=probes[0].actor;g.man.gotoAndStop(1);
            var ground:Object={x:0,y:0};p.man.phaseShadow.localToGlobal(ground);library.globalToLocal(ground);
            check(Math.abs(ground.y-p.Z轴坐标)<0.2,"transform shadow retains ground registration");
        }
        if(ticks==12)for(var n:Number=0;n<phases.length;n++)phases[n].pausedFrame=phases[n].actor.man._currentframe;
        if(ticks==17)for(n=0;n<phases.length;n++) {
            check(phases[n].actor.man._currentframe==phases[n].pausedFrame,"pause freezes transform "+n);
        }
        if(ticks==38) {
            for(n=0;n<phases.length;n++) {
                var actor:MovieClip=phases[n].actor;var before:Number=actor.man._currentframe;
                actor.状态改变("血腥死");actor.状态改变("被击");DeathEventComponent.onDeath(actor);
                check(actor.状态=="变身" && actor.man._currentframe==before,"duplicate death and hit keep phase "+n);
            }
        }
        if(ticks==125)for(n=0;n<phases.length;n++) {
            var entry:Object=phases[n],rec:Object=entry.record,unit:MovieClip=entry.actor;
            check(rec.spawnCalls==(entry.mode=="collision"?0:1),"at most one spawn attempt "+n);
            if(entry.mode=="ready" || entry.mode=="ready-dead") {
                check(rec.removed && rec.deathChecks==1,"first body retires once "+n);
                check(rec.deathOptions.noCount===true && rec.deathOptions.noCorpse===true,"phase death accounting "+n);
                check(rec.child.等级==entry.level && rec.child.是否为敌人===(entry.side==0),"level and faction inherited "+n);
                check(rec.child.方向==(entry.side==0?"右":"左") && rec.child._visible,"facing and visibility after initialization "+n);
                check(rec.child.hp==(entry.mode=="ready-dead"?0:9999) && rec.child.hp满血值==9999 && rec.child.mp==333
                    && rec.child.oldBuff==undefined,"fresh successor combat state "+n);
                check(rec.params.hp==undefined && rec.params.mp==undefined && rec.params.hp满血值==undefined
                    && rec.params.空手攻击力==undefined,"no old combat attributes passed "+n);
                check(rec.child.名字=="暴君克隆兽" && rec.child.称号==undefined
                    && rec.child.displayName.indexOf("暴君克隆兽")>=0 && rec.child.displayName.indexOf("保安姓名继承")<0
                    && rec.child.displayName.indexOf("undefined")<0,"real name initializer uses successor identity "+n);
                check(rec.kind=="敌人-完全体克隆兽" && rec.params.身高==230 && rec.params.产生源=="phaseSource"
                    && rec.params._x==200 && rec.params._y==200,"canonical tyrant and spawn context "+n);
            }else {
                check(!rec.removed && rec.deathChecks==0,"failed handoff keeps source count "+n);
                check(unit.guardTransform.error!=undefined && !unit.guardTransform.active,"failure becomes stable explicit state "+n);
                unit.guardSpawnTyrant(unit.man);unit.guardTransformTick(unit.man);
                check(rec.spawnCalls==(entry.mode=="collision"?0:1),"failed spawn never replayed "+n);
            }
            if(rec.child!=null)rec.child.removeMovieClip();
        }
    }
    private static function capture(data:Object):Void {
        var u:MovieClip=library[data.发射者],rec:Object=u.fixtureRecord;if(rec==undefined)return;
        if(data.子弹种类=="近战子弹") {
            rec.meleeHits++;check(u.man._currentframe==22,"melee emission on authored frame 22");
            var savedMelee:Number=rec.meleeHits;u.guardMeleeHit(u.man);check(rec.meleeHits==savedMelee,"duplicate melee callback rejected");
            rec.powerOk=rec.powerOk && data.子弹威力==150;
            rec.contractOk=rec.contractOk && data.霰弹值==1 && data.Z轴攻击范围==28 && data.shootZ==u.Z轴坐标
                && data.击倒率==2 && data.水平击退速度==28 && data.区域定位area!=null && data.区域定位area._parent===u.man;
            var mdx:Number=(data.shootX-u._x)*(u.方向=="右"?1:-1);
            rec.areaOk=rec.areaOk && mdx>30 && mdx<70;
            if(mdx>0)rec.front++;else rec.back++;
            if(rec.followupMode!=undefined){
                rec.followupHitClock=u.guardClock;
                if(rec.followupMode!="miss"){
                    data.hitTarget=rec.followupTarget;data.击中时触发函数();
                    var combo:Object=u.guardCombo;data.击中时触发函数();
                    check(combo!=null && u.guardCombo===combo,"actual melee payload arms followup once");
                    rec.followupTarget._x=u._x+(rec.followupSide==0?180:-180);
                    if(rec.followupMode=="stale")rec.followupTarget.__guardActionIdentity={};
                    if(rec.followupMode=="dead")rec.followupTarget.hp=0;
                    if(rec.followupMode=="interrupt")rec.interruptQueued=true;
                }
            }
            return;
        }
        rec.shots++;
        var followup:Boolean=u.guardAttackOwner.mode=="followup";
        check(u.man._currentframe==(followup?96:41),"emission on normal or confirmed followup fire frame");
        if(followup)rec.followupShotClock=u.guardClock;
        var saved:Number=rec.shots;u.guardShoot(u.man);check(rec.shots==saved,"duplicate fire callback rejected");
        rec.powerOk=rec.powerOk && data.子弹威力==100;
        rec.contractOk=rec.contractOk && data.子弹种类=="穿刺子弹" && data.子弹速度==25
            && data.霰弹值==3 && data.Z轴攻击范围==24 && data.shootZ==u.Z轴坐标
            && data.击倒率==10 && data.区域定位area==undefined && data.子弹散射度==8
            && data.声音=="re_shotgun_spas12.wav" && data.发射效果=="霰弹枪枪火";
        var dx:Number=(data.shootX-u._x)*(u.方向=="右"?1:-1);
        rec.areaOk=rec.areaOk && dx>50 && dx<70 && data.shootY>u._y-110 && data.shootY<u._y-85;
        if(dx>0)rec.front++;else rec.back++;
        if(u._name=="guardCase0")render(u,"shoot");
    }
    private static function pixelHex(value:Number):String {
        var digits:String="0123456789abcdef",text:String="";
        for(var shift:Number=28;shift>=0;shift-=4)text+=digits.charAt((value>>>shift)&15);
        return text;
    }
    private static function render(u:MovieClip,key:String):Void {
        if(u==null)return;
        var info:Boolean=u.人物文字信息._visible;u.人物文字信息._visible=false;
        var bd:BitmapData=new BitmapData(640,430,true,0xffe8e6e2);
        var matrix:Matrix=u.transform.matrix;
        var scale:Number=key=="airborne-shadow"?0.65:1.4;
        matrix.a*=scale;matrix.b*=scale;matrix.c*=scale;matrix.d*=scale;matrix.tx=320;matrix.ty=350;
        bd.draw(u,matrix);u.人物文字信息._visible=info;
        var visible:Number=0,edge:Number=0;
        for(var y:Number=0;y<430;y+=3)for(var x:Number=0;x<640;x+=3)if(bd.getPixel(x,y)!=0xe8e6e2)visible++;
        check(visible>200,"native pixels "+key+" "+visible);images[key]=true;
        if(_root.guardCapture===true) {
            trace("[GUARD_IMAGE_BEGIN] "+key+" 640 430");
            for(var row:Number=0;row<430;row++) {
                var parts:Array=[],last:Number=bd.getPixel32(0,row),count:Number=1;
                for(var col:Number=1;col<640;col++) {
                    var value:Number=bd.getPixel32(col,row);
                    if(value==last)count++;else{parts.push(pixelHex(last)+":"+count);last=value;count=1;}
                }
                parts.push(pixelHex(last)+":"+count);
                trace("[GUARD_IMAGE_ROW] "+key+" "+row+" "+parts.join(","));
            }
            trace("[GUARD_IMAGE_END] "+key);
        }
        bd.dispose();
    }
    private static function shadowCheck(u:MovieClip,label:String):Void {
        check(u.guardShadow!=null && u.guardShadow._visible,"shadow "+label);
        check(library.shadow==undefined && u.shadow==undefined,"shadow registration private "+label);
        var p:Object={x:0,y:0};u.guardShadow.localToGlobal(p);library.globalToLocal(p);
        check(Math.abs(p.y-u.Z轴坐标)<0.2,"shadow grounded "+label);
    }
    private static function decisions():Void {
        var u:MovieClip=probes[0].actor;
        check(u.命中率==20 && u.击中效果=="飙血","human hit and accuracy initialization");
        var target:MovieClip=library.createEmptyMovieClip("guardDecisionTarget",library.getNextHighestDepth());
        target.hp=1000;target._x=500;target.Z轴坐标=target._y=200;target.createEmptyMovieClip("area",1);
        var change:Function=u.状态改变;
        u.状态改变=function(state:String):Void {this.requestedState=state;this.状态=state;};
        u.攻击目标=target._name;u.guardTargetName=target._name;u.guardReadyAt=0;
        var flags:Array=["暂停","manual","硬直中","倒地","浮空","dead","badTarget"];
        for(var i:Number=0;i<flags.length;i++) {
            u.状态="空手站立";u.requestedState="none";u.guardClock=99;
            var flag:String=flags[i];
            if(flag=="暂停")_root.暂停=true;else if(flag=="manual")_root.控制目标=u._name;
            else if(flag=="dead")u.hp=0;else if(flag=="badTarget")target.hp=0;else u[flag]=true;
            u.guardTick();check(u.requestedState==(flag=="dead"?"血腥死":"none"),"AI guard "+flag);
            _root.暂停=false;_root.控制目标="__no_player";u.hp=target.hp=1000;u.硬直中=u.倒地=u.浮空=false;
        }
        var distances:Array=[381,380,86,85,30];
        for(var d:Number=0;d<distances.length;d++) {
            target._x=u._x+distances[d];u.状态="空手站立";u.requestedState="none";u.guardClock=99;
            u.guardTick();check(u.requestedState==(d==0?"none":(d>=3?"近战":"空手攻击")),"range boundary "+distances[d]);
        }
        target._x=500;target.Z轴坐标=target._y=240;
        u.状态="空手站立";u.requestedState="none";u.guardClock=99;u.guardTick();
        check(u.requestedState=="none" && u.下行===true,"align before shooting");
        target.Z轴坐标=target._y=200;target.浮空高度=66;
        u.状态="空手站立";u.requestedState="none";u.guardClock=99;u.guardTick();
        check(u.requestedState=="none","unreachable aerial target");target.浮空高度=0;
        u.guardReadyAt=101;u.状态="空手站立";u.requestedState="none";u.guardClock=99;u.guardTick();
        check(u.requestedState=="none","post-shot rest");u.guardReadyAt=0;
        u.状态="空手攻击";u.guardBeginAttack(u.man);
        var first:Object=u.man.guardToken;u.guardBeginAttack(u.man);var current:Object=u.man.guardToken;
        u.man.guardToken=first;check(!u.guardCanAct(u.man),"stale token rejected");u.man.guardToken=current;
        check(u.guardCanAct(u.man),"current action accepted");
        _root.暂停=true;check(!u.guardCanAct(u.man),"paused action rejected");_root.暂停=false;
        u.guardCancelAttack();check(!u.guardCanAct(u.man),"cancelled action rejected");
        check(u.刚体===false && u.免疫击退===false,"cancel releases own windup stance");
        u.刚体=u.免疫击退=true;u.guardBeginAttack(u.man);u.guardCancelAttack();
        check(u.刚体===true && u.免疫击退===true,"external stance survives cancellation");
        u.刚体=u.免疫击退=false;
        u.状态="空手站立";target._x=500;target.Z轴坐标=target._y=201;u.guardMovementTarget="";
        for(var n:Number=0;n<48;n++){u.上行=true;u.下行=false;u.右行=true;u.行走();}
        check(u._x==200 && u.Z轴坐标==200,"cooldown holds position despite generic movement writes");
        target.Z轴坐标=235;u.行走();check(u.Z轴坐标==204,"large lane error starts movement");
        for(n=0;n<12;n++)u.行走();check(u.Z轴坐标==223,"lane movement stops at inner band");
        target.Z轴坐标=245;u.行走();check(u.Z轴坐标==223,"lane hysteresis avoids restart");
        target._x=585;target.Z轴坐标=u.Z轴坐标;u.行走();
        for(n=0;n<12;n++)u.行走();check(u._x==245,"approach caps final step at 340");
        _root.控制目标=u._name;u.行走();check(u.fixtureManualWalk===true,"manual walking delegates");_root.控制目标="__no_player";
        u.状态改变=change;
        u.状态改变("击倒");u.hp=0;u.guardTick();
        check(u.状态=="击倒" && u.man._currentframe==1 && !u.fixtureRecord.removed,"airborne lethal stays in 1f knockdown pose before landing");
        u.hp=1000;u.浮空=false;u.状态改变("空手站立");u.攻击目标="无";u._x=200;u._y=u.Z轴坐标=200;
        u.guardClearMovement();target.removeMovieClip();
        _root.是否阴影=false;u.guardShadow.updateGuardShadow();check(!u.guardShadow._visible,"shadow option off");
        _root.是否阴影=true;u.guardShadow.updateGuardShadow();check(u.guardShadow._visible,"shadow option on");
        u._y=160;u._rotation=25;u._xscale=-160;u._yscale=160;
        u.guardShadow.updateGuardShadow();shadowCheck(u,"lifted rotated mirrored");render(u,"airborne-shadow");
        u._y=200;u._rotation=0;u._xscale=u._yscale=100;u.guardShadow.updateGuardShadow();
    }
    private static function tick():Void {
        if(finished)return;ticks++;
        if(!ready){if(ticks>300){check(false,"load timeout");finish();}return;}
        followupTick();
        phaseTick();
        if(ticks==3) {
            for(var s:Number=0;s<probes.length;s++) {
                var pr:Object=probes[s];pr.actor.方向改变(pr.side==0?"右":"左");pr.actor.状态改变(pr.state);
            }
            for(var i:Number=0;i<cases.length;i++) {
                var c:Object=cases[i],u:MovieClip=c.actor;u.方向改变(c.side==0?"右":"左");
                if(c.move=="shoot" || c.move=="interrupt" || c.move=="dead")u.状态改变("空手攻击");
                else if(c.move=="near")u.状态改变("近战");
                else if(c.move.substr(0,3)=="hit"){u.状态改变("被击");u.man.gotoAndPlay("a"+c.move.substr(3));}
                else if(c.move=="down")u.状态改变("倒地");
                else if(c.move=="knockdown" || c.move=="airborne-dead"){u.状态改变("击倒");if(c.move=="airborne-dead")u.hp=0;}
                else if(c.move.substr(0,5)=="death"){u.hp=0;u.状态改变("血腥死");u.man.gotoAndPlay("a"+c.move.substr(5));}
            }
        }
        if(ticks==5) {
            for(var k:Number=0;k<probes.length;k++) {
                var p:Object=probes[k];
                if(p.state=="消失"){check(p.actor.man==null && p.actor.guardShadow==null,"disappeared body and shadow");continue;}
                check(p.actor.man._width>0,"native body "+p.state);shadowCheck(p.actor,p.state+" "+p.side);
            }
            var standing:MovieClip=probes[0].actor;standing.man.gotoAndStop(1);render(standing,"stand");
            var dying:MovieClip=cases[6].actor;var df:Number=dying.man._currentframe;dying.man.gotoAndStop(1);
            var a:Object=standing.man.getBounds(library),b:Object=dying.man.getBounds(library);
            check(Math.abs(a.yMax-b.yMax)<0.3,"death first pose ground");
            check(Math.abs(a.xMin-b.xMin)<0.3 && Math.abs(a.xMax-b.xMax)<0.3,"death first pose horizontal registration");
            render(dying,"death-start");dying.man.gotoAndPlay(df);standing.man.play();decisions();
        }
        if(ticks==9)for(var j:Number=0;j<cases.length;j++) {
            var q:Object=cases[j];
            if(q.move=="interrupt"){q.actor.状态改变("被击");q.actor.man.gotoAndPlay("a0");}
            else if(q.move=="dead")q.actor.hp=0;
            else if(q.move=="knockdown" || q.move=="airborne-dead"){
                if(q.move=="airborne-dead")check(q.actor.状态=="击倒" && q.actor.man._currentframe==1 && !q.record.removed,"airborne lethal stays in single-frame knockdown before landing");
                q.actor.浮空=false;q.actor.状态改变("倒地");
            }
        }
        if(ticks==12){
            check(cases[0].actor.刚体===true && cases[0].actor.免疫击退===true,"windup stance active");
            check(cases[9].actor.刚体===false && cases[9].actor.免疫击退===false,"forced interruption releases stance");
            _root.暂停=true;pauseFrame=cases[0].actor.man._currentframe;pauseClock=cases[0].actor.guardClock;}
        if(ticks==17){
            check(cases[0].actor.man._currentframe==pauseFrame,"pause freezes actual attack frames");
            check(cases[0].actor.guardClock==pauseClock,"pause freezes action clock");_root.暂停=false;
        }
        if(ticks==65){
            check(cases[0].actor.刚体===false && cases[0].actor.免疫击退===false,"post-shot recovery is vulnerable");
        }
        if(ticks==48){
            render(cases[11].actor,"shoot-mirrored");
        }
        if(ticks==20){
            var early:MovieClip=cases[0].actor;early.guardShoot(early.man);check(cases[0].record.shots==0,"no early emission during windup");
            render(cases[6].actor,"death-a0");render(cases[7].actor,"death-a1");render(cases[8].actor,"death-a2");}
        if(ticks==150) {
            for(var n:Number=0;n<cases.length;n++) {
                var entry:Object=cases[n],rec:Object=entry.record;var attack:Boolean=entry.move=="shoot" || entry.move=="near";
                check(rec.shots==(entry.move=="shoot"?1:0),"exact shot count "+entry.move+" "+entry.side+" got="+rec.shots);
                check(rec.meleeHits==(entry.move=="near"?1:0),"exact melee count "+entry.move+" "+entry.side+" got="+rec.meleeHits);
                check(rec.powerOk && rec.contractOk && rec.areaOk,"real shotgun/melee contract "+n);
                if(attack) {
                    check(rec.done==1,"attack completes once "+n);
                    check(rec.front==1 && rec.back==0,"muzzle/melee ahead on both sides "+n);
                    check(entry.actor.guardAttackOwner==null && entry.actor.刚体===false && entry.actor.免疫击退===false,"action and stance ownership released "+n);
                    check(entry.actor.guardInvalidMuzzleCount==0,"no missing nested muzzle "+n);
                } else if(entry.move.substr(0,5)=="death" || entry.move=="dead" || entry.move=="airborne-dead") {
                    check(rec.removed && rec.deathChecks==1,"death settles once "+n);
                } else {
                    check(rec.done==1,"hit/down recovery "+n+" done="+rec.done);
                    if(entry.move=="knockdown")check(rec.physics==1,"airborne physics delegated once "+n);
                }
            }
            var required:Array=["stand","death-start","death-a0","death-a1","death-a2","shoot","shoot-mirrored","airborne-shadow",
                "transform-start","transform-mid","transform-mid-mirrored","transform-end","transform-end-mirrored"];
            for(var h:Number=0;h<required.length;h++)check(images[required[h]]===true,"capture exists "+required[h]);finish();
        }
    }
    private static function finish():Void {
        if(finished)return;finished=true;delete driver.onEnterFrame;
        if(loader!=null)loader.removeListener(listener);
        trace("Cf6GuardAssetTest: "+passed+" passed, "+failed+" failed; "+cases.length+" actual timeline cases; "+phases.length+" transformation cases; "+followups.length+" hit-confirmed followup cases");
        library.removeMovieClip();driver.removeMovieClip();_root.cf6GuardAssetComplete();
    }
}
