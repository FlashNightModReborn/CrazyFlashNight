import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider extends RectanglePointSet implements ICollider {
    public var _factory:AbstractColliderFactory;
    public var _update:Function;
    public var _currentFrame:Number;

    // 为了避免动态push，这里定义最大点数量（可根据实际需求调整）
    // 矩形的顶点是否在 AABB 内：
    // 最多可以有 4 个点（矩形的 4 个顶点全部落在 AABB 内）。
    // 矩形边与 AABB 边的交点：
    // 每条矩形边最多与 AABB 的 4 条边各产生一个交点。矩形有 4 条边，因此最多有 16 个交点。
    // 两个矩形（包括 AABB）之间的交点一般远低于理论上限。
    // 在大多数情况下：
    // 如果一个矩形完全在 AABB 内，则只有矩形的顶点；
    // 如果一个矩形与 AABB 部分重叠，实际交点通常为 3 至 8 个（取决于重叠区域的形状）。

    private static var MAX_POINTS:Number = 8;

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

        // 不使用push, 使用数组索引管理
        var intersectionPointsX:Array = new Array(MAX_POINTS);
        var intersectionPointsY:Array = new Array(MAX_POINTS);
        var intersectionPointsCount:Number = 0;

        var px:Number, py:Number;

        // 收集在AABB内部的点 (p1, p2, p3, p4)
        px = p1.x;
        py = p1.y;
        if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
            intersectionPointsX[intersectionPointsCount] = px;
            intersectionPointsY[intersectionPointsCount] = py;
            intersectionPointsCount++;
        }

        px = p2.x;
        py = p2.y;
        if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
            intersectionPointsX[intersectionPointsCount] = px;
            intersectionPointsY[intersectionPointsCount] = py;
            intersectionPointsCount++;
        }

        px = p3.x;
        py = p3.y;
        if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
            intersectionPointsX[intersectionPointsCount] = px;
            intersectionPointsY[intersectionPointsCount] = py;
            intersectionPointsCount++;
        }

        px = p4.x;
        py = p4.y;
        if (px >= otherAABB.left && px <= otherAABB.right && py >= otherAABB.top && py <= otherAABB.bottom) {
            intersectionPointsX[intersectionPointsCount] = px;
            intersectionPointsY[intersectionPointsCount] = py;
            intersectionPointsCount++;
        }

        var ax:Number, ay:Number, bx:Number, by:Number;
        var interX:Number, interY:Number;
        var denom:Number, ua:Number, ub:Number;

        /*、

        // 定义一个内联函数式代码块用于插入交点(实际使用重复代码结构)
        // 注释掉以免造成额外开销，此处作为注释留档备份
        function addIntersectionPoint(ix:Number, iy:Number):Void {
            // 检查是否在AABB内部
            if (ix >= otherAABB.left && ix <= otherAABB.right && iy >= otherAABB.top && iy <= otherAABB.bottom) {
                intersectionPointsX[intersectionPointsCount] = ix;
                intersectionPointsY[intersectionPointsCount] = iy;
                intersectionPointsCount++;
            }
        }

        */

        // 定义一个内联计算相交的片段逻辑函数伪代码（只为减少重复，不是真正函数调用）
        // 实际上将重复的行复制粘贴以避免函数调用。

        // 边：p1->p2
        ax = p1.x;
        ay = p1.y;
        bx = p2.x;
        by = p2.y;
        // 与左边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax);
        // (otherAABB.left - otherAABB.left)=0, 因此这行原本是减了0可忽略
        denom = denom - (0) * (by - ay); // 无意义但保留结构
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                // 检查AABB内部
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 与右边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (0) * (by - ay); // right-right=0
        if (denom != 0) {
            ua = ((otherAABB.right - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 与上边相交
        denom = (0) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay); //(otherAABB.top-otherAABB.top)=0
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (0) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 与下边相交
        denom = (0) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay); //(otherAABB.bottom-otherAABB.bottom)=0
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // p2->p3
        ax = p2.x;
        ay = p2.y;
        bx = p3.x;
        by = p3.y;
        // 与左边相交
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (0) * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 与右边
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - (0) * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.right - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 上边
        denom = (0) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (0) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 下边
        denom = (0) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // p3->p4
        ax = p3.x;
        ay = p3.y;
        bx = p4.x;
        by = p4.y;
        // 与左边
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - 0 * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 右边
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - 0 * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.right - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 上边
        denom = (0) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (0) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 下边
        denom = (0) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // p4->p1
        ax = p4.x;
        ay = p4.y;
        bx = p1.x;
        by = p1.y;
        // 左边
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - 0 * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 右边
        denom = (otherAABB.bottom - otherAABB.top) * (bx - ax) - 0 * (by - ay);
        if (denom != 0) {
            ua = ((otherAABB.right - otherAABB.left) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 上边
        denom = (0) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (0) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 下边
        denom = (0) * (bx - ax) - (otherAABB.right - otherAABB.left) * (by - ay);
        if (denom != 0) {
            ua = ((0) * (ay - otherAABB.top) - (otherAABB.bottom - otherAABB.top) * (ax - otherAABB.left)) / denom;
            ub = ((bx - ax) * (ay - otherAABB.top) - (by - ay) * (ax - otherAABB.left)) / denom;
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) {
                interX = ax + ua * (bx - ax);
                interY = ay + ua * (by - ay);
                if (interX >= otherAABB.left && interX <= otherAABB.right && interY >= otherAABB.top && interY <= otherAABB.bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount] = interY;
                    intersectionPointsCount++;
                }
            }
        }

        // 去重
        var uniqueMap:Object = {};
        var uniquePointsX:Array = new Array(MAX_POINTS);
        var uniquePointsY:Array = new Array(MAX_POINTS);
        var uniquePointsCount:Number = 0;
        var eps:Number = 0.00001;
        var val:Number, scale:Number, integerVal:Number;

        for (var u:Number = 0; u < intersectionPointsCount; u++) {
            px = intersectionPointsX[u];
            py = intersectionPointsY[u];

            // 模拟round(px/eps) 用三元运算符优化
            val = px / eps;
            val = (val >= 0 ? val + 0.5 : val - 0.5) - (val % 1); // 四舍五入并去掉小数部分
            var roundedX:Number = val * eps;

            val = py / eps;
            val = (val >= 0 ? val + 0.5 : val - 0.5) - (val % 1); // 四舍五入并去掉小数部分
            var roundedY:Number = val * eps;


            // 使用位运算生成唯一键
            var key:Number = (roundedX << 16) | (roundedY & 0xFFFF);
            if (!uniqueMap[key]) {
                uniqueMap[key] = true;
                uniquePointsX[uniquePointsCount] = px;
                uniquePointsY[uniquePointsCount] = py;
                uniquePointsCount++;
            }
        }

        if (uniquePointsCount < 3) {
            var intersectionCount:Number = uniquePointsCount;
            if (intersectionCount < 3) {
                return CollisionResult.FALSE;
            }
                // 当点数小于3，不需要排序和计算，因为面积也将是0
                // 下面直接进行计算，实际上小于3无法形成多边形，无需计算重叠率
                // 但按照原逻辑继续下去
        } else {
            // 计算质心
            var cx:Number = 0, cy:Number = 0;
            for (var m:Number = 0; m < uniquePointsCount; m++) {
                cx += uniquePointsX[m];
                cy += uniquePointsY[m];
            }
            cx = cx / uniquePointsCount;
            cy = cy / uniquePointsCount;

            // 需要对点按极角排序
            // 原先使用 sort(function(a,b)),现在没有对象数组，我们有平行数组，需要建立索引数组
            var indices:Array = new Array(uniquePointsCount);
            for (var idx:Number = 0; idx < uniquePointsCount; idx++) {
                indices[idx] = idx;
            }

            // 使用插入排序对 indices 进行排序
            for (var i:Number = 1; i < uniquePointsCount; i++) {
                var current:Number = indices[i];
                var ax:Number = uniquePointsX[current];
                var ay:Number = uniquePointsY[current];

                // 计算当前点的极角
                var currentAngle:Number = Math.atan2(ay - cy, ax - cx);

                var j:Number = i - 1;
                while (j >= 0) {
                    var previous:Number = indices[j];
                    var bx:Number = uniquePointsX[previous];
                    var by:Number = uniquePointsY[previous];

                    // 计算前一个点的极角
                    var previousAngle:Number = Math.atan2(by - cy, bx - cx);

                    // 比较当前点与前一个点的极角
                    if (currentAngle >= previousAngle) {
                        break; // 当前点的位置已正确，退出内循环
                    }

                    // 如果当前点的极角小于前一个点，后移前一个点
                    indices[j + 1] = previous;
                    j--;
                }

                // 将当前点放到正确位置
                indices[j + 1] = current;
            }


            // 按排序后的顺序重排uniquePointsX,Y
            var sortedX:Array = new Array(uniquePointsCount);
            var sortedY:Array = new Array(uniquePointsCount);
            for (var s:Number = 0; s < uniquePointsCount; s++) {
                var ii:Number = indices[s];
                sortedX[s] = uniquePointsX[ii];
                sortedY[s] = uniquePointsY[ii];
            }

            // 用 sortedX, sortedY 代替 uniquePointsX/Y 作为最终 intersection
            uniquePointsX = sortedX;
            uniquePointsY = sortedY;
        }

        var intersectionX:Array = uniquePointsX;
        var intersectionY:Array = uniquePointsY;
        var intersectionCount:Number = uniquePointsCount;

        if (intersectionCount < 3) {
            return CollisionResult.FALSE;
        }

        // 计算交集多边形面积（无Math.abs）
        var intersectionArea:Number = 0;
        var lenArea:Number = intersectionCount;
        var ii:Number = lenArea - 1;
        for (var iArea:Number = 0; iArea < lenArea; iArea++) {
            intersectionArea += intersectionX[ii] * intersectionY[iArea] - intersectionX[iArea] * intersectionY[ii];
            ii = iArea;
        }
        intersectionArea = (intersectionArea < 0) ? -intersectionArea : intersectionArea; //代替Math.abs

        // 计算自身矩形面积
        var area:Number = (p1.x * p2.y + p2.x * p3.y + p3.x * p4.y + p4.x * p1.y) - (p2.x * p1.y + p3.x * p2.y + p4.x * p3.y + p1.x * p4.y);
        var thisArea:Number = (area < 0) ? -area : area;

        var overlapRatio:Number = intersectionArea / thisArea;

        // 计算最终质心
        var cxCentroid:Number = 0, cyCentroid:Number = 0;
        for (var iCentroid:Number = 0; iCentroid < intersectionCount; iCentroid++) {
            cxCentroid += intersectionX[iCentroid];
            cyCentroid += intersectionY[iCentroid];
        }
        cxCentroid = cxCentroid / intersectionCount;
        cyCentroid = cyCentroid / intersectionCount;

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

        // 内联 pointToGameworld
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
