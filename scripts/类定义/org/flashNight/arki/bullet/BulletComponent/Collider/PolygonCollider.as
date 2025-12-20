import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.sara.util.*;

/**
 * PolygonCollider 类用于检测凸四边形与另一个碰撞体之间的碰撞。
 * 该类继承自 RectanglePointSet，并实现了 ICollider 接口。
 *
 * 设计约束：
 * - 本碰撞器假设多边形为凸四边形，顶点按顺时针或逆时针顺序排列
 * - 其他碰撞器通过 getAABB() 退化为 AABB，因此交集多边形最多 4+4+8=16 个顶点
 *   （4个多边形顶点 + 4个AABB角点 + 每条边最多2个交点×4条边）
 *
 * 性能优化：
 * 1. 零分配碰撞路径：使用实例级缓存数组，避免运行时内存分配
 * 2. 无闭包：边界交点计算完全内联展开
 * 3. O(n²) 距离平方去重：替代 Object + String key 哈希，无字符串分配
 * 4. 角度预计算：atan2 只调用 O(n) 次，排序时直接查表
 * 5. 凸多边形同侧测试：用 4 次叉积替代射线法，无除法
 */

class org.flashNight.arki.bullet.BulletComponent.Collider.PolygonCollider extends RectanglePointSet implements ICollider {
    public var _factory:AbstractColliderFactory; // 碰撞工厂
    public var _currentFrame:Number; // 当前帧数

    /**
     * 交集多边形的最大顶点数量。
     *
     * 计算依据（凸四边形 vs AABB 的交集）：
     * - 多边形顶点在 AABB 内：最多 4 个
     * - AABB 角点在多边形内：最多 4 个
     * - 多边形边与 AABB 边交点：4 条边 × 最多 2 个交点 = 8 个
     * - 合计：4 + 4 + 8 = 16 个顶点
     *
     * 此值用于预分配缓存数组，保证零运行时分配。
     */
    private static var MAX_POINTS:Number = 16;

    // ========== 实例级缓存数组，实现零分配碰撞路径 ==========
    private var _ix:Array;      // 交点 X 坐标缓存
    private var _iy:Array;      // 交点 Y 坐标缓存
    private var _tmpX:Array;    // 去重临时 X 坐标
    private var _tmpY:Array;    // 去重临时 Y 坐标
    private var _idx:Array;     // 排序用索引数组
    private var _ang:Array;     // 预计算的极角缓存
    private var _polyX:Array;   // 多边形顶点 X（用于 shoelaceArea）
    private var _polyY:Array;   // 多边形顶点 Y（用于 shoelaceArea）

    /**
     * 去重用的距离阈值平方。
     * 两点距离平方小于此值视为重复点。
     * 值 0.0001 对应线性距离 0.01 像素。
     */
    private static var DEDUP_EPS_SQ:Number = 0.0001;

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
        // 初始化缓存数组（一次性分配，后续复用）
        initCacheArrays();
    }

    /**
     * 空构造函数，创建四个(0,0)点。
     */
    public function PolygonCollider_empty() {
        super(new Vector(0, 0), new Vector(0, 0), new Vector(0, 0), new Vector(0, 0));
        initCacheArrays();
    }

    /**
     * 初始化缓存数组，避免在碰撞检测时频繁分配内存
     */
    private function initCacheArrays():Void {
        _ix = new Array(MAX_POINTS);
        _iy = new Array(MAX_POINTS);
        _tmpX = new Array(MAX_POINTS);
        _tmpY = new Array(MAX_POINTS);
        _idx = new Array(MAX_POINTS);
        _ang = new Array(MAX_POINTS);
        _polyX = [0, 0, 0, 0];
        _polyY = [0, 0, 0, 0];
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
     *
     * ========== 性能优化说明 ==========
     * P0: 零分配路径 - 使用实例级缓存数组 _ix/_iy/_tmpX/_tmpY/_idx/_ang/_polyX/_polyY
     * P0: 去除闭包 - addEdgeBoxIntersections 中的交点添加逻辑直接内联
     * P1: O(n²) 去重 - 不使用 Object + String key，直接距离比较
     * P1: 角度预计算 - atan2 只调用一次，存入 _ang 数组
     * P1: 凸多边形同侧测试 - 用 cross product 替代射线法判断点在多边形内
     *
     * @param other 另一个碰撞体
     * @param zOffset z轴偏移量
     * @return CollisionResult 碰撞结果
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        // 使用实例级缓存数组（零分配）
        var ix:Array = _ix;
        var iy:Array = _iy;
        var count:Number = 0;

        var left:Number   = otherAABB.left;
        var right:Number  = otherAABB.right;
        var top:Number    = otherAABB.top;
        var bottom:Number = otherAABB.bottom;

        // 本地化多边形顶点坐标
        var p1x:Number = p1.x, p1y:Number = p1.y;
        var p2x:Number = p2.x, p2y:Number = p2.y;
        var p3x:Number = p3.x, p3y:Number = p3.y;
        var p4x:Number = p4.x, p4y:Number = p4.y;

        // ========== 1) 多边形的顶点在 AABB 内部（内联展开） ==========
        if (p1x >= left && p1x <= right && p1y >= top && p1y <= bottom) {
            ix[count] = p1x; iy[count] = p1y; count++;
        }
        if (p2x >= left && p2x <= right && p2y >= top && p2y <= bottom) {
            ix[count] = p2x; iy[count] = p2y; count++;
        }
        if (p3x >= left && p3x <= right && p3y >= top && p3y <= bottom) {
            ix[count] = p3x; iy[count] = p3y; count++;
        }
        if (p4x >= left && p4x <= right && p4y >= top && p4y <= bottom) {
            ix[count] = p4x; iy[count] = p4y; count++;
        }

        // ========== 2) 多边形边与 AABB 边的交点（内联展开，无闭包） ==========
        // 边 p1->p2
        count = addEdgeBoxIntersectionsInline(p1x, p1y, p2x, p2y, left, right, top, bottom, ix, iy, count);
        // 边 p2->p3
        count = addEdgeBoxIntersectionsInline(p2x, p2y, p3x, p3y, left, right, top, bottom, ix, iy, count);
        // 边 p3->p4
        count = addEdgeBoxIntersectionsInline(p3x, p3y, p4x, p4y, left, right, top, bottom, ix, iy, count);
        // 边 p4->p1
        count = addEdgeBoxIntersectionsInline(p4x, p4y, p1x, p1y, left, right, top, bottom, ix, iy, count);

        // ========== 3) AABB 的角点在多边形内部（凸多边形同侧测试） ==========
        // 预计算边向量的叉积符号（用于判断点在凸多边形内）
        // 边1: p1->p2, 边2: p2->p3, 边3: p3->p4, 边4: p4->p1
        var e1x:Number = p2x - p1x, e1y:Number = p2y - p1y;
        var e2x:Number = p3x - p2x, e2y:Number = p3y - p2y;
        var e3x:Number = p4x - p3x, e3y:Number = p4y - p3y;
        var e4x:Number = p1x - p4x, e4y:Number = p1y - p4y;

        // 左上角 (left, top)
        if (isPointInConvexQuad(left, top, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y, e1x, e1y, e2x, e2y, e3x, e3y, e4x, e4y)) {
            ix[count] = left; iy[count] = top; count++;
        }
        // 左下角 (left, bottom)
        if (isPointInConvexQuad(left, bottom, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y, e1x, e1y, e2x, e2y, e3x, e3y, e4x, e4y)) {
            ix[count] = left; iy[count] = bottom; count++;
        }
        // 右上角 (right, top)
        if (isPointInConvexQuad(right, top, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y, e1x, e1y, e2x, e2y, e3x, e3y, e4x, e4y)) {
            ix[count] = right; iy[count] = top; count++;
        }
        // 右下角 (right, bottom)
        if (isPointInConvexQuad(right, bottom, p1x, p1y, p2x, p2y, p3x, p3y, p4x, p4y, e1x, e1y, e2x, e2y, e3x, e3y, e4x, e4y)) {
            ix[count] = right; iy[count] = bottom; count++;
        }

        // 如果交点少于 3 个，则无法形成多边形，返回无碰撞
        if (count < 3) {
            return CollisionResult.FALSE;
        }

        // ========== 4) 去重并排序（O(n²) 无分配版本） ==========
        var uniqueCount:Number = deduplicateAndSortOptimized(ix, iy, count);

        if (uniqueCount < 3) {
            return CollisionResult.FALSE;
        }

        // ========== 5) 计算交集多边形的面积（Shoelace 公式，直接使用缓存数组） ==========
        var intersectionArea:Number = shoelaceAreaDirect(ix, iy, uniqueCount);

        // ========== 6) 计算多边形自身的面积（使用缓存数组，避免临时数组字面量） ==========
        _polyX[0] = p1x; _polyX[1] = p2x; _polyX[2] = p3x; _polyX[3] = p4x;
        _polyY[0] = p1y; _polyY[1] = p2y; _polyY[2] = p3y; _polyY[3] = p4y;
        var polyArea:Number = shoelaceAreaDirect(_polyX, _polyY, 4);

        // 计算重叠比例
        var ratio:Number = intersectionArea / polyArea;

        // 计算重叠中心
        var cx:Number = 0, cy:Number = 0;
        for (var i:Number = 0; i < uniqueCount; i++) {
            cx += ix[i];
            cy += iy[i];
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
    // HELPER METHODS (优化版本 - 零分配、无闭包、无字符串哈希)
    // ------------------------------------------------------------------------

    /**
     * P0 优化：添加多边形边与 AABB 边界的交点（内联展开，无闭包）
     * 直接将交点添加逻辑展开，避免闭包分配和函数调用开销
     */
    private function addEdgeBoxIntersectionsInline(ax:Number, ay:Number,
                                                    bx:Number, by:Number,
                                                    left:Number, right:Number,
                                                    top:Number, bottom:Number,
                                                    ix:Array, iy:Array,
                                                    count:Number):Number {
        var dx:Number = bx - ax;
        var dy:Number = by - ay;
        var t:Number, px:Number, py:Number;

        // 预计算 dx/dy 是否为零（只计算一次）
        var dxNonZero:Boolean = (dx > 1e-9 || dx < -1e-9);
        var dyNonZero:Boolean = (dy > 1e-9 || dy < -1e-9);

        // 1) 与 x=left 相交
        if (dxNonZero) {
            t = (left - ax) / dx;
            if (t >= 0 && t <= 1) {
                py = ay + t * dy;
                // 内联检查：交点是否在 AABB 内
                if (py >= top && py <= bottom) {
                    ix[count] = left;
                    iy[count] = py;
                    count++;
                }
            }
            // 2) 与 x=right 相交
            t = (right - ax) / dx;
            if (t >= 0 && t <= 1) {
                py = ay + t * dy;
                if (py >= top && py <= bottom) {
                    ix[count] = right;
                    iy[count] = py;
                    count++;
                }
            }
        }

        // 3) 与 y=top 相交
        if (dyNonZero) {
            t = (top - ay) / dy;
            if (t >= 0 && t <= 1) {
                px = ax + t * dx;
                // 内联检查：交点是否在 AABB 内
                if (px >= left && px <= right) {
                    ix[count] = px;
                    iy[count] = top;
                    count++;
                }
            }
            // 4) 与 y=bottom 相交
            t = (bottom - ay) / dy;
            if (t >= 0 && t <= 1) {
                px = ax + t * dx;
                if (px >= left && px <= right) {
                    ix[count] = px;
                    iy[count] = bottom;
                    count++;
                }
            }
        }

        return count;
    }

    /**
     * 凸四边形点在内判定（cross product 同侧测试）
     *
     * 算法原理：
     * 对于凸多边形，点在内部当且仅当点相对于所有边都在同一侧。
     * 通过计算点相对于每条边的叉积符号来判断。
     *
     * 前提条件（调用方必须保证）：
     * 1. 四边形必须是凸的（所有内角 < 180°）
     * 2. 顶点 v1->v2->v3->v4 必须按一致的顺序排列（全顺时针或全逆时针）
     * 3. 边向量 e1/e2/e3/e4 必须与顶点顺序匹配：
     *    e1 = v2 - v1, e2 = v3 - v2, e3 = v4 - v3, e4 = v1 - v4
     *
     * 边界行为：
     * 使用严格不等式（> 和 <），边界上的点返回 false。
     * 这与"边缘接触不算碰撞"的测试语义一致。
     *
     * 性能：4 次叉积（乘加），无除法，无分支预测失败风险
     *
     * @return true 如果点严格在凸四边形内部，false 如果在边界上或外部
     */
    private function isPointInConvexQuad(px:Number, py:Number,
                                          v1x:Number, v1y:Number,
                                          v2x:Number, v2y:Number,
                                          v3x:Number, v3y:Number,
                                          v4x:Number, v4y:Number,
                                          e1x:Number, e1y:Number,
                                          e2x:Number, e2y:Number,
                                          e3x:Number, e3y:Number,
                                          e4x:Number, e4y:Number):Boolean {
        // cross = edge × (point - vertex) = edge.x * (py - vy) - edge.y * (px - vx)
        // 若 cross > 0：点在边的左侧（逆时针方向）
        // 若 cross < 0：点在边的右侧（顺时针方向）
        // 若 cross = 0：点在边上

        var c1:Number = e1x * (py - v1y) - e1y * (px - v1x);
        var c2:Number = e2x * (py - v2y) - e2y * (px - v2x);
        var c3:Number = e3x * (py - v3y) - e3y * (px - v3x);
        var c4:Number = e4x * (py - v4y) - e4y * (px - v4x);

        // 所有叉积同号 => 点在凸多边形内部
        // 严格不等式排除边界点
        if (c1 > 0 && c2 > 0 && c3 > 0 && c4 > 0) return true;
        if (c1 < 0 && c2 < 0 && c3 < 0 && c4 < 0) return true;

        return false;
    }

    /**
     * P1 优化：去重并排序（O(n²) 无分配版本）
     * - 使用距离平方比较替代字符串哈希
     * - 预计算角度存入缓存数组
     * - 直接在原数组上操作
     */
    private function deduplicateAndSortOptimized(ix:Array, iy:Array, n:Number):Number {
        var tmpX:Array = _tmpX;
        var tmpY:Array = _tmpY;
        var idx:Array = _idx;
        var ang:Array = _ang;
        var epsSq:Number = DEDUP_EPS_SQ;

        // ========== 1) O(n²) 去重（无字符串、无Object分配） ==========
        var outCount:Number = 0;
        var i:Number, j:Number;
        var x:Number, y:Number, dx:Number, dy:Number;
        var dup:Boolean;

        for (i = 0; i < n; i++) {
            x = ix[i];
            y = iy[i];
            dup = false;

            // 检查是否与已有的唯一点重复
            for (j = 0; j < outCount; j++) {
                dx = x - tmpX[j];
                dy = y - tmpY[j];
                // 使用距离平方比较，避免 sqrt
                if (dx * dx + dy * dy < epsSq) {
                    dup = true;
                    break;
                }
            }

            if (!dup) {
                tmpX[outCount] = x;
                tmpY[outCount] = y;
                outCount++;
            }
        }

        if (outCount < 3) {
            // 复制回原数组
            for (i = 0; i < outCount; i++) {
                ix[i] = tmpX[i];
                iy[i] = tmpY[i];
            }
            return outCount;
        }

        // ========== 2) 计算质心 ==========
        var cx:Number = 0, cy:Number = 0;
        for (i = 0; i < outCount; i++) {
            cx += tmpX[i];
            cy += tmpY[i];
        }
        cx /= outCount;
        cy /= outCount;

        // ========== 3) 角度预计算（atan2 只调用一次） ==========
        for (i = 0; i < outCount; i++) {
            idx[i] = i;
            ang[i] = Math.atan2(tmpY[i] - cy, tmpX[i] - cx);
        }

        // ========== 4) 按角度排序（插入排序，使用预计算的角度） ==========
        var currIdx:Number, currAng:Number;
        var k:Number;

        for (j = 1; j < outCount; j++) {
            currIdx = idx[j];
            currAng = ang[currIdx];

            k = j - 1;
            while (k >= 0 && ang[idx[k]] > currAng) {
                idx[k + 1] = idx[k];
                k--;
            }
            idx[k + 1] = currIdx;
        }

        // ========== 5) 根据排序后的索引重新排列交点到原数组 ==========
        var sortedIdx:Number;
        for (i = 0; i < outCount; i++) {
            sortedIdx = idx[i];
            ix[i] = tmpX[sortedIdx];
            iy[i] = tmpY[sortedIdx];
        }

        return outCount;
    }

    /**
     * P1 优化：Shoelace 公式计算多边形面积（直接版本）
     * 与原版相同逻辑，但命名更清晰，避免与旧版混淆
     */
    private function shoelaceAreaDirect(xArr:Array, yArr:Array, len:Number):Number {
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
    // UPDATE METHODS
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
