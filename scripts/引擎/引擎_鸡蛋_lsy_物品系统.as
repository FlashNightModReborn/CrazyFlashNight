_root.根据装备名获得装备id = function(物品名)
{
	return _root.物品属性列表[物品名].id;
}

_root.根据物品名查找物品id = function(物品名)
{
	return _root.物品属性列表[物品名].id;
}

_root.根据物品名查找属性 = function(物品名, 属性号)
{
	return 根据物品名查找全部属性(物品名)[属性号];
}

_root.根据物品名查找全部属性 = function(物品名)
{
	var 物品 = new Array();
	var _loc4_ = _root.物品属性列表[物品名];
	物品[0] = 物品名;
	物品[1] = _loc4_.icon == undefined ? "" : _loc4_.icon;
	物品[2] = _loc4_.type == undefined ? "" : _loc4_.type;
	物品[3] = _loc4_.use == undefined ? "" : _loc4_.use;
	物品[4] = _loc4_.weight == undefined ? 0 : _loc4_.weight;
	物品[5] = _loc4_.price == undefined ? 0 : _loc4_.price;
	物品[6] = _loc4_.description == undefined ? "" : _loc4_.description;
	物品[7] = _loc4_.data.friend == undefined ? 0 : _loc4_.data.friend;
	物品[8] = _loc4_.equipped.defence == undefined ? 0 : _loc4_.equipped.defence;
	物品[9] = _loc4_.level == undefined ? 0 : _loc4_.level;
	if (_loc4_.use == "药剂")
	{
		物品[10] = _loc4_.data.affecthp == undefined ? 0 : _loc4_.data.affecthp;
		物品[11] = _loc4_.data.affectmp == undefined ? 0 : _loc4_.data.affectmp;
	}
	else
	{
		物品[10] = _loc4_.equipped.hp == undefined ? 0 : _loc4_.equipped.hp;
		物品[11] = _loc4_.equipped.mp == undefined ? 0 : _loc4_.equipped.mp;
	}
	物品[12] = _loc4_.equipped.bullet == undefined ? 0 : _loc4_.equipped.bullet;
	switch (_loc4_.use)
	{
		case "长枪" :
		case "手枪" :
		case "手雷" :
			物品[13] = 0;
			物品[14] = [_loc4_.data.capacity == undefined ? 0 : _loc4_.data.capacity, _loc4_.data.split == undefined ? 0 : _loc4_.data.split, _loc4_.data.diffusion == undefined ? 0 : _loc4_.data.diffusion, _loc4_.data.singleshoot == undefined ? 0 : _loc4_.data.singleshoot, false, _loc4_.data.interval == undefined ? 0 : _loc4_.data.interval, _loc4_.data.velocity == undefined ? 0 : _loc4_.data.velocity, _loc4_.data.bullet == undefined ? 0 : _loc4_.data.bullet, _loc4_.data.sound == undefined ? 0 : _loc4_.data.sound, _loc4_.data.muzzle == undefined ? 0 : _loc4_.data.muzzle, _loc4_.data.bullethit == undefined ? 0 : _loc4_.data.bullethit, _loc4_.data.clipname == undefined ? 0 : _loc4_.data.clipname, _loc4_.data.bulletsize == undefined ? 0 : _loc4_.data.bulletsize, _loc4_.data.power == undefined ? 0 : _loc4_.data.power, _loc4_.data.impact == undefined ? 0 : _loc4_.data.impact];
			break;
		case "刀" :
			物品[13] = _loc4_.data.power;
			物品[14] = [0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
			break;
		case "颈部装备" :
			物品[13] = 0;
			物品[14] = [_loc4_.equipped.title == undefined ? 0 : _loc4_.equipped.title, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
			break;
		default :
			物品[13] = _loc4_.equipped.damage == undefined ? 0 : _loc4_.equipped.damage;
			物品[14] = [0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
	}
	物品[15] = _loc4_.equipped.dressup == undefined ? "" : _loc4_.equipped.dressup;
	物品[16] = _loc4_.equipped.punch == undefined ? 0 : _loc4_.equipped.punch;
	物品[17] = _loc4_.equipped.balance == undefined ? 0 : _loc4_.equipped.balance;
	物品[18] = _loc4_.equipped.hitAccuracy == undefined ? 0 : _loc4_.equipped.hitAccuracy;
	物品[19] = _loc4_.equipped.dodgeAbility == undefined ? 0 : _loc4_.equipped.dodgeAbility;
	return 物品;
}

_root.parseXMLs2 = function(物品id)
{
	return _root.根据物品名查找全部属性(_root.id物品名对应表[物品id]);
}

_root.parseXMLs3 = function(物品名)
{
	if (物品名 != "")
	{
		return _root.根据装备名获得装备id(物品名);
	}
	return undefined;
}


_root.强化计算 = function(初始值, 强化等级)
{
	if (初始值 != undefined and 强化等级 != undefined and 强化等级 <= 13)
	{
		return Math.floor(初始值 * (1 + (强化等级 - 1) * (强化等级 - 1) / 100 + 0.05 * (强化等级 - 1)));
	}
	if (初始值 != undefined and 初始值 != NaN)
	{
		return 初始值;
	}
	return 1;
}

_root.getArr = function(str)
{
   if(str == "")
   {
      return [];
   }
   return str.split(",");
}


_root.物品栏总数 = 50;
_root.仓库栏基本总数 = 1240;
_root.仓库栏总数 = 1240;
// _root.仓库页数 = 1;
// _root.暂存仓库页数 = 1;
// _root.暂存后勤战备箱页数 = 31;
// _root.仓库名称 = "仓库";
// _root.仓库显示页数 = 仓库页数;


//新函数
_root.singleSubmit = function(name,value):Boolean{
	return org.flashNight.arki.item.ItemUtil.singleSubmit(name,value);
}

_root.singleAcquire = function(name,value):Boolean{
	return org.flashNight.arki.item.ItemUtil.singleAcquire(name,value);
}
