import org.flashNight.neur.Event.*;

_root.装备生命周期函数.M134初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    ref.gunFrame = 1;
    ref.gunPlaying = false;
    ref.fireCount = 0; // 连射计数
    ref.maxCount = 29;  // 质数
	ref.shootCount = 5; // 每次射击增加的连射计数
    
    target.dispatcher.subscribe("长枪射击", function() {
        ref.gunPlaying = true;
		ref.fireCount = Math.min(ref.fireCount + ref.shootCount, ref.maxCount); // 限制最大连射次数
    });
};

_root.装备生命周期函数.M134周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    var gunAnim:MovieClip = gun.动画;
    
    // 根据连射次数计算转速
    var currentSpeed = ref.fireCount * 0.1;
    
	ref.gunFrame += currentSpeed;
	
	if(ref.gunFrame > gunAnim._totalFrames) {
		ref.gunFrame = ref.gunFrame % gunAnim._totalFrames;
	}

	if(!ref.gunPlaying) {
		ref.fireCount = Math.max(0, ref.fireCount - 0.33); // 逐渐降低连射计数
	}

    // _root.发布消息(ref.gunFrame, currentSpeed, ref.fireCount);
    ref.gunPlaying = false; // 重置射击状态，等待下次射击信号
    gunAnim.gotoAndStop(Math.floor(ref.gunFrame));
};