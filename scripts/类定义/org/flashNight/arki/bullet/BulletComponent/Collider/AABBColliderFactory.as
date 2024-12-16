import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory extends LightObjectPool implements IColliderFactory {

    /**
     * 构造函数
     * @param initialSize 初始分配的碰撞器数量，可选
     */
    public function AABBColliderFactory(initialSize:Number) {
        // 父类构造时传入创建函数
        super(function():AABBCollider {
            // 初始化一个默认的 AABBCollider 对象
            return new AABBCollider(null);
        });

        // 若指定了 initialSize，可预先分配对应数量的碰撞器实例到池中
        if (initialSize > 0) {
            for (var i:Number = 0; i < initialSize; i++) {
                this.releaseObject(new AABBCollider(null));
            }
        }
    }

    /**
     * 基于透明子弹创建 AABBCollider 实例（从对象池获取）
     * @param bullet 透明子弹对象
     * @return AABBCollider 实例
     */
    public function createFromTransparentBullet(bullet:Object):AABBCollider {
        var collider:AABBCollider = AABBCollider(this.getObject());
        collider.updateFromTransparentBullet(bullet);
        return collider;
    }

    /**
     * 基于子弹与检测区域创建 AABBCollider 实例（从对象池获取）
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹检测区域 MovieClip 实例
     * @return AABBCollider 实例
     */
    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):AABBCollider {
        var collider:AABBCollider = AABBCollider(this.getObject());
        collider.updateFromBullet(bullet, detectionArea);
        return collider;
    }

    /**
     * 基于单位区域创建 AABBCollider 实例（从对象池获取）
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return AABBCollider 实例
     */
    public function createFromUnitArea(unit:MovieClip):AABBCollider {
        var collider:AABBCollider = AABBCollider(this.getObject());
        collider.updateFromUnitArea(unit);
        return collider;
    }
}
