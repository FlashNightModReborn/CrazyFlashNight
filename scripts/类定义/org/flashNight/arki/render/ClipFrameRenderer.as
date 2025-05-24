import org.flashNight.sara.util.Vector;
import org.flashNight.arki.render.VectorAfterimageRenderer;
import org.flashNight.arki.render.TrailRenderer;
import org.flashNight.naki.DataStructures.Dictionary;

/**
 * ClipFrameRenderer 影片剪辑边框与残影渲染器
 *
 * 本类提供两套静态渲染方法：
 *  - renderClipFrame：渲染静态线框残影（使用 VectorAfterimageRenderer）
 *  - renderClipTrail：渲染动态运动残影（使用 TrailRenderer）
 *
 * renderClipTrail 支持三种性能等级（高/中/低）以平衡渲染效果与性能开销。
 * 调用前可通过 setPerformanceLevel 切换性能档位。
 *
 * 类中所有方法均为静态，实现类无实例化构造函数。
 */
class org.flashNight.arki.render.ClipFrameRenderer {

    // ---------------------------
    // 性能等级常量
    // ---------------------------
    public static var PERFORMANCE_LEVEL_HIGH:Number   = 0;
    public static var PERFORMANCE_LEVEL_MEDIUM:Number = 1;
    public static var PERFORMANCE_LEVEL_LOW:Number    = 2;

    /**
     * 当前残影渲染处理函数指针
     * 根据性能等级指向对应的私有实现方法
     */
    public static var processClipTrail:Function = processClipTrailHigh;

    /**
     * 私有构造函数，禁止外部实例化
     */
    private function ClipFrameRenderer() {
        // no instance
    }

    // ---------------------------
    // 性能档位切换接口
    // ---------------------------
    /**
     * 设置残影渲染性能档位
     * @param level 三档性能等级：PERFORMANCE_LEVEL_HIGH / MEDIUM / LOW
     */
    public static function setPerformanceLevel(level:Number):Void {
        switch(level) {
            case PERFORMANCE_LEVEL_HIGH:
                processClipTrail = processClipTrailHigh;
                break;
            case PERFORMANCE_LEVEL_MEDIUM:
                processClipTrail = processClipTrailMedium;
                break;
            case PERFORMANCE_LEVEL_LOW:
            default:
                processClipTrail = processClipTrailLow;
                break;
        }
    }

    // ---------------------------
    // 静态线框渲染方法
    // ---------------------------
    /**
     * 渲染静态线框残影
     * 使用 VectorAfterimageRenderer 绘制矩形边框
     * @param mc 目标 MovieClip
     */
    public static function renderClipFrame(mc:MovieClip):Void {
        if (mc == undefined) {
            return;
        }
        // 获取自身坐标系下的边界
        var rect:Object = mc.getRect(mc);
        var p0:Vector = new Vector(rect.xMin, rect.yMin); // 左上
        var p1:Vector = new Vector(rect.xMax, rect.yMin); // 右上
        var p2:Vector = new Vector(rect.xMax, rect.yMax); // 右下

        // 局部->全局->目标容器局部坐标转换
        mc.localToGlobal(p0); mc.localToGlobal(p1); mc.localToGlobal(p2);
        var map:MovieClip = _root.gameworld.deadbody;
        map.globalToLocal(p0); map.globalToLocal(p1); map.globalToLocal(p2);

        // 计算第四个点（左下）：p3 = p0 + (p2 - p1)
        var p3:Vector = new Vector(p0.x + p2.x - p1.x, p0.y + p2.y - p1.y);

        // 绘制带残影效果的线框
        VectorAfterimageRenderer.instance.drawShape(
            [p0, p1, p2, p3],
            0xFF0000, // 填充色（红）
            0x00FF00, // 线条色（绿）
            2,        // 线宽
            80,       // 填充透明度
            100,      // 线条透明度
            30        // 残影数量
        );
    }

    // ---------------------------
    // 动态残影渲染方法
    // ---------------------------
    /**
     * 渲染动态运动残影
     * @param mc    目标 MovieClip
     * @param style 渲染样式标识，由 TrailRenderer 解析
     */
    public static function renderClipTrail(mc:MovieClip, style:String):Void {
        if (mc == undefined) {
            return;
        }
        processClipTrail(mc, style);
    }

    /**
     * 私有辅助：获取 MovieClip 在目标坐标系 (_root.gameworld.deadbody) 下的四个角点
     * @param mc 目标 MovieClip
     * @return {p0,p1,p2,p3} 四个角点向量
     */
    private static function getTransformedCorners(mc:MovieClip):Object {
        if (mc == undefined) {
            return null;
        }
        var rect:Object = mc.getRect(mc);
        if (!rect) {
            return null;
        }
        // 计算局部四角
        var p0:Vector = new Vector(rect.xMin, rect.yMin);
        var p1:Vector = new Vector(rect.xMax, rect.yMin);
        var p2:Vector = new Vector(rect.xMax, rect.yMax);

        // 转换到目标容器坐标系
        mc.localToGlobal(p0); mc.localToGlobal(p1); mc.localToGlobal(p2);
        var map:MovieClip = _root.gameworld.deadbody;
        map.globalToLocal(p0); map.globalToLocal(p1); map.globalToLocal(p2);

        // 利用平行四边形特性计算第四角
        var p3:Vector = new Vector(p0.x + p2.x - p1.x, p0.y + p2.y - p1.y);
        return { p0:p0, p1:p1, p2:p2, p3:p3 };
    }

    // ---------------------------
    // 低性能实现
    // ---------------------------
    /**
     * 低性能渲染实现
     * 简单方案：使用矩形两条相对边作为残影横截面
     */
    private static function processClipTrailLow(mc:MovieClip, style:String):Void {
        var c:Object = getTransformedCorners(mc);
        if (c == null) {
            return;
        }
        var trail:Array = [];
        // 左下->左上，右下->右上 两条边
        trail.push({ edge1: c.p3, edge2: c.p0 });
        trail.push({ edge1: c.p2, edge2: c.p1 });

        var tr:TrailRenderer = TrailRenderer.getInstance();
        tr.addTrailData(String(Dictionary.getStaticUID(mc)), trail, style);
    }

    // ---------------------------
    // 中性能实现
    // ---------------------------
    /**
     * 中性能渲染实现
     * 方案：对四个角点进行轻微向内收缩，使用收缩后的四条边
     */
    private static function processClipTrailMedium(mc:MovieClip, style:String):Void {
        var c:Object = getTransformedCorners(mc);
        if (c == null) {
            return;
        }
        // 计算矩形中心
        var center:Vector = c.p0.plusNew(c.p1).plusNew(c.p2).plusNew(c.p3).multNew(0.25);
        var contraction:Number = 0.1; // 收缩因子

        // 对四角进行收缩
        var p0c:Vector = c.p0.plusNew(center.minusNew(c.p0).multNew(contraction));
        var p1c:Vector = c.p1.plusNew(center.minusNew(c.p1).multNew(contraction));
        var p2c:Vector = c.p2.plusNew(center.minusNew(c.p2).multNew(contraction));
        var p3c:Vector = c.p3.plusNew(center.minusNew(c.p3).multNew(contraction));

        // 使用收缩后的四条边
        var trail:Array = [];
        trail.push({ edge1: p3c, edge2: p0c });
        trail.push({ edge1: p0c, edge2: p1c });
        trail.push({ edge1: p1c, edge2: p2c });
        trail.push({ edge1: p2c, edge2: p3c });

        var tr:TrailRenderer = TrailRenderer.getInstance();
        tr.addTrailData(String(Dictionary.getStaticUID(mc)), trail, style);
    }

    // ---------------------------
    // 高性能实现
    // ---------------------------
    /**
     * 高性能渲染实现
     * 方案：使用更大收缩并在各边插值，增强残影平滑度
     */
    private static function processClipTrailHigh(mc:MovieClip, style:String):Void {
        var c:Object = getTransformedCorners(mc);
        if (c == null) {
            return;
        }
        // 计算中心并收缩角点
        var center:Vector = c.p0.plusNew(c.p1).plusNew(c.p2).plusNew(c.p3).multNew(0.25);
        var contraction:Number = 0.2;
        var p0c:Vector = c.p0.plusNew(center.minusNew(c.p0).multNew(contraction));
        var p1c:Vector = c.p1.plusNew(center.minusNew(c.p1).multNew(contraction));
        var p2c:Vector = c.p2.plusNew(center.minusNew(c.p2).multNew(contraction));
        var p3c:Vector = c.p3.plusNew(center.minusNew(c.p3).multNew(contraction));

        // 在收缩后的边上插值中点
        var mid30:Vector = p3c.plusNew(p0c).multNew(0.5);
        var mid01:Vector = p0c.plusNew(p1c).multNew(0.5);
        var mid12:Vector = p1c.plusNew(p2c).multNew(0.5);
        var mid23:Vector = p2c.plusNew(p3c).multNew(0.5);

        // 组织四组横截面，增加平滑度
        var trail:Array = [];
        trail.push({ edge1: p3c,   edge2: p1c   });
        trail.push({ edge1: mid30, edge2: mid12 });
        trail.push({ edge1: p0c,   edge2: p2c   });
        trail.push({ edge1: mid01, edge2: mid23 });

        var tr:TrailRenderer = TrailRenderer.getInstance();
        tr.addTrailData(String(Dictionary.getStaticUID(mc)), trail, style);
    }

}
