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
    // 过渡动画配置：{起始帧, 结束帧, 结束后跳转帧(可选), 反向播放(可选)}
    ref.transitions = {
        默认形态_攻势形态: {start: 1, end: 15},
        攻势形态_守御形态: {start: 15, end: 30},
        守御形态_默认形态: {start: 30, end: 44, jumpTo: 1},
        // 战技释放时的特殊过渡：攻势形态反向回默认
        攻势形态_默认形态: {start: 15, end: 1, reverse: true}
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
    ref.transitionReverse = false; // 是否反向播放过渡动画
    ref.pendingBuffClear = false;  // 战技重置后待清空 buff 标记

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

    // ─────────────────────────────────────────────────────────────────────
    // 预分配复用对象（减少GC压力）
    // ─────────────────────────────────────────────────────────────────────
    // 子弹属性模板：由XML bullet配置预分配，此处补充动态字段
    // XML配置路径：lifecycle -> attr_0 -> bullet -> bullet_天秤之力
    if (ref.子弹配置 && ref.子弹配置.bullet_天秤之力) {
        var 子弹模板:Object = ref.子弹配置.bullet_天秤之力;
        // 补充XML不包含的动态字段（shootX/Y/Z在每次释放时更新）
        子弹模板.发射者 = target._name;
        子弹模板.shootX = 0;
        子弹模板.shootY = 0;
        子弹模板.shootZ = 0;
        子弹模板.击中地图效果 = "";
    }
    // 护盾回调对象（通过闭包引用ref来管理特效）
    ref.护盾特效 = null; // 特效引用，在护盾启动时赋值
    ref.护盾回调 = {
        onBreak: function(s) {
            _root.发布消息("天秤之护消散……");
            // 通过闭包访问ref，移除护盾特效
            if (ref.护盾特效) {
                ref.护盾特效.removeMovieClip();
                ref.护盾特效 = null;
            }
        }
    };

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

        // ─────────────────────────────────────────────────────────────────
        // 过图恢复：注入之前 buff 累计值的一半
        // ─────────────────────────────────────────────────────────────────
        if (gl.保存伤害累计 != undefined || gl.保存防御累计 != undefined) {
            var 恢复伤害:Number = Math.floor((gl.保存伤害累计 || 0) / 2);
            var 恢复防御:Number = Math.floor((gl.保存防御累计 || 0) / 2);

            if (恢复伤害 != 0 || 恢复防御 != 0) {
                ref.天秤伤害累计 = 恢复伤害;
                ref.天秤防御累计 = 恢复防御;
                // 使用全局参数标记待恢复状态（避免 ref 对象不一致问题）
                gl.pendingBuffRestore = true;
                _root.发布消息("天秤余力延续，保留一半属性加成：威力" + 恢复伤害 + "，防御" + 恢复防御);
            }

            // 清除保存的累计值（只恢复一次）
            delete gl.保存伤害累计;
            delete gl.保存防御累计;
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

        // 启动CD计时（cd单位ms，转换为帧数）
        var cdFrames:Number = Math.ceil(cdMs / 1000 * _root.帧计时器.帧率);
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

        // 复用XML预分配的子弹属性对象，仅更新动态字段
        var 子弹属性:Object = ref.子弹配置.bullet_天秤之力;
        子弹属性.子弹威力 = 子弹威力;
        子弹属性.Z轴攻击范围 = Z轴范围;
        子弹属性.水平击退速度 = 击退速度;
        子弹属性.shootX = target._x + xOffset;
        子弹属性.shootY = target.Z轴坐标;
        子弹属性.shootZ = target.Z轴坐标;

        _root.子弹区域shoot传递(子弹属性);

        // ─────────────────────────────────────────────────────────────────
        // 【战技护盾】天秤之护 - 在 buff 重置真空期提供保护
        // - 护盾容量 = 耗蓝量 × (|伤害累计| + |防御累计|) / 100
        // - 护盾强度 = 切换次数 × 10
        // - 衰减速率 = 护盾容量 / 过渡动画帧数
        // ─────────────────────────────────────────────────────────────────
        var buff层数:Number = Math.abs(ref.天秤伤害累计) + Math.abs(ref.天秤防御累计);
        if (buff层数 > 0) {
            // 计算过渡动画帧数（5秒）
            var 过渡帧数:Number = 5 * _root.帧计时器.帧率;

            var 护盾容量:Number = 耗蓝量 * buff层数 / 10;
            var 护盾强度:Number = 100 + 切换次数 * 20;
            var 衰减速率:Number = 护盾容量 / 过渡帧数;

            // 创建护盾特效（挂载在底层背景），并存储引用到ref
            var 搭载层:MovieClip = target.底层背景;
            ref.护盾特效 = 搭载层.attachMovie("星座护盾特效", "星座护盾特效", 搭载层.getNextHighestDepth());

            // 复用预分配的回调对象
            _root.护盾函数.添加衰减护盾(
                target,
                护盾容量,
                护盾强度,
                衰减速率,
                "天秤之护",
                ref.护盾回调
            );
            _root.发布消息("天秤之护启动！容量" + Math.floor(护盾容量) + "，强度" + 护盾强度);
        }

        // ─────────────────────────────────────────────────────────────────
        // 【战技释放后】形态重置回默认，清空 buff
        // - 攻势形态：反向播放动画回默认（15→1）
        // - 守御形态：按原有路径切换到默认（30→44→1）
        // - 默认形态：无需切换，直接清空 buff
        // ─────────────────────────────────────────────────────────────────
        _root.装备生命周期函数.光剑天秤战技重置(ref);
    }, target);
};


_root.装备生命周期函数.光剑天秤周期 = function(ref:Object, param:Object):Void
{
    //_root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;
    var currentFrame:Number = _root.帧计时器.当前帧数;

    // 0. 主角专用：延迟恢复 buff + 持续同步累计值
    if (ref.是否为主角) {
        var key:String = ref.标签名 + ref.初始化函数;
        var gl:Object = _root.装备生命周期函数.全局参数[key];

        // 0.1 延迟恢复 buff（过图后首帧执行）
        if (gl && gl.pendingBuffRestore) {
            delete gl.pendingBuffRestore;
            if (!ref.globalData) {
                ref.globalData = gl;
            }
            if (target.buffManager) {
                _root.装备生命周期函数.光剑天秤更新Buff(ref);
            }
        }

        // 0.2 持续同步累计值到全局参数（确保过图时能保存）
        if (gl && (ref.天秤伤害累计 != 0 || ref.天秤防御累计 != 0)) {
            gl.保存伤害累计 = ref.天秤伤害累计;
            gl.保存防御累计 = ref.天秤防御累计;
        }
    }

    // 1. 过渡动画推进
    if (ref.isTransitioning) {
        // 根据是否反向播放决定帧变化方向
        if (ref.transitionReverse) {
            ref.当前动画帧--;
        } else {
            ref.当前动画帧++;
        }

        // 检查是否到达过渡结束帧
        var transitionDone:Boolean = ref.transitionReverse
            ? (ref.当前动画帧 <= ref.transitionEnd)
            : (ref.当前动画帧 >= ref.transitionEnd);

        if (transitionDone) {
            // 过渡完成
            if (ref.transitionJumpTo > 0) {
                // 有跳转帧（守御→默认的情况）
                ref.当前动画帧 = ref.transitionJumpTo;
            } else {
                ref.当前动画帧 = ref.transitionEnd;
            }
            ref.isTransitioning = false;
            ref.transitionReverse = false;

            // 完成形态切换的逻辑部分
            _root.装备生命周期函数.光剑天秤完成形态切换(ref, ref.transitionTarget);
            ref.transitionTarget = null;

            // 如果是战技重置触发的，执行清空 buff 回调
            if (ref.pendingBuffClear) {
                ref.pendingBuffClear = false;
                _root.装备生命周期函数.光剑天秤清空Buff(ref);
            }
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

    // 攻击状态检测（使用静态常量避免每帧创建对象）
    var smallState:String = target.getSmallState();
    if (!_root.装备生命周期函数.光剑天秤有效攻击状态[smallState]) {
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
        // 攻势形态：确保扣除200防御后不会变负
        if (target.防御力 - 200 >= 0) {
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
        // 守御形态：确保扣除100伤害加成后不会变负
        if (target.伤害加成 - 100 >= 0) {
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

    // _root.发布消息("天秤之力转换，当前累计：威力" + ref.天秤伤害累计 + "，防御" + ref.天秤防御累计);

    // 如果累计值都为0，移除 buff
    if (ref.天秤伤害累计 == 0 && ref.天秤防御累计 == 0) {
        if (target.buffManager) {
            target.buffManager.removeBuff(buffId);
        }
        return;
    }

    // 创建新的 buff 实例（同 ID 会自动替换旧实例）
    // 使用 ADD_POSITIVE 保守语义：与其他来源的加成只取最高值，防止数值膨胀
    var 伤害buff:PodBuff = new PodBuff("伤害加成", BuffCalculationType.ADD_POSITIVE, ref.天秤伤害累计);
    var 防御buff:PodBuff = new PodBuff("防御力", BuffCalculationType.ADD_POSITIVE, ref.天秤防御累计);
    var metaBuff:MetaBuff = new MetaBuff([伤害buff, 防御buff], [], 0);
    target.buffManager.addBuff(metaBuff, buffId);
};


/**
 * 战技释放后重置形态
 * - 攻势形态：反向播放动画回默认（15→1）
 * - 守御形态：按原有路径切换到默认（30→44→1）
 * - 默认形态：无需切换，直接清空 buff
 */
_root.装备生命周期函数.光剑天秤战技重置 = function(ref:Object):Void
{
    var currentForm:String = ref.当前形态;

    // ─────────────────────────────────────────────────────────────────────
    // 【重要】立即保存累计值到全局参数（用于过图恢复一半）
    // 必须在清空前保存，且要在动画开始前保存（防止过图时动画未完成）
    // ─────────────────────────────────────────────────────────────────────
    if (ref.globalData) {
        ref.globalData.保存伤害累计 = ref.天秤伤害累计;
        ref.globalData.保存防御累计 = ref.天秤防御累计;
    }

    if (currentForm == "默认形态") {
        // 已经是默认形态，直接清空 buff
        _root.装备生命周期函数.光剑天秤清空Buff(ref);
        return;
    }

    // 获取切换到默认形态的过渡配置
    var transKey:String = currentForm + "_默认形态";
    var trans:Object = ref.transitions[transKey];

    if (trans) {
        // 启动过渡动画
        ref.isTransitioning = true;
        ref.transitionTarget = "默认形态";
        ref.当前动画帧 = trans.start;
        ref.transitionEnd = trans.end;
        ref.transitionJumpTo = trans.jumpTo || 0;
        ref.transitionReverse = trans.reverse || false;
        // 标记待清空 buff（动画完成后执行）
        ref.pendingBuffClear = true;
    } else {
        // 无过渡配置，直接切换并清空
        _root.装备生命周期函数.光剑天秤切换到形态(ref, "默认形态", true);
        _root.装备生命周期函数.光剑天秤清空Buff(ref);
    }
};


/**
 * 清空天秤 Buff（重置累计值并移除 buff）
 * 注：累计值的保存已在 光剑天秤战技重置 中提前执行，此处不再重复保存
 */
_root.装备生命周期函数.光剑天秤清空Buff = function(ref:Object):Void
{
    var target:MovieClip = ref.自机;
    var buffId:String = "天秤转换_" + ref.标签名;

    // 重置累计值
    ref.天秤伤害累计 = 0;
    ref.天秤防御累计 = 0;
    ref.天秤转换次数 = 0;

    // 移除 buff
    if (target.buffManager) {
        target.buffManager.removeBuff(buffId);
    }

    _root.发布消息("天秤之力释放，属性加成归零……");
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


// ═══════════════════════════════════════════════════════════════════════════
// 静态常量（文件级，避免每帧/每次调用创建对象）
// ═══════════════════════════════════════════════════════════════════════════
_root.装备生命周期函数.光剑天秤有效攻击状态 = {
    兵器一段中: true,
    兵器二段中: true,
    兵器三段中: true,
    兵器四段中: true,
    兵器五段中: true
};
