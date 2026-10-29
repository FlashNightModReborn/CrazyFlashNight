
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


// 独立固定骨架的武器适配入口；只清理该单位的标准射击调度，不操作库存。
_root.主角函数.清理射击任务 = function(target:MovieClip, preserveCooldown:Boolean):Void {
    ShootCore.cleanup(target, preserveCooldown);
};

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

// 固定骨架的混合武器入口：只初始化标准手枪，不改变单位的长枪攻击模式。
_root.主角函数.初始化混合手枪 = function():Void {
    var unit:MovieClip = _parent;
    WeaponAmmoRuntime.ensure(unit, "手枪");
    this.子弹属性2 = ShootInitCore.generateBulletProps(unit, "手枪", unit.手枪属性, {});
    this.副手射击速度 = unit.手枪属性.interval;
    this.副手使用弹匣名称 = unit.手枪属性.clipname;
    this.副手是否单发 = unit.手枪属性.singleshoot;
    this.副手剩余弹匣数 = ShootInitCore.resolveMagazineStock(unit, this.副手使用弹匣名称);
};


// 精英反身动作保留长枪状态，只投影真实的两个手枪槽。
_root.主角函数.初始化混合双枪 = function():Void {
    var unit:MovieClip = _parent;
    WeaponAmmoRuntime.ensure(unit, "手枪");
    WeaponAmmoRuntime.ensure(unit, "手枪2");
    this.子弹属性 = ShootInitCore.generateBulletProps(unit, "手枪", unit.手枪属性, {});
    this.主手射击速度 = unit.手枪属性.interval;
    this.主手使用弹匣名称 = unit.手枪属性.clipname;
    this.主手是否单发 = unit.手枪属性.singleshoot;
    this.主手剩余弹匣数 = ShootInitCore.resolveMagazineStock(unit, this.主手使用弹匣名称);
    if (unit.eliteSidearmEnabled()) {
        this.子弹属性2 = ShootInitCore.generateBulletProps(unit, "手枪2", unit.手枪2属性, {});
        this.副手射击速度 = unit.手枪2属性.interval;
        this.副手使用弹匣名称 = unit.手枪2属性.clipname;
        this.副手是否单发 = unit.手枪2属性.singleshoot;
        this.副手剩余弹匣数 = ShootInitCore.resolveMagazineStock(unit, this.副手使用弹匣名称);
    }
    this.主手换弹匣 = ReloadManager.createHandReloadFunction(this, unit, _root,
        {handPrefix:"主手", weaponType:"手枪"}, null);
    this.副手换弹匣 = ReloadManager.createHandReloadFunction(this, unit, _root,
        {handPrefix:"副手", weaponType:"手枪2"}, null);
};

_root.主角函数.取消混合换弹 = function():Void {
    ReloadManager.cancelReload(this, false);
};

// ============================================================
// 换弹负担系统 (Reload Burden System)
// 已迁移到 ReloadManager 类，此处保留桥接函数以保持向后兼容性
// Migrated to ReloadManager class, bridge functions kept for backward compatibility
// ============================================================

/**
 * 桥接函数：初始化换弹负担系统
 * Bridge: Initialize reload burden system
 *
 * 实际实现：ReloadManager.initReloadBurden()
 * Actual implementation: ReloadManager.initReloadBurden()
 */
_root.主角函数.初始化换弹负担 = function(
    target:MovieClip,
    初始帧:Number,
    门禁帧:Number,
    回跳帧:Number,
    结束帧:Number,
    音乐帧数组:Array
):Void {
    ReloadManager.initReloadBurden(target, 初始帧, 门禁帧, 回跳帧, 结束帧, 音乐帧数组);
};

/**
 * 桥接函数：换弹门禁
 * Bridge: Reload gate checkpoint
 *
 * 实际实现：ReloadManager.handleReloadGate()
 * Actual implementation: ReloadManager.handleReloadGate()
 */
_root.主角函数.换弹门禁 = function(target:MovieClip):Void {
    ReloadManager.handleReloadGate(target);
};

/**
 * 桥接函数：换弹帧率控制
 * Bridge: Reload frame rate control
 *
 * 实际实现：ReloadManager.controlReloadFrameRate()
 * Actual implementation: ReloadManager.controlReloadFrameRate()
 */
_root.主角函数.换弹帧率控制 = function(target:MovieClip):Void {
    ReloadManager.controlReloadFrameRate(target);
};


/**
 * 桥接函数：双枪初始化换弹负担系统
 * Bridge: Initialize dual-gun reload burden system
 *
 * 说明：双枪模式下主手/副手分别计算负担值，避免直接使用 _parent.攻击模式="双枪" 造成索引错误。
 *
 * 实际实现：ReloadManager.initDualGunReloadBurden()
 * Actual implementation: ReloadManager.initDualGunReloadBurden()
 */
_root.主角函数.双枪初始化换弹负担 = function(
    target:MovieClip,
    初始帧:Number,
    门禁帧:Number,
    回跳帧:Number,
    结束帧:Number,
    音乐帧数组:Array
):Void {
    ReloadManager.initDualGunReloadBurden(target, 初始帧, 门禁帧, 回跳帧, 结束帧, 音乐帧数组);
};

/**
 * 桥接函数：双枪换弹门禁
 * Bridge: Dual-gun reload gate checkpoint
 *
 * 实际实现：ReloadManager.handleDualGunReloadGate()
 * Actual implementation: ReloadManager.handleDualGunReloadGate()
 */
_root.主角函数.双枪换弹门禁 = function(target:MovieClip):Void {
    ReloadManager.handleDualGunReloadGate(target);
};

/**
 * 桥接函数：双枪换弹帧率控制
 * Bridge: Dual-gun reload frame rate control
 *
 * 实际实现：ReloadManager.controlReloadFrameRate()
 * Actual implementation: ReloadManager.controlReloadFrameRate()
 */
_root.主角函数.双枪换弹帧率控制 = function(target:MovieClip):Void {
    ReloadManager.controlReloadFrameRate(target);
};

_root.主角函数.混合手枪换弹匣 = function():Void {
    var slot:String = _parent.soldierAttackOwner.reloadSlot;
    if (slot == "手枪2") this.副手换弹匣();
    else if (slot == "手枪") this.主手换弹匣();
};

_root.主角函数.开始混合手枪换弹 = function(slot:String):Void {
    var unit:MovieClip = _parent;
    if (slot == undefined) slot = "手枪";
    if ((slot != "手枪" && slot != "手枪2") || !WeaponAmmoRuntime.canReload(unit, slot, false)) return;
    ShootCore.stopForReload(unit);
    ReloadManager.bumpReloadGeneration(this);
    this.dualReloadStartHand = slot == "手枪2" ? "副手" : "主手";
    delete this._dualReloadFirstInitStartFrame;
    this.换弹标签 = true;
    this.gotoAndPlay(unit.soldierAttackOwner.reloadPair===true?"双枪同步换弹匣":"双枪换弹匣");
};


// 临时放置的初始化敌人射击函数
_root.敌人函数.初始化并开始射击 = function(最大射击时长:Number):Void {
    var 自机 = _parent;
    var 攻击对象 = _root.gameworld[_parent.攻击目标];

    var maxShootTime = 最大射击时长 > 1 ? 最大射击时长 : 90;

    自机.长枪射击 = WeaponFireCore.LONG_GUN_SHOOT;
    ShootInitCore.initLongGun(this, _parent);

    自机.上行 = false;
    自机.下行 = false;
    自机.动作A = true;
    
    this.射击许可标签.timer = 0;
    // 临时糊一个小ai在这
    this.射击许可标签.onEnterFrame = function(){
        this.timer++;
        // 检查子弹耗尽，检查射击时长达到
        if(this.timer % 10 === 0){

            var attackMode:String = 自机.攻击模式;
            var weaponValue:Object = 自机[attackMode].value;
            var capacity:Number = 自机[attackMode + "弹匣容量"];

            if(weaponValue.shot >= capacity){
                delete this.onEnterFrame;
                自机.动作A = false;
                自机.man.开始换弹();
            }else if(timer >= maxShootTime){
                delete this.onEnterFrame;
                自机.动作A = false;
                自机.动画完毕();
            }
        }
        // 检查敌人不在攻击范围内
        if(this.timer % 30 === 0){
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

