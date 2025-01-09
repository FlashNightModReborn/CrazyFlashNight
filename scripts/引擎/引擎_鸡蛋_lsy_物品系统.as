_root.根据装备名获得装备id = function(物品名){
	return _root.物品属性列表[物品名].id;
}

_root.根据物品名查找物品id = function(物品名){
	return _root.物品属性列表[物品名].id;
}

_root.根据物品名查找属性 = function(物品名, 属性号){
	return 根据物品名查找全部属性(物品名)[属性号];
}

_root.根据物品名查找全部属性 = function(物品名){
	var 物品 = new Array();
	var itemData = _root.物品属性列表[物品名];
	物品[0] = 物品名;
	物品[1] = itemData.icon == undefined ? "" : itemData.icon;
	物品[2] = itemData.type == undefined ? "" : itemData.type;
	物品[3] = itemData.use == undefined ? "" : itemData.use;
	物品[4] = itemData.weight == undefined ? 0 : itemData.weight;
	物品[5] = itemData.price == undefined ? 0 : itemData.price;
	物品[6] = itemData.description == undefined ? "" : itemData.description;
	物品[7] = itemData.data.friend == undefined ? 0 : itemData.data.friend;
	物品[8] = itemData.equipped.defence == undefined ? 0 : itemData.equipped.defence;
	物品[9] = itemData.level == undefined ? 0 : itemData.level;
	if (itemData.use == "药剂"){
		物品[10] = itemData.data.affecthp == undefined ? 0 : itemData.data.affecthp;
		物品[11] = itemData.data.affectmp == undefined ? 0 : itemData.data.affectmp;
	}else{
		物品[10] = itemData.equipped.hp == undefined ? 0 : itemData.equipped.hp;
		物品[11] = itemData.equipped.mp == undefined ? 0 : itemData.equipped.mp;
	}
	物品[12] = itemData.equipped.bullet == undefined ? 0 : itemData.equipped.bullet;
	switch (itemData.use){
		case "长枪" :
		case "手枪" :
		case "手雷" :
			物品[13] = 0;
			物品[14] = [itemData.data.capacity == undefined ? 0 : itemData.data.capacity, itemData.data.split == undefined ? 0 : itemData.data.split, itemData.data.diffusion == undefined ? 0 : itemData.data.diffusion, itemData.data.singleshoot == undefined ? 0 : itemData.data.singleshoot, false, itemData.data.interval == undefined ? 0 : itemData.data.interval, itemData.data.velocity == undefined ? 0 : itemData.data.velocity, itemData.data.bullet == undefined ? 0 : itemData.data.bullet, itemData.data.sound == undefined ? 0 : itemData.data.sound, itemData.data.muzzle == undefined ? 0 : itemData.data.muzzle, itemData.data.bullethit == undefined ? 0 : itemData.data.bullethit, itemData.data.clipname == undefined ? 0 : itemData.data.clipname, itemData.data.bulletsize == undefined ? 0 : itemData.data.bulletsize, itemData.data.power == undefined ? 0 : itemData.data.power, itemData.data.impact == undefined ? 0 : itemData.data.impact];
			break;
		case "刀" :
			物品[13] = itemData.data.power;
			物品[14] = [0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
			break;
		case "颈部装备" :
			物品[13] = 0;
			物品[14] = [itemData.equipped.title == undefined ? 0 : itemData.equipped.title, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
			break;
		default :
			物品[13] = itemData.equipped.damage == undefined ? 0 : itemData.equipped.damage;
			物品[14] = [0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
	}
	物品[15] = itemData.equipped.dressup == undefined ? "" : itemData.equipped.dressup;
	物品[16] = itemData.equipped.punch == undefined ? 0 : itemData.equipped.punch;
	物品[17] = itemData.equipped.balance == undefined ? 0 : itemData.equipped.balance;
	物品[18] = itemData.equipped.hitAccuracy == undefined ? 0 : itemData.equipped.hitAccuracy;
	物品[19] = itemData.equipped.dodgeAbility == undefined ? 0 : itemData.equipped.dodgeAbility;
	return 物品;
}

_root.parseXMLs2 = function(物品id){
	return _root.根据物品名查找全部属性(_root.id物品名对应表[物品id]);
}

_root.parseXMLs3 = function(物品名){
	if (物品名 != ""){
		return _root.根据装备名获得装备id(物品名);
	}
	return undefined;
}


_root.强化计算 = function(初始值, 强化等级){
	if (!isNaN(初始值)){
		if(!isNaN(强化等级) && 强化等级 <= 13) return Math.floor(初始值 * (1 + (强化等级 - 1) * (强化等级 - 1) / 100 + 0.05 * (强化等级 - 1)));
		return 初始值;
	}
	return 1;
}

_root.getArr = function(str){
   if(str == ""){
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
