// 初始化阶段：只配置常量与订阅事件
_root.装备生命周期函数.G111初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    
    // 初始帧和计数
    ref.gunFrame        = 1;
    ref.gunAnimFrame    = 1;
    ref.chargeCount     = 0;
    
    // 配置常量（可由 param 覆盖）
    ref.chargeCountMax  = param.chargeCountMax  || 30;
    ref.chargeStep      = param.chargeStep      || 1;
    ref.frameStep       = param.frameStep       || 1;
    
    target.chargeComplete = false;
    
    // 射击时重置充能与动效
    target.dispatcher.subscribe("长枪射击", function() {
        ref.gunAnimFrame    = 2;
        ref.chargeCount     = 0;
        target.chargeComplete = false;
    });

    PlacementVisual.hookVisualUpdate(target, "长枪_引用", ref, _root.装备生命周期函数.G111视觉更新);
};

// 每帧周期更新：充能 → 主枪帧 → 动画帧
_root.装备生命周期函数.G111周期 = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;

    var target:MovieClip = ref.自机;
    var gun:MovieClip    = target.长枪_引用;

    // —— 1. 充能逻辑 ——
    ChargeKeyAccumulator.tick(ref, target, _root.武器变形键, target.攻击模式 === "长枪");

    // —— 2. 主枪帧推进 ——
    if (target.chargeComplete) {
        if (ref.gunFrame < gun._totalFrames) {
            ref.gunFrame = Math.min(ref.gunFrame + ref.frameStep, gun._totalFrames);
        }
    } else {
        if (ref.gunFrame > 1) {
            ref.gunFrame = Math.max(ref.gunFrame - ref.frameStep, 1);
        }
    }

    // —— 3. 动画帧推进 —— （先记录显示帧，再推进 state）
    ref.gunAnimDisplayFrame = ref.gunAnimFrame;
    if (ref.gunAnimFrame > 1) {
        var gunAnimTotal:Number = gun.动画._totalFrames;
        if (gunAnimTotal && ref.gunAnimFrame >= gunAnimTotal) {
            ref.gunAnimFrame = 1;
        } else {
            ref.gunAnimFrame++;
        }
    }

    _root.装备生命周期函数.G111视觉更新(ref);
};

_root.装备生命周期函数.G111视觉更新 = function(ref:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip    = target.长枪_引用;
    if (!gun) return;

    var gunAnim:MovieClip= gun.动画;
    var barrel:MovieClip = gun.枪管;
    var laser:MovieClip  = gun.激光模组;

    laser._visible = (target.攻击模式 === "长枪");
    gun.gotoAndStop(ref.gunFrame);

    var displayFrame:Number = (ref.gunAnimDisplayFrame != undefined) ? ref.gunAnimDisplayFrame : ref.gunAnimFrame;
    if (displayFrame > 1) {
        gunAnim.gotoAndStop(displayFrame);
        barrel.gotoAndStop(displayFrame);
    }
};