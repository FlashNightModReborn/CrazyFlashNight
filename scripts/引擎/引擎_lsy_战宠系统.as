
_root.战宠UI函数 = new Object();

// 宠物当前金币售价 = 基础价 + IncreasePrice×已购次数。
// 设计意图：IncreasePrice>0 的宠物每买一只就更贵，抑制玩家堆同质化战宠（购买价 + 刷怪可雇用价同步上涨）。
// 已购次数持久化于 _root._saveExt.宠物购买次数（存档预留命名空间，随 mydata.ext 往返）。
// 旧实现靠原地改写 _root.宠物库[id].Price 累积（会话内、不入存档）；现改为基于次数计算，配置保持只读。
// 权威单一来源：商城购买(PetPanelService)与刷怪雇佣价(计算可雇用敌人价格)都调本函数。
_root.获取宠物当前售价 = function(petId){
	var def = _root.宠物库[petId];
	if(def == undefined) return 0;
	var base = Number(def.Price) || 0;
	var inc = Number(def.IncreasePrice) || 0;
	if(inc <= 0) return base;
	var ext = _root._saveExt;
	var cnt = (ext != undefined && ext.宠物购买次数 != undefined) ? Number(ext.宠物购买次数[petId]) : 0;
	if(isNaN(cnt)) cnt = 0;
	return base + inc * cnt;
}

_root.开宠物格子 = function(){
	_root.宠物领养限制 += 1;
	_root.宠物信息.push([]);
	// Plan A audit: 开宠物格子 写 宠物领养限制 + 宠物信息，必须标脏
	_root.存档系统.dirtyMark = true;
}

_root.加载宠物 = function(地点X, 地点Y){
	if((!_root.限制系统.limitLevel || _root.难度等级 >= _root.限制系统.limitLevel) && _root.限制系统.DisableCompanion) return;
	_root.宠物mc库 = [];
	_root.出战宠物id库 = [];
	
	for (var i = 0; i < _root.宠物信息.length; i++){
		var 当前宠物信息 = _root.宠物信息[i];
		if (当前宠物信息[4] == 1){
			if (当前宠物信息[2] > 0){
				_root.战宠UI函数.设置宠物出战(i, true, 地点X, 地点Y);
			}else{
				_root.发布消息(_root.获得翻译("宠物体力不足，无法出战！"));
			}
		}
	}
	//加载宠物后立即应用减体力
	if(_root.当前为战斗地图) _root.宠物减体力();
	_root.宠物信息界面.排列宠物图标();
}

_root.战宠UI函数.计算战宠升级所需经验 = function(兵种,等级){
	var 敌人属性 = _root.敌人属性表[兵种];
	var obj = {兵种:兵种,等级:等级};
	if(敌人属性.线性插值经验值.length > 1){
		_root.敌人函数.获取线性插值经验值(obj, 敌人属性.线性插值经验值);
	}else{
		obj.最小经验值 = 敌人属性.最小经验值;
		obj.最大经验值 = 敌人属性.最大经验值;
	}
	var exp = Math.floor((obj.最小经验值 + ((obj.最大经验值 - obj.最小经验值) / (_root.最大等级 - 1)) * 等级) * 等级);
	return exp;
}

_root.战宠UI函数.计算战宠最大出战数 = function(){
	if(_root.isChallengeMode()) return Math.ceil(_root.等级 / 35);
	return Math.min(Math.ceil(_root.等级 / 5), 5);
}

_root.战宠UI函数.统计当前出战数 = function(){
	var count = 0;
	for (var i = 0; i < _root.宠物信息.length; i++){
		if (_root.宠物信息[i] && _root.宠物信息[i][4] == 1){
			count++;
		}
	}
	return count;
}

// 装备型战宠统一销毁入口：先执行 Dressup 生命周期显式 teardown，再交给
// removeMovieClip/onUnload 完成 StaticDeinitializer、dispatcher 与 task 清理。
_root.战宠UI函数.安全移除装备单位 = function(单位对象):Boolean{
	if(!单位对象) return true;
	org.flashNight.arki.unit.UnitComponent.Initializer.DressupInitializer.teardownLifeCycles(单位对象);
	单位对象.removeMovieClip();
	return true;
}

// 独立战宠 UI XFL 不直接依赖 asLoader 的包类路径；由主注入层提供失败关闭门面。
_root.战宠UI函数.预检托管长枪取回 = function(宠物信息):Object{
	return org.flashNight.arki.merc.ManagedLongGunService.preflightWithdrawal(宠物信息);
}

_root.战宠UI函数.取回托管长枪 = function(宠物信息):Object{
	return org.flashNight.arki.merc.ManagedLongGunService.withdraw(宠物信息);
}

// 托管装备变化必须整只重建，不能只走 宠物升级加载（后者不会重跑换装/lifecycle）。
_root.战宠UI函数.重建宠物单位 = function(id:Number):Boolean{
	var 当前宠物信息 = _root.宠物信息[id];
	if(!当前宠物信息 || 当前宠物信息.length < 5 || 当前宠物信息[4] != 1) return false;
	var 地点X:Number = 500;
	var 地点Y:Number = 300;
	var found:Number = -1;
	for(var i:Number = 0; i < _root.宠物mc库.length; i++){
		var unit = _root.宠物mc库[i];
		if(unit && unit.宠物属性 && unit.宠物属性.宠物信息数组号 == id){
			found = i;
			地点X = unit._x;
			地点Y = unit._y;
			break;
		}
	}
	if(found >= 0){
		var oldUnit = _root.宠物mc库[found];
		_root.宠物mc库.splice(found, 1);
		_root.出战宠物id库.splice(found, 1);
		_root.战宠UI函数.安全移除装备单位(oldUnit);
	}else{
		var hero:MovieClip = TargetCacheManager.findHero();
		if(hero){
			地点X = hero._x;
			地点Y = hero._y;
		}
	}
	return _root.战宠UI函数.设置宠物出战(id, true, 地点X, 地点Y);
}

_root.战宠UI函数.出战按钮函数 = function(是否出战:Boolean){
	if(_root.当前为战斗地图) return;
	var success = false;
	var 当前宠物信息 = _root.宠物信息[_parent.宠物信息数组号];
	_root.最大宠物出战数 = _root.战宠UI函数.计算战宠最大出战数();
	if (当前宠物信息[4] == 0){
		// 使用标记计数而非MC库长度判断出战数
		var 当前出战数 = _root.战宠UI函数.统计当前出战数();
		if (当前出战数 >= _root.最大宠物出战数){
			显示文字 = _root.获得翻译("出战数达到上限");
			return;
		}else if(当前宠物信息[2] <= 0){
			_root.发布消息(_root.获得翻译("宠物体力不足，无法出战！"));
			return;
		}else{
			// 设置出战状态并尝试创建宠物，失败则回滚
			var hero:MovieClip = TargetCacheManager.findHero();
			当前宠物信息[4] = 1;
			success = _root.战宠UI函数.设置宠物出战(_parent.宠物信息数组号,true, hero._x, hero._y);
			if(!success){
				当前宠物信息[4] = 0;
			}
		}
	}else if (当前宠物信息[4] == 1){
		// 取消出战状态并移除宠物，失败则回滚
		当前宠物信息[4] = 0;
		success = _root.战宠UI函数.设置宠物出战(_parent.宠物信息数组号,false);
		if(!success){
			当前宠物信息[4] = 1;
		}
	}
	//现在改为加载宠物完成后刷新图标
	if(success) _parent._parent.排列宠物图标();
}

_root.战宠UI函数.设置宠物出战 = function(id:Number, 是否出战:Boolean, 地点X:Number, 地点Y:Number):Boolean{
	var i = -1;
	var 当前宠物信息 = _root.宠物信息[id];
	if(是否出战){
		if (当前宠物信息[4] != 1) return false;
		if (当前宠物信息[2] <= 0) return false;
		for(i=0; i<_root.宠物mc库.length; i++){
			if(_root.宠物mc库[i].宠物属性.宠物信息数组号 == id) return false;
		}
		var 宠物数据 = _root.宠物库[当前宠物信息[0]];
		var 宠物兵种 = 宠物数据.Identifier;
		var 宠物等级 = 当前宠物信息[1];
		var 宠物名字 = 宠物数据.Name;
		var 宠物是否为敌人 = false;
		var 宠物身高 = 宠物数据.Height;
		var 宠物实例名 = "宠物" + id + 宠物兵种;
		//if (当前宠物信息.length >= 6)
		if (当前宠物信息.length >= 6 && 当前宠物信息[5]){
			宠物属性 = 当前宠物信息[5];
		}else{
			当前宠物信息[5] = {};
			宠物属性 = 当前宠物信息[5];
		}
		宠物属性.宠物库数组号 = 当前宠物信息[0];
		宠物属性.宠物信息数组号 = id;
		// var 称号 = "";
		// if (宠物属性.基础训练 && 宠物属性.基础训练.次数){
		// 	//宠物名字 = 宠物数据.Name + "（精锐" + 宠物属性.基础训练.次数 + "）";
		// 	称号 =  "精锐" + 宠物属性.基础训练.次数;
		// }
		var 宠物对象 = _root.加载游戏世界人物(宠物兵种,宠物实例名,_root.gameworld.getNextHighestDepth(),{
			等级:宠物等级, 
			名字:宠物名字, 
			宠物属性:宠物属性, 
			是否为敌人:宠物是否为敌人, 
			身高:宠物身高, 
			_x:地点X, 
			_y:地点Y
		});//,称号:称号
		_root.宠物mc库.push(宠物对象);
		_root.出战宠物id库.push(id);
		return true;
	}else{
		if(当前宠物信息[4] != 0) return false;
		for(i=0; i<_root.宠物mc库.length; i++){
			if(_root.宠物mc库[i].宠物属性.宠物信息数组号 == id)
			break;
		}
		if(i >= _root.出战宠物id库.length) return false;
		var 宠物对象 = _root.宠物mc库[i];
		_root.出战宠物id库.splice(i,1);
		_root.宠物mc库.splice(i,1);
		_root.战宠UI函数.安全移除装备单位(宠物对象);
		return true;
	}
}

_root.宠物减体力 = function(){
	for (var i = 0; i < _root.宠物mc库.length; i++){
		var id = _root.宠物mc库[i].宠物属性.宠物信息数组号;
		var 当前宠物信息 = _root.宠物信息[id];
		if(当前宠物信息 == null){
			_root.发布消息("战宠体力数据异常！");
			continue;
		}
		当前宠物信息[2] -= 2;
		if (当前宠物信息[2] <= 0){
			当前宠物信息[2] = 0;
		}
	}
}

_root.删除场景宠物 = function(){
	// 清理所有宠物MC实例
	for (var i = 0; i < _root.宠物mc库.length; i++){
		if (_root.宠物mc库[i]){
			_root.战宠UI函数.安全移除装备单位(_root.宠物mc库[i]);
		}
	}
	// 清空数组，确保计数归零
	_root.宠物mc库 = [];
	_root.出战宠物id库 = [];
}

// 读取/存盘战宠已折入 SaveManager.loadAll() / saveAll()
// 保留空壳防止外部调用报错
_root.读取本地存盘战宠 = function(){};
_root.本地存盘战宠 = function(){};

_root.最大宠物格子数 = 80;
_root.最大宠物出战数 = 5;
_root.宠物信息 = [];
_root.读取本地存盘战宠();
