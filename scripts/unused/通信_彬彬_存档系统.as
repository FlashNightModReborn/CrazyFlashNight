_root.存档数据处理 = function()
{
	_root.身价 = _root.基础身价值 * _root.等级;
	主角储存数据 = [_root.角色名, _root.性别, _root.金钱, _root.等级, _root.经验值, _root.身高, _root.技能点数, "空白", _root.身价, _root.虚拟币, [], _root.Difficulty_Mode];
	装备储存数据 = [_root.脸型, _root.发型, _root.头部装备, _root.上装装备, _root.手部装备, _root.下装装备, _root.脚部装备, _root.颈部装备, _root.长枪, _root.手枪, _root.手枪2, _root.刀, _root.手雷, _root.快捷物品栏1, _root.快捷物品栏2, _root.快捷物品栏3, _root.快捷技能栏1, _root.快捷技能栏2, _root.快捷技能栏3, _root.快捷技能栏4, _root.快捷技能栏5, _root.快捷技能栏6, _root.快捷技能栏7, _root.快捷技能栏8, _root.快捷技能栏9, _root.快捷技能栏10, _root.快捷技能栏11, _root.快捷技能栏12];
	主角技能表储存数据 = _root.主角技能表;
	物品储存数据 = _root.物品栏;
	同伴储存数据 = [_root.同伴数据, _root.同伴数];
	任务储存数据 = _root.主线任务进度;
	仓库储存数据 = _root.仓库栏;
	_root.存档数据 = [主角储存数据, 装备储存数据, 物品储存数据, 任务储存数据, 同伴储存数据, 主角技能表储存数据, 仓库储存数据];
};

_root.存盘 = function()
{
	_root.数字化存档 = "难度" + _root.Difficulty_Mode;
	_root.存档数据处理();

	var _loc2_ = new LoadVars();
	var _loc3_ = "http://127.0.0.1:1225/crazyflashercom/k5_saveplaydata.action?k=" + random(100);
	var _loc4_ = ["", "", "", ""];
	var _loc5_ = "";
	_root.lastsave2 = "";

	_loc4_[0] = _root.存档数字化(_root.存档数据, _root.lastsave2);

	_loc2_.recive = Encrypt.加密(_root.生成key(), _loc4_[0] + "");

	_loc2_.accId = "1002";
	_loc2_.sendAndLoad(_loc3_,_loc2_,"POST");
};


_root.读盘 = function()
{
	var _loc2_ = [];
	var _loc3_ = "http://127.0.0.1:1225/crazyflashercom/k5_readplaydata.action?k=" + random(100);
	var userDatarecieve = new LoadVars();
	userDatarecieve.userName = _root.游戏ID组[_root.服务器大区代号];
	userDatarecieve.sendAndLoad(_loc3_,userDatarecieve,"POST");
	userDatarecieve.onLoad = function(b)
	{
		if (b)
		{
			_root.游戏服务器无存盘 = false;
			_root.发布消息("游戏服务器读取成功！");
			s = Encrypt.解密(_root.生成key(), userDatarecieve.content.split(unescape("%20")).join("+"));
			_root.mydata = _root.数字化拆分(s);
			falgs = true;
			_root.codesigninfo = userDatarecieve.newsign.split(unescape("%20")).join("+");
			_root.gotoAndPlay("读取数据成功");
			starts = true;
			_root.键值设定 = [[_root.获得翻译("上键"), "上键", 87], [_root.获得翻译("下键"), "下键", 83], [_root.获得翻译("左键"), "左键", 65], [_root.获得翻译("右键"), "右键", 68], [_root.获得翻译("功能键A"), "A键", 74], [_root.获得翻译("功能键B"), "B键", 75], [_root.获得翻译("功能键C"), "C键", 82], [_root.获得翻译("攻击模式-空手"), "键1", 49], [_root.获得翻译("攻击模式-兵器"), "键2", 50], [_root.获得翻译("攻击模式-手枪"), "键3", 51], [_root.获得翻译("攻击模式-长枪"), "键4", 52], [_root.获得翻译("攻击模式-手雷"), "键5", 53], [_root.获得翻译("快捷物品栏1"), "快捷物品栏键1", 55], [_root.获得翻译("快捷物品栏2"), "快捷物品栏键2", 56], [_root.获得翻译("快捷物品栏3"), "快捷物品栏键3", 57], [_root.获得翻译("快捷技能栏1"), "快捷技能栏键1", 32], [_root.获得翻译("快捷技能栏2"), "快捷技能栏键2", 85], [_root.获得翻译("快捷技能栏3"), "快捷技能栏键3", 73], [_root.获得翻译("快捷技能栏4"), "快捷技能栏键4", 79], [_root.获得翻译("快捷技能栏5"), "快捷技能栏键5", 80], [_root.获得翻译("快捷技能栏6"), "快捷技能栏键6", 76], [_root.获得翻译("快捷技能栏7"), "快捷技能栏键7", 72], [_root.获得翻译("快捷技能栏8"), "快捷技能栏键8", 71], [_root.获得翻译("快捷技能栏9"), "快捷技能栏键9", 67], [_root.获得翻译("快捷技能栏10"), "快捷技能栏键10", 66], [_root.获得翻译("快捷技能栏11"), "快捷技能栏键11", 78], [_root.获得翻译("快捷技能栏12"), "快捷技能栏键12", 77], [_root.获得翻译("切换武器键"), "切换武器键", 81]];
		}
	};
};