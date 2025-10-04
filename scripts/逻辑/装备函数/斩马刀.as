// ============================================================
// 斩马刀：初始化
// ============================================================
_root.装备生命周期函数.斩马刀初始化 = function(ref:Object, param:Object)
{
    // ---- 参数与默认值（避免使用 ||） ----
    param = (param == undefined) ? {} : param;

    var FPS:Number = 30; // 项目固定 30fps
    var intervalSec:Number = (param.interval == undefined) ? 0.5 : param.interval; // 释放间隔（秒）
    var mpRatio:Number = (param.mpRatio != undefined) ? param.mpRatio
                   : (param.ratio   != undefined) ? param.ratio
                   : (param.ratiol  != undefined) ? param.ratiol
                   : 3; // 百分比（3 表示 3%）
    var bulletName:String = (param.bulletName == undefined) ? "碎石飞扬" : param.bulletName;
    var powerMul:Number = (param.power == undefined) ? 12 : param.power; // 蓝量伤害倍数
    var procOdds:Number = (param.procOdds == undefined) ? 5 : param.procOdds; // 随机触发概率（%）

    // 可调灯效/时长（秒）
    var activationSec:Number = (param.activationSeconds == undefined) ? 8 : param.activationSeconds;
    var fadeInSec:Number  = (param.fadeInSeconds  == undefined) ? 1 : param.fadeInSeconds;
    var fadeOutSec:Number = (param.fadeOutSeconds == undefined) ? 1 : param.fadeOutSeconds;

    // ---- 写入 ref，周期内零分配使用 ----
    ref._fps = FPS;
    ref.intervalSec = intervalSec;
    ref._frameInterval = Math.max(1, Math.floor(intervalSec * FPS));

    ref.mpRatio = mpRatio;           // 百分比
    ref.bulletName = bulletName;
    ref.power = powerMul;
    ref.procOdds = procOdds;

    ref.activation = false;
    ref.activationStartFrame = 0;

    ref.totalFrames   = Math.max(1, Math.floor(activationSec * FPS));
    ref.fadeInFrames  = Math.max(0, Math.floor(fadeInSec  * FPS));
    ref.fadeOutFrames = Math.max(0, Math.floor(fadeOutSec * FPS));

    // 使首帧就可触发（避免 isNaN），并保留帧逻辑
    ref.lastFrame = -999999;

    // ---- 预构造消弹属性（只改会变的字段） ----
    var selfMc:MovieClip = ref.自机;
    ref.blockProp = {
        shooter: (selfMc != undefined && selfMc._name != undefined) ? selfMc._name : "自机",
        shootZ: NaN,
        消弹敌我属性: (selfMc != undefined && selfMc.是否为敌人 != undefined) ? selfMc.是否为敌人 : false,
        消弹方向: null,
        Z轴攻击范围: 10,
        区域定位area: null,
        反弹: true
    };

    // ---- 订阅武器技事件（只注册一次）----
    var target:MovieClip = selfMc;
    if (target != undefined && target.dispatcher != undefined && target.dispatcher.subscribe != undefined)
    {
        // 注意：mode == "兵器" 才激活
        target.dispatcher.subscribe("WeaponSkill", function(mode:String) {
            // _root.发布消息("斩马刀激活", mode);
            if (mode != "兵器") return;
            ref.activation = true;
            ref.activationStartFrame = _root.帧计时器.当前帧数;
        }, target);
    }
};

// ============================================================
// 斩马刀：周期
// ============================================================
_root.装备生命周期函数.斩马刀周期 = function(ref:Object, param:Object)
{
    _root.装备生命周期函数.移除异常周期函数(ref);
    
    var target:MovieClip = ref.自机;
    if (target == undefined) return;

    var saber:MovieClip = target.刀_引用;
    if (saber == undefined) return;

    var glow:MovieClip = saber.发光纹路; // 可能不存在
    var now:Number = _root.帧计时器.当前帧数;
    var total:Number   = ref.totalFrames;
    var fadeIn:Number  = ref.fadeInFrames;
    var fadeOut:Number = ref.fadeOutFrames;

    // --- 激活时长到期检测 ---
    if (ref.activation)
    {
        var elapsed:Number = now - ref.activationStartFrame;
        if (elapsed >= total)
        {
            ref.activation = false;
            if (glow != undefined) { glow._visible = false; glow._alpha = 0; }
            // _root.发布消息("斩马刀激活结束");
        }
    }

    // --- 激活期：处理刀身纹路的淡入/淡出/常亮 ---
    if (ref.activation)
    {
        if (glow != undefined)
        {
            if (!glow._visible) glow._visible = true;

            var e:Number = now - ref.activationStartFrame;
            var alphaVal:Number;

            if (e <= fadeIn && fadeIn > 0)
            {
                // 淡入
                alphaVal = (e / fadeIn) * 100;
            }
            else if (e >= total - fadeOut && fadeOut > 0)
            {
                // 淡出
                var fo:Number = (e - (total - fadeOut)) / fadeOut;
                alphaVal = (1 - fo) * 100;
            }
            else
            {
                // 常亮
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

    // --- 触发间隔（帧）判定 ---
    var canFire:Boolean = false;
    if (now - ref.lastFrame >= ref._frameInterval)
    {
        ref.lastFrame = now;
        canFire = true;
    }

    // --- 仅在“兵器攻击检测”通过时执行后续（含消弹） ---
    if (!_root.兵器攻击检测(target)) return;

    // --- 帧内持续消弹：区域以刀对象为定位，Z 取自目标 ---
    ref.blockProp.shootZ = target.Z轴坐标;
    ref.blockProp.区域定位area = saber;
    _root.消除子弹(ref.blockProp);

    // --- 周期触发：发射特殊子弹（需蓝量达标） ---
    if (canFire)
    {
        var st:String = target.getSmallState();
        var force:Boolean = (st == "兵器一段中" || st == "兵器五段中");
        var ok:Boolean = force ? true : _root.成功率(ref.procOdds);

        if (ok)
        {
            var attackPoint:MovieClip = saber.刀口位置3;
            if (attackPoint == undefined) return;

            target.man.攻击时可改变移动方向(1);

            // 按最大蓝量百分比消耗
            var mpCost:Number = Math.floor(target.mp满血值 * ref.mpRatio * 0.01);

            if (target.mp >= mpCost)
            {
                var 子弹属性:Object = _root.子弹属性初始化(attackPoint, ref.bulletName, target);
                // —— 子弹参数（按原意保持不变，可按需再调）——
                子弹属性.子弹散射度 = 0;
                子弹属性.子弹威力 = mpCost * ref.power;
                子弹属性.子弹速度 = 0;
                子弹属性.Z轴攻击范围 = 50;
                子弹属性.击倒率 = 1;

                _root.子弹区域shoot传递(子弹属性);

                target.mp -= mpCost;
            }
            else if (target == _root.gameworld[_root.控制目标])
            {
                _root.发布消息("气力不足，难以发挥装备的真正力量……");
            }
        }
    }
};
