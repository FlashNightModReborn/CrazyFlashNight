import org.flashNight.arki.item.ItemUtil;
import org.flashNight.gesh.string.TooltipFormatter;
import org.flashNight.gesh.string.TooltipConstants;
import org.flashNight.gesh.string.TooltipDataSelector;
import org.flashNight.arki.bullet.BulletComponent.Type.*;

/**
 * 注释文本构建器类
 * 包含所有文本拼接的纯函数，用于生成各种类型的注释内容
 * 1:1 复刻 _root.注释文本 的功能
 */
class org.flashNight.gesh.string.TooltipTextBuilder {

  // === 生成基础描述（1:1 复刻 _root.注释文本.生成基础描述） ===
  public static function buildBasicDescription(item:Object):Array {
    var result = [];
    if (item.description) result.push(item.description.split("\r\n").join("<BR>"), "<BR>");
    return result;
  }
  
  // === 生成剧情碎片提示（1:1 复刻 _root.注释文本.生成剧情碎片提示） ===
  public static function buildStoryTip(item:Object):Array {
    var result = [];
    if (item.use == "情报") result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>详细信息可在物品栏的情报界面查阅</FONT><BR>");
    return result;
  }

  // === 生成合成材料（1:1 复刻 _root.注释文本.生成合成材料） ===
  public static function buildSynthesisMaterials(item:Object):Array {
    var result = [];
    // 三段防护：对象存在 / materials 存在 / 返回数组存在
    if (item.synthesis != null && 
        _root.改装清单对象 && 
        _root.改装清单对象[item.synthesis] && 
        _root.改装清单对象[item.synthesis].materials) {
      var requirements = ItemUtil.getRequirementFromTask(_root.改装清单对象[item.synthesis].materials);
      if (requirements && requirements.length > 0) {
        result.push("合成材料：<BR>");
        for (var i=0; i<requirements.length; i++) {
          if (requirements[i] && requirements[i].name) {
            result.push(ItemUtil.getItemData(requirements[i].name).displayname, "：", requirements[i].value, "<BR>");
          }
        }
      }
    }
    return result;
  }

  // === 生成刀技乘数（1:1 复刻 _root.注释文本.生成刀技乘数） ===
  public static function buildBladeSkillMultipliers(item:Object):Array {
    var result = [];
    if (item.use === "刀") {
      var multiplierTables = [_root.技能函数.凶斩伤害乘数表, _root.技能函数.瞬步斩伤害乘数表,
                 _root.技能函数.龙斩刀伤乘数表, _root.技能函数.拔刀术伤害乘数表];
      var skillNames = ["凶斩","瞬步斩","龙斩","拔刀术"];
      for (var i=0; i<multiplierTables.length; i++) {
        var multiplier = multiplierTables[i][item.name];
        if (multiplier > 1) result.push("<font color='" + TooltipConstants.COL_HL + "'>【技能加成】</font>使用", skillNames[i], "享受", String((multiplier-1)*100), TooltipConstants.SUF_PERCENT + "锋利度增益<BR>");
      }
    }
    return result;
  }

  // === 生成战技信息（1:1 复刻 _root.注释文本.生成战技信息） ===
  public static function buildSkillInfo(skill:Object):Array {
    var result = [];
    if (!skill) return result;
    if (skill.description) {
      result.push("<font color='" + TooltipConstants.COL_HL + "'>【主动战技】</font>", skill.description, "<BR><font color='" + TooltipConstants.COL_HL + "'>【战技信息】</font>");
      if (skill.information) {
        result.push(skill.information);
      } else {
        var cooldown = skill.cd/1000;
        result.push("冷却", cooldown, TooltipConstants.SUF_SECOND);
        if (skill.hp && skill.hp != 0) result.push("，消耗", skill.hp, TooltipConstants.SUF_HP);
        if (skill.mp && skill.mp != 0) result.push("，消耗", skill.mp, TooltipConstants.SUF_MP);
        result.push("。");
      }
    } else {
      result.push(skill);
    }
    result.push("<BR>");
    return result;
  }

  // === 生成生命周期（1:1 复刻 _root.注释文本.生成生命周期） ===
  public static function buildLifecycleInfo(lc:Object):Array {
    var result = [];
    if (lc && lc.description) result.push("<font color='" + TooltipConstants.COL_HL + "'>【词条信息】</font>", lc.description, "<BR>");
    return result;
  }

  // === 生成简介标题头（1:1 复刻 _root.注释文本.生成简介标题头） ===
  public static function buildIntroHeader(item:Object, value:Object, 强化等级:Number):Array {
    var result = [];
    result.push("<B>", (value.tier ? ("[" + value.tier + "]") : ""), item.displayname, "</B><BR>");
    result.push(item.type, "    ", item.use, "<BR>");
    if (item.type == "武器" || item.type == "防具") { result.push("等级限制：", item.level, "<BR>"); }
    result.push("$", item.price, "<BR>");
    if (item.weight != null && item.weight !== 0) result.push("重量：", item.weight, TooltipConstants.SUF_KG + "<BR>");
    if (强化等级 > 1 && (item.type == "武器" || item.type == "防具")) {
      result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>强化等级：", 强化等级, "</FONT><BR>");
    } else {
      // 兼容多种形态：value 为数字 或 对象里带各种数量字段
      var quantity:Number = 0;
      if (typeof value == "number") {
        quantity = Number(value);
      } else if (value) {
        // 优先级：count > amount > num > stack > quantity
        var candidates = [value.count, value.amount, value.num, value.stack, value.quantity];
        for (var i = 0; i < candidates.length; i++) {
          var candidate = Number(candidates[i]);
          if (!isNaN(candidate) && candidate > 0) {
            quantity = candidate;
            break;
          }
        }
      }
      if (quantity > 1) result.push("数量：", quantity, "<BR>");
    }
    return result;
  }

  // === 生成装备属性块（1:1 复刻 _root.注释文本.生成装备属性块） ===
  public static function buildEquipmentStats(item:Object, tier:String, 等级:Number):Array {
    if (等级 == undefined || isNaN(等级) || 等级 < 1) 等级 = 1;
    var result = [];
    var data = TooltipDataSelector.getEquipmentData(item, tier);

    switch (item.use) {
      case "刀":
        addUpgradeLine(result, "锋利度", data.power, 等级);
        break;
      case "手雷":
        result.push("等级限制：", item.level, "<BR>威力：", data.power, "<BR>");
        break;
      case "长枪":
      case "手枪":
        if (data.clipname) result.push("使用弹夹：", ItemUtil.getItemData(data.clipname).displayname, "<BR>");
        var bulletString = (data.bulletrename ? data.bulletrename : data.bullet);
        if (bulletString) result.push("子弹类型：", bulletString, "<BR>");
        var isNotMultiShot:Boolean = (data.bullet && BulletTypesetter.isVertical(data.bullet));
        
        // 数值字段统一防护：使用Number()转换 + isNaN()兜底
        var splitValue:Number = Number(data.split);
        if (isNaN(splitValue) || splitValue <= 1) splitValue = 1;
        
        var capacity:Number = Number(data.capacity);
        if (isNaN(capacity)) capacity = 0;
        
        var magazineCapacity = isNotMultiShot ? splitValue : 1;
        if (capacity > 0) result.push("弹夹容量：", (capacity * magazineCapacity), "<BR>");
        addUpgradeLine(result, "子弹威力", data.power, 等级);
        if (splitValue > 1) result.push(isNotMultiShot ? "点射弹数：" : "弹丸数量：", splitValue, "<BR>");
        
        // interval和impact的防护：确保是有效数值且非零
        var interval:Number = Number(data.interval);
        if (!isNaN(interval) && interval > 0) {
          result.push("射速：", (Math.floor(10000 / interval) * 0.1 * magazineCapacity), TooltipConstants.SUF_FIRE_RATE + "<BR>");
        }
        
        var impact:Number = Number(data.impact);
        if (!isNaN(impact) && impact > 0) {
          result.push("冲击力：", Math.floor(500 / impact), "<BR>");
        }
        break;
    }

    // 使用辅助方法生成属性行
    addUpgradeLine(result, "内力加成", data.force, 等级);
    addUpgradeLine(result, "伤害加成", data.damage, 等级);
    addUpgradeLine(result, "空手加成", data.punch, 等级);
    addUpgradeLine(result, "冷兵器加成", data.knifepower, 等级);
    addUpgradeLine(result, "枪械加成", data.gunpower, 等级);

    if (data.criticalhit !== undefined) {
      if (!isNaN(Number(data.criticalhit))) result.push("<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>暴击：</FONT><FONT COLOR='" + TooltipConstants.COL_CRIT + "'>", data.criticalhit, TooltipConstants.SUF_PERCENT + "概率造成1.5倍伤害</FONT><BR>");
      else if (data.criticalhit == "满血暴击") result.push("<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>暴击：对满血敌人造成1.5倍伤害</FONT><BR>");
    }
    
    addNumLine(result, "斩杀线", data.slay, TooltipConstants.SUF_BLOOD);
    addNumLine(result, "命中加成", data.accuracy, TooltipConstants.SUF_PERCENT);
    addNumLine(result, "挡拆加成", data.evasion, TooltipConstants.SUF_PERCENT);
    addNumLine(result, "韧性加成", data.toughness, TooltipConstants.SUF_PERCENT);
    addNumLine(result, "高危回避", data.lazymiss, "");
    
    // 非药剂才在通用区显示"剧毒性"；药剂的剧毒由药剂分支统一输出
    if (data.poison && item.use != "药剂") addColorLine(result, TooltipConstants.COL_POISON, "剧毒性：" + data.poison);
    if (data.vampirism) addColorLine(result, TooltipConstants.COL_VAMP, "吸血：" + data.vampirism + TooltipConstants.SUF_PERCENT);
    if (data.rout) addColorLine(result, TooltipConstants.COL_ROUT, "击溃：" + data.rout + TooltipConstants.SUF_PERCENT);

    if (data.damagetype) {
      if (data.damagetype == "魔法" && data.magictype) {
        addColorLine(result, TooltipConstants.COL_DMG, "伤害属性：" + data.magictype);
      } else if (data.damagetype == "破击" && data.magictype) {
        if (_root.敌人函数.魔法伤害种类.indexOf(data.magictype) >= 0)
          addColorLine(result, TooltipConstants.COL_BREAK_LIGHT, "附加伤害：" + data.magictype);
        else
          addColorLine(result, TooltipConstants.COL_BREAK_MAIN, "破击类型：" + data.magictype);
      } else {
        addColorLine(result, TooltipConstants.COL_DMG, "伤害类型：" + (data.damagetype == "魔法" ? "能量" : data.damagetype));
      }
    }

    if (data.magicdefence) {
      for (var key in data.magicdefence) {
        var displayName = (key == "基础" ? "能量" : key);
        var value = data.magicdefence[key];
        if (value != undefined && Number(value) != 0) result.push(displayName, "抗性：", value, "<BR>");
      }
    }

    addUpgradeLine(result, "防御", data.defence, 等级);
    addUpgradeLine(result, "<FONT COLOR='" + TooltipConstants.COL_HP + "'>HP</FONT>", data.hp, 等级);
    addUpgradeLine(result, "<FONT COLOR='" + TooltipConstants.COL_MP + "'>MP</FONT>", data.hp, 等级);

    if (item.use == "药剂") {
      if (!isNaN(data.affecthp) && data.affecthp != 0) result.push("<FONT COLOR='" + TooltipConstants.COL_HP + "'>HP+", data.affecthp, "</FONT><BR>");
      if (!isNaN(data.affectmp) && data.affectmp != 0) result.push("<FONT COLOR='" + TooltipConstants.COL_MP + "'>MP+", data.affectmp, "</FONT><BR>");
      if (data.friend == 1) result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>全体友方有效</FONT><BR>");
      else if (data.friend == "淬毒") {
        var poisonValue:Number = Number(data.poison);
        if (isNaN(poisonValue)) poisonValue = 0;
        result.push("<FONT COLOR='#66dd00'>剧毒性：", poisonValue, "</FONT><BR>");
      }
      else if (data.friend == "净化") result.push("净化度：", (isNaN(data.clean)?0:data.clean), "<BR>");
    }
    if (item.actiontype !== undefined) result.push("动作：", item.actiontype, "<BR>");

    return result;
  }

  // === 生成装备强化数据属性块 ===
  public static function buildEnhancementStats(itemData:Object, 等级:Number):Array {
    var result = [];
    var data = itemData.data;
    if(itemData.use === "刀"){
      addUpgradeLine(result, "锋利度", data.power, 等级, " -> ");
    }else if(itemData.use === "长枪" || itemData.use === "手枪"){
      addUpgradeLine(result, "子弹威力", data.power, 等级, " -> ");
    }
    addUpgradeLine(result, "内力加成", data.force, 等级, " -> ");
    addUpgradeLine(result, "伤害加成", data.damage, 等级, " -> ");
    addUpgradeLine(result, "空手加成", data.punch, 等级, " -> ");
    addUpgradeLine(result, "冷兵器加成", data.knifepower, 等级, " -> ");
    addUpgradeLine(result, "枪械加成", data.gunpower, 等级, " -> ");
    addUpgradeLine(result, "防御", data.defence, 等级, " -> ");
    addUpgradeLine(result, "<FONT COLOR='" + TooltipConstants.COL_HP + "'>HP</FONT>", data.hp, 等级, " -> ");
    addUpgradeLine(result, "<FONT COLOR='" + TooltipConstants.COL_MP + "'>MP</FONT>", data.hp, 等级, " -> ");
    return result;
  }




  // === 辅助方法：添加升级属性行 ===
  private static function addUpgradeLine(buffer:Array, title:String, baseValue:Number, level:Number, colon:String):Void {
    if (baseValue != undefined && !isNaN(baseValue) && baseValue != 0) {
      var upgradeBonus = _root.强化计算(baseValue, level) - baseValue;
      if(colon == null) colon = "：";
      buffer.push(title, colon, baseValue, "<FONT COLOR='" + TooltipConstants.COL_HL + "'>(+", upgradeBonus, ")</FONT><BR>");
    }
  }

  // === 辅助方法：添加数值行 ===
  private static function addNumLine(buffer:Array, title:String, value, suffix:String):Void {
    if (value != undefined && !isNaN(Number(value)) && Number(value) != 0) {
      buffer.push(title, "：", value, (suffix || ""), "<BR>");
    }
  }

  // === 辅助方法：添加彩色行 ===
  private static function addColorLine(buffer:Array, color:String, text:String):Void {
    if (text) {
      buffer.push("<FONT COLOR='", color, "'>", text, "</FONT><BR>");
    }
  }
}