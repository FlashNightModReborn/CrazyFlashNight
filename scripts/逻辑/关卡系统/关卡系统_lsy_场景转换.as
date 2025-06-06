//加载人物相关

_root.操控目标表 = [_root.控制目标];

import org.flashNight.arki.stage.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.转场景记录数据 = function(){
	转场景记录数据第一次记录 = true;
	var i = 0;
	while (i < 4){
		if (_root.操控目标表[i] != null && _root.操控目标表[i] != ""){
			var 操控对象 = _root.gameworld[_root.操控目标表[i]];
			_root.转场景数据[i][0] = 操控对象.hp;
			_root.转场景数据[i][1] = 操控对象.mp;
			_root.转场景数据[i][2] = 操控对象.攻击模式;
			_root.转场景数据[i][3] = 操控对象.长枪射击次数;
			_root.转场景数据[i][4] = 操控对象.手枪射击次数;
			_root.转场景数据[i][5] = 操控对象.手枪2射击次数;
		}
		i += 1;
	}
	佣兵同伴血量记录 = [-1, -1, -1];
	var _loc3_ = 0;
	while (_loc3_ < _root.同伴数){
		if (_root.gameworld["同伴" + _loc3_].hp > 0){
			佣兵同伴血量记录[_loc3_] = _root.gameworld["同伴" + _loc3_].hp;
		}
		_loc3_ += 1;
	}
	_root.写入装备缓存();
}

_root.转场景数据传递 = function(){
	_root.加载我方人物(_root.场景进入横坐标,_root.场景进入纵坐标);
	if (_root.新出生){
		_root.转场景数据 = [[0, 0, "空手", 0, 0, 0], [0, 0, "空手", 0, 0, 0], [0, 0, "空手", 0, 0, 0], [0, 0, "空手", 0, 0, 0]];
		佣兵同伴血量记录 = [-1, -1, -1];

		var hero:MovieClip = TargetCacheManager.findHero();
		_root.场景转换_主角hp = hero.hp满血值;
		_root.场景转换_主角mp = hero.mp满血值;
		_root.场景转换_主角长枪射击次数 = 0;
		_root.场景转换_主角手枪射击次数 = 0;
		_root.场景转换_主角手枪2射击次数 = 0;
		i = 0;
		while (i < _root.同伴数){
			if (_root.gameworld["同伴" + i].hp满血值 > 0){
				_root.场景转换_同伴hp[i] = _root.gameworld["同伴" + i].hp满血值;
				_root.场景转换_同伴mp[i] = _root.gameworld["同伴" + i].mp满血值;
			}
			i++;
		}
		_root.新出生 = false;
		return;
	}
	var i = 0;
	while (i < 4){
		if (_root.操控目标表[i] != null && _root.操控目标表[i] != ""){
			var 操控对象 = _root.gameworld[_root.操控目标表[i]];
			if (_root.转场景数据[i][0] > 0){
				操控对象.hp = _root.转场景数据[i][0];
			}
			if (_root.转场景数据[i][1] > 0){
				操控对象.mp = _root.转场景数据[i][1];
			}
			if (转场景记录数据第一次记录){
				操控对象.攻击模式切换(_root.转场景数据[i][2]);
				操控对象.攻击模式 = _root.转场景数据[i][2];
				操控对象.长枪射击次数 = _root.转场景数据[i][3];
				操控对象.手枪射击次数 = _root.转场景数据[i][4];
				操控对象.手枪2射击次数 = _root.转场景数据[i][5];
			}
		}
		i += 1;
	}
	i = 0;
	while (i < _root.同伴数){
		if (_root.佣兵同伴血量记录[i] > 0){
			_root.gameworld["同伴" + i].hp = _root.佣兵同伴血量记录[i];
		}
		i += 1;
	}
}

_root.转场景数据 = [[0, 0, "空手", 0, 0, 0], [0, 0, "空手", 0, 0, 0], [0, 0, "空手", 0, 0, 0], [0, 0, "空手", 0, 0, 0]];
_root.新出生 = true;
_root.转场景记录数据第一次记录 = false;

// _root.联机2015加载主角 = function(地点X, 地点Y)
// {
// 	_root.gameworld.attachMovie("主角-男",_root.控制目标,_root.gameworld.getNextHighestDepth(),{_x:地点X, _y:地点Y, 是否为敌人:false, 身高:_root.身高, 名字:_root.角色名, 等级:_root.等级, 性别:_root.性别, 用户ID:_root.accId, 是否允许发送联机数据:true});
	// _root.玩家信息界面.刷新hp显示();
	// _root.玩家信息界面.刷新mp显示();
// }

_root.加载我方人物 = function(地点X, 地点Y){
	if (_root.特殊操作单位){
		var 当前操作单位 = _root.特殊操作单位;
	}else{
		//当前操作单位 = "主角-" + _root.性别;
		var 当前操作单位 = "主角-男";//主角模型已经统一
	}
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
	_root.加载佣兵(地点X,地点Y);
	_root.加载宠物(地点X,地点Y);
}

_root.加载主角和战宠 = function(地点X, 地点Y){
	if (_root.特殊操作单位){
		var 当前操作单位 = _root.特殊操作单位;
	}else{
		//当前操作单位 = "主角-" + _root.性别;
		var 当前操作单位 = "主角-男";//主角模型已经统一
	}

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

_root.加载佣兵 = function(地点X, 地点Y){
	if((!_root.限制系统.limitLevel || _root.难度等级 >= _root.限制系统.limitLevel) && _root.限制系统.DisableCompanion) return;
	_root.帧计时器.添加单次任务(function() {
		for(var i = 0; i < _root.佣兵个数限制; i++){
			var 同伴信息 = _root.同伴数据[i];
			if (_root.佣兵是否出战信息[i] == 1 && 同伴信息[1] != undefined && 同伴信息[1] != "undefined"){
				/*if (同伴信息[17] == "男") 同伴信息[17] = "主角-男";
				if (同伴信息[17] == "女") 同伴信息[17] = "主角-女";
				*/
				//主角模型已经统一
				var 当前佣兵 = _root.加载游戏世界人物("主角-男","同伴" + i,_root.gameworld.getNextHighestDepth(),{_x:地点X + random(10), _y:地点Y + random(10), 用户ID:同伴信息[2], 是否为敌人:false, 身高:同伴信息[3], 名字:同伴信息[1], 等级:同伴信息[0], 脸型:同伴信息[4], 发型:同伴信息[5], 头部装备:同伴信息[6], 上装装备:同伴信息[7], 手部装备:同伴信息[8], 下装装备:同伴信息[9], 脚部装备:同伴信息[10], 颈部装备:同伴信息[11], 长枪:同伴信息[12], 手枪:同伴信息[13], 手枪2:同伴信息[14], 刀:同伴信息[15], 手雷:同伴信息[16], 性别:同伴信息[17], 是否为佣兵:true, 佣兵是否出战信息id:i});
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
		var 敌人 = _root.加载游戏世界人物("主角-男","敌人同伴" + i,_root.gameworld.getNextHighestDepth(),{_x:地点X + random(10), _y:地点Y + random(10), 是否为敌人:true, 身高:敌人信息[3], 名字:敌人信息[1], 等级:敌人信息[0], 脸型:敌人信息[4], 发型:敌人信息[5], 头部装备:敌人信息[6], 上装装备:敌人信息[7], 手部装备:敌人信息[8], 下装装备:敌人信息[9], 脚部装备:敌人信息[10], 颈部装备:敌人信息[11], 长枪:敌人信息[12], 手枪:敌人信息[13], 手枪2:敌人信息[14], 刀:敌人信息[15], 手雷:敌人信息[16], 性别:敌人信息[17]});
		//配置角斗场敌人的掉落物
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
			var 防具列表 = ["头部装备","上装装备","下装装备","手部装备","脚部装备",null.null];
			var 对应防具 = 防具列表[random(7)];
			if(对应防具 != null){
				for(var j=0; j<jjcDropItem.length; j++){
					if(敌人[对应防具].indexOf(jjcDropItem[j]) > -1) 敌人.掉落物.push({名字:敌人[对应防具], 概率:100});
				}
			}
		}
	}
}

//人物的统一加载函数
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
	_root.帧计时器.移除任务(_root.生存模式OBJ.波次时钟);
	_root.画面效果("过关提示动画",Stage.width / 2,Stage.height / 2,100);
	_root.FinishStage(_root.当前关卡名,_root.当前关卡难度);
	_root.stageDispatcher.publish("StageCleared");
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
	//清空限制词条
	_root.限制系统.clearEntries();
	//停止背景音乐
	_root.soundEffectManager.stopBGM();
}


//门函数

_root.场景转换函数 = new Object();

_root.场景转换函数.切换场景 = function(对应门名, 目标场景帧, 开门效果, 同时按键值){
	var 游戏世界 = _root.gameworld;
	if (!游戏世界.允许通行) return;

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
	
	var 条件满足 = false;
	if (对应方向 && this.hitTest(控制对象.area) && 控制对象.hp > 0){
		条件满足 = true;
	}
	// if (this.hitTest(控制对象.area) and _root.全鼠标控制 == true and this.hitTest(_root.鼠标) == true and 被点击 == true and 控制对象.hp > 0){
	// 	条件满足 = true;
	// }
	if (条件满足 === true){
		var pt = {x:控制对象._x, y:控制对象.Z轴坐标};
		游戏世界.localToGlobal(pt);
		if (this.hitTest(pt.x, pt.y, true)){
			_root.场景进入位置名 = 对应门名;
			_root.转场景记录数据();
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

_root.场景转换函数.是否从门加载角色 = function(){
	if (this.是否从门加载主角 && _root.场景进入位置名 == this._name){
		// _root.gameworld鼠标横向位置 = this._x;
		// _root.gameworld鼠标纵向位置 = this._y;
		_root.场景进入横坐标 = this._x;
		_root.场景进入纵坐标 = this._y;
		_root.转场景数据传递();
		_root.横版卷屏();
	}
}


//地图帧跳转相关
_root.防止播放跳关 = function(){
	if (_root.关卡标志 != undefined){
		_root.跳转地图(_root.关卡标志);
	}
}

_root.跳转地图 = function(跳转帧){
	var 游戏世界 = _root.gameworld;
	_root.常用工具函数.释放对象绘图内存(游戏世界);
	_root.当前为战斗地图 = false;
	for (var i = 0; i < _root.初期关卡列表.length; i++){
		if (_root.关卡标志 == _root.初期关卡列表[i]){
			_root.当前为战斗地图 = true;
			_root.gotoAndPlay("初期关卡");
			return;
		}
	}
	for (var i = 0; i < _root.基地地图列表.length; i++){
		if (_root.关卡标志 == _root.基地地图列表[i]){
			_root.gotoAndPlay("基地地图");
			return;
		}
	}
	for (var i = 0; i < _root.外部地图列表.length; i++){
		if (_root.关卡标志 == _root.外部地图列表[i]){
			_root.gotoAndPlay("外部地图");
			return;
		}
	}
	_root.gotoAndPlay(跳转帧);
}


_root.加载共享场景 = function(加载场景名){
	var gw:MovieClip = _root.attachMovie(加载场景名, "gameworld", _root.getNextHighestDepth());
	gw.swapDepths(_root.gameworld层级定位器);
	SceneManager.getInstance().initScene(gw);

	_root.帧计时器.eventBus.publish("SceneChanged");
}



// 转换场景画面完全淡出时移除组件
_root.清除游戏世界组件 = function(){
	// 彻底移除gameworld
	SceneManager.getInstance().removeGameWorld();
	
	// 清除游戏世界相关组件
	_root.collisionLayer.clear();
	_root.gameworld层级定位器.removeMovieClip();
	_root.层级管理器.检查层级范围();
	_root.卸载后景();

	// 清除重置部分绑定gameworld的数据组件
	_root.帧计时器.unitUpdateWheel.reset();

	//关闭UI
	_root.卸载外部UI();
	_root.卸载全屏UI();
	_root.购买物品界面.关闭();
	_root.仓库界面.关闭();
	_root.商城主mc = null;
	_root.关卡结束界面._visible = false;
	_root.关卡结束界面.关卡是否结束 = false;
	_root.新手引导界面.关闭指引();
}