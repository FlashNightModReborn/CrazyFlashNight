_root.装备生命周期函数.RPG初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    // RPG 这里走 placement 回调直接驱动周期函数（非视觉更新），需要带 param 实参，
    // PlacementVisual 1-参签名不适用，保留 DressupSubscriber 直调写法。
    DressupSubscriber.onPlacement(target, "长枪_引用", function() {
        _root.装备生命周期函数.RPG周期(ref, param);
    });
};

_root.装备生命周期函数.RPG周期 = function(ref:Object, param:Object) {
    EquipmentTick.cleanup(ref);
    
    var target:MovieClip = ref.自机;
    target.长枪_引用.弹头._visible = !(target.长枪属性.capacity == target[ref.装备类型].value.shot);
};