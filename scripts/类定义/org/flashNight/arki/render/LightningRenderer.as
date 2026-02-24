import org.flashNight.arki.bullet.BulletComponent.Config.TeslaRayConfig;
import org.flashNight.arki.render.RayVfxManager;

/**
 * LightningRenderer - 射线视觉效果渲染器 (代理层)
 *
 * 此类现为 RayVfxManager 的向后兼容代理层。
 * 所有调用转发到 RayVfxManager，支持多种视觉风格。
 *
 * 支持的视觉风格 (通过 TeslaRayConfig.vfxStyle)：
 * • tesla    - 磁暴风格（高频抖动电弧 + 随机分叉）
 * • prism    - 光棱风格（稳定直束 + 呼吸动画）
 * • spectrum - 光谱风格（彩虹渐变 + 颜色滚动）
 * • wave     - 波能风格（正弦波路径 + 脉冲膨胀）
 *
 * 使用方法：
 *   // 旧 API（完全兼容）
 *   LightningRenderer.spawn(startX, startY, endX, endY, rayConfig);
 *
 *   // 新 API（支持 SegmentMeta）
 *   LightningRenderer.spawnWithMeta(startX, startY, endX, endY, rayConfig, meta);
 *
 *   // 每帧更新
 *   LightningRenderer.update();
 *
 *   // 场景切换时清理
 *   LightningRenderer.reset();
 *
 * @author FlashNight
 * @version 6.0
 * @see RayVfxManager
 * @see TeslaRayConfig
 */
class org.flashNight.arki.render.LightningRenderer {

    // ════════════════════════════════════════════════════════════════════════
    // 公共 API（转发到 RayVfxManager）
    // ════════════════════════════════════════════════════════════════════════

    /**
     * 生成射线视觉效果（旧 API，保持向后兼容）
     *
     * @param startX 起点 X 坐标
     * @param startY 起点 Y 坐标
     * @param endX   终点 X 坐标
     * @param endY   终点 Y 坐标
     * @param config 射线配置对象（TeslaRayConfig），可为 null
     */
    public static function spawn(startX:Number, startY:Number,
                                  endX:Number, endY:Number,
                                  config:TeslaRayConfig):Void {
        // 转发到 RayVfxManager，使用默认 meta
        RayVfxManager.spawn(startX, startY, endX, endY, config, null);
    }

    /**
     * 生成射线视觉效果（新 API，支持 SegmentMeta）
     *
     * @param startX 起点 X 坐标
     * @param startY 起点 Y 坐标
     * @param endX   终点 X 坐标
     * @param endY   终点 Y 坐标
     * @param config 射线配置对象（TeslaRayConfig）
     * @param meta   段上下文（SegmentMeta），可为 null
     */
    public static function spawnWithMeta(startX:Number, startY:Number,
                                          endX:Number, endY:Number,
                                          config:TeslaRayConfig, meta:Object):Void {
        RayVfxManager.spawn(startX, startY, endX, endY, config, meta);
    }

    /**
     * 每帧更新所有活跃电弧
     */
    public static function update():Void {
        RayVfxManager.update();
    }

    /**
     * 重置渲染器，清理所有活跃电弧
     */
    public static function reset():Void {
        RayVfxManager.reset();
    }

    /**
     * 获取当前活跃电弧数量
     */
    public static function getActiveCount():Number {
        return RayVfxManager.getActiveCount();
    }

    /**
     * 获取当前 LOD 等级
     */
    public static function getCurrentLOD():Number {
        return RayVfxManager.getCurrentLOD();
    }

    /**
     * 获取当前渲染成本
     */
    public static function getRenderCost():Number {
        return RayVfxManager.getRenderCost();
    }
}