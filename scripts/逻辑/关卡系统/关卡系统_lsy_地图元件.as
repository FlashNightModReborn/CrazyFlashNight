import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.*;

// 拾取相关函数
_root.pickupItemManager = new Object();
_root.pickupItemManager.count = 0;

_root.pickupItemManager.createPickupItemPool = function(){
	_root.pickupItemManager.pickupItemDict = {};
	_root.pickupItemManager.dispatcher = new LifecycleEventDispatcher(gameworld);
	org.flashNight.aven.Coordinator.EventCoordinator.addUnloadCallback(
		gameworld, 
		function(){
			_root.pickupItemManager.pickupItemDict = null;
			_root.pickupItemManager.dispatcher.destroy();
		}
	);
}

_root.pickupItemManager.pickup = function(target, 拾取者, 播放拾取动画){
	var str = "获得";
	var itemName = target.物品名;
	var value = target.数量;
	if (拾取者.名字){
		str = 拾取者.名字 + "为你收集了";
	}
	if (itemName == "金钱"){
		_root.金钱 += value;
		str += "金钱" + value;
	}else if (itemName == "K点"){
		_root.虚拟币 += value;
		str += "K点" + value;
	}else if (!拾取者 && Key.isDown(_root.组合键) &&_root.pickupItemManager.拾取并装备(itemName, value)){
		str =  "已拾取" + itemName;
	}else if (_root.singleAcquire(itemName, value)){
		str += itemName + value + "个。";
	}else{
		_root.发布消息("物品栏空间不足，无法拾取！");
		return;
	}
	// 销毁对象
	_root.发布消息(str);
	var 控制对象 = _root.gameworld[_root.控制目标];
	target.gotoAndPlay("消失");
	delete _root.pickupItemManager.pickupItemDict[target.index];
	_root.播放音效("拾取音效");
	if (!拾取者 && 播放拾取动画){
		控制对象.拾取();
	}
}
_root.pickupItemManager.拾取并装备 = function(itemName, value){
	var itemData = _root.getItemData(itemName);
	if(itemData.type == "武器" || itemData.type == "防具" || itemData.use == "手雷"){
		装备 = _root.物品栏.装备栏.getNameString(itemData.use);
		if(itemData.level && itemData.level > _root.等级) return false;
		if(!装备 && itemData.use){
			if(itemData.use == "手雷"){
				_root.物品栏.装备栏.add(itemData.use,{name:itemName, value:value});
			}else{
				_root.物品栏.装备栏.add(itemData.use,{name:itemName, value:{level:value}});
			}
			_root.刷新人物装扮(_root.控制目标);
			if(itemData.type == "武器" || itemData.use == "手雷"){
				_root.gameworld[_root.控制目标].攻击模式切换(itemData.use);
			}
		}
		else if(装备 && itemData.use){
			var 背包 = _root.物品栏.背包;
			var targetIndex = 背包.getFirstVacancy();
			if(targetIndex == -1) {
				return false;
			}
			//卸下装备
			var result = _root.物品栏.装备栏.move(背包,itemData.use,targetIndex);
        	if(!result) return false;
			if(itemData.use == "手雷"){
				_root.物品栏.装备栏.add(itemData.use,{name:itemName, value:value});
			}else{
				_root.物品栏.装备栏.add(itemData.use,{name:itemName, value:{level:value}});
			}
			_root.刷新人物装扮(_root.控制目标);
			if(itemData.type == "武器" || itemData.use == "手雷"){
				_root.gameworld[_root.控制目标].攻击模式切换(itemData.use);
			}
		}
		else{
			return false
		}
	}else{
		return false
	}
	return true
}

_root.创建可拾取物 = function(物品名, 数量, X位置, Y位置, 是否飞出, parameterObject){
	if(数量 <= 0) 数量 = 1;
	if (物品名 === "金钱" && random(_root.打怪掉钱机率) == 0){
		物品名 = "K点";
	}
	
	if(!parameterObject){
		parameterObject = new Object();
	}

	parameterObject.index = _root.pickupItemManager.count;
	parameterObject._x = X位置;
	parameterObject._y = Y位置;
	parameterObject.物品名 = 物品名;
	parameterObject.数量 = Number(数量);
	parameterObject.在飞 = Boolean(是否飞出);

	var gameworld = _root.gameworld;
	var pickupItem = gameworld.attachMovie("可拾取物2", "可拾取物" + _root.pickupItemManager.count, gameworld.getNextHighestDepth(), parameterObject);

	pickupItem.焦点高亮框.gotoAndPlay(_root.随机整数(1,59));
	
	// 创建可拾取物池
	if (_root.pickupItemManager.dispatcher.isDestroyed() || _root.pickupItemManager.dispatcher == null) {
		_root.pickupItemManager.createPickupItemPool();
	}

	_root.pickupItemManager.pickupItemDict[_root.pickupItemManager.count] = pickupItem;
	pickupItem.焦点高亮框._visible = false;

	var pickUpFunc:Function = function():Void{
		// _root.发布消息("开始碰撞检测");
		var focusedObject:MovieClip = gameworld[_root.控制目标];
		var mc:MovieClip = this.焦点高亮框;
		mc.play();
		this.焦点高亮框._visible = true;
		if (Math.abs(this.Z轴坐标 - focusedObject.Z轴坐标) < 50 && focusedObject.area.hitTest(this.area)){
			_root.pickupItemManager.pickup(this,null,true);
		}
	};

	var resetFunc:Function = function():Void{
		var mc:MovieClip = this.焦点高亮框;
		mc.stop();
		mc._visible = false;
	}
    _root.pickupItemManager.dispatcher.subscribeGlobal("interactionKeyDown", pickUpFunc, pickupItem);
	_root.pickupItemManager.dispatcher.subscribeGlobal("interactionKeyUp", resetFunc, pickupItem);
	
	_root.pickupItemManager.count++;
}



// 出生点相关
_root.初始化出生点 = function(){
	//确定方向
	方向 = 方向 === "左" ? "左" : "右";
	if (方向 === "左"){
		this._xscale = -100;
	}
	//将碰撞箱附加到地图
	var gameworld = _root.gameworld;

	if(this.开门 == null){
		this.开门 = function(){
			gotoAndPlay("开门");
		}
	}
	if(this.area){
		var rect = this.area.getRect(gameworld);
		var 地图 = gameworld.地图;

        // 设置 `地图` 为不可枚举
        _global.ASSetPropFlags(gameworld, ["地图"], 1, false);
		
		地图.beginFill(0x000000);
		地图.moveTo(rect.xMin, rect.yMin);
		地图.lineTo(rect.xMax, rect.yMin);
		地图.lineTo(rect.xMax, rect.yMax);
		地图.lineTo(rect.xMin, rect.yMax);
		地图.lineTo(rect.xMin, rect.yMin);;
		地图.endFill();
	}
}

// 资源箱
_root.初始化资源箱 = function(){
	if (!isNaN(最小主线进度) && 最小主线进度 > _root.主线任务进度){
		this.removeMovieClip();
		return;
	}else if (!isNaN(最大主线进度) && 最大主线进度 < _root.主线任务进度){
		this.removeMovieClip();
		return;
	}if (数量_min > 0 and 数量_max > 0){
		数量 = 数量_min + random(数量_max - 数量_min + 1);
	}

	是否为敌人 = true;
	hp = hp满血值 = 10;
	躲闪率 = 100;
	击中效果 = "火花";
	Z轴坐标 = this._y;
	this.unitAIType = "None";
	StaticInitializer.initializeUnit(this);
	gotoAndStop("正常");
}

// NPC
//_root.初始化NPC(this);
_root.初始化NPC = function(目标){
	if(目标.NPC初始化完毕 === true) return;
	if(目标.任务需求 > 1 && _root.主线任务进度 < 目标.任务需求){
		目标.stop();
		目标._visible = false;
		return;
	}
	目标._name = 目标.名字;
	if(目标.默认对话 == null) 目标.默认对话 = _root.读取并组装NPC对话(目标.名字);
	if(目标.物品栏 == null) 目标.物品栏 = _root.getNPCShop(目标.名字);
	if(目标.可学的技能 == null) 目标.可学的技能 = _root.getNPCSkills(目标.名字);
	if (_root.NPCTaskCheck(目标.名字).result == "接受任务"){
		_root.发布消息(目标.名字 + "也许需要你的帮助");
	}
	// 目标.是否为敌人 = false;
	//目标.击中效果 = "飙血"; //意义不明
	if(目标.方向 == null) 目标.方向 = "右";
	if(isNaN(目标.身高)) 目标.身高 = 175;
	var 缩放系数 = UnitUtil.getHeightPercentage(目标.身高) / 100;
	目标._yscale *= 缩放系数;
	if(目标.方向 == "左"){
		目标._xscale *= - 缩放系数;
		目标.文字信息._xscale = -100;
		目标.商店名._xscale = -100;
	}else{
		目标._xscale *= 缩放系数;
	}
	目标.NPC初始化完毕 = true;
}