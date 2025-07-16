import org.flashNight.neur.Event.*;

_root.装备生命周期函数.G11初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    
    // 订阅射击事件
    target.dispatcher.subscribe("长枪射击", function() {
        var gun:MovieClip = target.长枪_引用;
        gun.gotoAndPlay(2);
    });

    ref.capacity = target["长枪弹匣容量"];
};
