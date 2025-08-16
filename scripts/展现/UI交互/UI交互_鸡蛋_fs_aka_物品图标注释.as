import org.flashNight.arki.item.*;
import org.flashNight.gesh.array.*;

// =========================
// 阶段3：常量与样式模块化
// =========================

// A. 常量模块：集中管理颜色、单位、布局参数
_root.注释常量 = {
  // 颜色常量
  COL_HL: "#FFCC00",        // 高亮黄色（强化等级、技能加成等）
  COL_HP: "#00FF00",        // HP绿色
  COL_MP: "#00FFFF",        // MP青色  
  COL_CRIT: "#DD4455",      // 暴击红色
  COL_POISON: "#66dd00",    // 剧毒绿色
  COL_VAMP: "#bb00aa",      // 吸血紫色
  COL_ROUT: "#FF3333",      // 击溃红色
  COL_DMG: "#0099FF",       // 伤害类型蓝色
  COL_BREAK_LIGHT: "#66bcf5", // 破击附加伤害淡蓝
  COL_BREAK_MAIN: "#CC6600",  // 破击类型橙色
  COL_INFO: "#FFCC00",      // 信息提示黄色
  
  // 单位/后缀常量
  SUF_PERCENT: "%",
  SUF_HP: "HP", 
  SUF_MP: "MP",
  SUF_BLOOD: "%血量",
  SUF_SECOND: "秒",
  SUF_FIRE_RATE: "发/秒",
  SUF_KG: "kg",
  
  // 布局参数常量
  BASE_NUM: 200,           // 基础宽度
  RATE: 0.6,              // 缩放比例（3/5）
  BASE_SCALE: 486.8,      // 基础缩放
  BASE_OFFSET: 7.5,       // 基础偏移
  MIN_W: 150,             // 最小宽度
  MAX_W: 500,             // 最大宽度
  TEXT_PAD: 10,           // 文本内边距
  BG_HEIGHT_OFFSET: 20,   // 背景高度偏移
  
  // 字符宽度估算
  CHAR_AVG_WIDTH: 0.5,    // 每字符平均宽度
  
  // 微调偏移（预留）
  OFFSET_X: 0,
  OFFSET_Y: 0
};

// B. 样式模块：文本包装器和格式化函数
_root.注释样式 = {
  // 文本包装器
  bold: function(str:String):String {
    return "<B>" + str + "</B>";
  },
  
  color: function(str:String, hex:String):String {
    return "<FONT COLOR='" + hex + "'>" + str + "</FONT>";
  },
  
  br: function():String {
    return "<BR>";
  },
  
  kv: function(label:String, val, suffix:String):String {
    if (suffix === undefined) suffix = "";
    return label + "：" + val + suffix;
  },
  
  // 数值行：统一数值行格式化（复用现有的空值过滤逻辑）
  numLine: function(buf:Array, label:String, val, suffix:String):Void {
    if (val === undefined || val === null) return;
    var n = Number(val);
    if (!isNaN(n)) {              // 数值（或可转为数值）
      if (n === 0) return;
      buf.push(label, "：", n, (suffix ? suffix : ""), "<BR>");
      return;
    }
    // 非数值：过滤空串/"0"/"null" 等情况
    if (val === "" || val == "0" || val == "null") return;
    buf.push(label, "：", val, (suffix ? suffix : ""), "<BR>");
  },
  
  // 强化行：基础值+强化加成显示
  upgradeLine: function(buf:Array, label:String, base:Number, lvl:Number):Void {
    if (base === undefined || base === 0) return;
    buf.push(label, "：", base);
    var enhanced = _root.强化计算(base, lvl);
    buf.push("<FONT COLOR='" + _root.注释常量.COL_HL + "'>(+", (enhanced - base), ")</FONT><BR>");
  },
  
  // 彩色行：带颜色的文本行
  colorLine: function(buf:Array, color:String, text:String):Void {
    buf.push("<FONT COLOR='" + color + "'>", text, "</FONT><BR>");
  }
};

// =========================
// 阶段1：文本拼接纯函数化  
// =========================
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
    if (item.synthesis != null) {
      var 表 = ItemUtil.getRequirementFromTask(_root.改装清单对象[item.synthesis].materials);
      if (表.length > 0) {
        a.push("合成材料：<BR>");
        for (var i=0; i<表.length; i++) {
          a.push(ItemUtil.getItemData(表[i].name).displayname, "：", 表[i].value, "<BR>");
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
      // 兼容两种形态：value 为数字 或 对象里带 count
      var 数量:Number = (typeof value == "number")
                        ? Number(value)
                        : (value && !isNaN(Number(value.count)) ? Number(value.count) : 0);
      if (数量 > 1) a.push("数量：", 数量, "<BR>");
    }
    return a;
  }
};

// 阶段2：数据选择器 + 行渲染工具 + 装备块渲染器
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

// D. 布局模块：宽度估算、简介布局、注释框定位
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
  应用简介布局: function(itemType:String, target:MovieClip, background:MovieClip, text:MovieClip):Number {
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
        text._x = -200;
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
    
    return backgroundHeightOffset;
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

// 兼容别名：保持向后兼容，内部转调新的样式模块
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

// 验证常量模块正确性（可在测试时启用）
// _root.testConstants = function() {
//   trace("COL_HL:", _root.注释常量.COL_HL);
//   trace("SUF_PERCENT:", _root.注释常量.SUF_PERCENT);
//   trace("BASE_NUM:", _root.注释常量.BASE_NUM);
// };

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
      var splitVal:Number = (d.split && d.split > 1) ? d.split : 1;
      var magazineCapacity = notMuti ? splitVal : 1;
      a.push("弹夹容量：", (d.capacity * magazineCapacity), "<BR>");
      a.push("子弹威力：", d.power, "<FONT COLOR='#FFCC00'>(+", (_root.强化计算(d.power, 等级)-d.power), ")</FONT><BR>");
      if (splitVal > 1) a.push(notMuti ? "点射弹数：" : "弹丸数量：", splitVal, "<BR>");
      if (d.interval) a.push("射速：", (Math.floor(10000 / d.interval) * 0.1 * magazineCapacity), "发/秒<BR>");
      if (d.impact)  a.push("冲击力：", Math.floor(500 / d.impact), "<BR>");
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

_root.物品图标注释 = function(name, value) {
    var 强化等级 = value.level > 0 ? value.level : 1;

    var 物品数据 = ItemUtil.getItemData(name);
    var 文本数据 = new Array();

    //避免回车换两行
    文本数据.push(物品数据.description.split("\r\n").join("<BR>"));
    文本数据.push("<BR>");

    //是否为剧情碎片                                                                                                 
    if (物品数据.use == "情报") {
        文本数据.push("<FONT COLOR=\'#FFCC00\'>详细信息可在物品栏的情报界面查阅</FONT><BR>");
    }


    //合成材料
    if (物品数据.synthesis != null) {
        var 合成表 = ItemUtil.getRequirementFromTask(_root.改装清单对象[物品数据.synthesis].materials);
        if (合成表.length > 0) {
            文本数据.push("合成材料：<BR>");
            for (var i = 0; i < 合成表.length; i++) {
                文本数据.push(ItemUtil.getItemData(合成表[i].name).displayname + "：" + 合成表[i].value);
                文本数据.push("<BR>");
            }
        }
    }

    //刀技乘数
    if (物品数据.use === "刀") {
        var templist = [_root.技能函数.凶斩伤害乘数表,
            _root.技能函数.瞬步斩伤害乘数表,
            _root.技能函数.龙斩刀伤乘数表,
            _root.技能函数.拔刀术伤害乘数表];
        var namelist = ["凶斩", "瞬步斩", "龙斩", "拔刀术"];
        for (var i = 0; i < templist.length; i++) {
            var temp = templist[i][物品数据.name];
            if (temp > 1) {
                var tempPercent = String((temp - 1) * 100);
                文本数据.push('<font color="#FFCC00">【技能加成】</font>使用' + namelist[i] + "享受" + tempPercent + "%锋利度增益<BR>");
            }
        }

    }

    //战技信息
    var 战技 = 物品数据.skill;
    if (战技 != null) {
        if (战技.description) {
            文本数据.push('<font color="#FFCC00">【主动战技】</font>');
            文本数据.push(战技.description);
            文本数据.push('<BR><font color="#FFCC00">【战技信息】</font>');
            if (战技.information) {
                文本数据.push(战技.information);
            } else {
                //自动生成战技信息
                var cd = 战技.cd / 1000;
                文本数据.push("冷却" + cd + "秒");
                if (战技.hp && 战技.hp != 0) {
                    文本数据.push("，消耗" + 战技.hp + "HP");
                }
                if (战技.mp && 战技.mp != 0) {
                    文本数据.push("，消耗" + 战技.mp + "MP");
                }
                文本数据.push("。");
            }
        } else {
            文本数据.push(战技);
        }
        文本数据.push("<BR>");
    }

    //生命周期信息

    var 生命周期 = 物品数据.lifecycle;
    if (生命周期 != null) {
        if (生命周期.description) {
            文本数据.push('<font color="#FFCC00">【词条信息】</font>');
            文本数据.push(生命周期.description);
            文本数据.push("<BR>");
        }
    }

    var 完整文本 = 文本数据.join('');
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


// 兼容包装：保留原入口，内部转调新渲染器（可逐步下线）
_root.物品装备信息注释 = function(文本数据:Array, 物品数据:Object, tier:String, 强化等级:Number):Void {
    var 块 = _root.注释文本.生成装备属性块(物品数据, tier, 强化等级);
    for (var i=0; i<块.length; i++) 文本数据.push(块[i]);
}


//技能图标
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
        // 阶段1：简介标题头纯函数
        var introductionString:Array = _root.注释文本.生成简介标题头(data, value, level);

        var tips:MovieClip = _root.注释框;
        
        // 使用新的布局模块处理简介布局
        var backgroundHeightOffset = _root.注释布局.应用简介布局(data.type, target, background, text);
        var stringWidth = background._width;  // 获取布局后的实际宽度

        // 阶段2：装备属性块（纯函数返回数组）
        var 装备块:Array = _root.注释文本.生成装备属性块(data, value.tier, level);
        introductionString = introductionString.concat(装备块);

        var introduction:String = introductionString.join('');

        if(extraString) introduction += "<BR>" + extraString;

        _root.注释(stringWidth, introduction, "简介")

        var iconString:String = "图标-" + data.icon;

        if(target.icon) target.icon.removeMovieClip();

        // 从库中将图标附加到 target MovieClip 上
        var icon:MovieClip = target.attachMovie(iconString, "icon", target.getNextHighestDepth());
        icon._xscale = icon._yscale = 150;
        icon._x = icon._y = 19;

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

