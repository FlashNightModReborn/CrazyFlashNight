

_root.装备生命周期函数.PF98A初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    DressupSubscriber.onPlacement(target, "长枪_引用", function() {
        _root.装备生命周期函数.PF98A视觉更新(ref);
    });
};

_root.装备生命周期函数.PF98A周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);
    if (!VisualSync.beginTick(ref)) return;

    _root.装备生命周期函数.PF98A视觉更新(ref);
};

_root.装备生命周期函数.PF98A视觉更新 = function(ref:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    gun.弹头._visible = !(target.长枪属性.capacity == target[ref.装备类型].value.shot);
    gun.gotoAndStop(target.攻击模式 === "长枪" ? 1 : 2);
};