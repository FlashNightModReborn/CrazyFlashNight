import org.flashNight.arki.unit.UnitComponent.Initializer.*;

_root.可拾取物计数 = 0;

_root.创建可拾取物 = function(物品名, 数量, X位置, Y位置, 是否飞出, 参数对象)
{
	if(数量 <= 0) 数量 = 1;
	if (物品名 === "金钱" && random(_root.打怪掉钱机率) == 0)
	{
		物品名 = "K点";
	}
	if(!参数对象){
		参数对象 = new Object();
	}
	参数对象._x = X位置;
	参数对象._y = Y位置;
	参数对象.物品名 = 物品名;
	参数对象.数量 = Number(数量);
	参数对象.在飞 = Boolean(是否飞出);
	var 游戏世界 = _root.gameworld;
	var 可拾取物 = 游戏世界.attachMovie("可拾取物2", "可拾取物" + _root.可拾取物计数, 游戏世界.getNextHighestDepth(), 参数对象);
	_root.可拾取物计数++;
}


_root.初始化出生点 = function(){
	//确定方向
	方向 = 方向 === "左" ? "左" : "右";
	if (方向 === "左")
	{
		this._xscale = -100;
	}
	//将碰撞箱附加到地图
	var 游戏世界 = _root.gameworld;
	if(this.area){
		var rect = this.area.getRect(游戏世界);
		var 地图 = 游戏世界.地图;

        // 设置 `地图` 为不可枚举
        _global.ASSetPropFlags(游戏世界, ["地图"], 1, true);
		
		地图.beginFill(0x000000);
		地图.moveTo(rect.xMin, rect.yMin);
		地图.lineTo(rect.xMax, rect.yMin);
		地图.lineTo(rect.xMax, rect.yMax);
		地图.lineTo(rect.xMin, rect.yMax);
		地图.lineTo(rect.xMin, rect.yMin);;
		地图.endFill();
	}
}

_root.初始化资源箱 = function(){
	if (!isNaN(最小主线进度) && 最小主线进度 > _root.主线任务进度)
	{
		this.removeMovieClip();
		return;
	}
	else if (!isNaN(最大主线进度) && 最大主线进度 < _root.主线任务进度)
	{
		this.removeMovieClip();
		return;
	}
	if (数量_min > 0 and 数量_max > 0)
	{
		数量 = 数量_min + random(数量_max - 数量_min + 1);
	}

	是否为敌人 = true;
	hp = hp满血值 = 10;
	躲闪率 = 100;
	击中效果 = "火花";
	Z轴坐标 = this._y;
	StaticInitializer.initializeUnit(this);
	gotoAndStop("正常");
}