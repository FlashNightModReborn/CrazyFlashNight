// 主长枪射击事件驱动的有限动画：状态只由射击/周期推进，placement 只同步画面。
_root.装备生命周期函数.长枪射击动画绑定有效 = function(ref:Object):Boolean {
    var actor:MovieClip = ref.自机;
    return ref.animationActive && actor.version === ref.animationVersion
        && actor.长枪 === ref.animationEquipment;
};

_root.装备生命周期函数.长枪射击动画初始化 = function(ref:Object, param:Object):Boolean {
    if (ref.animationShotHandler || ref.animationPlacementHandler) {
        _root.装备生命周期函数.长枪射击动画卸载(ref);
    }
    var actor:MovieClip = ref.自机;
    ref.animationLogEnabled = param.debug === true;
    ref.animationLogRemaining = 120;
    ref.animationIdle = 1;
    ref.animationStart = param.fireStart != undefined ? Math.floor(Number(param.fireStart)) : 2;
    ref.animationEnd = param.fireEnd != undefined ? Math.floor(Number(param.fireEnd)) : 8;
    ref.animationTarget = param.animationTarget != undefined ? String(param.animationTarget) : "动画";
    ref.animationContainer = param.instanceContainer ? String(param.instanceContainer) : "长枪_引用";
    ref.animationEquipment = actor.长枪;
    ref.animationVersion = actor.version;
    ref.animationFrame = 1;
    ref.animationStartTick = -1;
    ref.animationActive = false;
    if (!ref.animationEquipment || isNaN(ref.animationStart) || isNaN(ref.animationEnd)
        || ref.animationStart < 2 || ref.animationEnd <= ref.animationStart) {
        _root.装备生命周期函数.长枪射击动画日志(ref, "初始化拒绝", "参数或装备无效");
        return false;
    }
    ref.animationActive = true;
    _root.装备生命周期函数.长枪射击动画日志(ref, "初始化", "");

    ref.animationShotHandler = function(owner:MovieClip, weaponType:String):Void {
        _root.装备生命周期函数.长枪射击动画日志(ref, "射击回调",
            "owner相同=" + (owner === actor) + " 类型=" + weaponType);
        if (owner !== actor || !_root.装备生命周期函数.长枪射击动画绑定有效(ref)
            || !EquipmentFireIntent.isMainLongGunProcessShot(actor, weaponType)) return;
        // 每次已提交的主枪射击重新对齐击发帧；不排队、不忽略连发，也不改变弹药/伤害。
        ref.animationStartTick = _root.帧计时器.当前帧数;
        ref.animationFrame = ref.animationStart;
        _root.装备生命周期函数.长枪射击动画视觉更新(ref);
    };
    actor.dispatcher.subscribe("processShot", ref.animationShotHandler, ref);
    ref.animationPlacementHandler = PlacementVisual.hookVisualUpdate(
        actor, ref.animationContainer, ref, _root.装备生命周期函数.长枪射击动画视觉更新, ref);

    if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
    if (!ref.animationCleanup) {
        ref.animationCleanup = {动作:_root.装备生命周期函数.长枪射击动画卸载, 额外参数:ref};
    }
    var registered:Boolean = false;
    for (var i:Number = 0; i < ref.生命周期函数列表.length; i++) {
        if (ref.生命周期函数列表[i] === ref.animationCleanup) registered = true;
    }
    if (!registered) ref.生命周期函数列表.push(ref.animationCleanup);
    _root.装备生命周期函数.长枪射击动画视觉更新(ref);
    return true;
};

_root.装备生命周期函数.长枪射击动画周期 = function(ref:Object):Void {
    if (!EquipmentTick.open(ref)) return;
    if (ref.animationStartTick >= 0 || ref.animationLogWasPlaying) {
        _root.装备生命周期函数.长枪射击动画日志(ref, "周期开始", "");
    }
    ref.animationLogWasPlaying = ref.animationStartTick >= 0;
    if (!_root.装备生命周期函数.长枪射击动画绑定有效(ref)) {
        _root.装备生命周期函数.长枪射击动画卸载(ref);
        return;
    }
    if (ref.自机.攻击模式 != "长枪") {
        ref.animationFrame = ref.animationIdle;
        ref.animationStartTick = -1;
    } else if (ref.animationStartTick >= 0) {
        var age:Number = _root.帧计时器.当前帧数 - ref.animationStartTick;
        var span:Number = ref.animationEnd - ref.animationStart + 1;
        if (age < 0 || age >= span) {
            ref.animationFrame = ref.animationIdle;
            ref.animationStartTick = -1;
        } else {
            ref.animationFrame = ref.animationStart + age;
        }
    }
    _root.装备生命周期函数.长枪射击动画视觉更新(ref);
};

_root.装备生命周期函数.长枪射击动画视觉更新 = function(ref:Object):Void {
    if (!_root.装备生命周期函数.长枪射击动画绑定有效(ref)) return;
    var gun:MovieClip = ref.自机[ref.animationContainer];
    // 旧 holder 已卸载时等待下一次 placement，不缓存旧 MovieClip。
    if (!gun._parent) {
        if (ref.animationStartTick >= 0) _root.装备生命周期函数.长枪射击动画日志(ref, "视觉跳过", "枪引用未就绪");
        return;
    }
    var animation:MovieClip = ref.animationTarget == "" ? gun : gun[ref.animationTarget];
    if (!animation) {
        if (ref.animationStartTick >= 0) _root.装备生命周期函数.长枪射击动画日志(ref, "视觉跳过", "动画实例缺失");
        return;
    }
    var frame:Number = ref.自机.攻击模式 == "长枪" ? ref.animationFrame : ref.animationIdle;
    if (animation._totalframes < ref.animationEnd) frame = ref.animationIdle;
    animation.gotoAndStop(frame);
    if (ref.animationLogEnabled) {
        ref.animationLastVisualFrame = frame;
        ref.animationLastVisualClip = animation;
        if (ref.animationStartTick >= 0 || ref.animationLogWasPlaying) {
            _root.装备生命周期函数.长枪射击动画日志(ref, "视觉写入后", "");
        }
    }
};

_root.装备生命周期函数.长枪射击动画卸载 = function(ref:Object):Void {
    if (!ref) return;
    _root.装备生命周期函数.长枪射击动画日志(ref, "卸载", "");
    ref.animationFrame = ref.animationIdle;
    ref.animationStartTick = -1;
    _root.装备生命周期函数.长枪射击动画视觉更新(ref);
    ref.animationActive = false;
    var dispatcher:Object = ref.自机.dispatcher;
    if (dispatcher) {
        if (ref.animationShotHandler) dispatcher.unsubscribe("processShot", ref.animationShotHandler, ref);
        if (ref.animationPlacementHandler) dispatcher.unsubscribe(ref.animationContainer, ref.animationPlacementHandler, ref);
    }
    ref.animationShotHandler = null;
    ref.animationPlacementHandler = null;
};

// 物品 initParam.debug=true 时直接记录生命周期现场；每个 ref 最多 120 行。
_root.装备生命周期函数.长枪射击动画日志 = function(ref:Object, phase:String, extra:String):Void {
    if (!ref.animationLogEnabled || ref.animationLogRemaining <= 0) return;
    ref.animationLogRemaining--;
    var actor:MovieClip = ref.自机;
    var gun:MovieClip = actor[ref.animationContainer];
    var clip:MovieClip = ref.animationTarget == "" ? gun : gun[ref.animationTarget];
    var bounds:Object = clip.getBounds(clip);
    var message:String = "[枪械射击动画] 阶段=" + phase + " tick=" + _root.帧计时器.当前帧数
        + " 装备=" + ref.装备名称 + " 模式=" + actor.攻击模式
        + " 有效=" + _root.装备生命周期函数.长枪射击动画绑定有效(ref)
        + " 版本=" + ref.animationVersion + "/" + actor.version
        + " 装备相同=" + (actor.长枪 === ref.animationEquipment)
        + " 状态帧=" + ref.animationFrame + " 上次写入=" + ref.animationLastVisualFrame
        + " 实际帧=" + clip._currentframe + "/" + clip._totalframes
        + " 引用相同=" + (clip === ref.animationLastVisualClip)
        + " 可见=" + clip._visible + "/" + gun._visible + "/" + gun._parent._visible
        + " xMin=" + bounds.xMin + " 动画=" + clip
        + " 父帧=" + gun._parent._currentframe + "/" + gun._parent._totalframes
        + (extra ? " " + extra : "");
    if (_root.服务器.发布服务器消息) _root.服务器.发布服务器消息(message);
    else trace(message);
};
