/**
 * EquipmentStatProjector 的只读展示词汇与排序叶子。
 * Tooltip 内容规则已移至 launcher/tooltip-engine；不要在此继续扩展注释引擎。
 * 保留原值以维持装备调制 before/after 数值行语义。
 */
class org.flashNight.gesh.tooltip.TooltipConstants {
  public static var COL_VAMP:String = "#bb00aa";
  public static var COL_SILENCE:String = "#9999FF";
  public static var COL_ROUT:String = "#FF3333";
  public static var COL_POISON:String = "#66dd00";
  public static var COL_MP:String = "#00FFFF";
  public static var COL_HP:String = "#00FF00";
  public static var SUF_FIRE_RATE:String = "发/秒";
  public static var TXT_ENERGY:String = "能量";
  public static var TXT_BASE:String = "基础";
  public static var LBL_FIRE_RATE:String = "射速";
  public static var LBL_SHARPNESS:String = "锋利度";
  public static var LBL_BULLET_POWER:String = "子弹威力";

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
    singleshoot: "射击模式",
    reloadType: "装填形式",
    capacity: "弹夹容量",
    interval: "射击间隔",
    diffusion: "子弹散射度",
    velocity: "出膛速度",
    bulletsize: "纵向攻击范围",
    impact: "冲击力",
    split: "弹丸数量",
    reloadPenalty: "换弹延迟",
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

  public static var PROPERTY_PRIORITIES:Object = {
    // 先显示等级限制，重量，威力
    level: 0,
    weight: 1,
    power: 2,

    // 显示枪械数据
    singleshoot: 10,
    reloadType: 10.5,
    clipname: 11,
    capacity: 12,
    interval: 13,
    diffusion: 14,
    velocity: 15,
    bulletsize: 16,
    impact: 17,
    split: 17.5,
    reloadPenalty: 18,
    silence: 19,

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
