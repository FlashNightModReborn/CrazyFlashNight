_root.装备生命周期函数.斩马刀初始化 = function(ref:Object, param:Object) {
    ref.interval = param.interval || 0.5; // 默认0.5秒
    ref.ratiol = param.ratio || 3; // 默认3%蓝量
    ref.bulletName = param.bulletName || "碎石飞扬";
    ref.power = param.power || 12; // 默认12倍蓝量伤害
    ref.blockProp = {
        shooter: ref.自机._name,
		shootZ:NaN,
		消弹敌我属性:ref.自机.是否为敌人,   
		消弹方向:null,                                  
		Z轴攻击范围:10,                                
		区域定位area:null,
        反弹:true
	};
};

_root.装备生命周期函数.斩马刀周期 = function(ref:Object, param:Object) {
    var isAvailable:Boolean = true;
    var target:MovieClip = ref.自机;
    var currentTime:Number = getTimer();
    if (isNaN(ref.lastTime) || currentTime - ref.lastTime > ref.interval * 1000) {
        ref.lastTime = currentTime;
    } else {
        isAvailable = false;
    }

    if(!_root.兵器攻击检测(target)) {
        return;
    }

    var saber:MovieClip = target.刀_引用;

    ref.blockProp.shootZ = target.Z轴坐标;
    ref.blockProp.区域定位area = saber;
    _root.消除子弹(ref.blockProp);

    if (isAvailable) {
        var flag:Boolean = true;

        switch (target.getSmallState()) {
            case "兵器一段中":
            case "兵器五段中":
                flag = true;
                break;
            default:
                flag = _root.成功率(5);
        }
        if (flag) {
            // _root.发布消息(flag, saber);
            var attackPoint:MovieClip = saber.刀口位置3;

            target.man.攻击时可改变移动方向(1);
            var mpValue:Number = Math.floor(target.mp满血值 / 100 * ref.ratiol);
            if (target.mp >= mpValue) {
                子弹属性 = _root.子弹属性初始化(attackPoint, ref.bulletName, target);

                子弹属性.子弹散射度 = 0;
                子弹属性.子弹威力 = mpValue * ref.power;
                子弹属性.子弹速度 = 0;
                子弹属性.Z轴攻击范围 = 50;
                子弹属性.击倒率 = 1;
                
                _root.子弹区域shoot传递(子弹属性);
                target.mp -= mpValue;
                // _root.发布消息(target.mp);
                // _root.服务器.发布服务器消息(ObjectUtil.toString(子弹属性));
            } else if (target == root.gameworld[_root.控制目标]) {
                root.发布消息("气力不足，难以发挥装备的真正力量……");
            }
        }
    }
};
