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
 * 2. 完全内联：checkCollision 为单函数直线代码，消除所有函数调用开销
 *    - updateCachedGeometry 内联：避免重复读取点坐标
 *    - 4 个 Sutherland-Hodgman 裁剪 pass 内联：消除函数调用和参数传递
 * 3. SAT 快速判定：6 轴分离检测，提前退出不碰撞场景
 * 4. Containment 快路径：全包含时跳过裁剪计算
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
    private var _pt:Object;                           // 坐标转换缓存对象

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

        // 坐标转换缓存对象
        _pt = {x: 0, y: 0};

        // 标记几何数据需要更新
        _geometryDirty = true;
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
        // polyMaxX <= left: 多边形在 AABB 左侧，有序分离（与 AABBCollider 一致）
        // polyMinX >= right: 多边形在 AABB 右侧，普通分离
        if (polyMaxX <= left) return CollisionResult.ORDERFALSE;
        if (polyMinX >= right) return CollisionResult.FALSE;

        // 多边形在 Y 轴上的投影范围
        var polyMinY:Number = p1y;
        var polyMaxY:Number = p1y;
        if (p2y < polyMinY) polyMinY = p2y; else if (p2y > polyMaxY) polyMaxY = p2y;
        if (p3y < polyMinY) polyMinY = p3y; else if (p3y > polyMaxY) polyMaxY = p3y;
        if (p4y < polyMinY) polyMinY = p4y; else if (p4y > polyMaxY) polyMaxY = p4y;

        // Y 轴分离检测
        // polyMaxY <= top: 多边形在 AABB 上方，Y轴有序分离
        // polyMinY >= bottom: 多边形在 AABB 下方，普通分离
        if (polyMaxY <= top) return CollisionResult.YORDERFALSE;
        if (polyMinY >= bottom) return CollisionResult.FALSE;

        // ========== 内联 updateCachedGeometry ==========
        // 使用已本地化的 p1x..p4y，避免重复读取点坐标
        var e1x:Number, e1y:Number, e2x:Number, e2y:Number;
        var e3x:Number, e3y:Number, e4x:Number, e4y:Number;
        if (_geometryDirty) {
            // 计算边向量并缓存
            e1x = p2x - p1x; e1y = p2y - p1y;
            e2x = p3x - p2x; e2y = p3y - p2y;
            e3x = p4x - p3x; e3y = p4y - p3y;
            e4x = p1x - p4x; e4y = p1y - p4y;
            _e1x = e1x; _e1y = e1y;
            _e2x = e2x; _e2y = e2y;
            _e3x = e3x; _e3y = e3y;
            _e4x = e4x; _e4y = e4y;
            // 计算面积（Shoelace 公式）
            var area:Number = (p1x * p2y - p2x * p1y)
                            + (p2x * p3y - p3x * p2y)
                            + (p3x * p4y - p4x * p3y)
                            + (p4x * p1y - p1x * p4y);
            _cachedArea = (area < 0) ? -area : area;
            _geometryDirty = false;
        } else {
            // 直接从缓存加载
            e1x = _e1x; e1y = _e1y;
            e2x = _e2x; e2y = _e2y;
            e3x = _e3x; e3y = _e3y;
            e4x = _e4x; e4y = _e4y;
        }

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

        // ========== 阶段2: Containment 快路径 ==========
        // 快路径1: 多边形 AABB ⊆ otherAABB => ratio = 1
        if (polyMinX >= left && polyMaxX <= right && polyMinY >= top && polyMaxY <= bottom) {
            var collRes:CollisionResult = PolygonCollider.result;
            collRes.overlapCenter.x = (p1x + p2x + p3x + p4x) * 0.25;
            collRes.overlapCenter.y = (p1y + p2y + p3y + p4y) * 0.25;
            collRes.overlapRatio = 1;
            return collRes;
        }

        // 快路径2: AABB 四角全在多边形内 => ratio = area(AABB) / polyArea
        // 使用叉积检测：对于凸多边形，点在内部当且仅当它在所有边的同一侧
        // 边方向: p1->p2->p3->p4->p1，检查点是否都在边的右侧（或都在左侧）
        var crossSum:Number;
        var allCornersInside:Boolean = true;

        // 检查左上角 (left, top)
        crossSum = e1x * (top - p1y) - e1y * (left - p1x);
        var sign1:Number = (crossSum > 0) ? 1 : ((crossSum < 0) ? -1 : 0);
        crossSum = e2x * (top - p2y) - e2y * (left - p2x);
        if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        if (allCornersInside) {
            crossSum = e3x * (top - p3y) - e3y * (left - p3x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e4x * (top - p4y) - e4y * (left - p4x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }

        // 检查右上角 (right, top)
        if (allCornersInside) {
            crossSum = e1x * (top - p1y) - e1y * (right - p1x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e2x * (top - p2y) - e2y * (right - p2x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e3x * (top - p3y) - e3y * (right - p3x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e4x * (top - p4y) - e4y * (right - p4x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }

        // 检查左下角 (left, bottom)
        if (allCornersInside) {
            crossSum = e1x * (bottom - p1y) - e1y * (left - p1x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e2x * (bottom - p2y) - e2y * (left - p2x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e3x * (bottom - p3y) - e3y * (left - p3x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e4x * (bottom - p4y) - e4y * (left - p4x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }

        // 检查右下角 (right, bottom)
        if (allCornersInside) {
            crossSum = e1x * (bottom - p1y) - e1y * (right - p1x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e2x * (bottom - p2y) - e2y * (right - p2x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e3x * (bottom - p3y) - e3y * (right - p3x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }
        if (allCornersInside) {
            crossSum = e4x * (bottom - p4y) - e4y * (right - p4x);
            if ((crossSum > 0 ? 1 : (crossSum < 0 ? -1 : 0)) != sign1) allCornersInside = false;
        }

        if (allCornersInside) {
            // AABB 完全在多边形内部
            // AABB 面积 = (right - left) * (bottom - top) * 2（不除以2，与 _cachedArea 一致）
            var aabbArea:Number = (right - left) * (bottom - top) * 2;
            collRes = PolygonCollider.result;
            collRes.overlapCenter.x = (left + right) * 0.5;
            collRes.overlapCenter.y = (top + bottom) * 0.5;
            collRes.overlapRatio = aabbArea / _cachedArea;
            return collRes;
        }

        // ========== 阶段3: Sutherland-Hodgman 裁剪（完全内联） ==========
        var inX:Array = _clipInX;
        var inY:Array = _clipInY;
        var outX:Array = _clipOutX;
        var outY:Array = _clipOutY;
        var tmpArr:Array;

        inX[0] = p1x; inY[0] = p1y;
        inX[1] = p2x; inY[1] = p2y;
        inX[2] = p3x; inY[2] = p3y;
        inX[3] = p4x; inY[3] = p4y;
        var inCount:Number = 4;
        var outCount:Number = 0;

        // 统一声明裁剪用局部变量（4个pass复用）
        var i:Number, j:Number;
        var sx:Number, sy:Number, ex:Number, ey:Number;
        var t:Number;

        // -------- Pass 1: clipXMin (x >= left) --------
        j = inCount - 1;
        for (i = 0; i < inCount; i++) {
            sx = inX[j]; sy = inY[j];
            ex = inX[i]; ey = inY[i];
            if (sx >= left) {
                if (ex >= left) {
                    outX[outCount] = ex; outY[outCount] = ey; outCount++;
                } else {
                    t = (left - sx) / (ex - sx);
                    outX[outCount] = left; outY[outCount] = sy + t * (ey - sy); outCount++;
                }
            } else {
                if (ex >= left) {
                    t = (left - sx) / (ex - sx);
                    outX[outCount] = left; outY[outCount] = sy + t * (ey - sy); outCount++;
                    outX[outCount] = ex; outY[outCount] = ey; outCount++;
                }
            }
            j = i;
        }
        if (outCount < 3) return CollisionResult.FALSE;
        // buffer swap
        inCount = outCount; outCount = 0;
        tmpArr = inX; inX = outX; outX = tmpArr;
        tmpArr = inY; inY = outY; outY = tmpArr;

        // -------- Pass 2: clipXMax (x <= right) --------
        j = inCount - 1;
        for (i = 0; i < inCount; i++) {
            sx = inX[j]; sy = inY[j];
            ex = inX[i]; ey = inY[i];
            if (sx <= right) {
                if (ex <= right) {
                    outX[outCount] = ex; outY[outCount] = ey; outCount++;
                } else {
                    t = (right - sx) / (ex - sx);
                    outX[outCount] = right; outY[outCount] = sy + t * (ey - sy); outCount++;
                }
            } else {
                if (ex <= right) {
                    t = (right - sx) / (ex - sx);
                    outX[outCount] = right; outY[outCount] = sy + t * (ey - sy); outCount++;
                    outX[outCount] = ex; outY[outCount] = ey; outCount++;
                }
            }
            j = i;
        }
        if (outCount < 3) return CollisionResult.FALSE;
        // buffer swap
        inCount = outCount; outCount = 0;
        tmpArr = inX; inX = outX; outX = tmpArr;
        tmpArr = inY; inY = outY; outY = tmpArr;

        // -------- Pass 3: clipYMin (y >= top) --------
        j = inCount - 1;
        for (i = 0; i < inCount; i++) {
            sx = inX[j]; sy = inY[j];
            ex = inX[i]; ey = inY[i];
            if (sy >= top) {
                if (ey >= top) {
                    outX[outCount] = ex; outY[outCount] = ey; outCount++;
                } else {
                    t = (top - sy) / (ey - sy);
                    outX[outCount] = sx + t * (ex - sx); outY[outCount] = top; outCount++;
                }
            } else {
                if (ey >= top) {
                    t = (top - sy) / (ey - sy);
                    outX[outCount] = sx + t * (ex - sx); outY[outCount] = top; outCount++;
                    outX[outCount] = ex; outY[outCount] = ey; outCount++;
                }
            }
            j = i;
        }
        if (outCount < 3) return CollisionResult.FALSE;
        // buffer swap
        inCount = outCount; outCount = 0;
        tmpArr = inX; inX = outX; outX = tmpArr;
        tmpArr = inY; inY = outY; outY = tmpArr;

        // -------- Pass 4: clipYMax (y <= bottom) --------
        j = inCount - 1;
        for (i = 0; i < inCount; i++) {
            sx = inX[j]; sy = inY[j];
            ex = inX[i]; ey = inY[i];
            if (sy <= bottom) {
                if (ey <= bottom) {
                    outX[outCount] = ex; outY[outCount] = ey; outCount++;
                } else {
                    t = (bottom - sy) / (ey - sy);
                    outX[outCount] = sx + t * (ex - sx); outY[outCount] = bottom; outCount++;
                }
            } else {
                if (ey <= bottom) {
                    t = (bottom - sy) / (ey - sy);
                    outX[outCount] = sx + t * (ex - sx); outY[outCount] = bottom; outCount++;
                    outX[outCount] = ex; outY[outCount] = ey; outCount++;
                }
            }
            j = i;
        }
        if (outCount < 3) return CollisionResult.FALSE;
        // 最后一次 swap，使 inX/inY 指向最终结果
        inCount = outCount;
        tmpArr = inX; inX = outX; outX = tmpArr;
        tmpArr = inY; inY = outY; outY = tmpArr;

        // ========== 阶段4: 计算交集面积和中心 ==========
        var intersectionArea:Number = 0;
        var cx:Number = 0, cy:Number = 0;

        for (i = 0; i < inCount - 1; i++) {
            intersectionArea += (inX[i] * inY[i + 1] - inX[i + 1] * inY[i]);
            cx += inX[i];
            cy += inY[i];
        }
        intersectionArea += (inX[inCount - 1] * inY[0] - inX[0] * inY[inCount - 1]);
        cx += inX[inCount - 1];
        cy += inY[inCount - 1];

        if (intersectionArea < 0) intersectionArea = -intersectionArea;

        // 退化保护：交集面积过小视为不碰撞（避免点/线接触误判）
        if (intersectionArea < 0.0001) return CollisionResult.FALSE;

        cx /= inCount;
        cy /= inCount;

        var ratio:Number = intersectionArea / _cachedArea;

        collRes = PolygonCollider.result;
        collRes.overlapCenter.x = cx;
        collRes.overlapCenter.y = cy;
        collRes.overlapRatio = ratio;

        return collRes;
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
     * 性能优化：完全零分配版本
     * - 使用实例缓存 _pt 进行坐标转换
     * - 消除三角函数调用（length * cos(atan2(vy, vx)) = vx）
     *
     * @param bullet 子弹 MovieClip
     * @param detectionArea 检测区域 MovieClip
     */
    public function updateFromBullet(bullet:MovieClip, detectionArea:MovieClip):Void {
        var frame:Number = _root.帧计时器.当前帧数;
        if (this._currentFrame == frame) return;
        this._currentFrame = frame;

        var rect:Object = detectionArea.getRect(detectionArea);
        var pt:Object = _pt;  // 使用实例缓存

        pt.x = rect.xMax;
        pt.y = rect.yMax;
        detectionArea.localToGlobal(pt);
        _root.gameworld.globalToLocal(pt);
        var p1x:Number = pt.x;
        var p1y:Number = pt.y;

        pt.x = rect.xMin;
        pt.y = rect.yMin;
        detectionArea.localToGlobal(pt);
        _root.gameworld.globalToLocal(pt);
        var p3x:Number = pt.x;
        var p3y:Number = pt.y;

        // 计算中心点和向量
        var centerX:Number = (p1x + p3x) * 0.5;
        var centerY:Number = (p1y + p3y) * 0.5;
        var vx:Number = p1x - centerX;
        var vy:Number = p1y - centerY;

        // 直接使用 vx, vy 作为偏移量
        p1.x = p1x; p1.y = p1y;
        p3.x = p3x; p3.y = p3y;
        p2.x = centerX + vx; p2.y = centerY - vy;
        p4.x = centerX - vx; p4.y = centerY + vy;
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
