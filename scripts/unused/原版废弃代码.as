//运营活动信息
/*function 获取运营活动信息()
{
   _root.是否显示商城活动 = 1;
   _root.活动按钮标题 = "";
   _root.活动内容详情文件 = "";
   _root.是否显示套装活动 = 1;
   _root.运营活动战宠等级限制 = 1;
   _root.最强战宠是否显示 = 1;
   _root.战宠折扣 = 1;
   _root.战宠格子折扣 = 1;
   _root.次元塔副本开关 = 1;
   _root.斯巴达副本开关 = 1;
   _root.按钮副本一排 = random(4) + 1 + 1;
   _root.按钮副本二排 = random(4) + 1;
   _root.新年碎片副本开关 = 1;
   _root.在线时长奖励类别 = 1;
   return undefined;
}
function 打开全部活动()
{
   _root.是否显示商城活动 = 1;
   _root.是否显示套装活动 = 1;
   _root.运营活动战宠等级限制 = 1;
   _root.最强战宠是否显示 = 1;
   _root.次元塔副本开关 = 1;
   _root.斯巴达副本开关 = 1;
   _root.按钮副本一排 = random(5) + 1;
   _root.按钮副本二排 = random(5) + 1;
   _root.新年碎片副本开关 = 1;
   _root.在线时长奖励类别 = 1;
}
获取运营活动信息();
*/

//多玩家支持
/*
function 多人玩家注销(玩家编号)
{
	if (_root.当前玩家总数 > 1)
	{
		if (playerCurrent != 玩家编号)
		{
			_root.gameworld["玩家" + 玩家编号].removeMovieClip();
			_root.多玩家exitlogin(_root.playerAccId[玩家编号]);
			_root.当前玩家总数--;
			_root.playerData[玩家编号] = [];
			_root.playerAccount[玩家编号] = "";
			_root.playerPass[玩家编号] = "";
			_root.playerName[玩家编号] = "";
			_root.playerAccId[玩家编号] = 0;
			_root.操控目标表[玩家编号] = "";
			_root.排列显示多人UI();
		}
		else
		{
			var _loc3_ = 0;
			while (_loc3_ < _root.playerAccount.length)
			{
				if (_loc3_ != 玩家编号 and _root.playerAccount[_loc3_] != "")
				{
					_root.切换玩家(_loc3_);
					_root.gameworld["玩家" + 玩家编号].removeMovieClip();
					_root.当前玩家总数--;
					_root.playerData[玩家编号] = [];
					_root.playerAccount[玩家编号] = "";
					_root.playerPass[玩家编号] = "";
					_root.playerName[玩家编号] = "";
					_root.playerAccId[玩家编号] = 0;
					_root.操控目标表[玩家编号] = "";
					_root.排列显示多人UI();
					_root.发布消息(_root.playerAccount[_loc3_] + "自动切换为1号玩家！");
				}
				_loc3_ += 1;
			}
		}
	}
	else
	{
		_root.发布消息("只剩一个玩家！");
	}
	_root.多玩家登录与设置界面.gotoAndPlay("刷新");
}
_root.读取数据库存盘 = function()
{
    var _loc2_ = [];
    var _loc3_ = "http://" + address + "/crazyflashercom/k5_readplaydata.action?k=" + random(100);
    var userDatarecieve = new LoadVars();
    userDatarecieve.userName = _root.游戏ID组[_root.服务器大区代号];
    userDatarecieve.sendAndLoad(_loc3_,userDatarecieve,"POST");
    userDatarecieve.onLoad = function(b)
    {
        if(b)
        {
            _root.游戏服务器无存盘 = false;
            if(userDatarecieve.content + "" == "1")
            {
            _root.游戏服务器无存盘 = true;
            _root.codesigninfo = userDatarecieve.newsign.split(unescape("%20")).join("+");
            _root.gotoAndPlay("读取数据成功");
            }
            else if(userDatarecieve.content + "" == "-1")
            {
            _root.gotoAndStop("读失败");
            }
            else if(userDatarecieve.contentlength == userDatarecieve.content.length)
            {
            _root.游戏服务器无存盘 = false;
            s = Encrypt.解密(_root.生成key(),userDatarecieve.content.split(unescape("%20")).join("+"));
            本地loadgame = SharedObject.getLocal("crazyflasher7_saves");
            _root.mydata = 本地loadgame.data[存盘名];
            falgs = true;
            _root.codesigninfo = userDatarecieve.newsign.split(unescape("%20")).join("+");
            _root.gotoAndPlay("读取数据成功");
            }
            else
            {
            _root.gotoAndStop("读失败");
            }
        }
        else
        {
            _root.gotoAndStop("读失败");
        }
        starts = true;
    };
}
function 读取数据库存盘2(id, pass, dataStore)
{
	var _loc4_ = 0;
	while (_loc4_ < _root.playerAccount.length)
	{
		if (_root.playerAccount[_loc4_] == id)
		{
			_root.发布消息("禁止重复登录！");
			return undefined;
		}
		_loc4_ += 1;
	}
	_root.playerPass[dataStore] = pass;
	_root.playerAccount[dataStore] = id;
	var mydata1 = [];
	var _loc5_ = "http://" + address + "/crazyflashercom/k5_readplaydatatwo.action?k=" + random(100);
	var userDatarecieve = new LoadVars();
	userDatarecieve.userPass = pass;
	userDatarecieve.userName = id;
	userDatarecieve.region = _root.服务器大区代号;
	userDatarecieve.sendAndLoad(_loc5_,userDatarecieve,"POST");
	_root.多玩家登录与设置界面.gotoAndStop("等待中");
	userDatarecieve.onLoad = function(b)
	{
		if (b)
		{
			if (userDatarecieve.content == 1)
			{
				_root.发布消息("帐号或密码错误或无数据！");
				_root.playerAccount[dataStore] = "";
				_root.多玩家登录与设置界面.gotoAndPlay("失败");
			}
			else if (userDatarecieve.content == 2)
			{
				_root.发布消息("该帐号被封！");
				_root.playerAccount[dataStore] = "";
				_root.多玩家登录与设置界面.gotoAndPlay("失败");
			}
			else if (userDatarecieve.content == 3)
			{
				_root.发布消息("禁止一号多登！");
				_root.playerAccount[dataStore] = "";
				_root.多玩家登录与设置界面.gotoAndPlay("失败");
			}
			else
			{
				_root.发布消息("新玩家登录成功！");
				mydata1 = _root.分析数据包(Encrypt.解密(_root.生成key(), userDatarecieve.content.split(unescape("%20")).join("+")));
				_root.playerAccId[dataStore] = Encrypt.解密(_root.生成key(), userDatarecieve.accId);
				_root["lastsave_" + dataStore] = mydata1.toString();
				_root["lastsave2_" + dataStore][0] = mydata1[0].toString();
				_root["lastsave2_" + dataStore][1] = mydata1[1].toString();
				_root["lastsave2_" + dataStore][2] = mydata1[2].toString();
				_root["lastsave2_" + dataStore][3] = mydata1[3].toString();
				_root["lastsave2_" + dataStore][4] = mydata1[4].toString();
				_root["lastsave2_" + dataStore][5] = mydata1[5].toString();
				_root["lastsave2_" + dataStore][6] = mydata1[6].toString();
				if (_root.playerData[dataStore].length == 0)
				{
					_root.当前玩家总数++;
				}
				_root.playerData[dataStore] = mydata1;
				_root.新出生 = true;
				_root.添加新玩家(dataStore);
				_root.多玩家登录与设置界面.gotoAndPlay("成功");
			}
		}
		else
		{
			_root.发布消息("游戏服务器读取失败2！");
			_root.多玩家登录与设置界面.gotoAndPlay("失败");
			_root.playerAccount[dataStore] = "";
		}
	};
}
function 添加新玩家(n)
{
	_root.操控目标表[n] = "玩家" + n;
	var _loc3_ = _root.playerData[n];
	if (_root.新出生 == true)
	{
		_root.gameworld.attachMovie("主角-" + _loc3_[0][1],"玩家" + n,_root.gameworld.getNextHighestDepth(),{_x:_root.gameworld[_root.控制目标]._x, _y:_root.gameworld[_root.控制目标]._y, 用户ID:"userID", 是否为敌人:_root.玩家队伍[n], 身高:_loc3_[0][5], 名字:_loc3_[0][0], 等级:_loc3_[0][3], 脸型:_loc3_[1][0], 发型:_loc3_[1][1], 头部装备:_loc3_[1][2], 上装装备:_loc3_[1][3], 手部装备:_loc3_[1][4], 下装装备:_loc3_[1][5], 脚部装备:_loc3_[1][6], 颈部装备:_loc3_[1][7], 长枪:_loc3_[1][8], 手枪:_loc3_[1][9], 手枪2:_loc3_[1][10], 刀:_loc3_[1][11], 手雷:_loc3_[1][12], 性别:_loc3_[0][1], 是否允许掉装备:false});
	}
	else if (_root.转场景数据[n][0] > 0 and isNaN(_root.转场景数据[n][0]) == false)
	{
		_root.gameworld.attachMovie("主角-" + _loc3_[0][1],"玩家" + n,_root.gameworld.getNextHighestDepth(),{_x:_root.gameworld[_root.控制目标]._x, _y:_root.gameworld[_root.控制目标]._y, 用户ID:"userID", 是否为敌人:_root.玩家队伍[n], 身高:_loc3_[0][5], 名字:_loc3_[0][0], 等级:_loc3_[0][3], 脸型:_loc3_[1][0], 发型:_loc3_[1][1], 头部装备:_loc3_[1][2], 上装装备:_loc3_[1][3], 手部装备:_loc3_[1][4], 下装装备:_loc3_[1][5], 脚部装备:_loc3_[1][6], 颈部装备:_loc3_[1][7], 长枪:_loc3_[1][8], 手枪:_loc3_[1][9], 手枪2:_loc3_[1][10], 刀:_loc3_[1][11], 手雷:_loc3_[1][12], 性别:_loc3_[0][1], 是否允许掉装备:false});
	}
	_root.playerName[n] = "玩家" + n;
	_root.强行刷新多人UI.gotoAndPlay(2);
}
function 切换玩家(n)
{
	主角储存数据 = [_root.角色名, _root.性别, _root.金钱, _root.等级, _root.经验值, _root.身高, _root.技能点数, _root.玩家称号, _root.身价];
	装备储存数据 = [_root.脸型, _root.发型, _root.头部装备, _root.上装装备, _root.手部装备, _root.下装装备, _root.脚部装备, _root.颈部装备, _root.长枪, _root.手枪, _root.手枪2, _root.刀, _root.手雷, _root.快捷物品栏1, _root.快捷物品栏2, _root.快捷物品栏3, _root.快捷技能栏1, _root.快捷技能栏2, _root.快捷技能栏3, _root.快捷技能栏4, _root.快捷技能栏5, _root.快捷技能栏6, 1];
	主角技能表储存数据 = _root.主角技能表;
	物品储存数据 = _root.物品栏;
	同伴储存数据 = [_root.同伴数据, _root.同伴数];
	任务储存数据 = _root.主线任务进度;
	仓库储存数据 = _root.仓库栏;
	lastData = [主角储存数据, 装备储存数据, 物品储存数据, 任务储存数据, 同伴储存数据, 主角技能表储存数据, 仓库储存数据];
	_root.playerData[_root.playerCurrent] = lastData;
	lastplayerAccId = _root.accId;
	_root.playerAccId[_root.playerCurrent] = lastplayerAccId;
	_root.playerCurrent = n;
	_root.mydata = _root.playerData[n];
	_root.accId = _root.playerAccId[n];
	_root.userID = _root.playerAccount[n];
	_root.userPass = _root.playerPass[n];
	_root.控制目标 = _root.操控目标表[n];
	_root.读取存盘();
	_root.切换玩家时UI刷新();
}
function 切换玩家时UI刷新()
{
	_root.排列技能图标();
	_root.排列物品图标();
	_root.物品栏界面.gotoAndPlay("物品栏刷新");
	_root.快捷技能界面.gotoAndPlay("刷新");
	_root.快捷药剂界面.gotoAndPlay("刷新");
	_root.主角是否升级(_root.等级,_root.经验值);
	_root.切换玩家时商城刷新();
	_root.切换玩家任务刷新(_root.主线任务进度);
	_root.排列仓库物品图标();
}
function 切换玩家时商城刷新()
{
	_root.发布消息("刷新商城界面！");
	_root.商城主mc深度 = _root.商城主mc.getDepth();
	_root.商城主mc.removeMovieClip();
	_root.attachMovie("shopMainMC","商城主mc2",_root.getNextHighestDepth());
	_root.发布消息(_root.商城主mc2._x);
	_root.商城主mc2._x = 5;
	_root.商城主mc2._y = 30;
	_root.发布消息(_root.商城主mc2._x);
	_root.商城主mc2._name = "商城主mc";
	_root.商城主mc.swapDepths(_root.商城主mc深度);
	_root.商城主mc.gotoAndPlay("刷新");
}
playerData = [[], [], [], []];
playerAccount = [_root.userID, "", "", ""];
playerPass = ["", "", "", ""];
playerName = ["玩家0", "", "", ""];
playerAccId = [_root.accId, 0, 0, 0];
playerCurrent = 0;
当前玩家总数 = 1;
*/

//多人操控系统
/*
function 添加其他玩家()
{
	var _loc2_ = 0;
	while (_loc2_ < _root.playerData.length)
	{
		if (_loc2_ != _root.playerCurrent)
		{
			if (_root.playerData[_loc2_] != undefined)
			{
				_root.添加新玩家(_loc2_);
			}
		}
		_loc2_ = _loc2_ + 1;
	}
}
function 获取操控编号(目标名)
{
	var _loc2_ = 0;
	while (_loc2_ < _root.操控目标表.length)
	{
		if (目标名 == _root.操控目标表[_loc2_])
		{
			return _loc2_;
		}
		_loc2_ = _loc2_ + 1;
	}
	return -1;
}
function 获取AccId编号(目标名)
{
	var _loc2_ = 0;
	while (_loc2_ < _root.playerAccId.length)
	{
		if (目标名 == _root.playerAccId[_loc2_])
		{
			return _loc2_;
		}
		_loc2_ = _loc2_ + 1;
	}
	return -1;
}

_root.发动技能 = function(玩家编号, 技能号)
{
	var 目标 = _root.操控目标表[玩家编号];
	var _loc3_ = -1;
	var 技能名 = "小跳";
	if (技能号 > -1)
	{
		技能名 = _root.playerData[玩家编号][1][16 + 技能号];
	}
	var i = 0;
	while (i < _root.技能表.length)
	{
		if (技能名 == _root.技能表[i][0])
		{
			_loc3_ = i;
		}
		i++;
	}
	if (目标.hp > 0 and 目标.浮空 != true and 目标.倒地 != true and 目标.mp > _root.技能表[_loc3_][6])
	{
		目标.mp -= _root.技能表[_loc3_][6];
		主角mp显示界面.刷新显示();
		发布消息(技能名 + "！！");
		目标.技能等级 = 10;
		目标.技能名 = 技能名;
		目标.状态改变("技能");
		目标.man.gotoAndPlay(技能名);
	}
}

操控目标表 = [_root.控制目标, "", "", ""];
玩家队伍 = [false, false, false, false];
按键设定表 = [[87, 83, 65, 68, 74, 75, 82, 81, 72, 79, 76, 73], [38, 40, 37, 39, 97, 98, 99, 96, 100, 103, 101, 102], [90, 88, 67, 86, 66, 78, 77, 190, 191, 186, 222, 220], [192, 49, 50, 51, 52, 53, 54, 55, 56, 57, 48, 189]];
function getArray(str)
{
	var _loc2_ = [];
	if (str == "")
	{
		return _loc2_;
	}
	_loc2_ = str.split(",");
	return _loc2_;
}
function getArray1(str, lg)
{
	var _loc3_ = [];
	if (str == "")
	{
		return _loc3_;
	}
	var _loc4_ = "";
	var _loc5_ = str.split(",");
	i = 0;
	while (i < _loc5_.length)
	{
		_loc4_ += _loc5_[i];
		if ((i + 1) % 3 == 0)
		{
			if (i != _loc5_.length - 1)
			{
				_loc4_ += ";";
			}
		}
		else
		{
			_loc4_ += ",";
		}
		i++;
	}
	var _loc6_ = _loc4_.split(";");
	i = 0;
	while (i < lg)
	{
		_loc3_.push(_loc6_[i].split(","));
		i++;
	}
	return _loc3_;
}
function getArray11(str)
{
	var _loc2_ = [];
	if (str == "")
	{
		return _loc2_;
	}
	var _loc3_ = "";
	var _loc4_ = str.split(",");
	i = 0;
	while (i < _loc4_.length)
	{
		_loc3_ += _loc4_[i];
		if ((i + 1) % 3 == 0)
		{
			if (i != _loc4_.length - 1)
			{
				_loc3_ += ";";
			}
		}
		else
		{
			_loc3_ += ",";
		}
		i++;
	}
	var _loc5_ = _loc3_.split(";");
	i = 0;
	while (i < _loc5_.length)
	{
		_loc2_.push(_loc5_[i].split(","));
		i++;
	}
	return _loc2_;
}
function getArray2(str)
{
	var _loc2_ = [];
	var _loc3_ = [];
	if (str == "")
	{
		return _loc3_;
	}
	var _loc4_ = str.split(",");
	var _loc5_ = -1;
	var _loc6_ = 0;
	while (_loc6_ < int(_loc4_.length / 18))
	{
		_loc2_[_loc6_] = [];
		_loc6_ += 1;
	}
	var _loc7_ = 0;
	_loc6_ = 0;
	while (_loc6_ < _loc4_.length - 1)
	{
		if (_loc6_ % 18 == 0)
		{
			_loc5_ += 1;
			_loc7_ = 0;
		}
		_loc2_[_loc5_][_loc7_] = _loc4_[_loc6_];
		_loc7_ += 1;
		_loc6_ += 1;
	}
	_loc3_ = [_loc2_, _loc2_.length];
	return _loc3_;
}
System.useCodepage = false;
var starts = false;
var falgs = false;
*/

//数字化
/*
function 分析数据包(data)
{
   var _loc2_ = [];
   var _loc6_ = data.split("\n");
   _loc2_.push(_loc6_[0].split(" "));
   _loc2_[0].splice(7,0,"菜鸟");
   if(_loc2_[0][1] == "1")
   {
      _loc2_[0][1] = "男";
   }
   else
   {
      _loc2_[0][1] = "女";
   }
   _loc2_.push(_loc6_[1].split(" "));
   _loc2_[1][0] = _root.脸型库[Number(_loc2_[1][0])];
   _loc2_[1][1] = _root.发型库[Number(_loc2_[1][1])];
   var _loc5_ = 2;
   while(_loc5_ < 16)
   {
      if(_loc2_[1][_loc5_] == "-1")
      {
         _loc2_[1][_loc5_] = "";
      }
      else
      {
         _loc2_[1][_loc5_] = _root.parseXMLs2(_loc2_[1][_loc5_])[0];
      }
      _loc5_ = _loc5_ + 1;
   }
   _loc5_ = 16;
   while(_loc5_ < _loc2_[1].length)
   {
      if(_loc2_[1][_loc5_] == "-1")
      {
         _loc2_[1][_loc5_] = "";
      }
      else
      {
         _loc2_[1][_loc5_] = _root.技能表[_loc2_[1][_loc5_]][0];
      }
      _loc5_ = _loc5_ + 1;
   }
   _loc2_.push([]);
   _loc5_ = 0;
   while(_loc5_ < 40)
   {
      _loc2_[2][_loc5_] = ["空",0,0];
      _loc5_ = _loc5_ + 1;
   }
   tempArr = _loc6_[2].split("\t");
   _loc5_ = 0;
   while(_loc5_ < tempArr.length)
   {
      tempArr2 = tempArr[_loc5_].split(" ");
      temp_bbb = tempArr2[1];
      if(temp_bbb == "-1")
      {
         temp_bbb = "空";
         _loc2_[2][Number(tempArr2[0])] = [temp_bbb,tempArr2[2],0];
      }
      else
      {
         _loc2_[2][Number(tempArr2[0])] = [_root.parseXMLs2(tempArr2[1])[0],tempArr2[2],0];
      }
      _loc5_ = _loc5_ + 1;
   }
   _loc5_ = 2;
   while(_loc5_ < 13)
   {
      if(_loc2_[1][_loc5_] != "")
      {
         var _loc4_ = 0;
         while(_loc4_ < 40)
         {
            if(_loc2_[2][_loc4_][0] == _loc2_[1][_loc5_])
            {
               if(_loc2_[2][_loc4_][2] != "1")
               {
                  _loc2_[2][_loc4_][2] = "1";
                  break;
               }
               next;
            }
            _loc4_ = _loc4_ + 1;
         }
      }
      _loc5_ = _loc5_ + 1;
   }
   _loc5_ = 0;
   while(_loc5_ < 40)
   {
      _loc5_ = _loc5_ + 1;
   }
   _loc2_.push(_loc6_[3]);
   _loc2_.push([]);
   var _loc3_ = _loc6_[4].split("\r");
   _loc4_ = 0;
   _loc5_ = 0;
   while(_loc5_ < _loc3_.length - 1)
   {
      _loc3_[_loc5_] = _loc3_[_loc5_].split(" ");
      _loc3_[_loc5_][4] = _root.脸型库[Number(_loc3_[_loc5_][4])];
      _loc3_[_loc5_][5] = _root.发型库[Number(_loc3_[_loc5_][5])];
      _loc4_ = 6;
      while(_loc4_ < _loc3_[_loc5_].length - 1)
      {
         if(_loc3_[_loc5_][_loc4_] == "-1")
         {
            _loc3_[_loc5_][_loc4_] = "";
         }
         else
         {
            _loc3_[_loc5_][_loc4_] = _root.parseXMLs2(_loc3_[_loc5_][_loc4_])[0];
         }
         _loc4_ = _loc4_ + 1;
      }
      if(_loc3_[_loc5_][_loc4_] == "1")
      {
         _loc3_[_loc5_][_loc4_] = "男";
      }
      else
      {
         _loc3_[_loc5_][_loc4_] = "女";
      }
      _loc5_ = _loc5_ + 1;
   }
   _loc2_[4][0] = _loc3_;
   _loc2_[4][1] = _loc3_.length - 1;
   技能数据 = [];
   _loc5_ = 0;
   while(_loc5_ < 80)
   {
      技能数据.push(["",0,"false"]);
      _loc5_ = _loc5_ + 1;
   }
   技能数据2 = _loc6_[5].split("\t");
   _loc5_ = 0;
   while(_loc5_ < 技能数据2.length)
   {
      技能数据2[_loc5_] = 技能数据2[_loc5_].split(" ");
      if(_root.技能表[Number(技能数据2[_loc5_][0])][0] != undefined)
      {
         技能数据[_loc5_][0] = _root.技能表[Number(技能数据2[_loc5_][0])][0];
         技能数据[_loc5_][1] = 技能数据2[_loc5_][1];
         _loc4_ = 16;
         while(_loc4_ < 22)
         {
            if(技能数据[_loc5_][0] == _loc2_[1][_loc4_])
            {
               技能数据[_loc5_][2] = "true";
               break;
            }
            _loc4_ = _loc4_ + 1;
         }
      }
      _loc5_ = _loc5_ + 1;
   }
   _loc2_.push(技能数据);
   _loc2_.push([]);
   _loc5_ = 0;
   while(_loc5_ < _root.仓库栏总数)
   {
      _loc2_[6][_loc5_] = ["空",0,0];
      _loc5_ = _loc5_ + 1;
   }
   tempArr = _loc6_[6].split("\t");
   _loc5_ = 0;
   while(_loc5_ < tempArr.length)
   {
      tempArr2 = tempArr[_loc5_].split(" ");
      temp_bbb = tempArr2[1];
      if(temp_bbb == "-1")
      {
         temp_bbb = "空";
         _loc2_[6][Number(tempArr2[0])] = [temp_bbb,tempArr2[2],0];
      }
      else
      {
         _loc2_[6][Number(tempArr2[0])] = [_root.parseXMLs2(tempArr2[1])[0],tempArr2[2],0];
      }
      _loc5_ = _loc5_ + 1;
   }
   return _loc2_;
}
*/

//名字生成
/*
function 随机名字库初始化()
{
   男性名字库 = 男性名字.split(",");
   女性名字库 = 女性名字.split(",");
}
function 根据性别获得随机名字(性别)
{
   var _loc1_ = "";
   if(性别 == "女")
   {
      _loc1_ = 女性名字库[random(女性名字库.length)];
   }
   else
   {
      _loc1_ = 男性名字库[random(男性名字库.length)];
   }
   return _loc1_;
}
男性名字 = "Abe,Abel,Abner,Abraham,Allen,Adam,Adolf,Albin,Alden,Alexis,Ambrose,Amos,Adrian,Al,Albert,Alexander,Alfred,Alistair,Alvin,Andrew,Andy,Anselm,Anthony,Antony,Angus,Archibald,Archie,Arnold,Arthur,Augustin,Augustus,Auberon,Aubrey,Baldwin,Bertran,Bryan,Barnaby,Barry,Bartholomew,Basil,Ben,Benjamin,Bernard,Bernie,Bert,Bill,Billy,Bob,Bobby,Boris,Bradford,Brad,Brandon,Brendan,Brian,Bruce,Bud,Burt,Caesar,Calvin,Carlton,Cary,Christian,Carl,Cecil,Cedric,Charles,Charlie,Chuck,Christopher,Chris,Clarence,Clark,Claude,Clement,Clare,Constant,Curtis,Clifford,Cliff,Clint,Clive,Clyde,Colin,Craig,Curt,Cyril,Cuthbert,Dexter,Derby,Dale,Daniel,Dan,Danny,Darrell,Darren,David,Dave,Dean,Dennis,Derek,Dermot,Desmond,Des,Dick,Dirk,Dominic,Donald,Don,Douglas,Doug,Duane,Dudley,Dud,Duncan,Dustin,Dwight,Duke,Earl,Ebenezer,Eamonn,Ed,Edgar,Edmund,Edward,Edwin,Eliot,Elmer,Elroy,Emlyn,Enoch,Eric,Ernest,Errol,Eugene,Eli,Enos,Freddie,Felix,Ferdinand,Fergus,Floyd,Francis,Frank,Frankie,Frederick,Fred,Gaston,Gabriel,Gareth,Gary,Gavin,Gene,Geoffrey,Geoff,George,Geraint,Gerald,Gerry,Gerard,Gilbert,Giles,Glen,Godfrey,Gordon,Graham,Graeme,Gregory,Greg,Guy,Gideon,Grant,Humphry,Hal,Hank,Harold,Harry,Henry,Herbert,Horace,Howard,Hubert,Hugh,Hamilton,Hector,Heman,Hugo,Herman,Hilary,Howell,Hugh,Humphrey,Hiram,Homer,Ian,Isaac,Ivan,Ivor,Ira,Irving,Irwin,Jarvis,Jean,Job,Jack,Jacob,Jake,James,Jamie,Jason,Jasper,Jed,Jeff,Jeffrey,Jeremy,Jerome,Jerry,Jesse,Jessy,Jim,Jimmy,Jock,Joe,John,Johnny,Jonathan,Jon,Joseph,Joshua,Julian,Justin,Julius,Karl,Kay,Keith,Ken,Kenneth,Kenny,Kent,Kevin,Kit,Kev,Kirk,Laban,Lee,Lance,Larry,Laurence,Len,Lenny,Leo,Leonard,Les,Leslie,Lester,Lew,Leon,Lincoln,Lewis,Liam,Lionel,Lou,Louis,Luke,Lucius,Luman,Lynn,Malcolm,Mark,Martin,Malachi,Marshall,Marvin,Marty,Matt,Mattew,Matlhew,Milton,Monroe,Maurice,Max,Mervyn,Michael,Mick,Micky,Miles,Mike,Mitch,Mitchell,Morris,Mort,Murray,Morgan,Montgomery,Na\'amai,Nat,Nathan,Nahum,Napoleon,Nelson,Newton,Noah,Norbert,Nathaniel,Neal,Ned,Neddy,Nicholas,Nick,Nicky,Nigel,Noel,Norm,Norman,Ollie,Oliver,Oscar,Oswald,Owen,Oz,Ozzie,Octavius,Osmond,Otto,Paddy,Pat,Patrick,Paul,Percy,Pete,Peter,Phil,Philip,Padraic,Pearce,Perry,Philander,Philemen,Pius,Quentin,Quincy,Rene,Reuben,Ralph,Randolf,Randy,Raphael,Ray,Raymond,Reg,Reginald,Rex,Richard,Richie,Rick,Ricky,Rob,Robbie,Robby,Robert,Robin,Rod,Roderick,Rodney,Rodge,Roger,Ronald,Ron,Ronnie,Rory,Roy,Rudolph,Rufus,Rupert,Russ,Reuel,Reynold,Roland,Ross,Russell,Samson,Saul,Sam,Sammy,Samuel,Sandy,Scott,Seamas,Sean,Seb,Sebastian,Sid,Sidney,Simon,Stan,Stanley,Steve,Steven,Stewart,Sinclair,Solomon,Stuart,Ted,Teddy,Tel,Terence,Terry,Theo,Theodore,Thomas,Tim,Timmy,Timothy,Toby,Tom,Tommy,Tony,Theobald,Theodoric,Terence,Trevor,Troy,Urban,Van,Vivian,Vic,Victor,Vince,Vincent,Viv,Wallace,Wally,Walter,Warren,Wayne,Wesley,Winston,Will,Wilbur,Wilfred,Willy,William,Willis";
女性名字 = "Abigail,Ada,Agatha,Adelaide,Adelina,Alethea,Aggie,Agnes,Aileen,Alex,Alexandra,Alexis,Alice,Alison,Amanda,Amy,Angela,Angie,Anita,Anne,Anna,Annabel,Annie,Annette,Anthea,Antonia,Audrey,Allson,Alma,Althea,Angelica,Aspasia,Aurelian,Ava,Avis,Beata,Belle,Babs,Barbara,Beatrice,Becky,Belinda,Bernadette,Beryl,Betty,Bid,Brenda,Bridget,Brittany,Bertha,Bonny,Camilla,Candice,Carla,Carol,Caroline,Carrie,Catherine,Cathy,Cecilia,Cecily,Celia,Charlene,Charlotte,Cherry,Cheryl,Chloe,Chris,Chrissie,Christina,Christine,Cindy,Clare,Claudia,Cleo,Connie,Constance,Crystal,Candida,Carmen,Celestine,Charissa,Colleen,Cora,Corinna,Cynthia,Dulcie,Dottie,Daisy,Daphne,Dawn,Deb,Debby,Deborah,Deirdre,Delia,Della,Denise,Di,Diana,Diane,Dolly,Donna,Dora,Doreen,Doris,Dorothy,Dot,Elva,Edith,Edna,Eileen,Elaine,Eleanor,Eleanora,Eliza,Elizabeth,Ella,Ellen,Ellie,Elsa,Elsie,Elspeth,Emily,Emma,Erica,Ethel,Eunice,Eva,Eve,Evelyn,Eugenia,Eulalia,Evadne,Evangeline,Faustina,Fay,Felicity,Fidelia,Fiona,Flo,Flora,Florence,Felicia,Flavia,Frieda,Freda,Florrie,Fran,Frances,Frankie,Gene,Georgia,Georgie,Georgina,Geraldine,Germaine,Gertie,Gertrude,Gill,Gillian,Ginny,Gladys,Glenda,Gloria,Grace,Gracie,Ashley,Gwen,Gwendoline,Hannah,Harriet,Hazel,Heather,Helen,Henrietta,Hilary,Hilda,Hedda,Hedwig,Helga,Hortensia,Isabella,Ivy,Ida,Ingrid,Irene,Iris,Isabel,Jemima,Juliana,Jan,Jane,Janet,Janey,Janice,Jackie,Jacqueline,Jean,Jeanie,Jennifer,Jenny,Jess,Jessica,Jessie,Jill,Jo,Joan,Joanna,Joanne,Jocelyn,Josephine,Josie,Jode,Joyce,Judith,Judy,Julia,Julie,Juliet,June,Karen,Kathleen,Kate,Kathy,Katie,Kay,Kelly,Kim,Kimberly,Kirsten,Kitty,Katharine,Kit,Leila,Laura,Lauretta,Lesley,Libby,Lilian,Lily,Linda,Lindsay,Lisa,Livia,Liz,Lois,Lori,Lorna,Louisa,Louise,Lucia,Lucinda,Lucy,Lydia,Lynn,Leslie,Lucile,LuLu,Mabel,Madeleine,Madge,Maggie,Maisie,Mandy,Marcia,Marcie,Margaret,Margery,Maria,Marian,Mary,Marilyn,Marlene,Martha,Melanie,Mercedes,Mignon,Mimi,Martha,Martina,Mary,Maud,Maureen,Mavis,Meg,Melanie,Melinda,Melissa,Michelle,Mildred,Millicent,Millie,Miranda,Miriam,Moira,Molly,Monica,Muriel,Minnie,Nadine,Nina,Nadia,Nan,Nancy,Naomi,Natalie,Natasha,Nell,Nellie,Nicky,Nicola,Nicole,Nora,Norma,Nita,Olga,Olympia,Olive,Olivia,Pam,Pamela,Pat,Patience,Pancy,Persis,Prudence,Patricia,Patsy,Patti,Paula,Pauline,Pearl,Peggie,Penelope,Penny,Philippa,Phoebe,Phyllis,Poll,Polly,Priscilla,Pru,Renee,Rachel,Rebecca,Rhoda,Rita,Roberta,Robin,Rosalie,Rosalind,Rosalyn,Rose,Rosemary,Rosie,Ruby,Rosa,Ruth,Salome,Sylvia,Sadie,Sal,Sally,Sam,Samantha,Sandra,Sandy,Sara,Sharon,Sheila,Sherry,Shirley,Sibyl,Silvia,Sonia,Sophia,Sophronia,Sophie,Stella,Stephanie,Susan,Susanna,Sue,Susie,Suzanne,Tabitha,Teresa,Terri,Tess,Tessa,Thelma,Tina,Thalia,Thea,Thirza,Toni,Tracy,Tricia,Trudie,Uerica,Una,Undine,Ursula,Urania,Vivian,Vivien,Val,Valerie,Vanessa,Vera,Veronica,Vicky,Victoria,Viola,Violet,Virginia,Viv,Willa,Wendy,Winifred,Winnie,Yvonne,Zoe";
男性名字库 = [];
女性名字库 = [];
随机名字库初始化();
*/

//在线判断
/*
function 连接测试失败()
{
	if (重新连接 == false)
	{
		_root.前状态 = _root.暂停;
		重新连接 = true;
		_root.暂停 = true;
	}
	_root.连接面板._visible = true;
	clearInterval(连接定时器);
	连接定时器 = setInterval(_root.连接检测, 30000);
}
function 连接测试成功()
{
	if (重新连接 == true)
	{
		if (_root.前状态 == false)
		{
			_root.暂停 = false;
		}
		重新连接 = false;
	}
	_root.连接面板._visible = false;
	clearInterval(连接定时器);
	连接定时器 = setInterval(_root.连接检测, 循环运行毫秒数);
}
function 连接检测()
{
	本地loadgame = SharedObject.getLocal("crazyflasher7_saves");
	temp_task = 本地loadgame.data[存盘名][3];
	if (_root.是否允许5分钟连接 == false)
	{
		return undefined;
	}
	_root.防沉迷连接次数++;
	_root.防沉迷界面.防沉迷体力槽.刷新();
	在线时间 = _root.防沉迷连接次数 * 5;
	if (在线时间 == 10 and temp_task > 28)
	{
		_root.奖励10分钟._visible = 1;
	}
	else if (在线时间 == 20 and temp_task > 28)
	{
		_root.奖励20分钟._visible = 1;
	}
	else if (在线时间 == 40 and temp_task > 28)
	{
		_root.奖励40分钟._visible = 1;
	}
	else if (在线时间 == 60 and temp_task > 28)
	{
		_root.奖励60分钟._visible = 1;
	}
	else if (在线时间 == 120 and temp_task > 28)
	{
		_root.奖励120分钟._visible = 1;
	}
	_root.连接测试成功();
}
function 停止在线检测()
{
	clearInterval(连接定时器);
	_root.是否允许5分钟连接 = false;
}
function 多玩家exitlogin(accId)
{
}
function exitlogin2()
{
	return "游戏已退出登录。";
}
function 连接保持初始化()
{
	连接检测();
	clearInterval(连接定时器);
	连接定时器 = setInterval(_root.连接检测, 循环运行毫秒数);
}
function exitlogin()
{
	return "游戏已退出登录。";
}
健康游戏时间 = 180;
循环运行毫秒数 = 300000;
_root.防沉迷连接次数 = 0;
_root.防沉迷限制 = false;
前状态 = _root.暂停;
重新连接 = false;
_root.是否允许5分钟连接 = true;
var methodName = "exitlogin";
var instance = null;
var method = exitlogin;
var ws = flash.external.ExternalInterface.addCallback(methodName, instance, method);
var methodName2 = "exitlogin2";
var method2 = exitlogin2;
var ws2 = flash.external.ExternalInterface.addCallback(methodName2, method2);
连接保持初始化();
*/

//多人UI
/*
function 排列显示多人UI()
{
   var _loc2_ = 0;
   while(_loc2_ < 4)
   {
      _root["多人UI_" + _loc2_]._visible = false;
      if(_root.playerData[_loc2_] != "" and _root.playerData[_loc2_].length > 0 and _root.playerData[_loc2_] != undefined)
      {
         _root["多人UI_" + _loc2_].启动多人UI("玩家" + _loc2_);
         if(_root.playerName[_loc2_] != _root.控制目标)
         {
            _root["多人UI_" + _loc2_]._visible = true;
         }
      }
      _loc2_ = _loc2_ + 1;
   }
}
*/

//组装数据包
/*
function 查找技能(name)
{
   var _loc2_ = 0;
   while(_loc2_ < _root.技能表.length)
   {
      if(name == _root.技能表[_loc2_][0])
      {
         return _loc2_;
      }
      _loc2_ = _loc2_ + 1;
   }
   return -1;
}
function 查找脸型(name)
{
   var _loc2_ = 0;
   while(_loc2_ < _root.脸型库.length)
   {
      if(_root.脸型库[_loc2_] == name)
      {
         return _loc2_;
      }
      _loc2_ = _loc2_ + 1;
   }
   return undefined;
}
function 查找发型(name)
{
   var _loc2_ = 0;
   while(_loc2_ < _root.发型库.length)
   {
      if(_root.发型库[_loc2_] == name)
      {
         return _loc2_;
      }
      _loc2_ = _loc2_ + 1;
   }
   return undefined;
}
function 组装数据包(data2, n, 比较数据)
{
   var _loc2_ = data2.slice();
   数据包 = "";
   if(n == 0)
   {
      if(_loc2_[1] == "男")
      {
         _loc2_[1] = 1;
      }
      else if(_loc2_[1] == "女")
      {
         _loc2_[1] = 0;
      }
      _loc2_.splice(7,1);
      数据包 += _loc2_.join(" ");
      return 数据包;
   }
   if(n == 1)
   {
      _loc2_[0] = _root.查找脸型(_loc2_[0]);
      _loc2_[1] = _root.查找发型(_loc2_[1]);
      var _loc3_ = 2;
      while(_loc3_ < 16)
      {
         _loc2_[_loc3_] = _root.parseXMLs3(_loc2_[_loc3_]);
         if(_loc2_[_loc3_] == undefined)
         {
            _loc2_[_loc3_] = -1;
         }
         _loc3_ = _loc3_ + 1;
      }
      _loc3_ = 16;
      while(_loc3_ < 22)
      {
         _loc2_[_loc3_] = _root.查找技能(_loc2_[_loc3_]);
         _loc3_ = _loc3_ + 1;
      }
      数据包 += _loc2_.join(" ");
      return 数据包;
   }
   var _loc8_ = false;
   if(n == 2)
   {
      var _loc6_ = [];
      _loc3_ = 0;
      while(_loc3_ < 比较数据[2].split(",").length / 3)
      {
         _loc6_[_loc3_] = [];
         _loc3_ = _loc3_ + 1;
      }
      var _loc9_ = 0;
      _loc3_ = 0;
      while(_loc3_ < 比较数据[2].split(",").length)
      {
         _loc6_[_loc9_].push(比较数据[2].split(",")[_loc3_]);
         if((_loc3_ + 1) % 3 == 0)
         {
            _loc9_ = _loc9_ + 1;
         }
         _loc3_ = _loc3_ + 1;
      }
      _loc3_ = 0;
      while(_loc3_ < 40)
      {
         if("" + _loc6_[_loc3_] != "" + _loc2_[_loc3_])
         {
            if(_loc8_)
            {
               数据包 += "\t";
            }
            else
            {
               _loc8_ = true;
            }
            tmp_aaa = _root.parseXMLs3(_loc2_[_loc3_][0]);
            if(tmp_aaa == undefined)
            {
               tmp_aaa = -1;
            }
            if(_loc2_[_loc3_][1] == undefined)
            {
               _loc2_[_loc3_][1] = -1;
            }
            数据包 += _loc3_ + " " + tmp_aaa + " " + _loc2_[_loc3_][1];
            if("" + _loc6_[_loc3_] == "" + _loc2_[_loc3_])
            {
            }
         }
         _loc3_ = _loc3_ + 1;
      }
      return 数据包;
   }
   if(n == 3)
   {
      数据包 += data2;
      return 数据包;
   }
   if(n == 4)
   {
      _loc2_ = [[],data2[1]];
      _loc3_ = 0;
      while(_loc3_ < Number(data2[1]))
      {
         _loc2_[0].push(_root.同伴数据[_loc3_].slice());
         _loc3_ = _loc3_ + 1;
      }
      var _loc7_ = [];
      _loc3_ = 0;
      while(_loc3_ < Number(_loc2_[1]))
      {
         _loc7_[_loc3_] = _loc2_[0][_loc3_][2];
         _loc2_[0][_loc3_][4] = _root.查找脸型(_loc2_[0][_loc3_][4]);
         _loc2_[0][_loc3_][5] = _root.查找发型(_loc2_[0][_loc3_][5]);
         var _loc4_ = 6;
         while(_loc4_ < 17)
         {
            _loc2_[0][_loc3_][_loc4_] = _root.parseXMLs3(_loc2_[0][_loc3_][_loc4_]);
            if(_loc2_[0][_loc3_][_loc4_] == undefined)
            {
               _loc2_[0][_loc3_][_loc4_] = -1;
            }
            _loc4_ = _loc4_ + 1;
         }
         if(_loc2_[0][_loc3_][17] == "男")
         {
            _loc2_[0][_loc3_][17] = 1;
         }
         else
         {
            _loc2_[0][_loc3_][17] = 0;
         }
         _loc3_ = _loc3_ + 1;
      }
      _loc4_ = 0;
      while(_loc4_ < 3)
      {
         if(_loc7_.length > _loc4_)
         {
            if(_loc7_[_loc4_] != undefined)
            {
               数据包 += _loc7_[_loc4_];
            }
            else
            {
               数据包 += "0";
            }
         }
         else
         {
            数据包 += "0";
         }
         if(_loc4_ != 2)
         {
            数据包 += "\t";
         }
         _loc4_ = _loc4_ + 1;
      }
      return 数据包;
   }
   if(n == 5)
   {
      _loc8_ = false;
      _loc3_ = 0;
      while(_loc3_ < 80)
      {
         if(_loc2_[_loc3_][0] != "")
         {
            if(_loc8_)
            {
               数据包 += "\t";
            }
            else
            {
               _loc8_ = true;
            }
            数据包 += _root.查找技能(_loc2_[_loc3_][0]) + " " + _loc2_[_loc3_][1];
         }
         _loc3_ = _loc3_ + 1;
      }
      return 数据包;
   }
   _loc8_ = false;
   if(n == 6)
   {
      _loc6_ = [];
      _loc3_ = 0;
      while(_loc3_ < 比较数据[6].split(",").length / 3)
      {
         _loc6_[_loc3_] = [];
         _loc3_ = _loc3_ + 1;
      }
      _loc9_ = 0;
      _loc3_ = 0;
      while(_loc3_ < 比较数据[6].split(",").length)
      {
         _loc6_[_loc9_].push(比较数据[6].split(",")[_loc3_]);
         if((_loc3_ + 1) % 3 == 0)
         {
            _loc9_ = _loc9_ + 1;
         }
         _loc3_ = _loc3_ + 1;
      }
      _loc3_ = 0;
      while(_loc3_ < _root.仓库栏总数)
      {
         if("" + _loc6_[_loc3_] != "" + _loc2_[_loc3_])
         {
            if(_loc8_)
            {
               数据包 += "\t";
            }
            else
            {
               _loc8_ = true;
            }
            tmp_aaa = _root.parseXMLs3(_loc2_[_loc3_][0]);
            if(tmp_aaa == undefined)
            {
               tmp_aaa = -1;
            }
            数据包 += _loc3_ + " " + tmp_aaa + " " + _loc2_[_loc3_][1];
            if("" + _loc6_[_loc3_] == "" + _loc2_[_loc3_])
            {
            }
         }
         _loc3_ = _loc3_ + 1;
      }
      return 数据包;
   }
   return "";
}
*/

//鼠标控制移动
/*
function 鼠标控制移动()
{
   if(_root.全鼠标控制 == true)
   {
      _root.控制目标全自动 = false;
      _root.gameworld鼠标横向位置 = _root.gameworld._xmouse;
      _root.gameworld鼠标纵向位置 = _root.gameworld._ymouse;
      _root.效果("鼠标控制移动效果",_root.gameworld._xmouse,_root.gameworld._ymouse,100);
      _root.gameworld[_root.控制目标].命令 = "停止";
   }
}
*/
