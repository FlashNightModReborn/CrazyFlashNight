_root.装备生命周期函数.混凝土切割机初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // --- 从武器数据读取伤害类型配置 ---
    var weaponData:Object = target.长枪数据;
    var skillData:Object = weaponData.skill;

    // 基础伤害类型（从 <data> 读取，用于常规模式）
    ref.基础伤害类型 = weaponData.data.damagetype || "破击";
    ref.基础魔法属性 = weaponData.data.magictype || "装甲";

    // 超载伤害类型（从 <skill> 读取，用于超载模式）
    ref.超载伤害类型 = param.damagetype || "魔法";
    ref.超载魔法属性 = param.magictype || "冲";

    // --- 性能参数常量化 ---
    ref.maxSpinCount = param.maxSpinCount || 29;            // 最大连射计数
    ref.spinUpAmount = param.spinUpAmount || 5;             // 每次射击增加的连射计数
    ref.spinSpeedFactor = param.spinSpeedFactor || 0.1;     // 连射计数转换为转速的系数
    ref.spinDownRate = param.spinDownRate || 0.33;          // 连射计数的自然衰减率

    // --- 状态变量 ---
    ref.gunFrame = 1;              // 当前动画帧 (浮点数)
    ref.fireCount = 0;             // 当前连射计数
    ref.isFiring = false;          // 是否正在射击

    // 订阅射击事件
    target.dispatcher.subscribe("长枪射击", function() {
        ref.isFiring = true; // 标记本帧正在射击
        var target:MovieClip = ref.自机;
        var gun:MovieClip = target.长枪_引用;
        var prop:Object = target.man.子弹属性;
        var area:MovieClip = gun.枪口位置;

        var flag:Boolean = target.混凝土切割机超载打击许可;
        spark._visible = true;
        prop.区域定位area = area;

        // 使用配置的伤害类型（而非硬编码）
        prop.伤害类型 = flag ? ref.超载伤害类型 : ref.基础伤害类型;
        prop.魔法伤害属性 = flag ? ref.超载魔法属性 : ref.基础魔法属性;
    });

    PlacementVisual.hookVisualUpdate(target, "长枪_引用", ref, _root.装备生命周期函数.混凝土切割机视觉更新);
};

_root.装备生命周期函数.混凝土切割机周期 = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;

    var target:MovieClip = ref.自机;

    (ref.isFiring && (ref.fireCount = Math.min(ref.fireCount + ref.spinUpAmount, ref.maxSpinCount))) ||
    (ref.fireCount = Math.max(0, ref.fireCount - ref.spinDownRate));

    // 推进动画帧（仅 state）
    if (ref.fireCount > 0) {
        var gun:MovieClip = target.长枪_引用;
        var currentSpeed:Number = ref.fireCount * ref.spinSpeedFactor;
        ref.gunFrame += currentSpeed;

        if (gun && ref.gunFrame > gun._totalFrames) {
            ref.gunFrame = ((ref.gunFrame - 1) % gun._totalFrames) + 1;
        }
    }

    // 重置射击状态
    ref.isFiring = false;

    // 超载剩余时间衰减
    if (target.混凝土切割机超载打击许可) {
        if (--target.混凝土切割机超载打击剩余时间 < 0) {
            target.混凝土切割机超载打击许可 = false;
        }
    }

    _root.装备生命周期函数.混凝土切割机视觉更新(ref);
};

_root.装备生命周期函数.混凝土切割机视觉更新 = function(ref:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    if (!gun) return;
    var spark:MovieClip = gun.火花;

    if (ref.fireCount > 0) {
        gun.gotoAndStop(Math.floor(ref.gunFrame));
        spark.play();
    } else if (gun._currentFrame != 1) {
        gun.gotoAndStop(1);
    }

    var flag:Boolean = target.混凝土切割机超载打击许可;
    var clip:MovieClip = gun.锯片.晶片;
    var bigClip:MovieClip = gun.锯盘;

    if (flag) {
        // 0‑1 归一化进度（依据剩余时间派生，幂等）
        var prog:Number = 1 - (target.混凝土切割机超载打击剩余时间 /
                            target.混凝土切割机超载打击持续时间);

        var ramp:Number = 0.05;      // 峰值所处的时间占比（越小 = 越快亮）
        var fade:Number;             // 0‑1 的可见度系数

        if (prog <= ramp) {
            fade = prog / ramp;                 // 快速线性冲峰
        } else {
            var t:Number = (prog - ramp) / (1 - ramp);
            fade = Math.pow(1 - t, 2);   // 二次幂衰减
        }

        var fadeAlpha:Number = 10 + 90 * fade;
        clip._alpha = fadeAlpha;
        spark._alpha = fadeAlpha;
    }

    clip._visible = flag;
    bigClip._visible = flag;
    spark._visible = flag;
};