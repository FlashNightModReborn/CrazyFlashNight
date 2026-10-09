// 光效生命周期只控制显示与光照投影，不修改装备数值或战技槽。
_root.装备生命周期函数.装备光源初始化 = function(ref:Object, param:Object):Boolean {
    return org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController.initialize(ref, param);
};
_root.装备生命周期函数.装备光源周期 = function(ref:Object):Void {
    org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController.tick(ref);
};

_root.装备生命周期函数.装备光源载入 = function(beam:MovieClip, slot:String):Void {
    org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentLightController.beamLoaded(beam,slot);
};

_root.装备生命周期函数.装备自发光初始化 = function(ref:Object, param:Object):Boolean {
    return org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissiveController.initialize(ref, param);
};
_root.装备生命周期函数.装备自发光周期 = function(ref:Object):Void {
    org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.EquipmentEmissiveController.tick(ref);
};
