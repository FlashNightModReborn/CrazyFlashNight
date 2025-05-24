import org.flashNight.aven.Coordinator.*;

// 确保_root上有常用工具函数对象
if (_root.常用工具函数 == undefined)
{
	_root.常用工具函数 = new Object();
}
// 在常用工具函数对象内创建一个对象用于存储解析结果       
_root.常用工具函数.检测结果存储 = {};// 实现检测函数
_root.常用工具函数.字符串子串匹配 = function(查询字符串, 查询片段)
{
	// 直接尝试获取二级结构的检测结果
	var 检测结果 = _root.常用工具函数.检测结果存储[查询字符串][查询片段];

	// 如果检测结果为undefined，说明未进行过这一查询
	if (检测结果 === undefined)
	{
		// 检查并创建一级结构
		if (_root.常用工具函数.检测结果存储[查询字符串] === undefined)
		{
			_root.常用工具函数.检测结果存储[查询字符串] = {};
		}
		// 执行检测逻辑  
		检测结果 = 查询字符串.indexOf(查询片段) != -1;

		// 存储检测结果到二级结构
		_root.常用工具函数.检测结果存储[查询字符串][查询片段] = 检测结果;
	}

	return 检测结果;
};

_root.常用工具函数.洗牌 = function(数组) {
    var i = 数组.length, j, temp;
    while (--i > 0) {
        j = _root.随机整数(0, i);
        temp = 数组[i];
        数组[i] = 数组[j];
        数组[j] = temp;
    }
};

_root.对象浅拷贝 = function(Obj){
	var newObj = new Object();
	for (var key in Obj)
	{
		newObj[key] = Obj[key];
	}
	return newObj;
}

_root.深拷贝数组 = function(原数组)
{
	var 新数组 = [];
	for (var i = 0; i < 原数组.length; i++)
	{
		if (typeof 原数组[i] == "object")
		{
			新数组[i] = _root.深拷贝数组(原数组[i]);// 递归拷贝对象或数组
		}
		else
		{
			新数组[i] = 原数组[i];
		}
	}
	return 新数组;
};

_root.简单数据类型深拷贝 = function(原数组:Array):Array 
{
	var 新数组:Array = [], len:Number = 原数组.length, i:Number = 0;
	var 余数:Number = len % 8, 迭代器:Number = (len - 余数) / 8;	// 计算需要执行的完整迭代次数和起始位置

	do
	{
		switch (余数)
		{
			case 0 :新数组.push(原数组[i++]);
			case 7 :新数组.push(原数组[i++]);
			case 6 :新数组.push(原数组[i++]);
			case 5 :新数组.push(原数组[i++]);
			case 4 :新数组.push(原数组[i++]);
			case 3 :新数组.push(原数组[i++]);
			case 2 :新数组.push(原数组[i++]);
			case 1 :新数组.push(原数组[i++]);
		}
		余数 = 0;// 达夫设备减少循环消耗
	} while (--迭代器 > 0);

	return 新数组;//默认原数组只有简单数据类型，没有嵌套数组或者对象元素
};
_root.随机选择数组元素 = function(数组)
{
	if (数组.length == 0)
	{
		return null;// 数组为空时返回 null
	}

	return 数组[_root.获取随机索引(数组)];
};
_root.获取随机索引 = function(数组)
{
	if (数组.length == 0)
	{
		return -1;// 数组为空时返回 -1
	}
	return _root.随机整数(0, 数组.length - 1);
};

_root.根据权重获取随机对象 = function(对象数组)
{
	// 计算总权重
	var 总权重 = 0;
	for (var i = 0; i < 对象数组.length; i++)
	{
		总权重 += 对象数组[i].权重;
	}

	// 生成随机值
	var 随机值 = _root.basic_random() * 总权重;

	// 根据随机值选择对象
	var 当前权重 = 0;
	for (var j = 0; j < 对象数组.length; j++)
	{
		当前权重 += 对象数组[j].权重;
		if (随机值 < 当前权重)
		{
			return 对象数组[j];
		}
	}

	// 如果没有返回，返回最后一个对象（保底）
	return 对象数组[对象数组.length - 1];
};

_root.根据权重反比获取随机对象 = function(对象数组)
{
	// 计算总权重
	var 总权重 = 0;
    var 权重反比表 = new Array(对象数组.length);
	for (var i = 0; i < 对象数组.length; i++)
	{
        var 权重反比 = 1 / 对象数组[i].权重;
		总权重 += 权重反比;
        权重反比表[i] = 权重反比;
	}

	// 生成随机值
	var 随机值 = _root.basic_random() * 总权重;

	// 根据随机值选择对象
	var 当前权重 = 0;
	for (var j = 0; j < 对象数组.length; j++)
	{
		当前权重 += 权重反比表[j];
		if (随机值 < 当前权重)
		{
			return 对象数组[j];
		}
	}

	// 如果没有返回，返回最后一个对象（保底）
	return 对象数组[对象数组.length - 1];
};



// 定义全局函数列表


// 定义字符类型判断的辅助函数
_root.是日文 = function(字符:Number):Boolean 
{
	return 字符 >= 0x3040 and 字符 <= 0x30FF;
};

_root.是汉字 = function(字符:Number):Boolean 
{
	return 字符 >= 0x4E00 and 字符 <= 0x9FA5;
};

_root.是全角ASCII或标点 = function(字符:Number):Boolean 
{
	return (字符 >= 0xFF00 and 字符 <= 0xFFEF) or (字符 >= 0x2000 and 字符 <= 0x206F);
};
_root.字符类型判断函数列表 = new Array();
_root.字符类型判断函数列表.push(_root.是日文);
_root.字符类型判断函数列表.push(_root.是汉字);
_root.字符类型判断函数列表.push(_root.是全角ASCII或标点);
// 定义判断字符类型的函数
_root.判断字符类型 = function(字符:String):String 
{
	var 当前字符:Number = 字符.charCodeAt(0);
	for (var i:Number = 0; i < _root.字符类型判断函数列表.length; i++)
	{
		if (_root.字符类型判断函数列表[i](当前字符))
		{
			return "宽字符";
		}
	}
	return "窄字符";
};

// 定义截断字符串的函数
_root.按宽度截断字符串 = function(字符串:String, 最大宽度:Number):String 
{
	var 当前宽度:Number = 0;
	var 截断索引:Number = 字符串.length;

	for (var i:Number = 0; i < 字符串.length; i++)
	{
		var 当前字符:String = 字符串.charAt(i);
		var 字符宽度:Number = (_root.判断字符类型(当前字符) == "宽字符") ? 2 : 1;

		当前宽度 += 字符宽度;
		if (当前宽度 > 最大宽度)
		{
			截断索引 = i;
			break;
		}
	}

	return 字符串.substring(0, 截断索引);
};


_root.定位自机 = function(对象):MovieClip 
{
	var 当前对象:MovieClip = 对象;
	if(当前对象.man._name == 'man')
	{
		return 当前对象;
	}
	
	while (当前对象 and 当前对象._name != 'man')
	{
		当前对象 = 当前对象._parent;// 用man定位自机
	}

	if (当前对象 and 当前对象._name == 'man')
	{
		return 当前对象._parent;
	}
	else
	{
		return null;// 异常情况下用null
	}
};

_root.常用工具函数.escapeString = function(str:String):String 
{
    // 简单的字符串替换来处理引号和反斜杠
    var escapedStr:String = '';
    for (var i = 0; i < str.length; i++) 
	{
        switch (str.charAt(i)) {
            case '"':
                escapedStr += '\\"';
                break;
            case '\\':
                escapedStr += '\\\\';
                break;
            default:
                escapedStr += str.charAt(i);
                break;
        }
    }
    return escapedStr;
};

_root.常用工具函数.createIndent = function(level:Number):String 
{
    var indent:String = '';
    for (var i = 0; i < level; i++) 
	{
        indent += '    ';  // 4个空格作为缩进单位
    }
    return indent;
};

_root.常用工具函数.对象转JSON = function(obj:Object, pretty:Boolean, depth:Number):String {
    if (depth == undefined) depth = 0;
    var tools = _root.常用工具函数;
    var createIndent = tools.createIndent;
    var toJSON = tools.对象转JSON;
    var escapeString = tools.escapeString;
    var indent = pretty ? createIndent(depth) : '';
    var newIndent = pretty ? createIndent(depth + 1) : '';
    var endIndent = pretty ? createIndent(depth) : '';  // 使用相同的缩进级别作为开始
    var json = '';
    var isArray = obj instanceof Array;
    var first = true;

    json += (pretty ? '\n' + indent : '') + (isArray ? '[' : '{');
    if (pretty) json += '\n';

    for (var key in obj) {
        if (!first) {
            json += ',';
            if (pretty) json += '\n';
        }
        first = false;

        var value = obj[key];
        if (typeof(value) == 'object' and value !== null) {
            value = toJSON(value, pretty, depth + 1);
        } else if (typeof(value) == 'string') {
            value = '"' + escapeString(value) + '"';
        } else if (typeof(value) == 'number') {
            value = isFinite(value) ? String(value) : 'null';
        } else if (typeof(value) == 'boolean') {
            value = value ? 'true' : 'false';
        } else {
            continue; // Skip undefined and functions
        }

        json += newIndent + (isArray ? '' : '"' + key + '": ') + value;
    }

    if (pretty and !first) json += '\n';
    json += endIndent + (isArray ? ']' : '}'); // 使用相同的缩进级别

    return json;
};

_root.常用工具函数.线性插值 = function(value, srcLow, srcHigh, dstLow, dstHigh) 
{
    if (srcLow == srcHigh)  return dstLow; // 排除0
    return (value - srcLow) / (srcHigh - srcLow) * (dstHigh - dstLow) + dstLow;
};

_root.格式化对象为字符串 = function(对象, 对象名, 递归深度)
{
    if (对象名 == undefined) 对象名 = 对象._name || "未命名对象";
    if (递归深度 == undefined) 递归深度 = 0;
	if (typeof (对象) != "object" && 对象._x === undefinded)
	{
		var 输出信息 = 对象名 + ": " + 对象;
		return 输出信息;// 如果是基本数据类型，则直接输出
	}

    var 输出字符串 = "";
    if (递归深度 == 0) 输出字符串 += 对象名 + "属性: ";

    for (var 属性 in 对象)
    {
        if (typeof(对象[属性]) == "object")
        {
            输出字符串 += _root.格式化对象为字符串(对象[属性], 属性, 递归深度 + 1);
        }
        else
        {
            输出字符串 += "(" + 属性 + ", " + 对象[属性] + ") ";
        }
    }
    return "(" + 输出字符串 + ")";
};

_root.常用工具函数.彻底移除对象 = function(对象):Void 
{
    _root.服务器.发布服务器消息("开始处理对象：" + 对象); 

    for (var each in 对象) 
	{
        var item = 对象[each];
        _root.服务器.发布服务器消息("处理属性：" + each + "，类型：" + typeof(item)); 
        if (typeof(item) == "movieclip") 
		{
            _root.常用工具函数.彻底移除对象(item); // Recursive call
            item.removeMovieClip();
            _root.服务器.发布服务器消息("移除MovieClip：" + each); 
        } 
		else if (typeof(item) == "object" || typeof(item) == "array") 
		{
            _root.常用工具函数.彻底移除对象(item); // Recursive call
            delete 对象[each];
            _root.服务器.发布服务器消息("删除对象/数组：" + each); 
        } 
		else if (typeof(item) == "bitmapdata") 
		{
            item.dispose(); // Dispose BitmapData
            delete 对象[each];
            _root.服务器.发布服务器消息("释放并删除BitmapData：" + each);
		}
		else 
		{
            delete 对象[each]; // Delete other types
            _root.服务器.发布服务器消息("删除属性：" + each); 
        }
    }
	
	if (typeof(对象) == "movieclip" && 对象.removeMovieClip) {
        对象.removeMovieClip(); // Remove the MovieClip itself
        _root.服务器.发布服务器消息("移除MovieClip自身：" + 对象); 
    }

    _root.服务器.发布服务器消息("完成处理对象：" + 对象); 
};

_root.常用工具函数.释放对象绘图内存 = function(对象):Void 
{
    //_root.服务器.发布服务器消息("开始处理对象：" + 对象); 

    for (var each in 对象) 
    {
        var item = 对象[each];
        //_root.服务器.发布服务器消息("处理属性：" + each + "，类型：" + typeof(item)); 
        
        if (typeof(item) == "movieclip") 
        {
            _root.常用工具函数.清除影片剪辑与位图对象(item); // Recursive call
            item.removeMovieClip(true);
            //_root.服务器.发布服务器消息("移除MovieClip：" + each); 
        } 
        else if (typeof(item) == "bitmapdata") 
        {
            item.dispose(); // Dispose BitmapData
            delete 对象[each];
            //_root.服务器.发布服务器消息("释放并删除BitmapData：" + each);
        }
    }

    // Remove the MovieClip itself if it's a MovieClip
    if (typeof(对象) == "movieclip" && 对象.removeMovieClip) 
    {
        对象.removeMovieClip(true); 
        //_root.服务器.发布服务器消息("移除MovieClip自身：" + 对象); 
    }

    //_root.服务器.发布服务器消息("完成处理对象：" + 对象); 
};

_root.常用工具函数.补零到宽度 = function(数字, 宽度):String 
{
    var str = String(Math.floor(数字));
    var zeroes = "";
    for (var i = str.length; i < 宽度; i++) zeroes += "0";
    return zeroes + str;
};

// 在全局工具对象中，用 EventCoordinator 包装设置卸载回调
_root.常用工具函数.设置卸载回调 = function(对象:Object, 动作函数:Function):String {
    // addUnloadCallback 是 EventCoordinator 动态生成的快捷方法，
    // 它会在内部为 target.onUnload 注册一个监听并保证可多次触发，
    // 同时自动管理原生 onUnload 的调用时机、清理逻辑等。
    return EventCoordinator.addUnloadCallback(对象, 动作函数);
};
