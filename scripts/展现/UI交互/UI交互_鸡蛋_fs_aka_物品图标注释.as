import org.flashNight.arki.item.*;
import org.flashNight.gesh.array.*;

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
    var 字数 = 完整文本.length;
    var 每字平均宽度 = 0.5; // 根据实际情况调整
    var 最大宽度 = 500; // 根据实际情况调整
    var 计算宽度 = Math.max(150, Math.min(字数 * 每字平均宽度, 最大宽度));

    // 调用注释函数，传递计算出的宽度和文本内容
    _root.注释(计算宽度, 完整文本);
    _root.注释物品图标(true, name, value);
};


_root.物品装备信息注释 = function(文本数据:Array, 物品数据:Object, tier:String):Void {
    var 物品装备数据;
    if (tier != null) {
        switch (tier) {
            case "二阶":
                物品装备数据 = 物品数据.data_2;
                break;
            case "三阶":
                物品装备数据 = 物品数据.data_3;
                break;
            case "四阶":
                物品装备数据 = 物品数据.data_4;
                break;
            case "墨冰":
                物品装备数据 = 物品数据.data_ice;
                break;
            case "狱火":
                物品装备数据 = 物品数据.data_fire;
                break;
        }
    }
    if (物品装备数据 == null)
        物品装备数据 = 物品数据.data;

    switch (物品数据.use) {
        case "刀":
            文本数据.push("锋利度：");
            文本数据.push(物品装备数据.power);
            文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.power, 强化等级) - 物品装备数据.power) + ")</FONT>");
            文本数据.push("<BR>");
            break;
        case "手雷":
            文本数据.push("等级限制：");
            文本数据.push(物品数据.level);
            文本数据.push("<BR>");
            文本数据.push("威力：");
            文本数据.push(物品装备数据.power);
            文本数据.push("<BR>");
            break;
        case "长枪":
        case "手枪":
            文本数据.push("使用弹夹：");
            文本数据.push(ItemUtil.getItemData(物品装备数据.clipname).displayname);
            文本数据.push("<BR>");
            文本数据.push("子弹类型：");
            if (物品装备数据.bulletrename) {
                文本数据.push(物品装备数据.bulletrename);
            } else {
                文本数据.push(物品装备数据.bullet);
            }
            文本数据.push("<BR>");
            文本数据.push("弹夹容量：");
            var notMuti:Boolean = (物品装备数据.bullet.indexOf("纵向") >= 0);

            var magazineCapacity:Number = notMuti ? 物品装备数据.split : 1;

            文本数据.push(物品装备数据.capacity * magazineCapacity);
            文本数据.push("<BR>");
            文本数据.push("子弹威力：");
            文本数据.push(物品装备数据.power);
            文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.power, 强化等级) - 物品装备数据.power) + ")</FONT>");
            文本数据.push("<BR>");
            if (物品装备数据.split > 1) {
                文本数据.push(notMuti ? "点射弹数：" : "弹丸数量：");
                文本数据.push(物品装备数据.split);
                文本数据.push("<BR>");
            }
            文本数据.push("射速：");
            文本数据.push(Math.floor(10000 / 物品装备数据.interval) * 0.1 * magazineCapacity);
            文本数据.push("发/秒<BR>");
            文本数据.push("冲击力：" + Math.floor(500 / 物品装备数据.impact));
            文本数据.push("<BR>");

    }
    if (物品装备数据.force !== undefined && 物品装备数据.force !== 0) {
        文本数据.push("内力加成：");
        文本数据.push(物品装备数据.force);
        文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.force, 强化等级) - 物品装备数据.force) + ")</FONT>");
        文本数据.push("<BR>");
    }
    if (物品装备数据.damage !== undefined && 物品装备数据.damage !== 0) {
        文本数据.push("伤害加成：");
        文本数据.push(物品装备数据.damage);
        文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.damage, 强化等级) - 物品装备数据.damage) + ")</FONT>");
        文本数据.push("<BR>");
    }
    if (物品装备数据.punch !== undefined && 物品装备数据.punch !== 0) {
        文本数据.push("空手加成：");
        文本数据.push(物品装备数据.punch);
        文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.punch, 强化等级) - 物品装备数据.punch) + ")</FONT>");
        文本数据.push("<BR>");
    }
    if (物品装备数据.knifepower !== undefined && 物品装备数据.knifepower !== 0) {
        文本数据.push("冷兵器加成：");
        文本数据.push(物品装备数据.knifepower);
        文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.knifepower, 强化等级) - 物品装备数据.knifepower) + ")</FONT>");
        文本数据.push("<BR>");
    }
    if (物品装备数据.gunpower !== undefined && 物品装备数据.gunpower !== 0) {
        文本数据.push("枪械加成：");
        文本数据.push(物品装备数据.gunpower);
        文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.gunpower, 强化等级) - 物品装备数据.gunpower) + ")</FONT>");
        文本数据.push("<BR>");
    }
    if (物品装备数据.criticalhit !== undefined) {
        if (!isNaN(Number(物品装备数据.criticalhit))) {
            文本数据.push("<FONT COLOR=\'#DD4455\'>" + "暴击：" + "</FONT>");
            文本数据.push("<FONT COLOR=\'#DD4455\'>" + 物品装备数据.criticalhit + "%概率造成1.5倍伤害" + "</FONT>");
        } else if (物品装备数据.criticalhit == "满血暴击") {
            文本数据.push("<FONT COLOR=\'#DD4455\'>" + "暴击：对满血敌人造成1.5倍伤害" + "</FONT>");
        }
        文本数据.push("<BR>");
    }
    if (物品装备数据.slay !== undefined && 物品装备数据.slay !== 0) {
        文本数据.push("斩杀线：");
        文本数据.push(物品装备数据.slay + "%血量");
        文本数据.push("<BR>");
    }
    if (物品装备数据.accuracy !== undefined && 物品装备数据.accuracy !== 0) {
        文本数据.push("命中加成：");
        文本数据.push(物品装备数据.accuracy + "%");
        文本数据.push("<BR>");
    }
    if (物品装备数据.evasion !== undefined && 物品装备数据.evasion !== 0) {
        文本数据.push("挡拆加成：");
        文本数据.push(物品装备数据.evasion + "%");
        文本数据.push("<BR>");
    }
    if (物品装备数据.toughness !== undefined && 物品装备数据.toughness !== 0) {
        文本数据.push("韧性加成：");
        文本数据.push(物品装备数据.toughness + "%");
        文本数据.push("<BR>");
    }
    if (物品装备数据.lazymiss !== undefined && 物品装备数据.lazymiss !== 0) {
        文本数据.push("高危回避：");
        文本数据.push(物品装备数据.lazymiss + "");
        文本数据.push("<BR>");
    }
    if (物品装备数据.poison !== undefined && 物品装备数据.poison !== 0) {
        文本数据.push("<FONT COLOR=\'#66dd00\'>剧毒性</FONT>：");
        文本数据.push(物品装备数据.poison + "");
        文本数据.push("<BR>");
    }
    if (物品装备数据.vampirism !== undefined && 物品装备数据.vampirism !== 0) {
        文本数据.push("<FONT COLOR=\'#bb00aa\'>吸血</FONT>：");
        文本数据.push(物品装备数据.vampirism + "%");
        文本数据.push("<BR>");
    }
    if (物品装备数据.rout !== undefined && 物品装备数据.rout !== 0) {
        文本数据.push("<FONT COLOR=\'#FF3333\'>击溃</FONT>：");
        文本数据.push(物品装备数据.rout + "%");
        文本数据.push("<BR>");
    }
    // 检查是否存在伤害类型信息
    if (物品装备数据.damagetype !== undefined && 物品装备数据.damagetype !== 0) {
        // 如果是“魔法”类型，并且指定了具体的魔法属性
        if (物品装备数据.damagetype == "魔法" && 物品装备数据.magictype !== undefined && 物品装备数据.magictype !== 0) {
            文本数据.push("<FONT COLOR=\'#0099FF\'>伤害属性：");
            文本数据.push(物品装备数据.magictype + "");
            文本数据.push("</FONT><BR>");
        }
        // ========== 新增：“破击”类型的显示逻辑 ==========
        // 如果是“破击”类型，并且指定了触发的魔法属性
        else if (物品装备数据.damagetype == "破击" && 物品装备数据.magictype !== undefined && 物品装备数据.magictype !== 0) {
            if (ArrayUtil.includes(_root.敌人函数.魔法伤害种类, 物品装备数据.magictype)) {
                // 比伤害类型淡一些的蓝色
                文本数据.push("<FONT COLOR=\'#66bcf5\'>附加伤害：");
                // 伤害数字可以考虑用这个图标：✨
                文本数据.push(物品装备数据.magictype);
            } else {
                // 使用“破击”的专属颜色，更醒目
                文本数据.push("<FONT COLOR=\'#CC6600\'>破击类型：");
                // 将“破击”和其关联的属性一同显示，例如：“破击 (生化)”
                文本数据.push(物品装备数据.magictype);
            }
            文本数据.push("</FONT><BR>");
        }
        // ========== 新增逻辑结束 ==========
        else {
            // 其他所有情况（如 真伤，或没有指定属性的魔法/破击）
            文本数据.push("<FONT COLOR=\'#0099FF\'>伤害类型：");
            文本数据.push(物品装备数据.damagetype == "魔法" ? "能量" : 物品装备数据.damagetype + "");
            文本数据.push("</FONT><BR>");
        }
    }
    if (物品装备数据.magicdefence !== undefined && 物品装备数据.magicdefence !== 0) {
        var 魔法抗性对象 = 物品装备数据.magicdefence;
        if (魔法抗性对象) {
            for (var key in 魔法抗性对象) {
                var 抗性种类 = key == "基础" ? "能量" : key;
                文本数据.push(抗性种类 + "抗性：" + 魔法抗性对象[key] + "<BR>");
            }
        }
    }
    if (物品装备数据.defence !== undefined && 物品装备数据.defence !== 0) {
        文本数据.push("防御：");
        文本数据.push(物品装备数据.defence);
        文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.defence, 强化等级) - 物品装备数据.defence) + ")</FONT>");
        文本数据.push("<BR>");
    }
    if (物品装备数据.hp !== undefined && 物品装备数据.hp !== 0) {
        文本数据.push("<FONT COLOR=\'#00FF00\'>HP：" + 物品装备数据.hp + "</FONT>");
        文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.hp, 强化等级) - 物品装备数据.hp) + ")</FONT>");
        文本数据.push("<BR>");
    }
    if (物品装备数据.mp !== undefined && 物品装备数据.mp !== 0) {
        文本数据.push("<FONT COLOR=\'#00FFFF\'>MP：" + 物品装备数据.mp + "</FONT>");
        文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品装备数据.mp, 强化等级) - 物品装备数据.mp) + ")</FONT>");
        文本数据.push("<BR>");
    }

    if (物品数据.use == "药剂") {
        if (!isNaN(物品装备数据.affecthp) && 物品装备数据.affecthp != 0)
            文本数据.push("<FONT COLOR=\'#00FF00\'>HP+" + 物品装备数据.affecthp + "</FONT><BR>");
        if (!isNaN(物品装备数据.affectmp) && 物品装备数据.affectmp != 0)
            文本数据.push("<FONT COLOR=\'#00FFFF\'>MP+" + 物品装备数据.affectmp + "</FONT><BR>");
        if (物品装备数据.friend == 1) {
            文本数据.push("<FONT COLOR=\'#FFCC00\'>全体友方有效</FONT><BR>");
        } else if (物品装备数据.friend == "淬毒") {
            文本数据.push("<FONT COLOR=\'#66dd00\'>剧毒性: " + (isNaN(物品装备数据.poison) ? 0 : 物品装备数据.poison) + "</FONT><BR>");
        } else if (物品装备数据.friend == "净化") {
            文本数据.push("净化度: " + (isNaN(物品装备数据.clean) ? 0 : 物品装备数据.clean) + "<BR>");
        }
    }
    if (物品数据.actiontype !== undefined) {
        文本数据.push("动作：");
        文本数据.push(物品数据.actiontype);
        文本数据.push("<BR>");
    }
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

    var 计算宽度 = 技能信息.Description.length < 20 ? 160 : 200;
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

    var 计算宽度 = 技能信息.Description.length < 20 ? 160 : 200;
    _root.注释(计算宽度, 文本数据);
};


_root.注释物品图标 = function(enable:Boolean, name:String, value:Object) {
    // 'target' MovieClip 作为您在舞台上放置的占位符
    // 它在 Flash IDE 中的位置和大小，应决定图标最终的显示效果
    var target:MovieClip = _root.注释框.物品图标定位;
    var background:MovieClip = _root.注释框.简介背景;
    var text:MovieClip = _root.注释框.简介文本框;

    if (enable) {

        target._visible = true;
        text._visible = true;
        background._visible = true;

        var data:Object = ItemUtil.getItemData(name);
        var introductionString:Array = new Array();
        introductionString.push("<B>");

        var displayName = data.displayname;
        if (value.tier)
            displayName = "[" + value.tier + "]" + displayName;
        introductionString.push(displayName);

        introductionString.push("</B><BR>");
        introductionString.push(data.type);
        introductionString.push("    ");
        introductionString.push(data.use);
        introductionString.push("<BR>");
        if (data.type == "武器" || data.type == "防具") {
            introductionString.push("等级限制：");
            introductionString.push(data.level);
            introductionString.push("<BR>");
        }
        introductionString.push("$");
        introductionString.push(data.price);
        introductionString.push("<BR>");
        if (data.weight != null && data.weight !== 0) {
            introductionString.push("重量：");
            introductionString.push(data.weight + "kg");
            introductionString.push("<BR>");
        }

        var level:Number = value.level > 0 ? value.level : 1;

        if (level > 1 && data.type == "武器" || data.type == "防具") {
            introductionString.push("<FONT COLOR=\'#FFCC00\'>");
            introductionString.push("强化等级：");
            introductionString.push(level);
            introductionString.push("</FONT>");
            introductionString.push("<BR>");
        } else if (value > 1) {
            introductionString.push("数量：");
            introductionString.push(value);
            introductionString.push("<BR>");
        }

        var tips:MovieClip = _root.注释框;
        
        var stringWidth:Number;
        var baseNum:Number = 200;
        var rate:Number = 3 / 5;
        var baseScale:Number = 486.8;
        var baseOffset:Number = 7.5;

        switch(data.type) {
            case "武器":
            case "防具":
                
                stringWidth = baseNum;
                background._width = baseNum;
                background._x = -baseNum;
                target._x = -baseNum + baseOffset;
                target._xscale = target._yscale = baseScale;
                text._x = -200;
                text._y = 210;
                break;
            default:
                stringWidth = 200 * rate;
                background._width = 200 * rate;
                background._x = -200 * rate;
                target._x = -200 * rate + baseOffset * rate;
                target._xscale = target._yscale = (baseScale * rate);
                text._x = -baseNum * rate;
                text._y = 10 - text._x;
        }

        // 获取装备数据
        _root.物品装备信息注释(introductionString, data, value.tier);

        var introduction:String = introductionString.join('');


        _root.注释(stringWidth, introduction, "简介")

        var iconString:String = "图标-" + data.icon;

        // 从库中将图标附加到 target MovieClip 上
        var icon:MovieClip = target.attachMovie(iconString, "icon", target.getNextHighestDepth());
        icon._xscale = icon._yscale = 150;
        icon._x = icon._y = 19;


        background._height = text._height + 220;
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
    框体 = 框体 || "";
    var tips:MovieClip = _root.注释框;
    var target:MovieClip = tips[框体 + "文本框"];
    var background:MovieClip = tips[框体 + "背景"]
    tips._visible = true;
    target.htmlText = 内容;
    target._width = 宽度;

    background._width = target._width;
    background._height = target.textHeight + 10;
    target._height = target.textHeight + 10;

    var isAbbr:Boolean = !tips.简介背景._visible;

    if(isAbbr) {
        // 简介背景隐藏时的定位逻辑
        tips._x = Math.min(Stage.width - background._width, Math.max(0, _root._xmouse - background._width));
        tips._y = Math.min(Stage.height - background._height, Math.max(0, _root._ymouse - background._height - 20));
    } else {

        // 为了代码清晰，明确获取左右两个背景的引用
        var rightBackground:MovieClip = tips.背景;
        var leftBackground:MovieClip = tips.简介背景;
        
        // 1. 计算鼠标的理想定位点（将注释框的右边缘对齐到鼠标指针）
        var desiredX:Number = _root._xmouse - rightBackground._width;

        // 2. 计算允许的最小X值
        //    为了保证左背景不移出屏幕，注册点(tips._x)的最小值必须是左背景的宽度
        var minX:Number = leftBackground._width;

        // 3. 计算允许的最大X值
        //    为了保证右背景不移出屏幕，注册点(tips._x)的最大值是舞台宽度减去右背景的宽度
        var maxX:Number = Stage.width - rightBackground._width;

        // 4. 应用约束：先在最大和最小边界内夹住理想值
        //    这里的逻辑可以简化为一行，但分解开更易于理解
        tips._x = Math.max(minX, Math.min(desiredX, maxX));

        // Y轴定位逻辑保持不变
        tips._y = Math.min(Stage.height - tips._height, Math.max(0, _root._ymouse - tips._height - 20));

        // --- 修改结束 ---
        var icon:MovieClip = _root.注释框.物品图标定位;
        rightBackground._height = Math.max(tips.文本框.textHeight, icon._height) + 10;
    }
};

_root.注释结束 = function() {
    _root.注释框._visible = false;
    _root.注释物品图标(false);
};

_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
    _root.注释结束();
}, null); 

