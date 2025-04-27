// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/DefaultMissileCallbacks.as

import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*;

/**
 * 默认导弹回调函数生成器
 * 提供一组用于导弹/子弹组件的默认回调函数
 * 支持通过配置对象自定义导弹行为参数
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.DefaultMissileCallbacks {
    /**
     * 构建并返回默认回调函数对象
     * @param shooter       发射此导弹的 MovieClip 实例
     * @param velocity      导弹的最大速度
     * @param angleRadians  导弹初始的旋转角度（弧度）
     * @param config        导弹配置对象（可选，默认使用标准配置）
     * @return Object       包含 onInitializeMissile、onSearchForTarget、onTrackTarget、onPreLaunchMove 四个回调
     */
    public static function build(shooter:MovieClip,
                                 velocity:Number,
                                 angleRadians:Number,
                                 config:MissileConfig):Object {
        // 如果未提供配置，使用默认配置
        if (config == undefined) {
            config = MissileConfig.create();
        }
        
        return {
            onInitializeMissile : InitMissileCallbacks.create(shooter, velocity, angleRadians, config),
            onSearchForTarget   : SearchForTargetCallbacks.create(config),
            onTrackTarget       : TrackTargetCallbacks.create(config),
            onPreLaunchMove     : PreLaunchMoveCallbacks.create(config)
        };
    }
}