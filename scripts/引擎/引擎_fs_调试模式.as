_root.调试模式 = false;
//_root.调试模式 = true;

_root.发布消息 = function() 
{
	var 消息 = "";
    for (var i = 0; i < arguments.length; i++) {
        if (i > 0) 消息 += " "; // 参数间用空格分隔
        消息 += arguments[i];
    }
	
	if (_root.调试模式) 
	{
        _root.发布调试消息(消息);
    } 
	else 
	{
        if(!消息窗.正在播放动画)
		{
			消息窗.正在播放动画 = true;
			消息窗.动画结束帧 = 30;
			消息窗.gotoAndPlay(1);
		}
		else
		{
			消息窗.gotoAndPlay(Math.min(消息窗._currentframe, 消息窗.动画结束帧));
		}

        消息窗.mytext += 消息 + "<BR>";
		var 显示框 = 消息窗.文本框.文字显示框;
        if (显示框.textHeight > 显示框._height - 10) 
		{
            var 消息数组 = 消息窗.mytext.split("<BR>");
            var 初始索引 = 消息数组.length >= 8 ? 消息数组.length - 4 : (消息数组.length >= 4 ? 消息数组.length - 5 : Math.floor(消息数组.length / 2));
            var 新消息 = 消息数组.slice(初始索引).join("<BR>");
            消息窗.mytext = 新消息;
			_root.服务器.发布服务器消息(消息数组.length);
        }
    }
};


_root.发布调试消息 = function(消息)
{
	if (_root.调试模式)
	{
		if (消息窗)
		{
			_root.服务器.发布服务器消息(消息)
			消息窗.文字显示框._height = Stage.height * 0.9;
			消息窗.文字显示框._width = Stage.width * 0.9;
			消息窗.gotoAndStop(消息窗.动画结束帧);
			消息窗.mytext += 消息 + "<BR>";
			if (消息窗.文字显示框.textHeight > 消息窗.文字显示框._height - 10)
			{
				消息窗.mytext = 消息窗.mytext.split("<BR>").slice(3).join("<BR>");
			}
		}
		else
		{
			trace(消息);
		}
	}
};


_root.发布调试信息 = _root.发布调试消息;

_root.获取父级名称 = function(对象)
{
	分隔符 = " -> ";
	父级名称 = [];
	输出字符串 = "对象 " + 对象._name;

	// 逐级获取父级名称
	目前对象 = 对象;
	while (目前对象._parent != undefned)
	{
		父级名称.push(目前对象._parent);
		目前对象 = 目前对象._parent;
	}
	循环计数 = 0;

	// 输出父级名称
	while (循环计数 < 父级名称.length and 父级名称[循环计数] != _root)
	{
		输出字符串 += (分隔符 + (循环计数 + 1) + "级父级: " + 父级名称[循环计数]._name);
		循环计数++;
	}

	_root.发布调试消息(输出字符串);
};

// 将函数定义放在 _root 的作用域中
_root.traceObject = function(obj:Object, indent:String):Void 
{
	for (var key in obj)
	{
		if (typeof (obj[key]) == "object")
		{
			_root.发布调试消息(indent + key + ":");
			traceObject(obj[key],indent + "  ");
		}
		else
		{
			_root.发布调试消息(indent + key + ": " + obj[key]);
		}
	}
};
_root.输出对象属性 = function(对象, 对象名, 递归深度)
{
	if (对象名 == undefined)
	{
		对象名 = 对象._name || "未命名对象";
	}
	if (递归深度 == undefined)
	{
		递归深度 = 0;
	}
	// 检查是否是基本数据类型    
	if (typeof (对象) != "object" and 对象._x === undefinded)
	{
		// 如果是基本数据类型，则直接输出
		var 输出信息 = 对象名 + ": " + 对象;
		if (递归深度 == 0)
		{
			_root.发布调试消息(输出信息);
		}
		return 输出信息;
	}

	var 输出字符串 = "";
	if (递归深度 == 0)
	{
		输出字符串 += 对象名 + "属性: ";
	}

	for (var 属性 in 对象)
	{
		if (typeof (对象[属性]) == "object")
		{
			// 如果属性是对象，则递归调用
			输出字符串 += _root.输出对象属性(对象[属性], 属性, 递归深度 + 1);
		}
		else
		{
			// 否则，输出属性值
			输出字符串 += "(" + 属性 + ", " + 对象[属性] + ") ";
		}
	}

	if (递归深度 == 0)
	{
		// 如果是最外层递归，发布调试消息
		_root.发布调试消息(输出字符串);
	}

	return 输出字符串;
};

// 将函数挂载在_root上，以实现跨SWF调用  
_root.输出所有父级的属性 = function(对象, 属性)
{
	var 当前对象 = 对象;
	var 父级等级 = 0;
	var 输出字符串 = "";

	while (当前对象)
	{
		// 获取当前对象的指定属性  
		var value = 当前对象[_root.获得属性(当前对象, 属性)];
		if (当前对象._name == undefined)
		{
			当前对象._name = "";
		}
		// 输出属性值和层级信息                    
		输出字符串 += 父级等级 + "级父级 " + 当前对象._name + ": " + value + "\n";

		// 向上遍历父级节点  
		当前对象 = 当前对象._parent;
		父级等级++;
	}

	// 返回输出结果  
	return 输出字符串;
};

// 获取对象属性的函数  
_root.获得属性 = function(对象, 属性)
{
	if (对象.hasOwnProperty(属性))
	{
		return 属性;
	}
	else
	{
		return null;
	}
};


_root.获得父节点 = function(对象, 层级)
{
	var 当前对象 = 对象;
	var 当前层级 = 0;

	while (当前对象 and 当前层级 < 层级)
	{
		当前对象 = 当前对象._parent;
		当前层级++;
	}

	return 当前对象;
};

_root.获得父节点属性 = function(对象, 层级, 属性)
{
	return _root.获得父节点(对象, 层级)[_root.获得属性(对象, 属性)];
};

_root.traceObject = function(obj:Object, indent:String):Void 
{
	for (var key in obj)
	{
		if (typeof (obj[key]) == "object")
		{
			_root.发布调试消息(indent + key + ":");
			traceObject(obj[key],indent + "  ");
		}
		else
		{
			_root.发布调试消息(indent + key + ": " + obj[key]);
		}
	}
};

