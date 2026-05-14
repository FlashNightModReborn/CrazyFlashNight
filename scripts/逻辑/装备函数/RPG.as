_root.装备生命周期函数.RPG初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    PlacementVisual.hookVisualUpdate(target, "长枪_引用", ref,param, _root.装备生命周期函数.RPG周期);
};

_root.装备生命周期函数.RPG周期 = function(ref:Object, param:Object) {
    EquipmentTick.cleanup(ref);
    
    var target:MovieClip = ref.自机;
    target.长枪_引用.弹头._visible = !(target.长枪属性.capacity == target[ref.装备类型].value.shot);
};