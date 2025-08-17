import org.flashNight.arki.item.*;
import org.flashNight.gesh.array.*;
import org.flashNight.gesh.string.*;

// =========================
// 阶段3：常量与样式模块化
// =========================


// =========================
// 阶段1：文本拼接纯函数化  
// =========================


/**
 * 文本组合模块
 * 统一组合各种文本段落，生成完整的注释内容
 */
_root.注释组合 = {
  // 基础段：聚合描述/剧情/合成/刀技/战技/生命周期
  基础段: function(item:Object):Array {
    var segments = [];
    segments = segments.concat(
      TooltipTextBuilder.buildBasicDescription(item),
      TooltipTextBuilder.buildStoryTip(item), 
      TooltipTextBuilder.buildSynthesisMaterials(item),
      TooltipTextBuilder.buildBladeSkillMultipliers(item),
      TooltipTextBuilder.buildSkillInfo(item.skill),
      TooltipTextBuilder.buildLifecycleInfo(item.lifecycle)
    );
    return segments;
  },
  
  // 装备段：直接调用现有的装备属性块生成
  装备段: function(item:Object, tier:String, lvl:Number):Array {
    return TooltipTextBuilder.buildEquipmentStats(item, tier, lvl);
  },
  
  // 简介头：直接调用现有的简介标题头生成
  简介头: function(item:Object, value:Object, lvl:Number):Array {
    return TooltipTextBuilder.buildIntroHeader(item, value, lvl);
  },
  
  // 生成物品全文：组合所有段落为完整HTML
  生成物品全文: function(item:Object, value:Object, lvl:Number):String {
    var allSegments = [];
    
    // 按顺序组合：简介头 + 装备段 + 基础段
    allSegments = allSegments.concat(
      this.简介头(item, value, lvl),
      this.装备段(item, value.tier, lvl),
      this.基础段(item)
    );
    
    return allSegments.join('');
  },
  
  // 生成物品描述文本：仅描述部分（用于主要注释）
  生成物品描述文本: function(item:Object):String {
    return this.基础段(item).join('');
  },
  
  // 生成简介面板内容：只包含简介头+装备段（修复左侧面板语义）
  生成简介面板内容: function(item:Object, value:Object, lvl:Number):String {
    var segments = [];
    segments = segments.concat(
      this.简介头(item, value, lvl),
      this.装备段(item, value.tier, lvl)
    );
    return segments.join('');
  }
};


/**
 * 物品图标注释主入口函数
 * @param name:String 物品名称
 * @param value:Object 物品数值对象，包含level、tier等属性
 */
_root.物品图标注释 = function(name, value) {
    var 强化等级 = value.level > 0 ? value.level : 1;

    var 物品数据 = ItemUtil.getItemData(name);
    // 阶段3：使用文本组合器统一生成
    var 完整文本 = _root.注释组合.生成物品描述文本(物品数据);
    var 计算宽度 = TooltipLayout.estimateWidth(完整文本);

    _root.注释结束(); // 保底清理

    // 调用注释函数，传递计算出的宽度和文本内容
    if(完整文本.length > 64) {
        _root.注释(计算宽度, 完整文本);
        _root.注释物品图标(true, name, value);
    } else {
        _root.注释物品图标(true, name, value, 完整文本);
        _root.注释框.文本框.htmlText = "";
        _root.注释框.文本框._visible = false;
        _root.注释框.背景._visible = false;
    }

};


/**
 * 技能栏技能图标注释
 * @param 对应数组号:Number 技能在主角技能表中的数组索引
 */
_root.技能栏技能图标注释 = function(对应数组号) {
    var 主角技能信息 = _root.主角技能表[对应数组号];
    var 技能名 = 主角技能信息[0];
    var 技能信息 = _root.技能表对象[技能名];

    var 是否装备或启用:String;
    if (技能信息.Equippable)
        是否装备或启用 = 主角技能信息[2] == true ? "<FONT COLOR='#66FF00'>已装备</FONT>" : "<FONT COLOR='#FFDDDD'>未装备</FONT>";
    else
        是否装备或启用 = 主角技能信息[4] == true ? "<FONT COLOR='#66FF00'>已启用</FONT>" : "<FONT COLOR='#FFDDDD'>未启用</FONT>";

    var 文本数据 = "<B>" + 技能信息.Name + "</B>";
    文本数据 += "<BR>" + 技能信息.Type + "   " + 是否装备或启用;
    文本数据 += "<BR>" + 技能信息.Description;
    文本数据 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
    文本数据 += "<BR>MP消耗：" + 技能信息.MP;
    文本数据 += "<BR>技能等级：" + 主角技能信息[1];
    // 文本数据 += "<BR>" + 是否装备或启用;

    var 计算宽度 = TooltipLayout.estimateWidth(文本数据, 160, 200);
    _root.注释(计算宽度, 文本数据);
};

/**
 * 学习界面技能图标注释
 * @param 对应数组号:Number 技能在技能表中的数组索引
 */
_root.学习界面技能图标注释 = function(对应数组号) {
    var 技能信息 = _root.技能表[对应数组号];

    var 文本数据 = "<B>" + 技能信息.Name + "</B>";
    文本数据 += "<BR>" + 技能信息.Type;
    文本数据 += "<BR>" + 技能信息.Description;
    文本数据 += "<BR>最高等级：" + 技能信息.MaxLevel;
    文本数据 += "<BR>解锁需要技能点数：" + 技能信息.UnlockSP;
    if (技能信息.MaxLevel > 1)
        文本数据 += "<BR>升级需要技能点数：" + 技能信息.UpgradeSP;
    文本数据 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
    文本数据 += "<BR>MP消耗：" + 技能信息.MP;
    文本数据 += "<BR>等级限制：" + 技能信息.UnlockLevel;

    var 计算宽度 = TooltipLayout.estimateWidth(文本数据, 160, 200);
    _root.注释(计算宽度, 文本数据);
};


/**
 * 注释物品图标显示控制函数
 * @param enable:Boolean 是否启用显示
 * @param name:String 物品名称
 * @param value:Object 物品数值对象
 * @param extraString:String 额外显示的文本（可选）
 */
_root.注释物品图标 = function(enable:Boolean, name:String, value:Object, extraString:String) {
    // 'target' MovieClip 作为在舞台上放置的占位符
    // 它在 Flash IDE 中的位置和大小，应决定图标最终的显示效果
    var target:MovieClip = _root.注释框.物品图标定位;
    var background:MovieClip = _root.注释框.简介背景;
    var text:MovieClip = _root.注释框.简介文本框;

    if (enable) {

        target._visible = true;
        text._visible = true;
        background._visible = true;

        var data:Object = ItemUtil.getItemData(name);
        var level:Number = value.level > 0 ? value.level : 1;
        
        var tips:MovieClip = _root.注释框;
        
        // 使用新的布局模块处理简介布局
        var layout = TooltipLayout.applyIntroLayout(data.type, target, background, text);
        var stringWidth = layout.width;
        var backgroundHeightOffset = layout.heightOffset;

        // 阶段3：使用文本组合器生成简介面板内容（只包含简介头+装备段）
        var introduction:String = _root.注释组合.生成简介面板内容(data, value, level);

        if(extraString) introduction += "<BR>" + extraString;

        _root.注释(stringWidth, introduction, "简介")

        var iconString:String = "图标-" + data.icon;

        if(target.icon) target.icon.removeMovieClip();

        // 从库中将图标附加到 target MovieClip 上
        var icon:MovieClip = target.attachMovie(iconString, "icon", target.getNextHighestDepth());
        icon._xscale = icon._yscale = 150;
        icon._x = icon._y = 19;
        
        // 层级修正：确保图标在简介背景之上，避免被遮挡
        if (tips.简介背景) {
          var iconDepth = target.getDepth();
          var bgDepth = tips.简介背景.getDepth();
          if (iconDepth <= bgDepth) {
            // 将图标容器提升到背景之上
            target.swapDepths(bgDepth + 1);
          }
        }

        background._height = text._height + backgroundHeightOffset;
    } else {
        // 清理动态附加的图标
        if (target.icon) {
            target.icon.removeMovieClip();
        }

        target._visible = false;
        text._visible = false;
        background._visible = false;
    }
}


/**
 * 注释显示函数
 * @param 宽度:Number 注释框宽度
 * @param 内容:String 注释内容HTML文本
 * @param 框体:String 框体类型（可选，默认为主框体）
 */
_root.注释 = function(宽度, 内容, 框体) {
    if(!框体) {
        框体 = "";
        _root.注释框.文本框._visible = true;
        _root.注释框.背景._visible = true;
    }

    _root.注释框.文本框._y = 0;
    _root.注释框.背景._y = 0;

    var tips:MovieClip = _root.注释框;
    var target:MovieClip = tips[框体 + "文本框"];
    var background:MovieClip = tips[框体 + "背景"]

    tips._visible = true;
    target.htmlText = 内容;
    target._width = 宽度;

    background._width = target._width;
    background._height = target.textHeight + 10;
    target._height = target.textHeight + 10;

    // 使用新的布局模块处理注释框定位
    TooltipLayout.positionTooltip(tips, background, _root._xmouse, _root._ymouse);
};

/**
 * 注释结束函数，清理所有注释相关的显示元素
 */
_root.注释结束 = function() {
    _root.注释框._visible = false;
    _root.注释物品图标(false);
    
    // 清理文本框内容
    _root.注释框.文本框.htmlText = "";
    _root.注释框.文本框._visible = false;
    _root.注释框.简介文本框.htmlText = "";
    _root.注释框.简介文本框._visible = false;
    
    // 清理背景可见性
    _root.注释框.背景._visible = false;
    _root.注释框.简介背景._visible = false;
    
    // 清理物品图标定位和图标
    _root.注释框.物品图标定位._visible = false;
    if (_root.注释框.物品图标定位.icon) {
        _root.注释框.物品图标定位.icon.removeMovieClip();
    }
};

_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
    _root.注释结束();
}, null); 

