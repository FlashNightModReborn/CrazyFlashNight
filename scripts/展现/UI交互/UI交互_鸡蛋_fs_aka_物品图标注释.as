﻿import org.flashNight.arki.item.*;

_root.物品图标注释 = function(name, value){
	var 强化等级 = value.level > 0 ? value.level : 1;
	
	var 物品数据 = ItemUtil.getItemData(name);
	var 文本数据 = new Array();
	文本数据.push("<B>");

	var displayName = 物品数据.displayname;
	if(value.tier) displayName = "[" + value.tier + "]" + displayName;
	文本数据.push(displayName);
	
	文本数据.push("</B><BR>");
	文本数据.push(物品数据.type);
	文本数据.push("    ");
	文本数据.push(物品数据.use);
	文本数据.push("<BR>");
	if (物品数据.type == "武器" || 物品数据.type == "防具")
	{
		文本数据.push("等级限制：");
		文本数据.push(物品数据.level);
		文本数据.push("<BR>");
	}
	文本数据.push("$");
	文本数据.push(物品数据.price);
	文本数据.push("<BR>");
	if (物品数据.weight != null && 物品数据.weight !== 0)
	{
		文本数据.push("重量：");
		文本数据.push(物品数据.weight + "kg");
		文本数据.push("<BR>");
	}
	switch (物品数据.use)
	{
		case "刀" :
			文本数据.push("锋利度：");
			文本数据.push(物品数据.data.power);
			文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.data.power, 强化等级) - 物品数据.data.power) + ")</FONT>");
			文本数据.push("<BR>");
			break;
		case "手雷" :
			文本数据.push("等级限制：");
			文本数据.push(物品数据.level);
			文本数据.push("<BR>");
			文本数据.push("威力：");
			文本数据.push(物品数据.data.power);
			文本数据.push("<BR>");
			break;
		case "长枪" :
		case "手枪" :
			文本数据.push("使用弹夹：");
			文本数据.push(ItemUtil.getItemData(物品数据.data.clipname).displayname);
			文本数据.push("<BR>");
			文本数据.push("子弹类型：");
			if(物品数据.data.bulletrename){
				文本数据.push(物品数据.data.bulletrename);
			}else{
				文本数据.push(物品数据.data.bullet);
			}
			文本数据.push("<BR>");
			文本数据.push("弹夹容量：");
			var notMuti:Boolean = (物品数据.data.bullet.indexOf("纵向") >= 0);

			var magazineCapacity:Number = notMuti ? 物品数据.data.split : 1;

			文本数据.push(物品数据.data.capacity * magazineCapacity);
			文本数据.push("<BR>");
			文本数据.push("子弹威力：");
			文本数据.push(物品数据.data.power);
			文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.data.power, 强化等级) - 物品数据.data.power) + ")</FONT>");
			文本数据.push("<BR>");
			if(物品数据.data.split > 1){
				文本数据.push(notMuti ? "点射弹数：" : "弹丸数量：");
				文本数据.push(物品数据.data.split);
				文本数据.push("<BR>");
			}
			文本数据.push("射速：");
			文本数据.push(Math.floor(10000 / 物品数据.data.interval) * 0.1 * magazineCapacity);
			文本数据.push("发/秒<BR>");
			文本数据.push("冲击力：" + Math.floor(500 / 物品数据.data.impact));
			文本数据.push("<BR>");

	}
	if (物品数据.equipped.force !== undefined && 物品数据.equipped.force !== 0)
	{
		文本数据.push("内力加成：");
		文本数据.push(物品数据.equipped.force);
		文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.equipped.force, 强化等级) - 物品数据.equipped.force) + ")</FONT>");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.damage !== undefined && 物品数据.equipped.damage !== 0)
	{
		文本数据.push("伤害加成：");
		文本数据.push(物品数据.equipped.damage);
		文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.equipped.damage, 强化等级) - 物品数据.equipped.damage) + ")</FONT>");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.punch !== undefined && 物品数据.equipped.punch !== 0)
	{
		文本数据.push("空手加成：");
		文本数据.push(物品数据.equipped.punch);
		文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.equipped.punch, 强化等级) - 物品数据.equipped.punch) + ")</FONT>");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.knifepower !== undefined && 物品数据.equipped.knifepower !== 0)
	{
		文本数据.push("冷兵器加成：");
		文本数据.push(物品数据.equipped.knifepower);
		文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.equipped.knifepower, 强化等级) - 物品数据.equipped.knifepower) + ")</FONT>");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.gunpower !== undefined && 物品数据.equipped.gunpower !== 0)
	{
		文本数据.push("枪械加成：");
		文本数据.push(物品数据.equipped.gunpower);
		文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.equipped.gunpower, 强化等级) - 物品数据.equipped.gunpower) + ")</FONT>");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.criticalhit !== undefined)
	{
		if(!isNaN(Number(物品数据.equipped.criticalhit))){
			文本数据.push("<FONT COLOR=\'#DD4455\'>" + "暴击：" + "</FONT>");
			文本数据.push("<FONT COLOR=\'#DD4455\'>" + 物品数据.equipped.criticalhit + "%概率造成1.5倍伤害" + "</FONT>");
		}else if(物品数据.equipped.criticalhit == "满血暴击"){
			文本数据.push("<FONT COLOR=\'#DD4455\'>" + "暴击：对满血敌人造成1.5倍伤害" + "</FONT>");
		}
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.slay !== undefined && 物品数据.equipped.slay !== 0)
	{
		文本数据.push("斩杀线：");
		文本数据.push(物品数据.equipped.slay + "%血量");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.accuracy !== undefined && 物品数据.equipped.accuracy !== 0)
	{
		文本数据.push("命中加成：");
		文本数据.push(物品数据.equipped.accuracy + "%");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.evasion !== undefined && 物品数据.equipped.evasion !== 0)
	{
		文本数据.push("挡拆加成：");
		文本数据.push(物品数据.equipped.evasion + "%");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.toughness !== undefined && 物品数据.equipped.toughness !== 0)
	{
		文本数据.push("韧性加成：");
		文本数据.push(物品数据.equipped.toughness + "%");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.lazymiss !== undefined && 物品数据.equipped.lazymiss !== 0)
	{
		文本数据.push("高危回避：");
		文本数据.push(物品数据.equipped.lazymiss + "");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.poison !== undefined && 物品数据.equipped.poison !== 0)
	{
		文本数据.push("<FONT COLOR=\'#66dd00\'>剧毒性</FONT>：");
		文本数据.push(物品数据.equipped.poison + "");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.vampirism !== undefined && 物品数据.equipped.vampirism !== 0)
	{
		文本数据.push("<FONT COLOR=\'#bb00aa\'>吸血</FONT>：");
		文本数据.push(物品数据.equipped.vampirism + "%");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.rout !== undefined && 物品数据.equipped.rout !== 0)
	{
		文本数据.push("<FONT COLOR=\'#FF3333\'>击溃</FONT>：");
		文本数据.push(物品数据.equipped.rout + "%");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.damagetype !== undefined && 物品数据.equipped.damagetype !== 0)
	{
		if (物品数据.equipped.damagetype == "魔法" && 物品数据.equipped.magictype !== undefined && 物品数据.equipped.magictype !== 0)
		{
			文本数据.push("<FONT COLOR=\'#0099FF\'>伤害属性：");
			文本数据.push(物品数据.equipped.magictype + "");
			文本数据.push("</FONT><BR>");
		}else{
			文本数据.push("<FONT COLOR=\'#0099FF\'>伤害类型：");
			文本数据.push(物品数据.equipped.damagetype == "魔法"? "能量" : 物品数据.equipped.damagetype + "");
			文本数据.push("</FONT><BR>");
		}
	}
	if (物品数据.equipped.magicdefence !== undefined && 物品数据.equipped.magicdefence !== 0)
	{
		var 魔法抗性对象 = 物品数据.equipped.magicdefence;
		if(魔法抗性对象){
			for(var key in 魔法抗性对象){
				var 抗性种类 = key == "基础" ? "能量" : key;
				文本数据.push(抗性种类 +"抗性："+ 魔法抗性对象[key] + "<BR>");
			}
		}
	}
	if (物品数据.equipped.defence !== undefined && 物品数据.equipped.defence !== 0)
	{
		文本数据.push("防御：");
		文本数据.push(物品数据.equipped.defence);
		文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.equipped.defence, 强化等级) - 物品数据.equipped.defence) + ")</FONT>");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.hp !== undefined && 物品数据.equipped.hp !== 0)
	{
		文本数据.push("<FONT COLOR=\'#00FF00\'>HP："+物品数据.equipped.hp+"</FONT>");
		文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.equipped.hp, 强化等级) - 物品数据.equipped.hp) + ")</FONT>");
		文本数据.push("<BR>");
	}
	if (物品数据.equipped.mp !== undefined && 物品数据.equipped.mp !== 0)
	{
		文本数据.push("<FONT COLOR=\'#00FFFF\'>MP："+物品数据.equipped.mp+"</FONT>");
		文本数据.push("<FONT COLOR=\'#FFCC00\'>(+" + (_root.强化计算(物品数据.equipped.mp, 强化等级) - 物品数据.equipped.mp) + ")</FONT>");
		文本数据.push("<BR>");
	}

	if (物品数据.use == "药剂")
	{
		if(!isNaN(物品数据.data.affecthp) && 物品数据.data.affecthp != 0) 文本数据.push("<FONT COLOR=\'#00FF00\'>HP+" + 物品数据.data.affecthp + "</FONT><BR>");
		if(!isNaN(物品数据.data.affectmp) && 物品数据.data.affectmp != 0) 文本数据.push("<FONT COLOR=\'#00FFFF\'>MP+" + 物品数据.data.affectmp + "</FONT><BR>");
		if (物品数据.data.friend == 1)
		{
			文本数据.push("<FONT COLOR=\'#FFCC00\'>全体友方有效</FONT><BR>");
		}
		else if (物品数据.data.friend == "淬毒")
		{
			文本数据.push("<FONT COLOR=\'#66dd00\'>剧毒性: "+ (isNaN(物品数据.data.poison) ? 0 : 物品数据.data.poison) + "</FONT><BR>" );
		}
		else if (物品数据.data.friend == "净化")
		{
			文本数据.push("净化度: " + (isNaN(物品数据.data.clean) ? 0 : 物品数据.data.clean) + "<BR>" );
		}
	}
	if (物品数据.actiontype !== undefined){
		文本数据.push("动作：");
		文本数据.push(物品数据.actiontype);
		文本数据.push("<BR>");
	}

	//避免回车换两行
	文本数据.push(物品数据.description.split("\r\n").join("<BR>"));
	文本数据.push("<BR>");

	//是否为剧情碎片                                                                                                 
	if (物品数据.use == "情报"){
		文本数据.push("<FONT COLOR=\'#FFCC00\'>详细信息可在物品栏的情报界面查阅</FONT><BR>");
	}


	//合成材料
	if (物品数据.synthesis != null){
		var 合成表 = ItemUtil.getRequirementFromTask(_root.改装清单对象[物品数据.synthesis].materials);
		if(合成表.length > 0){
			文本数据.push("合成材料：<BR>");
			for(var i = 0; i < 合成表.length; i++){
				文本数据.push(ItemUtil.getItemData(合成表[i].name).displayname+"："+ 合成表[i].value);
				文本数据.push("<BR>");
			}
		}
	}

	//刀技乘数
	if(物品数据.use === "刀"){
		var templist = [
			_root.技能函数.凶斩伤害乘数表,
			_root.技能函数.瞬步斩伤害乘数表,
			_root.技能函数.龙斩刀伤乘数表,
			_root.技能函数.拔刀术伤害乘数表
		];
		var namelist = ["凶斩", "瞬步斩", "龙斩", "拔刀术"];
		for(var i = 0; i < templist.length; i++){
			var temp = templist[i][物品数据.name];
			if(temp > 1){
				var tempPercent = String((temp - 1) * 100);
				文本数据.push('<font color="#FFCC00">【技能加成】</font>使用' + namelist[i] + "享受" + tempPercent + "%锋利度增益<BR>");
			}
		}
		
	}

	//战技信息
	var 战技 = 物品数据.skill;
	if (战技 != null){
		if(战技.description){
			文本数据.push('<font color="#FFCC00">【主动战技】</font>');
			文本数据.push(战技.description);
			文本数据.push('<BR><font color="#FFCC00">【战技信息】</font>');
			if(战技.information){
				文本数据.push(战技.information);
			}else{
				//自动生成战技信息
				var cd = 战技.cd / 1000;
				文本数据.push("冷却" + cd + "秒");
				if(战技.hp && 战技.hp != 0){
					文本数据.push("，消耗" + 战技.hp + "HP");
				}
				if(战技.mp && 战技.mp != 0){
					文本数据.push("，消耗" + 战技.mp + "MP");
				}
				文本数据.push("。");
			}
		}else{
			文本数据.push(战技);
		}
		文本数据.push("<BR>");
	}

	//生命周期信息

	var 生命周期 = 物品数据.lifecycle;
	if (生命周期 != null)
	{
		if(生命周期.description)
		{
			文本数据.push('<font color="#FFCC00">【词条信息】</font>');
			文本数据.push(生命周期.description);
			文本数据.push("<BR>");
		}
	}

	if (强化等级 > 1 && 物品数据.type == "武器" || 物品数据.type == "防具")
	{
		文本数据.push("<FONT COLOR=\'#FFCC00\'>");
		文本数据.push("强化等级：");
		文本数据.push(强化等级);
		文本数据.push("</FONT>");
	}
	else if (value > 1)
	{
		文本数据.push("数量：");
		文本数据.push(value);
	}

	var 完整文本 = 文本数据.join('');
	var 字数 = 完整文本.length;
	var 每字平均宽度 = 0.5;// 根据实际情况调整
	var 最大宽度 = 500;// 根据实际情况调整
	var 计算宽度 = Math.max(150, Math.min(字数 * 每字平均宽度, 最大宽度));

	// 调用注释函数，传递计算出的宽度和文本内容
	_root.注释(计算宽度, 完整文本);
};


//技能图标
_root.技能栏技能图标注释 = function(对应数组号){
	var 主角技能信息 = _root.主角技能表[对应数组号];
	var 技能名 = 主角技能信息[0];
	var 技能信息 = _root.技能表对象[技能名];

	var 是否装备或启用:String;
	if(技能信息.Equippable) 是否装备或启用 = 主角技能信息[2] == true ? "<FONT COLOR='#66FF00'>已装备</FONT>" : "<FONT COLOR='#FFDDDD'>未装备</FONT>";
	else 是否装备或启用 = 主角技能信息[4] == true ? "<FONT COLOR='#66FF00'>已启用</FONT>" : "<FONT COLOR='#FFDDDD'>未启用</FONT>";

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

_root.学习界面技能图标注释 = function(对应数组号){
	var 技能信息 = _root.技能表[对应数组号];

	var 文本数据 = "<B>" + 技能信息.Name + "</B>";
	文本数据 += "<BR>" + 技能信息.Type;
	文本数据 += "<BR>" + 技能信息.Description;
	文本数据 += "<BR>最高等级：" + 技能信息.MaxLevel;
	文本数据 += "<BR>解锁需要技能点数：" + 技能信息.UnlockSP;
	if(技能信息.MaxLevel > 1) 文本数据 += "<BR>升级需要技能点数：" + 技能信息.UpgradeSP;
	文本数据 += "<BR>冷却秒数：" + Math.floor(技能信息.CD / 1000);
	文本数据 += "<BR>MP消耗：" + 技能信息.MP;
	文本数据 += "<BR>等级限制：" + 技能信息.UnlockLevel;

	var 计算宽度 = 技能信息.Description.length < 20 ? 160 : 200;
	_root.注释(计算宽度, 文本数据);
};



_root.注释 = function(宽度, 内容){
	_root.注释框._visible = true;
	_root.注释框.文本框.htmlText = 内容;
	_root.注释框.文本框._width = 宽度;

	/*
	var 宽度增量:Number = _root.注释框.文本框._width * 0.25;
	var 黄金比例:Number = (1 + Math.sqrt(5)) / 2;
	var 长宽比:Number = _root.注释框.文本框.textHeight / _root.注释框.文本框._width;
	var 循环计数上限:Number = 50;
	//_root.发布调试消息(_root.注释框.文本框._width + "," + _root.注释框.文本框.textHeight + "  " + _root.注释框.文本框.textHeight / _root.注释框.文本框._width);
	// 调整宽度以适应内容
	
	
	while ((_root.注释框.文本框.textHeight >= Stage.height && 循环计数上限 > 0) || (长宽比 > 黄金比例 * 1.05))
	{
	if (长宽比 < 黄金比例 * 1.15)
	{
	宽度增量 = 5;//当接近黄金比例时放缓速度提高精度
	}
	else
	{
	宽度增量 = _root.注释框.文本框._width * 0.25;
	}
	_root.注释框.文本框._width += Math.min(宽度增量, Stage.width - _root.注释框.文本框._width);// 增加当前宽度
	长宽比 = _root.注释框.文本框.textHeight / _root.注释框.文本框._width;
	循环计数上限 -= 1;
	//_root.发布调试消息(_root.注释框.文本框._width + "," + _root.注释框.文本框.textHeight + "  " + 长宽比);
	
	}
	_root.发布调试消息(循环计数上限);
	
	*/
	_root.注释框.背景._width = _root.注释框.文本框._width;
	_root.注释框.背景._height = _root.注释框.文本框.textHeight + 10;
	_root.注释框.文本框._height = _root.注释框.文本框.textHeight + 10;
	_root.注释框._x = Math.min(Stage.width - _root.注释框._width, Math.max(0, _root._xmouse - _root.注释框._width));
	_root.注释框._y = Math.min(Stage.height - _root.注释框._height, Math.max(0, _root._ymouse - _root.注释框._height - 20));
};

_root.注释结束 = function(){
	_root.注释框._visible = false;
};