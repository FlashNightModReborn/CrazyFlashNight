// 统合61共享class拥有全部持久回调，帧脚本仅注册同步入口。
_root.装备生命周期函数.统合61套装准备 = function(effect:Object,target:MovieClip):Object {
    return org.flashNight.arki.unit.UnitComponent.Initializer.UnifiedType61Runtime.prepare(effect,target);
};
_root.装备生命周期函数.统合61组件初始化 = function(ref:Object,param:Object):String {
    return ref.套装上下文.initializeComponent(ref,param);
};
_root.装备生命周期函数.统合61组件周期 = function(ref:Object):Void {
    if (!EquipmentTick.open(ref)) return;
    ref.套装上下文.tick(ref);
};
