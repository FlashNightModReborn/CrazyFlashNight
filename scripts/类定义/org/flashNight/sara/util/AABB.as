import org.flashNight.sara.util.*;
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

    /**
     * 根据两个点表示的对角线创建 AABB
     * @param p1 对角线起点（Vector 实例）
     * @param p2 对角线终点（Vector 实例）
     * @return 一个新的 AABB 实例
     */
    public static function fromDiagonal(p1:Vector, p2:Vector):AABB {
        return new AABB(
            (p1.x < p2.x) ? p1.x : p2.x, // 左边界
            (p1.x > p2.x) ? p1.x : p2.x, // 右边界
            (p1.y < p2.y) ? p1.y : p2.y, // 上边界
            (p1.y > p2.y) ? p1.y : p2.y  // 下边界
        );
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

    // 获取AABB的中心点，返回 Vector
    public function getCenter():Vector {
        var centerX:Number = (this.left + this.right) / 2;
        var centerY:Number = (this.top + this.bottom) / 2;
        return new Vector(centerX, centerY);
    }

    // 获取当前AABB与另一个AABB之间的最小平移向量（MTV）
    public function getMTV(other:AABB):Object {
        // 计算 x 轴重叠
        var overlapX:Number = 0;
        if (this.left < other.right && this.right > other.left) {
            var moveRight:Number = other.right - this.left;
            var moveLeft:Number = this.right - other.left;
            overlapX = (moveLeft < moveRight) ? -moveLeft : moveRight;
        } else {
            return null; // x 轴没有重叠
        }

        // 计算 y 轴重叠
        var overlapY:Number = 0;
        if (this.top < other.bottom && this.bottom > other.top) {
            var moveDown:Number = other.bottom - this.top;
            var moveUp:Number = this.bottom - other.top;
            overlapY = (moveUp < moveDown) ? -moveUp : moveDown;
        } else {
            return null; // y 轴没有重叠
        }

        // 确定最小平移向量
        if ((overlapX * overlapX) <= (overlapY * overlapY)) {
            return {dx: overlapX, dy: 0};
        } else {
            return {dx: 0, dy: overlapY};
        }
    }

    // 检查当前AABB是否包含给定的点
    public function containsPoint(x:Number, y:Number):Boolean {
        return (x >= this.left && x <= this.right &&
                y >= this.top && y <= this.bottom);
    }

    // 新增：接受 Vector 的 containsPoint 方法
    public function containsPointV(point:Vector):Boolean {
        return (point.x >= this.left && point.x <= this.right &&
                point.y >= this.top && point.y <= this.bottom);
    }

    // 计算AABB中离给定点最近的点，返回 Vector
    public function closestPoint(x:Number, y:Number):Vector {
        var clampedX:Number = (x < this.left) ? this.left : (x > this.right ? this.right : x);
        var clampedY:Number = (y < this.top) ? this.top : (y > this.bottom ? this.bottom : y);
        return new Vector(clampedX, clampedY);
    }

    // 新增：接受 Vector 的 closestPoint 方法
    public function closestPointV(point:Vector):Vector {
        var clampedX:Number = (point.x < this.left) ? this.left : (point.x > this.right ? this.right : point.x);
        var clampedY:Number = (point.y < this.top) ? this.top : (point.y > this.bottom ? this.bottom : point.y);
        return new Vector(clampedX, clampedY);
    }

    // 检查线段是否与AABB相交
    public function intersectsLine(x1:Number, y1:Number, x2:Number, y2:Number):Boolean {
        // 快速包含性检查
        if ((x1 >= this.left && x1 <= this.right && y1 >= this.top && y1 <= this.bottom) ||
            (x2 >= this.left && x2 <= this.right && y2 >= this.top && y2 <= this.bottom)) {
            return true;
        }

        // 初始化变量
        var t0:Number = 0.0;
        var t1:Number = 1.0;
        var dx:Number = x2 - x1;
        var dy:Number = y2 - y1;

        // 逐个轴的边界检测
        var p:Number, q:Number, t:Number;

        // 左边界
        p = -dx;
        q = x1 - this.left;
        if (p == 0) {
            if (q < 0) return false;
        } else {
            t = q / p;
            if (p < 0) {
                if (t > t1) return false;
                if (t > t0) t0 = t;
            } else {
                if (t < t0) return false;
                if (t < t1) t1 = t;
            }
        }

        // 右边界
        p = dx;
        q = this.right - x1;
        if (p == 0) {
            if (q < 0) return false;
        } else {
            t = q / p;
            if (p < 0) {
                if (t > t1) return false;
                if (t > t0) t0 = t;
            } else {
                if (t < t0) return false;
                if (t < t1) t1 = t;
            }
        }

        // 上边界
        p = -dy;
        q = y1 - this.top;
        if (p == 0) {
            if (q < 0) return false;
        } else {
            t = q / p;
            if (p < 0) {
                if (t > t1) return false;
                if (t > t0) t0 = t;
            } else {
                if (t < t0) return false;
                if (t < t1) t1 = t;
            }
        }

        // 下边界
        p = dy;
        q = this.bottom - y1;
        if (p == 0) {
            if (q < 0) return false;
        } else {
            t = q / p;
            if (p < 0) {
                if (t > t1) return false;
                if (t > t0) t0 = t;
            } else {
                if (t < t0) return false;
                if (t < t1) t1 = t;
            }
        }

        // 最终判断
        return t0 <= t1 && t1 >= 0 && t0 <= 1;
    }

    // 新增：接受 Vector 参数的 intersectsLine 方法
    public function intersectsLineV(start:Vector, end:Vector):Boolean {
        return this.intersectsLine(start.x, start.y, end.x, end.y);
    }

    // 检查圆是否与AABB相交
    public function intersectsCircle(circleX:Number, circleY:Number, radius:Number):Boolean {
        // 局部化边界值
        var left:Number = this.left, right:Number = this.right;
        var top:Number = this.top, bottom:Number = this.bottom;

        // 直接计算 deltaX 和 deltaY
        var deltaX:Number = circleX - ((circleX < left) ? left : (circleX > right ? right : circleX));
        var deltaY:Number = circleY - ((circleY < top) ? top : (circleY > bottom ? bottom : circleY));

        // 判断是否在半径范围内
        return (deltaX * deltaX + deltaY * deltaY) <= (radius * radius);
    }

    // 新增：接受 Vector 参数的 intersectsCircle 方法
    public function intersectsCircleV(circleCenter:Vector, radius:Number):Boolean {
        var left:Number = this.left, right:Number = this.right;
        var top:Number = this.top, bottom:Number = this.bottom;

        var deltaX:Number = circleCenter.x - ((circleCenter.x < left) ? left : (circleCenter.x > right ? right : circleCenter.x));
        var deltaY:Number = circleCenter.y - ((circleCenter.y < top) ? top : (circleCenter.y > bottom ? bottom : circleCenter.y));

        return (deltaX * deltaX + deltaY * deltaY) <= (radius * radius);
    }

    // 检查射线是否与AABB相交
    public function intersectsRay(rayOriginX:Number, rayOriginY:Number, rayDirX:Number, rayDirY:Number):Boolean {
        var invDirX:Number, invDirY:Number, tMin:Number, tMax:Number, tyMin:Number, tyMax:Number;
        var temp:Number;

        // 计算 X 轴交点
        if (rayDirX != 0) {
            invDirX = 1.0 / rayDirX;
            tMin = (this.left - rayOriginX) * invDirX;
            tMax = (this.right - rayOriginX) * invDirX;

            if (tMin > tMax) {
                temp = tMin;
                tMin = tMax;
                tMax = temp;
            }
        } else if (rayOriginX < this.left || rayOriginX > this.right) {
            return false;
        } else {
            tMin = Number.NEGATIVE_INFINITY;
            tMax = Number.POSITIVE_INFINITY;
        }

        // 计算 Y 轴交点
        if (rayDirY != 0) {
            invDirY = 1.0 / rayDirY;
            tyMin = (this.top - rayOriginY) * invDirY;
            tyMax = (this.bottom - rayOriginY) * invDirY;

            if (tyMin > tyMax) {
                temp = tyMin;
                tyMin = tyMax;
                tyMax = temp;
            }
        } else if (rayOriginY < this.top || rayOriginY > this.bottom) {
            return false;
        } else {
            tyMin = Number.NEGATIVE_INFINITY;
            tyMax = Number.POSITIVE_INFINITY;
        }

        if (tMin > tyMax || tyMin > tMax) {
            return false;
        }

        tMin = (tMin > tyMin) ? tMin : tyMin;
        tMax = (tMax < tyMax) ? tMax : tyMax;

        return tMax >= 0;
    }

    // 新增：接受 Vector 参数的 intersectsRay 方法
    public function intersectsRayV(rayOrigin:Vector, rayDir:Vector):Boolean {
        return this.intersectsRay(rayOrigin.x, rayOrigin.y, rayDir.x, rayDir.y);
    }

    // 检查当前AABB是否与另一个AABB相交
    public function intersects(other:AABB):Boolean {
        return !(this.right < other.left || this.left > other.right ||
                 this.bottom < other.top || this.top > other.bottom);
    }

    public function merge(other:AABB):AABB {
        return new AABB(
            (other.left < this.left) ? other.left : this.left,
            (other.right > this.right) ? other.right : this.right,
            (other.top < this.top) ? other.top : this.top,
            (other.bottom > this.bottom) ? other.bottom : this.bottom
        );
    }

    public function mergeWith(other:AABB):Void {
        if (this.left > other.left) {
            this.left = other.left;
        }
        if (this.right < other.right) {
            this.right = other.right;
        }
        if (this.top > other.top) {
            this.top = other.top;
        }
        if (this.bottom < other.bottom) {
            this.bottom = other.bottom;
        }
    }

    public static function mergeBatch(aabbs:Array):AABB {
        var len:Number = aabbs.length;

        if (len == 0) {
            throw new Error("mergeBatch: No AABBs to merge.");
        }

        var lastAABB:AABB = aabbs[len - 1];

        var left:Number = lastAABB.left;
        var right:Number = lastAABB.right;
        var top:Number = lastAABB.top;
        var bottom:Number = lastAABB.bottom;

        for (var i:Number = len - 2; i >= 0; i--) {
            var aabb:AABB = aabbs[i];
            if (aabb.left < left) left = aabb.left;
            if (aabb.right > right) right = aabb.right;
            if (aabb.top < top) top = aabb.top;
            if (aabb.bottom > bottom) bottom = aabb.bottom;
        }

        return new AABB(left, right + 1, top, bottom + 1);
    }

    // 将AABB细分为四个更小的AABB
    public function subdivide():Array {
        var center:Vector = this.getCenter();
        var left:Number = this.left;
        var right:Number = this.right;
        var top:Number = this.top;
        var bottom:Number = this.bottom;

        var quad1:AABB = new AABB(center.x, right, top, center.y);     // 右上
        var quad2:AABB = new AABB(left, center.x, top, center.y);      // 左上
        var quad3:AABB = new AABB(left, center.x, center.y, bottom);   // 左下
        var quad4:AABB = new AABB(center.x, right, center.y, bottom);  // 右下

        return [quad1, quad2, quad3, quad4];
    }

    // 计算AABB的面积
    public function getArea():Number {
        return (this.right - this.left) * (this.bottom - this.top);
    }

    // 从 MovieClip 创建 AABB
    public static function fromMovieClip(area:MovieClip, z_offset:Number):AABB {
        var rect:Object = area.getRect(area._parent);
        return new AABB(rect.xMin, rect.xMax, rect.yMin + z_offset, rect.yMax + z_offset);
    }

    // 从 Bullet 创建 AABB
    public static function fromBullet(bullet:MovieClip):AABB {
        var rect:Object = bullet.getRect(bullet._parent);
        return new AABB(rect.xMin, rect.xMax, rect.yMin, rect.yMax);
    }

    // 在给定的 MovieClip 上绘制 AABB
    public function draw(dmc:MovieClip):Void {
        var width:Number = this.right - this.left;
        var height:Number = this.bottom - this.top;
        var centerX:Number = this.left + width / 2;
        var centerY:Number = this.top + height / 2;

        Graphics.paintRectangle(dmc, centerX, centerY, width, height);
    }

    // 新增：返回 AABB 的四个顶点
    public function getVertices():Array {
        return [
            new Vector(this.left, this.top),     // 左上
            new Vector(this.right, this.top),    // 右上
            new Vector(this.right, this.bottom), // 右下
            new Vector(this.left, this.bottom)   // 左下
        ];
    }
}
