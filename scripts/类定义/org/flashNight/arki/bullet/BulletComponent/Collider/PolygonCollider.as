import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.sara.util.*;

/**
 * PolygonCollider 类
 * 
 * 基于多边形（点集）的碰撞检测器，通过实现 ICollider 接口，提供更精确的碰撞检测能力。
 * 
 * 多边形数据以世界坐标点集（Vector列表）表示。碰撞检测时，可使用全局函数进行多边形相交运算。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider implements ICollider {

    private var _factory:AbstractColliderFactory;
    private var _points:Array; // 包含 Vector 对象的数组，表示多边形的顶点集
    private var _boundingAABB:AABB; // 用于快速剔除的 AABB 边界
    
    /**
     * 构造函数
     */
    public function PolygonCollider() {
        _points = [];
    }

    /**
     * ICollider 接口实现：检查与另一个碰撞器是否发生碰撞
     * 
     * 流程：
     * 1. 获取对方的 AABB 边界（无论对方是 AABB 还是多边形，都可以先获取其包围盒）。
     * 2. 如果 AABB 不相交则提前返回 False。
     * 3. 如果对方是 AABBCollider，则进行多边形与 AABB 的相交检测。
     * 4. 如果对方是 PolygonCollider，则进行多边形与多边形的相交检测。
     * 
     * @param other 另一个 ICollider 实例
     * @param zOffset 用于 3D 高度模拟的 Z 轴偏移
     * @return 碰撞结果 CollisionResult
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);
        
        // AABB 快速剔除
        if (!_boundingAABB) {
            this.computeBoundingAABB();
        }
        var selfAABB:AABB = this.getAABB(zOffset);

        // AABB 不相交，提前退出
        if (selfAABB.right <= otherAABB.left)  return CollisionResult.FALSE;
        if (selfAABB.left >= otherAABB.right)  return CollisionResult.FALSE;
        if (selfAABB.bottom <= otherAABB.top)  return CollisionResult.FALSE;
        if (selfAABB.top >= otherAABB.bottom)  return CollisionResult.FALSE;

        // 如果对方是 AABBCollider，则多边形对矩形的检测
        // 简化处理：将 AABB 转化为点集，再进行点集相交
        // 实际可调用全局函数 _root.点集碰撞检测(this._points, otherAABB对应点集)
        if (other instanceof AABBCollider) {
            var rectPoints:Array = AABBToPoints(otherAABB);
            var intersection:Array = _root.点集碰撞检测(_points, rectPoints);
            if (intersection.length < 3) {
                return CollisionResult.FALSE;
            }
            // 计算覆盖率与中心
            var selfArea:Number = _root.点集面积系数(_points);
            var interArea:Number = _root.点集面积系数(intersection);
            var overlapRatio:Number = interArea / selfArea;
            var center:Vector = _root.点集质心(intersection);

            var result:CollisionResult = new CollisionResult(true);
            result.setOverlapCenter(center);
            result.setOverlapRatio(overlapRatio);
            return result;
        }

        // 如果对方也是 PolygonCollider
        if (other instanceof PolygonCollider) {
            var otherPoints:Array = PolygonCollider(other).getPoints();
            var intersection2:Array = _root.点集碰撞检测(_points, otherPoints);

            if (intersection2.length < 3) {
                return CollisionResult.FALSE;
            }

            // 计算覆盖率与中心
            var selfArea2:Number = _root.点集面积系数(_points);
            var interArea2:Number = _root.点集面积系数(intersection2);
            var overlapRatio2:Number = interArea2 / selfArea2;
            var center2:Vector = _root.点集质心(intersection2);

            var result2:CollisionResult = new CollisionResult(true);
            result2.setOverlapCenter(center2);
            result2.setOverlapRatio(overlapRatio2);
            return result2;
        }

        // 对于其他类型的碰撞器（如果有），可进一步扩展
        return CollisionResult.FALSE;
    }

    /**
     * ICollider 接口实现：获取 AABB 信息
     * 根据当前点集计算的 AABB 返回，并应用 Z 偏移
     * 
     * @param zOffset 用于3D高度模拟的 Z 轴偏移
     * @return AABB 实例
     */
    public function getAABB(zOffset:Number):AABB {
        if (!_boundingAABB) {
            this.computeBoundingAABB();
        }
        // 返回应用 zOffset 的副本
        return new AABB(_boundingAABB.left, _boundingAABB.right, _boundingAABB.top + zOffset, _boundingAABB.bottom + zOffset);
    }

    /**
     * ICollider 接口实现：更新边界信息，基于透明子弹对象
     * 
     * 假设透明子弹与 AABBCollider 一样大小，但这里我们可以在外部获取其点集，
     * 如若需要可使用固定点集（例如一个方形），作为透明子弹的多边形。
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        // 假设透明子弹是 25x25 的正方形中心点在 bullet._x, bullet._y
        var halfSize:Number = 12.5;
        _points = [
            new Vector(bullet._x - halfSize, bullet._y - halfSize),
            new Vector(bullet._x + halfSize, bullet._y - halfSize),
            new Vector(bullet._x + halfSize, bullet._y + halfSize),
            new Vector(bullet._x - halfSize, bullet._y + halfSize)
        ];
        computeBoundingAABB();
    }

    /**
     * ICollider 接口实现：更新边界信息，基于子弹和检测区域
     * 这里需要类似 AABBCollider 的逻辑，从 detectionArea 获取点集。
     * 假设有一个函数 `_root.影片剪辑至游戏世界点集(detectionArea)` 返回点集数据。
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        // 假设在上层已有将 MC 转换为点集的工具函数
        var globalPoints:Array = _root.影片剪辑至游戏世界点集(detectionArea);
        
        // globalPoints 已是世界坐标点集，无需再次转换
        // 如果需要根据 bullet 的 _x,_y 偏移，可以在此加上偏移量运算
        
        // 如需要偏移：
        // var dx:Number = bullet._x; 
        // var dy:Number = bullet._y;
        // for (var i:Number=0; i<globalPoints.length; i++) {
        //    var p:Vector = globalPoints[i];
        //    p.x += dx;
        //    p.y += dy;
        // }

        _points = globalPoints;
        computeBoundingAABB();
    }

    /**
     * ICollider 接口实现：更新边界信息，基于单位区域点集
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var globalPoints:Array = _root.影片剪辑至游戏世界点集(unit.area);
        _points = globalPoints;
        computeBoundingAABB();
    }

    /**
     * 设置工厂引用
     */
    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    /**
     * 获取工厂引用
     */
    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }

    // 辅助方法：计算多边形的 AABB，用于快速剔除
    private function computeBoundingAABB():Void {
        if (_points.length == 0) {
            _boundingAABB = new AABB(0,0,0,0);
            return;
        }
        var minX:Number = _points[0].x;
        var maxX:Number = _points[0].x;
        var minY:Number = _points[0].y;
        var maxY:Number = _points[0].y;
        for (var i:Number=1; i<_points.length; i++) {
            var px:Number = _points[i].x;
            var py:Number = _points[i].y;
            if (px < minX) minX = px;
            if (px > maxX) maxX = px;
            if (py < minY) minY = py;
            if (py > maxY) maxY = py;
        }
        _boundingAABB = new AABB(minX, maxX, minY, maxY);
    }

    // 将 AABB 转换为点集的辅助函数
    private function AABBToPoints(aabb:AABB):Array {
        return [
            new Vector(aabb.left, aabb.top),
            new Vector(aabb.right, aabb.top),
            new Vector(aabb.right, aabb.bottom),
            new Vector(aabb.left, aabb.bottom)
        ];
    }

    // 获取内部点集，用于碰撞检测
    public function getPoints():Array {
        return _points;
    }
}
