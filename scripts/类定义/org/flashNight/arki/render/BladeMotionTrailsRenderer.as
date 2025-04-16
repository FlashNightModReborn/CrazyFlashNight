import org.flashNight.arki.render.*;
import org.flashNight.sara.util.*;

/**
 * BladeMotionTrailsRenderer 刀口残影渲染器
 * 
 * 本类用于计算并渲染刀口残影效果，根据不同的性能需求提供三种计算方式：
 *   - PERFORMANCE_LEVEL_HIGH：高性能实现（复杂计算，全局中轴处理与收缩）
 *   - PERFORMANCE_LEVEL_MEDIUM：中性能实现（局部计算，每个刀口独立收缩）
 *   - PERFORMANCE_LEVEL_LOW：低性能实现（直接使用坐标，不做额外计算）
 * 
 * 调用前请先调用 setPerformanceLevel() 指定所需性能等级。所有处理均为静态方法，
 * 本类不允许被实例化。
 */
class org.flashNight.arki.render.BladeMotionTrailsRenderer {

    // ---------------------------
    // 性能等级常量
    // ---------------------------
    public static var PERFORMANCE_LEVEL_HIGH:Number   = 0;
    public static var PERFORMANCE_LEVEL_MEDIUM:Number = 1;
    public static var PERFORMANCE_LEVEL_LOW:Number    = 2;

    /**
     * 当前选定的刀口残影计算方法（默认为高性能实现）
     */
    public static var processBladeTrail:Function = processBladeTrailHigh;

    /**
     * 私有构造函数，禁止外部实例化。
     * 此类仅提供静态方法，不允许被实例化。
     */
    private function BladeMotionTrailsRenderer() {
        // 空实现
    }

    // ---------------------------
    // 性能调控接口
    // ---------------------------
    /**
     * 设置刀口残影计算的性能档位。
     * @param level 可传入 PERFORMANCE_LEVEL_HIGH / PERFORMANCE_LEVEL_MEDIUM / PERFORMANCE_LEVEL_LOW
     */
    public static function setPerformanceLevel(level:Number):Void {
        switch(level) {
            case PERFORMANCE_LEVEL_HIGH:
                processBladeTrail = processBladeTrailHigh;
                break;
            case PERFORMANCE_LEVEL_MEDIUM:
                processBladeTrail = processBladeTrailMedium;
                break;
            case PERFORMANCE_LEVEL_LOW:
            default:
                processBladeTrail = processBladeTrailLow;
                break;
        }
    }

    // ---------------------------
    // 核心残影计算接口
    // ---------------------------

    /**
     * 高性能实现
     * 
     * 计算流程：
     * 1. 遍历“刀口位置1”至“刀口位置5”，对每个有效刀口：
     *    - 直接获取刀口在目标坐标系下的边界矩形；
     *    - 根据矩形计算 p1（左下角）与 p3（右上角），再由 p3.x 与 p1.y 构成 p0；
     *    - 计算中点 mid 以及 p0 与 p1 之间的直线距离，得到半宽 halfWidth；
     * 2. 以所有刀口中第一个与最后一个的 mid 构造全局中轴，
     *    对每个刀口的 mid 计算沿中轴的投影，再根据收缩因子进行全局收缩，计算出新的边缘位置；
     * 3. 根据所有有效刀口的位序构造唯一标识，调用 TrailRenderer 的 addTrailData() 进行残影渲染。
     * 
     * @param target  发射者 MovieClip，用于标识残影的来源
     * @param mc      包含刀口位置（“刀口位置1”至“刀口位置5”）的 MovieClip，提供刀口数据
     * @param style   渲染样式参数，决定残影的视觉效果
     */
    private static function processBladeTrailHigh(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody; // 目标坐标系参考对象
        var rawData:Array = [];       // 存放每个刀口计算的数据 { p0, p1, mid, halfWidth }
        var trail:Array = [];         // 用于最终存储的残影边缘数据 { edge1, edge2 }
        var validIndexes:Array = [];  // 收集有效刀口的序号，后续用于构造唯一标识

        // 声明循环内重复使用的临时变量（提前声明，避免循环内重复 var 声明）
        var current:MovieClip;
        var rect:Object;
        var p1:Vector, p3:Vector, p0:Vector, mid:Vector;
        var halfWidth:Number;
        var i:Number;

        // 遍历刀口位置 1 ~ 5
        for(i = 1; i <= 5; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                validIndexes.push(i);
                rect = current.getRect(map);
                // 计算 p1（矩形左下角）和 p3（矩形右上角）
                p1 = new Vector(rect.xMin, rect.yMax);
                p3 = new Vector(rect.xMax, rect.yMin);
                // 由 p3.x 与 p1.y 构造 p0（右下角）
                p0 = new Vector(p3.x, p1.y);
                // 计算中点
                mid = p0.plusNew(p1).multNew(0.5);
                // 计算半宽
                halfWidth = p0.distance(p1) * 0.5;
                rawData.push({ p0: p0, p1: p1, mid: mid, halfWidth: halfWidth });
            }
        }

        if(rawData.length == 0) {
            return; // 无有效刀口数据，直接返回
        }

        // 全局中轴计算：以首尾 blade 的中点构造中轴向量
        var len:Number = rawData.length;
        var start:Vector = rawData[0].mid;
        var end:Vector   = rawData[len - 1].mid;
        var d:Vector = end.minusNew(start);
        var dLen:Number = d.magnitude();
        if(dLen == 0) {
            d = new Vector(1, 0); // 防止零向量情况
            dLen = 1;
        }
        var unitAxis:Vector = d.multNew(1 / dLen); // 中轴单位向量

        // 全局收缩因子及临时变量
        var contractionFactor:Number = 0.3;
        var v:Vector;
        var projectionLength:Number;
        var m_ideal:Vector;
        var offset:Number;
        var j:Number;

        // 对每个刀口数据，根据全局中轴进行收缩处理
        for(j = 0; j < len; j++) {
            var data:Object = rawData[j];
            v = data.mid.minusNew(start);
            projectionLength = v.dot(unitAxis);
            m_ideal = start.plusNew(unitAxis.multNew(projectionLength));
            offset = data.halfWidth * contractionFactor;
            // 保持最小收缩偏移
            if(offset < 5) {
                offset = 5;
            }
            var new_p0:Vector = m_ideal.minusNew(unitAxis.multNew(offset));
            var new_p1:Vector = m_ideal.plusNew(unitAxis.multNew(offset));
            trail.push({ edge1: new_p0, edge2: new_p1 });
        }

        // 利用数组收集有效刀口序号，再使用 join() 拼接成唯一标识字符串
        var bladeID:String = validIndexes.join("");
        var key:String = target._name + target.version + bladeID;
        var tr:TrailRenderer = TrailRenderer.getInstance();
        tr.addTrailData(key, trail, style);
    }

    /**
     * 中性能实现
     * 
     * 计算流程：
     * 1. 遍历“刀口位置1”至“刀口位置4”，对每个有效刀口：
     *    - 直接获取刀口在目标坐标系下的矩形；
     *    - 计算 p1（左下角）、p3（右上角）、由 p3.x 与 p1.y 构成 p0 及其中点 mid；
     *    - 根据 p0 与 p1 的直线计算单位向量，再以中点沿该方向进行局部收缩，
     *      得到新的边缘数据；
     * 2. 利用有效刀口的序号构造唯一标识，调用 TrailRenderer 的 addTrailData() 进行渲染。
     * 
     * @param target  发射者 MovieClip，用于标识残影的来源
     * @param mc      包含刀口位置（“刀口位置1”至“刀口位置4”）的 MovieClip，提供刀口数据
     * @param style   渲染样式参数，决定残影的视觉效果
     */
    private static function processBladeTrailMedium(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody; // 目标坐标系参考对象
        var trail:Array = [];
        var validIndexes:Array = [];

        // 声明循环内使用的临时变量
        var current:MovieClip;
        var rect:Object;
        var p1:Vector, p3:Vector, p0:Vector, mid:Vector;
        var direction:Vector, dist:Number;
        var halfWidth:Number;
        var offset:Number;
        var i:Number;
        var localContraction:Number = 0.4; // 局部收缩因子

        // 遍历刀口位置 1 ~ 4
        for(i = 1; i <= 4; i++) {
            current = mc["刀口位置" + i];
            if(current && current._x != undefined) {
                validIndexes.push(i);
                rect = current.getRect(map);
                p1 = new Vector(rect.xMin, rect.yMax);
                p3 = new Vector(rect.xMax, rect.yMin);
                p0 = new Vector(p3.x, p1.y);
                mid = p0.plusNew(p1).multNew(0.5);
                direction = p1.minusNew(p0);
                dist = direction.magnitude();
                if(dist == 0) {
                    direction = new Vector(1, 0); // 防止零向量情况
                    dist = 1;
                }
                direction = direction.multNew(1 / dist); // 单位化方向向量
                halfWidth = dist * 0.5;
                offset = halfWidth * localContraction;
                var new_p0:Vector = mid.minusNew(direction.multNew(offset));
                var new_p1:Vector = mid.plusNew(direction.multNew(offset));
                trail.push({ edge1: new_p0, edge2: new_p1 });
            }
        }

        if(trail.length > 0) {
            var bladeID:String = validIndexes.join("");
            var key:String = target._name + target.version + bladeID;
            var tr:TrailRenderer = TrailRenderer.getInstance();
            tr.addTrailData(key, trail, style);
        }
    }

    /**
     * 低性能实现
     * 
     * 计算流程：
     * 1. 遍历“刀口位置1”至“刀口位置3”，对每个有效刀口：
     *    - 直接获取刀口在目标坐标系下的边界矩形；
     *    - 分别将矩形的左下角作为 edge1，右上角作为 edge2；
     * 2. 利用有效刀口的序号构造唯一标识，调用 TrailRenderer 的 addTrailData() 进行残影渲染。
     * 
     * @param target  发射者 MovieClip，用于标识残影的来源
     * @param mc      包含刀口位置（“刀口位置1”至“刀口位置3”）的 MovieClip，提供刀口数据
     * @param style   渲染样式参数，决定残影的视觉效果
     */
    private static function processBladeTrailLow(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody; // 目标坐标系参考对象
        var trail:Array = [];
        var validIndexes:Array = [];

        // 声明临时变量
        var current:MovieClip;
        var rect:Object;
        var edge1:Vector, edge2:Vector;
        var i:Number;

        // 遍历刀口位置 1 ~ 3
        for(i = 1; i <= 3; i++) {
            current = mc["刀口位置" + i];
            if(current && current._x != undefined) {
                validIndexes.push(i);
                rect = current.getRect(map);
                edge1 = new Vector(rect.xMin, rect.yMax);
                edge2 = new Vector(rect.xMax, rect.yMin);
                trail.push({ edge1: edge1, edge2: edge2 });
            }
        }

        if(trail.length > 0) {
            var bladeID:String = validIndexes.join("");
            var key:String = target._name + target.version + bladeID;
            var tr:TrailRenderer = TrailRenderer.getInstance();
            tr.addTrailData(key, trail, style);
        }
    }
}