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
     * 路由面，不入契约。
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
}
