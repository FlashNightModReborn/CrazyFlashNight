/**
 * ============================================================================
 * 视觉系统_fs_打击数字池.as - 打击伤害数字系统（纯兼容层）
 * ============================================================================
 *
 * 【第四阶段：纯薄封装】
 * 核心逻辑已完全迁移到 HitNumberSystem 类中，此文件仅保留：
 * 1. 全局常量 _root.打击数字坐标偏离
 * 2. 对外接口的纯薄封装（兼容旧调用，直接转发到 HitNumberSystem）
 *
 * 所有路径最终都走 HitNumberSystem.effect + HitNumberBatchProcessor
 * ============================================================================
 */

// 坐标随机偏移量（像素）
_root.打击数字坐标偏离 = 60;

/**
 * 初始化打击伤害数字池（兼容接口）
 * 转发到 HitNumberSystem.initPool
 */
_root.初始化打击伤害数字池 = function(池大小) {
    org.flashNight.arki.component.Effect.HitNumberSystem.initPool(池大小);
};

/**
 * 处理打击数字特效（对外接口，保持向后兼容）
 *
 * 【第四阶段】纯薄封装
 * 直接转发到 HitNumberSystem.effect，所有逻辑（批处理/直接模式切换、
 * 节流判断、视野剔除）均由 HitNumberSystem.effect 内部处理。
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

/**
 * 打击数字特效内部渲染函数
 *
 * 【第二阶段】
 * 现在只是 HitNumberSystem.spawn 的薄封装。
 * 真正的池逻辑已迁移到 HitNumberSystem 类中。
 *
 * 供 HitNumberBatchProcessor.flush() 调用，跳过节流判断。
 * 注意：视野剔除和节流决策已由 HitNumberBatchProcessor 完成，此处不再重复判断。
 *
 * @param 控制字符串 效果种类（如"暴击"、"能"等）
 * @param 数字 数值或已格式化的字符串
 * @param myX 世界坐标 X
 * @param myY 世界坐标 Y
 * @param 必然触发 是否强制显示（此参数透传到 HitNumberSystem）
 */
_root.打击数字特效内部 = function(控制字符串, 数字, myX, myY, 必然触发) {
    // 第二阶段：转发到 HitNumberSystem，池逻辑已迁移到类中
    org.flashNight.arki.component.Effect.HitNumberSystem.spawn(控制字符串, 数字, myX, myY, 必然触发);
};
