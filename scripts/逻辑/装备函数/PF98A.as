﻿

_root.装备生命周期函数.PF98A初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    target.syncRequiredEquips.长枪_引用 = true;
    target.dispatcher.subscribe("StatusChange", function() {
       _root.装备生命周期函数.PF98A周期(ref,param);
   });
};

_root.装备生命周期函数.PF98A周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    gun.弹头._visible = !(target.长枪属性.capacity == target[ref.装备类型].value.shot);
    gun.gotoAndStop(target.攻击模式 === "长枪" ? 1 : 2);
};