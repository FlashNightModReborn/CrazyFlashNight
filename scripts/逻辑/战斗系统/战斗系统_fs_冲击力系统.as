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
	if(命中对象.懒闪避 > 0 && _root.lazyMiss(命中对象, 计算用伤害值, 命中对象.懒闪避)){
		return "直感";
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
//根据时间确定残余冲击力衰减
_root.冲击力衰减 = function(受击间隔:Number) {
    return (2000 * _root.冲击残余时间 - 受击间隔) / (2000 * _root.冲击残余时间);
};



_root.冲击力刷新 = function(命中对象) {
    var 当前时间:Number = getTimer();

    if (isNaN(命中对象.残余冲击力)) {
        _root.发布消息(命中对象 + " 触发异常残余 " + 命中对象.残余冲击力)
        命中对象.残余冲击力 = 0;
    }
    if (isNaN(命中对象.韧性系数)) {
        命中对象.韧性系数 = 1;
        _root.发布消息(命中对象 + " 触发异常韧性 " + 命中对象.韧性系数)
    }
    
    命中对象.韧性上限 = 命中对象.韧性系数 * 命中对象.hp / _root.防御减伤比(命中对象.防御力);

    if (!isNaN(命中对象.上次受击时间)) {
        var 受击间隔:Number = 当前时间 - 命中对象.上次受击时间;
        if (受击间隔 > 1000 * _root.冲击残余时间) {
            命中对象.残余冲击力 = Math.max(0, 命中对象.残余冲击力 * _root.冲击力衰减(受击间隔));
        }
    }
    命中对象.上次受击时间 = 当前时间;
    return;
};

//根据伤害转换冲击力

_root.冲击力计算 = function(伤害:Number, 击倒率:Number) {
    return 伤害 * _root.冲击系数 / 击倒率;
};


_root.冲击力结算 = function(伤害:Number, 击倒率:Number, 命中对象) {

    var 冲击力:Number = 伤害 * _root.冲击系数 / 击倒率;

    //未定位到产生无穷大的原因，姑且写着
    if (isFinite(冲击力)) {
        命中对象.残余冲击力 += 冲击力;
    } else {
        命中对象.残余冲击力 = 命中对象.韧性上限 + 1;
    }
    return;
};
