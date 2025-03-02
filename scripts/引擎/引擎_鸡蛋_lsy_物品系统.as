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
	var itemArr = new Array();
	var itemData = _root.物品属性列表[物品名];
	itemArr[0] = 物品名;
	itemArr[1] = itemData.icon == undefined ? "" : itemData.icon;
	itemArr[2] = itemData.type == undefined ? "" : itemData.type;
	itemArr[3] = itemData.use == undefined ? "" : itemData.use;
	itemArr[4] = itemData.weight == undefined ? 0 : itemData.weight;
	itemArr[5] = itemData.price == undefined ? 0 : itemData.price;
	itemArr[6] = itemData.description == undefined ? "" : itemData.description;
	itemArr[7] = itemData.data.friend == undefined ? 0 : itemData.data.friend;
	itemArr[8] = itemData.equipped.defence == undefined ? 0 : itemData.equipped.defence;
	itemArr[9] = itemData.level == undefined ? 0 : itemData.level;
	if (itemData.use == "药剂"){
		itemArr[10] = itemData.data.affecthp == undefined ? 0 : itemData.data.affecthp;
		itemArr[11] = itemData.data.affectmp == undefined ? 0 : itemData.data.affectmp;
	}else{
		itemArr[10] = itemData.equipped.hp == undefined ? 0 : itemData.equipped.hp;
		itemArr[11] = itemData.equipped.mp == undefined ? 0 : itemData.equipped.mp;
	}
	itemArr[12] = itemData.equipped.bullet == undefined ? 0 : itemData.equipped.bullet;
	switch (itemData.use){
		case "长枪" :
		case "手枪" :
		case "手雷" :
			itemArr[13] = 0;
			itemArr[14] = [itemData.data.capacity == undefined ? 0 : itemData.data.capacity, itemData.data.split == undefined ? 0 : itemData.data.split, itemData.data.diffusion == undefined ? 0 : itemData.data.diffusion, itemData.data.singleshoot == undefined ? 0 : itemData.data.singleshoot, false, itemData.data.interval == undefined ? 0 : itemData.data.interval, itemData.data.velocity == undefined ? 0 : itemData.data.velocity, itemData.data.bullet == undefined ? 0 : itemData.data.bullet, itemData.data.sound == undefined ? 0 : itemData.data.sound, itemData.data.muzzle == undefined ? 0 : itemData.data.muzzle, itemData.data.bullethit == undefined ? 0 : itemData.data.bullethit, itemData.data.clipname == undefined ? 0 : itemData.data.clipname, itemData.data.bulletsize == undefined ? 0 : itemData.data.bulletsize, itemData.data.power == undefined ? 0 : itemData.data.power, itemData.data.impact == undefined ? 0 : itemData.data.impact];
			break;
		case "刀" :
			itemArr[13] = itemData.data.power;
			itemArr[14] = [0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
			break;
		case "颈部装备" :
			itemArr[13] = 0;
			itemArr[14] = [itemData.equipped.title == undefined ? 0 : itemData.equipped.title, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
			break;
		default :
			itemArr[13] = itemData.equipped.damage == undefined ? 0 : itemData.equipped.damage;
			itemArr[14] = [0, 0, 0, false, 0, 0, 0, "", "", "", "", "", 0, 0, 0, ""];
	}
	itemArr[15] = itemData.equipped.dressup == undefined ? "" : itemData.equipped.dressup;
	itemArr[16] = itemData.equipped.punch == undefined ? 0 : itemData.equipped.punch;
	itemArr[17] = itemData.equipped.balance == undefined ? 0 : itemData.equipped.balance;
	itemArr[18] = itemData.equipped.hitAccuracy == undefined ? 0 : itemData.equipped.hitAccuracy;
	itemArr[19] = itemData.equipped.dodgeAbility == undefined ? 0 : itemData.equipped.dodgeAbility;
	return itemArr;
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


//对新物品提交与获取函数的引用
_root.itemContain = function(itemArray):Object{
	return org.flashNight.arki.item.ItemUtil.contain(itemArray);
}
_root.itemSubmit = function(itemArray):Boolean{
	return org.flashNight.arki.item.ItemUtil.submit(itemArray);
}

_root.singleAcquire = function(name,value):Boolean{
	return org.flashNight.arki.item.ItemUtil.singleAcquire(name,value);
}
_root.singleSubmit = function(name,value):Boolean{
	return org.flashNight.arki.item.ItemUtil.singleSubmit(name,value);
}