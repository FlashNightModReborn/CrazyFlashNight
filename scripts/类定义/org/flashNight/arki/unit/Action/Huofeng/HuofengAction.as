import org.flashNight.arki.unit.Action.Huofeng.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.arki.spatial.move.Mover;

/** 动作时间由未暂停帧推进；独立令牌隔离同名 man 重建和旧碰撞队列。 */
class org.flashNight.arki.unit.Action.Huofeng.HuofengAction {
    private static var NORMAL_OFFSETS:Array=[0,15,27,41,61];
    private static var retiredSerial:Number=0;

    public static function begin(runtime:HuofengSetRuntime,kind:String,tier:Number):Boolean {
        var unit:MovieClip=runtime.getUnit();
        if (!runtime.isActive() || !(unit.hp>0)) return false;
        runtime.cancelAction(false);
        var state:Object=runtime.getState();
        var action:Object={kind:kind,tier:tier,serial:++state.actionSequence,cancelled:false,
            frame:0,stage:0,localFrame:0,lastTick:-1,pendingTicks:0,watchdog:0,
            recovery:0,normalBridge:false,cycle:0,secondLoop:false,firstHit:false,direction:unit.方向,owner:runtime};
        if (kind==="nirvana" && state.pendingNirvanaTier===tier) action.paidSequence=state.pendingReviveSequence;
        runtime.setAction(action);
        if (kind==="nirvana") unit.__huofengNirvana=action;
        unit.格斗架势=true;
        RoutingIntent.suppressOldManUnload(unit);
        var logical:String=kind==="normal" ? "空手攻击" : (kind==="run" ? "空手冲击" : "战技");
        RoutingIntent.triggerStateTransitionJob(unit,logical,"容器",HuofengAction.attach,"容器");
        // 状态跳转之后的收尾由 class 回调接管，不能依赖被跳走帧脚本继续执行。
        return true;
    }

    public static function attach(unit:MovieClip):Void {
        var runtime:HuofengSetRuntime=unit.__huofeng;
        var action:Object=runtime.getAction();
        if (action==null || action.cancelled || !runtime.isActive()) return;
        var linkage:String;
        if (action.kind==="normal") linkage="火凤套装_五段普攻";
        else if (action.kind==="run") linkage="火凤套装_位移扫击";
        else if (action.kind==="spin") linkage="火凤套装_焰链回旋";
        else linkage=action.tier==1 ? "火凤套装_普通涅槃" : "火凤套装_完整涅槃";
        var init:Object=ContainerInitScratch.getWeapon(unit.container);
        var man:MovieClip=RoutingRuntime.attachMovie(unit,linkage,"man",0,init);
        if (man==undefined) {
            cancel(runtime,action,false);
            RoutingLifecycle.recoverMissingSkillContainer(unit);
            return;
        }
        action.man=man;
        man.__huofengAction=action;
        man.__huofengOwner=runtime;
        man.无敌标签=action.kind==="nirvana";
        man.stop();
        // MovieClip references can alias a replacement at the same path.
        // Queued callbacks retain this ordinary token, never reread a new man.
        var attachedAction:Object=action;
        man.onEnterFrame=function():Void {
            if (this.__huofengAction===attachedAction) HuofengAction.tick(this);
        };
        man.onUnload=function():Void { HuofengAction.unload(attachedAction); };
        // R2 的飞升只发生在画面局部；单位世界 X/Z 和碰撞基线不移动。
        if (action.kind==="nirvana") {
            action.anchorX=unit._x;
            action.anchorZ=unit.Z轴坐标;
        }
    }

    public static function ownsMan(unit:Object,action:Object):Boolean {
        return action!=null && !action.cancelled && unit.man.__huofengAction===action;
    }

    public static function unload(action:Object):Void {
        if (action==null) return;
        action.cancelled=true;
        action.owner.clearAction(action);
    }

    public static function cancel(runtime:HuofengSetRuntime,action:Object,recover:Boolean):Void {
        if (action==null || action.cancelled) { runtime.clearAction(action); return; }
        var unit:MovieClip=runtime.getUnit();
        var owned:Boolean=ownsMan(unit,action);
        var man:MovieClip=action.man;
        // A same-name timeline body can shadow the dynamic action at depth 0.
        if (man.__huofengAction!==action) man=unit.getInstanceAtDepth(0);
        action.cancelled=true;
        runtime.clearAction(action);
        if (man.__huofengAction===action && man._parent===unit) {
            man.无敌标签=false;delete man.onEnterFrame;
            if (!(unit.hp>0) || !owned) retireMan(man);
        }
        if (owned && recover && unit.hp>0) RoutingLifecycle.recoverMissingSkillContainer(unit);
    }

    /** Call only after checking the action/snapshot owner token. Renaming
     * avoids AVM1 resolving a delayed unload through the replacement body. */
    public static function retireMan(man:MovieClip):Void {
        man._visible=false;delete man.onEnterFrame;
        man._name="__huofengRetired"+(++retiredSerial);
        man.removeMovieClip();
    }

    public static function tick(man:MovieClip):Void {
        var action:Object=man.__huofengAction;
        if (action==null || action.cancelled) return;
        var runtime:HuofengSetRuntime=action.owner;
        var unit:MovieClip=runtime.getUnit();
        if (!runtime.isActive() || !ownsMan(unit,action) || !(unit.hp>0)
            || (action.kind!=="nirvana" && !HuofengRules.profileActive(unit))) {
            cancel(runtime,action,false);
            return;
        }
        if (_root.暂停) return;
        var tick:Number=Number(_root.帧计时器.当前帧数);
        if (tick===action.lastTick) return;
        action.lastTick=tick;
        action.pendingTicks=0;
        action.frame++;
        action.localFrame++;
        if (action.kind==="nirvana" && action.paidSequence>0) {
            var runState:Object=runtime.getState();
            if (runState.pendingReviveSequence===action.paidSequence) {
                runState.presentedReviveSequence=action.paidSequence;
                runState.pendingNirvanaTier=0;
            }
        }

        HuofengAudio.frame(unit,action);
        if (action.kind!=="nirvana") steer(unit,action);
        if (action.recovery>0) {
            if (action.normalBridge) { repeatNormal(runtime,unit,action); return; }
            man.gotoAndStop(action.recoveryBase+action.recovery);
            if (++action.recovery>12) cancel(runtime,action,true);
            return;
        }
        if (action.kind==="normal") tickNormal(runtime,unit,action);
        else if (action.kind==="run") tickRun(runtime,unit,action);
        else if (action.kind==="spin") tickSpin(runtime,unit,action);
        else tickNirvana(runtime,unit,action);
    }

    /** 沿用兵器四向控制规则，显式传入单位；旧帧 helper 的裸 _parent 不适用于 class 回调。 */
    private static function steer(unit:MovieClip,action:Object):Void {
        var controlled:Boolean=unit._name===_root.控制目标;
        if (controlled) {
            if (unit.右行) unit.方向改变("右");
            else if (unit.左行) unit.方向改变("左");
        }
        var forward:Boolean=action.kind==="run" && action.frame>=7 && action.frame<=30 && action.recovery==0;
        // Running attack must not slow below normal locomotion. Bound the
        // burst around the Boss's 15 px/frame dash and keep Mover collision.
        var runSpeed:Number=HuofengRules.numberOrZero(unit.跑X速度)*1.1;
        runSpeed=Math.max(12,Math.min(18,runSpeed));
        var speed:Number=forward ? runSpeed : (action.kind==="spin" ? HuofengRules.numberOrZero(unit.行走X速度)*0.25 : 6);
        if (forward) Mover.move2D(unit,unit.方向,speed);
        else if (controlled) {
            if (unit.左行) Mover.move2D(unit,"左",speed);
            else if (unit.右行) Mover.move2D(unit,"右",speed);
        }
        if (controlled) {
            if (unit.上行) Mover.move2D(unit,"上",speed*0.5);
            else if (unit.下行) Mover.move2D(unit,"下",speed*0.5);
        }
    }

    private static function recover(action:Object,base:Number):Void {
        action.recovery=1;
        action.recoveryBase=base;
    }

    private static function spinRecovery(unit:MovieClip,action:Object):Void {
        recover(action,114);
        unit.man.gotoAndStop(115);
        // This tick is already recovery frame one, rather than an extra hold.
        action.recovery=2;
    }

    private static function spendLoopMp(unit:MovieClip):Void {
        unit.mp-=12;
        if(unit._name===_root.控制目标 && _root.玩家信息界面.刷新mp显示) _root.玩家信息界面.刷新mp显示();
    }

    /** Finish four sampled return poses, retaining the same body and owner.
     * Release during this bridge cancels repetition; skill/jump still win.
     * Advance before trying input so a rejected held skill cannot freeze it. */
    private static function repeatNormal(runtime:HuofengSetRuntime,unit:MovieClip,action:Object):Void {
        var poses:Array=HuofengRules.NORMAL_REPEAT_POSES;
        unit.man.gotoAndStop(poses[action.recovery-1]);
        action.recovery++;
        if (!unit.动作A) action.repeatRequested=false;
        if (HuofengInput.tryCancel(unit,action)) {
            if (!action.cancelled && action.recovery>poses.length) cancel(runtime,action,true);
            return;
        }
        if (unit.动作B) { cancel(runtime,action,false); unit.跳(); return; }
        if (action.recovery<=poses.length) return;
        if (!action.repeatRequested) { cancel(runtime,action,true); return; }
        action.frame=0;action.stage=0;action.localFrame=0;action.recovery=0;
        action.normalBridge=false;action.nextStage=false;action.cycle++;
        runtime.getState().primaryReadyFrame=Number(_root.帧计时器.当前帧数)+HuofengRules.NORMAL_FRAMES[0]+12;
    }

    private static function tickNormal(runtime:HuofengSetRuntime,unit:MovieClip,action:Object):Void {
        var stage:Number=action.stage;
        var f:Number=action.localFrame;
        unit.man.gotoAndStop(NORMAL_OFFSETS[stage]+f);
        var pulse:Number=HuofengRules.pulseIndex(HuofengRules.NORMAL_PULSES[stage],f);
        if (pulse>=0) HuofengCombat.emit(unit,action,HuofengRules.NORMAL_COEFFICIENTS[stage],0,22,
            stage==4 && pulse==HuofengRules.NORMAL_PULSES[stage].length-1 ? 8 : 2,
            stage==4 ? HuofengRules.FINISH_KNOCK_RATE : HuofengRules.HIT_KNOCK_RATE);
        var window:Array=HuofengRules.NORMAL_CANCEL[stage];
        if (f>=window[0] && f<=window[1]) {
            if (HuofengInput.tryCancel(unit,action)) return;
            if (unit.动作B) { cancel(runtime,action,false); unit.跳(); return; }
            if (stage<4 && unit.动作A) action.nextStage=true;
            if (stage==4 && unit.动作A) {
                action.normalBridge=true;action.repeatRequested=true;action.recovery=2;
                unit.man.gotoAndStop(HuofengRules.NORMAL_REPEAT_POSES[0]);
                // Release in this bridge must not inherit the old 95-frame gate.
                runtime.getState().primaryReadyFrame=Number(_root.帧计时器.当前帧数)+HuofengRules.NORMAL_REPEAT_POSES.length-1;
                return;
            }
        }
        if (f>=HuofengRules.NORMAL_FRAMES[stage]) {
            if (stage<4 && action.nextStage) {
                action.stage++;
                action.localFrame=0;
                action.nextStage=false;
                var state:Object=runtime.getState();
                state.primaryReadyFrame=Number(_root.帧计时器.当前帧数)+HuofengRules.NORMAL_FRAMES[action.stage]+12;
            } else recover(action,83);
        }
    }

    private static function tickRun(runtime:HuofengSetRuntime,unit:MovieClip,action:Object):Void {
        var f:Number=action.frame;
        unit.man.gotoAndStop(f);
        if (HuofengRules.pulseIndex(HuofengRules.RUN_PULSES,f)>=0) HuofengCombat.emit(unit,action,0.85,0,30,2,HuofengRules.HIT_KNOCK_RATE);
        if (f>=31 && f<=36) {
            if (HuofengInput.tryCancel(unit,action)) return;
            if (unit.动作B) { cancel(runtime,action,false); unit.跳(); return; }
        }
        if (f>=48) cancel(runtime,action,true);
    }

    private static function tickSpin(runtime:HuofengSetRuntime,unit:MovieClip,action:Object):Void {
        var f:Number=action.frame;
        unit.man.gotoAndStop(f);
        if (f==13) {
            if (!isFinite(unit.mp) || unit.mp<12) { spinRecovery(unit,action); return; }
            spendLoopMp(unit);
        }
        if (f==61) {
            if (!HuofengInput.weaponSkillHeld() || !isFinite(unit.mp) || unit.mp<12) { spinRecovery(unit,action); return; }
            // 第二圈在实际进入第 67 帧才扣除 12 MP。
            action.secondLoop=true;
        }
        if (f==67) {
            if (!isFinite(unit.mp) || unit.mp<12) { spinRecovery(unit,action); return; }
            spendLoopMp(unit);
        }
        if (action.firstHit && unit.动作B) { cancel(runtime,action,false); unit.跳(); return; }
        // 第一圈保证完整；第二圈松开在下一个 8 帧检查点退出。
        if (f>=70 && !HuofengInput.weaponSkillHeld() && (f-70)%8==0) { spinRecovery(unit,action); return; }
        // Continuous native cancellation during the actual swing, including
        // the frames between damage pulses; windup/recovery remain exposed.
        if ((f>=14 && f<=60) || (action.secondLoop && f>=68 && f<=114)) HuofengCombat.cancelBullets(unit,action);
        if (HuofengRules.pulseIndex(HuofengRules.SPIN_PULSES,f)>=0) {
            HuofengCombat.emit(unit,action,0.75,0.25,35,1,HuofengRules.HIT_KNOCK_RATE);
            action.firstHit=true;
        }
        if (f>=126) cancel(runtime,action,true);
    }

    private static function tickNirvana(runtime:HuofengSetRuntime,unit:MovieClip,action:Object):Void {
        var f:Number=action.frame;
        unit.man.gotoAndStop(f);
        if (HuofengRules.pulseIndex(HuofengRules.NIRVANA_PULSES[action.tier],f)>=0) HuofengCombat.blast(unit,action);
        if (f>=HuofengRules.NIRVANA_FRAMES[action.tier]) cancel(runtime,action,true);
    }
}
