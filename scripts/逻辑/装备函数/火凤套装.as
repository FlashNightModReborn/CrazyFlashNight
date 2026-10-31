// 帧脚本只接线；跨动作与卸载回调由 Huofeng classes 所有。
org.flashNight.arki.unit.Action.Huofeng.HuofengInput.install();
_root.装备生命周期函数.火凤套装准备 = function(effect:Object,target:MovieClip):Object {
    return org.flashNight.arki.unit.Action.Huofeng.HuofengSetRuntime.prepare(effect,target);
};
_root.装备生命周期函数.火凤组件初始化 = function(ref:Object,param:Object):String {
    return ref.套装上下文.initializeComponent(ref,param);
};
_root.装备生命周期函数.火凤组件周期 = function(ref:Object):Void {
    // The committed set owns this timer. Its class validates all five item
    // identities and teardown; a weapon-only version change is not unequip.
    ref.套装上下文.tick(ref);
};

// R9 长发归头部单件所有，五件套失效不移除仍在佩戴的长发。
_root.装备生命周期函数.火凤长发初始化 = function(ref:Object,param:Object):Void {
    org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.initialize(ref,param);
};
_root.装备生命周期函数.火凤长发周期 = function(ref:Object,param:Object):Void {
    org.flashNight.arki.unit.Action.Huofeng.HuofengHairEquipment.cycle(ref,param);
};
