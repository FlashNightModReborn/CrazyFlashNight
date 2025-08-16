import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.string.TooltipFormatter;
import org.flashNight.gesh.string.TooltipConstants;
import org.flashNight.gesh.string.TooltipDataSelector;

/**
 * 注释文本构建器类
 * 包含所有文本拼接的纯函数，用于生成各种类型的注释内容
 * 1:1 复刻 _root.注释文本 的功能
 */
class org.flashNight.gesh.string.TooltipTextBuilder {

  // === 生成基础描述（1:1 复刻 _root.注释文本.生成基础描述） ===
  public static function buildBasicDescription(item:Object):Array {
    var a = [];
    if (item.description) a.push(item.description.split("\r\n").join("<BR>"), "<BR>");
    return a;
  }

  // === 生成剧情碎片提示（1:1 复刻 _root.注释文本.生成剧情碎片提示） ===
  public static function buildStoryTip(item:Object):Array {
    var a = [];
    if (item.use == "情报") a.push("<FONT COLOR='#FFCC00'>详细信息可在物品栏的情报界面查阅</FONT><BR>");
    return a;
  }

  // === 生成合成材料（1:1 复刻 _root.注释文本.生成合成材料） ===
  public static function buildSynthesisMaterials(item:Object):Array {
    var a = [];
    // 三段防护：对象存在 / materials 存在 / 返回数组存在
    if (item.synthesis != null && 
        _root.改装清单对象 && 
        _root.改装清单对象[item.synthesis] && 
        _root.改装清单对象[item.synthesis].materials) {
      var 表 = ItemUtil.getRequirementFromTask(_root.改装清单对象[item.synthesis].materials);
      if (表 && 表.length > 0) {
        a.push("合成材料：<BR>");
        for (var i=0; i<表.length; i++) {
          if (表[i] && 表[i].name) {
            a.push(ItemUtil.getItemData(表[i].name).displayname, "：", 表[i].value, "<BR>");
          }
        }
      }
    }
    return a;
  }

  // === 生成刀技乘数（1:1 复刻 _root.注释文本.生成刀技乘数） ===
  public static function buildBladeSkillMultipliers(item:Object):Array {
    var a = [];
    if (item.use === "刀") {
      var 列表 = [_root.技能函数.凶斩伤害乘数表, _root.技能函数.瞬步斩伤害乘数表,
                 _root.技能函数.龙斩刀伤乘数表, _root.技能函数.拔刀术伤害乘数表];
      var 名称 = ["凶斩","瞬步斩","龙斩","拔刀术"];
      for (var i=0; i<列表.length; i++) {
        var t = 列表[i][item.name];
        if (t > 1) a.push("<font color='#FFCC00'>【技能加成】</font>使用", 名称[i], "享受", String((t-1)*100), "%锋利度增益<BR>");
      }
    }
    return a;
  }

  // === 生成战技信息（1:1 复刻 _root.注释文本.生成战技信息） ===
  public static function buildSkillInfo(skill:Object):Array {
    var a = [];
    if (!skill) return a;
    if (skill.description) {
      a.push("<font color='#FFCC00'>【主动战技】</font>", skill.description, "<BR><font color='#FFCC00'>【战技信息】</font>");
      if (skill.information) {
        a.push(skill.information);
      } else {
        var cd = skill.cd/1000;
        a.push("冷却", cd, "秒");
        if (skill.hp && skill.hp != 0) a.push("，消耗", skill.hp, "HP");
        if (skill.mp && skill.mp != 0) a.push("，消耗", skill.mp, "MP");
        a.push("。");
      }
    } else {
      a.push(skill);
    }
    a.push("<BR>");
    return a;
  }

  // === 生成生命周期（1:1 复刻 _root.注释文本.生成生命周期） ===
  public static function buildLifecycleInfo(lc:Object):Array {
    var a = [];
    if (lc && lc.description) a.push("<font color='#FFCC00'>【词条信息】</font>", lc.description, "<BR>");
    return a;
  }

  // === 生成简介标题头（1:1 复刻 _root.注释文本.生成简介标题头） ===
  public static function buildIntroHeader(item:Object, value:Object, 强化等级:Number):Array {
    var a = [];
    a.push("<B>", (value.tier ? ("[" + value.tier + "]") : ""), item.displayname, "</B><BR>");
    a.push(item.type, "    ", item.use, "<BR>");
    if (item.type == "武器" || item.type == "防具") { a.push("等级限制：", item.level, "<BR>"); }
    a.push("$", item.price, "<BR>");
    if (item.weight != null && item.weight !== 0) a.push("重量：", item.weight, "kg<BR>");
    if (强化等级 > 1 && (item.type == "武器" || item.type == "防具")) {
      a.push("<FONT COLOR='#FFCC00'>强化等级：", 强化等级, "</FONT><BR>");
    } else {
      // 兼容多种形态：value 为数字 或 对象里带各种数量字段
      var 数量:Number = 0;
      if (typeof value == "number") {
        数量 = Number(value);
      } else if (value) {
        // 优先级：count > amount > num > stack > quantity
        var candidates = [value.count, value.amount, value.num, value.stack, value.quantity];
        for (var i = 0; i < candidates.length; i++) {
          var candidate = Number(candidates[i]);
          if (!isNaN(candidate) && candidate > 0) {
            数量 = candidate;
            break;
          }
        }
      }
      if (数量 > 1) a.push("数量：", 数量, "<BR>");
    }
    return a;
  }

  // === 生成装备属性块（1:1 复刻 _root.注释文本.生成装备属性块） ===
  public static function buildEquipmentStats(item:Object, tier:String, 等级:Number):Array {
    if (等级 == undefined || isNaN(等级) || 等级 < 1) 等级 = 1;
    var a = [];
    var d = TooltipDataSelector.getEquipmentData(item, tier);

    switch (item.use) {
      case "刀":
        a.push("锋利度：", d.power, "<FONT COLOR='#FFCC00'>(+", (_root.强化计算(d.power, 等级)-d.power), ")</FONT><BR>");
        break;
      case "手雷":
        a.push("等级限制：", item.level, "<BR>威力：", d.power, "<BR>");
        break;
      case "长枪":
      case "手枪":
        if (d.clipname) a.push("使用弹夹：", ItemUtil.getItemData(d.clipname).displayname, "<BR>");
        var bulletStr = (d.bulletrename ? d.bulletrename : d.bullet);
        if (bulletStr) a.push("子弹类型：", bulletStr, "<BR>");
        var notMuti = (d.bullet && d.bullet.indexOf("纵向") >= 0);
        
        // 数值字段统一防护：使用Number()转换 + isNaN()兜底
        var splitVal:Number = Number(d.split);
        if (isNaN(splitVal) || splitVal <= 1) splitVal = 1;
        
        var capacity:Number = Number(d.capacity);
        if (isNaN(capacity)) capacity = 0;
        
        var magazineCapacity = notMuti ? splitVal : 1;
        if (capacity > 0) a.push("弹夹容量：", (capacity * magazineCapacity), "<BR>");
        a.push("子弹威力：", d.power, "<FONT COLOR='#FFCC00'>(+", (_root.强化计算(d.power, 等级)-d.power), ")</FONT><BR>");
        if (splitVal > 1) a.push(notMuti ? "点射弹数：" : "弹丸数量：", splitVal, "<BR>");
        
        // interval和impact的防护：确保是有效数值且非零
        var interval:Number = Number(d.interval);
        if (!isNaN(interval) && interval > 0) {
          a.push("射速：", (Math.floor(10000 / interval) * 0.1 * magazineCapacity), "发/秒<BR>");
        }
        
        var impact:Number = Number(d.impact);
        if (!isNaN(impact) && impact > 0) {
          a.push("冲击力：", Math.floor(500 / impact), "<BR>");
        }
        break;
    }

    // 使用辅助方法生成属性行
    addUpgradeLine(a, "内力加成", d.force, 等级);
    addUpgradeLine(a, "伤害加成", d.damage, 等级);
    addUpgradeLine(a, "空手加成", d.punch, 等级);
    addUpgradeLine(a, "冷兵器加成", d.knifepower, 等级);
    addUpgradeLine(a, "枪械加成", d.gunpower, 等级);

    if (d.criticalhit !== undefined) {
      if (!isNaN(Number(d.criticalhit))) a.push("<FONT COLOR='#DD4455'>暴击：</FONT><FONT COLOR='#DD4455'>", d.criticalhit, "%概率造成1.5倍伤害</FONT><BR>");
      else if (d.criticalhit == "满血暴击") a.push("<FONT COLOR='#DD4455'>暴击：对满血敌人造成1.5倍伤害</FONT><BR>");
    }
    
    addNumLine(a, "斩杀线", d.slay, "%血量");
    addNumLine(a, "命中加成", d.accuracy, "%");
    addNumLine(a, "挡拆加成", d.evasion, "%");
    addNumLine(a, "韧性加成", d.toughness, "%");
    addNumLine(a, "高危回避", d.lazymiss, "");
    
    // 非药剂才在通用区显示"剧毒性"；药剂的剧毒由药剂分支统一输出
    if (d.poison && item.use != "药剂") addColorLine(a, "#66dd00", "剧毒性：" + d.poison);
    if (d.vampirism) addColorLine(a, "#bb00aa", "吸血：" + d.vampirism + "%");
    if (d.rout) addColorLine(a, "#FF3333", "击溃：" + d.rout + "%");

    if (d.damagetype) {
      if (d.damagetype == "魔法" && d.magictype) {
        addColorLine(a, "#0099FF", "伤害属性：" + d.magictype);
      } else if (d.damagetype == "破击" && d.magictype) {
        if (_root.敌人函数.魔法伤害种类.indexOf(d.magictype) >= 0)
          addColorLine(a, "#66bcf5", "附加伤害：" + d.magictype);
        else
          addColorLine(a, "#CC6600", "破击类型：" + d.magictype);
      } else {
        addColorLine(a, "#0099FF", "伤害类型：" + (d.damagetype == "魔法" ? "能量" : d.damagetype));
      }
    }

    if (d.magicdefence) {
      for (var k in d.magicdefence) {
        var 名 = (k == "基础" ? "能量" : k);
        var v = d.magicdefence[k];
        if (v != undefined && Number(v) != 0) a.push(名, "抗性：", v, "<BR>");
      }
    }

    addUpgradeLine(a, "防御", d.defence, 等级);
    if (d.hp) a.push("<FONT COLOR='#00FF00'>HP：", d.hp, "</FONT><FONT COLOR='#FFCC00'>(+", (_root.强化计算(d.hp, 等级)-d.hp), ")</FONT><BR>");
    if (d.mp) a.push("<FONT COLOR='#00FFFF'>MP：", d.mp, "</FONT><FONT COLOR='#FFCC00'>(+", (_root.强化计算(d.mp, 等级)-d.mp), ")</FONT><BR>");

    if (item.use == "药剂") {
      if (!isNaN(d.affecthp) && d.affecthp != 0) a.push("<FONT COLOR='#00FF00'>HP+", d.affecthp, "</FONT><BR>");
      if (!isNaN(d.affectmp) && d.affectmp != 0) a.push("<FONT COLOR='#00FFFF'>MP+", d.affectmp, "</FONT><BR>");
      if (d.friend == 1) a.push("<FONT COLOR='#FFCC00'>全体友方有效</FONT><BR>");
      else if (d.friend == "淬毒") {
        var p:Number = Number(d.poison);
        if (isNaN(p)) p = 0;
        a.push("<FONT COLOR='#66dd00'>剧毒性：", p, "</FONT><BR>");
      }
      else if (d.friend == "净化") a.push("净化度：", (isNaN(d.clean)?0:d.clean), "<BR>");
    }
    if (item.actiontype !== undefined) a.push("动作：", item.actiontype, "<BR>");

    return a;
  }

  // === 辅助方法：添加升级属性行 ===
  private static function addUpgradeLine(buf:Array, 标题:String, 基础:Number, 等级:Number):Void {
    if (基础 != undefined && !isNaN(基础) && 基础 != 0) {
      var 强化加成 = _root.强化计算(基础, 等级) - 基础;
      buf.push(标题, "：", 基础, "<FONT COLOR='#FFCC00'>(+", 强化加成, ")</FONT><BR>");
    }
  }

  // === 辅助方法：添加数值行 ===
  private static function addNumLine(buf:Array, 标题:String, 值, 后缀:String):Void {
    if (值 != undefined && !isNaN(Number(值)) && Number(值) != 0) {
      buf.push(标题, "：", 值, (后缀 || ""), "<BR>");
    }
  }

  // === 辅助方法：添加彩色行 ===
  private static function addColorLine(buf:Array, 颜色:String, 文本:String):Void {
    if (文本) {
      buf.push("<FONT COLOR='", 颜色, "'>", 文本, "</FONT><BR>");
    }
  }
}