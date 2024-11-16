_root.根据技能名查找主角技能等级 = function(技能名)
{
	var 主角技能表 = _root.主角技能表;
	for(var i = 0; i < 主角技能表.length; i++)
	{
		if (主角技能表[i][0] == 技能名)
		{
			return 主角技能表[i][1];
		}
	}
	return 0;
};

_root.学习技能 = function(技能名, 等级)
{
	var 主角技能表 = _root.主角技能表;
	var 技能信息 = _root.技能表对象[技能名];
	var 已获得该技能 = false;
	for(var i = 0; i < 主角技能表.length; i++)
	{
		var 技能 = 主角技能表[i];
		if (技能[0] == 技能名)
		{
			已获得该技能 = true;
			if (技能[1] < 等级)
			{
				技能[1] = 等级;
				_root.排列技能图标();
				_root.发布消息(_root.获得翻译(技能名) + "，" + _root.获得翻译("技能升级成功！"));
				if(技能信息.Passive){
					_root.更新主角被动技能();
				}
				return true;
			}
		}
	}
	for(var i = 0; i < 主角技能表.length; i++)
	{
		var 技能 = 主角技能表[i];
		if (技能[0] == "" && !已获得该技能)
		{
			技能[0] = 技能名;
			技能[1] = 等级;
			技能[2] = false;
			技能[3] = 技能信息.Type;
			技能[4] = false;
			//被动技能学习时默认开启
			if(!技能信息.Equippable){
				技能[2] = true;
				技能[4] = true;
			}
			_root.排列技能图标();
			_root.发布消息(_root.获得翻译(技能名) + "，" + _root.获得翻译("新技能获得！"));
			if(技能信息.Passive){
				_root.更新主角被动技能();
			}
			return true;
		}
	}
	_root.发布消息(_root.获得翻译("技能槽已满！"));
	return false;
}

_root.更新主角被动技能 = function()
{
	_root.主角被动技能 = {};
	for(var i = 0; i < _root.主角技能表.length; i++)
	{
		var 技能 = _root.主角技能表[i];
		if(技能[0] != ""){
			if(_root.技能表对象[技能[0]].Passive){
				_root.主角被动技能[技能[0]] = {技能名:技能[0], 等级:技能[1], 启用:技能[4]};
			}
		}
	}
	_root.gameworld[_root.控制目标].被动技能 = _root.主角被动技能;
	_root.gameworld[_root.控制目标].读取被动效果();
}

_root.排列技能图标 = function()
{
	var 物品栏界面 = _root.物品栏界面;
	_root.玩家信息界面.刷新技能等级显示();
	if (_root.物品栏界面.界面 == "技能")
	{
		var 图标x = 物品栏界面.技能图标._x;
		var 图标y = 物品栏界面.技能图标._y;
		var 图标高度 = 28;
		var 图标宽度 = 28;
		var 列数 = 8;
		var 行数 = 10;
		var 换行计数 = 0;
		
		for(var i = 0; i < 列数 * 行数; i++)
		{
			var 技能信息 = 主角技能表[i];

			物品栏界面["技能图标" + i].removeMovieClip();
			var 当前技能图标 = 物品栏界面.attachMovie("技能图标","技能图标" + i,物品栏界面.getNextHighestDepth(),{数量:技能信息[1]});

			当前技能图标._x = 图标x;
			当前技能图标._y = 图标y;
			图标x += 图标宽度;
			换行计数++;
			if (换行计数 == 列数)
			{
				换行计数 = 0;
				图标x = 物品栏界面.技能图标._x;
				图标y += 图标高度;
			}

			当前技能图标.数量 = 技能信息[1];
			当前技能图标.对应数组号 = i;
			当前技能图标.图标是否可对换位置 = 1;

			if (技能信息[0] && 技能信息[0] != ""){
				当前技能图标.图标 = "图标-" + 技能信息[0];
				当前技能图标.gotoAndStop("默认图标");
			}
		}
	}
	_root.gameworld[_root.控制目标].读取被动效果();
}

_root.删除技能图标 = function()
{
	for(var i = 0; i < 80; i ++)
	{
		_root.物品栏界面["技能图标" + i].removeMovieClip();
	}
}

_root.根据技能名查找全部属性 = function(技能名)
{
	return _root.技能表对象[技能名];
}


_root.主角是否已学 = function(技能名)
{
	var 主角技能表 = _root.主角技能表;
	for (var i = 0; i < 主角技能表.length; i++)
	{
		if (主角技能表[i][0] == 技能名)
		{
			return 主角技能表[i][1];
		}
	}
	return false;
}


_root.主角技能表总数 = 80;

_root.初始化主角技能表 = function(){
	if(_root.主角技能表.length > 0) return;
	_root.主角技能表 = new Array(_root.主角技能表总数);
	for (var i = 0; i < _root.主角技能表总数; i++) _root.主角技能表[i] = ["", 0, false,"",true];
}
_root.初始化主角技能表();

_root.blue的技能 = new Array(56);
_root.blue的技能[0] = ["小跳", 1, false];
_root.blue的技能[1] = ["闪现", 1, false];
_root.blue的技能[2] = ["一瞬千击", 1, false]
_root.blue的技能[3] = ["铁布衫", 1, false];
_root.blue的技能[4] = ["能量盾", 1, false];
_root.blue的技能[5] = ["霸体", 1, false];
_root.blue的技能[6] = ["觉醒霸体", 1, false];
_root.blue的技能[7] = ["觉醒不坏金身", 1, false];
_root.blue的技能[8] = ["寸拳", 1, false];
_root.blue的技能[9] = ["踩人", 1, false];
_root.blue的技能[10] = ["日字冲拳", 1, false];
_root.blue的技能[11] = ["组合拳", 1, false];
_root.blue的技能[12] = ["旋风腿", 1, false];
_root.blue的技能[13] = ["虎拳", 1, false];
_root.blue的技能[14] = ["兽王崩拳", 1, false];
_root.blue的技能[15] = ["径庭拳/黑闪", 1, false];
_root.blue的技能[16] = [];
_root.blue的技能[17] = [];
_root.blue的技能[18] = [];
_root.blue的技能[19] = [];
_root.blue的技能[20] = [];
_root.blue的技能[21] = [];
_root.blue的技能[22] = [];
_root.blue的技能[23] = [];
_root.blue的技能[24] = ["气动波", 1, false];
_root.blue的技能[25] = ["震地", 1, false];
_root.blue的技能[26] = ["地震", 1, false];
_root.blue的技能[27] = ["觉醒震地", 1, false];
_root.blue的技能[28] = [];
_root.blue的技能[31] = ["聚气", 1, false];
_root.blue的技能[40] = ["背摔", 1, false];
_root.blue的技能[41] = ["抱腿摔", 1, false];
_root.blue的技能[48] = ["拳脚攻击", 1, false];
_root.blue的技能[49] = ["升龙拳", 1, false];
_root.blue的技能[50] = ["裂地拳", 1, false];
_root.blue的技能[51] = ["拳脚空中连招", 1, false];


// _root.andy的技能 = [];
// _root.andy的技能[16] = ["瞬步斩", 1, false];
// _root.andy的技能[17] = ["凶斩", 1, false];
// _root.andy的技能[18] = ["火舞旋风", 1, false];
// _root.andy的技能[19] = ["拔刀术", 1, false];
// _root.andy的技能[20] = ["龙斩", 1, false];
// _root.andy的技能[21] = ["六连", 1, false];
// _root.andy的技能[22] = ["空间斩", 1, false];
// _root.andy的技能[27] = ["追猎射击", 1, false];
// _root.andy的技能[28] = ["翻滚换弹", 1, false];
// _root.andy的技能[29] = ["火力支援", 1, false];
// _root.andy的技能[51] = ["上挑", 1, false];
// _root.andy的技能[52] = ["下劈", 1, false];
// _root.andy的技能[53] = ["刀剑空中连招", 1, false];
_root.andy的技能 = new Array(24);
_root.andy的技能[0] = ["迅斩", 1, false];
_root.andy的技能[1] = ["瞬步斩", 1, false];
_root.andy的技能[2] = ["凶斩", 1, false];
_root.andy的技能[3] = ["火舞旋风", 1, false];
_root.andy的技能[4] = ["拔刀术", 1, false];
_root.andy的技能[5] = ["龙斩", 1, false];
_root.andy的技能[6] = ["六连", 1, false];
_root.andy的技能[7] = ["空间斩", 1, false];
_root.andy的技能[8] = ["追猎射击", 1, false];
_root.andy的技能[9] = ["翻滚换弹", 1, false];
_root.andy的技能[10] = ["火力支援", 1, false];
_root.andy的技能[11] = ["战术目镜", 1, false];
_root.andy的技能[12] = ["上帝之杖", 1, false];
_root.andy的技能[16] = ["刀剑攻击", 1, false];
_root.andy的技能[17] = ["上挑", 1, false];
_root.andy的技能[18] = ["下劈", 1, false];
_root.andy的技能[19] = ["刀剑空中连招", 1, false];
_root.andy的技能[20] = ["枪械攻击", 1, false];
_root.andy的技能[21] = ["移动射击", 1, false];
_root.andy的技能[22] = ["枪械师", 1, false];
_root.andy的技能[23] = ["轰炸专家", 1, false];
_root.andy的技能[24] = ["独行者", 1, false];


_root.theGirl的技能 = new Array(2);
_root.theGirl的技能[0] = ["兴奋剂" ,1,false];
_root.theGirl的技能[1] = ["能量盾", 1, false];



_root.boy的技能 = new Array(16);
_root.boy的技能[0] = ["追猎射击", 1, false];
_root.boy的技能[1] = ["翻滚换弹", 1, false];
_root.boy的技能[2] = ["火力支援", 1, false];
_root.boy的技能[3] = ["战术目镜", 1, false];
_root.boy的技能[4] = ["上帝之杖", 1, false];
_root.boy的技能[8] = ["枪械攻击", 1, false];
_root.boy的技能[9] = ["移动射击", 1, false];
_root.boy的技能[10] = ["枪械师", 1, false];
_root.boy的技能[11] = ["轰炸专家", 1, false];


_root.盔甲君的技能 = new Array(8);
_root.盔甲君的技能[0] = ["时间停止", 1,false];
_root.盔甲君的技能[1] = [];
_root.盔甲君的技能[2] = ["不卸之力", 1,false];
_root.盔甲君的技能[3] = ["重力场", 1,false];
_root.盔甲君的技能[4] = ["重力井", 1,false];


_root.小F的技能 = new Array(2);
_root.小F的技能[0] = ["铁匠", 1,false];
_root.小F的技能[1] = ["上帝之杖", 1, false];


_root.shopGirl的技能 = new Array(2);
_root.shopGirl的技能[0] = ["口才", 1,false];


_root.酒保的技能 = new Array(2);
_root.酒保的技能[0] = ["口才", 1,false];


_root.丽丽丝的技能 = new Array(2);
_root.丽丽丝的技能[0] = ["炼金", 1,false];


_root.格格巫的技能 = new Array(2);
_root.格格巫的技能[0] = ["炼金", 1,false];








