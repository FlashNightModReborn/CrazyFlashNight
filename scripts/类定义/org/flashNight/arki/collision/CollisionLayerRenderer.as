/**
 * CollisionLayerRenderer.as
 * 碰撞层渲染器 - 统一管理碰撞箱的绘制操作
 *
 * 功能：
 * 1. 封装所有碰撞箱绘制逻辑 
 * 2. 提供脏标记机制供小地图使用
 * 3. 绘制完成后自动发布事件通知
 *
 * 使用方式：
 * - 绘制边界: CollisionLayerRenderer.drawBoundary()
 * - 绘制多边形: CollisionLayerRenderer.drawPolygons(arr)
 * - 绘制矩形: CollisionLayerRenderer.drawRect(rect)
 * - 检查脏标记: CollisionLayerRenderer.consumeDirty()
 */

import org.flashNight.neur.Event.EventBus;
import org.flashNight.arki.spatial.transform.SceneCoordinateManager;
import org.flashNight.sara.util.Vector;

class org.flashNight.arki.collision.CollisionLayerRenderer {

    // ==================== 私有状态 ====================

    /** 脏标记 - 碰撞层内容发生变化时为 true */
    private static var _dirty:Boolean = false;

    /** 事件名称常量 */
    public static var EVENT_COLLISION_CHANGED:String = "CollisionLayerChanged";

    // ==================== 绘制方法 ====================

    /**
     * 绘制边界碰撞箱（带中空效果）
     * 原 _root.绘制地图碰撞箱 的核心绘制逻辑
     *
     * @param collisionLayer 碰撞层 MovieClip
     * @param xmin 内边界左
     * @param xmax 内边界右
     * @param ymin 内边界上
     * @param ymax 内边界下
     * @param margin 外边距，默认 300
     * @param debugMode 是否调试模式
     */
    public static function drawBoundary(
        collisionLayer:MovieClip,
        xmin:Number, xmax:Number,
        ymin:Number, ymax:Number,
        margin:Number,
        debugMode:Boolean
    ):Void {
        if (margin == undefined) margin = 300;

        // 计算外框坐标
        var outerLeft:Number   = xmin - margin;
        var outerRight:Number  = xmax + margin;
        var outerTop:Number    = ymin - margin;
        var outerBottom:Number = ymax + margin;

        // 设置线条和填充样式
        collisionLayer.lineStyle(2, 0xFF0000, 100);   // 红色边线
        collisionLayer.beginFill(0x66CC66, 100);      // 绿色填充

        // 绘制外框 (顺时针)
        collisionLayer.moveTo(outerLeft, outerTop);
        collisionLayer.lineTo(outerRight, outerTop);
        collisionLayer.lineTo(outerRight, outerBottom);
        collisionLayer.lineTo(outerLeft, outerBottom);
        collisionLayer.lineTo(outerLeft, outerTop);

        // 绘制内框 (逆时针) - 形成中空效果
        collisionLayer.moveTo(xmin, ymin);
        collisionLayer.lineTo(xmax, ymin);
        collisionLayer.lineTo(xmax, ymax);
        collisionLayer.lineTo(xmin, ymax);
        collisionLayer.lineTo(xmin, ymin);

        collisionLayer.endFill();

        // 设置可见性
        if (debugMode) {
            collisionLayer._visible = true;
            collisionLayer._alpha = 50;
        } else {
            collisionLayer._visible = false;
        }

        // 标记脏并发布事件
        markDirty();
    }

    /**
     * 通过多边形数组绘制碰撞箱
     * 原 _root.通过数组绘制地图碰撞箱
     *
     * @param collisionLayer 碰撞层 MovieClip
     * @param polygonArray 多边形数组，每个元素包含 Point 数组
     */
    public static function drawPolygons(collisionLayer:MovieClip, polygonArray:Array):Void {
        if (!polygonArray || polygonArray.length == 0) return;

        for (var i:Number = 0; i < polygonArray.length; i++) {
            var polygon:Array = polygonArray[i].Point;
            if (!polygon || polygon.length < 3) continue;

            collisionLayer.beginFill(0x000000);

            // 解析第一个点
            var pt:Array = polygon[0].split(",");
            var px:Number = Number(pt[0]);
            var py:Number = Number(pt[1]);
            collisionLayer.moveTo(px, py);

            // 逆序绘制其余点
            for (var j:Number = polygon.length - 1; j >= 0; j--) {
                pt = polygon[j].split(",");
                px = Number(pt[0]);
                py = Number(pt[1]);
                collisionLayer.lineTo(px, py);
            }

            collisionLayer.endFill();
        }

        collisionLayer._visible = false;

        // 标记脏并发布事件
        markDirty();
    }

    /**
     * 绘制矩形碰撞箱
     * 原 _root.通过影片剪辑外框绘制地图碰撞箱 的核心逻辑
     *
     * @param collisionLayer 碰撞层 MovieClip
     * @param rect 矩形对象 {xMin, yMin, xMax, yMax}
     */
    public static function drawRect(collisionLayer:MovieClip, rect:Object):Void {
        if (!rect) return;

        collisionLayer.beginFill(0x000000);
        collisionLayer.moveTo(rect.xMin, rect.yMin);
        collisionLayer.lineTo(rect.xMax, rect.yMin);
        collisionLayer.lineTo(rect.xMax, rect.yMax);
        collisionLayer.lineTo(rect.xMin, rect.yMax);
        collisionLayer.lineTo(rect.xMin, rect.yMin);
        collisionLayer.endFill();

        collisionLayer._visible = false;

        // 标记脏并发布事件
        markDirty();
    }

    /**
     * 绘制单个障碍物矩形（供 ObstacleRenderer 调用）
     * 不改变可见性，不单独发布事件（批量绘制时由调用者统一处理）
     *
     * @param collisionLayer 碰撞层 MovieClip
     * @param rect 矩形对象 {xMin, yMin, xMax, yMax}
     * @param publishEvent 是否发布事件，默认 true
     */
    public static function drawObstacle(collisionLayer:MovieClip, rect:Object, publishEvent:Boolean):Void {
        if (!rect) return;
        if (publishEvent == undefined) publishEvent = true;

        collisionLayer.beginFill(0x000000);
        collisionLayer.moveTo(rect.xMin, rect.yMin);
        collisionLayer.lineTo(rect.xMax, rect.yMin);
        collisionLayer.lineTo(rect.xMax, rect.yMax);
        collisionLayer.lineTo(rect.xMin, rect.yMax);
        collisionLayer.lineTo(rect.xMin, rect.yMin);
        collisionLayer.endFill();

        if (publishEvent) {
            markDirty();
        } else {
            // 仅标记脏，不发布事件
            _dirty = true;
        }
    }

    // ==================== 脏标记管理 ====================

    /**
     * 标记碰撞层为脏并发布事件
     */
    public static function markDirty():Void {
        _dirty = true;
        EventBus.getInstance().publish(EVENT_COLLISION_CHANGED);
    }

    /**
     * 检查脏标记（不重置）
     * @return 当前脏标记状态
     */
    public static function isDirty():Boolean {
        return _dirty;
    }

    /**
     * 消费脏标记（检查并重置）
     * 小地图调用此方法判断是否需要重绘
     *
     * @return 之前的脏标记状态
     */
    public static function consumeDirty():Boolean {
        var wasDirty:Boolean = _dirty;
        _dirty = false;
        return wasDirty;
    }

    /**
     * 强制重置脏标记
     */
    public static function resetDirty():Void {
        _dirty = false;
    }

    // ==================== 工具方法 ====================

    /**
     * 获取碰撞层引用
     * @return 碰撞层 MovieClip
     */
    public static function getLayer():MovieClip {
        return _root.collisionLayer;
    }
}
