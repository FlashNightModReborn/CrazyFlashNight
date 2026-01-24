_root.装备生命周期函数.P90初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;    
    
    ref.modeObject = { 双枪:true, 手枪:true, 手枪2:true };

    var equipmentType:String = ref.装备类型;
    ref.gunString = equipmentType + "_引用";

    // 直接从装备数据读取弹容，以50发为基准计算比例
    var equipmentData = target[ref.装备类型 + "属性"];
    var bulletCapacity = equipmentData.capacity > 0 ? equipmentData.capacity : 50;
    ref.bulletRate = bulletCapacity / 50; // 以50发为基准的比例

    target.syncRequiredEquips[ref.gunString] = true;
    target.dispatcher.subscribe("StatusChange", function() {
       _root.装备生命周期函数.P90周期(ref,param);
       // _root.发布消息(ref.gunString)
   });
};

_root.装备生命周期函数.P90周期 = function(ref:Object, param:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);
    
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target[ref.gunString];

    var bulletFrame = target[ref.装备类型].value.shot;
    bulletFrame = Math.floor(bulletFrame / ref.bulletRate) + 1; // 应用子弹视觉比例
    gun.弹匣.gotoAndStop(bulletFrame);

    gun.激光模组._visible = !!ref.modeObject[target.攻击模式];
};