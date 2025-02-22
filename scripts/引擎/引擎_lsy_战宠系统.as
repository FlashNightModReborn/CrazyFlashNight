_root.开宠物格子 = function(){
	_root.宠物领养限制 += 1;
	_root.宠物信息.push([]);
}

/*
_root.读取宠物信息233 = function()
{
	var _loc2_ = "http://" + _root.address + "/crazyflashercom/k5_readpetinfo.action?k=" + random(100);
	var petgetdata = new LoadVars();
	petgetdata.accId = _root.accId;
	petgetdata.sendAndLoad(_loc2_,petgetdata,"POST");
	petgetdata.onLoad = function(b){
		if (b){
			if (petgetdata.content + "" == "-1"){
				_root.发布消息("获取战宠信息失败");
			}else if (petgetdata.content + "" == "0"){
				_root.发布消息("获取战宠信息成功");
				_root.宠物领养限制 = Number(petgetdata.boxnum);
				var _loc3_ = petgetdata.petinfo.split("_");
				var _loc4_ = 0;
				while (_loc4_ < _loc3_.length){
					var _loc5_ = [];
					if (_loc3_[_loc4_] != "-1"){
						_loc5_ = _loc3_[_loc4_].substr(1, _loc3_[_loc4_].length - 1).substr(0, _loc3_[_loc4_].length - 2).split(",");
						_root.宠物信息.push([Number(_loc5_[0]), Number(_loc5_[1]), Number(_loc5_[2]), 500, 0]);
					}else{
						_root.宠物信息.push([]);
					}
					_loc4_ += 1;
				}
			}
		}
	};
}
*/

_root.加载宠物 = function(地点X, 地点Y){
	if(_root.限制系统.DisableCompanion) return;
	_root.宠物mc库 = [];
	_root.出战宠物id库 = [];
	
	for (var i = 0; i < _root.宠物信息.length; i++){
		var 当前宠物信息 = _root.宠物信息[i];
		if (当前宠物信息[4] == 1){
			if (当前宠物信息[2] > 0){
				var 宠物数据 = _root.宠物库[当前宠物信息[0]];
				var 宠物兵种 = 宠物数据.Identifier;
				var 宠物等级 = 当前宠物信息[1];
				var 宠物名字 = 宠物数据.Name;
				var 宠物是否为敌人 = false;
				var 宠物身高 = 宠物数据.Height;
				var 宠物实例名 = "宠物" + i + 宠物兵种;
				//if (当前宠物信息.length >= 6)
				if (当前宠物信息.length >= 6 && 当前宠物信息[5]){
					宠物属性 = 当前宠物信息[5];
				}else{
					当前宠物信息[5] = {};
					宠物属性 = 当前宠物信息[5];
				}
				宠物属性.宠物库数组号 = 当前宠物信息[0];
				宠物属性.宠物信息数组号 = i;
				var 称号 = "";
				if (宠物属性.基础训练 && 宠物属性.基础训练.次数){
					//宠物名字 = 宠物数据.Name + "（精锐" + 宠物属性.基础训练.次数 + "）";
					称号 =  "精锐" + 宠物属性.基础训练.次数;
				}
				var 宠物对象 = _root.加载游戏世界人物(宠物兵种,宠物实例名,_root.gameworld.getNextHighestDepth(),{等级:宠物等级, 名字:宠物名字, 宠物属性:宠物属性, 是否为敌人:宠物是否为敌人, 身高:宠物身高, _x:地点X, _y:地点Y,称号:称号});
				宠物mc库.push(宠物对象);
				if (当前宠物信息[0] == 66){
					宠物对象.长枪 = "L85A1";
				}
				出战宠物id库.push(i);
			}else{
				_root.发布消息(_root.获得翻译("宠物体力不足，无法出战！"));
			}
		}
	}
	//加载宠物后立即应用减体力
	if(_root.当前为战斗地图) _root.宠物减体力();
}

_root.宠物减体力 = function(){
	for (var i = 0; i < _root.出战宠物id库.length; i++){
		var 当前宠物信息 = _root.宠物信息[出战宠物id库[i]];
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
	var 本地loadgame = SharedObject.getLocal("crazyflasher7_saves");
	if (本地loadgame.data.战宠 == undefined){
		_root.宠物信息 = new Array(5);
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
	var mysave = SharedObject.getLocal("crazyflasher7_saves");
	mysave.data.战宠 = _root.宠物信息;
	mysave.data.宠物领养限制 = _root.宠物领养限制;
	mysave.flush();
}

_root.最大宠物格子数 = 80;
_root.最大宠物出战数 = 5;
_root.宠物信息 = [];
_root.读取本地存盘战宠();
