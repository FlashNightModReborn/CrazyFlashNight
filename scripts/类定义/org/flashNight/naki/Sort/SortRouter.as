import org.flashNight.naki.Sort.IntroSort;
import org.flashNight.naki.Sort.TimSort;

/**
 * SortRouter — 自适应排序路由器
 *
 * 核心思路：AS2 native Array.sort(NUMERIC) 在随机数据上 ~5ms (n=10000)，
 * 是脚本层排序的 8-10x 快。但 native 在以下模式上灾难级退化 (O(n^2))：
 *   - 高有序度：sorted/reverse/nearSorted1%/pushFront/pushBack
 *   - 低 cardinality：allEqual/twoValues/threeValues/fewUnique
 *
 * 策略：用 O(n) 单次遍历扫描检测这两类风险，安全输入路由到 native，
 * 危险输入路由到 IntroSort(null)。
 *
 * 扫描特征（单次遍历）：
 *   - orderRatio = max(ascCount, descCount) / (n-1)
 *   - sampleCardinality = 64个等距采样的唯一值数
 *
 * 路由规则：
 *   - n < 64      → IntroSort（native 启动开销相对高，脚本 insertion sort 足够快）
 *   - cardinality <= 20  → IntroSort（低 cardinality 导致 native O(n^2)）
 *   - orderRatio > 0.95  → IntroSort（高有序度导致 native O(n^2)）
 *   - 否则         → native Array.sort(NUMERIC)
 *
 * 性能画像 (n=10000)：
 *   - random:    Router ~9ms   vs Native 5ms   vs IntroSort 41ms  (+4ms 扫描税)
 *   - sorted:    Router ~10ms  vs Native 582ms  vs IntroSort 5ms   (拯救 572ms)
 *   - allEqual:  Router ~9ms   vs Native 578ms  vs IntroSort 5ms   (拯救 569ms)
 *   - twoValues: Router ~8ms   vs Native 289ms  vs IntroSort 5ms   (拯救 281ms)
 */
class org.flashNight.naki.Sort.SortRouter {

    /**
     * 自适应排序 — null 比较器走路由，非 null 走 TimSort
     */
    public static function sort(arr:Array, compareFunction:Function):Array {
        if (compareFunction != null) {
            return TimSort.sort(arr, compareFunction);
        }

        var n:Number = arr.length;
        if (n < 2) return arr;

        // 小数组：直接 IntroSort（含内联 insertion sort）
        if (n < 64) {
            return IntroSort.sort(arr, null);
        }

        // ============================================================
        // O(n) 风险扫描 — 全部内联，零函数调用
        // ============================================================
        var ascCnt:Number = 0;
        var descCnt:Number = 0;
        var i:Number, j:Number;
        var prev:Number = arr[0];
        var cur:Number;

        // cardinality 采样：64 个等距样本
        var SAMPLE_K:Number = 64;
        var stride:Number = n / SAMPLE_K;
        var samples:Array = new Array(SAMPLE_K);
        var sIdx:Number = 0;
        var nextSample:Number = 0;

        for (i = 0; i < n; i++) {
            cur = arr[i];
            if (i > 0) {
                if (cur > prev) { ascCnt++; }
                else if (cur < prev) { descCnt++; }
                // eq 不需要计数，不影响路由决策
            }
            // 采样
            if (i >= nextSample && sIdx < SAMPLE_K) {
                samples[sIdx] = cur;
                sIdx++;
                nextSample += stride;
            }
            prev = cur;
        }

        // O(k^2) 去重计数 (k=64, 最多 4096 次比较)
        var uniq:Number = 0;
        for (i = 0; i < sIdx; i++) {
            var dup:Boolean = false;
            var sv:Number = samples[i];
            for (j = 0; j < i; j++) {
                if (samples[j] === sv) { dup = true; break; }
            }
            if (!dup) uniq++;
        }

        // 路由决策
        var total:Number = n - 1;
        var orderR:Number = (ascCnt > descCnt) ? (ascCnt / total) : (descCnt / total);

        if (uniq <= 20 || orderR > 0.95) {
            // 危险输入 → IntroSort
            return IntroSort.sort(arr, null);
        }

        // 安全输入 → native
        arr.sort(Array.NUMERIC);
        return arr;
    }
}
