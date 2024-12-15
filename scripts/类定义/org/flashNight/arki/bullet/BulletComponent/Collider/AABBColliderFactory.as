import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

/**
 * AABBColliderFactory
 * 
 * 基于 AABBCollider 的工厂实现，负责根据不同的数据来源
 * 来创建 AABBCollider 类型的 ICollider 实例。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory implements IColliderFactory {

    /**
     * 基于透明子弹对象创建 AABBCollider 实例
     * @param bullet 透明子弹对象
     * @return ICollider 实例（AABBCollider）
     */
    public function createFromTransparentBullet(bullet:Object):ICollider {
        return AABBCollider.fromTransparentBullet(bullet);
    }

    /**
     * 基于子弹与检测区域创建 AABBCollider 实例
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     * @return ICollider 实例（AABBCollider）
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        return AABBCollider.fromBullet(bullet, detectionArea);
    }

    /**
     * 基于单位区域创建 AABBCollider 实例
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return ICollider 实例（AABBCollider）
     */
    public function createFromUnitArea(unit:MovieClip):ICollider {
        return AABBCollider.fromUnitArea(unit);
    }
}