import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.neur.Event.*;

//计算闪避
// 已移至 DodgeHandler 类中的常量：
// - _root.躲闪率极限 → DodgeHandler.DODGE_RATE_LIMIT
// - _root.命中率极限 → DodgeHandler.HIT_RATE_LIMIT
// - _root.闪避系统闪避率上限 → DodgeHandler.DODGE_SYSTEM_MAX
// - _root.基准躲闪率 → DodgeHandler.BASE_DODGE_RATE
// - _root.基准命中率 → DodgeHandler.BASE_HIT_RATE
// - _root.跳弹基准重量 → DodgeHandler.JUMP_BOUNCE_BASE_WEIGHT
// - _root.过穿基准重量 → DodgeHandler.PENETRATION_BASE_WEIGHT

//防御计算公式 - 已移至 DamageResistanceHandler 类
// 直接调用 DamageResistanceHandler.defenseDamageRatio() 替代委托

/*
_root.跳弹伤害计算 = Delegate.create(DamageResistanceHandler, DamageResistanceHandler.bounceDamageCalculation);
_root.过穿伤害计算 = Delegate.create(DamageResistanceHandler, DamageResistanceHandler.penetrationDamageCalculation);

*/


// 以下函数已在DodgeHandler重构
/*
_root.is119 = function(x:Number):Boolean 
{
	return x == _root.闪客之夜;
};

//sigmoid函数
_root.sigmoid = function(x:Number):Number 
{
    var expX:Number = Math.exp(x); // 避免重复计算 e^x
    return expX / (1 + expX);      // 化简公式，减少一次减法操作
};

//relu函数
_root.relu = function(x:Number):Number 
{
	return Math.max(0, x);
};

//softplus函数
_root.softplus = function(x:Number):Number 
{
	return Math.log(1 + Math.exp(x));
};

_root.sig_tyler = function(x:Number):Number 
{
	//_root.发布调试消息(3 * x / 40 + 0.5 - x * x * x / 4000);
	return 3 * x / 40 + 0.5 - x * x * x / 4000;
};//展开节约性能


//根据重量判断是跳弹还是过穿
_root.躲闪状态校验 = function(重量:Number, 等级:Number) {
    if (_root.成功率((等级 - 重量))) {
        return "躲闪";
    } else if (_root.成功率(100 * (重量 - _root.过穿基准重量) / (_root.跳弹基准重量 - _root.过穿基准重量))) {
        return "跳弹";
    } else {
        return "过穿";
    }
};

//兼容性考虑
_root.躲闪状态计算 = function(命中对象:MovieClip, 躲闪结果:Boolean, 子弹:MovieClip) {
	var 计算用伤害值 = 命中对象.损伤值 + 子弹.additionalEffectDamage;
    计算用伤害值 = isNaN(计算用伤害值) ? 0 : 计算用伤害值;
	if(命中对象.懒闪避 > 0)
    {
        // _root.服务器.发布服务器消息("损伤:" + 命中对象.损伤值 + "附加:" + 子弹.additionalEffectDamage + " 伤害:" + 计算用伤害值 + " 高危闪避:" + 命中对象.懒闪避);
        if(_root.lazyMiss(命中对象, 计算用伤害值, 命中对象.懒闪避))
        {
            return "直感";
        }
	}

	if(命中对象.受击反制) return "格挡";

    if (躲闪结果) {
		
        // if (isNaN(命中对象.等级)) {
        //     命中对象.等级 = 1;
        //     _root.发布消息(命中对象 + " 触发异常等级 " + 命中对象.等级)
        // }
        // if (isNaN(命中对象.重量)) {

        //     命中对象.重量 = 999;
        //     _root.发布消息(命中对象 + " 触发异常重量 " + 命中对象.重量)
        // }
		
		return _root.躲闪状态校验(命中对象.重量, 命中对象.等级);
    }

	return "未躲闪";
};


_root.根据等级计算闪避率 = function(攻击者等级, 闪避者等级, 躲闪率, 命中率)
{
	//_root.调试模式 = true;
	//_root.发布调试消息(攻击者等级 + " " + 闪避者等级 + " " + 躲闪率 + " " + 命中率);
	;
	if (躲闪率 < 0 || isNaN(躲闪率))
	{
		return 0;
	}
	var 闪避指数 = (闪避者等级 * _root.基准命中率 / 躲闪率 - 攻击者等级 * 命中率 / _root.基准躲闪率) / 40;
	闪避率 = _root.sigmoid(闪避指数) * _root.闪避系统闪避率上限;//通过
	//_root.发布调试消息(闪避率);
	return 闪避率;
};

_root.根据命中计算闪避结果 = function(发射者对象, 命中者对象, 命中率)
{
	//命中未赋值则查找发射者属性

	闪避率 = _root.根据等级计算闪避率(发射者对象.等级, 命中者对象.等级, 命中者对象.躲闪率, isNaN(命中率) ? 发射者对象.命中率 : 命中率);

	// _root.发布消息(发射者对象.等级 + " " + 发射者对象.命中率 + " " + 命中者对象.等级 + " " + 命中者对象.躲闪率 + " " + 命中率 + " " + 闪避率);
	return _root.成功率(闪避率);
};

*/