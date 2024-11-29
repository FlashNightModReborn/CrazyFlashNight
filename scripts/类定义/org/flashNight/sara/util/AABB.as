

import org.flashNight.sara.graphics.*;

class org.flashNight.sara.util.AABB {
    public var left:Number;
    public var right:Number;
    public var top:Number;
    public var bottom:Number;

    // 构造函数
    public function AABB(left:Number, right:Number, top:Number, bottom:Number) {
        this.left = left;
        this.right = right;
        this.top = top;
        this.bottom = bottom;
    }

    // 克隆当前的AABB
    public function clone():AABB {
        return new AABB(this.left, this.right, this.top, this.bottom);
    }

    // 获取AABB的宽度
    public function getWidth():Number {
        return this.right - this.left;
    }

    // 获取AABB的高度
    public function getLength():Number {
        return this.bottom - this.top;
    }

    // 获取AABB的中心点
    public function getCenter():Object {
        var centerX:Number = (this.left + this.right) / 2;
        var centerY:Number = (this.top + this.bottom) / 2;
        return {x: centerX, y: centerY};
    }

    // 获取当前AABB与另一个AABB之间的最小平移向量（MTV）
    public function getMTV(other:AABB):Object {
        // Calculate x-axis overlap
        var overlapX:Number = 0;
        if (this.left < other.right && this.right > other.left) {
            var moveRight:Number = other.right - this.left; // Move 'this' to the right
            var moveLeft:Number = this.right - other.left;  // Move 'this' to the left
            overlapX = (moveLeft < moveRight) ? -moveLeft : moveRight; // Choose minimal distance
        } else {
            return null; // No overlap on x-axis
        }

        // Calculate y-axis overlap
        var overlapY:Number = 0;
        if (this.top < other.bottom && this.bottom > other.top) {
            var moveDown:Number = other.bottom - this.top; // Move 'this' down
            var moveUp:Number = this.bottom - other.top;   // Move 'this' up
            overlapY = (moveUp < moveDown) ? -moveUp : moveDown; // Choose minimal distance
        } else {
            return null; // No overlap on y-axis
        }

        // Determine the minimal translation vector
        if (Math.abs(overlapX) <= Math.abs(overlapY)) {
            return {dx: overlapX, dy: 0}; // Prioritize x-axis if equal or smaller
        } else {
            return {dx: 0, dy: overlapY}; // Otherwise, prioritize y-axis
        }
    }





    // 检查当前AABB是否包含给定的点
    public function containsPoint(x:Number, y:Number):Boolean {
        return (x >= this.left && x <= this.right && 
                y >= this.top && y <= this.bottom);
    }

    // 计算AABB中离给定点最近的点
    public function closestPoint(x:Number, y:Number):Object {
        return {
            x: Math.max(this.left, Math.min(x, this.right)),
            y: Math.max(this.top, Math.min(y, this.bottom))
        };
    }

    // 检查线段是否与AABB相交
    public function intersectsLine(x1:Number, y1:Number, x2:Number, y2:Number):Boolean {
        if (this.containsPoint(x1, y1) || this.containsPoint(x2, y2)) {
            return true;
        }

        var t0:Number = 0.0;
        var t1:Number = 1.0;
        var dx:Number = x2 - x1;
        var dy:Number = y2 - y1;
        var p:Array = [-dx, dx, -dy, dy];
        var q:Array = [x1 - this.left, this.right - x1, y1 - this.top, this.bottom - y1];

        for (var i:Number = 0; i < 4; i++) {
            if (p[i] == 0) {
                if (q[i] < 0) {
                    return false;
                }
            } else {
                var t:Number = q[i] / p[i];
                if (p[i] < 0) {
                    if (t > t1) {
                        return false;
                    }
                    if (t > t0) {
                        t0 = t;
                    }
                } else {
                    if (t < t0) {
                        return false;
                    }
                    if (t < t1) {
                        t1 = t;
                    }
                }
            }
        }

        return t0 <= t1 && t1 >= 0 && t0 <= 1;
    }

    // 检查AABB是否与给定的圆相交
    public function intersectsCircle(circleX:Number, circleY:Number, radius:Number):Boolean {
        var nearestX:Number = Math.max(this.left, Math.min(circleX, this.right));
        var nearestY:Number = Math.max(this.top, Math.min(circleY, this.bottom));
        var deltaX:Number = circleX - nearestX;
        var deltaY:Number = circleY - nearestY;
        return (deltaX * deltaX + deltaY * deltaY) <= (radius * radius);
    }

    // 检查射线是否与AABB相交
    public function intersectsRay(rayOriginX:Number, rayOriginY:Number, rayDirX:Number, rayDirY:Number):Boolean {
        var tMin:Number, tMax:Number, tyMin:Number, tyMax:Number;
        var invDirX:Number = 1.0 / rayDirX;
        var invDirY:Number = 1.0 / rayDirY;

        if (rayDirX != 0) {
            tMin = (this.left - rayOriginX) * invDirX;
            tMax = (this.right - rayOriginX) * invDirX;

            if (tMin > tMax) {
                var temp:Number = tMin;
                tMin = tMax;
                tMax = temp;
            }
        } else {
            if (rayOriginX < this.left || rayOriginX > this.right) {
                return false;
            }
            tMin = Number.NEGATIVE_INFINITY;
            tMax = Number.POSITIVE_INFINITY;
        }

        if (rayDirY != 0) {
            tyMin = (this.top - rayOriginY) * invDirY;
            tyMax = (this.bottom - rayOriginY) * invDirY;

            if (tyMin > tyMax) {
                temp = tyMin;
                tyMin = tyMax;
                tyMax = temp;
            }
        } else {
            if (rayOriginY < this.top || rayOriginY > this.bottom) {
                return false;
            }
            tyMin = Number.NEGATIVE_INFINITY;
            tyMax = Number.POSITIVE_INFINITY;
        }

        if ((tMin > tyMax) || (tyMin > tMax)) {
            return false;
        }

        tMin = Math.max(tMin, tyMin);
        tMax = Math.min(tMax, tyMax);

        return tMax >= 0;
    }

    // 检查当前AABB是否与另一个AABB相交
    public function intersects(other:AABB):Boolean {
        return !(this.right < other.left || this.left > other.right || 
                 this.bottom < other.top || this.top > other.bottom);
    }

    // 将当前AABB与另一个AABB合并，返回新的AABB
    public function merge(other:AABB):AABB {
        var newLeft:Number = Math.min(this.left, other.left);
        var newRight:Number = Math.max(this.right, other.right);
        var newTop:Number = Math.min(this.top, other.top);
        var newBottom:Number = Math.max(this.bottom, other.bottom);
        return new AABB(newLeft, newRight, newTop, newBottom);
    }

    // 合并另一个AABB到当前AABB
    public function mergeWith(other:AABB):Void {
        this.left = Math.min(this.left, other.left);
        this.right = Math.max(this.right, other.right);
        this.top = Math.min(this.top, other.top);
        this.bottom = Math.max(this.bottom, other.bottom);
    }

    // 批量合并多个AABB
    public static function mergeBatch(aabbs:Array):AABB {
        if (aabbs.length == 0) {
            throw new Error("mergeBatch: No AABBs to merge.");
        }

        var mergedAABB:AABB = new AABB(aabbs[0].left, aabbs[0].right, aabbs[0].top, aabbs[0].bottom);

        for (var i:Number = 1; i < aabbs.length; i++) {
            mergedAABB.mergeWith(aabbs[i]);
        }

        // 调整最大边界以确保包含性
        mergedAABB.right += 1;
        mergedAABB.bottom += 1;

        return mergedAABB;
    }

    // 将AABB细分为四个更小的AABB
    public function subdivide():Array {
        var center:Object = this.getCenter();
        var left:Number = this.left;
        var right:Number = this.right;
        var top:Number = this.top;
        var bottom:Number = this.bottom;

        // 创建四个更小的AABB
        var quad1:AABB = new AABB(center.x, right, top, center.y);   // 右上
        var quad2:AABB = new AABB(left, center.x, top, center.y);    // 左上
        var quad3:AABB = new AABB(left, center.x, center.y, bottom); // 左下
        var quad4:AABB = new AABB(center.x, right, center.y, bottom); // 右下

        return [quad1, quad2, quad3, quad4];
    }

    // 计算AABB的面积
    public function getArea():Number {
        return (this.right - this.left) * (this.bottom - this.top);
    }

    // fromMovieClip
    public static function fromMovieClip(area:MovieClip, z_offset:Number):AABB {
        var rect = area.getRect(area._parent); // Use area._parent instead of _root.gameworld
        return new AABB(rect.xMin, rect.xMax, rect.yMin + z_offset, rect.yMax + z_offset);
    }

    // fromBullet
    public static function fromBullet(bullet:MovieClip):AABB {
        var rect = bullet.getRect(bullet._parent); // Use bullet._parent instead of _root.gameworld
        return new AABB(rect.xMin, rect.xMax, rect.yMin, rect.yMax);
    }


    // 在给定的MovieClip上绘制AABB
    public function draw(dmc:MovieClip):Void {
        var width:Number = this.right - this.left;
        var height:Number = this.bottom - this.top;
        var centerX:Number = this.left + width / 2;
        var centerY:Number = this.top + height / 2;

        Graphics.paintRectangle(dmc, centerX, centerY, width, height);
    }
}

