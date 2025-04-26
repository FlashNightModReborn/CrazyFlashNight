// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/DefaultMissileCallbacks.as

import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*;

/**
 * 提供一组用于导弹/子弹组件的默认回调函数。
 * 调用 build(shooter, velocity, angleRadians) 获取一个包含四个回调的对象。
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.DefaultMissileCallbacks {
    /**
     * 构建并返回默认回调函数对象
     * @param shooter       发射此导弹的 MovieClip 实例
     * @param velocity      导弹的最大速度
     * @param angleRadians  导弹初始的旋转角度（弧度）
     * @return Object 包含 onInitializeMissile、onSearchForTarget、onTrackTarget、onPreLaunchMove 四个回调
     */
    public static function build(shooter:MovieClip,
                                 velocity:Number,
                                 angleRadians:Number):Object {
        return {
            onInitializeMissile : InitMissileCallbacks.create(shooter, velocity, angleRadians),
            onSearchForTarget   : SearchForTargetCallbacks.create(),
            onTrackTarget       : TrackTargetCallbacks.create(),
            onPreLaunchMove     : PreLaunchMoveCallbacks.create()
        };
    }
}
