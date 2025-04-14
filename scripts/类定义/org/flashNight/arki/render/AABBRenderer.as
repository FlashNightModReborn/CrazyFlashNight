import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.render.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.spatial.transform.*;

/**
 * AABBRenderer 类
 *
 * 用于可视化调试 AABB 碰撞器（AABBCollider）的边界框绘制。
 * 当前版本采用职责分离思想，将数据收集（顶点坐标及样式配置）与绘制逻辑拆分为两个独立的方法：
 *   - collectAABBData()：负责从碰撞器中提取绘制所需的几何数据和样式设置，并根据传入的 mode 参数配置不同样式
 *   - drawCollectedData()：负责根据收集的数据调用绘图接口实现实际渲染
 *
 * 同时保留 renderAABB() 作为快捷入口，一次性完成数据收集与绘制操作，并增加 mode 参数以支持三种调试样式：
 *   - "line"   : 仅线框模式（默认），用于显示子弹的碰撞箱，持续帧数为 1
 *   - "thick"  : 粗线框模式，用于显示发生碰撞的子弹碰撞箱，持续帧数为 30（线宽加粗）
 *   - "filled" : 填充模式，用于显示被命中的单位碰撞箱，持续帧数为 30
 */
class org.flashNight.arki.render.AABBRenderer {

    /**
     * 渲染传入的 AABBCollider 对象对应的轴对齐边界框。
     *
     * 渲染流程：
     *   1. 调用 collectAABBData() 收集绘制所需的几何数据和样式配置，
     *      根据 mode 参数调整不同的绘制样式
     *   2. 调用 drawCollectedData() 根据收集的数据执行实际绘制
     *
     * @param iCollider 需要调试绘制的 AABBCollider 对象（必须实现 ICollider 接口）
     * @param zOffset   高度偏移量，用于在渲染时区分碰撞检测的高度（z 轴偏移）
     * @param mode      绘制模式控制字符串，可选值：
     *                    "line"   - 仅绘制线框（默认，持续帧数 1）
     *                    "thick"  - 绘制粗线框（持续帧数 30）
     *                    "filled" - 绘制填充模式（持续帧数 30）
     *                  如果该参数为空，则默认为 "line" 模式。
     */
    public static function renderAABB(iCollider:ICollider, zOffset:Number, mode:String):Void {
        if (iCollider == null) return;
        if (mode == null || mode == "") {
            mode = "line"; // 默认模式为仅线框模式
        }
        
        // 1. 收集绘制数据（几何数据和样式配置），根据 mode 调整各参数
        var data:Object = collectAABBData(iCollider, zOffset, mode);
        
        // 2. 根据收集的数据执行绘制操作
        drawCollectedData(data);
    }
    
    /**
     * 收集用于绘制 AABB 边界框的几何数据和样式配置，
     * 并根据 mode 参数配置不同的绘制样式。
     *
     * 详细说明：
     *   - 首先根据传入的碰撞器 iCollider 提取经过 zOffset 调整后的 AABB，
     *     同时应用全局效果偏移（SceneCoordinateManager.effectOffset）
     *   - 根据 AABB 的 left、right、top、bottom 属性计算出矩形四个顶点的坐标，
     *     顶点顺序依次为 [左上, 右上, 右下, 左下]
     *   - 预设绘图样式参数如下：
     *         fillColor : 0xFF0000（红色）
     *         lineColor : 0x00FF00（绿色）
     *         lineWidth : 默认 2 像素
     *         fillAlpha : 默认 80（填充透明度）
     *         lineAlpha : 默认 100（线条透明度）
     *         shadowCount : 默认 30（残影持续帧数）
     *   - 根据 mode 参数调整样式：
     *         "line"   - 仅线框：填充透明度设为 0；残影持续帧数设为 1
     *         "thick"  - 粗线框：填充透明度设为 0；线条宽度设为 4 像素；残影持续帧数设为 30
     *         "filled" - 填充模式：保持填充效果，残影持续帧数设为 30
     *
     * @param iCollider 需要调试绘制的碰撞器对象（实现 ICollider 接口）
     * @param zOffset   高度偏移量，用于确保渲染时的正确位置
     * @param mode      绘制模式控制字符串
     * @return 一个 Object 对象，包含以下属性：
     *         - vertices: Array — 顶点数组，顺序依次为 [左上, 右上, 右下, 左下]
     *         - fillColor: Number — 填充颜色（十六进制表示，如 0xFF0000）
     *         - lineColor: Number — 线条颜色（十六进制表示，如 0x00FF00）
     *         - lineWidth: Number — 线条宽度（单位像素）
     *         - fillAlpha: Number — 填充透明度
     *         - lineAlpha: Number — 线条透明度
     *         - shadowCount: Number — 残影持续帧数（控制显示帧数）
     */
    public static function collectAABBData(iCollider:ICollider, zOffset:Number, mode:String):Object {
        // 获取经过 zOffset 调整后的 AABB，并应用全局效果偏移
        var collider:AABB = iCollider.getAABB(zOffset).moveNew(SceneCoordinateManager.effectOffset);
        
        // 计算矩形四个顶点的坐标
        var p0:Vector = new Vector(collider.left, collider.top);
        var p1:Vector = new Vector(collider.right, collider.top);
        var p2:Vector = new Vector(collider.right, collider.bottom);
        var p3:Vector = new Vector(collider.left, collider.bottom);
        
        // =============== 默认绘图样式配置 ===============
        // 可以在这里换成你项目适合的默认值
        var fillColor:Number   = 0xFF0000;  // 填充色：红色
        var lineColor:Number   = 0x00FF00;  // 线条色：绿色
        var lineWidth:Number   = 2;         // 线条宽度
        var fillAlpha:Number   = 80;        // 填充透明度 (0~100)
        var lineAlpha:Number   = 100;       // 线条透明度 (0~100)
        var shadowCount:Number = 30;        // 残影持续帧数
        
        // =============== 根据 mode 调整样式配置 ===============
        switch(mode) {
            case "line":
                // 线框模式：示例采用青色线，较细，短暂出现
                lineColor   = 0x00FFFF;   // 青色
                lineWidth   = 2;          // 较细
                fillAlpha   = 0;          // 无填充
                lineAlpha   = 100;        // 完全不透明的线
                shadowCount = 5;          // 比原来略长，但仍然很短
                break;
            
            case "thick":
                // 粗线框模式：示例采用亮黄色，线更粗，残影稍长
                lineColor   = 0xFFFF00;   // 亮黄色
                lineWidth   = 6;          // 粗线条
                fillAlpha   = 0;          // 无填充
                lineAlpha   = 80;         // 稍微透明一点的线
                shadowCount = 20;         // 中等残影帧数
                break;
            
            case "filled":
                // 填充模式：示例保持红线红填充，线条稍微加粗，填充半透明
                fillColor   = 0xFF0000;   // 红色填充
                lineColor   = 0xFF0000;   // 线条也用红色
                lineWidth   = 3;          // 适中
                fillAlpha   = 60;         // 半透明
                lineAlpha   = 100;        // 线条不透明
                shadowCount = 30;         // 较长的残影帧数
                break;
            
            default:
                // 其他情况回退为最基础的线框模式
                lineColor   = 0x00FF00;
                lineWidth   = 2;
                fillAlpha   = 0;
                lineAlpha   = 100;
                shadowCount = 3;
                break;
        }
        
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
     * 根据提供的绘制数据对象，调用 VectorAfterimageRenderer 进行 AABB 边界框的绘制操作。
     * 本方法职责单一，仅负责将已收集的绘制数据交由绘图接口执行渲染。
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
