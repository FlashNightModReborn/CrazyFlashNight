import org.flashNight.naki.Sort.IntroSort;
import org.flashNight.naki.Sort.TimSort;

/**
 * SortRouter — 自适应排序路由器
 *
 * v3 把旧版“全量 O(n) 扫描再决策”改成两层：
 *   1. 32 点顺序采样：估计是否接近单调
 *   2. 32 点互素步长采样：估计 cardinality，避免周期别名
 *   3. 只有命中高单调嫌疑时，才做一次 O(n) 深扫确认
 *
 * 目标不是识别所有“略慢于 IntroSort”的输入，而是用更低的扫描税，
 * 拦住最容易把 native 拖进 O(n^2) 的极端输入，并减少对明显安全流量的误杀。
 */
class org.flashNight.naki.Sort.SortRouter {
    public static var ROUTE_NATIVE:String = "native";
    public static var ROUTE_INTRO:String = "intro";

    private static var SMALL_THRESHOLD:Number = 64;
    private static var SAMPLE_K:Number = 32;
    private static var LOW_CARDINALITY_THRESHOLD:Number = 20;
    private static var SAMPLE_ORDER_DEEP_SCAN_THRESHOLD:Number = 0.97;
    private static var FULL_SCAN_EQ_RATIO_SCALE:Number = 4;
    private static var FULL_SCAN_TINY_ANTI_THRESHOLD:Number = 4;
    private static var FULL_SCAN_LONG_RUN_PERCENT:Number = 98;
    private static var FULL_SCAN_LONG_RUN_ANTI_THRESHOLD:Number = 32;

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
        // Stage A-1: 顺序采样，快速估计“是否接近单调”
        // ------------------------------------------------------------
        var sAsc:Number = 0;
        var sDesc:Number = 0;
        var sEq:Number = 0;
        var bias:Number = Math.floor(n * 3 / 8);

        for (i = 0; i < SAMPLE_K; i++) {
            idx = Math.floor((i * n + bias) / SAMPLE_K);
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
        var step:Number = Math.floor(n / SAMPLE_K) + 1;
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
        var sampleOrder:Number = (sAsc > sDesc) ? (sAsc / samplePairs) : (sDesc / samplePairs);
        if (sEq == 0 && sampleOrder == 1) {
            return ROUTE_INTRO;
        }
        if (sampleOrder < SAMPLE_ORDER_DEEP_SCAN_THRESHOLD) {
            return ROUTE_NATIVE;
        }

        // ------------------------------------------------------------
        // Stage B: 只对高单调嫌疑输入做深扫确认
        // ------------------------------------------------------------
        var ascCnt:Number = 0;
        var descCnt:Number = 0;
        var eqCnt:Number = 0;
        var maxAscRun:Number = 1;
        var maxDescRun:Number = 1;
        var curAscRun:Number = 1;
        var curDescRun:Number = 1;
        var total:Number = n - 1;

        prev = arr[0];
        for (i = 1; i < n; i++) {
            cur = arr[i];
            if (cur > prev) {
                ascCnt++;
                curAscRun++;
                if (curDescRun > maxDescRun) maxDescRun = curDescRun;
                curDescRun = 1;
            } else if (cur < prev) {
                descCnt++;
                curDescRun++;
                if (curAscRun > maxAscRun) maxAscRun = curAscRun;
                curAscRun = 1;
            } else {
                eqCnt++;
                if (curAscRun > maxAscRun) maxAscRun = curAscRun;
                if (curDescRun > maxDescRun) maxDescRun = curDescRun;
                curAscRun = 1;
                curDescRun = 1;
            }
            prev = cur;
        }
        if (curAscRun > maxAscRun) maxAscRun = curAscRun;
        if (curDescRun > maxDescRun) maxDescRun = curDescRun;

        var antiCnt:Number = (ascCnt < descCnt) ? ascCnt : descCnt;
        var dominantRun:Number = (ascCnt >= descCnt) ? maxAscRun : maxDescRun;

        if ((eqCnt * FULL_SCAN_EQ_RATIO_SCALE >= total)
            || (antiCnt <= FULL_SCAN_TINY_ANTI_THRESHOLD)
            || ((dominantRun * 100 >= n * FULL_SCAN_LONG_RUN_PERCENT)
                && (antiCnt <= FULL_SCAN_LONG_RUN_ANTI_THRESHOLD))) {
            return ROUTE_INTRO;
        }

        return ROUTE_NATIVE;
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
