import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * PolygonColliderFactory 类
 *
 * 碰撞器工厂类，继承自 AbstractColliderFactory 并实现 IColliderFactory 接口。
 * 用于创建和管理基于多边形(PointSet)的碰撞器实例（PolygonCollider）。
 *
 * 功能概述：
 * 1. 创建适用于透明子弹、普通子弹、单位区域的 PolygonCollider。
 * 2. 通过对象池机制重用实例，提高性能。
 * 3. 根据不同输入参数设置合适的更新函数，实现多态更新。
 *
 * 使用场景：
 * - 在需要频繁创建、销毁多边形碰撞器的场景中通过工厂降低实例化开销。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonColliderFactory 
    extends AbstractColliderFactory implements IColliderFactory {

    /**
     * 静态属性：空更新函数。
     * 当碰撞器不需要后续动态更新时，可将此属性赋值为更新函数，用于占位。
     */
    private static var nullUpdate:Function = null;

    /**
     * 构造函数
     * 
     * 初始化 PolygonColliderFactory 实例，并预先分配一定数量的碰撞器。
     * 
     * @param initialSize 初始分配的碰撞器数量，可选参数，默认值为0。
     */
    public function PolygonColliderFactory(initialSize:Number) {
        super(function():PolygonCollider {
            // 工厂方法：创建默认的 PolygonCollider 实例（空点集）
            return new PolygonCollider();
        }, initialSize);
    }

    /**
     * 创建适用于透明子弹的 PolygonCollider 实例。
     * 
     * 实现流程：
     * 1. 从对象池获取一个空闲的 PolygonCollider。
     * 2. 将更新函数设置为 updateFromTransparentBullet。
     * 3. 调用更新函数，根据透明子弹坐标构造固定形状的多边形。
     * 
     * @param bullet 透明子弹对象，包含坐标信息。
     * @return ICollider 对应的 PolygonCollider 实例。
     */
    public function createFromTransparentBullet(bullet:Object):ICollider {
        var collider:PolygonCollider = PolygonCollider(this.getObject());
        collider._update = collider.updateFromTransparentBullet;
        collider._update(bullet);
        return collider;
    }

    /**
     * 创建适用于普通子弹的 PolygonCollider 实例。
     * 
     * 实现流程：
     * 1. 从对象池获取一个空闲的 PolygonCollider。
     * 2. 将更新函数设置为 updateFromBullet。
     * 3. 调用更新函数，将检测区域转换为游戏世界点集更新到碰撞器。
     * 
     * @param bullet 子弹MovieClip实例。
     * @param detectionArea 子弹的检测区域MovieClip实例。
     * @return ICollider 对应的 PolygonCollider 实例。
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider:PolygonCollider = PolygonCollider(this.getObject());
        collider._update = collider.updateFromBullet;
        collider._update(bullet, detectionArea);
        return collider;
    }

    /**
     * 创建适用于单位区域的 PolygonCollider 实例。
     * 
     * 实现流程：
     * 1. 从对象池获取一个空闲的 PolygonCollider。
     * 2. 将更新函数设置为 updateFromUnitArea。
     * 3. 调用更新函数，基于单位区域更新多边形点集（通常为矩形）。
     * 
     * @param unit 包含 area 属性的单位MovieClip实例。
     * @return ICollider 对应的 PolygonCollider 实例。
     */
    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider:PolygonCollider = PolygonCollider(this.getObject());
        collider._update = collider.updateFromUnitArea;
        collider._update(unit);
        return collider;
    }
}
