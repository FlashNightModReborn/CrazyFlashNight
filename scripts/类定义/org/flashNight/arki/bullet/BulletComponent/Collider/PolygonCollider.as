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
    public var _currentFrame:Number; // 当前帧数

    // 定义最大点数量以避免动态push操作，提升性能
    private static var MAX_POINTS:Number = 16;
    
    /**
     * 更新函数引用，用于多态表达当前使用的更新路径
     */
    public var _update:Function;
    /**
     * 用于 aabb 碰撞器的碰撞结果，缓存避免频繁创建
     */
    public static var result:CollisionResult = CollisionResult.Create(true, new Vector(0,0), 1);

    /**
     * 用于 aabb 碰撞器的碰撞交互介质，缓存避免频繁创建
     */
    public static var AABB:AABB = new AABB(null);

    /**
     * 构造函数
     * @param p1 第一个顶点
     * @param p2 第二个顶点
     * @param p3 第三个顶点
     * @param p4 第四个顶点
     */
    public function PolygonCollider(p1:Vector, p2:Vector, p3:Vector, p4:Vector) {
        super(p1 ? p1 : new Vector(0,0), p2 ? p2 : new Vector(0,0),
              p3 ? p3 : new Vector(0,0), p4 ? p4 : new Vector(0,0));
    }

    /**
     * 空构造函数，创建四个(0,0)点。
     */
    public function PolygonCollider_empty() {
        super(new Vector(0, 0), new Vector(0, 0), new Vector(0, 0), new Vector(0, 0));
    }

    /**
     * 获取当前碰撞器的 AABB 信息。
     */
    public function getAABB(zOffset:Number):AABB {
        var aabb = PolygonCollider.AABB;

        // 本地化点坐标
        var p1x:Number = p1.x, p1y:Number = p1.y;
        var p2x:Number = p2.x, p2y:Number = p2.y;
        var p3x:Number = p3.x, p3y:Number = p3.y;
        var p4x:Number = p4.x, p4y:Number = p4.y;

        // --- Left-Right
        if (p1x < p2x) {
            if (p1x < p3x) {
                if (p1x < p4x) {
                    aabb.left = p1x;
                    if (p2x > p3x) {
                        if (p2x > p4x) aabb.right = p2x; else aabb.right = p4x;
                    } else {
                        if (p3x > p4x) aabb.right = p3x; else aabb.right = p4x;
                    }
                } else {
                    aabb.left = p4x;
                    if (p2x > p3x) {
                        if (p2x > p1x) aabb.right = p2x; else aabb.right = p1x;
                    } else {
                        if (p3x > p1x) aabb.right = p3x; else aabb.right = p1x;
                    }
                }
            } else {
                aabb.left = p3x;
                if (p1x > p2x) {
                    if (p1x > p4x) aabb.right = p1x; else aabb.right = p4x;
                } else {
                    if (p2x > p4x) aabb.right = p2x; else aabb.right = p4x;
                }
            }
        } else {
            if (p2x < p3x) {
                if (p2x < p4x) {
                    aabb.left = p2x;
                    if (p1x > p3x) {
                        if (p1x > p4x) aabb.right = p1x; else aabb.right = p4x;
                    } else {
                        if (p3x > p4x) aabb.right = p3x; else aabb.right = p4x;
                    }
                } else {
                    aabb.left = p4x;
                    if (p1x > p3x) {
                        if (p1x > p2x) aabb.right = p1x; else aabb.right = p2x;
                    } else {
                        if (p3x > p2x) aabb.right = p3x; else aabb.right = p2x;
                    }
                }
            } else {
                aabb.left = p3x;
                if (p2x > p1x) {
                    if (p2x > p4x) aabb.right = p2x; else aabb.right = p4x;
                } else {
                    if (p1x > p4x) aabb.right = p1x; else aabb.right = p4x;
                }
            }
        }

        // --- Top-Bottom (adding zOffset)
        if (p1y < p2y) {
            if (p1y < p3y) {
                if (p1y < p4y) {
                    aabb.top = p1y + zOffset;
                    if (p2y > p3y) {
                        if (p2y > p4y) aabb.bottom = p2y + zOffset; else aabb.bottom = p4y + zOffset;
                    } else {
                        if (p3y > p4y) aabb.bottom = p3y + zOffset; else aabb.bottom = p4y + zOffset;
                    }
                } else {
                    aabb.top = p4y + zOffset;
                    if (p2y > p3y) {
                        if (p2y > p1y) aabb.bottom = p2y + zOffset; else aabb.bottom = p1y + zOffset;
                    } else {
                        if (p3y > p1y) aabb.bottom = p3y + zOffset; else aabb.bottom = p1y + zOffset;
                    }
                }
            } else {
                aabb.top = p3y + zOffset;
                if (p1y > p2y) {
                    if (p1y > p4y) aabb.bottom = p1y + zOffset; else aabb.bottom = p4y + zOffset;
                } else {
                    if (p2y > p4y) aabb.bottom = p2y + zOffset; else aabb.bottom = p4y + zOffset;
                }
            }
        } else {
            if (p2y < p3y) {
                if (p2y < p4y) {
                    aabb.top = p2y + zOffset;
                    if (p1y > p3y) {
                        if (p1y > p4y) aabb.bottom = p1y + zOffset; else aabb.bottom = p4y + zOffset;
                    } else {
                        if (p3y > p4y) aabb.bottom = p3y + zOffset; else aabb.bottom = p4y + zOffset;
                    }
                } else {
                    aabb.top = p4y + zOffset;
                    if (p1y > p3y) {
                        if (p1y > p2y) aabb.bottom = p1y + zOffset; else aabb.bottom = p2y + zOffset;
                    } else {
                        if (p3y > p2y) aabb.bottom = p3y + zOffset; else aabb.bottom = p2y + zOffset;
                    }
                }
            } else {
                aabb.top = p3y + zOffset;
                if (p2y > p1y) {
                    if (p2y > p4y) aabb.bottom = p2y + zOffset; else aabb.bottom = p4y + zOffset;
                } else {
                    if (p1y > p4y) aabb.bottom = p1y + zOffset; else aabb.bottom = p4y + zOffset;
                }
            }
        }
        return aabb;
    }

    /**
     * 检查与另一个碰撞体的碰撞。
     * @param other 另一个碰撞体
     * @param zOffset z轴偏移量
     * @return CollisionResult 碰撞结果
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        // 准备存储交点的数组
        var intersectionPointsX:Array = new Array(MAX_POINTS);
        var intersectionPointsY:Array = new Array(MAX_POINTS);
        var intersectionPointsCount:Number = 0;

        var left:Number   = otherAABB.left;
        var right:Number  = otherAABB.right;
        var top:Number    = otherAABB.top;
        var bottom:Number = otherAABB.bottom;

        // 1) 多边形的顶点在 AABB 内部
        intersectionPointsCount = this.addPointIfInsideBox(p1.x, p1.y, left, right, top, bottom,
                                                          intersectionPointsX, intersectionPointsY,
                                                          intersectionPointsCount);
        intersectionPointsCount = this.addPointIfInsideBox(p2.x, p2.y, left, right, top, bottom,
                                                          intersectionPointsX, intersectionPointsY,
                                                          intersectionPointsCount);
        intersectionPointsCount = this.addPointIfInsideBox(p3.x, p3.y, left, right, top, bottom,
                                                          intersectionPointsX, intersectionPointsY,
                                                          intersectionPointsCount);
        intersectionPointsCount = this.addPointIfInsideBox(p4.x, p4.y, left, right, top, bottom,
                                                          intersectionPointsX, intersectionPointsY,
                                                          intersectionPointsCount);

        // 2) 多边形边与 AABB 边的交点
        intersectionPointsCount = this.addEdgeBoxIntersections(p1.x, p1.y, p2.x, p2.y,
                                                               left, right, top, bottom,
                                                               intersectionPointsX, intersectionPointsY, intersectionPointsCount);
        intersectionPointsCount = this.addEdgeBoxIntersections(p2.x, p2.y, p3.x, p3.y,
                                                               left, right, top, bottom,
                                                               intersectionPointsX, intersectionPointsY, intersectionPointsCount);
        intersectionPointsCount = this.addEdgeBoxIntersections(p3.x, p3.y, p4.x, p4.y,
                                                               left, right, top, bottom,
                                                               intersectionPointsX, intersectionPointsY, intersectionPointsCount);
        intersectionPointsCount = this.addEdgeBoxIntersections(p4.x, p4.y, p1.x, p1.y,
                                                               left, right, top, bottom,
                                                               intersectionPointsX, intersectionPointsY, intersectionPointsCount);

        // --- FIX: 3) AABB 的角点在多边形内部
        intersectionPointsCount = this.addBoxCornerIfInPolygon(left, top,
                                                               intersectionPointsX, intersectionPointsY,
                                                               intersectionPointsCount);
        intersectionPointsCount = this.addBoxCornerIfInPolygon(left, bottom,
                                                               intersectionPointsX, intersectionPointsY,
                                                               intersectionPointsCount);
        intersectionPointsCount = this.addBoxCornerIfInPolygon(right, top,
                                                               intersectionPointsX, intersectionPointsY,
                                                               intersectionPointsCount);
        intersectionPointsCount = this.addBoxCornerIfInPolygon(right, bottom,
                                                               intersectionPointsX, intersectionPointsY,
                                                               intersectionPointsCount);

        // 如果交点少于 3 个，则无法形成多边形，返回无碰撞
        if (intersectionPointsCount < 3) {
            return CollisionResult.FALSE;
        }

        // 4) 去重并排序
        var uniqueCount:Number = this.deduplicateAndSort(intersectionPointsX, intersectionPointsY, intersectionPointsCount);

        if (uniqueCount < 3) {
            return CollisionResult.FALSE;
        }

        // 5) 计算交集多边形的面积（Shoelace 公式）
        var intersectionArea:Number = this.shoelaceArea(intersectionPointsX, intersectionPointsY, uniqueCount);

        // 6) 计算多边形自身的面积（Shoelace 公式）
        var polyArea:Number = this.shoelaceArea(
            [p1.x, p2.x, p3.x, p4.x],
            [p1.y, p2.y, p3.y, p4.y],
            4
        );

        // 计算重叠比例
        var ratio:Number = intersectionArea / polyArea;

        // 计算重叠中心
        var cx:Number = 0, cy:Number = 0;
        for (var i:Number = 0; i < uniqueCount; i++) {
            cx += intersectionPointsX[i];
            cy += intersectionPointsY[i];
        }
        cx /= uniqueCount;
        cy /= uniqueCount;

        var collRes:CollisionResult = PolygonCollider.result;
        collRes.overlapCenter.x = cx;
        collRes.overlapCenter.y = cy;
        collRes.overlapRatio = ratio;

        return collRes;
    }


    // ------------------------------------------------------------------------
    // HELPER METHODS
    // ------------------------------------------------------------------------

    /**
     * 如果点在 AABB 内部，则添加到交点数组中。
     */
    private function addPointIfInsideBox(px:Number, py:Number,
                                         left:Number, right:Number, top:Number, bottom:Number,
                                         ix:Array, iy:Array, count:Number):Number {
        if (px >= left && px <= right && py >= top && py <= bottom) {
            ix[count] = px;
            iy[count] = py;
            return count + 1;
        }
        return count;
    }

    /**
     * 添加多边形边与 AABB 边界的交点。
     */
    private function addEdgeBoxIntersections(ax:Number, ay:Number,
                                             bx:Number, by:Number,
                                             left:Number, right:Number,
                                             top:Number, bottom:Number,
                                             ix:Array, iy:Array,
                                             count:Number):Number {
        var dx:Number = bx - ax;
        var dy:Number = by - ay;

        // 避免重复代码，定义一个内联函数
        var addIntersection:Function = function(px:Number, py:Number):Number {
            // 检查交点是否在 AABB 内部
            if (px >= left && px <= right && py >= top && py <= bottom) {
                ix[count] = px;
                iy[count] = py;
                count++;
            }
            return count;
        };

        // 1) 与 x=left 相交
        if (Math.abs(dx) > 1e-9) {
            var t1:Number = (left - ax) / dx; // 参数 t
            if (t1 >= 0 && t1 <= 1) {
                var y1:Number = ay + t1 * dy;
                addIntersection(left, y1);
            }
        }
        // 2) 与 x=right 相交
        if (Math.abs(dx) > 1e-9) {
            var t2:Number = (right - ax) / dx;
            if (t2 >= 0 && t2 <= 1) {
                var y2:Number = ay + t2 * dy;
                addIntersection(right, y2);
            }
        }
        // 3) 与 y=top 相交
        if (Math.abs(dy) > 1e-9) {
            var t3:Number = (top - ay) / dy;
            if (t3 >= 0 && t3 <= 1) {
                var x3:Number = ax + t3 * dx;
                addIntersection(x3, top);
            }
        }
        // 4) 与 y=bottom 相交
        if (Math.abs(dy) > 1e-9) {
            var t4:Number = (bottom - ay) / dy;
            if (t4 >= 0 && t4 <= 1) {
                var x4:Number = ax + t4 * dx;
                addIntersection(x4, bottom);
            }
        }
        return count;
    }

    /**
     * 如果 AABB 的角点在多边形内部，则添加到交点数组中。
     */
    private function addBoxCornerIfInPolygon(bx:Number, by:Number,
                                           ix:Array, iy:Array,
                                           count:Number):Number {
        if (isPointInPolygon(bx, by)) {
            ix[count] = bx;
            iy[count] = by;
            return count + 1;
        }
        return count;
    }

    /**
     * 使用射线投射法判断点是否在多边形内部。
     */
    private function isPointInPolygon(px:Number, py:Number):Boolean {
        var cnt:Number = 0;
        // 检查多边形的每一条边
        cnt += rayIntersectsSegment(px, py, p1.x, p1.y, p2.x, p2.y);
        cnt += rayIntersectsSegment(px, py, p2.x, p2.y, p3.x, p3.y);
        cnt += rayIntersectsSegment(px, py, p3.x, p3.y, p4.x, p4.y);
        cnt += rayIntersectsSegment(px, py, p4.x, p4.y, p1.x, p1.y);

        // 如果交点数为奇数，则点在多边形内部
        return ((cnt % 2) == 1);
    }

    /**
     * 判断水平射线从 (px, py) 向右是否与线段 ((x1, y1)->(x2, y2)) 相交。
     * @return 1 如果相交，0 否则。
     */
    private function rayIntersectsSegment(px:Number, py:Number,
                                          x1:Number, y1:Number,
                                          x2:Number, y2:Number):Number {
        // 确保 y1 <= y2
        if (y1 > y2) {
            var tmpx:Number = x1, tmpy:Number = y1;
            x1 = x2; y1 = y2;
            x2 = tmpx; y2 = tmpy;
        }
        // 如果点的 y 坐标不在线段的 y 范围内，则不相交
        if (py < y1 || py > y2) {
            return 0;
        }
        // 如果线段水平，忽略
        if (Math.abs(y1 - y2) < 1e-9) {
            return 0;
        }

        // 计算射线与线段的交点的 x 坐标
        var t:Number = (py - y1) / (y2 - y1);
        var xint:Number = x1 + t * (x2 - x1);

        // 如果交点在射线的右侧，则计数
        return (xint >= px) ? 1 : 0;
    }

    /**
     * 去除重复的交点并按极角排序。
     * 返回排序后的唯一交点数量。
     */
    private function deduplicateAndSort(ix:Array, iy:Array, n:Number):Number {
        // 1) 去重
        var uniqueMap:Object = {};
        var eps:Number = 0.01;
        var outX:Array = new Array(n);
        var outY:Array = new Array(n);
        var outCount:Number = 0;

        for (var i:Number = 0; i < n; i++) {
            var rx:Number = Math.round(ix[i]/eps)*eps; // 四舍五入以减少浮点数误差
            var ry:Number = Math.round(iy[i]/eps)*eps;
            var key:String = rx + "_" + ry;
            if (!uniqueMap[key]) {
                uniqueMap[key] = true;
                outX[outCount] = rx;
                outY[outCount] = ry;
                outCount++;
            }
        }
        if (outCount < 3) {
            return outCount;
        }

        // 2) 计算质心
        var cx:Number = 0, cy:Number = 0;
        for (i = 0; i < outCount; i++) {
            cx += outX[i];
            cy += outY[i];
        }
        cx /= outCount;
        cy /= outCount;

        // 3) 按极角排序（插入排序）
        var indices:Array = new Array(outCount);
        for (i = 0; i < outCount; i++) {
            indices[i] = i;
        }

        for (var j:Number = 1; j < outCount; j++) {
            var currIndex:Number = indices[j];
            var ax:Number = outX[currIndex] - cx;
            var ay:Number = outY[currIndex] - cy;
            var currAngle:Number = Math.atan2(ay, ax);

            var k:Number = j - 1;
            while (k >= 0) {
                var prevIndex:Number = indices[k];
                var bx:Number = outX[prevIndex] - cx;
                var by:Number = outY[prevIndex] - cy;
                var prevAngle:Number = Math.atan2(by, bx);

                if (currAngle >= prevAngle) break;

                indices[k + 1] = prevIndex;
                k--;
            }

            indices[k + 1] = currIndex;
        }

        // 4) 根据排序后的索引数组重新排列交点
        for (i = 0; i < outCount; i++) {
            var sortedIndex:Number = indices[i];
            ix[i] = outX[sortedIndex];
            iy[i] = outY[sortedIndex];
        }

        return outCount;
    }

    /**
     * 使用 Shoelace 公式计算多边形面积。
     * @return 多边形的绝对面积值。
     */
    private function shoelaceArea(xArr:Array, yArr:Array, len:Number):Number {
        var area:Number = 0;
        var j:Number = len - 1;
        for (var i:Number = 0; i < len; i++) {
            area += (xArr[j] * yArr[i] - yArr[j] * xArr[i]);
            j = i;
        }
        if (area < 0) area = -area;
        return area;
    }

    // ------------------------------------------------------------------------
    // UPDATE METHODS (保持不变)
    // ------------------------------------------------------------------------
    /**
     * 更新为透明子弹，直接修改 p1, p2, p3, p4 的 x, y 坐标。
     * @param bullet 子弹对象，包含 _x 和 _y 属性
     */
    public function updateFromTransparentBullet(bullet:Object):Void {
        p1.x = bullet._x - 12.5; p1.y = bullet._y - 12.5;
        p2.x = bullet._x + 12.5; p2.y = bullet._y - 12.5;
        p3.x = bullet._x + 12.5; p3.y = bullet._y + 12.5;
        p4.x = bullet._x - 12.5; p4.y = bullet._y + 12.5;
    }

    /**
     * 从子弹和检测区域更新多边形的顶点。
     * @param bullet 子弹 MovieClip
     * @param detectionArea 检测区域 MovieClip
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var frame:Number = _root.帧计时器.当前帧数; // 获取当前帧数
        if (this._currentFrame == frame) // 如果已在当前帧更新，跳过
            return;
        this._currentFrame = frame; // 更新当前帧数

        var rect:Object = detectionArea.getRect(detectionArea); // 获取检测区域的矩形边界

        // 转换点到游戏世界坐标
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
        var vx:Number = p1gw.x - centerX; // 计算向量 x 分量
        var vy:Number = p1gw.y - centerY; // 计算向量 y 分量
        var angle:Number = Math.atan2(vy, vx); // 计算向量角度
        var length:Number = Math.sqrt(vx * vx + vy * vy); // 计算向量长度
        var cosVal:Number = length * Math.cos(angle); // 计算 cos 值
        var sinVal:Number = length * Math.sin(angle); // 计算 sin 值

        // 更新多边形顶点
        p1.x = p1gw.x; p1.y = p1gw.y;
        p3.x = p3gw.x; p3.y = p3gw.y;
        p2.x = centerX + cosVal; p2.y = centerY - sinVal;
        p4.x = centerX - cosVal; p4.y = centerY + sinVal;
    }

    /**
     * 从单位区域更新多边形的顶点。
     * @param unit 单位 MovieClip
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
