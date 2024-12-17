import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;
import org.flashNight.naki.Sort.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider extends PointSet implements ICollider {
    private var _factory:AbstractColliderFactory;

    /**
     * 构造函数
     * 初始化为空点集，后续通过 updateFrom... 方法填充点数据
     */
    public function PolygonCollider() {
        super();
    }

    /**
     * 检查与另一个碰撞器的碰撞
     * 在本设计中，我们只关心 PolygonCollider 与对方 AABB 的碰撞检测。
     * 逻辑：
     * 1. 获取对方的 AABB。
     * 2. 将 AABB 转换为点集（一个矩形多边形的4个顶点）。
     * 3. 调用 _root.点集碰撞检测 来获取交集多边形。
     * 4. 如果交集多边形点数>=3，表示碰撞发生。
     *    - 计算交集面积与自身面积的比例作为 overlapRatio
     *    - 计算交集多边形的质心作为 overlapCenter
     * 5. 返回 CollisionResult。
     * 
     * @param other 另一个 ICollider
     * @param zOffset Z轴偏移，用于模拟3D高度差
     * @return CollisionResult
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        // 获取对方的 AABB
        var otherAABB:AABB = other.getAABB(zOffset);

        // 将 AABB 转为多边形（矩形点集）
        var boxPoints:Array = [
            {x: otherAABB.left,  y: otherAABB.top},
            {x: otherAABB.right, y: otherAABB.top},
            {x: otherAABB.right, y: otherAABB.bottom},
            {x: otherAABB.left,  y: otherAABB.bottom}
        ];

        // 获取当前多边形点集
        var thisPoints:Array = this.toArray();

        // 调用点集碰撞检测函数：_root.点集碰撞检测(多边形A点集, 多边形B点集, 边向量, Z轴差)
        // 此处边向量数组可传空数组，因为内部计算可能不依赖此值。
        var intersection:Array = _root.点集碰撞检测(thisPoints, boxPoints, [], zOffset);
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
