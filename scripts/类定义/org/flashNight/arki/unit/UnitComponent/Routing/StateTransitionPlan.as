import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * StateTransitionPlan — unit.状态改变 的"决策计划"层
 *
 * 职责分层（自下而上）：
 *   StateTransitionCore   — 6 个真值表纯函数，零依赖
 *   StateTransitionPlan   — snapshot 字段提取 + buildPlan 组合 Core，纯函数
 *   StateTransition.apply — 拿 snapshot/plan，做副作用（gotoAndStop / executeJob / ...）
 *
 * 设计要点：
 * 1) snapshot(self) 一次性把 buildPlan 所需的 unit 字段 + _root.控制目标 + job override
 *    抽出来。job override 不走 RoutingIntent.getJobGotoOverride（方法调用 ~1340ns），
 *    inline 两行成员读（~330ns），同时拿到"流程纯净 + 性能最优"。
 * 2) buildPlan(snapshot, newStateName) 100% 纯函数：不读 _root、不调 instance method、
 *    不写 unit 字段，返回 plan:Object。
 * 3) Plan 是 union-like：earlyReturn=true 分支下其余决策字段保持 undefined；
 *    validatePlan() 静态断言这个不变式。
 *
 * AS2 strict 注意（见 [[feedback-as2-strict-function-param-dynamic-path]]）：
 *   snapshot 的形参 :MovieClip 仅对生产路径成立；testloader 路径用 untyped fake unit，
 *   编译期类型擦除，运行时一致。buildPlan 形参 :Object 兼容真实 snapshot 与 fake snapshot。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.StateTransitionPlan {

    // ====================================================================
    // snapshot — 从 self + _root 一次性抽取 buildPlan 所需的全部值。
    // ====================================================================

    public static function snapshot(self:MovieClip):Object {
        // job override inline lookup —— 不调 RoutingIntent.getJobGotoOverride，
        // 直接 2 次成员读 + null check，省 1 次方法调用税。
        var job:Object = self.__stateTransitionJob;
        var jobOverride:String = null;
        if (job != undefined && job.gotoLabel != undefined) {
            jobOverride = job.gotoLabel;
        }

        var manRef:Object = self.man;
        var hasDynamicMan:Boolean = false;
        if (manRef != undefined && manRef.__isDynamicMan === true) {
            hasDynamicMan = true;
        }

        return {
            name:             self._name,
            兵种:             self.兵种,
            攻击模式:         self.攻击模式,
            状态:             self.状态,
            __stateGotoLabel: self.__stateGotoLabel,
            飞行浮空:         self.飞行浮空,
            controlTarget:    _root.控制目标,
            hasDynamicMan:    hasDynamicMan,
            jobGotoOverride:  jobOverride
        };
    }

    // ====================================================================
    // buildPlan — 纯函数：snapshot + newStateName → plan
    //
    // plan 字段（union-like）：
    //   storeFlyState     : Boolean   总是定义
    //   earlyReturn       : Boolean   总是定义
    //   ───── 以下字段仅当 earlyReturn=false 时定义；earlyReturn=true 时为 undefined ─────
    //   attackMode        : String    self.攻击模式 兜底结果
    //   oldState          : String    snapshot.状态
    //   removeDynamicMan  : Boolean   是否需要 self.man.removeMovieClip()
    //   gotoLabel         : String    本次 gotoAndStop 实际帧标签
    //   transition        : Boolean   是否真发生 transition（gotoAndStop + executeJob）
    //   newLogicalState   : String    transition=true 时写入 self.状态 的值
    // ====================================================================

    public static function build(snapshot:Object, newStateName:String):Object {
        var plan:Object = {
            storeFlyState: false,
            earlyReturn:   false
        };

        plan.storeFlyState = StateTransitionCore.shouldStoreFlyState(
            snapshot.name, snapshot.controlTarget, newStateName, snapshot.攻击模式
        );

        if (StateTransitionCore.shouldEarlyReturnOnFlyingRun(snapshot.飞行浮空, newStateName)) {
            plan.earlyReturn = true;
            return plan;
        }

        plan.attackMode       = StateTransitionCore.resolveAttackMode(snapshot.攻击模式);
        plan.oldState         = snapshot.状态;
        plan.removeDynamicMan = snapshot.hasDynamicMan === true;

        var prevGotoLabel:String = StateTransitionCore.resolvePrevGotoLabel(
            snapshot.__stateGotoLabel, snapshot.状态
        );
        var isHeroMale:Boolean = (snapshot.兵种 === StateTransitionCore.HERO_KIND_MALE);
        // 短路：仅主角-男容器化场景 jobGotoOverride 才参与计算。
        // snapshot 已 inline lookup 拿到值（杂兵也读，无函数调用税），这里只是策略选择。
        var jobOverride:String = isHeroMale ? snapshot.jobGotoOverride : null;
        plan.gotoLabel = StateTransitionCore.resolveGotoLabel(
            newStateName, isHeroMale, jobOverride
        );
        plan.transition = StateTransitionCore.shouldTransition(
            snapshot.状态, newStateName, prevGotoLabel, plan.gotoLabel
        );
        plan.newLogicalState = newStateName;

        return plan;
    }

    // ====================================================================
    // validatePlan — 结构性不变式（仅测试用，生产不调）。
    // ====================================================================

    public static function validate(plan:Object):Boolean {
        if (plan == undefined) return false;
        if (plan.earlyReturn === true) {
            // earlyReturn 分支：除 storeFlyState/earlyReturn 外字段必须 undefined
            return plan.attackMode === undefined
                && plan.oldState === undefined
                && plan.removeDynamicMan === undefined
                && plan.gotoLabel === undefined
                && plan.transition === undefined
                && plan.newLogicalState === undefined;
        }
        // 正常分支：transition=true 需要 gotoLabel/newLogicalState 非空
        if (plan.transition === true) {
            if (plan.gotoLabel == undefined || plan.gotoLabel === "") return false;
            if (plan.newLogicalState == undefined || plan.newLogicalState === "") return false;
        }
        return true;
    }
}
