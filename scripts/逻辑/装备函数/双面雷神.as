

_root.装备生命周期函数.双面雷神初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    target.syncRequiredEquips.长枪_引用 = true;
    target.dispatcher.subscribe("StatusChange", function() {
       _root.装备生命周期函数.双面雷神视觉(ref);
   });
};

_root.装备生命周期函数.双面雷神视觉 = function(ref:Object) {

};

_root.装备生命周期函数.双面雷神周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);

};