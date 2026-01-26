_root.装备生命周期函数.键盘镰刀初始化 = function(ref:Object, param:Object)
{
    var target:MovieClip = ref.自机;

    // ===== 从XML参数对象读取配置 =====
    ref.animDuration = param.animDuration || 15;
    ref.transformInterval = param.transformInterval || 1000;

    var 耗蓝比例:Number = param.mpCostRatio || 1;
    ref.坐标偏移范围 = param.coordOffsetRange || 10;

    // 武器模式配置
    ref.keyboardDamageMultiplier = param.keyboardDamageMultiplier || 0.8;
    ref.actionTypeScythe = param.actionTypeScythe || "镰刀";
    ref.actionTypeKeyboard = param.actionTypeKeyboard || "短柄";

    // 蓝色音符系统配置（键盘模式）
    ref.蓝色音符最大增幅次数 = param.blueNoteMaxStacks || 24;
    ref.蓝色音符速度增幅百分比 = param.blueNoteSpeedBoostPercent || 2.5;
    ref.蓝色音符威力倍率 = param.blueNotePowerMultiplier || 10;
    ref.蓝色音符间隔下限 = param.blueNoteIntervalMin || 200;
    ref.蓝色音符间隔上限 = param.blueNoteIntervalMax || 1000;

    // 天蓝增幅系统配置（键盘模式）
    ref.天蓝增幅间隔倍率 = param.cyanBoostIntervalMultiplier || 3;
    ref.天蓝增幅耗蓝除数 = param.cyanBoostMpCostDivisor || 2;

    // 镰刀光斩系统配置（镰刀模式）
    ref.镰刀光斩距离系数 = param.scytheSlashDistCoeff || 195;
    ref.镰刀光斩间隔下限 = param.scytheSlashIntervalMin || 200;
    ref.镰刀光斩间隔上限 = param.scytheSlashIntervalMax || 1000;

    // 镰刀风车斩系统配置（瞬步斩时）
    ref.镰刀风车斩间隔下限 = param.windmillSlashMinInterval || 50;
    ref.镰刀风车斩间隔上限 = param.windmillSlashMaxInterval || 150;

    // 追踪充能配置
    ref.追踪充能倍率 = param.trackingChargeMultiplier || 3;

    // 刀口位置偏移量配置（镰刀模式 vs 键盘模式）
    ref.bladePos1 = {
        scythe: {x: param.bladePos1_scythe_x || 35.125, y: param.bladePos1_scythe_y || 637.25},
        keyboard: {x: param.bladePos1_keyboard_x || 20, y: param.bladePos1_keyboard_y || 245}
    };
    ref.bladePos2 = {
        scythe: {x: param.bladePos2_scythe_x || -182.35, y: param.bladePos2_scythe_y || 712.95},
        keyboard: {x: param.bladePos2_keyboard_x || 16, y: param.bladePos2_keyboard_y || 125}
    };
    ref.bladePos3 = {
        scythe: {x: param.bladePos3_scythe_x || -410.6, y: param.bladePos3_scythe_y || 637.25},
        keyboard: {x: param.bladePos3_keyboard_x || 12, y: param.bladePos3_keyboard_y || 35}
    };

    // 初始化基础伤害数据（首次加载时缓存到ref）
    if (isNaN(ref.baseDamage)) {
        ref.baseDamage = target.刀属性.power;
        ref.weaponMode = "镰刀";
        ref.initialRotation = target.刀_引用._rotation;
        ref.initialXScale = target.刀_引用._xscale;
    }

    // 同步主角武器形态状态（使用全局参数持久化）
    if (ref.是否为主角) {
        var key:String = ref.标签名 + ref.初始化函数;
        if (!_root.装备生命周期函数.全局参数[key]) {
            _root.装备生命周期函数.全局参数[key] = {};
        }
        var gl:Object = _root.装备生命周期函数.全局参数[key];
        ref.weaponMode = gl.weaponMode || "镰刀";
        ref.globalParam = gl;
        if (ref.weaponMode == "键盘") {
            target.刀属性.power = ref.baseDamage * ref.keyboardDamageMultiplier;
        }
        // 根据当前武器形态设置动作模组
        target.兵器动作类型 = (ref.weaponMode == "镰刀") ? ref.actionTypeScythe : ref.actionTypeKeyboard;
    }

    // 初始化动画帧
    if (ref.animFrame == undefined) {
        ref.animFrame = 1;
    }

    // 订阅刀引用同步事件
    target.syncRefs.刀_引用 = true;
    target.dispatcher.subscribe("刀_引用", function(unit) {
        _root.装备生命周期函数.键盘镰刀动画更新(ref);
        _root.装备生命周期函数.键盘镰刀更新刀口位置(ref);
    });

    // ===== 战斗系统变量初始化 =====
    if (ref.增幅次数 == undefined) {
        ref.增幅次数 = {};
    }

    // 蓝色音符系统变量（键盘模式）
    ref.蓝色音符标识 = target.刀 + "蓝色音符";
    ref.蓝色音符时间戳名 = ref.蓝色音符标识 + "时间戳";
    ref.蓝色音符时间间隔 = _root.随机整数(ref.蓝色音符间隔下限, ref.蓝色音符间隔上限);
    ref.蓝色音符耗蓝量 = Math.floor(target.mp满血值 / 100 * 耗蓝比例);

    // 天蓝增幅系统变量（键盘模式）
    ref.天蓝增幅标识 = target.刀 + "天蓝增幅";
    ref.天蓝增幅时间戳名 = ref.天蓝增幅标识 + "时间戳";
    ref.天蓝增幅时间间隔 = _root.随机整数(ref.蓝色音符间隔下限, ref.蓝色音符间隔上限) * ref.天蓝增幅间隔倍率;
    ref.天蓝增幅耗蓝量 = Math.floor(target.mp满血值 / 100 * 耗蓝比例 / ref.天蓝增幅耗蓝除数);

    // 镰刀光斩系统变量（镰刀模式）
    ref.镰刀光斩标识 = target.刀 + "镰刀光斩";
    ref.镰刀光斩时间戳名 = ref.镰刀光斩标识 + "时间戳";
    ref.镰刀光斩时间间隔 = _root.随机整数(ref.镰刀光斩间隔下限, ref.镰刀光斩间隔上限);
    ref.镰刀光斩耗蓝量 = Math.floor(target.mp满血值 / 100 * 耗蓝比例);

    // 镰刀风车斩系统变量（瞬步斩时使用）
    ref.镰刀风车斩标识 = target.刀 + "镰刀风车斩";
    ref.镰刀风车斩时间戳名 = ref.镰刀风车斩标识 + "时间戳";
    ref.镰刀风车斩时间间隔 = _root.随机整数(ref.镰刀风车斩间隔下限, ref.镰刀风车斩间隔上限);
    ref.镰刀风车斩耗蓝量 = Math.floor(target.mp满血值 / 100 * 耗蓝比例);

    // ===== 跳砍追踪系统配置 =====
    var 追踪耗蓝比例:Number = param.trackingMpCostRatio || 5;
    ref.跳砍甜区距离X = param.jumpSweetSpotDistX || 195;
    ref.跳砍甜区X宽容度 = param.jumpSweetSpotTolerance || 99;
    ref.跳砍追踪X速度系数 = param.trackingSpeedCoeff || 10; // 追踪速度 = 行走X速度 / 系数
    ref.跳砍追踪强度容量 = param.trackingCapacity || 240;
    ref.跳砍追踪强度下限 = param.trackingMinThreshold || 3;

    // 初始化追踪强度（首次）
    if (isNaN(target.跳砍追踪强度)) {
        target.跳砍追踪强度 = ref.跳砍追踪强度下限;
    }

    // 追踪充能系统变量
    ref.追踪充能标识 = target.刀 + "追踪充能";
    ref.追踪充能时间戳名 = ref.追踪充能标识 + "时间戳";
    ref.追踪充能时间间隔 = param.trackingChargeInterval || 1000;
    ref.追踪充能耗蓝量 = Math.floor(target.mp满血值 / 100 * 追踪耗蓝比例);

    // 空中兵器攻击配置（镰刀光斩时附加）
    // 缓存参数模板，运行时只需更新动态值
    ref.空中兵器攻击参数 = {
        Z轴攻击范围: param.airBladeAttackZRange || 150,
        击中后子弹的效果: "斩打命中特效",
        击倒率: param.airBladeAttackKnockdown || 10,
        水平击退速度: param.airBladeAttackHorizontalKnockback || 10,
        垂直击退速度: param.airBladeAttackVerticalKnockback || 3
    };
    ref.空中兵器攻击威力除数 = param.airBladeAttackPowerDivisor || 5;
    ref.空中光斩间隔除数 = param.airSlashIntervalDivisor || 2;

    // 子弹威力计算配置
    ref.子弹威力倍率 = param.bulletPowerMultiplier || 30;
    ref.天蓝增幅回蓝倍率 = param.cyanBoostMpRecoveryMultiplier || 2;

    // 动画配置
    ref.凶斩展开比例 = param.fierceSlashExpandRatio || 0.667;
    ref.瞬步斩旋转下限 = param.flashSlashRotationMin || 60;
    ref.瞬步斩旋转上限 = param.flashSlashRotationMax || 120;
    ref.瞬步斩缩放除数 = param.flashSlashScaleDivisor || 4;
    ref.瞬步斩动画Y = param.flashSlashAnimY || -600;
    ref.正常动画Y = param.normalAnimY || -242;

    // 风车斩Y轴偏移
    ref.风车斩Y偏移 = param.windmillSlashYOffset || 50;

    // 追踪系统配置
    ref.距离修正除数 = param.distanceCorrectionDivisor || 30;
    ref.追踪警告阈值50 = param.trackingWarningThreshold50 || 0.5;
    ref.追踪警告阈值20 = param.trackingWarningThreshold20 || 0.2;

    // ===== 战技系统配置 =====
    ref.战技时间戳名 = target.刀 + "战技时间戳";
    ref.战技时间间隔 = param.skillInterval || 10000;
    ref.战技mp消耗 = param.skillMpCost || 30;

    // ===== 瞬步斩握持变形配置 =====
    ref.瞬步斩帧起始 = param.flashSlashFrameStart || 370;
    ref.瞬步斩帧结束 = param.flashSlashFrameEnd || 405;

    // ===== 子弹属性配置 =====
    ref.蓝色音符子弹属性 = ref.子弹配置.bullet_1;
    ref.天蓝增幅子弹属性 = ref.子弹配置.bullet_2;
    ref.镰刀光斩子弹属性 = ref.子弹配置.bullet_3;
    ref.镰刀风车斩子弹属性 = ref.子弹配置.bullet_4;
    ref.追踪充能子弹属性 = ref.子弹配置.bullet_5;
    if (!ref.__兵器跳浮空维持Hooked) {
        ref.__兵器跳浮空维持Hooked = true;

        var 兵器跳浮空维持硬直触发:Function = function():Void {
            if (this.击中地图) return;

            var shooter:MovieClip = this.shooter;
            if (!shooter) return;

            if (_root.控制目标 !== shooter._name) return;
            if (!shooter.浮空) return;
            if (isNaN(shooter.垂直速度) || shooter.垂直速度 <= -1) return;
            if (shooter.状态 != "兵器跳") return;
            if (shooter.man && shooter.man.坠地中) return;

            var 刀剑攻击:Object = shooter.被动技能 ? shooter.被动技能.刀剑攻击 : null;
            if (!刀剑攻击 || !刀剑攻击.启用) return;
            if (shooter.硬直 && shooter.man) shooter.硬直(shooter.man, _root.钝感硬直时间);
        };

        if (ref.镰刀光斩子弹属性) {
            var oldOnHit:Function = ref.镰刀光斩子弹属性.击中时触发函数;
            ref.镰刀光斩子弹属性.击中时触发函数 = function():Void {
                if (oldOnHit) oldOnHit.call(this);
                兵器跳浮空维持硬直触发.call(this);
            };
        }

        if (ref.空中兵器攻击参数) {
            var oldMeleeOnHit:Function = ref.空中兵器攻击参数.击中时触发函数;
            ref.空中兵器攻击参数.击中时触发函数 = function():Void {
                if (oldMeleeOnHit) oldMeleeOnHit.call(this);
                兵器跳浮空维持硬直触发.call(this);
            };
        }
    }

    // ===== 战技系统配置 =====
    ref.skill_0 = param.skill_0; // 地面战技：瞬步斩
    ref.skill_1 = param.skill_1; // 空中战技：镰刀追踪充能
    ref.当前装载战技 = null; // 当前已装载的战技

    // 装载主动战技函数（带变更检查）
    ref.装载战技 = function(目标战技:Object) {
        // 检查是否需要变更
        if (ref.当前装载战技 === 目标战技) return;

        ref.当前装载战技 = 目标战技;
        target.装载主动战技(目标战技, "兵器");

        if (ref.是否为主角) {
            _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
        }
    };

    // 获取当前应装载的战技
    ref.获取目标战技 = function():Object {
        if (ref.weaponMode != "镰刀") return null; // 键盘模式无战技
        if (_root.是否兵器跳(target)) return ref.skill_1; // 空中：追踪充能
        return ref.skill_0; // 地面：瞬步斩
    };

    // 初始装载战技
    ref.装载战技(ref.获取目标战技());

    // 订阅 WeaponSkill 事件处理空中充能逻辑
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        // 空中战技：镰刀追踪充能
        if (mode != "兵器") return;
        if (ref.weaponMode == "镰刀" && _root.是否兵器跳(target)) {
            // 空中按技能键触发追踪充能
            _root.装备生命周期函数.键盘镰刀充能跳砍追踪强度(ref);
            target.temp_y = 0;
        }
    });
};

_root.装备生命周期函数.键盘镰刀周期 = function(ref:Object, param:Object)
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;

    // 武器形态切换检测
    if (target.攻击模式 == "兵器" && _root.按键输入检测(target, _root.武器变形键)) {
        _root.更新并执行时间间隔动作(
            ref,
            "武器形态切换",
            function() { _root.装备生命周期函数.键盘镰刀切换武器形态(ref); },
            ref.transformInterval,
            false
        );
    }

    // 动画控制和更新
    _root.装备生命周期函数.键盘镰刀动画控制(ref);

    // 刀口位置更新
    _root.装备生命周期函数.键盘镰刀更新刀口位置(ref);

    // 瞬步斩握持变形
    _root.装备生命周期函数.键盘镰刀握持变形(ref);

    // 镰刀模式特殊系统：跳砍追踪 + 战技
    if (ref.weaponMode == "镰刀") {
        _root.装备生命周期函数.键盘镰刀跳砍系统(ref);
    }

    // 战斗逻辑
    _root.装备生命周期函数.键盘镰刀战斗周期(ref);
};

// ===== 武器形态切换函数 =====
_root.装备生命周期函数.键盘镰刀切换武器形态 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    if (ref.weaponMode == "镰刀") {
        // 切换为键盘
        ref.weaponMode = "键盘";
        target.刀属性.power = ref.baseDamage * ref.keyboardDamageMultiplier;
        target.兵器动作类型 = ref.actionTypeKeyboard;
    } else {
        // 切换为镰刀
        ref.weaponMode = "镰刀";
        target.刀属性.power = ref.baseDamage;
        target.兵器动作类型 = ref.actionTypeScythe;
    }

    _root.发布消息("键盘武器类型切换为[" + ref.weaponMode + "]");

    // 保存武器类型到全局参数
    if (ref.globalParam) ref.globalParam.weaponMode = ref.weaponMode;

    // 重新装载战技
    if (ref.装载战技) ref.装载战技(ref.获取目标战技());
};

// ===== 动画控制函数 =====
_root.装备生命周期函数.键盘镰刀动画控制 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    // 判断是否应该展开镰刀
    var shouldExpand = function():Boolean {
        if (!_root.兵器使用检测(target) && target.攻击模式 != "兵器" || ref.weaponMode == "键盘") {
            return false;
        }

        if (_root.装备生命周期函数.键盘镰刀正在使用技能(ref, "凶斩")) {
            // 凶斩时快速展开到指定比例
            ref.animFrame = Math.max(ref.animFrame, Math.floor(ref.animDuration * ref.凶斩展开比例));
        }

        return true;
    };

    // 根据状态调整动画帧值
    if (shouldExpand()) {
        if (ref.animFrame < ref.animDuration) {
            ref.animFrame++;
        }
    } else {
        if (ref.animFrame > 1) {
            ref.animFrame--;
        }
    }

    // 调用动画更新函数
    _root.装备生命周期函数.键盘镰刀动画更新(ref);
};

// ===== 动画更新函数 =====
_root.装备生命周期函数.键盘镰刀动画更新 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var scythe:MovieClip = target.刀_引用;

    if (scythe.动画) {
        scythe.动画.gotoAndStop(ref.animFrame);
    }
};

// ===== 刀口位置更新函数 =====
_root.装备生命周期函数.键盘镰刀更新刀口位置 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var scythe:MovieClip = target.刀_引用;

    var isScythe:Boolean = (ref.weaponMode == "镰刀");
    var mode:String = isScythe ? "scythe" : "keyboard";

    if (scythe.刀口位置1) {
        scythe.刀口位置1._x = ref.bladePos1[mode].x;
        scythe.刀口位置1._y = ref.bladePos1[mode].y;
    }

    if (scythe.刀口位置2) {
        scythe.刀口位置2._x = ref.bladePos2[mode].x;
        scythe.刀口位置2._y = ref.bladePos2[mode].y;
    }

    if (scythe.刀口位置3) {
        scythe.刀口位置3._x = ref.bladePos3[mode].x;
        scythe.刀口位置3._y = ref.bladePos3[mode].y;
    }
};

// ===== 工具函数：获得随机坐标偏离 =====
_root.装备生命周期函数.键盘镰刀获得随机坐标偏离 = function(ref:Object):Object
{
    var target:MovieClip = ref.自机;
    var xOffset:Number = (_root.basic_random() - 0.5) * 2 * ref.坐标偏移范围;
    var yOffset:Number = (_root.basic_random() - 0.5) * 2 * ref.坐标偏移范围;
    return {x: target._x + xOffset, y: target._y + yOffset};
};

// ===== 蓝色音符系统（键盘模式） =====
_root.装备生命周期函数.键盘镰刀释放蓝色音符 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var myPoint:Object = _root.装备生命周期函数.键盘镰刀获得随机坐标偏离(ref);
    var 增幅名:String = ref.蓝色音符标识 + "攻击增幅";

    if (ref.增幅次数[增幅名] === undefined) {
        ref.增幅次数[增幅名] = 1;
    }
    if (ref.增幅次数[增幅名] <= ref.蓝色音符最大增幅次数) {
        // 速度增幅 - 通过 buff 管理器处理（同ID自动替换旧buff）
        var 速度提升倍率:Number = (100 + ref.蓝色音符速度增幅百分比) / 100;
        var 累计倍率:Number = Math.pow(速度提升倍率, ref.增幅次数[增幅名]);

        var buffName:String = "蓝色音符速度增幅";
        var childBuffs:Array = [
            new PodBuff("行走X速度", BuffCalculationType.MULT_POSITIVE, 累计倍率)
        ];
        var metaBuff:MetaBuff = new MetaBuff(childBuffs, [], 0);
        target.buffManager.addBuffImmediate(metaBuff, buffName);

        _root.发布消息("速度第" + ref.增幅次数[增幅名] + "次上升" + ref.蓝色音符速度增幅百分比 + "%！目前速度为" + Math.floor(target.行走X速度 * 20) / 10 + "m/s！");
        ref.增幅次数[增幅名] += 1;
    }

    var 子弹属性:Object = ref.蓝色音符子弹属性;
    子弹属性.子弹威力 = ref.蓝色音符耗蓝量 * ref.蓝色音符威力倍率;
    子弹属性.发射者 = target._name;
    子弹属性.shootX = myPoint.x;
    子弹属性.shootY = target._y;
    子弹属性.shootZ = target._y;
    _root.子弹区域shoot传递(子弹属性);

    ref.蓝色音符时间间隔 = _root.随机整数(ref.蓝色音符间隔下限, ref.蓝色音符间隔上限);
};

// ===== 天蓝增幅系统（键盘模式） =====
_root.装备生命周期函数.键盘镰刀释放天蓝增幅 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var myPoint:Object = _root.装备生命周期函数.键盘镰刀获得随机坐标偏离(ref);

    var 子弹属性:Object = ref.天蓝增幅子弹属性;
    子弹属性.子弹威力 = ref.天蓝增幅耗蓝量 * ref.子弹威力倍率;
    子弹属性.发射者 = target._name;
    子弹属性.shootX = myPoint.x;
    子弹属性.shootY = target._y;
    子弹属性.shootZ = target._y;
    _root.子弹区域shoot传递(子弹属性);

    target.mp -= ref.天蓝增幅耗蓝量;
    ref.天蓝增幅时间间隔 = _root.随机整数(ref.蓝色音符间隔下限, ref.蓝色音符间隔上限) * ref.天蓝增幅间隔倍率;

    // MP回复逻辑
    if (target.mp < target.mp满血值) {
        var 回蓝量:Number = Math.min(target.mp满血值 - target.mp, ref.天蓝增幅耗蓝量 * ref.天蓝增幅回蓝倍率);
        target.mp += 回蓝量;
    }
};

// ===== 镰刀光斩系统（镰刀模式） =====
_root.装备生命周期函数.键盘镰刀释放镰刀光斩 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    // 计算发射位置
    var 修正:Number = ref.镰刀光斩距离系数 * target.身高 / 175;
    if (target.方向 == "左") {
        修正 *= -1;
    }

    var 子弹属性:Object = ref.镰刀光斩子弹属性;
    子弹属性.子弹威力 = ref.镰刀光斩耗蓝量 * ref.子弹威力倍率 + ref.baseDamage;
    子弹属性.发射者 = target._name;
    子弹属性.shootX = target._x + 修正;
    子弹属性.shootY = target._y;
    子弹属性.shootZ = target._y;

    var isInAir:Boolean = _root.是否兵器跳(target);
    _root.子弹区域shoot传递(子弹属性);

    // 空中额外释放兵器攻击（使用缓存的参数模板）
    if (isInAir) {
        var 兵器参数:Object = ref.空中兵器攻击参数;
        兵器参数.子弹威力 = target.空手攻击力 / ref.空中兵器攻击威力除数 + target.刀属性.power;
        target.刀口位置生成子弹(target, 兵器参数);
    }

    // 空中时发射频率提升（间隔缩短）
    var 基础间隔:Number = _root.随机整数(ref.镰刀光斩间隔下限, ref.镰刀光斩间隔上限);
    ref.镰刀光斩时间间隔 = isInAir ? Math.floor(基础间隔 / ref.空中光斩间隔除数) : 基础间隔;
};

// ===== 镰刀风车斩系统（瞬步斩时使用） =====
_root.装备生命周期函数.键盘镰刀释放镰刀风车斩 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var scythe:MovieClip = target.刀_引用;

    // 坐标转换
    var myPoint:Object = {x: scythe._x, y: scythe._y};
    scythe._parent.localToGlobal(myPoint);
    _root.gameworld.globalToLocal(myPoint);

    var 子弹属性:Object = ref.镰刀风车斩子弹属性;
    子弹属性.子弹威力 = ref.镰刀风车斩耗蓝量 * ref.子弹威力倍率 + ref.baseDamage;
    子弹属性.发射者 = target._name;
    子弹属性.shootX = myPoint.x;
    子弹属性.shootY = target._y - ref.风车斩Y偏移;
    子弹属性.shootZ = target._y - ref.风车斩Y偏移;
    _root.子弹区域shoot传递(子弹属性);

    ref.镰刀风车斩时间间隔 = _root.随机整数(ref.镰刀风车斩间隔下限, ref.镰刀风车斩间隔上限);
};

// ===== 战斗主循环 =====
_root.装备生命周期函数.键盘镰刀战斗周期 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    if (!_root.兵器攻击检测(target)) return;

    // 瞬步斩时不释放普通光斩
    if (_root.装备生命周期函数.键盘镰刀正在使用瞬步斩(ref)) return;

    if (ref.weaponMode == "镰刀") {
        // 镰刀模式：释放镰刀光斩
        if (_root.更新时间间隔(target, ref.镰刀光斩时间戳名, ref.镰刀光斩时间间隔)) {
            _root.装备生命周期函数.键盘镰刀释放镰刀光斩(ref);
        }
    } else {
        // 键盘模式：释放蓝色音符和天蓝增幅
        if (_root.更新时间间隔(target, ref.蓝色音符时间戳名, ref.蓝色音符时间间隔)) {
            _root.装备生命周期函数.键盘镰刀释放蓝色音符(ref);
        }

        if (target.mp >= ref.天蓝增幅耗蓝量) {
            if (_root.更新时间间隔(target, ref.天蓝增幅时间戳名, ref.天蓝增幅时间间隔)) {
                _root.装备生命周期函数.键盘镰刀释放天蓝增幅(ref);
            }
        }
    }
};

// ===== 跳砍追踪系统 =====
_root.装备生命周期函数.键盘镰刀获得敌我距离差 = function(ref:Object):Object
{
    var target:MovieClip = ref.自机;
    if (target.攻击目标 != "无") {
        var enemy:MovieClip = _root.gameworld[target.攻击目标];
        return {
            x: enemy._x - target._x,
            y: enemy.Z轴坐标 - target.Z轴坐标
        };
    }
    return {x: 0, y: 0};
};

_root.装备生命周期函数.键盘镰刀跳砍修正 = function(ref:Object)
{
    var target:MovieClip = ref.自机;

    _root.寻找攻击目标基础函数(target);
    if (target.攻击目标 == "无") return;

    var 修正系数:Number = target.跳砍追踪强度 / ref.跳砍追踪强度容量;
    var 距离差:Object = _root.装备生命周期函数.键盘镰刀获得敌我距离差(ref);
    var 距离差X:Number = 距离差.x;
    var 甜区距离X:Number = ref.跳砍甜区距离X * target.身高 / 175;
    var 宽容距离X:Number = 甜区距离X * ref.跳砍甜区X宽容度 / 100 * 修正系数;
    var 跳砍追踪X速度:Number = target.行走X速度 / ref.跳砍追踪X速度系数; // 动态获取
    var 修正距离X:Number = (跳砍追踪X速度 + Math.abs(距离差X) / ref.距离修正除数) * 修正系数;
    var 是否充能:Boolean = target.跳砍追踪强度 > ref.跳砍追踪强度下限;

    // X轴修正
    var 移动方向:String = 距离差.x > 0 ? "右" : "左";
    var 速度:Number = 距离差X > 甜区距离X - 宽容距离X
        ? Math.min(修正距离X, 距离差X - 甜区距离X)
        : (距离差X + 甜区距离X - 宽容距离X < 0
            ? Math.max(-1 * 修正距离X, 距离差X + 甜区距离X)
            : 0);
    if (移动方向 == "左") {
        速度 *= -1;
    }
    target.移动(移动方向, 速度);

    // 设置方向和消耗追踪强度
    if (是否充能) {
        target.跳跃中左右方向 = 移动方向;
        target.方向改变(target.跳跃中左右方向);

        // 追踪强度提示
        if (target.跳砍追踪强度 == 4) {
            _root.发布消息("镰刀追踪充能衰竭！");
        } else if (target.跳砍追踪强度 == Math.floor(ref.跳砍追踪强度容量 * ref.追踪警告阈值50)) {
            _root.发布消息("镰刀追踪充能还剩50%！");
        } else if (target.跳砍追踪强度 == Math.floor(ref.跳砍追踪强度容量 * ref.追踪警告阈值20)) {
            _root.发布消息("镰刀追踪充能还剩20%！");
        }
        target.跳砍追踪强度 -= 1;
    }

    // Y轴修正
    if (target.跳横移速度 == 0) {
        target.跳跃中上下方向 = 距离差.y > 0 ? "下" : "上";
        target.跳跃上下移动(target.跳跃中上下方向, target.跳跃中移动速度 / 2 * 修正系数);
    }
};

_root.装备生命周期函数.键盘镰刀追踪充能 = function(ref:Object, 充能数值:Number)
{
    var target:MovieClip = ref.自机;
    target.跳砍追踪强度 = Math.min(ref.跳砍追踪强度容量, target.跳砍追踪强度 + 充能数值);
};

_root.装备生命周期函数.键盘镰刀释放追踪充能 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var myPoint:Object = _root.装备生命周期函数.键盘镰刀获得随机坐标偏离(ref);

    var 子弹属性:Object = ref.追踪充能子弹属性;
    子弹属性.子弹威力 = ref.追踪充能耗蓝量;
    子弹属性.发射者 = target._name;
    子弹属性.shootX = myPoint.x;
    子弹属性.shootY = target._y;
    子弹属性.shootZ = target._y;
    _root.子弹区域shoot传递(子弹属性);

    if (target.跳砍追踪强度 < ref.跳砍追踪强度容量) {
        target.mp -= ref.追踪充能耗蓝量;
        _root.装备生命周期函数.键盘镰刀追踪充能(ref, ref.追踪充能耗蓝量 * ref.追踪充能倍率);
    }
};

_root.装备生命周期函数.键盘镰刀充能跳砍追踪强度 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    if (target.mp >= ref.追踪充能耗蓝量) {
        _root.装备生命周期函数.键盘镰刀释放追踪充能(ref);
        _root.发布消息("镰刀追踪充能至" + Math.floor(target.跳砍追踪强度 / ref.跳砍追踪强度容量 * 1000) / 10 + "%!");
    }
};

_root.装备生命周期函数.键盘镰刀跳砍系统 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var isInAir:Boolean = _root.是否兵器跳(target);

    // 动态切换战技（统一使用装载战技函数，内部有变更检查）
    ref.装载战技(ref.获取目标战技());

    // 空中：跳砍追踪修正（自动执行，不需要按键）
    if (isInAir) {
        _root.装备生命周期函数.键盘镰刀跳砍修正(ref);
    }
    // 注意：战技释放由战技系统自动处理，不再手动检测按键
};

// ===== 技能判断函数（基于通用兵器技能检测） =====
_root.装备生命周期函数.键盘镰刀正在使用技能 = function(ref:Object, 技能名:String):Boolean
{
    return _root.兵器技能检测(ref.自机, 技能名) && ref.weaponMode == "镰刀";
};

// ===== 瞬步斩握持变形系统 =====
_root.装备生命周期函数.键盘镰刀正在使用瞬步斩 = function(ref:Object):Boolean
{
    return _root.装备生命周期函数.键盘镰刀正在使用技能(ref, "瞬步斩");
};

_root.装备生命周期函数.键盘镰刀握持变形 = function(ref:Object)
{
    var target:MovieClip = ref.自机;
    var scythe:MovieClip = target.刀_引用;
    if (!scythe || !scythe.动画) return;

    if (_root.装备生命周期函数.键盘镰刀正在使用瞬步斩(ref)) {
        // 瞬步斩中：变形握持 + 释放风车斩
        scythe.动画._y = ref.瞬步斩动画Y;
        scythe._rotation += _root.随机整数(ref.瞬步斩旋转下限, ref.瞬步斩旋转上限);
        scythe._xscale = ref.initialXScale / ref.瞬步斩缩放除数;

        if (_root.更新时间间隔(target, ref.镰刀风车斩时间戳名, ref.镰刀风车斩时间间隔)) {
            _root.装备生命周期函数.键盘镰刀释放镰刀风车斩(ref);
        }
    } else {
        // 正常状态：恢复握持
        scythe.动画._y = ref.正常动画Y;
        scythe._rotation = ref.initialRotation;
        scythe._xscale = ref.initialXScale;
    }
};

/*
===== 原始资产代码参考 =====
来源: flashswf\arts\new\fs配置素材\LIBRARY\键盘镰刀\键盘镰刀.xml

===== 刀口位置3 (跳砍追踪、战技系统) =====
onClipEvent (load) {
	var 自机 = _root.获得父节点(this, 5);
	var 武器类型名 = "武器类型名" + 自机.刀;
	var 跳砍甜区距离X = 195;
	var 跳砍甜区X宽容度 = 99;
	var 跳砍追踪X速度 = 自机.行走X速度 / 10;
	var 跳砍追踪强度容量 = 240;
	var 跳砍追踪强度下限 = 3;
	if (isNaN(自机.跳砍追踪强度))
	{
		自机.跳砍追踪强度 = 跳砍追踪强度下限;
	}

	var 耗蓝比例 = 5;
	var 坐标偏移范围 = 10;
	//_root.调试模式 = true;
	this.动态调整位置 = function()
	{//镰刀模式切换位移
		if (自机[武器类型名] == "镰刀")
		{
			this._x = -410.6;
			this._y = 637.25;
		}
		else
		{
			this._x = 12;
			this._y = 35;
		}
	};
	this.检查并执行时间间隔动作 = _root.检查并执行时间间隔动作;
	this.获得随机坐标偏离 = _root.获得随机坐标偏离;

	this.动态调整位置();
	this.是否兵器跳 = function()
	{
		if (自机._currentframe >= 599 and 自机._currentframe <= 618)
		{
			return true;
		}
		else
		{
			return false;
		}
	};
	this.寻找攻击目标 = _root.寻找攻击目标基础函数;

	this.获得敌我距离差 = function()
	{
		//_root.发布调试消息(自机.攻击目标 + _root.gameworld[自机.攻击目标]._x);
		if (自机.攻击目标 != "无")
		{
			return {x:_root.gameworld[自机.攻击目标]._x - 自机._x, y:_root.gameworld[自机.攻击目标].Z轴坐标 - 自机.Z轴坐标};
		}
		return {x:0, y:0};// 异常处理，如果没有找到目标，返回 {0, 0}
	};
	this.镰刀跳砍修正 = function()
	{
		this.寻找攻击目标(自机);
		if (自机.攻击目标 != "无")
		{
			var 修正系数 = 自机.跳砍追踪强度 / 跳砍追踪强度容量;
			var 距离差 = this.获得敌我距离差();
			var 距离差X = 距离差.x;
			var 距离差Y = 距离差.y;
			var 甜区距离X = 跳砍甜区距离X * 自机.身高 / 175;
			var 宽容距离X = 甜区距离X * 跳砍甜区X宽容度 / 100 * 修正系数;
			var 修正距离X = (跳砍追踪X速度 + Math.abs(距离差X) / 30) * 修正系数;
			var 是否充能 = 自机.跳砍追踪强度 > 跳砍追踪强度下限 ? true : false;
			// X轴修正，宽容距离代表自动修正
			//自机._x += 距离差X > 甜区距离X - 宽容距离X ? Math.min(修正距离X, 距离差X - 甜区距离X) : (距离差X + 甜区距离X - 宽容距离X < 0 ? Math.max(-1 * 修正距离X, 距离差X + 甜区距离X) : 0);
			var 移动方向 = 距离差.x > 0 ? "右" : "左";
			var 速度 = 距离差X > 甜区距离X - 宽容距离X ? Math.min(修正距离X, 距离差X - 甜区距离X) : (距离差X + 甜区距离X - 宽容距离X < 0 ? Math.max(-1 * 修正距离X, 距离差X + 甜区距离X) : 0);
			if (移动方向 == "左")
			{
				速度 *= -1;
			}
			自机.移动(移动方向,速度);
			// 设置左右方向
			if (是否充能)
			{
				自机.跳跃中左右方向 = 移动方向;
				自机.方向改变(自机.跳跃中左右方向);
				if (自机.跳砍追踪强度 == 4)
				{
					_root.发布消息("镰刀追踪充能衰竭！");
				}
				else if (自机.跳砍追踪强度 == Math.floor(跳砍追踪强度容量 * 0.5))
				{
					_root.发布消息("镰刀追踪充能还剩50%！");
				}
				else if (自机.跳砍追踪强度 == Math.floor(跳砍追踪强度容量 * 0.2))
				{
					_root.发布消息("镰刀追踪充能还剩20%！");
				}
				自机.跳砍追踪强度 -= 1;//自动衰减强度
			}
			// Y轴修正
			if (自机.跳横移速度 == 0)
			{
				自机.跳跃中上下方向 = 距离差.y > 0 ? "下" : "上";
				自机.跳跃上下移动(自机.跳跃中上下方向,自机.跳跃中移动速度 / 2 * 修正系数);
			}
		}
	};

	var 追踪充能标识 = 自机.刀 + "追踪充能";
	var 追踪充能时间戳名 = 追踪充能标识 + "时间戳";
	var 追踪充能时间间隔 = 1 * 1000;
	var 追踪充能耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	this.追踪充能倍率 = 3;

	this.追踪充能 = function(充能数值:Number)
	{
		自机.跳砍追踪强度 = Math.min(跳砍追踪强度容量, 自机.跳砍追踪强度 + 充能数值);
	};
	this.释放追踪充能 = function()
	{
		var myPoint = this.获得随机坐标偏离(自机, 坐标偏移范围);

		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 360;
		发射效果 = "";
		子弹种类 = "天蓝增幅";
		子弹威力 = 追踪充能耗蓝量 * 1;
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
		if (自机.跳砍追踪强度 < 跳砍追踪强度容量)
		{
			自机.mp -= 追踪充能耗蓝量;
			this.追踪充能(追踪充能耗蓝量 * this.追踪充能倍率);
		}

	};
	this.充能跳砍追踪强度 = function()
	{
		if (自机.mp >= 追踪充能耗蓝量)
		{
			this.释放追踪充能();
			_root.发布消息("镰刀追踪充能至" + Math.floor(自机.跳砍追踪强度 / 跳砍追踪强度容量 * 1000) / 10 + "%!");
		}
	};
	var 战技时间戳名 = 自机.刀 + "战技" + "时间戳";
	var 战技时间间隔 = 10 * 1000;
	var 战技mp消耗 = 30;

	this.释放战技 = function()
	{
		自机.技能名 = "瞬步斩";
		自机.技能等级 = Math.min(10, _root.获得强化等级(_root.刀));
		自机.mp -= 战技mp消耗;
		自机.状态改变("技能");
	};
	this.onEnterFrame = function()
	{
		this.动态调整位置();

		if (自机[武器类型名] == "镰刀")
		{
			if (this.是否兵器跳())
			{
				if (Key.isDown(_root.武器技能键))
				{
					this.检查并执行时间间隔动作(自机,追踪充能时间间隔,"充能跳砍追踪强度",追踪充能时间戳名);

				}
				this.镰刀跳砍修正();
			}
			else
			{
				if (Key.isDown(_root.武器技能键) and 自机.攻击模式 == "兵器" and 自机.mp >= 战技mp消耗)
				{
					this.检查并执行时间间隔动作(自机,战技时间间隔,"释放战技",战技时间戳名);
				}
			}
		}


	};
}

===== 刀口位置2 (蓝色音符、天蓝增幅、镰刀光斩) =====
onClipEvent (load) {
	var 耗蓝比例 = 1;
	var 坐标偏移范围 = 10;
	var 自机 = _root.获得父节点(this, 5);
	var 武器类型名 = "武器类型名" + 自机.刀;
	if (自机[增幅次数] == undefined)
	{
		自机[增幅次数] = {};
	}
	this.动态调整位置 = function()
	{//镰刀模式切换位移
		if (自机[武器类型名] == "镰刀")
		{
			this._x = -182.35;
			this._y = 712.95;
		}
		else
		{
			this._x = 16;
			this._y = 125;
		}
	};
	this.获得随机时间间隔 = function()
	{
		return _root.随机整数(200, 1 * 1000);
	};
	this.检查并执行时间间隔动作 = _root.检查并执行时间间隔动作;
	this.获得随机坐标偏离 = _root.获得随机坐标偏离;

	var 蓝色音符标识 = 自机.刀 + "蓝色音符";
	var 蓝色音符时间戳名 = 蓝色音符标识 + "时间戳";
	var 蓝色音符时间间隔 = this.获得随机时间间隔();
	var 蓝色音符耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	var 蓝色音符最大增幅次数 = 24;
	var 蓝色音符速度增幅百分比 = 2.5;
	this.释放蓝色音符 = function()
	{
		var myPoint = this.获得随机坐标偏离(自机, 坐标偏移范围);
		var 增幅名 = 蓝色音符标识 + "攻击增幅";

		if (自机[增幅次数][增幅名] === undefined)
		{
			自机[增幅次数][增幅名] = 1;
		}
		if (自机[增幅次数][增幅名] <= 蓝色音符最大增幅次数)
		{
			var 速度提升系数 = (100 + 蓝色音符速度增幅百分比) / 100;
			自机.行走X速度 *= 速度提升系数;
			自机.跳跃中移动速度 *= 速度提升系数;
			自机.行走Y速度 *= 速度提升系数;
			自机.跑X速度 *= 速度提升系数;
			自机.跑Y速度 *= 速度提升系数;
			自机.被击硬直度 /= 速度提升系数;
			自机.起跳速度 *= 速度提升系数;
			_root.发布消息("速度第" + 自机[增幅次数][增幅名] + "次上升" + 蓝色音符速度增幅百分比 + "%！目前速度为" + Math.floor(自机.行走X速度 * 20) / 10 + "m/s！");
			自机[增幅次数][增幅名] += 1;
		}
		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 360;
		发射效果 = "";
		子弹种类 = "蓝色音符";
		子弹威力 = 蓝色音符耗蓝量 * 10;
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
		蓝色音符时间间隔 = this.获得随机时间间隔();
	};

	var 天蓝增幅标识 = 自机.刀 + "天蓝增幅";
	var 天蓝增幅时间戳名 = 天蓝增幅标识 + "时间戳";
	var 天蓝增幅间隔倍率 = 3;
	var 天蓝增幅时间间隔 = this.获得随机时间间隔() * 天蓝增幅间隔倍率;
	var 天蓝增幅耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例 / 2);

	this.释放天蓝增幅 = function()
	{
		var myPoint = this.获得随机坐标偏离(自机, 坐标偏移范围);

		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 360;
		发射效果 = "";
		子弹种类 = "天蓝增幅";
		子弹威力 = 天蓝增幅耗蓝量 * 30;
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
		自机.mp -= 天蓝增幅耗蓝量;
		天蓝增幅时间间隔 = this.获得随机时间间隔() * 天蓝增幅间隔倍率;
		if (自机.mp < 自机.mp满血值)
		{
			var 回蓝量 = Math.min(自机.mp满血值 - 自机.mp, 天蓝增幅耗蓝量 * 2);
			自机.mp += 回蓝量;
			_parent.刀口位置3.追踪充能(回蓝量 * _parent.刀口位置3.追踪充能倍率);
		}
		_parent.刀口位置3.追踪充能(回蓝量 * _parent.刀口位置3.追踪充能倍率);
		_root.发布消息("镰刀追踪充能至" + Math.floor(自机.跳砍追踪强度 / _parent.刀口位置3.跳砍追踪强度容量 * 1000) / 10 + "%!");

	};
	var 镰刀光斩标识 = 自机.刀 + "镰刀光斩";
	var 镰刀光斩时间戳名 = 镰刀光斩标识 + "时间戳";
	var 镰刀光斩时间间隔 = this.获得随机时间间隔();
	var 镰刀光斩耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	this.释放镰刀光斩 = function()
	{

		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 0;
		发射效果 = "";
		子弹种类 = "镰刀光斩";
		子弹威力 = 镰刀光斩耗蓝量 * 30 + 自机.键盘基础伤害;
		子弹速度 = 0;
		击中地图效果 = "";
		Z轴攻击范围 = 40;
		击倒率 = 10;
		击中后子弹的效果 = "";
		子弹敌我属性 = true;
		发射者名 = 自机._name;
		子弹敌我属性值 = !自机.是否为敌人;
		var 修正 = 195 * 自机.身高 / 175;
		if (自机.方向 == "左")
		{
			修正 *= -1;
		}
		shootX = 自机._x + 修正;
		Z轴坐标 = shootY = 自机._y;
		_root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,子弹敌我属性值,击倒率,击中后子弹的效果);
		镰刀光斩时间间隔 = this.获得随机时间间隔();
	};
	this.动态调整位置();
	this.onEnterFrame = function()
	{
		var 释放光斩:Boolean = false;
		if (_root.兵器攻击检测(自机))
		{
			if (自机[武器类型名] == "镰刀")
			{
				if (!_parent.动画.正在使用瞬步斩())
				{
					if (_parent.刀口位置3.是否兵器跳() and 自机.man._currentframe >= 5 and false)
					{
						释放光斩 = true;//跳砍
					}
					else if (自机._currentframe >= 619 and 自机._currentframe <= 628 and false)
					{
						switch (自机.man._currentframe)
						{
							case 7 :
							case 20 :
							case 34 :
							case 50 :
								释放光斩 = true;//平砍
								break;
						}
					}
					else
					{
						释放光斩 = true;
					}
				}
				if (释放光斩)
				{
					this.检查并执行时间间隔动作(自机,镰刀光斩时间间隔,"释放镰刀光斩",镰刀光斩时间戳名);
				}
			}
			else
			{
				this.检查并执行时间间隔动作(自机,蓝色音符时间间隔,"释放蓝色音符",蓝色音符时间戳名);
				this.检查并执行时间间隔动作(自机,天蓝增幅时间间隔,"释放天蓝增幅",天蓝增幅时间戳名);

			}
		}
		this.动态调整位置();
	};
}

===== 刀口位置1 (动态位置调整) =====
onClipEvent (load) {
	var 自机 = _root.获得父节点(this, 5);
	var 武器类型名 = "武器类型名" + 自机.刀;
	this.动态调整位置 = function()
	{//镰刀模式切换位移
		if (自机[武器类型名] == "镰刀")
		{
			this._x = 35.125;
			this._y = 637.25;
		}
		else
		{
			this._x = 20;
			this._y = 245;
		}
	};
	this.动态调整位置();
	this.onEnterFrame = function()
	{
		this.动态调整位置();
	};
}

===== 动画 (动画控制、武器形态切换、镰刀风车斩) =====
onClipEvent (load) {
	var 自机 = _root.获得父节点(this, 5);
	var 动画时长 = 15;
	var 变形时间间隔 = 1 * 1000;
	var 时间戳名 = 自机.刀 + "时间戳";
	var 武器类型名 = "武器类型名" + 自机.刀;
	var 动画帧名 = 自机.刀 + "动画帧";
	var 耗蓝比例 = 1;
	var 坐标偏移范围 = 10;
	this.检查并执行时间间隔动作 = _root.检查并执行时间间隔动作;


	this.获得随机时间间隔 = function()
	{
		return _root.随机整数(50, 150);
	};
	var 镰刀风车斩标识 = 自机.刀 + "镰刀风车斩";
	var 镰刀风车斩时间戳名 = 镰刀风车斩标识 + "时间戳";
	var 镰刀风车斩时间间隔 = this.获得随机时间间隔();
	var 镰刀风车斩耗蓝量 = Math.floor(自机.mp满血值 / 100 * 耗蓝比例);
	this.释放镰刀风车斩 = function()
	{
		var myPoint = {x:_parent._x, y:_parent._y};
		_parent.localToGlobal(myPoint);
		_root.gameworld.globalToLocal(myPoint);

		声音 = "";
		霰弹值 = 1;
		子弹散射度 = 360;
		发射效果 = "";
		子弹种类 = "镰刀风车斩";
		子弹威力 = 镰刀风车斩耗蓝量 * 30 + 自机.键盘基础伤害;
		子弹速度 = 0;
		击中地图效果 = "";
		Z轴攻击范围 = 40;
		击倒率 = 10;
		击中后子弹的效果 = "";
		子弹敌我属性 = true;
		发射者名 = 自机._name;
		子弹敌我属性值 = !自机.是否为敌人;
		shootX = myPoint.x;
		Z轴坐标 = shootY = 自机._y - 50;
		_root.子弹区域shoot(声音,霰弹值,子弹散射度,发射效果,子弹种类,子弹威力,子弹速度,Z轴攻击范围,击中地图效果,发射者名,shootX,shootY,Z轴坐标,子弹敌我属性值,击倒率,击中后子弹的效果);
		镰刀风车斩时间间隔 = this.获得随机时间间隔();
	};

	this.切换为键盘 = function()
	{
		自机[武器类型名] = "键盘";
		自机.刀属性.power = 自机.键盘基础伤害 * 0.8;
	};
	this.切换为镰刀 = function()
	{
		自机[武器类型名] = "镰刀";
		自机.刀属性.power = 自机.键盘基础伤害;
	};

	this.切换武器形态 = function()
	{
		(自机[武器类型名] == "镰刀") ? this.切换为键盘() : this.切换为镰刀();
	};
	if (自机[动画帧名] == undefined)
	{
		自机[动画帧名] = 1;
	}

	this.保存武装类型 = function()
	{
		if (_root.控制目标 == 自机._name)
		{
			_root[武器类型名] = 自机[武器类型名];//_root.发布调试消息(_root[武器类型名] + " " + 自机.武器类型);
		}
	};

	this.读取武装类型 = function()
	{
		if (_root.控制目标 == 自机._name and _root[武器类型名] == "键盘")
		{
			this.切换为键盘();
			//_root.发布调试消息(_root[武器类型名] + " " + 自机.武器类型);
		}
	};

	if (isNaN(自机.键盘基础伤害))
	{//初始化键盘数据

		自机.键盘基础伤害 = 自机.刀属性.power;
		自机.键盘旋转角度 = _parent._rotation;
		自机.键盘水平宽度 = _parent._xscale;
		自机.键盘刀口位置 = _parent.刀口位置1._x;
		自机[武器类型名] = "镰刀";
		this.读取武装类型();
	}


	gotoAndStop(自机[动画帧名]);
	this.判断是否展开 = function()
	{
		if (!_root.兵器使用检测(自机) and 自机.攻击模式 != "兵器" or 自机[武器类型名] == "键盘")
		{
			return false;
		}

		var 当前帧 = 自机.man._currentframe;
		if (当前帧 >= 370 and 当前帧 <= 413)
		{
			自机[动画帧名] = Math.max(自机[动画帧名], Math.floor(动画时长 * 2 / 3));// 凶斩的帧区间
		}

		return true;
	};
	this.展开动画 = function()
	{
		if (自机[动画帧名] < 动画时长)
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

	this.检查并执行时间间隔动作 = _root.检查并执行时间间隔动作;

	this.执行武器切换 = function()
	{
		this.切换武器形态();
		_root.发布消息("键盘武器类型切换为[" + 自机[武器类型名] + "]");
		this.保存武装类型();
	};
	this.正在使用瞬步斩 = function()
	{
		if (自机.状态 == "技能" and 自机.man._currentframe >= 370 and 自机.man._currentframe <= 405 and 自机[武器类型名] == "镰刀")
		{
			return true;//瞬步斩结束与413帧，为视觉效果提前回收
		}
		return false;
	};
	this.改变握持模式 = function()
	{
		if (this.正在使用瞬步斩())
		{
			this._y = -600;
			_parent._rotation += _root.随机整数(60, 120);
			_parent._xscale = 自机.键盘水平宽度 / 4;
			this.检查并执行时间间隔动作(自机,镰刀风车斩时间间隔,"释放镰刀风车斩",镰刀风车斩时间戳名);
		}
		else
		{
			this._y = -242;
			_parent._rotation = 自机.键盘旋转角度;
			_parent._xscale = 自机.键盘水平宽度;
		}
	};

	this.改变握持模式();
	this.onEnterFrame = function()
	{
		if (Key.isDown(_root.武器变形键) and 自机.攻击模式 == "兵器")
		{
			this.检查并执行时间间隔动作(自机,变形时间间隔,"执行武器切换",时间戳名);
		}
		this.改变握持模式();
		this[this.判断是否展开() ? '展开动画' : '折叠动画']();
		gotoAndStop(自机[动画帧名]);
	};
}
*/
