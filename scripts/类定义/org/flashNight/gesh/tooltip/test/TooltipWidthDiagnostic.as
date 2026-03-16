import org.flashNight.gesh.tooltip.test.MockTooltipContainer;
import org.flashNight.gesh.tooltip.test.TestDataBootstrap;
import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.tooltip.test.MockItemFactory;
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader;
import org.flashNight.gesh.xml.LoadXml.ItemDataLoader;

/**
 * TooltipWidthDiagnostic - 宽度估算诊断工具
 *
 * 支持两种模式：
 * - runAll()：使用 fixture 数据，同步执行（快速验证）
 * - runWithRealData()：加载真实 XML 数据，异步执行（完整采集）
 */
class org.flashNight.gesh.tooltip.test.TooltipWidthDiagnostic {

    private static var _scratch:Object = {total: 0, maxLine: 0, lineCount: 0};

    // ══════════════════════════════════════════════════════════════
    // 入口：真实数据模式（异步）
    // ══════════════════════════════════════════════════════════════

    public static function runWithRealData():Void {
        trace("=== TooltipWidthDiagnostic (Real Data Mode) ===");
        MockTooltipContainer.install();

        // Phase 1-3: 不依赖物品数据，先跑
        phase1_mockMeasureCapability();
        phase2_pixPerUnitCalibration();
        phase3_lineHeightCalibration();

        // Phase 4+: 需要真实数据，链式异步加载
        trace("");
        trace("--- Loading real game data... ---");

        var equipLoader:EquipmentConfigLoader = EquipmentConfigLoader.getInstance();
        equipLoader.loadEquipmentConfig(function(configData:Object):Void {
            trace("  EquipmentConfig loaded OK");
            EquipmentUtil.loadEquipmentConfig(configData);

            var itemLoader:ItemDataLoader = ItemDataLoader.getInstance();
            itemLoader.loadItemData(function(combinedData):Void {
                trace("  ItemData loaded OK, count=" + combinedData.length);
                ItemUtil.loadItemData(combinedData);

                // 现在可以跑真实数据的诊断了
                var bi2 = MockItemFactory.mockBaseItem();
                var splitItems:Array = collectSplitItems(ItemUtil.itemDataArray, bi2);

                phase4_realItemProfiles();
                phase5_sqrtFormulaWithRealData();
                phase6_currentVsSqrtWithRealData();
                phase7_configSweep(splitItems);
                phase8_heightAnalysis(splitItems);

                MockTooltipContainer.teardown();
                trace("=== END TooltipWidthDiagnostic ===");
            }, function():Void {
                trace("  [ERROR] ItemData load failed!");
                MockTooltipContainer.teardown();
            });
        }, function():Void {
            trace("  [ERROR] EquipmentConfig load failed!");
            MockTooltipContainer.teardown();
        });
    }

    // ══════════════════════════════════════════════════════════════
    // 入口：fixture 模式（同步，保留兼容）
    // ══════════════════════════════════════════════════════════════

    public static function runAll():Void {
        trace("=== TooltipWidthDiagnostic (Fixture Mode) ===");
        MockTooltipContainer.install();
        phase1_mockMeasureCapability();
        phase2_pixPerUnitCalibration();
        phase3_lineHeightCalibration();
        phase4_fixtureItemProfiles();
        phase5_sqrtFormulaDemo();
        phase6_currentVsSqrt();
        MockTooltipContainer.teardown();
        trace("=== END TooltipWidthDiagnostic ===");
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 1: mock 容器测量能力验证
    // ══════════════════════════════════════════════════════════════

    private static function phase1_mockMeasureCapability():Void {
        trace("");
        trace("--- Phase 1: Mock TextField Capability ---");

        var tf:Object = TooltipBridge.getMainTextBox();
        trace("  TextField exists: " + (tf != null));
        trace("  html=" + tf.html + " wordWrap=" + tf.wordWrap + " multiline=" + tf.multiline);

        var w1:Number = TooltipBridge.measureTextLineWidth("ABC", false);
        var w2:Number = TooltipBridge.measureTextLineWidth("测试中文", false);
        var w3:Number = TooltipBridge.measureTextLineWidth("ABC<BR>测试中文很长的一行", false);
        trace("  measure: ABC=" + w1 + " 测试中文=" + w2 + " multiline=" + w3);

        var pass:Boolean = (w1 > 0) && (w2 > 0) && (w3 > w2);
        trace("  Phase 1: " + (pass ? "PASS" : "FAIL"));
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 2: pixPerUnit 校准
    // ══════════════════════════════════════════════════════════════

    private static function phase2_pixPerUnitCalibration():Void {
        trace("");
        trace("--- Phase 2: pixPerUnit Calibration ---");

        var samples:Array = [
            "ABCDEFGHIJ",
            "Hello World Test String Here",
            "测试中文文本",
            "这是一段较长的中文测试文本内容用于校准",
            "Mixed混合Content内容TestStr测试文本",
            "<B>Bold粗体</B>和<FONT COLOR='#FF0000'>Color彩色</FONT>混排内容测试"
        ];

        trace("  text | score | px | px/unit");
        for (var i:Number = 0; i < samples.length; i++) {
            var s:String = samples[i];
            var sc:Object = StringUtils.htmlScoresBoth(s, null, _scratch);
            var px:Number = TooltipBridge.measureTextLineWidth(s, false);
            var ratio:Number = (sc.total > 0) ? (Math.round(px / sc.total * 100) / 100) : 0;
            var display:String = (s.length > 35) ? s.substr(0, 35) + "..." : s;
            trace("  " + display + " | " + sc.total + " | " + px + " | " + ratio);
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 3: lineHeight 校准
    // ══════════════════════════════════════════════════════════════

    private static function phase3_lineHeightCalibration():Void {
        trace("");
        trace("--- Phase 3: lineHeight Calibration ---");

        var tf:Object = TooltipBridge.getMainTextBox();

        tf._width = 9999;
        tf.wordWrap = false;
        tf.htmlText = "A";
        var h1:Number = tf.textHeight;
        tf.htmlText = "A<BR>B";
        var h2:Number = tf.textHeight;
        tf.htmlText = "1<BR>2<BR>3<BR>4<BR>5<BR>6<BR>7<BR>8<BR>9<BR>10";
        var h10:Number = tf.textHeight;

        trace("  1-line=" + h1 + " 2-line=" + h2 + " 10-line=" + h10);
        trace("  lineH(1gap)=" + (h2 - h1) + " lineH(avg9)=" + (Math.round((h10 - h1) / 9 * 100) / 100));

        // 测试不同宽度下的换行行为
        var testContent:String = "这是一段中等长度的测试内容用来观察换行<BR>第二行也有一些文字<BR>第三行结束";
        var sc:Object = StringUtils.htmlScoresBoth(testContent, null, _scratch);
        trace("  testContent: total=" + sc.total + " maxLine=" + sc.maxLine + " lines=" + sc.lineCount);

        var widths:Array = [100, 150, 200, 250, 300, 400, 500];
        var line:String = "  w→h:";
        for (var i:Number = 0; i < widths.length; i++) {
            tf.wordWrap = true;
            tf._width = widths[i];
            tf.htmlText = testContent;
            line += " " + widths[i] + "→" + tf.textHeight;
        }
        trace(line);

        tf.wordWrap = true;
        tf._width = 56;
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 4: 真实物品内容分布（全量扫描）
    // ══════════════════════════════════════════════════════════════

    private static function phase4_realItemProfiles():Void {
        trace("");
        trace("--- Phase 4: Real Item Profiles (ALL items) ---");

        var allItems:Array = ItemUtil.itemDataArray;
        if (allItems == null || allItems.length == 0) {
            trace("  [WARN] No items loaded!");
            return;
        }

        trace("  Total items: " + allItems.length);

        // 统计用
        var equipCount:Number = 0;
        var splitCount:Number = 0;
        var totalDescScore:Number = 0;
        var maxDescScore:Number = 0;
        var maxDescItem:String = "";
        var totalIntroScore:Number = 0;
        var maxIntroScore:Number = 0;
        var maxIntroItem:String = "";

        // 分档统计
        var descBuckets:Array = [0, 0, 0, 0, 0]; // <50, 50-100, 100-200, 200-400, 400+
        var introBuckets:Array = [0, 0, 0, 0, 0];

        // 详细输出 top 样本（按 descScore 排序找最重的）
        var topSamples:Array = [];

        var bi = MockItemFactory.mockBaseItem();

        for (var i:Number = 0; i < allItems.length; i++) {
            var item:Object = allItems[i];
            if (item == null) continue;

            var isEquip:Boolean = (item.type == "武器" || item.type == "防具");
            if (isEquip) equipCount++;

            var descText:String = TooltipComposer.generateItemDescriptionText(item, bi);
            var introText:String = TooltipComposer.generateIntroPanelContent(bi, item, bi.value);

            var descSc:Object = StringUtils.htmlScoresBoth(descText, null);
            var introSc:Object = StringUtils.htmlScoresBoth(introText, null);

            var dT:Number = descSc.total;
            var dM:Number = descSc.maxLine;
            var dL:Number = descSc.lineCount;
            var iT:Number = introSc.total;
            var iM:Number = introSc.maxLine;
            var iL:Number = introSc.lineCount;

            // 是否触发 split
            var wouldSplit:Boolean = TooltipLayout.shouldSplitSmart(descText, introText, null);
            if (wouldSplit) splitCount++;

            totalDescScore += dT;
            if (dT > maxDescScore) { maxDescScore = dT; maxDescItem = item.name; }
            totalIntroScore += iT;
            if (iT > maxIntroScore) { maxIntroScore = iT; maxIntroItem = item.name; }

            // 分档
            if (dT < 50) descBuckets[0]++;
            else if (dT < 100) descBuckets[1]++;
            else if (dT < 200) descBuckets[2]++;
            else if (dT < 400) descBuckets[3]++;
            else descBuckets[4]++;

            if (iT < 50) introBuckets[0]++;
            else if (iT < 100) introBuckets[1]++;
            else if (iT < 200) introBuckets[2]++;
            else if (iT < 400) introBuckets[3]++;
            else introBuckets[4]++;

            // 收集 top 候选
            if (dT > 80 || iT > 150) {
                topSamples.push({
                    name: item.name, type: item.type, use: item.use,
                    dT: dT, dM: dM, dL: dL,
                    iT: iT, iM: iM, iL: iL,
                    split: wouldSplit
                });
            }
        }

        // 汇总
        trace("  Equipment: " + equipCount + " | Would split: " + splitCount + "/" + allItems.length);
        trace("  Desc score: avg=" + Math.round(totalDescScore / allItems.length) + " max=" + maxDescScore + " (" + maxDescItem + ")");
        trace("  Intro score: avg=" + Math.round(totalIntroScore / allItems.length) + " max=" + maxIntroScore + " (" + maxIntroItem + ")");
        trace("  Desc buckets [<50, 50-100, 100-200, 200-400, 400+]: " + descBuckets.join(", "));
        trace("  Intro buckets [<50, 50-100, 100-200, 200-400, 400+]: " + introBuckets.join(", "));

        // Top 样本详情（按 descScore 降序，最多 20 条）
        topSamples.sort(function(a, b) { return b.dT - a.dT; });
        var showCount:Number = Math.min(topSamples.length, 20);
        trace("  --- Top " + showCount + " heaviest items (by desc score) ---");
        trace("  name | type/use | dT dM dL | iT iM iL | split | curW");
        for (var j:Number = 0; j < showCount; j++) {
            var s:Object = topSamples[j];
            var curW:Number = TooltipLayout.estimateMainWidthFromMetrics(s.dT, s.dM, s.dL, undefined, undefined);
            trace("  " + s.name + " | " + s.type + "/" + s.use
                + " | d:" + s.dT + "/" + s.dM + "/" + s.dL
                + " | i:" + s.iT + "/" + s.iM + "/" + s.iL
                + " | " + (s.split ? "SPLIT" : "merge")
                + " | W=" + Math.round(curW));
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 5: sqrt 公式 vs 当前算法（用真实 top 物品）
    // ══════════════════════════════════════════════════════════════

    private static function phase5_sqrtFormulaWithRealData():Void {
        trace("");
        trace("--- Phase 5: sqrt vs current (real top items) ---");

        var PIX:Number = TooltipConstants.PIX_PER_UNIT;
        var LH:Number = TooltipConstants.LINE_HEIGHT;

        var tf:Object = TooltipBridge.getMainTextBox();
        var bi = MockItemFactory.mockBaseItem();

        var allItems:Array = ItemUtil.itemDataArray;
        if (allItems == null) return;

        // 收集 split 模式物品
        var splitItems:Array = collectSplitItems(allItems, bi);

        splitItems.sort(function(a, b) { return b.dT - a.dT; });
        var count:Number = Math.min(splitItems.length, 15);
        trace("  Split items: " + splitItems.length + ", showing top " + count);
        trace("  name | dT | curW curH curW/H | sqrtW sqrtH sqrtW/H | delta");

        for (var j:Number = 0; j < count; j++) {
            var si:Object = splitItems[j];

            // 当前算法
            var curW:Number = TooltipLayout.estimateMainWidthFromMetrics(si.dT, si.dM, si.dL, undefined, undefined);
            tf.wordWrap = true;
            tf._width = curW;
            tf.htmlText = si.desc;
            var curH:Number = tf.textHeight;
            var curR:Number = (curH > 0) ? (Math.round(curW / curH * 100) / 100) : 0;

            // sqrt 公式
            var sqW:Number = computeSqrtWidth(si.dT, si.dM, PIX, LH,
                TooltipConstants.RATIO_MIN, TooltipConstants.RATIO_MAX, TooltipConstants.RATIO_SCORE_CAP);
            var maxLW:Number = si.dM * PIX + TooltipConstants.LINE_GUTTER;

            tf._width = sqW;
            tf.htmlText = si.desc;
            var sqH:Number = tf.textHeight;
            var sqR:Number = (sqH > 0) ? (Math.round(sqW / sqH * 100) / 100) : 0;

            var delta:Number = Math.round(sqW - curW);
            trace("  " + si.name + " | " + si.dT
                + " | " + Math.round(curW) + " " + curH + " " + curR
                + " | " + Math.round(sqW) + " " + sqH + " " + sqR
                + " | " + (delta >= 0 ? "+" : "") + delta);
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 6: 合成内容的宽高比对比（用真实数据生成的代表性内容）
    // ══════════════════════════════════════════════════════════════

    private static function phase6_currentVsSqrtWithRealData():Void {
        trace("");
        trace("--- Phase 6: W/H ratio distribution across ALL split items ---");

        var PIX:Number = TooltipConstants.PIX_PER_UNIT;
        var LH:Number = TooltipConstants.LINE_HEIGHT;
        var tf:Object = TooltipBridge.getMainTextBox();
        var bi = MockItemFactory.mockBaseItem();
        var allItems:Array = ItemUtil.itemDataArray;
        if (allItems == null) return;

        // W/H 分档: <0.5, 0.5-0.8, 0.8-1.2, 1.2-2.0, 2.0+
        var curBuckets:Array = [0, 0, 0, 0, 0];
        var sqrtBuckets:Array = [0, 0, 0, 0, 0];
        var total:Number = 0;

        var splitItems:Array = collectSplitItems(allItems, bi);
        for (var i:Number = 0; i < splitItems.length; i++) {
            var si:Object = splitItems[i];
            total++;

            // 当前算法
            var curW:Number = TooltipLayout.estimateMainWidthFromMetrics(si.dT, si.dM, si.dL, undefined, undefined);
            tf.wordWrap = true;
            tf._width = curW;
            tf.htmlText = si.desc;
            var curH:Number = tf.textHeight;
            var curR:Number = (curH > 0) ? (curW / curH) : 99;
            bucketize(curBuckets, curR);

            // sqrt
            var sqW:Number = computeSqrtWidth(si.dT, si.dM, PIX, LH,
                TooltipConstants.RATIO_MIN, TooltipConstants.RATIO_MAX, TooltipConstants.RATIO_SCORE_CAP);
            tf._width = sqW;
            tf.htmlText = si.desc;
            var sqH:Number = tf.textHeight;
            var sqR:Number = (sqH > 0) ? (sqW / sqH) : 99;
            bucketize(sqrtBuckets, sqR);
        }

        trace("  Split items counted: " + total);
        trace("  W/H buckets [<0.5, 0.5-0.8, 0.8-1.2, 1.2-2.0, 2.0+]");
        trace("    Current: " + curBuckets.join(", "));
        trace("    Sqrt:    " + sqrtBuckets.join(", "));

        tf.wordWrap = true;
        tf._width = 56;
    }

    private static function bucketize(arr:Array, ratio:Number):Void {
        if (ratio < 0.5) arr[0]++;
        else if (ratio < 0.8) arr[1]++;
        else if (ratio < 1.2) arr[2]++;
        else if (ratio < 2.0) arr[3]++;
        else arr[4]++;
    }

    // ══════════════════════════════════════════════════════════════
    // 共享工具函数
    // ══════════════════════════════════════════════════════════════

    /** 收集全部 split 模式物品的 {name, desc, dT, dM, dL} */
    private static function collectSplitItems(allItems:Array, bi):Array {
        var result:Array = [];
        for (var i:Number = 0; i < allItems.length; i++) {
            var item:Object = allItems[i];
            if (item == null) continue;
            var desc:String = TooltipComposer.generateItemDescriptionText(item, bi);
            var intro:String = TooltipComposer.generateIntroPanelContent(bi, item, bi.value);
            if (TooltipLayout.shouldSplitSmart(desc, intro, null)) {
                var sc:Object = StringUtils.htmlScoresBoth(desc, null);
                result.push({name: item.name, desc: desc, dT: sc.total, dM: sc.maxLine, dL: sc.lineCount});
            }
        }
        return result;
    }

    /** sqrt 公式计算宽度（独立于 TooltipLayout 实现，供 sweep 评估） */
    private static function computeSqrtWidth(totalScore:Number, maxLineScore:Number,
            pix:Number, lh:Number, rMin:Number, rMax:Number, cap:Number):Number {
        var t:Number = totalScore / cap;
        if (t > 1) t = 1;
        var ss:Number = t * t * (3 - 2 * t);
        var r:Number = rMin + ss * (rMax - rMin);
        var sqW:Number = Math.sqrt(r * totalScore * pix * lh);
        var maxLW:Number = maxLineScore * pix + TooltipConstants.LINE_GUTTER;
        if (sqW > maxLW) sqW = maxLW;
        if (sqW < TooltipConstants.MIN_W) sqW = TooltipConstants.MIN_W;
        if (sqW > TooltipConstants.MAX_W) sqW = TooltipConstants.MAX_W;
        return sqW;
    }

    /** W/H 惩罚函数 */
    private static function penalty(ratio:Number):Number {
        if (ratio < 0.5) return 3.0;
        if (ratio < 0.8) return 1.0;
        if (ratio < 1.5) return 0.0;
        if (ratio < 2.5) return 0.5;
        return 2.0;
    }

    /** 5 档分桶（与惩罚函数对齐）: <0.5, 0.5-0.8, 0.8-1.5, 1.5-2.5, 2.5+ */
    private static function bucketize5(arr:Array, ratio:Number):Void {
        if (ratio < 0.5) arr[0]++;
        else if (ratio < 0.8) arr[1]++;
        else if (ratio < 1.5) arr[2]++;
        else if (ratio < 2.5) arr[3]++;
        else arr[4]++;
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 7: Config Sweep + 帕累托前沿分析
    // ══════════════════════════════════════════════════════════════

    private static function phase7_configSweep(splitItems:Array):Void {
        trace("");
        trace("--- Phase 7: Config Sweep + Pareto Front ---");

        var tf:Object = TooltipBridge.getMainTextBox();
        var n:Number = splitItems.length;
        if (n == 0) { trace("  No split items!"); return; }

        // 配置列表：每轮 sweep 前编辑此数组
        // === Round 2: 围绕 B(RMIN=0.618,RMAX=1.5,CAP=300) 精调 + PIX 灵敏度 ===
        var CONFIGS:Array = [
            {id: "CUR", useCurrent: true},
            {id: "B",  PIX: 6.0, LH: 15, RMIN: 0.618, RMAX: 1.5, CAP: 300},
            // RMAX 微调
            {id: "B1", PIX: 6.0, LH: 15, RMIN: 0.618, RMAX: 1.3, CAP: 300},
            {id: "B2", PIX: 6.0, LH: 15, RMIN: 0.618, RMAX: 1.7, CAP: 300},
            // CAP 微调
            {id: "B3", PIX: 6.0, LH: 15, RMIN: 0.618, RMAX: 1.5, CAP: 250},
            {id: "B4", PIX: 6.0, LH: 15, RMIN: 0.618, RMAX: 1.5, CAP: 350},
            // RMIN 微调
            {id: "B5", PIX: 6.0, LH: 15, RMIN: 0.55,  RMAX: 1.5, CAP: 300},
            {id: "B6", PIX: 6.0, LH: 15, RMIN: 0.7,   RMAX: 1.5, CAP: 300},
            // PIX 灵敏度探针
            {id: "PX1", PIX: 5.5, LH: 15, RMIN: 0.618, RMAX: 1.5, CAP: 300},
            {id: "PX2", PIX: 7.0, LH: 15, RMIN: 0.618, RMAX: 1.5, CAP: 300}
        ];

        // 评估所有配置
        var results:Array = [];
        for (var ci:Number = 0; ci < CONFIGS.length; ci++) {
            results.push(evaluateConfig(CONFIGS[ci], splitItems, tf));
        }

        // 输出所有配置结果
        trace("  n=" + n + " | configs=" + CONFIGS.length);
        trace("  ID  | meanP | p95P | <0.5 | 0.5-0.8 | 0.8-1.5 | 1.5-2.5 | 2.5+ | ideal% | worst");
        for (var ri:Number = 0; ri < results.length; ri++) {
            var res:Object = results[ri];
            trace("  " + pad(res.id, 4)
                + "| " + pad(String(Math.round(res.meanP * 100) / 100), 6)
                + "| " + pad(String(Math.round(res.p95P * 100) / 100), 5)
                + "| " + pad(String(res.buckets[0]), 5)
                + "| " + pad(String(res.buckets[1]), 8)
                + "| " + pad(String(res.buckets[2]), 8)
                + "| " + pad(String(res.buckets[3]), 8)
                + "| " + pad(String(res.buckets[4]), 5)
                + "| " + pad(String(res.idealPct) + "%", 7)
                + "| " + res.worstItem + "(" + (Math.round(res.worstWH * 100) / 100) + ")");
        }

        // 帕累托前沿标记
        trace("  --- Pareto Front ---");
        for (var ai:Number = 0; ai < results.length; ai++) {
            var a:Object = results[ai];
            a.dominated = false;
            a.dominatedBy = "";
            for (var bi:Number = 0; bi < results.length; bi++) {
                if (ai == bi) continue;
                var b:Object = results[bi];
                if (b.meanP <= a.meanP && b.p95P <= a.p95P && (b.meanP < a.meanP || b.p95P < a.p95P)) {
                    a.dominated = true;
                    a.dominatedBy = b.id;
                    break;
                }
            }
            if (a.dominated) {
                trace("  " + a.id + " dominated by " + a.dominatedBy);
            } else {
                trace("  " + a.id + " ON FRONT | meanP=" + (Math.round(a.meanP * 100) / 100)
                    + " p95P=" + (Math.round(a.p95P * 100) / 100)
                    + " ideal=" + a.idealPct + "%");
            }
        }
    }

    /** 评估单个配置在全部 split 物品上的表现 */
    private static function evaluateConfig(cfg:Object, splitItems:Array, tf:Object):Object {
        var n:Number = splitItems.length;
        var penalties:Array = [];
        var buckets:Array = [0, 0, 0, 0, 0];
        var totalP:Number = 0;
        var worstItem:String = "";
        var worstWH:Number = 0;
        var worstP:Number = -1;

        for (var i:Number = 0; i < n; i++) {
            var si:Object = splitItems[i];
            var w:Number;

            if (cfg.useCurrent) {
                // 当前生产算法
                w = TooltipLayout.estimateMainWidthFromMetrics(si.dT, si.dM, si.dL, undefined, undefined);
            } else {
                w = computeSqrtWidth(si.dT, si.dM, cfg.PIX, cfg.LH, cfg.RMIN, cfg.RMAX, cfg.CAP);
            }

            tf.wordWrap = true;
            tf._width = w;
            tf.htmlText = si.desc;
            var h:Number = tf.textHeight;
            var wh:Number = (h > 0) ? (w / h) : 99;

            var p:Number = penalty(wh);
            penalties.push(p);
            totalP += p;
            bucketize5(buckets, wh);

            if (p > worstP || (p == worstP && wh > worstWH)) {
                worstP = p;
                worstWH = wh;
                worstItem = si.name;
            }
        }

        // 排序取 p95
        penalties.sort(Array.NUMERIC);
        var p95Idx:Number = Math.floor(n * 0.95);
        if (p95Idx >= n) p95Idx = n - 1;
        var p95:Number = penalties[p95Idx];

        var idealPct:Number = Math.round(buckets[2] / n * 100);

        return {
            id: cfg.id,
            meanP: totalP / n,
            p95P: p95,
            buckets: buckets,
            idealPct: idealPct,
            worstItem: worstItem,
            worstWH: worstWH
        };
    }

    /** 右填充字符串到指定长度 */
    private static function pad(s:String, len:Number):String {
        while (s.length < len) s += " ";
        return s;
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 4 (fixture 模式 - 保留兼容)
    // ══════════════════════════════════════════════════════════════

    private static function phase4_fixtureItemProfiles():Void {
        trace("");
        trace("--- Phase 4: Fixture Item Profiles ---");
        TestDataBootstrap.beginSandbox();
        var names:Array = ["测试军刀", "测试手枪", "测试手雷", "测试护甲", "测试药水", "测试情报"];
        var bi = MockItemFactory.mockBaseItem();
        for (var i:Number = 0; i < names.length; i++) {
            var name:String = names[i];
            var item:Object = ItemUtil.getItemData(name);
            if (item == null) { trace("  " + name + " | NOT FOUND"); continue; }
            var descText:String = TooltipComposer.generateItemDescriptionText(item, bi);
            var introText:String = TooltipComposer.generateIntroPanelContent(bi, item, bi.value);
            var descSc:Object = StringUtils.htmlScoresBoth(descText, null);
            var introSc:Object = StringUtils.htmlScoresBoth(introText, null);
            var curW:Number = TooltipLayout.estimateMainWidthFromMetrics(descSc.total, descSc.maxLine, descSc.lineCount, undefined, undefined);
            trace("  " + name + " | d:" + descSc.total + "/" + descSc.maxLine + "/" + descSc.lineCount
                + " | i:" + introSc.total + "/" + introSc.maxLine + "/" + introSc.lineCount
                + " | W=" + Math.round(curW));
        }
        TestDataBootstrap.endSandbox();
    }

    private static function phase5_sqrtFormulaDemo():Void {
        trace("");
        trace("--- Phase 5: sqrt Formula Demo ---");
        var testCases:Array = [
            {label: "short(10)", total: 10, maxLine: 10, lines: 1},
            {label: "med(120)", total: 120, maxLine: 30, lines: 6},
            {label: "long(300)", total: 300, maxLine: 40, lines: 12},
            {label: "heavy(800)", total: 800, maxLine: 50, lines: 25}
        ];
        for (var i:Number = 0; i < testCases.length; i++) {
            var tc:Object = testCases[i];
            var t:Number = Math.min(1, tc.total / 400);
            var r:Number = 0.618 + t * (1.5 - 0.618);
            var sqW:Number = Math.sqrt(r * tc.total * TooltipConstants.PIX_PER_UNIT * TooltipConstants.LINE_HEIGHT);
            var curW:Number = TooltipLayout.estimateMainWidthFromMetrics(tc.total, tc.maxLine, tc.lines, undefined, undefined);
            trace("  " + tc.label + " | r=" + (Math.round(r * 100) / 100) + " sqrtW=" + Math.round(sqW) + " curW=" + Math.round(curW));
        }
    }

    // ══════════════════════════════════════════════════════════════
    // Phase 8: 高度约束与 balanceWidth 效果分析
    // ══════════════════════════════════════════════════════════════

    /**
     * 对全部 split 物品分析高度约束效果：
     * - 比较 initW→initLines vs balancedW→balancedLines
     * - 分可解/不可解两类统计
     * - 输出 top 20 明细 + 汇总表
     */
    private static function phase8_heightAnalysis(splitItems:Array):Void {
        trace("");
        trace("--- Phase 8: Height & Balance Analysis ---");

        var tf:Object = TooltipBridge.getMainTextBox();
        var n:Number = splitItems.length;
        if (n == 0) { trace("  No split items!"); return; }

        var maxL:Number = TooltipConstants.MAX_RENDERED_LINES;

        // 使用与运行时一致的 effectiveMax（对齐 TooltipComposer.renderItemTooltipSmart）
        var screenMax:Number = Stage.width - TooltipConstants.BASE_NUM - TooltipConstants.DUAL_PANEL_MARGIN;
        var effectiveMax:Number = (screenMax > TooltipConstants.MIN_W)
            ? Math.min(TooltipConstants.MAX_W, screenMax)
            : TooltipConstants.MAX_W;
        trace("  effectiveMax=" + effectiveMax + " (Stage.width=" + Stage.width
            + " screenMax=" + screenMax + " MAX_W=" + TooltipConstants.MAX_W + ")");

        // 统计变量
        var overflowBefore:Number = 0;  // initW 下超 32 行的数量
        var overflowAfter:Number = 0;   // balancedW 下超 32 行的数量
        var solvableCount:Number = 0;   // 可解（effectiveMax 下 ≤32 行）
        var unsolvableCount:Number = 0; // 不可解（effectiveMax 下仍 >32 行）
        var solvableOverflowAfter:Number = 0; // 可解但 balance 后仍溢出（应为 0）
        var modeACount:Number = 0;      // modeA 触发次数
        var modeBCount:Number = 0;      // modeB 触发次数
        var totalShrink:Number = 0;     // modeB 总收缩像素
        var maxLinesBefore:Number = 0;
        var maxLinesAfter:Number = 0;
        var worstBefore:String = "";
        var worstAfter:String = "";

        // 明细收集（按 initLines 降序取 top 20）
        var details:Array = [];

        for (var i:Number = 0; i < n; i++) {
            var si:Object = splitItems[i];
            var initW:Number = TooltipLayout.estimateMainWidthFromMetrics(
                si.dT, si.dM, si.dL, undefined, undefined);

            // 设置内容（仅一次）
            tf.wordWrap = true;
            tf.htmlText = si.desc;

            // 测量 initW 下的行数
            var initLines:Number = TooltipBridge.measureRenderedLines(initW, false);

            // 测量 effectiveMax 下的行数（判定可解性，对齐运行时上限）
            var maxWLines:Number = TooltipBridge.measureRenderedLines(effectiveMax, false);
            var solvable:Boolean = (maxWLines >= 0 && maxWLines <= maxL);

            // 调用 balanceWidth
            var balW:Number = TooltipLayout.balanceWidth(initW, si.desc, effectiveMax);

            // 测量 balancedW 下的行数
            tf.wordWrap = true;
            tf.htmlText = si.desc;
            var balLines:Number = TooltipBridge.measureRenderedLines(balW, false);

            // 统计
            if (initLines > maxL) overflowBefore++;
            if (balLines > maxL) overflowAfter++;

            if (solvable) {
                solvableCount++;
                if (balLines > maxL) solvableOverflowAfter++;
            } else {
                unsolvableCount++;
            }

            if (initLines > maxL && balLines <= maxL) modeACount++;
            if (initLines <= maxL && balW < initW) {
                modeBCount++;
                totalShrink += (initW - balW);
            }

            if (initLines > maxLinesBefore) { maxLinesBefore = initLines; worstBefore = si.name; }
            if (balLines > maxLinesAfter) { maxLinesAfter = balLines; worstAfter = si.name; }

            details.push({
                name: si.name,
                initW: Math.round(initW),
                initL: initLines,
                balW: Math.round(balW),
                balL: balLines,
                maxWL: maxWLines,
                solvable: solvable
            });
        }

        // 按 initLines 降序排序
        details.sort(function(a, b) { return b.initL - a.initL; });

        // 输出 top 20 明细
        var showCount:Number = Math.min(n, 20);
        trace("  Top " + showCount + " by initLines:");
        trace("  name | initW initL | balW balL | maxWL | solvable | delta");
        for (var j:Number = 0; j < showCount; j++) {
            var d:Object = details[j];
            var delta:Number = d.balW - d.initW;
            trace("  " + d.name
                + " | " + d.initW + " " + d.initL
                + " | " + d.balW + " " + d.balL
                + " | " + d.maxWL
                + " | " + (d.solvable ? "Y" : "N")
                + " | " + (delta >= 0 ? "+" : "") + delta);
        }

        // 汇总
        trace("");
        trace("  === Summary (n=" + n + ") ===");
        trace("  Overflow before: " + overflowBefore + "/" + n
            + " (" + Math.round(overflowBefore / n * 100) + "%)");
        trace("  Overflow after:  " + overflowAfter + "/" + n
            + " (" + Math.round(overflowAfter / n * 100) + "%)");
        trace("  Solvable: " + solvableCount + " | Unsolvable: " + unsolvableCount);
        trace("  Solvable overflow after balance: " + solvableOverflowAfter
            + " (should be 0)");
        trace("  ModeA triggered: " + modeACount
            + " | ModeB triggered: " + modeBCount);
        if (modeBCount > 0) {
            trace("  ModeB avg shrink: "
                + Math.round(totalShrink / modeBCount) + "px");
        }
        trace("  Max lines before: " + maxLinesBefore + " (" + worstBefore + ")");
        trace("  Max lines after:  " + maxLinesAfter + " (" + worstAfter + ")");
    }

    private static function phase6_currentVsSqrt():Void {
        trace("");
        trace("--- Phase 6: W/H Ratio Comparison (synthetic) ---");
        var tf:Object = TooltipBridge.getMainTextBox();
        var contents:Array = [
            {label: "3line-even", html: "均匀内容行一<BR>均匀内容行二<BR>均匀内容行三"},
            {label: "1line-short", html: "很短"},
            {label: "9short+1long", html: "短<BR>短<BR>短<BR>短<BR>短<BR>短<BR>短<BR>短<BR>这是一行非常非常非常非常非常非常非常非常非常长的描述文本"},
            {label: "10line-long", html: "第一行有一些内容<BR>第二行也有内容<BR>第三行继续写<BR>第四行还在写<BR>第五行快写完了<BR>第六行新的开始<BR>第七行继续<BR>第八行快了<BR>第九行马上<BR>第十行结束了终于"}
        ];
        for (var i:Number = 0; i < contents.length; i++) {
            var c:Object = contents[i];
            var sc:Object = StringUtils.htmlScoresBoth(c.html, null);
            var curW:Number = TooltipLayout.estimateMainWidthFromMetrics(sc.total, sc.maxLine, sc.lineCount, undefined, undefined);
            tf.wordWrap = true;
            tf._width = curW;
            tf.htmlText = c.html;
            var curH:Number = tf.textHeight;
            var curR:String = (curH > 0) ? String(Math.round(curW / curH * 100) / 100) : "inf";
            trace("  " + c.label + " | curW=" + Math.round(curW) + " H=" + curH + " W/H=" + curR);
        }
        tf.wordWrap = true;
        tf._width = 56;
    }
}
