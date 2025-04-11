import org.flashNight.arki.render.TrailRenderer;

/**
 * BladeMotionTrailsRenderer
 * 
 * 本类用于计算并渲染刀口残影，提供三种不同性能档位：
 *   - PERFORMANCE_LEVEL_HIGH：高性能（复杂计算，全局中轴投影+收缩）
 *   - PERFORMANCE_LEVEL_MEDIUM：中性能（简化计算，每个刀口本地收缩）
 *   - PERFORMANCE_LEVEL_LOW：低性能（简单直接使用坐标，不做额外计算）
 * 
 * 使用前请调用 setPerformanceLevel() 指定所需性能等级。
 */
class org.flashNight.arki.render.BladeMotionTrailsRenderer {

    // 定义性能等级常量
    public static var PERFORMANCE_LEVEL_HIGH:Number = 0;
    public static var PERFORMANCE_LEVEL_MEDIUM:Number = 1;
    public static var PERFORMANCE_LEVEL_LOW:Number = 2;

    /**
     * 私有构造函数，禁止外部实例化。
     * 此类仅提供静态方法，不允许被实例化
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
     * 当前选定的刀口残影计算方法（默认为高性能实现）
     */
    public static var processBladeTrail:Function = processBladeTrailHigh;

    /**
     * 高性能实现：
     *  - 先收集每个刀口的 p0, p1, mid, halfWidth 数据
     *  - 对所有刀口计算全局中轴（用首尾 mid 构造中轴），再按中轴进行收缩处理
     *
     * @param target  发射者 MovieClip
     * @param mc      包含刀口位置（命名为“刀口位置1”至“刀口位置5”）的 MovieClip
     * @param style   渲染样式参数
     */
    private static function processBladeTrailHigh(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var rawData:Array = [];
        var trail:Array = [];

        var i:Number, j:Number;
        var current:MovieClip;
        var rect:Object;
        var pt1:Object = { x:0, y:0 };
        var pt3:Object = { x:0, y:0 };
        var p0:Object;  
        var mid:Object = { x:0, y:0 };
        var dx:Number, dy:Number, halfWidth:Number;

        // -----------------------------
        // 1) 收集每个刀口的碰撞盒数据
        // -----------------------------
        for (i = 1; i <= 5; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                rect = current.getRect(current);

                // 将局部坐标转换为全局（再转换到 map 内坐标）
                pt1.x = rect.xMin;
                pt1.y = rect.yMax;
                current.localToGlobal(pt1);
                map.globalToLocal(pt1);

                pt3.x = rect.xMax;
                pt3.y = rect.yMin;
                current.localToGlobal(pt3);
                map.globalToLocal(pt3);

                var p1:Object = { x: pt1.x, y: pt1.y };
                var p3:Object = { x: pt3.x, y: pt3.y };
                p0 = { x: p3.x, y: p1.y };

                mid.x = (p0.x + p1.x) / 2;
                mid.y = (p0.y + p1.y) / 2;

                dx = p1.x - p0.x;
                dy = p1.y - p0.y;
                halfWidth = Math.sqrt(dx * dx + dy * dy) * 0.5;

                rawData.push({
                    p0: { x:p0.x, y:p0.y },
                    p1: { x:p1.x, y:p1.y },
                    mid: { x:mid.x, y:mid.y },
                    halfWidth: halfWidth
                });
            }
        }

        // -----------------------------
        // 2) 全局中轴处理与刀光边缘计算
        // -----------------------------
        var len:Number = rawData.length;
        if (len > 0) {
            // 以首尾 mid 构造中轴
            var start:Object = rawData[0].mid;
            var end:Object   = rawData[len - 1].mid;

            var d:Object = { x:end.x - start.x, y:end.y - start.y };
            var dLen:Number = Math.sqrt(d.x * d.x + d.y * d.y);
            if (dLen == 0) {
                d.x = 1; d.y = 0; dLen = 1;
            }
            var ux:Number = d.x / dLen;
            var uy:Number = d.y / dLen;

            // 全局收缩因子
            var contractionFactor:Number = 0.3;
            var v:Object = { x:0, y:0 };
            var m_ideal:Object = { x:0, y:0 };
            var offset:Number, projectionLength:Number;
            var ox:Number, oy:Number;

            for (j = 0; j < len; j++) {
                var data:Object = rawData[j];
                // 计算当前 mid 到起始点的向量投影长度
                v.x = data.mid.x - start.x;
                v.y = data.mid.y - start.y;
                projectionLength = v.x * ux + v.y * uy;
                // 得到理想中轴点
                m_ideal.x = start.x + ux * projectionLength;
                m_ideal.y = start.y + uy * projectionLength;

                offset = Math.max(data.halfWidth * contractionFactor, 5);
                ox = offset * ux;
                oy = offset * uy;

                var new_p0:Object = { x: m_ideal.x - ox, y: m_ideal.y - oy };
                var new_p1:Object = { x: m_ideal.x + ox, y: m_ideal.y + oy };
                trail.push({ edge1: new_p0, edge2: new_p1 });
            }

            var tr:TrailRenderer = TrailRenderer.getInstance();
            tr.addTrailData(target._name, trail, style);
        }
    };

    /**
     * 中性能实现（进一步简化版）：
     *  - 对每个刀口直接计算 p0、p1、mid 和 halfWidth
     *  - 根据刀口自身方向计算单位向量，再以 mid 点沿该方向双向偏移，得到收缩后的边缘
     *  - 此实现省去全局中轴计算，仅进行每个局部收缩，适合中性能要求
     *
     * @param target  发射者 MovieClip
     * @param mc      包含刀口位置的 MovieClip
     * @param style   渲染样式参数
     */
    private static function processBladeTrailMedium(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var trail:Array = [];
        var current:MovieClip;
        var rect:Object;
        var pt1:Object = { x:0, y:0 };
        var pt3:Object = { x:0, y:0 };

        // 收缩系数：用于调节刀光边缘偏移量
        var localContraction:Number = 0.4;

        // 遍历所有可能的刀口位置
        for (var i:Number = 1; i <= 4; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                rect = current.getRect(current);

                pt1.x = rect.xMin;
                pt1.y = rect.yMax;
                current.localToGlobal(pt1);
                map.globalToLocal(pt1);

                pt3.x = rect.xMax;
                pt3.y = rect.yMin;
                current.localToGlobal(pt3);
                map.globalToLocal(pt3);

                var p1:Object = { x: pt1.x, y: pt1.y };
                var p3:Object = { x: pt3.x, y: pt3.y };
                var p0:Object = { x: p3.x, y: p1.y };
                // 以 p0 与 p1 求出中点作为刀口中心
                var mid:Object = { x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 };

                // 计算刀口的方向向量及其长度（用于归一化）
                var dx:Number = p1.x - p0.x;
                var dy:Number = p1.y - p0.y;
                var dist:Number = Math.sqrt(dx * dx + dy * dy);
                if (dist == 0) {
                    dx = 1; dy = 0; dist = 1;
                }
                var ux:Number = dx / dist;
                var uy:Number = dy / dist;
                // 使用刀口宽度的一半作为基础参考
                var halfWidth:Number = dist * 0.5;
                var offset:Number = halfWidth * localContraction;

                // 计算简化后的边缘：以 mid 为中心，沿刀口方向各偏移 offset
                var new_p0:Object = { x: mid.x - ux * offset, y: mid.y - uy * offset };
                var new_p1:Object = { x: mid.x + ux * offset, y: mid.y + uy * offset };

                trail.push({ edge1: new_p0, edge2: new_p1 });
            }
        }

        if (trail.length > 0) {
            var tr:TrailRenderer = TrailRenderer.getInstance();
            tr.addTrailData(target._name, trail, style);
        }
    };

    /**
     * 低性能实现：
     *  - 直接从每个刀口的碰撞盒获取 p1 与 p3 坐标，
     *    不进行额外的中点、收缩等计算，适合资源受限环境。
     *
     * @param target  发射者 MovieClip
     * @param mc      包含刀口位置的 MovieClip
     * @param style   渲染样式参数
     */
    private static function processBladeTrailLow(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var trail:Array = [];
        var current:MovieClip;
        var rect:Object;
        var pt1:Object = { x:0, y:0 };
        var pt3:Object = { x:0, y:0 };

        for (var i:Number = 1; i <= 3; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                rect = current.getRect(current);
                
                pt1.x = rect.xMin;
                pt1.y = rect.yMax;
                current.localToGlobal(pt1);
                map.globalToLocal(pt1);
                
                pt3.x = rect.xMax;
                pt3.y = rect.yMin;
                current.localToGlobal(pt3);
                map.globalToLocal(pt3);

                var edge1:Object = { x: pt1.x, y: pt1.y };
                var edge2:Object = { x: pt3.x, y: pt3.y };
                
                trail.push({ edge1: edge1, edge2: edge2 });
            }
        }

        if (trail.length > 0) {
            var tr:TrailRenderer = TrailRenderer.getInstance();
            tr.addTrailData(target._name, trail, style);
        }
    }
}
