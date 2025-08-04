import org.flashNight.neur.Event.*;

_root.装备生命周期函数.AR57初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;    
    
    ref.modeObject = { 长枪:true};

    var equipmentType:String = ref.装备类型;
    ref.gunString = equipmentType + "_引用";

    var equipmentCountString:String = equipmentType + "射击次数";

    // 直接从装备数据读取弹容，以50发为基准计算比例
    var equipmentData = _root.getItemData(target[ref.装备类型]);
    var bulletCapacity = equipmentData.data.capacity > 0 ? Number(equipmentData.data.capacity) : 50;
    ref.bulletRate = bulletCapacity / 50; // 以50发为基准的比例
    ref.equipmentCountString = equipmentCountString;
};

_root.装备生命周期函数.AR57周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target[ref.gunString];

    var bulletFrame = target[ref.equipmentCountString][target[ref.装备类型]];
    bulletFrame = bulletFrame / ref.bulletRate  + 1; // 应用子弹视觉比例
    gun.弹匣.gotoAndStop(Math.floor(bulletFrame));

    gun.激光模组._visible = !!ref.modeObject[target.攻击模式];
};