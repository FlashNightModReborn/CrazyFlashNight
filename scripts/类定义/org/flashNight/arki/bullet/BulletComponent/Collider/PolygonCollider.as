import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;
import org.flashNight.naki.Sort.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider extends PointSet implements ICollider {
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


    private var cachePolygon:Array;


    /**
     * 构造函数
     * 初始化为空点集，后续通过 updateFrom... 方法填充点数据
     */
    public function PolygonCollider() {
        super();
    }

    // 裁剪辅助函数，用Sutherland–Hodgman算法对多边形进行裁剪
    // clipFunc: (point:Object) => Boolean 判断点是否在剪裁区域内
    // intersectFunc: (p1:Object, p2:Object) => Object 计算线段与剪裁边的交点
    private function clipPolygon(polygon:Array, clipFunc:Function, intersectFunc:Function):Array {
        var output:Array = [];
        var len:Number = polygon.length;
        if (len < 2) return polygon;

        var a:Object = polygon[len - 1];
        for (var i:Number = 0; i < len; i++) {
            var b:Object = polygon[i];
            var aInside:Boolean = clipFunc(a);
            var bInside:Boolean = clipFunc(b);

            if (aInside && bInside) {
                // 两点都在内
                output.push(b);
            } else if (aInside && !bInside) {
                // a在内b在外，求交点
                var inter:Object = intersectFunc(a, b);
                if (inter) output.push(inter);
            } else if (!aInside && bInside) {
                // a在外b在内，求交点+加上b
                var inter2:Object = intersectFunc(a, b);
                if (inter2) output.push(inter2);
                output.push(b);
            }
            a = b;
        }
        return output;
    }

    // 针对AABB的特殊求交函数
    private function intersectPolygonWithAABB(polygon:Array, aabb:Object):Array {
        // 剪裁线定义与辅助函数
        // left剪裁: 保留x >= left的点
        var leftClip:Function = function(p:Object):Boolean { return p.x >= aabb.left; };
        var leftIntersect:Function = function(p1:Object, p2:Object):Object {
            var dx:Number = p2.x - p1.x;
            var dy:Number = p2.y - p1.y;
            if (dx == 0) return null;
            var t:Number = (aabb.left - p1.x) / dx;
            if (t >= 0 && t <= 1) {
                return {x:aabb.left, y:p1.y + t * dy};
            }
            return null;
        };

        // right剪裁: 保留x <= right
        var rightClip:Function = function(p:Object):Boolean { return p.x <= aabb.right; };
        var rightIntersect:Function = function(p1:Object, p2:Object):Object {
            var dx:Number = p2.x - p1.x;
            var dy:Number = p2.y - p1.y;
            if (dx == 0) return null;
            var t:Number = (aabb.right - p1.x) / dx;
            if (t >= 0 && t <= 1) {
                return {x:aabb.right, y:p1.y + t * dy};
            }
            return null;
        };

        // top剪裁: 保留y >= top
        var topClip:Function = function(p:Object):Boolean { return p.y >= aabb.top; };
        var topIntersect:Function = function(p1:Object, p2:Object):Object {
            var dx:Number = p2.x - p1.x;
            var dy:Number = p2.y - p1.y;
            if (dy == 0) return null;
            var t:Number = (aabb.top - p1.y) / dy;
            if (t >= 0 && t <= 1) {
                return {x:p1.x + t * dx, y:aabb.top};
            }
            return null;
        };

        // bottom剪裁: 保留y <= bottom
        var bottomClip:Function = function(p:Object):Boolean { return p.y <= aabb.bottom; };
        var bottomIntersect:Function = function(p1:Object, p2:Object):Object {
            var dx:Number = p2.x - p1.x;
            var dy:Number = p2.y - p1.y;
            if (dy == 0) return null;
            var t:Number = (aabb.bottom - p1.y) / dy;
            if (t >= 0 && t <= 1) {
                return {x:p1.x + t * dx, y:aabb.bottom};
            }
            return null;
        };

        // 对polygon依次进行4次裁剪
        var clipped:Array;
        clipped = clipPolygon(polygon, leftClip, leftIntersect);
        if (clipped.length < 3) return clipped;
        clipped = clipPolygon(clipped, rightClip, rightIntersect);
        if (clipped.length < 3) return clipped;
        clipped = clipPolygon(clipped, topClip, topIntersect);
        if (clipped.length < 3) return clipped;
        clipped = clipPolygon(clipped, bottomClip, bottomIntersect);
        return clipped;
    }

    // 在 checkCollision 中使用新的特化函数
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        // 获取对方的AABB
        var otherAABB:AABB = other.getAABB(zOffset);

        // 当前多边形点集
        var thisPoints:Array = this.toArray();

        // 使用特化的函数直接求 thisPoints 和 otherAABB 的交集
        var intersection:Array = intersectPolygonWithAABB(thisPoints, {
            left: otherAABB.left,
            right: otherAABB.right,
            top: otherAABB.top,
            bottom: otherAABB.bottom
        });

        if (!intersection || intersection.length < 3) {
            // 没有形成有效的交集多边形
            return CollisionResult.FALSE;
        }

        // 如果有交集多边形，计算面积与质心
        var intersectionArea:Number = _root.点集面积系数(intersection);
        var thisArea:Number = _root.点集面积系数(thisPoints);
        var overlapRatio:Number = intersectionArea / thisArea;

        // 计算交集多边形的质心
        var cx:Number = 0;
        var cy:Number = 0;
        for (var i:Number = 0; i < intersection.length; i++) {
            cx += intersection[i].x;
            cy += intersection[i].y;
        }
        cx /= intersection.length;
        cy /= intersection.length;
        var overlapCenter:Vector = new Vector(cx, cy);

        var result:CollisionResult = new CollisionResult(true);
        result.setOverlapRatio(overlapRatio);
        result.setOverlapCenter(overlapCenter);
        return result;
    }

    /**
     * 获取当前多边形的 AABB 边界框
     * 
     * @param zOffset Z轴偏移，用于模拟3D高度差
     * @return AABB
     */
    public function getAABB(zOffset:Number):AABB {
        var box:AABB = this.getBoundingBox(); // PointSet自带方法获取AABB
        // 将 zOffset 应用于 top/bottom
        return new AABB(box.left, box.right, box.top + zOffset, box.bottom + zOffset);
    }

    /**
     * 从透明子弹对象中更新多边形点集
     * 此处可与AABB类似，构造一个固定形状的多边形(例如25x25的正方形）
     * 
     * @param bullet 透明子弹对象
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        // 透明子弹为25x25正方形，以子弹坐标为中心
        var halfSize:Number = 12.5;
        this.fromArray([
            {x: bullet._x - halfSize, y: bullet._y - halfSize},
            {x: bullet._x + halfSize, y: bullet._y - halfSize},
            {x: bullet._x + halfSize, y: bullet._y + halfSize},
            {x: bullet._x - halfSize, y: bullet._y + halfSize}
        ]);
    }

    /**
     * 基于子弹和检测区域更新多边形点集
     * 使用 _root.影片剪辑至游戏世界点集(detectionArea) 获取检测区域的多边形点集
     * 
     * @param bullet 子弹MovieClip
     * @param detectionArea 子弹的检测区域MovieClip
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var areaPoints:Array = _root.影片剪辑至游戏世界点集(detectionArea);
        // 假设返回值为点的数组：[{x:Number, y:Number}, ...]
        this.fromArray(areaPoints);
    }

    /**
     * 基于单位区域更新多边形点集
     * 使用 unit.area.getRect(_root.gameworld) 获取单位的矩形区域
     * 然后转换为一个多边形（矩形）
     * 
     * @param unit 包含 area 属性的单位 MovieClip
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var frame = _root.帧计时器.当前帧数;
        if (this._currentFrame == frame) return;
        this._currentFrame = frame;
        var unitRect:Object = unit.area.getRect(_root.gameworld);
        this.fromArray([
            {x: unitRect.xMin, y: unitRect.yMin},
            {x: unitRect.xMax, y: unitRect.yMin},
            {x: unitRect.xMax, y: unitRect.yMax},
            {x: unitRect.xMin, y: unitRect.yMax}
        ]);
    }

    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }
}
