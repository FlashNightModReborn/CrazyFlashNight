_root.主角函数.开始射击 = function(){
	var 攻击模式 = _parent.攻击模式;
	if (_parent.主手射击中 || this.换弹标签) return;
	if (_parent[攻击模式 + "射击次数"][_parent[攻击模式]] >= _parent[攻击模式 + "弹匣容量"])
	{
		if(剩余弹匣数 > 0 || _root.控制目标 != _parent._name) 开始换弹();
		return;
	}
	if (!this.射击许可标签) return;
	var 继续射击许可 = this.主手持续射击(_parent, 攻击模式, this.射击速度);
	if(继续射击许可){
		_parent.keepshooting = _root.帧计时器.添加生命周期任务(_parent, "开始射击", this.主手持续射击, this.射击速度, _parent, 攻击模式, this.射击速度);
		if(this.射击速度 > 300){
			_root.帧计时器.添加或更新任务(_parent, "结束射击后摇", function(自机){自机.射击最大后摇中 = false;}, 300, _parent);
		}
	}
}

_root.主角函数.主手持续射击 = function(自机, 攻击模式, 射击速度){
	自机.射击最大后摇中 = false;
	if(!自机.man.射击许可标签){
		自机.主手射击中 = false;
		_root.帧计时器.移除任务(自机.keepshooting);
		return false;
	}
	自机.man.子弹属性.角度偏移 = 0;
	var 跳转帧名 = "射击";
	if (_root.控制目标 === 自机._name && !自机.上下移动射击)
	{
		if (自机.下行)
		{
			自机.man.子弹属性.角度偏移 = 30;
			跳转帧名 = "下射击";
		}
		else if (自机.上行)
		{
			自机.man.子弹属性.角度偏移 = -30;
			跳转帧名 = "上射击";
		}
	}
	自机.主手射击中 = false;
	if(自机.动作A){
		自机.man.gotoAndPlay(跳转帧名);
		自机.主手射击中 = 自机[攻击模式 + "射击"](自机.man.枪.枪.装扮.枪口位置, 自机.man.子弹属性);
		var 弹匣余弹量 = 自机[攻击模式 + "弹匣容量"] - 自机[攻击模式 + "射击次数"][自机[攻击模式]];
		if (_root.控制目标 === 自机._name) _root.玩家信息界面.玩家必要信息界面.子弹数 = 弹匣余弹量;
		if (弹匣余弹量 <= 0) 自机.主手射击中 = false;
		自机.射击最大后摇中 = 自机.主手射击中;
		if(射击速度 > 300){
			_root.帧计时器.添加或更新任务(自机, "结束射击后摇", function(自机){自机.射击最大后摇中 = false;}, 300, 自机);
		}
	}

	if(自机.主手射击中) return true;
	_root.帧计时器.移除任务(自机.keepshooting);
	return false;
}

_root.主角函数.副手持续射击 = function(自机, 攻击模式, 射击速度){
	自机.射击最大后摇中 = false;
	if(!自机.man.射击许可标签){
		自机.副手射击中 = false;
		_root.帧计时器.移除任务(自机.keepshooting2);
		return false;
	}
	自机.man.子弹属性.角度偏移 = 0;
	自机.man.子弹属性2.角度偏移 = 0;
	var 跳转帧名 = "射击2";
	if (_root.控制目标 === 自机._name && !自机.上下移动射击)
	{
		if (自机.下行)
		{
			自机.man.子弹属性.角度偏移 = 30;
			自机.man.子弹属性2.角度偏移 = 30;
			跳转帧名 = "下射击2";
		}
		else if (自机.上行)
		{
			自机.man.子弹属性.角度偏移 = -30;
			自机.man.子弹属性2.角度偏移 = -30;
			跳转帧名 = "上射击2";
		}
	}
	自机.副手射击中 = false;
	if(自机.动作B){
		自机.man.gotoAndPlay(跳转帧名);
		自机.副手射击中 = 自机[攻击模式 + "射击"](自机.man.枪2.枪.装扮.枪口位置, 自机.man.子弹属性2);
		var 弹匣余弹量 = 自机[攻击模式 + "弹匣容量"] - 自机[攻击模式 + "射击次数"][自机[攻击模式]];
		if (_root.控制目标 === 自机._name) _root.玩家信息界面.玩家必要信息界面.子弹数_2 = 弹匣余弹量;
		if (弹匣余弹量 <= 0) 自机.副手射击中 = false;
		自机.射击最大后摇中 = 自机.副手射击中;
		if(射击速度 > 300){
			_root.帧计时器.添加或更新任务(自机, "结束射击后摇", function(自机){自机.射击最大后摇中 = false;}, 300, 自机);
		}
	}

	if(自机.副手射击中) return true;
	_root.帧计时器.移除任务(自机.keepshooting2);
	return false;
}


_root.主角函数.开始换弹 = function()
{
	var 攻击模式 = _parent.攻击模式;
	if(this.换弹标签 || _parent[攻击模式 + "射击次数"][_parent[攻击模式]] == 0) return;
	if (_root.控制目标 === _parent._name)
	{
		if(org.flashNight.arki.item.ItemUtil.singleContain(使用弹匣名称,1) != null){
			gotoAndPlay("换弹匣");
		}
		// for(var i = 0; i < _root.物品栏总数; i++)
		// {
		// 	if (_root.物品栏[i][0] === 使用弹匣名称 && _root.物品栏[i][1] >= 1)
		// 	{
		// 		this.弹匣所在物品栏编号 = i;
		// 		gotoAndPlay("换弹匣");
		// 		return;
		// 	}
		// }
	}
	else
	{
		gotoAndPlay("换弹匣");
	}
}

_root.主角函数.换弹匣 = function(){
	var 攻击模式 = _parent.攻击模式;
	_parent[攻击模式 + "射击次数"][_parent[攻击模式]] = 0;
	if (_root.控制目标 === _parent._name)
	{
		org.flashNight.arki.item.ItemUtil.singleSubmit(使用弹匣名称,1);
		// if(--_root.物品栏[弹匣所在物品栏编号][1] <= 0){
		// 	_root.物品栏[弹匣所在物品栏编号] = ["空", 0, 0];
		// }
		剩余弹匣数 = _parent.检查弹匣数量(使用弹匣名称);
		if(剩余弹匣数 === 0) _root.发布消息("弹匣耗尽！");
		_root.排列物品图标();
		_parent.当前弹夹副武器已发射数 = 0;
		刷新弹匣数显示();
	}
}

_root.主角函数.结束换弹 = function(){
	gotoAndStop("空闲");
}

_root.主角函数.刷新弹匣数显示 = function(){
	if(_root.控制目标 != _parent._name) return;
	var 攻击模式 = _parent.攻击模式;
	if(攻击模式 === "双枪"){
		_root.玩家信息界面.玩家必要信息界面.子弹数 = _parent.手枪弹匣容量 - _parent.手枪射击次数[_parent.手枪];
		_root.玩家信息界面.玩家必要信息界面.弹夹数 = 主手剩余弹匣数;
		_root.玩家信息界面.玩家必要信息界面.子弹数_2 = _parent.手枪2弹匣容量 - _parent.手枪2射击次数[_parent.手枪2];
		_root.玩家信息界面.玩家必要信息界面.弹夹数_2 = 副手剩余弹匣数;
	}else{
		_root.玩家信息界面.玩家必要信息界面.子弹数 = _parent[攻击模式 + "弹匣容量"] - _parent[攻击模式 + "射击次数"][_parent[攻击模式]];
		_root.玩家信息界面.玩家必要信息界面.弹夹数 = 剩余弹匣数;
	}
}


_root.主角函数.初始化长枪射击函数 = function(){
	if(_parent.攻击模式 != "长枪") return;

	this.开始射击 = _root.主角函数.开始射击;
	this.主手持续射击 = _root.主角函数.主手持续射击;

	this.开始换弹 = _root.主角函数.开始换弹;
	this.换弹匣 = _root.主角函数.换弹匣;
	this.结束换弹 = _root.主角函数.结束换弹;


	this.长枪属性 = _parent.长枪属性数组[14];

	this.射击速度 = 长枪属性[5];
	this.使用弹匣名称 = 长枪属性[11];
	this.长枪是否单发 = 长枪属性[3];
	this.剩余弹匣数 = _parent.检查弹匣数量(使用弹匣名称);

	this.刷新弹匣数显示 = _root.主角函数.刷新弹匣数显示;
	this.刷新弹匣数显示();

	//读取子弹属性
	this.子弹属性 = new Object();
	this.子弹属性.发射者 = _parent._name;
	this.子弹属性.声音 = 长枪属性[8];
	this.子弹属性.霰弹值 = 长枪属性[1];
	this.子弹属性.子弹散射度 = 长枪属性[2];
	this.子弹属性.站立子弹散射度 = 长枪属性[2];
	this.子弹属性.移动子弹散射度 = 长枪属性[2] + 20 - (_parent.被动技能.移动射击 && _parent.被动技能.移动射击.启用 && _parent.被动技能.移动射击.等级? _parent.被动技能.移动射击.等级 * 2 : 0);
	this.子弹属性.发射效果 = 长枪属性[9];
	this.子弹属性.子弹种类 = 长枪属性[7];
	this.子弹属性.子弹威力 = 长枪属性[13];
	if (_parent.被动技能.枪械攻击 && _parent.被动技能.枪械攻击.启用)
	{
		this.子弹属性.子弹威力 = 长枪属性[13] * (1.5 + _parent.被动技能.枪械攻击.等级 * 0.03) + 30;
	}
	if (_parent.长枪额外攻击加成倍率)
	{
		子弹属性.子弹威力 += 长枪属性[13] * _parent.长枪额外攻击加成倍率;
	}
	
	var 暴击 =  _parent.长枪暴击;
	if (暴击){
		if(!isNaN(Number(暴击))){
			子弹属性.暴击 = function(当前子弹){
				if(_root.成功率(Number(暴击))){
					return 1.5;
				}
				return 1;
			}
		}else if(暴击== "满血暴击"){
			子弹属性.暴击 = function(当前子弹){
				// _root.发布消息(当前子弹.hitTarget.hp + " " + 当前子弹.hitTarget.hp满血值);
				if(当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值){
					return 1.5;
				}
				return 1;
			}
		}
	}
	
	var 斩杀 =  _parent.长枪斩杀;
	if(斩杀 && !isNaN(Number(斩杀))){
		子弹属性.斩杀 = Number(斩杀);
	}
	this.子弹属性.子弹速度 = 长枪属性[6];
	this.子弹属性.击中地图效果 = 长枪属性[10];
	this.子弹属性.Z轴攻击范围 = 长枪属性[12];
	this.子弹属性.击倒率 = 长枪属性[14];
	this.子弹属性.击中后子弹的效果 = 长枪属性[15];
	this.子弹属性.子弹敌我属性 = !_parent.是否为敌人;
};


_root.主角函数.初始化手枪射击函数 = function(){
	if(_parent.攻击模式 != "手枪") return;

	this.开始射击 = _root.主角函数.开始射击;
	this.主手持续射击 = _root.主角函数.主手持续射击;

	this.开始换弹 = _root.主角函数.开始换弹;
	this.换弹匣 = _root.主角函数.换弹匣;
	this.结束换弹 = _root.主角函数.结束换弹;


	手枪属性 = _parent.手枪属性数组[14];

	this.射击速度 = 手枪属性[5];
	this.使用弹匣名称 = 手枪属性[11];
	this.手枪是否单发 = 手枪属性[3];
	this.剩余弹匣数 = _parent.检查弹匣数量(使用弹匣名称);

	this.刷新弹匣数显示 = _root.主角函数.刷新弹匣数显示;
	this.刷新弹匣数显示();

	//读取子弹属性
	this.子弹属性 = new Object();
	this.子弹属性.发射者 = _parent._name;
	this.子弹属性.声音 = 手枪属性[8];
	this.子弹属性.霰弹值 = 手枪属性[1];
	this.子弹属性.子弹散射度 = 手枪属性[2];
	this.子弹属性.站立子弹散射度 = 手枪属性[2];
	this.子弹属性.移动子弹散射度 = 手枪属性[2] + 20 - (_parent.被动技能.移动射击 && _parent.被动技能.移动射击.启用 && _parent.被动技能.移动射击.等级? _parent.被动技能.移动射击.等级 * 2 : 0);
	this.子弹属性.发射效果 = 手枪属性[9];
	this.子弹属性.子弹种类 = 手枪属性[7];
	this.子弹属性.子弹威力 = 手枪属性[13];
	if (_parent.被动技能.枪械攻击 && _parent.被动技能.枪械攻击.启用)
	{
		this.子弹属性.子弹威力 = 手枪属性[13] * (1 + _parent.被动技能.枪械攻击.等级 * 0.015) + 20;
	}
	if(_parent.短枪额外攻击加成倍率)
	{
		this.子弹属性.子弹威力 += 手枪属性[13] * _parent.短枪额外攻击加成倍率;
	}
	
	var 暴击 =  _parent.手枪暴击;
	if (暴击)
	{
		if(!isNaN(Number(暴击))){
			子弹属性.暴击 = function(当前子弹){
				if(_root.成功率(Number(暴击))){
					return 1.5;
				}
				return 1;
			}
		}else if(暴击== "满血暴击"){
			子弹属性.暴击 = function(当前子弹){
				if(当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值){
					return 1.5;
				}
				return 1;
			}
		}
	}
	
	var 斩杀 =  _parent.手枪斩杀;
	if(斩杀 && !isNaN(Number(斩杀))){
		子弹属性.斩杀 = Number(斩杀);
	}
	this.子弹属性.子弹速度 = 手枪属性[6];
	this.子弹属性.击中地图效果 = 手枪属性[10];
	this.子弹属性.Z轴攻击范围 = 手枪属性[12];
	this.子弹属性.击倒率 = 手枪属性[14];
	this.子弹属性.击中后子弹的效果 = 手枪属性[15];
	this.子弹属性.子弹敌我属性 = !_parent.是否为敌人;
};

_root.主角函数.初始化手枪2射击函数 = function(){
	if(_parent.攻击模式 != "手枪2") return;

	this.开始射击 = _root.主角函数.开始射击;
	this.主手持续射击 = _root.主角函数.主手持续射击;

	this.开始换弹 = _root.主角函数.开始换弹;
	this.换弹匣 = _root.主角函数.换弹匣;
	this.结束换弹 = _root.主角函数.结束换弹;


	this.手枪2属性 = _parent.手枪2属性数组[14];

	this.射击速度 = 手枪2属性[5];
	this.使用弹匣名称 = 手枪2属性[11];
	this.手枪2是否单发 = 手枪2属性[3];
	this.剩余弹匣数 = _parent.检查弹匣数量(使用弹匣名称);

	this.刷新弹匣数显示 = _root.主角函数.刷新弹匣数显示;
	this.刷新弹匣数显示();

	//读取子弹属性
	this.子弹属性 = new Object();
	this.子弹属性.发射者 = _parent._name;
	this.子弹属性.声音 = 手枪2属性[8];
	this.子弹属性.霰弹值 = 手枪2属性[1];
	this.子弹属性.子弹散射度 = 手枪2属性[2];
	this.子弹属性.站立子弹散射度 = 手枪2属性[2];
	this.子弹属性.移动子弹散射度 = 手枪2属性[2] + 20 - (_parent.被动技能.移动射击 && _parent.被动技能.移动射击.启用 && _parent.被动技能.移动射击.等级? _parent.被动技能.移动射击.等级 * 2 : 0);
	this.子弹属性.发射效果 = 手枪2属性[9];
	this.子弹属性.子弹种类 = 手枪2属性[7];
	this.子弹属性.子弹威力 = 手枪2属性[13];
	if (_parent.被动技能.枪械攻击 && _parent.被动技能.枪械攻击.启用)
	{
		this.子弹属性.子弹威力 = 手枪2属性[13] * (1 + _parent.被动技能.枪械攻击.等级 * 0.015) + 20;
	}
	if(_parent.短枪额外攻击加成倍率)
	{
		this.子弹属性.子弹威力 += 手枪2属性[13] * _parent.短枪额外攻击加成倍率;
	}
	
	var 暴击 =  _parent.手枪2暴击;
	if (暴击)
	{
		if(!isNaN(Number(暴击))){
			子弹属性.暴击 = function(当前子弹){
				if(_root.成功率(Number(暴击))){
					return 1.5;
				}
				return 1;
			}
		}else if(暴击== "满血暴击"){
			子弹属性.暴击 = function(当前子弹){
				if(当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值){
					return 1.5;
				}
				return 1;
			}
		}
	}
	
	var 斩杀 =  _parent.手枪2斩杀;
	if(斩杀 && !isNaN(Number(斩杀))){
		子弹属性.斩杀 = Number(斩杀);
	}
	this.子弹属性.子弹速度 = 手枪2属性[6];
	this.子弹属性.击中地图效果 = 手枪2属性[10];
	this.子弹属性.Z轴攻击范围 = 手枪2属性[12];
	this.子弹属性.击倒率 = 手枪2属性[14];
	this.子弹属性.击中后子弹的效果 = 手枪2属性[15];
	this.子弹属性.子弹敌我属性 = !_parent.是否为敌人;
};

_root.主角函数.初始化双枪射击函数 = function(){
	if(_parent.攻击模式 != "双枪") return;
	this.开始换弹 = function()
	{
		if(this.换弹标签 || (_parent.手枪射击次数[_parent.手枪] == 0 && _parent.手枪2射击次数[_parent.手枪2] == 0)) return;
		if (_root.控制目标 === _parent._name)
		{
			if(_parent.手枪射击次数[_parent.手枪] > 0){
				if(org.flashNight.arki.item.ItemUtil.singleContain(主手使用弹匣名称,1)){
					gotoAndPlay("主手换弹匣");
					return;
				}
				// for(var i = 0; i < _root.物品栏总数; i++)
				// {
				// 	if (_root.物品栏[i][0] === 主手使用弹匣名称 && _root.物品栏[i][1] >= 1)
				// 	{
				// 		this.弹匣所在物品栏编号 = i;
				// 		gotoAndPlay("主手换弹匣");
				// 		return;
				// 	}
				// }
			}else if(_parent.手枪2射击次数[_parent.手枪2] > 0){
				if(org.flashNight.arki.item.ItemUtil.singleContain(副手使用弹匣名称,1)){
					gotoAndPlay("副手换弹匣");
					return;
				}
				// for(var i = 0; i < _root.物品栏总数; i++){
				// 	if (_root.物品栏[i][0] === 副手使用弹匣名称 && _root.物品栏[i][1] >= 1){
				// 		this.弹匣所在物品栏编号 = i;
				// 		gotoAndPlay("副手换弹匣");
				// 		return;
				// 	}
				// }
			}
		}
		else
		{
			gotoAndPlay("主手换弹匣");
		}
	}

	this.主手换弹匣 = function(){
		_parent.手枪射击次数[_parent.手枪] = 0;
		if (_root.控制目标 === _parent._name){
			org.flashNight.arki.item.ItemUtil.singleSubmit(主手使用弹匣名称,1);
			// if(--_root.物品栏[弹匣所在物品栏编号][1] <= 0){
			// 	_root.物品栏[弹匣所在物品栏编号] = ["空", 0, 0];
			// }
			主手剩余弹匣数 = _parent.检查弹匣数量(主手使用弹匣名称);
			副手剩余弹匣数 = _parent.检查弹匣数量(副手使用弹匣名称);
			if(主手剩余弹匣数 === 0) _root.发布消息("弹匣耗尽！");
			_root.排列物品图标();
			刷新弹匣数显示();
			if(副手剩余弹匣数 == 0 || _parent.手枪2射击次数[_parent.手枪2] == 0){
				gotoAndPlay("换弹结束");
			}
		}
	}

	this.副手换弹匣 = function(){
		_parent.手枪2射击次数[_parent.手枪2] = 0;
		if (_root.控制目标 === _parent._name){
			org.flashNight.arki.item.ItemUtil.singleSubmit(副手使用弹匣名称,1);
			// if(--_root.物品栏[弹匣所在物品栏编号][1] <= 0){
			// 	_root.物品栏[弹匣所在物品栏编号] = ["空", 0, 0];
			// }
			主手剩余弹匣数 = _parent.检查弹匣数量(主手使用弹匣名称);
			副手剩余弹匣数 = _parent.检查弹匣数量(副手使用弹匣名称);
			if(副手剩余弹匣数 === 0) _root.发布消息("弹匣耗尽！");
			_root.排列物品图标();
			刷新弹匣数显示();
		}
	}

	this.结束换弹 = _root.主角函数.结束换弹;


	this.主手开始射击 = function()
	{
		if (_parent.主手射击中 || this.换弹标签) return;
		if (_parent.手枪射击次数[_parent.手枪] >= _parent.手枪弹匣容量)
		{
			if((_parent.手枪2射击次数[_parent.手枪2] >= _parent.手枪2弹匣容量 && 主手剩余弹匣数 > 0) || _root.控制目标 != _parent._name) 开始换弹();
			return;
		}
		if (!this.射击许可标签) return;
		var 继续射击许可 = 主手持续射击(_parent, "手枪", 主手射击速度);
		if(继续射击许可) {
			_parent.keepshooting = _root.帧计时器.添加生命周期任务(_parent, "主手开始射击", this.主手持续射击, 主手射击速度, _parent, "手枪", 主手射击速度);
		}
	}

	this.副手开始射击 = function()
	{
		if (_parent.副手射击中 || this.换弹标签) return;
		if (_parent.手枪2射击次数[_parent.手枪2] >= _parent.手枪2弹匣容量)
		{
			if((_parent.手枪射击次数[_parent.手枪] >= _parent.手枪弹匣容量 && 副手剩余弹匣数 > 0) || _root.控制目标 != _parent._name) 开始换弹();
			return;
		}
		if (!this.射击许可标签) return;
		var 继续射击许可 = 副手持续射击(_parent, "手枪2", 副手射击速度);
		if(继续射击许可){
			_parent.keepshooting2 = _root.帧计时器.添加生命周期任务(_parent, "副手开始射击", this.副手持续射击, 副手射击速度, _parent, "手枪2", 副手射击速度);
		}
	}

	this.主手持续射击 = _root.主角函数.主手持续射击;
	this.副手持续射击 = _root.主角函数.副手持续射击;


	this.手枪属性 = _parent.手枪属性数组[14];
	this.手枪2属性 = _parent.手枪2属性数组[14];

	this.主手射击速度 = 手枪属性[5];
	this.主手使用弹匣名称 = 手枪属性[11];
	this.主手是否单发 = 手枪属性[3];
	this.主手剩余弹匣数 = _parent.检查弹匣数量(主手使用弹匣名称);

	this.副手射击速度 = 手枪2属性[5];
	this.副手使用弹匣名称 = 手枪2属性[11];
	this.副手是否单发 = 手枪2属性[3];
	this.副手剩余弹匣数 = _parent.检查弹匣数量(副手使用弹匣名称);

	this.刷新弹匣数显示 = _root.主角函数.刷新弹匣数显示;
	this.刷新弹匣数显示();

	//读取子弹属性
	this.子弹属性 = new Object();
	this.子弹属性.发射者 = _parent._name;
	this.子弹属性.声音 = 手枪属性[8];
	this.子弹属性.霰弹值 = 手枪属性[1];
	this.子弹属性.子弹散射度 = 手枪属性[2];
	this.子弹属性.站立子弹散射度 = 手枪属性[2];
	this.子弹属性.移动子弹散射度 = 手枪属性[2] + 20 - (_parent.被动技能.移动射击 && _parent.被动技能.移动射击.启用 && _parent.被动技能.移动射击.等级? _parent.被动技能.移动射击.等级 * 2 : 0);
	this.子弹属性.发射效果 = 手枪属性[9];
	this.子弹属性.子弹种类 = 手枪属性[7];
	this.子弹属性.子弹威力 = 手枪属性[13];
	if (_parent.被动技能.枪械攻击 && _parent.被动技能.枪械攻击.启用)
	{
		this.子弹属性.子弹威力 = 手枪属性[13] * (1 + _parent.被动技能.枪械攻击.等级 * 0.015) + 20;
	}
	if(_parent.短枪额外攻击加成倍率)
	{
		this.子弹属性.子弹威力 += 手枪属性[13] * _parent.短枪额外攻击加成倍率;
	}
	if(_parent.手枪伤害类型)
	{
		this.子弹属性.伤害类型 = _parent.手枪伤害类型;
	}
	if(_parent.手枪魔法伤害属性)
	{
		this.子弹属性.魔法伤害属性 = _parent.手枪魔法伤害属性;
	}
	if(_parent.手枪毒)
	{
		this.子弹属性.毒 = _parent.手枪毒;
	}
	if(_parent.手枪吸血)
	{
		this.子弹属性.吸血 = _parent.手枪吸血;
	}
	if(_parent.手枪击溃)
	{
		this.子弹属性.血量上限击溃 = _parent.手枪击溃;
	}
	
	var 暴击 =  _parent.手枪暴击;
	if (暴击)
	{
		if(!isNaN(Number(暴击))){
			子弹属性.暴击 = function(当前子弹){
				if(_root.成功率(Number(暴击))){
					return 1.5;
				}
				return 1;
			}
		}else if(暴击== "满血暴击"){
			子弹属性.暴击 = function(当前子弹){
				if(当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值){
					return 1.5;
				}
				return 1;
			}
		}
	}
	
	var 斩杀 =  _parent.手枪斩杀;
	if(斩杀 && !isNaN(Number(斩杀))){
		子弹属性.斩杀 = Number(斩杀);
	}
	this.子弹属性.子弹速度 = 手枪属性[6];
	this.子弹属性.击中地图效果 = 手枪属性[10];
	this.子弹属性.Z轴攻击范围 = 手枪属性[12];
	this.子弹属性.击倒率 = 手枪属性[14];
	this.子弹属性.击中后子弹的效果 = 手枪属性[15];
	this.子弹属性.子弹敌我属性 = !_parent.是否为敌人;

	this.子弹属性2 = new Object();
	this.子弹属性2.发射者 = _parent._name;
	this.子弹属性2.声音 = 手枪2属性[8];
	this.子弹属性2.霰弹值 = 手枪2属性[1];
	this.子弹属性2.子弹散射度 = 手枪2属性[2];
	this.子弹属性2.站立子弹散射度 = 手枪2属性[2];
	this.子弹属性2.移动子弹散射度 = 手枪2属性[2] + 20 - (_parent.被动技能.移动射击 && _parent.被动技能.移动射击.启用 && _parent.被动技能.移动射击.等级? _parent.被动技能.移动射击.等级 * 2 : 0);
	this.子弹属性2.发射效果 = 手枪2属性[9];
	this.子弹属性2.子弹种类 = 手枪2属性[7];
	this.子弹属性2.子弹威力 = 手枪2属性[13];
	if (_parent.被动技能.枪械攻击 && _parent.被动技能.枪械攻击.启用)
	{
		this.子弹属性2.子弹威力 = 手枪2属性[13] * (1 + _parent.被动技能.枪械攻击.等级 * 0.015) + 20;
	}
	if(_parent.短枪额外攻击加成倍率)
	{
		this.子弹属性2.子弹威力 += 手枪2属性[13] * _parent.短枪额外攻击加成倍率;
	}
	if(_parent.手枪2伤害类型)
	{
		this.子弹属性2.伤害类型 = _parent.手枪2伤害类型;
	}
	if(_parent.手枪2魔法伤害属性)
	{
		this.子弹属性2.魔法伤害属性 = _parent.手枪2魔法伤害属性;
	}
	if(_parent.手枪2毒)
	{
		this.子弹属性2.毒 = _parent.手枪2毒;
	}
	if(_parent.手枪2吸血)
	{
		this.子弹属性2.吸血 = _parent.手枪2吸血;
	}
	if(_parent.手枪2击溃)
	{
		this.子弹属性2.血量上限击溃 = _parent.手枪2击溃;
	}
	
	var 暴击 =  _parent.手枪2暴击;
	if (暴击)
	{
		if(!isNaN(Number(暴击))){
			子弹属性2.暴击 = function(当前子弹){
				if(_root.成功率(Number(暴击))){
					return 1.5;
				}
				return 1;
			}
		}else if(暴击== "满血暴击"){
			子弹属性2.暴击 = function(当前子弹){
				if(当前子弹.hitTarget.hp >= 当前子弹.hitTarget.hp满血值){
					return 1.5;
				}
				return 1;
			}
		}
	}
	
	var 斩杀 =  _parent.手枪2斩杀;
	if(斩杀 && !isNaN(Number(斩杀))){
		子弹属性2.斩杀 = Number(斩杀);
	}
	this.子弹属性2.子弹速度 = 手枪2属性[6];
	this.子弹属性2.击中地图效果 = 手枪2属性[10];
	this.子弹属性2.Z轴攻击范围 = 手枪2属性[12];
	this.子弹属性2.击倒率 = 手枪2属性[14];
	this.子弹属性2.击中后子弹的效果 = 手枪2属性[15];
	this.子弹属性2.子弹敌我属性 = !_parent.是否为敌人;
};

