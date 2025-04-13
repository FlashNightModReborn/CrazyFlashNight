import org.flashNight.arki.render.TrailRenderer;

/**
 * BladeMotionTrailsRenderer
 * 
 * 本类用于计算并渲染刀口残影，提供三种不同性能档位：
 *   - PERFORMANCE_LEVEL_HIGH：高性能（复杂计算，全局中轴投影+收缩）
 *   - PERFORMANCE_LEVEL_MEDIUM：中性能（简化计算，每个刀口本地收缩）
 *   - PERFORMANCE_LEVEL_LOW：低性能（直接使用坐标，不做额外计算）
 * 
 * 使用前请调用 setPerformanceLevel() 指定所需性能等级。
 */
class org.flashNight.arki.render.BladeMotionTrailsRenderer {

    // 性能等级常量
    public static var PERFORMANCE_LEVEL_HIGH:Number = 0;
    public static var PERFORMANCE_LEVEL_MEDIUM:Number = 1;
    public static var PERFORMANCE_LEVEL_LOW:Number = 2;

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
     * 当前选定的刀口残影计算方法（默认为高性能实现）
     */
    public static var processBladeTrail:Function = processBladeTrailHigh;

    /**
     * 高性能实现：
     *  - 收集每个刀口的 p0, p1, mid, halfWidth 数据
     *  - 对所有刀口计算全局中轴（以首尾 mid 构造中轴），再按中轴进行收缩处理
     *  - 同时拼接有效刀口数字构成唯一标识，避免因刀口数量不同而引起数据冲突
     *
     * @param target  发射者 MovieClip
     * @param mc      包含刀口位置（命名为“刀口位置1”至“刀口位置5”）的 MovieClip
     * @param style   渲染样式参数
     */
    private static function processBladeTrailHigh(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var rawData:Array = [];
        var trail:Array = [];
        var current:MovieClip;
        var rect:Object;
        var p0:Object, p1:Object, p3:Object, mid:Object;
        var dx:Number, dy:Number, halfWidth:Number;

        // 用于保存有效刀口位序拼接成的标识字符串
        var bladeID:String = "";

        // -----------------------------
        // 1) 收集每个刀口的碰撞盒数据
        // -----------------------------
        for (var i:Number = 1; i <= 5; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                // 累加有效的刀口数字到标识字符串中
                bladeID += i.toString();

                // 直接获取 current 在 map 坐标系下的矩形
                rect = current.getRect(map);

                // 计算 p1（矩形左上角）与 p3（矩形右下角），p0 取 p3.x 与 p1.y 构成
                p1 = { x: rect.xMin, y: rect.yMax };
                p3 = { x: rect.xMax, y: rect.yMin };
                p0 = { x: p3.x, y: p1.y };

                mid = { x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 };

                dx = p1.x - p0.x;
                dy = p1.y - p0.y;
                halfWidth = Math.sqrt(dx * dx + dy * dy) * 0.5;

                rawData.push({
                    p0: { x: p0.x, y: p0.y },
                    p1: { x: p1.x, y: p1.y },
                    mid: { x: mid.x, y: mid.y },
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

            var d:Object = { x: end.x - start.x, y: end.y - start.y };
            var dLen:Number = Math.sqrt(d.x * d.x + d.y * d.y);
            if (dLen == 0) {
                d.x = 1; d.y = 0; dLen = 1;
            }
            var ux:Number = d.x / dLen;
            var uy:Number = d.y / dLen;

            // 全局收缩因子
            var contractionFactor:Number = 0.3;
            var v:Object = { x: 0, y: 0 };
            var m_ideal:Object = { x: 0, y: 0 };
            var offset:Number, projectionLength:Number;
            var ox:Number, oy:Number;

            for (var j:Number = 0; j < len; j++) {
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

            // 将 bladeID 拼接到 key 后面，作为唯一标识
            var key:String = target._name + target.version + bladeID;
            var tr:TrailRenderer = TrailRenderer.getInstance();
            tr.addTrailData(key, trail, style);
        }
    }

    /**
     * 中性能实现：
     *  - 对每个刀口直接计算 p0、p1、mid 和 halfWidth
     *  - 根据刀口方向计算单位向量，再以 mid 点沿该方向双向偏移，得到局部收缩后的边缘
     *  - 同时拼接有效刀口数字构成唯一标识
     *
     * @param target  发射者 MovieClip
     * @param mc      包含刀口位置的 MovieClip（命名为“刀口位置1”至“刀口位置4”）
     * @param style   渲染样式参数
     */
    private static function processBladeTrailMedium(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var trail:Array = [];
        var current:MovieClip;
        var rect:Object;
        var p0:Object, p1:Object, p3:Object, mid:Object;
        var dx:Number, dy:Number, dist:Number, halfWidth:Number;
        // 局部收缩系数
        var localContraction:Number = 0.4;

        // 用于保存有效刀口位序字符串
        var bladeID:String = "";

        // 遍历所有可能的刀口位置（“刀口位置1”至“刀口位置4”）
        for (var i:Number = 1; i <= 4; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                bladeID += i.toString();

                // 直接获取 current 在 map 坐标系下的矩形
                rect = current.getRect(map);

                p1 = { x: rect.xMin, y: rect.yMax };
                p3 = { x: rect.xMax, y: rect.yMin };
                p0 = { x: p3.x, y: p1.y };
                mid = { x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2 };

                dx = p1.x - p0.x;
                dy = p1.y - p0.y;
                dist = Math.sqrt(dx * dx + dy * dy);
                if (dist == 0) {
                    dx = 1; dy = 0; dist = 1;
                }
                var ux:Number = dx / dist;
                var uy:Number = dy / dist;
                halfWidth = dist * 0.5;
                var offset:Number = halfWidth * localContraction;

                var new_p0:Object = { x: mid.x - ux * offset, y: mid.y - uy * offset };
                var new_p1:Object = { x: mid.x + ux * offset, y: mid.y + uy * offset };

                trail.push({ edge1: new_p0, edge2: new_p1 });
            }
        }

        if (trail.length > 0) {
            var key:String = target._name + target.version + bladeID;
            var tr:TrailRenderer = TrailRenderer.getInstance();
            tr.addTrailData(key, trail, style);
        }
    }

    /**
     * 低性能实现：
     *  - 直接从每个刀口的碰撞盒获取 p1 与 p3 坐标，
     *    不进行额外的计算，适用于资源受限环境
     *  - 同时拼接有效刀口数字构成唯一标识
     *
     * @param target  发射者 MovieClip
     * @param mc      包含刀口位置的 MovieClip（命名为“刀口位置1”至“刀口位置3”）
     * @param style   渲染样式参数
     */
    private static function processBladeTrailLow(target:MovieClip, mc:MovieClip, style:String):Void {
        var map:MovieClip = _root.gameworld.deadbody;
        var trail:Array = [];
        var current:MovieClip;
        var rect:Object;
        var edge1:Object, edge2:Object;
        var bladeID:String = "";

        for (var i:Number = 1; i <= 3; i++) {
            current = mc["刀口位置" + i];
            if (current && current._x != undefined) {
                bladeID += i.toString();
                // 直接获取 current 在 map 坐标系下的矩形
                rect = current.getRect(map);
                edge1 = { x: rect.xMin, y: rect.yMax };
                edge2 = { x: rect.xMax, y: rect.yMin };
                trail.push({ edge1: edge1, edge2: edge2 });
            }
        }

        if (trail.length > 0) {
            var key:String = target._name + target.version + bladeID;
            var tr:TrailRenderer = TrailRenderer.getInstance();
            tr.addTrailData(key, trail, style);
        }
    }
}
