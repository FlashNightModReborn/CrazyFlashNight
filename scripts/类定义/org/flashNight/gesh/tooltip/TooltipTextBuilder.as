import org.flashNight.arki.item.*;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipDataSelector;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.component.Damage.*;

/**
 * 注释文本构建器类
 * 包含所有文本拼接的纯函数，用于生成各种类型的注释内容
 * 1:1 复刻 _root.注释文本 的功能
 */
class org.flashNight.gesh.tooltip.TooltipTextBuilder {

  // === 生成基础描述（1:1 复刻 _root.注释文本.生成基础描述） ===
  public static function buildBasicDescription(item:Object):Array {
    var result = [];
    if (item.description) {
      result.push(item.description.split("\r\n").join(TooltipFormatter.br()), TooltipFormatter.br());
    }
    return result;
  } 
  
  // === 生成剧情碎片提示（1:1 复刻 _root.注释文本.生成剧情碎片提示） ===
  public static function buildStoryTip(item:Object):Array {
    var result = [];
    if (item.use == "情报") {
      result.push(
        TooltipFormatter.color("详细信息可在物品栏的情报界面查阅", TooltipConstants.COL_INFO),
        TooltipFormatter.br()
      );
    }
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
        var multiplier = Number(multiplierTables[i][item.name]);
        if (!isNaN(multiplier) && multiplier > 1) {
          result.push(
            TooltipFormatter.color("【技能加成】", TooltipConstants.COL_HL),
            "使用", skillNames[i], "享受", String((multiplier-1)*100), TooltipConstants.SUF_PERCENT, "锋利度增益",
            TooltipFormatter.br()
          );
        }
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
  public static function buildIntroHeader(baseItem:BaseItem, item:Object):Array {
    var value = baseItem.value ? baseItem.value : 1;
    var upgradeLevel = value.level ? value.level : 1;
    
    var result = [];
    result.push("<B>", (value.tier ? ("[" + value.tier + "]") : ""), item.displayname, "</B><BR>");
    result.push(item.type, "    ", item.use, "<BR>");
    // 为手枪和长枪显示具体武器类型
    if ((item.use == "手枪" || item.use == "长枪") && item.data && item.weapontype) {
      result.push("武器类型：", item.weapontype, "<BR>");
    }
    result.push("$", item.price, "<BR>");
    if (upgradeLevel > 1 && (item.type == "武器" || item.type == "防具")) {
      result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>强化等级：", upgradeLevel, "</FONT><BR>");
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



  public static function buildStats(baseItem:BaseItem, item:Object):Array {
    if(!item.data) return [];
    if (item.use === "药剂"){
      return buildDrugStats(item);
    }else{
      return buildEquipmentStats(baseItem, item);
    }
  }

  public static function buildDrugStats(item:Object):Array {
    var data = item.data;
    var result = [];

    if (!isNaN(data.affecthp) && data.affecthp != 0) result.push("<FONT COLOR='" + TooltipConstants.COL_HP + "'>HP+", data.affecthp, "</FONT><BR>");
    if (!isNaN(data.affectmp) && data.affectmp != 0) result.push("<FONT COLOR='" + TooltipConstants.COL_MP + "'>MP+", data.affectmp, "</FONT><BR>");
    if (data.friend == "群体") result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>全体友方有效</FONT><BR>");
    if (!!(data.poison)) {
      var poisonValue:Number = Number(data.poison);
      if (isNaN(poisonValue)) poisonValue = 0;
      result.push("<FONT COLOR='#66dd00'>剧毒性：", poisonValue, "</FONT><BR>");
    }
    if (!!(data.clean)) result.push("净化度：", (isNaN(data.clean) ? 0 : data.clean), "<BR>");
    
    return result;
  }

  // === 生成装备属性块（1:1 复刻 _root.注释文本.生成装备属性块） ===
  public static function buildEquipmentStats(baseItem:BaseItem, item:Object):Array {
    var value = baseItem.value ? baseItem.value : 1;
    var upgradeLevel = value.level ? value.level : 1;

    var result = [];

    var data = TooltipDataSelector.getEquipmentData(item, value.tier);
    var equipData = upgradeLevel > 1 || value.mods ? baseItem.getData().data : null;

    TooltipFormatter.upgradeLine(result, data, equipData, "level", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "weight", null, TooltipConstants.SUF_KG);

    switch (item.use) {
      case "刀":
        TooltipFormatter.upgradeLine(result, data, equipData, "power", "锋利度", null);
        break;
      case "手雷":
        result.push("威力：", data.power, "<BR>");
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
        TooltipFormatter.upgradeLine(result, data, equipData, "power", "子弹威力", null);
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
    TooltipFormatter.upgradeLine(result, data, equipData, "force", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "damage", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "punch", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "knifepower", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "gunpower", null, null);

    if (data.criticalhit) {
      if (!isNaN(Number(data.criticalhit))) result.push("<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>暴击：</FONT><FONT COLOR='" + TooltipConstants.COL_CRIT + "'>", data.criticalhit, TooltipConstants.SUF_PERCENT + "概率造成1.5倍伤害</FONT><BR>");
      else if (data.criticalhit == "满血暴击") result.push("<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>暴击：对满血敌人造成1.5倍伤害</FONT><BR>");
    }
    
    TooltipFormatter.upgradeLine(result, data, equipData, "accuracy", null, TooltipConstants.SUF_PERCENT);
    TooltipFormatter.upgradeLine(result, data, equipData, "evasion", null, TooltipConstants.SUF_PERCENT);
    TooltipFormatter.upgradeLine(result, data, equipData, "toughness", null, TooltipConstants.SUF_PERCENT);
    TooltipFormatter.upgradeLine(result, data, equipData, "lazymiss", null, null);
    
    // 非药剂才在通用区显示"剧毒性"；药剂的剧毒由药剂分支统一输出
    TooltipFormatter.upgradeLine(result, data, equipData, "poison", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "vampirism", null, TooltipConstants.SUF_PERCENT);
    TooltipFormatter.upgradeLine(result, data, equipData, "rout", null, TooltipConstants.SUF_PERCENT);
    TooltipFormatter.upgradeLine(result, data, equipData, "slay", null, TooltipConstants.SUF_BLOOD);

    if (data.damagetype) {
      if (data.damagetype == "魔法" && data.magictype) {
        TooltipFormatter.colorLine(result, TooltipConstants.COL_DMG, "伤害属性：" + data.magictype);
      } else if (data.damagetype == "破击" && data.magictype) {
        if (MagicDamageTypes.isMagicDamageType(data.magictype))
          TooltipFormatter.colorLine(result, TooltipConstants.COL_BREAK_LIGHT, "附加伤害：" + data.magictype);
        else
          TooltipFormatter.colorLine(result, TooltipConstants.COL_BREAK_MAIN, "破击类型：" + data.magictype);
      } else {
        TooltipFormatter.colorLine(result, TooltipConstants.COL_DMG, "伤害类型：" + (data.damagetype == "魔法" ? "能量" : data.damagetype));
      }
    }

    if (data.magicdefence) {
      for (var key in data.magicdefence) {
        var displayName = (key == "基础" ? "能量" : key);
        var value = data.magicdefence[key];
        if (value != undefined && Number(value) != 0) result.push(displayName, "抗性：", value, "<BR>");
      }
    }

    TooltipFormatter.upgradeLine(result, data, equipData, "defence", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "hp", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "mp", null, null);

    if (item.actiontype !== undefined) result.push("动作：", item.actiontype, "<BR>");

    return result;
  }

  // === 生成装备强化数据属性块 ===
  public static function buildEnhancementStats(itemData:Object, level:Number):Array {
    var result = [];
    var data = itemData.data;
    var stat = EquipmentUtil.levelStatList[level] - 1;
    if(isNaN(stat)) return;
    
    if(itemData.use === "刀"){
      TooltipFormatter.enhanceLine(result, "multiply", data, "power", stat, "锋利度");
    }else if(itemData.use === "长枪" || itemData.use === "手枪"){
      TooltipFormatter.enhanceLine(result, "multiply", data, "power", stat, "子弹威力");
    }
    TooltipFormatter.enhanceLine(result, "multiply", data, "force", stat, null);
    TooltipFormatter.enhanceLine(result, "multiply", data, "damage", stat, null);
    TooltipFormatter.enhanceLine(result, "multiply", data, "punch", stat, null);
    TooltipFormatter.enhanceLine(result, "multiply", data, "knifepower", stat, null);
    TooltipFormatter.enhanceLine(result, "multiply", data, "gunpower", stat, null);
    TooltipFormatter.enhanceLine(result, "multiply", data, "defence", stat, null);

    TooltipFormatter.enhanceLine(result, "multiply", data, "hp", stat, null);
    TooltipFormatter.enhanceLine(result, "multiply", data, "mp", stat, null);

    return result;
  }

  // === 生成插件数据属性块 ===
  public static function buildModInfo(item:Object, tier:String, level:Number):Array {
    return null; // TODO
  }



  // === 生成单个插件加成 ===
  public static function buildModStat(modData:Object):Array {
    return null; // TODO
  }



}