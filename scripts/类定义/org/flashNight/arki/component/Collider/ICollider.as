import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

interface org.flashNight.arki.component.Collider.ICollider {
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

    /**
     * 更新 ICollider 实例的边界信息，基于透明子弹对象
     * 
     * @param bullet 透明子弹对象
     */
    function updateFromTransparentBullet(bullet:Object):Void;

    /**
     * 更新 ICollider 实例的边界信息，基于子弹和检测区域的 MovieClip 实例
     * 
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     */
    function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void;

    /**
     * 更新 ICollider 实例的边界信息，基于单位区域的 MovieClip 实例
     * 
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    function updateFromUnitArea(unit:MovieClip):Void;

    function setFactory(factory:AbstractColliderFactory):Void;  // 设置工厂引用
    function getFactory():AbstractColliderFactory;             // 获取工厂引用
}
