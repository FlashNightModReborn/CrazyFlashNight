_root.装备生命周期函数.G111初始化 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;

    ref.gunAnimFrame = 1;
    ref.gunFrame = 1;
    ref.chargeCount = 0;
    ref.chargeCountMax = 30;
    target.chargeComplete = false;
    
    // 订阅射击事件
    target.dispatcher.subscribe("长枪射击", function() {
        ref.gunAnimFrame = 2;
        target.chargeComplete = false;
        ref.chargeCount = 0;
    });
};
_root.装备生命周期函数.G111周期 = function(ref:Object, param:Object) {
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    var gunAnim:MovieClip = gun.动画;
    var laser:MovieClip = gun.激光模组;
    var barrel:MovieClip = gun.枪管;

    if(target.攻击模式 === "长枪") {
        laser._visible = true;
        if(_root.按键输入检测(target, _root.武器变形键)) {
            ref.chargeCount++
        } else if(ref.chargeCount > 0) {
            ref.chargeCount--;
        }

        if(ref.chargeCount >= ref.chargeCountMax) {
            target.chargeComplete = true;
        }
    } else {
        laser._visible = false;
        target.chargeComplete = false;
        if(ref.chargeCount > 0) ref.chargeCount--;
    }

    if(target.chargeComplete) {
        if(ref.gunFrame < gun._totalFrames) {
            ref.gunFrame++;
        }
    } else {
        if(ref.gunFrame > 1) {
            ref.gunFrame--;
        }
    }

    gun.gotoAndStop(ref.gunFrame);

    if(ref.gunAnimFrame > 1) {
        gunAnim.gotoAndStop(ref.gunAnimFrame);
        barrel.gotoAndStop(ref.gunAnimFrame);
        if(ref.gunAnimFrame >= gunAnim._totalFrames) {
            ref.gunAnimFrame = 1;
        } else {
            ref.gunAnimFrame++;
        }
    }
};