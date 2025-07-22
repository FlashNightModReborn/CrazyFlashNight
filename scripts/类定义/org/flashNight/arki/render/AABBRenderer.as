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
 *   3. 当 zRange > 0 时，基于 "主 AABB + y 轴平移/伸缩" 来可视化
 *      zOffset ± zRange 的上下边界，避免与主 AABB 形状脱节。
 *
 * 使用要点：
 *   - 若项目中 Z 轴与屏幕坐标系 (x,y) 的对应方式有特殊需求，
 *     可在 shiftVerticesForZ 方法中自定义映射规则（平移、缩放、倾斜等）。
 */
class org.flashNight.arki.render.AABBRenderer {

    // =============== 配置缓存 ===============
    private static var modeConfigs:Object;
    private static var isInitialized:Boolean = false;

    /**
     * 初始化模式配置对象
     */
    private static function initModeConfigs():Void {
        if (isInitialized) return;
        
        modeConfigs = new Object();
        
        // line 模式配置
        var lineConfig:Object = new Object();
        lineConfig.fillColor = 0xFF0000;
        lineConfig.lineColor = 0x00FFFF;
        lineConfig.lineWidth = 2;
        lineConfig.fillAlpha = 0;
        lineConfig.lineAlpha = 100;
        lineConfig.shadowCount = 5;
        modeConfigs["line"] = lineConfig;
        
        // thick 模式配置
        var thickConfig:Object = new Object();
        thickConfig.fillColor = 0xFF0000;
        thickConfig.lineColor = 0xFFFF00;
        thickConfig.lineWidth = 6;
        thickConfig.fillAlpha = 0;
        thickConfig.lineAlpha = 80;
        thickConfig.shadowCount = 20;
        modeConfigs["thick"] = thickConfig;
        
        // filled 模式配置
        var filledConfig:Object = new Object();
        filledConfig.fillColor = 0xFF0000;
        filledConfig.lineColor = 0xFF0000;
        filledConfig.lineWidth = 3;
        filledConfig.fillAlpha = 60;
        filledConfig.lineAlpha = 100;
        filledConfig.shadowCount = 30;
        modeConfigs["filled"] = filledConfig;
        
        // unhit 模式配置
        var unhitConfig:Object = new Object();
        unhitConfig.fillColor = 0x00FF00;
        unhitConfig.lineColor = 0x00FF00;
        unhitConfig.lineWidth = 2;
        unhitConfig.fillAlpha = 20;
        unhitConfig.lineAlpha = 100;
        unhitConfig.shadowCount = 10;
        modeConfigs["unhit"] = unhitConfig;

        // =============== 扫描锁定模式系列 ===============
        // scan1 模式配置 - 初始扫描（淡青色，最轻微）
        var scan1Config:Object = new Object();
        scan1Config.fillColor = 0x00FFFF;    // 淡青色
        scan1Config.lineColor = 0x00FFFF;    // 淡青色
        scan1Config.lineWidth = 1;           // 细线
        scan1Config.fillAlpha = 10;          // 很低的填充透明度
        scan1Config.lineAlpha = 40;          // 较低的线条透明度
        scan1Config.shadowCount = 1;         // 最少残影
        modeConfigs["scan1"] = scan1Config;
        
        // scan2 模式配置 - 检测中（淡黄色，轻微增强）
        var scan2Config:Object = new Object();
        scan2Config.fillColor = 0xFFFF00;    // 黄色
        scan2Config.lineColor = 0xFFFF00;    // 黄色
        scan2Config.lineWidth = 1;           // 细线
        scan2Config.fillAlpha = 15;          // 稍高的填充透明度
        scan2Config.lineAlpha = 60;          // 中等线条透明度
        scan2Config.shadowCount = 2;         // 较少残影
        modeConfigs["scan2"] = scan2Config;
        
        // scan3 模式配置 - 锁定中（橙色，明显增强）
        var scan3Config:Object = new Object();
        scan3Config.fillColor = 0xFF8000;    // 橙色
        scan3Config.lineColor = 0xFF8000;    // 橙色
        scan3Config.lineWidth = 2;           // 中等线宽
        scan3Config.fillAlpha = 25;          // 中等填充透明度
        scan3Config.lineAlpha = 80;          // 较高线条透明度
        scan3Config.shadowCount = 3;         // 中等残影
        modeConfigs["scan3"] = scan3Config;
        
        // scan4 模式配置 - 完全锁定（红色，最强烈）
        var scan4Config:Object = new Object();
        scan4Config.fillColor = 0xFF0000;    // 红色
        scan4Config.lineColor = 0xFF0000;    // 红色
        scan4Config.lineWidth = 2;           // 中等线宽
        scan4Config.fillAlpha = 35;          // 较高填充透明度
        scan4Config.lineAlpha = 100;         // 完全不透明线条
        scan4Config.shadowCount = 4;         // 最多残影（但仍<5）
        modeConfigs["scan4"] = scan4Config;
        
        isInitialized = true;
    }

    /**
     * 获取指定模式的配置，如果模式不存在则返回默认配置
     */
    private static function getModeConfig(mode:String):Object {
        initModeConfigs();
        
        var config:Object = modeConfigs[mode];
        if (config != null) {
            return config;
        }
        
        // 返回默认配置
        var defaultConfig:Object = new Object();
        defaultConfig.fillColor = 0x0000FF;
        defaultConfig.lineColor = 0x0000FF;
        defaultConfig.lineWidth = 2;
        defaultConfig.fillAlpha = 0;
        defaultConfig.lineAlpha = 100;
        defaultConfig.shadowCount = 3;
        return defaultConfig;
    }

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
        
        // =============== 2. 根据 mode 获取样式配置 ===============
        var styleConfig:Object = getModeConfig(mode);
        
        // 提取样式参数
        var fillColor:Number   = styleConfig.fillColor;
        var lineColor:Number   = styleConfig.lineColor;
        var lineWidth:Number   = styleConfig.lineWidth;
        var fillAlpha:Number   = styleConfig.fillAlpha;
        var lineAlpha:Number   = styleConfig.lineAlpha;
        var shadowCount:Number = styleConfig.shadowCount;
        
        // =============== 3. 组装主要 AABB 的绘制信息 ===============
        var mainVertices:Array = [p0, p1, p2, p3];
        var mainData:Object = new Object();
        mainData.vertices = mainVertices;
        mainData.fillColor = fillColor;
        mainData.lineColor = lineColor;
        mainData.lineWidth = lineWidth;
        mainData.fillAlpha = fillAlpha;
        mainData.lineAlpha = lineAlpha;
        mainData.shadowCount = shadowCount;
        
        // =============== 4. 基于主 AABB 顶点计算 minZ/maxZ AABB（若 zRange>0） ===============
        var minZData:Object = null;
        var maxZData:Object = null;
        if(zRange > 0) {
            // 加入一个缩放系数
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
            
            minZData = new Object();
            minZData.vertices = minZVertices;
            minZData.fillColor = 0x000000;
            minZData.lineColor = zRangeLineColor;
            minZData.lineWidth = zRangeLineWidth;
            minZData.fillAlpha = zRangeFillAlpha;
            minZData.lineAlpha = zRangeLineAlpha;
            minZData.shadowCount = zRangeShadowCount;
            
            maxZData = new Object();
            maxZData.vertices = maxZVertices;
            maxZData.fillColor = 0x000000;
            maxZData.lineColor = zRangeLineColor;
            maxZData.lineWidth = zRangeLineWidth;
            maxZData.fillAlpha = zRangeFillAlpha;
            maxZData.lineAlpha = zRangeLineAlpha;
            maxZData.shadowCount = zRangeShadowCount;
        }
        
        // =============== 5. 返回包含主 AABB + zRange AABB 的综合数据 ===============
        var result:Object = new Object();
        result.mainAABB = mainData;  // 当前 zOffset AABB
        result.minZAABB = minZData;  // zOffset - zRange
        result.maxZAABB = maxZData;  // zOffset + zRange
        return result;
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
            // 如果你需要额外做"缩放"、"倾斜"或"梯形变形"，
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