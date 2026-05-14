

_root.装备生命周期函数.RShG4初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    PlacementVisual.hookVisualUpdate(target, "长枪_引用", ref, _root.装备生命周期函数.RShG4视觉更新);
};

_root.装备生命周期函数.RShG4周期 = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;

    _root.装备生命周期函数.RShG4视觉更新(ref);
};

_root.装备生命周期函数.RShG4视觉更新 = function(ref:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    gun.弹头._visible = !(target.长枪属性.capacity == target[ref.装备类型].value.shot);
    gun.gotoAndStop(target.攻击模式 === "长枪" ? 1 : 2);
    if(target._xscale > 0) {
        gun.文字1._xscale = 100;
        gun.文字2._xscale = 100;
    } else {
        gun.文字1._xscale = -100;
        gun.文字2._xscale = -100;
    }
};