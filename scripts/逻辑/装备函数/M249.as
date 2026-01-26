_root.装备生命周期函数.M249初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    
    // 订阅射击事件
    target.dispatcher.subscribe("长枪射击", function() {
        
        var gun:MovieClip = target.长枪_引用;
        var gunAnim:MovieClip = gun.动画;
        gunAnim.play();
    });

    ref.capacity = target["长枪弹匣容量"];
};

_root.装备生命周期函数.M249周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);
    
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    var gunAnim:MovieClip = gun.动画;
    var laser:MovieClip = gun.激光模组;

    gunAnim._visible = !(target.长枪.value.shot == ref.capacity);
};