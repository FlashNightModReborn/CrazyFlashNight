import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * PointColliderFactory 类
 *
 * 点碰撞器工厂类，继承自 AbstractColliderFactory 并实现 IColliderFactory 接口。
 * 该类用于创建和管理基于点的碰撞器实例。
 *
 * 功能概述：
 * 1. 支持透明子弹、普通子弹和单位区域的点碰撞器实例创建。
 * 2. 实现对象复用机制，避免频繁实例化，提高性能。
 * 3. 点碰撞器的 AABB 为零体积（左右边界相等，上下边界相等）。
 *
 * 使用场景：
 * - 用于精确命中检测（如狙击枪、激光指示器）
 * - 用于点击检测、拾取判定等单点碰撞场景
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.PointColliderFactory
    extends AbstractColliderFactory implements IColliderFactory {

    /**
     * 构造函数
     *
     * 初始化 PointColliderFactory 实例，并预先分配一定数量的碰撞器。
     *
     * @param initialSize 初始分配的碰撞器数量，可选参数，默认值为 0。
     */
    public function PointColliderFactory(initialSize:Number) {
        super(function():PointCollider {
            // 工厂方法：创建默认的 PointCollider 实例
            // 使用默认位置 (0, 0)
            return new PointCollider(0, 0);
        }, initialSize);
    }

    /**
     * 创建透明子弹的点碰撞器实例。
     *
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 使用透明子弹的坐标更新点位置。
     *
     * @param bullet 透明子弹对象，包含 _x, _y 坐标信息。
     * @return ICollider 透明子弹的点碰撞器实例。
     */
    public function createFromTransparentBullet(bullet:Object):ICollider {
        var collider:PointCollider = PointCollider(this.getObject());
        collider.updateFromTransparentBullet(bullet);
        return collider;
    }

    /**
     * 创建普通子弹的点碰撞器实例。
     *
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 使用子弹的坐标更新点位置。
     *
     * @param bullet        子弹的 MovieClip 实例，包含坐标信息。
     * @param detectionArea 子弹的检测区域 MovieClip 实例（点碰撞器暂不使用此参数）。
     * @return ICollider 普通子弹的点碰撞器实例。
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider:PointCollider = PointCollider(this.getObject());
        collider.updateFromBullet(bullet, detectionArea);
        return collider;
    }

    /**
     * 创建单位区域的点碰撞器实例。
     *
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 使用单位区域的中心点作为点位置。
     *
     * @param unit 单位区域的 MovieClip 实例，包含 area 属性。
     * @return ICollider 单位区域的点碰撞器实例。
     */
    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider:PointCollider = PointCollider(this.getObject());
        collider.updateFromUnitArea(unit);
        return collider;
    }

    /**
     * 创建自定义点碰撞器实例。
     *
     * 该方法允许直接指定点的位置。
     *
     * @param x 点的 x 坐标
     * @param y 点的 y 坐标
     * @return PointCollider 自定义的点碰撞器实例
     */
    public function createAtPosition(x:Number, y:Number):PointCollider {
        var collider:PointCollider = PointCollider(this.getObject());
        collider.setPosition(x, y);
        return collider;
    }
}
