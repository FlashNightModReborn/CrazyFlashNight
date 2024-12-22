import flash.geom.Point;
import flash.geom.Rectangle;
import org.flashNight.naki.Sort.*;
import org.flashNight.neur.Event.*;
import org.flashNight.sara.util.*;

//输入点与影片剪辑的引用，将点坐标从该影片剪辑转换到gameworld
_root.pointToGameworld = function(point, loc)
{
	loc.localToGlobal(point);
	_root.gameworld.globalToLocal(point);
	return new Vector(point.x, point.y);
};

_root.点集至游戏世界 = function(点集, loc)
{
    for (var i = 0; i < 点集.length; i++) {
        loc.localToGlobal(点集[i]);
        _root.gameworld.globalToLocal(点集[i]);
    }
    return 点集;
};

_root.pointToMovieclip = function(point, loc)
{
	_root.gameworld.globalToLocal(point);
	loc.localToGlobal(point);
	return point;
};

_root.点集至影片剪辑 = function(点集, loc)
{
    for (var i = 0; i < 点集.length; i++) {
        _root.gameworld.globalToLocal(点集[i]);
        loc.localToGlobal(点集[i]);
    }
    return 点集;
};

_root.影片剪辑至游戏世界点集 = function(影片剪辑:MovieClip):Array 
{
	var 点集:Array = new Array(4);//创建点集数组并预扩容
	var rect:Object = 影片剪辑.getRect(影片剪辑);//获得影片剪辑的边界框

	点集[1] = _root.pointToGameworld({x:rect.xMax, y:rect.yMax}, 影片剪辑);
	点集[3] = _root.pointToGameworld({x:rect.xMin, y:rect.yMin}, 影片剪辑);
	var 中点x = (点集[1].x + 点集[3].x) / 2, 中点y = (点集[1].y + 点集[3].y) / 2;//计算中点坐标以获得向量
	var 向量x = 点集[1].x - 中点x, 向量y = 点集[1].y - 中点y;//
	var 夹角:Number = Math.atan2(向量y, 向量x);// 计算旋转角度
	var 向量模:Number = Math.sqrt(向量x * 向量x + 向量y * 向量y);// 取向量模长
	var 余弦值 = 向量模 * Math.cos(夹角), 正弦值 = 向量模 * Math.sin(夹角);

	点集[0] = new Vector(中点x - 余弦值, 中点y + 正弦值);// 计算0号和2号顶点的向量（旋转后）
	点集[2] = new Vector(中点x + 余弦值, 中点y - 正弦值);
	return 点集;
};

//将矩形坐标转换到gameworld（好像用不到了）
/*
_root.rectToGameworld = function(rect, loc)
{
	p1 = {x:rect.left, y:rect.top};
	p2 = {x:rect.right, y:rect.bottom};
	_root.pointToGameworld(p1,loc);
	_root.pointToGameworld(p1,loc);
	x0 = Math.min(p1.x, p2.x);
	y0 = Math.min(p1.y, p2.y);
	w = Math.max(p1.x, p2.x) - x0;
	h = Math.max(p1.y, p2.y) - y0;
	return new Rectangle(x0, y0, w, h);
};
*/

//输入影片剪辑的引用，将其外框坐标转换到gameworld
_root.areaToRectGameworld = function(area:MovieClip) {
    var rect = area.getRect(_root.gameworld);
    return {
		left: rect.xMin, 
		right: rect.xMax, 
		top: rect.yMin, 
		bottom: rect.yMax
	};
};

_root.areaToRectGameworldWithZ = function(area:MovieClip, z_offset:Number)
{
	var rect = area.getRect(_root.gameworld);
    return {
		left: rect.xMin, 
		right: rect.xMax, 
		top: rect.yMin + z_offset, 
		bottom: rect.yMax + z_offset
	};
};


_root.bulletToRectGameworld = function(bullet:MovieClip)
{
	var rect = area.getRect(_root.gameworld);
    return {
		left: rect.xMin, 
		right: rect.xMax, 
		top: rect.yMin, 
		bottom: rect.yMax
	};
};

//输入子弹区域与命中目标的引用，以及它们的Z轴坐标
_root.rectHitTest = function(bullet_rect:Object, target_area:MovieClip, z_offset:Number) {
    if (!bullet_rect or !target_area) {
        return null;
    }

    var bullet_left = bullet_rect.left;
    var bullet_right = bullet_rect.right;
    var bullet_top = bullet_rect.top + z_offset;// 考虑Z轴偏移
    var bullet_bottom = bullet_rect.bottom + z_offset;
    
    var target_rect = target_area.getRect(_root.gameworld);// 获取 target_area 的边界并转换到局部坐标
    var target_left = target_rect.xMin;
    var target_right = target_rect.xMax;
    var target_top = target_rect.yMin;
    var target_bottom = target_rect.yMax;

	if (bullet_left >= target_right or target_left >= bullet_right) {
		return null;//早期返回
	}
	if (bullet_top >= target_bottom or target_top >= bullet_bottom) {
		return null;// 提前返回检测，如果没有交集
	}

    return {
		left: Math.max(bullet_left, target_left), 
		right: Math.min(bullet_right, target_right), 
		top: Math.max(bullet_top, target_top), 
		bottom: Math.min(bullet_bottom, target_bottom)
	};// 返回交集区域
};

_root.calculateRectArea = function(rect:Object):Number {  
    if (!rect) return 0; // 表示无效的输入   
    return (rect.right - rect.left) * (rect.bottom - rect.top); // 返回面积  
};

_root.矩形area击中检测 = function(bullet_area:MovieClip, target_area:MovieClip, bullet_z:Number, target_z:Number){
	return _root.rectHitTest(bullet_area, target_area, bullet_z, target_z);//返回击中点信息对象
};

_root.area击中检测 = function(bullet_area:MovieClip, target_area:MovieClip, bullet_z:Number, target_z:Number) {
	//return area1.hitTest(area2);//与子弹区域area击中检测保持同样的碰撞逻辑
	return _root.rectHitTest(bullet_area, target_area, bullet_z, target_z);//尝试也使用新版碰撞检测
};

_root.aabb碰撞检测 = function(bullet_rect:Object, target_rect:Object, z_offset:Number) {  
    if (!bullet_rect or !target_rect)  return false; 
 
    // var target_rect = target_area.getRect(_root.gameworld);
	var bullet_top = bullet_rect.top + z_offset;
	var bullet_bottom = bullet_rect.bottom + z_offset;
  
    if (bullet_rect.left >= target_rect.xMax or target_rect.xMin >= bullet_rect.right) {
        return false; // 提前终止检测  
    }  
    if (bullet_top >= target_rect.yMax or target_rect.yMin >= bullet_bottom) {
        return false;  
    }  
  
    return true; // 存在碰撞  
};

_root.点集碰撞检测 = function(子弹点集:Array, 目标:MovieClip, z_offset:Number):Array {
    if (!子弹点集 or !目标) return null;

	var 子弹点集复制:Array = [
		{x: 子弹点集[0].x, y: 子弹点集[0].y + z_offset},
		{x: 子弹点集[1].x, y: 子弹点集[1].y + z_offset},
		{x: 子弹点集[2].x, y: 子弹点集[2].y + z_offset},
		{x: 子弹点集[3].x, y: 子弹点集[3].y + z_offset}
	];  

    return _root.多边形交集(子弹点集复制, _root.影片剪辑至游戏世界点集(目标)); // 返回交集
};

_root.点集面积系数 = function(点集:Array):Number {
    var len:Number = 点集.length;
    if (len < 3) {
        return 0; // 不是多边形
    }
    
    var 面积:Number = 0;
    for (var i:Number = 0, ii:Number = len - 1; i < len; ii = i++) {
        面积 += 点集[ii].x * 点集[i].y - 点集[i].x * 点集[ii].y;//抽屉算法
    }

    return Math.abs(面积);//这个函数用于计算面积比值，因此不需要/2
};
_root.创建向量 = Delegate.create(_root, function(x:Number, y:Number):Object {
    return new 向量(x, y);
});
// 创建一个向量对象的函数，包含基本的向量操作：减法、点积和求垂直向量（法线）

_root.投影多边形 = function(轴:Object, 多边形:Array):Object 
{
	var min:Number = 轴.点积(多边形[0]), max:Number = min;
	var len:Number = 多边形.length;
	for (var i:Number = 1; i < len; i++)
	{
		var p:Number = 轴.点积(多边形[i]);
		if (p < min)
		{
			min = p;
		}
		else if (p > max)
		{
			max = p;
		}
	}
	return {min:min, max:max};
};// 计算一个多边形在给定轴上的投影，返回投影的最小值和最大值

_root.投影检测 = function(a:Object, b:Object):Boolean 
{
	return a.min <= b.max and a.max >= b.min;
};// 检查两个投影是否重叠，用于确定是否有碰撞

// 计算两条线段的交点
_root.计算交点 = function(a:Object, b:Object, c:Object, d:Object):Object 
{
	var ABx:Number = b.x - a.x, ABy:Number = b.y - a.y;
	var CDx:Number = d.x - c.x, CDy:Number = d.y - c.y;
	var ACx:Number = c.x - a.x, ACy:Number = c.y - a.y;
	var det:Number = ABx * CDy - ABy * CDx;// 直接计算所需值，避免创建额外向量
	if (det == 0)
	{
		return null;// 线段平行或重合
	}
	var t:Number = (ACx * CDy - ACy * CDx) / det;// 计算交点参数
	var u:Number = (ACx * ABy - ACy * ABx) / det;

	if (t >= 0 and t <= 1 and u >= 0 and u <= 1)
	{
		return {x:a.x + t * ABx, y:a.y + t * ABy};// 交点在线段上
	}

	return null;//未相交
};

_root.点是否存在 = function(点:Object, 点集:Array):Boolean 
{
	var 容差:Number = 0.00001;// 设置一个小的容忍值
	var len:Number = 点集.length;
	for (var k:Number = 0; k < len; k++)
	{
		if (Math.abs(点.x - 点集[k].x) <= 容差 and Math.abs(点.y - 点集[k].y) <= 容差)
		{
			return true;
		}
	}
	return false;
};
_root.点恰在边上 = function(点:Object, 边起点:Object, 边终点:Object):Boolean 
{
	var 边向量:Object = _root.创建向量(边终点.x - 边起点.x, 边终点.y - 边起点.y);// 计算边的向量
	var 点向量:Object = _root.创建向量(点.x - 边起点.x, 点.y - 边起点.y);
	return 点向量.叉积(边向量) == 0 and _root.点在边的投影范围内(点, 边起点, 边终点);
};

_root.点在边的投影范围内 = function(点:Object, 边起点:Object, 边终点:Object):Boolean 
{
	var 最小x:Number = Math.min(边起点.x, 边终点.x);
	var 最大x:Number = Math.max(边起点.x, 边终点.x);
	var 最小y:Number = Math.min(边起点.y, 边终点.y);
	var 最大y:Number = Math.max(边起点.y, 边终点.y);
	return 点.x >= 最小x and 点.x <= 最大x and 点.y >= 最小y and 点.y <= 最大y;
};
_root.计算多边形边界框 = function(多边形:Array):Object 
{
	var minX:Number = 多边形[0].x;
	var maxX:Number = 多边形[0].x;
	var minY:Number = 多边形[0].y;
	var maxY:Number = 多边形[0].y;

	for (var i:Number = 1; i < 多边形.length; i++)
	{
		minX = Math.min(minX, 多边形[i].x);
		maxX = Math.max(maxX, 多边形[i].x);
		minY = Math.min(minY, 多边形[i].y);
		maxY = Math.max(maxY, 多边形[i].y);
	}

	return {minX:minX, maxX:maxX, minY:minY, maxY:maxY};
};
_root.计算线段边界框 = function(点1:Object, 点2:Object):Object 
{
	return {minX:Math.min(点1.x, 点2.x), maxX:Math.max(点1.x, 点2.x), minY:Math.min(点1.y, 点2.y), maxY:Math.max(点1.y, 点2.y)};
};

_root.边界框相交 = function(边界框a:Object, 边界框b:Object):Boolean 
{
	return !(边界框a.maxX < 边界框b.minX or 边界框a.minX > 边界框b.maxX or 边界框a.maxY < 边界框b.minY or 边界框a.minY > 边界框b.maxY);
};
_root.点在边界框内 = function(点:Object, 边界框:Object):Boolean 
{
	return 点.x >= 边界框.minX and 点.x <= 边界框.maxX and 点.y >= 边界框.minY and 点.y <= 边界框.maxY;
};
// 检查点是否在多边形内（基于射线法）
_root.射线法点在多边形内 = function(点:Object, 多边形:Array):Boolean 
{
	var 边界框:Object = _root.计算多边形边界框(多边形);// 计算并检查边界框
	if (!_root.点在边界框内(点, 边界框))
	{
		return false;//aabb预检测
	}

	var 交点数:Number = 0, len:Number = 多边形.length;
	var x:Number = 点.x, y:Number = 点.y;
	for (var i:Number = 0, j:Number = len - 1; i < len; j = i++)
	{
		if (_root.点恰在边上(点, {x:xi, y:yi}, {x:xj, y:yj}))
		{
			return true;// 检查点是否恰好位于多边形的边上，如果是提前返回 
		}

		var xi:Number = 多边形[i].x, yi:Number = 多边形[i].y;
		var xj:Number = 多边形[j].x, yj:Number = 多边形[j].y;

		if ((yi > y) != (yj > y))
		{
			var 斜率:Number = (xj - xi) / (yj - yi);
			var x交点:Number = xi + (y - yi) * 斜率;

			if (x <= x交点)
			{
				交点数++;// 检查交点是否在射线的右侧
			}
		}
	}
	return (交点数 % 2 == 1);// 奇数次为内部，偶数次为外
};
_root.计算多边形边向量 = function(多边形:Array):Array 
{
	var 边向量集:Array = [], len:Number = 多边形.length;
	for (var i:Number = 0, j:Number = len - 1; i < len; j = i++)
	{
		边向量集.push(_root.创建向量(多边形[i].x - 多边形[j].x, 多边形[i].y - 多边形[j].y));
	}
	return 边向量集;//用于缓存边避免重复计算
};

//基于叉积法对凸多边形特殊优化，放弃点在边上的特殊处理以优化性能，由于叉积法效率足够且点本身相当靠近多边形，放弃aabb检测
_root.点在多边形内 = function(点:Object, 多边形:Array):Boolean 
{
	var len:Number = 多边形.length;

	/*// 使用时默认传入为四边形
	if (len < 3)
	{
	return false;
	
	}*/
	// 计算第一个边向量和点向量的叉积  
	var 边向量:Object = _root.创建向量(多边形[0].x - 多边形[len - 1].x, 多边形[0].y - 多边形[len - 1].y);
	var 符号标志:Number = 边向量.叉积({x:点.x - 多边形[len - 1].x, y:点.y - 多边形[len - 1].y}) > 0 ? 1 : -1;//提前计算第一个点用于确定叉积符号

	for (var i:Number = 1, j:Number = 0; i < len; j = i++)
	{
		边向量 = _root.创建向量(多边形[i].x - 多边形[j].x, 多边形[i].y - 多边形[j].y);

		if (边向量.叉积({x:点.x - 多边形[j].x, y:点.y - 多边形[j].y}) * 符号标志 < 0)
		{
			return false;// 叉积符号不一致，点在多边形外
		}
	}
	return true;// 所有叉积符号一致，点在多边形内
};
// 预计算边向量节约性能
_root.点在缓存多边形内 = function(点:Object, 多边形:Array, 边向量集:Array):Boolean 
{
	var len:Number = 多边形.length;
	var 符号标志:Number = 边向量集[0].叉积({x:点.x - 多边形[len - 1].x, y:点.y - 多边形[len - 1].y}) > 0 ? 1 : -1;// 使用预先计算的边向量集的第一个边向量和点向量的叉积 

	for (var i:Number = 1, j:Number = 0; i < len; j = i++)
	{
		if (边向量集[i].叉积({x:点.x - 多边形[j].x, y:点.y - 多边形[j].y}) * 符号标志 < 0)
		{
			return false;// 叉积符号不一致，点在多边形外
		}
	}
	return true;// 所有叉积符号一致，点在多边形内
};

_root.点在缓存四边形内 = function(点:Object, 四边形:Array, 边向量集:Array):Boolean 
{
    // 使用第一个边向量和点向量的叉积初始化符号标志
    var 符号标志:Number = 边向量集[0].叉积({x:点.x - 四边形[3].x, y:点.y - 四边形[3].y}) > 0 ? 1 : -1;

    // 循环展开，分别计算剩余三个边向量和点向量的叉积
    if (边向量集[1].叉积({x:点.x - 四边形[0].x, y:点.y - 四边形[0].y}) * 符号标志 < 0) return false;
    if (边向量集[2].叉积({x:点.x - 四边形[1].x, y:点.y - 四边形[1].y}) * 符号标志 < 0) return false;
    if (边向量集[3].叉积({x:点.x - 四边形[2].x, y:点.y - 四边形[2].y}) * 符号标志 < 0) return false;

    // 如果所有叉积符号一致，点在四边形内
    return true;
};


// 判断是否左转
_root.凸包左转 = function(a, b, c)
{
	return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x) > 0;
};
// Graham 扫描算法实现凸包
_root.凸包Graham扫描 = function(点集)
{
	// 找到Y坐标最小的点（最下面的点），如果有多个，则取最左边的
	var 最低点 = 点集[0];
	var len:Number = 点集.length;
	for (var i = 1; i < len; i++)
	{
		var 点 = 点集[i];
		if (点.y < 最低点.y or (点.y == 最低点.y and 点.x < 最低点.x))
		{
			最低点 = 点;
		}
	}

	点集 = InsertionSort.sort(点集, function (a, b) {
		return Math.atan2(a.y - 最低点.y, a.x - 最低点.x) - Math.atan2(b.y - 最低点.y, b.x - 最低点.x);
	});

	var 凸包 = [点集[0], 点集[1]];
	for (var i = 2; i < len; i++)
	{
		while (凸包.length >= 2 and !_root.凸包左转(凸包[凸包.length - 2], 凸包[凸包.length - 1], 点集[i]))
		{
			凸包.pop();
		}
		凸包.push(点集[i]);
	}

	return 凸包;
};

_root.凸包Jarvis步进 = function(点集:Array):Array 
{
	var len:Number = 点集.length;
	if (len < 4)
	{
		return 点集.concat();// 对三角形，线段与点直接返回不需要计算   
	}

	var 凸包:Array = [];
	var 起点索引:Number = 0;// 找到Y坐标最小的点，如果有多个，则取最左边的
	for (var i:Number = 1; i < len; i++)
	{
		if (点集[i].y < 点集[起点索引].y or (点集[i].y == 点集[起点索引].y and 点集[i].x < 点集[起点索引].x))
		{
			起点索引 = i;
		}
	}

	var 索引:Number = 起点索引;
	do
	{
		凸包.push(点集[索引]);
		var 下一个点索引:Number = 索引 + 1 == len ? 0 : 索引 + 1;

		for (var i:Number = 0; i < len; i++)
		{
			if (i == 索引)
			{
				continue;// 避免重复检查 
			}
			if (_root.凸包左转(点集[索引], 点集[i], 点集[下一个点索引]))
			{
				下一个点索引 = i;
			}
		}

		索引 = 下一个点索引;
	} while (索引 != 起点索引);// 回到起始点

	return 凸包;
};

_root.多边形交集 = function(多边形a:Array, 多边形b:Array):Array 
{
	var 交点集:Array = [];// 获取碰撞产生的交集
	var 检查并添加点 = function(点:Object)
	{
		var 键:String = 点.x + "_" + 点.y;//闭包优化性能
		if (!点哈希[键])
		{
			点哈希[键] = 点;// 如果点不在哈希表中则添加到哈希表
			交点集.push(点);
		}
	};// 添加到交点集
	var len_a = 多边形a.length, len_b = 多边形b.length;
	var 边向量集a:Array = new Array(len_a), 边向量集b:Array = new Array(len_b);//缓存多边形的边避免重复计算
	var 边界框缓存a:Array = new Array(len_a), 边界框缓存b:Array = new Array(len_b);// 预计算并缓存多边形的每条边的边界框
	var 边界框a:Object = {minX:多边形a[0].x, maxX:多边形a[0].x, minY:多边形a[0].y, maxY:-多边形a[0].y};// 计算两个多边形的边界框用于aabb过滤
	var 边界框b:Object = {minX:多边形b[0].x, maxX:多边形b[0].x, minY:多边形b[0].y, maxY:-多边形b[0].y};

	for (var i:Number = 0, ii:Number = len_a - 1; i < len_a; ii = i++)
	{
		边界框缓存a[ii] = _root.计算线段边界框(多边形a[ii], 多边形a[i]);//利用上一个索引实现反向赋值
		边界框a.minX = Math.min(边界框a.minX, 多边形a[i].x);
		边界框a.maxX = Math.max(边界框a.maxX, 多边形a[i].x);
		边界框a.minY = Math.min(边界框a.minY, 多边形a[i].y);
		边界框a.maxY = Math.max(边界框a.maxY, 多边形a[i].y);
		边向量集a[i] = _root.创建向量(多边形a[i].x - 多边形a[ii].x, 多边形a[i].y - 多边形a[ii].y);
	}
	for (var j:Number = 0, jj:Number = len_b - 1; j < len_b; jj = j++)
	{
		边界框缓存b[jj] = _root.计算线段边界框(多边形b[jj], 多边形b[j]);
		边界框b.minX = Math.min(边界框b.minX, 多边形b[j].x);
		边界框b.maxX = Math.max(边界框b.maxX, 多边形b[j].x);
		边界框b.minY = Math.min(边界框b.minY, 多边形b[j].y);
		边界框b.maxY = Math.max(边界框b.maxY, 多边形b[j].y);
		边向量集b[j] = _root.创建向量(多边形b[j].x - 多边形b[jj].x, 多边形b[j].y - 多边形b[jj].y);
	}

	for (var k = 0; k < len_a; k++)
	{
		for (var l = 0; l < len_b; l++)
		{
			if (_root.边界框相交(边界框缓存a[k], 边界框缓存b[l]))
			{
				var 交点:Object = _root.计算交点(多边形a[k], 多边形a[(k + 1 == len_a) ? 0 : k + 1], 多边形b[l], 多边形b[(l + 1 == len_b) ? 0 : l + 1]);//交点并不是必被计算，因此不需要保持记录上一个索引
				if (交点)
				{
					交点集.push(交点);// 计算所有交点
				}
			}
		}
		if (_root.点在边界框内(多边形a[k], 边界框b) and _root.点在缓存多边形内(多边形a[k], 多边形b, 边向量集b))
		{
			检查并添加点(多边形a[k]);// 合并交点和原始顶点
		}
	}

	for (m = 0; m < len_b; m++)
	{
		if (_root.点在边界框内(多边形b[m], 边界框a) and _root.点在缓存多边形内(多边形b[m], 多边形a, 边向量集a))
		{
			检查并添加点(多边形b[m]);//合并剩下的原始顶点
		}
	}
	if(交点集.length > 16)
	{
		return _root.凸包Graham扫描(交点集);//构建凸多边形方便计算，在大交点数量的情况下扫描法比步进法开销更低
	}
	return _root.凸包Jarvis步进(交点集);//在小交点数量的情况下步进法比扫描法开销更低
};

_root.矩形交集 = function(子弹:Array, 目标:Array,子弹边向量集:Array):Array 
{
	var 交点集:Array = [];// 获取碰撞产生的交集

	var 目标边向量集:Array = [
		_root.创建向量(目标[0].x - 目标[3].x, 目标[0].y - 目标[3].y),
		_root.创建向量(目标[1].x - 目标[0].x, 目标[1].y - 目标[0].y),
		_root.创建向量(目标[2].x - 目标[1].x, 目标[2].y - 目标[1].y),
		_root.创建向量(目标[3].x - 目标[2].x, 目标[3].y - 目标[2].y)
	];// 缓存目标的边避免重复计算

	var 子弹边界框缓存:Array = 
	[
		{
			minX: Math.min(子弹[0].x, 子弹[1].x),
			maxX: Math.max(子弹[0].x, 子弹[1].x),
			minY: Math.min(子弹[0].y, 子弹[1].y),
			maxY: Math.max(子弹[0].y, 子弹[1].y)
		},
		{
			minX: Math.min(子弹[1].x, 子弹[2].x),
			maxX: Math.max(子弹[1].x, 子弹[2].x),
			minY: Math.min(子弹[1].y, 子弹[2].y),
			maxY: Math.max(子弹[1].y, 子弹[2].y)
		},
		{
			minX: Math.min(子弹[2].x, 子弹[3].x),
			maxX: Math.max(子弹[2].x, 子弹[3].x),
			minY: Math.min(子弹[2].y, 子弹[3].y),
			maxY: Math.max(子弹[2].y, 子弹[3].y)
		},
		{
			minX: Math.min(子弹[3].x, 子弹[0].x),
			maxX: Math.max(子弹[3].x, 子弹[0].x),
			minY: Math.min(子弹[3].y, 子弹[0].y),
			maxY: Math.max(子弹[3].y, 子弹[0].y)
		}
	];// 预计算并缓存子弹的每条边的边界框

	var 目标边界框缓存:Array = [
		{
			minX: Math.min(目标[0].x, 目标[1].x),
			maxX: Math.max(目标[0].x, 目标[1].x),
			minY: Math.min(目标[0].y, 目标[1].y),
			maxY: Math.max(目标[0].y, 目标[1].y)
		},
		{
			minX: Math.min(目标[1].x, 目标[2].x),
			maxX: Math.max(目标[1].x, 目标[2].x),
			minY: Math.min(目标[1].y, 目标[2].y),
			maxY: Math.max(目标[1].y, 目标[2].y)
		},
		{
			minX: Math.min(目标[2].x, 目标[3].x),
			maxX: Math.max(目标[2].x, 目标[3].x),
			minY: Math.min(目标[2].y, 目标[3].y),
			maxY: Math.max(目标[2].y, 目标[3].y)
		},
		{
			minX: Math.min(目标[3].x, 目标[0].x),
			maxX: Math.max(目标[3].x, 目标[0].x),
			minY: Math.min(目标[3].y, 目标[0].y),
			maxY: Math.max(目标[3].y, 目标[0].y)
		}
	];// 预计算并缓存子弹的每条边的边界框

	var 子弹边界框:Object = {}; // 初始化子弹边界框

	子弹边界框.minX = Math.min(子弹[0].x, Math.min(Math.min(子弹[1].x, 子弹[2].x), 子弹[3].x));
	子弹边界框.maxX = Math.max(子弹[0].x, Math.max(Math.max(子弹[1].x, 子弹[2].x), 子弹[3].x));
	子弹边界框.minY = Math.min(子弹[0].y, Math.min(Math.min(子弹[1].y, 子弹[2].y), 子弹[3].y));
	子弹边界框.maxY = Math.max(子弹[0].y, Math.max(Math.max(子弹[1].y, 子弹[2].y), 子弹[3].y));

	var 目标边界框:Object = {}; // 初始化目标边界框
	目标边界框.minX = Math.min(目标[0].x, Math.min(Math.min(目标[1].x, 目标[2].x), 目标[3].x));
	目标边界框.maxX = Math.max(目标[0].x, Math.max(Math.max(目标[1].x, 目标[2].x), 目标[3].x));
	目标边界框.minY = Math.min(目标[0].y, Math.min(Math.min(目标[1].y, 目标[2].y), 目标[3].y));
	目标边界框.maxY = Math.max(目标[0].y, Math.max(Math.max(目标[1].y, 目标[2].y), 目标[3].y));

	
	var 交点:Object = {};
	var 键:String = "";
	var 符号标志:Number = 0;

	if (!(子弹边界框缓存[0].maxX < 目标边界框缓存[0].minX or
      子弹边界框缓存[0].minX > 目标边界框缓存[0].maxX or
      子弹边界框缓存[0].maxY < 目标边界框缓存[0].minY or
      子弹边界框缓存[0].minY > 目标边界框缓存[0].maxY)) 
	{
		交点 = _root.计算交点(子弹[0], 子弹[1], 目标[0], 目标[1]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[0].maxX < 目标边界框缓存[1].minX or 
      子弹边界框缓存[0].minX > 目标边界框缓存[1].maxX or 
      子弹边界框缓存[0].maxY < 目标边界框缓存[1].minY or 
      子弹边界框缓存[0].minY > 目标边界框缓存[1].maxY)) 
	{
		交点 = _root.计算交点(子弹[0], 子弹[1], 目标[1], 目标[2]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[0].maxX < 目标边界框缓存[2].minX or 
		子弹边界框缓存[0].minX > 目标边界框缓存[2].maxX or 
		子弹边界框缓存[0].maxY < 目标边界框缓存[2].minY or 
		子弹边界框缓存[0].minY > 目标边界框缓存[2].maxY)) 
	{
		交点 = _root.计算交点(子弹[0], 子弹[1], 目标[2], 目标[3]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[0].maxX < 目标边界框缓存[3].minX or 
		子弹边界框缓存[0].minX > 目标边界框缓存[3].maxX or 
		子弹边界框缓存[0].maxY < 目标边界框缓存[3].minY or 
		子弹边界框缓存[0].minY > 目标边界框缓存[3].maxY)) 
	{
		交点 = _root.计算交点(子弹[0], 子弹[1], 目标[3], 目标[0]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[1].maxX < 目标边界框缓存[0].minX or 
      子弹边界框缓存[1].minX > 目标边界框缓存[0].maxX or 
      子弹边界框缓存[1].maxY < 目标边界框缓存[0].minY or 
      子弹边界框缓存[1].minY > 目标边界框缓存[0].maxY)) 
	{
		交点 = _root.计算交点(子弹[1], 子弹[2], 目标[0], 目标[1]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[1].maxX < 目标边界框缓存[1].minX or 
		子弹边界框缓存[1].minX > 目标边界框缓存[1].maxX or 
		子弹边界框缓存[1].maxY < 目标边界框缓存[1].minY or 
		子弹边界框缓存[1].minY > 目标边界框缓存[1].maxY)) 
	{
		交点 = _root.计算交点(子弹[1], 子弹[2], 目标[1], 目标[2]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[1].maxX < 目标边界框缓存[2].minX or 
		子弹边界框缓存[1].minX > 目标边界框缓存[2].maxX or 
		子弹边界框缓存[1].maxY < 目标边界框缓存[2].minY or 
		子弹边界框缓存[1].minY > 目标边界框缓存[2].maxY)) 
	{
		交点 = _root.计算交点(子弹[1], 子弹[2], 目标[2], 目标[3]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[1].maxX < 目标边界框缓存[3].minX or 
		子弹边界框缓存[1].minX > 目标边界框缓存[3].maxX or 
		子弹边界框缓存[1].maxY < 目标边界框缓存[3].minY or 
		子弹边界框缓存[1].minY > 目标边界框缓存[3].maxY)) 
	{
		交点 = _root.计算交点(子弹[1], 子弹[2], 目标[3], 目标[0]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[2].maxX < 目标边界框缓存[0].minX or 
      子弹边界框缓存[2].minX > 目标边界框缓存[0].maxX or 
      子弹边界框缓存[2].maxY < 目标边界框缓存[0].minY or 
      子弹边界框缓存[2].minY > 目标边界框缓存[0].maxY)) 
	{
		交点 = _root.计算交点(子弹[2], 子弹[3], 目标[0], 目标[1]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[2].maxX < 目标边界框缓存[1].minX or 
		子弹边界框缓存[2].minX > 目标边界框缓存[1].maxX or 
		子弹边界框缓存[2].maxY < 目标边界框缓存[1].minY or 
		子弹边界框缓存[2].minY > 目标边界框缓存[1].maxY)) 
	{
		交点 = _root.计算交点(子弹[2], 子弹[3], 目标[1], 目标[2]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[2].maxX < 目标边界框缓存[2].minX or 
		子弹边界框缓存[2].minX > 目标边界框缓存[2].maxX or 
		子弹边界框缓存[2].maxY < 目标边界框缓存[2].minY or 
		子弹边界框缓存[2].minY > 目标边界框缓存[2].maxY)) 
	{
		交点 = _root.计算交点(子弹[2], 子弹[3], 目标[2], 目标[3]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[2].maxX < 目标边界框缓存[3].minX or 
		子弹边界框缓存[2].minX > 目标边界框缓存[3].maxX or 
		子弹边界框缓存[2].maxY < 目标边界框缓存[3].minY or 
		子弹边界框缓存[2].minY > 目标边界框缓存[3].maxY)) 
	{
		交点 = _root.计算交点(子弹[2], 子弹[3], 目标[3], 目标[0]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[3].maxX < 目标边界框缓存[0].minX or 
      子弹边界框缓存[3].minX > 目标边界框缓存[0].maxX or 
      子弹边界框缓存[3].maxY < 目标边界框缓存[0].minY or 
      子弹边界框缓存[3].minY > 目标边界框缓存[0].maxY)) 
	{
		交点 = _root.计算交点(子弹[3], 子弹[0], 目标[0], 目标[1]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[3].maxX < 目标边界框缓存[1].minX or 
		子弹边界框缓存[3].minX > 目标边界框缓存[1].maxX or 
		子弹边界框缓存[3].maxY < 目标边界框缓存[1].minY or 
		子弹边界框缓存[3].minY > 目标边界框缓存[1].maxY)) 
	{
		交点 = _root.计算交点(子弹[3], 子弹[0], 目标[1], 目标[2]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[3].maxX < 目标边界框缓存[2].minX or 
		子弹边界框缓存[3].minX > 目标边界框缓存[2].maxX or 
		子弹边界框缓存[3].maxY < 目标边界框缓存[2].minY or 
		子弹边界框缓存[3].minY > 目标边界框缓存[2].maxY)) 
	{
		交点 = _root.计算交点(子弹[3], 子弹[0], 目标[2], 目标[3]);
		if (交点) 交点集.push(交点);
	}
	if (!(子弹边界框缓存[3].maxX < 目标边界框缓存[3].minX or 
		子弹边界框缓存[3].minX > 目标边界框缓存[3].maxX or 
		子弹边界框缓存[3].maxY < 目标边界框缓存[3].minY or 
		子弹边界框缓存[3].minY > 目标边界框缓存[3].maxY)) 
	{
		交点 = _root.计算交点(子弹[3], 子弹[0], 目标[3], 目标[0]);
		if (交点) 交点集.push(交点);
	}
	if (目标[0].x >= 子弹边界框.minX and 目标[0].x <= 子弹边界框.maxX and
		目标[0].y >= 子弹边界框.minY and 目标[0].y <= 子弹边界框.maxY) 
	{
		符号标志 = 子弹边向量集[0].叉积({x:目标[0].x - 子弹[3].x, y:目标[0].y - 子弹[3].y}) > 0 ? 1 : -1;
		if (子弹边向量集[1].叉积({x:目标[0].x - 子弹[0].x, y:目标[0].y - 子弹[0].y}) * 符号标志 >= 0 and
			子弹边向量集[2].叉积({x:目标[0].x - 子弹[1].x, y:目标[0].y - 子弹[1].y}) * 符号标志 >= 0 and
			子弹边向量集[3].叉积({x:目标[0].x - 子弹[2].x, y:目标[0].y - 子弹[2].y}) * 符号标志 >= 0)
		{
			键 = 目标[0].x + "_" + 目标[0].y;
			if (!点哈希[键]) {
				点哈希[键] = 目标[0];
				交点集.push(目标[0]);
			}
		}
	}
	if (目标[1].x >= 子弹边界框.minX and 目标[1].x <= 子弹边界框.maxX and
		目标[1].y >= 子弹边界框.minY and 目标[1].y <= 子弹边界框.maxY) 
	{
		符号标志 = 子弹边向量集[0].叉积({x:目标[1].x - 子弹[3].x, y:目标[1].y - 子弹[3].y}) > 0 ? 1 : -1;
		if (子弹边向量集[1].叉积({x:目标[1].x - 子弹[0].x, y:目标[1].y - 子弹[0].y}) * 符号标志 >= 0 and
			子弹边向量集[2].叉积({x:目标[1].x - 子弹[1].x, y:目标[1].y - 子弹[1].y}) * 符号标志 >= 0 and
			子弹边向量集[3].叉积({x:目标[1].x - 子弹[2].x, y:目标[1].y - 子弹[2].y}) * 符号标志 >= 0)
		{
			键 = 目标[1].x + "_" + 目标[1].y;
			if (!点哈希[键]) {
				点哈希[键] = 目标[1];
				交点集.push(目标[1]);
			}
		}
	}
	if (目标[2].x >= 子弹边界框.minX and 目标[2].x <= 子弹边界框.maxX and
		目标[2].y >= 子弹边界框.minY and 目标[2].y <= 子弹边界框.maxY) 
	{
		符号标志 = 子弹边向量集[0].叉积({x:目标[2].x - 子弹[3].x, y:目标[2].y - 子弹[3].y}) > 0 ? 1 : -1;
		if (子弹边向量集[1].叉积({x:目标[2].x - 子弹[0].x, y:目标[2].y - 子弹[0].y}) * 符号标志 >= 0 and
			子弹边向量集[2].叉积({x:目标[2].x - 子弹[1].x, y:目标[2].y - 子弹[1].y}) * 符号标志 >= 0 and
			子弹边向量集[3].叉积({x:目标[2].x - 子弹[2].x, y:目标[2].y - 子弹[2].y}) * 符号标志 >= 0)
		{
			键 = 目标[2].x + "_" + 目标[2].y;
			if (!点哈希[键]) {
				点哈希[键] = 目标[2];
				交点集.push(目标[2]);
			}
		}
	}
	if (目标[3].x >= 子弹边界框.minX and 目标[3].x <= 子弹边界框.maxX and
		目标[3].y >= 子弹边界框.minY and 目标[3].y <= 子弹边界框.maxY) 
	{
		符号标志 = 子弹边向量集[0].叉积({x:目标[3].x - 子弹[3].x, y:目标[3].y - 子弹[3].y}) > 0 ? 1 : -1;
		if (子弹边向量集[1].叉积({x:目标[3].x - 子弹[0].x, y:目标[3].y - 子弹[0].y}) * 符号标志 >= 0 and
			子弹边向量集[2].叉积({x:目标[3].x - 子弹[1].x, y:目标[3].y - 子弹[1].y}) * 符号标志 >= 0 and
			子弹边向量集[3].叉积({x:目标[3].x - 子弹[2].x, y:目标[3].y - 子弹[2].y}) * 符号标志 >= 0)
		{
			键 = 目标[3].x + "_" + 目标[3].y;
			if (!点哈希[键]) {
				点哈希[键] = 目标[3];
				交点集.push(目标[3]);
			}
		}
	}
	if (子弹[0].x >= 目标边界框.minX and 子弹[0].x <= 目标边界框.maxX and
		子弹[0].y >= 目标边界框.minY and 子弹[0].y <= 目标边界框.maxY) 
	{
		符号标志 = 目标边向量集[0].叉积({x:子弹[0].x - 目标[3].x, y:子弹[0].y - 目标[3].y}) > 0 ? 1 : -1;
		if (目标边向量集[1].叉积({x:子弹[0].x - 目标[0].x, y:子弹[0].y - 目标[0].y}) * 符号标志 >= 0 and
			目标边向量集[2].叉积({x:子弹[0].x - 目标[1].x, y:子弹[0].y - 目标[1].y}) * 符号标志 >= 0 and
			目标边向量集[3].叉积({x:子弹[0].x - 目标[2].x, y:子弹[0].y - 目标[2].y}) * 符号标志 >= 0)
		{
			键 = 子弹[0].x + "_" + 子弹[0].y;
			if (!点哈希[键]) {
				点哈希[键] = 子弹[0];
				交点集.push(子弹[0]);
			}
		}
	}
	if (子弹[1].x >= 目标边界框.minX and 子弹[1].x <= 目标边界框.maxX and
		子弹[1].y >= 目标边界框.minY and 子弹[1].y <= 目标边界框.maxY) 
	{
		符号标志 = 目标边向量集[0].叉积({x:子弹[1].x - 目标[3].x, y:子弹[1].y - 目标[3].y}) > 0 ? 1 : -1;
		if (目标边向量集[1].叉积({x:子弹[1].x - 目标[0].x, y:子弹[1].y - 目标[0].y}) * 符号标志 >= 0 and
			目标边向量集[2].叉积({x:子弹[1].x - 目标[1].x, y:子弹[1].y - 目标[1].y}) * 符号标志 >= 0 and
			目标边向量集[3].叉积({x:子弹[1].x - 目标[2].x, y:子弹[1].y - 目标[2].y}) * 符号标志 >= 0)
		{
			键 = 子弹[1].x + "_" + 子弹[1].y;
			if (!点哈希[键]) {
				点哈希[键] = 子弹[1];
				交点集.push(子弹[1]);
			}
		}
	}
	if (子弹[2].x >= 目标边界框.minX and 子弹[2].x <= 目标边界框.maxX and
		子弹[2].y >= 目标边界框.minY and 子弹[2].y <= 目标边界框.maxY) 
	{
		符号标志 = 目标边向量集[0].叉积({x:子弹[2].x - 目标[3].x, y:子弹[2].y - 目标[3].y}) > 0 ? 1 : -1;
		if (目标边向量集[1].叉积({x:子弹[2].x - 目标[0].x, y:子弹[2].y - 目标[0].y}) * 符号标志 >= 0 and
			目标边向量集[2].叉积({x:子弹[2].x - 目标[1].x, y:子弹[2].y - 目标[1].y}) * 符号标志 >= 0 and
			目标边向量集[3].叉积({x:子弹[2].x - 目标[2].x, y:子弹[2].y - 目标[2].y}) * 符号标志 >= 0)
		{
			键 = 子弹[2].x + "_" + 子弹[2].y;
			if (!点哈希[键]) {
				点哈希[键] = 子弹[2];
				交点集.push(子弹[2]);
			}
		}
	}
	if (子弹[3].x >= 目标边界框.minX and 子弹[3].x <= 目标边界框.maxX and
		子弹[3].y >= 目标边界框.minY and 子弹[3].y <= 目标边界框.maxY) 
	{
		符号标志 = 目标边向量集[0].叉积({x:子弹[3].x - 目标[3].x, y:子弹[3].y - 目标[3].y}) > 0 ? 1 : -1;
		if (目标边向量集[1].叉积({x:子弹[3].x - 目标[0].x, y:子弹[3].y - 目标[0].y}) * 符号标志 >= 0 and
			目标边向量集[2].叉积({x:子弹[3].x - 目标[1].x, y:子弹[3].y - 目标[1].y}) * 符号标志 >= 0 and
			目标边向量集[3].叉积({x:子弹[3].x - 目标[2].x, y:子弹[3].y - 目标[2].y}) * 符号标志 >= 0)
		{
			键 = 子弹[3].x + "_" + 子弹[3].y;
			if (!点哈希[键]) {
				点哈希[键] = 子弹[3];
				交点集.push(子弹[3]);
			}
		}
	}

	var len:Number = 交点集.length;
	if (len < 4) {
		return 交点集.concat(); // 对三角形，线段与点直接返回不需要计算
	}

	var 凸包:Array = [];
	var 起点索引:Number = 0; // 找到Y坐标最小的点，如果有多个，则取最左边的
	for (var i:Number = 1; i < len; i++) {
		if (交点集[i].y < 交点集[起点索引].y or (交点集[i].y == 交点集[起点索引].y and 交点集[i].x < 交点集[起点索引].x)) {
			起点索引 = i;
		}
	}

	var 索引:Number = 起点索引;
	do {
		凸包.push(交点集[索引]);
		var 下一个点索引:Number = 索引 + 1 == len ? 0 : 索引 + 1;

		for (var i:Number = 0; i < len; i++) {
			if (i == 索引) {
				continue; // 避免重复检查
			}
			if ((交点集[i].x - 交点集[索引].x) * (交点集[下一个点索引].y - 交点集[索引].y) - (交点集[i].y - 交点集[索引].y) * (交点集[下一个点索引].x - 交点集[索引].x) > 0) {
				下一个点索引 = i;
			}
		}

		索引 = 下一个点索引;
	} while (索引 != 起点索引); // 回到起始点

	return 凸包;//由于这个函数条件确定，因此手动展开循环优化性能
};