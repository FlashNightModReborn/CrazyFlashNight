import org.flashNight.arki.unit.Action.Shoot.*;

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

// 主手持续射击包装函数
_root.主角函数.主手持续射击 = function(core, attackMode, shootSpeed){
    return ShootCore.continuousShoot(core, attackMode, shootSpeed, 
           ShootCore.primaryParams);
};

// 副手持续射击包装函数
_root.主角函数.副手持续射击 = function(core, attackMode, shootSpeed){
    return ShootCore.continuousShoot(core, attackMode, shootSpeed, 
           ShootCore.secondaryParams);
};



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


// 初始化长枪射击函数
_root.主角函数.初始化长枪射击函数 = function():Void {
    ShootInitCore.initLongGun(this, _parent);
};

// 初始化手枪射击函数
_root.主角函数.初始化手枪射击函数 = function():Void {
    ShootInitCore.initPistol(this, _parent);
};

// 初始化手枪2射击函数
_root.主角函数.初始化手枪2射击函数 = function():Void {
    ShootInitCore.initPistol2(this, _parent);
};

// 初始化双枪射击函数
_root.主角函数.初始化双枪射击函数 = function():Void {
    ShootInitCore.initDualGun(this, _parent);
};
