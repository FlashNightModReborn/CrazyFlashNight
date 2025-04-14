import org.flashNight.sara.util.*;
import org.flashNight.sara.graphics.*;

/**
 * AABB（轴对齐边界框）类
 * 
 * 此类用于表示和操作二维空间中的轴对齐边界框（Axis-Aligned Bounding Box）。
 * 提供了克隆、合并、细分、碰撞检测等多种方法，适用于游戏开发中的碰撞检测和空间划分。
 */
class org.flashNight.sara.util.AABB {
    // 边界坐标
    public var left:Number;   // 左边界
    public var right:Number;  // 右边界
    public var top:Number;    // 上边界
    public var bottom:Number; // 下边界

    /**
     * 构造函数
     * 
     * @param left 左边界坐标
     * @param right 右边界坐标
     * @param top 上边界坐标
     * @param bottom 下边界坐标
     */
    public function AABB(left:Number, right:Number, top:Number, bottom:Number) {
        this.left = left;
        this.right = right;
        this.top = top;
        this.bottom = bottom;
    }

    /**
     * 将 AABB 导出为 Morton 码
     * 
     * @return Morton 码
     */
    public function toMorton():Number {
        // 计算中心点并向下取整，使用无符号右移确保正确性
        var x:Number = (left + right) >>> 1;
        var y:Number = (top + bottom) >>> 1;

        // 计算 Morton 码
        x = (x | (x << 16)) & 0x0000FFFF;
        x = (x | (x << 8)) & 0x00FF00FF;
        x = (x | (x << 4)) & 0x0F0F0F0F;
        x = (x | (x << 2)) & 0x33333333;
        x = (x | (x << 1)) & 0x55555555;

        y = (y | (y << 16)) & 0x0000FFFF;
        y = (y | (y << 8)) & 0x00FF00FF;
        y = (y | (y << 4)) & 0x0F0F0F0F;
        y = (y | (y << 2)) & 0x33333333;
        y = (y | (y << 1)) & 0x55555555;

        return x | (y << 1);
    }


    /**
     * 根据两个点表示的对角线创建 AABB
     * 
     * @param p1 对角线起点（Vector 实例）
     * @param p2 对角线终点（Vector 实例）
     * @return 一个新的 AABB 实例
     */
    public static function fromDiagonal(p1:Vector, p2:Vector):AABB {
        return new AABB(
            (p1.x < p2.x) ? p1.x : p2.x, // 确定左边界
            (p1.x > p2.x) ? p1.x : p2.x, // 确定右边界
            (p1.y < p2.y) ? p1.y : p2.y, // 确定上边界
            (p1.y > p2.y) ? p1.y : p2.y  // 确定下边界
        );
    }

    /**
     * 克隆当前的 AABB
     * 
     * @return 一个新的 AABB 实例，具有相同的边界坐标
     */
    public function clone():AABB {
        return new AABB(this.left, this.right, this.top, this.bottom);
    }

    /**
     * 获取 AABB 的宽度
     * 
     * @return AABB 的宽度（右边界 - 左边界）
     */
    public function getWidth():Number {
        return this.right - this.left;
    }

    /**
     * 获取 AABB 的高度
     * 
     * @return AABB 的高度（下边界 - 上边界）
     */
    public function getLength():Number {
        return this.bottom - this.top;
    }

    /**
     * 获取 AABB 的中心点，返回 Vector 实例
     * 
     * @return AABB 的中心点坐标（Vector 实例）
     */
    public function getCenter():Vector {
        var centerX:Number = (this.left + this.right) / 2;
        var centerY:Number = (this.top + this.bottom) / 2;
        return new Vector(centerX, centerY);
    }

    /**
     * 移动AABB（修改自身）
     * 
     * @param offset 移动向量（Vector实例）
     */
    public function move(offset:Vector):Void {
        this.left += offset.x;
        this.right += offset.x;
        this.top += offset.y;
        this.bottom += offset.y;
    }

    /**
     * 移动AABB（不修改自身，返回新实例）
     * 
     * @param offset 移动向量（Vector实例）
     * @return 新的AABB实例
     */
    public function moveNew(offset:Vector):AABB {
        var newAABB:AABB = this.clone();
        newAABB.move(offset);
        return newAABB;
    }

    /**
     * 获取当前 AABB 与另一个 AABB 之间的最小平移向量（MTV）
     * 
     * @param other 另一个 AABB 实例
     * @return 一个包含 dx 和 dy 的对象，表示最小平移向量；如果没有重叠则返回 null
     */
    public function getMTV(other:AABB):Object {
        // 计算 x 轴重叠
        var overlapX:Number = 0;
        if (this.left < other.right && this.right > other.left) {
            var moveRight:Number = other.right - this.left;
            var moveLeft:Number = this.right - other.left;
            overlapX = (moveLeft < moveRight) ? -moveLeft : moveRight;
        } else {
            return null; // x 轴没有重叠，无法计算 MTV
        }

        // 计算 y 轴重叠
        var overlapY:Number = 0;
        if (this.top < other.bottom && this.bottom > other.top) {
            var moveDown:Number = other.bottom - this.top;
            var moveUp:Number = this.bottom - other.top;
            overlapY = (moveUp < moveDown) ? -moveUp : moveDown;
        } else {
            return null; // y 轴没有重叠，无法计算 MTV
        }

        // 确定最小平移向量，比较绝对值以决定移动方向
        var absOverlapX:Number = (overlapX < 0) ? -overlapX : overlapX;
        var absOverlapY:Number = (overlapY < 0) ? -overlapY : overlapY;

        return (absOverlapX <= absOverlapY) 
            ? {dx: overlapX, dy: 0} 
            : {dx: 0, dy: overlapY};
    }

    /**
     * 获取当前 AABB 与另一个 AABB 之间的最小平移向量（MTV），返回 Vector 实例
     * 
     * @param other 另一个 AABB 实例
     * @return 最小平移向量的 Vector 实例（如果没有重叠则返回 null）
     */
    public function getMTVV(other:AABB):Vector {
        // 计算 x 轴重叠
        var overlapX:Number = 0;
        if (this.left < other.right && this.right > other.left) {
            var moveRight:Number = other.right - this.left;
            var moveLeft:Number = this.right - other.left;
            overlapX = (moveLeft < moveRight) ? -moveLeft : moveRight;
        } else {
            return null; // x 轴没有重叠，无法计算 MTV
        }

        // 计算 y 轴重叠
        var overlapY:Number = 0;
        if (this.top < other.bottom && this.bottom > other.top) {
            var moveDown:Number = other.bottom - this.top;
            var moveUp:Number = this.bottom - other.top;
            overlapY = (moveUp < moveDown) ? -moveUp : moveDown;
        } else {
            return null; // y 轴没有重叠，无法计算 MTV
        }

        // 确定最小平移向量，比较绝对值以决定移动方向
        var absOverlapX:Number = (overlapX < 0) ? -overlapX : overlapX;
        var absOverlapY:Number = (overlapY < 0) ? -overlapY : overlapY;

        return (absOverlapX <= absOverlapY) 
            ? new Vector(overlapX, 0) 
            : new Vector(0, overlapY);
    }

    /**
     * 检查当前 AABB 是否包含给定的点
     * 
     * @param x 点的 x 坐标
     * @param y 点的 y 坐标
     * @return 如果点在 AABB 内部或边界上，返回 true；否则返回 false
     */
    public function containsPoint(x:Number, y:Number):Boolean {
        return (x >= this.left && x <= this.right &&
                y >= this.top && y <= this.bottom);
    }

    /**
     * 检查当前 AABB 是否包含给定的点（使用 Vector 参数）
     * 
     * @param point 包含点的 Vector 实例
     * @return 如果点在 AABB 内部或边界上，返回 true；否则返回 false
     */
    public function containsPointV(point:Vector):Boolean {
        return (point.x >= this.left && point.x <= this.right &&
                point.y >= this.top && point.y <= this.bottom);
    }

    /**
     * 计算 AABB 中离给定点最近的点，返回 Vector 实例
     * 
     * @param x 给定点的 x 坐标
     * @param y 给定点的 y 坐标
     * @return 最近点的 Vector 实例
     */
    public function closestPoint(x:Number, y:Number):Vector {
        return new Vector(
            (x < this.left) ? this.left : (x > this.right ? this.right : x),
            (y < this.top) ? this.top : (y > this.bottom ? this.bottom : y)
        );
    }

    /**
     * 计算 AABB 中离给定点最近的点，返回 Vector 实例（使用 Vector 参数）
     * 
     * @param point 给定点的 Vector 实例
     * @return 最近点的 Vector 实例
     */
    public function closestPointV(point:Vector):Vector {
        return new Vector(
            (point.x < this.left) ? this.left : (point.x > this.right ? this.right : point.x), 
            (point.y < this.top) ? this.top : (point.y > this.bottom ? this.bottom : point.y)
        );
    }

    /**
     * 检查线段是否与 AABB 相交
     * 
     * @param x1 线段起点的 x 坐标
     * @param y1 线段起点的 y 坐标
     * @param x2 线段终点的 x 坐标
     * @param y2 线段终点的 y 坐标
     * @return 如果线段与 AABB 相交，返回 true；否则返回 false
     */
    public function intersectsLine(x1:Number, y1:Number, x2:Number, y2:Number):Boolean {
        // 快速包含性检查：如果任意一个端点在 AABB 内部，则相交
        if ((x1 >= this.left && x1 <= this.right && y1 >= this.top && y1 <= this.bottom) ||
            (x2 >= this.left && x2 <= this.right && y2 >= this.top && y2 <= this.bottom)) {
            return true;
        }

        // 初始化变量，用于计算参数 t
        var t0:Number = 0.0;
        var t1:Number = 1.0;
        var dx:Number = x2 - x1; // 线段在 x 轴的增量
        var dy:Number = y2 - y1; // 线段在 y 轴的增量

        // 逐个轴的边界检测
        var p:Number, q:Number, t:Number;

        // 检查左边界
        p = -dx;
        q = x1 - this.left;
        if (p == 0) {
            if (q < 0) return false; // 线段平行于左边界且在左侧，无法相交
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

        // 检查右边界
        p = dx;
        q = this.right - x1;
        if (p == 0) {
            if (q < 0) return false; // 线段平行于右边界且在右侧，无法相交
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

        // 检查上边界
        p = -dy;
        q = y1 - this.top;
        if (p == 0) {
            if (q < 0) return false; // 线段平行于上边界且在上方，无法相交
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

        // 检查下边界
        p = dy;
        q = this.bottom - y1;
        if (p == 0) {
            if (q < 0) return false; // 线段平行于下边界且在下方，无法相交
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

        // 最终判断，判断 t0 和 t1 是否有重叠，并且 tMax >= 0，tMin <= 1
        return t0 <= t1 && t1 >= 0 && t0 <= 1;
    }

    /**
     * 检查线段是否与 AABB 相交，接受 Vector 参数
     * 
     * @param start 起点的 Vector 实例
     * @param end 终点的 Vector 实例
     * @return 如果线段与 AABB 相交，返回 true；否则返回 false
     */
    public function intersectsLineV(start:Vector, end:Vector):Boolean {
        var x1:Number = start.x;
        var y1:Number = start.y;
        var x2:Number = end.x;
        var y2:Number = end.y;

        // 快速包含性检查：如果任意一个端点在 AABB 内部，则相交
        if ((x1 >= this.left && x1 <= this.right && y1 >= this.top && y1 <= this.bottom) ||
            (x2 >= this.left && x2 <= this.right && y2 >= this.top && y2 <= this.bottom)) {
            return true;
        }

        // 初始化变量，用于计算参数 t
        var t0:Number = 0.0;
        var t1:Number = 1.0;
        var dx:Number = x2 - x1; // 线段在 x 轴的增量
        var dy:Number = y2 - y1; // 线段在 y 轴的增量

        // 逐个轴的边界检测
        var p:Number, q:Number, t:Number;

        // 检查左边界
        p = -dx;
        q = x1 - this.left;
        if (p == 0) {
            if (q < 0) return false; // 线段平行于左边界且在左侧，无法相交
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

        // 检查右边界
        p = dx;
        q = this.right - x1;
        if (p == 0) {
            if (q < 0) return false; // 线段平行于右边界且在右侧，无法相交
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

        // 检查上边界
        p = -dy;
        q = y1 - this.top;
        if (p == 0) {
            if (q < 0) return false; // 线段平行于上边界且在上方，无法相交
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

        // 检查下边界
        p = dy;
        q = this.bottom - y1;
        if (p == 0) {
            if (q < 0) return false; // 线段平行于下边界且在下方，无法相交
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

        // 最终判断，判断 t0 和 t1 是否有重叠，并且 tMax >= 0，tMin <= 1
        return t0 <= t1 && t1 >= 0 && t0 <= 1;
    }

    /**
     * 检查圆是否与 AABB 相交
     * 
     * @param circleX 圆心的 x 坐标
     * @param circleY 圆心的 y 坐标
     * @param radius 圆的半径
     * @return 如果圆与 AABB 相交，返回 true；否则返回 false
     */
    public function intersectsCircle(circleX:Number, circleY:Number, radius:Number):Boolean {
        // 局部化边界值，减少属性访问次数
        var left:Number = this.left, right:Number = this.right;
        var top:Number = this.top, bottom:Number = this.bottom;

        // 计算圆心到 AABB 最近点的 deltaX 和 deltaY
        var deltaX:Number = circleX - ((circleX < left) ? left : (circleX > right ? right : circleX));
        var deltaY:Number = circleY - ((circleY < top) ? top : (circleY > bottom ? bottom : circleY));

        // 判断距离是否在半径范围内
        return (deltaX * deltaX + deltaY * deltaY) <= (radius * radius);
    }

    /**
     * 检查圆是否与 AABB 相交（使用 Vector 参数）
     * 
     * @param circleCenter 圆心的 Vector 实例
     * @param radius 圆的半径
     * @return 如果圆与 AABB 相交，返回 true；否则返回 false
     */
    public function intersectsCircleV(circleCenter:Vector, radius:Number):Boolean {
        // 局部化边界值，减少属性访问次数
        var left:Number = this.left, right:Number = this.right;
        var top:Number = this.top, bottom:Number = this.bottom;
        var circleX:Number = circleCenter.x;
        var circleY:Number = circleCenter.y;

        // 计算圆心到 AABB 最近点的 deltaX 和 deltaY
        var deltaX:Number = circleX - ((circleX < left) ? left : (circleX > right ? right : circleX));
        var deltaY:Number = circleY - ((circleY < top) ? top : (circleY > bottom ? bottom : circleY));

        // 判断距离是否在半径范围内
        return (deltaX * deltaX + deltaY * deltaY) <= (radius * radius);
    }

    /**
     * 检查射线是否与 AABB 相交
     * 
     * @param rayOriginX 射线起点的 x 坐标
     * @param rayOriginY 射线起点的 y 坐标
     * @param rayDirX 射线方向的 x 分量
     * @param rayDirY 射线方向的 y 分量
     * @return 如果射线与 AABB 相交，返回 true；否则返回 false
     */
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
            return false; // 射线平行于 X 轴且不在 AABB 范围内
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
            return false; // 射线平行于 Y 轴且不在 AABB 范围内
        } else {
            tyMin = Number.NEGATIVE_INFINITY;
            tyMax = Number.POSITIVE_INFINITY;
        }

        // 判断 X 和 Y 的范围是否重叠
        if (tMin > tyMax || tyMin > tMax) {
            return false; // 没有重叠部分，射线不相交
        }

        // 更新 tMin 和 tMax，取交集
        tMin = (tMin > tyMin) ? tMin : tyMin;
        tMax = (tMax < tyMax) ? tMax : tyMax;

        // 检查射线是否与 AABB 相交
        return tMax >= 0;
    }

    /**
     * 检查射线是否与 AABB 相交（使用 Vector 参数）
     * 
     * @param rayOrigin 射线起点的 Vector 实例
     * @param rayDir 射线方向的 Vector 实例
     * @return 如果射线与 AABB 相交，返回 true；否则返回 false
     */
    public function intersectsRayV(rayOrigin:Vector, rayDir:Vector):Boolean {
        var rayOriginX:Number = rayOrigin.x;
        var rayOriginY:Number = rayOrigin.y;
        var rayDirX:Number = rayDir.x;
        var rayDirY:Number = rayDir.y;

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
            return false; // 射线平行于 X 轴且不在 AABB 范围内
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
            return false; // 射线平行于 Y 轴且不在 AABB 范围内
        } else {
            tyMin = Number.NEGATIVE_INFINITY;
            tyMax = Number.POSITIVE_INFINITY;
        }

        // 判断 X 和 Y 的范围是否重叠
        if (tMin > tyMax || tyMin > tMax) {
            return false; // 没有重叠部分，射线不相交
        }

        // 更新 tMin 和 tMax，取交集
        tMin = (tMin > tyMin) ? tMin : tyMin;
        tMax = (tMax < tyMax) ? tMax : tyMax;

        // 检查射线是否与 AABB 相交
        return tMax >= 0;
    }

    /**
     * 检查当前 AABB 是否与另一个 AABB 相交
     * 
     * @param other 另一个 AABB 实例
     * @return 如果两个 AABB 相交，返回 true；否则返回 false
     */
    public function intersects(other:AABB):Boolean {
        return !(this.right < other.left || this.left > other.right ||
                 this.bottom < other.top || this.top > other.bottom);
    }

    /**
     * 合并当前 AABB 与另一个 AABB，返回一个新的 AABB 实例
     * 
     * @param other 另一个 AABB 实例
     * @return 合并后的 AABB 实例
     */
    public function merge(other:AABB):AABB {
        return new AABB(
            (other.left < this.left) ? other.left : this.left,   // 合并后的左边界
            (other.right > this.right) ? other.right : this.right, // 合并后的右边界
            (other.top < this.top) ? other.top : this.top,      // 合并后的上边界
            (other.bottom > this.bottom) ? other.bottom : this.bottom // 合并后的下边界
        );
    }

    /**
     * 合并当前 AABB 与另一个 AABB，直接修改当前 AABB 的边界
     * 
     * @param other 另一个 AABB 实例
     */
    public function mergeWith(other:AABB):Void {
        if (this.left > other.left) {
            this.left = other.left; // 更新左边界
        }
        if (this.right < other.right) {
            this.right = other.right; // 更新右边界
        }
        if (this.top > other.top) {
            this.top = other.top; // 更新上边界
        }
        if (this.bottom < other.bottom) {
            this.bottom = other.bottom; // 更新下边界
        }
    }

    /**
     * 批量合并多个 AABB，返回一个新的 AABB 实例
     * 
     * @param aabbs 要合并的 AABB 数组
     * @return 合并后的 AABB 实例
     * @throws Error 如果传入的数组为空
     */
    public static function mergeBatch(aabbs:Array):AABB {
        var len:Number = aabbs.length;

        if (len == 0) {
            throw new Error("mergeBatch: No AABBs to merge."); // 抛出错误，提示没有 AABB 可供合并
        }

        var lastAABB:AABB = aabbs[len - 1];

        // 初始化合并后的边界为最后一个 AABB 的边界
        var left:Number = lastAABB.left;
        var right:Number = lastAABB.right;
        var top:Number = lastAABB.top;
        var bottom:Number = lastAABB.bottom;

        // 遍历剩余的 AABB，更新合并后的边界
        for (var i:Number = len - 2; i >= 0; i--) {
            var aabb:AABB = aabbs[i];
            if (aabb.left < left) left = aabb.left;
            if (aabb.right > right) right = aabb.right;
            if (aabb.top < top) top = aabb.top;
            if (aabb.bottom > bottom) bottom = aabb.bottom;
        }

        // 返回合并后的 AABB 实例，注意右边界和下边界增加了 1
        return new AABB(left, right + 1, top, bottom + 1);
    }

    /**
     * 将 AABB 细分为四个更小的 AABB
     * 
     * @return 包含四个子 AABB 的数组
     */
    public function subdivide():Array {
        var center:Vector = this.getCenter(); // 获取当前 AABB 的中心点
        var left:Number = this.left;
        var right:Number = this.right;
        var top:Number = this.top;
        var bottom:Number = this.bottom;

        // 创建四个子 AABB，分别代表四个象限
        var quad1:AABB = new AABB(center.x, right, top, center.y);     // 右上
        var quad2:AABB = new AABB(left, center.x, top, center.y);      // 左上
        var quad3:AABB = new AABB(left, center.x, center.y, bottom);   // 左下
        var quad4:AABB = new AABB(center.x, right, center.y, bottom);  // 右下

        return [quad1, quad2, quad3, quad4]; // 返回包含四个子 AABB 的数组
    }

    /**
     * 计算 AABB 的面积
     * 
     * @return AABB 的面积（宽度 * 高度）
     */
    public function getArea():Number {
        return (this.right - this.left) * (this.bottom - this.top);
    }

    public static function getGameWorldAABB(dmc:MovieClip):AABB
    {
        var rect = dmc.getRect(_root.gameworld);
        return new AABB(rect.xMin, rect.xMax, rect.yMin, rect.yMax);
    }

    /**
     * 从 MovieClip 创建 AABB
     * 
     * @param area 用于创建 AABB 的 MovieClip 实例
     * @param z_offset z 轴偏移量，用于调整 y 坐标
     * @return 一个新的 AABB 实例
     */
    public static function fromMovieClip(area:MovieClip, z_offset:Number):AABB {
        var rect:Object = area.getRect(area._parent); // 获取 MovieClip 的矩形边界
        return new AABB(rect.xMin, rect.xMax, rect.yMin + z_offset, rect.yMax + z_offset);
    }

    /**
     * 从 Bullet 创建 AABB
     * 
     * @param bullet 用于创建 AABB 的 Bullet MovieClip 实例
     * @return 一个新的 AABB 实例
     */
    public static function fromBullet(bullet:MovieClip):AABB {
        var rect:Object = bullet.getRect(bullet._parent); // 获取 Bullet 的矩形边界
        return new AABB(rect.xMin, rect.xMax, rect.yMin, rect.yMax);
    }

    /**
     * 在给定的 MovieClip 上绘制 AABB
     * 
     * @param dmc 用于绘制 AABB 的目标 MovieClip 实例
     */
    public function draw(dmc:MovieClip):Void {
        var width:Number = this.right - this.left;  // 计算 AABB 的宽度
        var height:Number = this.bottom - this.top; // 计算 AABB 的高度
        var centerX:Number = this.left + width / 2; // 计算中心点的 x 坐标
        var centerY:Number = this.top + height / 2; // 计算中心点的 y 坐标

        Graphics.paintRectangle(dmc, centerX, centerY, width, height); // 调用 Graphics 类的方法绘制矩形
    }

    /**
     * 返回 AABB 的四个顶点，按左上、右上、右下、左下顺序
     * 
     * @return 包含四个 Vector 实例的数组，分别代表四个顶点
     */
    public function getVertices():Array {
        return [
            new Vector(this.left, this.top),     // 左上
            new Vector(this.right, this.top),    // 右上
            new Vector(this.right, this.bottom), // 右下
            new Vector(this.left, this.bottom)   // 左下
        ];
    }

    /**
     * 将 AABB 转换为 PointSet
     * 
     * PointSet 是一个自定义的数据结构，用于存储和操作一组点。
     * 此方法将 AABB 的四个顶点添加到 PointSet 中。
     * 
     * @return 一个包含四个顶点的 PointSet 实例
     */
    public function toPointSet():PointSet {
        var pointSet:PointSet = new PointSet();

        // 添加 AABB 的四个顶点到 PointSet
        pointSet.addPoint(this.left, this.top);     // 左上
        pointSet.addPoint(this.right, this.top);    // 右上
        pointSet.addPoint(this.right, this.bottom); // 右下
        pointSet.addPoint(this.left, this.bottom);  // 左下

        return pointSet;
    }
    /**
     * 转换成字符串输出
     * 
     * @return 字符串形式的 AABB 信息
     */

    public function toString():String
    {
        return "[" + this.left + "," + this.right + "," + this.top + "," + this.bottom + "]";
    }
}
