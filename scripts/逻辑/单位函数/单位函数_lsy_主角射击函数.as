import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.*;

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
    // 如果控制目标不匹配，则直接返回
    if (_root.控制目标 != _parent._name) return;
    
    // 缓存UI引用
    var ui = _root.玩家信息界面.玩家必要信息界面;
    var mode = _parent.攻击模式;
    var weapons = [];
    
    // 构造武器配置：每个对象包含武器实例、弹匣容量、已射击次数（预先计算好）、UI对应字段和剩余弹匣数
    if(mode === "双枪"){
        weapons.push({
            weapon: _parent.手枪,
            capacity: _parent.手枪弹匣容量,
            shot: _parent.手枪射击次数[_parent.手枪],
            uiBullet: "子弹数",
            uiMag: "弹夹数",
            magCount: 主手剩余弹匣数
        });
        weapons.push({
            weapon: _parent.手枪2,
            capacity: _parent.手枪2弹匣容量,
            shot: _parent.手枪2射击次数[_parent.手枪2],
            uiBullet: "子弹数_2",
            uiMag: "弹夹数_2",
            magCount: 副手剩余弹匣数
        });
    } else {
        // 单武器情况：注意这里“射击次数”是个对象，需要预先取出正确的值
        var singleShot = _parent[mode + "射击次数"][_parent[mode]];
        weapons.push({
            weapon: _parent.长枪,
            capacity: _parent[mode + "弹匣容量"],
            shot: singleShot,
            uiBullet: "子弹数",
            uiMag: "弹夹数",
            magCount: 剩余弹匣数
        });
    }
    
    // 统一遍历每个武器配置，计算剩余子弹数并更新UI
    for(var i = 0; i < weapons.length; i++){
        var w = weapons[i];
        var data = ItemUtil.getRawItemData(w.weapon);
        // 根据bullet属性判断是否需要拆分计算
        var cost = (data.data.bullet.indexOf("纵向") >= 0) ? data.data.split : 1;
        var remaining = w.capacity - w.shot;
        
        ui[w.uiBullet] = cost * remaining;
        ui[w.uiMag] = w.magCount;
    }
};



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
