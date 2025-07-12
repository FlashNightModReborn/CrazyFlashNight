_root.装备生命周期函数.Jackhammer初始化 = function(ref:Object, param:Object) {
};

_root.装备生命周期函数.Jackhammer周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    var laser:MovieClip = gun.激光模组;

    laser._visible = (target.攻击模式 === "长枪");
};