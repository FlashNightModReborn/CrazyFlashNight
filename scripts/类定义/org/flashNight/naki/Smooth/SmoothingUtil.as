// 文件路径：org/flashNight/naki/Smooth/SmoothingUtil.as

import org.flashNight.naki.DataStructures.RingBuffer;
import org.flashNight.sara.util.Vector; 

/**
 * SmoothingUtil
 * =============
 * 曲线平滑工具类 (Curve Smoothing Utility Class)
 *
 * 提供对 RingBuffer 中点数据进行平滑处理的静态方法，
 * 包括三点平均的 Simple Smooth 和经过性能优化的 Catmull-Rom 曲线平滑。
 * (Provides static methods for smoothing point data within a RingBuffer,
 * including three-point average Simple Smooth and performance-optimized Catmull-Rom curve smoothing.)
 *
 * 使用示例 (Usage Example):
 *   var ring:RingBuffer = new RingBuffer(10);
 *   // ... 添加点数据 (add point data) ...
 *   SmoothingUtil.simpleSmooth(ring);
 *   SmoothingUtil.catmullRomSmooth(ring, 0.5);
 *
 */
class org.flashNight.naki.Smooth.SmoothingUtil
{
    // --------------------------
    // 常量 (Constants)
    // --------------------------
    /**
     * @private
     * 用于 Catmull-Rom 插值的固定时间步长 (Fixed time steps for Catmull-Rom interpolation)
     */
    private static var CR_STEPS:Array = [0.25, 0.75];
    /**
     * @private
     * 用于避免除以零的距离最小值 (Minimum distance to avoid division by zero)
     */
    private static var MIN_DISTANCE_SQ:Number = 0.00001 * 0.00001; // 使用距离平方避免开方 (Use squared distance to avoid sqrt)
    private static var MIN_DISTANCE:Number = 0.0001;

    // --------------------------
    // 构造函数 (Constructor)
    // --------------------------
    /**
     * 私有构造函数 —— 工具类不允许实例化。
     * (Private constructor - Utility class cannot be instantiated.)
     */
    private function SmoothingUtil() { }

    // --------------------------
    // 平滑方法 (Smoothing Methods)
    // --------------------------
    /**
     * 简单平均平滑 (Simple Average Smoothing)
     * 对 RingBuffer 中的点数据执行三点平均平滑。
     * (Performs three-point average smoothing on the point data in the RingBuffer.)
     *
     * @param ring 包含点对象 {x,y} (或 Vector 实例) 的 RingBuffer 实例
     *             (RingBuffer instance containing point Vectors {x,y} (or Vector instances))
     */
    public static function simpleSmooth(ring:RingBuffer):Void
    {
        // --- 变量声明提升 (Hoisted Variable Declarations) ---
        var pts:Array;        // 原始点数组 (Original points array)
        var n:Number;         // 点的数量 (Number of points)
        var k:Number;         // 循环索引 (Loop index)
        var p0:Vector; // 前一个点 (Previous point) - 使用 Vector 兼容 {x,y}
        var p:Vector;  // 当前点 (Current point)
        var p1:Vector; // 后一个点 (Next point)
        var avgX:Number;      // 平均 x 坐标 (Average x coordinate)
        var avgY:Number;      // 平均 y 坐标 (Average y coordinate)
        // --------------------------------------------------

        pts = ring.toArray();
        n = pts.length;

        // 点数少于3个无法进行三点平滑 (Cannot perform 3-point smoothing with less than 3 points)
        if (n < 3) {
            return;
        }

        // 创建一个新数组来存储平滑后的点，避免原地修改影响后续计算
        // (Create a new array to store smoothed points to avoid in-place modification affecting subsequent calculations)
        var smoothedPts:Array = [];
        // 第一个点保持不变 (Keep the first point unchanged)
        smoothedPts.push(pts[0]);

        // 对中间的点进行三点平均 (Apply three-point average to the middle points)
        for (k = 1; k < n - 1; k++)
        {
            p0 = pts[k - 1];
            p  = pts[k];
            p1 = pts[k + 1];

            avgX = (p0.x + p.x + p1.x) / 3;
            avgY = (p0.y + p.y + p1.y) / 3;

            // 创建新的点对象存储结果 (Create a new point Vector to store the result)
            smoothedPts.push({x: avgX, y: avgY});
            // 注意：原实现是原地修改 `p.x` 和 `p.y`，如果 `pts` 中的对象被其他地方引用，
            // 这种修改可能会产生副作用。返回新数组更安全。
            // (Note: The original implementation modified `p.x` and `p.y` in place.
            // If Vectors in `pts` are referenced elsewhere, this modification might have side effects.
            // Returning a new array is safer.)
        }

        // 最后一个点保持不变 (Keep the last point unchanged)
        smoothedPts.push(pts[n - 1]);

        // 使用平滑后的点重置 RingBuffer (Reset the RingBuffer with the smoothed points)
        ring.reset(smoothedPts);
    }

    /**
     * 优化的 Catmull-Rom 曲线平滑 (Optimized Catmull-Rom Curve Smoothing)
     * 对 RingBuffer 中的点数据进行性能优化的 Catmull-Rom 样条插值平滑。
     * (Performs performance-optimized Catmull-Rom spline interpolation smoothing on the point data in the RingBuffer.)
     *
     * 优化点 (Optimizations):
     * 1. 预计算距离和张力相关值 (Pre-calculation of distances and tension-related values).
     * 2. 预计算插值系数 h (Pre-calculation of interpolation coefficients h).
     * 3. 展开内层插值循环 (Unrolling of the inner interpolation loop).
     * 4. 提取坐标到局部变量 (Extraction of coordinates to local variables).
     * 5. 变量声明提升 (Hoisting of variable declarations).
     * 6. 使用距离平方避免部分开方运算 (Using squared distance to avoid some square root operations).
     *
     * @param ring      包含点对象 {x,y} (或 Vector 实例) 的 RingBuffer 实例
     *                  (RingBuffer instance containing point Vectors {x,y} (or Vector instances))
     * @param tension   张力参数 (Tension parameter)，影响曲线的紧绷程度 (affects curve tightness)。默认为 0.5 (centripetal Catmull-Rom).
     *                  (Defaults to 0.5 for centripetal Catmull-Rom).
     */
    public static function catmullRomSmooth(ring:RingBuffer, tension:Number):Void
    {
        // --- 变量声明提升 (Hoisted Variable Declarations) ---
        var pts:Array;            // 原始点数组 (Original points array)
        var n:Number;             // 原始点的数量 (Number of original points)
        var ptsWrap:Array;        // 首尾环绕后的点数组 (Points array after wrapping ends)
        var wrapN:Number;         // 环绕后点的数量 (Number of points after wrapping)
        var newPts:Array;         // 存储生成的新点 (Array to store newly generated points)
        var i:Number;             // 主循环索引 (Main loop index)
        var k:Number;             // 预计算循环索引 (Pre-calculation loop index)

        // 点对象和坐标 (Point Vectors and coordinates)
        var p0:Vector, p1:Vector, p2:Vector, p3:Vector; // 控制点 (Control points)
        var p0x:Number, p0y:Number, p1x:Number, p1y:Number; // p0, p1 坐标
        var p2x:Number, p2y:Number, p3x:Number, p3y:Number; // p2, p3 坐标

        // 距离和张力相关值 (Distance and tension related values)
        var distancesSq:Array;     // 存储相邻点距离的平方 (Stores squared distances between adjacent points)
        var tensionedDistances:Array; // 存储距离的 tension 次幂 (Stores distance^tension)
        var distSq:Number;        // 临时距离平方 (Temporary squared distance)
        var dist:Number;          // 临时距离 (Temporary distance)
        var t01:Number, t12:Number, t23:Number; // 相邻点张力距离 t_ij = dist(pi, pj)^tension
        var invT01:Number, invT12:Number, invT23:Number; // 张力距离的倒数 (Inverse of tensioned distances) - 优化除法
        var t01t12:Number, t12t23:Number; // 张力距离之和 (Sum of tensioned distances)

        // Catmull-Rom 系数和切线向量 (Catmull-Rom coefficients and tangent vectors)
        var t:Number;             // 插值参数 (Interpolation parameter, 0 to 1)
        var t2:Number, t3:Number; // t 的平方和立方 (t squared and cubed)
        // 预计算的 H 基函数系数 (Pre-calculated H basis function coefficients)
        var h1_1:Number, h2_1:Number, h3_1:Number, h4_1:Number; // for t = 0.25
        var h1_2:Number, h2_2:Number, h3_2:Number, h4_2:Number; // for t = 0.75
        // 切线向量分量 (Tangent vector components)
        var m1x:Number, m1y:Number, m2x:Number, m2y:Number;
        // 插值计算的中间变量 (Intermediate variables for interpolation calculation)
        var c1x:Number, c1y:Number, c2x:Number, c2y:Number; // 用于计算切线的公共部分
        // 插值生成的新点坐标 (Coordinates of the new interpolated point)
        var nx1:Number, ny1:Number; // for t = 0.25
        var nx2:Number, ny2:Number; // for t = 0.75
        // --------------------------------------------------

        // 设置默认张力 (Set default tension)
        if (tension == undefined || isNaN(tension)) {
             tension = 0.5; // Centripetal Catmull-Rom as default
        }
        // 张力为0时，退化为线性插值，但此算法不直接处理，可能导致除零。
        // Tension = 0 degenerates to linear interpolation, but this algorithm doesn't handle it directly, may cause division by zero.
        // 通常 tension 取值范围 (0, 1]. Common tension range is (0, 1].

        pts = ring.toArray();
        n = pts.length;

        // 点数少于4个无法进行 Catmull-Rom 插值 (Cannot perform Catmull-Rom with less than 4 points)
        if (n < 4) {
            // trace("Warning: CatmullRomSmooth requires at least 4 points. Skipping.");
            return;
        }

        // 1. 创建首尾环绕的点数组 (Create wrapped points array)
        //    [p(n-1), p0, p1, ..., p(n-1), p0]
        ptsWrap = [];
        ptsWrap.push(pts[n - 1]); // 添加最后一个点到开头 (Add last point to the beginning)
        for (k = 0; k < n; k++) {
            ptsWrap.push(pts[k]); // 添加原始点 (Add original points)
        }
        ptsWrap.push(pts[0]); // 添加第一个点到末尾 (Add first point to the end)
        wrapN = ptsWrap.length; // n + 2

        // 2. 预计算相邻点距离的平方和张力距离 (Pre-calculate squared distances and tensioned distances)
        distancesSq = [];
        tensionedDistances = [];
        for (k = 0; k < wrapN - 1; k++) {
            p0 = ptsWrap[k];
            p1 = ptsWrap[k + 1];
            distSq = _distSq(p0, p1); // 计算距离平方 (Calculate squared distance)

            if (distSq < MIN_DISTANCE_SQ) {
                // 如果点重合或非常接近，使用一个很小的距离避免除零
                // (If points coincide or are very close, use a tiny distance to avoid division by zero)
                dist = MIN_DISTANCE;
                tensionedDistances.push(Math.pow(dist, tension));
            } else {
                // 只有在需要实际距离时才开方 (Only take sqrt if needed for tension calculation)
                dist = Math.sqrt(distSq);
                tensionedDistances.push(Math.pow(dist, tension));
            }
            distancesSq.push(distSq); // 存储平方距离可能在其他地方有用 (Storing squared distance might be useful elsewhere)
        }

        // 3. 预计算 H 基函数系数 (Pre-calculate H basis function coefficients)
        //    针对固定的插值步长 t = 0.25 和 t = 0.75
        //    (For fixed interpolation steps t = 0.25 and t = 0.75)
        // H1(t) =  2*t^3 - 3*t^2 + 1
        // H2(t) = -2*t^3 + 3*t^2
        // H3(t) =    t^3 - 2*t^2 + t
        // H4(t) =    t^3 -   t^2

        // for t = 0.25
        t = CR_STEPS[0]; // 0.25
        t2 = t * t;      // 0.0625
        t3 = t2 * t;     // 0.015625
        h1_1 =  2.0 * t3 - 3.0 * t2 + 1.0; // 0.828125
        h2_1 = -2.0 * t3 + 3.0 * t2;       // 0.171875
        h3_1 =       t3 - 2.0 * t2 + t;    // 0.140625
        h4_1 =       t3 -       t2;       // -0.046875

        // for t = 0.75
        t = CR_STEPS[1]; // 0.75
        t2 = t * t;      // 0.5625
        t3 = t2 * t;     // 0.421875
        h1_2 =  2.0 * t3 - 3.0 * t2 + 1.0; // 0.171875
        h2_2 = -2.0 * t3 + 3.0 * t2;       // 0.828125
        h3_2 =       t3 - 2.0 * t2 + t;    // -0.046875
        h4_2 =       t3 -       t2;       // 0.140625


        // 4. 主循环：遍历每个原始线段 (p1, p2) 并插值 (Main loop: Iterate through each original segment (p1, p2) and interpolate)
        newPts = [];
        // 循环范围对应原始点索引 k = 0 到 n-1
        // The loop range corresponds to original point indices k = 0 to n-1
        // 在 ptsWrap 中的索引 i = 1 到 n (即 wrapN - 2)
        // Indices in ptsWrap are i = 1 to n (which is wrapN - 2)
        for (i = 1; i < wrapN - 2; i++)
        {
            // 4.1 获取当前段所需的四个控制点 (Get the four control points for the current segment)
            //     p0 = ptsWrap[i-1], p1 = ptsWrap[i], p2 = ptsWrap[i+1], p3 = ptsWrap[i+2]
            p0 = ptsWrap[i - 1];
            p1 = ptsWrap[i];
            p2 = ptsWrap[i + 1];
            p3 = ptsWrap[i + 2];

            // 4.2 提取坐标到局部变量 (Extract coordinates to local variables)
            p0x = p0.x; p0y = p0.y;
            p1x = p1.x; p1y = p1.y;
            p2x = p2.x; p2y = p2.y;
            p3x = p3.x; p3y = p3.y;

            // 4.3 获取预计算的张力距离 (Get pre-calculated tensioned distances)
            //     t_ij = dist(pi, pj)^tension
            t01 = tensionedDistances[i - 1]; // dist(p0, p1)^tension
            t12 = tensionedDistances[i];     // dist(p1, p2)^tension
            t23 = tensionedDistances[i + 1]; // dist(p2, p3)^tension

            // 4.4 计算切线向量 M1 (在 p1 点) 和 M2 (在 p2 点)
            //     (Calculate tangent vectors M1 (at p1) and M2 (at p2))
            //     使用 Catmull-Rom (Centripetal / Chordal) 的切线公式变体
            //     (Using a variant of the Catmull-Rom (Centripetal/Chordal) tangent formula)
            //     m1 = (p2 - p1) + t12 * ((p1 - p0) / t01 - (p2 - p0) / (t01 + t12))
            //     m2 = (p2 - p1) + t12 * ((p3 - p2) / t23 - (p3 - p1) / (t12 + t23))

            // 优化：预计算倒数和和，处理潜在的除零 (Optimization: pre-calculate inverses and sums, handle potential division by zero)
            // 由于在预计算距离时加入了 MIN_DISTANCE，t_ij 理论上不为零
            // (Since MIN_DISTANCE was added during distance pre-calculation, t_ij should theoretically not be zero)
            invT01 = 1.0 / t01;
            invT12 = 1.0 / t12;
            invT23 = 1.0 / t23;
            t01t12 = t01 + t12;
            t12t23 = t12 + t23;
            // 添加检查以防万一 (Add checks just in case)
            var invT01T12:Number = (t01t12 == 0) ? 0 : (1.0 / t01t12);
            var invT12T23:Number = (t12t23 == 0) ? 0 : (1.0 / t12t23);

            // 计算切线 m1 (Tangent m1 calculation)
            c1x = (p1x - p0x) * invT01 - (p2x - p0x) * invT01T12;
            c1y = (p1y - p0y) * invT01 - (p2y - p0y) * invT01T12;
            m1x = (p2x - p1x) + t12 * c1x;
            m1y = (p2y - p1y) + t12 * c1y;

            // 计算切线 m2 (Tangent m2 calculation)
            c2x = (p3x - p2x) * invT23 - (p3x - p1x) * invT12T23;
            c2y = (p3y - p2y) * invT23 - (p3y - p1y) * invT12T23;
            m2x = (p2x - p1x) + t12 * c2x;
            m2y = (p2y - p1y) + t12 * c2y;

            // 4.5 使用预计算的 H 系数和展开的循环进行插值
            //     (Interpolate using pre-calculated H coefficients and unrolled loop)
            //     P(t) = H1(t)*P1 + H2(t)*P2 + H3(t)*M1 + H4(t)*M2

            // 插值点 1 (t = 0.25) (Interpolated point 1)
            nx1 = h1_1 * p1x + h2_1 * p2x + h3_1 * m1x + h4_1 * m2x;
            ny1 = h1_1 * p1y + h2_1 * p2y + h3_1 * m1y + h4_1 * m2y;
            newPts.push({x: nx1, y: ny1});

            // 插值点 2 (t = 0.75) (Interpolated point 2)
            nx2 = h1_2 * p1x + h2_2 * p2x + h3_2 * m1x + h4_2 * m2x;
            ny2 = h1_2 * p1y + h2_2 * p2y + h3_2 * m1y + h4_2 * m2y;
            newPts.push({x: nx2, y: ny2});
        }

        // 5. 使用新生成的点重置 RingBuffer (Reset the RingBuffer with the newly generated points)
        //    注意：新点集的数量大约是原始点数的两倍
        //    (Note: The number of points in the new set is approximately twice the original number)
        if (newPts.length > 0) {
            ring.reset(newPts);
        }
        // else: 如果原始点数 < 4，newPts 会是空的，这里不需要重置
        // (If original points < 4, newPts will be empty, no reset needed here)
    }

    /**
     * @private
     * 计算两点间距离的平方 (Calculates the squared distance between two points)
     * 避免不必要的开方运算 (Avoids unnecessary square root operations)
     *
     * @param a 第一个点 {x, y} (First point {x, y})
     * @param b 第二个点 {x, y} (Second point {x, y})
     * @return 两点距离的平方 (Squared distance between the points)
     */
    private static function _distSq(a:Vector, b:Vector):Number
    {
        var dx:Number = a.x - b.x;
        var dy:Number = a.y - b.y;
        return dx * dx + dy * dy;
    }

     /**
      * @private
      * 计算两点间距离 (Calculates the distance between two points)
      * 原始方法，在需要实际距离时使用 (Original method, used when actual distance is needed)
      *
      * @param a 第一个点 {x, y} (First point {x, y})
      * @param b 第二个点 {x, y} (Second point {x, y})
      * @return 两点间的距离 (Distance between the points)
      */
     private static function _dist(a:Vector, b:Vector):Number
     {
         var dx:Number = a.x - b.x;
         var dy:Number = a.y - b.y;
         return Math.sqrt(dx * dx + dy * dy);
     }
}