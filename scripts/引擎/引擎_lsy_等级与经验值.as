import org.flashNight.gesh.object.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.component.Effect.*;


_root.最大等级 = 60;
_root.等级限制 = 100;

_root.根据等级得升级所需经验 = function(等级):Number{
	var 经验 = Math.floor(13 * 等级 * 等级 * 等级 * 等级 + 500);
	if (!isNaN(经验) && 经验 > 0) return 经验;
	return 1000000000000;
}

_root.根据等级计算获得技能点 = function(等级):Number{
	if (_root.isChallengeMode()) return 15;
	if (等级 > 70) return 100;
	if (等级 > 60) return 90;
	if (等级 > 50) return 80;
	if (等级 > 40) return 70;
	if (等级 > 30) return 60;
	if (等级 > 20) return 50;
	if (等级 > 10) return 30;
	return 20;
}

_root.健身房主角是否升级 = function()
{
	if (isNaN(_root.经验值) || isNaN(_root.等级) || _root.等级 >= _root.等级限制) return;

	var 是否升级 = false;
	var 是否完成全部升级 = false;
	while (!是否完成全部升级)
	{
		_root.升级需要经验值 = _root.根据等级得升级所需经验(_root.等级);
		_root.上次升级需要经验值 = _root.等级 > 1 ? _root.根据等级得升级所需经验(_root.等级 - 1) : 0;
		_root.玩家信息界面.刷新经验值显示();
		if (_root.升级需要经验值 <= _root.经验值)
		{
			_root.玩家信息界面.主角经验值显示界面.frame = 100;
			_root.等级++;
			_root.技能点数 += _root.根据等级计算获得技能点(_root.等级);
			// _root.聊天窗.传言("勤奋的" + _root.玩家称号 + _root.角色名 + "升到了" + _root.等级 + "级！");
			是否升级 = true;
		}
		else
		{
			是否完成全部升级 = true;
		}
	}

	if (是否升级) {
		_root.身价 = _root.基础身价值 * _root.等级;
		var 控制对象 = TargetCacheManager.findHero();
		控制对象.等级 = _root.等级;
		控制对象.根据等级初始数值(_root.等级);
		if(!控制对象.hp || 控制对象.hp < 控制对象.hp满血值) 控制对象.hp = 控制对象.hp满血值;
		if(!控制对象.mp || 控制对象.mp < 控制对象.mp满血值) 控制对象.mp = 控制对象.mp满血值;
		_root.玩家信息界面.刷新hp显示();
		_root.玩家信息界面.刷新mp显示();
		EffectSystem.Effect("升级动画",控制对象._x,控制对象._y,100);
		_root.自动存盘();
	}
}

_root.主角是否升级 = function(当前等级, 当前经验值)
{
	if (isNaN(当前经验值) || isNaN(当前等级) || 当前等级 >= _root.等级限制) return;

	_root.升级需要经验值 = 根据等级得升级所需经验(当前等级);
	_root.上次升级需要经验值 = _root.等级 > 1 ? 根据等级得升级所需经验(当前等级 - 1) : 0;
	_root.玩家信息界面.刷新经验值显示();

	if (_root.升级需要经验值 <= 当前经验值)
	{
		_root.玩家信息界面.主角经验值显示界面.frame = 100;
		_root.等级++;
		_root.技能点数 += _root.根据等级计算获得技能点(_root.等级);

		var 控制对象 = TargetCacheManager.findHero();
		_root.身价 = _root.基础身价值 * _root.等级;
		控制对象.等级 = _root.等级;
		控制对象.根据等级初始数值(_root.等级);
		控制对象.hp = 控制对象.hp满血值;
		控制对象.mp = 控制对象.mp满血值;
		_root.玩家信息界面.刷新hp显示();
		_root.玩家信息界面.刷新mp显示();
		EffectSystem.Effect("升级动画",控制对象._x,控制对象._y,100);
		// _root.聊天窗.传言("勤奋的" + _root.玩家称号 + _root.角色名 + "升到了" + _root.等级 + "级！");
		_root.自动存盘();
	}
}

_root.经验值计算 = function(最小经验值, 最大经验值, 怪物等级, 怪物最大等级){
	var tmp_exp = Math.floor((最小经验值 + (最大经验值 - 最小经验值) / (怪物最大等级 - 1) * 怪物等级) * _root.难度等级);
	if (isNaN(tmp_exp) || tmp_exp <= 1) tmp_exp = 1;
	
	//战宠加经验
	for (var i = 0; i < _root.出战宠物id库.length; i++){
		var petid = 出战宠物id库[i];
		var 宠物对象 = _root.宠物mc库[i];
		var 当前宠物信息 = _root.宠物信息[petid];
		if (宠物对象.hp > 0 && 当前宠物信息[4] == 1){
			//
			if (当前宠物信息.length < 6) 当前宠物信息.push({});
			if (!当前宠物信息[5] || typeof 当前宠物信息[5] == "number") 当前宠物信息[5] = {};
			if (!当前宠物信息[5].宠物升级经验) 当前宠物信息[5].宠物升级经验 = 0;
			
			if (当前宠物信息[5].宠物升级所需经验 <= 0) 当前宠物信息[5].宠物升级所需经验 = _root.战宠UI函数.计算战宠升级所需经验(宠物对象.兵种,宠物对象.等级);

			当前宠物信息[5].宠物升级经验 += tmp_exp;

			if (当前宠物信息[5].宠物升级经验 > 当前宠物信息[5].宠物升级所需经验 && 当前宠物信息[1] < 等级限制){
				当前宠物信息[1]++;
				当前宠物信息[5].宠物升级经验 = 0;
				_root.发布消息("宠物" + _root.宠物库[当前宠物信息[0]].Name + "已升级！");
				_root.宠物升级加载(i);
				当前宠物信息[5].宠物升级所需经验 = _root.战宠UI函数.计算战宠升级所需经验(宠物对象.兵种,宠物对象.等级);
			}
		}
	}

	_root.等级 = Number(_root.等级);
	if (_root.等级 < _root.等级限制){
		if (isNaN(_root.经验值)) _root.经验值 = _root.等级 > 1 ? 根据等级得升级所需经验(_root.等级 - 1) : 0;

		if (_root.等级 > 怪物等级)
		{
			tmp_exp = Math.floor(tmp_exp / (_root.等级 - 怪物等级) * _root.难度等级);
		}
		_root.经验值 = Number(_root.经验值) + tmp_exp;
		_root.主角是否升级(_root.等级,_root.经验值);
	}
}

_root.宠物升级加载 = function(i){
	var 宠物对象 = _root.宠物mc库[i];
	var temppet_x = 宠物对象._x;
	var temppet_y = 宠物对象._y;
	// 宠物对象.removeMovieClip();
	var temp_petid = 出战宠物id库[i];

	var 当前宠物信息 = _root.宠物信息[temp_petid];
	if (当前宠物信息[4] == 1 && 当前宠物信息[2] >= 0){
		var 宠物等级 = 当前宠物信息[1];

		// var 宠物数据 = _root.宠物库[当前宠物信息[0]];
		// var 宠物标识符 = 宠物数据.Identifier;
		// var 宠物名字 = 宠物数据.Name;
		// var 宠物是否为敌人 = false;
		// var 宠物身高 = 宠物数据.Height;
		// var 宠物僵尸型敌人newname = "宠物" + temp_petid + 宠物标识符;
		// //if (当前宠物信息.length >= 6)
		if (当前宠物信息.length >= 6 && 当前宠物信息[5])
		{
			var 宠物属性 = 当前宠物信息[5];
		}
		else
		{
			当前宠物信息[5] = {};
			var 宠物属性 = 当前宠物信息[5];
		}
		宠物属性.宠物库数组号 = 当前宠物信息[0];
		宠物属性.宠物信息数组号 = temp_petid;
		// var 新宠物对象 = _root.加载游戏世界人物(宠物标识符,宠物僵尸型敌人newname,_root.gameworld.getNextHighestDepth(),{等级:宠物等级, 名字:宠物名字, 宠物属性:this.宠物属性, 是否为敌人:宠物是否为敌人, 身高:宠物身高, _x:temppet_x, _y:temppet_y});//,称号:称号
		// _root.宠物mc库[i] = 新宠物对象;

		// _root.发布消息("宠物属性", ObjectUtil.toString(宠物属性));

		

		

		宠物对象.等级 = 宠物等级;
		DisplayNameInitializer.initialize(宠物对象);
		// _root.发布消息(宠物等级, 宠物对象.等级, 宠物对象.displayName)
		宠物对象.宠物属性 = 宠物属性;
		宠物对象.根据等级初始数值(宠物对象.等级);
		宠物对象.宠物属性初始化(宠物对象.等级);
		宠物对象.hp = 宠物对象.hp满血值;

		EffectSystem.Effect("升级动画2",宠物对象._x,宠物对象._y,100);
	}
}

