import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

interface org.flashNight.arki.bullet.BulletComponent.Collider.ICollider {
    /**
     * 检查与另一个碰撞器是否发生碰撞
     * 
     * @param other 另一个 ICollider 实例
     * @return CollisionResult 实例，包含碰撞结果及相关信息
     */
    function checkCollision(other:ICollider):CollisionResult;
    
    /**
     * 获取碰撞器的 AABB 信息
     * 
     * @return AABB 实例，表示碰撞器的轴对齐边界框
     */
    function getAABB():AABB;
}
