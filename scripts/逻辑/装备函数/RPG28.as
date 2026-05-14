

_root.装备生命周期函数.RPG28初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    PlacementVisual.hookVisualUpdate(target, "长枪_引用", ref, _root.装备生命周期函数.RPG28视觉更新);
};

_root.装备生命周期函数.RPG28周期 = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;

    _root.装备生命周期函数.RPG28视觉更新(ref);
};

_root.装备生命周期函数.RPG28视觉更新 = function(ref:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    gun.gotoAndStop(target.攻击模式 === "长枪" ? 1 : 2);
};
