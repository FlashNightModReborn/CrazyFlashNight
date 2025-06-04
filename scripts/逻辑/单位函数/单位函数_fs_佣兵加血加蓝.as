import org.flashNight.arki.unit.UnitComponent.Targetcache.*;

_root.佣兵集体加血 = function(healValue:Number)
{
	if(isNaN(healValue)) return;
	var hero:MovieClip = TargetCacheManager.findHero();
	var map:Array = TargetCacheManager.getCachedAlly(hero, 30);

	for(var i:Number = 0; i < map.length; ++i) {
		var target:MovieClip = map[i];
		var hp:Number = target.hp;

		if(target.hp满血值 > (healValue + hp)) {
			target.hp = target.hp满血值;
		} else {
			target.hp += healValue;
		}
	}
};

_root.佣兵集体回蓝 = function(回蓝值:Number)
{
	if(isNaN(回蓝值)) return;
	
	var hero:MovieClip = TargetCacheManager.findHero();
	var allies:Array = TargetCacheManager.getCachedAlly(hero, 30);
	
	for(var i:Number = 0; i < allies.length; ++i) {
		var target:MovieClip = allies[i];
		
		// 检查目标是否有效且需要回蓝
		if(target.mp != undefined && target.mp > 0 && !isNaN(target.mp)) {
			if(target.mp + 回蓝值 > target.mp满血值) {
				target.mp = target.mp满血值;
			} else {
				target.mp += 回蓝值;
			}
			_root.效果("药剂动画-2", target._x, target._y, 100, true);
		}
	}
};

_root.佣兵使用血包 = function(目标:String)
{
	if(目标 == undefined || _root.gameworld[目标] == undefined) return;
	
	var targetUnit:MovieClip = _root.gameworld[目标];
	var 加血值:Number = targetUnit.hp满血值 * targetUnit.血包恢复比例 / 100;

	// 友方单位双倍恢复
	if(!targetUnit.是否为敌人) {
		加血值 *= 2;
	}
	
	// 只对存活单位生效
	if(targetUnit.hp > 0) {
		if(targetUnit.hp + 加血值 > targetUnit.hp满血值) {
			targetUnit.hp = targetUnit.hp满血值;
		} else {
			targetUnit.hp += 加血值;
		}
		_root.效果("药剂动画-2", targetUnit._x, targetUnit._y, 100, true);
	}
};

_root.加血动作 = new Object();

// 通用的范围治疗函数
_root.加血动作._范围治疗 = function(caster:MovieClip, rangeX:Number, rangeY:Number, healValue:Number, isPercentage:Boolean, effectName:String)
{
	if(isNaN(rangeX) || isNaN(rangeY) || isNaN(healValue)) return;
	
	var allies:Array = TargetCacheManager.findAlliesInRange(caster, 30, rangeX);
	
	for(var i:Number = 0; i < allies.length; ++i) {
		var target:MovieClip = allies[i];
		
		// 检查是否在治疗范围内
		if(Math.abs(target._y - caster._y) < rangeY) {
			// 检查目标是否需要治疗
			if(target.hp > 0 && target.hp < target.hp满血值) {
				var actualHealValue:Number;
				
				if(isPercentage) {
					actualHealValue = target.hp满血值 * healValue;
				} else {
					actualHealValue = healValue;
				}
				
				if(target.hp + actualHealValue > target.hp满血值) {
					target.hp = target.hp满血值;
				} else {
					target.hp += actualHealValue;
				}
				
				_root.效果(effectName || "药剂动画-2", target._x, target._y, 100);
			}
		}
	}
};

_root.加血动作.将军集体加血 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number)
{
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 加血值, false, "药剂动画-2");
};

_root.加血动作.主唱百分比集体加血 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number)
{
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 加血值, true, "猩红增幅");
};

_root.加血动作.主唱集体加血 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number)
{
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 0.03, true, "猩红增幅");
};

_root.加血动作.主唱集体加血2 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number)
{
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 0.02, true, "猩红增幅");
};

_root.加血动作.键盘集体加血 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number)
{
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 0.05, true, "猩红增幅");
};