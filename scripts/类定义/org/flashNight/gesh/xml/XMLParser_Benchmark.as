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
        this.benchStartupCorpus();

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
     * 收集 XMLNode 树中所有元素节点（nodeType == 1），
     * 用于模拟 parseXMLNode 递归中每层都调用 isValidXML 的累积成本。
     */
    private function collectElementNodes(node:XMLNode, out:Array):Void {
        if (node == null) return;
        if (node.nodeType == 1) { // ELEMENT_NODE
            out.push(node);
        }
        var i:Number = 0;
        while (i < node.childNodes.length) {
            this.collectElementNodes(node.childNodes[i], out);
            i++;
        }
    }

    /**
     * 生成每个 item 都带 Description 的密集 XML（用于 Description 路径压力测试）。
     */
    private function generateDenseDescriptionXML(itemCount:Number, seed:Number):String {
        if (seed == undefined) {
            seed = 0;
        }
        var s:String = '<root><metadata version="1.0" count="' + itemCount + '" seed="' + seed + '"/>';
        var i:Number = 0;
        while (i < itemCount) {
            s += '<item id="' + (i + seed) + '">';
            s += '<Description>&lt;p&gt;Desc &amp; detail ' + i + '&lt;/p&gt;</Description>';
            s += '</item>';
            i++;
        }
        s += '</root>';
        return s;
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

    /**
     * 生成匹配真实 data/items/*.xml 结构的武器 XML。
     * 结构: root > item(weapontype属性) > name/displayname/icon/type/use/price/description/data
     *        data > level/weight/dressup/capacity/split/diffusion/interval/velocity/bullet/
     *               sound/muzzle/bullethit/clipname/bulletsize/power/impact/reloadPenalty
     * 每 item 约 8 直接子节点 + data 含 17 子节点 = 25 节点，全部唯一命名（无碰撞）。
     */
    private function generateRealisticItemXML(itemCount:Number, seed:Number):String {
        if (seed == undefined) {
            seed = 0;
        }
        var s:String = "<root>";
        var i:Number = 0;
        while (i < itemCount) {
            var id:Number = i + seed;
            s += '<item weapontype="手枪">';
            s += "<name>weapon_" + id + "</name>";
            s += "<displayname>Weapon " + id + "</displayname>";
            s += "<icon>weapon_" + id + "</icon>";
            s += "<type>武器</type>";
            s += "<use>手枪</use>";
            s += "<price>" + ((i + 1) * 1000 + seed * 100) + "</price>";
            s += "<description>这是武器 " + id + " 的描述文本</description>";
            s += "<data>";
            s += "<level>" + (Math.floor(i / 3) + 1) + "</level>";
            s += "<weight>1</weight>";
            s += "<dressup>枪-手枪-weapon_" + id + "</dressup>";
            s += "<capacity>" + (8 + i % 20) + "</capacity>";
            s += "<split>1</split>";
            s += "<diffusion>" + (2 + i % 5) + "</diffusion>";
            s += "<interval>" + (100 + i * 10) + "</interval>";
            s += "<velocity>" + (20 + i % 10) + "</velocity>";
            s += "<bullet>普通子弹</bullet>";
            s += "<sound>pistol_" + (i % 5) + ".wav</sound>";
            s += "<muzzle>紧凑手枪枪火</muzzle>";
            s += "<bullethit>火花</bullethit>";
            s += "<clipname>手枪通用弹药</clipname>";
            s += "<bulletsize>" + (25 + i % 10) + "</bulletsize>";
            s += "<power>" + (30 + i * 5) + "</power>";
            s += "<impact>" + (100 + i * 50) + "</impact>";
            s += "<reloadPenalty>-15</reloadPenalty>";
            s += "</data>";
            s += "</item>";
            i++;
        }
        s += "</root>";
        return s;
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
     * isValidXML 累积计时（模拟真实调用模式）。
     * 真实 parseXMLNode 在每次递归入口都调用 isValidXML(node)，
     * 而 isValidXML 本身又递归验证整个子树。
     * 因此对 N 个元素节点的树，根节点验证 N 个，
     * 每个子节点再验证其子树，总复杂度 O(N²)。
     * 本方法模拟这个调用模式：对预收集的所有元素节点逐个调用 isValidXML。
     */
    private function timeIsValidXMLCumulativeLoop(elementNodes:Array, iterations:Number):Number {
        var sink:Boolean = false;
        var nodeCount:Number = elementNodes.length;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            var n:Number = 0;
            while (n < nodeCount) {
                sink = XMLParser.isValidXML(elementNodes[n]);
                n++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * isValidXML 累积基线：仅遍历节点数组。
     */
    private function timeIsValidXMLCumulativeBaseline(elementNodes:Array, iterations:Number):Number {
        var sink:XMLNode = null;
        var nodeCount:Number = elementNodes.length;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            var n:Number = 0;
            while (n < nodeCount) {
                sink = elementNodes[n];
                n++;
            }
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
    // 计时循环 —— Description 完整路径（getInnerText + decodeHTML）
    // ========================================================================

    /**
     * Description 完整路径：模拟 parseXMLNode 行 74-75 的真实调用。
     * getInnerText(childNode) 内部遍历子节点并调用 decodeHTML，
     * 然后外层再调用一次 decodeHTML —— 即双重解码。
     * 输入为含 Description 子节点的 XMLNode 数组。
     */
    private function timeDescriptionFullPathLoop(descNodes:Array, iterations:Number, batchSize:Number):Number {
        var sink:String = "";
        var vLen:Number = descNodes.length;
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
                // 模拟 XMLParser.as:74-75 的调用路径
                var innerText:String = XMLParser.getInnerText(descNodes[idx]);
                sink = StringUtils.decodeHTML(innerText);
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
     * Description 完整路径基线：仅遍历节点数组。
     */
    private function timeDescriptionFullPathBaseline(descNodes:Array, iterations:Number, batchSize:Number):Number {
        var sink:XMLNode = null;
        var vLen:Number = descNodes.length;
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
                sink = descNodes[idx];
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
    // 计时循环 —— 属性迭代（for..in attributes + convertDataType）
    // ========================================================================

    /**
     * 模拟 parseXMLNode 行 54-57：for (var attr in node.attributes) + convertDataType。
     * 输入为含多属性的 XMLNode 数组。
     */
    private function timeAttributeIterationLoop(attrNodes:Array, iterations:Number, batchSize:Number):Number {
        var sink:Object = null;
        var vLen:Number = attrNodes.length;
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
                var node:XMLNode = attrNodes[idx];
                var result:Object = {};
                for (var attr:String in node.attributes) {
                    result[attr] = XMLParser.convertDataType(node.attributes[attr]);
                }
                sink = result;
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
     * 属性迭代基线：仅遍历节点数组 + 创建空对象。
     */
    private function timeAttributeIterationBaseline(attrNodes:Array, iterations:Number, batchSize:Number):Number {
        var sink:Object = null;
        var vLen:Number = attrNodes.length;
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
                sink = attrNodes[idx];
                var dummy:Object = {};
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
    // 计时循环 —— 同名数组提升（result[name] 检查 + instanceof Array + push）
    // ========================================================================

    /**
     * 模拟 parseXMLNode 行 93-104 的同名节点数组提升逻辑。
     * 用预构造的 (nodeName, childValue) 对数组驱动，模拟真实的碰撞率。
     * pairs 结构：[{name:String, value:Object}, ...]
     */
    private function timeArrayPromotionLoop(pairs:Array, iterations:Number):Number {
        var sink:Object = null;
        var pLen:Number = pairs.length;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            var result:Object = {};
            var p:Number = 0;
            while (p < pLen) {
                var pair:Object = pairs[p];
                var nodeName:String = pair.name;
                var childValue:Object = pair.value;
                if (result[nodeName] !== undefined) {
                    if (!(result[nodeName] instanceof Array)) {
                        result[nodeName] = [result[nodeName]];
                    }
                    result[nodeName].push(childValue);
                } else {
                    result[nodeName] = childValue;
                }
                p++;
            }
            sink = result;
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * 数组提升基线：仅遍历 pairs 数组。
     */
    private function timeArrayPromotionBaseline(pairs:Array, iterations:Number):Number {
        var sink:Object = null;
        var pLen:Number = pairs.length;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            var result:Object = {};
            var p:Number = 0;
            while (p < pLen) {
                sink = pairs[p];
                p++;
            }
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    // ========================================================================
    // 计时循环 —— concat 累积合并（模拟 ItemDataLoader.concat）
    // ========================================================================

    /**
     * 模拟 ItemDataLoader.loadChildXmlFiles 的累积 concat 行为：
     * combined = combined.concat(childData.item) 对 N 个文件串行执行。
     * arrays 参数为预解析好的 item 数组列表。
     */
    private function timeConcatAccumulateLoop(arrays:Array, iterations:Number):Number {
        var sink:Array = null;
        var aLen:Number = arrays.length;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            var combined:Array = [];
            var a:Number = 0;
            while (a < aLen) {
                combined = combined.concat(arrays[a]);
                a++;
            }
            sink = combined;
            i++;
        }
        this.benchSink = sink;
        return getTimer() - t0;
    }

    /**
     * concat 累积基线：仅遍历数组列表。
     */
    private function timeConcatAccumulateBaseline(arrays:Array, iterations:Number):Number {
        var sink:Array = null;
        var aLen:Number = arrays.length;
        var i:Number = 0;
        var t0:Number = getTimer();
        while (i < iterations) {
            var a:Number = 0;
            while (a < aLen) {
                sink = arrays[a];
                a++;
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

        // 4. Description 节点（HTML 实体）严格验证
        // 真实路径：AS2 原生 XML 解析会将 &lt; 还原为 <，
        // 然后 getInnerText 调用 decodeHTML，再外层再调 decodeHTML（双重解码）。
        // 最终结果必须是完全解码的 "<p>Desc 0</p>"。
        this.assert(parsed0.item[0].Description != undefined, "首项有 Description");
        var desc:String = String(parsed0.item[0].Description);
        this.assertEqual("Description 严格解码验证", "<p>Desc 0</p>", desc);

        // 5. convertDataType 值数组验证
        var values:Array = this.generateConvertValues(12);
        this.assertEqual("convertDataType 值数组长度", 12, values.length);
        this.assert(typeof values[0] == "string", "值数组元素为字符串");

        // 6. decodeHTML 字符串数组验证
        var htmlStrs:Array = this.generateHTMLStrings(6);
        this.assertEqual("decodeHTML 字符串数组长度", 6, htmlStrs.length);
        this.assert(htmlStrs[0].indexOf("&lt;") >= 0, "含实体的 HTML 字符串正确");
        this.assert(htmlStrs[1].indexOf("&") < 0, "无实体的纯文本字符串正确");

        // 7. collectElementNodes 验证
        var elemNodes50:Array = [];
        this.collectElementNodes(xml0.firstChild, elemNodes50);
        this.assert(elemNodes50.length > 6, "collectElementNodes: 元素节点数 > item 数 (实际=" + elemNodes50.length + ")");
        // 对一个 6 项 XML：root + metadata(自闭合) + 6*item + 6*tags + 12*tag + 若干 Description = 远多于 6
        // 验证每个收集到的节点确实是元素节点
        this.assert(elemNodes50[0].nodeType == 1, "collectElementNodes: 首节点为元素节点");

        // 8. 密集 Description XML 验证
        var denseXml:String = this.generateDenseDescriptionXML(4, 0);
        var denseParsed:XML = new XML();
        denseParsed.ignoreWhite = true;
        denseParsed.parseXML(denseXml);
        var denseObj:Object = XMLParser.parseXMLNode(denseParsed.firstChild);
        this.assert(denseObj != null, "密集 Description XML 解析成功");
        this.assert(denseObj.item instanceof Array, "密集 Description: item 为数组");
        this.assertEqual("密集 Description 首项解码", "<p>Desc & detail 0</p>", String(denseObj.item[0].Description));

        // 9. Description 子节点收集验证（供 timeDescriptionFullPathLoop 使用）
        var descChildNodes:Array = [];
        var di:Number = 0;
        while (di < denseParsed.firstChild.childNodes.length) {
            var dChild:XMLNode = denseParsed.firstChild.childNodes[di];
            if (dChild.nodeName == "item") {
                var ddi:Number = 0;
                while (ddi < dChild.childNodes.length) {
                    if (dChild.childNodes[ddi].nodeName == "Description") {
                        descChildNodes.push(dChild.childNodes[ddi]);
                    }
                    ddi++;
                }
            }
            di++;
        }
        this.assertEqual("Description 子节点收集数量", 4, descChildNodes.length);

        // 10. 数组提升 pairs 验证
        var testPairs:Array = [
            {name: "tag", value: "t0"},
            {name: "tag", value: "t1"},
            {name: "tag", value: "t2"},
            {name: "single", value: "only"}
        ];
        this.assertEqual("数组提升 pairs 长度", 4, testPairs.length);

        // 11. 真实结构 XML 验证
        var realisticXml:String = this.generateRealisticItemXML(3, 0);
        var realisticParsed:XML = new XML();
        realisticParsed.ignoreWhite = true;
        realisticParsed.parseXML(realisticXml);
        var realisticObj:Object = XMLParser.parseXMLNode(realisticParsed.firstChild);
        this.assert(realisticObj != null, "真实结构 XML 解析成功");
        this.assert(realisticObj.item instanceof Array, "真实结构: item 为数组");
        this.assertEqual("真实结构 item 长度", 3, realisticObj.item.length);
        this.assertEqual("真实结构首项 name", "weapon_0", realisticObj.item[0].name);
        this.assert(realisticObj.item[0].data != undefined, "真实结构首项有 data");
        this.assertEqual("真实结构首项 data.bullet", "普通子弹", realisticObj.item[0].data.bullet);
        this.assertEqual("真实结构首项 data.power", 30, realisticObj.item[0].data.power);

        // 12. 深层嵌套 XML 验证
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
        trace("  说明: 对 parseXMLNode 内部各热点独立计时，定位时间分布。");
        trace("        isValidXML 使用累积模式（模拟递归中每层都调用的真实 O(N^2) 行为）。");

        var repeats:Number = 5;
        var targetMs:Number = 120;
        var self:XMLParser_Benchmark = this;

        // 公用：50 项 XML 预解析
        var xmlStr50:String = this.generateBenchXML(50, 0);
        var xmlPre50:XML = new XML();
        xmlPre50.ignoreWhite = true;
        xmlPre50.parseXML(xmlStr50);
        var node50:XMLNode = xmlPre50.firstChild;

        // parseXMLNode 总时间作参照（全局基准线）
        var nodeRef:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeParseXMLNodeLoop(node50, iterations); },
            function(iterations:Number):Number { return self.timeNodeReadBaseline(node50, iterations); },
            targetMs, 0, 4, 1024, repeats, 0, 1
        );

        // ================================================================
        // 热点 1: isValidXML 累积成本
        // ================================================================
        trace("\n  isValidXML 累积成本（50 项，模拟递归调用模式）");
        trace("    真实行为: parseXMLNode 每层递归入口调用 isValidXML(node)，");
        trace("    而 isValidXML 自身递归验证整个子树 → 总复杂度 O(N^2)。");

        var elemNodes:Array = [];
        this.collectElementNodes(node50, elemNodes);
        trace("    元素节点数: " + elemNodes.length);

        var validCumulativeStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeIsValidXMLCumulativeLoop(elemNodes, iterations); },
            function(iterations:Number):Number { return self.timeIsValidXMLCumulativeBaseline(elemNodes, iterations); },
            targetMs, 0, 2, 512, repeats, 0, 1
        );
        this.reportBenchStats("isValidXML(累积): ", validCumulativeStats);
        this.reportBenchStats("parseXMLNode:     ", nodeRef);
        this.reportPhaseShare("isValidXML 累积占 parseXMLNode: ", validCumulativeStats, nodeRef);

        // ================================================================
        // 热点 2: 属性迭代（for..in attributes + convertDataType）
        // ================================================================
        trace("\n  属性迭代（50 项 XML 的 item 节点，每节点 4 属性）");

        // 收集所有 item 节点（它们各有 id/name/value/enabled 四个属性）
        var itemNodes:Array = [];
        var ci:Number = 0;
        while (ci < node50.childNodes.length) {
            if (node50.childNodes[ci].nodeName == "item") {
                itemNodes.push(node50.childNodes[ci]);
            }
            ci++;
        }
        trace("    item 节点数: " + itemNodes.length);
        var attrBatch:Number = itemNodes.length;

        var attrStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeAttributeIterationLoop(itemNodes, iterations, attrBatch); },
            function(iterations:Number):Number { return self.timeAttributeIterationBaseline(itemNodes, iterations, attrBatch); },
            targetMs, 120, 4, 4096, repeats, 0, attrBatch
        );
        this.reportBenchStats("属性迭代:         ", attrStats);

        // ================================================================
        // 热点 3: 同名节点数组提升
        // ================================================================
        trace("\n  同名节点数组提升（展平全树碰撞模式）");
        trace("    模式: 根层 50 item 碰撞 + 50 item 各含 tags/Description +");
        trace("          50 tags 各含 2 tag 碰撞。展平为单次循环测量总工作量。");

        // 展平全树 (nodeName, childValue) 序列
        // 根层: 50 item + metadata + config = 52 pairs
        var promotionPairs:Array = [];
        var pi:Number = 0;
        while (pi < 50) {
            promotionPairs.push({name: "item", value: {id: pi}});
            pi++;
        }
        promotionPairs.push({name: "metadata", value: {version: "1.0"}});
        promotionPairs.push({name: "config", value: {maxRetry: 3}});
        // 每个 item 层: tags + 可能的 Description = ~60 pairs
        pi = 0;
        while (pi < 50) {
            promotionPairs.push({name: "tags", value: {tag: "t" + pi}});
            if (pi % 5 == 0) {
                promotionPairs.push({name: "Description", value: "Desc " + pi});
            }
            pi++;
        }
        // 每个 tags 层: 2 tag 碰撞 = 100 pairs
        pi = 0;
        while (pi < 50) {
            promotionPairs.push({name: "tag", value: "t" + pi});
            promotionPairs.push({name: "tag", value: "common"});
            pi++;
        }
        trace("    pairs 数: " + promotionPairs.length);

        var promotionStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeArrayPromotionLoop(promotionPairs, iterations); },
            function(iterations:Number):Number { return self.timeArrayPromotionBaseline(promotionPairs, iterations); },
            targetMs, 0, 8, 4096, repeats, 0, 1
        );
        this.reportBenchStats("数组提升:         ", promotionStats);

        // ================================================================
        // 热点 4: Description 完整路径（getInnerText + 双重 decodeHTML）
        // ================================================================
        trace("\n  Description 完整路径（密集模式：每项都有 Description）");
        trace("    真实路径: getInnerText(node) 内调 decodeHTML → 外层再调 decodeHTML（双重解码）。");

        // 用密集 Description XML 生成 Description 子节点数组
        var denseXmlStr:String = this.generateDenseDescriptionXML(50, 0);
        var densePre:XML = new XML();
        densePre.ignoreWhite = true;
        densePre.parseXML(denseXmlStr);
        var descNodes:Array = [];
        var dri:Number = 0;
        while (dri < densePre.firstChild.childNodes.length) {
            var itemNode:XMLNode = densePre.firstChild.childNodes[dri];
            if (itemNode.nodeName == "item") {
                var drii:Number = 0;
                while (drii < itemNode.childNodes.length) {
                    if (itemNode.childNodes[drii].nodeName == "Description") {
                        descNodes.push(itemNode.childNodes[drii]);
                    }
                    drii++;
                }
            }
            dri++;
        }
        trace("    Description 节点数: " + descNodes.length);
        var descBatch:Number = descNodes.length;

        var descFullStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeDescriptionFullPathLoop(descNodes, iterations, descBatch); },
            function(iterations:Number):Number { return self.timeDescriptionFullPathBaseline(descNodes, iterations, descBatch); },
            targetMs, 120, 4, 4096, repeats, 0, descBatch
        );
        this.reportBenchStats("Description全路径: ", descFullStats);

        // 对比：单独 decodeHTML（同样的输入数量）
        var descStrings:Array = [];
        var dsi:Number = 0;
        while (dsi < descNodes.length) {
            descStrings[dsi] = "&lt;p&gt;Desc &amp; detail " + dsi + "&lt;/p&gt;";
            dsi++;
        }
        var decodeOnlyStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeDecodeHTMLLoop(descStrings, iterations, descBatch); },
            function(iterations:Number):Number { return self.timeHTMLReadBaseline(descStrings, iterations, descBatch); },
            targetMs, 120, 4, 4096, repeats, 0, descBatch
        );
        this.reportBenchStats("单独 decodeHTML:  ", decodeOnlyStats);
        this.reportRatio("完整路径 / 单独 decodeHTML = ", descFullStats, decodeOnlyStats);

        // ================================================================
        // 热点 5: convertDataType（保留原基准作为参考）
        // ================================================================
        trace("\n  convertDataType（240 值轮转）");
        var convertValues:Array = this.generateConvertValues(240);
        var convertBatch:Number = 60;

        var convertStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeConvertDataTypeLoop(convertValues, iterations, convertBatch); },
            function(iterations:Number):Number { return self.timeConvertValueReadBaseline(convertValues, iterations, convertBatch); },
            targetMs, 120, 4, 4096, repeats, 0, convertBatch
        );
        this.reportBenchStats("convertDataType:  ", convertStats);

        // ================================================================
        // 汇总占比
        // ================================================================
        trace("\n  --- 各热点占 parseXMLNode 总耗时占比 ---");
        this.reportBenchStats("parseXMLNode(参照): ", nodeRef);
        this.reportPhaseShare("isValidXML(累积):  ", validCumulativeStats, nodeRef);
        this.reportPhaseShare("属性迭代:          ", attrStats, nodeRef);
        this.reportPhaseShare("数组提升:          ", promotionStats, nodeRef);
        this.reportPhaseShare("Description全路径: ", descFullStats, nodeRef);
        this.reportPhaseShare("convertDataType:   ", convertStats, nodeRef);

        if (nodeRef.reliable && validCumulativeStats.reliable && attrStats.reliable && promotionStats.reliable && descFullStats.reliable && convertStats.reliable) {
            var accounted:Number = validCumulativeStats.perOpMs + attrStats.perOpMs + promotionStats.perOpMs + descFullStats.perOpMs + convertStats.perOpMs;
            var pct:Number = Math.round(accounted / nodeRef.perOpMs * 100);
            trace("    已解释: " + pct + "% | 未解释（递归/对象创建/childNodes访问等）: " + (100 - pct) + "%");
        }
    }

    // ========================================================================
    // 基准 4：启动语料基准（模拟真实初始化加载链路）
    // ========================================================================
    private function benchStartupCorpus():Void {
        trace("\n--- 启动语料基准（模拟真实初始化加载链路） ---");
        trace("  说明: 使用匹配真实 data/items/*.xml 结构的合成 XML，");
        trace("        模拟 51 文件的 parseXML + parseXMLNode + concat 全流程。");
        trace("        不含 IO/网络等待，仅度量 CPU 部分。");

        var self:XMLParser_Benchmark = this;
        var repeats:Number = 5;
        var targetMs:Number = 120;

        // 真实分布近似（51 文件, 总 ~1.42 MB）:
        //   小文件(<15KB):  ~15 个, 约 5 items/文件
        //   中文件(15-50KB): ~25 个, 约 20 items/文件
        //   大文件(50-100KB): ~8 个, 约 50 items/文件
        //   超大文件(>100KB): ~3 个, 约 100 items/文件
        var fileProfiles:Array = [
            {items: 5,   desc: "小(5项)",    count: 15},
            {items: 20,  desc: "中(20项)",   count: 25},
            {items: 50,  desc: "大(50项)",   count: 8},
            {items: 100, desc: "超大(100项)", count: 3}
        ];

        var perFileCosts:Array = [];
        var concatArrays:Array = [];

        var fi:Number = 0;
        while (fi < fileProfiles.length) {
            var profile:Object = fileProfiles[fi];
            var xmlStr:String = this.generateRealisticItemXML(profile.items, fi);
            var payloadChars:Number = length(xmlStr);

            trace("\n  " + profile.desc + " | " + payloadChars + " 字符 | 模拟 " + profile.count + " 个文件");

            var stats:Object = this.measureBenchStats(
                function(iterations:Number):Number { return self.timeFullPipelineLoop(xmlStr, iterations); },
                function(iterations:Number):Number { return self.timeFullPipelineBaseline(xmlStr, iterations); },
                targetMs, 0, 2, 256, repeats, payloadChars, 1
            );
            this.reportBenchStats("全流水线:  ", stats);

            perFileCosts.push({perOpMs: stats.perOpMs, count: profile.count, chars: payloadChars, reliable: stats.reliable});

            // 为 concat 基准准备模拟解析结果
            var xml:XML = new XML();
            xml.ignoreWhite = true;
            xml.parseXML(xmlStr);
            var parsed:Object = XMLParser.parseXMLNode(xml.firstChild);
            var itemArray:Array;
            if (parsed.item instanceof Array) {
                itemArray = parsed.item;
            } else {
                itemArray = [parsed.item];
            }
            var ci:Number = 0;
            while (ci < profile.count) {
                concatArrays.push(itemArray);
                ci++;
            }

            fi++;
        }

        // concat 累积合并基准
        var totalItems:Number = 0;
        var cai:Number = 0;
        while (cai < concatArrays.length) {
            totalItems += concatArrays[cai].length;
            cai++;
        }
        trace("\n  Array.concat 累积合并（" + concatArrays.length + " 文件, " + totalItems + " 总物品）");

        var concatStats:Object = this.measureBenchStats(
            function(iterations:Number):Number { return self.timeConcatAccumulateLoop(concatArrays, iterations); },
            function(iterations:Number):Number { return self.timeConcatAccumulateBaseline(concatArrays, iterations); },
            targetMs, 0, 2, 512, repeats, 0, 1
        );
        this.reportBenchStats("concat累积: ", concatStats);

        // 启动 CPU 时间估算
        trace("\n  --- 启动期 CPU 时间估算（不含 IO） ---");
        var totalCpuMs:Number = 0;
        var allReliable:Boolean = true;
        var ei:Number = 0;
        while (ei < perFileCosts.length) {
            var cost:Object = perFileCosts[ei];
            var subtotal:Number = cost.perOpMs * cost.count;
            totalCpuMs += subtotal;
            if (!cost.reliable) {
                allReliable = false;
            }
            trace("    " + fileProfiles[ei].desc + " x" + cost.count + ": "
                + this.toFixed2(cost.perOpMs) + " ms/文件 x" + cost.count
                + " = " + this.toFixed2(subtotal) + " ms");
            ei++;
        }
        if (concatStats.reliable) {
            totalCpuMs += concatStats.perOpMs;
            trace("    concat: " + this.toFixed2(concatStats.perOpMs) + " ms");
        } else {
            allReliable = false;
        }
        trace("    --");
        if (allReliable) {
            trace("    估算启动期总 CPU: " + this.toFixed2(totalCpuMs) + " ms（纯解析+合并，不含IO）");
        } else {
            trace("    估算启动期总 CPU: ~" + this.toFixed2(totalCpuMs) + " ms（含低置信度项，仅供参考）");
        }
    }
}
