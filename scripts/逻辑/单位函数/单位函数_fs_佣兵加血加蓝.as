import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.unit.Action.Regeneration.*;

/**
 * 佣兵集体加血 - RegenerationCore包装函数
 * 保持原有接口兼容性，内部使用RegenerationCore实现
 */
_root.佣兵集体加血 = function(healValue:Number) {
	if(isNaN(healValue)) return;
	
	// 使用RegenerationCore的群体恢复功能
	RegenerationCore.executeRegeneration(
		null, 
		RegenerationCore.HEALTH_REGEN, 
		RegenerationCore.FIXED_VALUE, 
		"group", 
		healValue, 
		{
			maxTargets: 30,
			effectName: "药剂动画-2"
		}
	);
};

/**
 * 佣兵集体回蓝 - RegenerationCore包装函数
 * 保持原有接口兼容性，内部使用RegenerationCore实现
 */
_root.佣兵集体回蓝 = function(回蓝值:Number) {
	if(isNaN(回蓝值)) return;
	
	// 使用RegenerationCore的群体法力值恢复功能
	RegenerationCore.executeRegeneration(
		null, 
		RegenerationCore.MANA_REGEN, 
		RegenerationCore.FIXED_VALUE, 
		"group", 
		回蓝值, 
		{
			maxTargets: 30,
			effectName: "药剂动画-2",
			effectScale: 100,
			effectStick: true
		}
	);
};

/**
 * 佣兵使用血包 - RegenerationCore包装函数
 * 保持原有接口兼容性，内部使用RegenerationCore实现
 */
_root.佣兵使用血包 = function(目标:String) {
	if(目标 == undefined || _root.gameworld[目标] == undefined) return;
	
	var targetUnit:MovieClip = _root.gameworld[目标];
	
	// 使用RegenerationCore的单体百分比恢复功能
	RegenerationCore.executeRegeneration(
		targetUnit, 
		RegenerationCore.HEALTH_REGEN, 
		RegenerationCore.PERCENTAGE, 
		"single", 
		targetUnit.血包恢复比例 / 100, 
		{
			multiplier: targetUnit.是否为敌人 ? 1 : 2,
			effectName: "药剂动画-2",
			effectScale: 100,
			effectStick: true
		}
	);
};

_root.加血动作 = new Object();

/**
 * 通用的范围治疗函数 - RegenerationCore包装函数
 * 保持原有接口兼容性，内部使用RegenerationCore实现
 */
_root.加血动作._范围治疗 = function(caster:MovieClip, rangeX:Number, rangeY:Number, healValue:Number, isPercentage:Boolean, effectName:String) {
	if(isNaN(rangeX) || isNaN(rangeY) || isNaN(healValue)) return;
	
	var valueMode:String = isPercentage ? RegenerationCore.PERCENTAGE : RegenerationCore.FIXED_VALUE;
	
	// 使用RegenerationCore的范围恢复功能
	RegenerationCore.executeRegeneration(
		caster, 
		RegenerationCore.HEALTH_REGEN, 
		valueMode, 
		"range", 
		healValue, 
		{
			rangeX: rangeX,
			rangeY: rangeY,
			maxTargets: 30,
			effectName: effectName || "药剂动画-2",
			effectScale: 100
		}
	);
};

/**
 * 将军集体加血 - RegenerationCore包装函数
 * 保持原有接口兼容性，内部调用通用范围治疗
 */
_root.加血动作.将军集体加血 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number) {
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 加血值, false, "药剂动画-2");
};

/**
 * 主唱百分比集体加血 - RegenerationCore包装函数
 * 保持原有接口兼容性，内部调用通用范围治疗
 */
_root.加血动作.主唱百分比集体加血 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number) {
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 加血值, true, "猩红增幅");
};

/**
 * 主唱集体加血 - RegenerationCore包装函数
 * 保持原有接口兼容性，使用固定的3%恢复比例
 */
_root.加血动作.主唱集体加血 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number) {
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 0.03, true, "猩红增幅");
};

/**
 * 主唱集体加血2 - RegenerationCore包装函数
 * 保持原有接口兼容性，使用固定的2%恢复比例
 */
_root.加血动作.主唱集体加血2 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number) {
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 0.02, true, "猩红增幅");
};

/**
 * 键盘集体加血 - RegenerationCore包装函数
 * 保持原有接口兼容性，使用固定的5%恢复比例
 */
_root.加血动作.键盘集体加血 = function(加血距离X:Number, 加血距离Y:Number, 加血值:Number) {
	_root.加血动作._范围治疗(_parent, 加血距离X, 加血距离Y, 0.05, true, "猩红增幅");
};

// 为了向后兼容，也提供便捷调用方法
_root.快速佣兵加血 = function(healValue:Number) {
	return RegenerationCore.healMercenariesGroup(healValue);
};

_root.快速佣兵回蓝 = function(manaValue:Number) {
	return RegenerationCore.restoreMercenariesMana(manaValue);
};

_root.快速使用血包 = function(targetName:String) {
	return RegenerationCore.useMedkit(targetName);
};

_root.快速范围治疗 = function(caster:MovieClip, rangeX:Number, rangeY:Number, healValue:Number, isPercentage:Boolean, effectName:String) {
	return RegenerationCore.rangeHealing(caster, rangeX, rangeY, healValue, isPercentage, effectName);
};