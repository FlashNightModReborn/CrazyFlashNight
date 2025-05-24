import org.flashNight.naki.Interpolation.PointSetInterpolator;
import org.flashNight.sara.util.*;

/**
 * Graphics 类
 * 提供一系列静态方法用于绘制基本图形和调试信息。
 */
class org.flashNight.sara.graphics.Graphics {

    // 静态方法：绘制直线
    public static function paintLine (
            dmc:MovieClip, 
            x0:Number, 
            y0:Number, 
            x1:Number, 
            y1:Number):Void {
        
        dmc.moveTo(x0, y0);
        dmc.lineTo(x1, y1);
    }

    // 静态方法：绘制圆形
    public static function paintCircle (dmc:MovieClip, x:Number, y:Number, r:Number):Void {

        var mtp8r:Number = Math.tan(Math.PI/8) * r;
        var msp4r:Number = Math.sin(Math.PI/4) * r;

        with (dmc) {
            moveTo(x + r, y);
            curveTo(r + x, mtp8r + y, msp4r + x, msp4r + y);
            curveTo(mtp8r + x, r + y, x, r + y);
            curveTo(-mtp8r + x, r + y, -msp4r + x, msp4r + y);
            curveTo(-r + x, mtp8r + y, -r + x, y);
            curveTo(-r + x, -mtp8r + y, -msp4r + x, -msp4r + y);
            curveTo(-mtp8r + x, -r + y, x, -r + y);
            curveTo(mtp8r + x, -r + y, msp4r + x, -msp4r + y);
            curveTo(r + x, -mtp8r + y, r + x, y);
        }
    }
    
    // 静态方法：绘制矩形
    public static function paintRectangle(
            dmc:MovieClip, 
            x:Number, 
            y:Number, 
            w:Number, 
            h:Number):Void {
        
        var w2:Number = w/2;
        var h2:Number = h/2;
        
        with (dmc) {
            moveTo(x - w2, y - h2);
            lineTo(x + w2, y - h2);
            lineTo(x + w2, y + h2);
            lineTo(x - w2, y + h2);
            lineTo(x - w2, y - h2);
        }
    }

    // 静态方法：绘制插值曲线，使用 PointSet 代替数组
    public static function drawInterpolatedCurve(
        dmc:MovieClip, 
        pointSet:PointSet,  // 使用 PointSet 代替 Array
        mode:String, 
        step:Number
    ):Void {
        // 如果 mode 未传入，或者 mode 是 undefined 或空值，默认设置为 "bezier"
        if (mode == undefined || mode == "" || typeof mode != "string") {
            mode = "bezier";
        }
        
        // 如果 step 未传入，或者 step 是 undefined 或 NaN，默认设置为 0.01
        if (step == undefined || isNaN(step)) {
            step = 0.01;
        }

        // 确保点集至少有两个点用于插值
        if (pointSet.size() < 2) {
            trace("点集必须至少包含两个点");
            return;
        }

        // 创建 PointSetInterpolator 实例
        var interpolator:PointSetInterpolator = new PointSetInterpolator(pointSet, mode);

        // 获取第一个插值点，作为曲线的起始点
        var result:Object = interpolator.interpolate(0);
        
        if (result == null) {
            trace("起始插值点获取失败");
            return;
        }
        
        dmc.moveTo(result.x, result.y);  // 将绘图移动到第一个插值点
        
        // 循环生成插值点，t 从 0 递增到 1
        for (var t:Number = 0; t <= 1; t += step) {
            result = interpolator.interpolate(t);
            if (result != null) {
                // 画线到下一个插值点
                dmc.lineTo(result.x, result.y);
            } else {
                trace("插值失败，停止插值");
                break;  // 插值失败时跳出循环，防止死循环
            }
        }
    }

    // 静态方法：绘制多边形，使用 PointSet 代替数组
    public static function paintPolygon(dmc:MovieClip, pointSet:PointSet):Void {
        if (pointSet.size() < 3) {
            trace("多边形必须至少有3个点");
            return;
        }

        var firstPoint:Vector = pointSet.getPoint(0);
        dmc.moveTo(firstPoint.x, firstPoint.y);

        for (var i:Number = 1; i < pointSet.size(); i++) {
            var point:Vector = pointSet.getPoint(i);
            dmc.lineTo(point.x, point.y);
        }

        // 闭合多边形
        dmc.lineTo(firstPoint.x, firstPoint.y);
    }

    // 静态方法：绘制影片剪辑的 AABB（轴对齐包围盒）
    public static function drawAABBFromMovieClip(dmc:MovieClip, mc:MovieClip):Void {
        if (mc) 
        {
            var rect:Object = mc.getRect(mc);

            dmc.moveTo(rect.xMin, rect.yMin);
            dmc.lineTo(rect.xMax, rect.yMin);
            dmc.lineTo(rect.xMax, rect.yMax);
            dmc.lineTo(rect.xMin, rect.yMax);
            dmc.lineTo(rect.xMin, rect.yMin);
        }
    }

    // 静态方法：绘制 AABB（轴对齐包围盒）
    public static function drawAABB(dmc:MovieClip, aabb:AABB):Void 
    {
        if (aabb) 
        {
            var left:Number = aabb.left;
            var right:Number = aabb.right;
            var top:Number = aabb.top;
            var bottom:Number = aabb.bottom;

            dmc.moveTo(left, top);
            dmc.lineTo(right, top);
            dmc.lineTo(right, bottom);
            dmc.lineTo(left, bottom);
            dmc.lineTo(left, top);
        }
    }

    // 静态方法：绘制向量
    public static function drawVector(
        dmc:MovieClip, 
        start:Vector, 
        vector:Vector, 
        color:Number
    ):Void {
        // 设置线条样式
        dmc.lineStyle(2, color, 100);
        
        // 绘制向量线
        dmc.moveTo(start.x, start.y);
        dmc.lineTo(start.x + vector.x, start.y + vector.y);
        
        // 绘制箭头头部
        var arrowLength:Number = 10; // 箭头长度
        var arrowAngle:Number = Math.PI / 6; // 箭头角度（30度）

        var angle:Number = Math.atan2(vector.y, vector.x); // 向量的角度

        var endX:Number = start.x + vector.x;
        var endY:Number = start.y + vector.y;

        var arrowX1:Number = endX - arrowLength * Math.cos(angle - arrowAngle);
        var arrowY1:Number = endY - arrowLength * Math.sin(angle - arrowAngle);

        var arrowX2:Number = endX - arrowLength * Math.cos(angle + arrowAngle);
        var arrowY2:Number = endY - arrowLength * Math.sin(angle + arrowAngle);

        // 绘制箭头的两条边
        dmc.moveTo(endX, endY);
        dmc.lineTo(arrowX1, arrowY1);
        dmc.moveTo(endX, endY);
        dmc.lineTo(arrowX2, arrowY2);
    }
}
