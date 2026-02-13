// ============================================================================
// TargetCacheThresholdTuner.as — 排序微基准（方案A）
// org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheThresholdTuner
//
// 仅测量 "预提取 left/right + isSorted 检测 + 排序" 路径
// 完全排除 _reconcile / collection / addUnit / resetVersions 开销
//
// 原理：
//   1. 离线生成 origList（单位数组，按指定分布排列）
//   2. 热循环内：复制 origList → list → 执行 sortKernel → 累计时间
//   3. sortKernel 完全复刻 updateCache 第260-347行逻辑
//   4. 每组使用确定性种子，保证跨阈值看到完全相同的数据
//
// 启动：
//   org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheThresholdTuner.run();
//   TargetCacheThresholdTuner.run({thresholds:[8,16,24,32,48,64], sizes:[16,32,64,128]});
// ============================================================================

import org.flashNight.naki.Sort.TimSort;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

class org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheThresholdTuner {

    // ==================== 对外入口 ====================

    /**
     * @param config 可选配置
     *   config.thresholds : Array  - 候选阈值（默认 [8,12,16,20,24,28,32,40,48,64]）
     *   config.sizes      : Array  - 测试规模（默认 [8,12,16,20,24,32,48,64,96,128,256,512]）
     *   config.seed       : Number - 随机种子（默认 1234567）
     */
    public static function run(config:Object):Object {
        var tuner:TargetCacheThresholdTuner = new TargetCacheThresholdTuner();
        return tuner._run(config);
    }

    // ==================== 成员 ====================

    private var thresholds:Array;
    private var sizes:Array;
    private var dists:Array;
    private var seed:Number;

    private var rng:LinearCongruentialEngine;

    /** results[ti][si][di] = {ms, totalMs, iters, ok} */
    private var results:Array;

    private var assertTotal:Number;
    private var assertFailed:Number;

    // 预分配排序缓冲区（跨迭代复用）
    private var _leftBuf:Array;
    private var _rightBuf:Array;
    private var _idxBuf:Array;
    private var _sListBuf:Array;
    private var _sLeftBuf:Array;
    private var _sRightBuf:Array;

    // ==================== 主流程 ====================

    private function _run(config:Object):Object {
        if (!config) config = {};

        this.thresholds = config.thresholds || [8, 12, 16, 20, 24, 28, 32, 40, 48, 64];
        this.sizes      = config.sizes      || [8, 12, 16, 20, 24, 32, 48, 64, 96, 128, 256, 512];
        this.seed       = (!isNaN(config.seed)) ? Number(config.seed) : 1234567;

        this.dists = [
            "random", "ascending", "descending", "nearlySorted",
            "twoRuns", "sawtooth", "fewUniques", "allSame"
        ];

        this.assertTotal  = 0;
        this.assertFailed = 0;
        this.results      = [];

        this._leftBuf  = [];
        this._rightBuf = [];
        this._idxBuf   = [];
        this._sListBuf = [];
        this._sLeftBuf = [];
        this._sRightBuf = [];

        this.initRNG();

        log("============================================================");
        log(" TargetCacheThresholdTuner 排序微基准（方案A）");
        log(" 仅测量 预提取+排序 路径，排除 reconcile/collection 开销");
        log(" thresholds=" + this.thresholds.join(","));
        log(" sizes=" + this.sizes.join(","));
        log(" distributions=" + this.dists.join(","));
        log(" seed=" + this.seed);
        log("============================================================");

        var totalStart:Number = getTimer();

        for (var ti:Number = 0; ti < this.thresholds.length; ti++) {
            var threshold:Number = this.thresholds[ti];
            log("\n--- threshold = " + threshold + " ---");

            this.results[ti] = [];

            for (var si:Number = 0; si < this.sizes.length; si++) {
                this.results[ti][si] = [];

                for (var di:Number = 0; di < this.dists.length; di++) {
                    var r:Object = this.runOneCase(
                        threshold, this.dists[di], this.sizes[si]
                    );
                    this.results[ti][si][di] = r;
                }
            }
        }

        var totalEnd:Number = getTimer();

        // ---- 输出汇总 ----
        this.printSummaryBySize();
        this.printBestThresholdMatrix();
        this.printOverallRanking();
        this.printMeasurementQuality();

        log("\n断言统计: total=" + this.assertTotal + ", failed=" + this.assertFailed);
        if (this.assertFailed == 0) log("✅ 全部断言通过");
        else log("❌ 存在 " + this.assertFailed + " 个断言失败");
        log("总耗时: " + (totalEnd - totalStart) + "ms");
        log("============================================================");

        if (!_root.gameworld) _root.gameworld = {};
        var output:Object = {
            thresholds: this.thresholds,
            sizes: this.sizes,
            dists: this.dists,
            results: this.results,
            assertTotal: this.assertTotal,
            assertFailed: this.assertFailed
        };
        _root.gameworld.ThresholdTunerResults = output;
        return output;
    }

    // ==================== 迭代次数策略 ====================

    /**
     * 根据数组规模确定迭代次数
     * 小数组排序极快，需要更多迭代才能积累到 getTimer() 可分辨的毫秒数
     */
    private function getIters(n:Number):Number {
        if (n <= 16)  return 4000;
        if (n <= 32)  return 2000;
        if (n <= 64)  return 1000;
        if (n <= 128) return 400;
        if (n <= 256) return 100;
        if (n <= 512) return 30;
        return 10;
    }

    // ==================== 单个用例 ====================

    private function runOneCase(threshold:Number, dist:String, n:Number):Object {
        // 确定性种子：同一 (size, dist) 跨所有阈值使用相同数据
        this.resetRNG(this.seed + n * 10000 + this.distIndex(dist));
        var origList:Array = this.makeUnits(dist, n);

        var list:Array = new Array(n);
        var ITERS:Number = this.getIters(n);

        // 本地化缓冲区引用（避免热循环内 this 查找）
        var leftBuf:Array  = this._leftBuf;
        var rightBuf:Array = this._rightBuf;
        var idxBuf:Array   = this._idxBuf;
        var sListBuf:Array = this._sListBuf;
        var sLeftBuf:Array = this._sLeftBuf;
        var sRightBuf:Array = this._sRightBuf;

        // 预热（3次，让 JIT/缓存行稳定）
        var w:Number;
        for (w = 0; w < 3; w++) {
            arrayCopy(origList, list, n);
            sortKernel(list, n, threshold,
                       leftBuf, rightBuf, idxBuf, sListBuf, sLeftBuf, sRightBuf);
        }

        // ---- 计时 ----
        var t0:Number = getTimer();
        for (var r:Number = 0; r < ITERS; r++) {
            arrayCopy(origList, list, n);
            sortKernel(list, n, threshold,
                       leftBuf, rightBuf, idxBuf, sListBuf, sLeftBuf, sRightBuf);
        }
        var t1:Number = getTimer();

        // 正确性验证（最后一次排序的结果）
        var ok:Boolean = this.verifySorted(list, leftBuf, n);

        var totalMs:Number   = t1 - t0;
        var msPerIter:Number = totalMs / ITERS;

        return {
            ms: msPerIter,
            msPer1k: msPerIter / Math.max(1, n) * 1000,
            ok: ok,
            iters: ITERS,
            totalMs: totalMs
        };
    }

    // ==================== 排序微内核 ====================
    // 完全复刻 TargetCacheUpdater.updateCache 第260-347行
    // 入参全部为局部引用，与生产代码性能特征一致

    private static function sortKernel(
        list:Array, len:Number, threshold:Number,
        leftValues:Array, rightValues:Array,
        indices:Array, sortedList:Array, sortedLeft:Array, sortedRight:Array
    ):Void {

        // ===== 预提取 left/right + isSorted 检测 =====
        leftValues.length  = len;
        rightValues.length = len;

        var isSorted:Boolean = true;
        var prevLeft:Number  = -Infinity;
        var k:Number  = 0;
        var unit:Object;
        var collider:Object;
        var lv:Number;

        while (k < len) {
            unit     = list[k];
            collider = unit.aabbCollider;
            lv       = collider.left;

            leftValues[k]  = lv;
            rightValues[k] = collider.right;

            if (isSorted && lv < prevLeft) {
                isSorted = false;
            }
            prevLeft = lv;
            k++;
        }

        // ===== 排序 =====
        if (!isSorted && len > 1) {
            if (len < threshold) {
                // ---- 内联插入排序（并行移动 list/left/right）----
                var arr:Array   = list;
                var lkeys:Array = leftValues;
                var rkeys:Array = rightValues;
                var i:Number = 1;
                var j:Number;
                var keyUnit:Object;
                var keyLeft:Number;
                var keyRight:Number;

                do {
                    keyUnit = arr[i];
                    keyLeft = lkeys[i];
                    if (lkeys[i - 1] <= keyLeft) continue;
                    keyRight = rkeys[i];

                    j = i - 1;
                    while (j >= 0 && lkeys[j] > keyLeft) {
                        arr[j + 1]   = arr[j];
                        lkeys[j + 1] = lkeys[j];
                        rkeys[j + 1] = rkeys[j];
                        j--;
                    }
                    arr[j + 1]   = keyUnit;
                    lkeys[j + 1] = keyLeft;
                    rkeys[j + 1] = keyRight;
                } while (++i < len);
            } else {
                // ---- sortIndirect + 投影回写 ----
                indices.length = len;
                for (k = 0; k < len; k++) indices[k] = k;

                TimSort.sortIndirect(indices, leftValues);

                sortedList.length  = len;
                sortedLeft.length  = len;
                sortedRight.length = len;

                for (k = 0; k < len; k++) {
                    var idx:Number = indices[k];
                    sortedList[k]  = list[idx];
                    sortedLeft[k]  = leftValues[idx];
                    sortedRight[k] = rightValues[idx];
                }
                for (k = 0; k < len; k++) {
                    list[k]        = sortedList[k];
                    leftValues[k]  = sortedLeft[k];
                    rightValues[k] = sortedRight[k];
                }
            }
        }
    }

    // ==================== 辅助 ====================

    private static function arrayCopy(src:Array, dst:Array, len:Number):Void {
        dst.length = len;
        for (var i:Number = 0; i < len; i++) dst[i] = src[i];
    }

    // ==================== 正确性验证 ====================

    private function verifySorted(list:Array, leftValues:Array, len:Number):Boolean {
        this.assertTotal++;

        // 非降序
        for (var i:Number = 1; i < len; i++) {
            if (leftValues[i - 1] > leftValues[i]) {
                this.assertFailed++;
                log("[FAIL] 排序错误 @" + i + ": " + leftValues[i-1] + " > " + leftValues[i]);
                return false;
            }
        }

        // leftValues 与 data.aabbCollider.left 对齐
        for (var j:Number = 0; j < len; j++) {
            if (list[j].aabbCollider.left != leftValues[j]) {
                this.assertFailed++;
                log("[FAIL] leftValues[" + j + "] 与 data 不一致");
                return false;
            }
        }

        return true;
    }

    // ==================== 数据分布 ====================

    private function makeUnits(dist:String, n:Number):Array {
        if (dist == "ascending")     return this.genAscending(n);
        if (dist == "descending")    return this.genDescending(n);
        if (dist == "random")        return this.genRandom(n);
        if (dist == "nearlySorted")  return this.genNearlySorted(n, 0.05);
        if (dist == "twoRuns")       return this.genTwoRuns(n);
        if (dist == "sawtooth")      return this.genSawtooth(n, Math.max(5, Math.floor(n / 10)));
        if (dist == "fewUniques")    return this.genFewUniques(n, Math.max(3, Math.floor(Math.sqrt(n))));
        if (dist == "allSame")       return this.genAllSame(n);
        return this.genRandom(n);
    }

    private function makeUnit(left:Number, id:Number):Object {
        return {
            _name: "tu_" + id,
            hp: 100,
            maxhp: 100,
            是否为敌人: ((id % 2) == 0),
            aabbCollider: { left: left, right: left + 20 }
        };
    }

    /** 升序 */
    private function genAscending(n:Number):Array {
        var A:Array = [];
        for (var i:Number = 0; i < n; i++) {
            A.push(this.makeUnit(i * 10 + this.srand() * 2, i));
        }
        return A;
    }

    /** 逆序 */
    private function genDescending(n:Number):Array {
        var A:Array = [];
        for (var i:Number = 0; i < n; i++) {
            A.push(this.makeUnit((n - 1 - i) * 10 + this.srand() * 2, i));
        }
        return A;
    }

    /** 完全随机 */
    private function genRandom(n:Number):Array {
        var A:Array = [];
        for (var i:Number = 0; i < n; i++) {
            A.push(this.makeUnit(this.rndRange(0, n * 10), i));
        }
        return A;
    }

    /** 近乎有序（5%元素交换） */
    private function genNearlySorted(n:Number, rate:Number):Array {
        var A:Array = this.genAscending(n);
        var swaps:Number = Math.max(1, Math.floor(n * rate));
        for (var s:Number = 0; s < swaps; s++) {
            var a:Number = Math.floor(this.srand() * n);
            var b:Number = Math.floor(this.srand() * n);
            var t:Object = A[a]; A[a] = A[b]; A[b] = t;
        }
        return A;
    }

    /**
     * 两段有序拼接（模拟"全体"请求从2个阵营桶收集后的真实数据形态）
     * [sorted_half_A, sorted_half_B] 值域交错
     */
    private function genTwoRuns(n:Number):Array {
        var half:Number = Math.floor(n / 2);
        var A:Array = [];
        // 第一段：偶数位置的值域
        for (var i:Number = 0; i < half; i++) {
            A.push(this.makeUnit(i * 20 + this.srand() * 4, i));
        }
        // 第二段：奇数位置的值域（与第一段交错）
        for (var j:Number = half; j < n; j++) {
            A.push(this.makeUnit((j - half) * 20 + 10 + this.srand() * 4, j));
        }
        return A;
    }

    /** 锯齿波 */
    private function genSawtooth(n:Number, period:Number):Array {
        var A:Array = [];
        for (var i:Number = 0; i < n; i++) {
            A.push(this.makeUnit((i % period) * 10, i));
        }
        return A;
    }

    /** 少量不同值 */
    private function genFewUniques(n:Number, k:Number):Array {
        var A:Array = [];
        for (var i:Number = 0; i < n; i++) {
            A.push(this.makeUnit(Math.floor(this.srand() * k) * 10, i));
        }
        return A;
    }

    /** 全部相同 */
    private function genAllSame(n:Number):Array {
        var A:Array = [];
        for (var i:Number = 0; i < n; i++) {
            A.push(this.makeUnit(500, i));
        }
        return A;
    }

    // ==================== 输出报表 ====================

    /** 表1: 阈值 × 规模 平均耗时(ms)，跨分布平均 */
    private function printSummaryBySize():Void {
        log("\n========== 表1: 阈值 × 规模 平均耗时(ms) ==========");

        var header:String = padR("threshold", 11);
        for (var si:Number = 0; si < this.sizes.length; si++) {
            header += padR("n=" + this.sizes[si], 10);
        }
        log(header);
        log(repeatStr("-", 11 + this.sizes.length * 10));

        for (var ti:Number = 0; ti < this.thresholds.length; ti++) {
            var line:String = padR(String(this.thresholds[ti]), 11);
            for (var sj:Number = 0; sj < this.sizes.length; sj++) {
                line += padR(fmt4(this.avgAcrossDists(ti, sj)), 10);
            }
            log(line);
        }
    }

    /** 表2: 最优阈值矩阵（行=规模, 列=分布） */
    private function printBestThresholdMatrix():Void {
        log("\n========== 表2: 最优阈值矩阵（行=规模, 列=分布）==========");

        var header:String = padR("n", 8);
        for (var di:Number = 0; di < this.dists.length; di++) {
            header += padR(this.dists[di], 14);
        }
        log(header);
        log(repeatStr("-", 8 + this.dists.length * 14));

        for (var si:Number = 0; si < this.sizes.length; si++) {
            var line:String = padR(String(this.sizes[si]), 8);
            for (var dj:Number = 0; dj < this.dists.length; dj++) {
                var best:Object = this.findBestThreshold(si, dj);
                line += padR(best.threshold + "(" + fmt4(best.ms) + ")", 14);
            }
            log(line);
        }
    }

    /** 表3: 总体排名 */
    private function printOverallRanking():Void {
        log("\n========== 表3: 总体排名（加权平均耗时）==========");

        var scores:Array = [];
        for (var ti:Number = 0; ti < this.thresholds.length; ti++) {
            var total:Number = 0;
            var count:Number = 0;
            for (var si:Number = 0; si < this.sizes.length; si++) {
                for (var di:Number = 0; di < this.dists.length; di++) {
                    total += this.results[ti][si][di].ms;
                    count++;
                }
            }
            scores.push({threshold: this.thresholds[ti], avg: total / count});
        }

        // 插入排序
        for (var i:Number = 1; i < scores.length; i++) {
            var key:Object = scores[i];
            var j:Number = i - 1;
            while (j >= 0 && scores[j].avg > key.avg) {
                scores[j + 1] = scores[j];
                j--;
            }
            scores[j + 1] = key;
        }

        log(padR("排名", 6) + padR("阈值", 8) + padR("平均ms", 12) + "相对最优");
        log(repeatStr("-", 40));
        var bestAvg:Number = scores[0].avg;
        for (var k:Number = 0; k < scores.length; k++) {
            var ratio:String = (bestAvg > 0)
                ? ("x" + fmt4(scores[k].avg / bestAvg))
                : "N/A";
            log(padR(String(k + 1), 6)
                + padR(String(scores[k].threshold), 8)
                + padR(fmt4(scores[k].avg), 12)
                + ratio);
        }
        log("\n★ 推荐阈值: " + scores[0].threshold
            + " (平均 " + fmt4(scores[0].avg) + "ms)");
    }

    /** 表4: 测量质量（每组的 totalMs/iters，验证信噪比） */
    private function printMeasurementQuality():Void {
        log("\n========== 表4: 测量质量（totalMs / iters）==========");
        log("  规模 ≤ 32 的单次排序在亚毫秒级，需要累积足够的 totalMs 才有意义。");
        log("  totalMs < 10 的数据点可靠性较低。\n");

        // 只打印第一个阈值（totalMs 随阈值变化不大，用于确认迭代次数是否充分）
        var header:String = padR("n", 8) + padR("iters", 8) + padR("totalMs", 10)
            + padR("ms/iter", 10) + "信噪比";
        log(header);
        log(repeatStr("-", 50));

        for (var si:Number = 0; si < this.sizes.length; si++) {
            // 取第一个阈值、random 分布的数据作为代表
            var sample:Object = this.results[0][si][0]; // ti=0, di=0(random)
            var quality:String;
            if (sample.totalMs >= 100) quality = "优";
            else if (sample.totalMs >= 20) quality = "良";
            else if (sample.totalMs >= 5) quality = "中";
            else quality = "差(噪声主导)";

            log(padR(String(this.sizes[si]), 8)
                + padR(String(sample.iters), 8)
                + padR(String(sample.totalMs), 10)
                + padR(fmt4(sample.ms), 10)
                + quality);
        }
    }

    // ==================== 统计辅助 ====================

    private function avgAcrossDists(ti:Number, si:Number):Number {
        var total:Number = 0;
        for (var di:Number = 0; di < this.dists.length; di++) {
            total += this.results[ti][si][di].ms;
        }
        return total / this.dists.length;
    }

    private function findBestThreshold(si:Number, di:Number):Object {
        var bestMs:Number = Infinity;
        var bestT:Number  = 0;
        for (var ti:Number = 0; ti < this.thresholds.length; ti++) {
            var ms:Number = this.results[ti][si][di].ms;
            if (ms < bestMs) {
                bestMs = ms;
                bestT  = this.thresholds[ti];
            }
        }
        return {threshold: bestT, ms: bestMs};
    }

    private function distIndex(dist:String):Number {
        for (var i:Number = 0; i < this.dists.length; i++) {
            if (this.dists[i] == dist) return i;
        }
        return 0;
    }

    // ==================== RNG ====================

    private function initRNG():Void {
        this.rng = LinearCongruentialEngine.getInstance();
        this.resetRNG(this.seed);
    }

    private function resetRNG(s:Number):Void {
        this.rng.init(1664525, 1013904223, 4294967296, s);
    }

    private function srand():Number {
        return this.rng.nextFloat();
    }

    private function rndRange(a:Number, b:Number):Number {
        return a + (b - a) * this.srand();
    }

    // ==================== 格式化 ====================

    private function log(msg:String):Void {
        if (_root.服务器 && _root.服务器.发布服务器消息) {
            _root.服务器.发布服务器消息(msg);
        } else {
            trace(msg);
        }
    }

    private static function padR(s:String, n:Number):String {
        var r:String = (s == null) ? "" : s;
        while (r.length < n) r += " ";
        return r;
    }

    private static function fmt4(v:Number):String {
        return String(Math.round(v * 10000) / 10000);
    }

    private static function repeatStr(ch:String, n:Number):String {
        var s:String = "";
        for (var i:Number = 0; i < n; i++) s += ch;
        return s;
    }
}
