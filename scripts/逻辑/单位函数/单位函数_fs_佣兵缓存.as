_root.写入装备缓存 = function()
{
	_root.玩家装备缓存 = [];
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].面具);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].身体);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].上臂);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].左下臂);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].右下臂);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].左手);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].右手);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].屁股);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].左大腿);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].右大腿);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].小腿);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].脚);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].刀_装扮);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].长枪_装扮);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].手枪_装扮);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].手枪2_装扮);
	_root.玩家装备缓存.push(_root.gameworld[_root.控制目标].手雷_装扮);
	_root.玩家缓存状态 = true;
	_root.同伴装备缓存 = [[], [], [], []];
	_root.同伴缓存状态 = [];
	_root.同伴缓存状态[0] = false;
	_root.同伴缓存状态[1] = false;
	_root.同伴缓存状态[2] = false;
	_root.同伴缓存状态[3] = false;
	var _loc2_ = 0;
	while (_loc2_ < _root.同伴数)
	{
		if (_root.gameworld["同伴" + _loc2_].hp > 0)
		{
			_root.场景转换_同伴hp[_loc2_] = _root.gameworld["同伴" + _loc2_].hp;
			_root.场景转换_同伴mp[_loc2_] = _root.gameworld["同伴" + _loc2_].mp;
			_root.场景转换_同伴攻击模式[_loc2_] = _root.gameworld["同伴" + _loc2_].攻击模式;
			_root.同伴装备缓存[_loc2_] = [];
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].面具);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].身体);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].上臂);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].左下臂);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].右下臂);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].左手);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].右手);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].屁股);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].左大腿);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].右大腿);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].小腿);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].脚);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].刀_装扮);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].长枪_装扮);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].手枪_装扮);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].手枪2_装扮);
			_root.同伴装备缓存[_loc2_].push(_root.gameworld["同伴" + _loc2_].手雷_装扮);
			_root.同伴缓存状态[_loc2_] = true;
		}
		_loc2_ = _loc2_ + 1;
	}
};

_root.玩家装备缓存 = [];
_root.同伴装备缓存 = [[],[],[],[]];
_root.玩家缓存状态 = false;
_root.同伴缓存状态 = [false,false,false,false];
