// -------------------------------------------------------
// 公社爆燃钻矛 · 初始化（新增：魔法热伤增益 120 帧窗口）
// -------------------------------------------------------
_root.装备生命周期函数.公社爆燃钻矛初始化 = function(ref:Object, param:Object) {
    ref.active         = false;
    ref.fireCount      = (param.fireCount      != undefined) ? param.fireCount      : 3;   // 连发数
    ref.fireInterval   = (param.fireInterval   != undefined) ? param.fireInterval   : 3;   // 发射间隔(帧)
    ref.fireDelay      = (param.fireDelay      != undefined) ? param.fireDelay      : 10;  // 首发延迟(帧)
    ref.lastFireFrame  = -1;
    ref.fireIndex      = 0;

    // 炮口/抖动参数（可选）
    ref.offsetX        = (param.offsetX        != undefined) ? param.offsetX        : 140;
    ref.offsetY        = (param.offsetY        != undefined) ? param.offsetY        : -30;
    ref.stepX          = (param.stepX          != undefined) ? param.stepX          : 0;
    ref.stepY          = (param.stepY          != undefined) ? param.stepY          : 0;
    ref.flucX          = (param.flucX          != undefined) ? param.flucX          : 0;
    ref.flucY          = (param.flucY          != undefined) ? param.flucY          : 0;

    ref.bullet         = ref.子弹配置.bullet_1;

    // —— 新增：魔法热伤增益窗口配置 ——
    ref.magicBuffFrames   = (param.magicBuffFrames != undefined) ? param.magicBuffFrames : 120; // 增益持续帧数
    ref.magicBuffActive   = false;
    ref.magicBuffEndFrame = -1;

    var target:MovieClip = ref.自机;

    // 订阅战技触发事件
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        if (mode != "兵器") return;

        // 发射相关复位
        ref.active        = true;
        ref.fireIndex     = 0;
        ref.lastFireFrame = _root.帧计时器.当前帧数 + ref.fireDelay;

        // —— 开启/刷新 魔法·热 增益窗口（立即生效） ——
        var now = _root.帧计时器.当前帧数;
        ref.magicBuffActive   = true;
        ref.magicBuffEndFrame = now + ref.magicBuffFrames;
        target.兵器伤害类型 = "魔法";
        target.兵器魔法伤害属性 = "热";
    }, target);
};

// -------------------------------------------------------
// 公社爆燃钻矛 · 周期（新增：独立维护增益窗口，超时清空）
// -------------------------------------------------------
_root.装备生命周期函数.公社爆燃钻矛周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var now:Number = _root.帧计时器.当前帧数;
    var prop:Object = target.刀属性;


    // —— 维护魔法热伤增益窗口 ——
    if (ref.magicBuffActive && now > ref.magicBuffEndFrame) {
        // 到时清空并关闭窗口
        target.兵器伤害类型 = null;
        target.兵器魔法伤害属性  = null;
        if(_root.兵器使用检测(target)) {
            target.伤害类型 = target.兵器伤害类型;
            target.魔法伤害属性 = target.兵器魔法伤害属性;
        }
        ref.magicBuffActive = false;
    }

    // _root.发布消息(ref.magicBuffActive, ref.magicBuffEndFrame - now, target.兵器伤害类型, target.兵器魔法伤害属性);
    // 若未处于连发流程，后续发射逻辑不用跑
    if (!ref.active) return;

    // 战技窗口结束 → 立即复位发射状态（不影响上面的增益窗口计时）
    if (target.状态 != "战技") {
        ref.active    = false;
        ref.fireIndex = 0;
        return;
    }

    if (now - ref.lastFireFrame >= ref.fireInterval) {
        var bp:Object = {};
        var k:String;
        for (k in ref.bullet) bp[k] = ref.bullet[k];

        var dir:Number = (target.方向 == "左") ? -1 : 1;

        var sx:Number = target._x + dir * (ref.offsetX + ref.stepX * ref.fireIndex);
        var sy:Number = target._y + (ref.offsetY + ref.stepY * ref.fireIndex);

        if (ref.flucX) sx += _root.随机偏移(ref.flucX);
        if (ref.flucY) sy += _root.随机偏移(ref.flucY);

        bp.shootX = sx;
        bp.shootY = sy;
        bp.shootZ = sy;

        _root.子弹区域shoot传递(bp);

        ref.lastFireFrame = now;
        ref.fireIndex++;

        if (ref.fireIndex >= ref.fireCount) {
            ref.active    = false;
            ref.fireIndex = 0;
        }
    }
};
