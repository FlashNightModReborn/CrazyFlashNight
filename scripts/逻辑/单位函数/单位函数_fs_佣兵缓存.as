import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.写入装备缓存 = function()
{
	// 统一装备字段列表
	var equipmentFields = [
		"面具", "身体", "上臂", "左下臂", "右下臂", "左手", "右手",
		"屁股", "左大腿", "右大腿", "小腿", "脚",
		"刀_装扮", "长枪_装扮", "手枪_装扮", "手枪2_装扮", "手雷_装扮"
	];

	// 缓存主角装备
	var hero:MovieClip = TargetCacheManager.findHero();
	var heroCache:Object = [];
	for (var i:Number = 0; i < equipmentFields.length; i++) {
		heroCache.push(hero[equipmentFields[i]]);
	}
	_root.玩家装备缓存 = heroCache;
	_root.玩家缓存状态 = true;

	// 初始化同伴装备缓存与状态
	_root.同伴装备缓存 = [[], [], [], []];
	_root.同伴缓存状态 = [false, false, false, false];

	// 缓存同伴数据
	for (var index:Number = 0; index < _root.同伴数; index++) {
		var fellowName:String = "同伴" + index;
		var fellow:MovieClip = _root.gameworld[fellowName];
		if (fellow.hp > 0) {
			// 缓存战斗状态
			_root.场景转换_同伴hp[index] = fellow.hp;
			_root.场景转换_同伴mp[index] = fellow.mp;
			_root.场景转换_同伴攻击模式[index] = fellow.攻击模式;

			// 缓存装备
			var fellowCache:Array = [];
			for (var j:Number = 0; j < equipmentFields.length; j++) {
				fellowCache.push(fellow[equipmentFields[j]]);
			}
			_root.同伴装备缓存[index] = fellowCache;
			_root.同伴缓存状态[index] = true;
		}
	}
};


_root.玩家装备缓存 = [];
_root.同伴装备缓存 = [[],[],[],[]];
_root.玩家缓存状态 = false;
_root.同伴缓存状态 = [false,false,false,false];
