import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.ItemUseTypes;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.string.StringUtils;

class org.flashNight.gesh.tooltip.TooltipLayout {

    private static var _scoreScratch:Object = {total: 0, maxLine: 0, lineCount: 0};
    private static var _splitScratch:Object = {
        needSplit: false,
        descTotal: 0,
        descMaxLine: 0,
        descLineCount: 0,
        introTotal: 0
    };

    // === 智能分栏判定 ===

    /**
     * 判断是否需要对注释进行"智能分栏"显示。
     * @param descriptionText:String 主描述文本（通常是长描述）
     * @param introText:String 简介面板文本（标题、类型、基础信息）
     * @param options:Object 可选参数：
     *   {
     *     totalMultiplier:Number, // 默认 TooltipConstants.SMART_TOTAL_MULTIPLIER
     *     descDivisor:Number,     // 默认 TooltipConstants.SMART_DESC_DIVISOR
     *     threshold:Number        // 默认 TooltipConstants.SPLIT_THRESHOLD
     *   }
     * @return Boolean 是否采用"分离显示"（true = 长内容分栏；false = 短内容合并）
     */
    public static function shouldSplitSmart(descriptionText:String, introText:String, options:Object):Boolean {
        return shouldSplitSmartWithScores(descriptionText, introText, options, _splitScratch).needSplit;
    }

    /**
     * 智能分栏判定 + 描述评分一次性计算（消除 renderItemTooltipSmart 中的重复扫描）。
     *
     * 返回 {needSplit:Boolean, descTotal:Number, descMaxLine:Number, descLineCount:Number, introTotal:Number}
     * 调用方可直接将 descTotal/descMaxLine 传入 estimateMainWidthFromScores 跳过二次扫描。
     * 若传入 out，则结果写回该对象，供热路径复用。
     */
    public static function shouldSplitSmartWithScores(descriptionText:String, introText:String, options:Object, out:Object):Object {
        if (out == undefined || out == null) out = {};
        var threshold:Number = (options && options.threshold != undefined)
            ? options.threshold
            : TooltipConstants.SPLIT_THRESHOLD;
        var totalMultiplier:Number = (options && options.totalMultiplier != undefined)
            ? options.totalMultiplier
            : TooltipConstants.SMART_TOTAL_MULTIPLIER;
        var descDivisor:Number = (options && options.descDivisor != undefined)
            ? options.descDivisor
            : TooltipConstants.SMART_DESC_DIVISOR;

        // 描述文本：单次扫描同时拿到 total + maxLine
        var descScores:Object = StringUtils.htmlScoresBoth(descriptionText, null, _scoreScratch);
        var descTotal:Number = descScores.total;
        var descMaxLine:Number = descScores.maxLine;
        var descLineCount:Number = descScores.lineCount;

        // intro 只需要 total
        var introTotal:Number = StringUtils.htmlScoresBoth(introText, null, _scoreScratch).total;

        var totalLength:Number = descTotal + introTotal;

        out.needSplit = totalLength > threshold * totalMultiplier && descTotal > threshold / descDivisor;
        out.descTotal = descTotal;
        out.descMaxLine = descMaxLine;
        out.descLineCount = descLineCount;
        out.introTotal = introTotal;
        return out;
    }

    // === 估算文本宽度（双维度：总量 + 最长行，取最大值） ===
    //
    // 维度1（总量）：内容越多 → 框越宽，减少换行层数
    // 维度2（最长行）：保证最宽单行放得下，系数取保守上界（ASCII ≈5.5px/unit + gutter）
    public static function estimateWidth(html:String, minW:Number, maxW:Number):Number {
        if (minW === undefined) minW = TooltipConstants.MIN_W;
        if (maxW === undefined) maxW = TooltipConstants.MAX_W;

        var scores:Object = StringUtils.htmlScoresBoth(html, null, _scoreScratch);
        var totalBasedWidth:Number = scores.total * TooltipConstants.CHAR_AVG_WIDTH;
        var lineBasedWidth:Number = scores.maxLine * TooltipConstants.LINE_WIDTH_SCALE
                                  + TooltipConstants.LINE_GUTTER;

        var widthEst:Number = Math.max(totalBasedWidth, lineBasedWidth);
        return Math.max(minW, Math.min(widthEst, maxW));
    }

    // === 主框体宽度估算（分布感知：均匀度加权插值） ===
    //
    // 维度1（总量）：totalScore × MAIN_CHAR_AVG_WIDTH —— 按内容体量定宽，接受折行
    // 维度2（最长行）：maxLineScore × LINE_WIDTH_SCALE —— 最长行不折行所需宽度
    //
    // 均匀度 = smoothstep(meanLineScore / maxLineScore)，自然落于 [0,1]
    //   meanLineScore = totalScore / 实际行数（<BR> 计数）
    //   均匀内容（MACSIV，各行等宽）：mean≈max → uniformity→1 → 偏最长行估算
    //   稀疏内容（聚束射线弹，22短行+1长描述）：mean≪max → uniformity→0 → 偏总量估算
    //
    // 插值：finalW = lineBased × uniformity + totalBased × (1 - uniformity)
    public static function estimateMainWidth(html:String, minW:Number, maxW:Number):Number {
        if (minW === undefined) minW = TooltipConstants.MIN_W;
        if (maxW === undefined) maxW = TooltipConstants.MAX_W;

        var scores:Object = StringUtils.htmlScoresBoth(html, null, _scoreScratch);
        return estimateMainWidthFromMetrics(scores.total, scores.maxLine, scores.lineCount, minW, maxW);
    }

    /**
     * 从预计算的评分与逻辑行数直接估算主框体宽度。
     *
     * sqrt 公式：W = sqrt(r × totalScore × PIX_PER_UNIT × LINE_HEIGHT)
     * 其中 r 由 RATIO_MIN 经 smoothstep 渐变到 RATIO_MAX，
     * 以 totalScore / RATIO_SCORE_CAP 为插值参数。
     *
     * 短内容 → r≈0.618（黄金比例，纵向） → 宽度适中
     * 长内容 → r≈1.5（横向）              → 宽度增大但受 maxLine 约束
     *
     * 上界 clamp：min(sqrtW, maxLineW) 防止宽于最长行所需像素。
     */
    public static function estimateMainWidthFromMetrics(totalScore:Number, maxLineScore:Number, lineCount:Number, minW:Number, maxW:Number):Number {
        if (minW === undefined) minW = TooltipConstants.MIN_W;
        if (maxW === undefined) maxW = TooltipConstants.MAX_W;

        if (totalScore <= 0) return minW;

        // smoothstep 插值 r：短内容偏纵向（0.618），长内容偏横向（1.5）
        var t:Number = totalScore / TooltipConstants.RATIO_SCORE_CAP;
        if (t > 1) t = 1;
        var ss:Number = t * t * (3 - 2 * t);
        var r:Number = TooltipConstants.RATIO_MIN + ss * (TooltipConstants.RATIO_MAX - TooltipConstants.RATIO_MIN);

        var sqrtW:Number = Math.sqrt(r * totalScore * TooltipConstants.PIX_PER_UNIT * TooltipConstants.LINE_HEIGHT);

        // P0 安全网：高度下限宽度，避免估算器给出明显不可能压住高度的初值
        var wFloor:Number = totalScore * TooltipConstants.PIX_PER_UNIT / TooltipConstants.MAX_RENDERED_LINES;
        if (sqrtW < wFloor) sqrtW = wFloor;

        // maxLine 约束：宽度不超过最长行所需像素 + 边距
        if (maxLineScore > 0) {
            var maxLineW:Number = maxLineScore * TooltipConstants.PIX_PER_UNIT + TooltipConstants.LINE_GUTTER;
            if (sqrtW > maxLineW) sqrtW = maxLineW;
        }

        return Math.max(minW, Math.min(sqrtW, maxW));
    }

    /**
     * 从预计算的评分直接估算主框体宽度（避免重复扫描 HTML）。
     * @param totalScore  htmlScoresBoth.total
     * @param maxLineScore htmlScoresBoth.maxLine
     * @param html 原始 HTML（仅用于兼容旧调用方估算行数）
     */
    public static function estimateMainWidthFromScores(totalScore:Number, maxLineScore:Number, html:String, minW:Number, maxW:Number):Number {
        return estimateMainWidthFromMetrics(totalScore, maxLineScore, StringUtils.htmlLogicalLineCount(html), minW, maxW);
    }

    /**
     * 二分搜索宽度平衡（高度约束 + shrink-to-fit）。
     *
     * modeA：渲染行 > MAX_RENDERED_LINES 时，在 [initW, maxW] 搜索
     *        使行数 <= MAX_RENDERED_LINES 的最小宽度。
     *        极限探针：若 maxW 下仍超标，熔断返回 initW。
     * modeB：渲染行 <= MAX_RENDERED_LINES 时，O(1) shrink-to-fit
     *        读取 textWidth 紧缩到实际内容宽度。
     *
     * 性能关键：htmlText 全局仅赋值一次，循环内只改 _width。
     *
     * @param initW 初始估算宽度
     * @param html  HTML 内容
     * @param maxW  宽度上限
     * @return 优化后的宽度
     */
    public static function balanceWidth(initW:Number, html:String, maxW:Number):Number {
        if (maxW === undefined) maxW = TooltipConstants.MAX_W;

        // ★ 入口钳制：确保所有测量在真实渲染宽度范围内
        // 防止 initW > maxW 时 modeB 在过宽的宽度上判定"行数合规"，
        // 但最终被调用方裁到 maxW 后行数重新溢出
        if (initW > maxW) initW = maxW;

        var tf:MovieClip = TooltipBridge.getMainTextBox();
        if (tf == null) return initW;

        // 保存状态
        var savedWordWrap:Boolean = tf.wordWrap;
        var savedWidth:Number = tf._width;
        var savedHtml:String = tf.htmlText;

        // ★ htmlText 全局仅赋值一次
        tf.wordWrap = true;
        tf.htmlText = html;

        // 测量初始行数（在钳制后的 initW 下）
        var initLines:Number = TooltipBridge.measureRenderedLines(initW, false);
        if (initLines <= 1 || initLines < 0) {
            tf.wordWrap = savedWordWrap;
            tf._width = savedWidth;
            tf.htmlText = savedHtml;
            return initW;
        }

        var result:Number;

        if (initLines > TooltipConstants.MAX_RENDERED_LINES) {
            // === 极限探针 ===
            var maxWLines:Number = TooltipBridge.measureRenderedLines(maxW, false);
            if (maxWLines > TooltipConstants.MAX_RENDERED_LINES) {
                // 不可解：即使 maxW 也放不下，熔断返回 initW
                tf.wordWrap = savedWordWrap;
                tf._width = savedWidth;
                tf.htmlText = savedHtml;
                return initW;
            }

            // === modeA 二分：找 lines <= MAX_RENDERED_LINES 的最小宽度 ===
            var lo:Number = initW;
            var hi:Number = maxW;
            var prevLines:Number = -1;
            var iter:Number = 0;
            while (hi - lo > TooltipConstants.BALANCE_PRECISION
                   && iter < TooltipConstants.BALANCE_MAX_ITER) {
                var mid:Number = Math.floor((lo + hi) / 2);
                var midLines:Number = TooltipBridge.measureRenderedLines(mid, false);
                // 台阶感知早停
                if (midLines == prevLines && midLines <= TooltipConstants.MAX_RENDERED_LINES) {
                    hi = mid;
                    break;
                }
                prevLines = midLines;
                if (midLines <= TooltipConstants.MAX_RENDERED_LINES) {
                    hi = mid;
                } else {
                    lo = mid + 1;
                }
                iter++;
            }
            result = hi;
        } else {
            // === modeB O(1) shrink-to-fit ===
            tf._width = initW;
            var tightW:Number = tf.textWidth + 4; // +4 补 TextField 左右 2px 内边距
            result = Math.max(TooltipConstants.MIN_W, Math.min(tightW, initW));
        }

        // 恢复状态
        tf.wordWrap = savedWordWrap;
        tf._width = savedWidth;
        tf.htmlText = savedHtml;

        return result;
    }

    // === 精确测量并 clamp 宽度（优先 TextField 真实测量，降级到双维度估算） ===
    //
    // 真实测量在 AS2 同帧内同步完成，无视觉闪烁；
    // TextField 不可用时（如初始化前）自动回退到评分估算。
    public static function measureOrEstimateWidth(html:String, useIntroBox:Boolean, minW:Number, maxW:Number):Number {
        if (minW === undefined) minW = TooltipConstants.MIN_W;
        if (maxW === undefined) maxW = TooltipConstants.MAX_W;

        var measured:Number = TooltipBridge.measureTextLineWidth(html, useIntroBox);
        if (measured > 0) {
            return Math.max(minW, Math.min(measured, maxW));
        }
        // 降级到双维度评分估算
        return estimateWidth(html, minW, maxW);
    }
 

    // === 应用简介布局 ===
    // 返回 { width:Number, heightOffset:Number }
    //
    // customWidth（可选）：调用方传入的期望宽度（来自真实测量或估算）。
    //   装备/武器/技能/消耗品布局：X 轴（background._x / text._x / target._x）跟随 w；
    //   Y 轴（text._y）与 bgHeightOffset 固定不变，与面板宽度完全解耦。
    //   bgHeightOffset 始终 = BASE_NUM(200) + BG_HEIGHT_OFFSET(20) = 220，
    //   覆盖图标区纵深，不随宽度变化，避免底部出现大块空白。
    public static function applyIntroLayout(itemType:String, target:MovieClip, background:MovieClip, text:MovieClip, customWidth:Number):Object {
        var stringWidth:Number;
        var bgHeightOffset:Number;

        switch (itemType) {
            case ItemUseTypes.TYPE_WEAPON:
            case ItemUseTypes.TYPE_ARMOR:
            case ItemUseTypes.TYPE_SKILL:
            case ItemUseTypes.POTION:
                // X 轴：取 customWidth 与 BASE_NUM 的较大值，不超过 INTRO_MAX_W
                var w:Number = (customWidth != undefined && customWidth > TooltipConstants.BASE_NUM)
                    ? Math.min(customWidth, TooltipConstants.INTRO_MAX_W)
                    : TooltipConstants.BASE_NUM;

                stringWidth       = w;
                background._width = w;
                background._x     = -w;                                    // X 动态锚点

                // 图标定位参数复刻 Flash 源文件变换矩阵；X 跟随 w，大小/Y 不变
                // 注释框.xml:23  <Matrix a="4.86798" d="4.86798" tx="-192.5" ty="7.5"/>
                target._x         = -w + TooltipConstants.BASE_OFFSET;     // X 跟随
                target._xscale    = target._yscale = TooltipConstants.BASE_SCALE; // 大小固定

                text._x           = -w;                                    // X 跟随
                text._y           = TooltipConstants.TEXT_Y_EQUIPMENT;     // Y 固定（210）

                // ★ 关键：bgHeightOffset 固定为图标区高度基准，与 w 无关
                // BASE_NUM(200) = 图标区纵深；BG_HEIGHT_OFFSET(20) = 底部留白
                // 绑定到 w 会在 w>200 时凭空多出 (w-200) 的底部空白
                bgHeightOffset    = TooltipConstants.BASE_NUM + TooltipConstants.BG_HEIGHT_OFFSET;
                break;

            default:
                var scaledWidth:Number = TooltipConstants.BASE_NUM * TooltipConstants.RATE;

                stringWidth       = scaledWidth;
                background._width = scaledWidth;
                background._x     = -scaledWidth;

                target._x         = -scaledWidth + TooltipConstants.BASE_OFFSET * TooltipConstants.RATE;
                target._xscale    = target._yscale = TooltipConstants.BASE_SCALE * TooltipConstants.RATE;

                text._x           = -scaledWidth;
                // 紧凑布局：Y 与带宽耦合（历史逻辑，该分支不参与自适应宽度）
                text._y           = TooltipConstants.TEXT_Y_BASE + scaledWidth;
                bgHeightOffset    = TooltipConstants.BG_HEIGHT_OFFSET + TooltipConstants.RATE * TooltipConstants.BASE_NUM;
                break;
        }

        return {width: stringWidth, heightOffset: bgHeightOffset};
    }

    // === 定位注释框（使用 Bridge 访问 UI 元素） ===
    public static function positionTooltip(tips:MovieClip, background:MovieClip, mouseX:Number, mouseY:Number):Void {
        // 通过 Bridge 获取 UI 元素
        var introBg:MovieClip = TooltipBridge.getIntroBackground();
        var rightBg:MovieClip = TooltipBridge.getMainBackground();
        var mainText:MovieClip = TooltipBridge.getMainTextBox();
        var introText:MovieClip = TooltipBridge.getIntroTextBox();
        var icon:MovieClip = TooltipBridge.getIconTarget();

        if (!introBg) return; // 安全检查

        var isAbbr:Boolean = !introBg._visible;

        if (isAbbr) {
            // 简介背景隐藏时
            tips._x = Math.min(Stage.width - background._width, Math.max(0, mouseX - background._width));
            tips._y = Math.min(Stage.height - background._height, Math.max(0, mouseY - background._height - TooltipConstants.MOUSE_OFFSET));
            return;
        }
        // 简介背景显示时
        if (rightBg && rightBg._visible) {
            // 将注释框右边缘对齐到鼠标指针
            var desiredX:Number = mouseX - rightBg._width;

            // 允许的 X 范围
            var minX:Number = introBg._width;
            var maxX:Number = Stage.width - rightBg._width;

            // Y 定位（与原逻辑一致）
            tips._y = Math.min(Stage.height - tips._height, Math.max(0, mouseY - tips._height - TooltipConstants.MOUSE_OFFSET));

            var rightBottomHeight:Number = tips._y + rightBg._height;
            var offset:Number = mouseY - rightBottomHeight - TooltipConstants.MOUSE_OFFSET;

            if (offset > 0) {
                // 使用 Bridge 设置位置
                TooltipBridge.setPosition("main", NaN, offset);
                TooltipBridge.setPosition("mainBg", NaN, offset);
            } else {
                if (mainText && icon) {
                    rightBg._height = Math.max(mainText.textHeight, icon._height) + TooltipConstants.HEIGHT_ADJUST;
                }
            }

            tips._x = Math.max(minX, Math.min(desiredX, maxX));
        } else {
            // 只有左背景可见时(简介模式)
            // X定位:先计算左边缘位置,再加回宽度得到注册点(右边缘)的X坐标
            // 这样确保简介框完整显示且不超出屏幕边界
            tips._x = Math.min(Stage.width - introBg._width, Math.max(0, mouseX - introBg._width)) + introBg._width;
            tips._y = Math.min(Stage.height - introBg._height, Math.max(0, mouseY - introBg._height - TooltipConstants.MOUSE_OFFSET));

            // 左背景高度自适应
            if (introText) {
                introBg._height = introText.textHeight + TooltipConstants.HEIGHT_ADJUST;
            }
        }
    }

    // === 渲染图标注释（1:1 复刻 _root.注释图标核心） ===
    public static function renderIconTooltip(enable:Boolean, iconName:String, contentText:String, contentWidth:Number, layoutType:String):Void {
        var target:MovieClip = TooltipBridge.getIconTarget();
        var background:MovieClip = TooltipBridge.getIntroBackground();
        var text:MovieClip = TooltipBridge.getIntroTextBox();

        if (enable) {
            TooltipBridge.setVisibility("icon", true);
            TooltipBridge.setVisibility("intro", true);
            TooltipBridge.setVisibility("introBg", true);

            var tips:MovieClip = TooltipBridge.getTooltipContainer();

            // contentWidth 来自调用方（真实测量或估算），传入 applyIntroLayout 作为 customWidth
            // 这样 background._x / text._x 在同一次调用中就以正确的宽度锚定，无需二次修正
            var layoutTypeToUse:String = layoutType ? layoutType : TooltipConstants.FRAME_EQUIPMENT;
            var layout:Object = applyIntroLayout(layoutTypeToUse, target, background, text, contentWidth);
            var stringWidth:Number = layout.width;
            var backgroundHeightOffset:Number = layout.heightOffset;

            // 显示注释文本
            showTooltip(stringWidth, contentText, TooltipConstants.FRAME_INTRO);

            // 图标挂载：使用 Flash 库链接命名约定 "图标-" + 图标名
            // 例如: iconName="剑" → 库链接ID="图标-剑"
            if (target.icon) target.icon.removeMovieClip();
            var iconString:String = TooltipConstants.ICON_PREFIX + iconName;
            var icon:MovieClip = target.attachMovie(iconString, "icon", target.getNextHighestDepth());
            // 图标缩放和位置偏移:150%缩放,19像素偏移(基于美术设计的视觉平衡)
            icon._xscale = icon._yscale = TooltipConstants.ICON_SCALE;
            icon._x = icon._y = TooltipConstants.ICON_OFFSET;

            // 确保图标层级在简介背景之上
            TooltipBridge.ensureIconAboveIntroBg(TooltipConstants.DEPTH_INCREMENT);

            background._height = text._height + backgroundHeightOffset;
        } else {
            if (target.icon) target.icon.removeMovieClip();
            TooltipBridge.setVisibility("icon", false);
            TooltipBridge.setVisibility("intro", false);
            TooltipBridge.setVisibility("introBg", false);
        }
    }

    // === 基础注释显示控制 ===

    /**
     * 显示注释框：
     * - 设置文本内容和尺寸
     * - 处理背景尺寸
     * - 调用定位逻辑
     * 
     * @param width:Number 注释框宽度
     * @param content:String 注释内容HTML文本
     * @param frameType:String 框体类型（可选，默认为主框体）
     */
    public static function showTooltip(width:Number, content:String, frameType:String):Void {
        if(!frameType) {
            frameType = "";
            TooltipBridge.showMainElements();
        }

        TooltipBridge.resetMainPositions();

        var tips:MovieClip = TooltipBridge.getTooltipContainer();
        if (!tips) return; // 安全检查

        // 使用 Bridge 的动态解析器获取元素
        var target:MovieClip = TooltipBridge.getTextByFrameType(frameType);
        var background:MovieClip = TooltipBridge.getBgByFrameType(frameType);

        if (!target || !background) return; // 安全检查

        tips._visible = true;
        target.htmlText = content;
        target._width = width;

        background._width = target._width;
        background._height = target.textHeight + TooltipConstants.TEXT_PAD;
        target._height = target.textHeight + TooltipConstants.TEXT_PAD;

        // 使用定位逻辑处理注释框定位
        positionTooltip(tips, background, _root._xmouse, _root._ymouse);

        // 对主框体也应用边界回弹保护
        if (frameType != TooltipConstants.FRAME_INTRO) {
            TooltipBridge.clampContainerByBg(background, 8);
        }
    }

    /**
     * 清理并隐藏所有注释相关的显示元素：
     * - 隐藏主注释框
     * - 隐藏图标注释
     * - 清理文本内容
     * - 重置可见性状态
     */
    public static function hideTooltip():Void {
        TooltipBridge.hideAllElements();
        renderIconTooltip(false);
        TooltipBridge.clearAllContent();
    }
}
