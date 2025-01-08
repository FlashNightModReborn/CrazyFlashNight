_root.背包查空 = function()
{
	var 物品栏总数 = _root.物品栏总数;
	var 物品栏 = _root.物品栏;
	for(var i = 0; i < 物品栏总数; i++)
	{
		if (物品栏[i][0] == "空")
		{
			return true;
		}
	}
	return false;
}

_root.物品栏是否有 = function(此物品, 个数)
{
	if (此物品 == "" or 此物品 == undefined)
	{
		return true;
	}
	var 物品栏总数 = _root.物品栏总数;
	var 物品属性 = _root.根据物品名查找全部属性(此物品);
	var 总数量 = 0;
	if (物品属性[2] == "消耗品" or 物品属性[3] == "颈部装备")
	{
		总数量 = 0;
		for(var i = 0; i < 物品栏总数; i++)
		{
			var 当前物品 = _root.物品栏[i];
			if (当前物品[0] == 此物品)
			{
				总数量 += Number(当前物品[1]);
				if (总数量 >= Number(个数))
				{
					return true;
				}
			}
		}
	}
	else if (物品属性[2] == "武器" or 物品属性[2] == "防具")
	{
		总数量 = 0;
		for(var i = 0; i < 物品栏总数; i++)
		{
			if (_root.物品栏[i][0] == 此物品)
			{
				总数量 += 1;
			}
			if (总数量 >= Number(个数))
			{
				return true;
			}
		}
	}
	else if (此物品 == "空")
	{
		总数量 = 0;
		for(var i = 0; i < 物品栏总数; i++)
		{
			if (_root.物品栏[i][0] == 此物品)
			{
				总数量 += 1;
			}
			if (总数量 >= Number(个数))
			{
				return true;
			}
		}
	}
	return false;
}

_root.物品栏删除指定物品 = function(此物品, 个数)
{
	if (_root.物品栏是否有(此物品, 个数))
	{
		var 物品栏 = _root.物品栏;
		var 物品栏总数 = _root.物品栏总数;
		var _loc4_ = _root.根据物品名查找全部属性(此物品);
		if (_loc4_[2] == "消耗品")
		{
			var 剩余所需个数 = 个数;
			for(var i = 0; i < 物品栏总数; i++)
			{
				var 物品格 = 物品栏[i];
				if (物品格[0] == 此物品)
				{
					if (Number(物品格[1]) <= 个数)
					{
						剩余所需个数 -= Number(物品格[1]);
						if (物品格[2] == 1)
						{
							_root.卸载已装备的装备(物品格[0]);
						}
						物品栏[i] = ["空", 0, 0];
					}
					else
					{
						物品格[1] = Number(物品格[1]) - 剩余所需个数;
						剩余所需个数 = 0;
					}
					if (剩余所需个数 <= 0)
					{
						_root.排列物品图标();
						return true;
					}
				}
			}
		}
		else if (_loc4_[2] == "武器" or _loc4_[2] == "防具")
		{
			var 剩余所需个数 = 个数;
			i = 0;
			for(var i = 0; i < _root.物品栏总数; i++)
			{
				var 物品格 = 物品栏[i];
				if (物品格[0] == 此物品)
				{
					剩余所需个数 -= 1;
					if (物品格[2] == 1)
					{
						_root.卸载已装备的装备(物品格[0]);
					}
					物品栏[i] = ["空", 0, 0];
				}
				if (剩余所需个数 <= 0)
				{
					_root.排列物品图标();
					return true;
				}
			}
		}
	}
	return false;
}

_root.卸载已装备的装备 = function(名称)
{
	if (_root.头部装备 == 名称)
	{
		_root.头部装备 = "";
	}
	else if (_root.上装装备 == 名称)
	{
		_root.上装装备 = "";
	}
	else if (_root.手部装备 == 名称)
	{
		_root.手部装备 = "";
	}
	else if (_root.下装装备 == 名称)
	{
		_root.下装装备 = "";
	}
	else if (_root.脚部装备 == 名称)
	{
		_root.脚部装备 = "";
	}
	else if (_root.颈部装备 == 名称)
	{
		_root.颈部装备 = "";
	}
	else if (_root.长枪 == 名称)
	{
		_root.长枪 = "";
	}
	else if (_root.手枪 == 名称)
	{
		_root.手枪 = "";
	}
	else if (_root.手枪2 == 名称)
	{
		_root.手枪2 = "";
	}
	else if (_root.刀 == 名称)
	{
		_root.刀 = "";
	}
	else if (_root.手雷 == 名称)
	{
		_root.手雷 = "";
	}
	_root.刷新人物装扮(_root.控制目标);
	_root.物品栏界面.gotoAndPlay("物品栏刷新");
}

_root.物品栏添加 = function(物品名, 个数, 是否已装备)
{
	if (物品名 == "K点")
	{
		return undefined;
	}

	var 物品栏总数 = _root.物品栏总数;
	if (_root.根据物品名查找属性(物品名, 2) == "消耗品")
	{
		
		for (var i = 0; i < 物品栏总数; i++)
		{
			var 物品格 = _root.物品栏[i];
			if (物品格[0] == 物品名)
			{
				物品格[1] = Number(物品格[1]) + Number(个数);
				_root.排列物品图标();
				return true;
			}
		}
		for (var i = 0; i < 物品栏总数; i++)
		{
			var 物品格 = _root.物品栏[i];
			if (物品格[0] == "空")
			{
				物品格[0] = 物品名;
				物品格[1] = 个数;
				_root.排列物品图标();
				return true;
			}
		}
	}
	for (var i = 0; i < 物品栏总数; i++)
	{
		var 物品格 = _root.物品栏[i];
		if (物品格[0] == "空")
		{
			物品格[0] = 物品名;
			物品格[1] = Number(个数);
			物品格[2] = 是否已装备;
			_root.排列物品图标();
			return true;
		}
	}
	return false;
}

_root.物品栏是否能添加 = function(物品名, 个数, 是否已装备)
{
	var 物品栏总数 = _root.物品栏总数;
	if (_root.根据物品名查找属性(物品名, 2) == "消耗品")
	{
		for (var i = 0; i < 物品栏总数; i++)
		{
			if (_root.物品栏[i][0] == 物品名)
			{
				return true;
			}
		}
		i = 0;
		for (var i = 0; i < 物品栏总数; i++)
		{
			if (_root.物品栏[i][0] == "空")
			{
				return true;
			}
		}
	}
	i = 0;
	for (var i = 0; i < 物品栏总数; i++)
	{
		if (_root.物品栏[i][0] == "空")
		{
			return true;
		}
	}
	return false;
}

_root.物品栏有空位数 = function()
{
	var 物品栏总数 = _root.物品栏总数;
	var 空位数 = 0;
	for (var i = 0; i < 物品栏总数; i++)
	{
		if (_root.物品栏[i][0] == "空")
		{
			空位数 += 1;
		}
	}
	return 空位数;
}

_root.获得强化等级 = function(物品名)
{
	for (var i = 0; i < _root.物品栏.length; i++)
	{
		var 物品格 = _root.物品栏[i];
		if (物品格[0] == 物品名 and 物品格[2] == 1)
		{
			if (物品格[1] != undefined)
			{
				return 物品格[1];
			}
			return 1;
		}
	}
}

_root.排列物品图标 = function()
{
	if (_root.物品栏界面.界面 == "物品装备")
	{
		var 物品栏 = _root.物品栏;
		var 物品栏界面 = _root.物品栏界面;
		var 起始x = 物品栏界面.物品图标._x;
		var 起始y = 物品栏界面.物品图标._y;
		var 图标高度 = 28;
		var 图标宽度 = 28;
		var 列数 = 10;
		var 行数 = 5;
		var 换行计数 = 0;
		var i = 0;
		while (i < 列数 * 行数)
		{
			物品栏界面.attachMovie("物品图标","物品图标" + i,i);
			var 物品图标 = 物品栏界面["物品图标" + i];
			var 物品 = 物品栏[i];
			物品图标 = 物品栏界面["物品图标" + i];
			物品图标._x = 起始x;
			物品图标._y = 起始y;
			起始x += 图标宽度;
			换行计数++;
			if (换行计数 == 列数)
			{
				换行计数 = 0;
				起始x = 物品栏界面.物品图标._x;
				起始y += 图标高度;
			}
			
			if (!物品 || !物品[0])
			{
				物品栏[i] = ["空", 0, 0];
				物品图标.gotoAndStop(物品[0]);
			}
			else if (物品[0] == "空")
			{
				物品图标.gotoAndStop(物品[0]);
			}
			else
			{
				物品图标.图标 = "图标-" + _root.getItemData(物品[0]).icon;
				物品图标.gotoAndStop("默认图标");
			}
			物品图标.数量 = 物品[1];
			物品图标.对应数组号 = i;
			物品图标.图标是否可对换位置 = 1;
			i++;
		}
	}
}

_root.删除物品图标 = function()
{
	for(var i=0; i <= _root.物品栏总数; i++)
	{
		_root.物品栏界面["物品图标" + i].removeMovieClip();
	}
}

_root.排列仓库物品图标 = function()
{
	删除仓库物品图标();
	var 起始x = _root.仓库界面.物品图标._x;
	var 起始y = _root.仓库界面.物品图标._y;
	var 图标高度 = 28;
	var 图标宽度 = 28;
	var 列数 = 8;
	var 行数 = 5;
	var 单页物品数 = 行数*列数;
	var 换行计数 = 0;
	var i = 仓库页数 * 单页物品数 - 单页物品数;
	while (i < 单页物品数 * 仓库页数)
	{
		_root.仓库界面.attachMovie("物品图标","物品图标" + i,i);
		var 物品图标 = _root.仓库界面["物品图标" + i];
		var 物品 = 仓库栏[i];
		物品图标._x = 起始x;
		物品图标._y = 起始y;
		起始x += 图标宽度;
		换行计数++;
		if (换行计数 == 列数)
		{
			换行计数 = 0;
			起始x = 仓库界面.物品图标._x;
			起始y += 图标高度;
		}
		if (物品 != undefined)
		{
			if (物品[0] == "空")
			{
				物品图标.gotoAndStop(物品[0]);
			}
			else
			{
				物品图标.图标 = "图标-" + _root.getItemData(物品[0]).icon;
				物品图标.gotoAndStop("默认图标");
			}
		}
		else
		{
			仓库栏[i] = ["空", 0];
		}
		物品图标.数量 = 物品[1];
		物品图标.对应数组号 = i;
		物品图标.图标是否可对换位置 = 1;
		i++;
	}
}

_root.删除仓库物品图标 = function()
{
	var 仓库界面 = _root.仓库界面;
	for(var i = 0; i < 仓库栏总数; i++)
	{
		仓库界面["物品图标" + i].removeMovieClip();
	}
}

_root.读取仓库数据 = function()
{
   _root.仓库界面._visible = 1;
   _root.仓库界面.gotoAndStop("完毕");
   _root.排列仓库物品图标();
}
