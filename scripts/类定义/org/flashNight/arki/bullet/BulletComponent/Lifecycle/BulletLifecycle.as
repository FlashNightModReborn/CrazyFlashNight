// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle.as

import org.flashNight.arki.bullet.BulletComponent.Lifecycle.ILifecycle;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle implements ILifecycle {
    private var 射程阈值:Number;

    /**
     * 构造函数
     * @param 射程阈值:Number 子弹的射程限制。
     */
    public function BulletLifecycle(射程阈值:Number) {
        this.射程阈值 = 射程阈值;
    }

    /**
     * 检查对象是否需要被销毁或移除。
     * @param target:MovieClip 要检查的目标对象。
     * @return Boolean 是否需要销毁。
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        var 发射者:MovieClip = _root.gameworld[target.发射者名];
        if (发射者 == undefined) return false;

        // 缓存常用变量
        var targetX:Number = target._x;
        var targetY:Number = target._y;
        var 发射者X:Number = 发射者._x;
        var 发射者Y:Number = 发射者._y;

        // 判断是否超出射程
        var isOutOfRange:Boolean = !target.远距离不消失 &&
                                   (Math.abs(targetX - 发射者X) > this.射程阈值 ||
                                    Math.abs(targetY - 发射者Y) > this.射程阈值);

        // 地图碰撞检测
        var isCollidedWithMap:Boolean = this.checkMapCollision(target);

        if (isCollidedWithMap) {
            target.击中地图 = true;
        }

        return isOutOfRange || isCollidedWithMap;
    }

    /**
     * 检查子弹是否与地图碰撞。
     * @param target:MovieClip 目标对象。
     * @return Boolean 是否与地图碰撞。
     */
    private function checkMapCollision(target:MovieClip):Boolean {
        var 游戏世界:Object = _root.gameworld;
        var Z轴坐标:Number = target.Z轴坐标;
        var 近战检测:Boolean = target.近战检测;

        var Xmin:Number = _root.Xmin;
        var Xmax:Number = _root.Xmax;
        var Ymin:Number = _root.Ymin;
        var Ymax:Number = _root.Ymax;

        var targetX:Number = target._x;
        var targetY:Number = target._y;

        if (targetX < Xmin || targetX > Xmax || Z轴坐标 < Ymin || Z轴坐标 > Ymax) {
            return true;
        } else if (targetY > Z轴坐标 && !近战检测) {
            return true;
        } else {
            var 子弹地面坐标:Object = {x: targetX, y: Z轴坐标};
            游戏世界.localToGlobal(子弹地面坐标);
            return 游戏世界.地图.hitTest(子弹地面坐标.x, 子弹地面坐标.y, true);
        }
    }
}
