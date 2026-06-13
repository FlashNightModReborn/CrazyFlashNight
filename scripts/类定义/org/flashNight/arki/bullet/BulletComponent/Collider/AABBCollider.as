import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
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
 *
 * ========================= 宽相碰撞器基类契约 =========================
 *
 * 本类是所有宽相碰撞器的基类（extends AABB，天然持有 left/right/top/bottom）。
 * 所有子类在实现 update 方法时必须遵守 ICollider C2 不变量：
 *
 *   【子类 update 契约】
 *   updateFromBullet / updateFromTransparentBullet / updateFromUnitArea
 *   在返回前必须将 this.left, this.right, this.top, this.bottom 更新为
 *   当前几何形状的精确轴对齐包围盒。
 *
 *   【原因】
 *   BulletQueueProcessor 的宽相内联路径直接读取这四个属性：
 *     uTop = unitArea.top + zOffset;
 *     uBottom = unitArea.bottom + zOffset;
 *     if (areaAABB.left >= unitArea.right || ...)
 *   不经过 getAABB(zOffset)，因此属性必须始终处于最新状态。
 *
 *   【已验证子类】
 *   - AABBCollider: updateFromBullet/updateFromTransparentBullet/updateFromUnitArea ✓
 *   - CoverageAABBCollider: 继承本类 update 方法 ✓
 *   - RayCollider: 所有 update 方法从射线端点计算并写入 left/right/top/bottom ✓
 *   - PointCollider: 所有 update 方法同步 _position 和 left/right/top/bottom ✓
 *
 * =====================================================================
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
    public var _currentFrame:Number;

    /**
     * 用于aabb碰撞器的碰撞结果，缓存避免频繁创建
     */
    public static var result:CollisionResult = CollisionResult.Create(true, new Vector(0,0) ,1);

    /**
     * 用于aabb碰撞器的碰撞交互介质，缓存避免频繁创建
     */
    public static var AABB:AABB = new AABB(null);

    /**
     * 对象化联弹边界计算用的可复用坐标点（避免每帧分配）
     */
    private static var chainPt:Object = {x: 0, y: 0};

    // ---------- 子弹区域 → gameworld 仿射帧缓存（对象化联弹共享） ----------
    // localToGlobal/globalToLocal 是 native 方法调用（极重带），旧实现逐弹逐角调用
    // 每帧可达数十次；该变换对全部对象化联弹相同且帧内恒定，按 帧计时器.当前帧数
    // 缓存，每帧仅在首个调用方处用 3 个基准点重建一次（6 次 native 调用/帧 → 0/弹）。
    // PolygonCollider.updateFromChainObject 复用同一缓存，故为 public。
    public static var zoneFrame:Number = -1;
    public static var zoneA:Number = 1;
    public static var zoneB:Number = 0;
    public static var zoneC:Number = 0;
    public static var zoneD:Number = 1;
    public static var zoneTx:Number = 0;
    public static var zoneTy:Number = 0;

    /**
     * 重建 子弹区域→gameworld 仿射缓存（每帧至多一次，调用方先做帧戳判别）
     */
    public static function refreshChainZoneAffine(frame:Number):Void {
        zoneFrame = frame;
        var world:MovieClip = _root.gameworld;
        var zone:MovieClip = world.子弹区域;
        var pt:Object = chainPt;
        pt.x = 0; pt.y = 0;
        zone.localToGlobal(pt);
        world.globalToLocal(pt);
        var t0x:Number = pt.x;
        var t0y:Number = pt.y;
        pt.x = 1; pt.y = 0;
        zone.localToGlobal(pt);
        world.globalToLocal(pt);
        zoneA = pt.x - t0x;
        zoneB = pt.y - t0y;
        pt.x = 0; pt.y = 1;
        zone.localToGlobal(pt);
        world.globalToLocal(pt);
        zoneC = pt.x - t0x;
        zoneD = pt.y - t0y;
        zoneTx = t0x;
        zoneTy = t0y;
    }

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
        aabbResultCenter.x = (((myLeft > otherLeft) ? myLeft : otherLeft) + ((myRight < otherRight) ? myRight : otherRight)) >> 1;
        aabbResultCenter.y = (((myTop > otherTop) ? myTop : otherTop) + ((myBottom < otherBottom) ? myBottom : otherBottom)) >> 1;

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

    // ========================= 静态辅助方法区域 ========================= //

    /**
     * 提取子弹与检测区域的边界坐标。
     *
     * @param bullet        子弹的 MovieClip 实例
     * @param detectionArea 子弹检测区域的 MovieClip 实例
     * @return 包含边界坐标的 Object：left, right, top, bottom
     */
    private static function getBulletCoordinates(bullet:MovieClip, detectionArea:MovieClip):Object {
        var areaRect:Object = detectionArea.getRect(_root.gameworld);
        return {
            left: areaRect.xMin,
            right: areaRect.xMax,
            top: areaRect.yMin,
            bottom: areaRect.yMax
        };
    }

    // 已移除 getTransparentBulletCoordinates() - 已内联到 updateFromTransparentBullet() 中以优化性能

    /**
     * 提取单位区域的边界坐标。
     *
     * @param unit 包含 area 属性的单位 MovieClip 实例
     * @return 包含边界坐标的 Object：left, right, top, bottom
     */
    private static function getUnitAreaCoordinates(unit:MovieClip):Object {
        var unitRect:Object = unit.area.getRect(_root.gameworld);
        return {
            left: unitRect.xMin,
            right: unitRect.xMax,
            top: unitRect.yMin,
            bottom: unitRect.yMax
        };
    }

    // ========================= 动态更新方法区域 ========================= //

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
     * 性能优化：
     * - 单次 bullet[area_key] 查表（避免重复哈希计算）
     * - 缓存结构展平：直接存储 left/right/top/bottom，无嵌套 area 对象
     *
     * @param bullet        子弹 MovieClip 实例
     * @param detectionArea 检测区域的 MovieClip 实例
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var bullet_x:Number = bullet._x;
        var bullet_y:Number = bullet._y;

        // 生成唯一缓存键值
        var area_key:Number = (detectionArea._x << 16) | (detectionArea._height << 8) | (detectionArea._width ^ detectionArea._y);
        var cache:Object = bullet[area_key];

        // 单次查表：miss 时创建展平缓存
        if (!cache) {
            var coords:Object = getBulletCoordinates(bullet, detectionArea);
            cache = {
                left: coords.left,
                right: coords.right,
                top: coords.top,
                bottom: coords.bottom,
                x: bullet_x,
                y: bullet_y
            };
            bullet[area_key] = cache;
        }

        var x_offset:Number = bullet_x - cache.x;
        var y_offset:Number = bullet_y - cache.y;

        this.left = cache.left + x_offset;
        this.right = cache.right + x_offset;
        this.top = cache.top + y_offset;
        this.bottom = cache.bottom + y_offset;
    }

    /**
     * 基于对象化联弹（无 area 子剪辑的纯对象子弹）更新碰撞器边界。
     *
     * 等价契约：与 updateFromBullet 的 detectionArea.getRect(_root.gameworld) 语义一致——
     * 联弹组本地碰撞盒（盒x/盒y/盒宽/盒高，即 area 子剪辑的本地矩形）四角经子弹
     * 仿射矩阵映射到 子弹区域 坐标，再经 子弹区域→gameworld 转换取轴对齐包围盒。
     *
     * 热路径实现（P4，agentsDoc/as2-performance.md）：
     * • 子弹仿射复用渲染矩阵缓存（group.ma/mb/mc2/md，渲染组维护；
     *   tick 中组更新先于本调用执行，processQueue 晚于 tick——同帧必为新值，零三角函数）
     * • 子弹区域→gameworld 用帧缓存仿射（refreshChainZoneAffine），与子弹矩阵一次复合后
     *   4 角纯算术展开——每弹每帧零 native 调用、零分配
     *
     * @param bullet 对象化联弹（携带 chainGroup 组引用，坐标字段与 MC 同名）
     */
    public function updateFromChainObject(bullet:Object):Void {
        var g:ChainGroup = bullet.chainGroup;   // 类型化引用：组字段拼写编译期校验

        var frame:Number = _root.帧计时器.当前帧数;
        if (AABBCollider.zoneFrame != frame) AABBCollider.refreshChainZoneAffine(frame);
        var za:Number = AABBCollider.zoneA;
        var zb:Number = AABBCollider.zoneB;
        var zc:Number = AABBCollider.zoneC;
        var zd:Number = AABBCollider.zoneD;

        var ma:Number = g.ma;
        var mb:Number = g.mb;
        var mc2:Number = g.mc2;
        var md:Number = g.md;
        var bx:Number = bullet._x;
        var by:Number = bullet._y;

        // 复合矩阵 C = Zone ∘ Bullet（6 乘 4 加），4 角展开复用乘积
        var ca:Number = za * ma + zc * mb;
        var cc:Number = za * mc2 + zc * md;
        var cb:Number = zb * ma + zd * mb;
        var cd:Number = zb * mc2 + zd * md;
        var ctx:Number = za * bx + zc * by + AABBCollider.zoneTx;
        var cty:Number = zb * bx + zd * by + AABBCollider.zoneTy;

        var x0:Number = g.盒x;
        var x1:Number = x0 + g.盒宽;
        var y0:Number = g.盒y;
        var y1:Number = y0 + g.盒高;

        var ax0:Number = ca * x0;
        var ax1:Number = ca * x1;
        var cy0:Number = cc * y0;
        var cy1:Number = cc * y1;
        var bx0:Number = cb * x0;
        var bx1:Number = cb * x1;
        var dy0:Number = cd * y0;
        var dy1:Number = cd * y1;

        var px:Number = ax0 + cy0 + ctx;
        var pyv:Number = bx0 + dy0 + cty;
        var minX:Number = px;
        var maxX:Number = px;
        var minY:Number = pyv;
        var maxY:Number = pyv;

        px = ax1 + cy0 + ctx;
        if (px < minX) minX = px; else if (px > maxX) maxX = px;
        pyv = bx1 + dy0 + cty;
        if (pyv < minY) minY = pyv; else if (pyv > maxY) maxY = pyv;

        px = ax1 + cy1 + ctx;
        if (px < minX) minX = px; else if (px > maxX) maxX = px;
        pyv = bx1 + dy1 + cty;
        if (pyv < minY) minY = pyv; else if (pyv > maxY) maxY = pyv;

        px = ax0 + cy1 + ctx;
        if (px < minX) minX = px; else if (px > maxX) maxX = px;
        pyv = bx0 + dy1 + cty;
        if (pyv < minY) minY = pyv; else if (pyv > maxY) maxY = pyv;

        this.left = minX;
        this.right = maxX;
        this.top = minY;
        this.bottom = maxY;
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
