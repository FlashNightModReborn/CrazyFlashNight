import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.string.StringUtils;

class org.flashNight.gesh.tooltip.TooltipLayout {

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
        // _root.发布消息(minW,maxW,lengthScore,widthEst,Math.max(minW, Math.min(widthEst, maxW)));
        return Math.max(minW, Math.min(widthEst, maxW));
    }
 

    // === 应用简介布局（1:1 复刻 _root.注释布局.应用简介布局） ===
    // 返回 { width:Number, heightOffset:Number }
    public static function applyIntroLayout(itemType:String, target:MovieClip, background:MovieClip, text:MovieClip):Object {
        var stringWidth:Number;
        var bgHeightOffset:Number;


        switch (itemType) {
            case "武器":
            case "防具":
            case "技能":
                stringWidth = TooltipConstants.BASE_NUM;
                background._width = TooltipConstants.BASE_NUM;
                background._x = -TooltipConstants.BASE_NUM;

                target._x = -TooltipConstants.BASE_NUM + TooltipConstants.BASE_OFFSET;
                target._xscale = target._yscale = TooltipConstants.BASE_SCALE;

                text._x = -TooltipConstants.BASE_NUM;
                text._y = TooltipConstants.TEXT_Y_EQUIPMENT;

                bgHeightOffset = TooltipConstants.BASE_NUM + TooltipConstants.BG_HEIGHT_OFFSET;
                break;

            default:
                var scaledWidth:Number = TooltipConstants.BASE_NUM * TooltipConstants.RATE;

                stringWidth = scaledWidth;
                background._width = scaledWidth;
                background._x = -scaledWidth;

                target._x = -scaledWidth + TooltipConstants.BASE_OFFSET * TooltipConstants.RATE;
                target._xscale = target._yscale = TooltipConstants.BASE_SCALE * TooltipConstants.RATE;

                text._x = -scaledWidth;
                // 保持原逻辑：text._y 依赖 text._x
                text._y = TooltipConstants.TEXT_Y_BASE - text._x;

                bgHeightOffset = TooltipConstants.BG_HEIGHT_OFFSET + TooltipConstants.RATE * TooltipConstants.BASE_NUM;
                break;
        }

        return {width: stringWidth, heightOffset: bgHeightOffset};
    }

    // === 定位注释框（1:1 复刻 _root.注释布局.定位注释框） ===
    public static function positionTooltip(tips:MovieClip, background:MovieClip, mouseX:Number, mouseY:Number):Void {
        var introBg:MovieClip = tips.简介背景; // 舞台实例名保留中文
        var rightBg:MovieClip = tips.背景; // 舞台实例名保留中文
        var isAbbr:Boolean = !introBg._visible;

        if (isAbbr) {
            // 简介背景隐藏时
            tips._x = Math.min(Stage.width - background._width, Math.max(0, mouseX - background._width));
            tips._y = Math.min(Stage.height - background._height, Math.max(0, mouseY - background._height - TooltipConstants.MOUSE_OFFSET));
            return;
        }
        // 简介背景显示时 
        if (rightBg._visible) {
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
                tips.文本框._y = offset;
                tips.背景._y = offset;
            } else {
                var icon:MovieClip = tips.物品图标定位;
                rightBg._height = Math.max(tips.文本框.textHeight, icon._height) + TooltipConstants.HEIGHT_ADJUST;
            }

            tips._x = Math.max(minX, Math.min(desiredX, maxX));
        } else {
            // 只有左背景可见时
            tips._x = Math.min(Stage.width - introBg._width, Math.max(0, mouseX - introBg._width)) + introBg._width;
            tips._y = Math.min(Stage.height - introBg._height, Math.max(0, mouseY - introBg._height - TooltipConstants.MOUSE_OFFSET));

            // 左背景高度自适应
            introBg._height = tips.简介文本框.textHeight + TooltipConstants.HEIGHT_ADJUST;
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
            var layoutTypeToUse:String = layoutType ? layoutType : "装备";
            var layout:Object = applyIntroLayout(layoutTypeToUse, target, background, text);
            var stringWidth:Number = Math.max(contentWidth, layout.width);
            var backgroundHeightOffset:Number = layout.heightOffset;

            // 显示注释文本
            showTooltip(stringWidth, contentText, "简介");

            // 图标挂载，使用 "图标-" + 图标名 的命名规则
            if (target.icon) target.icon.removeMovieClip();
            var iconString:String = "图标-" + iconName;
            var icon:MovieClip = target.attachMovie(iconString, "icon", target.getNextHighestDepth());
            icon._xscale = icon._yscale = TooltipConstants.ICON_SCALE;
            icon._x = icon._y = TooltipConstants.ICON_OFFSET;

            // 确保图标层级在简介背景之上
            if (tips.简介背景) {
                var iconDepth:Number = target.getDepth();
                var bgDepth:Number = tips.简介背景.getDepth();
                if (iconDepth <= bgDepth) {
                    target.swapDepths(bgDepth + TooltipConstants.DEPTH_INCREMENT);
                }
            }

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
        var target:MovieClip = tips[frameType + "文本框"];
        var background:MovieClip = tips[frameType + "背景"];

        tips._visible = true;
        target.htmlText = content;
        target._width = width;

        background._width = target._width;
        background._height = target.textHeight + TooltipConstants.TEXT_PAD;
        target._height = target.textHeight + TooltipConstants.TEXT_PAD;

        // 使用定位逻辑处理注释框定位
        positionTooltip(tips, background, _root._xmouse, _root._ymouse);
        
        // 对主框体也应用边界回弹保护
        if (frameType != "简介") {
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
