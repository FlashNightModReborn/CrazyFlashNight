import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * RayColliderFactory 类
 * 
 * 射线碰撞器工厂类，继承自 AbstractColliderFactory 并实现 IColliderFactory 接口。
 * 该类用于创建和管理基于射线的碰撞器实例。
 *
 * 功能概述：
 * 1. 支持透明子弹、普通子弹和单位区域的射线碰撞器实例创建。
 * 2. 实现对象复用机制，避免频繁实例化，提高性能。
 * 3. 射线碰撞器使用默认方向(1,0)和默认长度100，可通过setRay方法动态更新。
 *
 * 使用场景：
 * - 用于激光、射线类武器的碰撞检测
 * - 用于视线检测、射击判定等需要射线碰撞的场景
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.RayColliderFactory
    extends AbstractColliderFactory implements IColliderFactory {

    /** 默认射线方向 */
    private static var DEFAULT_DIRECTION:Vector = new Vector(1, 0);

    /** 默认射线长度 */
    private static var DEFAULT_MAX_DISTANCE:Number = 100;

    /**
     * 构造函数
     *
     * 初始化 RayColliderFactory 实例，并预先分配一定数量的碰撞器。
     *
     * @param initialSize 初始分配的碰撞器数量，可选参数，默认值为 0。
     */
    public function RayColliderFactory(initialSize:Number) {
        super(function():RayCollider {
            // 工厂方法：创建默认的 RayCollider 实例
            // 使用默认起点(0,0)、默认方向(1,0)、默认长度100
            return new RayCollider(
                new Vector(0, 0),
                RayColliderFactory.DEFAULT_DIRECTION,
                RayColliderFactory.DEFAULT_MAX_DISTANCE
            );
        }, initialSize);
    }

    /**
     * 创建透明子弹的射线碰撞器实例。
     *
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 使用透明子弹的坐标更新射线起点。
     *
     * @param bullet 透明子弹对象，包含 _x, _y 坐标信息。
     * @return ICollider 透明子弹的射线碰撞器实例。
     */
    public function createFromTransparentBullet(bullet:Object):ICollider {
        var collider:RayCollider = RayCollider(this.getObject());
        collider.updateFromTransparentBullet(bullet);
        return collider;
    }

    /**
     * 创建普通子弹的射线碰撞器实例。
     *
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 使用子弹的坐标更新射线起点。
     *
     * @param bullet        子弹的 MovieClip 实例，包含坐标信息。
     * @param detectionArea 子弹的检测区域 MovieClip 实例（射线碰撞器暂不使用此参数）。
     * @return ICollider 普通子弹的射线碰撞器实例。
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider:RayCollider = RayCollider(this.getObject());
        collider.updateFromBullet(bullet, detectionArea);
        return collider;
    }

    /**
     * 创建单位区域的射线碰撞器实例。
     *
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 使用单位区域的中心点作为射线起点。
     *
     * @param unit 单位区域的 MovieClip 实例，包含 area 属性。
     * @return ICollider 单位区域的射线碰撞器实例。
     */
    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider:RayCollider = RayCollider(this.getObject());
        collider.updateFromUnitArea(unit);
        return collider;
    }

    /**
     * 创建自定义射线碰撞器实例。
     *
     * 该方法允许完全自定义射线的起点、方向和长度。
     *
     * @param origin      射线起点
     * @param direction   射线方向（会被归一化）
     * @param maxDistance 射线最大长度
     * @return RayCollider 自定义的射线碰撞器实例
     */
    public function createCustomRay(origin:Vector, direction:Vector, maxDistance:Number):RayCollider {
        var collider:RayCollider = RayCollider(this.getObject());
        collider.setRay(origin, direction, maxDistance);
        return collider;
    }
}
