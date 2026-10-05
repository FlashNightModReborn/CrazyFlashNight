import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;

/**
 * 三种穿刺共用生命周期与默认命中转换。
 *
 * 兼容阶段保留原 MovieClip 的碰撞 area、消失标签和帧推进；不把静态帧表
 * 猜成新的 tick 定时器。这样保留同帧多目标继续结算、间歇 area、地图回调
 * 以及消弹令牌引发的尾帧碰撞。NormalBulletLifecycle 的预检查/销毁不变。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.PierceBulletLifecycle extends NormalBulletLifecycle {
    public static var BASIC:PierceBulletLifecycle = new PierceBulletLifecycle();

    public function PierceBulletLifecycle() {
        super(900);
    }

    /** 退场帧保留碰撞/地图检测，让素材播完；射程不能每帧重启同一消失动画。 */
    public function shouldDestroy(target:MovieClip):Boolean {
        if (target._currentframe > 1) {
            #include "../macros/STATE_HIT_MAP.as"
            // 父类地图检测为 private；保持同一 Y/Z 与像素判定，并写权威状态位。
            var hitMap:Boolean = target._y > target.Z轴坐标
                || _root.collisionLayer.hitTest(target._x, target.Z轴坐标, true);
            if (hitMap) target.stateFlags |= STATE_HIT_MAP;
            return hitMap;
        }
        return super.shouldDestroy(target);
    }
    /**
     * 必须在 attachMovie 前传入。XFL 第1帧仅在 hook 为假值时安装旧默认函数，
     * 因此预先提供共用执行器可以接管默认行为，同时保留装备传入的自定义函数。
     * 返回副本，不能把每发的状态/函数回写给可复用发射模板。
     */
    public static function prepareInit(source:Object, profile:PierceBulletProfile):Object {
        var result:Object = {};
        for (var key:String in source) result[key] = source[key];
        result.__pierceProfile = profile;
        if (profile.firstHitLabel != null && !result.击中时触发函数) {
            result.击中时触发函数 = createDefaultHit();
        }
        if (profile.removeOnMapHit && !result.击中地图时触发函数) {
            result.击中地图时触发函数 = function():Void { this.removeMovieClip(); };
        }
        return result;
    }

    private static function createDefaultHit():Function {
        return function():Void {
            var target:Object = this;
            var profile:PierceBulletProfile = target.__pierceProfile;
            if (!target.已爆炸) {
                target.已爆炸 = true;
                // 帧跳转放最后；Flash 会同步卸载旧帧 area，当前碰撞队列仍继续使用
                // 已取得的 AABB，保持本帧后续目标和预算记账的原有顺序。
                target.gotoAndPlay(profile.firstHitLabel);
            } else if (profile.disableRepeatedHitHook) {
                target.击中时触发函数 = false;
            }
        };
    }
}
