import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * CoverageAABBColliderFactory 类
 *
 * 继承自 AbstractColliderFactory，实现 IColliderFactory 接口。
 * 该类专门用于创建和管理 CoverageAABBCollider 实例，并支持对象复用。
 * 
 * 功能概述：
 * 1. 提供三种创建方法，分别针对透明子弹、普通子弹和单位区域。
 * 2. 通过对象池机制实现碰撞器的复用，避免频繁的实例化和销毁。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.CoverageAABBColliderFactory 
    extends AbstractColliderFactory implements IColliderFactory {

    /**
     * 静态属性：空更新函数。
     * 用于无需更新的碰撞器，如透明子弹。
     */
    public static var nullUpdate:Function = null;

    /**
     * 构造函数
     * 
     * @param initialSize 初始分配的碰撞器数量，可选，默认值为 0。
     */
    public function CoverageAABBColliderFactory(initialSize:Number) {
        super(function():CoverageAABBCollider {
            // 工厂方法：创建默认的 CoverageAABBCollider 实例
            return new CoverageAABBCollider(0, 0, 0, 0);
        }, initialSize);
    }

    /**
     * 创建透明子弹的碰撞器实例。
     * 
     * @param bullet 透明子弹对象
     * @return ICollider 实例
     */
    public function createFromTransparentBullet(bullet:Object):ICollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        // collider._update = CoverageAABBColliderFactory.nullUpdate; // 不需要更新边界
        // collider._update(bullet);
        return collider;
    }

    /**
     * 创建普通子弹的碰撞器实例。
     * 
     * @param bullet        子弹的 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     * @return ICollider 实例
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider._update = collider.updateFromBullet;
        collider._update(bullet, detectionArea);
        return collider;
    }

    /**
     * 创建单位区域的碰撞器实例。
     * 
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return ICollider 实例
     */
    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider._update = collider.updateFromUnitArea;
        collider._update(unit);
        return collider;
    }
}
