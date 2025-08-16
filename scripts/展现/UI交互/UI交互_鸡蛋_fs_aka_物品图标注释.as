import org.flashNight.arki.item.*;
import org.flashNight.gesh.array.*;

// =========================
// 阶段3：常量与样式模块化
// =========================

/**
 * @deprecated 请使用 org.flashNight.gesh.string.TooltipConstants
 * 兼容性包装：注释常量
 */
_root.注释常量 = org.flashNight.gesh.string.TooltipConstants;

/**
 * @deprecated 请使用 org.flashNight.gesh.string.TooltipFormatter  
 * 兼容性包装：注释样式格式化函数
 */
_root.注释样式 = {
  bold: function(str:String):String {
    return org.flashNight.gesh.string.TooltipFormatter.bold(str);
  },
  
  color: function(str:String, hex:String):String {
    return org.flashNight.gesh.string.TooltipFormatter.color(str, hex);
  },
  
  br: function():String {
    return org.flashNight.gesh.string.TooltipFormatter.br();
  },
  
  kv: function(label:String, val, suffix:String):String {
    return org.flashNight.gesh.string.TooltipFormatter.kv(label, val, suffix);
  },
  
  numLine: function(buf:Array, label:String, val, suffix:String):Void {
    org.flashNight.gesh.string.TooltipFormatter.numLine(buf, label, val, suffix);
  },
  
  upgradeLine: function(buf:Array, label:String, base:Number, lvl:Number):Void {
    org.flashNight.gesh.string.TooltipFormatter.upgradeLine(buf, label, base, lvl, _root.注释常量.COL_HL);
  },
  
  colorLine: function(buf:Array, color:String, text:String):Void {
    org.flashNight.gesh.string.TooltipFormatter.colorLine(buf, color, text);
  }
};

// =========================
// 阶段1：文本拼接纯函数化  
// =========================

/**
 * 注释文本生成模块
 * 包含所有文本拼接的纯函数，用于生成各种类型的注释内容
 */
_root.注释文本 = {
  生成基础描述: function(item:Object):Array {
    var a = [];
    if (item.description) a.push(item.description.split("\r\n").join("<BR>"), "<BR>");
    return a;
  },
  生成剧情碎片提示: function(item:Object):Array {
    var a = [];
    if (item.use == "情报") a.push("<FONT COLOR='#FFCC00'>详细信息可在物品栏的情报界面查阅</FONT><BR>");
    return a;
  },
  生成合成材料: function(item:Object):Array {
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
  },
  生成刀技乘数: function(item:Object):Array {
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
  },
  生成战技信息: function(skill:Object):Array {
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
  },
  生成生命周期: function(lc:Object):Array {
    var a = [];
    if (lc && lc.description) a.push("<font color='#FFCC00'>【词条信息】</font>", lc.description, "<BR>");
    return a;
  },
  生成简介标题头: function(item:Object, value:Object, 强化等级:Number):Array {
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
};

/**
 * 数据选择器模块
 * 用于根据装备阶级选择正确的数据源
 */
_root.注释选择 = {
  取装备数据: function(item:Object, tier:String):Object {
    if (tier == null) return item.data;
    switch (tier) {
      case "二阶": return item.data_2;
      case "三阶": return item.data_3;
      case "四阶": return item.data_4;
      case "墨冰": return item.data_ice;
      case "狱火": return item.data_fire;
      default: return item.data;
    }
  }
};

/**
 * 布局模块
 * 处理宽度估算、简介布局计算和注释框定位
 */
_root.注释布局 = {
  // 估算文本宽度：基于字符数的粗估算法
  估算宽度: function(html:String, minW:Number, maxW:Number):Number {
    if (minW === undefined) minW = _root.注释常量.MIN_W;
    if (maxW === undefined) maxW = _root.注释常量.MAX_W;
    
    var 字数 = html.length;
    var 估算宽度 = 字数 * _root.注释常量.CHAR_AVG_WIDTH;
    return Math.max(minW, Math.min(估算宽度, maxW));
  },
  
  // 应用简介布局：处理武器/防具 vs 其他物品的布局差异
  应用简介布局: function(itemType:String, target:MovieClip, background:MovieClip, text:MovieClip):Object {
    var 常量 = _root.注释常量;
    var stringWidth:Number;
    var backgroundHeightOffset:Number;
    
    switch(itemType) {
      case "武器":
      case "防具":
        stringWidth = 常量.BASE_NUM;
        background._width = 常量.BASE_NUM;
        background._x = -常量.BASE_NUM;
        target._x = -常量.BASE_NUM + 常量.BASE_OFFSET;
        target._xscale = target._yscale = 常量.BASE_SCALE;
        text._x = -常量.BASE_NUM;  // 使用常量替换魔法数
        text._y = 210;
        backgroundHeightOffset = 常量.BASE_NUM + 常量.BG_HEIGHT_OFFSET;
        break;
      default:
        var scaledWidth = 常量.BASE_NUM * 常量.RATE;
        stringWidth = scaledWidth;
        background._width = scaledWidth;
        background._x = -scaledWidth;
        target._x = -scaledWidth + 常量.BASE_OFFSET * 常量.RATE;
        target._xscale = target._yscale = 常量.BASE_SCALE * 常量.RATE;
        text._x = -scaledWidth;
        text._y = 10 - text._x;
        backgroundHeightOffset = 常量.BG_HEIGHT_OFFSET + 常量.RATE * 常量.BASE_NUM;
        break;
    }
    
    return { width: stringWidth, heightOffset: backgroundHeightOffset };
  },
  
  // 定位注释框：处理边界检测和左右背景对齐
  定位注释框: function(tips:MovieClip, background:MovieClip, mouseX:Number, mouseY:Number):Void {
    var 简介背景:MovieClip = tips.简介背景;
    var 右背景:MovieClip = tips.背景;
    
    var isAbbr:Boolean = !简介背景._visible;
    
    if (isAbbr) {
      // 简介背景隐藏时的定位逻辑
      tips._x = Math.min(Stage.width - background._width, Math.max(0, mouseX - background._width));
      tips._y = Math.min(Stage.height - background._height, Math.max(0, mouseY - background._height - 20));
    } else {
      if (右背景._visible) {
        // 计算鼠标的理想定位点（将注释框的右边缘对齐到鼠标指针）
        var desiredX:Number = mouseX - 右背景._width;
        
        // 计算允许的最小X值和最大X值
        var minX:Number = 简介背景._width;
        var maxX:Number = Stage.width - 右背景._width;
        
        // Y轴定位逻辑
        tips._y = Math.min(Stage.height - tips._height, Math.max(0, mouseY - tips._height - 20));
        var rightBottomHeight:Number = tips._y + 右背景._height;
        
        var offset:Number = mouseY - rightBottomHeight - 20;
        if (offset > 0) {
          tips.文本框._y = offset;
          tips.背景._y = offset;
        } else {
          var icon:MovieClip = tips.物品图标定位;
          右背景._height = Math.max(tips.文本框.textHeight, icon._height) + 10;
        }
        
        tips._x = Math.max(minX, Math.min(desiredX, maxX));
      } else {
        // 只有左背景可见时
        tips._x = Math.min(Stage.width - 简介背景._width, Math.max(0, mouseX - 简介背景._width)) + 简介背景._width;
        tips._y = Math.min(Stage.height - 简介背景._height, Math.max(0, mouseY - 简介背景._height - 20));
        
        // 调整左背景高度以适配内容
        简介背景._height = tips.简介文本框.textHeight + 10;
      }
    }
  }
};

/**
 * 文本组合模块
 * 统一组合各种文本段落，生成完整的注释内容
 */
_root.注释组合 = {
  // 基础段：聚合描述/剧情/合成/刀技/战技/生命周期
  基础段: function(item:Object):Array {
    var segments = [];
    segments = segments.concat(
      _root.注释文本.生成基础描述(item),
      _root.注释文本.生成剧情碎片提示(item), 
      _root.注释文本.生成合成材料(item),
      _root.注释文本.生成刀技乘数(item),
      _root.注释文本.生成战技信息(item.skill),
      _root.注释文本.生成生命周期(item.lifecycle)
    );
    return segments;
  },
  
  // 装备段：直接调用现有的装备属性块生成
  装备段: function(item:Object, tier:String, lvl:Number):Array {
    return _root.注释文本.生成装备属性块(item, tier, lvl);
  },
  
  // 简介头：直接调用现有的简介标题头生成
  简介头: function(item:Object, value:Object, lvl:Number):Array {
    return _root.注释文本.生成简介标题头(item, value, lvl);
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
 * 兼容别名模块
 * 保持向后兼容，内部转调新的样式模块
 */
_root.注释行 = {
  基础加强化: function(buf:Array, 标题:String, 基础:Number, 等级:Number):Void {
    _root.注释样式.upgradeLine(buf, 标题, 基础, 等级);
  },
  纯数值行: function(buf:Array, 标题:String, 值, 后缀:String):Void {
    _root.注释样式.numLine(buf, 标题, 值, 后缀);
  },
  彩色行: function(buf:Array, 颜色:String, 文本:String):Void {
    _root.注释样式.colorLine(buf, 颜色, 文本);
  }
};


_root.注释文本.生成装备属性块 = function(item:Object, tier:String, 等级:Number):Array {
  if (等级 == undefined || isNaN(等级) || 等级 < 1) 等级 = 1;
  var a = [];
  var d = _root.注释选择.取装备数据(item, tier);

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

  _root.注释行.基础加强化(a, "内力加成", d.force, 等级);
  _root.注释行.基础加强化(a, "伤害加成", d.damage, 等级);
  _root.注释行.基础加强化(a, "空手加成", d.punch, 等级);
  _root.注释行.基础加强化(a, "冷兵器加成", d.knifepower, 等级);
  _root.注释行.基础加强化(a, "枪械加成", d.gunpower, 等级);

  if (d.criticalhit !== undefined) {
    if (!isNaN(Number(d.criticalhit))) a.push("<FONT COLOR='#DD4455'>暴击：</FONT><FONT COLOR='#DD4455'>", d.criticalhit, "%概率造成1.5倍伤害</FONT><BR>");
    else if (d.criticalhit == "满血暴击") a.push("<FONT COLOR='#DD4455'>暴击：对满血敌人造成1.5倍伤害</FONT><BR>");
  }
  _root.注释行.纯数值行(a, "斩杀线", d.slay, "%血量");
  _root.注释行.纯数值行(a, "命中加成", d.accuracy, "%");
  _root.注释行.纯数值行(a, "挡拆加成", d.evasion, "%");
  _root.注释行.纯数值行(a, "韧性加成", d.toughness, "%");
  _root.注释行.纯数值行(a, "高危回避", d.lazymiss, "");
  if (d.poison) _root.注释行.彩色行(a, "#66dd00", "剧毒性：" + d.poison);
  if (d.vampirism) _root.注释行.彩色行(a, "#bb00aa", "吸血：" + d.vampirism + "%");
  if (d.rout) _root.注释行.彩色行(a, "#FF3333", "击溃：" + d.rout + "%");

  if (d.damagetype) {
    if (d.damagetype == "魔法" && d.magictype) {
      _root.注释行.彩色行(a, "#0099FF", "伤害属性：" + d.magictype);
    } else if (d.damagetype == "破击" && d.magictype) {
      if (ArrayUtil.includes(_root.敌人函数.魔法伤害种类, d.magictype))
        _root.注释行.彩色行(a, "#66bcf5", "附加伤害：" + d.magictype);
      else
        _root.注释行.彩色行(a, "#CC6600", "破击类型：" + d.magictype);
    } else {
      _root.注释行.彩色行(a, "#0099FF", "伤害类型：" + (d.damagetype == "魔法" ? "能量" : d.damagetype));
    }
  }

  if (d.magicdefence) {
    for (var k in d.magicdefence) {
      var 名 = (k == "基础" ? "能量" : k);
      var v = d.magicdefence[k];
      if (v != undefined && Number(v) != 0) a.push(名, "抗性：", v, "<BR>");
    }
  }

  _root.注释行.基础加强化(a, "防御", d.defence, 等级);
  if (d.hp) a.push("<FONT COLOR='#00FF00'>HP：", d.hp, "</FONT><FONT COLOR='#FFCC00'>(+", (_root.强化计算(d.hp, 等级)-d.hp), ")</FONT><BR>");
  if (d.mp) a.push("<FONT COLOR='#00FFFF'>MP：", d.mp, "</FONT><FONT COLOR='#FFCC00'>(+", (_root.强化计算(d.mp, 等级)-d.mp), ")</FONT><BR>");

  if (item.use == "药剂") {
    if (!isNaN(d.affecthp) && d.affecthp != 0) a.push("<FONT COLOR='#00FF00'>HP+", d.affecthp, "</FONT><BR>");
    if (!isNaN(d.affectmp) && d.affectmp != 0) a.push("<FONT COLOR='#00FFFF'>MP+", d.affectmp, "</FONT><BR>");
    if (d.friend == 1) a.push("<FONT COLOR='#FFCC00'>全体友方有效</FONT><BR>");
    else if (d.friend == "淬毒") a.push("<FONT COLOR='#66dd00'>剧毒性: ", (isNaN(d.poison)?0:d.poison), "</FONT><BR>");
    else if (d.friend == "净化") a.push("净化度: ", (isNaN(d.clean)?0:d.clean), "<BR>");
  }
  if (item.actiontype !== undefined) a.push("动作：", item.actiontype, "<BR>");

  return a;
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
    var 计算宽度 = _root.注释布局.估算宽度(完整文本);

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
 * 兼容包装：物品装备信息注释（已重构为模块化调用）
 * @param 文本数据:Array 输出文本数组
 * @param 物品数据:Object 物品数据对象
 * @param tier:String 装备阶级
 * @param 强化等级:Number 强化等级
 */
_root.物品装备信息注释 = function(文本数据:Array, 物品数据:Object, tier:String, 强化等级:Number):Void {
    var 块 = _root.注释文本.生成装备属性块(物品数据, tier, 强化等级);
    for (var i=0; i<块.length; i++) 文本数据.push(块[i]);
}


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

    var 计算宽度 = _root.注释布局.估算宽度(文本数据, 160, 200);
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

    var 计算宽度 = _root.注释布局.估算宽度(文本数据, 160, 200);
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
        var layout = _root.注释布局.应用简介布局(data.type, target, background, text);
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
    _root.注释布局.定位注释框(tips, background, _root._xmouse, _root._ymouse);
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

