_root.当前效果总数 = 0;
_root.当前画面效果总数 = 0;
_root.画面效果存在时间 = 1 * 1000;

_root.效果系统 = {};
_root.效果系统.初始化效果池 = function()
{
	var 游戏世界 = _root.gameworld;
    游戏世界.可用效果池 = {};
    _root.当前效果总数 = 0;
};

_root.效果系统.创建效果 = function(效果种类, myX, myY)
{
	var 游戏世界 = _root.gameworld;// 缓存全局对象
	var 世界效果 = 游戏世界.效果;
	var 效果深度 = 世界效果.getNextHighestDepth();
	var 效果名 = 效果种类 + " " + 效果深度;

	var 创建的效果 = 世界效果.attachMovie(效果种类,效果名,效果深度,{_x:myX, _y:myY});
	创建的效果.效果种类 = 效果种类;
    创建的效果.old_removeMovieClip = 创建的效果.removeMovieClip;

	创建的效果.removeMovieClip = function(是否销毁) 
	{
		if (是否销毁) 
		{
			_root.服务器.发布服务器消息("已被remove");
			this.old_removeMovieClip();	
		} 
		else 
		{
			var 效果池 = 游戏世界.可用效果池[this.效果种类];
			if (!效果池) 
			{
				效果池 = 游戏世界.可用效果池[this.效果种类] = [];
			}
			this.stop(); 
			this._visible = false; 
			效果池.push(this); 
			//_root.服务器.发布服务器消息("回收入池" + 效果池.length);
			_root.当前效果总数--;
		}
	};

	创建的效果.unload = function() {
		
		//_root.服务器.发布服务器消息("即将卸载对象");
		this.removeMovieClip(true);// 强制执行必要的清理操作
	};
    
	return 创建的效果;
};

_root.效果 = function(效果种类, myX, myY, 方向, 必然触发)
{
	//_root.联机2015特效发送(效果种类,myX,myY,方向,-1);
	
	if (_root.是否视觉元素 && (_root.当前效果总数 <= _root.效果上限 || _root.成功率(_root.效果上限 / 5)) || 必然触发)
	{
		var 游戏世界 = _root.gameworld;
		if(!游戏世界.可用效果池) _root.效果系统.初始化效果池();
		var 效果池 = 游戏世界.可用效果池[效果种类];
		
        if(效果池.length > 0)
        {
            var 新效果 = 效果池.pop();
            新效果._x = myX;
            新效果._y = myY;
            新效果._visible = true;
			新效果.gotoAndPlay(1);
			//_root.服务器.发布服务器消息(_root.当前效果总数 + " 重用对象 " + 效果种类 + ":" + 效果池.length);
        }
        else
        {
			var 新效果 = _root.效果系统.创建效果(效果种类, myX, myY);
			//_root.服务器.发布服务器消息(_root.当前效果总数 + " 创建对象 " + 效果种类 + ":" + 效果池.length);
        }
		
		if(新效果)
		{
			新效果._x = myX;
			新效果._y = myY;
			新效果._xscale = 方向;
			_root.当前效果总数++;
		}


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



