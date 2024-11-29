

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
        var clampedX:Number, clampedY:Number;

        // Clamp x within [left, right]
        if (x < this.left) {
            clampedX = this.left;
        } else if (x > this.right) {
            clampedX = this.right;
        } else {
            clampedX = x;
        }

        // Clamp y within [top, bottom]
        if (y < this.top) {
            clampedY = this.top;
        } else if (y > this.bottom) {
            clampedY = this.bottom;
        } else {
            clampedY = y;
        }

        return { x: clampedX, y: clampedY };
    }


    // 检查线段是否与AABB相交
    public function intersectsLine(x1:Number, y1:Number, x2:Number, y2:Number):Boolean {
        // 快速包含性检查（内联 containsPoint 逻辑）
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
            if (q < 0) return false; // 平行且在线段外
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



    public function intersectsRay(rayOriginX:Number, rayOriginY:Number, rayDirX:Number, rayDirY:Number):Boolean {
        var invDirX:Number, invDirY:Number, tMin:Number, tMax:Number, tyMin:Number, tyMax:Number;
        var temp:Number;

        // 计算 X 轴交点
        if (rayDirX != 0) {
            invDirX = 1.0 / rayDirX;
            tMin = (this.left - rayOriginX) * invDirX;
            tMax = (this.right - rayOriginX) * invDirX;

            // 确保 tMin 是最小值，tMax 是最大值
            if (tMin > tMax) {
                temp = tMin;
                tMin = tMax;
                tMax = temp;
            }
        } else if (rayOriginX < this.left || rayOriginX > this.right) {
            return false; // 射线平行且不在 AABB 范围内
        } else {
            tMin = Number.NEGATIVE_INFINITY;
            tMax = Number.POSITIVE_INFINITY;
        }

        // 计算 Y 轴交点
        if (rayDirY != 0) {
            invDirY = 1.0 / rayDirY;
            tyMin = (this.top - rayOriginY) * invDirY;
            tyMax = (this.bottom - rayOriginY) * invDirY;

            // 确保 tyMin 是最小值，tyMax 是最大值
            if (tyMin > tyMax) {
                temp = tyMin;
                tyMin = tyMax;
                tyMax = temp;
            }
        } else if (rayOriginY < this.top || rayOriginY > this.bottom) {
            return false; // 射线平行且不在 AABB 范围内
        } else {
            tyMin = Number.NEGATIVE_INFINITY;
            tyMax = Number.POSITIVE_INFINITY;
        }

        // 判断 X 和 Y 的范围是否重叠
        if (tMin > tyMax || tyMin > tMax) {
            return false;
        }

        // 更新 tMin 和 tMax，取交集
        tMin = (tMin > tyMin) ? tMin : tyMin;
        tMax = (tMax < tyMax) ? tMax : tyMax;

        // 检查射线是否与 AABB 相交
        return tMax >= 0;
    }


    // 检查当前AABB是否与另一个AABB相交
    public function intersects(other:AABB):Boolean {
        return !(this.right < other.left || this.left > other.right || 
                 this.bottom < other.top || this.top > other.bottom);
    }

    public function merge(other:AABB):AABB {
        return new AABB(
            (other.left < this.left) ? other.left : this.left,  // newLeft
            (other.right > this.right) ? other.right : this.right,  // newRight
            (other.top < this.top) ? other.top : this.top,  // newTop
            (other.bottom > this.bottom) ? other.bottom : this.bottom // newBottom
        );
    }


    public function mergeWith(other:AABB):Void {
        // 局部化变量，减少属性访问
        var left2:Number = other.left, right2:Number = other.right;
        var top2:Number = other.top, bottom2:Number = other.bottom;

        // 使用 if-else 更新 this 的边界值
        if (this.left > left2) {
            this.left = left2;
        }
        if (this.right < right2) {
            this.right = right2;
        }
        if (this.top > top2) {
            this.top = top2;
        }
        if (this.bottom < bottom2) {
            this.bottom = bottom2;
        }
    }



    public static function mergeBatch(aabbs:Array):AABB {
        var len = aabbs.length;

        if (len == 0) {
            throw new Error("mergeBatch: No AABBs to merge.");
        }

        var lastAABB = aabbs[len - 1];

        // 初始化边界值为最后一个 AABB 的值（逆序遍历）
        var left:Number = lastAABB.left;
        var right:Number = lastAABB.right;
        var top:Number = lastAABB.top;
        var bottom:Number = lastAABB.bottom;

        // 逆序遍历并更新边界值
        for (var i:Number = len - 2; i >= 0; i--) {
            var aabb:AABB = aabbs[i];
            if (aabb.left < left) left = aabb.left;
            if (aabb.right > right) right = aabb.right;
            if (aabb.top < top) top = aabb.top;
            if (aabb.bottom > bottom) bottom = aabb.bottom;
        }

        // 返回新的 AABB 对象，调整边界值以确保包含性
        return new AABB(left, right + 1, top, bottom + 1);
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

