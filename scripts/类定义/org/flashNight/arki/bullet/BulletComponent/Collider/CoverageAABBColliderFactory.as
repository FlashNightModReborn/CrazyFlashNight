import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

/**
 * CoverageAABBColliderFactory
 * 
 * 继承自 AABBColliderFactory，用于创建 CoverageAABBCollider 类型的碰撞器实例。
 * 重用 AABBColliderFactory 的对象池逻辑，并扩展支持 CoverageAABBCollider。
 */

import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.CoverageAABBColliderFactory extends AABBColliderFactory implements IColliderFactory {

    /**
     * 构造函数
     * 
     * @param initialSize 初始分配的碰撞器数量，可选
     */
    public function CoverageAABBColliderFactory(initialSize:Number) {
        // 直接调用 LightObjectPool 的构造函数，避免间接调用带来的语义混淆
        LightObjectPool.call(this, function():CoverageAABBCollider {
            return new CoverageAABBCollider(null);
        });

        // 初始化对象池
        if (initialSize > 0) {
            for (var i:Number = 0; i < initialSize; i++) {
                this.releaseObject(new CoverageAABBCollider(null));
            }
        }
    }

    /**
     * 基于透明子弹对象创建 CoverageAABBCollider 实例（从对象池获取）
     * @param bullet 透明子弹对象
     * @return CoverageAABBCollider 实例
     */
    public function createFromTransparentBullet(bullet:Object):CoverageAABBCollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider.updateFromTransparentBullet(bullet);
        return collider;
    }

    /**
     * 基于子弹与检测区域创建 CoverageAABBCollider 实例（从对象池获取）
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     * @return CoverageAABBCollider 实例
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):CoverageAABBCollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider.updateFromBullet(bullet, detectionArea);
        return collider;
    }

    /**
     * 基于单位区域创建 CoverageAABBCollider 实例（从对象池获取）
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return CoverageAABBCollider 实例
     */
    public function createFromUnitArea(unit:MovieClip):CoverageAABBCollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider.updateFromUnitArea(unit);
        return collider;
    }

    /**
     * 将使用完毕的 CoverageAABBCollider 回收到对象池中
     * @param collider CoverageAABBCollider 实例
     */
    public function releaseCollider(collider:CoverageAABBCollider):Void {
        this.releaseObject(collider);
    }
}
