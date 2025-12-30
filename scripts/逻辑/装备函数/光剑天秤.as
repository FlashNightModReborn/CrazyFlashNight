/**
 * 光剑天秤 - 装备生命周期函数
 *
 * 形态系统：默认形态 → 攻势形态 → 守御形态 → 默认形态（循环）
 * - 默认形态：动画帧2，无特殊效果
 * - 攻势形态：动画帧15，攻击时 +100伤害加成/-200防御力
 * - 守御形态：动画帧30，攻击时 -100伤害加成/+200防御力
 *
 * 主动技能：消耗5%MP释放"天秤之力"，伤害 = 耗蓝量 * 12 * 天秤切换次数
 */

_root.装备生命周期函数.光剑天秤初始化 = function(ref:Object, param:Object):Void
{
    var target:MovieClip = ref.自机;

    // 配置参数
    ref.transformInterval = 1000; // 形态切换冷却时间(ms)
    ref.attackCooldown = 250;     // 攻击时天秤转换冷却(ms)
    ref.skillCooldown = 5000;     // 主动技能冷却(ms)

    // 动画帧配置
    ref.animFrames = {
        默认形态: 2,
        攻势形态: 15,
        守御形态: 30
    };

    // 状态数据 - 直接存储在ref上
    ref.天秤切换次数 = 1;
    ref.天秤转换次数 = 0;
    ref.当前形态 = "默认形态";
    ref.当前动画帧 = 2;
    ref.形态切换时间戳 = 0;
    ref.攻击转换时间戳 = 0;

    // 初始化基础伤害数据
    if (isNaN(ref.默认形态基础伤害)) {
        ref.默认形态基础伤害 = target.刀属性.power;

        // 读取保存的武器类型（主角切换场景后恢复）
        if (ref.是否为主角 && _root.光剑天秤保存形态) {
            _root.装备生命周期函数.光剑天秤切换到形态(ref, _root.光剑天秤保存形态);
        }
    }

    target.syncRequiredEquips.刀_引用 = true; // 触发StatusChange中刀_引用的加载状态
};


_root.装备生命周期函数.光剑天秤周期 = function(ref:Object, param:Object):Void
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var target:MovieClip = ref.自机;

    // 1. 武器形态切换检测（武器变形键）
    if (Key.isDown(_root.武器变形键) && target.攻击模式 == "兵器") {
        var now:Number = getTimer();
        if (now - ref.形态切换时间戳 > ref.transformInterval) {
            ref.形态切换时间戳 = now;
            _root.装备生命周期函数.光剑天秤切换武器形态(ref);
        }
    }

    // 2. 攻击时天秤转换（攻势/守御形态下攻击触发buff互换）
    if (ref.当前形态 == "攻势形态" || ref.当前形态 == "守御形态") {
        _root.装备生命周期函数.光剑天秤攻击转换(ref);
    }

    // 3. 主动技能检测（武器技能键）
    if (Key.isDown(_root.武器技能键) && target._name == _root.控制目标) {
        if (!target.主动战技cd中 && target.攻击模式 == "兵器") {
            _root.装备生命周期函数.光剑天秤触发特效(ref);
        }
    }

    // 4. 刀光效果
    _root.装备生命周期函数.光剑天秤刀光(ref);

    // 5. 同步动画帧到武器元件
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
 */
_root.装备生命周期函数.光剑天秤切换到形态 = function(ref:Object, formName:String):Void
{
    var target:MovieClip = ref.自机;

    // 更新天秤计数器
    ref.天秤切换次数++;
    ref.天秤转换次数 = 0;

    // 更新形态
    ref.当前形态 = formName;
    target.刀属性.power = ref.默认形态基础伤害;
    ref.当前动画帧 = ref.animFrames[formName] || 2;

    _root.发布消息("光剑天秤类型切换为[" + formName + "]");

    // 保存武器类型到全局（主角）
    if (ref.是否为主角) {
        _root.光剑天秤保存形态 = formName;
    }
};


/**
 * 攻击时天秤转换（buff互换）
 */
_root.装备生命周期函数.光剑天秤攻击转换 = function(ref:Object):Void
{
    var target:MovieClip = ref.自机;

    // 冷却检测
    var now:Number = getTimer();
    if (now - ref.攻击转换时间戳 < ref.attackCooldown) {
        return;
    }

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

    ref.攻击转换时间戳 = now;

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
 * 主动技能：天秤之力
 * 消耗5%MP，伤害 = 耗蓝量 * 12 * 天秤切换次数
 */
_root.装备生命周期函数.光剑天秤触发特效 = function(ref:Object):Void
{
    var target:MovieClip = ref.自机;

    var 耗蓝比例:Number = 5;
    var 耗蓝量:Number = Math.floor(target.mp满血值 / 100 * 耗蓝比例);

    if (target.mp < 耗蓝量) {
        if (target._name == _root.控制目标) {
            _root.发布消息("气力不足，难以发挥武器的真正力量……");
        }
        return;
    }

    target.mp -= 耗蓝量;

    // 随机坐标偏移
    var offsetRange:Number = 50;
    var xOffset:Number = (Math.random() - 0.5) * 2 * offsetRange;
    var yOffset:Number = (Math.random() - 0.5) * 2 * offsetRange;

    _root.发布消息("共转换过" + ref.天秤切换次数 + "次天秤，星盘转动的力量因此得到了强化……");

    var 子弹威力:Number = 耗蓝量 * 12 * ref.天秤切换次数;

    // 重置切换次数
    ref.天秤切换次数 = 1;
    _root.发布消息("天秤转换的次数归一……");

    // 发射子弹
    _root.子弹区域shoot(
        "",                     // 声音
        1,                      // 霰弹值
        0,                      // 子弹散射度
        "",                     // 发射效果
        "天秤之力",              // 子弹种类
        子弹威力,                // 子弹威力
        0,                      // 子弹速度
        72,                     // Z轴攻击范围
        "",                     // 击中地图效果
        target._name,           // 发射者名
        target._x + xOffset,    // shootX
        target._y,              // shootY
        target._y,              // Z轴坐标
        !target.是否为敌人,      // 子弹敌我属性值
        1,                      // 击倒率
        "",                     // 击中后子弹的效果
        18                      // 击退初速度
    );

    // 设置技能CD
    target.主动战技cd中 = true;
    _root.帧计时器.添加主动战技cd(function() {
        _root.gameworld[_root.控制目标].主动战技cd中 = false;
    }, ref.skillCooldown);
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
