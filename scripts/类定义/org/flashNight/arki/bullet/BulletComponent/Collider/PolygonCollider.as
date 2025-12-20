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
    private var _clipInX:Array;   // Sutherland-Hodgman 裁剪输入 X
    private var _clipInY:Array;   // Sutherland-Hodgman 裁剪输入 Y
    private var _clipOutX:Array;  // Sutherland-Hodgman 裁剪输出 X
    private var _clipOutY:Array;  // Sutherland-Hodgman 裁剪输出 Y

    // ========== P1 优化：缓存多边形几何数据 ==========
    private var _cachedArea:Number;   // 缓存的多边形面积
    private var _e1x:Number; private var _e1y:Number;  // 边向量 p1->p2
    private var _e2x:Number; private var _e2y:Number;  // 边向量 p2->p3
    private var _e3x:Number; private var _e3y:Number;  // 边向量 p3->p4
    private var _e4x:Number; private var _e4y:Number;  // 边向量 p4->p1
    private var _geometryDirty:Boolean;               // 几何数据是否需要更新

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
        // Sutherland-Hodgman 裁剪用缓存数组
        _clipInX = new Array(MAX_POINTS);
        _clipInY = new Array(MAX_POINTS);
        _clipOutX = new Array(MAX_POINTS);
        _clipOutY = new Array(MAX_POINTS);

        // 标记几何数据需要更新
        _geometryDirty = true;
    }

    /**
     * 更新缓存的几何数据（面积和边向量）
     * 在顶点变化后调用此方法
     */
    private function updateCachedGeometry():Void {
        if (!_geometryDirty) return;

        var p1x:Number = p1.x, p1y:Number = p1.y;
        var p2x:Number = p2.x, p2y:Number = p2.y;
        var p3x:Number = p3.x, p3y:Number = p3.y;
        var p4x:Number = p4.x, p4y:Number = p4.y;

        // 计算边向量
        _e1x = p2x - p1x; _e1y = p2y - p1y;
        _e2x = p3x - p2x; _e2y = p3y - p2y;
        _e3x = p4x - p3x; _e3y = p4y - p3y;
        _e4x = p1x - p4x; _e4y = p1y - p4y;

        // 计算面积（Shoelace 公式: Σ(x[i]*y[i+1] - x[i+1]*y[i]) / 2）
        // 注意：这里不除以2，与 intersectionArea 保持一致
        var area:Number = (p1x * p2y - p2x * p1y)
                        + (p2x * p3y - p3x * p2y)
                        + (p3x * p4y - p4x * p3y)
                        + (p4x * p1y - p1x * p4y);
        _cachedArea = (area < 0) ? -area : area;

        _geometryDirty = false;
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
     * ========== 优化策略 ==========
     * 1. SAT 快速判定：先用分离轴定理快速判断是否分离，不碰撞时立即返回
     * 2. Sutherland-Hodgman 裁剪：碰撞时用裁剪算法生成有序交集顶点，
     *    彻底消除 atan2 排序和 O(n²) 去重
     * 3. 缓存几何数据：多边形面积和边向量在更新时计算，避免重复计算
     *
     * @param other 另一个碰撞体
     * @param zOffset z轴偏移量
     * @return CollisionResult 碰撞结果
     */
    public function checkCollision(other:ICollider, zOffset:Number):CollisionResult {
        var otherAABB:AABB = other.getAABB(zOffset);

        var left:Number   = otherAABB.left;
        var right:Number  = otherAABB.right;
        var top:Number    = otherAABB.top;
        var bottom:Number = otherAABB.bottom;

        // 本地化多边形顶点坐标
        var p1x:Number = p1.x, p1y:Number = p1.y;
        var p2x:Number = p2.x, p2y:Number = p2.y;
        var p3x:Number = p3.x, p3y:Number = p3.y;
        var p4x:Number = p4.x, p4y:Number = p4.y;

        // ========== 阶段1: SAT 快速判定 ==========
        // 检查 AABB 的两条轴（X 轴和 Y 轴）
        // 多边形在 X 轴上的投影范围
        var polyMinX:Number = p1x;
        var polyMaxX:Number = p1x;
        if (p2x < polyMinX) polyMinX = p2x; else if (p2x > polyMaxX) polyMaxX = p2x;
        if (p3x < polyMinX) polyMinX = p3x; else if (p3x > polyMaxX) polyMaxX = p3x;
        if (p4x < polyMinX) polyMinX = p4x; else if (p4x > polyMaxX) polyMaxX = p4x;

        // X 轴分离检测
        if (polyMaxX <= left || polyMinX >= right) {
            return CollisionResult.FALSE;
        }

        // 多边形在 Y 轴上的投影范围
        var polyMinY:Number = p1y;
        var polyMaxY:Number = p1y;
        if (p2y < polyMinY) polyMinY = p2y; else if (p2y > polyMaxY) polyMaxY = p2y;
        if (p3y < polyMinY) polyMinY = p3y; else if (p3y > polyMaxY) polyMaxY = p3y;
        if (p4y < polyMinY) polyMinY = p4y; else if (p4y > polyMaxY) polyMaxY = p4y;

        // Y 轴分离检测
        if (polyMaxY <= top || polyMinY >= bottom) {
            return CollisionResult.FALSE;
        }

        // 确保缓存的几何数据是最新的
        updateCachedGeometry();
        var e1x:Number = _e1x, e1y:Number = _e1y;
        var e2x:Number = _e2x, e2y:Number = _e2y;
        var e3x:Number = _e3x, e3y:Number = _e3y;
        var e4x:Number = _e4x, e4y:Number = _e4y;

        // 检查多边形的 4 条边法线方向
        // 边1法线: (e1y, -e1x)，投影 AABB 4 个角点到此法线
        var proj:Number, minBox:Number, maxBox:Number, minPoly:Number, maxPoly:Number;

        // 边1: p1->p2, 法线 (e1y, -e1x)
        // 多边形顶点投影（相对于 p1）
        proj = 0; // p1 投影 = 0
        minPoly = 0; maxPoly = 0;
        proj = e1y * (p2x - p1x) - e1x * (p2y - p1y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;
        proj = e1y * (p3x - p1x) - e1x * (p3y - p1y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;
        proj = e1y * (p4x - p1x) - e1x * (p4y - p1y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;

        // AABB 4 个角点投影
        proj = e1y * (left - p1x) - e1x * (top - p1y);
        minBox = proj; maxBox = proj;
        proj = e1y * (right - p1x) - e1x * (top - p1y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;
        proj = e1y * (left - p1x) - e1x * (bottom - p1y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;
        proj = e1y * (right - p1x) - e1x * (bottom - p1y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;

        if (maxBox <= minPoly || minBox >= maxPoly) return CollisionResult.FALSE;

        // 边2: p2->p3
        minPoly = 0; maxPoly = 0;
        proj = e2y * (p1x - p2x) - e2x * (p1y - p2y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;
        proj = e2y * (p3x - p2x) - e2x * (p3y - p2y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;
        proj = e2y * (p4x - p2x) - e2x * (p4y - p2y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;

        proj = e2y * (left - p2x) - e2x * (top - p2y);
        minBox = proj; maxBox = proj;
        proj = e2y * (right - p2x) - e2x * (top - p2y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;
        proj = e2y * (left - p2x) - e2x * (bottom - p2y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;
        proj = e2y * (right - p2x) - e2x * (bottom - p2y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;

        if (maxBox <= minPoly || minBox >= maxPoly) return CollisionResult.FALSE;

        // 边3: p3->p4
        minPoly = 0; maxPoly = 0;
        proj = e3y * (p1x - p3x) - e3x * (p1y - p3y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;
        proj = e3y * (p2x - p3x) - e3x * (p2y - p3y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;
        proj = e3y * (p4x - p3x) - e3x * (p4y - p3y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;

        proj = e3y * (left - p3x) - e3x * (top - p3y);
        minBox = proj; maxBox = proj;
        proj = e3y * (right - p3x) - e3x * (top - p3y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;
        proj = e3y * (left - p3x) - e3x * (bottom - p3y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;
        proj = e3y * (right - p3x) - e3x * (bottom - p3y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;

        if (maxBox <= minPoly || minBox >= maxPoly) return CollisionResult.FALSE;

        // 边4: p4->p1
        minPoly = 0; maxPoly = 0;
        proj = e4y * (p1x - p4x) - e4x * (p1y - p4y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;
        proj = e4y * (p2x - p4x) - e4x * (p2y - p4y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;
        proj = e4y * (p3x - p4x) - e4x * (p3y - p4y);
        if (proj < minPoly) minPoly = proj; else if (proj > maxPoly) maxPoly = proj;

        proj = e4y * (left - p4x) - e4x * (top - p4y);
        minBox = proj; maxBox = proj;
        proj = e4y * (right - p4x) - e4x * (top - p4y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;
        proj = e4y * (left - p4x) - e4x * (bottom - p4y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;
        proj = e4y * (right - p4x) - e4x * (bottom - p4y);
        if (proj < minBox) minBox = proj; else if (proj > maxBox) maxBox = proj;

        if (maxBox <= minPoly || minBox >= maxPoly) return CollisionResult.FALSE;

        // ========== 阶段2: Sutherland-Hodgman 裁剪 ==========
        // 初始化输入多边形为凸四边形
        var inX:Array = _clipInX;
        var inY:Array = _clipInY;
        var outX:Array = _clipOutX;
        var outY:Array = _clipOutY;

        inX[0] = p1x; inY[0] = p1y;
        inX[1] = p2x; inY[1] = p2y;
        inX[2] = p3x; inY[2] = p3y;
        inX[3] = p4x; inY[3] = p4y;
        var inCount:Number = 4;
        var outCount:Number;

        // 依次用 AABB 的 4 条边裁剪
        // 裁剪边 1: x >= left
        outCount = clipByEdge(inX, inY, inCount, outX, outY, left, 0, 1, 0);
        if (outCount < 3) return CollisionResult.FALSE;

        // 裁剪边 2: x <= right
        inCount = clipByEdge(outX, outY, outCount, inX, inY, right, 0, -1, 0);
        if (inCount < 3) return CollisionResult.FALSE;

        // 裁剪边 3: y >= top
        outCount = clipByEdge(inX, inY, inCount, outX, outY, top, 1, 0, 1);
        if (outCount < 3) return CollisionResult.FALSE;

        // 裁剪边 4: y <= bottom
        inCount = clipByEdge(outX, outY, outCount, inX, inY, bottom, 1, 0, -1);
        if (inCount < 3) return CollisionResult.FALSE;

        // ========== 阶段3: 计算交集面积和中心 ==========
        // Shoelace 公式计算面积: Σ(x[i]*y[i+1] - x[i+1]*y[i])
        // 与 _cachedArea 使用完全相同的公式结构
        var intersectionArea:Number = 0;
        var cx:Number = 0, cy:Number = 0;
        var i:Number;

        // 使用与 _cachedArea 相同的公式：x[i]*y[i+1] - x[i+1]*y[i]
        for (i = 0; i < inCount - 1; i++) {
            intersectionArea += (inX[i] * inY[i + 1] - inX[i + 1] * inY[i]);
            cx += inX[i];
            cy += inY[i];
        }
        // 最后一条边：从最后一个点到第一个点
        intersectionArea += (inX[inCount - 1] * inY[0] - inX[0] * inY[inCount - 1]);
        cx += inX[inCount - 1];
        cy += inY[inCount - 1];

        if (intersectionArea < 0) intersectionArea = -intersectionArea;

        cx /= inCount;
        cy /= inCount;

        // 使用缓存的多边形面积
        var ratio:Number = intersectionArea / _cachedArea;

        var collRes:CollisionResult = PolygonCollider.result;
        collRes.overlapCenter.x = cx;
        collRes.overlapCenter.y = cy;
        collRes.overlapRatio = ratio;

        return collRes;
    }

    /**
     * Sutherland-Hodgman 单边裁剪
     *
     * @param inX 输入多边形 X 坐标数组
     * @param inY 输入多边形 Y 坐标数组
     * @param inCount 输入顶点数
     * @param outX 输出多边形 X 坐标数组
     * @param outY 输出多边形 Y 坐标数组
     * @param edgeVal 边界值
     * @param axis 0=X轴, 1=Y轴
     * @param sign 1=保留>=边界的点, -1=保留<=边界的点
     * @param dummy 占位参数（保持参数对齐）
     * @return 输出顶点数
     */
    private function clipByEdge(inX:Array, inY:Array, inCount:Number,
                                 outX:Array, outY:Array,
                                 edgeVal:Number, axis:Number, sign:Number, dummy:Number):Number {
        var outCount:Number = 0;
        var i:Number, j:Number;
        var sx:Number, sy:Number, ex:Number, ey:Number;
        var sVal:Number, eVal:Number;
        var sInside:Boolean, eInside:Boolean;
        var t:Number, ix:Number, iy:Number;

        j = inCount - 1;
        for (i = 0; i < inCount; i++) {
            sx = inX[j]; sy = inY[j];
            ex = inX[i]; ey = inY[i];

            // 根据轴选择比较值
            if (axis == 0) {
                sVal = sx; eVal = ex;
            } else {
                sVal = sy; eVal = ey;
            }

            // 判断点是否在边界内侧
            if (sign > 0) {
                sInside = (sVal >= edgeVal);
                eInside = (eVal >= edgeVal);
            } else {
                sInside = (sVal <= edgeVal);
                eInside = (eVal <= edgeVal);
            }

            if (sInside) {
                if (eInside) {
                    // 两点都在内侧：输出终点
                    outX[outCount] = ex;
                    outY[outCount] = ey;
                    outCount++;
                } else {
                    // 起点在内，终点在外：输出交点
                    t = (edgeVal - sVal) / (eVal - sVal);
                    ix = sx + t * (ex - sx);
                    iy = sy + t * (ey - sy);
                    outX[outCount] = ix;
                    outY[outCount] = iy;
                    outCount++;
                }
            } else {
                if (eInside) {
                    // 起点在外，终点在内：输出交点和终点
                    t = (edgeVal - sVal) / (eVal - sVal);
                    ix = sx + t * (ex - sx);
                    iy = sy + t * (ey - sy);
                    outX[outCount] = ix;
                    outY[outCount] = iy;
                    outCount++;

                    outX[outCount] = ex;
                    outY[outCount] = ey;
                    outCount++;
                }
                // 两点都在外侧：不输出
            }
            j = i;
        }
        return outCount;
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
        _geometryDirty = true;
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
        _geometryDirty = true;
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
        _geometryDirty = true;
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
