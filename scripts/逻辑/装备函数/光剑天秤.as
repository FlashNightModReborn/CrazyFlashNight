/**
 * 光剑天秤 - 装备生命周期函数
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 形态系统：默认形态 → 攻势形态 → 守御形态 → 默认形态（循环）
 * ═══════════════════════════════════════════════════════════════════════════
 * - 默认形态：动画帧1，无特殊效果
 * - 攻势形态：动画帧15，攻击时 +100伤害加成/-200防御力
 * - 守御形态：动画帧30，攻击时 -100伤害加成/+200防御力
 *
 * 过渡动画：
 * - 默认→攻势：帧1→15
 * - 攻势→守御：帧15→30
 * - 守御→默认：帧30→44，然后跳回帧1
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 核心玩法机制：天秤切换次数 → 主动技"天秤之力"伤害倍率
 * ═══════════════════════════════════════════════════════════════════════════
 * - 每次切换形态时 天秤切换次数++ （这是有意设计的积累机制）
 * - 主动技"天秤之力"伤害 = 耗蓝量 × 伤害系数 × 天秤切换次数
 * - 释放主动技后 天秤切换次数 重置为1
 * - 场景切换恢复形态时不增加计数（isRestore=true）
 *
 * 主动技能：通过 WeaponSkill 事件触发，释放逻辑在本文件中实现
 * 战技函数：单位函数_雾人_aka_fs_主动战技.as -> _root.主动战技函数.兵器.天秤之力（仅空壳）
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * Buff系统：使用 BuffManager 管理天秤转换的属性加成
 * ═══════════════════════════════════════════════════════════════════════════
 * - 业务层维护累计值（天秤伤害累计、天秤防御累计）
 * - 通过同 ID 替换驱动 BuffManager 重算
 * - buff 效果永久累加，不随形态切换清除（原始设计意图）
 */

_root.装备生命周期函数.光剑天秤初始化 = function(ref:Object, param:Object):Void
{
    var target:MovieClip = ref.自机;

    // 配置参数（帧数，30fps）
    ref.transformCooldownFrames = 30;  // 形态切换冷却（30帧 = 1秒）
    ref.attackCooldownFrames = 8;      // 攻击时天秤转换冷却（8帧 ≈ 250ms）
    ref.lastTransformFrame = 0;        // 上次形态切换帧数
    ref.lastAttackConvertFrame = 0;    // 上次攻击转换帧数

    // 动画帧配置
    // 形态停止帧
    ref.animFrames = {
        默认形态: 1,
        攻势形态: 15,
        守御形态: 30
    };
    // 过渡动画配置：{起始帧, 结束帧, 结束后跳转帧(可选)}
    ref.transitions = {
        默认形态_攻势形态: {start: 1, end: 15},
        攻势形态_守御形态: {start: 15, end: 30},
        守御形态_默认形态: {start: 30, end: 44, jumpTo: 1}
    };

    // 状态数据 - 直接存储在ref上
    ref.天秤切换次数 = 1;  // 【玩法核心】形态切换累计次数，影响主动技"天秤之力"伤害倍率
    ref.天秤转换次数 = 0;  // 当前形态内的buff转换次数（每次切换形态重置）
    ref.当前形态 = "默认形态";
    ref.当前动画帧 = 1;
    ref.isTransitioning = false;  // 是否正在过渡动画中
    ref.transitionTarget = null;  // 过渡目标形态
    ref.transitionEnd = 0;        // 过渡动画结束帧
    ref.transitionJumpTo = 0;     // 过渡结束后跳转帧（0表示不跳转）

    // 主动技CD状态（自行维护）
    ref.skillCdEndFrame = 0;      // 技能CD结束帧
    ref.isSkillInCd = false;      // 是否在CD中

    // BuffManager 累计值（业务层维护，用于同 ID 替换驱动重算）
    // 上下限与原 buff.调整 保持一致
    ref.天秤伤害累计 = 0;         // 伤害加成累计值，范围 [-20000, 20000]
    ref.天秤防御累计 = 0;         // 防御力累计值，范围 [-60000, 60000]
    ref.天秤伤害上限 = 20000;
    ref.天秤伤害下限 = -20000;
    ref.天秤防御上限 = 60000;
    ref.天秤防御下限 = -60000;

    // 初始化基础伤害数据
    if (isNaN(ref.默认形态基础伤害)) {
        ref.默认形态基础伤害 = target.刀属性.power;
    }

    // 全局主角同步（场景切换后恢复形态）
    if (ref.是否为主角) {
        var key:String = ref.标签名 + ref.初始化函数;
        // 确保全局参数对象存在
        if (!_root.装备生命周期函数.全局参数) {
            _root.装备生命周期函数.全局参数 = {};
        }
        if (!_root.装备生命周期函数.全局参数[key]) {
            _root.装备生命周期函数.全局参数[key] = {};
        }
        var gl:Object = _root.装备生命周期函数.全局参数[key];
        ref.globalData = gl;

        // 恢复保存的形态（仅视觉，不计数）
        if (gl.保存形态) {
            _root.装备生命周期函数.光剑天秤切换到形态(ref, gl.保存形态, true);
        }
    }

    target.syncRequiredEquips.刀_引用 = true; // 触发StatusChange中刀_引用的加载状态

    // ─────────────────────────────────────────────────────────────────────
    // 主动技能"天秤之力"事件订阅（通过闭包持久化ref访问）
    // ─────────────────────────────────────────────────────────────────────
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        if (mode != "兵器") return;

        // 读取技能参数
        var skill:Object = target.刀数据.skill;
        var 伤害系数:Number = skill.power > 0 ? Number(skill.power) : 12;
        var Z轴范围:Number = skill.range > 0 ? Number(skill.range) : 72;
        var 击退速度:Number = skill.knockback > 0 ? Number(skill.knockback) : 18;
        var cdMs:Number = skill.cd > 0 ? Number(skill.cd) : 5000;

        // 启动CD计时（cd单位ms，转换为帧数，30fps）
        var cdFrames:Number = Math.ceil(cdMs / 1000 * 30);
        ref.skillCdEndFrame = _root.帧计时器.当前帧数 + cdFrames;
        ref.isSkillInCd = true;

        // MP消耗由主动战技系统统一扣除，此处读取已扣蓝量用于伤害计算
        var 耗蓝量:Number = target.主动战技.兵器.消耗mp;

        // 【玩法核心】读取天秤切换次数，作为伤害倍率
        var 切换次数:Number = ref.天秤切换次数 || 1;

        _root.发布消息("共转换过" + 切换次数 + "次天秤，星盘转动的力量因此得到了强化……");

        var 子弹威力:Number = 耗蓝量 * 伤害系数 * 切换次数;

        // 释放后重置切换次数，开始新一轮积累
        ref.天秤切换次数 = 1;
        _root.发布消息("天秤转换的次数归一……");

        // 随机坐标偏移
        var offsetRange:Number = 50;
        var xOffset:Number = (Math.random() - 0.5) * 2 * offsetRange;

        var 子弹属性:Object = {
            声音: "",
            霰弹值: 1,
            子弹散射度: 0,
            发射效果: "",
            子弹种类: "天秤之力",
            子弹威力: 子弹威力,
            子弹速度: 0,
            击中地图效果: "",
            Z轴攻击范围: Z轴范围,
            击倒率: 1,
            击中后子弹的效果: "",
            水平击退速度: 击退速度,
            发射者: target._name,
            shootX: target._x + xOffset,
            shootY: target.Z轴坐标,
            shootZ: target.Z轴坐标
        };

        _root.子弹区域shoot传递(子弹属性);
    }, target);
};


_root.装备生命周期函数.光剑天秤周期 = function(ref:Object, param:Object):Void
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var currentFrame:Number = _root.帧计时器.当前帧数;

    // 1. 过渡动画推进
    if (ref.isTransitioning) {
        ref.当前动画帧++;

        // 检查是否到达过渡结束帧
        if (ref.当前动画帧 >= ref.transitionEnd) {
            // 过渡完成
            if (ref.transitionJumpTo > 0) {
                // 有跳转帧（守御→默认的情况）
                ref.当前动画帧 = ref.transitionJumpTo;
            } else {
                ref.当前动画帧 = ref.transitionEnd;
            }
            ref.isTransitioning = false;

            // 完成形态切换的逻辑部分
            _root.装备生命周期函数.光剑天秤完成形态切换(ref, ref.transitionTarget);
            ref.transitionTarget = null;
        }
    } else {
        // 2. 武器形态切换检测（武器变形键，仅玩家控制单位响应）
        // 只有在非过渡状态下才能触发切换
        if (_root.按键输入检测(target, _root.武器变形键) && target.攻击模式 == "兵器") {
            if (currentFrame - ref.lastTransformFrame >= ref.transformCooldownFrames) {
                ref.lastTransformFrame = currentFrame;
                _root.装备生命周期函数.光剑天秤切换武器形态(ref);
            }
        }

        // 3. 攻击时天秤转换（攻势/守御形态下攻击触发buff互换）
        if (ref.当前形态 == "攻势形态" || ref.当前形态 == "守御形态") {
            _root.装备生命周期函数.光剑天秤攻击转换(ref);
        }
    }

    // 4. 主动技CD状态更新
    if (ref.isSkillInCd && currentFrame >= ref.skillCdEndFrame) {
        ref.isSkillInCd = false;
    }

    // 5. 刀光效果
    _root.装备生命周期函数.光剑天秤刀光(ref);

    // 5. 同步动画帧到武器元件
    var saber:MovieClip = target.刀_引用;
    if (saber && saber.动画) {
        saber.动画.gotoAndStop(ref.当前动画帧);
    }
};


/**
 * 形态切换系统：默认 → 攻势 → 守御 → 默认
 * 启动过渡动画，动画完成后切换形态
 */
_root.装备生命周期函数.光剑天秤切换武器形态 = function(ref:Object):Void
{
    // 正在过渡中则忽略
    if (ref.isTransitioning) return;

    var currentForm:String = ref.当前形态;
    var newForm:String;

    switch (currentForm) {
        case "默认形态":
            newForm = "攻势形态";
            break;
        case "攻势形态":
            newForm = "守御形态";
            break;
        default:
            newForm = "默认形态";
    }

    // 获取过渡配置
    var transKey:String = currentForm + "_" + newForm;
    var trans:Object = ref.transitions[transKey];

    if (trans) {
        // 启动过渡动画
        ref.isTransitioning = true;
        ref.transitionTarget = newForm;
        ref.当前动画帧 = trans.start;
        ref.transitionEnd = trans.end;
        ref.transitionJumpTo = trans.jumpTo || 0;
    } else {
        // 无过渡配置，直接切换
        _root.装备生命周期函数.光剑天秤切换到形态(ref, newForm);
    }
};


/**
 * 完成形态切换（过渡动画结束后调用）
 */
_root.装备生命周期函数.光剑天秤完成形态切换 = function(ref:Object, formName:String):Void
{
    _root.装备生命周期函数.光剑天秤切换到形态(ref, formName);
};


/**
 * 切换到指定形态
 * @param ref 反射对象
 * @param formName 目标形态名
 * @param isRestore 是否为恢复形态（场景切换后恢复，不计数/不提示/不保存）
 */
_root.装备生命周期函数.光剑天秤切换到形态 = function(ref:Object, formName:String, isRestore:Boolean):Void
{
    var target:MovieClip = ref.自机;

    // 更新形态基础状态
    ref.当前形态 = formName;
    target.刀属性.power = ref.默认形态基础伤害;
    ref.当前动画帧 = ref.animFrames[formName] || 2;

    // ─────────────────────────────────────────────────────────────────────
    // 场景切换恢复形态：仅恢复视觉状态，不触发玩法逻辑
    // ─────────────────────────────────────────────────────────────────────
    if (isRestore) {
        return;
    }

    // ─────────────────────────────────────────────────────────────────────
    // 【玩法核心】正常切换形态：累计切换次数，强化主动技"天秤之力"伤害
    // ─────────────────────────────────────────────────────────────────────
    ref.天秤切换次数++;
    ref.天秤转换次数 = 0;

    _root.发布消息("光剑天秤类型切换为[" + formName + "]");

    // 保存武器类型到全局参数（主角专用，用于场景切换后恢复）
    if (ref.globalData) {
        ref.globalData.保存形态 = formName;
    }
};


/**
 * 攻击时天秤转换（buff互换）
 * 使用 BuffManager 管理属性加成，通过同 ID 替换驱动重算
 */
_root.装备生命周期函数.光剑天秤攻击转换 = function(ref:Object):Void
{
    var target:MovieClip = ref.自机;

    // 兵器攻击检测
    if (!_root.兵器攻击检测(target)) {
        return;
    }

    // 攻击状态检测
    var smallState:String = target.getSmallState();
    var validStates:Object = {
        兵器一段中: true,
        兵器二段中: true,
        兵器三段中: true,
        兵器四段中: true,
        兵器五段中: true
    };

    if (!validStates[smallState]) {
        return;
    }

    // 冷却检测（帧计时器）
    var currentFrame:Number = _root.帧计时器.当前帧数;
    if (currentFrame - ref.lastAttackConvertFrame < ref.attackCooldownFrames) {
        return;
    }
    ref.lastAttackConvertFrame = currentFrame;

    // 允许攻击时转向
    target.man.攻击时可改变移动方向(1);

    if (ref.当前形态 == "攻势形态") {
        // 攻势形态：需要200防御力才能转换
        if (target.防御力 >= 200) {
            ref.天秤转换次数++;
            // 业务层累加（带上下限 clamp，与原 buff.调整 行为一致）
            ref.天秤伤害累计 = Math.max(ref.天秤伤害下限, Math.min(ref.天秤伤害上限, ref.天秤伤害累计 + 100));
            ref.天秤防御累计 = Math.max(ref.天秤防御下限, Math.min(ref.天秤防御上限, ref.天秤防御累计 - 200));
            // 同 ID 替换驱动 BuffManager 重算
            _root.装备生命周期函数.光剑天秤更新Buff(ref);
            _root.发布消息("光剑天秤类型为[" + ref.当前形态 + "]，威力" + Math.floor(target.伤害加成) + "，防御" + Math.floor(target.防御力));
        } else {
            _root.发布消息("你当前的防护能力不足以调整攻势的天秤……");
        }
    } else if (ref.当前形态 == "守御形态") {
        // 守御形态：需要100伤害加成才能转换
        if (target.伤害加成 >= 100) {
            ref.天秤转换次数++;
            // 业务层累加（带上下限 clamp，与原 buff.调整 行为一致）
            ref.天秤伤害累计 = Math.max(ref.天秤伤害下限, Math.min(ref.天秤伤害上限, ref.天秤伤害累计 - 100));
            ref.天秤防御累计 = Math.max(ref.天秤防御下限, Math.min(ref.天秤防御上限, ref.天秤防御累计 + 200));
            // 同 ID 替换驱动 BuffManager 重算
            _root.装备生命周期函数.光剑天秤更新Buff(ref);
            _root.发布消息("光剑天秤类型为[" + ref.当前形态 + "]，威力" + Math.floor(target.伤害加成) + "，防御" + Math.floor(target.防御力));
        } else {
            _root.发布消息("你当前的杀伤能力不足以调整守御的天秤……");
        }
    }
};


/**
 * 更新天秤转换 Buff（同 ID 替换驱动重算）
 * 当累计值都为0时移除 buff，否则用新值替换
 */
_root.装备生命周期函数.光剑天秤更新Buff = function(ref:Object):Void
{
    var target:MovieClip = ref.自机;
    var buffId:String = "天秤转换_" + ref.标签名;

    // 如果累计值都为0，移除 buff
    if (ref.天秤伤害累计 == 0 && ref.天秤防御累计 == 0) {
        if (target.buffManager) {
            target.buffManager.removeBuff(buffId);
        }
        return;
    }

    // 创建新的 buff 实例（同 ID 会自动替换旧实例）
    var 伤害buff:PodBuff = new PodBuff("伤害加成", BuffCalculationType.ADD, ref.天秤伤害累计);
    var 防御buff:PodBuff = new PodBuff("防御力", BuffCalculationType.ADD, ref.天秤防御累计);
    var metaBuff:MetaBuff = new MetaBuff([伤害buff, 防御buff], [], 0);
    target.buffManager.addBuff(metaBuff, buffId);
    target.buffManager.update(0); // 立即生效
};


/**
 * 刀光效果
 */
_root.装备生命周期函数.光剑天秤刀光 = function(ref:Object):Void
{
    var target:MovieClip = ref.自机;

    switch (ref.当前形态) {
        case "攻势形态":
            ref.basicStyle = "烈焰残焰";
            _root.装备生命周期函数.通用刀光周期(ref, null);
            break;
        case "守御形态":
            ref.basicStyle = "金色余辉";
            _root.装备生命周期函数.通用刀光周期(ref, null);
            break;
        default:
            // 默认形态：仅在主动技能CD中显示刀光
            if (ref.isSkillInCd) {
                ref.basicStyle = "薄暮幽蓝";
                _root.装备生命周期函数.通用刀光周期(ref, null);
            }
    }
};
