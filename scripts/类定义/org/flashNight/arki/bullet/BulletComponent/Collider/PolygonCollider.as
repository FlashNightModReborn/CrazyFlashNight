import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider extends RectanglePointSet implements ICollider {
    public var _factory:AbstractColliderFactory;
    public var _update:Function;
    public var _currentFrame:Number;

    /**
     * 构造函数
     * 如果传入为null，则自动创建4个(0,0)点保证数据结构完整。
     */
    public function PolygonCollider(p1:Vector, p2:Vector, p3:Vector, p4:Vector) {
        super(p1 ? p1 : new Vector(0, 0), p2 ? p2 : new Vector(0, 0), p3 ? p3 : new Vector(0, 0), p4 ? p4 : new Vector(0, 0));
    }

    public function PolygonCollider_empty() {
        super(new Vector(0, 0), new Vector(0, 0), new Vector(0, 0), new Vector(0, 0));
    }

    private function pointToGameworld(x:Number, y:Number, loc:MovieClip):Vector {
        var pt:Object = {x: x, y: y};
        loc.localToGlobal(pt);
        _root.gameworld.globalToLocal(pt);
        return new Vector(pt.x, pt.y);
    }

    private function isInsideAABB(px:Number, py:Number, aabb:AABB):Boolean {
        return (px >= aabb.left && px <= aabb.right && py >= aabb.top && py <= aabb.bottom);
    }

    private function lineIntersect(ax:Number, ay:Number, bx:Number, by:Number, cx:Number, cy:Number, dx:Number, dy:Number):Object {
        var denom:Number = (dy - cy) * (bx - ax) - (dx - cx) * (by - ay);
        if (denom == 0)
            return null; // 平行或重合

        var ua:Number = ((dx - cx) * (ay - cy) - (dy - cy) * (ax - cx)) / denom;
        var ub:Number = ((bx - ax) * (ay - cy) - (by - ay) * (ax - cx)) / denom;

        if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
            return {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
        }
        return null;
    }

    private function intersectRectangleWithAABB(aabb:AABB):Array {
        var intersectionPoints:Array = [];

        // 收集在AABB内部的点 (p1, p2, p3, p4)
        if (isInsideAABB(p1.x, p1.y, aabb))
            intersectionPoints.push({x: p1.x, y: p1.y});
        if (isInsideAABB(p2.x, p2.y, aabb))
            intersectionPoints.push({x: p2.x, y: p2.y});
        if (isInsideAABB(p3.x, p3.y, aabb))
            intersectionPoints.push({x: p3.x, y: p3.y});
        if (isInsideAABB(p4.x, p4.y, aabb))
            intersectionPoints.push({x: p4.x, y: p4.y});

        // AABB的4条边为：
        // 左边：  x=aabb.left    (y: top->bottom)
        // 右边：  x=aabb.right
        // 上边：  y=aabb.top     (x: left->right)
        // 下边：  y=aabb.bottom

        // 矩形4条边：p1->p2, p2->p3, p3->p4, p4->p1
        // 为减少循环和数组，直接手写8次检查（4条矩形边×4条AABB边）

        // 定义矩形四边
        var ax:Number, ay:Number, bx:Number, by:Number;

        // p1->p2
        ax = p1.x;
        ay = p1.y;
        bx = p2.x;
        by = p2.y;
        // 与左边相交
        var inter:Object = lineIntersect(ax, ay, bx, by, aabb.left, aabb.top, aabb.left, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        // 与右边相交
        inter = lineIntersect(ax, ay, bx, by, aabb.right, aabb.top, aabb.right, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        // 与上边相交
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.top, aabb.right, aabb.top);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        // 与下边相交
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.bottom, aabb.right, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);

        // p2->p3
        ax = p2.x;
        ay = p2.y;
        bx = p3.x;
        by = p3.y;
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.top, aabb.left, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.right, aabb.top, aabb.right, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.top, aabb.right, aabb.top);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.bottom, aabb.right, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);

        // p3->p4
        ax = p3.x;
        ay = p3.y;
        bx = p4.x;
        by = p4.y;
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.top, aabb.left, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.right, aabb.top, aabb.right, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.top, aabb.right, aabb.top);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.bottom, aabb.right, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);

        // p4->p1
        ax = p4.x;
        ay = p4.y;
        bx = p1.x;
        by = p1.y;
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.top, aabb.left, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.right, aabb.top, aabb.right, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.top, aabb.right, aabb.top);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);
        inter = lineIntersect(ax, ay, bx, by, aabb.left, aabb.bottom, aabb.right, aabb.bottom);
        if (inter && isInsideAABB(inter.x, inter.y, aabb))
            intersectionPoints.push(inter);

        if (intersectionPoints.length < 3)
            return intersectionPoints;

        // 去重
        var uniqueMap:Object = {};
        var uniquePoints:Array = [];
        var eps:Number = 0.00001;
        for (var u:Number = 0; u < intersectionPoints.length; u++) {
            var px:Number = intersectionPoints[u].x;
            var py:Number = intersectionPoints[u].y;
            var key:String = Math.round(px / eps) * eps + "_" + Math.round(py / eps) * eps;
            if (!uniqueMap[key]) {
                uniqueMap[key] = true;
                uniquePoints.push(intersectionPoints[u]);
            }
        }

        if (uniquePoints.length < 3)
            return uniquePoints;

        // 按质心排序点集
        var cx:Number = 0, cy:Number = 0;
        var lenu:Number = uniquePoints.length;
        for (var m:Number = 0; m < lenu; m++) {
            cx += uniquePoints[m].x;
            cy += uniquePoints[m].y;
        }
        cx /= lenu;
        cy /= lenu;

        uniquePoints.sort(function(a:Object, b:Object):Number {
            var angleA:Number = Math.atan2(a.y - cy, a.x - cx);
            var angleB:Number = Math.atan2(b.y - cy, b.x - cx);
            return angleA - angleB;
        });

        return uniquePoints;
    }

    public function getAABB(zOffset:Number):AABB {
        var box:AABB = super.getBoundingBox();
        return new AABB(box.left, box.right, box.top + zOffset, box.bottom + zOffset);
    }

    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        // AABB快速剔除
        var box:AABB = this.getBoundingBox();
        if (box.right <= otherAABB.left || box.left >= otherAABB.right || box.bottom <= otherAABB.top || box.top >= otherAABB.bottom) {
            return CollisionResult.FALSE;
        }

        var intersection:Array = intersectRectangleWithAABB(otherAABB);
        if (!intersection || intersection.length < 3) {
            return CollisionResult.FALSE;
        }

        var intersectionArea:Number = this.calcArea(intersection);
        var thisArea:Number = this.calcRectangleArea();
        var overlapRatio:Number = intersectionArea / thisArea;

        // 计算质心
        var cx:Number = 0, cy:Number = 0;
        var leni:Number = intersection.length;
        for (var i:Number = 0; i < leni; i++) {
            cx += intersection[i].x;
            cy += intersection[i].y;
        }
        cx /= leni;
        cy /= leni;
        var overlapCenter:Vector = new Vector(cx, cy);

        var result:CollisionResult = new CollisionResult(true);
        result.setOverlapRatio(overlapRatio);
        result.setOverlapCenter(overlapCenter);
        return result;
    }

    // 计算任意点集的多边形面积
    private function calcArea(points:Array):Number {
        var len:Number = points.length;
        if (len < 3)
            return 0;
        var area:Number = 0;
        var ii:Number = len - 1;
        for (var i:Number = 0; i < len; ii = i++) {
            area += points[ii].x * points[i].y - points[i].x * points[ii].y;
        }
        return Math.abs(area);
    }

    // 计算矩形自身4点面积：直接使用p1,p2,p3,p4
    private function calcRectangleArea():Number {
        // 抽屉公式
        var area:Number = (p1.x * p2.y + p2.x * p3.y + p3.x * p4.y + p4.x * p1.y) - (p2.x * p1.y + p3.x * p2.y + p4.x * p3.y + p1.x * p4.y);
        return (area < 0) ? -area : area;
    }

    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }

    // 更新为透明子弹，直接修改p1,p2,p3,p4的x,y
    public function updateFromTransparentBullet(bullet:Object):Void {
        var halfSize:Number = 12.5;
        p1.x = bullet._x - halfSize;
        p1.y = bullet._y - halfSize;
        p2.x = bullet._x + halfSize;
        p2.y = bullet._y - halfSize;
        p3.x = bullet._x + halfSize;
        p3.y = bullet._y + halfSize;
        p4.x = bullet._x - halfSize;
        p4.y = bullet._y + halfSize;
    }

    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var rect:Object = detectionArea.getRect(detectionArea);

        var p1gw:Vector = pointToGameworld(rect.xMax, rect.yMax, detectionArea);
        var p3gw:Vector = pointToGameworld(rect.xMin, rect.yMin, detectionArea);

        var centerX:Number = (p1gw.x + p3gw.x) * 0.5;
        var centerY:Number = (p1gw.y + p3gw.y) * 0.5;
        var vx:Number = p1gw.x - centerX;
        var vy:Number = p1gw.y - centerY;
        var angle:Number = Math.atan2(vy, vx);
        var length:Number = Math.sqrt(vx * vx + vy * vy);
        var cosVal:Number = length * Math.cos(angle);
        var sinVal:Number = length * Math.sin(angle);

        // p0, p1, p2, p3 对应之前的推断
        // p0 = centerX - cosVal, centerY + sinVal
        // p2 = centerX + cosVal, centerY - sinVal
        // p1 = p1gw, p3 = p3gw

        p1.x = p1gw.x;
        p1.y = p1gw.y;
        p3.x = p3gw.x;
        p3.y = p3gw.y;
        p2.x = centerX + cosVal;
        p2.y = centerY - sinVal;
        p4.x = centerX - cosVal;
        p4.y = centerY + sinVal;
    }

    public function updateFromUnitArea(unit:MovieClip):Void {
        var frame = _root.帧计时器.当前帧数;
        if (this._currentFrame == frame)
            return;
        this._currentFrame = frame;
        var unitRect:Object = unit.area.getRect(_root.gameworld);

        p1.x = unitRect.xMin;
        p1.y = unitRect.yMin;
        p2.x = unitRect.xMax;
        p2.y = unitRect.yMin;
        p3.x = unitRect.xMax;
        p3.y = unitRect.yMax;
        p4.x = unitRect.xMin;
        p4.y = unitRect.yMax;
    }
}
