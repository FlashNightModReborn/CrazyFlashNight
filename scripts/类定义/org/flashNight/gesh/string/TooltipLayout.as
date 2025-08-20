import org.flashNight.gesh.string.TooltipConstants;

class org.flashNight.gesh.string.TooltipLayout {

    // === 估算文本宽度（1:1 复刻 _root.注释布局.估算宽度） ===
    public static function estimateWidth(html:String, minW:Number, maxW:Number):Number {
        if (minW === undefined) {
            minW = TooltipConstants.MIN_W;
        }
        if (maxW === undefined) {
            maxW = TooltipConstants.MAX_W;
        }

        var charCount:Number = html.length;
        var widthEst:Number = charCount * TooltipConstants.CHAR_AVG_WIDTH;
        // _root.发布消息(minW,maxW,charCount,widthEst,Math.max(minW, Math.min(widthEst, maxW)));
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
                text._y = 210;

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
                text._y = 10 - text._x;

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
            tips._y = Math.min(Stage.height - background._height, Math.max(0, mouseY - background._height - 20));
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
            tips._y = Math.min(Stage.height - tips._height, Math.max(0, mouseY - tips._height - 20));

            var rightBottomHeight:Number = tips._y + rightBg._height;
            var offset:Number = mouseY - rightBottomHeight - 20;

            if (offset > 0) {
                tips.文本框._y = offset;
                tips.背景._y = offset;
            } else {
                var icon:MovieClip = tips.物品图标定位;
                rightBg._height = Math.max(tips.文本框.textHeight, icon._height) + 10;
            }

            tips._x = Math.max(minX, Math.min(desiredX, maxX));
        } else {
            // 只有左背景可见时
            tips._x = Math.min(Stage.width - introBg._width, Math.max(0, mouseX - introBg._width)) + introBg._width;
            tips._y = Math.min(Stage.height - introBg._height, Math.max(0, mouseY - introBg._height - 20));

            // 左背景高度自适应
            introBg._height = tips.简介文本框.textHeight + 10;
        }
    }
}
