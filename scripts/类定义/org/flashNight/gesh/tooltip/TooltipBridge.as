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
class org.flashNight.gesh.tooltip.TooltipBridge {

    // ══════════════════════════════════════════════════════════════
    // UI元素访问 - 获取底层UI组件引用
    // ══════════════════════════════════════════════════════════════

    /**
     * 获取主文本框引用
     */
    public static function getMainTextBox():MovieClip {
        return _root.注释框.文本框;
    }

    /**
     * 获取主背景引用
     */
    public static function getMainBackground():MovieClip {
        return _root.注释框.背景;
    }

    /**
     * 获取简介文本框引用
     */
    public static function getIntroTextBox():MovieClip {
        return _root.注释框.简介文本框;
    }

    /**
     * 获取简介背景引用
     */
    public static function getIntroBackground():MovieClip {
        return _root.注释框.简介背景;
    }

    /**
     * 获取图标定位器引用
     */
    public static function getIconTarget():MovieClip {
        return _root.注释框.物品图标定位;
    }

    /**
     * 获取注释容器引用
     */
    public static function getTooltipContainer():MovieClip {
        return _root.注释框;
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