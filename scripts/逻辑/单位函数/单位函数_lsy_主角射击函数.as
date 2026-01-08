import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.item.*;
import org.flashNight.neur.ScheduleTimer.*;

/**
 * 单位函数_lsy_主角射击函数.as
 *
 * 重构后的主角射击相关函数
 * 将原有功能分拆到不同的类中管理：
 * 1. ShootCore - 统一管理射击核心功能
 * 2. ShootInitCore - 管理武器初始化逻辑
 * 3. WeaponStateManager - 管理武器状态判断逻辑
 * 4. ReloadManager - 管理换弹和弹药显示逻辑
 */

// --- 目前未被使用，留着以备其他资源swf需要使用
_root.主角函数.长枪射击 = WeaponFireCore.LONG_GUN_SHOOT;
_root.主角函数.手枪射击 = WeaponFireCore.PISTOL_SHOOT;
_root.主角函数.手枪2射击 = WeaponFireCore.PISTOL2_SHOOT;


// 初始化长枪射击函数
_root.主角函数.初始化长枪射击函数 = function():Void {
    /*
    var instance:EnhancedCooldownWheel = EnhancedCooldownWheel.I();

    _root.发布消息("初始化长枪射击函数",this.keepshooting,this.keepshooting2,this.taskLabel.结束射击后摇);

    // 清理可能干扰的帧计时器任务
    instance.removeTask(this.keepshooting);
    instance.removeTask(this.keepshooting2);
    instance.removeTask(this.taskLabel.结束射击后摇);
    // _root.发布消息("初始化长枪射击函数");

    */
    ShootInitCore.initLongGun(this, _parent);
};

// 初始化手枪射击函数
_root.主角函数.初始化手枪射击函数 = function():Void {
    /*
    var instance:EnhancedCooldownWheel = EnhancedCooldownWheel.I();

    _root.发布消息("初始化手枪射击函数",this.keepshooting,this.keepshooting2,this.taskLabel.结束射击后摇);

    // 清理可能干扰的帧计时器任务
    instance.removeTask(this.keepshooting);
    instance.removeTask(this.keepshooting2);
    instance.removeTask(this.taskLabel.结束射击后摇);
    // _root.发布消息("初始化手枪射击函数");
    */
    ShootInitCore.initPistol(this, _parent);
};

// 初始化手枪2射击函数
_root.主角函数.初始化手枪2射击函数 = function():Void {
    /*
    var instance:EnhancedCooldownWheel = EnhancedCooldownWheel.I();

    _root.发布消息("初始化手枪2射击函数",this.keepshooting,this.keepshooting2,this.taskLabel.结束射击后摇);

    // 清理可能干扰的帧计时器任务
    instance.removeTask(this.keepshooting);
    instance.removeTask(this.keepshooting2);
    instance.removeTask(this.taskLabel.结束射击后摇);
    // _root.发布消息("初始化手枪2射击函数");
    */
    ShootInitCore.initPistol2(this, _parent);
};

// 初始化双枪射击函数
_root.主角函数.初始化双枪射击函数 = function():Void {
    /*
    var instance:EnhancedCooldownWheel = EnhancedCooldownWheel.I();

    _root.发布消息("初始化双枪射击函数",this.keepshooting,this.keepshooting2,this.taskLabel.结束射击后摇);

    // 清理可能干扰的帧计时器任务
    instance.removeTask(this.keepshooting);
    instance.removeTask(this.keepshooting2);
    instance.removeTask(this.taskLabel.结束射击后摇);
    // _root.发布消息("初始化双枪射击函数");
    */
    ShootInitCore.initDualGun(this, _parent);
};



// 临时放置的初始化敌人射击函数
_root.敌人函数.初始化并开始射击 = function():Void {
    var 自机 = _parent;
    var 攻击对象 = _root.gameworld[_parent.攻击目标];

    自机.长枪射击 = WeaponFireCore.LONG_GUN_SHOOT;
    ShootInitCore.initLongGun(this, _parent);

    自机.上行 = false;
    自机.下行 = false;
    自机.动作A = true;
    
    this.射击许可标签.timer = 30;
    // 临时糊一个小ai在这
    this.射击许可标签.onEnterFrame = function(){
        this.timer--;
        if(this.timer <= 0){
            this.timer = 30;
        
            var dx = 攻击对象._x - 自机._x;
            if(自机.方向 == "左") dx = -dx;
            var dz = Math.abs(攻击对象.Z轴坐标 - 自机.Z轴坐标);

            if(dx <= 0 || dz >= 自机.y轴攻击范围){
                delete this.onEnterFrame;
                自机.动作A = false;
                自机.动画完毕();
            }
        }
    }

    this.开始射击();
};

