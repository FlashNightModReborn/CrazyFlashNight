import org.flashNight.sara.util.*;
import org.flashNight.gesh.object.*
import org.flashNight.arki.component.Collider.*;

class org.flashNight.arki.component.Collider.CollisionResult {
    public var isColliding:Boolean;       // 碰撞是否发生（必要字段）
    public var isOrdered:Boolean;         // X轴有序标记：false=在目标左侧分离 (提前退出用)
    public var isYOrdered:Boolean;        // Y轴有序标记：false=在目标上方分离 (提前退出用)
    public var overlapCenter:Vector;      // 碰撞中心点（可选字段）
    public var overlapRatio:Number;       // 重叠比率（可选字段）
    public var additionalInfo:Object;     // 额外碰撞信息（可选字段）

    // 静态属性：表示无碰撞结果的常量实例
    //
    // 语义说明（0成本约束下的信息最大化）：
    // - FALSE:       X右侧或Y下方分离，isOrdered=true, isYOrdered=true
    // - ORDERFALSE:  X左侧分离（Y状态未检查），isOrdered=false, isYOrdered=true
    // - YORDERFALSE: Y上方分离（已确认X不在左侧），isOrdered=true, isYOrdered=false
    //
    // 注意：由于早退机制，ORDERFALSE 返回时 Y 轴实际未检测，isYOrdered=true 表示"未检测到Y轴无序"
    public static var FALSE:CollisionResult = CollisionResult.createFalse();
    public static var ORDERFALSE:CollisionResult = CollisionResult.createOrderFalse();
    public static var YORDERFALSE:CollisionResult = CollisionResult.createYOrderFalse();

    /**
     * 碰撞器进行碰撞检测的结果对象
     * 
     * @param isColliding 碰撞检测的结果
     */
    public function CollisionResult(isColliding:Boolean) {
        this.isColliding = isColliding;
        // this.additionalInfo = {}; // 初始化为空对象，避免 null 检查
    }
    
    public static function Create(isColliding:Boolean, overlapCenter:Vector, overlapRatio:Number, additionalInfo:Object):CollisionResult
    {
        var cr:CollisionResult = new CollisionResult(isColliding);
        cr.overlapCenter = overlapCenter;
        cr.overlapRatio = overlapRatio;
        cr.additionalInfo = additionalInfo;
        return cr;
    }

    public static function createFalse():CollisionResult
    {
        var result:CollisionResult = new CollisionResult(false);
        result.isOrdered = true;
        result.isYOrdered = true;
        return result;
    }

    public static function createOrderFalse():CollisionResult
    {
        var result:CollisionResult = new CollisionResult(false);
        result.isOrdered = false;
        result.isYOrdered = true;  // Y轴未检测，默认为true
        return result;
    }

    public static function createYOrderFalse():CollisionResult
    {
        var result:CollisionResult = new CollisionResult(false);
        result.isOrdered = true;   // 已确认X不在左侧
        result.isYOrdered = false;
        return result;
    }

    /**
     * 设置碰撞中心的包装方法
     * 
     * @param overlapCenter 碰撞中心点
     */
    public function setOverlapCenter(overlapCenter:Vector):Void {
        this.overlapCenter = overlapCenter;
    }

    /**
     * 设置覆盖率的包装方法
     * 
     * @param 覆盖率的大小，数值范围是0-1
     */
    public function setOverlapRatio(ratio:Number):Void {
        this.overlapRatio = ratio;
    }


    /**
     * 添加额外信息的包装方法
     * 
     * @param key 键
     * @param value 值
     */
    public function addInfo(key:String, value):Void {
        this.additionalInfo[key] = value;
    }

    public function toString():String
    {
        var str:String = "[CR]" + String(isColliding);

        if(!isColliding) return str;

        str += " " + String(overlapCenter) + " " + String(overlapRatio);

        if(!additionalInfo) return str;

        return str + " " + additionalInfo;
    }

    public function clone():CollisionResult
    {
        var cr:CollisionResult = new CollisionResult(null);
        cr.isColliding = this.isColliding;
        cr.overlapCenter = this.overlapCenter.clone();
        cr.overlapRatio = this.overlapRatio;

        if(!cr.addInfo)  return cr;

        cr.addInfo = ObjectUtil.clone(this.additionalInfo);

        return cr;
    }
}