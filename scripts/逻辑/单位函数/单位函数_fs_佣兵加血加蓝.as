_root.佣兵集体加血 = function(加血值:Number)
{
	for (var 目标 in _root.gameworld)
	{
		if (_root.gameworld[目标].是否为敌人 == false && _root.gameworld[目标].hp != undefined && _root.gameworld[目标].hp > 0  && _root.gameworld[目标].hp < _root.gameworld[目标].hp满血值 && 加血值 != undefined && isNaN(_root.gameworld[目标].hp) != true && isNaN(加血值) != true)
		{
			if (_root.gameworld[目标].hp + 加血值 > _root.gameworld[目标].hp满血值)
			{
				_root.gameworld[目标].hp = _root.gameworld[目标].hp满血值;
			}
			else
			{
				_root.gameworld[目标].hp += 加血值;
			}
			_root.效果("药剂动画-2",_root.gameworld[目标]._x,_root.gameworld[目标]._y,100,true);
		}
	}
};
_root.佣兵集体回蓝 = function(回蓝值:Number)
{
	for (var 目标 in _root.gameworld)
	{
		if (_root.gameworld[目标].是否为敌人 == false && _root.gameworld[目标].mp != undefined && _root.gameworld[目标].mp > 0 && 回蓝值 != undefined && isNaN(_root.gameworld[目标].mp) != true && isNaN(回蓝值) != true)
		{
			if (_root.gameworld[目标].mp + 回蓝值 > _root.gameworld[目标].mp满血值)
			{
				_root.gameworld[目标].mp = _root.gameworld[目标].mp满血值;
			}
			else
			{
				_root.gameworld[目标].mp += 回蓝值;
			}
			_root.效果("药剂动画-2",_root.gameworld[目标]._x,_root.gameworld[目标]._y,100,true);
		}
	}
};

_root.佣兵使用血包 = function(目标)
{
	var 加血值 = _root.gameworld[目标].hp满血值 * _root.gameworld[目标].血包恢复比例/100;

	if(_root.gameworld[目标].是否为敌人==false){
		加血值=加血值*2;
	}
	
	if (_root.gameworld[目标].hp > 0)
	{
		if (_root.gameworld[目标].hp + 加血值 > _root.gameworld[目标].hp满血值)
		{
			_root.gameworld[目标].hp = _root.gameworld[目标].hp满血值;
		}
		else
		{
			_root.gameworld[目标].hp += 加血值;
		}
		_root.效果("药剂动画-2",_root.gameworld[目标]._x,_root.gameworld[目标]._y,100,true);
	}
	

};