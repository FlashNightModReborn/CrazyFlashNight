
import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.gesh.object.*;


_root.删佣兵 = function(佣兵ID)
{
	删佣兵数组号 = -1;
	var 迭代器 = 0;
	while (迭代器 < _root.佣兵个数限制)
	{
		if (_root.同伴数据[迭代器][2] == 佣兵ID)
		{
			删佣兵数组号 = 迭代器;
			break;
		}
		迭代器 += 1;
	}
	if (删佣兵数组号 == -1)
	{
		return undefined;
	}
	if(_root.同伴数据[删佣兵数组号][19] && _root.同伴数据[删佣兵数组号][19].是否杂交 == false){
		_root.可雇佣兵.push(_root.同伴数据[删佣兵数组号]);
	}
	if(_root.同伴数据[删佣兵数组号][19] && _root.同伴数据[删佣兵数组号][19].隐藏){
		_root.隐藏的可雇佣兵.push(_root.同伴数据[删佣兵数组号]);
	}
	_root.同伴数--;
	_root.同伴数据[删佣兵数组号] = [];
	temp_同伴数据 = [];
	迭代器 = 0;
	while (迭代器 < _root.佣兵个数限制)
	{
		if (_root.同伴数据[迭代器][0] != undefined)
		{
			temp_同伴数据.push(_root.同伴数据[迭代器]);
		}
		迭代器 += 1;
	}
	_root.同伴数据 = temp_同伴数据;
	_root.gameworld[_root.菜单MC对应名].removeMovieClip();
	for (var 单位 in _root.gameworld)
	{
		if (_root.gameworld[单位].用户ID == 佣兵ID)
		{
			_root.gameworld[单位].removeMovieClip();
		}
	}
};

_root.初始化佣兵编号缓存 = function() {
    var 游戏世界 = _root.gameworld;

    // 初始化并设置为不可枚举
    if (游戏世界.佣兵编号缓存 == undefined) {
        游戏世界.佣兵编号缓存 = {权重列表: [], 总权重: 0, 已初始化: false};

        // 设置 `佣兵编号缓存` 为不可枚举
        _global.ASSetPropFlags(游戏世界, ["佣兵编号缓存"], 1, false);
    }
};


_root.更新佣兵编号缓存 = function()
{
	_root.初始化佣兵编号缓存();
	var 缓存 = _root.gameworld.佣兵编号缓存;
	if (!缓存.已初始化)
	{
		缓存.权重列表 = [];
		缓存.总权重 = 0;

		// 计算等级分界线，至少为5级，或者是玩家等级的20%
		var 等级分界线 = Math.max(5, Math.floor(_root.等级 * 0.2));

		for (var i = 0; i < _root.可雇佣兵.length; i++)
		{
			var 等级差 = Math.abs(_root.等级 - _root.可雇佣兵[i][0]);
			var 权重 = 等级差 <= 等级分界线 ? 1 : 1 / Math.sqrt(等级差 - 等级分界线 + 1) / 2;
			缓存.权重列表.push(权重);
			缓存.总权重 += 权重;
		}

		缓存.已初始化 = true;
	}
};

_root.获取随机佣兵编号 = function(已上场佣兵编号)
{
	_root.更新佣兵编号缓存();
	var 缓存 = _root.gameworld.佣兵编号缓存;

	var 可选择佣兵编号 = [];
	for (var i = 0; i < 缓存.权重列表.length; i++)
	{
		if (已上场佣兵编号[i] == undefined)
		{
			可选择佣兵编号.push(i);
		}
	}

	if (可选择佣兵编号.length == 0)
	{
		return -1;// 如果没有可选佣兵，返回 -1
	}

	var 随机数 = _root.basic_random() * 缓存.总权重;
	var 累计 = 0;
	for (var j = 0; j < 可选择佣兵编号.length; j++)
	{
		var 索引 = 可选择佣兵编号[j];
		累计 += 缓存.权重列表[索引];
		if (随机数 <= 累计)
		{
			return 索引;
		}
	}

	return -1;// 理论上不应该到达这里
};

_root.生成游戏世界佣兵 = function(添加佣兵函数, 机率, 是否门口)
{
	var 游戏世界 = _root.gameworld;
	var 场上佣兵总人数 = _root.成功率(100 / 机率) ? _root.随机整数(1, 3) : 0.5;
	var 面积系数 = (_root.Xmax - _root.Xmin) * (_root.Ymax - _root.Ymin) / _root.面积系数;
	if(!isNaN(游戏世界.面积系数)) 面积系数 *= 游戏世界.面积系数;
	场上佣兵总人数 = Math.floor(Math.max(场上佣兵总人数 * 面积系数, 1));
	if (场上佣兵总人数 > _root.可雇佣兵.length){
		场上佣兵总人数 = _root.可雇佣兵.length;
	}

	var 已上场佣兵编号 = [];

	for (var 迭代器 = 0; 迭代器 < 场上佣兵总人数; 迭代器++)
	{
		var 随机编号 = _root.获取随机佣兵编号(已上场佣兵编号);
		if (随机编号 == -1)
		{
			break;
		}
		// 没有更多可用佣兵，跳出循环   
		_root.帧计时器.添加单次任务(function(是否门口, 随机编号, 添加佣兵函数, 场上佣兵总人数, frameFlag) {
			// _root.发布消息(frameFlag, _root.gameworld.frameFlag)
			if(frameFlag != _root.gameworld.frameFlag) return;

			if (是否门口)
			{
				var 刷佣兵的门 = _root.随机选择数组元素(_root.gameworld.出生点列表);
				添加佣兵函数(随机编号, 刷佣兵的门._x, 刷佣兵的门._y);
			}
			else
			{
				添加佣兵函数(随机编号);
			}
		}, _root.随机整数(1,场上佣兵总人数 * 2) * 1000, 是否门口, 随机编号, 添加佣兵函数, 场上佣兵总人数, _root.gameworld.frameFlag)                                                                                                                     

		已上场佣兵编号[随机编号] = -1;// 标记编号已使用
	}
};

_root.门口刷可雇用玩家 = function(){
	if (_root.成功率(30)){
		_root.生成游戏世界佣兵(_root.添加场上佣兵,机率,false);
	}else{
		_root.生成游戏世界佣兵(_root.添加场上佣兵,机率,true);
	}
};

_root.场景刷可雇用玩家 = function(机率)
{
	_root.生成游戏世界佣兵(_root.添加场上佣兵,机率,false);
};

_root.场景随机有效位置 = function(){
	var 游戏世界 = _root.gameworld;
	var tempx;
	var tempy;
	var pt;
	for(var i=0; i<99; i++){
		tempx = _root.随机整数(_root.Xmin, _root.Xmax);
		tempy = _root.随机整数(_root.Ymin, _root.Ymax);
		if (!_root.collisionLayer.hitTest(tempx, tempy, true)){
			break;
		}else{
			// _root.gameworld.attachMovie("point","p1" + _root.随机整数(0, 999),_root.gameworld.getNextHighestDepth(),{_x:tempx, _y:tempy});
		}
	}
	return {x:tempx, y:tempy};
};
_root.佣兵杂交序号 = function(n, 杂交几率, 杂交许可)
{
	if (_root.成功率(杂交几率) and 杂交许可)
	{
		return _root.获取随机索引(_root.可雇佣兵);
	}
	return n;
};
_root.拼接生成杂交佣兵名 = function(原佣兵名称, 杂交佣兵名称)
{
	var 切割点原名称 = _root.随机整数(0, 原佣兵名称.length - 1);
	var 切割点杂交名称 = _root.随机整数(0, 杂交佣兵名称.length - 1);
	var 原名称前半部 = 原佣兵名称.substring(0, 切割点原名称);
	var 杂交名称后半部 = 杂交佣兵名称.substring(切割点杂交名称);
	return 原名称前半部 + 杂交名称后半部;
};
_root.分解音节 = function(名称)
{
	// 这个函数需要根据您的具体需求来实现，以下是一个简化的例子
	var 音节 = [];
	for (var i = 0; i < 名称.length; i += 2)
	{
		音节.push(名称.substring(i, Math.min(i + 2, 名称.length)));
	}
	return 音节;
};
_root.音节生成杂交佣兵名 = function(原佣兵名称, 杂交佣兵名称)
{
	var 原名称音节 = _root.分解音节(原佣兵名称);
	var 杂交名称音节 = _root.分解音节(杂交佣兵名称);
	var 新名称音节 = [];

	var 从原名称中取的音节数 = _root.随机整数(1, 原名称音节.length);
	var 从杂交名称中取的音节数 = _root.随机整数(1, 杂交名称音节.length);

	for (var i = 0; i < 从原名称中取的音节数; i++)
	{
		新名称音节.push(_root.随机选择数组元素(原名称音节));
	}

	for (var j = 0; j < 从杂交名称中取的音节数; j++)
	{
		新名称音节.push(_root.随机选择数组元素(杂交名称音节));
	}

	return 新名称音节.join('');
};

_root.常规生成杂交佣兵名 = function(原佣兵名称, 杂交佣兵名称)
{
	return _root.成功率(50) ? 原佣兵名称 : 杂交佣兵名称;
};
_root.战队信息数组 = [];

_root.加载并配置战队信息("data/hybrid_mercenaries/teams.xml");
_root.加载随机名称库("data/hybrid_mercenaries/name.xml");
_root.加载并配置佣兵随机对话("data/hybrid_mercenaries/dialogues.xml");

_root.随机生成杂交佣兵名 = function()
{
	// 从随机名称库中随机选择一个名称
	var 随机名称 = _root.随机选择数组元素(_root.随机名称库);
	return 随机名称;
};
_root.检查并返回有效佣兵名称 = function(佣兵名称)
{
	// 检查佣兵名称是否有效
	if (佣兵名称 == undefined or 佣兵名称 == null or 佣兵名称.trim() === "")
	{
		return "无名的佣兵";// 返回默认名称
	}
	return 佣兵名称;// 返回有效的佣兵名称
};
sd;

_root.名称生成函数集 = [];
//_root.名称生成函数集.push({函数:_root.拼接生成杂交佣兵名, 权重:0.5});
//_root.名称生成函数集.push({函数:_root.音节生成杂交佣兵名, 权重:0.5});
//_root.名称生成函数集.push({函数:_root.常规生成杂交佣兵名, 权重:1});
_root.名称生成函数集.push({函数:_root.随机生成杂交佣兵名, 权重:4});

_root.基于权重随机选择函数 = function(函数集)
{
	var 总权重 = 0;
	for (var i = 0; i < 函数集.length; i++)
	{
		总权重 += 函数集[i].权重;
	}

	var 随机数 = _root.basic_random() * 总权重;
	var 累计权重 = 0;
	for (var j = 0; j < 函数集.length; j++)
	{
		累计权重 += 函数集[j].权重;
		if (随机数 <= 累计权重)
		{
			return 函数集[j].函数;
		}
	}
	return null;// 理论上不应该到达这里
};

_root.佣兵杂交名称 = function(n, 杂交许可, 战队信息)
{
	if (!杂交许可)
	{
		return _root.检查并返回有效佣兵名称(_root.可雇佣兵[n][1]);
	}

	var 原佣兵名称 = _root.检查并返回有效佣兵名称(_root.可雇佣兵[n][1]);
	var 杂交佣兵名称 = _root.检查并返回有效佣兵名称(_root.随机选择数组元素(_root.可雇佣兵)[1]);

	var 选中的生成函数 = _root.基于权重随机选择函数(_root.名称生成函数集);
	if (选中的生成函数 != null)
	{
		return _root.按宽度截断字符串(战队信息.战队抬头 + " " + 选中的生成函数(原佣兵名称, 杂交佣兵名称), 30);
	}
	return "无名的佣兵";// 如果没有合适的函数被选中
};
_root.杂交许可 = function(输入字符串)
{
	var 装备排除表 = ["小熊", "诛神","轶事奇人","炎魔","合金","钛","章鱼","Andy","JK","余烬","军阀","装甲头盔","奇美拉","牙狼", "K5", "兽王", "异形"];
	for (var i = 0; i < 装备排除表.length; i++)
	{
		if (输入字符串.indexOf(装备排除表[i]) != -1)
		{
			return false;
		}
	}
	return true;
};
_root.装备杂交许可 = function(杂交装备, 装备杂交几率)
{
	// 检查杂交装备是否为null或undefined或它们的字符串形式，或者空字符串
	if (杂交装备 === null or 杂交装备 === "null" or 杂交装备 === undefined or 杂交装备 === "undefined" or 杂交装备 === "")
	{
		return false;
	}
	// 进一步检查杂交装备是否为合法字符串                                                                                                                                     
	if (typeof 杂交装备 !== "string" or 杂交装备.trim().length === 0)
	{
		return false;
	}
	// 检查是否满足随机杂交几率                                                                                                                                     
	return _root.成功率(装备杂交几率);
};
_root.杂交可雇佣兵 = function(n, 杂交几率, 杂交许可)
{
	var 样本佣兵 = _root.深拷贝数组(_root.可雇佣兵[n]);
	var 佣兵杂交等级 = _root.可雇佣兵[_root.佣兵杂交序号(n, 100, 杂交许可)][0];
	var 战队信息 = _root.根据权重获取随机对象(_root.战队信息数组);
	var 装备杂交系数 = 3;
	var 杂交装备等级;
	var 自身装备等级;
	var 杂交装备类型;
	var 装备类型数组 = ["头部装备", "上装装备", "手部装备", "下装装备", "脚部装备", "", "长枪", "手枪", "手枪", "刀", "手雷"];		

	for(var 迭代器 = 0;迭代器 <= 16;迭代器++)
	{
		switch(迭代器)
		{
			case 0:样本佣兵[0] = Math.min(Math.floor(样本佣兵[0] * 1.5), Math.max(样本佣兵[0], 佣兵杂交等级));break;
			case 1:样本佣兵[1] = _root.佣兵杂交名称(n, 杂交许可, 战队信息);break;
			case 3:case 4:case 5:case 17:
				样本佣兵[迭代器] = _root.可雇佣兵[_root.佣兵杂交序号(n, 杂交几率, 杂交许可)][迭代器];
				break;
			case 11:break;
			default:
				var 杂交装备 = _root.可雇佣兵[_root.佣兵杂交序号(n, 100, 杂交许可)][迭代器];
				if(杂交装备 == undefined or 杂交装备 == "null" or 杂交装备 == "undefined" or 杂交装备 == "")
				{
					break;
				}
				杂交装备等级 = _root.getItemData(杂交装备).level;
				自身装备等级 = _root.getItemData(样本佣兵[迭代器]).level;
				杂交装备类型 = _root.getItemData(杂交装备).use;
				var 装备杂交几率 = (杂交装备等级 >= 自身装备等级) ? ((杂交几率 - (样本佣兵[0] - 杂交装备等级) * 2) * 装备杂交系数) : 0;
				var 装备杂交许可检测 = (杂交装备类型 == 装备类型数组[迭代器 - 6]) and (杂交装备等级 <= 样本佣兵[0]) ;
				if (装备杂交许可检测 and _root.杂交许可(杂交装备) and _root.杂交许可(样本佣兵[迭代器]) and _root.装备杂交许可(杂交装备, 装备杂交几率))
				{
					//_root.发布调试消息(样本佣兵[1] + ":" + 样本佣兵[0] + "  " + 杂交装备 + ":" + 杂交装备等级 + " 取代 " + 装备类型数组[迭代器 - 6] + 样本佣兵[迭代器] + ":" + 自身装备等级);
					样本佣兵[迭代器] = 杂交装备;
				}
				break;
		}
	}
	
	if ((样本佣兵[13] == null or 样本佣兵[13] == "undefined" or 样本佣兵[13] == "") and (样本佣兵[14] != null and 样本佣兵[14] != "undefined" and 样本佣兵[14] != ""))
	{
		样本佣兵[13] = 样本佣兵[14];
	}
	else if ((样本佣兵[14] == null or 样本佣兵[14] == "undefined" or 样本佣兵[14] == "") and (样本佣兵[13] != null and 样本佣兵[13] != "undefined" and 样本佣兵[13] != ""))
	{
		样本佣兵[14] = 样本佣兵[13];
	}
	样本佣兵[11] = 战队信息.战队项链;//保证佣兵不会出现只带一把副武器的情况，并且装备上对应的战队项链
	样本佣兵[19].是否杂交 = true;//保证佣兵不会出现只带一把副武器的情况，并且装备上对应的战队项链
	_root.随机可雇佣兵=[];//预防内存泄漏，但测试无效
	_root.随机可雇佣兵.push(样本佣兵);//_root.输出对象属性(样本佣兵);     
};

_root.创建佣兵实体 = function(n, 杂交几率)
{
	var 佣兵库 = _root.可雇佣兵;

	// 直接在条件判断中处理杂交逻辑
	if (_root.isEasyMode() != true)
	{
		杂交几率 = Math.min(杂交几率, Math.max(0, _root.主线任务进度 - 13));//在竞技场之后解锁，当达到38时杂交率达到25
	}
	if (_root.成功率(杂交几率))
	{
		_root.杂交可雇佣兵(n,杂交几率,true);
		佣兵库 = _root.随机可雇佣兵;
		n = _root.随机可雇佣兵.length - 1;
	}

	佣兵库[n][2] = 佣兵库[n][2].toString() + 佣兵库[n][1] + 佣兵库[n][0].toString() + _root.随机整数(0, 9999).toString();

	if (佣兵库[n] == undefined || 佣兵库[n][1] + "" == "undefined")
	{
		return null;
	}
	// 返回佣兵库中的佣兵数据                                                                                                                                                              
	return 佣兵库[n];
};
_root.创建佣兵实体对象 = function(佣兵数据, X, Y)
{
	if (佣兵数据 == null)
	{
		return null;
	}
	// 如果没有佣兵数据则返回null                                                                                                                                                            

	生成佣兵计数++;
	var 佣兵名 = "佣兵" + 佣兵数据[1] + 生成佣兵计数;// 根据佣兵数据生成唯一的佣兵名

	// 在游戏世界中创建佣兵对象
	_root.加载游戏世界人物("佣兵npc",佣兵名,_root.gameworld.getNextHighestDepth(),{_x:X, _y:Y});
	var 佣兵对象 = _root.gameworld[佣兵名];

	// 设置佣兵对象的各项属性
	佣兵对象.佣兵库编号 = 佣兵数据[1];
	佣兵对象.是否为敌人 = false;
	佣兵对象.脸型 = 佣兵数据[4];
	佣兵对象.发型 = 佣兵数据[5];
	佣兵对象.头部装备 = 佣兵数据[6];
	佣兵对象.上装装备 = 佣兵数据[7];
	佣兵对象.手部装备 = 佣兵数据[8];
	佣兵对象.下装装备 = 佣兵数据[9];
	佣兵对象.脚部装备 = 佣兵数据[10];
	佣兵对象.颈部装备 = 佣兵数据[11];
	佣兵对象.长枪 = 佣兵数据[12];
	佣兵对象.手枪 = 佣兵数据[13];
	佣兵对象.手枪2 = 佣兵数据[14];
	佣兵对象.刀 = 佣兵数据[15];
	佣兵对象.手雷 = 佣兵数据[16];
	佣兵对象.名字 = 佣兵数据[1];// 使用佣兵库中的名字
	佣兵对象.身高 = 佣兵数据[3];
	佣兵对象.性别 = 佣兵数据[17];
	佣兵对象.等级 = 佣兵数据[0];

	佣兵对象.NPC = true;


	// 设置佣兵对象的佣兵数据
	佣兵对象.佣兵数据 = 佣兵数据;
	// 受雇欲望为5的单位必定可以雇佣
	佣兵对象.受雇欲望 = 5;

	// 设置佣兵对象的默认对话
	佣兵对象.默认对话 = [[]];
	// 设置佣兵对象的默认对话
	var 对话数量 = _root.随机整数(1, 5);
	for (var i = 0; i < 对话数量; ++i)
	{
		var 随机对话编号 = _root.获取随机索引(_root.佣兵随机对话);
		var 随机对话内容 = _root.佣兵随机对话[随机对话编号].Text + "   (" + _root.佣兵随机对话[随机对话编号].Personality + ":" + _root.佣兵随机对话[随机对话编号].Value + ")";
		佣兵对象.默认对话[0][i] = [佣兵数据[1], "佣兵", "主角模板", 随机对话内容, _root.佣兵随机对话[随机对话编号].Expression, 佣兵对象];
	}

	var nx:Number = 佣兵对象.人物文字信息._x;
	var ny:Number = 佣兵对象.人物文字信息._y;

	// 随机设置佣兵的方向
	var 方向 = _root.随机整数(0, 1) == 0 ? "左" : "右";
	佣兵对象.方向 = 方向;


	return 佣兵对象;// 返回创建的佣兵对象
};
_root.添加门口佣兵 = function(n, X, Y)
{
	var 佣兵数据 = _root.创建佣兵实体(n, _root.杂交佣兵几率);
	_root.创建佣兵实体对象(佣兵数据,X,Y);
};

_root.添加场上佣兵 = function(n)
{
	var 佣兵数据 = _root.创建佣兵实体(n, _root.杂交佣兵几率);
	var obj = _root.场景随机有效位置();
	_root.创建佣兵实体对象(佣兵数据,obj.x,obj.y);
};

_root.刷新基地佣兵数据 = function(机率)
{
	if (_root.成功率(100 / 机率))
	{
		_root.请求新佣兵("#0@1-50%5",trace,"**已更新佣兵");
	}
};

//角斗场
_root.进入决斗场 = function()
{
	if (_root.出阵表 != undefined)
	{
		_root.金钱 -= _root.押金;
		_root.最上层发布文字提示("已扣除押金" + _root.押金);
		_root.当前通关的关卡 = "";
		_root.当前关卡名 = "DEATH MATCH角斗场";
		_root.场景进入位置名 = "出生地";
		_root.敌人同伴数 = _root.出阵人员.length;
		_root.敌人同伴数据 = _root.出阵人员;
		_root.淡出动画.淡出跳转帧("wuxianguotu_1");
	}
};
_root.佣兵不足时进入决斗场 = function(请求表达式)
{
	佣兵不足时查询表 = [];
	佣兵不足时查询表 = _root.表达式解析器(请求表达式).slice();
	出阵表 = [];
	var 迭代器 = 0;
	while (迭代器 < 佣兵不足时查询表.length)
	{
		可出场表 = [];
		var _loc4_ = 0;
		while (_loc4_ < _root.佣兵不足时出阵人员.length)
		{
			if (_root.佣兵不足时出阵人员[_loc4_][0] >= 佣兵不足时查询表[迭代器][1] && _root.佣兵不足时出阵人员[_loc4_][0] <= 佣兵不足时查询表[迭代器][2])
			{
				可出场表.push(_loc4_);
			}
			_loc4_ += 1;
		}
		while (佣兵不足时查询表[迭代器][3] > 0)
		{
			出阵号 = random(可出场表.length);
			出阵表.push(可出场表[出阵号]);
			可出场表.splice(出阵号,1);
			佣兵不足时查询表[迭代器][3]--;
		}
		迭代器 += 1;
	}
	_root.出阵人员 = [];
	var _loc5_ = 0;
	while (_loc5_ < 出阵表.length)
	{
		_root.出阵人员.push(_root.佣兵不足时出阵人员[出阵表[_loc5_]]);
		_loc5_ += 1;
	}
	_root.金钱 -= _root.押金;
	_root.最上层发布文字提示("已扣除押金" + _root.押金);
	_root.当前通关的关卡 = "";
	_root.当前关卡名 = "DEATH MATCH角斗场";
	_root.场景进入位置名 = "出生地";
	_root.敌人同伴数 = _root.出阵人员.length;
	_root.敌人同伴数据 = _root.出阵人员;
	_root.淡出动画.淡出跳转帧("wuxianguotu_1");
};

_root.决斗场关闭 = function(){
	_root.发布请求 = false;
	_root.决斗场进入中 = false;
	org.flashNight.arki.scene.StageManager.instance.clear();

}

_root.在数组中 = function(数组, 数字)
{
	var 迭代器 = 0;
	while (迭代器 < 数组.length)
	{
		if (数组[迭代器] == 数字)
		{
			return true;
		}
		迭代器 += 1;
	}
	return false;
};
_root.竞技场随机对手选择 = function(条件)
{
	查询表 = _root.表达式解析器(条件).slice();
	出阵表 = [];
	var 迭代器 = 0;
	while (迭代器 < 查询表.length)
	{
		可出场表 = [];
		var _loc4_ = 0;
		while (_loc4_ < _root.可雇佣兵.length)
		{
			if (_root.可雇佣兵[_loc4_][0] >= 查询表[迭代器][1] && _root.可雇佣兵[_loc4_][0] <= 查询表[迭代器][2])
			{
				可出场表.push(_loc4_);
			}
			_loc4_ += 1;
		}
		while (查询表[迭代器][3] > 0)
		{
			出阵号 = random(可出场表.length);
			出阵表.push(可出场表[出阵号]);
			可出场表.splice(出阵号,1);
			查询表[迭代器][3]--;
		}
		迭代器 += 1;
	}
	_root.出阵人员 = [];
	var _loc5_ = 0;
	while (_loc5_ < 出阵表.length)
	{
		_root.出阵人员.push(_root.可雇佣兵[出阵表[_loc5_]]);
		_loc5_ += 1;
	}
	if (_root.决斗场进入中 == true)
	{
		_root.进入决斗场();
		_root.决斗场进入中 = false;
	}
};
// _root.abc = function()
// {
// };
_root.竞技场对手请求 = function(请求表达式)
{
	if (_root.确认佣兵库(请求表达式))
	{
		if (_root.当前佣兵重用数 <= _root.竞技场佣兵重用基数)
		{
			_root.当前佣兵重用数++;
			_root.竞技场随机对手选择(请求表达式);
		}
		else
		{
			_root.竞技场随机对手选择(请求表达式);
			_root.请求新佣兵(请求表达式,_root.更新重用限制);
		}
	}
	else
	{
		_root.佣兵不足时进入决斗场(请求表达式);
	}
};
_root.更新重用限制 = function()
{
	_root.竞技场佣兵重用基数 += _root.重用基数成长率;
	_root.当前佣兵重用数 = 0;
};
// _root.doNothing = function()
// {
// };
_root.清除佣兵库回调 = function()
{
	_root.佣兵请求成功回调 = null;
	_root.佣兵请求失败回调 = null;
	_root.佣兵请求中回调 = null;
};
_root.佣兵请求成功回调 = function()
{
	_root.等待mc._visible = false;
};
_root.佣兵请求失败回调 = function()
{
	_root.等待mc._visible = false;
};
_root.佣兵请求中回调 = function()
{
	_root.等待mc._visible = true;
};
_root.确认佣兵库 = function(请求内容)
{
	temp = _root.佣兵库查询(请求内容);
	if (temp != undefined)
	{
		return false;
	}
	return true;
};
_root.请求佣兵 = function(请求内容, 成功回调, 失败回调, 请求中回调)
{
	if (成功回调 != undefined)
	{
		_root.佣兵请求成功回调 = 成功回调;
	}
	if (成功回调 != undefined)
	{
		_root.佣兵请求失败回调 = 失败回调;
	}
	if (请求中回调 != undefined)
	{
		_root.佣兵请求中回调 = 请求中回调;
	}
	temp = _root.佣兵库查询(请求内容);
	if (temp != undefined)
	{
		_root.佣兵请求中回调();
		_root.补充佣兵(temp,请求内容);
	}
	else
	{
		_root.佣兵请求成功回调();
	}
};
_root.补充佣兵 = function(要求, 请求内容)
{
	_root.载入新佣兵库数据(要求[3],要求[1],要求[2],_root.请求佣兵,请求内容);
};
_root.请求新佣兵 = function(条件, 回调函数, 回调参数)
{
	查询表 = [];
	查询表 = _root.表达式解析器(条件);
	var _loc5_ = 0;
	while (_loc5_ < 查询表.length)
	{
		载入新佣兵库数据(查询表[_loc5_][3],查询表[_loc5_][1],查询表[_loc5_][2],回调函数,回调参数);
		_loc5_ += 1;
	}
};
_root.载入新佣兵库数据 = function(人数, 等级下限, 等级上限, 回调函数, 回调参数)
{
	// if (_root.isEasyMode() == true)
	// {
	// 	list = _root.mercs_easy_list;
	// }
	// else
	// {
	// 	list = _root.mercs_list;
	// }
	var list = _root.mercs_list;
	_root.可雇佣兵 = [];
	_root.隐藏的可雇佣兵 = [];
	var 迭代器 = 0;
	var seen = {}; 
	while (迭代器 < _root.佣兵个数限制)
	{
		if (_root.同伴数据[迭代器][1] && _root.同伴数据[迭代器][2])
		{
			seen[_root.同伴数据[迭代器][2]] = _root.同伴数据[迭代器][1];
		}
		迭代器 += 1;
	}
	for (var _loc7_ in list)
	{
		var rawMercData = list[_loc7_];
		if(seen[rawMercData.id] && seen[rawMercData.id] == rawMercData.name){
			continue;
		}
		var mercData = new Array(20);
		mercData[0] = rawMercData.level;//0
		mercData[1] = rawMercData.name;//1
		mercData[2] = rawMercData.id;//2
		mercData[3] = rawMercData.height;//3
		mercData[4] = rawMercData.face == null ? "" : _root.脸型库[rawMercData.face];//4
		mercData[5] = rawMercData.hair == null ? "" : _root.发型库[rawMercData.hair];//5
		mercData[6] = rawMercData.equipment.head == null ? "" : rawMercData.equipment.head;//6
		mercData[7] = rawMercData.equipment.body == null ? "" : rawMercData.equipment.body;//7
		mercData[8] = rawMercData.equipment.hand == null ? "" : rawMercData.equipment.hand;//8
		mercData[9] = rawMercData.equipment.leg == null ? "" : rawMercData.equipment.leg;//9
		mercData[10] = rawMercData.equipment.foot == null ? "" : rawMercData.equipment.foot;//10
		mercData[11] = rawMercData.equipment.neck == null ? "" : rawMercData.equipment.neck;//11
		mercData[12] = rawMercData.equipment.primary == null ? "" : rawMercData.equipment.primary;//12
		mercData[13] = rawMercData.equipment.secondary1 == null ? "" : rawMercData.equipment.secondary1;//13
		mercData[14] = rawMercData.equipment.secondary2 == null ? "" : rawMercData.equipment.secondary2;//14
		mercData[15] = rawMercData.equipment.melee == null ? "" : rawMercData.equipment.melee;//15
		mercData[16] = rawMercData.equipment.gerenade == null ? "" : rawMercData.equipment.gerenade;//16
		mercData[17] = rawMercData.gender;//17
		mercData[18] = _root.计算佣兵金币价格(rawMercData.level);//18
		mercData[19] = {是否杂交:false};//19
		if(rawMercData.price){
			mercData[19].价格倍率 = rawMercData.price;
		}
		if(rawMercData.enhancement){
			mercData[19].装备强化度 = rawMercData.enhancement;
		}
		if(rawMercData.passive){
			mercData[19].被动技能 = rawMercData.passive;
		}
		if(rawMercData.hidden){
			mercData[19].隐藏 = rawMercData.hidden;
			_root.隐藏的可雇佣兵.push(mercData);
		}else{
			_root.可雇佣兵.push(mercData);
		}
	}
	// _root.可雇佣兵去重 = [];
	// var seen = {}; 

	// for (var i = 0; i < _root.可雇佣兵.length; i++) {
	// 	var key = _root.可雇佣兵[i].join("-");  // 将子数组转为字符串作为唯一标识

	// 	if (!seen[key]) {
	// 		seen[key] = true;  // 标记该子数组已出现
	// 		_root.可雇佣兵去重.push(_root.可雇佣兵[i]);  
	// 	}
	// }
	// _root.可雇佣兵 = _root.可雇佣兵去重;
	//_root.可雇佣兵.sortOn(0, Array.NUMERIC);
	InsertionSort.sortOn(_root.可雇佣兵, 0, Array.NUMERIC);
	_root.可雇佣兵 = _root.可雇佣兵.concat(_root.隐藏的可雇佣兵);
	if (回调函数 != undefined)
	{
		回调函数(回调参数);
	}
};

_root.计算佣兵金币价格 = function(等级){
	var 金币价格 = 0;
	var 等级 = Number(等级);
	if (_root.isEasyMode() == true)
	{
		金币价格 = 等级 * _root.基础身价值;
	}
	else if (_root.isChallengeMode() == true)
	{
		金币价格 = 等级 * 15 * _root.基础身价值;
	}
	else if (等级 >= 50)
	{
		金币价格 = 等级 * 25 * _root.基础身价值 - 1000 * _root.基础身价值;
	}
	else if (等级 >= 10)
	{
		金币价格 = 等级 * 5 * _root.基础身价值- 20 * _root.基础身价值;
	}
	else
	{
		金币价格 = 2.5 * _root.基础身价值 + 等级 * 2.5 * _root.基础身价值;
	}
	return Number(金币价格);
}
_root.表达式解析器 = function(条件)
{
	查询表 = [];
	条件集 = 条件.split(",");
	var _loc2_ = 0;
	while (_loc2_ < 条件集.length)
	{
		temp = 条件集[_loc2_].split("@");
		temp2 = temp[1].split("%");
		查询表.push([Number(temp[0].split("#")[1]), Number(temp2[0].split("-")[0]), Number(temp2[0].split("-")[1]), Number(temp2[1])]);
		_loc2_ += 1;
	}
	return 查询表;
};
_root.佣兵库查询 = function(条件)
{
	查询表 = [];
	查询表 = _root.表达式解析器(条件);
	var 迭代器 = 0;
	while (迭代器 < _root.可雇佣兵.length)
	{
		var _loc4_ = 0;
		while (_loc4_ < 查询表.length)
		{
			if (查询表[_loc4_][3] > 0)
			{
				if (_root.可雇佣兵[迭代器][查询表[_loc4_][0]] >= 查询表[_loc4_][1] && _root.可雇佣兵[迭代器][查询表[_loc4_][0]] <= 查询表[_loc4_][2])
				{
					查询表[_loc4_][3]--;
					break;
				}
			}
			_loc4_ += 1;
		}
		迭代器 += 1;
	}
	迭代器 = 0;
	while (迭代器 < 查询表.length)
	{
		if (查询表[迭代器][3] > 0)
		{
			return 查询表[迭代器];
		}
		迭代器 += 1;
	}
	return undefined;
};
_root.可雇佣兵 = [];
_root.随机可雇佣兵 = [];
_root.刷兵机率 = 4;
// _root.场景佣兵出现机率 = 8;
_root.杂交佣兵几率 = 50;

_root.竞技场佣兵重用基数 = 2;
_root.当前佣兵重用数 = 0;
_root.重用基数成长率 = 2;
_root.出阵人员 = [];
_root.生成佣兵计数 = 0;
_root.佣兵不足时出阵人员 = [];
_root.佣兵不足时出阵人员.push([1, "欧阳", 0, 175, "男变装-基本脸型", "发型-男式-黑韩式头2", "", "绿色马甲", "", "咖啡色多包短裤", "棕色皮鞋", "", "", "", "", "", "", "男", 0]);
_root.佣兵不足时出阵人员.push([2, "欧阳冰", 0, 165, "女变装-基本脸型", "发型-女式-咖啡色中长马尾", "", "米色高腰背心", "", "棕色带腿包短裤", "深灰色皮鞋", "", "", "", "", "", "", "女", 0]);
_root.佣兵不足时出阵人员.push([3, "李逵", 0, 180, "男变装-基本脸型", "发型-男式-黑暴走头", "", "黑色功夫装", "", "咖啡色多包裤", "白色板鞋", "", "", "", "", "", "", "男", 0]);
_root.佣兵不足时出阵人员.push([4, "母夜叉", 0, 160, "女变装-基本脸型", "发型-女式-银色清爽直发", "", "廉价西服", "", "破牛仔裤", "棕色圆头皮鞋", "", "", "", "", "", "", "女", 0]);
_root.佣兵不足时出阵人员.push([5, "楚留香", 0, 175, "男变装-基本脸型", "发型-男式-黑长发", "医用口罩", "黑色功夫装", "牛皮手套", "破牛仔裤", "白色板鞋", "", "", "", "", "", "", "男", 0]);
_root.佣兵不足时出阵人员.push([6, "人杰", 0, 175, "男变装-基本脸型", "发型-男式-黑暴走头", "医用口罩", "黑短袖", "牛皮手套", "咖啡色多包短裤", "棕色皮鞋", "", "", "", "", "匕首", "普通手雷", "男", 0]);
_root.佣兵不足时出阵人员.push([7, "阿斯顿", 0, 150, "女变装-基本脸型", "发型-女式-咖啡色丸子头", "医用口罩", "米色高腰背心", "牛皮手套", "棕色带腿包短裤", "深灰色皮鞋", "", "", "瓦尔特PPK手枪", "", "匕首", "普通手雷", "女", 0]);
_root.佣兵不足时出阵人员.push([8, "地灵", 0, 175, "男变装-基本脸型", "发型-男式-黑马尾头", "双色巧克力味小熊头", "双色巧克力味小熊上装", "双色巧克力味小熊手套", "双色巧克力味小熊下装", "双色巧克力味小熊鞋", "", "AK74", "", "", "", "", "男", 0]);
_root.佣兵不足时出阵人员.push([9, "啊哈", 0, 175, "男变装-基本脸型", "发型-男式-非主流", "防毒面具2号", "休闲马甲", "牛皮手套", "黑色西装裤", "黑色军用皮鞋", "", "", "Desert Eagle", "", "水管", "普通手雷", "男", 0]);
_root.佣兵不足时出阵人员.push([10, "屋顶", 0, 175, "男变装-基本脸型", "发型-男式-黑猫王头", "防毒面具2号", "bob自由牛仔衫", "牛皮手套", "bob自由喇叭裤", "bob自由火箭皮鞋", "", "", "Desert Eagle", "Desert Eagle", "水管", "普通手雷", "男", 0]);
_root.佣兵不足时出阵人员.push([11, "偶一", 0, 175, "男变装-基本脸型", "发型-男式-黑贴头", "黑框眼镜", "橘色赛车夹克 ", "黑色皮手套", "墨绿军用下装", "黑色军用皮鞋", "", "", "Mossberg500", "Desert Eagle", "锤子", "", "男", 0]);
_root.佣兵不足时出阵人员.push([12, "发大水", 0, 175, "男变装-基本脸型", "发型-男式-黑碎平头", "黑框眼镜", "橘色赛车夹克 ", "黑色皮手套", "墨绿军用下装", "黑色军用皮鞋", "", "AUG", "", "", "", "", "男", 0]);
_root.佣兵不足时出阵人员.push([13, "而非", 0, 175, "男变装-基本脸型", "发型-男式-黑骑士头", "黑色太阳镜", "黑色功夫高手装 ", "白色手套", "白色功夫高手裤子", "黑色功夫布鞋", "", "", "", "", "电子音乐键盘", "", "男", 0]);
_root.佣兵不足时出阵人员.push([14, "困惑", 0, 150, "女变装-基本脸型", "发型-女式-深蓝色挑染短发", "咖啡色条纹蒙面", "SM女王皮衣", "SM女王黑色皮手套", "SM女王吊带袜", "黑色高跟皮鞋", "", "AK47", "", "", "", "", "女", 0]);
_root.佣兵不足时出阵人员.push([15, "留人头", 0, 150, "女变装-基本脸型", "发型-女式-金色中长头发", "咖啡色条纹蒙面", "SM女王皮衣", "SM女王黑色皮手套", "SM女王吊带袜", "黑色高跟皮鞋", "", "Galili", "", "", "", "", "女", 0]);
_root.佣兵不足时出阵人员.push([16, "林肯", 0, 175, "男变装-基本脸型", "发型-男式-平头", "新手面具", "军绿防弹衣", "红色皮手套", "沙漠军装裤", "沙漠军装皮鞋", "", "", "", "", "美式警棍", "", "男", 0]);
_root.佣兵不足时出阵人员.push([17, "卓天", 0, 175, "男变装-基本脸型", "发型-男式-金色不良少年头", "军阀红色贝雷帽", "军阀突击兵衣服", "军阀装甲手套", "军阀带腰包裤子", "沙漠军装皮鞋", "", "G36", "", "", "", "", "男", 0]);
_root.佣兵不足时出阵人员.push([18, "凉快", 0, 175, "男变装-基本脸型", "发型-男式-白色主题头", "装甲头盔", "军阀重装兵衣服", "军阀装甲手套", "军阀装甲裤", "军阀棕色皮靴", "", "", "", "", "中国战刀", "", "男", 0]);
_root.佣兵不足时出阵人员.push([19, "美女", 0, 150, "女变装-基本脸型", "发型-女式-金色中长头发", "科技潜入头盔", "科技潜入上装", "科技潜入手套", "科技潜入裤子", "科技潜入靴", "", "Galili", "", "", "虎彻", "", "女", 0]);
_root.佣兵不足时出阵人员.push([20, "鱼人", 0, 175, "男变装-基本脸型", "发型-男式-黑妹妹头", "红色风镜", "沙漠军装背心", "红色皮手套", "盗贼牛仔裤带腿包", "褐色简单皮鞋", "", "", "", "", "砍刀", "", "男", 0]);
_root.佣兵不足时出阵人员.push([21, "概念版", 0, 175, "男变装-基本脸型", "发型-男式-黑妹妹头", "红色风镜", "沙漠军装背心", "红色皮手套", "盗贼牛仔裤带腿包", "褐色简单皮鞋", "", "M3 Rocket Launcher", "", "", "光剑天秤", "", "男", 0]);
_root.佣兵不足时出阵人员.push([22, "killer", 0, 175, "男变装-基本脸型", "发型-男式-黑混混头", "草莓味小熊头", "草莓味小熊上装", "草莓味小熊手套", "草莓味小熊下装", "草莓味小熊鞋", "", "Fire Gun", "", "", "光剑天秤", "", "男", 0]);
_root.佣兵不足时出阵人员.push([23, "knight", 0, 175, "男变装-基本脸型", "发型-男式-黑骑士头", "骷髅面具", "褐色皮带装", "道钉手套", "盗贼褐色皮裤", "褐色简单皮鞋", "", "", "P90", "P90", "双面斧", "", "男", 0]);
_root.佣兵不足时出阵人员.push([24, "monster", 0, 175, "男变装-基本脸型", "发型-男式-黑骑士头", "钢铁小熊头", "钢铁小熊上装", "钢铁小手套", "钢铁小熊下装", "钢铁小熊鞋", "", "M134", "", "", "", "", "男", 0]);
_root.佣兵不足时出阵人员.push([25, "boss", 0, 175, "男变装-基本脸型", "发型-男式-黑骑士头", "92式头部装甲", "92式胸甲", "92式手甲", "92式腿甲", "92式装甲鞋", "", "", "MP7", "MP7", "光斧金牛", "", "男", 0]);