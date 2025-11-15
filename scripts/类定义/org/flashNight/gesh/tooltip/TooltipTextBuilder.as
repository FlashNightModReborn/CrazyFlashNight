import org.flashNight.arki.item.*;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.ItemUseTypes;
import org.flashNight.gesh.tooltip.TooltipDataSelector;
import org.flashNight.gesh.tooltip.builder.EquipmentStatsComposer;
import org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder;
import org.flashNight.gesh.tooltip.builder.SlayEffectBuilder;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.gesh.object.ObjectUtil;

import org.flashNight.naki.Sort.InsertionSort;

/**
 * 注释文本构建器类
 * 包含所有文本拼接的纯函数，用于生成各种类型的注释内容
 * 1:1 复刻 _root.注释文本 的功能
 */
class org.flashNight.gesh.tooltip.TooltipTextBuilder {

  /**
   * 构建操作类型前缀（用于显示"覆盖"、"合并"等标签）
   * @param operationType 操作类型名称（如"覆盖"、"合并"）
   * @return 格式化后的前缀字符串，如果 operationType 为空则返回空字符串
   */
  private static function buildOperationPrefix(operationType:String):String {
    if (!operationType) return "";
    return "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>[" + operationType + "]</FONT> ";
  }

  // === 生成基础描述（1:1 复刻 _root.注释文本.生成基础描述） ===
  public static function buildBasicDescription(item:Object, baseItem:BaseItem):Array {
    var result = [];

    // 获取最终的 description（考虑进阶可能修改描述）
    var description:String = item.description;
    if(baseItem && baseItem.getData != undefined) {
      var calculatedData:Object = baseItem.getData();
      if(calculatedData && calculatedData.description !== undefined) {
        description = calculatedData.description;
      }
    }

    if (description) {
      result.push(description.split("\r\n").join(TooltipFormatter.br()), TooltipFormatter.br());
    }
    return result;
  } 
  
  // === 生成剧情碎片提示（1:1 复刻 _root.注释文本.生成剧情碎片提示） ===
  public static function buildStoryTip(item:Object):Array {
    var result = [];
    if (item.use == ItemUseTypes.INFORMATION) {
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
            var itemData = ItemUtil.getItemData(requirements[i].name);
            var displayText = itemData.displayname;

            // 根据是否为数量模式决定显示方式
            if (requirements[i].isQuantity) {
              // 数量模式：显示 "物品名 x 数量"
              displayText += " x " + requirements[i].value;
            } else if (ItemUtil.isEquipment(requirements[i].name)) {
              // 强化度模式：显示 "物品名 +强化度"
              displayText += " +" + requirements[i].value;
            } else {
              // 非装备物品：显示数量
              displayText += "：" + requirements[i].value;
            }

            result.push(displayText, "<BR>");
          }
        }
      }
    }
    return result;
  }

  // === 生成刀技乘数（重构后：从XML配置读取，显示插件影响） ===
  public static function buildBladeSkillMultipliers(item:Object, baseItem:BaseItem):Array {
    var result = [];
    if (item.use !== ItemUseTypes.MELEE) return result;

    // 获取基础数据和最终数据
    var baseSkillMultipliers = (item.data && item.data.skillmultipliers) ? item.data.skillmultipliers : null;
    var finalSkillMultipliers = null;
    var hasEquipData = false;

    if (baseItem && baseItem.getData != undefined) {
      var calculatedData = baseItem.getData();
      if (calculatedData && calculatedData.data && calculatedData.data.skillmultipliers) {
        finalSkillMultipliers = calculatedData.data.skillmultipliers;
        hasEquipData = true;
      }
    }

    // 如果没有计算后的数据，使用原始数据
    if (!finalSkillMultipliers) {
      finalSkillMultipliers = baseSkillMultipliers;
    }

    if (!finalSkillMultipliers && !baseSkillMultipliers) return result;

    // 收集所有技能名称（基础和最终的并集）
    var skillNames = {};
    if (baseSkillMultipliers) {
      for (var key in baseSkillMultipliers) {
        if (ObjectUtil.isInternalKey(key)) continue;
        skillNames[key] = true;
      }
    }
    if (finalSkillMultipliers) {
      for (var key in finalSkillMultipliers) {
        if (ObjectUtil.isInternalKey(key)) continue;
        skillNames[key] = true;
      }
    }

    // 对每个技能显示变化前后的值（类似魔法抗性的逻辑）
    for (var skillName:String in skillNames) {
      var baseMultiplier = (baseSkillMultipliers && baseSkillMultipliers[skillName]) ? baseSkillMultipliers[skillName] : null;
      var finalMultiplier = (finalSkillMultipliers && finalSkillMultipliers[skillName]) ? finalSkillMultipliers[skillName] : null;

      // 转换为数字，默认为1（无加成）
      var baseNum = Number(baseMultiplier);
      if (isNaN(baseNum) || baseNum <= 1) baseNum = 1;

      var finalNum = Number(finalMultiplier);
      if (isNaN(finalNum) || finalNum <= 1) finalNum = 1;

      // 如果两者都是1（无加成），跳过显示
      if (baseNum == 1 && finalNum == 1) continue;

      // 若没有实际装备数值或实际数值与原始数值相等，则打印原始数值
      if (!hasEquipData || finalNum == baseNum) {
        if (baseNum > 1) {
          result.push(
            TooltipFormatter.color("【技能加成】", TooltipConstants.COL_HL),
            "使用", skillName, "享受", String((baseNum-1)*100), TooltipConstants.SUF_PERCENT, "锋利度增益",
            TooltipFormatter.br()
          );
        }
      } else {
        // 有变化，显示变化前后的值（包括降低到0的情况）
        var finalPercent = (finalNum - 1) * 100;
        var basePercent = (baseNum - 1) * 100;
        var enhance = finalNum - baseNum;
        var enhancePercent = enhance * 100;

        result.push(
          TooltipFormatter.color("【技能加成】", TooltipConstants.COL_HL),
          "使用", skillName, "享受<FONT COLOR='", TooltipConstants.COL_HL, "'>", String(finalPercent), TooltipConstants.SUF_PERCENT, "</FONT>锋利度增益"
        );

        // 显示变化量
        var sign:String;
        if (enhance < 0) {
          enhancePercent = -enhancePercent;
          sign = " - ";
        } else {
          sign = " + ";
        }
        result.push(" (", String(basePercent), TooltipConstants.SUF_PERCENT, sign, String(enhancePercent), TooltipConstants.SUF_PERCENT, ")<BR>");
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

    // 获取最终的 displayname（考虑进阶可能修改显示名称）
    var displayName:String = item.displayname;
    if(baseItem && baseItem.getData != undefined) {
      var calculatedData:Object = baseItem.getData();
      if(calculatedData && calculatedData.displayname !== undefined) {
        displayName = calculatedData.displayname;
      }
    }

    var result = [];
    result.push("<B>", (value.tier ? ("[" + value.tier + "]") : ""), displayName, "</B><BR>");
    result.push(item.type, "    ", item.use, "<BR>");
    // 为手枪和长枪显示具体武器类型
    if (ItemUseTypes.isGun(item.use) && item.data && item.weapontype) {
      result.push("武器类型：", item.weapontype, "<BR>");
    }
    result.push("$", item.price, "<BR>");
    if (upgradeLevel > 1 && (item.type == ItemUseTypes.TYPE_WEAPON || item.type == ItemUseTypes.TYPE_ARMOR)) {
      // 获取强化等级对应的倍率并计算增幅百分比
      var levelMultiplier:Number = EquipmentUtil.levelStatList[upgradeLevel];
      if (levelMultiplier && !isNaN(levelMultiplier)) {
        var enhancement:Number = Math.round((levelMultiplier - 1) * 100);
        result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>强化等级：", upgradeLevel, " (+", enhancement, "%)</FONT><BR>");
      } else {
        result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>强化等级：", upgradeLevel, "</FONT><BR>");
      }
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
    if (item.use === ItemUseTypes.POTION){
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

    var data = TooltipDataSelector.getEquipmentData(item, value.tier);
    var equipData = upgradeLevel > 1 || value.mods ? baseItem.getData().data : null;

    // 委托给新的编排器（保持完全相同的输出）
    return EquipmentStatsComposer.compose(baseItem, item, data, equipData);
  }

  // === 生成装备强化数据属性块 ===
  public static function buildEnhancementStats(itemData:Object, level:Number):Array {
    var result = [];
    var data = itemData.data;
    var stat = EquipmentUtil.levelStatList[level] - 1;
    if(isNaN(stat)) return result;

    if(itemData.use === ItemUseTypes.MELEE){
      TooltipFormatter.enhanceLine(result, "multiply", data, "power", stat, "锋利度");
    }else if(ItemUseTypes.isGun(itemData.use)){
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

  // === 生成进阶数据属性块 ===
  public static function buildTierInfo(equipDisplayName:String, itemName:String, tierName:String, tierData:Object):Array {
    var result:Array = [];
    var displayName = ItemUtil.getItemData(itemName).displayname;
    result.push("<B>", displayName, "</B><BR>");
    if(!tierData) {
      tierData = EquipmentUtil.defaultTierDataDict[tierName];
      if(!tierData) {
        result.push("无加成数据");
        return result;
      }
    }
    result.push("对装备<B>",equipDisplayName,"</B>的加成：<BR>");

    var sortedList = getSortedAttrList(tierData);
    for(var i = 0; i < sortedList.length; i++){
      var key = sortedList[i];
      TooltipFormatter.statLine(result, "override", key, tierData[key], null);
    }
    // 打印魔法抗性
    if (tierData.magicdefence) {
      result.push(quickBuildMagicDefence(tierData.magicdefence, null));
    }

    return result;
  }
  
  // === 生成插件数据属性块 ===
  public static function buildModInfo(item:Object, tier:String, level:Number):Array {
    return null; // TODO
  }



  // === 生成单个插件加成 ===
  public static function buildModStat(itemName:String):Array {
    var result = [];
    var modData = EquipmentUtil.modDict[itemName];
    if(!modData) return result;
    result.push("<font color='" + TooltipConstants.COL_HL + "'>【配件信息】</font><BR>");
    result.push("适用装备类型：" + modData.use + "<BR>");
    // 显示插件的tag分类
    if(modData.tagValue){
      result.push("<font color='" + TooltipConstants.COL_INFO + "'>插件位置：</font>" + modData.tagValue + "<BR>");
    }
    if(modData.weapontype){
      result.push("适用武器子类：" + modData.weapontype + "<BR>");
    }

    var stats = modData.stats;
    var percentage = stats.percentage;
    var flat = stats.flat;
    var override = stats.override;
    var merge = stats.merge;  // 新增：读取merge数据
    var cap = stats.cap;
    var multiplier = stats.multiplier;  // 新增：读取multiplier数据
    if(percentage){
      var sortedList = getSortedAttrList(percentage);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        TooltipFormatter.statLine(result, "multiply", key, percentage[key], null);
      }
    }
    if(multiplier){
      var sortedList = getSortedAttrList(multiplier);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        var mValue = multiplier[key];
        var label = TooltipConstants.PROPERTY_DICT[key];
        if(!label) label = key;

        var displayText:String;
        if(mValue < 0) {
          // 负数：显示为倍率（如 ×0.65）
          var multiplierValue = 1 + mValue;  // 1 + (-0.35) = 0.65
          var displayValue = Math.round(multiplierValue * 100) / 100;  // 保留2位小数
          displayText = "×" + displayValue;
        } else {
          // 正数：显示为百分比（如 ×+15%）
          var percentDisplay = Math.round(mValue * 100);
          displayText = "×+" + percentDisplay + "%";
        }

        // 使用特殊颜色和符号标识独立乘区
        result.push("<FONT COLOR='#FF6600'>", label, " ", displayText, "</FONT> <FONT COLOR='#FF9944'>[独立乘区]</FONT><BR>");
      }
    }
    if(flat){
      var sortedList = getSortedAttrList(flat);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        // 跳过 slay，使用专门的 SlayEffectBuilder 显示
        if(key == "slay") continue;
        TooltipFormatter.statLine(result, "add", key, flat[key], null);
      }
      // 使用 SlayEffectBuilder 处理斩杀线属性
      if(flat.slay){
        SlayEffectBuilder.buildFlat(result, flat.slay);
      }
    }
    if(override){
      var sortedList = getSortedAttrList(override);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        // 跳过 damagetype 和 magictype，这些需要组合显示
        if(key == "damagetype" || key == "magictype") continue;
        // 跳过 silence，使用专门的 SilenceEffectBuilder 显示
        if(key == "silence") continue;
        // 跳过 slay，使用专门的 SlayEffectBuilder 显示
        if(key == "slay") continue;
        TooltipFormatter.statLine(result, "override", key, override[key], null);
      }
      // 使用 SlayEffectBuilder 处理斩杀线属性
      if(override.slay){
        SlayEffectBuilder.buildOverride(result, override.slay);
      }
    }
    if(merge){
      var sortedList = getSortedAttrList(merge);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        // 跳过嵌套对象，它们需要特殊处理
        if(key == "magicdefence" || key == "skillmultipliers") continue;
        TooltipFormatter.statLine(result, "merge", key, merge[key], null);
      }
    }
    // 显示cap上限
    if(cap){
      var sortedList = getSortedAttrList(cap);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        var capValue = cap[key];
        var label = TooltipConstants.PROPERTY_DICT[key];
        if(!label) label = key;

        if(capValue > 0){
          // 正数cap = 增益上限
          result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " 增益上限: +", capValue, "</FONT><BR>");
        }else if(capValue < 0){
          // 负数cap = 减益下限
          result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " 减益下限: ", capValue, "</FONT><BR>");
        }
      }
    }
    // 查找criticalhit、magicdefence、skillmultipliers和silence（从override）
    if(override && override.criticalhit){
      result.push(quickBuildCriticalHit(override.criticalhit));
    }
    if(override && override.magicdefence){
      result.push(quickBuildMagicDefence(override.magicdefence, "覆盖"));
    }
    if(override && override.skillmultipliers){
      result.push(quickBuildSkillMultipliers(override.skillmultipliers, "覆盖"));
    }
    // 使用 SilenceEffectBuilder 构建消音效果显示
    if(override && override.silence){
      SilenceEffectBuilder.build(result, null, null, override, null);
    }
    // 查找magicdefence和skillmultipliers（从merge）
    if(merge && merge.magicdefence){
      result.push(quickBuildMagicDefence(merge.magicdefence, "合并"));
    }
    if(merge && merge.skillmultipliers){
      result.push(quickBuildSkillMultipliers(merge.skillmultipliers, "合并"));
    }
    // 显示伤害类型和破击类型（与 buildEquipmentStats 保持一致）
    if(override) quickBuildDamageType(result, override);

    // 显示useSwitch条件效果（详细版）
    if(stats && stats.useSwitch && stats.useSwitch.useCases){
      var useCases = stats.useSwitch.useCases;
      if(useCases.length > 0){
        result.push("<font color='" + TooltipConstants.COL_HL + "'>【按装备类型追加效果】</font><BR>");

        for(var ucIdx = 0; ucIdx < useCases.length; ucIdx++){
          var useCase = useCases[ucIdx];
          if(!useCase.name) continue;

          result.push("<font color='" + TooltipConstants.COL_INFO + "'>对 " + useCase.name + "：</font><BR>");

          // 显示percentage加成
          if(useCase.percentage){
            var sortedList = getSortedAttrList(useCase.percentage);
            for(var i = 0; i < sortedList.length; i++){
              var key = sortedList[i];
              result.push("  ");  // 缩进
              TooltipFormatter.statLine(result, "multiply", key, useCase.percentage[key], null);
            }
          }

          // 显示multiplier独立乘区
          if(useCase.multiplier){
            var sortedList = getSortedAttrList(useCase.multiplier);
            for(var i = 0; i < sortedList.length; i++){
              var key = sortedList[i];
              var mValue = useCase.multiplier[key];
              var label = TooltipConstants.PROPERTY_DICT[key];
              if(!label) label = key;

              var displayText:String;
              if(mValue < 0) {
                // 负数：显示为倍率
                var multiplierValue = 1 + mValue;
                var displayValue = Math.round(multiplierValue * 100) / 100;
                displayText = "×" + displayValue;
              } else {
                // 正数：显示为百分比
                var percentDisplay = Math.round(mValue * 100);
                displayText = "×+" + percentDisplay + "%";
              }

              result.push("  <FONT COLOR='#FF6600'>", label, " ", displayText, "</FONT> <FONT COLOR='#FF9944'>[独立乘区]</FONT><BR>");
            }
          }

          // 显示flat加成
          if(useCase.flat){
            var sortedList = getSortedAttrList(useCase.flat);
            for(var i = 0; i < sortedList.length; i++){
              var key = sortedList[i];
              result.push("  ");  // 缩进
              TooltipFormatter.statLine(result, "add", key, useCase.flat[key], null);
            }
          }

          // 显示override覆盖
          if(useCase.override){
            var sortedList = getSortedAttrList(useCase.override);
            for(var i = 0; i < sortedList.length; i++){
              var key = sortedList[i];
              if(key == "damagetype" || key == "magictype" || key == "silence") continue;
              result.push("  ");  // 缩进
              TooltipFormatter.statLine(result, "override", key, useCase.override[key], null);
            }
          }

          // 显示cap上限
          if(useCase.cap){
            var sortedList = getSortedAttrList(useCase.cap);
            for(var i = 0; i < sortedList.length; i++){
              var key = sortedList[i];
              var capValue = useCase.cap[key];
              var label = TooltipConstants.PROPERTY_DICT[key];
              if(!label) label = key;

              if(capValue > 0){
                result.push("  <FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " 增益上限: +", capValue, "</FONT><BR>");
              }else if(capValue < 0){
                result.push("  <FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " 减益下限: ", capValue, "</FONT><BR>");
              }
            }
          }
        }
      }
    }

    if(modData.skill){
      result = result.concat(buildSkillInfo(modData.skill));
    }

    // 读取描述（如果有）
    if(typeof modData.description === "string"){
      result.push(modData.description.split("\r\n").join(TooltipFormatter.br()), TooltipFormatter.br());
    }
    return result;
  }

  // === 快速打印暴击数据 ===
  public static function quickBuildCriticalHit(criticalhit):String{
    if (!isNaN(Number(criticalhit)))
      return "<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>暴击：</FONT><FONT COLOR='" + TooltipConstants.COL_CRIT + "'>" + criticalhit + TooltipConstants.SUF_PERCENT + "概率造成1.5倍伤害</FONT><BR>";
    else if (criticalhit === "满血暴击")
        return "<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>暴击：对满血敌人造成1.5倍伤害</FONT><BR>";
    return "";
  }

  // === 快速打印魔法抗性数据 ===
  public static function quickBuildMagicDefence(magicdefence:Object, operationType:String):String{
    var mdList = [];
    for(var key in magicdefence) {
      if (ObjectUtil.isInternalKey(key)) continue; // 跳过内部字段（如 __dictUID）
      var mdName = (key === "基础" ? "能量" : key);
      var value = magicdefence[key];
      if (value) mdList.push(mdName + ": " + value);
    }
    if(mdList.length > 0) {
      var prefix = buildOperationPrefix(operationType);
      return prefix + "抗性 -> " + mdList.join(", ") + "<BR>";
    }
    return "";
  }

  // === 快速打印技能乘数数据（用于插件tooltip） ===
  public static function quickBuildSkillMultipliers(skillmultipliers:Object, operationType:String):String{
    if(!skillmultipliers) return "";
    var result = "";

    // 动态遍历所有技能，无需硬编码技能名称列表
    for (var skillName:String in skillmultipliers) {
      // 跳过内部属性
      if (ObjectUtil.isInternalKey(skillName)) continue;

      var multiplier = Number(skillmultipliers[skillName]);
      if (!isNaN(multiplier) && multiplier > 1) {
        var prefix = buildOperationPrefix(operationType);
        result += prefix + TooltipFormatter.color("【技能加成】", TooltipConstants.COL_HL);
        result += "使用" + skillName + "享受" + String((multiplier-1)*100) + TooltipConstants.SUF_PERCENT + "锋利度增益";
        result += TooltipFormatter.br();
      }
    }
    return result;
  }

  // === 快速打印伤害类型和破击类型 ===
  public static function quickBuildDamageType(buf:Array, data:Object):Void{
    if(!data.damagetype) return;

    if(data.damagetype == "魔法" && data.magictype){
      TooltipFormatter.colorLine(buf, TooltipConstants.COL_DMG, "伤害属性：" + data.magictype);
    }else if(data.damagetype == "破击" && data.magictype){
      if(MagicDamageTypes.isMagicDamageType(data.magictype))
        TooltipFormatter.colorLine(buf, TooltipConstants.COL_BREAK_LIGHT, "附加伤害：" + data.magictype);
      else
        TooltipFormatter.colorLine(buf, TooltipConstants.COL_BREAK_MAIN, "破击类型：" + data.magictype);
    }else{
      TooltipFormatter.colorLine(buf, TooltipConstants.COL_DMG, "伤害类型：" + (data.damagetype == "魔法" ? "能量" : data.damagetype));
    }
  }


  public static function getSortedAttrList(data:Object):Array{
    var list:Array = [];
    var priorities = TooltipConstants.PROPERTY_PRIORITIES;
    for(var key in data){
      if(!isNaN(priorities[key])) list.push(key);
    }
    var sortFunc = function(keyA, keyB){
      return priorities[keyA] - priorities[keyB];
    }
    return InsertionSort.sort(list, sortFunc);
  }



}