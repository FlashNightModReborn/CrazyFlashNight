import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * PolygonCollider 类用于检测多边形与另一个碰撞体之间的碰撞。
 * 该类继承自 RectanglePointSet，并实现了 ICollider 接口。
 * 
 * 优化点：
 * 1. 内联展开碰撞检测逻辑，减少函数调用开销。
 * 2. 消除冗余计算，如固定值的乘法和减法。
 * 3. 合并副作用操作，如使用后置递增运算符 `++`。
 * 4. 使用并行数组管理交点，避免动态数组操作。
 * 5. 使用位运算生成唯一键，加快去重过程。
 */
class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider extends RectanglePointSet implements ICollider {
    public var _factory:AbstractColliderFactory; // 碰撞工厂
    public var _update:Function; // 更新函数
    public var _currentFrame:Number; // 当前帧数

    // 定义最大点数量以避免动态push操作，提升性能
    // 矩形点集与aabb进行碰撞检测正常来说会返回3-8个交点，最多16个，因此选择8作为阈值
    private static var MAX_POINTS:Number = 8;

    /**
     * 构造函数
     * @param p1 第一个顶点
     * @param p2 第二个顶点
     * @param p3 第三个顶点
     * @param p4 第四个顶点
     * 如果传入为null，则自动创建四个(0,0)点以保证数据结构完整。
     */
    public function PolygonCollider(p1:Vector, p2:Vector, p3:Vector, p4:Vector) {
        super(p1 ? p1 : new Vector(0, 0), p2 ? p2 : new Vector(0, 0), p3 ? p3 : new Vector(0, 0), p4 ? p4 : new Vector(0, 0));
    }

    /**
     * 空构造函数，创建四个(0,0)点。
     */
    public function PolygonCollider_empty() {
        super(new Vector(0, 0), new Vector(0, 0), new Vector(0, 0), new Vector(0, 0));
    }

    /**
     * 获取包围盒（AABB），并应用z轴偏移。
     * @param zOffset z轴偏移量
     * @return AABB 对象
     */
    public function getAABB(zOffset:Number):AABB {
        var box:AABB = super.getBoundingBox();
        return new AABB(box.left, box.right, box.top + zOffset, box.bottom + zOffset);
    }

    /**
     * 检查与另一个碰撞体的碰撞。
     * @param other 另一个碰撞体
     * @param zOffset z轴偏移量
     * @return CollisionResult 碰撞结果
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset); // 获取另一个碰撞体的AABB

        /*

        // AABB快速剔除：如果两个AABB不重叠，则无需进一步检测
        var box:AABB = this.getBoundingBox();
        if (box.right <= otherAABB.left || box.left >= otherAABB.right || box.bottom <= otherAABB.top || box.top >= otherAABB.bottom) {
            return CollisionResult.FALSE;
        }

        // 预筛选已在外部完成，因此不需要额外做快速剔除

        */

        // 使用并行数组管理交点，预扩容以提高性能
        var intersectionPointsX:Array = new Array(MAX_POINTS);
        var intersectionPointsY:Array = new Array(MAX_POINTS);
        var intersectionPointsCount:Number = 0; // 记录交点数量

        var px:Number, py:Number; // 临时变量，用于存储顶点坐标

        // 获取AABB的边界值，简化后续计算
        var left:Number   = otherAABB.left;
        var right:Number  = otherAABB.right;
        var top:Number    = otherAABB.top;
        var bottom:Number = otherAABB.bottom;

        // 检查多边形自身四个顶点是否在AABB内，如果在则添加为交点
        // 使用多个简单的if语句替代一个复杂的if条件，以提升AS2中的性能

        // 检查顶点p1
        px = p1.x; 
        py = p1.y;
        if (px >= left) {             // 第一个条件：x坐标不小于AABB左边界
            if (px <= right) {        // 第二个条件：x坐标不大于AABB右边界
                if (py >= top) {       // 第三个条件：y坐标不小于AABB上边界
                    if (py <= bottom) { // 第四个条件：y坐标不大于AABB下边界
                        // 如果所有条件都满足，则将p1作为交点添加到交点数组中
                        intersectionPointsX[intersectionPointsCount] = px;
                        intersectionPointsY[intersectionPointsCount++] = py; // 合并递增操作，减少指令数
                    }
                }
            }
        }

        // 检查顶点p2
        px = p2.x; 
        py = p2.y;
        if (px >= left) {             // 第一个条件：x坐标不小于AABB左边界
            if (px <= right) {        // 第二个条件：x坐标不大于AABB右边界
                if (py >= top) {       // 第三个条件：y坐标不小于AABB上边界
                    if (py <= bottom) { // 第四个条件：y坐标不大于AABB下边界
                        // 如果所有条件都满足，则将p2作为交点添加到交点数组中
                        intersectionPointsX[intersectionPointsCount] = px;
                        intersectionPointsY[intersectionPointsCount++] = py;
                    }
                }
            }
        }

        // 检查顶点p3
        px = p3.x; 
        py = p3.y;
        if (px >= left) {             // 第一个条件：x坐标不小于AABB左边界
            if (px <= right) {        // 第二个条件：x坐标不大于AABB右边界
                if (py >= top) {       // 第三个条件：y坐标不小于AABB上边界
                    if (py <= bottom) { // 第四个条件：y坐标不大于AABB下边界
                        // 如果所有条件都满足，则将p3作为交点添加到交点数组中
                        intersectionPointsX[intersectionPointsCount] = px;
                        intersectionPointsY[intersectionPointsCount++] = py;
                    }
                }
            }
        }

        // 检查顶点p4
        px = p4.x; 
        py = p4.y;
        if (px >= left) {             // 第一个条件：x坐标不小于AABB左边界
            if (px <= right) {        // 第二个条件：x坐标不大于AABB右边界
                if (py >= top) {       // 第三个条件：y坐标不小于AABB上边界
                    if (py <= bottom) { // 第四个条件：y坐标不大于AABB下边界
                        // 如果所有条件都满足，则将p4作为交点添加到交点数组中
                        intersectionPointsX[intersectionPointsCount] = px;
                        intersectionPointsY[intersectionPointsCount++] = py;
                    }
                }
            }
        }


        var ax:Number, ay:Number, bx:Number, by:Number; // 线段起点和终点
        var interX:Number, interY:Number; // 交点坐标
        var denom:Number, ua:Number, ub:Number; // 计算参数
        var w:Number = (right - left); // AABB宽度
        var h:Number = (bottom - top); // AABB高度

        /**
         * 优化后的相交计算逻辑：
         * 处理多边形的四条边（p1->p2, p2->p3, p3->p4, p4->p1）与AABB的四条边（x=left, x=right, y=top, y=bottom）的相交检测。
         * 通过内联展开和消除冗余计算，减少运算量和指令数。
         */

        // 边：p1->p2
        ax = p1.x; ay = p1.y;
        bx = p2.x; by = p2.y;

        // 与左边相交（x = left）
        denom = h * (bx - ax); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = -(h * (ax - left)) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与右边相交（x = right）
        // denom同上为 h * (bx - ax)
        if (denom != 0) {
            ua = ((w * (ay - top) - h * (ax - left))) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与上边相交（y = top）
        denom = -w * (by - ay); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = 0; // 因为与上边相关的项为0，直接设ua为0
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ub >= 0 && ub <= 1) { // 只需要检查ub是否在有效范围内
                interX = ax; // ua=0时，交点X坐标为ax
                interY = ay; // ua=0时，交点Y坐标为ay
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与下边相交（y = bottom）
        denom = -w * (by - ay); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = -((bottom - top) * (ax - left)) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 边：p2->p3
        ax = p2.x; ay = p2.y;
        bx = p3.x; by = p3.y;

        // 与左边相交（x = left）
        denom = h * (bx - ax); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = -(h * (ax - left)) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与右边相交（x = right）
        // denom同上为 h * (bx - ax)
        if (denom != 0) {
            ua = ((w * (ay - top) - h * (ax - left))) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与上边相交（y = top）
        denom = -w * (by - ay); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = 0; // 因为与上边相关的项为0，直接设ua为0
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ub >= 0 && ub <= 1) { // 只需要检查ub是否在有效范围内
                interX = ax; // ua=0时，交点X坐标为ax
                interY = ay; // ua=0时，交点Y坐标为ay
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与下边相交（y = bottom）
        denom = -w * (by - ay); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = -((bottom - top) * (ax - left)) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 边：p3->p4
        ax = p3.x; ay = p3.y;
        bx = p4.x; by = p4.y;

        // 与左边相交（x = left）
        denom = h * (bx - ax); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = -(h * (ax - left)) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与右边相交（x = right）
        // denom同上为 h * (bx - ax)
        if (denom != 0) {
            ua = ((w * (ay - top) - h * (ax - left))) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与上边相交（y = top）
        denom = -w * (by - ay); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = 0; // 因为与上边相关的项为0，直接设ua为0
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ub >= 0 && ub <= 1) { // 只需要检查ub是否在有效范围内
                interX = ax; // ua=0时，交点X坐标为ax
                interY = ay; // ua=0时，交点Y坐标为ay
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        // 与下边相交（y = bottom）
        denom = -w * (by - ay); // 分母计算，简化后的形式
        if (denom != 0) {
            ua = -((bottom - top) * (ax - left)) / denom; // 计算ua
            ub = ((bx - ax) * (ay - top) - (by - ay) * (ax - left)) / denom; // 计算ub
            if (ua >= 0 && ua <= 1 && ub >= 0 && ub <= 1) { // 检查参数是否在有效范围内
                interX = ax + ua * (bx - ax); // 计算交点X坐标
                interY = ay + ua * (by - ay); // 计算交点Y坐标
                // 检查交点是否在AABB内部
                if (interX >= left && interX <= right && interY >= top && interY <= bottom) {
                    intersectionPointsX[intersectionPointsCount] = interX;
                    intersectionPointsY[intersectionPointsCount++] = interY;
                }
            }
        }

        /**
         * 去除重复的交点
         * 使用对象映射(uniqueMap)来记录已存在的交点，通过位运算生成唯一键加快查找速度。
         * 使用并行数组uniquePointsX和uniquePointsY来存储唯一交点，避免动态数组操作。
         */
        var uniqueMap:Object = {}; // 用于记录唯一交点
        var uniquePointsX:Array = new Array(MAX_POINTS);
        var uniquePointsY:Array = new Array(MAX_POINTS);
        var uniquePointsCount:Number = 0; // 记录唯一交点数量
        var eps:Number = 0.00001; // 精度，用于四舍五入

        for (var u:Number = 0; u < intersectionPointsCount; u++) {
            px = intersectionPointsX[u];
            py = intersectionPointsY[u];

            // 对交点坐标进行四舍五入，减少浮点数精度带来的重复
            var val:Number = px / eps;
            val = (val >= 0 ? val + 0.5 : val - 0.5) - (val % 1); // 四舍五入并去掉小数部分
            var roundedX:Number = val * eps;

            val = py / eps;
            val = (val >= 0 ? val + 0.5 : val - 0.5) - (val % 1); // 四舍五入并去掉小数部分
            var roundedY:Number = val * eps;

            // 使用位运算生成唯一键
            var key:Number = (roundedX << 16) | (roundedY & 0xFFFF);
            if (!uniqueMap[key]) { // 如果该键尚未存在，则添加到唯一交点数组
                uniqueMap[key] = true;
                uniquePointsX[uniquePointsCount] = px;
                uniquePointsY[uniquePointsCount++] = py;
            }
        }

        var intersectionCount:Number = uniquePointsCount; // 更新交点数量

        // 如果唯一交点少于3个，则无法形成多边形，返回无碰撞
        if (intersectionCount < 3) {
            return CollisionResult.FALSE;
        } else {
            /**
             * 计算质心
             * 通过所有交点的平均位置来确定质心，用于后续计算重叠率和重叠中心。
             */
            var cx:Number = 0, cy:Number = 0;
            for (var m:Number = 0; m < uniquePointsCount; m++) {
                cx += uniquePointsX[m];
                cy += uniquePointsY[m];
            }
            cx = cx / uniquePointsCount;
            cy = cy / uniquePointsCount;

            /**
             * 对交点按极角进行插入排序
             * 由于没有对象数组，使用索引数组(indices)来记录排序后的顺序。
             */
            var indices:Array = new Array(uniquePointsCount);
            for (var idx:Number = 0; idx < uniquePointsCount; idx++) {
                indices[idx] = idx; // 初始化索引数组
            }

            // 使用插入排序对索引数组进行排序，根据交点相对于质心的极角
            for (var i:Number = 1; i < uniquePointsCount; i++) {
                var current:Number = indices[i];
                var axSort:Number = uniquePointsX[current];
                var aySort:Number = uniquePointsY[current];

                // 计算当前点的极角
                var currentAngle:Number = Math.atan2(aySort - cy, axSort - cx);

                var j:Number = i - 1;
                while (j >= 0) {
                    var previous:Number = indices[j];
                    var bxSort:Number = uniquePointsX[previous];
                    var bySort:Number = uniquePointsY[previous];

                    // 计算前一个点的极角
                    var previousAngle:Number = Math.atan2(bySort - cy, bxSort - cx);

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

            // 根据排序后的索引数组，重排交点数组
            var sortedX:Array = new Array(uniquePointsCount);
            var sortedY:Array = new Array(uniquePointsCount);
            for (var s:Number = 0; s < uniquePointsCount; s++) {
                var ii:Number = indices[s];
                sortedX[s] = uniquePointsX[ii];
                sortedY[s] = uniquePointsY[ii];
            }
            uniquePointsX = sortedX;
            uniquePointsY = sortedY;
        }

        intersectionCount = uniquePointsCount; // 更新交点数量
        if (intersectionCount < 3) {
            return CollisionResult.FALSE; // 交点少于3个，无法形成多边形
        }

        /**
         * 计算交集多边形面积
         * 使用多边形面积计算公式（Shoelace公式）。
         * 不使用 Math.abs，而是手动取绝对值以替代。
         */
        var intersectionArea:Number = 0;
        var lenArea:Number = intersectionCount;
        var iiArea:Number = lenArea - 1; // 初始化为最后一个点的索引
        for (var iArea:Number = 0; iArea < lenArea; iArea++) {
            intersectionArea += uniquePointsX[iiArea] * uniquePointsY[iArea] - uniquePointsX[iArea] * uniquePointsY[iiArea];
            iiArea = iArea; // 更新上一点的索引
        }
        intersectionArea = (intersectionArea < 0) ? -intersectionArea : intersectionArea; // 手动取绝对值

        /**
         * 计算自身矩形面积
         * 使用多边形面积计算公式（Shoelace公式）。
         */
        var area:Number = (p1.x * p2.y + p2.x * p3.y + p3.x * p4.y + p4.x * p1.y) - (p2.x * p1.y + p3.x * p2.y + p4.x * p3.y + p1.x * p4.y);
        var thisArea:Number = (area < 0) ? -area : area; // 手动取绝对值

        var overlapRatio:Number = intersectionArea / thisArea; // 计算重叠比例

        /**
         * 计算最终质心
         * 通过所有交点的平均位置来确定重叠区域的质心。
         */
        var cxCentroid:Number = 0, cyCentroid:Number = 0;
        for (var iCentroid:Number = 0; iCentroid < intersectionCount; iCentroid++) {
            cxCentroid += uniquePointsX[iCentroid];
            cyCentroid += uniquePointsY[iCentroid];
        }
        cxCentroid = cxCentroid / intersectionCount;
        cyCentroid = cyCentroid / intersectionCount;

        var overlapCenter:Vector = new Vector(cxCentroid, cyCentroid); // 创建重叠中心向量

        // 创建并返回碰撞结果
        var result:CollisionResult = new CollisionResult(true);

        result.overlapRatio = overlapRatio; // 设置重叠比例
        result.overlapCenter = overlapCenter; // 设置重叠中心
        return result;
    }

    /**
     * 更新为透明子弹，直接修改p1, p2, p3, p4的x, y坐标。
     * @param bullet 子弹对象，包含_x和_y属性
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        p1.x = bullet._x - 12.5; p1.y = bullet._y - 12.5;
        p2.x = bullet._x + 12.5; p2.y = bullet._y - 12.5;
        p3.x = bullet._x + 12.5; p3.y = bullet._y + 12.5;
        p4.x = bullet._x - 12.5; p4.y = bullet._y + 12.5;
    }

    /**
     * 从子弹和检测区域更新多边形的顶点。
     * @param bullet 子弹MovieClip
     * @param detectionArea 检测区域MovieClip
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var frame:Number = _root.帧计时器.当前帧数; // 获取当前帧数
        if (this._currentFrame == frame) // 如果已在当前帧更新，跳过
            return;
        this._currentFrame = frame; // 更新当前帧数
        var rect:Object = detectionArea.getRect(detectionArea); // 获取检测区域的矩形边界

        // 内联转换点到游戏世界坐标
        var pt:Object = {x: rect.xMax, y: rect.yMax};
        detectionArea.localToGlobal(pt); // 本地坐标转换到全局坐标
        _root.gameworld.globalToLocal(pt); // 全局坐标转换到游戏世界坐标
        var p1gw:Vector = new Vector(pt.x, pt.y); // 创建顶点1

        pt = {x: rect.xMin, y: rect.yMin};
        detectionArea.localToGlobal(pt); // 本地坐标转换到全局坐标
        _root.gameworld.globalToLocal(pt); // 全局坐标转换到游戏世界坐标
        var p3gw:Vector = new Vector(pt.x, pt.y); // 创建顶点3

        // 计算中心点
        var centerX:Number = (p1gw.x + p3gw.x) * 0.5;
        var centerY:Number = (p1gw.y + p3gw.y) * 0.5;
        var vx:Number = p1gw.x - centerX; // 计算向量x分量
        var vy:Number = p1gw.y - centerY; // 计算向量y分量
        var angle:Number = Math.atan2(vy, vx); // 计算向量角度
        var length:Number = Math.sqrt(vx * vx + vy * vy); // 计算向量长度
        var cosVal:Number = length * Math.cos(angle); // 计算cos值
        var sinVal:Number = length * Math.sin(angle); // 计算sin值

        // 更新多边形顶点
        p1.x = p1gw.x; p1.y = p1gw.y;
        p3.x = p3gw.x; p3.y = p3gw.y;
        p2.x = centerX + cosVal; p2.y = centerY - sinVal;
        p4.x = centerX - cosVal; p4.y = centerY + sinVal;
    }

    /**
     * 从单位区域更新多边形的顶点。
     * @param unit 单位MovieClip
     */
    public function updateFromUnitArea(unit:MovieClip):Void {
        var frame:Number = _root.帧计时器.当前帧数; // 获取当前帧数
        if (this._currentFrame == frame) // 如果已在当前帧更新，跳过
            return;
        this._currentFrame = frame; // 更新当前帧数

        var unitRect:Object = unit.area.getRect(_root.gameworld); // 获取单位区域的矩形边界

        // 更新多边形顶点
        p1.x = unitRect.xMin; p1.y = unitRect.yMin;
        p2.x = unitRect.xMax; p2.y = unitRect.yMin;
        p3.x = unitRect.xMax; p3.y = unitRect.yMax;
        p4.x = unitRect.xMin; p4.y = unitRect.yMax;
    }

    /**
     * 设置碰撞工厂。
     * @param factory AbstractColliderFactory 对象
     */
    public function setFactory(factory:AbstractColliderFactory):Void {
        this._factory = factory;
    }

    /**
     * 获取碰撞工厂。
     * @return AbstractColliderFactory 对象
     */
    public function getFactory():AbstractColliderFactory {
        return this._factory;
    }
}
