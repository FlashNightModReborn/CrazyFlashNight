import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.neur.Event.*;

_root.跳弹基准重量 = 100;
_root.过穿基准重量 = 20;
_root.跳弹防御系数 = 5;
_root.踉跄判定 = 2;
_root.冲击系数 = 50;
_root.冲击残余时间 = 5;

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
	var 计算用伤害值 = 命中对象.损伤值 + 子弹.附加层伤害计算;
    计算用伤害值 = isNaN(计算用伤害值) ? 0 : 计算用伤害值;
	if(命中对象.懒闪避 > 0)
    {
        // _root.服务器.发布服务器消息("损伤:" + 命中对象.损伤值 + "附加:" + 子弹.附加层伤害计算 + " 伤害:" + 计算用伤害值 + " 高危闪避:" + 命中对象.懒闪避);
        if(_root.lazyMiss(命中对象, 计算用伤害值, 命中对象.懒闪避))
        {
            return "直感";
        }
	}

    if (躲闪结果) {
        if (isNaN(命中对象.等级)) {
            命中对象.等级 = 1;
            _root.发布消息(命中对象 + " 触发异常等级 " + 命中对象.等级)
        }
        if (isNaN(命中对象.重量)) {

            命中对象.重量 = 999;
            _root.发布消息(命中对象 + " 触发异常重量 " + 命中对象.重量)
        }
		return _root.躲闪状态校验(命中对象.重量, 命中对象.等级);
    }
	else if(命中对象.受击反制){
		return "格挡";
	}
	return "未躲闪";
};

_root.冲击力刷新 = Delegate.create(ImpactHandler, ImpactHandler.refreshImpactForce);
_root.冲击力结算 = Delegate.create(ImpactHandler, ImpactHandler.settleImpactForce);
