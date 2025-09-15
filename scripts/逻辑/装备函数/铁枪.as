// =======================================================
// 铁枪 · 装备生命周期函数 (FSM 改进版，优化细节)
// =======================================================

_root.装备生命周期函数.铁枪初始化 = function(ref, param)
{
    var 自机 = ref.自机;

    // 1. 创建状态机
    ref.fsm = new FSM_StateMachine(null, null, null);

    // 2. 定义配置常量 - 集中管理帧区间与变形参数
    var CONFIG = {FRAMES: {
                BFG: {start: param.bfgStart || 1, end: param.bfgEnd || 15},
                TRANSFORM: {start: param.transStart || 16, end: param.transEnd || 25},
                UNMAYKR: {start: param.unmStart || 26, end: param.unmEnd || 41}
            },
            TRANSFORM: {
                interval: param.transformInterval || 1000,
                label: param.transformLabel || "铁枪变形检测"
            }};

    // 3. 定义共享数据
    ref.fsm.data = {target: 自机,
            config: CONFIG,
            unmaykr化: false,
            isTransforming: false,
            transformTargetShape: false,
            isWeaponActive: false,
            currentFrame: 1,
            cachedTargetFrame: null,
            lastStateHash: null,
            isPlayer: ref.是否为主角,
            labelObject: null};
    var data = ref.fsm.data;

    // —— 主角全局形态同步
    if (data.isPlayer)
    {
        var key = ref.标签名 + ref.初始化函数;
        var gl = _root.装备生命周期函数.全局参数[key] || {};
        data.unmaykr化 = gl.unmaykr化 || false;
        data.labelObject = gl;
    }
    // —— 初始帧
    data.currentFrame = data.unmaykr化 ? CONFIG.FRAMES.UNMAYKR.start : CONFIG.FRAMES.BFG.start;

    // 4. 工具方法
    var Utils = {validateFrame: function(frame, cfg)
        {
            var minF = cfg.FRAMES.BFG.start;
            var maxF = cfg.FRAMES.UNMAYKR.end;
            return Math.max(minF, Math.min(maxF, frame));
        },
            getFrameRegion: function(frame, cfg)
            {
                var f = cfg.FRAMES;
                if (frame >= f.BFG.start && frame <= f.BFG.end)
                    return "BFG";
                if (frame >= f.TRANSFORM.start && frame <= f.TRANSFORM.end)
                    return "TRANSFORM";
                if (frame >= f.UNMAYKR.start && frame <= f.UNMAYKR.end)
                    return "UNMAYKR";
                return "INVALID";
            },
            getStateHash: function(d)
            {
                return d.isWeaponActive + "|" + d.unmaykr化 + "|" + d.isTransforming;
            }
        };

    // 5. 动画策略
    var AnimationStrategies = {handleTransformation: function(d)
        {
            var endF = d.config.FRAMES.TRANSFORM.end;
            if (d.currentFrame < endF)
            {
                d.currentFrame++;
            }
            else if (d.currentFrame > endF)
            {
                d.currentFrame--;
            }
            else
            {
                // 完成变形
                this.completeTransformation(d);
            }
        },
            completeTransformation: function(d)
            {
                d.isTransforming = false;
                d.unmaykr化 = d.transformTargetShape;
                if (d.isPlayer)
                {
                    d.labelObject.unmaykr化 = d.unmaykr化;
                }
                var nf = d.unmaykr化 ? d.config.FRAMES.UNMAYKR : d.config.FRAMES.BFG;
                d.currentFrame = nf.start;
                d.cachedTargetFrame = null;
                d.lastStateHash = null;
            },
            calculateTargetFrame: function(d)
            {
                var hash = Utils.getStateHash(d);
                if (d.lastStateHash === hash && d.cachedTargetFrame !== null)
                {
                    return d.cachedTargetFrame;
                }
                var cf = d.unmaykr化 ? d.config.FRAMES.UNMAYKR : d.config.FRAMES.BFG;
                var tf = d.isWeaponActive ? cf.end : cf.start;
                d.cachedTargetFrame = tf;
                d.lastStateHash = hash;
                return tf;
            },
            handleNormalAnimation: function(d)
            {
                var tf = this.calculateTargetFrame(d);
                if (d.currentFrame === tf)
                    return;
                d.currentFrame += (d.currentFrame < tf) ? 1 : -1;
                d.currentFrame = Utils.validateFrame(d.currentFrame, d.config);
            }
        };

    // 6. 统一动画推进函数
    function animateFrame()
    {
        var d = this.data;

        if (d.isTransforming)
        {
            // 异常恢复
            if (Utils.getFrameRegion(d.currentFrame, d.config) === "INVALID")
            {
                d.currentFrame = d.config.FRAMES.TRANSFORM.start;
            }
            AnimationStrategies.handleTransformation(d);
        }
        else
        {
            AnimationStrategies.handleNormalAnimation(d);
        }
    }

    // 7. 注册 FSM 状态
    var deployedState = new FSM_Status(animateFrame, null, null);
    var holsteredState = new FSM_Status(animateFrame, null, null);
    ref.fsm.AddStatus("DEPLOYED", deployedState);
    ref.fsm.AddStatus("HOLSTERED", holsteredState);

    // 8. 状态转换规则
    ref.fsm.transitions.push("HOLSTERED", "DEPLOYED", function():Boolean
        {
            return this.data.isWeaponActive === true;
        });
    ref.fsm.transitions.push("DEPLOYED", "HOLSTERED", function():Boolean
        {
            return this.data.isWeaponActive === false;
        });

    // 9. 初始状态
    var init = (自机.攻击模式 === "长枪") ? "DEPLOYED" : "HOLSTERED";
    ref.fsm.setActiveState(ref.fsm.statusDict[init]);
    ref.fsm.setLastState(null);

    ref.energyLevel = 1;

    // 订阅长枪射击事件
    ref.自机.dispatcher.subscribe("长枪射击", function() {
        ref.energyLevel = 10;
        var fsm = ref.fsm;
        var data = fsm.data;
        var 自机 = data.target;
        var 长枪 = 自机.man.枪.枪.装扮;
        长枪.枪口位置 = 长枪["枪口位置" + (data.unmaykr化 ? "0" : "1")];
    });

    ref.gunParts = ["欧米茄", "枪身", "轮盘", "枪托", "弹舱", "活塞杆", "枪管"];

};

/*--------------------------------------------------------
 * 周期函数
 *------------------------------------------------------*/
_root.装备生命周期函数.铁枪周期 = function(ref, param)
{
    _root.装备生命周期函数.移除异常周期函数(ref);

    var fsm = ref.fsm;
    var data = fsm.data;
    var 自机 = data.target;
    var 长枪 = 自机.长枪_引用;

    // 同步激活状态
    var prev = data.isWeaponActive;
    data.isWeaponActive = (自机.攻击模式 === "长枪");


    if (prev !== data.isWeaponActive)
    {
        data.cachedTargetFrame = null;
        data.lastStateHash = null;
    }

    // 触发变形
    if (data.isWeaponActive && !data.isTransforming)
    {
        if (_root.按键输入检测(自机, _root.武器变形键))
        {
            _root.更新并执行时间间隔动作(ref, data.config.TRANSFORM.label, function(d)
                {
                    d.isTransforming = true;
                    d.transformTargetShape = !d.unmaykr化;
                    d.currentFrame = d.config.FRAMES.TRANSFORM.start;
                    d.cachedTargetFrame = null;
                    d.lastStateHash = null;
                }, data.config.TRANSFORM.interval, false, data);
        }
    }

    // 执行动画推进
    fsm.onAction();

    // 更新画面

    长枪.动画.gotoAndStop(data.currentFrame);

    ref.energyLevel = Math.max(ref.energyLevel - 1, (data.isWeaponActive ? 3 : 1));
    var energyLevel = ref.energyLevel;
    var gun = ref.自机.长枪_引用.动画;
    var gunParts = ref.gunParts;

    for (var i:Number = 0; i < gunParts.length; ++i)
    {
        gun[gunParts[i]].gotoAndStop(energyLevel);
    }

    gun["轮盘"]._rotation += energyLevel;
};
