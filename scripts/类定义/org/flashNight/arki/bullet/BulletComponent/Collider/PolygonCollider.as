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

        // 内联展开 intersectRectangleWithAABB(otherAABB)
        var intersectionPoints:Array = [];

        // 收集在AABB内部的点 (p1, p2, p3, p4)
        var px:Number, py:Number;

        px = p1.x;
        py = p1.y;
        if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
            intersectionPoints.push({x: p1.x, y: p1.y});
        }

        px = p2.x;
        py = p2.y;
        if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
            intersectionPoints.push({x: p2.x, y: p2.y});
        }

        px = p3.x;
        py = p3.y;
        if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
            intersectionPoints.push({x: p3.x, y: p3.y});
        }

        px = p4.x;
        py = p4.y;
        if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
            intersectionPoints.push({x: p4.x, y: p4.y});
        }

        // 定义矩形四边
        var ax:Number, ay:Number, bx:Number, by:Number;
        var inter:Object;

        // 内联展开 lineIntersect 和 isInsideAABB
        // p1->p2
        ax = p1.x;
        ay = p1.y;
        bx = p2.x;
        by = p2.y;

        // 与左边相交 (AABB左边: x = otherAABB.left, y: top -> bottom)
        var denom:Number = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (otherAABB.left - otherAABB.left) * (by - ay);
        if (denom != 0) {
            var ua:Number = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            var ub:Number = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                // 检查是否在AABB内部
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与右边相交 (AABB右边: x = otherAABB.right, y: top -> bottom)
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (otherAABB.right - otherAABB.right) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.right - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与上边相交 (AABB上边: y = otherAABB.top, x: left -> right)
        denom = (otherAABB.top - otherAABB.top) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.top - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与下边相交 (AABB下边: y = otherAABB.bottom, x: left -> right)
        denom = (otherAABB.bottom - otherAABB.bottom) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // p2->p3
        ax = p2.x;
        ay = p2.y;
        bx = p3.x;
        by = p3.y;

        // 与左边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (otherAABB.left - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与右边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (otherAABB.right - otherAABB.right) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.right - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与上边相交
        denom = (otherAABB.top - otherAABB.top) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.top - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与下边相交
        denom = (otherAABB.bottom - otherAABB.bottom) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // p3->p4
        ax = p3.x;
        ay = p3.y;
        bx = p4.x;
        by = p4.y;

        // 与左边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (otherAABB.left - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与右边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (otherAABB.right - otherAABB.right) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.right - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与上边相交
        denom = (otherAABB.top - otherAABB.top) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.top - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与下边相交
        denom = (otherAABB.bottom - otherAABB.bottom) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // p4->p1
        ax = p4.x;
        ay = p4.y;
        bx = p1.x;
        by = p1.y;

        // 与左边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (otherAABB.left - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与右边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (otherAABB.right - otherAABB.right) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.right - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与上边相交
        denom = (otherAABB.top - otherAABB.top) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.top - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 与下边相交
        denom = (otherAABB.bottom - otherAABB.bottom) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.left - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                inter = {x: ax + ua * (bx - ax), y: ay + ua * (by - ay)};
                px = inter.x;
                py = inter.y;
                if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
                    intersectionPoints.push(inter);
                }
            }
        }

        // 去重
        var uniqueMap:Object = {};
        var uniquePoints:Array = [];
        var eps:Number = 0.00001;
        for (var u:Number = 0; u < intersectionPoints.length; u++) {
            px = intersectionPoints[u].x;
            py = intersectionPoints[u].y;
            var key:String = Math.round(px / eps) * eps + "_" + Math.round(py / eps) * eps;
            if (!uniqueMap[key]) {
                uniqueMap[key] = true;
                uniquePoints.push(intersectionPoints[u]);
            }
        }

        if (uniquePoints.length < 3) {
            var intersection:Array = uniquePoints;
        } else {
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

            intersection = uniquePoints;
        }

        // 内联展开 intersectRectangleWithAABB 完成

        if (!intersection || intersection.length < 3) {
            return CollisionResult.FALSE;
        }

        // 内联展开 calcArea(intersection)
        var intersectionArea:Number = 0;
        var lenArea:Number = intersection.length;
        var ii:Number = lenArea - 1;
        for (var iArea:Number = 0; iArea < lenArea; iArea++) {
            intersectionArea += intersection[ii].x * intersection[iArea].y - intersection[iArea].x * intersection[ii].y;
            ii = iArea;
        }
        intersectionArea = Math.abs(intersectionArea);

        // 内联展开 calcRectangleArea()
        var area:Number = (p1.x * p2.y + p2.x * p3.y + p3.x * p4.y + p4.x * p1.y) - (p2.x * p1.y + p3.x * p2.y + p4.x * p3.y + p1.x * p4.y);
        var thisArea:Number = (area < 0) ? -area : area;

        var overlapRatio:Number = intersectionArea / thisArea;

        // 计算质心
        var cxCentroid:Number = 0, cyCentroid:Number = 0;
        var leni:Number = intersection.length;
        for (var iCentroid:Number = 0; iCentroid < leni; iCentroid++) {
            cxCentroid += intersection[iCentroid].x;
            cyCentroid += intersection[iCentroid].y;
        }
        cxCentroid /= leni;
        cyCentroid /= leni;
        var overlapCenter:Vector = new Vector(cxCentroid, cyCentroid);

        var result:CollisionResult = new CollisionResult(true);
        result.setOverlapRatio(overlapRatio);
        result.setOverlapCenter(overlapCenter);
        return result;
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

        // 内联展开 pointToGameworld(x, y, loc)
        var pt:Object = {x: rect.xMax, y: rect.yMax};
        detectionArea.localToGlobal(pt);
        _root.gameworld.globalToLocal(pt);
        var p1gw:Vector = new Vector(pt.x, pt.y);

        pt = {x: rect.xMin, y: rect.yMin};
        detectionArea.localToGlobal(pt);
        _root.gameworld.globalToLocal(pt);
        var p3gw:Vector = new Vector(pt.x, pt.y);

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
        var frame:Number = _root.帧计时器.当前帧数;
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

    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }
}
