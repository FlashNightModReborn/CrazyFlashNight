// ============================================================
// 烈焰斩马刀：初始化
// ============================================================

_root.装备生命周期函数.烈焰斩马刀初始化 = function(ref:Object, param:Object)
{
    param = (param == undefined) ? {} : param;

    var FPS:Number = 30; // 项目固定 30fps
    var intervalSec:Number = (param.interval == undefined) ? 1.2 : param.interval; // 冷却/触发间隔（秒）——保留原 FLA：1.2s
    var mpRatio:Number = (param.mpRatio != undefined) ? param.mpRatio : 2; // 百分比（2 表示 2%）——保留原 FLA：2
    var powerMul:Number = (param.power == undefined) ? 12 : param.power;  // 蓝量伤害倍数——原 FLA：12

    // 子弹名映射（保持原有三种）
    var b1:String = (param.stage1Name == undefined) ? "熔炎裂渊" : param.stage1Name; // 兵器一段中 / 兵器冲击
    var b4:String = (param.stage4Name == undefined) ? "烈炎斜升" : param.stage4Name; // 兵器四段中 / 兵器冲击
    var b5:String = (param.stage5Name == undefined) ? "终极打击" : param.stage5Name; // 兵器五段中 / 兵器冲击

    // 视觉：沿用斩马刀的发光纹路淡入/淡出/常亮
    var selfMc:MovieClip = ref.自机;
    // 读取强化度（缺省=1，范围 1~13）
    var upgradeLevel:Number = (selfMc != undefined && selfMc.刀 != undefined && selfMc.刀.value != undefined && !isNaN(selfMc.刀.value.level))
        ? Number(selfMc.刀.value.level) : 1;
    if (upgradeLevel < 1) upgradeLevel = 1;
    else if (upgradeLevel > 13) upgradeLevel = 13;

    // 线性插值：1级→4s，13级→8s（每级 + (8-4)/(13-1) = 1/3 s）
    var minLv:Number = 1, maxLv:Number = 13;
    var minSec:Number = 4, maxSec:Number = 8;
    var t:Number = (upgradeLevel - minLv) / (maxLv - minLv);
    if (t < 0) t = 0; else if (t > 1) t = 1;
    var defaultActivationSec:Number = minSec + t * (maxSec - minSec);
    
    // 若传入 activationSeconds，则优先使用；否则用插值结果
    var activationSec:Number = (param.activationSeconds == undefined) ? defaultActivationSec : param.activationSeconds;
    // _root.发布消息(activationSec)

    var fadeInSec:Number  = (param.fadeInSeconds  == undefined) ? 1 : param.fadeInSeconds;
    var fadeOutSec:Number = (param.fadeOutSeconds == undefined) ? 1 : param.fadeOutSeconds;

    // 可选：是否必须“武器技事件”激活窗口（与斩马刀一致，默认 true）
    var requireActivation:Boolean = (param.requireActivation == undefined) ? true : param.requireActivation;

    // 随机偏移（原 FLA 对 4/5 段有随机 10 像素左右抖动）
    var offsetRange:Number = (param.offsetRange == undefined) ? 10 : param.offsetRange;

    // ---- 写入 ref，周期内零分配使用 ----
    ref._fps = FPS;
    ref.intervalSec = intervalSec;
    ref._frameInterval = Math.max(1, Math.floor(intervalSec * FPS));

    ref.mpRatio = mpRatio;         // 扣蓝百分比（按最大蓝量）
    ref.power   = powerMul;        // 伤害倍数
    ref.offsetRange = offsetRange; // 偏移范围像素
    ref.requireActivation = requireActivation;

    // 三段子弹名
    ref._b1 = b1;
    ref._b4 = b4;
    ref._b5 = b5;

    // 激活窗口与淡入/淡出
    ref.activation = requireActivation ? false : true; // 若不需要激活，则常开
    ref.activationStartFrame = 0;
    ref.totalFrames   = Math.max(1, Math.floor(activationSec * FPS));
    ref.fadeInFrames  = Math.max(0, Math.floor(fadeInSec  * FPS));
    ref.fadeOutFrames = Math.max(0, Math.floor(fadeOutSec * FPS));

    // 间隔（帧）判定
    ref.lastFrame = -999999;

    // ---- 消弹/反弹配置（与斩马刀一致）----
    ref.blockProp = {
        shooter: (selfMc != undefined && selfMc._name != undefined) ? selfMc._name : "自机",
        shootZ: NaN,
        消弹敌我属性: (selfMc != undefined && selfMc.是否为敌人 != undefined) ? selfMc.是否为敌人 : false,
        消弹方向: null,
        Z轴攻击范围: 10,
        区域定位area: null,
        反弹: true
    };

    // ---- 订阅武器技事件（仅一次）----
    var target:MovieClip = selfMc;
    target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
        if (!ref.requireActivation) return; // 常开时无需激活窗口
        if (mode != "兵器") return;
        
        ref.activation = true;
        ref.activationStartFrame = _root.帧计时器.当前帧数;
    }, target);

};

// ============================================================
// 烈焰斩马刀：周期
// ============================================================
_root.装备生命周期函数.烈焰斩马刀周期 = function(ref:Object, param:Object)
{
    var target:MovieClip = ref.自机;
    var saber:MovieClip = target.刀_引用;
    var glow:MovieClip = saber.发光纹路;
    var now:Number = _root.帧计时器.当前帧数;


    // --- 激活窗口处理（与斩马刀一致）---
    if (ref.requireActivation)
    {
        if (ref.activation)
        {
            var elapsed:Number = now - ref.activationStartFrame;
            if (elapsed >= ref.totalFrames)
            {
                ref.activation = false;
                if (glow != undefined) { glow._visible = false; glow._alpha = 0; }
            }
        }

        if (ref.activation)
        {
            if (glow != undefined)
            {
                if (!glow._visible) glow._visible = true;
                var e:Number = now - ref.activationStartFrame;
                var alphaVal:Number;

                if (e <= ref.fadeInFrames && ref.fadeInFrames > 0)
                {   // 淡入
                    alphaVal = (e / ref.fadeInFrames) * 100;
                }
                else if (e >= ref.totalFrames - ref.fadeOutFrames && ref.fadeOutFrames > 0)
                {   // 淡出
                    var fo:Number = (e - (ref.totalFrames - ref.fadeOutFrames)) / ref.fadeOutFrames;
                    alphaVal = (1 - fo) * 100;
                }
                else
                {   // 常亮
                    alphaVal = 100;
                }
                glow._alpha = (alphaVal > 100) ? 100 : (alphaVal < 0) ? 0 : alphaVal;
            }
        }
        else
        {
            if (glow != undefined && glow._visible)
            {
                glow._visible = false;
                glow._alpha = 0;
            }
            return; // 未激活直接返回
        }
    }
    else
    {
        if (!glow._visible) glow._visible = true;
        glow._alpha = 100;

    }

    // --- 间隔（帧）判定：一次通过允许同帧按段落多发（与原 FLA 同语义）---
    var canCycle:Boolean = false;
    if (now - ref.lastFrame >= ref._frameInterval)
    {
        ref.lastFrame = now;
        canCycle = true;
    }

    // --- 仅在“兵器攻击检测”通过时才进行后续（含消弹）---
    if (!_root.兵器攻击检测(target)) return;

    // --- 帧内持续消弹/反弹：区域以刀对象定位，Z 取自目标 ---
    ref.blockProp.shootZ = target.Z轴坐标;
    ref.blockProp.区域定位area = saber;
    _root.消除子弹(ref.blockProp);

    // --- 周期触发（冷却通过后）：按小状态分别尝试三段发射 ---
    if (!canCycle) return;

    // 扣蓝（按最大蓝量百分比）
    var mpCost:Number = Math.floor(target.mp满血值 * ref.mpRatio * 0.01);

    // 公共子弹基础参数
    var baseSpeed:Number = 0;
    var baseZR:Number = 50;
    var baseKD:Number = 1;

    // —— 段 1：兵器一段中 / 兵器冲击 -> 熔炎裂渊（无随机偏移）——
    var st:String = target.getSmallState();
    if (st == "兵器一段中" || st == "兵器冲击")
    {
        if (target.mp >= mpCost)
        {
            var attackPoint1:MovieClip = saber.刀口位置3;
            if (attackPoint1 != undefined)
            {
                target.man.攻击时可改变移动方向(1);

                var prop1:Object = _root.子弹属性初始化(attackPoint1, ref._b1, target);
                prop1.子弹散射度 = 0;
                prop1.子弹威力   = mpCost * ref.power;
                prop1.子弹速度   = baseSpeed;
                prop1.Z轴攻击范围 = baseZR;
                prop1.击倒率     = baseKD;
                // 敌我：沿用初始化逻辑（如需强制）：
                // prop1.子弹敌我属性值 = target.是否为敌人 ? false : true;

                _root.子弹区域shoot传递(prop1);
                target.mp -= mpCost;
            }
        }
        else if (target == _root.gameworld[_root.控制目标])
        {
            _root.发布消息("气力不足，难以发挥装备的真正力量……");
        }
    }

    // —— 段 4：兵器四段中 / 兵器冲击 -> 烈炎斜升（带随机偏移）——
    if (st == "兵器四段中" || st == "兵器冲击")
    {
        if (target.mp >= mpCost)
        {
            var attackPoint4:MovieClip = saber.刀口位置3;
            if (attackPoint4 != undefined)
            {
                target.man.攻击时可改变移动方向(1);

                // 先按攻击点求世界->gameworld 坐标，再做随机偏移
                var p4:Object = {x:attackPoint4._x, y:attackPoint4._y};
                saber.localToGlobal(p4);
                _root.gameworld.globalToLocal(p4);

                var r4:Number = ref.offsetRange;
                p4.x += (Math.random() - 0.5) * 2 * r4;
                p4.y += (Math.random() - 0.5) * 2 * r4;

                var prop4:Object = _root.子弹属性初始化(attackPoint4, ref._b4, target);
                prop4.子弹散射度 = 0;
                prop4.子弹威力   = mpCost * ref.power;
                prop4.子弹速度   = baseSpeed;
                prop4.Z轴攻击范围 = baseZR;
                prop4.击倒率     = baseKD;

                // 覆盖发射坐标为偏移后的坐标（若你的 传递 方法支持）
                prop4.shootX = p4.x;
                prop4.shootY = p4.y;
                prop4.Z轴坐标 = target._y; // 原 FLA 用自机._y 作为 Z 坐标

                _root.子弹区域shoot传递(prop4);
                target.mp -= mpCost;
            }
        }
        else if (target == _root.gameworld[_root.控制目标])
        {
            _root.发布消息("气力不足，难以发挥装备的真正力量……");
        }
    }

    // —— 段 5：兵器五段中 / 兵器冲击 -> 终极打击（带随机偏移）——
    if (st == "兵器五段中" || st == "兵器冲击")
    {
        if (target.mp >= mpCost)
        {
            var attackPoint5:MovieClip = saber.刀口位置3;
            if (attackPoint5 != undefined)
            {
                target.man.攻击时可改变移动方向(1);

                var p5:Object = {x:attackPoint5._x, y:attackPoint5._y};
                saber.localToGlobal(p5);
                _root.gameworld.globalToLocal(p5);

                var r5:Number = ref.offsetRange;
                p5.x += (Math.random() - 0.5) * 2 * r5;
                p5.y += (Math.random() - 0.5) * 2 * r5;

                var prop5:Object = _root.子弹属性初始化(attackPoint5, ref._b5, target);
                prop5.子弹散射度 = 0;
                prop5.子弹威力   = mpCost * ref.power;
                prop5.子弹速度   = baseSpeed;
                prop5.Z轴攻击范围 = baseZR;
                prop5.击倒率     = baseKD;

                prop5.shootX = p5.x;
                prop5.shootY = p5.y;
                prop5.Z轴坐标 = target._y;

                _root.子弹区域shoot传递(prop5);
                target.mp -= mpCost;
            }
        }
        else if (target == _root.gameworld[_root.控制目标])
        {
            _root.发布消息("气力不足，难以发挥装备的真正力量……");
        }
    }
};
