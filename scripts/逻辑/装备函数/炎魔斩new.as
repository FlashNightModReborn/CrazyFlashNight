// =======================================================
//  炎魔斩 · 装备生命周期函数 (FSM 改进版 - 优化)
// =======================================================

_root.装备生命周期函数.炎魔斩new初始化 = function(反射对象, 参数对象) {
    var 自机 = 反射对象.自机;
    
    // 1. 创建状态机
    反射对象.fsm = new FSM_StateMachine(null, null, null);

    // 2. 配置常量
    var CONFIG = {
        FRAMES: {
            JAGGED:    { start: 参数对象.startFrame_0 || 1,   end: 参数对象.endFrame_0   || 15 },
            TRANSFORM: { start: 参数对象.startFrame_1 || 16,  end: 参数对象.endFrame_1 || 25 },
            CHAINSAW:  { start: 参数对象.startFrame_2 || 26,  end: 参数对象.endFrame_2 || 40 }
        },
        TRANSFORM: {
            interval: 参数对象.transformInterval || 1000,
            label:    参数对象.transformLabel    || "链锯化切换检测"
        },
        EFFECT: {
            interval: 参数对象.interval     || 666,
            label:    参数对象.label        || "释放特效",
            xFluc:    参数对象.effectXfluc  || 50,
            xOffset:  参数对象.effectXoffset|| 200,
            yOffset:  参数对象.effectYoffset|| -50,
            yCount:   参数对象.effectYcount || 0,
            yCoef:    参数对象.effectYcoef  || 5
        },
        PROB:      参数对象.probability   || 3,
        BULLETS: {
            JAGGED:   反射对象.子弹配置.bullet_1,
            CHAINSAW: 反射对象.子弹配置.bullet_2
        },
        SKILLS: {
            JAGGED:   参数对象.skill_0,
            CHAINSAW: 参数对象.skill_1
        },
        COEFF: {
            JAGGED:   参数对象.coefficient_0 || 10,
            CHAINSAW: 参数对象.coefficient_1 || 5
        }
    };

    // 3. 初始化共享数据
    反射对象.fsm.data = {
        target:               自机,
        config:               CONFIG,
        chainsaw化:           false,
        isTransforming:       false,
        transformTargetShape: false,
        isWeaponActive:       false,
        currentFrame:         CONFIG.FRAMES.CHAINSAW.start,
        effectOffsetCount:    CONFIG.EFFECT.yCount,
        successRate:          CONFIG.PROB,
        bulletProps:          null,
        skillInterval:        null,
        labelObject:          null
    };
    var d = 反射对象.fsm.data;

    // 4. 同步主角形态状态
    if (反射对象.是否为主角) {
        var key = 反射对象.标签名 + 反射对象.初始化函数;
        if (!_root.装备生命周期函数.全局参数[key]) {
            _root.装备生命周期函数.全局参数[key] = {};
        }
        var gl  = _root.装备生命周期函数.全局参数[key];
        d.chainsaw化   = gl.链锯化 || false;
        d.labelObject  = gl;
    }
    // 载入子弹属性与战技
    function loadShapeProps() {
        if (d.chainsaw化) {
            d.bulletProps    = CONFIG.BULLETS.CHAINSAW;
            自机.装载主动战技(CONFIG.SKILLS.CHAINSAW, "兵器");
            d.skillInterval  = CONFIG.EFFECT.interval / CONFIG.COEFF.CHAINSAW;
        } else {
            d.bulletProps    = CONFIG.BULLETS.JAGGED;
            自机.装载主动战技(CONFIG.SKILLS.JAGGED,  "兵器");
            d.skillInterval  = CONFIG.EFFECT.interval / CONFIG.COEFF.JAGGED;
        }
        if (反射对象.是否为主角) {
            _root.玩家信息界面.玩家必要信息界面.战技栏.战技栏图标刷新();
        }
    }
    loadShapeProps();

    // 5. 工具方法
    var Utils = {
        validateFrame: function(f) {
            var mi = CONFIG.FRAMES.JAGGED.start, ma = CONFIG.FRAMES.CHAINSAW.end;
            return Math.max(mi, Math.min(ma, f));
        },
        getStateHash: function() {
            return d.isWeaponActive + "|" + d.chainsaw化 + "|" + d.isTransforming;
        }
    };

    // 6. 动画策略
    var Anim = {
        // 变形阶段
        handleTransform: function() {
            var endF = CONFIG.FRAMES.TRANSFORM.end;
            if (d.currentFrame < endF) {
                d.currentFrame++;
            } else if (d.currentFrame > endF) {
                d.currentFrame--;
            } else {
                // 完成变形
                d.isTransforming       = false;
                d.chainsaw化           = d.transformTargetShape;
                if (d.labelObject) d.labelObject.链锯化 = d.chainsaw化;
                // 跳至新形态起始帧
                var nf = d.chainsaw化
                       ? CONFIG.FRAMES.CHAINSAW
                       : CONFIG.FRAMES.JAGGED;
                d.currentFrame      = nf.start;
                // 重新载入参数
                loadShapeProps();
                d.cachedTargetFrame = null;
                d.lastStateHash     = null;
            }
        },
        // 普通展开/收纳
        calculateTarget: function() {
            var hash = Utils.getStateHash();
            if (d.lastStateHash === hash && d.cachedTargetFrame != null) {
                return d.cachedTargetFrame;
            }
            var region = d.chainsaw化 ? CONFIG.FRAMES.CHAINSAW : CONFIG.FRAMES.JAGGED;
            var tf     = d.isWeaponActive ? region.end : region.start;
            d.cachedTargetFrame = tf;
            d.lastStateHash     = hash;
            return tf;
        },
        handleNormal: function() {
            var tf = this.calculateTarget();
            if (d.currentFrame === tf) return;
            d.currentFrame += (d.currentFrame < tf) ? 1 : -1;
            d.currentFrame = Utils.validateFrame(d.currentFrame);
        }
    };

    // 7. 统一动画推进
    function animateFrame() {
        if (d.isTransforming) {
            Anim.handleTransform();
        } else {
            Anim.handleNormal();
        }
    }

    // 8. 注册 FSM 状态
    var sDeploy = new FSM_Status(animateFrame, null, null);
    var sHolster= new FSM_Status(animateFrame, null, null);
    反射对象.fsm.AddStatus("DEPLOYED",  sDeploy);
    反射对象.fsm.AddStatus("HOLSTERED", sHolster);

    反射对象.fsm.transitions.push("HOLSTERED", "DEPLOYED", function() {
        return this.data.isWeaponActive === true;
    });
    反射对象.fsm.transitions.push("DEPLOYED", "HOLSTERED", function() {
        return this.data.isWeaponActive === false;
    });

    // 9. 启动状态机（构建期 ChangeState 仅移指针，start 统一触发首次 onEnter）
    反射对象.fsm.ChangeState("HOLSTERED");
    反射对象.fsm.start();

    // 10. 定义切换与特效函数
    d.toggleShape = function() {
        if (d.isTransforming) return;
        d.isTransforming       = true;
        d.transformTargetShape = !d.chainsaw化;
        d.currentFrame         = CONFIG.FRAMES.TRANSFORM.start;
        d.cachedTargetFrame    = null;
        d.lastStateHash        = null;
    };
    d.techEffect = function() {
        // 战技特效
        var x = (自机.方向==="左"? -1:1) * CONFIG.EFFECT.xOffset
              + _root.随机偏移(CONFIG.EFFECT.xFluc);
        var y = 自机._y + CONFIG.EFFECT.yOffset
              * (d.effectOffsetCount++ * 2 / CONFIG.EFFECT.yCoef);
        d.effectOffsetCount %= CONFIG.EFFECT.yCoef;
        var bp = d.bulletProps;
        bp.shootX = 自机._x + x;
        bp.shootY = y;
        bp.shootZ = y;
        _root.子弹区域shoot传递(bp);
    };
    d.normalEffect = function() {
        // 普通攻击特效
        var x = 自机._x + _root.随机偏移(CONFIG.EFFECT.xFluc);
        var y = 自机._y + CONFIG.EFFECT.yOffset
              * (d.effectOffsetCount++ * 2 / CONFIG.EFFECT.yCoef);
        d.effectOffsetCount %= CONFIG.EFFECT.yCoef;
        var bp = d.bulletProps;
        bp.shootX = x;
        bp.shootY = y;
        bp.shootZ = y;
        _root.子弹区域shoot传递(bp);
    };
};


_root.装备生命周期函数.炎魔斩new周期 = function(反射对象, 参数对象) {
    _root.装备生命周期函数.移除异常周期函数(反射对象);
    var fsm  = 反射对象.fsm;
    var d    = fsm.data;
    var 自机 = d.target;
    var 刀   = 自机.刀_引用;

    // 同步展开/收纳
    var prev = d.isWeaponActive;
    d.isWeaponActive = _root.兵器使用检测(自机);
    if (prev !== d.isWeaponActive) {
        d.cachedTargetFrame = null;
        d.lastStateHash     = null;
    }

    // 切换形态
    if (d.isWeaponActive && !d.isTransforming) {
        if (_root.按键输入检测(自机, _root.武器变形键)) {
            _root.更新并执行时间间隔动作(
                反射对象,
                d.config.TRANSFORM.label,
                function() { d.toggleShape(); },
                d.config.TRANSFORM.interval,
                false,
                d
            );
        }
    }

    // 触发特效
    if (_root.兵器攻击检测(自机)) {
        if (自机.状态 === "战技") {
            _root.更新并执行时间间隔动作(
                反射对象,
                d.config.EFFECT.label,
                function() { d.techEffect(); },
                d.skillInterval,
                false,
                d
            );
        } else if (_root.成功率(d.successRate)) {
            _root.更新并执行时间间隔动作(
                反射对象,
                d.config.EFFECT.label,
                function() { d.normalEffect(); },
                d.config.EFFECT.interval * 2,
                false,
                d
            );
        }
    }

    // 执行动画推进
    fsm.onAction();

    // 更新画面
    刀.动画.gotoAndStop(d.currentFrame);
};

