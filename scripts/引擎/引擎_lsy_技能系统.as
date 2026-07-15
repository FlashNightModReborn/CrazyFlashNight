
_root.根据技能名查找主角技能等级 = function(技能名){
	var 主角技能表 = _root.主角技能表;
	for(var i = 0; i < 主角技能表.length; i++){
		if (主角技能表[i][0] == 技能名){
			return 主角技能表[i][1];
		}
	}
	return 0;
};

_root.学习技能 = function(技能名, 等级){
	// 兼容 API 只保留 Boolean 返回/旧提示；写权威统一进入 SkillPanelService 事务。
	// service 尚未安装、当前 NPC 无教师目录或校验失败时一律 fail-closed。
	if(typeof _root.legacySkillLearnCommit != "function") return false;
	var 当前等级:Number = Number(_root.根据技能名查找主角技能等级(技能名));
	var 教师对象:Object = _root.gameworld ? _root.gameworld[_root.当前NPC] : null;
	var 结果:Object = _root.legacySkillLearnCommit(技能名, Number(等级), 教师对象);
	if(!结果 || 结果.success !== true){
		if(结果 && 结果.error == "skill_table_full" && typeof _root.发布消息 == "function") _root.发布消息(_root.获得翻译("技能槽已满！"));
		return false;
	}
	if(typeof _root.发布消息 == "function"){
		var 提示:String = 当前等级 > 0 ? "技能升级成功！" : "新技能获得！";
		_root.发布消息(_root.获得翻译(技能名) + "，" + _root.获得翻译(提示));
	}
	return true;
}

// 纯领域层：不读取 hero、HUD 或物品栏 MovieClip。
_root.重建主角被动技能领域 = function(){
	if(!_root.技能表对象 || !(_root.主角技能表 instanceof Array)) return false;
	_root.主角被动技能 = {};
	var seen:Object = {};
	for(var i = 0; i < Math.min(80, _root.主角技能表.length); i++){
		var 技能 = _root.主角技能表[i];
		if(!(技能 instanceof Array) || typeof 技能[0] != "string" || 技能[0] == "" || seen["$" + 技能[0]]) continue;
		seen["$" + 技能[0]] = true;
		var 技能对象 = _root.技能表对象[技能[0]];
		if(技能对象 && 技能对象.Passive){
			var enabled = 技能[4];
			var enabledBool:Boolean = enabled === true || enabled === 1 || enabled === "true" || enabled === "1";
			_root.主角被动技能[技能[0]] = {技能名:技能[0], 等级:Number(技能[1]), 启用:enabledBool};
		}
	}
	return _root.动态更新技能冷却领域() !== false;
};

_root.技能系统投影Hero = function(){
	if(typeof TargetCacheManager == "undefined" || typeof TargetCacheManager.findHero != "function") return false;
	var hero:Object = TargetCacheManager.findHero();
	if(hero){
		hero.被动技能 = _root.主角被动技能;
		if(typeof hero.读取被动效果 == "function") hero.读取被动效果();
		return true;
	}
	return false;
};

_root.更新主角被动技能 = function(){
	if(!_root.重建主角被动技能领域()){
		if(typeof _root.发布调试消息 == "function") _root.发布调试消息("技能表对象未加载，延迟更新被动技能");
		return;
	}
	_root.技能系统投影Hero();
	_root.技能系统投影快捷栏();
};

_root.动态更新技能冷却领域 = function() {
	return SkillLoadoutService.recalculateDynamicCooldownDomain();
};

// 可选快捷 HUD renderer：只投影，不参与领域读写。
_root.技能系统投影快捷栏 = function(){
	var 玩家界面:Object = _root.玩家信息界面;
	var 快捷界面:Object = 玩家界面 ? 玩家界面.快捷技能界面 : null;
	if(!快捷界面) return false;
	for (var i = 1; i < 13; i++){
		var 当前技能栏:Object = 快捷界面["快捷技能栏" + i];
		if(!当前技能栏) continue;
		var 技能名 = _root["快捷技能栏" + i];
		if(技能名 == null || 技能名 == ""){
			当前技能栏.是否装备 = 0;
			当前技能栏.已装备名 = "";
			continue;
		}
		var 该技能全部属性:Object = _root.技能表对象 ? _root.技能表对象[技能名] : null;
		if(!该技能全部属性) continue;
		当前技能栏.是否装备 = 1;
		当前技能栏.已装备名 = 技能名;
		当前技能栏.冷却时间 = Number(该技能全部属性.CD);
		当前技能栏.消耗mp = Number(该技能全部属性.MP);
	}
	return true;
};

_root.动态更新技能冷却 = function(){
	_root.动态更新技能冷却领域();
	_root.技能系统投影快捷栏();
};

// 可选旧技能列表 renderer：HUD/物品栏不存在时正常跳过。
_root.技能系统投影旧列表 = function(){
	var 物品栏界面:Object = _root.物品栏界面;
	var 玩家界面:Object = _root.玩家信息界面;
	if(玩家界面 && typeof 玩家界面.刷新技能等级显示 == "function") 玩家界面.刷新技能等级显示();
	if (物品栏界面 && 物品栏界面.界面 == "技能" && 物品栏界面.技能图标
		&& _root.主角技能表 instanceof Array && typeof 物品栏界面.attachMovie == "function"
		&& typeof 物品栏界面.getNextHighestDepth == "function"){
		var 图标x = 物品栏界面.技能图标._x;
		var 图标y = 物品栏界面.技能图标._y;
		var 图标高度 = 28;
		var 图标宽度 = 28;
		var 列数 = 8;
		var 行数 = 10;
		var 换行计数 = 0;
		
		for(var i = 0; i < 列数 * 行数; i++){
			var 技能信息 = _root.主角技能表[i];
			if(!(技能信息 instanceof Array)) 技能信息 = ["", 0, false, "", false];

			if(物品栏界面["技能图标" + i]) 物品栏界面["技能图标" + i].removeMovieClip();
			var 当前技能图标 = 物品栏界面.attachMovie("技能图标","技能图标" + i,物品栏界面.getNextHighestDepth(),{数量:技能信息[1]});
			if(!当前技能图标) continue;

			当前技能图标._x = 图标x;
			当前技能图标._y = 图标y;
			图标x += 图标宽度;
			换行计数++;
			if (换行计数 == 列数){
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
	return true;
};

_root.排列技能图标 = function(){
	_root.技能系统投影旧列表();
	_root.技能系统投影Hero();
};

_root.删除技能图标 = function(){
	if(!_root.物品栏界面) return;
	for(var i = 0; i < 80; i ++) if(_root.物品栏界面["技能图标" + i]) _root.物品栏界面["技能图标" + i].removeMovieClip();
}

_root.根据技能名查找全部属性 = function(技能名){
	return _root.技能表对象[技能名];
}


_root.主角是否已学 = function(技能名){
	var 主角技能表 = _root.主角技能表;
	for (var i = 0; i < 主角技能表.length; i++){
		if (主角技能表[i][0] == 技能名) return 主角技能表[i][1];
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


_root.getNPCSkills = function(NPCName){
	return _root.NPC技能表[NPCName];
}
