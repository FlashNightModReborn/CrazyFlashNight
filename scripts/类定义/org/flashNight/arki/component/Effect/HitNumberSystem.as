/**
 * HitNumberSystem
 * ----------------
 * 打击伤害数字系统（静态类）
 *
 * 【第一阶段：API 收口】
 * 当前实现为纯代理模式，所有调用直接转发到 _root.打击数字特效内部。
 * 这样做的目的是：
 *   1. 统一 API 入口，便于后续迁移
 *   2. 不改变任何现有行为，零风险
 *   3. HitNumberBatchProcessor.flush 可以通过此类调用渲染
 *
 * 【计数与池】
 * 当前阶段不维护独立的池和计数，完全依赖：
 *   - _root.gameworld.可用数字池（池存储）
 *   - _root.当前打击数字特效总数（权威计数）
 *   - _root.同屏打击数字特效上限（节流上限）
 *
 * 【节流职责】
 * spawn() 不做任何节流判断，节流由调用方负责：
 *   - HitNumberBatchProcessor.flush() 负责批处理路径的节流
 *   - _root.打击数字特效() 负责直接调用路径的节流
 *
 * @version 2.0 - 代理模式
 * @author FlashNight
 */
class org.flashNight.arki.component.Effect.HitNumberSystem {

    // ========================================================================
    // 公共 API
    // ========================================================================

    /**
     * 播放一次打击数字特效
     *
     * 【第一阶段实现】
     * 纯代理，直接调用 _root.打击数字特效内部，不做任何额外处理。
     * 节流、视野剔除等决策由调用方（HitNumberBatchProcessor）负责。
     *
     * @param ctrl  控制字符串（效果种类，如"暴击"、"能"等）
     * @param value 数值或已格式化的字符串
     * @param x     世界坐标 X
     * @param y     世界坐标 Y
     * @param force 是否强制显示（此参数透传，由内部函数决定如何使用）
     */
    public static function spawn(ctrl:String, value:Object, x:Number, y:Number, force:Boolean):Void {
        // 第一阶段：纯代理，直接转发到现有脚本实现
        // 不做任何节流判断，节流由 HitNumberBatchProcessor 负责
        _root.打击数字特效内部(ctrl, value, x, y, force);
    }
}
