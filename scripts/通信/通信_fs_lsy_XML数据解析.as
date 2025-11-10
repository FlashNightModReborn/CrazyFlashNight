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
			// _root.rogue敌人集合表 = _root.解析rogue敌人集合(data.Unions);
			org.flashNight.arki.scene.StageManager.instance.initialize(data.SubStage);
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

	// _root.发布消息("读取NPC对话: " + NPC名称 + " 对话数量: " + (总对话 ? 总对话.length : 0));
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

	// _root.发布消息("过滤后NPC对话数量: " + 输出对话.length);
	return 输出对话;
};

_root.读取并组装NPC对话 = function(NPC名称:String){
	var 总对话 = _root.读取NPC对话(NPC名称);
	var 输出对话 = new Array(总对话.length);
	for(var i:Number = 0; i < 总对话.length; i++){
		输出对话[i] = _root.组装单次对话(总对话[i]);
	}

	// _root.发布消息(NPC名称, "组装后NPC对话数量: " + 输出对话.length);
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