import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * RoutingLifecycle — 路由生命周期 API 的 class 化落点
 *
 * 负责技能/战技/普攻容器共用的动画完毕、浮空、结束清理与通用 initObject。
 * `_root.路由基础` 暂时保留为兼容门面，生产路由逐步直连本 class。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.RoutingLifecycle {

    public static function preparePoseAndBonus(unit:MovieClip):Void {
        unit.格斗架势 = true;
        unit.根据模式重新读取武器加成(
            RoutingLifecycleCore.resolveBonusMode(HeroUtil.isFistSkill(unit.技能名))
        );
    }

    /**
     * 位移技能起手前按当前水平输入校正面向。
     * 射击/受击时方向可能仍停在开火或受击方向，而技能位移帧读取 unit.方向；
     * 不校正会出现“按住左右仍朝受击方向跳/闪”的方向异常。
     * 小跳/闪现/滑步保留起手快照；其余位移动作沿用既有单侧输入转向。
     */
    public static function applyMovementSkillFacing(unit:MovieClip, skillName:String):Void {
        if (!unit) return;
        MovementSkillDirection.capture(unit, skillName);
        if (MovementSkillDirection.supports(skillName)) return;
        if (typeof unit.方向改变 != "function") return;
        if (_root.控制目标 == undefined || String(unit._name) != String(_root.控制目标)) return;
        if (skillName != "小跳" && skillName != "闪现" && skillName != "一瞬千击"
            && skillName != "瞬步斩" && skillName != "拔刀斩") return;
        if (unit.右行 && !unit.左行) unit.方向改变("右");
        else if (unit.左行 && !unit.右行) unit.方向改变("左");
    }

    public static function ensureTempY(unit:MovieClip):Void {
        unit.temp_y = RoutingLifecycleCore.isInAir(unit._y, unit.Z轴坐标) ? unit._y : 0;
    }

    public static function bindMovement(man:MovieClip):Void {
        bindMovementFrom(man, _root.技能函数);
    }

    public static function bindMovementFrom(man:MovieClip, skillFns:Object):Void {
        man.攻击时移动 = skillFns.攻击时移动;
        man.攻击时后退移动 = skillFns.攻击时移动;
        man.攻击时按键四向移动 = skillFns.攻击时按键四向移动;
        man.攻击时可改变移动方向 = skillFns.攻击时可改变移动方向;
        man.攻击时可斜向改变移动方向 = skillFns.攻击时可斜向改变移动方向;
        man.攻击时斜向移动 = skillFns.攻击时斜向移动;
        man.攻击时可斜向改变移动方向2 = skillFns.攻击时可斜向改变移动方向2;
        man.获取移动方向 = skillFns.获取移动方向;
    }

    public static function buildPublicContainerInit(container:MovieClip):Object {
        return ContainerInitScratch.getPublic(container);
    }

    /**
     * 技能容器 linkage 缺失时立即退出空容器状态。
     * 动画完毕是角色既有的安全恢复入口，会按死亡、浮空与攻击模式选择正确状态。
     */
    public static function recoverMissingSkillContainer(unit:MovieClip):Void {
        if (!unit) return;

        if (unit.根据模式重新读取武器加成) {
            unit.根据模式重新读取武器加成(unit.攻击模式);
        }
        if (unit.动画完毕) {
            unit.动画完毕();
            return;
        }

        // 非标准单位缺少动画完毕时的保底，仅用于防止永久停留在空容器。
        unit.技能名 = null;
        if (unit.状态改变) {
            var attackMode:String = unit.攻击模式 ? String(unit.攻击模式) : "空手";
            unit.状态改变(attackMode + "站立");
        }
    }

    public static function bindEndCleanup(clip:MovieClip, unit:MovieClip, excludeState:String, endBigState:String, floatFlag:String):Void {
        var prevOnUnload:Function = clip.onUnload;
        var targetUnit:MovieClip = unit;
        var excluded:String = excludeState;
        var endState:String = endBigState;
        var flag:String = floatFlag;
        clip.onUnload = function() {
            if (prevOnUnload != undefined) {
                prevOnUnload.apply(this);
            }
            targetUnit.无敌 = false;
            var needReset:Boolean = RoutingLifecycleCore.shouldResetOnEndCleanup(targetUnit.状态, excluded);
            if (needReset) {
                targetUnit.temp_y = 0;
            }
            targetUnit.UpdateBigSmallState(endState, endState);
            targetUnit.根据模式重新读取武器加成(targetUnit.攻击模式);
            if (needReset) {
                if (targetUnit.__preserveFloatFlagOnUnload == flag) {
                    delete targetUnit.__preserveFloatFlagOnUnload;
                } else {
                    targetUnit[flag] = false;
                }
            }
            if (targetUnit.dispatcher != undefined && targetUnit.dispatcher != null) {
                targetUnit.dispatcher.publish("skillEnd", targetUnit);
            }
        };
    }

    public static function handleFloat(man:MovieClip, unit:MovieClip, floatFlag:String):Void {
        var sources:Object = unit.__air.sources;
        var skill:Object = sources.skillFloat;
        var oldJump:Object = sources.jumpFloat;
        var oldNatural:Object = sources.naturalFall;
        var owns:Boolean = skill != undefined && skill === man.__skillFloatSource;
        var rising:Boolean = unit.垂直速度 < 0 && (skill != undefined || oldJump != undefined
            || sources.knockback != undefined || sources.jetpack.active == true);
        if (!owns && !RoutingLifecycleCore.shouldApplyFloat(unit._y, unit.Z轴坐标, rising)) {
            man.落地 = true;
            return;
        }

        unit[floatFlag] = true;
        unit.temp_y = unit._y;
        unit.起始Y = unit.Z轴坐标;
        man.落地 = false;
        unit.浮空 = true;

        // 先接管再让出旧来源，停轮后重启会在同一帧额外积分。容器自行登记的初速和悬停也要保留。
        clearLegacySkillFloatTask(unit);
        if (!owns) RoutingRuntime.enableSkillFloat(unit, floatFlag, man);
        if (oldNatural != undefined && unit.__air.sources.naturalFall === oldNatural) RoutingRuntime.closeNaturalLanding(unit);
        if (oldJump != undefined && unit.__air.sources.jumpFloat === oldJump) RoutingRuntime.closeJumpFloat(unit);
    }

    public static function clearSkillFloatTask(unit:MovieClip):Void {
        RoutingRuntime.closeSkillFloat(unit);
        clearLegacySkillFloatTask(unit);
    }

    private static function clearLegacySkillFloatTask(unit:MovieClip):Void {
        if (unit.__技能浮空任务ID != null) {
            RoutingRuntime.removeTask(unit.__技能浮空任务ID);
            unit.__技能浮空任务ID = null;
        }
    }

    public static function clearNaturalLandingTask(unit:MovieClip):Void {
        RoutingRuntime.closeNaturalLanding(unit);
        if (unit.__自然落地任务ID != null) {
            RoutingRuntime.removeTask(unit.__自然落地任务ID);
            unit.__自然落地任务ID = null;
        }
    }

    public static function startNaturalLandingTask(unit:MovieClip):Void {
        clearNaturalLandingTask(unit);
        RoutingRuntime.enableNaturalLanding(unit);
    }

    /** 只在装备重建的栈上记住正在播放的普通兵器动作；同路径 man 可能在重建期间被替换。 */
    public static function captureOrdinaryBladeAction(unit:MovieClip):Object {
        var man:MovieClip = unit.man;
        var name:String = unit.兵器攻击名;
        // 普攻入口取“动作类型 + 1连招”（缺省为“1连招”）。派生入口另走 STATE_WEAPON_CONTAINER。
        if (unit.兵种 !== "主角-男" || unit.攻击模式 !== "兵器" || unit.状态 !== RoutingIntent.STATE_WEAPON
                || unit.__stateGotoLabel !== RoutingIntent.LABEL_CONTAINER || man._parent !== unit
                || man.__isDynamicMan !== true || typeof man.onUnload != "function" || name.slice(-3) !== "1连招"
                || man.__huofengColdSnapshot != null || unit.__deadHandOwner != null) return null;
        return {name:name, endHook:man.onUnload};
    }

    /** 在 alias、装备变形和模式校验之后判定。其它招式及已进入下一动作的单位由原出口收尾。 */
    public static function incompatibleBladeExit(unit:MovieClip, action:Object):Function {
        var man:MovieClip = unit.man;
        if (man.onUnload !== action.endHook || man._parent !== unit || man.__isDynamicMan !== true
                || unit.兵器攻击名 !== action.name || unit.__stateGotoLabel !== RoutingIntent.LABEL_CONTAINER
                || man.__huofengColdSnapshot != null || unit.__deadHandOwner != null
                || org.flashNight.arki.unit.Action.Huofeng.HuofengRules.profileActive(unit)) return null;

        // validateAttackMode 在卸刀时已写空手站立；显示标签此时仍然是容器。
        var unequipped:Boolean = !unit.刀 && unit.攻击模式 === "空手" && unit.状态 === "空手站立";
        if (!unequipped && (unit.攻击模式 !== "兵器" || unit.状态 !== RoutingIntent.STATE_WEAPON)) return null;
        // 烬灭长柄保留副剑配置，但隐藏这把三刀口副剑，整把武器按五刀口发射。
        var hiddenSecondary:Boolean = unit.刀2_装扮 === "刀-烬灭裁决副剑" && unit.兵器动作类型 === "长柄";
        var missingSecondary:Boolean = action.name === "双刀1连招" && (!unit.刀2_装扮 || hiddenSecondary);
        var missingSheath:Boolean = action.name === "疾影1连招" && !unit.刀3_装扮;
        // 强制退出没有自然末帧的预输入机会。直接复用收尾，不经过兵器动画完毕的搓招包装。
        return !unit.刀 || missingSecondary || missingSheath ? RoutingLifecycle.completeAnimation : null;
    }

    public static function completeAnimation(man:MovieClip, unit:MovieClip, enableDoubleJump:Boolean):Void {
        clearSkillFloatTask(unit);

        var inAir:Boolean = RoutingLifecycleCore.isInAir(unit._y, unit.Z轴坐标);
        if (RoutingLifecycleCore.shouldPreserveDoubleJump(enableDoubleJump, inAir)) {
            unit.技能浮空 = true;
            unit.__preserveFloatFlagOnUnload = "技能浮空";
        }

        unit.动画完毕();
        man.removeMovieClip();

        if (RoutingLifecycleCore.shouldStartNaturalLanding(enableDoubleJump, inAir)) {
            startNaturalLandingTask(unit);
        }
    }
}
