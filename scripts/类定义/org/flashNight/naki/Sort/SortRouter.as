import org.flashNight.naki.Sort.IntroSort;
import org.flashNight.naki.Sort.TimSort;

/**
 * SortRouter — 自适应排序路由器
 *
 * v3 把旧版"全量 O(n) 扫描再决策"改成两层：
 *   1. 32 点顺序采样：估计是否接近单调
 *   2. 32 点互素步长采样：估计 cardinality，避免周期别名
 *   3. 只有命中高单调嫌疑时，才做一次 O(n) 深扫确认
 *
 * 目标不是识别所有"略慢于 IntroSort"的输入，而是用更低的扫描税，
 * 拦住最容易把 native 拖进 O(n^2) 的极端输入，并减少对明显安全流量的误杀。
 */
class org.flashNight.naki.Sort.SortRouter {
    public static var ROUTE_NATIVE:String = "native";
    public static var ROUTE_INTRO:String = "intro";

    private static var SMALL_THRESHOLD:Number = 64;
    private static var SAMPLE_K:Number = 32;
    private static var LOW_CARDINALITY_THRESHOLD:Number = 20;
    // 修复：旧值 0.97 导致 Stage B 死代码。
    // 31 对采样的离散值域: 31/31=1.0, 30/31=0.9677, 29/31=0.935...
    // perfect-sample 吃掉 1.0 后最大值仅 0.9677 < 0.97，Stage B 永不可达。
    // 降到 0.93 使 1-2 个采样违规 (30/31, 29/31) 能进入 Stage B。
    private static var SAMPLE_ORDER_DEEP_SCAN_THRESHOLD:Number = 0.93;
    // Stage B: 简化为 antiCnt 计数 + early exit
    // antiCnt ≤ 此阈值 → 几乎纯单调 → native O(n²) 风险 → INTRO
    // antiCnt > 此阈值 → 足够混乱 → native 安全 → NATIVE (early exit)
    private static var STAGE_B_ANTI_LIMIT:Number = 32;

    // Stage A-3: near-sorted 双端探针
    // 用 O(PROBE_LEN) 探测首尾两段是否都有稀疏违规
    // 只有「两端都有且都稀疏」才判 near-sorted
    // sortedTailRand 首段 0 违规 → 不触发；sortedMidRand 同理
    private static var NEAR_SORTED_GATE:Number = 0.90;
    private static var NEAR_SORTED_PROBE_LEN:Number = 256;
    private static var NEAR_SORTED_PROBE_MAX_VIOL:Number = 8; // 每端最多 8 个违规

    /**
     * 自适应排序 — null 比较器走路由，非 null 走 TimSort
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        if (compareFunction != null) {
            return TimSort.sort(arr, compareFunction);
        }

        var n:Number = arr.length;
        if (n < 2) return arr;

        if (classifyNumeric(arr) === ROUTE_INTRO) {
            return IntroSort.sort(arr, null);
        }

        arr.sort(Array.NUMERIC);
        return arr;
    }

    /**
     * 数值路径的路由决策。
     * 不修改数组内容，可供测试和 profile 直接复用。
     */
    public static function classifyNumeric(arr:Array):String {
        var n:Number = arr.length;
        if (n < SMALL_THRESHOLD) {
            return ROUTE_INTRO;
        }

        var i:Number;
        var j:Number;
        var idx:Number;
        var cur:Number;
        var prev:Number;

        // ------------------------------------------------------------
        // Stage A-1: 顺序采样，快速估计"是否接近单调"
        // ------------------------------------------------------------
        var sAsc:Number = 0;
        var sDesc:Number = 0;
        var sEq:Number = 0;
        var bias:Number = (n * 3) >> 3; // Math.floor(n*3/8)

        for (i = 0; i < SAMPLE_K; i++) {
            idx = (i * n + bias) >> 5; // Math.floor((i*n+bias)/32), 安全: i*n+bias < 2^31 for n≤16M
            if (idx >= n) idx = n - 1;

            cur = arr[idx];
            if (i > 0) {
                if (cur > prev) sAsc++;
                else if (cur < prev) sDesc++;
                else sEq++;
            }
            prev = cur;
        }

        // ------------------------------------------------------------
        // Stage A-2: 互素步长采样 cardinality，避免固定 stride 共振
        // ------------------------------------------------------------
        var step:Number = (n >> 5) + 1; // Math.floor(n/32)+1
        while (gcd(step, n) != 1) step++;

        var sampleVals:Array = new Array(SAMPLE_K);
        var uniq:Number = 0;
        idx = 17 % n;

        for (i = 0; i < SAMPLE_K; i++) {
            cur = arr[idx];
            var dup:Boolean = false;
            for (j = 0; j < uniq; j++) {
                if (sampleVals[j] === cur) {
                    dup = true;
                    break;
                }
            }
            if (!dup) {
                sampleVals[uniq] = cur;
                uniq++;
            }

            idx += step;
            if (idx >= n) idx -= n;
        }

        if (uniq <= LOW_CARDINALITY_THRESHOLD) {
            return ROUTE_INTRO;
        }

        var samplePairs:Number = SAMPLE_K - 1;
        // 修复：sEq 不是反单调信号，等值对应计入单调度。
        // 否则"有序+少量重复值"会被 sEq 拉低 sampleOrder 误判为安全。
        var sampleOrder:Number = (sAsc > sDesc)
            ? ((sAsc + sEq) / samplePairs)
            : ((sDesc + sEq) / samplePairs);
        if (sEq == 0 && sampleOrder == 1) {
            return ROUTE_INTRO;
        }
        // ------------------------------------------------------------
        // Stage A-3: near-sorted 双端探针
        //
        // 仅对升序主导触发（native 对近逆序不退化）。
        // 探测首尾各 PROBE_LEN 对：若两端都出现少量违规（≤ MAX_VIOL），
        // 说明乱序是均匀散布的 near-sorted；否则乱序集中在局部
        // （sortedTailRand / sortedMidRand），放行 native。
        //
        // 成本：O(PROBE_LEN * 2) = O(512) ≈ 0.02ms，不依赖 n。
        // ------------------------------------------------------------
        if (sAsc > sDesc && sampleOrder >= NEAR_SORTED_GATE && uniq > LOW_CARDINALITY_THRESHOLD) {
            var probeLen:Number = NEAR_SORTED_PROBE_LEN;
            if (probeLen > (n >> 2)) probeLen = n >> 2; // 不超过 n/4
            var maxV:Number = NEAR_SORTED_PROBE_MAX_VIOL;

            // 探测首段 [0, probeLen)
            var headV:Number = 0;
            prev = arr[0];
            for (i = 1; i < probeLen; i++) {
                if (arr[i] < prev) headV++;
                prev = arr[i];
            }

            // 首段有稀疏违规才继续探测尾段
            if (headV > 0 && headV <= maxV) {
                // 探测尾段 [n - probeLen, n)
                var tailV:Number = 0;
                var tailStart:Number = n - probeLen;
                prev = arr[tailStart];
                for (i = tailStart + 1; i < n; i++) {
                    if (arr[i] < prev) tailV++;
                    prev = arr[i];
                }
                if (tailV > 0 && tailV <= maxV) {
                    return ROUTE_INTRO;
                }
            }
        }

        if (sampleOrder < SAMPLE_ORDER_DEEP_SCAN_THRESHOLD) {
            return ROUTE_NATIVE;
        }

        // ------------------------------------------------------------
        // desc-dominant 处理
        //
        // sEq <= 2: 高 cardinality 近逆序（nearReverse1% 典型）。
        //   native 实测不退化 (16ms)，直接放行，跳过深扫。
        //   纯逆序已被 perfect-sample 拦截。
        //
        // sEq > 2: 有平台结构（如 25 值 × 400 重复, 降序排列）。
        //   native 在此类输入上 O(n²) 退化，必须进入 desc 方向 Stage B。
        //   计数升序对（少数方向），antiCnt ≤ 32 → INTRO。
        // ------------------------------------------------------------
        if (sDesc >= sAsc) {
            if (sEq <= 2) {
                return ROUTE_NATIVE;
            }
            // desc-dominant + 平台结构 → desc 方向 Stage B
            var antiCntD:Number = 0;
            var antiLimitD:Number = STAGE_B_ANTI_LIMIT;
            prev = arr[0];
            for (i = 1; i < n; i++) {
                if (arr[i] > prev) {
                    if (++antiCntD > antiLimitD) {
                        return ROUTE_NATIVE;
                    }
                }
                prev = arr[i];
            }
            return ROUTE_INTRO;
        }

        // ------------------------------------------------------------
        // Stage B: 升序主导深扫
        //
        // 计数 desc 对（少数方向）+ early exit。
        // antiCnt ≤ 32 → 几乎纯升序 → native O(n²) 风险 → INTRO
        // antiCnt > 32 → early exit → 足够混乱 → NATIVE
        // ------------------------------------------------------------
        var antiCnt:Number = 0;
        var antiLimit:Number = STAGE_B_ANTI_LIMIT;
        prev = arr[0];
        for (i = 1; i < n; i++) {
            if (arr[i] < prev) {
                if (++antiCnt > antiLimit) {
                    return ROUTE_NATIVE;
                }
            }
            prev = arr[i];
        }
        return ROUTE_INTRO;
    }

    private static function gcd(a:Number, b:Number):Number {
        var t:Number;
        while (b != 0) {
            t = a % b;
            a = b;
            b = t;
        }
        return (a < 0) ? -a : a;
    }
}
