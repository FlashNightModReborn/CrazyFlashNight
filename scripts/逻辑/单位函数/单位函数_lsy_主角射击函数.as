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



// ============ 换弹负担系统 ============

// 计算每次逐发换弹循环应该填充的发数
// 目的：大弹容机枪减少循环次数，提升换弹体验
// 参数：capacity - 弹匣容量
// 返回：每次换弹循环填充的发数
_root.主角函数.计算每次换弹发数 = function(capacity:Number):Number {
    if (capacity <= 10) {
        return 1;  // 小容量：逐发换弹（保持原有手感）
    } else if (capacity <= 30) {
        return 2;  // 中容量：每次2发
    } else if (capacity <= 60) {
        return 3;  // 每次3发
    } else if (capacity <= 100) {
        return 5;  // 每次5发
    } else {
        // 大容量：控制循环次数在20-30次
        return Math.max(5, Math.ceil(capacity / 25));
    }
};

// 初始化换弹负担（在换弹起始帧调用）
// 参数：target - 时间轴MC，初始帧/门禁帧/回跳帧 - 门禁模式用，结束帧 - 帧率控制结束帧，音乐帧数组 - 必经的音频帧
//
// 换弹惩罚机制说明：
// - 不同武器类型有不同的换弹惩罚值(reloadPenalty)，定义在武器XML的data节点中
// - 正值增加换弹负担（延迟），负值减少换弹负担（加速）
// - 配件可通过flat操作修改此值（如加长弹匣在NOAH结构下提供-10加速）
// - 快速换弹（枪械师被动）按比例衰减总负担（包含惩罚值），而非完全抵消
// - 计算公式：实际换弹帧数 ≈ 基础帧数 × (总负担值 / 100)
//
// 各武器类型默认惩罚值参考（额外帧数 × 3.33 ≈ 惩罚值）：
// - 冲锋枪/突击步枪/霰弹枪/近战/压制近战/特殊: 0
// - 战斗步枪: 17 (额外5帧)
// - 狙击步枪: 33 (额外10帧)
// - 反器材武器/机枪: 50 (额外15帧)
// - 压制机枪: 67 (额外20帧)
// - 发射器: 0 (预留，待后续调整)
_root.主角函数.初始化换弹负担 = function(target:MovieClip, 初始帧:Number, 门禁帧:Number, 回跳帧:Number, 结束帧:Number, 音乐帧数组:Array):Void {
    var parent:Object = target._parent;
    target.快速换弹 = (parent._name == _root.控制目标
                     && parent.被动技能.枪械师
                     && parent.被动技能.枪械师.启用);
    // 记录帧位置
    target.换弹初始帧 = 初始帧;
    target.换弹门禁帧 = 门禁帧;
    target.换弹回跳帧 = 回跳帧;
    target.换弹结束帧 = 结束帧;

    // 检测是否为逐发换弹类型
    var weaponAttr:Object = parent[parent.攻击模式 + "属性"];
    var isTubeReload:Boolean = (weaponAttr.reloadType == "tube");
    var capacity:Number = parent[parent.攻击模式 + "弹匣容量"];
    var shot:Number = parent[parent.攻击模式].value.shot;

    // 路径分流：完全打空走整弹匣换弹，未打空走逐发换弹
    // shot == capacity 表示完全打空（已发射数等于弹匣容量）
    var usePerRoundReload:Boolean = isTubeReload && (shot < capacity);
    target.逐发换弹 = usePerRoundReload;

    // 音乐帧数组：排序+去重，避免未排序导致跳过必经帧
    // 对于逐发换弹类型，门禁帧也是必经帧
    var audioFrames:Array = [];
    if (音乐帧数组 != null) {
        for (var i:Number = 0; i < 音乐帧数组.length; i++) {
            var af:Number = Number(音乐帧数组[i]);
            if (!isNaN(af)) audioFrames.push(af);
        }
    }
    // 逐发换弹：添加门禁帧为必经帧
    if (usePerRoundReload && 门禁帧 != undefined) {
        audioFrames.push(门禁帧);
    }
    if (audioFrames.length > 0) {
        audioFrames.sort(function(a, b) { return a - b; });
        var uniq:Array = [];
        for (var j:Number = 0; j < audioFrames.length; j++) {
            if (j == 0 || audioFrames[j] != audioFrames[j - 1]) {
                uniq.push(audioFrames[j]);
            }
        }
        target.换弹音乐帧数组 = uniq;
    } else {
        target.换弹音乐帧数组 = null;
    }

    // 负担值 = 时间缩放比例（100正常，200慢放2倍，<100加速）
    var burden:Number = 100;

    // 根据武器类型获取换弹惩罚值（从武器数据的reloadPenalty字段读取）
    var reloadPenalty:Number = 0;
    if (parent.攻击模式 == "长枪" && parent.长枪属性) {
        var penaltyValue:Number = Number(parent.长枪属性.reloadPenalty);
        if (!isNaN(penaltyValue)) {
            reloadPenalty = penaltyValue;
        }
    }
    // 将惩罚值加入基础负担
    burden += reloadPenalty;

    // 快速换弹：按节省帧数比例缩减总负担（包含惩罚值，按比例衰减而非完全抵消）
    if (target.快速换弹 && 结束帧 != undefined) {
        var totalFrames:Number = 结束帧 - 初始帧;
        var savedFrames:Number = 10; // TODO: 配置化，当前长枪节省4+6=10帧
        if (totalFrames > savedFrames) {
            burden = Math.round(burden * (totalFrames - savedFrames) / totalFrames);
        }
    }

    // 逐发换弹负担值缩放
    // 设计目标：弹容2时40%，弹容8时100%，弹容50时175%，大容量收敛到200%
    // 小容量武器（≤10发）：逐发换弹，灵活快速
    // 中容量武器（11-100发）：每次换2-5发，平衡手感和效率
    // 大容量武器（>100发）：每次换N发，控制循环次数在20-30次，ratio收敛到2.0
    if (usePerRoundReload && 结束帧 != undefined && 门禁帧 != undefined && 回跳帧 != undefined) {
        var loopFrames:Number = 门禁帧 - 回跳帧;  // 单次循环帧数 t
        var fullFrames:Number = 结束帧 - 初始帧;   // 整弹匣换弹帧数 T

        // 计算时间比例系数 ratio（收敛设计）
        var ratio:Number;
        if (capacity <= 2) {
            ratio = 0.4;
        } else if (capacity <= 8) {
            ratio = 0.4 + (capacity - 2) * 0.1;  // 2-8发：线性增长
        } else if (capacity <= 50) {
            ratio = 1.0 + (capacity - 8) * 0.75 / 42;  // 8-50发：平滑过渡到1.75
        } else {
            ratio = 2.0 - 12.5 / capacity;  // 50发以上：渐近收敛到2.0
        }

        // 计算每次换弹发数和总循环次数
        var roundsPerCycle:Number = _root.主角函数.计算每次换弹发数(capacity);
        var totalCycles:Number = Math.ceil(capacity / roundsPerCycle);

        // 计算逐发换弹负担值（基于实际循环次数）
        // 目标：(loopFrames × totalCycles) / (100/新负担) = fullFrames × ratio
        // 即：逐发真实时间 = 整弹匣真实时间 × ratio
        // 新负担 = 100 × fullFrames × ratio / (loopFrames × totalCycles)
        var perRoundBurden:Number = Math.round(100 * fullFrames * ratio / (loopFrames * totalCycles));

        // 应用基础负担的惩罚/加速比例
        perRoundBurden = Math.round(perRoundBurden * burden / 100);

        burden = perRoundBurden;
    }

    target.换弹负担 = burden;
    // 帧率控制模式（仅当传入结束帧时启用）
    if (结束帧 != undefined) {
        target.换弹帧率控制请求 = true;
        target.换弹帧进度 = 0;
    }
};

// 换弹门禁（在检查帧调用，扣除负担并决定放行或回跳，放行后检查快速换弹跳帧）
// 参数：target - 时间轴MovieClip(this)，快速换弹跳帧数 - 放行后若快速换弹启用则跳过的帧数
//
// 路径分流说明：
// - 完全打空（shot == capacity）：走整弹匣换弹路径，门禁不做任何事，动画继续到换弹匣()
// - 未完全打空（shot < capacity）且为tube类型：走逐发换弹路径
//
// 逐发换弹（tube类型）说明：
// - 适用于霰弹枪、狙击步枪、机枪等管状弹仓武器或大容量弹链武器
// - 每次门禁执行：检查换弹值 → 消耗弹匣获取换弹值 → 填充N发 → 回跳或结束
// - 填充发数N根据弹容动态计算：小容量逐发（1发），大容量批量（2-40发）
// - 中途打断时换弹值保留，下次换弹继续消耗
// - 换弹值 = capacity（弹匣容量），每次填充 shot -= N
_root.主角函数.换弹门禁 = function(target:MovieClip, 快速换弹跳帧数:Number):Void {
    var parent:Object = target._parent;
    var attackMode:String = parent.攻击模式;

    // 获取武器属性
    var weaponAttr:Object = parent[attackMode + "属性"];
    var reloadType:String = weaponAttr.reloadType;

    // 非tube类型或未启用逐发换弹模式：直接返回，让动画继续播放到换弹匣()
    if (!target.逐发换弹) {
        return;
    }

    // ============ 逐发换弹（tube类型，shot < capacity） ============
    var capacity:Number = parent[attackMode + "弹匣容量"];
    var weaponValue:Object = parent[attackMode].value;
    var shot:Number = weaponValue.shot;

    // 1. 弹匣已满，清空换弹值，跳到结束帧
    if (shot <= 0) {
        weaponValue.reloadCount = 0;
        // 关闭帧率控制，防止继续推进到换弹匣()帧
        target.换弹帧率控制中 = false;
        target.gotoAndPlay(target.换弹结束帧);
        return;
    }

    // 2. 检查换弹值，没有则消耗弹匣获取
    if (weaponValue.reloadCount == undefined || weaponValue.reloadCount <= 0) {
        // 玩家需要检查并消耗弹匣
        if (_root.控制目标 == parent._name) {
            if (ItemUtil.singleContain(target.使用弹匣名称, 1) != null) {
                ItemUtil.singleSubmit(target.使用弹匣名称, 1);
                weaponValue.reloadCount = capacity;
                // _root.发布消息("消耗一个弹匣，开始填充。");
                target.剩余弹匣数 = ItemUtil.getTotal(target.使用弹匣名称);
            } else {
                // 没有弹匣了，结束换弹（保留当前填充进度）
                _root.发布消息("弹匣耗尽！");
                target.换弹帧率控制中 = false;
                target.gotoAndPlay(target.换弹结束帧);
                return;
            }
        } else {
            // AI直接获得换弹值
            weaponValue.reloadCount = capacity;
        }
    }

    // 3. 填充N发（大容量武器每次换多发）
    var roundsPerCycle:Number = _root.主角函数.计算每次换弹发数(capacity);
    // 不能超过剩余需要填充的发数
    roundsPerCycle = Math.min(roundsPerCycle, shot);
    // 也不能超过当前换弹值剩余
    roundsPerCycle = Math.min(roundsPerCycle, weaponValue.reloadCount);

    weaponValue.reloadCount -= roundsPerCycle;
    weaponValue.shot -= roundsPerCycle;

    // 更新UI显示
    ReloadManager.updateAmmoDisplay(target, parent, _root);
    _root.soundEffectManager.playSound("9mmclip2.wav");

    // 4. 检查是否继续
    if (weaponValue.shot <= 0) {
        // 弹匣满了，关闭帧率控制，跳到结束帧
        target.换弹帧率控制中 = false;
        target.gotoAndPlay(target.换弹结束帧);
    } else {
        // 回跳继续循环
        target.gotoAndPlay(target.换弹回跳帧);
    }
};

// 换弹帧率控制（由挂载在换弹区间内的子MC的onClipEvent(enterFrame)每帧调用）
// 通过stop()+nextFrame()手动推进时间轴，负担值控制推进速率，音乐帧保证必经
_root.主角函数.换弹帧率控制 = function(target:MovieClip):Void {
    // 首次请求：接管时间轴控制
    if (target.换弹帧率控制请求) {
        target.换弹帧率控制请求 = false;
        target.换弹帧率控制中 = true;
        target.stop();
        return;
    }
    if (!target.换弹帧率控制中) return;
    // 保护：避免除零/负值
    if (target.换弹负担 == undefined || target.换弹负担 <= 0) {
        target.换弹负担 = 100;
    }
    // 累积帧进度：每真实帧推进 100/负担 个动画帧
    target.换弹帧进度 += 100 / target.换弹负担;
    var framesToAdvance:Number = Math.floor(target.换弹帧进度);
    if (framesToAdvance < 1) return;
    target.换弹帧进度 -= framesToAdvance;
    var currentFrame:Number = target._currentframe;
    var endFrame:Number = target.换弹结束帧;

    // 本帧计划到达的目标帧（先按结束帧夹住，避免越界导致跳过帧脚本/音乐帧）
    var targetFrame:Number = currentFrame + framesToAdvance;
    if (endFrame != undefined && targetFrame > endFrame) {
        targetFrame = endFrame;
    }

    // 音乐帧约束：多帧推进时，遇到音乐帧必须停住，剩余进度存回下帧继续
    if (targetFrame - currentFrame > 1) {
        var audioFrames:Array = target.换弹音乐帧数组;
        if (audioFrames != null) {
            var stopFrame:Number = undefined;
            for (var i:Number = 0; i < audioFrames.length; i++) {
                var af:Number = audioFrames[i];
                if (af > currentFrame && af < targetFrame && (stopFrame == undefined || af < stopFrame)) {
                    stopFrame = af;
                }
            }
            if (stopFrame != undefined) {
                target.换弹帧进度 += (targetFrame - stopFrame);
                targetFrame = stopFrame;
            }
        }
    }

    var advanceFrames:Number = targetFrame - currentFrame;
    if (advanceFrames < 1) return;

    // 到达结束帧：逐帧推进到结束帧前一帧，再gotoAndPlay(结束帧)交还时间轴控制
    // 这样既不跳过中间帧脚本，也避免在已到达结束帧时重复执行结束帧脚本。
    if (endFrame != undefined && targetFrame == endFrame) {
        for (var f:Number = 1; f < advanceFrames; f++) {
            target.nextFrame();
        }
        target.换弹帧率控制中 = false;
        target.gotoAndPlay(endFrame);
        return;
    }

    // 逐帧推进（确保每帧脚本正常执行）
    for (var f:Number = 0; f < advanceFrames; f++) {
        var beforeFrame:Number = target._currentframe;
        target.nextFrame();
        // 如果帧脚本执行了跳转（如门禁回跳/结束），中断循环
        if (target._currentframe != beforeFrame + 1) {
            target.换弹帧进度 = 0;
            break;
        }
    }
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

