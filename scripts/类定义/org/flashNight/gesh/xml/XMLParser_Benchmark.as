import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.string.StringUtils;

/**
 * XMLParser 性能基准测试
 *
 * 方法论（对齐 JSONTest）：
 * 1. 基线扣除 —— 每个计时循环配对一个等结构的空操作基线，中位数相减
 * 2. 多次采样中位数 —— 默认 5 轮采样取中位数，消除 GC / JIT 抖动
 * 3. 自动放大迭代次数 —— 校准阶段按指数增长直到中位总耗时达到目标阈值
 * 4. 低置信度标记 —— 若扣除后时间 < 30ms 且原始窗口不稳定，标记为低置信度
 * 5. 分相计时 —— 将 XML 解析拆为「原生 XML.parseXML」与「parseXMLNode」两阶段独立度量
 * 6. 热点隔离 —— 对 isValidXML / convertDataType / decodeHTML 做单独微基准
 * 7. 负载自校验 —— 在进入性能区前验证生成的 XML 变体确实不同、解析结果正确
 *
 * 入口：new XMLParser_Benchmark()
 */
class org.flashNight.gesh.xml.XMLParser_Benchmark {

    private var passCount:Number;
    private var failCount:Number;
    private var totalCount:Number;
    private var benchSink;

    // ========================================================================
    // 构造 & 入口
    // ========================================================================
    public function XMLParser_Benchmark() {
        this.passCount = 0;
        this.failCount = 0;
        this.totalCount = 0;
        this.benchSink = null;

        trace("╔══════════════════════════════════════════════════╗");
        trace("║       XMLParser 性能基准测试                     ║");
        trace("╚══════════════════════════════════════════════════╝");

        trace("\n========== 负载自校验 ==========");
        this.testWorkloadAssumptions();

        trace("\n---------- 自校验汇总 ----------");
        trace("通过: " + this.passCount + " / " + this.totalCount + "  失败: " + this.failCount);

        trace("\n========== 性能基准 ==========");
        this.benchPhaseBreakdown();
        this.benchParseMultiScale();
        this.benchHotspotProfile();

        trace("\n========== 测试结束 ==========");
    }

    // ========================================================================
    // 断言 & 辅助
    // ========================================================================
    private function assert(condition:Boolean, desc:String):Void {
        this.totalCount++;
        if (condition) {
            this.passCount++;
            trace("[PASS] " + desc);
        } else {
            this.failCount++;
            trace("[FAIL] " + desc);
        }
    }

    private function assertEqual(desc:String, expected, actual):Void {
        if (expected == null && actual == null) {
            this.assert(typeof expected == typeof actual, desc + " (expected type=" + typeof expected + ", actual type=" + typeof actual + ")");
            return;
        }
        this.assert(expected === actual, desc + " (expected=" + expected + ", actual=" + actual + ")");
    }

    private function toFixed2(n:Number):String {
        var rounded:Number = Math.round(n * 100) / 100;
        var s:String = String(rounded);
        if (s.indexOf(".") < 0) {
            s += ".00";
        } else {
            var dotPos:Number = s.indexOf(".");
            var decimals:Number = length(s) - dotPos - 1;
            while (decimals < 2) {
                s += "0";
                decimals++;
            }
        }
        return s;
    }

    private function toFixed3(n:Number):String {
        var rounded:Number = Math.round(n * 1000) / 1000;
        var s:String = String(rounded);
        if (s.indexOf(".") < 0) {
            s += ".000";
        } else {
            var dotPos:Number = s.indexOf(".");
            var decimals:Number = length(s) - dotPos - 1;
            while (decimals < 3) {
                s += "0";
                decimals++;
            }
        }
        return s;
    }

    // ========================================================================
    // 统计原语（与 JSONTest 等价）
    // ========================================================================
    private function median(arr:Array):Number {
        var n:Number = arr.length;
        var sorted:Array = [];
        var i:Number = 0;
        while (i < n) {
            sorted[i] = arr[i];
            i++;
        }
        i = 1;
        while (i < n) {
            var v:Number = sorted[i];
            var j:Number = i - 1;
            while (j >= 0 && sorted[j] > v) {
                sorted[j + 1] = sorted[j];
                j--;
            }
            sorted[j + 1] = v;
            i++;
        }
        if (n % 2 == 1) {
            return sorted[(n - 1) / 2];
        }
        return (sorted[n / 2 - 1] + sorted[n / 2]) / 2;
    }

    private function minValue(arr:Array):Number {
        var v:Number = arr[0];
        var i:Number = 1;
        while (i < arr.length) {
            if (arr[i] < v) {
                v = arr[i];
            }
            i++;
        }
        return v;
    }

    private function maxValue(arr:Array):Number {
        var v:Number = arr[0];
        var i:Number = 1;
        while (i < arr.length) {
            if (arr[i] > v) {
                v = arr[i];
            }
            i++;
        }
        return v;
    }

    // ========================================================================
    // 核心度量引擎（与 JSONTest 等价）
    // ========================================================================

    /**
     * 从原始/基线采样数组构建统计对象。
     * 置信度判定：扣除后中位 >= 30ms，或 >= 12ms 且原始窗口稳定。
     */
    private function buildBenchStats(totalTimes:Array, baselineTimes:Array,
                                     iterations:Number, payloadChars:Number,
                                     opsPerIteration:Number):Object {
        var adjustedTimes:Array = [];
        var i:Number = 0;
        while (i < totalTimes.length) {
            var adjusted:Number = Number(totalTimes[i]) - Number(baselineTimes[i]);
            if (adjusted < 0) {
                adjusted = 0;
            }
            adjustedTimes[i] = adjusted;
            i++;
        }

        var stats:Object = {};
        stats.iterations = iterations;
        stats.opsPerIteration = opsPerIteration;
        stats.totalOps = iterations * opsPerIteration;
        stats.rawTotalMedianMs = this.median(totalTimes);
        stats.rawBaselineMedianMs = this.median(baselineTimes);
        stats.totalMedianMs = this.median(adjustedTimes);
        stats.perOpMs = (stats.totalOps > 0) ? (stats.totalMedianMs / stats.totalOps) : 0;
        stats.minTotalMs = this.minValue(adjustedTimes);
        stats.maxTotalMs = this.maxValue(adjustedTimes);
        stats.rawTotalRangeMs = this.maxValue(totalTimes) - this.minValue(totalTimes);
        stats.rawBaselineRangeMs = this.maxValue(baselineTimes) - this.minValue(baselineTimes);

        var stableRawWindow:Boolean = stats.rawTotalMedianMs >= 80 &&
            stats.rawBaselineMedianMs >= 20 &&
            stats.rawTotalRangeMs <= (stats.rawTotalMedianMs * 0.08 + 2) &&
            stats.rawBaselineRangeMs <= (stats.rawBaselineMedianMs * 0.10 + 2);
        stats.reliable = stats.totalMedianMs >= 30 || (stats.totalMedianMs >= 12 && stableRawWindow);
        stats.timerFloor = (stats.totalMedianMs <= 0) ||
            (!stats.reliable && stats.rawTotalMedianMs < 30);

        if (payloadChars > 0 && stats.totalMedianMs > 0) {
            stats.mbPerSec = (payloadChars * stats.totalOps / 1048576) / (stats.totalMedianMs / 1000);
        } else {
            stats.mbPerSec = 0;
        }
        return stats;
    }

    /**
     * 采样：预热一轮后交替采集 repeats 轮基线与被测数据。
     */
    private function sampleBenchStats(timedFn:Function, baselineFn:Function,
                                      iterations:Number, repeats:Number,
                                      payloadChars:Number, opsPerIteration:Number):Object {
        // 预热
        timedFn(iterations);
        baselineFn(iterations);

        var totalTimes:Array = [];
        var baselineTimes:Array = [];
        var r:Number = 0;
        while (r < repeats) {
            baselineTimes[r] = Number(baselineFn(iterations));
            totalTimes[r] = Number(timedFn(iterations));
            r++;
        }
        return this.buildBenchStats(totalTimes, baselineTimes, iterations, payloadChars, opsPerIteration);
    }

    /**
     * 计算迭代次数增长倍率（2~8x）。
     */
    private function computeIterationGrowth(stats:Object, targetAdjustedMs:Number, targetRawTotalMs:Number):Number {
        var adjustedScale:Number = 1;
        var rawScale:Number = 1;
        if (targetAdjustedMs > 0) {
            if (stats.totalMedianMs > 0) {
                adjustedScale = targetAdjustedMs / stats.totalMedianMs;
            } else {
                adjustedScale = 8;
            }
        }
        if (targetRawTotalMs > 0) {
            if (stats.rawTotalMedianMs > 0) {
                rawScale = targetRawTotalMs / stats.rawTotalMedianMs;
            } else {
                rawScale = 8;
            }
        }
        var scale:Number = Math.ceil(Math.max(adjustedScale, rawScale));
        if (scale < 2) {
            scale = 2;
        } else if (scale > 8) {
            scale = 8;
        }
        return scale;
    }

    /**
     * 校准迭代次数：从 startIterations 出发指数增长直到达标或上限。
     */
    private function calibrateIterations(timedFn:Function, baselineFn:Function,
                                         targetAdjustedMs:Number, targetRawTotalMs:Number,
                                         startIterations:Number, maxIterations:Number,
                                         opsPerIteration:Number):Number {
        var iterations:Number = startIterations;
        if (iterations < 1) {
            iterations = 1;
        }
        var round:Number = 0;
        while (round < 8) {
            var probe:Object = this.sampleBenchStats(timedFn, baselineFn, iterations, 3, 0, opsPerIteration);
            if ((probe.totalMedianMs >= targetAdjustedMs && probe.rawTotalMedianMs >= targetRawTotalMs) || iterations >= maxIterations) {
                break;
            }
            var growth:Number = this.computeIterationGrowth(probe, targetAdjustedMs, targetRawTotalMs);
            var scaled:Number = iterations * growth;
            if (scaled <= iterations) {
                scaled = iterations * 2;
            }
            iterations = scaled;
            if (iterations > maxIterations) {
                iterations = maxIterations;
            }
            round++;
        }
        return iterations;
    }

    /**
     * 完整度量：校准 → 采样 → 若未达标再精炼。
     */
    private function measureBenchStats(timedFn:Function, baselineFn:Function,
                                       targetAdjustedMs:Number, targetRawTotalMs:Number,
                                       startIterations:Number, maxIterations:Number,
                                       repeats:Number, payloadChars:Number,
                                       opsPerIteration:Number):Object {
        if (opsPerIteration == undefined || opsPerIteration < 1) {
            opsPerIteration = 1;
        }
        var iterations:Number = this.calibrateIterations(timedFn, baselineFn, targetAdjustedMs, targetRawTotalMs, startIterations, maxIterations, opsPerIteration);
        var stats:Object = this.sampleBenchStats(timedFn, baselineFn, iterations, repeats, payloadChars, opsPerIteration);

        var refineRound:Number = 0;
        while (refineRound < 4 &&
               iterations < maxIterations &&
               (stats.totalMedianMs < targetAdjustedMs || stats.rawTotalMedianMs < targetRawTotalMs)) {
            var growth:Number = this.computeIterationGrowth(stats, targetAdjustedMs, targetRawTotalMs);
            var nextIterations:Number = iterations * growth;
            if (nextIterations <= iterations) {
                nextIterations = iterations * 2;
            }
            if (nextIterations > maxIterations) {
                nextIterations = maxIterations;
            }
            if (nextIterations == iterations) {
                break;
            }
            iterations = nextIterations;
            stats = this.sampleBenchStats(timedFn, baselineFn, iterations, repeats, payloadChars, opsPerIteration);
            refineRound++;
        }
        return stats;
    }

    // ========================================================================
    // 报告
    // ========================================================================
    private function reportBenchStats(label:String, stats:Object):Void {
        var line:String = "    " + label;
        if (stats.timerFloor) {
            line += "低于计时分辨率";
        } else if (stats.perOpMs < 0.1) {
            line += this.toFixed2(stats.perOpMs * 1000) + " us/次";
        } else {
            line += this.toFixed3(stats.perOpMs) + " ms/次";
        }
        if (stats.opsPerIteration > 1) {
            line += " | " + stats.iterations + " 批/轮 x" + stats.opsPerIteration + " = " + stats.totalOps + " 次";
        } else {
            line += " | " + stats.iterations + " 次/轮";
        }
        line += " | 中位总 " + this.toFixed2(stats.totalMedianMs) + " ms";
        if (stats.mbPerSec > 0) {
            line += " | " + this.toFixed2(stats.mbPerSec) + " MB/s";
        }
        if (stats.minTotalMs > 0) {
            line += " | 波动 " + this.toFixed2(stats.maxTotalMs / stats.minTotalMs) + "x";
        }
        if (!stats.reliable && stats.rawTotalMedianMs > 0) {
            line += " | 原始/基线 " + this.toFixed2(stats.rawTotalMedianMs) + "/" + this.toFixed2(stats.rawBaselineMedianMs) + " ms";
        }
        if (!stats.reliable) {
            line += " | ⚠低置信度";
        }
        trace(line);
    }

    private function reportRatio(label:String, numerator:Object, denominator:Object):Void {
        if (numerator.perOpMs > 0 && denominator.perOpMs > 0 &&
            numerator.reliable && denominator.reliable &&
            !numerator.timerFloor && !denominator.timerFloor) {
            trace("    " + label + this.toFixed2(numerator.perOpMs / denominator.perOpMs) + "x");
        } else {
            trace("    " + label + "n/a（低置信度）");
        }
    }

    private function reportPhaseShare(label:String, phaseStats:Object, totalStats:Object):Void {
        if (phaseStats.reliable && totalStats.reliable &&
            !phaseStats.timerFloor && !totalStats.timerFloor &&
            totalStats.perOpMs > 0) {
            var pct:Number = Math.round(phaseStats.perOpMs / totalStats.perOpMs * 100);
            trace("    " + label + pct + "% (" + this.toFixed3(phaseStats.perOpMs) + " / " + this.toFixed3(totalStats.perOpMs) + " ms)");
        } else {
            trace("    " + label + "n/a（低置信度）");
        }
    }

    // ========================================================================
    // XML 数据生成器
    // ========================================================================

    /**
     * 生成模拟游戏配置 XML 字符串。
     * 结构模拟 data/items/ 下的真实武器/装备 XML：
     *   <root>
     *     <metadata version="1.0" count="N" seed="S" />
     *     <item id="0" name="item_0" value="0" enabled="true">
     *       <tags><tag>t0</tag><tag>common</tag></tags>
     *       <Description>&lt;p&gt;Desc 0&lt;/p&gt;</Description>
     *     </item>
     *     ...
     *   </root>
     */
    private function generateBenchXML(itemCount:Number, seed:Number):String {
        if (seed == undefined) {
            seed = 0;
        }
        var s:String = '<root><metadata version="1.0" count="' + itemCount + '" seed="' + seed + '" active="true"/>';
        var i:Number = 0;
        while (i < itemCount) {
            var id:Number = i + seed;
            var val:Number = i * 1.5 + seed;
            var enabled:String = ((i % 2 == 0) ? "true" : "false");
            s += '<item id="' + id + '" name="item_' + i + '" value="' + val + '" enabled="' + enabled + '">';
            s += '<tags><tag>t' + i + '</tag><tag>common</tag></tags>';
            // 每 5 个 item 包含 HTML 实体（模拟 Description 节点）
            if (i % 5 == 0) {
                s += '<Description>&lt;p&gt;Desc ' + i + '&lt;/p&gt;</Description>';
            }
            s += '</item>';
            i++;
        }
        s += '<config maxRetry="3" timeout="5000" debug="false" label="benchmark"/></root>';
        return s;
    }

    /**
     * 生成 count 个不同 seed 的 XML 变体。
     */
    private function generateXMLVariants(itemCount:Number, count:Number):Array {
        var variants:Array = [];
        var i:Number = 0;
        while (i < count) {
            variants[i] = this.generateBenchXML(itemCount, i);
            i++;
        }
        return variants;
    }

    /**
     * 将 XML 字符串批量预解析为 XMLNode 数组（用于隔离 parseXMLNode 阶段）。
     */
    private function preParseToNodes(xmlStrings:Array):Array {
        var nodes:Array = [];
        var i:Number = 0;
        while (i < xmlStrings.length) {
            var xml:XML = new XML();
            xml.ignoreWhite = true;
            xml.parseXML(xmlStrings[i]);
            nodes[i] = xml.firstChild;
            i++;
        }
        return nodes;
    }

    /**
     * 生成深层嵌套 XML。
     */
    private function generateDeepXML(depth:Number):String {
        var s:String = "<leaf>1</leaf>";
        var i:Number = 0;
        while (i < depth) {
            s = "<level" + i + ">" + s + "</level" + i + ">";
            i++;
        }
        return "<root>" + s + "</root>";
    }

    /**
     * 生成用于 convertDataType 微基准的值数组。
     */
    private function generateConvertValues(count:Number):Array {
        var values:Array = [];
        var i:Number = 0;
        while (i < count) {
            var mod:Number = i % 6;
            if (mod == 0) {
                values[i] = String(i * 1.5);      // 浮点数
            } else if (mod == 1) {
                values[i] = String(i);             // 整数
            } else if (mod == 2) {
                values[i] = "true";                // 布尔 true
            } else if (mod == 3) {
                values[i] = "false";               // 布尔 false
            } else if (mod == 4) {
                values[i] = "item_" + i;           // 纯字符串
            } else {
                values[i] = "-" + String(i * 0.7); // 负浮点
            }
            i++;
        }
        return values;
    }

    /**
     * 生成用于 decodeHTML 微基准的字符串数组。
     */
    private function generateHTMLStrings(count:Number):Array {
        var values:Array = [];
        var i:Number = 0;
        while (i < count) {
            if (i % 3 == 0) {
                // 含实体
                values[i] = "&lt;p&gt;Hello &amp; World " + i + "&lt;/p&gt;";
            } else if (i % 3 == 1) {
                // 无实体（短路快速路径的候选）
                values[i] = "Just plain text number " + i;
            } else {
                // 含引号实体
                values[i] = "&quot;Value " + i + "&quot; is &lt;good&gt;";
            }
            i++;
        }
        return values;
    }

    // ========================================================================
    // 计时循环 —— 全流水线
    // ========================================================================

    /**
     * 全流水线：XML 字符串 → new XML().parseXML() → parseXMLNode() → Object
     */
    private function timeFullPipelineLoop(xmlStr:String, iterations:Number):Number {
        var sink:Object = null;
        var xml:XML;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            xml = new XML();
            xml.ignoreWhite = true;
            xml.parseXML(xmlStr);
            sink = XMLParser.parseXMLNode(xml.firstChild);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * 全流水线基线：仅读取字符串（模拟循环开销）。
     */
    private function timeFullPipelineBaseline(xmlStr:String, iterations:Number):Number {
        var sink:String = "";
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = xmlStr;
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    // ========================================================================
    // 计时循环 —— 分相：原生 XML.parseXML
    // ========================================================================

    /**
     * 阶段 1：仅原生 XML.parseXML()（C++ 部分）。
     */
    private function timeNativeParseLoop(xmlStr:String, iterations:Number):Number {
        var xml:XML;
        var sink:XMLNode = null;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            xml = new XML();
            xml.ignoreWhite = true;
            xml.parseXML(xmlStr);
            sink = xml.firstChild;
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    // ========================================================================
    // 计时循环 —— 分相：parseXMLNode
    // ========================================================================

    /**
     * 阶段 2：仅 parseXMLNode()（AS2 部分）。
     * 输入为预解析好的 XMLNode。
     * 注意：XMLNode 是引用不会被消耗，可重复解析。
     */
    private function timeParseXMLNodeLoop(node:XMLNode, iterations:Number):Number {
        var sink:Object = null;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = XMLParser.parseXMLNode(node);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * 阶段 2 基线：仅读取节点引用。
     */
    private function timeNodeReadBaseline(node:XMLNode, iterations:Number):Number {
        var sink:XMLNode = null;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = node;
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    // ========================================================================
    // 计时循环 —— 变体批次（模拟无缓存冷路径）
    // ========================================================================

    /**
     * 全流水线变体循环：轮转不同 XML 字符串避免任何可能的引擎级缓存。
     */
    private function timeFullPipelineVariantLoop(variants:Array, iterations:Number, batchSize:Number):Number {
        var sink:Object = null;
        var vLen:Number = variants.length;
        var idx:Number = 0;
        var xml:XML;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                xml = new XML();
                xml.ignoreWhite = true;
                xml.parseXML(variants[idx]);
                sink = XMLParser.parseXMLNode(xml.firstChild);
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * 变体基线：仅轮转读取字符串。
     */
    private function timeVariantReadBaseline(variants:Array, iterations:Number, batchSize:Number):Number {
        var sink:String = "";
        var vLen:Number = variants.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = variants[idx];
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * parseXMLNode 变体循环：轮转预解析的 XMLNode 数组。
     */
    private function timeParseNodeVariantLoop(nodes:Array, iterations:Number, batchSize:Number):Number {
        var sink:Object = null;
        var vLen:Number = nodes.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = XMLParser.parseXMLNode(nodes[idx]);
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * 节点变体基线：仅轮转读取节点引用。
     */
    private function timeNodeVariantReadBaseline(nodes:Array, iterations:Number, batchSize:Number):Number {
        var sink:XMLNode = null;
        var vLen:Number = nodes.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = nodes[idx];
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    // ========================================================================
    // 计时循环 —— 热点隔离
    // ========================================================================

    /**
     * isValidXML 隔离计时。
     */
    private function timeIsValidXMLLoop(node:XMLNode, iterations:Number):Number {
        var sink:Boolean = false;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            sink = XMLParser.isValidXML(node);
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * convertDataType 隔离计时：轮转预生成的值数组。
     */
    private function timeConvertDataTypeLoop(values:Array, iterations:Number, batchSize:Number):Number {
        var sink = null;
        var vLen:Number = values.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = XMLParser.convertDataType(values[idx]);
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * convertDataType 基线：仅读取值数组。
     */
    private function timeConvertValueReadBaseline(values:Array, iterations:Number, batchSize:Number):Number {
        var sink:String = "";
        var vLen:Number = values.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = values[idx];
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * StringUtils.decodeHTML 隔离计时。
     */
    private function timeDecodeHTMLLoop(htmlStrings:Array, iterations:Number, batchSize:Number):Number {
        var sink:String = "";
        var vLen:Number = htmlStrings.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = StringUtils.decodeHTML(htmlStrings[idx]);
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * decodeHTML 基线：仅读取字符串数组。
     */
    private function timeHTMLReadBaseline(htmlStrings:Array, iterations:Number, batchSize:Number):Number {
        var sink:String = "";
        var vLen:Number = htmlStrings.length;
        var idx:Number = 0;
        var i:Number = 0;
        var j:Number = 0;
        if (batchSize == undefined || batchSize < 1) {
            batchSize = 1;
        }
        var t0:Number = getTimer();
        while (i < iterations) {
            j = 0;
            while (j < batchSize) {
                sink = htmlStrings[idx];
                idx++;
                if (idx >= vLen) {
                    idx = 0;
                }
                j++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    // ========================================================================
    // 负载自校验
    // ========================================================================
    private function testWorkloadAssumptions():Void {
        trace("\n--- 负载自校验 ---");

        // 1. 变体生成验证
        var variants:Array = this.generateXMLVariants(6, 4);
        this.assertEqual("生成 XML 变体数量", 4, variants.length);
        this.assert(variants[0] !== variants[1], "相邻 XML 变体字符串不同");
        this.assert(variants[0] !== variants[2], "非相邻 XML 变体字符串不同");

        // 2. 解析正确性验证
        var xml0:XML = new XML();
        xml0.ignoreWhite = true;
        xml0.parseXML(variants[0]);
        var parsed0:Object = XMLParser.parseXMLNode(xml0.firstChild);
        this.assert(parsed0 != null, "变体 0 解析不为 null");
        this.assertEqual("变体 0 metadata.seed", 0, parsed0.metadata.seed);
        this.assertEqual("变体 0 metadata.count", 6, parsed0.metadata.count);
        this.assert(parsed0.item instanceof Array, "变体 0 item 为数组");
        this.assertEqual("变体 0 item 长度", 6, parsed0.item.length);
        this.assertEqual("变体 0 首项 id", 0, parsed0.item[0].id);
        this.assert(parsed0.item[0].tags != undefined, "变体 0 首项有 tags");

        var xml1:XML = new XML();
        xml1.ignoreWhite = true;
        xml1.parseXML(variants[1]);
        var parsed1:Object = XMLParser.parseXMLNode(xml1.firstChild);
        this.assertEqual("变体 1 metadata.seed", 1, parsed1.metadata.seed);
        this.assertEqual("变体 1 首项 id", 1, parsed1.item[0].id);

        // 3. 预解析节点验证
        var nodes:Array = this.preParseToNodes(variants);
        this.assertEqual("预解析节点数量", 4, nodes.length);
        this.assert(nodes[0] != null, "预解析节点 0 不为 null");
        var reparsed:Object = XMLParser.parseXMLNode(nodes[0]);
        this.assertEqual("预解析后重新 parseXMLNode 的 seed", 0, reparsed.metadata.seed);

        // 4. Description 节点（HTML 实体）验证
        this.assert(parsed0.item[0].Description != undefined, "首项有 Description");
        // Description 含 HTML 实体，parseXMLNode 内部会 decodeHTML
        var desc:String = String(parsed0.item[0].Description);
        this.assert(desc.indexOf("<p>") >= 0 || desc.indexOf("&lt;") >= 0, "Description 含已解码或原始 HTML");

        // 5. convertDataType 值数组验证
        var values:Array = this.generateConvertValues(12);
        this.assertEqual("convertDataType 值数组长度", 12, values.length);
        this.assert(typeof values[0] == "string", "值数组元素为字符串");

        // 6. decodeHTML 字符串数组验证
        var htmlStrs:Array = this.generateHTMLStrings(6);
        this.assertEqual("decodeHTML 字符串数组长度", 6, htmlStrs.length);
        this.assert(htmlStrs[0].indexOf("&lt;") >= 0, "含实体的 HTML 字符串正确");
        this.assert(htmlStrs[1].indexOf("&") < 0, "无实体的纯文本字符串正确");

        // 7. 深层嵌套 XML 验证
        var deepXml:String = this.generateDeepXML(10);
        var deepParsed:XML = new XML();
        deepParsed.ignoreWhite = true;
        deepParsed.parseXML(deepXml);
        this.assert(deepParsed.firstChild != null, "深层嵌套 XML 解析成功");
        var deepObj:Object = XMLParser.parseXMLNode(deepParsed.firstChild);
        this.assert(deepObj != null, "深层嵌套 XML parseXMLNode 成功");
    }

    // ========================================================================
    // 基准 1：分相分解（固定中等规模）
    // ========================================================================
    private function benchPhaseBreakdown():Void {
        trace("\n--- 分相分解（50 项） ---");
        trace("  说明: 将全流水线拆为「原生 XML.parseXML」与「XMLParser.parseXMLNode」两阶段");
        trace("        独立度量，定位时间到底花在 C++ 还是 AS2。");

        var itemCount:Number = 50;
        var xmlStr:String = this.generateBenchXML(itemCount, 0);
        var payloadChars:Number = length(xmlStr);
        var repeats:Number = 5;
        var targetMs:Number = 120;

        // 预解析一份 XMLNode 供阶段 2 使用
        var preXml:XML = new XML();
        preXml.ignoreWhite = true;
        preXml.parseXML(xmlStr);
        var preNode:XMLNode = preXml.firstChild;

        var self:XMLParser_Benchmark = this;

        trace("\n  " + itemCount + " 项 | " + payloadChars + " 字符");

        // 全流水线
        var fullStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeFullPipelineLoop(xmlStr, iterations); },
            function(iterations:Number):Number { return self.timeFullPipelineBaseline(xmlStr, iterations); },
            targetMs, 0, 4, 512, repeats, payloadChars, 1
        );
        this.reportBenchStats("全流水线:      ", fullStats);

        // 阶段 1：原生解析
        var nativeStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeNativeParseLoop(xmlStr, iterations); },
            function(iterations:Number):Number { return self.timeFullPipelineBaseline(xmlStr, iterations); },
            targetMs, 0, 4, 512, repeats, payloadChars, 1
        );
        this.reportBenchStats("原生 parseXML: ", nativeStats);

        // 阶段 2：parseXMLNode
        var nodeStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeParseXMLNodeLoop(preNode, iterations); },
            function(iterations:Number):Number { return self.timeNodeReadBaseline(preNode, iterations); },
            targetMs, 0, 4, 1024, repeats, payloadChars, 1
        );
        this.reportBenchStats("parseXMLNode:  ", nodeStats);

        // 占比报告
        trace("    --");
        this.reportPhaseShare("原生占全流水线: ", nativeStats, fullStats);
        this.reportPhaseShare("parseXMLNode 占全流水线: ", nodeStats, fullStats);
        var sumMs:Number = nativeStats.perOpMs + nodeStats.perOpMs;
        if (fullStats.reliable && nativeStats.reliable && nodeStats.reliable && fullStats.perOpMs > 0) {
            var overhead:Number = Math.round((fullStats.perOpMs - sumMs) / fullStats.perOpMs * 100);
            trace("    分相加总 vs 全流水线偏差: " + overhead + "% (正常应 <10%)");
        }
    }

    // ========================================================================
    // 基准 2：多规模 parseXMLNode（变体冷路径）
    // ========================================================================
    private function benchParseMultiScale():Void {
        trace("\n--- parseXMLNode 多规模基准（变体冷路径 + 基线扣除） ---");
        trace("  说明: 使用不同 seed 的 XML 变体轮转，避免 AVM 内部可能的字符串缓存。");
        trace("        分别度量全流水线与纯 parseXMLNode 阶段。");

        var scales:Array = [
            {items: 10, desc: "小(10项)", start: 8, max: 512, variants: 64, batch: 32},
            {items: 50, desc: "中(50项)", start: 4, max: 256, variants: 64, batch: 32},
            {items: 200, desc: "大(200项)", start: 2, max: 64, variants: 32, batch: 16}
        ];
        var repeats:Number = 5;
        var targetMs:Number = 120;
        var coldTargetMs:Number = 240;
        var self:XMLParser_Benchmark = this;

        var si:Number = 0;
        while (si < scales.length) {
            var scale:Object = scales[si];
            var sampleXml:String = this.generateBenchXML(scale.items, 0);
            var variants:Array = this.generateXMLVariants(scale.items, scale.variants);
            var nodes:Array = this.preParseToNodes(variants);
            var payloadChars:Number = length(sampleXml);

            trace("\n  " + scale.desc + " | " + payloadChars + " 字符 | " + scale.variants + " 变体");

            // 全流水线（变体冷路径）
            var fullStats:Object = this.measureBenchStats(
                function(iterations:Number):Number { return self.timeFullPipelineVariantLoop(variants, iterations, scale.batch); },
                function(iterations:Number):Number { return self.timeVariantReadBaseline(variants, iterations, scale.batch); },
                coldTargetMs, 120, scale.start, scale.max, repeats, payloadChars, scale.batch
            );
            this.reportBenchStats("全流水线(冷):   ", fullStats);

            // 纯 parseXMLNode（变体冷路径）
            var nodeStats:Object = this.measureBenchStats(
                function(iterations:Number):Number { return self.timeParseNodeVariantLoop(nodes, iterations, scale.batch); },
                function(iterations:Number):Number { return self.timeNodeVariantReadBaseline(nodes, iterations, scale.batch); },
                coldTargetMs, 120, scale.start, scale.max * 2, repeats, payloadChars, scale.batch
            );
            this.reportBenchStats("parseXMLNode(冷): ", nodeStats);

            // 单字符串热路径（同一 XMLNode 重复解析）
            var preXml:XML = new XML();
            preXml.ignoreWhite = true;
            preXml.parseXML(sampleXml);
            var hotNode:XMLNode = preXml.firstChild;
            var hotStats:Object = this.measureBenchStats(
                function(iterations:Number):Number { return self.timeParseXMLNodeLoop(hotNode, iterations); },
                function(iterations:Number):Number { return self.timeNodeReadBaseline(hotNode, iterations); },
                targetMs, 0, scale.start * 4, scale.max * 4, repeats, payloadChars, 1
            );
            this.reportBenchStats("parseXMLNode(热): ", hotStats);

            trace("    --");
            this.reportPhaseShare("parseXMLNode 占全流水线: ", nodeStats, fullStats);
            this.reportRatio("parseXMLNode 冷/热 = ", nodeStats, hotStats);

            si++;
        }
    }

    // ========================================================================
    // 基准 3：热点剖析（微基准）
    // ========================================================================
    private function benchHotspotProfile():Void {
        trace("\n--- 热点剖析（微基准） ---");
        trace("  说明: 对 isValidXML / convertDataType / decodeHTML 独立计时，");
        trace("        定位 parseXMLNode 内部的时间分布。");

        var repeats:Number = 5;
        var targetMs:Number = 120;
        var self:XMLParser_Benchmark = this;

        // --- isValidXML ---
        trace("\n  isValidXML（50 项 XML 的根节点）");
        var xmlStr50:String = this.generateBenchXML(50, 0);
        var xmlPre50:XML = new XML();
        xmlPre50.ignoreWhite = true;
        xmlPre50.parseXML(xmlStr50);
        var node50:XMLNode = xmlPre50.firstChild;

        var validStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeIsValidXMLLoop(node50, iterations); },
            function(iterations:Number):Number { return self.timeNodeReadBaseline(node50, iterations); },
            targetMs, 0, 8, 2048, repeats, 0, 1
        );
        this.reportBenchStats("isValidXML:     ", validStats);

        // parseXMLNode 总时间作参照
        var nodeRef:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeParseXMLNodeLoop(node50, iterations); },
            function(iterations:Number):Number { return self.timeNodeReadBaseline(node50, iterations); },
            targetMs, 0, 4, 1024, repeats, 0, 1
        );
        this.reportBenchStats("parseXMLNode:   ", nodeRef);
        this.reportPhaseShare("isValidXML 占 parseXMLNode: ", validStats, nodeRef);

        // --- convertDataType ---
        trace("\n  convertDataType（240 值轮转）");
        var convertValues:Array = this.generateConvertValues(240);
        var convertBatch:Number = 60;

        var convertStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeConvertDataTypeLoop(convertValues, iterations, convertBatch); },
            function(iterations:Number):Number { return self.timeConvertValueReadBaseline(convertValues, iterations, convertBatch); },
            targetMs, 120, 4, 4096, repeats, 0, convertBatch
        );
        this.reportBenchStats("convertDataType: ", convertStats);

        // --- decodeHTML ---
        trace("\n  StringUtils.decodeHTML（90 字符串轮转）");
        var htmlStrings:Array = this.generateHTMLStrings(90);
        var htmlBatch:Number = 30;

        var decodeWithEntityStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeDecodeHTMLLoop(htmlStrings, iterations, htmlBatch); },
            function(iterations:Number):Number { return self.timeHTMLReadBaseline(htmlStrings, iterations, htmlBatch); },
            targetMs, 120, 4, 4096, repeats, 0, htmlBatch
        );
        this.reportBenchStats("decodeHTML(混合): ", decodeWithEntityStats);

        // 纯含实体字符串
        var entityOnly:Array = [];
        var ei:Number = 0;
        while (ei < 90) {
            entityOnly[ei] = "&lt;p&gt;Hello &amp; World " + ei + "&lt;/p&gt;";
            ei++;
        }
        var decodeEntityOnlyStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeDecodeHTMLLoop(entityOnly, iterations, htmlBatch); },
            function(iterations:Number):Number { return self.timeHTMLReadBaseline(entityOnly, iterations, htmlBatch); },
            targetMs, 120, 4, 4096, repeats, 0, htmlBatch
        );
        this.reportBenchStats("decodeHTML(纯实体): ", decodeEntityOnlyStats);

        // 纯无实体字符串
        var plainOnly:Array = [];
        var pi:Number = 0;
        while (pi < 90) {
            plainOnly[pi] = "Just plain text number " + pi;
            pi++;
        }
        var decodePlainOnlyStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeDecodeHTMLLoop(plainOnly, iterations, htmlBatch); },
            function(iterations:Number):Number { return self.timeHTMLReadBaseline(plainOnly, iterations, htmlBatch); },
            targetMs, 120, 4, 4096, repeats, 0, htmlBatch
        );
        this.reportBenchStats("decodeHTML(纯文本): ", decodePlainOnlyStats);

        trace("    --");
        this.reportRatio("纯实体 / 纯文本 = ", decodeEntityOnlyStats, decodePlainOnlyStats);
        trace("    （若比值 >> 1 则说明短路优化有价值）");
    }
}
