_root.消除子弹 = function(obj)
{
	//暂停判定
	if (_root.暂停)
	{
		return;
	}
	
	var 消弹敌我属性 = obj.消弹敌我属性;
	var 消弹方向 = obj.消弹方向;
	var shootZ = obj.shootZ;
	var Z轴攻击范围 = obj.Z轴攻击范围;
	var 区域定位area = obj.区域定位area;
	
	for (var bullet in _root.gameworld.子弹区域)
	{
		var 子弹实例 = _root.gameworld.子弹区域[bullet];
		var Z轴坐标差 = 子弹实例.Z轴坐标 - shootZ;
		if(Math.abs(Z轴坐标差) > Z轴攻击范围 or 子弹实例.近战检测 or 子弹实例.xmov == 0){
			continue;
		}
		
		var 子弹方向 = 子弹实例.xmov > 0 ? "右" : "左";
		if(消弹方向 and 消弹方向 != 子弹方向){
			continue;
		}
		
		if(消弹敌我属性 == 子弹实例.子弹敌我属性值){
			var 子弹区域area = 子弹实例.area;
			if(!子弹实例.area){
				子弹区域area = 子弹实例;
			}
			if(子弹区域area.hitTest(区域定位area)){
				子弹实例.击中地图 = true;
				_root.效果(子弹实例.击中地图效果,子弹实例._x,子弹实例._y);
				子弹实例.gotoAndPlay("消失");
			}
		}
	}
};


_root.消弹属性初始化 = function(消弹区域:MovieClip){
	var 消弹属性 = {
		shootZ:消弹区域._parent._parent.Z轴坐标,
		消弹敌我属性:消弹区域._parent._parent.是否为敌人,
		消弹方向:null,
		Z轴攻击范围:10,
		区域定位area:消弹区域
	}
	return 消弹属性;
}
