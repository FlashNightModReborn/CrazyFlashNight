import org.flashNight.arki.spatial.move.Mover;
import org.flashNight.arki.spatial.animation.FragmentAnimator;
import org.flashNight.arki.spatial.animation.FragmentConfig;
import org.flashNight.arki.unit.Action.Shoot.WeaponFireCore;
import org.flashNight.arki.unit.Action.Shoot.ShootCore;
import org.flashNight.arki.unit.Action.Shoot.ShootInitCore;
import org.flashNight.arki.unit.Action.Skill.SkillReloadCore;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController;
import org.flashNight.arki.unit.Action.Melee.BladeShootCore;
import org.flashNight.arki.unit.Action.Skill.SheriffShieldRush;
import org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle;
import org.flashNight.arki.unit.UnitComponent.Routing.RoutingIntent;
import org.flashNight.arki.unit.UnitComponent.Routing.RoutingRuntime;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;
import org.flashNight.arki.unit.UnitComponent.Updater.HitUpdater;
import org.flashNight.arki.unit.UnitComponent.Initializer.EventComponent.KillEventComponent;
import org.flashNight.arki.component.Buff.PodBuff;
import org.flashNight.arki.component.Buff.MetaBuff;
import org.flashNight.arki.component.Buff.BuffCalculationType;

/**
 * Independent former-sheriff encounter controller. No BaseUnitAI / Hero AI.
 * Native player motion, weapon/reload and damage services remain authoritative.
 * First-life HP never exposes zero to the shared death/reward consumers.
 * Phase two owns fixed shield actions, magazine loops and one final death.
 */
class org.flashNight.arki.unit.UnitAI.Custom.FormerSheriffController {
    public static var KIND:String = "敌人-前治安官";
    public static var LONE_BUFF:String = "前治安官_独行者";

    public static function install(root:Object):Void {
        root.前治安官固定头部=function(head:MovieClip,u:MovieClip):Void {
            u.__formerSheriff.head=head;
            head.gotoAndStop(u.__formerSheriff.helmetFlown ? 2 : 1);
        };
        root.前治安官固定武器=function(skin:MovieClip,u:MovieClip,ref:String):Void {
            u[ref]=skin;
            if(u.__formerSheriff.finalDeath){skin._visible=false;return;}
            if(u.syncRefs[ref])u.dispatcher.publish(ref,u);
        };
        root.前治安官初始化长枪射击=function():Void {ShootInitCore.initLongGun(this,this._parent);};
        root.前治安官初始化手枪射击=function():Void {ShootInitCore.initPistol(this,this._parent);};
        root.前治安官上下闪避=function(man:MovieClip,u:MovieClip):Void {FormerSheriffController.moveHop(u);};
        root.前治安官翻滚换弹=function():Void {SkillReloadCore.reloadAllWeapons(this._parent);};
        root.前治安官初始化 = function(u:MovieClip):Void {
            FormerSheriffController.initialize(u);
        };
        root.前治安官绑定动作 = function(man:MovieClip):Void {
            FormerSheriffController.bindMotion(man);
        };
    }

    /** Frames are 30fps. Encounter overrides live in unit.前治安官参数. */
    public static function defaults():Object {
        return {closeEnter:85,closeExit:125,farEnter:330,farExit:270,
            laneTolerance:18,reloadLane:55,reloadDistance:310,safeDistance:220,
            senseFrames:10,stanceFrames:24,batonFrames:42,
            rushCooldown:300,rollCooldown:150,hopCooldown:30,reactionLock:18,
            skillLevel:6,rushChargeFrames:18,transitionChargeFrames:36,
            rushSpeedBonus:2,rushPowerMultiplier:0.02,rushChargedPower:0.03,
            rushReduction:50,rushShieldDefenseRatio:0.2,
            loneAttack:1.35,loneDefense:1.8,loneHealth:1.1,
            shotgunPower:0.3,pistolPower:0.35,batonPower:0.38,hopDistance:54,hopFrames:8,
            secondLifeRatio:0.5,phaseTwoBashRange:100,phaseTwoKnifeRange:115,
            phaseTwoPistolRange:440,phaseTwoRest:18,phaseTwoRushCooldown:300,
            phaseTwoBashPower:0.2,phaseTwoKnifePower:0.65,phaseTwoPistolPower:0.35,
            phaseTwoBashImpact:1,phaseTwoKnifeImpact:6,
            phaseTwoMoveRatio:.8,deathFoldChance:.3,knockdownFrames:9,landingFrames:9,getupFrames:16,groundPause:12};
    }

    public static function initialize(u:MovieClip):Void {
        if (u.__formerSheriff) return;
        var p:Object=defaults();
        for(var key:String in u.前治安官参数) {
            var number:Number=Number(u.前治安官参数[key]);
            if(isFinite(number) && number>=0)p[key]=number;
        }
        var c:Object={unit:u,world:u._parent,tune:p,phase:1,age:0,clock:0,
            action:null,actionAge:0,opening:0,nextSense:0,nextStance:0,
            nextRush:0,nextRoll:0,nextHop:0,nextBaton:0,reactionUntil:0,
            transitionCount:0,lone:null,ready:false,spawnSettled:false};
        u.__formerSheriff=c;
        u.兵种=KIND;u.名字=u.名字 || "前治安官";u.性别="男";
        u.unitAIType="None";u.使用人形怪AI=false;u.hasDressup=false;u.hasFixedEquipment=false;u.enableShoot=true;
        u.允许拾取=false;u.不掉装备=true;u.基础命中率=10;
        if(u.是否为敌人==undefined)u.是否为敌人=true;
        if(isNaN(u.等级))u.等级=20;
        // Authored fixed art is independent of inventory, enhancement and item lifecycles.
        // Only NPC-owned fire/reload descriptors participate in the shared animation API.
        initializeWeapons(u);
        u.攻击模式="手枪";u.内力=80;u.mp_min=100;u.mp_max=100;u.mp满血值=100;u.mp=100;
        u.bigState=[];u.state=[];u.smallState=[];u.被动技能={移动射击:{启用:true,等级:10}};u.操控编号=-1;
        var names:Array=["根据模式重新读取武器加成","方向改变","移动","攻击时移动",
            "跑步音效","UpdateBigState","UpdateState","UpdateSmallState","UpdateBigSmallState",
            "getBigState","getState","getSmallState","getAllState",
            "getPastBigStates","getPastStates","getPastSmallStates",
            "装载主动战技","装载副武器控制槽","创建主动战技槽位表","获取装备主动战技种类",
            "装载生命周期函数","完成生命周期函数装载","读取被动效果","读取基础被动效果",
            "存储当前飞行状态","读取当前飞行状态","硬直","移动钝感硬直"];
        for(var i:Number=0;i<names.length;i++)u[names[i]]=_root.主角函数[names[i]];
        u.根据等级初始数值=function(ignored:Number):Void {
            _root.敌人函数.根据等级初始数值.call(this,this.等级);
        };
        u.主动战技=u.创建主动战技槽位表();
        u.刀口位置生成子弹=BladeShootCore.shoot;
        u.长枪射击=function(muzzle:MovieClip,props:Object):Boolean {
            props.子弹威力=this.空手攻击力*this.__formerSheriff.tune.shotgunPower;
            return WeaponFireCore.LONG_GUN_SHOOT.call(this,muzzle,props);
        };
        u.手枪射击=function(muzzle:MovieClip,props:Object):Boolean {
            props.子弹威力=this.空手攻击力*this.__formerSheriff.tune.pistolPower;
            return WeaponFireCore.PISTOL_SHOOT.call(this,muzzle,props);
        };
        u.状态改变=function(s:String):Void {FormerSheriffController.changeState(this,s);};
        u.装载固定盾冲=function():MovieClip {return FormerSheriffController.mountShieldRush(this);};
        u.动画完毕=function():Void {FormerSheriffController.animationDone(this);};
        u.被击移动=function(direction:String,distance:Number):Void {
            var context:Object=this.__formerSheriff;
            if(context.phase==1 && !context.pendingReaction && !context.action)
                _root.敌人函数.被击移动.apply(this,arguments);
        };
        // Capture the authored anchor before the legacy facade unloads it.
        // ParameterInitializer and the HP updater must use the same coordinates.
        u.icX=u.人物文字信息._x;u.icY=u.人物文字信息._y;
        // Preserve explicit spawn resistance before the legacy initializer's
        // unqualified fallback fills elemental entries from the base value.
        // Only this custom unit reapplies its own monster profile afterwards.
        var spawnResistance:Object={};
        for(var resistanceName:String in u.魔法抗性)
            spawnResistance[resistanceName]=u.魔法抗性[resistanceName];
        _root.初始化敌人模板.apply(u);
        var declaredResistance:Object=_root.敌人属性表[KIND].魔法抗性;
        for(resistanceName in declaredResistance)
            u.魔法抗性[resistanceName]=Number(declaredResistance[resistanceName]);
        for(resistanceName in spawnResistance)
            u.魔法抗性[resistanceName]=Number(spawnResistance[resistanceName]);
        u.刀_刀口数=Number(u.刀属性.bladeCount);
        u.根据模式重新读取武器加成(u.攻击模式);
        // Shared nameplate is dynamically attached by the common initializer.
        // Reserve depth 0 for the player-derived skill containers.
        if(u.新版人物文字信息) {
            u.新版人物文字信息.swapDepths(9999);
            u.新版人物文字信息._x=u.icX;u.新版人物文字信息._y=u.icY;
        }
        // The legacy frame facade has unqualified fields at its tail. This
        // class-owned entry must take scale, direction and state from the actor.
        u.myxscale=Math.abs(u._yscale);
        u.方向改变(u.方向);
        changeState(u,u.攻击模式+"站立");
        c.light={自机:u,装备类型:"长枪",装备:u.长枪,装备名称:u.长枪.name,是否为主角:false,版本号:u.version};
        EquipmentLightController.initialize(c.light,{kind:"flashlight",beamPath:"装备光束",
            fallbackVisual:false,color:16773584,anchor:"手电口"});
        u.dispatcher.subscribe("unload",function():Void {EquipmentLightController.dispose(this.__formerSheriff.light);},u);
        c.hp=Number(u.hp);c.externalInvincible=u.无敌===true;
        u.addProperty("无敌",function():Boolean {
            var context:Object=this.__formerSheriff;
            return context.phase=="transition" || (context.finalDeath && !context.finalFinished) || context.externalInvincible;
        },function(value:Boolean):Void {this.__formerSheriff.externalInvincible=value===true;});
        // Accessor is local to this new unit, never installed on players/enemies.
        // It catches DoT, execution and forced-terminal writes before kill/onDown.
        u.addProperty("hp",function():Number {return this.__formerSheriff.hp;},
            function(value:Number):Void {FormerSheriffController.setHP(this,Number(value));});
        var hit:Function=HitUpdater.getUpdater(u);
        c.hit=hit;
        u.dispatcher.subscribeSingle("hit",function():Void {
            var context:Object=this.__formerSheriff;
            if(context.finalDeath && context.finalStep=="pending" && context.finalShooter==undefined) {
                context.finalShooter=arguments[1];
                context.finalBullet=_root.对象浅拷贝(arguments[2]);
            }
            context.hit.apply(this,arguments);
            FormerSheriffController.afterHit(this);
        },u);
        u.dispatcher.subscribeSingle("kill",function(target:MovieClip):Void {
            if(target.__formerSheriff.phase==2 && (target.__formerSheriff.finalDeath || target.hp<=0) && !target.__formerSheriff.finalFinished) {
                FormerSheriffController.beginFinalDeath(target);return;
            }
            if((target.__formerSheriff.phase==2 || target.__formerSheriff.phase=="calibrationDefeated") && target.hp<=0 && !target._killed)
                KillEventComponent.onKill(target);
        },u);
        var thinker:MovieClip=u.createEmptyMovieClip("__formerSheriffThink",10000);
        thinker.onEnterFrame=function():Void {FormerSheriffController.tick(this._parent);};
        c.thinker=thinker;c.ready=true;
        u.配置音效("人类",u);
        c.oldDeathCheck=u.死亡检测;
        u.死亡检测=function():Void {
            if(this.__formerSheriff.phase==2 || this.__formerSheriff.phase=="calibrationDefeated")
                {
                var context:Object=this.__formerSheriff;
                if(context.phase==2 && (context.finalDeath || this.hp<=0) && !context.finalFinished) {
                    FormerSheriffController.beginFinalDeath(this);return;
                }
                context.oldDeathCheck.apply(this,arguments);
            }
        };
        u.__前治安官阶段=1;
        sense(u);c.hp=u.hp满血值;c.spawnSettled=true;
    }

    /** No BaseItem / item XML / equipment stat projection is involved. */
    private static function initializeWeapons(u:MovieClip):Void {
        var p:Object=u.__formerSheriff.tune;
        var shotgun:Object={capacity:8,split:1,diffusion:4,interval:600,singleshoot:true,
            velocity:30,bullet:"镇暴射线",sound:"re_shotgun_m1014.wav",muzzle:"霰弹枪枪火",
            bullethit:"火花",clipname:"12号霰弹弹药",bulletsize:42,impact:2,reloadType:"tube",reloadPenalty:0};
        var pistol:Object={capacity:8,split:1,diffusion:3,interval:550,singleshoot:true,
            velocity:36,bullet:"穿刺子弹",sound:"re_pistol_DEagle.wav",muzzle:"马格南手枪枪火",
            bullethit:"火花",clipname:"马格南手枪弹药",bulletsize:30,impact:10,reloadPenalty:17};
        var baton:Object={bladeCount:3};
        // Frame scripts may query power between stance changes; derive it live.
        bindMonsterPower(shotgun,u,p.shotgunPower);
        bindMonsterPower(pistol,u,p.pistolPower);
        bindMonsterPower(baton,u,p.batonPower);
        u.长枪={name:"特勤霰弹枪",value:{shot:0}};u.手枪={name:"特勤沙鹰",value:{shot:0}};
        u.刀={name:"特勤警棍",value:{}};
        u.长枪数据={name:"特勤霰弹枪",data:shotgun,skill:{parameters:{}}};
        u.手枪数据={name:"特勤沙鹰",data:pistol};u.刀数据={name:"特勤警棍",actiontype:"棍棒",data:baton};
        u.长枪属性=shotgun;u.手枪属性=pistol;u.刀属性=baton;
        u.长枪弹匣容量=8;u.手枪弹匣容量=8;u.兵器动作类型="棍棒";
        u.装备防御力=0;u.伤害加成=0;u.基础伤害类型="物理";
        u.基础毒=0;u.基础吸血=0;u.基础击溃=0;u.基础命中加成=0;u.基础斩杀=0;
        u.长枪吸血=0;u.手枪吸血=0;u.兵器吸血=0;
    }

    private static function bindMonsterPower(profile:Object,u:MovieClip,ratio:Number):Void {
        profile.addProperty("power",function():Number {return u.空手攻击力*ratio;},null);
    }

    public static function chooseHopDirection(u:MovieClip):String {
        var c:Object=u.__formerSheriff;
        var preferred:String=c.target.Z轴坐标>u.Z轴坐标 ? "上":"下";
        var best:String=preferred,bestRoom:Number=-1;
        for(var i:Number=0;i<2;i++) {
            var direction:String=i==0?preferred:(preferred=="上"?"下":"上");
            var sign:Number=direction=="上"?-1:1,room:Number=0;
            for(var step:Number=6;step<=c.tune.hopDistance;step+=6) {
                if(_root.collisionLayer.hitTest(u._x,u.Z轴坐标+sign*step,true))break;
                room=step;
            }
            if(room>bestRoom){best=direction;bestRoom=room;}
        }
        return best;
    }

    public static function moveHop(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        var frame:Number=Number(_root.帧计时器.当前帧数);
        if(c.action!="小跳" || c.hopTick==frame)return;
        c.hopTick=frame;
        var step:Number=Math.min(c.tune.hopDistance-c.hopTravel,c.tune.hopDistance/c.tune.hopFrames);
        if(step>0){Mover.move2DStrict(u,c.hopDirection,step);c.hopTravel+=step;}
    }

    public static function setHP(u:MovieClip,value:Number):Void {
        var c:Object=u.__formerSheriff;
        if(!c || isNaN(value))return;
        if(c.phase=="transition" || c.finalDeath)return;
        if(c.phase==1 && value<=0) {
            // Explicit roster opt-in only inside the no-player calibration arena.
            // A first-life duel must end before the deathrattle and second HP pool.
            // Ordinary encounters, custom matches and the default roster keep both lives.
            if(_root.斗兽标定模式===true && u._arenaCalibrationUnit===true && c.tune.calibrationPhaseOne==1) {
                c.phase="calibrationDefeated";c.hp=value;c.fatalHP=value;
                c.pendingReaction=null;c.action=null;
                u.动作A=false;u.动作B=false;
                u.__前治安官阶段="标定一阶段结束";
                return;
            }
            c.hp=1;c.phase="transition";c.pendingTransition=true;
            c.transitionCount++;c.fatalHP=value;
            u.无敌=true;
            u.__前治安官阶段="转阶段";
            return;
        }
        if(c.phase==2 && value<=0) {
            // Melee settlement publishes death directly, not through kill.
            // Keep terminal HP private until the authored fall has landed.
            c.finalFatalHP=value;c.hp=1;beginFinalDeath(u);return;
        }
        c.hp=value;
    }

    public static function changeState(u:MovieClip,s:String):Void {
        var c:Object=u.__formerSheriff;
        if(c.phase=="transition" && c.transitionStep=="air" && s=="倒地" && !u.浮空) {
            c.transitionStep="land";c.age=0;ground(u);
            changeState(u,"转阶段落地");u.man.gotoAndStop(1);
            _root.效果("灰尘1",u._x,u._y,u._xscale);
            _root.播放音效("sound143.mp3");
            return;
        }
        if(c.phase==2 && (c.finalDeath || u.hp<=0)) {
            if(s=="倒地" && c.finalStep=="air" && !u.浮空) {
                c.finalStep="land";c.age=0;ground(u);
                changeState(u,"转阶段落地");u.man.gotoAndStop(1);
                _root.效果("灰尘1",u._x,u._y,u._xscale);
                _root.播放音效("sound143.mp3");
            } else if(!c.finalDeath)beginFinalDeath(u);
            if(s.indexOf("转阶段")!=0)return;
        }
        if(c.ready && (s=="被击" || s=="击倒")) {
            if(c.phase==2) {
                if(s=="击倒" && c.action!="rush" && c.clock>=c.nextRush && c.clock>=c.reactionUntil) {
                    c.pendingReaction="phaseTwoRush";c.reactionUntil=c.clock+c.tune.reactionLock;
                }
                return;
            }
            var escaping:Boolean=c.action=="rush" || c.action=="翻滚换弹" || c.action=="小跳";
            if(c.phase==1 && !escaping && c.clock>=c.reactionUntil) {
                c.pendingReaction=chooseReaction(u);
                c.reactionUntil=c.clock+c.tune.reactionLock;
            }
            return;
        }
        if(c.ready && c.phase=="transition" && s!="战技" && s.indexOf("转阶段")!=0)return;
        var label:String=(s=="技能" || s=="战技" || s=="兵器攻击" || s=="持盾") ? "容器" : s;
        if(u.状态==s && u.__stateGotoLabel==label)return;
        if(u.man.__isDynamicMan===true)u.man.removeMovieClip();
        u.旧状态=u.状态;u.状态=s;u.__stateGotoLabel=label;
        u.gotoAndStop(label);
        RoutingIntent.executeStateTransitionJob(u);
    }

    public static function chooseReaction(u:MovieClip):String {
        var c:Object=u.__formerSheriff;
        if(u.攻击模式=="长枪" && c.clock>=c.nextRush)return "rush";
        if(missingAmmo(u)!=null && c.clock>=c.nextRoll)return "roll";
        return c.clock>=c.nextHop ? "hop" : null;
    }

    public static function afterHit(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(c.phase=="transition" || c.finalDeath)return;
        if(c.phase==2 && u.hp<=0){beginFinalDeath(u);return;}
        if(c.phase==2 && c.pendingReaction=="phaseTwoRush") {
            c.pendingReaction=null;c.nextRush=c.clock+c.tune.phaseTwoRushCooldown;
            if(!startRush(u,false))phaseTwoGuard(u);
            return;
        }
        if(c.action || c.pendingReaction)ground(u);
        if(c.pendingReaction && c.phase==1) {
            var next:String=c.pendingReaction;c.pendingReaction=null;
            react(u,next);
        }
    }

    private static function ground(u:MovieClip):Void {
        u.浮空=false;u.倒地=false;u.硬直中=false;u.飞行浮空=false;
        u.垂直速度=0;u._y=u.Z轴坐标;u.temp_y=0;
        u.remainingImpactForce=0;
    }

    private static function stopInput(u:MovieClip):Void {
        u.动作A=false;u.动作B=false;u.上行=false;u.下行=false;
        u.左行=false;u.右行=false;
        ShootCore.cleanup(u);
    }

    private static function stance(u:MovieClip,mode:String):Void {
        if(u.攻击模式==mode)return;
        stopInput(u);u.换弹中=false;
        u.攻击模式=mode;u.根据模式重新读取武器加成(mode);
        changeState(u,mode+"站立");
        u.__formerSheriff.nextStance=u.__formerSheriff.clock+u.__formerSheriff.tune.stanceFrames;
    }

    public static function pickStance(current:String,distance:Number,p:Object):String {
        if(current=="兵器" && distance<=p.closeExit)return "兵器";
        if(distance<p.closeEnter)return "兵器";
        if(current=="手枪" && distance>=p.farExit)return "手枪";
        return distance>p.farEnter ? "手枪" : "长枪";
    }

    /** shot is consumed rounds, not remaining rounds. Prefer the active gun. */
    public static function missingAmmo(u:MovieClip):String {
        if((u.攻击模式=="长枪" || u.攻击模式=="手枪") && u[u.攻击模式].value.shot>0)return u.攻击模式;
        if(u.长枪.value.shot>0)return "长枪";
        if(u.手枪.value.shot>0)return "手枪";
        return null;
    }

    public static function castSkill(u:MovieClip,name:String):Boolean {
        stopInput(u);ground(u);
        var c:Object=u.__formerSheriff;
        c.action=name;c.actionAge=0;u.技能名=name;u.技能等级=c.tune.skillLevel;
        RoutingLifecycle.ensureTempY(u);
        changeState(u,"技能");RoutingLifecycle.preparePoseAndBonus(u);
        var man:MovieClip=RoutingRuntime.attachMovie(u,"前治安官动作-"+name,"man",0,
            RoutingLifecycle.buildPublicContainerInit(u.container));
        if(!man || man===u.container) {
            c.action=null;animationDone(u);return false;
        }
        RoutingLifecycle.handleFloat(man,u,"技能浮空");
        RoutingLifecycle.bindEndCleanup(man,u,"战技","技能结束","技能浮空");
        bindMotion(man);
        u.位移锁向截止帧=Number(_root.帧计时器.当前帧数)+45;
        // Four-way roll reads NPC intention; it must not read the player's keys.
        if(name=="翻滚换弹") {
            man.攻击时按键四向移动=function(forward:Number,backward:Number):Void {
                var actor:MovieClip=this._parent;
                var context:Object=actor.__formerSheriff;
                Mover.move2DStrict(actor,context.escapeDirection,Math.min(10,backward*.3));
            };
        }
        if(name=="小跳") {
            man.上下跳移动方向=c.hopDirection;
            man.gotoAndPlay("上下跳");
        }
        return true;
    }

    /** Same execution lifecycle, with a native fixed-costume NPC timeline. */
    public static function mountShieldRush(u:MovieClip):MovieClip {
        u.技能名=SheriffShieldRush.NAME;
        RoutingLifecycle.ensureTempY(u);
        changeState(u,"战技");RoutingLifecycle.preparePoseAndBonus(u);
        u.dispatcher.publish("skillStart",u,SheriffShieldRush.NAME);
        var man:MovieClip=RoutingRuntime.attachMovie(u,"前治安官动作-盾冲","man",0,
            RoutingLifecycle.buildPublicContainerInit(u.container));
        if(man) {
            RoutingLifecycle.handleFloat(man,u,"技能浮空");
            RoutingLifecycle.bindEndCleanup(man,u,undefined,"技能结束","技能浮空");
        }
        return man;
    }

    /** Called again by the native first frame after its authored function bodies. */
    public static function bindMotion(man:MovieClip):Void {
        var u:MovieClip=man._parent;
        if(!u.__formerSheriff)return;
        man.攻击时移动=function(slow:Number,fast:Number):Void {
            Mover.move2DStrict(this._parent,this._parent.方向,slow);
        };
        man.攻击时后退移动=function(slow:Number,fast:Number):Void {
            Mover.move2DStrict(this._parent,this._parent.方向=="右"?"左":"右",slow);
        };
        man.攻击时按键四向移动=function(slow:Number,fast:Number):Void {
            var actor:MovieClip=this._parent;
            var context:Object=actor.__formerSheriff;
            var direction:String=context.action=="翻滚换弹" ? context.escapeDirection : actor.方向;
            Mover.move2DStrict(actor,direction,Math.min(10,slow*.3));
        };
        man.攻击时可改变移动方向=function(speed:Number):Void {
            Mover.move2DStrict(this._parent,this._parent.方向,speed);
        };
        man.攻击时斜向移动=man.攻击时移动;
        man.攻击时可斜向改变移动方向=man.攻击时可改变移动方向;
        man.攻击时可斜向改变移动方向2=man.攻击时可改变移动方向;
        man.轻型武器攻击搓招=function():Void {};
        // Complete one three-hit baton sequence. No player key/combo readers.
        man.变招判定=function(next:String,ending:Boolean):Void {
            if(!ending && (next=="棍棒2连招" || next=="棍棒3连招"))this.gotoAndPlay(next);
        };
    }

    private static function react(u:MovieClip,kind:String):Void {
        var c:Object=u.__formerSheriff;var p:Object=c.tune;
        // Interrupted preparation may resume safely, but applied permanent buffs
        // are never cast again. Ordinary attacks can yield to a first reaction.
        if(c.action=="兴奋剂" && u.buffManager.getBuffById("兴奋剂")==null)c.opening=0;
        else if(c.action=="铁布衫" && u.buffManager.getBuffById("铁布衫")==null)c.opening=1;
        stopInput(u);ground(u);
        c.escapeDirection=u.方向=="右" ? "左" : "右";
        if(kind=="rush") {
            if(startRush(u,false)) {c.nextRush=c.clock+p.rushCooldown;return;}
            kind=missingAmmo(u)!=null && c.clock>=c.nextRoll ? "roll" : "hop";
        }
        if(kind=="roll") {
            stance(u,missingAmmo(u));
            if(castSkill(u,"翻滚换弹"))c.nextRoll=c.clock+p.rollCooldown;
        } else {
            c.hopDirection=chooseHopDirection(u);c.hopTravel=0;c.hopTick=-1;
            if(castSkill(u,"小跳"))c.nextHop=c.clock+p.hopCooldown;
        }
    }

    private static function startRush(u:MovieClip,transition:Boolean):Boolean {
        var c:Object=u.__formerSheriff;
        stopInput(u);ground(u);stance(u,"长枪");
        c.action="rush";c.actionAge=0;
        var target:Object=c.target;
        if(target.hp>0)u.方向改变(target._x<u._x ? "左":"右");
        c.rushControl={
            chargeFrames:transition ? c.tune.transitionChargeFrames : c.tune.rushChargeFrames,
            holdAtEnd:transition || c.phase==2, startHeld:c.phase==2,
            parameters:{speedBonus:c.tune.rushSpeedBonus,powerMultiplier:c.tune.rushPowerMultiplier,
                chargedPower:c.tune.rushChargedPower,reduction:c.tune.rushReduction,
                shieldDefenseRatio:c.tune.rushShieldDefenseRatio},
            onHeld:c.phase==2 ? FormerSheriffController.phaseTwoGuard : FormerSheriffController.phaseTwoReady,lane:0
        };
        var ok:Boolean=SheriffShieldRush.releaseNPC(u,c.rushControl);
        if(!ok)c.action=null;
        return ok;
    }

    public static function animationDone(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(c.phase=="transition" || c.finalDeath)return;
        if(c.phase==2){phaseTwoGuard(u);return;}
        c.action=null;c.actionAge=0;
        stopInput(u);ground(u);u.技能名=null;u.换弹中=false;
        if(u.hp<=0) {changeState(u,"倒地");return;}
        u.根据模式重新读取武器加成(u.攻击模式);
        changeState(u,u.攻击模式+"站立");
    }

    public static function isCombatAlly(u:MovieClip,other:Object):Boolean {
        if(other===u || !(other.hp>0) || other._killed || other.element || other.非战斗单位)return false;
        if(other._parent!==u._parent)return false;
        if(u.战斗遭遇ID!=undefined && other.战斗遭遇ID!=u.战斗遭遇ID)return false;
        return other.unitAI!=undefined || other.__formerSheriff!=undefined ||
            (String(other.兵种).indexOf("敌人-")==0);
    }

    private static function sense(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        var enemies:Array=TargetCacheManager.acquireEnemyCache(u,1).data;
        var nearest:Object=null;var best:Number=Number.MAX_VALUE;
        c.nearThreat=false;
        for(var i:Number=0;i<enemies.length;i++) {
            var e:Object=enemies[i];
            if(!(e.hp>0) || e._killed || e.element)continue;
            var dx:Number=Math.abs(u._x-e._x),dz:Number=Math.abs(u.Z轴坐标-e.Z轴坐标);
            var distance:Number=dx+2*dz;
            if(distance<best){best=distance;nearest=e;}
            if(dx<c.tune.safeDistance && dz<70)c.nearThreat=true;
        }
        c.target=nearest;
        var allies:Array=TargetCacheManager.acquireAllyCache(u,1).data;
        var alone:Boolean=true;
        for(i=0;i<allies.length;i++)if(isCombatAlly(u,allies[i])){alone=false;break;}
        applyLoneWolf(u,alone);
    }

    public static function applyLoneWolf(u:MovieClip,alone:Boolean):Void {
        var c:Object=u.__formerSheriff;
        if(c.lone===alone)return;
        var hp:Number=u.hp;
        c.lone=alone;
        if(alone) {
            var p:Object=c.tune;
            u.buffManager.addBuffImmediate(new MetaBuff([
                new PodBuff("空手攻击力",BuffCalculationType.MULTIPLY,p.loneAttack),
                new PodBuff("防御力",BuffCalculationType.MULTIPLY,p.loneDefense),
                new PodBuff("hp满血值",BuffCalculationType.MULTIPLY,p.loneHealth)
            ],[],0),LONE_BUFF);
        } else {
            u.buffManager.removeBuff(LONE_BUFF);u.buffManager.update(0);
        }
        // Current HP is never granted again when the encounter roster changes.
        u.hp=Math.min(hp,u.hp满血值);
        u.__独行者生效=alone;
    }

    private static function beginTransition(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        c.pendingTransition=false;c.pendingReaction=null;c.action="transition";c.age=0;
        stopInput(u);
        if(u.__sheriffShieldRush)SheriffShieldRush.cleanup(u.__sheriffShieldRush);
        ground(u);u.无敌=true;u.换弹中=false;
        c.transitionStep="air";
        changeState(u,"转阶段击倒");u.man.gotoAndStop(1);
        // Use the SAME airborne integrator and landing callback as normal knockdown.
        // Transition state guards intercept its final 倒地 without exposing death.
        startFall(u);
    }

    private static function flyHelmet(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(c.helmetFlown)return;
        c.helmetFlown=true;
        var point:Object={x:0,y:-160};
        // Root rig height is 175 normalized by the common unit initializer.
        point.y=u.area.getBounds(u).yMin+30;
        u.localToGlobal(point);c.world.globalToLocal(point);
        // Use the same fragment engine as map debris and humanoid weapon drops.
        // A separate carrier keeps the ground plane fixed while the NPC moves.
        var carrier:MovieClip=c.world.createEmptyMovieClip(
            "前治安官飞盔_"+u._name,c.world.getNextHighestDepth());
        carrier._x=point.x;carrier._y=u.Z轴坐标;
        var fragments:MovieClip=carrier.createEmptyMovieClip("fragments",0);
        var prop:MovieClip=fragments.attachMovie("特勤飞盔","helmet1",0,
            {_x:0,_y:point.y-carrier._y,_xscale:100,_yscale:100});
        if(prop) {
            var config:FragmentConfig=new FragmentConfig();
            config.fragmentCount=1;config.collisionProbability=0;config.massScale=200;
            config.groundY=u.Z轴坐标-carrier._y;
            config.direction=u.方向=="右" ? -1 : 1;
            config.baseVelocityX=3.5;config.velocityXRange=0;
            config.velocityYMin=6;config.velocityYMax=6;
            config.rotationRange=12;config.gravity=.5;
            config.bounce=.22;config.friction=.75;
            carrier.animationId=FragmentAnimator.startAnimation(fragments,"helmet",config);
            carrier.advanceFragment=fragments.onEnterFrame;
            delete fragments.onEnterFrame;
            carrier.ownerWorld=c.world;carrier.age=0;
            carrier.onUnload=function():Void {FragmentAnimator.stopAnimation(this.animationId);};
            // The adapter only owns pause, scene retirement and visual lifetime.
            // Flight, rebound, friction and the final stop belong to the engine.
            carrier.onEnterFrame=function():Void {
                if(_root.gameworld!==this.ownerWorld){this.removeMovieClip();return;}
                if(_root.暂停)return;
                this.age++;
                if(FragmentAnimator.isAnimationRunning(this.animationId))
                    this.advanceFragment.call(this.fragments);
                if(this.age>180)this._alpha-=4;
                if(this._alpha<=0)this.removeMovieClip();
            };
            c.helmet=carrier;
        } else carrier.removeMovieClip();
        // Both visual states are authored. No equipment refresh or attachment.
        c.head.gotoAndStop(2);
    }

    private static function transitionTick(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        u.无敌=true;
        if(c.pendingTransition){beginTransition(u);return;}
        c.age++;
        if(c.transitionStep=="air") {
            u.man.gotoAndStop(Math.min(c.tune.knockdownFrames,c.age+1));
            if(c.age==2)flyHelmet(u);
        } else if(c.transitionStep=="land") {
            u.man.gotoAndStop(Math.min(c.tune.landingFrames,c.age+1));
            if(c.age>=c.tune.landingFrames+c.tune.groundPause) {
                c.transitionStep="up";c.age=0;
                changeState(u,"转阶段起身");u.man.gotoAndStop(1);
            }
        } else if(c.transitionStep=="up") {
            u.man.gotoAndStop(Math.min(c.tune.getupFrames,c.age+1));
            if(c.age>=c.tune.getupFrames) {
                c.transitionStep="rush";c.age=0;
                if(!startRush(u,true)) {
                    c.transitionStep="error";c.error="missing shield rush asset";
                    trace("[FormerSheriff] transition failed: "+c.error);
                }
            }
        }
    }

    public static function phaseTwoReady(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(c.phase!="transition" || c.phaseTwoEntered)return;
        c.phaseTwoEntered=true;c.phase=2;c.action="shield";c.age=0;
        c.hp=Math.max(1,Math.round(u.hp满血值*c.tune.secondLifeRatio));
        // A fatal terminal write may interrupt the roll's temporary invulnerability.
        // Its end frame no longer runs, so never carry that transient flag forward.
        u.无敌=false;u.__前治安官阶段=2;
        u.dispatcher.publish("formerSheriffPhaseTwo",u);
        phaseTwoGuard(u);
        if(typeof u.前治安官二阶段接管=="function")u.前治安官二阶段接管(u);
    }

    public static function tick(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(!c || !c.ready || c.world!==_root.gameworld || _root.暂停)return;
        c.clock++;
        EquipmentLightController.tick(c.light);
        if(c.action=="rush" && c.rushControl) {
            var offset:Number=c.target.Z轴坐标-u.Z轴坐标;
            c.rushControl.lane=c.target.hp>0 && Math.abs(offset)>c.tune.laneTolerance ? (offset<0?-1:1):0;
        }
        if(c.phase=="transition"){transitionTick(u);return;}
        if(c.phase==2) {
            if(c.finalDeath || u.hp<=0){finalDeathTick(u);return;}
            if(c.clock>=c.nextSense){sense(u);c.nextSense=c.clock+c.tune.senseFrames;}
            phaseTwoTick(u);return;
        }
        if(u.hp<=0)return;
        if(c.pendingReaction){afterHit(u);return;}
        if(c.clock>=c.nextSense) {
            sense(u);c.nextSense=c.clock+c.tune.senseFrames;
        }
        if(c.action) {
            c.actionAge++;
            // A routing failure must be visible, not silently masquerade as AI idle.
            if(c.actionAge>360 && c.action!="rush") {
                trace("[FormerSheriff] action timeout "+c.action);
                animationDone(u);
            }
            return;
        }
        var target:Object=c.target;
        if(!c.nearThreat && c.opening<2) {
            var name:String=c.opening==0 ? "兴奋剂" : "铁布衫";
            if(castSkill(u,name))c.opening++;
            return;
        }
        if(!target || !(target.hp>0)) {stopInput(u);changeState(u,u.攻击模式+"站立");return;}
        var dx:Number=target._x-u._x,dz:Number=target.Z轴坐标-u.Z轴坐标;
        var distance:Number=Math.abs(dx),lane:Number=Math.abs(dz);
        u.方向改变(dx<0 ? "左" : "右");
        if(u.换弹中 || u.man.换弹标签)return;
        var missing:String=missingAmmo(u);
        if(missing!=null && !c.nearThreat && distance>c.tune.reloadDistance && lane>c.tune.reloadLane) {
            stance(u,missing);
            if(typeof u.man.开始换弹=="function"){stopInput(u);u.man.开始换弹();}
            return;
        }
        if(c.clock>=c.nextStance)stance(u,pickStance(u.攻击模式,distance,c.tune));
        if(u.攻击模式=="兵器") {
            stopInput(u);
            if(distance<c.tune.closeExit && lane<c.tune.laneTolerance && c.clock>=c.nextBaton) {
                c.action="baton";c.actionAge=0;c.nextBaton=c.clock+c.tune.batonFrames;
                u.兵器攻击名=_root.兵器攻击路由.获取普攻连招首帧标签(u);
                changeState(u,"兵器攻击");
                var baton:MovieClip=RoutingRuntime.attachMovie(u,"前治安官动作-棍棒","man",0,
                    _root.兵器攻击路由.构建兵器攻击容器初始化对象(u.container));
                if(!baton){animationDone(u);return;}
                RoutingIntent.bindContainerEndState(baton,u,RoutingIntent.SMALL_END_WEAPON);
                bindMotion(baton);baton.gotoAndPlay(u.兵器攻击名);
                return;
            }
        }
        // Align Z while not firing; firearms can then strafe horizontally.
        if(lane>c.tune.laneTolerance) {
            stopInput(u);changeState(u,u.攻击模式+"行走");
            Mover.move2DStrict(u,dz<0?"上":"下",u.行走Y速度);
            if(distance>c.tune.farEnter)Mover.move2DStrict(u,u.方向,u.行走X速度);
            return;
        }
        if(u.攻击模式=="兵器") {
            changeState(u,"兵器行走");Mover.move2DStrict(u,u.方向,u.行走X速度);return;
        }
        var desired:Number=u.攻击模式=="长枪" ? 195 : 360;
        var moving:Boolean=Math.abs(distance-desired)>35;
        var moveDirection:String=distance>desired ? u.方向 : (u.方向=="左" ? "右":"左");
        changeState(u,u.攻击模式+(moving?"行走":"站立"));
        if(moving)Mover.move2DStrict(u,moveDirection,u.行走X速度*.65);
        u.动作A=true;
        if(typeof u.man.开始射击=="function")u.man.开始射击();
    }

    /** Fixed native actions. The thinker owns the playhead, so pause, hit
     * cancellation and terminal HP cannot emit a stale shot or melee event. */
    public static function phaseTwoGuard(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(c.phase!=2 || u.hp<=0 || c.finalDeath)return;
        if(u.__sheriffShieldRush)SheriffShieldRush.cleanup(u.__sheriffShieldRush);
        c.followup=null;c.phaseTwoReadyAt=c.clock+c.tune.phaseTwoRest;
        mountPhaseTwo(u,"持盾待机");
    }

    public static function mountPhaseTwo(u:MovieClip,action:String):MovieClip {
        var c:Object=u.__formerSheriff;
        stopInput(u);ground(u);u.换弹中=false;u.技能名=null;
        EquipmentLightController.clearActionVisual(u,"长枪",c);
        if(u.man.__isDynamicMan===true)u.man.removeMovieClip();
        c.action=action;c.actionAge=1;
        // The transformed long gun remains deployed as the shield, including
        // its equipment light. Pistol fire below supplies its explicit slot;
        // neither generic shooting input nor player item bonuses run here.
        u.攻击模式="长枪";
        u.根据模式重新读取武器加成(u.攻击模式);
        changeState(u,"持盾");
        var man:MovieClip=RoutingRuntime.attachMovie(u,"前治安官动作-"+action,"man",0,
            RoutingLifecycle.buildPublicContainerInit(u.container));
        if(!man) {trace("FormerSheriff missing phase-two action: "+action);return null;}
        man.gotoAndStop(1);bindMotion(man);
        if(action=="持盾射击")
            c.pistolProps=ShootInitCore.generateBulletProps(u,"手枪",u.手枪属性,{});
        phaseTwoLight(u);
        return man;
    }

    private static function phaseTwoLight(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        EquipmentLightController.setActionVisual(u,"长枪",c,u.man.盾具,null);
    }

    public static function phaseTwoTick(u:MovieClip):Void {
        var c:Object=u.__formerSheriff,p:Object=c.tune,target:MovieClip=c.target;
        if(c.action=="rush")return;
        // Named children of a freshly attached native pose settle next frame.
        phaseTwoLight(u);
        if(c.pendingReaction=="phaseTwoRush"){afterHit(u);return;}
        var active:Boolean=target && target.hp>0;
        var dx:Number=active ? target._x-u._x : 0;
        var dz:Number=active ? target.Z轴坐标-u.Z轴坐标 : 0;
        var distance:Number=Math.abs(dx),lane:Number=Math.abs(dz);
        var action:String=c.action;
        if(action=="盾击" || action=="持盾刺击" || action=="持盾射击") {
            // Aim during the draw only. No mirroring a planted impact mid-swing.
            if(active && (c.actionAge<12 || (action=="持盾射击" && c.actionAge<86)))u.方向改变(dx<0?"左":"右");
            var frame:Number=c.actionAge+1;
            if(action=="持盾射击") {
                if(frame==26 && u.手枪.value.shot>=u.手枪弹匣容量)frame=86;
                // One complete recoil cycle per remaining round. The accepted
                // 8-round art is also valid for a partially used phase-one gun.
                if(frame==34)frame=u.手枪.value.shot<u.手枪弹匣容量 ? 26:86;
            }
            c.actionAge=frame;u.man.gotoAndStop(frame);phaseTwoLight(u);
            if(action=="盾击" && frame==16)phaseTwoImpact(u,false);
            if(action=="持盾刺击" && (frame==24 || frame==36 || frame==48))phaseTwoImpact(u,true);
            if(action=="持盾射击") {
                if(frame==26) {
                    c.pistolProps.子弹威力=u.空手攻击力*p.phaseTwoPistolPower;
                    u.__pendingFireInterval=8*1000/30;
                    WeaponFireCore.PISTOL_SHOOT.call(u,u.man.手持武器.枪口位置,c.pistolProps);
                }
                // NPC-owned magazine only; never SkillReloadCore.reloadWeapon,
                // which is the player inventory transaction entry.
                if(frame==86)u.换弹中=true;
                if(frame==110){u.手枪.value.shot=0;u.换弹中=false;c.phaseTwoReloads=(c.phaseTwoReloads||0)+1;}
            }
            if(frame>=u.man._totalframes) {
                var follow:String=action=="盾击" && active ? (distance<=p.phaseTwoKnifeRange && lane<=p.laneTolerance ? "持盾刺击":"持盾射击") : null;
                phaseTwoGuard(u);c.followup=follow;
            }
            return;
        }
        if(!active) {
            if(action!="持盾待机")mountPhaseTwo(u,"持盾待机");
            return;
        }
        u.方向改变(dx<0?"左":"右");
        if(lane>p.laneTolerance || distance>p.phaseTwoPistolRange) {
            if(action!="持盾冲刺")mountPhaseTwo(u,"持盾冲刺");
            c.actionAge++;u.man.gotoAndStop(14+(Math.floor(c.actionAge/2)%16));
            if(lane>p.laneTolerance)Mover.move2DStrict(u,dz<0?"上":"下",u.行走Y速度*p.phaseTwoMoveRatio);
            if(distance>p.phaseTwoPistolRange)Mover.move2DStrict(u,u.方向,u.行走X速度*p.phaseTwoMoveRatio);
            phaseTwoLight(u);return;
        }
        if(action!="持盾待机")mountPhaseTwo(u,"持盾待机");
        if(c.clock<c.phaseTwoReadyAt)return;
        var next:String=c.followup;
        c.followup=null;
        if(next=="持盾刺击" && distance>p.phaseTwoKnifeRange)next="持盾射击";
        if(!next)next=distance<=p.phaseTwoBashRange ? "盾击":"持盾射击";
        mountPhaseTwo(u,next);
    }

    private static function phaseTwoImpact(u:MovieClip,knife:Boolean):Void {
        var c:Object=u.__formerSheriff,man:MovieClip=u.man;
        if(c.phase!=2 || u.hp<=0 || c.finalDeath)return;
        // Unit-space reach transformed through the actual root/man hierarchy,
        // including mirrored and scaled NPCs. Standard bullet settlement owns
        // hit, armor, toughness, allied filtering and death accounting.
        var a:Object={x:10,y:-125},z:Object={x:knife?115:105,y:-38};
        u.localToGlobal(a);u.localToGlobal(z);man.globalToLocal(a);man.globalToLocal(z);
        var area:MovieClip=man.createEmptyMovieClip("二阶段命中区",man.getNextHighestDepth());
        area._visible=false;area.beginFill(0,0);area.moveTo(a.x,a.y);
        area.lineTo(z.x,a.y);area.lineTo(z.x,z.y);area.lineTo(a.x,z.y);area.lineTo(a.x,a.y);area.endFill();
        var props:Object=_root.子弹属性初始化(area,"近战子弹",u);
        props.子弹威力=knife ? u.空手攻击力*c.tune.phaseTwoKnifePower : u.防御力*c.tune.phaseTwoBashPower;
        props.霰弹值=1;props.子弹散射度=0;props.子弹速度=0;props.区域定位area=area;
        props.shootZ=u.Z轴坐标;props.Z轴攻击范围=c.tune.laneTolerance+8;
        // This field divides impact force: zero means guaranteed toughness
        // break, not zero knockdown chance. Stabs accumulate ordinary impact.
        props.击倒率=Math.max(1,knife ? c.tune.phaseTwoKnifeImpact:c.tune.phaseTwoBashImpact);
        props.水平击退速度=knife ? 1:5;props.垂直击退速度=0;
        props.击中地图效果="";props.击中后子弹的效果=knife ? "刀光":"空手攻击火花";
        _root.子弹区域shoot传递(props);
        c.phaseTwoHits=(c.phaseTwoHits||0)+1;
    }

    public static function beginFinalDeath(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(c.finalDeath || c.phase!=2 || !(c.finalFatalHP<=0 || u.hp<=0))return;
        if(c.finalFatalHP==undefined)c.finalFatalHP=Math.min(0,u.hp);
        c.hp=1;
        // A lethal hit may share the frame that attached a new guard/action.
        // Freeze intent now; its named native children become valid next tick.
        c.finalDeath=true;c.finalStep="pending";c.age=0;c.action="death";c.pendingReaction=null;
        c.deathFolded=Math.random()<c.tune.deathFoldChance;
        stopInput(u);u.换弹中=false;
        EquipmentLightController.clearActionVisual(u,"长枪",c);
        if(u.__sheriffShieldRush)SheriffShieldRush.cleanup(u.__sheriffShieldRush);
    }

    private static function dropFinalShield(u:MovieClip):Void {
        var c:Object=u.__formerSheriff,world:MovieClip=c.world;
        var carrier:MovieClip=world.createEmptyMovieClip(u._name+"_finalShield",world.getNextHighestDepth());
        carrier._x=u._x;carrier._y=u.Z轴坐标;
        var fragments:MovieClip=carrier.createEmptyMovieClip("fragments",0);
        var piece:MovieClip=fragments.attachMovie("前治安官落盾","shield1",0);
        var prop:MovieClip=u.man.盾具;
        var origin:Object={x:60,y:250},axisX:Object={x:61,y:250},axisY:Object={x:60,y:251};
        prop.localToGlobal(origin);prop.localToGlobal(axisX);prop.localToGlobal(axisY);
        world.globalToLocal(origin);world.globalToLocal(axisX);world.globalToLocal(axisY);
        piece.transform.matrix=new flash.geom.Matrix(axisX.x-origin.x,axisX.y-origin.y,
            axisY.x-origin.x,axisY.y-origin.y,origin.x-carrier._x,origin.y-carrier._y);
        piece.gotoAndStop(1);
        var config:FragmentConfig=new FragmentConfig();
        config.fragmentCount=1;config.collisionProbability=0;config.massScale=200;config.groundY=0;
        config.direction=u.方向=="左"?1:-1;
        config.baseVelocityX=2;config.velocityXRange=0;config.velocityYMin=4;config.velocityYMax=4;
        config.rotationRange=5;config.gravity=.6;config.bounce=.16;config.friction=.8;
        carrier.animationId=FragmentAnimator.startAnimation(fragments,"shield",config);
        carrier.engineStep=fragments.onEnterFrame;delete fragments.onEnterFrame;
        carrier.world=world;carrier.age=0;carrier.fold=c.deathFolded;
        carrier.onEnterFrame=function():Void {
            if(_root.gameworld!==this.world){this.removeMovieClip();return;}
            if(_root.暂停)return;
            this.age++;
            if(this.fold && this.age<=15)this.fragments.shield1.gotoAndStop(this.age);
            if(FragmentAnimator.isAnimationRunning(this.animationId)) {
                if(this.engineStep!=undefined)this.engineStep.call(this.fragments);
                delete this.fragments.onEnterFrame;
            }
            if(this.age>210){this._alpha-=4;if(this._alpha<=0)this.removeMovieClip();}
        };
        carrier.onUnload=function():Void{FragmentAnimator.stopAnimation(this.animationId);};
        c.finalShield=carrier;
    }

    /** Own the shared physics outside replaceable timeline poses. AVM1 flushes
     * their unload handlers after enterFrame; attaching the fall to that `man`
     * can immediately retire the new knockback source and strand the actor. */
    private static function startFall(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(c.fallOwner==undefined)c.fallOwner=u.createEmptyMovieClip("__formerSheriffFall",10001);
        // This private, empty carrier has no other unload work. Avoid stacking
        // the shared helper's cleanup wrapper across the two terminal falls.
        delete c.fallOwner.onUnload;
        _root.启动被击飞浮空(c.fallOwner,u);
    }

    private static function finalDeathTick(u:MovieClip):Void {
        var c:Object=u.__formerSheriff;
        if(!c.finalDeath)beginFinalDeath(u);
        if(c.finalStep=="pending") {
            dropFinalShield(u);c.finalStep="air";c.age=0;
            ground(u);changeState(u,"转阶段击倒");u.man.gotoAndStop(1);
            startFall(u);return;
        }
        if(c.finalFinished)return;
        c.age++;
        if(c.finalStep=="air")u.man.gotoAndStop(Math.min(c.tune.knockdownFrames,c.age));
        else if(c.finalStep=="land") {
            u.man.gotoAndStop(Math.min(c.tune.landingFrames,c.age));
            if(c.age>=c.tune.landingFrames+c.tune.groundPause) {
                c.finalFinished=true;
                c.hp=c.finalFatalHP;
                if(!u._killed)KillEventComponent.onKill(u);
                if(c.finalShooter._parent===c.world)
                    c.finalShooter.dispatcher.publish("enemyKilled",u,c.finalBullet);
                c.finalShooter=null;c.finalBullet=null;
                u.死亡检测();
            }
        }
    }

}
