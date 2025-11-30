/**
 * TooltipBridge - 注释UI适配器/门面类
 *
 * 设计目标：
 * - 将所有对 _root.注释框.* 的直接访问收口到统一接口
 * - 提供高层抽象，隐藏底层UI实现细节
 * - 便于未来UI结构变更时的维护
 * - 降低类间耦合，提高代码可测试性
 *
 * 使用示例：
 * ```actionscript
 * // 替换：_root.注释框.文本框.htmlText = content;
 * TooltipBridge.setTextContent("main", content);
 *
 * // 替换：_root.注释框.背景._visible = false;
 * TooltipBridge.setVisibility("mainBg", false);
 * ```
 */
import org.flashNight.gesh.tooltip.TooltipConstants;

class org.flashNight.gesh.tooltip.TooltipBridge {

    // ══════════════════════════════════════════════════════════════
    // UI元素访问 - 获取底层UI组件引用
    // ══════════════════════════════════════════════════════════════

    /**
     * 获取主文本框引用
     */
    public static function getMainTextBox():MovieClip {
        if (!_root.注释框 || !_root.注释框.文本框) {
            trace("[TooltipBridge] WARNING: 主文本框不存在");
            return null;
        }
        return _root.注释框.文本框;
    }

    /**
     * 获取主背景引用
     */
    public static function getMainBackground():MovieClip {
        if (!_root.注释框 || !_root.注释框.背景) {
            trace("[TooltipBridge] WARNING: 主背景不存在");
            return null;
        }
        return _root.注释框.背景;
    }

    /**
     * 获取简介文本框引用
     */
    public static function getIntroTextBox():MovieClip {
        if (!_root.注释框 || !_root.注释框.简介文本框) {
            trace("[TooltipBridge] WARNING: 简介文本框不存在");
            return null;
        }
        return _root.注释框.简介文本框;
    }

    /**
     * 获取简介背景引用
     */
    public static function getIntroBackground():MovieClip {
        if (!_root.注释框 || !_root.注释框.简介背景) {
            trace("[TooltipBridge] WARNING: 简介背景不存在");
            return null;
        }
        return _root.注释框.简介背景;
    }

    /**
     * 获取图标定位器引用
     */
    public static function getIconTarget():MovieClip {
        if (!_root.注释框 || !_root.注释框.物品图标定位) {
            trace("[TooltipBridge] WARNING: 图标定位器不存在");
            return null;
        }
        return _root.注释框.物品图标定位;
    }

    /**
     * 获取注释容器引用
     */
    public static function getTooltipContainer():MovieClip {
        if (!_root.注释框) {
            trace("[TooltipBridge] WARNING: 注释容器不存在");
            return null;
        }
        return _root.注释框;
    }

    // ══════════════════════════════════════════════════════════════
    // 动态解析器 - 支持 frameType 参数化访问
    // ══════════════════════════════════════════════════════════════

    /**
     * 根据框体类型动态获取文本框
     * @param frameType:String 框体类型（"" 表示主框体，"简介" 表示简介框体）
     * @return MovieClip 文本框引用，不存在时返回 null
     *
     * @example
     * ```actionscript
     * var mainText = TooltipBridge.getTextByFrameType("");      // 获取主文本框
     * var introText = TooltipBridge.getTextByFrameType("简介"); // 获取简介文本框
     * ```
     */
    public static function getTextByFrameType(frameType:String):MovieClip {
        var container:MovieClip = getTooltipContainer();
        if (!container) return null;

        var textBoxName:String = frameType + TooltipConstants.SUFFIX_TEXTBOX;
        var textBox:MovieClip = container[textBoxName];

        if (!textBox) {
            trace("[TooltipBridge] WARNING: " + TooltipConstants.SUFFIX_TEXTBOX + " '" + textBoxName + "' 不存在");
            return null;
        }

        return textBox;
    }

    /**
     * 根据框体类型动态获取背景
     * @param frameType:String 框体类型（"" 表示主框体，"简介" 表示简介框体）
     * @return MovieClip 背景引用，不存在时返回 null
     *
     * @example
     * ```actionscript
     * var mainBg = TooltipBridge.getBgByFrameType("");      // 获取主背景
     * var introBg = TooltipBridge.getBgByFrameType("简介"); // 获取简介背景
     * ```
     */
    public static function getBgByFrameType(frameType:String):MovieClip {
        var container:MovieClip = getTooltipContainer();
        if (!container) return null;

        var bgName:String = frameType + TooltipConstants.SUFFIX_BG;
        var bg:MovieClip = container[bgName];

        if (!bg) {
            trace("[TooltipBridge] WARNING: " + TooltipConstants.SUFFIX_BG + " '" + bgName + "' 不存在");
            return null;
        }

        return bg;
    }

    // ══════════════════════════════════════════════════════════════
    // 统一属性操作接口
    // ══════════════════════════════════════════════════════════════

    /**
     * 设置文本内容
     * @param target:String 目标标识 ("main", "intro")
     * @param content:String HTML文本内容
     */
    public static function setTextContent(target:String, content:String):Void {
        var textBox:MovieClip = getTextBoxByTarget(target);
        if (textBox) {
            textBox.htmlText = content;
        }
    }

    /**
     * 设置元素可见性
     * @param target:String 目标标识 ("main", "mainBg", "intro", "introBg", "icon", "container")
     * @param visible:Boolean 是否可见
     */
    public static function setVisibility(target:String, visible:Boolean):Void {
        var element:MovieClip = getElementByTarget(target);
        if (element) {
            element._visible = visible;
        }
    }

    /**
     * 设置元素位置
     * @param target:String 目标标识
     * @param x:Number X坐标 (可选)
     * @param y:Number Y坐标 (可选)
     */
    public static function setPosition(target:String, x:Number, y:Number):Void {
        var element:MovieClip = getElementByTarget(target);
        if (element) {
            if (!isNaN(x)) element._x = x;
            if (!isNaN(y)) element._y = y;
        }
    }

    /**
     * 获取文本高度
     * @param target:String 目标标识 ("main", "intro")
     * @return Number 文本高度
     */
    public static function getTextHeight(target:String):Number {
        var textBox:MovieClip = getTextBoxByTarget(target);
        return textBox ? textBox.textHeight : 0;
    }

    /**
     * 设置元素尺寸
     * @param target:String 目标标识
     * @param width:Number 宽度 (可选)
     * @param height:Number 高度 (可选)
     */
    public static function setSize(target:String, width:Number, height:Number):Void {
        var element:MovieClip = getElementByTarget(target);
        if (element) {
            if (!isNaN(width)) element._width = width;
            if (!isNaN(height)) element._height = height;
        }
    }

    // ══════════════════════════════════════════════════════════════
    // 批量操作接口
    // ══════════════════════════════════════════════════════════════

    /**
     * 隐藏所有注释元素
     */
    public static function hideAllElements():Void {
        setVisibility("container", false);
        setVisibility("main", false);
        setVisibility("mainBg", false);
        setVisibility("intro", false);
        setVisibility("introBg", false);
        setVisibility("icon", false);
    }

    /**
     * 清理所有文本内容
     */
    public static function clearAllContent():Void {
        setTextContent("main", "");
        setTextContent("intro", "");
    }

    /**
     * 重置主要元素位置
     */
    public static function resetMainPositions():Void {
        setPosition("main", NaN, 0);
        setPosition("mainBg", NaN, 0);
    }

    /**
     * 显示主框体元素
     */
    public static function showMainElements():Void {
        setVisibility("main", true);
        setVisibility("mainBg", true);
    }

    /**
     * 显示简介框体元素
     */
    public static function showIntroElements():Void {
        setVisibility("intro", true);
        setVisibility("introBg", true);
        setVisibility("icon", true);
    }

    /**
     * 将容器根据背景元素回弹到屏幕可视区内
     * @param bg:MovieClip 作为边界参考的背景元素
     * @param padding:Number 距离屏幕边缘的内边距（默认8像素）
     */
    public static function clampContainerByBg(bg:MovieClip, padding:Number):Void {
        var container:MovieClip = getTooltipContainer(); // _root.注释框
        var m:Number = isNaN(padding) ? 8 : padding;

        // 以"某个背景"作为实际可视边界（单栏=简介背景；双栏=主背景）
        var left:Number   = container._x + bg._x;
        var right:Number  = left + bg._width;
        var top:Number    = container._y + bg._y;
        var bottom:Number = top + bg._height;

        var stageW:Number = Stage.width;
        var stageH:Number = Stage.height;

        var dx:Number = 0;
        var dy:Number = 0;

        if (right  > stageW - m) dx -= (right  - (stageW - m));
        if (left   < m)          dx += (m - left);
        if (bottom > stageH - m) dy -= (bottom - (stageH - m));
        if (top    < m)          dy += (m - top);

        if (dx != 0) container._x += dx;
        if (dy != 0) container._y += dy;
    }

    /**
     * 确保图标层级在简介背景之上
     *
     * 检查图标定位器的深度，如果低于或等于简介背景的深度，
     * 则将图标定位器移动到简介背景上方一层。
     *
     * @param depthIncrement:Number 深度增量（默认为 1）
     */
    public static function ensureIconAboveIntroBg(depthIncrement:Number):Void {
        var icon:MovieClip = getIconTarget();
        var introBg:MovieClip = getIntroBackground();

        if (!icon || !introBg) return; // 安全检查

        var increment:Number = isNaN(depthIncrement) ? 1 : depthIncrement;
        var iconDepth:Number = icon.getDepth();
        var bgDepth:Number = introBg.getDepth();

        if (iconDepth <= bgDepth) {
            icon.swapDepths(bgDepth + increment);
        }
    }

    // ══════════════════════════════════════════════════════════════
    // 私有辅助方法
    // ══════════════════════════════════════════════════════════════

    /**
     * 根据目标标识获取文本框
     */
    private static function getTextBoxByTarget(target:String):MovieClip {
        switch (target) {
            case "main": return getMainTextBox();
            case "intro": return getIntroTextBox();
            default: return null;
        }
    }

    /**
     * 根据目标标识获取UI元素
     */
    private static function getElementByTarget(target:String):MovieClip {
        switch (target) {
            case "main": return getMainTextBox();
            case "mainBg": return getMainBackground();
            case "intro": return getIntroTextBox();
            case "introBg": return getIntroBackground();
            case "icon": return getIconTarget();
            case "container": return getTooltipContainer();
            default: return null;
        }
    }
}