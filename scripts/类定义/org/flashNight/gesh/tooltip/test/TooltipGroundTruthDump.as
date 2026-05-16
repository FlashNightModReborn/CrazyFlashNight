import org.flashNight.gesh.tooltip.test.MockTooltipContainer;
import org.flashNight.gesh.tooltip.test.MockItemFactory;
import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipComposer;
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader;
import org.flashNight.gesh.xml.LoadXml.ItemDataLoader;

/**
 * TooltipGroundTruthDump — 把 AS2 端注释面板的几何真值 dump 出来，
 * 给 web 端 panels.css / tooltip.js 做"用真值重写"的参照源。
 *
 * 为什么需要这个：
 *   - AS2 端 introBg / mainBg / icon / introText / mainText 各自的 width/height/x/y
 *     在源码里是公式分散 + applyIntroLayout / showTooltip / positionTooltip 串起来才能算出来；
 *   - 单读代码很容易漏关键事实（比如 icon Y=19~219 与 introText Y=210+ 重叠 9px，
 *     说明 icon 不是 flex column 在 intro text 上方，而是 absolute 锚定在 introBg 左上的独立层）；
 *   - 用真实物品全量 dump，把每一项的真值落地成 JSON，web 端按这份真值复刻几何，避免"读 AS2 → 推视觉"。
 *
 * 输出协议（trace 行级，给 compile_output.txt 抓）：
 *   GT_META|<k=v,k=v,...>      AS2 常量基线（BASE_NUM/INTRO_MAX_W/...）
 *   GT_HEAD|<colName1|colName2|...>     字段名声明
 *   GT_ITEM|name|use|...                每个 split item 一行
 *   GT_TOTAL|<n>                        dump 完毕的 item 数
 *
 * 字段宽度都按 AS2 公式现场算（不依赖完整 positionTooltip 链路，避免 icon 资产
 * 在 testMovie 下没法 attachMovie 的副作用）：
 *   introBg._height = introText.textHeight + BASE_NUM + BG_HEIGHT_OFFSET   （= textH + 220）
 *   mainBg._height  = mainText.textHeight + TEXT_PAD                       （= textH + 10）
 *   mainBg height floor （positionTooltip else 分支）= max(mainTextH, icon._height) + HEIGHT_ADJUST
 *   icon._height = BASE_NUM × ICON_SCALE/100                               （200 × 1.5 = 300）
 *
 * 用法：TestLoader.as 替换为 TooltipGroundTruthDump.runWithRealData()，bash scripts/compile_test.sh 即可。
 */
class org.flashNight.gesh.tooltip.test.TooltipGroundTruthDump {

    private static var _scratch:Object = {total: 0, maxLine: 0, lineCount: 0};

    public static function runWithRealData():Void {
        trace("=== TooltipGroundTruthDump (Real Data Mode) ===");
        MockTooltipContainer.install();

        var equipLoader:EquipmentConfigLoader = EquipmentConfigLoader.getInstance();
        equipLoader.loadEquipmentConfig(function(configData:Object):Void {
            trace("  EquipmentConfig loaded OK");
            EquipmentUtil.loadEquipmentConfig(configData);

            var itemLoader:ItemDataLoader = ItemDataLoader.getInstance();
            itemLoader.loadItemData(function(combinedData):Void {
                trace("  ItemData loaded OK, count=" + combinedData.length);
                ItemUtil.loadItemData(combinedData);

                dumpConstants();
                dumpAllSplitItems();

                MockTooltipContainer.teardown();
                trace("=== END TooltipGroundTruthDump ===");
            }, function():Void {
                trace("  [ERROR] ItemData load failed!");
                MockTooltipContainer.teardown();
            });
        }, function():Void {
            trace("  [ERROR] EquipmentConfig load failed!");
            MockTooltipContainer.teardown();
        });
    }

    private static function dumpConstants():Void {
        // icon 实际像素（AS2 库资产 BASE_NUM × ICON_SCALE 缩放）
        var iconH:Number = TooltipConstants.BASE_NUM * (TooltipConstants.ICON_SCALE / 100);
        trace("GT_META|BASE_NUM=" + TooltipConstants.BASE_NUM
            + ",INTRO_MAX_W=" + TooltipConstants.INTRO_MAX_W
            + ",MIN_W=" + TooltipConstants.MIN_W
            + ",MAX_W=" + TooltipConstants.MAX_W
            + ",TEXT_PAD=" + TooltipConstants.TEXT_PAD
            + ",BG_HEIGHT_OFFSET=" + TooltipConstants.BG_HEIGHT_OFFSET
            + ",TEXT_Y_EQUIPMENT=" + TooltipConstants.TEXT_Y_EQUIPMENT
            + ",TEXT_Y_BASE=" + TooltipConstants.TEXT_Y_BASE
            + ",MOUSE_OFFSET=" + TooltipConstants.MOUSE_OFFSET
            + ",HEIGHT_ADJUST=" + TooltipConstants.HEIGHT_ADJUST
            + ",ICON_SCALE=" + TooltipConstants.ICON_SCALE
            + ",ICON_OFFSET=" + TooltipConstants.ICON_OFFSET
            + ",BASE_SCALE=" + TooltipConstants.BASE_SCALE
            + ",BASE_OFFSET=" + TooltipConstants.BASE_OFFSET
            + ",ICON_H_PX=" + iconH
            + ",DUAL_PANEL_MARGIN=" + TooltipConstants.DUAL_PANEL_MARGIN
            + ",STAGE_W=" + Stage.width
            + ",STAGE_H=" + Stage.height);
    }

    /**
     * 真实复刻 TooltipLayout.positionTooltip 的双面板分支算法，给定 (introBgH, mainBgH, mainTH, iconH, mouseY)
     * 返回 (rightBg_y, rightBg_h_final, tips_y, branch) — 不依赖 MovieClip，纯函数。
     */
    private static function simulatePose(introBgH:Number, mainBgH:Number, mainTH:Number, iconH:Number, mouseY:Number, stageH:Number):Object {
        // tips._height = max(introBgH, mainBgH)（mainBgH 是 base = textH+10，不含 floor）
        var tipsH:Number = Math.max(introBgH, mainBgH);
        var tipsY:Number = Math.min(stageH - tipsH, Math.max(0, mouseY - tipsH - TooltipConstants.MOUSE_OFFSET));
        var rightBottomH:Number = tipsY + mainBgH;
        var offset:Number = mouseY - rightBottomH - TooltipConstants.MOUSE_OFFSET;

        var rightBgY:Number;   // rightBg 在 tips 内的 y（相对，不是 stage）
        var rightBgH:Number;
        var branch:String;
        if (offset > 0) {
            // IF 分支：mainBg 整块下移 offset，高度不变
            rightBgY = offset;
            rightBgH = mainBgH;
            branch = "IF";
        } else {
            // ELSE 分支：mainBg 高度被 max(textH, iconH)+10 顶起
            rightBgY = 0;
            rightBgH = Math.max(mainTH, iconH) + TooltipConstants.HEIGHT_ADJUST;
            branch = "ELSE";
        }
        return {rightBgY: rightBgY, rightBgH: rightBgH, tipsY: tipsY, branch: branch, offset: offset};
    }

    private static function dumpAllSplitItems():Void {
        var allItems:Array = ItemUtil.itemDataArray;
        if (allItems == null || allItems.length == 0) {
            trace("  [WARN] No items loaded!");
            return;
        }

        // 字段说明：
        //   name        item.name
        //   type/use    item.type "/" item.use（用于按物品种类筛 fixture）
        //   dT/dM/dL    desc total / maxLine / lineCount score
        //   iT/iM/iL    intro 同上
        //   introW      AS2 算出的 intro 宽度
        //   mainW       AS2 算出的 main 宽度（含 balanceWidth 二分搜索后）
        //   introTH     introText.textHeight @introW
        //   mainTH      mainText.textHeight @mainW
        //   introBgH    introBg 高度 = introTH + 220
        //   mainBgH     mainBg 高度（基础） = mainTH + 10
        //   mainBgFlr   mainBg 高度下限（positionTooltip else 分支） = max(mainTH, iconH) + 10
        trace("GT_HEAD|name|type|use|dT|dM|dL|iT|iM|iL|introW|mainW|introTH|mainTH|introBgH|mainBgH|mainBgFlr");
        // GT_POSE 行：模拟 positionTooltip 在不同 mouseY 下的 desc 实际位置
        // 字段：name|mouseY|branch|tipsY|rightBgY|rightBgH|offset
        // 解读：rightBgY 是 desc 面板在 tips 内的相对 y（相对 tips 顶部），rightBgH 是 desc 面板实际高度
        trace("GT_POSE_HEAD|name|mouseY|branch|tipsY|rightBgY|rightBgH|offset");

        var bi = MockItemFactory.mockBaseItem();
        var introTf:Object = TooltipBridge.getIntroTextBox();
        var mainTf:Object = TooltipBridge.getMainTextBox();
        var iconH:Number = TooltipConstants.BASE_NUM * (TooltipConstants.ICON_SCALE / 100);
        var stageH:Number = Stage.height;
        // mouseY sweep: 鼠标从顶到底覆盖 stage 全程，间隔 ~stageH/8（共 9 个采样点）
        var mouseSweep:Array = [];
        var ms:Number = 8;
        for (var sm:Number = 0; sm <= ms; sm++) {
            mouseSweep.push(Math.round(sm * stageH / ms));
        }
        var dumped:Number = 0;

        for (var i:Number = 0; i < allItems.length; i++) {
            var item:Object = allItems[i];
            if (item == null) continue;

            var descText:String = TooltipComposer.generateItemDescriptionText(item, bi);
            var introText:String = TooltipComposer.generateIntroPanelContent(bi, item, bi.value);

            // 只 dump split 模式物品（merge 模式只有单面板，几何简单）
            if (!TooltipLayout.shouldSplitSmart(descText, introText, null)) continue;

            var descSc:Object = StringUtils.htmlScoresBoth(descText, null, _scratch);
            var dT:Number = descSc.total;
            var dM:Number = descSc.maxLine;
            var dL:Number = descSc.lineCount;
            // htmlScoresBoth 复用 scratch，第二次 call 会覆盖第一次结果，所以这里再开一个对象
            var introScScratch:Object = {total: 0, maxLine: 0, lineCount: 0};
            var introSc:Object = StringUtils.htmlScoresBoth(introText, null, introScScratch);
            var iT:Number = introSc.total;
            var iM:Number = introSc.maxLine;
            var iL:Number = introSc.lineCount;

            // intro 宽：AS2 端 introBg 用 estimateWidth 把内容塞进 [MIN_W, INTRO_MAX_W]
            var introW:Number = TooltipLayout.estimateWidth(introText,
                TooltipConstants.MIN_W, TooltipConstants.INTRO_MAX_W);
            // main 宽：先用 estimateMainWidth 估算 + balanceWidth 二分搜索 shrink-to-fit
            var initMainW:Number = TooltipLayout.estimateMainWidth(descText,
                TooltipConstants.MIN_W, TooltipConstants.MAX_W);
            var mainW:Number = TooltipLayout.balanceWidth(initMainW, descText,
                TooltipConstants.MAX_W);

            // 测 introText textHeight @ introW
            introTf.wordWrap = true;
            introTf._width = introW;
            introTf.htmlText = introText;
            var introTH:Number = introTf.textHeight;

            // 测 mainText textHeight @ mainW
            mainTf.wordWrap = true;
            mainTf._width = mainW;
            mainTf.htmlText = descText;
            var mainTH:Number = mainTf.textHeight;

            // AS2 公式计算面板高度
            var introBgH:Number = introTH + TooltipConstants.BASE_NUM + TooltipConstants.BG_HEIGHT_OFFSET;
            var mainBgH:Number = mainTH + TooltipConstants.TEXT_PAD;
            var mainBgFlr:Number = Math.max(mainTH, iconH) + TooltipConstants.HEIGHT_ADJUST;

            trace("GT_ITEM|" + escapeBar(item.name)
                + "|" + escapeBar(String(item.type))
                + "|" + escapeBar(String(item.use))
                + "|" + dT + "|" + dM + "|" + dL
                + "|" + iT + "|" + iM + "|" + iL
                + "|" + introW + "|" + mainW
                + "|" + introTH + "|" + mainTH
                + "|" + introBgH + "|" + mainBgH + "|" + mainBgFlr);

            // HTML 内容（给 web fixture 重新渲染做 box-model diff 用）
            // 换行/竖线在 escapeForLine 里替换为 ¶ / _，python 解析时再还原
            trace("GT_HTML_INTRO|" + escapeBar(item.name) + "|" + escapeForLine(introText));
            trace("GT_HTML_DESC|" + escapeBar(item.name) + "|" + escapeForLine(descText));

            // 该 item 在不同 mouseY 下的 pose（模拟 positionTooltip）
            for (var mi:Number = 0; mi < mouseSweep.length; mi++) {
                var mY:Number = mouseSweep[mi];
                var pose:Object = simulatePose(introBgH, mainBgH, mainTH, iconH, mY, stageH);
                trace("GT_POSE|" + escapeBar(item.name)
                    + "|" + mY + "|" + pose.branch
                    + "|" + pose.tipsY + "|" + pose.rightBgY
                    + "|" + pose.rightBgH + "|" + pose.offset);
            }
            dumped++;
        }
        trace("GT_TOTAL|" + dumped);
    }

    /** 把 | 替换成 _ 避免破坏 GT 行的列分隔 */
    private static function escapeBar(s:String):String {
        if (s == null) return "";
        return s.split("|").join("_");
    }

    /** 整行内容转义：竖线 → _，换行 → ¶ (U+00B6)，回车 → ¤
     *  目的是把多行 HTML 塞进单行 trace；python 端解析时反向替换 */
    private static function escapeForLine(s:String):String {
        if (s == null) return "";
        var r:String = s.split("|").join("_");
        r = r.split("\n").join("¶");
        r = r.split("\r").join("¤");
        return r;
    }
}
