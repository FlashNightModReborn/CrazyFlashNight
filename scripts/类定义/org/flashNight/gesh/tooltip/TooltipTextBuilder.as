import org.flashNight.arki.item.*;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.ItemUseTypes;
import org.flashNight.gesh.tooltip.TooltipDataSelector;
import org.flashNight.gesh.tooltip.ItemObtainIndex;
import org.flashNight.gesh.tooltip.builder.EquipmentStatsComposer;
import org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder;
import org.flashNight.gesh.tooltip.builder.SlayEffectBuilder;
import org.flashNight.gesh.tooltip.builder.UseSwitchStatsBuilder;
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
        TooltipFormatter.color(TooltipConstants.TIP_INFO_LOCATION, TooltipConstants.COL_INFO),
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
        result.push(TooltipConstants.LBL_SYNTHESIS, "：<BR>");
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

  // === 生成获取方式信息 ===
  /**
   * 构建物品获取方式文本
   * 显示物品的合成来源、NPC商店、K点商店等获取渠道
   *
   * @param itemName 物品名称
   * @return Array<String> HTML文本片段数组，若无来源返回空数组（不显示区块）
   */
  public static function buildObtainMethods(itemName:String):Array {
    var result:Array = [];

    var index:ItemObtainIndex = ItemObtainIndex.getInstance();
    if (!index.isIndexBuilt()) return result;

    var methods:Object = index.getObtainMethods(itemName);
    var hasCrafting:Boolean = methods.crafting && methods.crafting.length > 0;
    var hasShops:Boolean = methods.shops && methods.shops.length > 0;
    var hasKshop:Boolean = methods.kshop && methods.kshop.length > 0;

    // 无任何来源时返回空数组，不显示该区块
    if (!hasCrafting && !hasShops && !hasKshop) return result;

    // 标题
    result.push(TooltipFormatter.br());
    result.push("<FONT COLOR='" + TooltipConstants.COL_INFO + "'>");
    result.push(TooltipConstants.LBL_OBTAIN_METHODS);
    result.push("</FONT>");
    result.push(TooltipFormatter.br());

    // 1. 合成来源
    if (hasCrafting) {
      for (var i:Number = 0; i < methods.crafting.length; i++) {
        var craft:Object = methods.crafting[i];
        result.push("  <FONT COLOR='" + TooltipConstants.COL_CRAFT + "'>");
        result.push(TooltipConstants.TIP_OBTAIN_CRAFT);
        result.push("</FONT>");
        result.push(craft.category);
        // 显示费用
        if (craft.price > 0 || craft.kprice > 0) {
          result.push(" (");
          if (craft.price > 0) result.push("$" + craft.price);
          if (craft.price > 0 && craft.kprice > 0) result.push(" + ");
          if (craft.kprice > 0) result.push(craft.kprice + "K");
          result.push(")");
        }
        result.push(TooltipFormatter.br());
      }
    }

    // 2. NPC商店来源
    if (hasShops) {
      result.push("  <FONT COLOR='" + TooltipConstants.COL_SHOP + "'>");
      result.push(TooltipConstants.TIP_OBTAIN_SHOP);
      result.push("</FONT>");
      result.push(methods.shops.join("、"));
      result.push(TooltipFormatter.br());
    }

    // 3. K点商店来源
    if (hasKshop) {
      for (var j:Number = 0; j < methods.kshop.length; j++) {
        var kitem:Object = methods.kshop[j];
        result.push("  <FONT COLOR='" + TooltipConstants.COL_KSHOP + "'>");
        result.push(TooltipConstants.TIP_OBTAIN_KSHOP);
        result.push("</FONT>");
        result.push(kitem.type + " (" + kitem.price + "K)");
        result.push(TooltipFormatter.br());
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
            TooltipFormatter.color(TooltipConstants.LBL_SKILL_BONUS, TooltipConstants.COL_HL),
            TooltipConstants.TIP_USE, skillName, TooltipConstants.TIP_ENJOY, String((baseNum-1)*100), TooltipConstants.SUF_PERCENT, TooltipConstants.TIP_SHARPNESS_BONUS,
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
          TooltipFormatter.color(TooltipConstants.LBL_SKILL_BONUS, TooltipConstants.COL_HL),
          TooltipConstants.TIP_USE, skillName, TooltipConstants.TIP_ENJOY, "<FONT COLOR='", TooltipConstants.COL_HL, "'>", String(finalPercent), TooltipConstants.SUF_PERCENT, "</FONT>", TooltipConstants.TIP_SHARPNESS_BONUS
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
      result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_ACTIVE_SKILL + "</font>", skill.description, "<BR><font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_SKILL_INFO + "</font>");
      if (skill.information) {
        result.push(skill.information);
      } else {
        var cooldown = skill.cd/1000;
        result.push(TooltipConstants.LBL_COOLDOWN, cooldown, TooltipConstants.SUF_SECOND);
        if (skill.hp && skill.hp != 0) result.push("，", TooltipConstants.LBL_COST, skill.hp, TooltipConstants.SUF_HP);
        if (skill.mp && skill.mp != 0) result.push("，", TooltipConstants.LBL_COST, skill.mp, TooltipConstants.SUF_MP);
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
    if (lc && lc.description) result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_AFFIX_INFO + "</font>", lc.description, "<BR>");
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
      result.push(TooltipConstants.LBL_WEAPON_TYPE, "：", item.weapontype, "<BR>");
    }
    result.push("$", item.price, "<BR>");
    if (upgradeLevel > 1 && (item.type == ItemUseTypes.TYPE_WEAPON || item.type == ItemUseTypes.TYPE_ARMOR)) {
      // 获取强化等级对应的倍率并计算增幅百分比
      var levelMultiplier:Number = EquipmentUtil.levelStatList[upgradeLevel];
      if (levelMultiplier && !isNaN(levelMultiplier)) {
        var enhancement:Number = Math.round((levelMultiplier - 1) * 100);
        result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_UPGRADE_LEVEL + "：", upgradeLevel, " (+", enhancement, "%)</FONT><BR>");
      } else {
        result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_UPGRADE_LEVEL + "：", upgradeLevel, "</FONT><BR>");
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
      if (quantity > 1) result.push(TooltipConstants.LBL_QUANTITY, "：", quantity, "<BR>");
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
    if (data.friend == TooltipConstants.TXT_GROUP) result.push("<FONT COLOR='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.TIP_ALLY_EFFECT + "</FONT><BR>");
    if (!!(data.poison)) {
      var poisonValue:Number = Number(data.poison);
      if (isNaN(poisonValue)) poisonValue = 0;
      result.push("<FONT COLOR='" + TooltipConstants.COL_POISON + "'>" + TooltipConstants.LBL_POISON + "：", poisonValue, "</FONT><BR>");
    }
    if (!!(data.clean)) result.push(TooltipConstants.LBL_CLEAN, "：", (isNaN(data.clean) ? 0 : data.clean), "<BR>");

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
      TooltipFormatter.enhanceLine(result, "multiply", data, "power", stat, TooltipConstants.LBL_SHARPNESS);
    }else if(ItemUseTypes.isGun(itemData.use)){
      TooltipFormatter.enhanceLine(result, "multiply", data, "power", stat, TooltipConstants.LBL_BULLET_POWER);
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
        result.push(TooltipConstants.TIP_NO_BONUS_DATA);
        return result;
      }
    }
    result.push(TooltipConstants.TIP_EQUIP_BONUS_PREFIX, "<B>", equipDisplayName, "</B>", TooltipConstants.TIP_EQUIP_BONUS_SUFFIX, "：<BR>");

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

    // 【方案A实施】改进配件查找逻辑，使用O(1)的反向索引
    // 1. 先尝试直接查找（配件的name属性）
    var modData = EquipmentUtil.modDict[itemName];

    // 2. 如果找不到，尝试通过displayname反向索引查找（O(1)）
    if(!modData) {
        modData = ModRegistry.getModDataByDisplayName(itemName);
        if(modData && EquipmentUtil.DEBUG_MODE) {
            _root.服务器.发布服务器消息("[buildModStat] 通过displayname索引找到配件: '" + itemName + "'");
        }
    }

    // 3. 如果还找不到，尝试去除空格后再查找
    if(!modData) {
        var trimmedName:String = StringUtils.trim(itemName);
        if(trimmedName != itemName) {
            // 先尝试name
            modData = EquipmentUtil.modDict[trimmedName];
            // 再尝试displayname
            if(!modData) {
                modData = ModRegistry.getModDataByDisplayName(trimmedName);
            }
            if(modData && EquipmentUtil.DEBUG_MODE) {
                _root.服务器.发布服务器消息("[buildModStat] 通过trim后找到配件: '" + trimmedName + "'");
            }
        }
    }

    // 调试输出
    if(EquipmentUtil.DEBUG_MODE) {
        _root.服务器.发布服务器消息("[buildModStat] itemName='" + itemName + "', 找到配件=" + (modData != undefined));
    }

    if(!modData) return result;
    result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_MOD_INFO + "</font><BR>");
    result.push(TooltipConstants.LBL_MOD_USE_TYPE, "：", modData.use, "<BR>");
    // 显示插件的tag分类
    if(modData.tagValue){
      result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.LBL_MOD_SLOT + "：</font>", modData.tagValue, "<BR>");
    }
    if(modData.weapontype){
      result.push(TooltipConstants.LBL_MOD_WEAPON_TYPE, "：", modData.weapontype, "<BR>");
    }
    // 显示排除的武器类型（黑名单）
    if(modData.excludeWeapontype){
      result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_MOD_EXCLUDE_WEAPON_TYPE + "：</font>", modData.excludeWeapontype, "<BR>");
    }

    // 显示提供的结构标签
    if(modData.provideTagDict){
      var provideTags = [];
      for(var pTag in modData.provideTagDict){
        if (ObjectUtil.isInternalKey(pTag)) continue;
        provideTags.push(pTag);
      }
      if(provideTags.length > 0){
        result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_PROVIDE_TAGS + "：</font>", provideTags.join(", "), "<BR>");
      }
    }

    // 显示前置需求标签
    if(modData.requireTagDict){
      var requireTags = [];
      for(var rTag in modData.requireTagDict){
        if (ObjectUtil.isInternalKey(rTag)) continue;
        requireTags.push(rTag);
      }
      if(requireTags.length > 0){
        result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_REQUIRE_TAGS + "：</font>", requireTags.join(", "), "<BR>");
      }
    }

    var stats = modData.stats;

    // 使用 UseSwitchStatsBuilder.buildStatBlock 统一处理顶层 stats 的所有属性
    UseSwitchStatsBuilder.buildStatBlock(result, stats, "");

    // 使用 UseSwitchStatsBuilder 显示 useSwitch 条件效果（详细版）
    UseSwitchStatsBuilder.buildDetailed(result, stats);

    if(modData.skill){
      result = result.concat(buildSkillInfo(modData.skill));
    }

    // 读取描述（如果有）
    if(typeof modData.description === "string"){
      result.push(modData.description.split("\r\n").join(TooltipFormatter.br()), TooltipFormatter.br());
    }
    return result;
  }

  /**
   * 构建装备的固有标签和禁止标签信息
   * @param item 物品原始数据对象
   * @return 标签信息的 HTML 数组
   */
  public static function buildEquipmentTagInfo(item:Object):Array {
    var result:Array = [];

    // 显示固有结构标签 (inherentTags)
    if(item.inherentTags){
      var inherentArr:Array = item.inherentTags.split(",");
      var inherentTags:Array = [];
      for(var i:Number = 0; i < inherentArr.length; i++){
        var tag:String = StringUtils.trim(inherentArr[i]);
        if(tag.length > 0){
          inherentTags.push(tag);
        }
      }
      if(inherentTags.length > 0){
        result.push("<font color='" + TooltipConstants.COL_ENHANCE + "'>" + TooltipConstants.LBL_INHERENT_TAGS + "：</font>", inherentTags.join(", "), "<BR>");
      }
    }

    // 显示禁止挂载标签 (blockedTags)
    if(item.blockedTags){
      var blockedArr:Array = item.blockedTags.split(",");
      var blockedTags:Array = [];
      for(var j:Number = 0; j < blockedArr.length; j++){
        var blocked:String = StringUtils.trim(blockedArr[j]);
        if(blocked.length > 0){
          blockedTags.push(blocked);
        }
      }
      if(blockedTags.length > 0){
        result.push("<font color='" + TooltipConstants.COL_ROUT + "'>" + TooltipConstants.LBL_BLOCKED_TAGS + "：</font>", blockedTags.join(", "), "<BR>");
      }
    }

    return result;
  }

  // === 快速打印暴击数据 ===
  public static function quickBuildCriticalHit(criticalhit):String{
    if (!isNaN(Number(criticalhit)))
      return "<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>" + TooltipConstants.LBL_CRIT + "：</FONT><FONT COLOR='" + TooltipConstants.COL_CRIT + "'>" + criticalhit + TooltipConstants.SUF_PERCENT + TooltipConstants.TIP_CRIT_CHANCE + "</FONT><BR>";
    else if (criticalhit === TooltipConstants.TIP_CRIT_FULL_HP)
        return "<FONT COLOR='" + TooltipConstants.COL_CRIT + "'>" + TooltipConstants.LBL_CRIT + "：" + TooltipConstants.TIP_CRIT_FULL_HP_DESC + "</FONT><BR>";
    return "";
  }

  // === 快速打印魔法抗性数据 ===
  public static function quickBuildMagicDefence(magicdefence:Object, operationType:String):String{
    var mdList = [];
    for(var key in magicdefence) {
      if (ObjectUtil.isInternalKey(key)) continue; // 跳过内部字段（如 __dictUID）
      var mdName = (key === TooltipConstants.TXT_BASE ? TooltipConstants.TXT_ENERGY : key);
      var value = magicdefence[key];
      if (value) mdList.push(mdName + ": " + value);
    }
    if(mdList.length > 0) {
      var prefix = buildOperationPrefix(operationType);
      return prefix + TooltipConstants.SUF_RESISTANCE + " -> " + mdList.join(", ") + "<BR>";
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
        result += prefix + TooltipFormatter.color(TooltipConstants.LBL_SKILL_BONUS, TooltipConstants.COL_HL);
        result += TooltipConstants.TIP_USE + skillName + TooltipConstants.TIP_ENJOY + String((multiplier-1)*100) + TooltipConstants.SUF_PERCENT + TooltipConstants.TIP_SHARPNESS_BONUS;
        result += TooltipFormatter.br();
      }
    }
    return result;
  }

  // === 快速打印伤害类型和破击类型 ===
  public static function quickBuildDamageType(buf:Array, data:Object):Void{
    if(!data.damagetype) return;

    if(data.damagetype == TooltipConstants.TXT_MAGIC && data.magictype){
      TooltipFormatter.colorLine(buf, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_ATTR + "：" + data.magictype);
    }else if(data.damagetype == TooltipConstants.TXT_BREAK && data.magictype){
      if(MagicDamageTypes.isMagicDamageType(data.magictype))
        TooltipFormatter.colorLine(buf, TooltipConstants.COL_BREAK_LIGHT, TooltipConstants.LBL_EXTRA_DAMAGE + "：" + data.magictype);
      else
        TooltipFormatter.colorLine(buf, TooltipConstants.COL_BREAK_MAIN, TooltipConstants.LBL_BREAK_TYPE + "：" + data.magictype);
    }else{
      TooltipFormatter.colorLine(buf, TooltipConstants.COL_DMG, TooltipConstants.LBL_DAMAGE_TYPE + "：" + (data.damagetype == TooltipConstants.TXT_MAGIC ? TooltipConstants.TXT_ENERGY : data.damagetype));
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
