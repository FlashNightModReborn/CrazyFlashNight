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
  public static var COL_ENHANCE:String = "#88FF88";  // 增幅显示颜色（淡绿色）

  public static var SUF_PERCENT:String = "%";
  public static var SUF_HP:String = "HP";
  public static var SUF_MP:String = "MP";
  public static var SUF_BLOOD:String = "%血量";
  public static var SUF_SECOND:String = "秒";
  public static var SUF_FIRE_RATE:String = "发/秒";
  public static var SUF_KG:String = "kg";
  public static var SUF_DISTANCE:String = "距离";
  public static var COL_SILENCE:String = "#9999FF";

  // 通用文本常量
  public static var TXT_NONE:String = "无";  // 表示空值/无属性

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

  // 各个属性对应的名称
  public static var PROPERTY_DICT:Object = {
    // 必要参数 等级与重量
    level: "等级限制",
    weight: "重量",
    // 防御，hp，mp
    defence: "防御",
    hp: "<FONT COLOR='" + COL_HP + "'>HP</FONT>",
    mp: "<FONT COLOR='" + COL_MP + "'>MP</FONT>",
    // 武器威力，实际描述随武器类型而改变
    power: "威力",
    // 5种伤害加成
    damage: "伤害加成",
    punch: "空手加成",
    knifepower: "冷兵器加成",
    gunpower: "枪械加成",
    force: "内力加成",
    // 枪械数据
    clipname: "使用弹夹",
    capacity: "弹夹容量",
    diffusion: "子弹散射度",
    velocity: "出膛速度",
    bulletsize: "纵向攻击范围",
    impact: "冲击力",
    silence: "<FONT COLOR='" + COL_SILENCE + "'>消音效果</FONT>",
    // 额外加成
    accuracy: "命中加成",
    evasion: "挡拆加成",
    toughness: "韧性加成",
    lazymiss: "高危回避",
    poison: "<FONT COLOR='" + COL_POISON + "'>剧毒性</FONT>",
    vampirism: "<FONT COLOR='" + COL_VAMP + "'>吸血</FONT>",
    rout: "<FONT COLOR='" + COL_ROUT + "'>击溃</FONT>",
    slay: "斩杀线",
    //
    magictype: "伤害属性",
    // 根层属性（定义在item而非item.data中）
    actiontype: "动作类型"
  };

  // 各个属性的显示优先级
  public static var PROPERTY_PRIORITIES:Object = {
    // 先显示等级限制，重量，威力
    level: 0,
    weight: 1,
    power: 2,

    // 显示枪械数据
    clipname: 11,
    capacity: 12,
    diffusion: 13,
    velocity: 14,
    bulletsize: 15,
    impact: 16,
    silence: 17,

    // 5种伤害加成
    force: 21,
    damage: 22,
    punch: 23,
    knifepower: 24,
    gunpower: 25,

    // 额外加成
    accuracy: 31,
    evasion: 32,
    toughness: 33,
    lazymiss: 34,
    
    poison: 41,
    vampirism: 42,
    rout: 43,
    slay: 44,
    //
    magictype: 51,

    // 根层属性
    actiontype: 91,

    // 最后显示防御，hp，mp
    defence: 101,
    hp: 102,
    mp: 103
  };
}