import org.flashNight.arki.unit.UnitComponent.Routing.*;

/**
 * ContainerFrameScriptContract — 容器帧脚本 → 玩家模板 调用契约（第三阶段）
 *
 * ════════════════════════════════════════════════════════════════════
 * 为什么是"契约表"而不是"复刻时间轴"
 * ════════════════════════════════════════════════════════════════════
 *   容器元件（如 兵器攻击容器-1连招）是 5000+ 行 XFL DOMSymbolItem，含逐帧
 *   时间轴 + 帧脚本。复刻整个时间轴既脆（美术会重排连招帧）又无意义（AS2 帧脚本
 *   编译进 SWF 时间轴、不可单测）。
 *
 *   真正与路由/玩家模板相关的，只是帧脚本里 `_parent.*` 的**调用序列**。本类把该
 *   序列人工审计成小契约表，replay 驱动夹具单位 —— 验证"容器帧脚本 → 玩家模板"
 *   这条 in-direction 链路。
 *
 *   契约表是 **review-gated**：容器 XML 有意义变更时须重审此表（见
 *   [[feedback-reproduction-test-overconfidence]]）。它不证明真实容器一定这么调，
 *   只把"我们认定的容器调用契约"固化成可回归的断言。
 *
 * 数据来源：flashswf/arts/things0/LIBRARY/容器/兵器攻击容器/平A/兵器攻击容器-1连招.xml
 *   的 <DOMFrame><script> 节点（2026-05-20 审计）。
 *
 * 步骤结构：{ call:String 方法名, args:Array 实参 }。
 *
 * ════════════════════════════════════════════════════════════════════
 * 两类调用：_parent.* 序列  vs  _root.兵器攻击路由.* route handoff
 * ════════════════════════════════════════════════════════════════════
 *   容器末帧（index 72）的 <script> 有**两条**语句（XML L372-373）：
 *     1. _parent.UpdateBigSmallState("普攻结束","兵器五段结束");  ← dispatch 在 unit
 *     2. _root.兵器攻击路由.动画完毕(this, _parent);              ← route handoff
 *
 *   weaponComboFullSequence() 覆盖第 1 类：全部 `_parent.*` 调用、dispatch 在 unit。
 *   第 2 类 dispatch 在 `_root.兵器攻击路由`、实参 (this=容器man, _parent=玩家模板unit)，
 *   塞不进 unit-dispatch 的 {call,args} 步骤 —— 单列 weaponComboRouteHandoff() +
 *   replayRouteHandoff()。
 *
 *   `_root.兵器攻击路由.动画完毕` 是一行委派（引擎_fs_兵器攻击路由.as:188-190）：
 *     function(man,unit){ RoutingLifecycle.completeAnimation(man,unit,false); }
 *   replayRouteHandoff 直调真 `RoutingLifecycle.completeAnimation` —— 这一段是
 *   **真集成、有真牙齿**（completeAnimation 是 testloader 编译单元内的 production
 *   class）。残余保真度 gap 收缩成"那一行 wrapper 是否真等于
 *   completeAnimation(man,unit,false)" —— 一行 audit、review-gated
 *   （见 [[feedback-reproduction-test-overconfidence]]）。
 */
class org.flashNight.arki.unit.UnitComponent.Routing.ContainerFrameScriptContract {

    /**
     * 兵器攻击容器-1连招 走完五段连招时，帧脚本对 `_parent.*` 的调用序列。
     *
     * 审计自 兵器攻击容器-1连招.xml：
     *   一段中(L224) → 动画完毕(L252) → 二段中(L259) → 动画完毕(L278) →
     *   三段中(L285) → 动画完毕(L310) → 四段中(L317) → 动画完毕(L343) →
     *   五段中(L350) → 末帧 UpdateBigSmallState(L372)
     *
     * 注：帧首 helper 定义（攻击时可改变移动方向 等）与 刀口触发特效 不触玩家模板
     * 路由面，不入契约。末帧（index 72）与 UpdateBigSmallState 同帧紧跟的
     * `_root.兵器攻击路由.动画完毕(this,_parent)` 是 route handoff —— 见
     * weaponComboRouteHandoff()。
     */
    public static function weaponComboFullSequence():Array {
        return [
            { call: "UpdateSmallState",    args: ["兵器一段中"] },
            { call: "动画完毕",             args: [] },
            { call: "UpdateSmallState",    args: ["兵器二段中"] },
            { call: "动画完毕",             args: [] },
            { call: "UpdateSmallState",    args: ["兵器三段中"] },
            { call: "动画完毕",             args: [] },
            { call: "UpdateSmallState",    args: ["兵器四段中"] },
            { call: "动画完毕",             args: [] },
            { call: "UpdateSmallState",    args: ["兵器五段中"] },
            { call: "UpdateBigSmallState", args: ["普攻结束", "兵器五段结束"] }
        ];
    }

    /**
     * 按契约顺序在 unit 上回放 `_parent.*` 调用。
     *
     * @param unit     夹具单位（untyped；须实现契约涉及的方法）
     * @param contract weaponComboFullSequence() 这类步骤数组
     */
    public static function replay(unit, contract:Array):Void {
        for (var i:Number = 0; i < contract.length; i++) {
            var step:Object = contract[i];
            unit[step.call].apply(unit, step.args);
        }
    }

    /**
     * 容器末帧 route handoff 描述符 —— `_root.兵器攻击路由.动画完毕(this, _parent)`。
     *
     * 审计自 兵器攻击容器-1连招.xml:373（末帧 index 72，与 UpdateBigSmallState 同帧）
     * 与 引擎_fs_兵器攻击路由.as:188-190（动画完毕 = 一行委派）。
     *
     * 字段：
     *   frameIndex               触发帧（72，与 weaponComboFullSequence 末步同帧）
     *   routeObject / call       `_root.兵器攻击路由` . `动画完毕`
     *   argShape                 实参形状：(this=容器man, _parent=玩家模板unit)
     *   delegate                 动画完毕 的委派目标
     *   delegateEnableDoubleJump 委派时硬编码的 enableDoubleJump 实参（普攻恒 false）
     */
    public static function weaponComboRouteHandoff():Object {
        return {
            frameIndex: 72,
            routeObject: "兵器攻击路由",
            call: "动画完毕",
            argShape: ["this(容器man)", "_parent(玩家模板unit)"],
            delegate: "RoutingLifecycle.completeAnimation",
            delegateEnableDoubleJump: false
        };
    }

    /**
     * 回放容器末帧 route handoff —— 直调真实 RoutingLifecycle.completeAnimation。
     *
     * 这是 `_root.兵器攻击路由.动画完毕` wrapper 的忠实复刻（wrapper 本身即一行委派）。
     * completeAnimation 是 testloader 编译单元内的 production class —— 这一步有真牙齿；
     * 残余 gap 只剩"wrapper 是否真等于 completeAnimation(man,unit,false)"，review-gated。
     *
     * @param man   容器 man 剪辑（对应帧脚本里的 `this`）
     * @param unit  玩家模板单位（对应帧脚本里的 `_parent`）
     */
    public static function replayRouteHandoff(man, unit):Void {
        RoutingLifecycle.completeAnimation(man, unit, false);
    }
}
