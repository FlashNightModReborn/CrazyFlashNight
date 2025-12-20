import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;
import org.flashNight.neur.Server.*;
import org.flashNight.arki.render.*;

/**
 * AABBCollider 类
 *
 * 基于轴对齐边界框 (Axis-Aligned Bounding Box, AABB) 的碰撞检测器。
 * 继承 AABB 类并实现 ICollider 接口，提供碰撞检测功能、边界坐标获取和碰撞信息计算。
 * 
 * 功能概述：
 * 1. 碰撞检测逻辑：通过比较两个 AABB 的边界坐标判断是否发生碰撞。
 * 2. 提供多种静态辅助方法，用于获取不同类型的对象 (如子弹、透明子弹、单位区域) 的边界信息。
 * 3. 支持动态更新边界信息，适配游戏中实时变化的对象坐标。
 * 4. 提供碰撞结果，包括重叠中心点与重叠范围。
 * 
 * 使用场景：主要用于游戏中的子弹碰撞检测、单位区域碰撞等。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.AABBCollider extends AABB implements ICollider {

    /**
     * 碰撞器工厂实例，用于管理碰撞器的创建与复用。
     */
    public var _factory:AbstractColliderFactory;

    /**
     * 更新函数引用，用于多态表达当前使用的更新路径
     */
    public var _update:Function;

    /**
     * 当前帧数，避免在同一帧内重复更新边界。
     */
    public var _currentFrame:Number = -1;

    /**
     * 用于aabb碰撞器的碰撞结果，缓存避免频繁创建
     */
    public static var result:CollisionResult = CollisionResult.Create(true, new Vector(0,0) ,1);

    /**
     * 用于aabb碰撞器的碰撞交互介质，缓存避免频繁创建
     */
    public static var AABB:AABB = new AABB(null);

    /**
     * 构造函数，初始化 AABB 的边界坐标。
     * 
     * @param left   左边界坐标
     * @param right  右边界坐标
     * @param top    上边界坐标
     * @param bottom 下边界坐标
     */
    public function AABBCollider(left:Number, right:Number, top:Number, bottom:Number) {
        super(left, right, top, bottom);
    }

    // ========================= 碰撞检测区域 ========== //

    /**
     * 检查与其他碰撞器的碰撞情况。
     *
     * 实现流程：
     * 1. 获取另一个碰撞器的 AABB 信息，并根据 zOffset 偏移值调整。
     * 2. 通过边界坐标比较，快速判断是否发生碰撞。
     * 3. 如果碰撞，计算重叠区域的中心点和覆盖率。
     * 
     * 检测边缘情况:边缘接触不视作碰撞
     * 
     * @param other   另一个 ICollider 实例
     * @param zOffset Z轴偏移量，用于模拟 3D 高度差
     * @return CollisionResult 实例，包含碰撞结果、重叠中心点等信息
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        // 提前声明并初始化本地变量
        // 获取 other 的 AABB 并存储到本地变量中

        var otherAABB:AABB = other.getAABB(zOffset);

        // 优化：提前返回不碰撞的情况，减少计算量
        // 提前声明并初始化 this 的相关属性到本地变量中

        var myRight:Number = this.right;
        var otherLeft:Number = otherAABB.left;
        if (myRight <= otherLeft) return CollisionResult.ORDERFALSE;

        var myLeft:Number = this.left;
        var otherRight:Number = otherAABB.right;
        if (myLeft >= otherRight) return CollisionResult.FALSE;

        var myBottom:Number = this.bottom;
        var otherTop:Number = otherAABB.top;
        if (myBottom <= otherTop) return CollisionResult.YORDERFALSE;  // Y轴上方分离

        var myTop:Number = this.top;
        var otherBottom:Number = otherAABB.bottom;
        if (myTop >= otherBottom) return CollisionResult.FALSE;  // Y轴下方分离

        var aabbResult:CollisionResult = AABBCollider.result;
        var aabbResultCenter:Vector = aabbResult.overlapCenter;
        aabbResultCenter.x = ((myLeft > otherLeft) ? myLeft : otherLeft) + ((myRight < otherRight) ? myRight : otherRight) >> 1;
        aabbResultCenter.y = ((myTop > otherTop) ? myTop : otherTop) + ((myBottom < otherBottom) ? myBottom : otherBottom) >> 1;

        return aabbResult;
    }

    /**
     * 获取当前碰撞器的 AABB 信息。
     *
     * @param zOffset Z轴偏移量，用于模拟高度差
     * @return AABB 实例，包含边界坐标
     */
    public function getAABB(zOffset:Number):AABB {
        var aabb = AABBCollider.AABB;
        aabb.left = this.left;
        aabb.right = this.right;
        aabb.top = this.top + zOffset;
        aabb.bottom = this.bottom + zOffset;   
        return aabb;
    }

    // ========================= 静态工厂方法区域 ========================= //

    /**
     * 从现有的 AABB 对象创建一个纯工具用的 AABBCollider 实例。
     * 该方法创建的碰撞器不与游戏对象绑定，主要用于几何计算、碰撞测试等工具场景。
     *
     * @param aabb 源 AABB 对象
     * @return AABBCollider 实例，边界坐标复制自源 AABB
     */
    public static function fromAABB(aabb:AABB):AABBCollider {
        return new AABBCollider(aabb.left, aabb.right, aabb.top, aabb.bottom);
    }

    /**
     * 创建一个临时的工具用 AABBCollider，用于快速几何计算。
     * 这个方法创建的碰撞器适用于一次性计算，不会缓存任何状态。
     *
     * @param left   左边界坐标
     * @param right  右边界坐标
     * @param top    上边界坐标
     * @param bottom 下边界坐标
     * @return AABBCollider 实例
     */
    public static function createTempCollider(left:Number, right:Number, top:Number, bottom:Number):AABBCollider {
        return new AABBCollider(left, right, top, bottom);
    }

    /**
     * 从中心点和尺寸创建一个工具用的 AABBCollider。
     * 
     * @param centerX 中心点 X 坐标
     * @param centerY 中心点 Y 坐标
     * @param width   宽度
     * @param height  高度
     * @return AABBCollider 实例
     */
    public static function fromCenter(centerX:Number, centerY:Number, width:Number, height:Number):AABBCollider {
        var halfWidth:Number = width * 0.5;
        var halfHeight:Number = height * 0.5;
        return new AABBCollider(
            centerX - halfWidth,  // left
            centerX + halfWidth,  // right
            centerY - halfHeight, // top
            centerY + halfHeight  // bottom
        );
    }

    // ========================= 动态更新方法区域 ========================= //
    // 已移除静态辅助方法 getBulletCoordinates/getUnitAreaCoordinates
    // 优化后直接在 update 方法中内联处理，避免函数调用和临时对象分配

    /**
     * 基于透明子弹对象更新碰撞器的边界（内联优化版）
     *
     * 直接从透明子弹坐标计算边界，避免函数调用和临时对象创建的开销。
     * 透明子弹使用固定的 25x25 尺寸（半径 12.5）。
     *
     * @param bullet 透明子弹对象
     *
     * 性能优化：
     * - 消除了 getTransparentBulletCoordinates() 函数调用开销
     * - 避免创建临时坐标对象，减少GC压力
     * - 直接计算并赋值，减少属性访问次数
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        // 内联展开：直接计算透明子弹边界（25x25，半径12.5）
        var bullet_x:Number = bullet._x;
        var bullet_y:Number = bullet._y;

        this.left = bullet_x - 12.5;
        this.right = bullet_x + 12.5;
        this.top = bullet_y - 12.5;
        this.bottom = bullet_y + 12.5;
    }

    /**
     * 基于子弹和检测区域的 MovieClip 实例更新碰撞器的边界。
     *
     * 性能优化（借鉴 PolygonCollider）：
     * - 帧去重：同帧多次调用直接跳过
     * - 零分配：直接使用 getRect 结果，无缓存对象创建
     * - AABB 不旋转假设：无需复杂的偏移计算
     *
     * @param bullet        子弹 MovieClip 实例
     * @param detectionArea 检测区域的 MovieClip 实例
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        // 帧去重：同帧多次调用直接跳过
        var frame:Number = _root.帧计时器.当前帧数;
        if (this._currentFrame == frame) return;
        this._currentFrame = frame;

        // 直接获取检测区域在 gameworld 中的边界
        // AABB 不旋转，可以直接使用 getRect 结果
        var areaRect:Object = detectionArea.getRect(_root.gameworld);
        this.left = areaRect.xMin;
        this.right = areaRect.xMax;
        this.top = areaRect.yMin;
        this.bottom = areaRect.yMax;
    }

    /**
     * 基于单位区域的 MovieClip 实例更新碰撞器的边界。
     *
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        // var frame = _root.帧计时器.当前帧数;
        //if (this._currentFrame == frame) return;

        // this._currentFrame = frame;
        var unitRect:Object = unit.area.getRect(_root.gameworld);
        
        // 直接赋值边界坐标，避免创建临时对象
        this.left   = unitRect.xMin;
        this.right  = unitRect.xMax;
        this.top    = unitRect.yMin;
        this.bottom = unitRect.yMax;

        if(_root.调试模式) AABBRenderer.renderAABB(this, 0, "unhit")
    }

    /**
     * 设置碰撞器的工厂对象。
     *
     * @param factory 工厂实例
     */
    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    /**
     * 获取碰撞器的工厂对象。
     *
     * @return 工厂实例
     */
    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }
}
