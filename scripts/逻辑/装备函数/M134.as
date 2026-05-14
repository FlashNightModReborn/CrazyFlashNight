_root.装备生命周期函数.M134初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

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
    });

    PlacementVisual.hookVisualUpdate(target, "长枪_引用", ref, _root.装备生命周期函数.M134视觉更新);
};

_root.装备生命周期函数.M134周期 = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;

    BladeFireSpinController.tick(ref, ref.自机.长枪_引用.动画);

    _root.装备生命周期函数.M134视觉更新(ref);
};

_root.装备生命周期函数.M134视觉更新 = function(ref:Object) {
    var gun:MovieClip = ref.自机.长枪_引用;
    if (gun == undefined || gun.动画 == undefined) return;
    var gunAnim:MovieClip = gun.动画;

    if (ref.fireCount > 0) {
        gunAnim.gotoAndStop(Math.floor(ref.gunFrame));
    } else if (gunAnim._currentFrame != 1) {
        gunAnim.gotoAndStop(1);
    }
};