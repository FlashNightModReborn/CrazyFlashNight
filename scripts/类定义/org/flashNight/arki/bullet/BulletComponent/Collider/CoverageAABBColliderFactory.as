
/**
 * CoverageAABBColliderFactory
 * 
 * 基于 CoverageAABBCollider 的工厂实现，负责根据不同的数据来源
 * 来创建 CoverageAABBCollider 类型的 ICollider 实例。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.CoverageAABBColliderFactory implements IColliderFactory {

    /**
     * 基于透明子弹对象创建 CoverageAABBCollider 实例
     * @param bullet 透明子弹对象
     * @return ICollider 实例（CoverageAABBCollider）
     */
    public function createFromTransparentBullet(bullet:Object):ICollider {
        return CoverageAABBCollider.fromTransparentBullet(bullet);
    }

    /**
     * 基于子弹与检测区域创建 CoverageAABBCollider 实例
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     * @return ICollider 实例（CoverageAABBCollider）
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        return CoverageAABBCollider.fromBullet(bullet, detectionArea);
    }

    /**
     * 基于单位区域创建 CoverageAABBCollider 实例
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return ICollider 实例（CoverageAABBCollider）
     */
    public function createFromUnitArea(unit:MovieClip):ICollider {
        return CoverageAABBCollider.fromUnitArea(unit);
    }
}
