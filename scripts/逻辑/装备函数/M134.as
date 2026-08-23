_root.装备生命周期函数.M134初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    // 同一 ref 被防御性重入时，先撤销旧 callback；正常换装则由生命周期 teardown 调用同一入口。
    if (ref.旧长枪射击回调 || ref.成功射击回调 || ref.视觉更新回调) {
        _root.装备生命周期函数.M134移除射击订阅(ref);
    }

    // --- 性能参数常量化 ---
    ref.maxSpinCount = param.maxSpinCount || 29;            // 最大连射计数 
    ref.spinUpAmount = param.spinUpAmount || 5;             // 每次射击增加的连射计数 
    ref.spinSpeedFactor = param.spinSpeedFactor || 0.1;     // 连射计数转换为转速的系数
    ref.spinDownRate = param.spinDownRate || 0.33;          // 连射计数的自然衰减率

    // --- 状态变量 ---
    ref.gunFrame = 1;              // 当前动画帧 (浮点数)
    ref.fireCount = 0;             // 当前连射计数
    ref.isFiring = false;          // 是否正在射击 

    // 兼容旧时间轴预射击事件；同时接受 WeaponFireCore 的成功发射事件，
    // 让非人形单位和后续佣兵不依赖某一套动作帧，并排除长枪副武器。
    ref.旧长枪射击回调 = function() {
        ref.isFiring = true;
    };
    ref.成功射击回调 = function(owner:MovieClip, weaponType:String) {
        if (EquipmentFireIntent.isMainLongGunProcessShot(target, weaponType)) {
            ref.isFiring = true;
        }
    };
    var 旧事件已订阅:Boolean = target.dispatcher.subscribe("长枪射击", ref.旧长枪射击回调, ref);
    var 成功事件已订阅:Boolean = target.dispatcher.subscribe("processShot", ref.成功射击回调, ref);
    ref.视觉更新回调 = PlacementVisual.hookVisualUpdate(
        target, "长枪_引用", ref, _root.装备生命周期函数.M134视觉更新, ref);

    if (旧事件已订阅 || 成功事件已订阅 || ref.视觉更新回调) {
        if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
        if (!ref.M134订阅卸载对象) {
            ref.M134订阅卸载对象 = {
                动作:_root.装备生命周期函数.M134移除射击订阅,
                额外参数:ref
            };
        }
        var 已登记卸载:Boolean = false;
        for (var i:Number = 0; i < ref.生命周期函数列表.length; i++) {
            if (ref.生命周期函数列表[i] === ref.M134订阅卸载对象) {
                已登记卸载 = true;
                break;
            }
        }
        if (!已登记卸载) ref.生命周期函数列表.push(ref.M134订阅卸载对象);
    }
};

_root.装备生命周期函数.M134移除射击订阅 = function(ref:Object):Void {
    if (!ref) return;
    var target:MovieClip = ref.自机;
    var dispatcher:Object = target ? target.dispatcher : null;
    if (dispatcher) {
        if (ref.旧长枪射击回调) {
            dispatcher.unsubscribe("长枪射击", ref.旧长枪射击回调, ref);
        }
        if (ref.成功射击回调) {
            dispatcher.unsubscribe("processShot", ref.成功射击回调, ref);
        }
        if (ref.视觉更新回调) {
            dispatcher.unsubscribe("长枪_引用", ref.视觉更新回调, ref);
        }
    }
    ref.旧长枪射击回调 = null;
    ref.成功射击回调 = null;
    ref.视觉更新回调 = null;
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
