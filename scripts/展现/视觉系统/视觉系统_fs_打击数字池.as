/**
 * ============================================================================
 * 视觉系统_fs_打击数字池.as - 打击伤害数字系统（兼容层）
 * ============================================================================
 *
 * 【第三阶段：瘦身完成】
 * 核心逻辑已迁移到 HitNumberSystem 类中，此文件仅保留：
 * 1. 全局常量 _root.打击数字坐标偏离
 * 2. 对外接口的薄封装（兼容旧调用）
 *
 * 所有路径最终都走 HitNumberSystem + HitNumberBatchProcessor
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
 * 【第三阶段】
 * 所有路径统一走 HitNumberBatchProcessor + HitNumberSystem：
 * - 若批处理启用：通过 enqueue 加入队列，帧末统一处理
 * - 若批处理禁用：直接调用 HitNumberSystem.spawn
 *
 * 【节流说明】
 * - 批处理模式：节流由 HitNumberBatchProcessor.flush 统一处理
 * - 直接模式：此函数保留原有节流逻辑
 *
 * @param 控制字符串 效果种类（如"暴击"、"能"等）
 * @param 数字 数值或已格式化的字符串
 * @param myX 世界坐标 X
 * @param myY 世界坐标 Y
 * @param 必然触发 是否强制显示
 */
_root.打击数字特效 = function(控制字符串, 数字, myX, myY, 必然触发) {
    var HitNumberBatchProcessor = org.flashNight.arki.component.Effect.HitNumberBatchProcessor;
    var HitNumberSystem = org.flashNight.arki.component.Effect.HitNumberSystem;

    if (HitNumberBatchProcessor.enabled) {
        // 批处理模式：加入队列，节流由 flush 统一处理
        HitNumberBatchProcessor.enqueue(控制字符串, 数字, myX, myY, 必然触发);
    } else {
        // 直接模式：保留原有节流逻辑
        var gameWorld:MovieClip = _root.gameworld;
        var sx:Number = gameWorld._xscale * 0.01;
        var locX:Number = gameWorld._x + myX * sx;
        var locY:Number = gameWorld._y + myY * sx;

        // 视野外剔除
        if (locX < 0 || locX > Stage.width || locY < 0 || locY > Stage.height) {
            return;
        }

        // 节流判断
        if (_root.是否打击数字特效 && (_root.当前打击数字特效总数 <= _root.同屏打击数字特效上限 || _root.成功率(_root.同屏打击数字特效上限 / 5)) || 必然触发) {
            HitNumberSystem.spawn(控制字符串, 数字, myX, myY, 必然触发);
        }
    }
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
