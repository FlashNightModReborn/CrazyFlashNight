// 血剑战斗逻辑只在装备周期结算；美术中的四路光效由本脚本定帧驱动。
_root.装备生命周期函数.血色光剑随机 = function():Boolean {
    return random(5) == 0;
};

_root.装备生命周期函数.血色光剑绑定有效 = function(ref:Object):Boolean {
    var actor:MovieClip = ref.自机;
    return ref.bloodActive && actor._parent && actor.version === ref.bloodVersion
        && actor[ref.装备类型] === ref.bloodEquipment;
};

_root.装备生命周期函数.血色光剑外观有效 = function(view:MovieClip):Boolean {
    return view._parent && view.刀口位置1._parent && view.刀口位置2._parent
        && view.刀口位置3._parent && view.剑体.fxGrip._totalframes == 54
        && view.剑体.fxBreath._totalframes == 84 && view.剑体.fxFlow._totalframes == 54
        && view.剑体.fxBurst._totalframes == 12;
};

_root.装备生命周期函数.血色光剑实例可见 = function(view:MovieClip, actor:MovieClip):Boolean {
    var node:MovieClip = view;
    while (node && node !== actor) {
        if (!node._visible) return false;
        node = node._parent;
    }
    return node === actor && actor._visible;
};

_root.装备生命周期函数.血色光剑光效定帧 = function(clip:MovieClip, enabled:Boolean, frame:Number):Void {
    if (!clip._parent) return;
    clip.gotoAndStop(enabled ? frame : 1);
    clip._visible = enabled;
    clip._alpha = enabled ? 100 : 0;
};

_root.装备生命周期函数.血色光剑停止外观 = function(view:MovieClip, ref:Object):Void {
    if (view._cf7BloodSwordOwner !== ref) return;
    var art:MovieClip = view.剑体;
    _root.装备生命周期函数.血色光剑光效定帧(art.fxGrip, false, 1);
    _root.装备生命周期函数.血色光剑光效定帧(art.fxBreath, false, 1);
    _root.装备生命周期函数.血色光剑光效定帧(art.fxFlow, false, 1);
    _root.装备生命周期函数.血色光剑光效定帧(art.fxBurst, false, 1);
    delete view._cf7BloodSwordOwner;
};

_root.装备生命周期函数.血色光剑视觉更新 = function(ref:Object):Void {
    if (!_root.装备生命周期函数.血色光剑绑定有效(ref)) {
        _root.装备生命周期函数.血色光剑卸载(ref);
        return;
    }
    var actor:MovieClip = ref.自机;
    var primary:MovieClip = actor.刀_引用;
    var secondary:MovieClip = actor.刀1_引用;
    var i:Number;
    for (i = 0; i < ref.bloodViews.length; i++) {
        var old:MovieClip = ref.bloodViews[i];
        if (old !== primary && old !== secondary) {
            _root.装备生命周期函数.血色光剑停止外观(old, ref);
        }
    }
    ref.bloodViews = [];
    var views:Array = [primary, secondary];
    for (i = 0; i < views.length; i++) {
        var view:MovieClip = views[i];
        if (i == 1 && view === primary) continue;
        if (!_root.装备生命周期函数.血色光剑外观有效(view)) continue;
        if (view._cf7BloodSwordOwner && view._cf7BloodSwordOwner !== ref) continue;
        view._cf7BloodSwordOwner = ref;
        ref.bloodViews.push(view);
        var visible:Boolean = _root.装备生命周期函数.血色光剑实例可见(view, actor);
        var drawn:Boolean = visible && view === primary && ref.bloodDrawn;
        var art:MovieClip = view.剑体;
        _root.装备生命周期函数.血色光剑光效定帧(art.fxGrip, visible, ref.bloodGripFrame);
        _root.装备生命周期函数.血色光剑光效定帧(art.fxBreath, drawn, ref.bloodBreathFrame);
        _root.装备生命周期函数.血色光剑光效定帧(art.fxFlow, drawn, ref.bloodFlowFrame);
        _root.装备生命周期函数.血色光剑光效定帧(art.fxBurst, drawn && ref.bloodBurstFrame > 0, ref.bloodBurstFrame);
    }
};

_root.装备生命周期函数.血色光剑初始化 = function(ref:Object, param:Object):Boolean {
    if (ref.bloodActive) _root.装备生命周期函数.血色光剑卸载(ref);
    var actor:MovieClip = ref.自机;
    if (ref.装备类型 != "刀" || !actor[ref.装备类型]) return false;
    ref.bloodEquipment = actor[ref.装备类型];
    ref.bloodVersion = actor.version;
    ref.bloodActive = true;
    ref.bloodRoll = _root.装备生命周期函数.血色光剑随机;
    ref.bloodGripFrame = 1;
    ref.bloodBreathFrame = 1;
    ref.bloodFlowFrame = 1;
    ref.bloodBurstFrame = 0;
    ref.bloodDrawn = Boolean(actor.man.兵器使用标签) || actor.状态 == "兵器攻击";
    ref.bloodViews = [];
    ref.bloodHandlers = [];
    var keys:Array = ["刀_引用", "刀1_引用"];
    for (var i:Number = 0; i < keys.length; i++) {
        ref.bloodHandlers.push({key:keys[i], handler:PlacementVisual.hookVisualUpdate(
            actor, keys[i], ref, _root.装备生命周期函数.血色光剑视觉更新, ref)});
    }
    if (!ref.生命周期函数列表) ref.生命周期函数列表 = [];
    if (!ref.bloodCleanup) {
        ref.bloodCleanup = {动作:_root.装备生命周期函数.血色光剑卸载, 额外参数:ref};
    }
    var registered:Boolean = false;
    for (i = 0; i < ref.生命周期函数列表.length; i++) {
        if (ref.生命周期函数列表[i] === ref.bloodCleanup) registered = true;
    }
    if (!registered) ref.生命周期函数列表.push(ref.bloodCleanup);
    _root.装备生命周期函数.血色光剑视觉更新(ref);
    return true;
};

_root.装备生命周期函数.血色光剑发射 = function(ref:Object, marker:MovieClip, hpCost:Number, bullet:String, power:Number):Void {
    var actor:MovieClip = ref.自机;
    var point:Object = {x:0, y:0};
    marker.localToGlobal(point);
    _root.gameworld.globalToLocal(point);
    // 沿用旧脚本：X取刀口，Y和Z取单位所在平面；自损不设额外保底。
    actor.hp -= hpCost;
    _root.子弹区域shoot("", 1, 0, "", bullet, power, 0, 100, "", actor._name,
        point.x, actor._y, actor._y, actor.是否为敌人 == true ? false : true, 1, "");
};

_root.装备生命周期函数.血色光剑结算 = function(ref:Object):Void {
    var actor:MovieClip = ref.自机;
    var view:MovieClip = actor.刀_引用;
    if (actor.状态 != "兵器攻击" || !_root.装备生命周期函数.血色光剑外观有效(view)
        || !_root.装备生命周期函数.血色光剑实例可见(view, actor)) return;
    var triggered:Boolean = false;
    // 两路仍分别在每个攻击帧作一次五择一；两路成功均结算，不改为每刀一次。
    if (ref.bloodRoll()) {
        _root.装备生命周期函数.血色光剑发射(ref, view.刀口位置3, 3, "血爆炸", 999);
        triggered = true;
    }
    if (ref.bloodRoll()) {
        _root.装备生命周期函数.血色光剑发射(ref, view.刀口位置2, 1, "血滴落", 100);
        triggered = true;
    }
    // 合并的只有视觉：播放中的爆发保留进度，不因高频触发反复退回首帧。
    if (triggered && ref.bloodBurstFrame == 0) ref.bloodBurstFrame = 1;
};

_root.装备生命周期函数.血色光剑周期 = function(ref:Object):Void {
    if (!EquipmentTick.open(ref)) return;
    if (!_root.装备生命周期函数.血色光剑绑定有效(ref)) {
        _root.装备生命周期函数.血色光剑卸载(ref);
        return;
    }
    var actor:MovieClip = ref.自机;
    ref.bloodDrawn = Boolean(actor.man.兵器使用标签) || actor.状态 == "兵器攻击";
    ref.bloodGripFrame = ref.bloodGripFrame % 54 + 1;
    if (ref.bloodDrawn) {
        ref.bloodBreathFrame = ref.bloodBreathFrame % 84 + 1;
        ref.bloodFlowFrame = ref.bloodFlowFrame % 54 + 1;
        if (ref.bloodBurstFrame > 0 && ++ref.bloodBurstFrame >= 12) ref.bloodBurstFrame = 0;
        _root.装备生命周期函数.血色光剑结算(ref);
    } else {
        ref.bloodBreathFrame = 1;
        ref.bloodFlowFrame = 1;
        ref.bloodBurstFrame = 0;
    }
    _root.装备生命周期函数.血色光剑视觉更新(ref);
};

_root.装备生命周期函数.血色光剑卸载 = function(ref:Object):Void {
    if (!ref) return;
    ref.bloodActive = false;
    ref.bloodBurstFrame = 0;
    for (var i:Number = 0; i < ref.bloodViews.length; i++) {
        _root.装备生命周期函数.血色光剑停止外观(ref.bloodViews[i], ref);
    }
    for (i = 0; i < ref.bloodHandlers.length; i++) {
        var entry:Object = ref.bloodHandlers[i];
        ref.自机.dispatcher.unsubscribe(entry.key, entry.handler, ref);
    }
    ref.bloodViews = [];
    ref.bloodHandlers = [];
};
