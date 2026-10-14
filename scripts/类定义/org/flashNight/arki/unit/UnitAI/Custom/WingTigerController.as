import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;
import org.flashNight.arki.component.StatHandler.ImpactHandler;

/** 翅虎专用受身。原招式、伤害及死亡结算仍由原生单位负责。
 * 计时跨越被击/击倒/倒地，不因后续命中归零；只推进有效战斗帧。
 * 受身不修改 HP、不提供无敌，蓝红阵营共享同一机制，NPC 不启用。
 */
class org.flashNight.arki.unit.UnitAI.Custom.WingTigerController {
    public static var KIND:String = "敌人-飞刀小子";
    public static function install(root:Object):Void {
        root.翅虎初始化 = function(u:MovieClip):Void {WingTigerController.initialize(u);};
        root.翅虎烟雾动画加载 = function(man:MovieClip):Void {WingTigerController.bindMotion(man);};
        root.翅虎烟雾退场 = function(u:MovieClip):Void {
            if(u.__wingTiger && u.hp <= 0 && u.死亡动画 == "a1")
                WingTigerController.changeState(u,"血腥死");
        };
    }
    public static function defaults():Object {
        return {controlFrames:48,cooldownFrames:240,freeFrames:8,guardFrames:8,
            entryFrames:24,retreatFrames:24};
    }
    public static function initialize(u:MovieClip):Void {
        if(u.__wingTiger || u.NPC || u.兵种 != KIND) return;
        var p:Object=defaults();
        for(var key:String in p) {
            var n:Number=Number(u.翅虎参数[key]);
            if(isFinite(n) && n > 0) p[key]=Math.max(1,Math.floor(n));
        }
        var c:Object={world:u._parent,tune:p,clock:0,controlled:0,free:0,cooldown:0,
            guard:0,recoveries:0,phase:"active",phaseAge:0,finished:false,
            originalState:u.状态改变,entryInvincible:u.无敌,lastFrame:-1};
        u.__wingTiger=c;
        u.状态改变=function(next:String):Void {WingTigerController.changeState(this,next);};
        c.unloadCallback=ownedUnload(c);
        if(u.dispatcher) u.dispatcher.subscribe("unload",c.unloadCallback,u);
        if(u.状态 == "登场" && u.登场动画 == "a0") {
            c.phase="entry";u.无敌=true;
        }
        bindThinker(u,u);
    }
    private static function ownedUnload(identity:Object):Function {
        return function():Void {
            // AVM1 的旧 MovieClip 引用可能重指同路径新单位；只清理原组件身份。
            if(this.__wingTiger === identity) WingTigerController.dispose(this);
        };
    }
    private static function bindThinker(u:MovieClip,host:MovieClip):Void {
        var c:Object=u.__wingTiger;
        if(c.thinker._parent === host) return;
        // 不在自身 enterFrame 中删除当前载体；旧 man 随外层跳帧自然卸载。
        if(c.thinker && c.thinker._parent) delete c.thinker.onEnterFrame;
        var t:MovieClip=host.createEmptyMovieClip("__wingTigerThink",host.getNextHighestDepth());
        t.ownerUnit=u;
        t.onEnterFrame=function():Void {WingTigerController.tick(this.ownerUnit);};
        c.thinker=t;
    }
    public static function bindMotion(man:MovieClip):Void {
        var u:MovieClip=man._parent;
        if(!u.__wingTiger) initialize(u);
        var c:Object=u.__wingTiger;
        if(!c) {u.动画完毕();return;}
        man.stop();man.body.stop();man.smoke.__wingTigerManual=true;man.smoke.stop();
        c.motion=man;
        // death 事件会移除单位的其它直接子元件；退场观察者置于保留的 man 内。
        bindThinker(u,man);
        if(u.状态 == "烟雾退场") {
            c.phase="retreat";man.body._alpha=100;
        } else {
            c.phase="entry";u.无敌=true;man.body._alpha=0;
        }
        man.smoke.gotoAndStop(1);
    }
    public static function changeState(u:MovieClip,next:String):Void {
        var c:Object=u.__wingTiger;
        if(!c || c.finished) return;
        if(u.hp <= 0 && u.死亡动画 == "a1") {
            if(c.phase != "retreat") {
                releaseGuard(u);endEntry(u);clearImpactMotion(u);
                c.phase="retreat";c.phaseAge=0;c.controlled=0;
                c.originalState.call(u,"烟雾退场");
            }
            return;
        }
        if(c.phase == "entry" && next != "登场") {
            endEntry(u);c.phase="active";
            bindThinker(u,u);
        }
        c.originalState.call(u,next);
    }
    private static function endEntry(u:MovieClip):Void {
        var c:Object=u.__wingTiger;
        if(c.phase == "entry") u.无敌=c.entryInvincible;
    }
    private static function clearImpactMotion(u:MovieClip):Void {
        var ids:Array=["flyID","stiffID","knockStiffID"];
        for(var i:Number=0;i<ids.length;i++) {
            var key:String=ids[i];
            if(u[key] != null) EnhancedCooldownWheel.I().removeTask(u[key]);
            u[key]=null;
        }
        // 原版翅虎只在被击移动中使用单位 onEnterFrame；观察者另有私有子元件。
        delete u.onEnterFrame;
        u.speed=0;u.减速度=0;u.硬直中=false;u.浮空=false;u.倒地=false;
        u.垂直速度=0;u.temp_y=0;
        u._y=u.Z轴坐标;
        u.remainingImpactForce=0;u.impactDecayBaseForce=0;
        ImpactHandler.refreshImpactDerived(u);
        u.aabbCollider.updateFromUnitArea(u);
    }
    private static function beginGuard(u:MovieClip):Void {
        var c:Object=u.__wingTiger;
        c.guard=c.tune.guardFrames;c.previousImmune=u.免疫击退;
        c.guardIdentity={};c.previousRigidTag=u.man.刚体标签;
        u.免疫击退=true;
        u.man.__wingTigerGuard=c.guardIdentity;u.man.刚体标签=true;
        c.previousFacingDeadline=u.位移锁向截止帧;
        c.facingDeadline=Number(_root.帧计时器.当前帧数)+(c.move == "a2" ? 86 : 33);
        u.位移锁向截止帧=c.facingDeadline;
    }
    private static function releaseGuard(u:MovieClip):Void {
        var c:Object=u.__wingTiger;
        if(c.guardIdentity == undefined) return;
        if(u.man.__wingTigerGuard === c.guardIdentity) {
            u.man.刚体标签=c.previousRigidTag;delete u.man.__wingTigerGuard;
        }
        u.免疫击退=c.previousImmune;
        c.guard=0;delete c.guardIdentity;
    }
    private static function releaseFacing(u:MovieClip):Void {
        var c:Object=u.__wingTiger;
        if(c.facingDeadline != undefined && u.位移锁向截止帧 === c.facingDeadline)
            u.位移锁向截止帧=c.previousFacingDeadline;
        delete c.facingDeadline;
    }
    public static function recover(u:MovieClip):Void {
        var c:Object=u.__wingTiger;
        if(!c || !(u.hp > 0) || u._killed || u._deInitialized || c.cooldown > 0
                || c.phase != "active" || u._封印冻结 || u._warlordActionAiHeld) return;
        clearImpactMotion(u);
        var target:MovieClip=c.world[u.攻击目标];
        if(target._parent === c.world && target.hp > 0) {
            u.方向改变(target._x < u._x ? "左" : "右");
            c.move=LinearCongruentialEngine.instance.random(2) == 0 ? "a1" : "a2";
        } else {
            c.move="a1"; // 无存活目标仍可后撤，不借用玩家控制目标。
        }
        c.cooldown=c.tune.cooldownFrames;c.controlled=0;c.free=0;c.recoveries++;
        u.attachMovie("翅虎烟雾","__wingTigerSmoke"+c.recoveries,u.getNextHighestDepth(),
            {_xscale:70,_yscale:70,_y:-20});
        u.近战招式=c.move;
        // 走外层入口，让近战容器重新装载并获取已有的出招霸体。
        c.originalState.call(u,"近战");
        beginGuard(u);
    }
    public static function tick(u:MovieClip):Void {
        var c:Object=u.__wingTiger;
        if(!c || c.finished || u._parent !== c.world || c.world !== _root.gameworld || _root.暂停) return;
        var frame:Number=Number(_root.帧计时器.当前帧数);
        if(isFinite(frame) && frame === c.lastFrame) return;
        c.lastFrame=frame;c.clock++;
        if(c.phase == "entry" || c.phase == "retreat") {
            if(c.phase == "entry" && !(u.hp > 0)) {
                changeState(u,"血腥死");return;
            }
            c.phaseAge++;
            var total:Number=c.phase == "entry" ? c.tune.entryFrames : c.tune.retreatFrames;
            var ratio:Number=c.phaseAge/total;
            c.motion.smoke.gotoAndStop(Math.min(26,1+Math.floor(ratio*25)));
            if(c.phase == "entry") c.motion.body._alpha=Math.min(100,Math.max(0,(ratio-.25)*200));
            else c.motion.body._alpha=Math.max(0,100-ratio*180);
            if(c.phaseAge < total) return;
            if(c.phase == "retreat") {
                c.finished=true;releaseFacing(u);
                // 原死亡入口负责经验、掉落、计数及卸载；撤退只取消尸体贴图。
                u.死亡检测({noCorpse:true});return;
            }
            endEntry(u);c.phase="active";c.phaseAge=0;
            bindThinker(u,u);
            c.originalState.call(u,u.攻击模式+"站立");
            // 帧跳转会卸载 man 的执行上下文；所有后续工作交给站立后的观察者。
            return;
        }
        if(!(u.hp > 0) || u._killed || u._deInitialized) {
            releaseGuard(u);releaseFacing(u);c.controlled=0;
            if(u.hp <= 0 && u.死亡动画 == "a1") changeState(u,"血腥死");
            return;
        }
        if(c.thinker._parent !== u) bindThinker(u,u);
        if(c.cooldown > 0) c.cooldown--;
        if(c.guard > 0) {
            c.guard--;
            if(c.guard == 0 || u.状态 != "近战") releaseGuard(u);
        }
        if(c.facingDeadline != undefined && u.状态 != "近战") releaseFacing(u);
        if(u._封印冻结 || u._warlordActionAiHeld || u.状态 == "被投") return;
        if(u.状态 == "被击" || u.状态 == "击倒" || u.状态 == "倒地") {
            c.free=0;c.controlled++;
            if(c.controlled >= c.tune.controlFrames && c.cooldown == 0) recover(u);
        } else {
            if(++c.free >= c.tune.freeFrames) c.controlled=0;
        }
    }
    public static function dispose(u:MovieClip):Void {
        var c:Object=u.__wingTiger;
        if(!c) return;
        releaseGuard(u);releaseFacing(u);endEntry(u);
        c.finished=true;
        if(c.thinker && c.thinker._parent) c.thinker.removeMovieClip();
    }
}
