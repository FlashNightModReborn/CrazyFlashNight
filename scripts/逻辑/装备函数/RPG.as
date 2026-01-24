_root.装备生命周期函数.RPG初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    target.syncRequiredEquips.长枪_引用 = true;
    target.dispatcher.subscribe("StatusChange", function() {
       _root.装备生命周期函数.RPG周期(ref,param);
   });
};

_root.装备生命周期函数.RPG周期 = function(ref:Object, param:Object) {
    //_root.装备生命周期函数.移除异常周期函数(ref);
    
    var target:MovieClip = ref.自机;
    target.长枪_引用.弹头._visible = !(target.长枪属性.capacity == target[ref.装备类型].value.shot);
};