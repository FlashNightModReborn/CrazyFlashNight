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
    // 文本宽度真实测量
    // ══════════════════════════════════════════════════════════════

    /**
     * 利用实际 TextField 精确测量 HTML 内容中最长行的像素宽度。
     *
     * 原理：临时将 wordWrap 切为 false 并把字段展开至 9999px，
     * 让 Flash 在无换行约束下完成内部排版，再读取 textWidth。
     * 整个过程在同一 AS2 帧内同步完成，Flash 不会中间渲染，无视觉闪烁。
     *
     * @param htmlContent  待测量的 HTML 内容
     * @param useIntroBox  true = 简介文本框；false = 主文本框
     * @return 最长行像素宽度（含 TextField 4px 内边距），
     *         TextField 不可用时返回 0（调用方应回退到评分估算）
     */
    public static function measureTextLineWidth(htmlContent:String, useIntroBox:Boolean):Number {
        if (htmlContent == null || htmlContent == undefined || htmlContent == "") return 0;

        var tf:MovieClip = useIntroBox ? getIntroTextBox() : getMainTextBox();
        if (tf == null) return 0;

        // 保存现有状态
        var savedWordWrap:Boolean = tf.wordWrap;
        var savedWidth:Number    = tf._width;
        var savedHtml:String     = tf.htmlText;

        // 临时展开：禁止换行 + 足够宽的容器，消除字段宽度对 textWidth 的干扰
        tf.wordWrap = false;
        tf._width   = 9999;
        tf.htmlText = htmlContent;

        // textWidth = 内容自然宽度（不含内边距）；+4 补偿 TextField 左右各 2px 内边距
        var result:Number = tf.textWidth + 4;

        // 恢复原状态
        tf.wordWrap  = savedWordWrap;
        tf._width    = savedWidth;
        tf.htmlText  = savedHtml;

        return result;
    }

    // ══════════════════════════════════════════════════════════════
    // 行数测量（高度约束用）
    // ══════════════════════════════════════════════════════════════

    private static var _calibrated:Boolean = false;
    private static var _h1:Number = 0;       // 主文本框单行 textHeight 基准
    private static var _lineGap:Number = 15; // 主文本框行间距（h2-h1）

    // R3: 简介文本框专用校准参数（字体/leading 可能与主文本框不同）
    private static var _introCal:Boolean = false;
    private static var _introH1:Number = 0;
    private static var _introLineGap:Number = 15;

    /**
     * 运行时校准行高参数。
     * 使用主文本框测量单行/双行 textHeight，提取 h1 和 lineGap。
     * 首次调用 measureRenderedLines 时自动触发（lazy init）。
     */
    public static function calibrateLineMetrics():Void {
        var tf:MovieClip = getMainTextBox();
        if (tf == null) return;

        var savedWordWrap:Boolean = tf.wordWrap;
        var savedWidth:Number = tf._width;
        var savedHtml:String = tf.htmlText;

        tf.wordWrap = false;
        tf._width = 9999;
        tf.htmlText = "A";
        _h1 = tf.textHeight;
        tf.htmlText = "A<BR>B";
        _lineGap = tf.textHeight - _h1;

        tf.wordWrap = savedWordWrap;
        tf._width = savedWidth;
        tf.htmlText = savedHtml;

        _calibrated = true;
    }

    /**
     * 运行时校准简介文本框行高参数。
     * 与 calibrateLineMetrics 对称，使用简介文本框测量。
     */
    public static function calibrateIntroLineMetrics():Void {
        var tf:MovieClip = getIntroTextBox();
        if (tf == null) return;

        var savedWordWrap:Boolean = tf.wordWrap;
        var savedWidth:Number = tf._width;
        var savedHtml:String = tf.htmlText;

        tf.wordWrap = false;
        tf._width = 9999;
        tf.htmlText = "A";
        _introH1 = tf.textHeight;
        tf.htmlText = "A<BR>B";
        _introLineGap = tf.textHeight - _introH1;

        tf.wordWrap = savedWordWrap;
        tf._width = savedWidth;
        tf.htmlText = savedHtml;

        _introCal = true;
    }

    /**
     * 测量当前 htmlText 在指定宽度下的渲染行数。
     *
     * 前置条件：tf.htmlText 已由调用方赋值。
     * 本方法只修改 tf._width，不重新赋值 htmlText（避免 DOM thrashing）。
     *
     * 公式：round((textHeight - h1) / lineGap) + 1
     *   1行: (h1-h1)/gap+1 = 1
     *   N行: ((N-1)*gap)/gap+1 = N
     *
     * @param targetWidth 目标 TextField 宽度
     * @param useIntroBox true=简介文本框，false=主文本框
     * @return 渲染行数，TextField 不可用或校准失败返回 -1
     */
    public static function measureRenderedLines(targetWidth:Number, useIntroBox:Boolean):Number {
        if (useIntroBox) {
            // R3: 简介文本框使用独立校准参数
            if (!_introCal) calibrateIntroLineMetrics();
            if (_introLineGap <= 0) return -1;
            var itf:MovieClip = getIntroTextBox();
            if (itf == null) return -1;
            itf._width = targetWidth;
            return Math.round((itf.textHeight - _introH1) / _introLineGap) + 1;
        }
        if (!_calibrated) calibrateLineMetrics();
        if (_lineGap <= 0) return -1;
        var tf:MovieClip = getMainTextBox();
        if (tf == null) return -1;
        tf._width = targetWidth;
        return Math.round((tf.textHeight - _h1) / _lineGap) + 1;
    }

    // ══════════════════════════════════════════════════════════════
    // _root 全局数据网关（收口 _root 直接访问）
    // ══════════════════════════════════════════════════════════════

    /** 鼠标 X 坐标 */
    public static function getMouseX():Number { return _root._xmouse; }

    /** 鼠标 Y 坐标 */
    public static function getMouseY():Number { return _root._ymouse; }

    /**
     * 获取敌人显示名（替代直接访问 _root.敌人属性表）
     * @param enemyType 敌人类型标识
     * @return 显示名称，不存在时回退到 enemyType
     */
    public static function getEnemyDisplayName(enemyType:String):String {
        if (!_root.敌人属性表 || !_root.敌人属性表[enemyType]) return enemyType;
        var props:Object = _root.敌人属性表[enemyType];
        return props.displayname ? props.displayname : enemyType;
    }

    /**
     * 调试日志输出（替代直接访问 _root.服务器）
     * @param msg 日志消息
     */
    public static function debugLog(msg:String):Void {
        if (_root.服务器 && _root.服务器.发布服务器消息) {
            _root.服务器.发布服务器消息(msg);
        }
    }

    /** 重置校准状态（测试用，同时重置主框+简介框） */
    public static function resetCalibration():Void {
        _calibrated = false;
        _h1 = 0;
        _lineGap = 15;
        _introCal = false;
        _introH1 = 0;
        _introLineGap = 15;
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