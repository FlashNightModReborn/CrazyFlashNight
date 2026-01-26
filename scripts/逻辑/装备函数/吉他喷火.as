_root.装备生命周期函数.吉他喷火初始化 = function(ref:Object, param:Object)
{
    var target:MovieClip = ref.自机;

    // ===== 从XML参数对象读取配置 =====
    ref.transformInterval = param.transformInterval || 1000;
    ref.animDuration = param.animDuration || 15;
    ref.机枪动画帧上限 = param.machineGunFrameLimit || 13;

    // 机枪系统配置
    ref.机枪弹容倍率 = param.machineGunCapacityMultiplier || 3;
    ref.机枪弹容上限 = param.machineGunHeatCapacity || 48;
    ref.机枪弹容指示器格数 = param.machineGunIndicatorSegments || 5;
    ref.机枪威力系数 = param.machineGunPowerCoeff || 0.5;
    ref.机枪击倒力 = param.machineGunImpact || 15;
    ref.机枪速度倍率 = param.machineGunVelocityMultiplier || 6;
    ref.机枪射击间隔除数 = param.machineGunIntervalDivisor || 2;
    ref.机枪散射度除数 = param.machineGunDiffusionDivisor || 1.5;
    ref.机枪霰弹值倍率 = param.machineGunSplitMultiplier || 2;

    // 机枪模式固定属性
    ref.机枪命中效果 = param.machineGunBulletHit || "火花";
    ref.机枪枪口焰 = param.machineGunMuzzle || "枪火";
    ref.机枪音效 = param.machineGunSound || "p90-1.wav";
    ref.机枪子弹 = param.machineGunBullet || "加强普通子弹";

    // 刀形态配置
    ref.刀形态角度偏移 = param.bladeRotationOffset || 90;
    ref.刀形态x偏移 = param.bladeXOffset || 380;
    ref.刀形态y偏移 = param.bladeYOffset || -180;
    ref.刀威力系数 = param.bladePowerCoeff || (130 / 120);
    ref.刀形态动作类型 = param.bladeActionType || "狂野";

    // 枪口位置配置
    ref.喷火器枪口X = param.flamethrowerMuzzleX || 82;
    ref.机枪枪口X = param.machineGunMuzzleX || 282;

    // 战技系统配置
    ref.战技时间间隔 = param.skillInterval || 5000;
    ref.战技mp消耗 = param.skillMpCost || 30;
    ref.战技名 = param.skillName || "凶斩";

    // 吉他震地配置
    var 震地耗蓝比例:Number = param.quakeMpCostRatio || 5;
    ref.吉他震地耗蓝量 = Math.floor(target.mp满血值 / 100 * 震地耗蓝比例);
    ref.吉他震地威力倍率 = param.guitarQuakePowerMultiplier || 45;
    ref.吉他震地触发状态 = param.guitarQuakeTriggerState || "凶斩刀落";
    ref.吉他震地冷却时间 = param.guitarQuakeCooldown || 500;

    // 音符系统配置
    var 音符耗蓝比例:Number = param.noteMpCostRatio || 1;
    ref.坐标偏移范围 = param.coordOffsetRange || 10;
    ref.黄色音符最大增幅次数 = param.yellowNoteMaxStacks || 24;
    ref.黄色音符攻击力增幅百分比 = param.yellowNoteAtkBoostPercent || 2.5;
    ref.黄色音符威力倍率 = param.yellowNotePowerMultiplier || 10;
    ref.灯光增幅间隔倍率 = param.lightBoostIntervalMultiplier || 3;
    ref.灯光增幅威力倍率 = param.lightBoostPowerMultiplier || 30;

    // ===== 缓存基础长枪属性（首次初始化） =====
    if (ref.baseGunProps == undefined) {
        ref.baseGunProps = {
            impact: target.长枪属性.impact,
            power: target.长枪属性.power,
            bullethit: target.长枪属性.bullethit,
            muzzle: target.长枪属性.muzzle,
            sound: target.长枪属性.sound,
            bullet: target.长枪属性.bullet,
            velocity: target.长枪属性.velocity,
            interval: target.长枪属性.interval,
            diffusion: target.长枪属性.diffusion,
            split: target.长枪属性.split,
            capacity: target.长枪属性.capacity
        };
        ref.weaponMode = "喷火器";
    }

    // ===== 同步主角武器形态状态（使用全局参数持久化） =====
    if (ref.是否为主角) {
        var key:String = ref.标签名 + ref.初始化函数;
        if (!_root.装备生命周期函数.全局参数[key]) {
            _root.装备生命周期函数.全局参数[key] = {};
        }
        var gl:Object = _root.装备生命周期函数.全局参数[key];
        ref.weaponMode = gl.weaponMode || "喷火器";
        ref.globalParam = gl;

        // 恢复机枪模式
        if (ref.weaponMode == "机枪") {
            _root.装备生命周期函数.吉他喷火应用机枪属性(ref);
        }
    }

    // ===== 刀枪复用初始化 =====
    // 如果没有配置刀，则将吉他同时作为刀使用
    if (target.刀 == null || target.刀 == undefined) {
        _root.刀配置(target._name, "桔色电子吉他", 1);
        target.刀 = target.长枪;
        target.刀_装扮 = target.长枪_装扮;
        target.刀属性.power = ref.baseGunProps.power * ref.刀威力系数;
    }
    ref.是否刀枪复用 = (target.刀 == target.长枪);

    // ===== 订阅引用同步事件 =====
    // 长枪引用同步（枪形态渲染）
    target.syncRefs.长枪_引用 = true;
    target.dispatcher.subscribe("长枪_引用", function(unit) {
        _root.装备生命周期函数.吉他喷火动画控制(ref);
        _root.装备生命周期函数.吉他喷火更新枪口位置(ref);
        _root.装备生命周期函数.吉他喷火刷新机枪弹容(ref);
    });

    // 刀引用同步（刀形态渲染，仅刀枪复用时）
    if (ref.是否刀枪复用) {
        target.syncRefs.刀_引用 = true;
        target.dispatcher.subscribe("刀_引用", function(unit) {
            _root.装备生命周期函数.吉他喷火动画控制(ref);
            _root.装备生命周期函数.吉他喷火刀枪显示控制(ref);
        });
    }

    // ===== 动画帧初始化 =====
    if (ref.animFrame == undefined) {
        ref.animFrame = 1;
    }

    // ===== 机枪过热系统初始化 =====
    if (ref.机枪剩余弹容 == undefined) {
        ref.机枪剩余弹容 = ref.机枪弹容上限;
    }

    // ===== 变形动画状态 =====
    ref.改变武器类型许可 = false;
    ref.改变武器类型计数 = -1;
    ref.改变武器类型动画时长 = param.transformAnimDuration || 5;

    // ===== 时间戳系统初始化 =====
    // 战技系统
    ref.战技时间戳名 = target.长枪 + "战技时间戳";

    // 吉他震地系统
    ref.吉他震地时间戳名 = target.长枪 + "吉他震地时间戳";

    // 黄色音符系统
    ref.黄色音符标识 = target.刀 + "黄色音符";
    ref.黄色音符时间戳名 = ref.黄色音符标识 + "时间戳";
    ref.黄色音符时间间隔 = _root.随机整数(0, 1000);
    ref.黄色音符耗蓝量 = Math.floor(target.mp满血值 / 100 * 音符耗蓝比例);

    // 灯光增幅系统
    ref.灯光增幅标识 = target.刀 + "灯光增幅";
    ref.灯光增幅时间戳名 = ref.灯光增幅标识 + "时间戳";
    ref.灯光增幅时间间隔 = _root.随机整数(0, 1000) * ref.灯光增幅间隔倍率;
    ref.灯光增幅耗蓝量 = Math.floor(target.mp满血值 / 100 * 音符耗蓝比例);

    // ===== 增幅次数初始化 =====
    if (ref.增幅次数 == undefined) {
        ref.增幅次数 = {};
    }

    // ===== 子弹属性配置 =====
    ref.吉他震地子弹属性 = ref.子弹配置 ? ref.子弹配置.bullet_1 : null;
    ref.黄色音符子弹属性 = ref.子弹配置 ? ref.子弹配置.bullet_2 : null;
    ref.灯光增幅子弹属性 = ref.子弹配置 ? ref.子弹配置.bullet_3 : null;

    // ===== 战技系统配置 =====
    ref.skill_0 = param.skill_0; // 地面战技：凶斩
    ref.当前装载战技 = null;

    // 装载主动战技函数
    ref.装载战技 = function(目标战技:Object) {
        if (ref.当前装载战技 === 目标战技) return;
        ref.当前装载战技 = 目标战技;
        target.装载主动战技(目标战技, "兵器"); // 刀枪复用，战技在刀形态使用，用"兵器"模式

        if (ref.是否为主角) {
            _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
        }
    };

    // 获取当前应装载的战技
    ref.获取目标战技 = function():Object {
        // 刀枪复用时始终装载战技（战技在刀形态下可用）
        if (!ref.是否刀枪复用) return null;
        return ref.skill_0;
    };

    // 初始装载战技
    ref.装载战技(ref.获取目标战技());
};

// ===== 周期函数 =====
_root.装备生命周期函数.吉他喷火周期 = function(ref:Object, param:Object)
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;

    // 武器形态切换检测（仅在长枪模式下）
    if (target.攻击模式 == "长枪" && _root.按键输入检测(target, _root.武器变形键)) {
        _root.装备生命周期函数.吉他喷火触发形态切换(ref);
    }

    // 机枪过热检测
    _root.装备生命周期函数.吉他喷火过热检测(ref);

    // 动画控制
    _root.装备生命周期函数.吉他喷火动画控制(ref);

    // 刀枪隐藏显示
    _root.装备生命周期函数.吉他喷火刀枪显示控制(ref);

    // 枪口位置更新
    _root.装备生命周期函数.吉他喷火更新枪口位置(ref);

    // 机枪弹容刷新
    _root.装备生命周期函数.吉他喷火刷新机枪弹容(ref);

    // 战技系统（刀形态）
    if (ref.是否刀枪复用) {
        _root.装备生命周期函数.吉他喷火战技系统(ref);
    }

    // 战斗逻辑（刀形态音符系统）
    _root.装备生命周期函数.吉他喷火战斗周期(ref);
};

// ===== 判断是否为刀形态 =====
_root.装备生命周期函数.吉他喷火是否刀形态 = function(ref:Object):Boolean
{
    var target:MovieClip = ref.自机;
    return ref.是否刀枪复用 && (target.攻击模式 == "兵器" || _root.兵器使用检测(target));
};

// ===== 判断是否为枪形态 =====
_root.装备生命周期函数.吉他喷火是否枪形态 = function(ref:Object):Boolean
{
    var target:MovieClip = ref.自机;
    return target.攻击模式 == "长枪" && !_root.装备生命周期函数.吉他喷火是否刀形态(ref);
};

// ===== 应用喷火器属性 =====
_root.装备生命周期函数.吉他喷火应用喷火器属性 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var base:Object = ref.baseGunProps;

    ref.weaponMode = "喷火器";
    target.长枪属性.impact = base.impact;
    target.长枪属性.bullethit = base.bullethit;
    target.长枪属性.muzzle = base.muzzle;
    target.长枪属性.sound = base.sound;
    target.长枪属性.bullet = base.bullet;
    target.长枪属性.velocity = base.velocity;
    target.长枪属性.interval = base.interval;
    target.长枪属性.diffusion = base.diffusion;
    target.长枪属性.split = base.split;
    target.长枪属性.capacity = base.capacity;
    target.长枪弹匣容量 = base.capacity;

    // 弹药转换：机枪弹药 → 喷火器弹药
    target.长枪.value.shot = Math.floor(target.长枪.value.shot / ref.机枪弹容倍率);

    // 更新buff系统
    target.buff.基础值.长枪威力 = target.长枪.getData().data.power * 1 + target.装备枪械威力加成;
    target.buff.更新("长枪威力");

    // 重新初始化射击函数
    if (target.man.初始化长枪射击函数) {
        target.man.初始化长枪射击函数();
    }
};

// ===== 应用机枪属性 =====
_root.装备生命周期函数.吉他喷火应用机枪属性 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var base:Object = ref.baseGunProps;

    ref.weaponMode = "机枪";
    target.长枪属性.impact = ref.机枪击倒力;
    target.长枪属性.bullethit = ref.机枪命中效果;
    target.长枪属性.muzzle = ref.机枪枪口焰;
    target.长枪属性.sound = ref.机枪音效;
    target.长枪属性.bullet = ref.机枪子弹;
    target.长枪属性.velocity = base.velocity * ref.机枪速度倍率;
    target.长枪属性.interval = Math.floor(base.interval / ref.机枪射击间隔除数);
    target.长枪属性.diffusion = Math.floor(base.diffusion / ref.机枪散射度除数);
    target.长枪属性.split = base.split * ref.机枪霰弹值倍率;
    target.长枪属性.capacity = base.capacity * ref.机枪弹容倍率;
    target.长枪弹匣容量 = target.长枪属性.capacity;

    // 弹药转换：喷火器弹药 → 机枪弹药
    target.长枪.value.shot = target.长枪.value.shot * ref.机枪弹容倍率;

    // 更新buff系统
    target.buff.基础值.长枪威力 = target.长枪.getData().data.power * ref.机枪威力系数 + target.装备枪械威力加成;
    target.buff.更新("长枪威力");

    // 重新初始化射击函数
    if (target.man.初始化长枪射击函数) {
        target.man.初始化长枪射击函数();
    }
};

// ===== 切换武器形态 =====
_root.装备生命周期函数.吉他喷火切换武器形态 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    if (ref.weaponMode == "喷火器") {
        _root.装备生命周期函数.吉他喷火应用机枪属性(ref);
    } else {
        _root.装备生命周期函数.吉他喷火应用喷火器属性(ref);
    }

    // 刷新UI显示
    if (_root.控制目标 == target._name) {
        _root.玩家信息界面.玩家必要信息界面.子弹数 = target.长枪属性.capacity - target.长枪.value.shot;
    }

    // 如果正在射击，重新切换攻击模式
    if (target.主手射击中 == true) {
        target.攻击模式切换("长枪");
    }

    _root.发布消息("吉他武器类型切换为[" + ref.weaponMode + "]");

    // 保存到全局参数
    if (ref.globalParam) {
        ref.globalParam.weaponMode = ref.weaponMode;
    }
};

// ===== 触发形态切换（带变形动画） =====
_root.装备生命周期函数.吉他喷火触发形态切换 = function(ref:Object)
{
    if (ref.改变武器类型许可) return;

    _root.更新并执行时间间隔动作(
        ref,
        "武器形态切换",
        function() {
            ref.改变武器类型许可 = true;
            ref.animFrame = ref.机枪动画帧上限;
            ref.改变武器类型计数 = 0;
            _root.装备生命周期函数.吉他喷火切换武器形态(ref);
        },
        ref.transformInterval,
        false
    );
};

// ===== 机枪过热检测 =====
_root.装备生命周期函数.吉他喷火过热检测 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    if (ref.weaponMode != "机枪") return;
    if (ref.机枪剩余弹容 > 0) return;

    // 检查是否还有足够弹药（避免空弹匣时触发）
    var 已消耗弹药:Number = ref.baseGunProps.capacity * ref.机枪弹容倍率 - target.长枪.value.shot;
    if (已消耗弹药 <= 5) return;

    // 过热自动切换
    _root.发布消息("机枪形态过热，自动切换形态！");
    ref.改变武器类型许可 = true;
    ref.animFrame = ref.机枪动画帧上限;
    ref.改变武器类型计数 = 0;
    _root.装备生命周期函数.吉他喷火切换武器形态(ref);
};

// ===== 刷新机枪弹容 =====
_root.装备生命周期函数.吉他喷火刷新机枪弹容 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;

    // 射击时消耗，停止时恢复
    if (ref.weaponMode == "机枪" && target.攻击模式 == "长枪" && target.主手射击中 == true) {
        ref.机枪剩余弹容 = Math.max(0, ref.机枪剩余弹容 - 1);
    } else if (ref.机枪剩余弹容 < ref.机枪弹容上限) {
        ref.机枪剩余弹容 = Math.min(ref.机枪弹容上限, ref.机枪剩余弹容 + 1);
    }

    // 更新指示器显示
    if (gun && gun.动画 && gun.动画.机枪弹容指示器) {
        var 显示基数:Number = ref.机枪弹容上限 / ref.机枪弹容指示器格数;
        var 显示格数:Number = 1;
        if (ref.机枪剩余弹容 > 0) {
            显示格数 += Math.ceil((ref.机枪弹容上限 - ref.机枪剩余弹容) / 显示基数);
        }
        gun.动画.机枪弹容指示器.gotoAndStop(显示格数);
    }
};

// ===== 动画控制 =====
_root.装备生命周期函数.吉他喷火动画控制 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;

    // 变形动画播放中
    if (ref.改变武器类型许可 || ref.改变武器类型计数 >= 0) {
        if (ref.改变武器类型计数 < ref.改变武器类型动画时长 * 2) {
            ref.改变武器类型计数++;
            if (ref.改变武器类型计数 - ref.改变武器类型动画时长 > 0) {
                // 后半段：展开
                if (ref.animFrame < _root.装备生命周期函数.吉他喷火获得动画时长(ref)) {
                    ref.animFrame++;
                }
            } else {
                // 前半段：折叠
                if (ref.animFrame > 1) {
                    ref.animFrame--;
                }
            }
        } else {
            ref.改变武器类型许可 = false;
            ref.改变武器类型计数 = -1;
        }
    } else {
        // 正常动画控制
        var shouldExpand:Boolean = _root.装备生命周期函数.吉他喷火是否枪形态(ref);
        var maxFrame:Number = _root.装备生命周期函数.吉他喷火获得动画时长(ref);

        if (shouldExpand) {
            if (ref.animFrame < maxFrame) {
                ref.animFrame++;
            }
        } else {
            if (ref.animFrame > 1) {
                ref.animFrame--;
            }
        }
    }

    // 更新动画帧
    if (gun && gun.动画) {
        gun.动画.gotoAndStop(ref.animFrame);
    }
};

// ===== 获得动画时长 =====
_root.装备生命周期函数.吉他喷火获得动画时长 = function(ref:Object):Number
{
    return (ref.weaponMode == "喷火器") ? ref.animDuration : ref.机枪动画帧上限;
};

// ===== 刀枪隐藏显示控制 =====
_root.装备生命周期函数.吉他喷火刀枪显示控制 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;
    var blade:MovieClip = target.刀_引用;

    if (!ref.是否刀枪复用) return;

    var 是否刀形态:Boolean = _root.装备生命周期函数.吉他喷火是否刀形态(ref);

    // 枪形态时隐藏枪（因为刀形态在用）
    if (gun && gun.动画) {
        gun.动画._visible = !是否刀形态;
    }

    // 刀形态时显示刀并调整位置和动作类型
    if (blade && blade.动画) {
        blade.动画._visible = 是否刀形态;
        if (是否刀形态) {
            blade.动画._rotation = ref.刀形态角度偏移;
            blade.动画._x = ref.刀形态x偏移;
            blade.动画._y = ref.刀形态y偏移;
            target.兵器动作类型 = ref.刀形态动作类型;
        }
    }
};

// ===== 更新枪口位置 =====
_root.装备生命周期函数.吉他喷火更新枪口位置 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var gun:MovieClip = target.长枪_引用;

    if (!gun || !gun.枪口位置) return;

    gun.枪口位置._x = (ref.weaponMode == "喷火器") ? ref.喷火器枪口X : ref.机枪枪口X;
};

// ===== 技能判断函数（基于通用兵器技能检测） =====
_root.装备生命周期函数.吉他喷火正在使用技能 = function(ref:Object, 技能名:String):Boolean
{
    return _root.兵器技能检测(ref.自机, 技能名) && _root.装备生命周期函数.吉他喷火是否刀形态(ref);
};

_root.装备生命周期函数.吉他喷火正在使用凶斩 = function(ref:Object):Boolean
{
    return _root.装备生命周期函数.吉他喷火正在使用技能(ref, "凶斩");
};

// ===== 战技系统（刀形态） =====
_root.装备生命周期函数.吉他喷火战技系统 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    // 动态切换战技（节流：仅当目标战技变化时才调用）
    var 目标战技:Object = ref.获取目标战技();
    if (ref.当前装载战技 !== 目标战技) {
        ref.装载战技(目标战技);
    }

    // 只有在刀形态下才处理战技相关逻辑
    if (!_root.装备生命周期函数.吉他喷火是否刀形态(ref)) return;

    // 吉他震地：在凶斩刀落时触发（基于小状态检测，避免帧数依赖）
    if (_root.装备生命周期函数.吉他喷火正在使用凶斩(ref)) {
        if (target.getSmallState() == ref.吉他震地触发状态 && target.mp >= ref.吉他震地耗蓝量) {
            if (_root.更新时间间隔(target, ref.吉他震地时间戳名, ref.吉他震地冷却时间)) {
                _root.装备生命周期函数.吉他喷火释放吉他震地(ref);
            }
        }
    }
};

// ===== 释放吉他震地 =====
_root.装备生命周期函数.吉他喷火释放吉他震地 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    var 子弹属性:Object = ref.吉他震地子弹属性;
    if (!子弹属性) {
        // 兼容模式：没有配置子弹时使用默认参数
        子弹属性 = {
            子弹种类: "吉他震地",
            Z轴攻击范围: 200,
            击倒率: 1
        };
    }

    子弹属性.子弹威力 = ref.吉他震地耗蓝量 * ref.吉他震地威力倍率;
    子弹属性.发射者 = target._name;
    子弹属性.shootX = target._x;
    子弹属性.shootY = target._y;
    子弹属性.shootZ = target._y;

    _root.子弹区域shoot传递(子弹属性);
    target.mp -= ref.吉他震地耗蓝量;
};

// ===== 战斗周期（刀形态音符系统） =====
_root.装备生命周期函数.吉他喷火战斗周期 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    // 只有刀形态且正在兵器攻击时才释放音符
    if (!_root.装备生命周期函数.吉他喷火是否刀形态(ref)) return;
    if (!_root.兵器攻击检测(target)) return;

    // 黄色音符
    if (target.mp >= ref.黄色音符耗蓝量) {
        if (_root.更新时间间隔(target, ref.黄色音符时间戳名, ref.黄色音符时间间隔)) {
            _root.装备生命周期函数.吉他喷火释放黄色音符(ref);
        }
    }

    // 灯光增幅
    if (target.mp >= ref.灯光增幅耗蓝量) {
        if (_root.更新时间间隔(target, ref.灯光增幅时间戳名, ref.灯光增幅时间间隔)) {
            _root.装备生命周期函数.吉他喷火释放灯光增幅(ref);
        }
    }
};

// ===== 获得随机坐标偏离 =====
_root.装备生命周期函数.吉他喷火获得随机坐标偏离 = function(ref:Object):Object
{
    var target:MovieClip = ref.自机;
    var xOffset:Number = (_root.basic_random() - 0.5) * 2 * ref.坐标偏移范围;
    var yOffset:Number = (_root.basic_random() - 0.5) * 2 * ref.坐标偏移范围;
    return {x: target._x + xOffset, y: target._y + yOffset};
};

// ===== 释放黄色音符 =====
_root.装备生命周期函数.吉他喷火释放黄色音符 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var myPoint:Object = _root.装备生命周期函数.吉他喷火获得随机坐标偏离(ref);
    var 增幅名:String = ref.黄色音符标识 + "攻击增幅";

    if (ref.增幅次数[增幅名] === undefined) {
        ref.增幅次数[增幅名] = 1;
    }

    if (ref.增幅次数[增幅名] <= ref.黄色音符最大增幅次数) {
        // 使用BuffManager管理攻击力增幅（同ID自动替换旧buff）
        var 倍率:Number = Math.pow((100 + ref.黄色音符攻击力增幅百分比) / 100, ref.增幅次数[增幅名]);
        var buffName:String = "黄色音符攻击增幅";
        var podBuff:PodBuff = new PodBuff("空手攻击力", BuffCalculationType.MULT_POSITIVE, 倍率);
        var metaBuff:MetaBuff = new MetaBuff([podBuff], [], 0);
        target.buffManager.addBuffImmediate(metaBuff, buffName);

        _root.发布消息("攻击力第" + ref.增幅次数[增幅名] + "次上升" + ref.黄色音符攻击力增幅百分比 + "%！");
        ref.增幅次数[增幅名] += 1;
    }

    var 子弹属性:Object = ref.黄色音符子弹属性;
    if (!子弹属性) {
        子弹属性 = {
            子弹种类: "黄色音符",
            子弹速度: 3,
            Z轴攻击范围: 20,
            击倒率: 100,
            子弹散射度: 360
        };
    }

    子弹属性.子弹威力 = ref.黄色音符耗蓝量 * ref.黄色音符威力倍率;
    子弹属性.发射者 = target._name;
    子弹属性.shootX = myPoint.x;
    子弹属性.shootY = target._y;
    子弹属性.shootZ = target._y;

    _root.子弹区域shoot传递(子弹属性);
    target.mp -= ref.黄色音符耗蓝量;
    ref.黄色音符时间间隔 = _root.随机整数(0, 1000);
};

// ===== 释放灯光增幅 =====
_root.装备生命周期函数.吉他喷火释放灯光增幅 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var myPoint:Object = _root.装备生命周期函数.吉他喷火获得随机坐标偏离(ref);
    var 增幅名:String = ref.灯光增幅标识 + "防御增幅";

    if (ref.增幅次数[增幅名] === undefined) {
        ref.增幅次数[增幅名] = 1;
    }

    if (ref.增幅次数[增幅名] <= ref.黄色音符最大增幅次数) {
        // 使用BuffManager管理防御力增幅（同ID自动替换旧buff）
        var 倍率:Number = Math.pow((100 + ref.黄色音符攻击力增幅百分比) / 100, ref.增幅次数[增幅名]);
        var buffName:String = "灯光增幅防御增幅";
        var podBuff:PodBuff = new PodBuff("防御力", BuffCalculationType.MULT_POSITIVE, 倍率);
        var metaBuff:MetaBuff = new MetaBuff([podBuff], [], 0);
        target.buffManager.addBuffImmediate(metaBuff, buffName);

        _root.发布消息("防御力第" + ref.增幅次数[增幅名] + "次上升" + ref.黄色音符攻击力增幅百分比 + "%！");
        ref.增幅次数[增幅名] += 1;
    }

    var 子弹属性:Object = ref.灯光增幅子弹属性;
    if (!子弹属性) {
        子弹属性 = {
            子弹种类: "灯光增幅",
            子弹速度: 0,
            Z轴攻击范围: 50,
            击倒率: 1,
            子弹散射度: 360
        };
    }

    子弹属性.子弹威力 = ref.灯光增幅耗蓝量 * ref.灯光增幅威力倍率;
    子弹属性.发射者 = target._name;
    子弹属性.shootX = myPoint.x;
    子弹属性.shootY = target._y;
    子弹属性.shootZ = target._y;

    _root.子弹区域shoot传递(子弹属性);
    target.mp -= ref.灯光增幅耗蓝量;
    ref.灯光增幅时间间隔 = _root.随机整数(0, 1000) * ref.灯光增幅间隔倍率;
};

/*
===== 原始资产代码参考 =====
来源: flashswf\arts\new\fs配置素材\LIBRARY\吉他喷火\吉他喷火器.xml

===== 刀口位置1 (战技系统：凶斩 + 吉他震地) =====
onClipEvent (load) {
	var 耗蓝比例 = 5;
	var 自机 = _root.获得父节点(this, 5);
	var 吉他震地时间戳名 = 自机.长枪 + "吉他震地" + "时间戳";
	var 吉他震地时间间隔 = 1 * 1000;
	var 吉他震地耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	var 战技时间戳名 = 自机.长枪 + "战技" + "时间戳";
	var 战技时间间隔 = 5 * 1000;
	var 战技mp消耗 = 30;

	this.检查并执行时间间隔动作 = _root.检查并执行时间间隔动作;
	this.释放战技 = function()
	{
		自机.技能名 = "凶斩";
		自机.技能等级 = Math.min(10, _root.获得强化等级(_root.长枪));
		自机.mp -= 战技mp消耗;
		自机.状态改变("技能");
	};
	this.释放吉他震地 = function()
	{
		var myPoint = {x:自机._x, y:自机._y};
		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 0;
		发射效果 = "";
		子弹种类 = "吉他震地";
		子弹威力 = 吉他震地耗蓝量 * 45;
		子弹速度 = 0;
		击中地图效果 = "";
		Z轴攻击范围 = 200;
		击倒率 = 1;
		击中后子弹的效果 = "";
		子弹敌我属性 = true;
		发射者名 = 自机._name;
		子弹敌我属性值 = !自机.是否为敌人;
		shootX = myPoint.x;
		Z轴坐标 = shootY = 自机._y;
		_root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,子弹敌我属性值,击倒率,击中后子弹的效果);
		自机.mp -= 吉他震地耗蓝量;
	};
	this.onEnterFrame = function()
	{
		if (自机.刀 == 自机.长枪 and (自机.攻击模式 == "长枪" or 自机.攻击模式 == "兵器"))
		{
			if (Key.isDown(_root.武器技能键) and 自机.mp >= 战技mp消耗)
			{
				this.检查并执行时间间隔动作(自机,战技时间间隔,"释放战技",战技时间戳名);
			}
			if (自机.man._currentframe >= 347 and 自机.man._currentframe <= 369 and 自机.mp >= 吉他震地耗蓝量)
			{//凶斩判定
				this.检查并执行时间间隔动作(自机,吉他震地时间间隔,"释放吉他震地",吉他震地时间戳名);
			}
		}
	};
}

===== 刀口位置3 (黄色音符 + 灯光增幅系统) =====
onClipEvent (load) {
	var 耗蓝比例 = 1;
	var 坐标偏移范围 = 10;
	var 自机 = _root.获得父节点(this, 5);
	var 是否为刀形态 = _root.获得父节点(this, 2)._name == "刀";
	if (自机[增幅次数] == undefined)
	{
		自机[增幅次数] = {};
	}
	this.获得随机时间间隔 = function()
	{
		return _root.随机整数(0, 1 * 1000);
	};
	this.检查并执行时间间隔动作 = _root.检查并执行时间间隔动作;
	this.获得随机坐标偏离 = function()
	{
		var xOffset = (_root.basic_random() - 0.5) * 2 * 坐标偏移范围;
		var yOffset = (_root.basic_random() - 0.5) * 2 * 坐标偏移范围;
		return {x:自机._x + xOffset, y:自机._y + yOffset};
	};

	var 黄色音符标识 = 自机.刀 + "黄色音符";
	var 黄色音符时间戳名 = 黄色音符标识 + "时间戳";
	var 黄色音符时间间隔 = this.获得随机时间间隔();
	var 黄色音符耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	var 黄色音符最大增幅次数 = 24;
	var 黄色音符攻击力增幅百分比 = 2.5;
	this.释放黄色音符 = function()
	{
		var myPoint = this.获得随机坐标偏离();
		var 增幅名 = 黄色音符标识 + "攻击增幅";

		if (自机[增幅次数][增幅名] === undefined)
		{
			自机[增幅次数][增幅名] = 1;
		}
		if (自机[增幅次数][增幅名] <= 黄色音符最大增幅次数)
		{
			自机.空手攻击力 *= (100 + 黄色音符攻击力增幅百分比) / 100;
			_root.发布消息("攻击力第" + 自机[增幅次数][增幅名] + "次上升" + 黄色音符攻击力增幅百分比 + "%！目前攻击力为" + Math.floor(自机.空手攻击力) + "点！");
			自机[增幅次数][增幅名] += 1;
		}
		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 360;
		发射效果 = "";
		子弹种类 = "黄色音符";
		子弹威力 = 黄色音符耗蓝量 * 10;
		子弹速度 = 3;
		击中地图效果 = "";
		Z轴攻击范围 = 20;
		击倒率 = 100;
		击中后子弹的效果 = "";
		子弹敌我属性 = true;
		发射者名 = 自机._name;
		子弹敌我属性值 = !自机.是否为敌人;
		shootX = myPoint.x;
		Z轴坐标 = shootY = 自机._y;
		_root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,子弹敌我属性值,击倒率,击中后子弹的效果);
		自机.mp -= 黄色音符耗蓝量;
		黄色音符时间间隔 = this.获得随机时间间隔();
	};

	var 灯光增幅标识 = 自机.刀 + "灯光增幅";
	var 灯光增幅时间戳名 = 灯光增幅标识 + "时间戳";
	var 灯光增幅时间间隔 = this.获得随机时间间隔() * 3;
	var 灯光增幅耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	var 灯光增幅最大增幅次数 = 24;
	var 灯光增幅攻击力增幅百分比 = 2.5;
	this.释放灯光增幅 = function()
	{
		var myPoint = this.获得随机坐标偏离();
		var 增幅名 = 灯光增幅标识 + "攻击增幅";

		if (自机[增幅次数][增幅名] === undefined)
		{
			自机[增幅次数][增幅名] = 1;
		}
		if (自机[增幅次数][增幅名] <= 灯光增幅最大增幅次数)
		{
			自机.空手攻击力 *= (100 + 灯光增幅攻击力增幅百分比) / 100;
			_root.发布消息("防御力第" + 自机[增幅次数][增幅名] + "次上升" + 灯光增幅攻击力增幅百分比 + "%！目前防御力为" + Math.floor(自机.防御力) + "点！");
			自机[增幅次数][增幅名] += 1;
		}
		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 360;
		发射效果 = "";
		子弹种类 = "灯光增幅";
		子弹威力 = 灯光增幅耗蓝量 * 30;
		子弹速度 = 0;
		击中地图效果 = "";
		Z轴攻击范围 = 50;
		击倒率 = 1;
		击中后子弹的效果 = "";
		子弹敌我属性 = true;
		发射者名 = 自机._name;
		子弹敌我属性值 = !自机.是否为敌人;
		shootX = myPoint.x;
		Z轴坐标 = shootY = 自机._y;
		_root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,子弹敌我属性值,击倒率,击中后子弹的效果);
		自机.mp -= 灯光增幅耗蓝量;
		灯光增幅时间间隔 = this.获得随机时间间隔() * 3;
	};
	this.onEnterFrame = function()
	{
		if (_root.兵器攻击检测(自机) and 自机.mp >= 黄色音符耗蓝量 and 是否为刀形态)
		{
			if (自机.mp >= 黄色音符耗蓝量)
			{
				this.检查并执行时间间隔动作(自机,黄色音符时间间隔,"释放黄色音符",黄色音符时间戳名);
			}
			if (自机.mp >= 灯光增幅耗蓝量)
			{
				this.检查并执行时间间隔动作(自机,灯光增幅时间间隔,"释放灯光增幅",灯光增幅时间戳名);
			}
		}
	};
}

===== 枪口位置 (动态位置调整) =====
onClipEvent (load) {
	var 自机 = _root.获得父节点(this, 5);
	var 武器类型名 = "武器类型:" + 自机.长枪;
	this.动态调整位置 = function()
	{//保证机枪形态枪口焰视觉正常
		if (自机[武器类型名] == "喷火器")
		{
			this._x = 82;
		}
		else
		{
			this._x = 282;
		}
	};
	this.动态调整位置();
	this.onEnterFrame = function()
	{
		this.动态调整位置();
	};
}

===== 动画 (武器形态切换系统：喷火器/机枪 + 刀枪复用 + 机枪过热) =====
onClipEvent (load) {
	var 自机 = _root.获得父节点(this, 5);
	var 自机类型 = _root.获得父节点(this, 2)._name;
	var 时间戳名 = 自机.长枪 + "时间戳";
	var 动画帧名 = 自机.长枪 + "动画帧";
	var 变形计数 = 自机.长枪 + "变形计数";
	var 武器类型名 = "武器类型:" + 自机.长枪;
	var 基础属性名 = "基础属性:" + 自机.长枪;
	var 机枪动画帧上限 = 13;
	var 机枪弹容倍率 = 3;
	var 机枪弹容上限 = 48;
	var 机枪剩余弹容 = 自机.长枪 + "机枪剩余弹容";
	var 机枪弹容指示器格数 = 5;
	this.切换为喷火器 = function()
	{
		自机[武器类型名] = "喷火器";
		自机.长枪属性.impact = 自机[基础属性名].基础击倒力;
		//自机.长枪属性.power = 自机[基础属性名].基础伤害;
		自机.buff.基础值.长枪威力 = 自机.长枪.getData().data.power * 1 + 自机.装备枪械威力加成;
		自机.buff.更新("长枪威力");
		自机.长枪属性.bullethit = 自机[基础属性名].基础命中效果;
		自机.长枪属性.muzzle = 自机[基础属性名].基础枪口焰;
		自机.长枪属性.sound = 自机[基础属性名].基础音效;
		自机.长枪属性.bullet = 自机[基础属性名].基础子弹;
		自机.长枪属性.velocity = 自机[基础属性名].基础速度;
		自机.长枪属性.interval = 自机[基础属性名].基础射击间隔;
		自机.长枪属性.diffusion = 自机[基础属性名].基础散射度;
		自机.长枪属性.split = 自机[基础属性名].基础霰弹值;
		自机.长枪属性.capacity = 自机[基础属性名].基础弹容;
		自机.长枪弹匣容量 = 自机.长枪属性.capacity;
		自机.长枪.value.shot = Math.floor(自机.长枪.value.shot / 机枪弹容倍率);
		自机.man.初始化长枪射击函数();
	};
	this.切换为机枪 = function()
	{
		自机[武器类型名] = "机枪";
		自机.长枪属性.impact = 15;
		//自机.长枪属性.power = 自机[基础属性名].基础伤害 / 2;
		自机.buff.基础值.长枪威力 = 自机.长枪.getData().data.power * 0.5 + 自机.装备枪械威力加成;
		自机.buff.更新("长枪威力");
		自机.长枪属性.bullethit = "火花";
		自机.长枪属性.muzzle = "枪火";
		自机.长枪属性.sound = "p90-1.wav";
		自机.长枪属性.bullet = "加强普通子弹";
		自机.长枪属性.velocity = 自机[基础属性名].基础速度 * 6;
		自机.长枪属性.interval = Math.floor(自机[基础属性名].基础射击间隔 / 2);
		自机.长枪属性.diffusion = Math.floor(自机[基础属性名].基础散射度 / 1.5);
		自机.长枪属性.split = 自机[基础属性名].基础霰弹值 * 2;
		自机.长枪属性.capacity = 自机[基础属性名].基础弹容 * 机枪弹容倍率;
		自机.长枪弹匣容量 = 自机.长枪属性.capacity;
		自机.长枪.value.shot = 自机.长枪.value.shot * 机枪弹容倍率;
		自机.man.初始化长枪射击函数();
	};
	this.保存武装类型 = function()
	{
		if (_root.控制目标 == 自机._name)
		{
			_root[武器类型名] = 自机[武器类型名];//_root.发布调试消息(_root[武器类型名] + " " + 自机[武器类型名]);
		}
	};

	this.读取武装类型 = function()
	{
		if (_root.控制目标 == 自机._name and _root[武器类型名] == "机枪")
		{
			this.切换为机枪();
			自机.长枪.value.shot = 自机[基础属性名].基础弹容 - Math.floor((自机[基础属性名].基础弹容 * 机枪弹容倍率 - 自机.长枪.value.shot) / 机枪弹容倍率);//保证切换场景后子弹数量正常
			改变武器类型许可 = true;
			自机[动画帧名] = 机枪动画帧上限;
			改变武器类型计数 = 0;
			//_root.发布调试消息(_root[武器类型名] + " " + 自机[武器类型名]);
		}
	};
	//_root.调试模式 = true;
	if (自机[基础属性名] == undefined)
	{//初始化吉他数据
		自机[基础属性名] = {};
		自机[基础属性名].基础击倒力 = 自机.长枪属性.impact;
		自机[基础属性名].基础伤害 = 自机.长枪属性.power;
		// _root.发布消息(自机[基础属性名].基础伤害);
		自机[基础属性名].基础命中效果 = 自机.长枪属性.bullethit;
		自机[基础属性名].基础枪口焰 = 自机.长枪属性.muzzle;
		自机[基础属性名].基础音效 = 自机.长枪属性.sound;
		自机[基础属性名].基础子弹 = 自机.长枪属性.bullet;
		自机[基础属性名].基础速度 = 自机.长枪属性.velocity;
		自机[基础属性名].基础射击间隔 = 自机.长枪属性.interval;
		自机[基础属性名].基础散射度 = 自机.长枪属性.diffusion;
		自机[基础属性名].基础霰弹值 = 自机.长枪属性.split;
		自机[基础属性名].基础弹容 = 自机.长枪属性.capacity;

		自机[武器类型名] = "喷火器";
		this.读取武装类型();

		if (自机.刀 == null)
		{
			_root.刀配置(自机._name,"桔色电子吉他" + "",1);//借用配置生成因此不需要考虑强化数值
			自机.刀 = 自机.长枪;
			自机.刀_装扮 = 自机.长枪_装扮;
			自机.刀属性.power = 自机[基础属性名].基础伤害 * 130 / 120;//刀模式伤害调整
			//_root.发布调试消息(自机.刀 + " " + 自机.刀属性.power);
		}
	}

	this.获得动画时长 = function()
	{
		return (自机[武器类型名] == "喷火器") ? 15 : 机枪动画帧上限;//机枪模式不显示燃料罐
	};
	var 动画时长 = this.获得动画时长();
	var 改变武器类型动画时长 = 5;
	var 刀形态角度偏移 = 90;
	var 刀形态x偏移 = 380;
	var 刀形态y偏移 = -180;
	var 改变武器类型许可 = false;
	var 改变武器类型计数 = -1;
	var 变形时间间隔 = 1 * 1000;

	this.切换武器形态 = function()
	{
		(自机[武器类型名] == "喷火器") ? this.切换为机枪() : this.切换为喷火器();
		_root.控制目标 == 自机._name ? _root.玩家必要信息界面.子弹数 = 自机.长枪属性.capacity - 自机.长枪.value.shot : 0;//自机控制时刷新显示
		if (自机.主手射击中 == true)
		{
			自机.攻击模式切换("长枪");
		}
	};
	this.判断是否展开 = function()
	{
		return 自机.攻击模式 == "长枪" and !(自机.刀 == 自机.长枪 and (自机.攻击模式 == "兵器" or _root.兵器使用检测(自机)));
	};
	this.展开动画 = function()
	{
		//_root.发布调试消息(自机[武器类型名] + this.获得动画时长());
		if (自机[动画帧名] < this.获得动画时长())
		{
			自机[动画帧名] += 1;
		}
	};
	this.折叠动画 = function()
	{
		if (自机[动画帧名] > 1)
		{
			自机[动画帧名] -= 1;
		}
	};
	this.是否隐藏枪 = function()
	{
		return 自机.刀 == 自机.长枪 and (自机.攻击模式 == "兵器" or _root.兵器使用检测(自机));
	};

	this.是否显示刀 = function()
	{
		//_root.发布调试消息(自机.攻击模式 + _root.兵器使用检测(自机) + (自机.攻击模式 == "兵器") + (自机.攻击模式 == "兵器" or _root.兵器使用检测(自机)));
		return (自机.攻击模式 == "兵器" || _root.兵器使用检测(自机));
	};
	this.刀枪隐藏显示 = function()
	{
		if (自机类型 == "枪")
		{
			this._visible = !this.是否隐藏枪();
		}
		else
		{
			this._visible = this.是否显示刀();
			if (this._visible)
			{//利用可见度中介，减少一次函数调用
				this._rotation = 刀形态角度偏移;
				this._x = 刀形态x偏移;
				this._y = 刀形态y偏移;
			}
		}
	};
	this.刀枪隐藏显示();



	if (自机[动画帧名] == undefined)
	{
		自机[动画帧名] = 1;
	}
	if (自机[机枪剩余弹容] == undefined)
	{
		自机[机枪剩余弹容] = 机枪弹容上限;
	}

	this.机枪弹容指示器显示 = function()
	{
		var 显示基数 = 机枪弹容上限 / 机枪弹容指示器格数;
		var 显示格数 = 1;
		if (自机[机枪剩余弹容] > 0)
		{
			显示格数 += Math.ceil((机枪弹容上限 - 自机[机枪剩余弹容]) / 显示基数);
		}
		//_root.发布调试消息(自机[机枪剩余弹容] + " " + 显示格数);
		this.机枪弹容指示器.gotoAndStop(显示格数);
	};

	this.刷新机枪指示器弹容 = function()
	{
		if (自机[武器类型名] == "机枪" and 自机.攻击模式 == "长枪" and 自机.主手射击中 == true)
		{
			自机[机枪剩余弹容] -= 1;
		}
		else if (自机[机枪剩余弹容] < 机枪弹容上限)
		{
			自机[机枪剩余弹容] += 1;
		}
		this.机枪弹容指示器显示();
	};
	gotoAndStop(自机[动画帧名]);
	this.刷新机枪指示器弹容();
	this.onEnterFrame = function()
	{
		自机类型 = _root.获得父节点(this, 2)._name;
		//_root.发布调试消息(1+自机类型+1);
		this.刀枪隐藏显示();
		this.刷新机枪指示器弹容();
		//_root.发布调试消息("是否有刀" + (自机.刀 == 自机.长枪) + " 是否用刀 " + (自机.攻击模式 == "兵器" or _root.兵器使用检测(自机)) + " 是否持械 " + (自机.攻击模式 == "兵器") + " 是否砍人 " + _root.兵器使用检测(自机));
		//_root.发布调试消息(自机.攻击模式 + _root.兵器使用检测(自机));
		//_root.发布调试消息(自机.攻击模式 + " 枪 动画许可:" + 枪形态动画许可 + " 刀 动画许可:" + 刀形态动画许可 + 自机类型 + " 可见:" + this._visible);
		var 机枪过热:Boolean = false;
		if (自机[机枪剩余弹容] == 0 and 自机[武器类型名] == "机枪" and (自机[基础属性名].基础弹容 * 机枪弹容倍率 - 自机.长枪.value.shot) > 5)
		{
			机枪过热 = true;
			_root.发布消息("机枪形态过热，自动切换形态！");
		}
		if (Key.isDown(_root.武器变形键) and (自机[武器类型名] == "机枪" or 自机[武器类型名] == "喷火器") and !改变武器类型许可 and 自机.攻击模式 == "长枪" and 自机类型 == "枪" or 机枪过热)
		{
			改变武器类型许可 = true;
			自机[动画帧名] = 机枪动画帧上限;
			改变武器类型计数 = 0;
			this.切换武器形态();
			_root.发布消息("吉他武器类型切换为[" + 自机[武器类型名] + "]");
			this.保存武装类型();

		}

		if (改变武器类型许可 || 改变武器类型计数 >= 0)
		{
			if (改变武器类型计数 < 改变武器类型动画时长 * 2)
			{
				++改变武器类型计数;
				this[改变武器类型计数 - 改变武器类型动画时长 > 0 ? '展开动画' : '折叠动画']();
			}
			else
			{
				改变武器类型许可 = false;
				改变武器类型计数 = -1;
			}
		}
		else
		{
			this[this.判断是否展开() ? '展开动画' : '折叠动画']();
		}
		gotoAndStop(自机[动画帧名]);
	};
}
*/
