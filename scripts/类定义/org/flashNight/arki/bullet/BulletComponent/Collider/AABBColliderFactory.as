import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory extends AbstractColliderFactory implements IColliderFactory {

    /**
     * 构造函数
     * @param initialSize 初始分配的碰撞器数量，可选
     */
    public function AABBColliderFactory(initialSize:Number) {
        super(function():AABBCollider {
            // 初始化一个默认的 AABBCollider 对象
            return new AABBCollider(0,0,0,0);
        }, initialSize);
    }

    public function createFromTransparentBullet(bullet:Object):ICollider {
        var collider = this.getObject();
        collider.
        collider.updateFromTransparentBullet(bullet);
        return collider;
    }

    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider = this.getObject();
        collider.updateFromBullet(bullet, detectionArea);
        return collider;
    }

    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider = this.getObject();
        collider.updateFromUnitArea(unit);
        return collider;
    }
}
