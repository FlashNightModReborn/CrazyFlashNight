//加载人物相关

_root.操控目标表 = [_root.控制目标];


// 场景就绪时，若主角位置处于碰撞中，则尝试挤出到最近合法点（一次性挂钩，避免重复注册）
EventBus.getInstance().subscribe("SceneReady", function():Void {
	var hero:MovieClip = TargetCacheManager.findHero();
	if (hero && !Mover.isMovieClipPositionValid(hero)) {
		var pushed:Boolean = Mover.pushOutFromCollision(hero, 180, 8, 30);
		if (!pushed) {
			Mover.enforceScreenBounds(hero);
		}
	}
}, null);

_root.转场景记录数据 = function(){
	_root.转场景记录数据第一次记录 = true;

	var 操控对象 = _root.gameworld[_root.控制目标];
	if (!isNaN(操控对象.hp)) _root.转场景数据[0] = 操控对象.hp;
	if (!isNaN(操控对象.mp)) _root.转场景数据[1] = 操控对象.mp;
	_root.转场景数据[2] = 操控对象.攻击模式;
	// _root.转场景数据[3] = 操控对象.长枪射击次数;
	// _root.转场景数据[4] = 操控对象.手枪射击次数;
	// _root.转场景数据[5] = 操控对象.手枪2射击次数;

	佣兵同伴血量记录 = [-1, -1, -1];
	var _loc3_ = 0;
	while (_loc3_ < _root.同伴数){
		if (_root.gameworld["同伴" + _loc3_].hp > 0){
			佣兵同伴血量记录[_loc3_] = _root.gameworld["同伴" + _loc3_].hp;
		}
		_loc3_ += 1;
	}
}

_root.转场景数据传递 = function(){
	_root.加载我方人物(_root.场景进入横坐标,_root.场景进入纵坐标);
	if (_root.新出生){
		_root.转场景数据 = [0, 0, "空手"];
		佣兵同伴血量记录 = [-1, -1, -1];

		_root.新出生 = false;
		return;
	}

	var 操控对象 = _root.gameworld[_root.控制目标];

	if(_root.当前为战斗地图) {
		if (_root.转场景数据[0] > 0){
			操控对象.hp = _root.转场景数据[0];
		}
		if (_root.转场景数据[1] > 0){
			操控对象.mp = _root.转场景数据[1];
		}

		// 个别情况下mp会变成NaN，导致无法恢复，具体原因未知，在传递参数的时候加了NaN判断

		/*
		_root.服务器.发布服务器消息(_root.当前为战斗地图 + " " +
					  操控对象.hp + " " +
					  _root.转场景数据[0] + " " +
					  操控对象.mp + " " +
					  _root.转场景数据[1]);
		*/

	} else {
		if(操控对象.hp > 0) {
			_root.转场景数据[0] = 操控对象.hp;
		}

		if(操控对象.mp >= 0) {
			_root.转场景数据[1] = 操控对象.mp;
		}
	}

	if (转场景记录数据第一次记录){
		操控对象.攻击模式切换(_root.转场景数据[2]);
		操控对象.攻击模式 = _root.转场景数据[2];
		// 操控对象.长枪射击次数 = _root.转场景数据[3];
		// 操控对象.手枪射击次数 = _root.转场景数据[4];
		// 操控对象.手枪2射击次数 = _root.转场景数据[5];
	}

	var i = 0;
	while (i < _root.同伴数){
		if (_root.佣兵同伴血量记录[i] > 0){
			_root.gameworld["同伴" + i].hp = _root.佣兵同伴血量记录[i];
		}
		i ++;
	}

	// 重置场景切换冷却计数，防止加载期间持续按键导致的穿墙问题
	_root.场景转换函数.上次切换帧数 = _root.帧计时器.当前帧数;
}

_root.转场景数据 = [0, 0, "空手"];
_root.新出生 = true;
_root.转场景记录数据第一次记录 = false;

// _root.联机2015加载主角 = function(地点X, 地点Y)
// {
// 	_root.gameworld.attachMovie("主角-男",_root.控制目标,_root.gameworld.getNextHighestDepth(),{_x:地点X, _y:地点Y, 是否为敌人:false, 身高:_root.身高, 名字:_root.角色名, 等级:_root.等级, 性别:_root.性别, 用户ID:_root.accId, 是否允许发送联机数据:true});
	// _root.玩家信息界面.刷新hp显示();
	// _root.玩家信息界面.刷新mp显示();
// }

_root.加载我方人物 = function(地点X, 地点Y){
	var 当前操作单位 = (_root.特殊操作单位 != null && _root.特殊操作单位 != "") ? _root.特殊操作单位 : "主角-男"; //主角模型已经统一
	_root.加载游戏世界人物(当前操作单位,_root.控制目标,_root.gameworld.getNextHighestDepth(),{
		_x:地点X, 
		_y:地点Y, 
		是否为敌人:false, 
		respawn:true,
		身高:_root.身高, 
		名字:_root.角色名, 
		等级:_root.等级, 
		性别:_root.性别
	});
	_root.玩家信息界面.刷新hp显示();
	_root.玩家信息界面.刷新mp显示();
	_root.玩家信息界面.刷新经验值显示();
	// _root.添加其他玩家();
	_root.加载佣兵(地点X,地点Y);
	_root.加载宠物(地点X,地点Y);

	EventBus.instance.publish("SceneReady");
}

_root.加载主角和战宠 = function(地点X, 地点Y){
	var 当前操作单位 = (_root.特殊操作单位 != null && _root.特殊操作单位 != "") ? _root.特殊操作单位 : "主角-男"; //主角模型已经统一

	_root.加载游戏世界人物(当前操作单位,_root.控制目标,_root.gameworld.getNextHighestDepth(),{
		_x:地点X, 
		_y:地点Y, 
		是否为敌人:false, 
		respawn:true,
		身高:_root.身高, 
		名字:_root.角色名, 
		等级:_root.等级, 
		性别:_root.性别, 
		用户ID:_root.accId
	});
	_root.玩家信息界面.刷新hp显示();
	_root.玩家信息界面.刷新mp显示();
	// _root.添加其他玩家();
	_root.加载宠物(地点X,地点Y);
}

// issue #7 bug4：从 加载佣兵 抽出的「单佣兵进场」，供 handleDeploy 即时上人复用。
// 参数块与下方 加载佣兵 的 attach 保持一致；如改 merc spawn 参数需两处同步。
_root.加载单个佣兵 = function(i, 地点X, 地点Y){
	var 同伴信息 = _root.同伴数据[i];
	if (!(_root.佣兵是否出战信息[i] == 1 && 同伴信息[1] != undefined && 同伴信息[1] != "undefined")) return null;
	// 佣兵装备托管一期：出战生成逐槽取「托管有效克隆 ?? 预设字符串」（docs/佣兵装备托管-设计-2026-08-23.md §5）
	var 装备解析 = org.flashNight.arki.merc.MercLoadoutService.buildSpawnLoadout(同伴信息);
	var 当前佣兵 = _root.加载游戏世界人物("主角-男","同伴" + i,_root.gameworld.getNextHighestDepth(),{
		_x:地点X + random(10),
		_y:地点Y + random(10),
		用户ID:同伴信息[2],
		是否为敌人:false,
		身高:同伴信息[3],
		名字:同伴信息[1],
		等级:同伴信息[0],
		脸型:同伴信息[4],
		发型:同伴信息[5],
		头部装备:装备解析.头部装备,
		上装装备:装备解析.上装装备,
		手部装备:装备解析.手部装备,
		下装装备:装备解析.下装装备,
		脚部装备:装备解析.脚部装备,
		颈部装备:装备解析.颈部装备,
		长枪:装备解析.长枪,
		手枪:装备解析.手枪,
		手枪2:装备解析.手枪2,
		刀:装备解析.刀,
		手雷:同伴信息[16],
		性别:同伴信息[17],
		是否为佣兵:true,
		佣兵是否出战信息id:i
	});
	if(同伴信息[19]){
		当前佣兵.佣兵参数 = 同伴信息[19];
	}
	return 当前佣兵;
}

_root.加载佣兵 = function(地点X, 地点Y){
	if((!_root.限制系统.limitLevel || _root.难度等级 >= _root.限制系统.limitLevel) && _root.限制系统.DisableCompanion) return;
	// 标记本场景托管佣兵（issue #7 bug4：handleDeploy 即时上/撤人据此判定）
	_root.gameworld.佣兵已进场 = true;
	_root.帧计时器.添加单次任务(function() {
		for(var i = 0; i < _root.佣兵个数限制; i++){
			var 同伴信息 = _root.同伴数据[i];
			if (_root.佣兵是否出战信息[i] == 1 && 同伴信息[1] != undefined && 同伴信息[1] != "undefined"){
				/*if (同伴信息[17] == "男") 同伴信息[17] = "主角-男";
				if (同伴信息[17] == "女") 同伴信息[17] = "主角-女";
				*/
				//主角模型已经统一
				// 佣兵装备托管一期：与 加载单个佣兵 同步，attach 前解析托管/预设（docs/佣兵装备托管-设计-2026-08-23.md §5）
				var 装备解析 = org.flashNight.arki.merc.MercLoadoutService.buildSpawnLoadout(同伴信息);
				var 当前佣兵 = _root.加载游戏世界人物("主角-男","同伴" + i,_root.gameworld.getNextHighestDepth(),{
					_x:地点X + random(10), 
					_y:地点Y + random(10), 
					用户ID:同伴信息[2], 
					是否为敌人:false, 
					身高:同伴信息[3], 
					名字:同伴信息[1], 
					等级:同伴信息[0], 
					脸型:同伴信息[4], 
					发型:同伴信息[5], 
					头部装备:装备解析.头部装备,
					上装装备:装备解析.上装装备,
					手部装备:装备解析.手部装备,
					下装装备:装备解析.下装装备,
					脚部装备:装备解析.脚部装备,
					颈部装备:装备解析.颈部装备,
					长枪:装备解析.长枪,
					手枪:装备解析.手枪,
					手枪2:装备解析.手枪2,
					刀:装备解析.刀,
					手雷:同伴信息[16], 
					性别:同伴信息[17], 
					是否为佣兵:true, 
					佣兵是否出战信息id:i
				});
				// if(同伴信息[19].装备强化度){
				// 	当前佣兵.装备强化度 = 同伴信息[19].装备强化度;
				// }
				if(同伴信息[19]){
					当前佣兵.佣兵参数 = 同伴信息[19];
				}
				
			}
		}
	}, 33);
}

_root.删除场景上佣兵 = function(){
/*	for (var i in _root.gameworld)
	{
		if (_root.gameworld[i].是否为佣兵 === true)
		{
			_root.gameworld[i].removeMovieClip();
		}
	}*/
	var i = 0;
	while (i < _root.佣兵个数限制){
		_root.gameworld["同伴" + i].removeMovieClip();
		i++;
	}
}

_root.加载敌方人物 = function(地点X, 地点Y){
	//目前这个函数只有角斗场用到
	for(var i = 0; i < _root.敌人同伴数; i++){
		var 敌人信息 = _root.敌人同伴数据[i];
		var 敌人 = _root.加载游戏世界人物("主角-男", "敌人同伴" + i, _root.gameworld.getNextHighestDepth(), {
			_x:地点X + random(10), 
			_y:地点Y + random(10), 
			是否为敌人:true, 
			身高:敌人信息[3], 
			名字:敌人信息[1], 
			等级:敌人信息[0], 
			脸型:敌人信息[4], 
			发型:敌人信息[5], 
			头部装备:敌人信息[6], 
			上装装备:敌人信息[7], 
			手部装备:敌人信息[8], 
			下装装备:敌人信息[9], 
			脚部装备:敌人信息[10], 
			颈部装备:敌人信息[11], 
			长枪:敌人信息[12], 
			手枪:敌人信息[13], 
			手枪2:敌人信息[14], 
			刀:敌人信息[15], 
			手雷:敌人信息[16], 
			性别:敌人信息[17],
			产生源: "地图"
		});
		//配置角斗场敌人的掉落物
		// _root.服务器.发布服务器消息("配置角斗场敌人掉落物 " + ObjectUtil.stringify(敌人信息));

		敌人.掉落物 = [];
		//斩马刀必定掉落，佩戴对应项链的敌人有概率掉落对应的武器和防具
		if(敌人.刀 === "斩马刀") {
			敌人.掉落物.push({名字:"斩马刀", 概率:100});
		}else if (敌人.颈部装备 === "角斗高手项链" || 敌人.颈部装备 === "角斗王者项链"){
			var jjcDropItem = ["次品蓝晶", "巨兽", "冰魄斩", "合金", "烈焰", "异形", "巴雷特", "方舟武士"];
			for(var j=0; j<jjcDropItem.length; j++){
				if(敌人.长枪.indexOf(jjcDropItem[j]) > -1) {
					敌人.掉落物.push({名字:敌人.长枪, 概率:25});
					break;
				}
			}
			for(var j=0; j<jjcDropItem.length; j++){
				if(敌人.刀.indexOf(jjcDropItem[j]) > -1) {
					敌人.掉落物.push({名字:敌人.刀, 概率:25});
					break;
				}
			}
			var 防具列表 = ["头部装备","上装装备","下装装备","手部装备","脚部装备",null,null];
			var 对应防具 = 防具列表[random(7)];
			if(对应防具 != null){
				for(var j=0; j<jjcDropItem.length; j++){
					if(敌人[对应防具].indexOf(jjcDropItem[j]) > -1) 敌人.掉落物.push({名字:敌人[对应防具], 概率:100});
				}
			}
		}
	}
}

// 角斗场「堕落/元战队/混编」模式生成 roster 敌人。
// 读 _root.角斗场roster阵容 = [{兵种:"兵种N", 等级:L} | {类型:"merc", 佣兵:[...]} , ...]，
// 兵种经 _root.兵种库 解析兵种名+属性，佣兵直接复用 MercLibrary tuple，
// 逐个 加载游戏世界人物（是否为敌人:true）。死亡递减 僵尸型敌人总个数 → 达 -敌人同伴数 触发
// 角斗场获胜，与人形机制完全一致（见 WaveSpawner finishRequirement / 角斗场计算敌人数）。
_root.角斗场读取单位参数 = function(单位:Object){
	if(单位 == undefined) return undefined;
	if(单位.Parameters != undefined) return 单位.Parameters;
	if(单位.parameters != undefined) return 单位.parameters;
	if(单位.参数 != undefined) return 单位.参数;
	return undefined;
}

_root.角斗场应用单位参数 = function(初始化:Object, 单位:Object):Void{
	var 参数 = _root.角斗场读取单位参数(单位);
	if(参数 != undefined && 参数 != null){
		org.flashNight.gesh.object.ObjectUtil.cloneParameters(初始化, 参数);
	}
}

_root.角斗场应用怪物安全覆盖 = function(目标:Object, 是否敌人:Boolean, 产生源:String):Void{
	目标.是否为敌人 = 是否敌人;
	目标.产生源 = 产生源;
	目标.掉落物 = [];
	目标.不掉钱 = true;
	目标.计算经验值 = function():Void{
		this.已加经验值 = true;
	};
}

_root.角斗场roster活体上限 = 12;
_root.角斗场roster补刷阈值 = 6;
_root.角斗场roster判胜冻结值 = -99999;

_root.角斗场生成roster单位 = function(单位:Object, 地点X:Number, 地点Y:Number, 序号:Number):Boolean{
	if(单位 == undefined) return false;
	if(单位.类型 == "merc" && 单位.佣兵 != undefined){
		var 敌人信息 = 单位.佣兵;
		var 敌人 = _root.加载游戏世界人物("主角-男", "敌人同伴" + 序号, _root.gameworld.getNextHighestDepth(), {
			_x:地点X + random(160) - 80,
			_y:地点Y + random(120) - 60,
			是否为敌人:true,
			身高:敌人信息[3],
			名字:敌人信息[1],
			等级:敌人信息[0],
			脸型:敌人信息[4],
			发型:敌人信息[5],
			头部装备:敌人信息[6],
			上装装备:敌人信息[7],
			手部装备:敌人信息[8],
			下装装备:敌人信息[9],
			脚部装备:敌人信息[10],
			颈部装备:敌人信息[11],
			长枪:敌人信息[12],
			手枪:敌人信息[13],
			手枪2:敌人信息[14],
			刀:敌人信息[15],
			手雷:敌人信息[16],
			性别:敌人信息[17],
			产生源:"地图"
		});
		if(敌人 != undefined){
			_root.角斗场应用怪物安全覆盖(敌人, true, "地图");
			return true;
		}
		return false;
	}
	var 属性 = _root.兵种库[单位.兵种];
	if(属性 == undefined) return false;
	var 初始化 = _root.duplicateOf(属性);
	初始化.兵种名 = null;        // 同 WaveSpawner.spawn：兵种名走第一参数 id，initObject 内置 null
	初始化.等级 = 单位.等级;
	_root.角斗场应用单位参数(初始化, 单位);
	_root.角斗场应用怪物安全覆盖(初始化, true, "地图"); // 参数可改行为，安全字段最后覆盖
	初始化._x = 地点X + random(160) - 80;
	初始化._y = 地点Y + random(120) - 60;
	var mc:MovieClip = _root.加载游戏世界人物(属性.兵种名, "敌人同伴" + 序号, _root.gameworld.getNextHighestDepth(), 初始化);
	if(mc != undefined){
		_root.角斗场应用怪物安全覆盖(mc, true, "地图");
		return true;
	}
	return false;
}

_root.角斗场roster当前活体数 = function():Number{
	var st = _root.角斗场roster状态;
	if(st == undefined) return 0;
	var 计数:Number = Number(_root.gameworld.地图.僵尸型敌人总个数);
	var 死亡数:Number = 0;
	if(!isNaN(计数) && 计数 < 0) 死亡数 = -计数;
	var 活体:Number = Number(st.已生成数) - 死亡数;
	if(isNaN(活体) || 活体 < 0) 活体 = 0;
	return 活体;
}

_root.角斗场roster刷新判胜门槛 = function():Void{
	var st = _root.角斗场roster状态;
	if(st != undefined && st.待刷索引 < st.阵容.length){
		org.flashNight.arki.scene.WaveSpawner.instance.finishRequirement = _root.角斗场roster判胜冻结值;
		return;
	}
	org.flashNight.arki.scene.WaveSpawner.instance.finishRequirement = -_root.敌人同伴数;
}

_root.角斗场roster停止补刷时钟 = function():Void{
	var st = _root.角斗场roster状态;
	if(st == undefined || st.clock == undefined) return;
	st.clock.onEnterFrame = null;
	st.clock.removeMovieClip();
	st.clock = undefined;
}

_root.角斗场roster补刷 = function(强制:Boolean):Void{
	var st = _root.角斗场roster状态;
	if(st == undefined) return;
	var 活体:Number = 强制 ? 0 : _root.角斗场roster当前活体数();
	if(!强制 && 活体 > st.补刷阈值){
		_root.角斗场roster刷新判胜门槛();
		return;
	}
	var 预算:Number = st.活体上限 - 活体;
	if(预算 < 1 && !强制){
		_root.角斗场roster刷新判胜门槛();
		return;
	}
	var 本次生成:Number = 0;
	while(预算 > 0 && st.待刷索引 < st.阵容.length){
		var 单位 = st.阵容[st.待刷索引];
		st.待刷索引++;
		var 序号:Number = st.生成序号;
		st.生成序号++;
		if(_root.角斗场生成roster单位(单位, st.地点X, st.地点Y, 序号)){
			st.已生成数++;
			_root.敌人同伴数 = st.已生成数;
			预算--;
			本次生成++;
		}
	}
	if(st.待刷索引 >= st.阵容.length){
		_root.角斗场roster停止补刷时钟();
	}
	_root.角斗场roster刷新判胜门槛();
}

_root.角斗场roster启动补刷时钟 = function():Void{
	var st = _root.角斗场roster状态;
	if(st == undefined || st.clock != undefined) return;
	var clip:MovieClip = _root.gameworld.createEmptyMovieClip("角斗场roster补刷时钟", _root.gameworld.getNextHighestDepth());
	clip.onEnterFrame = function():Void{
		var state = _root.角斗场roster状态;
		if(state == undefined){
			this.onEnterFrame = null;
			this.removeMovieClip();
			return;
		}
		state.pollFrame++;
		if(state.pollFrame < 10) return;
		state.pollFrame = 0;
		_root.角斗场roster补刷(false);
	};
	st.clock = clip;
}

_root.加载角斗场怪物 = function(地点X, 地点Y){
	var 阵容 = _root.角斗场roster阵容;
	if(阵容 == undefined) return;
	var 活体上限:Number = Number(_root.角斗场roster活体上限);
	if(isNaN(活体上限) || 活体上限 < 1) 活体上限 = 12;
	var 补刷阈值:Number = Number(_root.角斗场roster补刷阈值);
	if(isNaN(补刷阈值) || 补刷阈值 < 0 || 补刷阈值 >= 活体上限) 补刷阈值 = Math.floor(活体上限 / 2);
	_root.角斗场roster状态 = {
		阵容: 阵容,
		待刷索引: 0,
		生成序号: 0,
		已生成数: 0,
		地点X: 地点X,
		地点Y: 地点Y,
		活体上限: 活体上限,
		补刷阈值: 补刷阈值,
		pollFrame: 0,
		clock: undefined
	};
	_root.敌人同伴数 = 0;
	_root.角斗场roster补刷(true);
	if(_root.角斗场roster状态 != undefined && _root.角斗场roster状态.待刷索引 < 阵容.length){
		_root.角斗场roster启动补刷时钟();
	}
	_root.角斗场roster刷新判胜门槛();
}

// 单位的统一加载函数
_root.加载游戏世界人物 = function(id:String, name:String, depth:Number, initObject:Object):MovieClip{
	if(!initObject) {
		initObject = {兵种:id};
	}else{
		initObject.兵种 = id;
	}
	return _root.gameworld.attachMovie(id, name, depth, initObject);
}


//场景转换相关
_root.关卡结束 = function(){
	_root.关卡结束界面.关卡结束();
	EffectSystem.ScreenEffect("过关提示动画",Stage.width / 2,Stage.height / 2,100);
	_root.FinishStage(_root.当前关卡名,_root.当前关卡难度);
}

_root.获取关卡状态 = function():String{
	var stageManager = StageManager.instance;
	if(!stageManager.isActive) return null;
	if(stageManager.isFinished) return "Finished";
	if(stageManager.isFailed) return "Failed";
	return "Active";
}

_root.返回基地 = function(){
	_root.新出生 = true;
	_root.玩家信息界面.刷新hp显示();
	_root.玩家信息界面.刷新mp显示();
	if (_root.关卡结束界面.关卡是否结束 == true){
		_root.关卡结束界面.关卡是否结束 = false;
		_root.关卡结束界面._visible = false;
		_root.奖励物品界面.标题 = _root.获得翻译("通关奖励");
		_root.奖励物品界面.生成关卡随机奖励品();
		_root.奖励物品界面.刷新();
	}
	_root.场景进入位置名 = "出生地";
	_root.关卡类型 = "";
	if (TargetCacheManager.findHero().hp == 0){
		_root.淡出动画.淡出跳转帧("医务室");
	}else{
		_root.淡出动画.淡出跳转帧(_root.关卡地图帧值);
	}
	// 清空限制词条
	_root.限制系统.clearEntries();
	// 停止背景音乐(jukebox override 时保持连续播放)
	_root.soundEffectManager.stopBGMForTransition();
	// 清除StageManager
	StageManager.instance.clear();
}


//门函数

_root.场景转换函数 = new Object();

_root.场景转换函数.上次切换帧数 = 0;
_root.场景转换函数.Web选关打开中 = false;

_root.场景转换函数.请求打开Web选关 = function(source){
	if (_root.场景转换函数.Web选关打开中) return true;
	if (_root.gameCommands == undefined || _root.gameCommands["openWebStageSelect"] == undefined) return false;
	var requestSource:String = (source != undefined && source != "") ? String(source) : "as2_stage_map_door";
	var stageFrameLabel:String = String(_root.关卡地图帧值 || "基地门口");
	var currentSceneLabel:String = String(_root.关卡标志 || "");
	if (currentSceneLabel.indexOf("地图-") == 0) stageFrameLabel = currentSceneLabel;
	var ok:Boolean = _root.gameCommands["openWebStageSelect"]({
		source: requestSource,
		frameLabel: stageFrameLabel,
		returnFrameLabel: String(_root.关卡地图帧值 || "基地门口")
	}) == true;
	if (ok) _root.场景转换函数.Web选关打开中 = true;
	return ok;
}

_root.场景转换函数.切换场景 = function(对应门名, 目标场景帧, 开门效果, 同时按键值){
	var 游戏世界 = _root.gameworld;
	if (!游戏世界.允许通行) return;
	if (_root.场景转换函数.Web选关打开中) return;

	var 控制对象 = 游戏世界[_root.控制目标];
	var 对应方向 = false;
	switch(同时按键值){
		case _root.上键:
			对应方向 = 控制对象.上行;
			break;
		case _root.下键:
			对应方向 = 控制对象.下行;
			break;
		case _root.左键:
			对应方向 = 控制对象.左行;
			break;
		case _root.右键:
			对应方向 = 控制对象.右行;
			break;
	}
	
	var currentFrame:Number = _root.帧计时器.当前帧数;
	// _root.发布消息("场景转换函数.切换场景 " + (currentFrame - _root.场景转换函数.上次切换帧数) + " " + 对应方向 + " " + this.hitTest(控制对象.area) + " " + 控制对象.hp);
	if ((currentFrame - _root.场景转换函数.上次切换帧数 > 15) && 对应方向 && this.hitTest(控制对象.area) && 控制对象.hp > 0){
		
		var pt = {x:控制对象._x, y:控制对象.Z轴坐标};
		游戏世界.localToGlobal(pt);
		if (this.hitTest(pt.x, pt.y, true)){
			_root.场景进入位置名 = 对应门名;
			_root.转场景记录数据();
			_root.场景转换函数.上次切换帧数 = currentFrame;
			if (目标场景帧 == "关卡地图" && _root.场景转换函数.请求打开Web选关("as2_legacy_stage_gate")) {
				return;
			}
			if (开门效果 == null || 开门效果 == ""){
				_root.淡出动画.淡出跳转帧(目标场景帧);
				this.gotoAndStop(3);
			}else{
				_root.淡出动画.跳转帧 = 目标场景帧;
				游戏世界[开门效果].play();
				this.gotoAndStop(3);
			}
		}
	}
}

_root.场景转换函数.打开Web选关 = function(对应门名, 目标场景帧, 开门效果, 同时按键值, source){
	var 游戏世界 = _root.gameworld;
	if (!游戏世界.允许通行) return;
	if (_root.场景转换函数.Web选关打开中) return;

	var 控制对象 = 游戏世界[_root.控制目标];
	var 对应方向 = false;
	switch(同时按键值){
		case _root.上键:
			对应方向 = 控制对象.上行;
			break;
		case _root.下键:
			对应方向 = 控制对象.下行;
			break;
		case _root.左键:
			对应方向 = 控制对象.左行;
			break;
		case _root.右键:
			对应方向 = 控制对象.右行;
			break;
	}

	var currentFrame:Number = _root.帧计时器.当前帧数;
	if ((currentFrame - _root.场景转换函数.上次切换帧数 > 15) && 对应方向 && this.hitTest(控制对象.area) && 控制对象.hp > 0){
		var pt = {x:控制对象._x, y:控制对象.Z轴坐标};
		游戏世界.localToGlobal(pt);
		if (this.hitTest(pt.x, pt.y, true)){
			_root.场景进入位置名 = 对应门名;
			_root.转场景记录数据();
			_root.场景转换函数.上次切换帧数 = currentFrame;

			if (_root.场景转换函数.请求打开Web选关(source)) {
				return;
			}

			if (开门效果 == null || 开门效果 == ""){
				_root.淡出动画.淡出跳转帧(目标场景帧);
				this.gotoAndStop(3);
			}else{
				_root.淡出动画.跳转帧 = 目标场景帧;
				游戏世界[开门效果].play();
				this.gotoAndStop(3);
			}
		}
	}
}

// _root.场景转换函数.切换场景 = function(){
// 	_root.发布消息("切换场景");
// 	this.onEnterFrame = undefined;
// }

_root.场景转换函数.是否从门加载角色 = function(){
	if (this.是否从门加载主角 && _root.场景进入位置名 == this._name){
		// _root.gameworld鼠标横向位置 = this._x;
		// _root.gameworld鼠标纵向位置 = this._y;
		_root.场景进入横坐标 = this._x;
		_root.场景进入纵坐标 = this._y;
		_root.转场景数据传递();
	}
}


//地图帧跳转相关
_root.防止播放跳关 = function(){
	if (_root.关卡标志 != undefined){
		_root.跳转地图(_root.关卡标志);
	}
}

_root.跳转地图 = function(跳转帧){
	_root.当前为战斗地图 = false;
	_root.soundEffectManager.notifyLeaveBattle();
	// 检索环境xml中是否存在对应的基地地图或外部地图
	if(WeatherSystem.getInstance().getEnvConfig().hasSceneEnv(_root.关卡标志)){
		// 通过关卡标志是否有"地图-"前缀来区分基地/外部地图
		跳转帧 = _root.关卡标志.indexOf("地图-") === 0 ? "外部地图" : "基地地图";
	}
	_root.gotoAndPlay(跳转帧);
}


_root.加载共享场景 = function(加载场景名){
	var gw:MovieClip = _root.attachMovie(加载场景名, "gameworld", _root.getNextHighestDepth());
	gw.swapDepths(_root.gameworld层级定位器);
	gw.场景名 = 加载场景名;
	SceneManager.instance.initGameWorld(gw);
}


_root.场景转换函数.场景切换时补充玩家弹药 = function(){
	if(_root.当前为战斗地图) return;
	var 装备栏 = _root.物品栏.装备栏;
	var keys = ["长枪", "手枪", "手枪2"];
	for(var i=0; i<keys.length; i++){
		var item = 装备栏.getItem(keys[i]);
		if(item.value.level > 0){
			item.value.shot = 0;
			item.value.reloadCount = 0;
			if (keys[i] == "长枪") {
				item.value.subweaponShot = 0;
				item.value.subweaponReloadCount = 0;
			}
		}
	}
}



// 转换场景画面完全淡出时移除组件
_root.__安排游戏世界清理重试 = function():Void {
	if (_root.__游戏世界清理重试已排队 === true) return;
	if (_root.帧计时器 == undefined
			|| typeof _root.帧计时器.添加单次任务 != "function") {
		_root.发布消息("[SceneManager] 战利品权威尚未收敛，缺少帧计时器；场景切换保持阻塞");
		return;
	}
	_root.__游戏世界清理重试已排队 = true;
	_root.帧计时器.添加单次任务(function():Void {
		_root.__游戏世界清理重试已排队 = false;
		if (_root.清除游戏世界组件()) {
			if (_root.淡出动画 != undefined && typeof _root.淡出动画.play == "function") {
				_root.淡出动画.play();
			}
		}
	}, 1);
}

_root.清除游戏世界组件 = function():Boolean{
	// 彻底移除gameworld
	if (!SceneManager.instance.removeGameWorld()) {
		// 淡出动画 frame 5 之后会在 frame 12 无条件跳图；先钉停当前时间线，
		// 仅在权威 journal/effects/transport 全部收敛并完成 teardown 后续播。
		if (_root.淡出动画 != undefined && typeof _root.淡出动画.stop == "function") {
			_root.淡出动画.stop();
		}
		_root.__安排游戏世界清理重试();
		return false;
	}
	
	// 清除游戏世界相关组件
	CollisionLayerRenderer.clearAll();
	_root.gameworld层级定位器.removeMovieClip();
	_root.层级管理器.检查层级范围();
	_root.卸载后景();

	// 清除重置部分绑定gameworld的数据组件
	_root.帧计时器.unitUpdateWheel.reset();

	//关闭UI
	_root.卸载外部UI();
	_root.卸载全屏UI();
	
	_root.对话框UI.清理外部立绘缓存(3);
	_root.对话框界面.关闭();
	_root.对话框界面.followingEvent = null;

	_root.关卡结束界面._visible = false;
	_root.关卡结束界面.关卡是否结束 = false;

	// 补充玩家弹药
	_root.场景转换函数.场景切换时补充玩家弹药();

	// 清理鼠标拖拽状态，防止物品图标卡在鼠标上
	if (_root.鼠标代理 != undefined) {
		_root.鼠标代理.清理拖拽图标();
	} else if (_root.鼠标.物品图标容器.物品图标) {
		_root.鼠标.物品图标容器.物品图标.removeMovieClip();
	}
	_root.鼠标.gotoAndStop(1); // 恢复鼠标默认状态

    _root.注释结束();
	return true;
}
