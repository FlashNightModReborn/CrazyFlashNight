// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycle.as
import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.ILifecycle;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;

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

        var targetX:Number = target._x;
        var targetY:Number = target._y;
        var 发射者X:Number = 发射者._x;
        var 发射者Y:Number = 发射者._y;

        var isOutOfRange:Boolean = !target.远距离不消失 &&
                                   (Math.abs(targetX - 发射者X) > this.射程阈值 ||
                                    Math.abs(targetY - 发射者Y) > this.射程阈值);

        var isCollidedWithMap:Boolean = this.checkMapCollision(target);

        if (isCollidedWithMap) {
            target.击中地图 = true;
        }

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
        var isAxisAlignedChain = target.联弹检测 && !isRotated;
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
