import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.CollisionResult {
    public var isColliding:Boolean;       // 碰撞是否发生（必要字段）
    public var overlapCenter:Vector;      // 碰撞中心点（可选字段）
    public var additionalInfo:Object;    // 额外碰撞信息（可选字段）

    /**
     * 碰撞器进行碰撞检测的结果对象
     * 
     * @param isColliding 碰撞检测的结果
     * @param overlapCenter 碰撞中心，用于定位特效发生的坐标
     */
    public function CollisionResult(isColliding:Boolean, overlapCenter:Vector) {
        this.isColliding = isColliding;
        this.overlapCenter = overlapCenter || {}; // 未碰撞则不必提供碰撞中心，这里用空对象占位
    }

    /**
     * 添加额外信息的包装方法，从性能来说，直接通过属性操作来添加额外信息更优
     * 
     * @param key 
     * @param value 
     * @return 
     */
    public function addInfo(key:String, value):Void {
        this.additionalInfo[key] = value;
    }
}
