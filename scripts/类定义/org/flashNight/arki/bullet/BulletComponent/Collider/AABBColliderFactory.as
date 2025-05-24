import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * AABBColliderFactory 类
 * 
 * 碰撞器工厂类，继承自 AbstractColliderFactory 并实现 IColliderFactory 接口。
 * 该类主要用于创建和管理基于轴对齐边界框 (AABB) 的碰撞器实例。
 * 
 * 功能概述：
 * 1. 支持透明子弹、普通子弹和单位区域的碰撞器实例创建。
 * 2. 实现对象复用机制，避免频繁实例化，提高性能。
 * 3. 根据不同的输入参数自动设置碰撞器的更新逻辑。
 * 
 * 使用场景：
 * - 在需要频繁创建和销毁碰撞器的场景下，提供高效的对象管理和复用。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory 
    extends AbstractColliderFactory implements IColliderFactory {
    
    /**
     * 静态属性：空更新函数。
     * 当碰撞器不需要更新时，将此属性赋值为更新函数，避免无用的逻辑调用。
     */
    private static var nullUpdate:Function = null;

    /**
     * 构造函数
     * 
     * 初始化 AABBColliderFactory 实例，并预先分配一定数量的碰撞器。
     * 
     * @param initialSize 初始分配的碰撞器数量，可选参数，默认值为 0。
     */
    public function AABBColliderFactory(initialSize:Number) {
        super(function():AABBCollider {
            // 工厂方法：创建默认的 AABBCollider 实例
            return new AABBCollider(0, 0, 0, 0);
        }, initialSize);
    }

    /**
     * 创建透明子弹的碰撞器实例。
     * 
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 将碰撞器的更新函数设为 nullUpdate，表示无需更新边界信息。
     * 3. 调用空更新函数 (占位) 并返回碰撞器。
     * 
     * @param bullet 透明子弹对象，包含坐标信息。
     * @return ICollider 透明子弹的碰撞器实例。
     */
    public function createFromTransparentBullet(bullet:Object):ICollider {
        var collider = this.getObject();
        // collider._update = AABBColliderFactory.nullUpdate; // 无需更新边界
        // collider._update(bullet);
        return collider;
    }

    /**
     * 创建普通子弹的碰撞器实例。
     * 
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 将碰撞器的更新函数设为 updateFromBullet。
     * 3. 调用更新函数，基于子弹和检测区域设置 AABB 边界。
     * 
     * @param bullet        子弹的 MovieClip 实例，包含坐标信息。
     * @param detectionArea 子弹的检测区域 MovieClip 实例，用于计算边界坐标。
     * @return ICollider 普通子弹的碰撞器实例。
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider = this.getObject();
        collider._update = collider.updateFromBullet; // 设置更新函数
        collider._update(bullet, detectionArea); // 更新碰撞器的边界信息
        return collider;
    }

    /**
     * 创建单位区域的碰撞器实例。
     * 
     * 实现流程：
     * 1. 获取一个空闲的碰撞器对象。
     * 2. 将碰撞器的更新函数设为 updateFromUnitArea。
     * 3. 调用更新函数，基于单位区域更新 AABB 边界。
     * 
     * @param unit 单位区域的 MovieClip 实例，包含 area 属性。
     * @return ICollider 单位区域的碰撞器实例。
     */
    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider = this.getObject();
        collider._update = collider.updateFromUnitArea; // 设置更新函数
        collider._update(unit); // 更新碰撞器的边界信息
        return collider;
    }
}
