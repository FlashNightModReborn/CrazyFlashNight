import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.render.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.spatial.transform.*;

/**
 * AABBRenderer 类
 *
 * 用于可视化调试 AABB 碰撞器（AABBCollider）的边界框绘制。当前版本采用职责分离思想，
 * 将数据收集（顶点坐标及样式配置）与绘制逻辑拆分为两个独立的方法：
 * - collectAABBData()：专注于从碰撞器中提取绘制所需的几何数据和样式设置
 * - drawCollectedData()：专注于根据收集的数据调用绘图接口实现渲染
 *
 * 同时保留 renderAABB() 作为快捷入口，一次性完成数据收集与绘制操作。
 */
class org.flashNight.arki.render.AABBRenderer {

    /**
     * 渲染传入的 AABBCollider 对象对应的轴对齐边界框。
     * 渲染流程：
     * 1. 调用 collectAABBData() 收集绘制所需的几何数据和样式配置。
     * 2. 调用 drawCollectedData() 根据收集的数据进行实际绘制。
     *
     * @param iCollider 需要调试绘制的 AABBCollider 对象（必须实现 ICollider 接口）
     * @param zOffset   高度偏移量，用于在渲染时区分碰撞检测高度z轴偏移的显示效果
     */
    public static function renderAABB(iCollider:ICollider, zOffset:Number):Void {
        if (iCollider == null) return;
        
        // 1. 收集绘制数据（几何数据和样式配置）
        var data:Object = collectAABBData(iCollider, zOffset);
        
        // 2. 根据收集的数据执行绘制操作
        drawCollectedData(data);
    }
    
    /**
     * 收集用于绘制 AABB 边界框的几何数据和样式配置。
     * 本方法将根据传入的碰撞器 iCollider 提取 AABB 数据，
     * 并利用 AABBCollider 中的 left、right、top、bottom 属性计算出矩形四个顶点坐标，
     * 同时预设绘制时使用的填充色、线条色、线宽、透明度以及残影数量。
     *
     * @param iCollider 需要调试绘制的碰撞器对象（实现 ICollider 接口）
     * @param zOffset   高度偏移量，用于确保渲染时的正确位置
     * @return 一个 Object 对象，包含以下属性：
     *         - vertices: Array — 顶点数组，顺序依次为 [左上, 右上, 右下, 左下]
     *         - fillColor: Number — 填充颜色（十六进制表示，如 0xFF0000）
     *         - lineColor: Number — 线条颜色（十六进制表示，如 0x00FF00）
     *         - lineWidth: Number — 线条宽度（单位像素）
     *         - fillAlpha: Number — 填充透明度
     *         - lineAlpha: Number — 线条透明度
     *         - shadowCount: Number — 残影数量
     */
    public static function collectAABBData(iCollider:ICollider, zOffset:Number):Object {
        // 获取经过 zOffset 调整后的 AABB，并应用全局效果偏移
        var collider:AABB = iCollider.getAABB(zOffset).moveNew(SceneCoordinateManager.effectOffset);
        
        // 计算矩形四个顶点的坐标
        var p0:Vector = new Vector(collider.left, collider.top);      // 左上角
        var p1:Vector = new Vector(collider.right, collider.top);     // 右上角
        var p2:Vector = new Vector(collider.right, collider.bottom);  // 右下角
        var p3:Vector = new Vector(collider.left, collider.bottom);   // 左下角
        
        // 预设绘图样式配置
        var fillColor:Number   = 0xFF0000;  // 填充色：红色
        var lineColor:Number   = 0x00FF00;  // 线条色：绿色
        var lineWidth:Number   = 2;         // 线宽：2
        var fillAlpha:Number   = 80;        // 填充透明度：80
        var lineAlpha:Number   = 100;       // 线条透明度：100
        var shadowCount:Number = 30;        // 残影数量：30
        
        // 返回包含所有绘制所需数据的对象
        return {
            vertices: [p0, p1, p2, p3],
            fillColor: fillColor,
            lineColor: lineColor,
            lineWidth: lineWidth,
            fillAlpha: fillAlpha,
            lineAlpha: lineAlpha,
            shadowCount: shadowCount
        };
    }
    
    /**
     * 根据提供的绘制数据对象，调用 VectorAfterimageRenderer 进行边界框的绘制操作。
     * 本方法职责单一，只负责将收集好的数据交给绘图接口执行渲染。
     *
     * @param data 包含顶点数组以及绘制样式配置的 Object 对象，
     *             具体结构请参见 collectAABBData() 方法的返回值说明。
     */
    public static function drawCollectedData(data:Object):Void {
        VectorAfterimageRenderer.instance.drawShape(
            data.vertices,
            data.fillColor,
            data.lineColor,
            data.lineWidth,
            data.fillAlpha,
            data.lineAlpha,
            data.shadowCount
        );
    }
}
