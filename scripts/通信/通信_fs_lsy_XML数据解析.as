// 当 XML 加载完成时触发的函数
// _root.关卡数据缓存 = [];

_root.配置数据为数组 = function(输入){
    // 检查输入是否已经是数组
    if (输入 instanceof Array){
        return 输入;
    }else if (输入 != undefined && 输入 != null){
        // 如果输入不是数组但不为空，则将其作为数组的单个元素返回
        return [输入];
    }else{
        // 对于未定义或空的输入，返回空数组
        return [];
    }
};

_root.实体映射反向 = new Object();// 反向映射 HTML 实体
_root.实体映射反向["&amp;"] = "&";
_root.实体映射反向["&lt;"] = "<";
_root.实体映射反向["&gt;"] = ">";
_root.实体映射反向["&quot;"] = "\"";
_root.实体映射反向["&apos;"] = "'";
_root.实体映射反向["&nbsp;"] = " ";
_root.实体映射反向["&NewLine;"] = "\n";
_root.实体映射反向["&copy;"] = "©";
_root.实体映射反向["&reg;"] = "®";
_root.实体映射反向["&trade;"] = "™";
_root.实体映射反向["&deg;"] = "°";
_root.实体映射反向["&plusmn;"] = "±";
_root.实体映射反向["&sup2;"] = "²";
_root.实体映射反向["&sup3;"] = "³";
_root.实体映射反向["&frac14;"] = "¼";
_root.实体映射反向["&frac12;"] = "½";
_root.实体映射反向["&frac34;"] = "¾";
_root.实体映射反向["&times;"] = "×";
_root.实体映射反向["&divide;"] = "÷";
_root.实体映射反向["&iexcl;"] = "¡";
_root.实体映射反向["&cent;"] = "¢";
_root.实体映射反向["&pound;"] = "£";
_root.实体映射反向["&curren;"] = "¤";
_root.实体映射反向["&yen;"] = "¥";
_root.实体映射反向["&brvbar;"] = "¦";
_root.实体映射反向["&sect;"] = "§";
_root.实体映射反向["&uml;"] = "¨";
_root.实体映射反向["&ordf;"] = "ª";
_root.实体映射反向["&laquo;"] = "«";
_root.实体映射反向["&not;"] = "¬";
_root.实体映射反向["&shy;"] = "­";
_root.实体映射反向["&macr;"] = "¯";
_root.转换HTML实体回文本 = function(带实体的文本:String):String 
{
	for (var 实体:String in _root.实体映射反向) {;


	var 对应字符:String = _root.实体映射反向[实体];
	带实体的文本 = 带实体的文本.split(实体).join(对应字符);
}
return 带实体的文本;
};


_root.解析并设置奖励品配置 = function(奖励品配置:Array)
{// 清空或初始化奖励数组
	var 奖励品 = [];
	for (var i:Number = 0; i < 奖励品配置.length; i++)
	{
		var 奖励:Object = 奖励品配置[i];
		var 奖励名称:String = 奖励.Name;
		var 出现概率:Number = 奖励.AcquisitionProbability;
		var 最大数量:Number = 奖励.QuantityMax;// 将奖励添加到数组中
		奖励品.push([奖励名称, 出现概率, 最大数量]);
	}// 检查奖励品数组是否为空，如果不为空，则返回数组
	if (奖励品.length == 1 and 奖励品[0][0] == undefined)
	{
		return null;
	}
	return 奖励品;
};

_root.解析rogue敌人集合 = function(Unions){
	var Unions = _root.配置数据为数组(Unions.Union);
	var rogue敌人集合表 = [];
	if(!Unions) return null;
	for (var i:Number = 0; i < Unions.length; i++){
		if(Unions[i].Types == undefined){
			实例配置.push(null);
			continue;
		}
		var 敌人集合 = {
			权重: Number(Unions[i].Weight), 
			唯一性: Unions[i].Unique ? true : false, 
			类型表: _root.配置数据为数组(Unions[i].Types.Type)
		};
		rogue敌人集合表.push(敌人集合);
	}
	return rogue敌人集合表;
}

_root.解析并设置基本配置 = function(关卡数据:Array)
{
	var 基本配置列表 = [];
	for (var i:Number = 0; i < 关卡数据.length; i++)
	{
		var 配置 = 关卡数据[i].BasicInformation;
		配置.PlayerX = 配置.PlayerX ? Number(配置.PlayerX) : undefined;
		配置.PlayerY = 配置.PlayerY ? Number(配置.PlayerY) : undefined;
		var environment = 配置.Environment;
		if(Boolean(environment.Default)){
			配置.Environment = _root.天气系统.关卡环境设置.Default;
		}
		基本配置列表.push(配置);
	}
return 基本配置列表;
};

// 解析并设置关卡配置
_root.解析并设置关卡配置 = function(关卡数据:Array)
{
	var 总关卡 = [];
	for (var i:Number = 0; i < 关卡数据.length; i++)
	{
		var 关卡波次配置;
		if(关卡数据[i].BasicInformation.RogueMode){
			关卡波次配置 = _root.解析rogue关卡波次(关卡数据[i].RogueWave);
		}else{
			关卡波次配置 = _root.解析无限过图关卡波次(_root.配置数据为数组(关卡数据[i].Wave.SubWave));
		}
		// var 关卡配置数量:Number = isNaN(关卡数据[i].Quantity) ? 1 : 关卡数据[i].Quantity;
		// for (var j:Number = 0; j < 关卡配置数量; j++){
		// 	总关卡.push(关卡波次配置);
		// }
		总关卡.push(关卡波次配置);
	}
	return 总关卡;
};

_root.解析无限过图关卡波次 = function(关卡波次数据:Array)
{
	var 关卡波次 = [];
	for (var i:Number = 0; i < 关卡波次数据.length; i++)
	{
		var 波次 = 关卡波次数据[i];
		var WaveInformation = _root.解析波次信息(波次.WaveInformation);
		var 敌人波次配置 = _root.解析敌人波次(_root.配置数据为数组(波次.EnemyGroup.Enemy));
		var 波次数量:Number = isNaN(波次.Quantity) ? 1 : 波次.Quantity;
		for (var j:Number = 0; j < 波次数量; j++)
		{
			关卡波次.push([WaveInformation].concat(敌人波次配置));
		}
	}
	return 关卡波次;
};

_root.解析rogue关卡波次 = function(关卡波次数据:Object)
{
	var 关卡波次 = new Object();
	关卡波次.初始时长 = Number(关卡波次数据.StartDuration);
	关卡波次.最终时长 = Number(关卡波次数据.EndDuration);
	关卡波次.总波数 = Number(关卡波次数据.TotalWave);
	关卡波次.初始敌人等级 = Number(关卡波次数据.StartLevel);
	关卡波次.最终敌人等级 = Number(关卡波次数据.EndLevel);
	关卡波次.初始权重 = Number(关卡波次数据.StartWeight);
	关卡波次.最终权重 = Number(关卡波次数据.EndWeight);
	关卡波次.单波最大生成数 = 关卡波次数据.QuantityMax > 0 ? Number(关卡波次数据.QuantityMax) : 99;
	关卡波次.敌人分组 = [];
	var 敌人分组配置 = _root.配置数据为数组(关卡波次数据.RogueGroup.Group);
	for(var i:Number = 0; i < 敌人分组配置.length; i++){
		var 敌人分组 = {
			起始波次: 敌人分组配置[i].StartWave ? Number(敌人分组配置[i].StartWave) : 0,
			终止波次: 敌人分组配置[i].EndWave ? Number(敌人分组配置[i].EndWave) : 999,
			权重: 敌人分组配置[i].Weight ? Number(敌人分组配置[i].Weight) : 1,
			分类索引表: _root.配置数据为数组(敌人分组配置[i].UnionIndex.Index)
		};
		关卡波次.敌人分组.push(敌人分组);
	}
	var 特殊波次 = _root.配置数据为数组(关卡波次数据.SpecialWave.SubWave);
	for(var i:Number = 0; i < 特殊波次.length; i++){
		if(isNaN(特殊波次[i].Index)) continue;
		var index = 特殊波次[i].Index;
		var WaveInformation = _root.解析波次信息(特殊波次[i].WaveInformation);
		var 敌人波次配置 = _root.解析敌人波次(_root.配置数据为数组(特殊波次[i].EnemyGroup.Enemy));
		关卡波次[index] = [WaveInformation].concat(敌人波次配置);
	}
	return 关卡波次;
}

_root.解析波次信息 = function(WaveInformation:Object)
{
	WaveInformation.Duration = Number(WaveInformation.Duration);
	WaveInformation.MapNoCount = WaveInformation.MapNoCount ? true : false;
	return WaveInformation;
}

_root.解析敌人波次 = function(敌人配置:Array)
{
	var 敌人波次 = [];
	for (var i:Number = 0; i < 敌人配置.length; i++)
	{
		var 敌人 = 敌人配置[i]
		var enemy = new Object();
		if(敌人.RandomType) {
			enemy.RandomType = _root.配置数据为数组(敌人.RandomType.Type);
		}else{
			enemy.Attribute = _root.解析敌人属性(敌人);
		}
		enemy.Interval = Number(敌人.Interval);
		enemy.Quantity = isNaN(敌人.Quantity) ? 1 : Number(敌人.Quantity);
		enemy.Level = isNaN(敌人.Level) ? 1 : Number(敌人.Level);
		enemy.SpawnIndex = (敌人.SpawnIndex || 敌人.SpawnIndex == 0) ? 敌人.SpawnIndex : -1;
		enemy.x = isNaN(敌人.x) ? undefined : Number(敌人.x);
		enemy.y = isNaN(敌人.y) ? undefined : Number(敌人.y);
		enemy.Parameters = 敌人.Parameters ? 敌人.Parameters : undefined;
		enemy.DifficultyMin = 敌人.DifficultyMin ? 敌人.DifficultyMin : undefined;
		enemy.DifficultyMax = 敌人.DifficultyMax ? 敌人.DifficultyMax : undefined;
		enemy.InstanceName = 敌人.InstanceName ? 敌人.InstanceName: undefined;
		敌人波次.push(enemy);
	}
	return 敌人波次;
};

_root.解析敌人属性 = function(敌人)
{
	// 如果Type属性存在，则直接返回已有敌人配置
	if (_root.兵种库[敌人.Type]) return _root.兵种库[敌人.Type];
	// 否则，组装敌人属性       
	var 敌人对象:Object = {};
	敌人对象.兵种名 = 敌人.spritename;
	敌人对象.名字 = 敌人.Name;
	敌人对象.等级 = 敌人.Level;
	敌人对象.是否为敌人 = 敌人.IsHostile;
	敌人对象.身高 = 敌人.Height;
	敌人对象.NPC = 敌人.NPC;
	敌人对象.长枪 = 敌人.PrimaryWeapon;
	敌人对象.手枪 = 敌人.SecondaryWeapon;
	敌人对象.手枪2 = 敌人.SecondaryWeapon2;
	敌人对象.刀 = 敌人.MeleeWeapon;
	敌人对象.手雷 = 敌人.Grenade;
	敌人对象.脸型 = 敌人.FaceType;
	敌人对象.发型 = 敌人.HairStyle;
	敌人对象.头部装备 = 敌人.HeadEquipment;
	敌人对象.上装装备 = 敌人.BodyArmor;
	敌人对象.下装装备 = 敌人.LegArmor;
	敌人对象.手部装备 = 敌人.HandGear;
	敌人对象.脚部装备 = 敌人.FootGear;
	敌人对象.颈部装备 = 敌人.NeckGear;
	敌人对象.性别 = 敌人.Gender;
	for (var 属性:String in 敌人对象) {
		// 检查属性值是否为undefined或null，如果是则赋值为""
		敌人对象[属性] = (敌人对象[属性] !== undefined && 敌人对象[属性] !== null) ? 敌人对象[属性] : "";
	}/*if (敌人.Type !== undefined)
	{
	_root[敌人.Type] = 敌人对象;
	}*/
	return 敌人对象;// 返回组装好的敌人对象
};

_root.解析并设置实例配置 = function(关卡数据:Array){
	var 实例配置 = [];
	for (var i:Number = 0; i < 关卡数据.length; i++){
		if(关卡数据[i].Instances == undefined){
			实例配置.push(null);
			continue;
		}
		var 实例:Object = _root.配置数据为数组(关卡数据[i].Instances.Instance);
		for (var j:Number = 0; j < 实例.length; j++){
			实例[j].x = Number(实例[j].x);
			实例[j].y = Number(实例[j].y);
		}
		实例配置.push(实例);
	}
	return 实例配置;
}

_root.解析并设置出生点配置 = function(关卡数据:Array){
	var 出生点配置 = [];
	for (var i:Number = 0; i < 关卡数据.length; i++){
		if(关卡数据[i].SpawnPoint == undefined){
			出生点配置.push(null);
			continue;
		}
		var 出生点数据:Object = _root.配置数据为数组(关卡数据[i].SpawnPoint.Point);
		for (var j:Number = 0; j < 出生点数据.length; j++){
			出生点数据[j].x = Number(出生点数据[j].x);
			出生点数据[j].y = Number(出生点数据[j].y);
			出生点数据[j].BiasX = 出生点数据[j].BiasX ? Number(出生点数据[j].BiasX) : null;
			出生点数据[j].BiasY = 出生点数据[j].BiasY ? Number(出生点数据[j].BiasY) : null;
			出生点数据[j].QuantityMax = 出生点数据[j].QuantityMax > 0 ? Number(出生点数据[j].QuantityMax) : 0;
			出生点数据[j].NoCount = 出生点数据[j].NoCount ? true : false;
		}
		出生点配置.push(出生点数据);
	}
	return 出生点配置;
}

// 解析并设置对话配置
_root.解析并设置对话配置 = function(关卡数据:Array)
{
	var 对话配置 = [];
	for (var i:Number = 0; i < 关卡数据.length; i++)
	{
		var 对话条数 = 0;
		var 对话数据 = [];
		var 对话列表 = _root.配置数据为数组(关卡数据[i].Dialogue.SubDialogue);
		var 单次对话 = _root.解析单次对话(对话列表);
		if(单次对话){
			对话条数 += 1;
		}
		对话数据.push(单次对话);
		var 波次列表 = _root.配置数据为数组(关卡数据[i].Wave.SubWave)
		for(var j:Number = 0; j < 波次列表.length; j++){
			对话列表 = _root.配置数据为数组(波次列表[j].Dialogue.SubDialogue);
			单次对话 = _root.解析单次对话(对话列表);
			if(单次对话){
				对话条数 += 1;
			}
			对话数据.push(单次对话);
		}
		if(对话条数 == 0){
			对话配置.push(null);
		}else{
			对话配置.push(对话数据);
		}
	}
	return 对话配置;
};
_root.解析单次对话 = function(对话列表:Array){
	var len = 对话列表.length;
	var 输出对话 = new Array(len);
	for(var i:Number = 0; i < len; i++){
		var 对话 = 对话列表[i];
		if (!对话){
			return null;
		}
		/*
		var sentence = [];
		var charsplit = 对话.Char.split("#");
		sentence.push(_root.getDialogueSpecialString(对话.Name));
		sentence.push(_root.getDialogueSpecialString(对话.Title));
		sentence.push(_root.getDialogueSpecialString(charsplit[0]));
		sentence.push(对话.Text);
		sentence.push(charsplit[1] != undefined ? charsplit[1] : "普通");
		*/
		var 对话对象 = _root.解析敌人属性(对话);
		输出对话[i] = {name:对话.Name, title:对话.Title, char:对话.Char, text:对话.Text, target:对话对象, imageurl:对话.ImageUrl};
	}
	return 输出对话;
}

_root.载入关卡数据 = function(stageType, url){
	var loader = new org.flashNight.gesh.xml.LoadXml.BaseStageXMLLoader(url);
	loader.load(function(data:Object):Void {
		_root.发布调试消息("load xml " + stageType + "  " + url);
		var 奖励品配置 = _root.配置数据为数组(data.Rewards.Reward);
		_root.关卡可获得奖励品 = 奖励品配置[0] != null ? _root.解析并设置奖励品配置(奖励品配置) : [];
		if(stageType == "无限过图"){
			_root.无限过图模式关卡计数 = -1;
			var subStageData = _root.配置数据为数组(data.SubStage);
			_root.无限过图基本配置 = _root.解析并设置基本配置(subStageData);
			_root.无限过图总关卡 = _root.解析并设置关卡配置(subStageData);
			_root.无限过图实例 = _root.解析并设置实例配置(subStageData);
			_root.无限过图出生点 = _root.解析并设置出生点配置(subStageData);
			_root.副本对话 = _root.解析并设置对话配置(subStageData);
			//
			_root.rogue敌人集合表 = _root.解析rogue敌人集合(data.Unions);
		}
	}, function():Void {
		_root.发布调试消息("fail to load xml " + stageType + "  " + url);
		onError();
	});
};

_root.配置外交地图关卡信息 = function(对象, StageInfo){
	_root.配置基础关卡信息(对象,StageInfo);
	对象.root场景进入位置名 = StageInfo.Address;
	对象.淡出动画淡出跳转帧 = StageInfo.RootFadeTransitionFrame;
	对象.onPress = function(){
		_root.场景进入位置名 = 对象.root场景进入位置名;
		_root.淡出动画.淡出跳转帧(对象.淡出动画淡出跳转帧);
	};
};

_root.配置基础关卡信息 = function(对象, StageInfo){
	对象.关卡路径 = StageInfo.url;
	对象.当前关卡名 = StageInfo.Name;
	对象.淡出跳转帧 = StageInfo.FadeTransitionFrame;
	对象.关卡开放条件 = StageInfo.UnlockCondition;
	对象.详细 = StageInfo.Description;
	对象.材料详细 = StageInfo.MaterialDetail;
	对象.起点帧 = StageInfo.StartFrame ? StageInfo.StartFrame : null;
	对象.终点帧 = StageInfo.EndFrame ? StageInfo.EndFrame : null;
	对象.限制词条 = StageInfo.Limitation ? _root.配置数据为数组(StageInfo.Limitation) : null;
	对象.限制难度等级 = StageInfo.LimitLevel ? StageInfo.LimitLevel : null;
};


/*
_root.自动输出关卡数据 = function(关卡数据地址){
	var 关卡数据 = _root.关卡数据缓存[关卡数据地址];
	if (关卡数据 != undefined){
		for (var 属性 in 关卡数据){
			_root.输出对象属性(关卡数据[属性],属性);
		}
	}else{
		_root.发布调试消息("没有找到指定的关卡数据：" + 关卡数据地址);
	}
};// 检查对象中的所有属性是否为 undefined


_root.关卡数据缓存上限 = 32;
_root.关卡数据缓清理许可 = true;
_root.关卡数据地址 = "/stages/";
_root.关卡缓存数据数组 = [];
_root.关卡缓存数据数组.push({key:"关卡类型", value:关卡类型});
_root.关卡缓存数据数组.push({key:"关卡可获得奖励品", value:关卡引用.关卡可获得奖励品});
_root.关卡缓存数据数组.push({key:"无限过图基本配置", value:关卡引用.无限过图基本配置});
_root.关卡缓存数据数组.push({key:"无限过图总关卡", value:关卡引用.无限过图总关卡});
_root.关卡缓存数据数组.push({key:"无限过图实例", value:关卡引用.无限过图实例});
_root.关卡缓存数据数组.push({key:"无限过图出生点", value:关卡引用.无限过图出生点});
_root.关卡缓存数据数组.push({key:"副本对话", value:关卡引用.副本对话});
_root.关卡缓存数据数组.push({key:"rogue敌人集合表", value:关卡引用.rogue敌人集合表});
_root.关卡缓存数据数组.push({key:"当前关卡名", value:关卡引用.当前关卡名});
_root.关卡缓存数据数组.push({key:"淡出跳转帧", value:关卡引用.淡出跳转帧});
_root.关卡缓存数据数组.push({key:"关卡开放条件", value:关卡引用.关卡开放条件});
_root.关卡缓存数据数组.push({key:"详细", value:关卡引用.详细});
_root.关卡缓存数据数组.push({key:"材料详细", value:关卡引用.材料详细});
_root.关卡缓存数据数组.push({key:"起点帧", value:关卡引用.起点帧});
_root.关卡缓存数据数组.push({key:"终点帧", value:关卡引用.终点帧});
_root.关卡缓存数据数组.push({key:"限制词条", value:关卡引用.限制词条});
_root.关卡缓存数据数组.push({key:"淡出动画淡出跳转帧", value:关卡引用.淡出动画淡出跳转帧});
_root.关卡缓存数据数组.push({key:"root场景进入位置名", value:关卡引用.root场景进入位置名});
_root.解析子文件夹名称 = function(xml文件地址:String, 固定地址起点:String):String {
	var 起始位置:Number = xml文件地址.indexOf(固定地址起点) + 固定地址起点.length;
	var 停止位置:Number = xml文件地址.indexOf("/", 起始位置);
	if (停止位置 == -1){
		return "";// 如果没有找到下一个 '/'，返回空字符串
	}
	return xml文件地址.substring(起始位置, 停止位置);
};

_root.清理缓存 = function(当前子文件夹名称:String):Void 
{
	var 缓存计数:Number = 0;
	for (var 缓存键 in _root.关卡数据缓存){
		缓存计数++;
	}
	if (缓存计数 > _root.关卡数据缓存上限 and _root.关卡数据缓清理许可)
	{
		_root.关卡数据缓清理许可 = false;
		for (var 缓存键 in _root.关卡数据缓存)
		{
			var 缓存中的子文件夹名称:String = _root.解析子文件夹名称(缓存键, _root.关卡数据地址);
			if (缓存中的子文件夹名称 != 当前子文件夹名称)
			{
				delete _root.关卡数据缓存[缓存键];// 清除缓存
			}
		}
		_root.发布消息("缓存数量过多，释放[" + 当前子文件夹名称 + "]以外的关卡缓存");
		_root.关卡数据缓清理许可 = true;
	}
};

_root.从关卡缓存中读取数据 = function(目标对象:Object, 缓存键:String):Void 
{// 检查缓存是否存在
	if (_root.关卡数据缓存[缓存键])
	{
		var 缓存数据:Object = _root.关卡数据缓存[缓存键];// 遍历缓存中的每个键值对
		for (var 属性 in 缓存数据)
		{// 将缓存值赋给目标对象的对应属性
			目标对象[属性] = 缓存数据[属性];
		}
		if (目标对象.root场景进入位置名 != undefined and 目标对象.淡出动画淡出跳转帧 != undefined)
		{
			目标对象.onPress = function()
			{
				_root.场景进入位置名 = 目标对象.root场景进入位置名;
				_root.淡出动画.淡出跳转帧(目标对象.淡出动画淡出跳转帧);
			};
		}
		_root.发布调试消息("load 缓存  " + 缓存数据.关卡类型 + "  " + 缓存键);
	}
	// 清理缓存                              
	_root.清理缓存(_root.解析子文件夹名称(缓存键, _root.关卡数据地址));
};

_root.配置关卡缓存数据 = function(关卡引用:Object, xml文件地址:String):Void 
{// 检查并初始化缓存对象
	if (!_root.关卡数据缓存[xml文件地址])
	{
		_root.关卡数据缓存[xml文件地址] = {};
	}
	// 遍历数据数组，将有效数据添加到缓存中                                                       
	for (var i:Number = 0; i < _root.关卡缓存数据数组.length; i++)
	{
		var 数据项:Object = _root.关卡缓存数据数组[i];
		if (关卡引用[数据项.key] !== undefined)
		{
			_root.关卡数据缓存[xml文件地址][数据项.key] = 关卡引用[数据项.key];
		}
	}
};// XML 加载成功时的处理逻辑
*/

_root.配置关卡属性 = function(StageName:String):Void {
	var 关卡引用:Object = this;
	var StageInfo:Object = _root.StageInfoDict[StageName];
	this.关卡类型 = StageInfo.Type;
	switch (this.关卡类型){
		case "无限过图" :
		case "初期关卡" :
			_root.配置基础关卡信息(关卡引用,StageInfo);
			break;
		case "外交地图" :
			if(!_root.isStageUnlocked(StageName)){
				this._visible = false;
			}else{
				_root.配置外交地图关卡信息(关卡引用,StageInfo);//外交地图数据配置
			}
			break;
	}/// 配置缓存数据
	// _root.配置关卡缓存数据(关卡引用,xml文件地址);
	//硬代码删除未xml化副本的起始帧变量
	delete this.NPC任务_任务_起始帧;
};// 使用函数

_root.加载随机名称库 = function(xml文件地址:String):Void 
{
	var 名称库XML:XML = new XML();
	名称库XML.ignoreWhite = true;
	名称库XML.onLoad = function(加载成功:Boolean)
	{
		if (加载成功)
		{
			var 名称节点数组:Array = this.firstChild.childNodes;
			var len = 名称节点数组.length;
			var 随机名称库 = new Array(len);
			for (var i:Number = 0; i < len; i++)
			{
				if (名称节点数组[i].nodeName == "Name")
				{
					随机名称库[i] = 名称节点数组[i].firstChild.nodeValue;
				}
			}
			_root.随机名称库 = 随机名称库;
			//trace("随机名称库加载成功: " + _root.随机名称库);
			//_root.服务器.发布服务器消息("随机名称库加载成功");
		}
		else
		{
			//_root.服务器.发布服务器消息("无法加载 XML 文件: " + xml文件地址);
		}
	};// 加载 XML 文件
	名称库XML.load(xml文件地址);
};

_root.加载并配置战队信息 = function(xml文件地址:String):Void 
{
	var 战队信息XML:XML = new XML();
	战队信息XML.ignoreWhite = true;
	战队信息XML.onLoad = function(加载成功:Boolean)
	{
		if (加载成功)
		{
			_root.战队信息数组 = [];
			var teamNodes:Array = this.firstChild.childNodes;
			for (var i:Number = 0; i < teamNodes.length; i++)
			{
				var team:Object = {};
				var childNodes:Array = teamNodes[i].childNodes;
				for (var j:Number = 0; j < childNodes.length; j++)
				{
					var nodeName:String = childNodes[j].nodeName;
					var nodeValue:String = childNodes[j].firstChild.nodeValue;
					switch (nodeName)
					{
						case "Title" :
							team.战队抬头 = nodeValue;
							break;
						case "Name" :
							team.战队名 = nodeValue;
							break;
						case "Weight" :
							team.权重 = parseInt(nodeValue);
							break;
						case "Necklace" :
							team.战队项链 = nodeValue;
							break;
					}
				}
				_root.战队信息数组.push(team);
			}//trace("战队信息加载成功: " + _root.战队信息数组);
		}
		else
		{//trace("无法加载 XML 文件: " + xml文件地址);
		}
	};// 加载 XML 文件
	战队信息XML.load(xml文件地址);
};

_root.加载并配置佣兵随机对话 = function(xml文件地址:String):Void 
{
	var 随机对话XML:XML = new XML();
	随机对话XML.ignoreWhite = true;
	随机对话XML.onLoad = function(加载成功:Boolean)
	{
		if (加载成功)
		{
			var dialogueNodes:Array = this.firstChild.childNodes;
			var len = dialogueNodes.length;
			_root.佣兵随机对话 = new Array(len);
			for (var i:Number = 0; i < len; i++)
			{
				var dialogue:Object = {};
				var childNodes:Array = dialogueNodes[i].childNodes;
				for (var j:Number = 0; j < childNodes.length; j++)
				{
					var nodeName:String = childNodes[j].nodeName;
					var nodeValue:String = childNodes[j].firstChild.nodeValue;
					dialogue[nodeName] = nodeValue;// 映射标签名和其对应的内容

				}
				_root.佣兵随机对话[i] = dialogue;
			}//trace("佣兵随机对话配置成功: " + _root.佣兵随机对话);
		}
		else
		{//trace("无法加载 XML 文件: " + xml文件地址);
		}
	};// 加载 XML 文件
	随机对话XML.load(xml文件地址);
};

_root.加载并配置非人形佣兵随机对话 = function(xml文件地址:String):Void 
{
	var 随机对话XML:XML = new XML();
	随机对话XML.ignoreWhite = true;
	随机对话XML.onLoad = function(加载成功:Boolean)
	{
		if (加载成功)
		{
			var groups:Array = _root.解析XML节点(this.firstChild).Group;
			var len = groups.length;
			_root.非人形佣兵随机对话 = new Object();
			for(var i:Number = 0; i < len; i++){
				var identity = _root.配置数据为数组(groups[i].Identity);
				var dialogue = _root.配置数据为数组(groups[i].Dialogue);
				for(var j:Number = 0; j < identity.length; j++)
				_root.非人形佣兵随机对话[identity[j]] = dialogue;
			}
		}
		else
		{//trace("无法加载 XML 文件: " + xml文件地址);
		}
	};// 加载 XML 文件
	随机对话XML.load(xml文件地址);
};

_root.加载并配置NPC对话 = function(xml文件地址:String):Void 
{
	var 对话XML:XML = new XML();
	对话XML.ignoreWhite = true;
	对话XML.onLoad = function(加载成功:Boolean){
		if (加载成功){
			var NPC对话 = {};
			var NPC对话数据 = _root.解析XML节点(this.firstChild);
			var dialogueNodes:Array = NPC对话数据.Dialogues;
			for (var i:Number = 0; i < dialogueNodes.length; i++){
				var NPC名称 = dialogueNodes[i].Name;
				NPC对话[NPC名称] = [];
				var NPC_Dialogue = _root.配置数据为数组(dialogueNodes[i].Dialogue);
				for (var j:Number = 0; j < NPC_Dialogue.length; j++){
					var 对话obj = {};
					var 对话列表 = _root.配置数据为数组(NPC_Dialogue[j].SubDialogue);
					对话obj.TaskRequirement = !isNaN(TaskRequirement) ? Number(NPC_Dialogue[j].TaskRequirement) : 0;
					对话obj.Dialogue = _root.解析单次对话(对话列表);
					NPC对话[NPC名称].push(对话obj);
				}
			}
			_root.NPC对话 = NPC对话;
		}else{
			//_root.服务器.发布服务器消息("无法加载 XML 文件: " + xml文件地址);
		}
	};
	对话XML.load(xml文件地址);
};

_root.读取NPC对话 = function(NPC名称:String){
	var 总对话 = _root.NPC对话[NPC名称];
	if(!总对话 || !总对话.length){
		return null;
	}
	var 输出对话 = [];
	for (var i:Number = 0; i < 总对话.length; i++){
		if(总对话[i].TaskRequirement > _root.主线任务进度){
			continue;
		}
		输出对话.push(总对话[i].Dialogue);
	}
	return 输出对话;
};

_root.读取并组装NPC对话 = function(NPC名称:String){
	var 总对话 = _root.读取NPC对话(NPC名称);
	var 输出对话 = new Array(总对话.length);
	for(var i:Number = 0; i < 总对话.length; i++){
		输出对话[i] = _root.组装单次对话(总对话[i]);
	}
	return 输出对话;
}

_root.加载并配置发型库 = function(xml文件地址:String):Void 
{
	var 发型:XML = new XML();
	发型.ignoreWhite = true;
	发型.onLoad = function(加载成功:Boolean){
		if (加载成功){
			var hairstyle = _root.解析XML节点(this.firstChild)
			var hairNodes:Array = hairstyle.Hair;
			var len = hairNodes.length;
			var 发型库 = new Array(len);
			var 发型名称库 = new Array(len);
			var 发型价格 = new Array(len);
			for(var i:Number = 0; i < len; i++){
				发型库[i] = hairNodes[i].Identifier ? hairNodes[i].Identifier : "";
				发型名称库[i] = hairNodes[i].Name ? hairNodes[i].Name : "";
				发型价格[i] = isNaN(hairNodes[i].Price) ? 0 : Number(hairNodes[i].Price);
			}
			_root.发型库 = 发型库;
			_root.发型名称库 = 发型名称库;
			_root.发型价格 = 发型价格;
		}else{
			//_root.服务器.发布服务器消息("无法加载 XML 文件: " + xml文件地址);
		}
	};
	发型.load(xml文件地址);
};

_root.配置关卡环境数据 = function(data:Object):Void {
	var 关卡环境设置 = {};
	var environmentNodes:Array = data.Environment;
	// 默认配置
	var 默认配置 = _root.天气系统.默认环境配置;
	关卡环境设置.Default = 默认配置;//把默认配置也存入环境设置
	for (var i:Number = 0; i < environmentNodes.length; i++){
		var 环境信息:Object = {};
		var child_Nodes:Array = environmentNodes[i];
		if(!child_Nodes.BackgroundURL) continue;
		
		关卡环境设置[child_Nodes.BackgroundURL] = _root.配置环境信息(child_Nodes, 默认配置);// 使用 URL 作为键存储环境信息
	}
	_root.天气系统.关卡环境设置 = 关卡环境设置;
};

_root.配置场景环境数据 = function(data:Object):Void {
	var 场景环境设置 = {};
	var environmentNodes:Array = data.Environment;
	// 默认配置
	var 默认配置 = _root.天气系统.默认环境配置;
	场景环境设置.Default = 默认配置;//把默认配置也存入环境设置
	for (var i:Number = 0; i < environmentNodes.length; i++){
		var 环境信息:Object = {};
		var child_Nodes:Array = environmentNodes[i];
		if(!child_Nodes.BackgroundURL) continue;
		
		场景环境设置[child_Nodes.BackgroundURL] = _root.配置环境信息(child_Nodes, 默认配置);// 使用 URL 作为键存储环境信息
	}
	_root.天气系统.场景环境设置 = 场景环境设置;
};


_root.解析背景元素 = function(背景元素数据:Array):Object{
	var len = 背景元素数据.length;
	if(len <= 0) return null;
	for(var i = 0; i < len; i++){
		if(!背景元素数据[i].name) 背景元素数据[i].name = "element"+i;
		背景元素数据[i].x = Number(背景元素数据[i].x);
		背景元素数据[i].y = Number(背景元素数据[i].y);
		if(!背景元素数据[i].depth) 背景元素数据[i].depth = null;
	}
	return 背景元素数据;
}


_root.色彩引擎 = {};
_root.色彩引擎.加载并配置色彩预设 = function(xml文件地址:String):Void 
{
    var colorEngineXML:XML = new XML();
    colorEngineXML.ignoreWhite = true; // 忽略空白字符

    colorEngineXML.onLoad = function(success:Boolean)
	{
		if (success) 
		{
            _root.色彩引擎.光照等级映射表 = {};
            var presetSets:Array = _root.解析XML节点(this.firstChild);
			var presetsData:Object = presetSets.PresetSet;

			for(var i = 0; i < presetsData.length; ++i)
			{
				var presets:Object = presetsData[i];
				var name:String = presets.name;
				var presetLevels = presets.Preset;
				var tempPreset:Object = {};
				for(var j:Number = 0; j < presetLevels.length; ++j)
				{
					var preset:Object = presetLevels[j];
					//_root.服务器.发布服务器消息("单位获取成功: " + _root.常用工具函数.对象转JSON(preset, true));
					var presetLevel:Number = Number(preset.level); // 将级别转为数字，用作数组索引
					tempPreset[presetLevel] = {
					亮度: preset.Brightness != undefined ? Number(preset.Brightness) : 0,
					对比度: preset.Contrast != undefined ? Number(preset.Contrast) : 0,
					饱和度: preset.Saturation != undefined ? Number(preset.Saturation) : 0,
					色相: preset.Hue != undefined ? Number(preset.Hue) : 0,
					红色乘数: preset.redMultiplier != undefined ? Number(preset.redMultiplier) : 1,
					绿色乘数: preset.greenMultiplier != undefined ? Number(preset.greenMultiplier) : 1,
					蓝色乘数: preset.blueMultiplier != undefined ? Number(preset.blueMultiplier) : 1,
					透明乘数: preset.alphaMultiplier != undefined ? Number(preset.alphaMultiplier) : 1,
					红色偏移: preset.redOffset != undefined ? Number(preset.redOffset) : 0,
					绿色偏移: preset.greenOffset != undefined ? Number(preset.greenOffset) : 0,
					蓝色偏移: preset.blueOffset != undefined ? Number(preset.blueOffset) : 0,
					透明偏移: preset.alphaOffset != undefined ? Number(preset.alphaOffset) : 0
				};
				}
				_root.色彩引擎.光照等级映射表[name] = tempPreset;
				
			}
            _root.服务器.发布服务器消息("色彩预设表已成功加载并配置。");
			_root.色彩引擎.初始化光照参数缓存();
        } 
		else 
		{
            _root.服务器.发布服务器消息("无法加载XML文件: " + xml文件地址);
        }
    };
	
    colorEngineXML.load(xml文件地址);
};

_root.加载并配置宠物信息 = function(xml文件地址:String):Void 
{
	var 宠物XML:XML = new XML();
	宠物XML.ignoreWhite = true;
	宠物XML.onLoad = function(加载成功:Boolean){
		if (加载成功){
			var 宠物数据 = _root.解析XML节点(this.firstChild);
			_root.宠物库 = 宠物数据.Pet;
		}else{
			//_root.服务器.发布服务器消息("无法加载 XML 文件: " + xml文件地址);
		}
	};
	宠物XML.load(xml文件地址);
};


_root.加载并配置技能表 = function(xml文件地址:String):Void 
{
	var 技能XML:XML = new XML();
	技能XML.ignoreWhite = true;
	技能XML.onLoad = function(加载成功:Boolean){
		if (加载成功){
			var 技能表 = _root.解析XML节点(this.firstChild).Skill;
			var 技能表对象 = new Object();
			for(var i = 0; i < 技能表.length; i++){
				var 技能对象 = 技能表[i];
				if(!技能对象.Name || 技能对象.Name == "") continue;
				技能对象.id = i;
				技能对象.Passive = 技能对象.Type.indexOf("被动") > -1;
				技能对象.Equippable = 技能对象.Type != "被动";
				技能表对象[技能对象.Name] = 技能对象;
			}
			_root.技能表 = 技能表;
			_root.技能表对象 = 技能表对象;
		}else{
			//_root.服务器.发布服务器消息("无法加载 XML 文件: " + xml文件地址);
		}
	};
	技能XML.load(xml文件地址);
};


_root.加载过场背景与文本 = function(xml文件地址:String):Void 
{
	var 背景XML:XML = new XML();
	背景XML.ignoreWhite = true;
	背景XML.onLoad = function(加载成功:Boolean){
		if (加载成功){
			var 加载背景列表 = new Object();
			var loading = _root.解析XML节点(this.firstChild);
			加载背景列表.基地背景 = loading.BaseImage.Image;
			加载背景列表.关卡背景 = loading.StageImage.Image;
			加载背景列表.本次背景 = null;
			_root.加载背景列表 = 加载背景列表;
			_root.提示文本列表 = loading.LoadingText.Group;
		}else{
			//_root.服务器.发布服务器消息("无法加载 XML 文件: " + xml文件地址);
		}
	};
	背景XML.load(xml文件地址);
};


// 解析 XML 节点
_root.处理带HTML标签的文本 = function(节点:XMLNode):String 
{// 这里假设传入的节点是包含HTML标签的文本节点的父节点
	// 检查节点是否有子节点
	if (!节点.hasChildNodes()){
		return "";
	}
	// 获取节点的内部XML字符串                                                                                                         
	var 节点内部XML:String = 节点.toString();// 移除节点标签，只保留内部的文本内容
	var 开始标签结束位置:Number = 节点内部XML.indexOf(">");
	var 结束标签开始位置:Number = 节点内部XML.lastIndexOf("<");
	var 内部文本:String = 节点内部XML.substring(开始标签结束位置 + 1, 结束标签开始位置);
	return 内部文本;
};
_root.解析XML节点 = function(节点:XMLNode):Object 
{// 如果节点是文本节点，直接返回其值
	if (节点.nodeType == 3)
	{
		return _root.转换数据类型(节点.nodeValue);
	}
	// 对象用于存储节点数据                                                                                                      
	var 解析结果:Object = {};// 遍历所有子节点
	for (var i = 0; i < 节点.childNodes.length; i++)
	{
		var 子节点:XMLNode = 节点.childNodes[i];
		var 节点名:String = 子节点.nodeName;// 特别处理 Description 节点
		if ((节点名 == "Description" or 节点名 == "MaterialDetail") && 子节点.nodeType == 1)
		{
			解析结果[节点名] = _root.转换HTML实体回文本(子节点.firstChild.nodeValue);
			continue;
		}
		// 检查是否有子节点                                                                                                      
		if (子节点.hasChildNodes())
		{
			var 子节点值:Object;
			if (子节点.childNodes.length == 1 && 子节点.firstChild.nodeType == 3)
			{
				子节点值 = _root.转换数据类型(子节点.firstChild.nodeValue);
			}
			else
			{// 递归解析子节点
				子节点值 = _root.解析XML节点(子节点);
			}// 检查是否已经存在同名节点
			if (解析结果[节点名] !== undefined)
			{// 如果已经有同名节点，则转换为数组
				if (!(解析结果[节点名] instanceof Array))
				{
					解析结果[节点名] = [解析结果[节点名]];
				}
				解析结果[节点名].push(子节点值);
			}
			else
			{
				解析结果[节点名] = 子节点值;
			}
		}
	}
	return 解析结果;
};// 将字符串转换为适当的数据类型
_root.转换数据类型 = function(value:String):Object 
{
	if (!isNaN(Number(value))){
		return Number(value);
	} else if (value.toLowerCase() == "true"){
		return true;
	} else if (value.toLowerCase() == "false"){
		return false;
	}
	return value;
};//_root.配置关卡属性("test.xml");