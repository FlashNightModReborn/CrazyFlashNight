/**
 * TooltipConstants - 注释系统常量定义
 *
 * 职责：
 * - 集中管理所有颜色、后缀、标签、提示文本常量
 * - 避免硬编码字符串散布在代码中
 * - 便于国际化和统一维护
 */
class org.flashNight.gesh.tooltip.TooltipConstants {
  // ══════════════════════════════════════════════════════════════
  // 颜色常量 (Colors)
  // ══════════════════════════════════════════════════════════════
  public static var COL_HL:String = "#FFCC00";           // 高亮色（金色）
  public static var COL_HP:String = "#00FF00";           // 生命值（绿色）
  public static var COL_MP:String = "#00FFFF";           // 魔法值（青色）
  public static var COL_CRIT:String = "#DD4455";         // 暴击（红色）
  public static var COL_POISON:String = "#66dd00";       // 毒性（黄绿色）
  public static var COL_VAMP:String = "#bb00aa";         // 吸血（紫色）
  public static var COL_ROUT:String = "#FF3333";         // 击溃（红色）
  public static var COL_DMG:String = "#0099FF";          // 伤害（蓝色）
  public static var COL_BREAK_LIGHT:String = "#66bcf5";  // 破击-附加（浅蓝）
  public static var COL_BREAK_MAIN:String = "#CC6600";   // 破击-主类型（橙色）
  public static var COL_INFO:String = "#FFCC00";         // 信息提示（金色）
  public static var COL_ENHANCE:String = "#88FF88";      // 增幅显示（淡绿色）
  public static var COL_SILENCE:String = "#9999FF";      // 消音效果（淡紫色）
  public static var COL_MULTIPLIER:String = "#FF6600";   // 独立乘区（橙色）
  public static var COL_MULTIPLIER_HINT:String = "#FF9944"; // 独立乘区提示（浅橙）
  public static var COL_USE_SWITCH:String = "#FFCC66";   // useSwitch条件效果（淡金）
  public static var COL_TAG_SWITCH:String = "#88CCFF";   // tagSwitch结构加成（淡蓝）
  public static var COL_COND_PROVIDE:String = "#99FF99"; // 条件性provideTags（淡绿）

  // ══════════════════════════════════════════════════════════════
  // 获取方式相关颜色 (Obtain Methods Colors)
  // ══════════════════════════════════════════════════════════════
  public static var COL_CRAFT:String = "#99CCFF";        // 合成来源（淡蓝）
  public static var COL_SHOP:String = "#99FF99";         // 商店来源（淡绿）
  public static var COL_KSHOP:String = "#FFCC99";        // K点商店（淡橙）
  public static var COL_DROP_STAGE:String = "#FFFF99";   // 关卡掉落（淡黄）
  public static var COL_DROP_ENEMY:String = "#FF99CC";   // 敌人掉落（淡粉）
  public static var COL_QUEST:String = "#CC99FF";        // 任务奖励（淡紫）

  // ══════════════════════════════════════════════════════════════
  // 后缀常量 (Suffixes)
  // ══════════════════════════════════════════════════════════════
  public static var SUF_PERCENT:String = "%";
  public static var SUF_HP:String = "HP";
  public static var SUF_MP:String = "MP";
  public static var SUF_BLOOD:String = "%血量";
  public static var SUF_SECOND:String = "秒";
  public static var SUF_FIRE_RATE:String = "发/秒";
  public static var SUF_KG:String = "kg";
  public static var SUF_DISTANCE:String = "距离";
  public static var SUF_RESISTANCE:String = "抗性";

  // ══════════════════════════════════════════════════════════════
  // 通用文本常量 (General Text)
  // ══════════════════════════════════════════════════════════════
  public static var TXT_NONE:String = "无";              // 表示空值/无属性
  public static var TXT_ENERGY:String = "能量";          // 能量（魔法伤害的别名）
  public static var TXT_MAGIC:String = "魔法";           // 魔法
  public static var TXT_BREAK:String = "破击";           // 破击
  public static var TXT_BASE:String = "基础";            // 基础（抗性类型）
  public static var TXT_OVERRIDE:String = "覆盖";        // 覆盖操作
  public static var TXT_MERGE:String = "合并";           // 合并操作
  public static var TXT_GROUP:String = "群体";           // 群体效果

  // ══════════════════════════════════════════════════════════════
  // 标签常量 - 方括号标签 (Labels - Bracketed)
  // ══════════════════════════════════════════════════════════════
  public static var LBL_SKILL_BONUS:String = "【技能加成】";
  public static var LBL_ACTIVE_SKILL:String = "【主动战技】";
  public static var LBL_SKILL_INFO:String = "【战技信息】";
  public static var LBL_AFFIX_INFO:String = "【词条信息】";
  public static var LBL_MOD_INFO:String = "【配件信息】";
  public static var LBL_USE_SWITCH_EFFECT:String = "【按装备类型追加效果】";
  public static var LBL_TAG_SWITCH_EFFECT:String = "【按结构标签追加效果】";
  public static var LBL_COND_PROVIDE_TAGS:String = "条件性提供结构";

  // ══════════════════════════════════════════════════════════════
  // 标签常量 - 操作类型标签 (Labels - Operation Tags)
  // ══════════════════════════════════════════════════════════════
  public static var TAG_OVERRIDE:String = "[覆盖]";
  public static var TAG_MERGE:String = "[合并]";
  public static var TAG_MULTIPLIER_ZONE:String = "[独立乘区]";

  // ══════════════════════════════════════════════════════════════
  // 属性标签常量 (Property Labels)
  // ══════════════════════════════════════════════════════════════
  public static var LBL_CLIP_NAME:String = "使用弹夹";
  public static var LBL_BULLET_TYPE:String = "子弹类型";
  public static var LBL_CAPACITY:String = "弹夹容量";
  public static var LBL_BURST_COUNT:String = "点射弹数";
  public static var LBL_PELLET_COUNT:String = "弹丸数量";
  public static var LBL_FIRE_RATE:String = "射速";
  public static var LBL_IMPACT:String = "冲击力";
  public static var LBL_BULLET_SIZE:String = "纵向攻击范围";
  public static var LBL_FIRE_MODE:String = "射击模式";
  public static var TIP_FIRE_MODE_AUTO:String = "全自动";
  public static var TIP_FIRE_MODE_SEMI:String = "半自动";
  public static var LBL_POWER:String = "威力";
  public static var LBL_SHARPNESS:String = "锋利度";
  public static var LBL_BULLET_POWER:String = "子弹威力";
  public static var LBL_ACTION:String = "动作";
  public static var LBL_ACTION_TYPE:String = "动作类型";
  public static var LBL_WEAPON_TYPE:String = "武器类型";
  public static var LBL_UPGRADE_LEVEL:String = "强化等级";
  public static var LBL_QUANTITY:String = "数量";
  public static var LBL_SYNTHESIS:String = "合成材料";
  public static var LBL_COOLDOWN:String = "冷却";
  public static var LBL_COST:String = "消耗";
  public static var LBL_CLEAN:String = "净化度";
  public static var LBL_POISON:String = "剧毒性";
  public static var LBL_INSTALLED_MODS:String = "已安装";
  public static var LBL_MOD_COUNT_SUFFIX:String = "个配件";
  public static var LBL_SLAY_SHORT:String = "斩杀";

  // ══════════════════════════════════════════════════════════════
  // 配件/插件相关标签 (Mod Labels)
  // ══════════════════════════════════════════════════════════════
  public static var LBL_MOD_USE_TYPE:String = "适用装备类型";
  public static var LBL_MOD_SLOT:String = "插件位置";
  public static var LBL_MOD_WEAPON_TYPE:String = "适用武器子类";
  public static var LBL_MOD_EXCLUDE_WEAPON_TYPE:String = "排除武器子类";
  public static var LBL_PROVIDE_TAGS:String = "提供结构";
  public static var LBL_REQUIRE_TAGS:String = "前置需求";
  public static var LBL_INHERENT_TAGS:String = "固有结构";
  public static var LBL_BLOCKED_TAGS:String = "禁止挂点";

  // ══════════════════════════════════════════════════════════════
  // 获取方式标签 (Obtain Methods Labels)
  // ══════════════════════════════════════════════════════════════
  public static var LBL_OBTAIN_METHODS:String = "【获取方式】";
  public static var TIP_OBTAIN_CRAFT:String = "合成：";
  public static var TIP_OBTAIN_SHOP:String = "商店：";
  public static var TIP_OBTAIN_KSHOP:String = "K点商城：";
  public static var TIP_OBTAIN_STAGE:String = "关卡：";
  public static var TIP_OBTAIN_ENEMY:String = "掉落：";
  public static var TIP_OBTAIN_QUEST:String = "任务：";

  // ══════════════════════════════════════════════════════════════
  // 伤害类型标签 (Damage Type Labels)
  // ══════════════════════════════════════════════════════════════
  public static var LBL_DAMAGE_ATTR:String = "伤害属性";
  public static var LBL_EXTRA_DAMAGE:String = "附加伤害";
  public static var LBL_BREAK_TYPE:String = "破击类型";
  public static var LBL_DAMAGE_TYPE:String = "伤害类型";

  // ══════════════════════════════════════════════════════════════
  // 消音效果相关 (Silence Effect Labels)
  // ══════════════════════════════════════════════════════════════
  public static var LBL_SILENCE_EFFECT:String = "消音效果";
  public static var LBL_SILENCE_DISTANCE:String = "距离 >";
  public static var TIP_SILENCE_PERCENT:String = "概率消音成功";
  public static var TIP_SILENCE_PERCENT_DESC:String = "攻击时有";
  public static var TIP_SILENCE_PERCENT_DESC2:String = "几率不触发敌人仇恨";
  public static var TIP_SILENCE_DIST_DESC:String = "攻击超过";
  public static var TIP_SILENCE_DIST_DESC2:String = "距离的目标不触发仇恨";
  public static var TIP_SILENCE_SHORT:String = "消音";
  public static var TIP_SILENCE_ORIG_DIST:String = "原距离";
  public static var TIP_SILENCE_ORIG_PERCENT:String = "原概率";
  public static var TIP_SILENCE_ORIG:String = "原";

  // ══════════════════════════════════════════════════════════════
  // 暴击效果相关 (Critical Hit Labels)
  // ══════════════════════════════════════════════════════════════
  public static var LBL_CRIT:String = "暴击";
  public static var TIP_CRIT_CHANCE:String = "概率造成1.5倍伤害";
  public static var TIP_CRIT_FULL_HP:String = "满血暴击";
  public static var TIP_CRIT_FULL_HP_DESC:String = "对满血敌人造成1.5倍伤害";

  // ══════════════════════════════════════════════════════════════
  // 提示/说明文本 (Tips)
  // ══════════════════════════════════════════════════════════════
  public static var TIP_INFO_LOCATION:String = "详细信息可在物品栏的情报界面查阅";
  public static var TIP_ALLY_EFFECT:String = "全体友方有效";
  public static var TIP_NO_BONUS_DATA:String = "无加成数据";
  public static var TIP_EQUIP_BONUS_PREFIX:String = "对装备";
  public static var TIP_EQUIP_BONUS_SUFFIX:String = "的加成";
  public static var TIP_SHARPNESS_BONUS:String = "锋利度增益";
  public static var TIP_USE:String = "使用";
  public static var TIP_ENJOY:String = "享受";
  public static var TIP_CAP_UPPER:String = "增益上限";
  public static var TIP_CAP_LOWER:String = "减益下限";
  public static var TIP_FOR:String = "对";
  public static var TIP_ETC:String = "等";
  public static var TIP_OBTAIN_MORE:String = "个";  // 用于 "等X个" 的后缀
  public static var TIP_WHEN_HAS:String = "当存在";   // tagSwitch条件前缀
  public static var TIP_TAG_SUFFIX:String = "时";    // tagSwitch条件后缀

  // ══════════════════════════════════════════════════════════════
  // 药剂系统文案 (Drug Tooltip Labels)
  // ══════════════════════════════════════════════════════════════
  public static var LBL_DRUG_REGEN:String = "缓释";             // 缓释恢复前缀
  public static var LBL_DRUG_BUFF:String = "Buff";              // Buff效果前缀
  public static var LBL_DRUG_GRANT:String = "获得";             // 获得物品前缀
  public static var LBL_DRUG_GRANT_HIDDEN:String = "可能获得额外物品";  // 隐藏获得物品
  public static var LBL_DRUG_NO_ALCHEMY:String = "(无炼金)";    // 无炼金加成标记
  public static var LBL_DRUG_REGEN_OVERRIDE:String = "（覆盖同类缓释）"; // 缓释叠加提示
  public static var TIP_DRUG_SECOND:String = "秒";              // 药剂时间单位
  public static var TIP_DRUG_PER_TICK:String = "/次";           // 每次恢复后缀
  public static var TIP_DRUG_INTERVAL:String = "，每";          // 间隔前缀
  public static var TIP_DRUG_RECOVER:String = "秒恢复";         // 恢复后缀
  public static var TIP_DRUG_CHANCE:String = "概率";            // 概率后缀

  // ══════════════════════════════════════════════════════════════
  // 获取方式截断阈值 (Obtain Methods Truncation Limits)
  // ══════════════════════════════════════════════════════════════
  public static var OBTAIN_MAX_CRAFTS:Number = 3;    // 合成来源最多显示条数
  public static var OBTAIN_MAX_SHOPS:Number = 5;     // NPC商店最多显示个数
  public static var OBTAIN_MAX_KSHOPS:Number = 2;    // K点商店最多显示条数
  public static var OBTAIN_MAX_STAGES:Number = 4;    // 关卡掉落最多显示个数
  public static var OBTAIN_MAX_ENEMIES:Number = 4;   // 敌人掉落最多显示个数
  public static var OBTAIN_MAX_QUESTS:Number = 3;    // 任务奖励最多显示条数

  // ══════════════════════════════════════════════════════════════
  // 框体/布局相关 (Frame/Layout)
  // ══════════════════════════════════════════════════════════════
  public static var FRAME_INTRO:String = "简介";
  public static var FRAME_EQUIPMENT:String = "装备";
  public static var ICON_PREFIX:String = "图标-";
  public static var SUFFIX_TEXTBOX:String = "文本框";
  public static var SUFFIX_BG:String = "背景";

  // ══════════════════════════════════════════════════════════════
  // 布局数值常量 (Layout Numbers)
  // ══════════════════════════════════════════════════════════════
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

  // ══════════════════════════════════════════════════════════════
  // 属性名称字典 (Property Dictionary)
  // ══════════════════════════════════════════════════════════════
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
    capacity: "弹夹容量",
    interval: "射击间隔",
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

  // ══════════════════════════════════════════════════════════════
  // 属性优先级字典 (Property Priorities)
  // ══════════════════════════════════════════════════════════════
  public static var PROPERTY_PRIORITIES:Object = {
    // 先显示等级限制，重量，威力
    level: 0,
    weight: 1,
    power: 2,

    // 显示枪械数据
    singleshoot: 10,
    clipname: 11,
    capacity: 12,
    interval: 13,
    diffusion: 14,
    velocity: 15,
    bulletsize: 16,
    impact: 17,
    silence: 18,

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
