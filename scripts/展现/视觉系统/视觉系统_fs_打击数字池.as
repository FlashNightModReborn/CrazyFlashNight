/**
 * ============================================================================
 * 视觉系统_fs_打击数字池.as - 打击伤害数字系统（_root 挂载层）
 * ============================================================================
 *
 * 核心逻辑已完全迁移到 HitNumberSystem 类中，此文件仅保留：
 * - _root.打击数字特效：子 SWF 通过 _root 调用打击数字特效的唯一入口
 *
 * 所有路径最终都走 HitNumberSystem.effect → HitNumberBatchProcessor
 * ============================================================================
 */

/**
 * 处理打击数字特效（_root 挂载接口，供子 SWF 调用）
 *
 * 直接转发到 HitNumberSystem.effect，由其加入批处理队列，
 * 节流与视野剔除在帧末 flush 时统一处理。
 *
 * @param 控制字符串 效果种类（如"暴击"、"能"等）
 * @param 数字 数值或已格式化的字符串
 * @param myX 世界坐标 X
 * @param myY 世界坐标 Y
 * @param 必然触发 是否强制显示
 */
_root.打击数字特效 = function(控制字符串, 数字, myX, myY, 必然触发) {
    org.flashNight.arki.component.Effect.HitNumberSystem.effect(控制字符串, 数字, myX, myY, 必然触发);
};

