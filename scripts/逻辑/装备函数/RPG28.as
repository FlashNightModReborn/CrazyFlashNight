

_root.装备生命周期函数.RPG28初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    target.syncRequiredEquips.长枪_引用 = true;
    target.dispatcher.subscribe("StatusChange", function() {
       _root.装备生命周期函数.RPG28周期(ref,param);
   });
};

_root.装备生命周期函数.RPG28周期 = function(ref:Object, param:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    gun.gotoAndStop(target.攻击模式 === "长枪" ? 1 : 2);
};