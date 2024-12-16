import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.CoverageAABBColliderFactory extends AbstractColliderFactory implements IColliderFactory {

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
        collider.updateFromTransparentBullet(bullet);
        return collider;
    }

    public function createFromBullet(bullet:MovieClip, detectionArea:MovieClip):ICollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider.updateFromBullet(bullet, detectionArea);
        return collider;
    }

    public function createFromUnitArea(unit:MovieClip):ICollider {
        var collider:CoverageAABBCollider = CoverageAABBCollider(this.getObject());
        collider.updateFromUnitArea(unit);
        return collider;
    }
}
