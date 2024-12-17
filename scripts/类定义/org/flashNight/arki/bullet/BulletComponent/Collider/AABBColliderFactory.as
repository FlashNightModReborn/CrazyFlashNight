import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.AABBColliderFactory extends AbstractColliderFactory implements IColliderFactory {
    private static var nullUpdate:Function = null; // 空更新函数
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
        collider._update = AABBColliderFactory.nullUpdate; // 透明子弹不需要更新 AABB
        collider._update(bullet);
        return collider;
    }

    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider = this.getObject();
        collider._update = collider.updateFromBullet;
        collider._update(bullet, detectionArea)
        return collider;
    }

    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider = this.getObject();
        collider._update - collider.updateFromUnitArea;
        collider._update(unit);
        return collider;
    }
}
