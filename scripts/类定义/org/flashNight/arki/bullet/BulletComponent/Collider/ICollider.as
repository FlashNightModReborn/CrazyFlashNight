import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

interface org.flashNight.arki.bullet.BulletComponent.Collider.ICollider {
    /**
     * 检查与另一个碰撞器是否发生碰撞
     * 
     * @param other 另一个 ICollider 实例
     * @param zOffset 碰撞体之间的Z轴差，用于模拟3d高度
     * @return CollisionResult 实例，包含碰撞结果及相关信息
     */
    function checkCollision(other:ICollider ,zOffset:Number):CollisionResult;
    
    /**
     * 获取碰撞器的 AABB 信息
     * @param zOffset 碰撞体之间的Z轴差，用于模拟3d高度
     * @return AABB 实例，表示碰撞器的轴对齐边界框
     */
    function getAABB(zOffset:Number):AABB;
}
