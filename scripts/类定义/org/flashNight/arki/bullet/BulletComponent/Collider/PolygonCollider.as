import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider implements ICollider {
    private var _factory:AbstractColliderFactory;
    private var _polygon:Array; // 存储多边形点集 [{x:Number, y:Number}, ...]
    private var _sourceMovieClip:MovieClip; // 用于调试或缓存引用
    
    public function PolygonCollider() {
        this._polygon = [];
    }

    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }

    /**
     * 核心碰撞检测逻辑
     * 
     * 从对方 ICollider 获取对方的点集数据，并与自身的多边形进行点集碰撞检测。
     * 若发生碰撞，计算交集多边形的面积与中心点，并作为 CollisionResult 返回。
     *
     * @param other 另一个 ICollider 实例（可能是 PolygonCollider 或其他类型）
     * @param zOffset Z轴偏移，用于调整对方点集高度
     * @return CollisionResult 实例
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        // 获取对方的 AABB 来判断是否需要进一步处理（按设计说明可不做，但接口需要兼容性）
        // 在现有业务中，AABB预筛选已由上层逻辑处理，因此这里直接进行点集碰撞计算。

        // 获取对方的点集数据
        var otherPolygon:Array = this.getOtherPolygonPoints(other, zOffset);
        if (!otherPolygon || otherPolygon.length < 3) {
            return CollisionResult.FALSE; // 无有效点集
        }

        // 如果自身或对方点集无效
        if (this._polygon.length < 3) {
            return CollisionResult.FALSE;
        }

        // 调用业务逻辑中的点集碰撞检测方法（与原有代码兼容）
        // 击中点集 = _root.点集碰撞检测(selfPolygon, otherPolygon, selfEdges, zOffset)
        
        var intersection:Array = _root.点集碰撞检测(this._polygon, otherPolygon, [], 0);
        if (!intersection || intersection.length < 3) {
            return CollisionResult.FALSE; // 没有有效的交集多边形
        }

        // 计算自身多边形与交集多边形的面积
        var selfArea:Number = _root.点集面积系数(this._polygon);
        var interArea:Number = _root.点集面积系数(intersection);
        if (selfArea <= 0 || interArea <= 0) {
            return CollisionResult.FALSE;
        }

        var overlapRatio:Number = interArea / selfArea;

        // 计算交集多边形的中心点（碰撞中心）
        var overlapCenter:Vector = this.calculatePolygonCenter(intersection);

        var result:CollisionResult = new CollisionResult(true);
        result.setOverlapRatio(overlapRatio);
        result.setOverlapCenter(overlapCenter);
        return result;
    }

    /**
     * 获取指定 ICollider 的点集数据。
     * 
     * 考虑到当前业务代码中对方碰撞器可能是 AABBCollider 或 PolygonCollider，
     * 这里采用"兼容性"做法：
     * - 如果对方是 PolygonCollider，则直接获取其点集数据。
     * - 如果不是，则假设对方提供的是一个 unit 或 bullet，对方有 area MovieClip 属性，
     *   我们使用 _root.影片剪辑至游戏世界点集(otherMovieClip.area) 来获取点集。
     *
     * @param other 另一个 ICollider 实例
     * @param zOffset Z轴偏移
     * @return 对方的多边形点集（Array）
     */
    private function getOtherPolygonPoints(other:ICollider, zOffset:Number):Array {
        // 判断是否为 PolygonCollider
        if (other instanceof PolygonCollider) {
            var polyOther:PolygonCollider = PolygonCollider(other);
            // 将对方点集进行 zOffset 偏移（这里简单处理：y坐标加 zOffset）
            var adjusted:Array = [];
            var oppPoints:Array = polyOther._polygon;
            for (var i:Number=0; i<oppPoints.length; i++) {
                adjusted.push({x:oppPoints[i].x, y:oppPoints[i].y + zOffset});
            }
            return adjusted;
        }

        // 如果不是 PolygonCollider，按照原有业务逻辑，对方可能是一个单位 area 或 bullet area 的 MovieClip
        // 通常可以在实现中加入对 other 的工厂引用或者强制类型转换，以获取对方的实例引用。
        // 此处由于为渐进式平替，不考虑过多架构变动。
        // 假设 other 有一个 getSourceClip() 方法或从工厂中可得到 original clip。
        // 若没有，我们需要扩展接口或拿到目标对象的 area MovieClip。
        
        // 简单处理：尝试获取对方的原始对象引用（需要业务层支持）
        var otherSource:MovieClip = this.tryGetOtherSourceMovieClip(other);
        if (!otherSource || !otherSource.area) {
            // 无法获取对方多边形点集
            return null;
        }
        
        // 调用业务中的点集转换方法，将影片剪辑area转换为世界坐标点集
        var otherPolygon:Array = _root.影片剪辑至游戏世界点集(otherSource.area);
        // 应用zOffset偏移到y坐标上
        for (var j:Number=0; j<otherPolygon.length; j++) {
            otherPolygon[j].y += zOffset;
        }
        return otherPolygon;
    }

    /**
     * 尝试获取 other 的源 MovieClip。
     * 在当前阶段，我们尽可能从 factory 或其他途径获取。
     * 实际业务中可能需要对框架进行调整。
     */
    private function tryGetOtherSourceMovieClip(other:ICollider):MovieClip {
        var fac:AbstractColliderFactory = other.getFactory();
        // 假定 factory 中有一个方法可以获取对应的 MovieClip 引用
        // 如果没有，需要根据实际业务情况修改该方法或在初始化时注入引用
        if (fac && fac.sourceClip) {
            return fac.sourceClip;
        }
        return null;
    }


    /**
     * 计算多边形的中心点（几何质心）
     * 通常通过多边形顶点坐标的平均值近似获取，
     * 或采用多边形质心公式（基于顶点坐标的加权平均）。
     * 简易实现先使用平均值法。
     *
     * @param polygon 多边形点集
     * @return Vector 中心点
     */
    private function calculatePolygonCenter(polygon:Array):Vector {
        var sumX:Number = 0;
        var sumY:Number = 0;
        var count:Number = polygon.length;
        for (var i:Number=0; i<count; i++) {
            sumX += polygon[i].x;
            sumY += polygon[i].y;
        }
        return new Vector(sumX / count, sumY / count);
    }


    /**
     * 返回当前多边形碰撞器的 AABB。
     * 尽管业务已在上层有 AABB 筛选，这里仍实现该方法。
     *
     * @param zOffset Z轴偏移，用于计算 AABB
     * @return AABB 实例
     */
    public function getAABB(zOffset:Number):AABB {
        if (!this._polygon || this._polygon.length < 1) {
            return new AABB(0,0,0,0);
        }

        var minX:Number = Number.MAX_VALUE;
        var maxX:Number = -Number.MAX_VALUE;
        var minY:Number = Number.MAX_VALUE;
        var maxY:Number = -Number.MAX_VALUE;

        for (var i:Number=0; i<this._polygon.length; i++) {
            var px:Number = this._polygon[i].x;
            var py:Number = this._polygon[i].y + zOffset; // 将zOffset加到y轴
            if (px < minX) minX = px;
            if (px > maxX) maxX = px;
            if (py < minY) minY = py;
            if (py > maxY) maxY = py;
        }
        return new AABB(minX, maxX, minY, maxY);
    }


    /**
     * 基于透明子弹更新 PolygonCollider 的多边形信息。
     * 由于透明子弹目前硬编码成 25x25 的正方形区域，可以直接构建一个矩形点集。
     *
     * @param bullet 透明子弹对象
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        var bx:Number = bullet._x;
        var by:Number = bullet._y;
        var half:Number = 12.5;
        // 构建矩形点集（按照顺时针或逆时针顺序）
        this._polygon = [
            {x: bx - half, y: by - half},
            {x: bx + half, y: by - half},
            {x: bx + half, y: by + half},
            {x: bx - half, y: by + half}
        ];
    }

    /**
     * 基于子弹和检测区域更新 PolygonCollider 的多边形信息。
     * 利用 _root.影片剪辑至游戏世界点集(detectionArea) 获取点集。
     *
     * @param bullet 子弹 MovieClip 实例
     * @param detectionArea 子弹的检测区域 MovieClip 实例
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        this._sourceMovieClip = bullet;
        // 直接使用业务函数获取多边形点集
        var polygon:Array = _root.影片剪辑至游戏世界点集(detectionArea);
        this._polygon = polygon;
    }

    /**
     * 基于单位区域更新 PolygonCollider 的多边形信息。
     * 与子弹类似，直接使用 _root.影片剪辑至游戏世界点集(unit.area) 获取点集。
     *
     * @param unit 包含 area 属性的单位 MovieClip 实例
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        this._sourceMovieClip = unit;
        var polygon:Array = _root.影片剪辑至游戏世界点集(unit.area);
        this._polygon = polygon;
    }

}
