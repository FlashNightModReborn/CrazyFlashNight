_root.装备生命周期函数.P90初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    ref.modeObject = { 双枪:true, 手枪:true, 手枪2:true };
    ref.gunString = ref.装备类型 + "_引用";

    MagazineFrameSync.init(ref);

    PlacementVisual.hookVisualUpdate(target, ref.gunString, ref, _root.装备生命周期函数.P90视觉更新);
};

_root.装备生命周期函数.P90周期 = function(ref:Object, param:Object) {
    if (!EquipmentTick.open(ref)) return;

    _root.装备生命周期函数.P90视觉更新(ref);
};

_root.装备生命周期函数.P90视觉更新 = function(ref:Object) {
    MagazineFrameSync.apply(ref);
};
