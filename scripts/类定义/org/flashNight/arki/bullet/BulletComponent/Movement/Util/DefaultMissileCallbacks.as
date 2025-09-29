// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/DefaultMissileCallbacks.as

import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*;

/**
 * 默认导弹回调函数生成器
 * ====================
 * 提供一组用于导弹/子弹组件的默认回调函数
 * 支持通过配置对象自定义导弹行为参数
 * 
 * 职责：
 *   - 整合所有导弹行为回调
 *   - 提供统一的接口创建回调集合
 *   - 处理默认配置的获取
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.DefaultMissileCallbacks {
    /**
     * 构建并返回默认回调函数对象
     * @param shooter 发射此导弹的 MovieClip 实例
     * @param velocity 导弹的最大速度
     * @param angleDegrees 导弹初始的旋转角度（度数）
     * @param config 导弹配置对象（可选，默认使用标准配置）
     * @return Object 包含导弹所有生命周期回调的对象
     */
    public static function build(shooter:MovieClip,
                                velocity:Number,
                                angleDegrees:Number,
                                config:Object):Object {
        // 如果未提供配置，使用默认配置
        if (config == undefined) {
            config = MissileConfig.getInstance().getConfig("default");
        }
        
        return {
            onInitializeMissile: InitMissileCallbacks.create(shooter, velocity, angleDegrees, config),
            onSearchForTarget: SearchForTargetCallbacks.create(config),
            onTrackTarget: TrackTargetCallbacks.create(config),
            onPreLaunchMove: PreLaunchMoveCallbacks.create(config, angleDegrees)
        };
    }
    
    /**
     * 使用配置名称构建回调函数对象
     * @param shooter 发射此导弹的 MovieClip 实例
     * @param velocity 导弹的最大速度
     * @param angleDegrees 导弹初始的旋转角度（度数）
     * @param configName 配置名称
     * @return Object 包含导弹所有生命周期回调的对象
     */
    public static function buildWithConfigName(shooter:MovieClip,
                                             velocity:Number,
                                             angleDegrees:Number,
                                             configName:String):Object {
        var configManager:MissileConfig = MissileConfig.getInstance();
        var config:Object = configManager.getConfig(configName || "default");
        return build(shooter, velocity, angleDegrees, config);
    }
}