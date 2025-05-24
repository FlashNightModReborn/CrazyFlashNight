import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.BulletColliderHandler {

    /**
     * 检查子弹与目标单位之间的碰撞
     * @param bullet 当前子弹对象
     * @param hitTarget 检测目标对象
     * @param areaAABB 当前子弹的AABB碰撞器
     * @param detectionArea 检测区域
     * @param zOffset Z轴偏移值
     * @param isPointSet 是否启用精确多边形检测
     * @return CollisionResult 返回碰撞检测结果
     */
    public static function checkBulletCollision(
        bullet:MovieClip, 
        hitTarget:MovieClip, 
        areaAABB:AABBCollider, 
        detectionArea:MovieClip, 
        zOffset:Number, 
        isPointSet:Boolean
    ):CollisionResult {
        // 更新目标单位的碰撞区域
        var unitArea:AABBCollider = hitTarget.aabbCollider;
        unitArea.updateFromUnitArea(hitTarget);

        // 执行初步的AABB碰撞检测
        var result:CollisionResult = areaAABB.checkCollision(unitArea, zOffset);

        // 如果启用精确多边形检测，执行进一步检测
        if (isPointSet && result.isColliding) {
            bullet.polygonCollider.updateFromBullet(bullet, detectionArea);
            result = bullet.polygonCollider.checkCollision(unitArea, zOffset);
        }

        // 返回最终的碰撞结果
        return result;
    }
}
