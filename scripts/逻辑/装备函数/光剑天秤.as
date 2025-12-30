/**
 * 光剑天秤 - 装备生命周期函数
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 形态系统：默认形态 → 攻势形态 → 守御形态 → 默认形态（循环）
 * ═══════════════════════════════════════════════════════════════════════════
 * - 默认形态：动画帧2，无特殊效果
 * - 攻势形态：动画帧15，攻击时 +100伤害加成/-200防御力
 * - 守御形态：动画帧30，攻击时 -100伤害加成/+200防御力
 *
 * ═══════════════════════════════════════════════════════════════════════════
 * 核心玩法机制：天秤切换次数 → 主动技"天秤之力"伤害倍率
 * ═══════════════════════════════════════════════════════════════════════════
 * - 每次切换形态时 天秤切换次数++ （这是有意设计的积累机制）
 * - 主动技"天秤之力"伤害 = 耗蓝量 × 伤害系数 × 天秤切换次数
 * - 释放主动技后 天秤切换次数 重置为1
 * - 场景切换恢复形态时不增加计数（isRestore=true）
 *
 * 主动技能已迁移至: 单位函数_雾人_aka_fs_主动战技.as -> _root.主动战技函数.兵器.天秤之力
 */

_root.装备生命周期函数.光剑天秤初始化 = function(ref:Object, param:Object):Void
{
    var target:MovieClip = ref.自机;

    // 配置参数
    ref.transformInterval = 1000; // 形态切换冷却时间(ms)
    ref.attackCooldown = 250;     // 攻击时天秤转换冷却(ms)

    // 动画帧配置
    ref.animFrames = {
        默认形态: 2,
        攻势形态: 15,
        守御形态: 30
    };

    // 状态数据 - 直接存储在ref上
    ref.天秤切换次数 = 1;  // 【玩法核心】形态切换累计次数，影响主动技"天秤之力"伤害倍率
    ref.天秤转换次数 = 0;  // 当前形态内的buff转换次数（每次切换形态重置）
    ref.当前形态 = "默认形态";
    ref.当前动画帧 = 2;

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
};


_root.装备生命周期函数.光剑天秤周期 = function(ref:Object, param:Object):Void
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;

    // 1. 武器形态切换检测（武器变形键，仅玩家控制单位响应）
    if (_root.按键输入检测(target, _root.武器变形键) && target.攻击模式 == "兵器") {
        _root.更新并执行时间间隔动作(ref, "形态切换",
            _root.装备生命周期函数.光剑天秤切换武器形态,
            ref.transformInterval, false, ref);
    }

    // 2. 攻击时天秤转换（攻势/守御形态下攻击触发buff互换）
    if (ref.当前形态 == "攻势形态" || ref.当前形态 == "守御形态") {
        _root.装备生命周期函数.光剑天秤攻击转换(ref);
    }

    // 3. 刀光效果
    _root.装备生命周期函数.光剑天秤刀光(ref);

    // 4. 同步动画帧到武器元件
    var saber:MovieClip = target.刀_引用;
    if (saber && saber.动画) {
        saber.动画.gotoAndStop(ref.当前动画帧);
    }
};


/**
 * 形态切换系统：默认 → 攻势 → 守御 → 默认
 */
_root.装备生命周期函数.光剑天秤切换武器形态 = function(ref:Object):Void
{
    var newForm:String;

    switch (ref.当前形态) {
        case "默认形态":
            newForm = "攻势形态";
            break;
        case "攻势形态":
            newForm = "守御形态";
            break;
        default:
            newForm = "默认形态";
    }

    _root.装备生命周期函数.光剑天秤切换到形态(ref, newForm);
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

    // 冷却检测（使用帧计时器）
    if (!_root.更新时间间隔(ref, "攻击转换", ref.attackCooldown)) {
        return;
    }

    // 允许攻击时转向
    target.man.攻击时可改变移动方向(1);

    if (ref.当前形态 == "攻势形态") {
        // 攻势形态：需要200防御力才能转换
        if (target.防御力 >= 200) {
            ref.天秤转换次数++;
            target.buff.调整("伤害加成", "加算", 100, 20000, -20000);
            target.buff.调整("防御力", "加算", -200, 60000, -60000);
            _root.发布消息("光剑天秤类型为[" + ref.当前形态 + "]，威力" + Math.floor(target.伤害加成) + "，防御" + Math.floor(target.防御力));
        } else {
            _root.发布消息("你当前的防护能力不足以调整攻势的天秤……");
        }
    } else if (ref.当前形态 == "守御形态") {
        // 守御形态：需要100伤害加成才能转换
        if (target.伤害加成 >= 100) {
            ref.天秤转换次数++;
            target.buff.调整("伤害加成", "加算", -100, 20000, -20000);
            target.buff.调整("防御力", "加算", 200, 60000, -60000);
            _root.发布消息("光剑天秤类型为[" + ref.当前形态 + "]，威力" + Math.floor(target.伤害加成) + "，防御" + Math.floor(target.防御力));
        } else {
            _root.发布消息("你当前的杀伤能力不足以调整守御的天秤……");
        }
    }
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
            if (target.主动战技cd中) {
                ref.basicStyle = "薄暮幽蓝";
                _root.装备生命周期函数.通用刀光周期(ref, null);
            }
    }
};
