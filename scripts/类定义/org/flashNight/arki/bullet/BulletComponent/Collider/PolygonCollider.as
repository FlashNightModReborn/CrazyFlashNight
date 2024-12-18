import org.flashNight.sara.util.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider extends RectanglePointSet implements ICollider {
    public var _factory:AbstractColliderFactory;
    public var _update:Function;
    public var _currentFrame:Number;

    public function PolygonCollider(p1:Vector, p2:Vector, p3:Vector, p4:Vector) {
        super(p1, p2, p3, p4);
    }

    public function PolygonCollider_empty() {
        super(null, null, null, null);
    }

    // 将局部坐标点转换到gameworld坐标
    private function pointToGameworld(x:Number, y:Number, loc:MovieClip):Vector {
        var pt:Object = {x:x, y:y};
        loc.localToGlobal(pt);
        _root.gameworld.globalToLocal(pt);
        return new Vector(pt.x, pt.y);
    }

    private function isInsideAABB(px:Number, py:Number, aabb:AABB):Boolean {
        return (px >= aabb.left && px <= aabb.right && py >= aabb.top && py <= aabb.bottom);
    }

    private function lineIntersect(p1x:Number, p1y:Number, p2x:Number, p2y:Number,
                                   p3x:Number, p3y:Number, p4x:Number, p4y:Number):Object {
        var denom:Number = (p4y - p3y)*(p2x - p1x) - (p4x - p3x)*(p2y - p1y);
        if (denom == 0) return null; // 平行或重合

        var ua:Number = ((p4x - p3x)*(p1y - p3y) - (p4y - p3y)*(p1x - p3x)) / denom;
        var ub:Number = ((p2x - p1x)*(p1y - p3y) - (p2y - p1y)*(p1x - p3x)) / denom;

        if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
            return {x:p1x + ua*(p2x - p1x), y:p1y + ua*(p2y - p1y)};
        }
        return null;
    }

    private function intersectRectangleWithAABB(aabb:AABB):Array {
        // 矩形4点
        var p0x:Number = p1.x, p0y:Number = p1.y;
        var p1x:Number = p2.x, p1y:Number = p2.y;
        var p2x:Number = p3.x, p2y:Number = p3.y;
        var p3x:Number = p4.x, p3y:Number = p4.y;

        var intersectionPoints:Array = [];

        // 检查矩形4点是否在AABB内
        if (isInsideAABB(p0x,p0y,aabb)) intersectionPoints.push({x:p0x,y:p0y});
        if (isInsideAABB(p1x,p1y,aabb)) intersectionPoints.push({x:p1x,y:p1y});
        if (isInsideAABB(p2x,p2y,aabb)) intersectionPoints.push({x:p2x,y:p2y});
        if (isInsideAABB(p3x,p3y,aabb)) intersectionPoints.push({x:p3x,y:p3y});

        // AABB四条边
        var aabbEdges:Array = [
            [aabb.left, aabb.top, aabb.left, aabb.bottom],    // left
            [aabb.right,aabb.top,aabb.right,aabb.bottom],     // right
            [aabb.left,aabb.top,aabb.right,aabb.top],         // top
            [aabb.left,aabb.bottom,aabb.right,aabb.bottom]    // bottom
        ];

        // 矩形4条边，与AABB边相交
        // 矩形边: (p1->p2), (p2->p3), (p3->p4), (p4->p1)
        var rectEdges:Array = [
            [p1.x,p1.y,p2.x,p2.y],
            [p2.x,p2.y,p3.x,p3.y],
            [p3.x,p3.y,p4.x,p4.y],
            [p4.x,p4.y,p1.x,p1.y]
        ];

        for (var j:Number=0; j<4; j++) {
            var re = rectEdges[j];
            for (var k:Number=0; k<4; k++) {
                var ae = aabbEdges[k];
                var inter:Object = lineIntersect(re[0], re[1], re[2], re[3], ae[0], ae[1], ae[2], ae[3]);
                if (inter && isInsideAABB(inter.x, inter.y, aabb)) {
                    intersectionPoints.push(inter);
                }
            }
        }

        if (intersectionPoints.length < 3) return intersectionPoints;

        // 去重
        var uniqueMap:Object = {};
        var uniquePoints:Array = [];
        var eps:Number = 0.00001;
        for (var u:Number=0; u<intersectionPoints.length; u++) {
            var px:Number = intersectionPoints[u].x;
            var py:Number = intersectionPoints[u].y;
            var key:String = Math.round(px/eps)*eps + "_" + Math.round(py/eps)*eps;
            if (!uniqueMap[key]) {
                uniqueMap[key] = true;
                uniquePoints.push(intersectionPoints[u]);
            }
        }

        if (uniquePoints.length < 3) return uniquePoints;

        // 按质心排序点集
        var cx:Number=0, cy:Number=0;
        for (var m:Number=0; m<uniquePoints.length; m++) {
            cx += uniquePoints[m].x;
            cy += uniquePoints[m].y;
        }
        cx /= uniquePoints.length;
        cy /= uniquePoints.length;

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
        var box:AABB = this.getAABB(0);
        if (box.right <= otherAABB.left || box.left >= otherAABB.right ||
            box.bottom <= otherAABB.top || box.top >= otherAABB.bottom) {
            return CollisionResult.FALSE;
        }

        // 求相交多边形
        var intersection:Array = intersectRectangleWithAABB(otherAABB);
        if (!intersection || intersection.length < 3) {
            return CollisionResult.FALSE;
        }

        // 计算相交区域面积
        var intersectionArea:Number = calcArea(intersection);

        // 计算自身矩形面积 (直接用p1,p2,p3,p4)
        var thisArea:Number = calcRectangleArea();

        var overlapRatio:Number = intersectionArea / thisArea;

        // 计算质心
        var cx:Number=0, cy:Number=0;
        for (var i:Number=0; i<intersection.length; i++) {
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

    // 计算任意点集多边形面积（保持不变）
    private function calcArea(points:Array):Number {
        var len:Number = points.length;
        if (len < 3) return 0;
        var area:Number = 0;
        for (var i:Number=0, ii:Number=len-1; i<len; ii=i++) {
            area += points[ii].x*points[i].y - points[i].x*points[ii].y;
        }
        return Math.abs(area);
    }

    // 直接用p1,p2,p3,p4计算自身面积
    private function calcRectangleArea():Number {
        // 四边形面积公式：利用抽屉公式
        // 面积 = |(x1*y2 + x2*y3 + x3*y4 + x4*y1 - (y1*x2 + y2*x3 + y3*x4 + y4*x1))| / 2
        // 这里调用calcArea那套逻辑时需要按顺序传入点
        var x1:Number=p1.x,y1:Number=p1.y;
        var x2:Number=p2.x,y2:Number=p2.y;
        var x3:Number=p3.x,y3:Number=p3.y;
        var x4:Number=p4.x,y4:Number=p4.y;
        
        // 使用抽屉算法直接计算
        var rawArea:Number = (x1*y2 + x2*y3 + x3*y4 + x4*y1 - (y1*x2 + y2*x3 + y3*x4 + y4*x1));
        return Math.abs(rawArea)/1; // 原先抽屉算法需要除2，但这里点集为4个闭合顶点时请注意:
        // 实际上上面calcArea也是同样的公式，但不除2是因为calcArea中使用了完整循环，会自动等效抽屉算法结果的一半。
        // 我们可以借鉴calcArea的逻辑以保持一致性:
        // 使用与calcArea相同的方式：
        // var arr:Array=[{x:x1,y:y1},{x:x2,y:y2},{x:x3,y:y3},{x:x4,y:y4}];
        // return calcArea(arr);
        // 为了确保一致性和不引入新问题，直接复用calcArea:
        var arr:Array = [{x:x1,y:y1},{x:x2,y:y2},{x:x3,y:y3},{x:x4,y:y4}];
        return calcArea(arr);
    }

    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }

    public function updateFromTransparentBullet(bullet:Object):Void {
        var halfSize:Number = 12.5;
        p1 = new Vector(bullet._x - halfSize, bullet._y - halfSize);
        p2 = new Vector(bullet._x + halfSize, bullet._y - halfSize);
        p3 = new Vector(bullet._x + halfSize, bullet._y + halfSize);
        p4 = new Vector(bullet._x - halfSize, bullet._y + halfSize);
    }

    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var rect:Object = detectionArea.getRect(detectionArea);

        var P1:Vector = pointToGameworld(rect.xMax, rect.yMax, detectionArea);
        var P3:Vector = pointToGameworld(rect.xMin, rect.yMin, detectionArea);

        var centerX:Number = (P1.x + P3.x)*0.5;
        var centerY:Number = (P1.y + P3.y)*0.5;
        var vx:Number = P1.x - centerX;
        var vy:Number = P1.y - centerY;
        var angle:Number = Math.atan2(vy, vx);
        var length:Number = Math.sqrt(vx*vx + vy*vy);
        var cosVal:Number = length * Math.cos(angle);
        var sinVal:Number = length * Math.sin(angle);

        var P0:Vector = new Vector(centerX - cosVal, centerY + sinVal);
        var P2:Vector = new Vector(centerX + cosVal, centerY - sinVal);

        p1 = P0;
        p2 = P1;
        p3 = P2;
        p4 = P3;
    }

    public function updateFromUnitArea(unit:MovieClip):Void {
        var frame = _root.帧计时器.当前帧数;
        if (this._currentFrame == frame) return;
        this._currentFrame = frame;
        var unitRect:Object = unit.area.getRect(_root.gameworld);

        p1 = new Vector(unitRect.xMin, unitRect.yMin);
        p2 = new Vector(unitRect.xMax, unitRect.yMin);
        p3 = new Vector(unitRect.xMax, unitRect.yMax);
        p4 = new Vector(unitRect.xMin, unitRect.yMax);
    }
}
