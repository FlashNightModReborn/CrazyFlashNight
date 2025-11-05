import org.flashNight.arki.item.*;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipDataSelector;
import org.flashNight.gesh.tooltip.builder.EquipmentStatsComposer;
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

  // === 生成刀技乘数（重构后：从XML配置读取，显示插件影响） ===
  public static function buildBladeSkillMultipliers(item:Object, baseItem:BaseItem):Array {
    var result = [];
    if (item.use !== "刀") return result;

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

    var data = TooltipDataSelector.getEquipmentData(item, value.tier);
    var equipData = upgradeLevel > 1 || value.mods ? baseItem.getData().data : null;

    // 委托给新的编排器（保持完全相同的输出）
    return EquipmentStatsComposer.compose(baseItem, item, data, equipData);

    /* 原实现已迁移到 builder 子模块
    var result = [];

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

        // 处理弹夹容量显示（考虑magazineCapacity乘数）
        if (capacity > 0) {
          if (magazineCapacity > 1) {
            // 有magazineCapacity乘数（点射武器）
            // 需要临时创建对象来正确显示乘数后的容量
            var tempData = {capacity: data.capacity * magazineCapacity};
            var tempEquipData = equipData ? {capacity: equipData.capacity * magazineCapacity} : null;
            TooltipFormatter.upgradeLine(result, tempData, tempEquipData, "capacity", "弹夹容量", null);
          } else {
            // 普通武器，直接使用upgradeLine
            TooltipFormatter.upgradeLine(result, data, equipData, "capacity", "弹夹容量", null);
          }
        }

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

    // 使用最终计算后的数据显示暴击（如果有mod或强化，则使用equipData）
    var critData = equipData ? equipData : data;
    if (critData.criticalhit) {
      result.push(quickBuildCriticalHit(critData.criticalhit));
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

    // 使用最终计算后的数据显示伤害类型（如果有mod或强化，则使用equipData）
    var finalData = equipData ? equipData : data;
    quickBuildDamageType(result, finalData);

    // 使用最终计算后的数据显示魔法抗性（如果有mod或强化，则使用equipData）
    // 收集所有需要显示的抗性类型（基础数据和最终数据的并集）
    if (finalData.magicdefence || data.magicdefence) {
      var resistanceTypes = {};
      if (data.magicdefence) {
        for (var key in data.magicdefence) {
          if (ObjectUtil.isInternalKey(key)) continue;
          resistanceTypes[key] = true;
        }
      }
      if (finalData.magicdefence) {
        for (var key in finalData.magicdefence) {
          if (ObjectUtil.isInternalKey(key)) continue;
          resistanceTypes[key] = true;
        }
      }

      // 对每个抗性类型显示变化前后的值（类似 upgradeLine 的逻辑）
      for (var key in resistanceTypes) {
        var baseResist = (data.magicdefence && data.magicdefence[key]) ? data.magicdefence[key] : null;
        var finalResist = (finalData.magicdefence && finalData.magicdefence[key]) ? finalData.magicdefence[key] : null;

        // 如果两者都没有值或都为0，跳过
        if ((baseResist == null || Number(baseResist) == 0) && (finalResist == null || Number(finalResist) == 0)) continue;

        var displayName = (key == "基础" ? "能量" : key);
        var label = displayName + "抗性";

        // 若没有实际装备数值或实际数值与原始数值相等，则打印原始数值
        if (!equipData || finalResist == baseResist || finalResist == null) {
          if (baseResist != null && Number(baseResist) != 0) {
            result.push(label, "：", baseResist, "<BR>");
          }
        } else {
          // 有变化，显示变化前后的值
          if (finalResist != null && Number(finalResist) != 0) {
            result.push(label, "：<FONT COLOR='", TooltipConstants.COL_HL, "'>", finalResist, "</FONT>");
            if (baseResist == null) baseResist = 0;
            // 若属性为数字，则额外打印增幅值
            var baseNum = Number(baseResist);
            var finalNum = Number(finalResist);
            if (isNaN(finalNum) || isNaN(baseNum)) {
              result.push(" (覆盖", baseResist, ")<BR>");
            } else {
              var enhance = finalNum - baseNum;
              var sign:String;
              if (enhance < 0) {
                enhance = -enhance;
                sign = " - ";
              } else {
                sign = " + ";
              }
              result.push(" (", baseResist, sign, enhance, ")<BR>");
            }
          }
        }
      }
    }

    TooltipFormatter.upgradeLine(result, data, equipData, "defence", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "hp", null, null);
    TooltipFormatter.upgradeLine(result, data, equipData, "mp", null, null);

    if (item.actiontype !== undefined) result.push("动作：", item.actiontype, "<BR>");

    if(value.mods.length > 0){
      result.push("<font color='" + TooltipConstants.COL_HL + "'>已安装", value.mods.length, "个配件：</font><BR>");
      for(var i = 0; i < value.mods.length; i++){
        var modName = value.mods[i];
        var modInfo = EquipmentUtil.modDict[modName];
        if(modInfo && modInfo.tagValue){
          result.push("  • ", modName, " <font color='" + TooltipConstants.COL_INFO + "'>[", modInfo.tagValue, "]</font><BR>");
        }else{
          result.push("  • ", modName, "<BR>");
        }
      }
    }

    return result;
    */
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
    if(percentage){
      var sortedList = getSortedAttrList(percentage);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        TooltipFormatter.statLine(result, "multiply", key, percentage[key], null);
      }
    }
    if(flat){
      var sortedList = getSortedAttrList(flat);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        TooltipFormatter.statLine(result, "add", key, flat[key], null);
      }
    }
    if(override){
      var sortedList = getSortedAttrList(override);
      for(var i = 0; i < sortedList.length; i++){
        var key = sortedList[i];
        // 跳过 damagetype 和 magictype，这些需要组合显示
        if(key == "damagetype" || key == "magictype") continue;
        TooltipFormatter.statLine(result, "override", key, override[key], null);
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
    // 查找criticalhit、magicdefence和skillmultipliers（从override）
    if(override && override.criticalhit){
      result.push(quickBuildCriticalHit(override.criticalhit));
    }
    if(override && override.magicdefence){
      result.push(quickBuildMagicDefence(override.magicdefence, "覆盖"));
    }
    if(override && override.skillmultipliers){
      result.push(quickBuildSkillMultipliers(override.skillmultipliers, "覆盖"));
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