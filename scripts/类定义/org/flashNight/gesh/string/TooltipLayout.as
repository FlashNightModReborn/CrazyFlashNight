import org.flashNight.gesh.string.TooltipConstants;

/**
 * Tooltip布局管理类
 * 负责处理注释框的宽度估算、简介布局计算和位置定位
 */
class org.flashNight.gesh.string.TooltipLayout {

  /**
   * 估算文本宽度：基于字符数的粗估算法
   * @param html:String 要估算的HTML文本
   * @param minW:Number 最小宽度（可选，默认使用常量）
   * @param maxW:Number 最大宽度（可选，默认使用常量）
   * @return Number 估算出的宽度
   */
  public static function estimateWidth(html:String, minW:Number, maxW:Number):Number {
    if (minW === undefined) minW = TooltipConstants.MIN_W;
    if (maxW === undefined) maxW = TooltipConstants.MAX_W;
    
    var 字数:Number = html.length;
    var 估算宽度:Number = 字数 * TooltipConstants.CHAR_AVG_WIDTH;
    return Math.max(minW, Math.min(估算宽度, maxW));
  }

  /**
   * 应用简介布局：处理武器/防具 vs 其他物品的布局差异
   * @param itemType:String 物品类型
   * @param target:MovieClip 目标MovieClip
   * @param background:MovieClip 背景MovieClip
   * @param text:MovieClip 文本MovieClip
   * @return Object 包含width和heightOffset的布局信息对象
   */
  public static function applyIntroLayout(itemType:String, target:MovieClip, background:MovieClip, text:MovieClip):Object {
    var stringWidth:Number;
    var backgroundHeightOffset:Number;
    
    switch(itemType) {
      case "武器":
      case "防具":
        stringWidth = TooltipConstants.BASE_NUM;
        background._width = TooltipConstants.BASE_NUM;
        background._x = -TooltipConstants.BASE_NUM;
        target._x = -TooltipConstants.BASE_NUM + TooltipConstants.BASE_OFFSET;
        target._xscale = target._yscale = TooltipConstants.BASE_SCALE;
        text._x = -TooltipConstants.BASE_NUM;
        text._y = 210;
        backgroundHeightOffset = TooltipConstants.BASE_NUM + TooltipConstants.BG_HEIGHT_OFFSET;
        break;
      default:
        var scaledWidth:Number = TooltipConstants.BASE_NUM * TooltipConstants.RATE;
        stringWidth = scaledWidth;
        background._width = scaledWidth;
        background._x = -scaledWidth;
        target._x = -scaledWidth + TooltipConstants.BASE_OFFSET * TooltipConstants.RATE;
        target._xscale = target._yscale = TooltipConstants.BASE_SCALE * TooltipConstants.RATE;
        text._x = -scaledWidth;
        text._y = 10 - text._x;
        backgroundHeightOffset = TooltipConstants.BG_HEIGHT_OFFSET + TooltipConstants.RATE * TooltipConstants.BASE_NUM;
        break;
    }
    
    return { width: stringWidth, heightOffset: backgroundHeightOffset };
  }

  /**
   * 定位注释框：处理边界检测和左右背景对齐
   * @param tips:MovieClip 注释框容器
   * @param background:MovieClip 背景MovieClip
   * @param mouseX:Number 鼠标X坐标
   * @param mouseY:Number 鼠标Y坐标
   */
  public static function positionTooltip(tips:MovieClip, background:MovieClip, mouseX:Number, mouseY:Number):Void {
    var 简介背景:MovieClip = tips.简介背景;
    var 右背景:MovieClip = tips.背景;
    
    var isAbbr:Boolean = !简介背景._visible;
    
    if (isAbbr) {
      // 简介背景隐藏时的定位逻辑
      tips._x = Math.min(Stage.width - background._width, Math.max(0, mouseX - background._width));
      tips._y = Math.min(Stage.height - background._height, Math.max(0, mouseY - background._height - 20));
    } else {
      if (右背景._visible) {
        // 计算鼠标的理想定位点（将注释框的右边缘对齐到鼠标指针）
        var desiredX:Number = mouseX - 右背景._width;
        
        // 计算允许的最小X值和最大X值
        var minX:Number = 简介背景._width;
        var maxX:Number = Stage.width - 右背景._width;
        
        // Y轴定位逻辑
        tips._y = Math.min(Stage.height - tips._height, Math.max(0, mouseY - tips._height - 20));
        var rightBottomHeight:Number = tips._y + 右背景._height;
        
        var offset:Number = mouseY - rightBottomHeight - 20;
        if (offset > 0) {
          tips.文本框._y = offset;
          tips.背景._y = offset;
        } else {
          var icon:MovieClip = tips.物品图标定位;
          右背景._height = Math.max(tips.文本框.textHeight, icon._height) + 10;
        }
        
        tips._x = Math.max(minX, Math.min(desiredX, maxX));
      } else {
        // 只有左背景可见时
        tips._x = Math.min(Stage.width - 简介背景._width, Math.max(0, mouseX - 简介背景._width)) + 简介背景._width;
        tips._y = Math.min(Stage.height - 简介背景._height, Math.max(0, mouseY - 简介背景._height - 20));
        
        // 调整左背景高度以适配内容
        简介背景._height = tips.简介文本框.textHeight + 10;
      }
    }
  }
}