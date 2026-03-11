import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.ItemUseTypes;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.string.StringUtils;

class org.flashNight.gesh.tooltip.TooltipLayout {

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
        var threshold:Number = (options && options.threshold != undefined)
            ? options.threshold
            : TooltipConstants.SPLIT_THRESHOLD;
        var totalMultiplier:Number = (options && options.totalMultiplier != undefined)
            ? options.totalMultiplier
            : TooltipConstants.SMART_TOTAL_MULTIPLIER;
        var descDivisor:Number = (options && options.descDivisor != undefined)
            ? options.descDivisor
            : TooltipConstants.SMART_DESC_DIVISOR;

        var descLength:Number = StringUtils.htmlLengthScore(descriptionText, null);
        var totalLength:Number = descLength + StringUtils.htmlLengthScore(introText, null);

        return totalLength > threshold * totalMultiplier && descLength > threshold / descDivisor;
    }

    /**
     * 智能分栏判定 + 描述评分一次性计算（消除 renderItemTooltipSmart 中的重复扫描）。
     *
     * 返回 {needSplit:Boolean, descTotal:Number, descMaxLine:Number}
     * 调用方可直接将 descTotal/descMaxLine 传入 estimateMainWidthFromScores 跳过二次扫描。
     * 返回值复用静态对象 _splitResult，调用方需立即读取。
     */
    private static var _splitResult:Object = {needSplit: false, descTotal: 0, descMaxLine: 0};

    public static function shouldSplitSmartWithScores(descriptionText:String, introText:String, options:Object):Object {
        var out:Object = _splitResult;
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
        var descScores:Object = StringUtils.htmlScoresBoth(descriptionText, null);
        var descTotal:Number = descScores.total;
        var descMaxLine:Number = descScores.maxLine;

        // intro 只需要 total
        var introTotal:Number = StringUtils.htmlLengthScore(introText, null);

        var totalLength:Number = descTotal + introTotal;

        out.needSplit = totalLength > threshold * totalMultiplier && descTotal > threshold / descDivisor;
        out.descTotal = descTotal;
        out.descMaxLine = descMaxLine;
        return out;
    }

    // === 估算文本宽度（双维度：总量 + 最长行，取最大值） ===
    //
    // 维度1（总量）：内容越多 → 框越宽，减少换行层数
    // 维度2（最长行）：保证最宽单行放得下，系数取保守上界（ASCII ≈5.5px/unit + gutter）
    public static function estimateWidth(html:String, minW:Number, maxW:Number):Number {
        if (minW === undefined) minW = TooltipConstants.MIN_W;
        if (maxW === undefined) maxW = TooltipConstants.MAX_W;

        var scores:Object = StringUtils.htmlScoresBoth(html, null);
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

        var scores:Object = StringUtils.htmlScoresBoth(html, null);
        return estimateMainWidthFromScores(scores.total, scores.maxLine, html, minW, maxW);
    }

    /**
     * 从预计算的评分直接估算主框体宽度（避免重复扫描 HTML）。
     * @param totalScore  htmlScoresBoth.total
     * @param maxLineScore htmlScoresBoth.maxLine
     * @param html 原始 HTML（仅用于 split("<BR>") 计算行数）
     */
    public static function estimateMainWidthFromScores(totalScore:Number, maxLineScore:Number, html:String, minW:Number, maxW:Number):Number {
        if (minW === undefined) minW = TooltipConstants.MIN_W;
        if (maxW === undefined) maxW = TooltipConstants.MAX_W;

        var totalBased:Number = totalScore * TooltipConstants.MAIN_CHAR_AVG_WIDTH;

        if (maxLineScore <= 0) {
            return Math.max(minW, Math.min(totalBased, maxW));
        }

        var lineBased:Number = maxLineScore * TooltipConstants.LINE_WIDTH_SCALE
                             + TooltipConstants.LINE_GUTTER;

        var lineCount:Number = html.split("<BR>").length;
        if (lineCount < 1) lineCount = 1;
        var meanScore:Number = totalScore / lineCount;
        var t:Number = Math.min(1, meanScore / maxLineScore);
        var uniformity:Number = t * t * (3 - 2 * t);

        var widthEst:Number = lineBased * uniformity + totalBased * (1 - uniformity);
        return Math.max(minW, Math.min(widthEst, maxW));
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
