class org.flashNight.gesh.string.TooltipTextBuilder {
  public static function generateBaseDescription(item:Object):Array {
    var a = [];
    if (item.description) a.push(item.description.split("\r\n").join("<BR>"), "<BR>");
    return a;
  }
  
  public static function generateStoryHint(item:Object):Array {
    var a = [];
    if (item.use == "情报") a.push("<FONT COLOR='#FFCC00'>详细信息可在物品栏的情报界面查阅</FONT><BR>");
    return a;
  }
  
  public static function generateSynthesis(item:Object, modBook:Object, itemUtil:Object):Array {
    var a = [];
    if (item.synthesis != null && 
        modBook && 
        modBook[item.synthesis] && 
        modBook[item.synthesis].materials) {
      var 表 = itemUtil.getRequirementFromTask(modBook[item.synthesis].materials);
      if (表 && 表.length > 0) {
        a.push("合成材料：<BR>");
        for (var i=0; i<表.length; i++) {
          if (表[i] && 表[i].name) {
            a.push(itemUtil.getItemData(表[i].name).displayname, "：", 表[i].value, "<BR>");
          }
        }
      }
    } 
    return a;
  }
  
  public static function generateBladeMultipliers(item:Object, skillTables:Object):Array {
    var a = [];
    if (item.use === "刀") {
      var 列表 = [skillTables.凶斩伤害乘数表, skillTables.瞬步斩伤害乘数表,
                 skillTables.龙斩刀伤乘数表, skillTables.拔刀术伤害乘数表];
      var 名称 = ["凶斩","瞬步斩","龙斩","拔刀术"];
      for (var i=0; i<列表.length; i++) {
        var t = 列表[i][item.name];
        if (t > 1) a.push("<font color='#FFCC00'>【技能加成】</font>使用", 名称[i], "享受", String((t-1)*100), "%锋利度增益<BR>");
      }
    }
    return a;
  }
  
  public static function generateActiveSkillInfo(skill:Object):Array {
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
  
  public static function generateLifecycle(lc:Object):Array {
    var a = [];
    if (lc && lc.description) a.push("<font color='#FFCC00'>【词条信息】</font>", lc.description, "<BR>");
    return a;
  }
  
  public static function generateIntroHeader(item:Object, value:Object, level:Number):Array {
    var a = [];
    a.push("<B>", (value.tier ? ("[" + value.tier + "]") : ""), item.displayname, "</B><BR>");
    a.push(item.type, "    ", item.use, "<BR>");
    if (item.type == "武器" || item.type == "防具") { a.push("等级限制：", item.level, "<BR>"); }
    a.push("$", item.price, "<BR>");
    if (item.weight != null && item.weight !== 0) a.push("重量：", item.weight, "kg<BR>");
    if (level > 1 && (item.type == "武器" || item.type == "防具")) {
      a.push("<FONT COLOR='#FFCC00'>强化等级：", level, "</FONT><BR>");
    } else {
      var 数量:Number = 0;
      if (typeof value == "number") {
        数量 = Number(value);
      } else if (value) {
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
  
  public static function generateEquipmentBlock(item:Object, tier:String, level:Number, deps:Object):Array {
    // TODO: 实现装备块生成，需要依赖注入
    return [];
  }
}