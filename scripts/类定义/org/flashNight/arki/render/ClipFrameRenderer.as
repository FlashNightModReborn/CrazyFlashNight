import org.flashNight.arki.render.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.render.ClipFrameRenderer {
    
    /**
     * 静态方法 - 渲染指定影片剪辑的边框线（线框）
     * 该方法先获取影片剪辑在自身坐标系下的边界信息，
     * 再通过局部／全局坐标转换，计算出4个角点，
     * 最后调用 VectorAfterimageRenderer 绘制出带残影效果的线框。
     *
     * @param mc 需要绘制边框的目标影片剪辑 MovieClip
     */
    public static function renderClipFrame(mc:MovieClip):Void {
        if (mc != undefined) {
            // 获取当前影片剪辑自身的边界信息
            var rect:Object = mc.getRect(mc);
            
            // 根据边界信息计算三个顶点：
            // p0 为左上角，p1 为右上角，p2 为右下角
            var p0:Vector = new Vector(rect.xMin, rect.yMin);
            var p1:Vector = new Vector(rect.xMax, rect.yMin);
            var p2:Vector = new Vector(rect.xMax, rect.yMax);
            
            // 将局部坐标转换为全局坐标
            mc.localToGlobal(p0);
            mc.localToGlobal(p1);
            mc.localToGlobal(p2);
            
            // 目标容器（例如 _root.gameworld.deadbody）中进行全局到局部转换
            var map:MovieClip = _root.gameworld.deadbody;
            map.globalToLocal(p0);
            map.globalToLocal(p1);
            map.globalToLocal(p2);
            
            // 利用矩形对称性计算第四个点：p3 = p0 + (p2 - p1)
            var p3:Vector = new Vector(p0.x + p2.x - p1.x, p0.y + p2.y - p1.y);
            
            // 调用 VectorAfterimageRenderer 绘制线框
            // 参数依次为：点数组、填充色、线条色、线宽、填充透明度、线条透明度、残影数量（shadowCount）
            VectorAfterimageRenderer.instance.drawShape(
                [p0, p1, p2, p3],
                0xFF0000,   // 填充色（红色）
                0x00FF00,   // 线条色（绿色）
                2,          // 线宽
                80,         // 填充透明度
                100,        // 线条透明度
                30          // 残影数量（可根据实际需要调整）
            );
        }
    }
}
