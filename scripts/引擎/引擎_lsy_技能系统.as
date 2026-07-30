
_root.根据技能名查找主角技能等级 = function(技能名){
	var 主角技能表 = _root.主角技能表;
	for(var i = 0; i < 主角技能表.length; i++){
		if (主角技能表[i][0] == 技能名){
			return 主角技能表[i][1];
		}
	}
	return 0;
};

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
	if(!玩家界面 || !玩家界面.快捷技能界面) return false;
	return SkillLoadoutService.projectQuickSlotRenderer(玩家界面);
};

_root.动态更新技能冷却 = function(){
	_root.动态更新技能冷却领域();
	_root.技能系统投影快捷栏();
};

_root.排列技能图标 = function(){
	_root.技能系统投影快捷栏();
	_root.技能系统投影Hero();
};

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
