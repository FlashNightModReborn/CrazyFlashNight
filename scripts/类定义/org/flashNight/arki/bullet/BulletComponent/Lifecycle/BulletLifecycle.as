// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle.as
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.ILifecycle;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle implements ILifecycle {

    public static var BASIC:BulletLifecycle = new BulletLifecycle(900);

    private var rangeThreshold:Number;

    /**
     * 构造函数
     * @param rangeThreshold:Number 子弹的射程限制。
     */
    public function BulletLifecycle(rangeThreshold:Number) {
        this.rangeThreshold = rangeThreshold;
    }

    /**
     * 检查对象是否需要被销毁或移除。
     * @param target:MovieClip 要检查的目标对象。
     * @return Boolean 是否需要销毁。
     */
    public function shouldDestroy(target:MovieClip):Boolean {
        var shooter:MovieClip = _root.gameworld[target.发射者名];
        
        if (shooter == undefined) return false;

        var targetX:Number = target._x;
        var targetY:Number = target._y;
        var shooterX:Number = shooter._x;
        var shooterY:Number = shooter._y;

        var isOutOfRange:Boolean = !target.远距离不消失 &&
                                   (Math.abs(targetX - shooterX) > this.rangeThreshold ||
                                    Math.abs(targetY - shooterY) > this.rangeThreshold);

        var isCollidedWithMap:Boolean = this.checkMapCollision(target);

        if (isCollidedWithMap) {
            target.击中地图 = true;
        }

        // _root.发布消息("[BulletLifecycle] Bullet should be destroyed: " + isOutOfRange + ", " + isCollidedWithMap);

        return isOutOfRange || isCollidedWithMap;
    }

    /**
     * 为目标对象绑定生命周期逻辑。
     * @param target:MovieClip 要绑定生命周期的目标对象。
     */
    public function bindLifecycle(target:MovieClip):Void {
        var areaAABB:ICollider;
        var detectionArea:MovieClip;
        var bulletRotation:Number = target._rotation; // 本地化避免多次访问造成getter开销
        var isRotated:Boolean = (bulletRotation != 0 && bulletRotation != 180);
        var factory:IColliderFactory;

        if(target.联弹检测)
        {
            if(isRotated)
            {
                factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);

                target.polygonCollider = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.PolygonFactory).createFromBullet(target);
            }
            else
            {
                factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.CoverageAABBFactory);
            }
        }
        else
        {
            factory = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.AABBFactory);
        }
        // 判断是否透明检测，设置 AABB 碰撞区域
        if (target.透明检测 && !target.子弹区域area) {
            areaAABB = factory.createFromTransparentBullet(target);
        } else {
            detectionArea = target.子弹区域area || target.area;
            areaAABB = factory.createFromBullet(target, detectionArea);
        }

        // 绑定 AABB 碰撞区域到子弹实例
        target.aabbCollider = areaAABB;
        // 判断是否需要绑定 onEnterFrame

        target.additionalEffectDamage = 0;

        // 在执行结算前设置伤害管理器
        target.damageManager = DamageManagerFactory.Basic.getDamageManager(target);

        _root.子弹生命周期.call(target);
        if(!target.透明检测) target.onEnterFrame = _root.子弹生命周期;
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
