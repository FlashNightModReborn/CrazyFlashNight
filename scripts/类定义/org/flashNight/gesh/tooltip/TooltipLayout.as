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

    // === 估算文本宽度（使用 htmlLengthScore 智能计算） ===
    public static function estimateWidth(html:String, minW:Number, maxW:Number):Number {
        if (minW === undefined) {
            minW = TooltipConstants.MIN_W;
        }
        if (maxW === undefined) {
            maxW = TooltipConstants.MAX_W;
        }

        // 使用 htmlLengthScore 获取加权长度分数
        var lengthScore:Number = StringUtils.htmlLengthScore(html, null);
        // 乘以 CHAR_AVG_WIDTH 作为像素缩放系数
        var widthEst:Number = lengthScore * TooltipConstants.CHAR_AVG_WIDTH;
        return Math.max(minW, Math.min(widthEst, maxW));
    }
 

    // === 应用简介布局（1:1 复刻 _root.注释布局.应用简介布局） ===
    // 返回 { width:Number, heightOffset:Number }
    public static function applyIntroLayout(itemType:String, target:MovieClip, background:MovieClip, text:MovieClip):Object {
        var stringWidth:Number;
        var bgHeightOffset:Number;


        switch (itemType) {
            case ItemUseTypes.TYPE_WEAPON:
            case ItemUseTypes.TYPE_ARMOR:
            case ItemUseTypes.TYPE_SKILL:
            case ItemUseTypes.POTION:
                stringWidth = TooltipConstants.BASE_NUM;
                background._width = TooltipConstants.BASE_NUM;
                background._x = -TooltipConstants.BASE_NUM;

                // 图标定位参数直接复刻 Flash 源文件中的变换矩阵
                // 注释框.xml:23 物品图标定位: <Matrix a="4.86798" d="4.86798" tx="-192.5" ty="7.5"/>
                // a/d = 4.86798 → 486.8% 缩放, tx = -192.5 ≈ -200 + 7.5
                target._x = -TooltipConstants.BASE_NUM + TooltipConstants.BASE_OFFSET;
                target._xscale = target._yscale = TooltipConstants.BASE_SCALE;

                text._x = -TooltipConstants.BASE_NUM;
                // 装备布局使用固定的Y坐标(210),与 注释框.xml:39 中简介文本框的 ty="212" 对应
                text._y = TooltipConstants.TEXT_Y_EQUIPMENT;

                // 背景高度偏移 = 带宽(200) + 额外偏移(20)
                // 装备布局优先保证足够的垂直空间来容纳图标和文本
                bgHeightOffset = TooltipConstants.BASE_NUM + TooltipConstants.BG_HEIGHT_OFFSET;
                break;

            default:
                var scaledWidth:Number = TooltipConstants.BASE_NUM * TooltipConstants.RATE;

                stringWidth = scaledWidth;
                background._width = scaledWidth;
                background._x = -scaledWidth;

                // 紧凑布局下,图标位置和缩放也按 RATE(0.6) 等比缩放
                // 保持与装备布局相同的相对位置关系
                target._x = -scaledWidth + TooltipConstants.BASE_OFFSET * TooltipConstants.RATE;
                target._xscale = target._yscale = TooltipConstants.BASE_SCALE * TooltipConstants.RATE;

                text._x = -scaledWidth;
                // 重要：Y坐标基于简介带(intro band)的宽度计算
                // 注释框素材采用右锚定、左扩展的布局(注册点在右边缘,简介带向左生长)
                // 在 注释框.xml 中,简介文本框坐标为 x=-198, y=212
                // 即 y ≈ TEXT_Y_BASE(10) + 宽度(200) = 210,保持文本垂直位置与带宽耦合
                // 当 scaledWidth 改变时(如紧凑布局 120),Y 坐标同步调整为 10+120=130
                text._y = TooltipConstants.TEXT_Y_BASE + scaledWidth;

                // 紧凑布局的背景高度偏移 = 额外偏移(20) + 缩放后带宽(120)
                // 注意:顺序与装备布局相反,优先保证基础偏移,再叠加缩放宽度
                bgHeightOffset = TooltipConstants.BG_HEIGHT_OFFSET + TooltipConstants.RATE * TooltipConstants.BASE_NUM;
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

            // 使用指定的布局类型，默认为装备布局
            var layoutTypeToUse:String = layoutType ? layoutType : TooltipConstants.FRAME_EQUIPMENT;
            var layout:Object = applyIntroLayout(layoutTypeToUse, target, background, text);
            var stringWidth:Number = Math.max(contentWidth, layout.width);
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
