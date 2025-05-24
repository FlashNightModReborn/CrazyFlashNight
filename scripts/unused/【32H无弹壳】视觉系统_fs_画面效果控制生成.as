_root.当前效果总数 = 0;
_root.效果存在时间 = 1 * 1000;
_root.当前画面效果总数 = 0;
_root.画面效果存在时间 = 1 * 1000;

_root.效果 = function(效果种类, myX, myY, 方向, 必然触发)
{
	_root.联机2015特效发送(效果种类,myX,myY,方向,-1);
	var 效果 = _root.gameworld.效果;
	if (_root.是否视觉元素 and (_root.当前效果总数 <= _root.效果上限 or _root.成功率(_root.效果上限 / 5)) or 必然触发)
	{
		var 效果深度 = 效果.getNextHighestDepth();
		var 效果名 = "mc" + 效果深度;
		新效果 = 效果.attachMovie(效果种类,效果名,效果深度);
		新效果._x = myX;
		新效果._y = myY;
		新效果._xscale = 方向;
		_root.当前效果总数++;

		
		var 定时器ID = _root.帧计时器.添加单次任务(function (){
			_root.当前效果总数--;
		}, _root.效果存在时间);// 添加定时器

		return 效果名;
	}
};


_root.画面效果 = function(效果种类, myX, myY, 方向, 必然触发)
{
	if (_root.是否视觉元素 and (_root.当前画面效果总数 <= _root.画面效果上限 or _root.成功率( _root.画面效果上限 / 5)) or 必然触发)
	{
		var 效果深度 = _root.getNextHighestDepth();
		var 效果名 = "mc" + 效果深度;
		_root.attachMovie(效果种类,效果名,效果深度);
		_root[效果名]._x = myX;
		_root[效果名]._y = myY;
		_root[效果名]._xscale = 方向;
		_root.当前画面效果总数++;
		//_root.发布调试消息("增加画面效果计数到" + _root.当前画面效果总数);
		// 添加定时器
		var 定时器ID = _root.帧计时器.添加单次任务(function (){
			_root.当前画面效果总数--;
		}, _root.画面效果存在时间);
	}
};



