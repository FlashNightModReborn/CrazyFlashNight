import org.flashNight.sara.util.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider;
import org.flashNight.arki.render.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.spatial.transform.*;

/**
 * AABBRenderer 类
 *
 * 主要功能：
 *   1. 用于可视化调试 AABBCollider（轴对齐边界框）碰撞器的边界框绘制。
 *   2. 提供多种绘制模式，以快速区分不同的碰撞状态（线框、粗线框、填充、未命中等）。
 *   3. 当 zRange > 0 时，基于 “主 AABB + y 轴平移/伸缩” 来可视化
 *      zOffset ± zRange 的上下边界，避免与主 AABB 形状脱节。
 *
 * 使用要点：
 *   - 若项目中 Z 轴与屏幕坐标系 (x,y) 的对应方式有特殊需求，
 *     可在 shiftVerticesForZ 方法中自定义映射规则（平移、缩放、倾斜等）。
 */
class org.flashNight.arki.render.AABBRenderer {

    /**
     * 渲染传入的 AABBCollider 对象对应的轴对齐边界框，并可选地可视化 z 轴范围。
     *
     * @param iCollider 需要调试绘制的 AABBCollider 对象（实现 ICollider 接口）
     * @param zOffset   高度偏移量，用于在渲染时区分碰撞检测的高度（z 轴偏移）
     * @param mode      绘制模式控制字符串（"line"、"thick"、"filled"、"unhit" 等）
     * @param zRange    子弹的 Z 轴攻击范围。若 0 则不绘制 zRange 辅助边界。
     */
    public static function renderAABB(iCollider:ICollider, 
                                      zOffset:Number, 
                                      mode:String, 
                                      zRange:Number):Void 
    {
        if (iCollider == null) return;

        if (mode == null || mode == "") {
            mode = "line"; // 默认模式为线框模式
        }
        if (zRange == null) {
            zRange = 0;   // 若不传该参数，则设为 0 表示不绘制 zRange
        }
        
        // 1. 收集绘制数据（几何数据和样式配置）
        var data:Object = collectAABBData(iCollider, zOffset, mode, zRange);
        
        // 2. 绘制
        drawCollectedData(data);
    }
    
    /**
     * 收集用于绘制 AABB 边界框的几何数据，包含：
     *   - mainAABB: 当前 zOffset 的主 AABB
     *   - minZAABB / maxZAABB: 分别表示 zOffset - zRange / zOffset + zRange 的边界
     *                          (通过对主 AABB 的顶点做 y 轴平移/变换来实现)
     */
    public static function collectAABBData(iCollider:ICollider, 
                                           zOffset:Number, 
                                           mode:String, 
                                           zRange:Number):Object
    {
        // =============== 1. 获取主 AABB ===============
        var collider:AABB = iCollider.getAABB(zOffset)
                                      .moveNew(SceneCoordinateManager.effectOffset);
        
        // 计算矩形四个顶点的坐标（左上、右上、右下、左下）
        var p0:Vector = new Vector(collider.left,   collider.top);
        var p1:Vector = new Vector(collider.right,  collider.top);
        var p2:Vector = new Vector(collider.right,  collider.bottom);
        var p3:Vector = new Vector(collider.left,   collider.bottom);
        
        // ================== 默认绘图样式配置 ===================
        var fillColor:Number   = 0xFF0000;  // 填充色：红色
        var lineColor:Number   = 0x00FF00;  // 线条色：绿色
        var lineWidth:Number   = 2;         // 线条宽度
        var fillAlpha:Number   = 80;        // 填充透明度 (0~100)
        var lineAlpha:Number   = 100;       // 线条透明度 (0~100)
        var shadowCount:Number = 30;        // 残影持续帧数
        
        // =============== 2. 根据 mode 调整主要 AABB 的样式 ===============
        switch(mode) {
            case "line":
                lineColor   = 0x00FFFF; // 青色线
                lineWidth   = 2;
                fillAlpha   = 0;
                lineAlpha   = 100;
                shadowCount = 5;
                break;
            
            case "thick":
                lineColor   = 0xFFFF00; // 亮黄色线
                lineWidth   = 6;
                fillAlpha   = 0;
                lineAlpha   = 80;
                shadowCount = 20;
                break;
            
            case "filled":
                fillColor   = 0xFF0000;
                lineColor   = 0xFF0000;
                lineWidth   = 3;
                fillAlpha   = 60;
                lineAlpha   = 100;
                shadowCount = 30;
                break;
            
            case "unhit":
                fillColor   = 0x00FF00;
                lineColor   = 0x00FF00;
                lineWidth   = 2;
                fillAlpha   = 20;  
                lineAlpha   = 100;
                shadowCount = 10;
                break;
            
            default:
                fillColor   = 0x0000FF;
                lineColor   = 0x0000FF;
                lineWidth   = 2;
                fillAlpha   = 0;
                lineAlpha   = 100;
                shadowCount = 3;
                break;
        }
        
        // =============== 3. 组装主要 AABB 的绘制信息 ===============
        var mainVertices:Array = [p0, p1, p2, p3];
        var mainData:Object = {
            vertices:   mainVertices,
            fillColor:  fillColor,
            lineColor:  lineColor,
            lineWidth:  lineWidth,
            fillAlpha:  fillAlpha,
            lineAlpha:  lineAlpha,
            shadowCount:shadowCount
        };
        
        // =============== 4. 基于主 AABB 顶点计算 minZ/maxZ AABB（若 zRange>0） ===============
        var minZData:Object = null;
        var maxZData:Object = null;
        if(zRange > 0) {
            // 你可以在此处自定义：zRange 在屏幕上相当于多少像素？缩放还是平移？
            // 示例：假设 “1 的 zRange = 1 像素的 y 位移”，
            //       zOffset + zRange 往 y 轴下方平移
            //       zOffset - zRange 往 y 轴上方平移
            
            // 可酌情加入一个缩放系数
            var Z_TO_Y_SCALE:Number = 1; 
            
            // 下边界：zOffset - zRange => 相对主 AABB 向上移动
            var minZVertices:Array = shiftVerticesForZ(mainVertices, -zRange * Z_TO_Y_SCALE);
            
            // 上边界：zOffset + zRange => 向下移动
            var maxZVertices:Array = shiftVerticesForZ(mainVertices, zRange * Z_TO_Y_SCALE);
            
            // 这里的样式与之前大同小异（灰色线、半透明等）
            var zRangeLineColor:Number = 0x999999; 
            var zRangeLineWidth:Number = 1;
            var zRangeFillAlpha:Number = 0;
            var zRangeLineAlpha:Number = 60; // 半透明
            var zRangeShadowCount:Number = 10;
            
            minZData = {
                vertices: minZVertices,
                fillColor: 0x000000,
                lineColor: zRangeLineColor,
                lineWidth: zRangeLineWidth,
                fillAlpha: zRangeFillAlpha,
                lineAlpha: zRangeLineAlpha,
                shadowCount: zRangeShadowCount
            };
            
            maxZData = {
                vertices: maxZVertices,
                fillColor: 0x000000,
                lineColor: zRangeLineColor,
                lineWidth: zRangeLineWidth,
                fillAlpha: zRangeFillAlpha,
                lineAlpha: zRangeLineAlpha,
                shadowCount: zRangeShadowCount
            };
        }
        
        // =============== 5. 返回包含主 AABB + zRange AABB 的综合数据 ===============
        return {
            mainAABB: mainData,  // 当前 zOffset AABB
            minZAABB: minZData,  // zOffset - zRange
            maxZAABB: maxZData   // zOffset + zRange
        };
    }

    
    /**
     * 将一组矩形顶点在 y 轴方向做平移或其他变换，可用于近似表示 zOffset ± zRange。
     *
     * @param vertices 原始矩形的四顶点 (Array of Vector)
     * @param yShift   要在 y 轴上平移的像素数 (正值表示往下, 负值表示往上)
     * @return Array   新的顶点数组 (不会修改原先的 vertices)
     */
    private static function shiftVerticesForZ(vertices:Array, yShift:Number):Array {
        var newVerts:Array = [];
        var len:Number = vertices.length;
        for(var i:Number = 0; i < len; i++) {
            var v:Vector = vertices[i];
            // 如果你需要额外做“缩放”、“倾斜”或“梯形变形”，
            // 也可在此处替换成更复杂的运算
            newVerts.push(new Vector(v.x, v.y + yShift));
        }
        return newVerts;
    }
    
    
    /**
     * 根据提供的数据对象，分别绘制 mainAABB 以及 zRange 边界（minZAABB 与 maxZAABB）。
     * 当 minZAABB 与 maxZAABB 均存在且样式相同时，调用 drawShapes 进行合并优化绘制。
     */
    public static function drawCollectedData(data:Object):Void {
        // 1) 绘制主 AABB
        var main:Object = data.mainAABB;
        if (main != null) {
            VectorAfterimageRenderer.instance.drawShape(
                main.vertices,
                main.fillColor,
                main.lineColor,
                main.lineWidth,
                main.fillAlpha,
                main.lineAlpha,
                main.shadowCount
            );
        }
        
        // 2) 绘制辅助 zRange 边界
        // 如果同时存在 minZAABB 和 maxZAABB，并且样式相同，则使用 drawShapes 优化绘制
        if (data.minZAABB != null && data.maxZAABB != null) {
            // 这里假定两个辅助边界使用相同的样式配置（由 collectAABBData 构造时保证）
            var commonStyle:Object = data.minZAABB;
            // 组合两组顶点数组
            var shapes:Array = [ data.minZAABB.vertices, data.maxZAABB.vertices ];
            VectorAfterimageRenderer.instance.drawShapes(
                shapes,
                commonStyle.fillColor,
                commonStyle.lineColor,
                commonStyle.lineWidth,
                commonStyle.fillAlpha,
                commonStyle.lineAlpha,
                commonStyle.shadowCount
            );
        } else {
            // 若只有其中一个存在，则分别调用 drawShape 绘制
            if (data.minZAABB != null) {
                var minData:Object = data.minZAABB;
                VectorAfterimageRenderer.instance.drawShape(
                    minData.vertices,
                    minData.fillColor,
                    minData.lineColor,
                    minData.lineWidth,
                    minData.fillAlpha,
                    minData.lineAlpha,
                    minData.shadowCount
                );
            }
            if (data.maxZAABB != null) {
                var maxData:Object = data.maxZAABB;
                VectorAfterimageRenderer.instance.drawShape(
                    maxData.vertices,
                    maxData.fillColor,
                    maxData.lineColor,
                    maxData.lineWidth,
                    maxData.fillAlpha,
                    maxData.lineAlpha,
                    maxData.shadowCount
                );
            }
        }
    }

}
