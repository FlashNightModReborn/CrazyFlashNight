class org.flashNight.gesh.tooltip.TooltipConstants {
  public static var COL_HL:String = "#FFCC00";
  public static var COL_HP:String = "#00FF00";
  public static var COL_MP:String = "#00FFFF";
  public static var COL_CRIT:String = "#DD4455";
  public static var COL_POISON:String = "#66dd00";
  public static var COL_VAMP:String = "#bb00aa";
  public static var COL_ROUT:String = "#FF3333";
  public static var COL_DMG:String = "#0099FF";
  public static var COL_BREAK_LIGHT:String = "#66bcf5";
  public static var COL_BREAK_MAIN:String = "#CC6600";
  public static var COL_INFO:String = "#FFCC00";
  
  public static var SUF_PERCENT:String = "%";
  public static var SUF_HP:String = "HP";
  public static var SUF_MP:String = "MP";
  public static var SUF_BLOOD:String = "%血量";
  public static var SUF_SECOND:String = "秒";
  public static var SUF_FIRE_RATE:String = "发/秒";
  public static var SUF_KG:String = "kg";

  public static var BASE_NUM:Number = 200;
  public static var RATE:Number = 0.6;
  public static var BASE_SCALE:Number = 486.8;
  public static var BASE_OFFSET:Number = 7.5;
  public static var MIN_W:Number = 150;
  public static var MAX_W:Number = 500;
  public static var TEXT_PAD:Number = 10;
  public static var BG_HEIGHT_OFFSET:Number = 20;
  public static var SPLIT_THRESHOLD:Number = 96;

  public static var CHAR_CJK_WIDTH:Number = 8;
  public static var CHAR_LATIN_WIDTH:Number = 5;
  public static var CHAR_AVG_WIDTH:Number = 0.5;

  public static var OFFSET_X:Number = 0;
  public static var OFFSET_Y:Number = 0;

  // 布局位置常量
  public static var TEXT_Y_EQUIPMENT:Number = 210;        // 装备/武器/技能布局的文本Y位置
  public static var TEXT_Y_BASE:Number = 10;              // 默认布局的文本Y位置基数
  public static var MOUSE_OFFSET:Number = 20;             // 鼠标位置偏移量
  public static var HEIGHT_ADJUST:Number = 10;            // 高度调整偏移量
  
  // 图标相关常量
  public static var ICON_SCALE:Number = 150;              // 图标缩放比例
  public static var ICON_OFFSET:Number = 19;              // 图标位置偏移
  public static var DEPTH_INCREMENT:Number = 1;           // 层级增量

  // 智能显示策略常量
  public static var SMART_TOTAL_MULTIPLIER:Number = 2;    // 总长度阈值倍数
  public static var SMART_DESC_DIVISOR:Number = 2;        // 描述长度阈值除数
}