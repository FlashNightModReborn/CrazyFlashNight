_root.装备生命周期函数.Six12_Matryoshka初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    ref.fireCount = 0;             // 当前连射计数

    // 订阅射击事件
    target.dispatcher.subscribe("长枪射击", function() {
        var gun:MovieClip = target.长枪_引用;
        var fireCount:Number = ref.fireCount++;
        
        gun.枪口位置 = (fireCount % 2 == 0) ? gun.枪口位置0 : gun.枪口位置1;
    });
};

_root.装备生命周期函数.Six12_Matryoshka周期 = function(ref:Object, param:Object) {
    _root.装备生命周期函数.移除异常周期函数(ref);
}; 