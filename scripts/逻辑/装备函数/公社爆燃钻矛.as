// -------------------------------------------------------
// 公社爆燃钻矛 · 初始化（新增：兵器五段发射配置）
// -------------------------------------------------------
_root.装备生命周期函数.公社爆燃钻矛初始化 = function(ref:Object, param:Object) {
    ref.active         = false;
    ref.fireCount      = (param.fireCount      != undefined) ? param.fireCount      : 3;
    ref.fireInterval   = (param.fireInterval   != undefined) ? param.fireInterval   : 3;
    ref.fireDelay      = (param.fireDelay      != undefined) ? param.fireDelay      : 10;
    ref.lastFireFrame  = -1;
    ref.fireIndex      = 0;

    // 炮口/抖动参数（可选）
    ref.offsetX        = (param.offsetX        != undefined) ? param.offsetX        : 40;
    ref.offsetY        = (param.offsetY        != undefined) ? param.offsetY        : -30;
    ref.stepX          = (param.stepX          != undefined) ? param.stepX          : 0;
    ref.stepY          = (param.stepY          != undefined) ? param.stepY          : 0;
    ref.flucX          = (param.flucX          != undefined) ? param.flucX          : 0;
    ref.flucY          = (param.flucY          != undefined) ? param.flucY          : 0;

    ref.bullet         = ref.子弹配置.bullet_1;

    // —— 兵器五段发射配置 ——
    ref.normalAttackActive      = false;   // 是否进入兵器五段发射流程
    ref.normalAttackFired       = false;   // 是否已发射（确保只发1发）
    ref.normalAttackFireDelay   = (param.normalAttackFireDelay != undefined) ? param.normalAttackFireDelay : 5;  // 五段发射前摇(帧)，可自定义
    ref.normalAttackStartFrame  = -1;      // 进入兵器五段的帧数

    // —— 魔法热伤增益窗口配置 ——
    var target:MovieClip = ref.自机;

    var basicBuffFrames = (param.basicBuffFrames != undefined) ? param.basicBuffFrames : 120;
    var upgradeLevel:Number = target.刀.value.level;

    ref.magicBuffFrames   = basicBuffFrames * (1 + Math.min(1.5, (upgradeLevel - 1) * 0.125));
    ref.magicBuffActive   = false;
    ref.magicBuffEndFrame = -1;

    // 订阅战技触发事件
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        if (mode != "兵器") return;
        var hasFuel:Boolean = ItemUtil.singleSubmit("火焰喷射器燃料罐", 1);

        //_root.发布消息("公社爆燃钻矛触发，燃料罐状态：" + (hasFuel ? "有" : "无"));
        if(!hasFuel) return;

        ref.active        = true;
        ref.fireIndex     = 0;
        ref.lastFireFrame = _root.帧计时器.当前帧数 + ref.fireDelay;

        // 开启/刷新 魔法·热 增益窗口
        var now = _root.帧计时器.当前帧数;
        ref.magicBuffActive   = true;
        ref.magicBuffEndFrame = now + ref.magicBuffFrames;
        target.兵器伤害类型 = "魔法";
        target.兵器魔法伤害属性 = "热";
    }, target);
};

// -------------------------------------------------------
// 公社爆燃钻矛 · 周期（新增：兵器五段单发逻辑）
// -------------------------------------------------------
_root.装备生命周期函数.公社爆燃钻矛周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var now:Number = _root.帧计时器.当前帧数;
    var state:String = target.getSmallState();

    // —— 维护魔法热伤增益窗口 ——
    if (ref.magicBuffActive && now > ref.magicBuffEndFrame) {
        // 从装备数据中恢复原始伤害类型（保留插件附加的属性）
        var weaponData:Object = target.刀数据.data;
        // _root.发布消息(weaponData.damagetype + " / " + weaponData.magictype);
        target.兵器伤害类型 = weaponData.damagetype ? weaponData.damagetype : null;
        target.兵器魔法伤害属性 = weaponData.magictype ? weaponData.magictype : null;
        if(_root.兵器使用检测(target)) {
            target.伤害类型 = target.兵器伤害类型;
            target.魔法伤害属性 = target.兵器魔法伤害属性;
        }
        ref.magicBuffActive = false;
    }

    var metal:MovieClip = target.刀_引用.金属件;
    metal._visible = ref.magicBuffActive;
    metal._alpha = ref.magicBuffActive ? Math.max(0, Math.min(100, Math.floor((ref.magicBuffEndFrame - now) / ref.magicBuffFrames * 100))) : 0;

    // —— 兵器五段单发逻辑 ——
    if (state == "兵器五段中") {
        // 进入兵器五段状态时初始化
        if (!ref.normalAttackActive) {
            ref.normalAttackActive     = true;
            ref.normalAttackFired      = false;
            ref.normalAttackStartFrame = now;
        }
        
        // 达到发射时机且未发射过
        if (!ref.normalAttackFired && (now - ref.normalAttackStartFrame >= ref.normalAttackFireDelay)) {
            // 复用战技的子弹发射逻辑
            var bp:Object = {};
            var k:String;
            for (k in ref.bullet) bp[k] = ref.bullet[k];

            var dir:Number = (target.方向 == "左") ? -1 : 1;
            var sx:Number = target._x + dir * ref.offsetX;
            var sy:Number = target._y + ref.offsetY;

            if (ref.flucX) sx += _root.随机偏移(ref.flucX);
            if (ref.flucY) sy += _root.随机偏移(ref.flucY);

            bp.shootX = sx;
            bp.shootY = sy;
            bp.shootZ = sy;

            _root.子弹区域shoot传递(bp);

            ref.normalAttackFired = true;  // 标记已发射，确保只发1发
        }
    } else {
        // 离开兵器五段状态时复位
        if (ref.normalAttackActive) {
            ref.normalAttackActive = false;
            ref.normalAttackFired  = false;
        }
    }

    // —— 战技连发逻辑 ——
    if (!ref.active) return;

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