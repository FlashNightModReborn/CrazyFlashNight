import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.战宠UI函数 = new Object();

_root.开宠物格子 = function(){
	_root.宠物领养限制 += 1;
	_root.宠物信息.push([]);
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

_root.战宠UI函数.出战按钮函数 = function(是否出战:Boolean){
	if(_root.当前为战斗地图) return;
	var success = false;
	var 当前宠物信息 = _root.宠物信息[_parent.宠物信息数组号];
	_root.最大宠物出战数 = _root.战宠UI函数.计算战宠最大出战数();
	if (当前宠物信息[4] == 0){
		if (_root.宠物mc库.length >= _root.最大宠物出战数){
			显示文字 = _root.获得翻译("出战数达到上限");
			return;
		}else if(当前宠物信息[2] <= 0){
			_root.发布消息(_root.获得翻译("宠物体力不足，无法出战！"));
			return;
		}else{
			当前宠物信息[4] = 1;
			var hero:MovieClip = TargetCacheManager.findHero();
			success = _root.战宠UI函数.设置宠物出战(_parent.宠物信息数组号,true, hero._x, hero._y);
		}
	}else if (当前宠物信息[4] == 1){
		当前宠物信息[4] = 0;
		success = _root.战宠UI函数.设置宠物出战(_parent.宠物信息数组号,false);
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
		if (当前宠物信息[0] == 66){
			宠物对象.长枪 = "L85A1";
		}
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
		宠物对象.removeMovieClip();
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
	var _loc1_ = 0;
	while (_loc1_ < 宠物mc库.length){
		宠物mc库[_loc1_].removeMovieClip();
		_loc1_ += 1;
	}
}

_root.读取本地存盘战宠 = function(){
	var 本地loadgame = SharedObject.getLocal(_root.savePath);
	if (本地loadgame.data.战宠 == undefined){
		_root.宠物信息 = new Array();
		_root.宠物信息.push([]);
		_root.宠物信息.push([]);
		_root.宠物信息.push([]);
		_root.宠物信息.push([]);
		_root.宠物信息.push([]);
		_root.宠物领养限制 = 5;
	}else{
		_root.宠物信息 = 本地loadgame.data.战宠;
		_root.宠物领养限制 = 本地loadgame.data.宠物领养限制;
	}
}
_root.本地存盘战宠 = function(){
	var mysave = SharedObject.getLocal(_root.savePath);
	mysave.data.战宠 = _root.宠物信息;
	mysave.data.宠物领养限制 = _root.宠物领养限制;
	mysave.flush();
}

_root.最大宠物格子数 = 80;
_root.最大宠物出战数 = 5;
_root.宠物信息 = [];
_root.读取本地存盘战宠();
