import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.CoverageAABBColliderFactory extends AbstractColliderFactory implements IColliderFactory {

    public static var nullUpdate:Function = null;
    
    /**
     * 构造函数
     * @param initialSize 初始分配的碰撞器数量，可选
     */
    public function CoverageAABBColliderFactory(initialSize:Number) {
        super(function():CoverageAABBCollider {
            return new CoverageAABBCollider(0,0,0,0);
        }, initialSize);
    }

    public function createFromTransparentBullet(bullet:Object):ICollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider._update = CoverageAABBColliderFactory.nullUpdate; // 透明子弹不需要更新 AABB
        collider._update(bullet);
        return collider;
    }

    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider._update = collider.updateFromBullet;
        collider._update(bullet, detectionArea)
        return collider;
    }

    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider._update - collider.updateFromUnitArea;
        collider._update(unit);
        return collider;
    }
}
