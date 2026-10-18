import org.flashNight.arki.spatial.animation.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.unit.*;
import flash.geom.*;
_root.地图元件={};
_root.护盾函数={};
_root.地图元件.地图元件破碎动画 = function(scope:MovieClip, fragmentPrefix:String, cfg:Object):Number {

    // ======================== 参数验证 ========================

    if (!scope) {
        trace("[地图元件破碎动画] 错误：scope参数不能为空");
        return -1;
    }
    if (!fragmentPrefix) {
        trace("[地图元件破碎动画] 错误：fragmentPrefix参数不能为空");
        return -1;
    }

    // ======================== 配置处理 ========================

    var config:FragmentConfig;
    var debugEnabled:Boolean = false;

    try {
        // 检测配置类型并进行相应处理
        if (!cfg) {
            // 情况1：无配置，使用默认
            config = FragmentPresets.getDefault();

        } else if (typeof cfg == "string") {
            // 情况2：字符串预设名称
            config = FragmentPresets.getPreset(String(cfg));
            if (!config) {
                trace("[地图元件破碎动画] 警告：未知预设 '" + cfg + "'，使用默认配置");
                config = FragmentPresets.getDefault();
            }

        } else if (typeof cfg == "object") {
            // 情况3：对象配置（传统方式或混合方式）

            if (cfg.preset) {
                // 混合方式：从预设开始，然后覆盖参数
                config = FragmentPresets.getPreset(String(cfg.preset));
                if (!config) {
                    trace("[地图元件破碎动画] 警告：未知预设 '" + cfg.preset + "'，使用默认配置作为基础");
                    config = FragmentPresets.getDefault();
                }

                // 从配置对象加载覆盖参数
                var loadResult:Boolean = config.loadFromObject(cfg);
                if (cfg.enableDebug) {
                    trace("[地图元件破碎动画] 混合配置模式：基础预设 '" + cfg.preset + "' + 自定义覆盖");
                }

            } else {
                // 传统方式：纯对象配置
                config = FragmentPresets.getDefault();
                var loadResult:Boolean = config.loadFromObject(cfg);

                if (cfg.enableDebug) {
                    trace("[地图元件破碎动画] 传统配置模式：" + (loadResult ? "配置加载成功" : "配置加载失败"));
                }
            }

            debugEnabled = Boolean(cfg.enableDebug);

        } else {
            // 情况4：无效配置类型
            trace("[地图元件破碎动画] 警告：无效的配置类型，使用默认配置");
            config = FragmentPresets.getDefault();
        }

        // ======================== 配置验证和调试 ========================

        // 验证配置有效性
        if (!config.validate()) {
            trace("[地图元件破碎动画] 配置参数存在问题，已自动修正");
        }

        // 输出调试信息
        if (debugEnabled || config.enableDebug) {
            trace("[地图元件破碎动画] ===== 动画启动信息 =====");
            trace("  作用域: " + scope);
            trace("  碎片前缀: " + fragmentPrefix);
            trace("  配置类型: " + typeof cfg);
            trace("  预设使用: " + (cfg && cfg.preset ? cfg.preset : "默认"));
            config.printSummary();
            trace("=========================================");
        }

        // ======================== 启动动画 ========================

        // 调用新的动画系统
        var animationId:Number = FragmentAnimator.startAnimation(scope, fragmentPrefix, config);

        if (animationId >= 0) {
            if (debugEnabled || config.enableDebug) {
                trace("[地图元件破碎动画] 动画启动成功，ID: " + animationId);
                trace("  当前活动动画数: " + FragmentAnimator.getActiveAnimationCount());
            }
            return animationId;
        } else {
            trace("[地图元件破碎动画] 错误：动画启动失败");
            return -1;
        }

    } catch (error:Error) {
        // ======================== 错误处理 ========================

        trace("[地图元件破碎动画] 捕获到异常: " + error.message);

        // 尝试使用最基础的配置作为后备方案
        try {
            trace("[地图元件破碎动画] 尝试使用后备配置...");
            var fallbackConfig:FragmentConfig = new FragmentConfig();
            fallbackConfig.enableDebug = debugEnabled;

            var fallbackId:Number = FragmentAnimator.startAnimation(scope, fragmentPrefix, fallbackConfig);

            if (fallbackId >= 0) {
                trace("[地图元件破碎动画] 后备方案成功，动画ID: " + fallbackId);
                return fallbackId;
            }

        } catch (fallbackError:Error) {
            trace("[地图元件破碎动画] 后备方案也失败: " + fallbackError.message);
        }

        return -1;
    }
};
_root.地图元件.停止地图元件破碎动画 = function(animationId:Number):Boolean {
    return FragmentAnimator.stopAnimation(animationId);
};
_root.地图元件.地图元件破碎动画运行中 = function(animationId:Number):Boolean {
    return FragmentAnimator.isAnimationRunning(animationId) === true;
};
_root.护盾函数.添加临时护盾 = function(target:Object, capacity:Number, strength:Number,
                                      duration:Number, name:String, callbacks:Object):Number {
    if (!target || !target.shield) return -1;

    // 处理默认值
    if (capacity == undefined || isNaN(capacity) || capacity <= 0) return -1;
    if (strength == undefined || isNaN(strength)) strength = Infinity;
    if (duration == undefined) duration = -1;
    if (name == undefined || name == null) name = "临时护盾";

    // 创建护盾
    var shield:Shield = Shield.createTemporary(capacity, strength, duration, name);

    // 设置回调
    if (callbacks != null) {
        if (callbacks.onBreak != undefined) shield.onBreakCallback = callbacks.onBreak;
        if (callbacks.onHit != undefined) shield.onHitCallback = callbacks.onHit;
        if (callbacks.onExpire != undefined) {
            // 过期回调需要在容器级别处理
            var existingExpire:Function = target.shield.onExpireCallback;
            target.shield.onExpireCallback = function(s:IShield):Void {
                callbacks.onExpire(s);
                if (existingExpire != null) existingExpire(s);
            };
        }
    }

    // 添加到单位护盾容器
    target.shield.addShield(shield);

    return shield.getId();
};
_root.护盾函数.添加衰减护盾 = function(target:Object, capacity:Number, strength:Number,
                                      decayRate:Number, name:String, callbacks:Object):Number {
    if (!target || !target.shield) return -1;

    // 处理默认值
    if (capacity == undefined || isNaN(capacity) || capacity <= 0) return -1;
    if (strength == undefined || isNaN(strength)) strength = Infinity;
    if (decayRate == undefined || isNaN(decayRate)) decayRate = 1;
    if (name == undefined || name == null) name = "衰减护盾";

    // 创建护盾
    var shield:Shield = Shield.createDecaying(capacity, strength, decayRate, name);

    // 设置回调
    if (callbacks != null) {
        if (callbacks.onBreak != undefined) shield.onBreakCallback = callbacks.onBreak;
        if (callbacks.onHit != undefined) shield.onHitCallback = callbacks.onHit;
    }

    // 添加到单位护盾容器
    target.shield.addShield(shield);

    return shield.getId();
};
_root.护盾函数.移除护盾 = function(target:Object, shieldId:Number):Boolean {
    if (!target || !target.shield) return false;
    return target.shield.removeShieldById(shieldId);
};
_root.cf6MakePlayerTarget=function(world:MovieClip,name:String,height:Number):MovieClip {
    var target:MovieClip=world.createEmptyMovieClip(name,world.getNextHighestDepth());
    target.hp=target.hp满血值=100000;target.等级=50;target.防御力=1;target.damageTakenMultiplier=1;
    target.ti61CrumbleTakenMultiplier=1;target.魔法抗性={波:0};target.dispatcher={publish:function():Void {}};
    target.shield=AdaptiveShield.createDormant("player-area-fixture");target.shield.setOwner(target);
    target.Z轴坐标=target._y=200;
    var area:MovieClip=target.createEmptyMovieClip("area",1);
    area.beginFill(0xFF0000,0);area.moveTo(25,25);area.lineTo(0,25);area.lineTo(0,0);area.lineTo(25,0);area.lineTo(25,25);area.endFill();
    area.transform.matrix=new Matrix(2.11715698242188,0.0,0.0,5.48248291015625,-26.45,-126.5);
    target._xscale=target._yscale=UnitUtil.getHeightPercentage(height);
    return target;
};
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
_root.cf6ProductionDeathCheck = function(para) {
    // 主控怪物由本局玩家生命期接管，不能进入敌人掉落/尸体移除分支。
    if (_root.敌人动作.handleDeath(this) === true) return;
    if (this.hp <= 0 && !this.已加经验值) {
        if (this.斗兽标定隔离 === true) {
            return;
        }
        this.man.stop();
        if (UnitUtil.isEnemy(this)) {
            if (this.是否为敌人 === true && para.noCount !== true) {
                // _root.敌人死亡计数++;
                _root.gameworld[this.产生源].僵尸型敌人场上实际人数--;
                _root.gameworld[this.产生源].僵尸型敌人总个数--;
            }
            this.计算经验值();
        }
        this.人物文字信息._visible = false;
        this.新版人物文字信息._visible = false;
        if (para.remainMovie === true) {
            StaticDeinitializer.deInitializeUnit(this); // 不卸载元件直接注销单位
        } else {
            if (para.noCorpse !== true)
                _root.add2map(this, 2); // 检测是否需要贴尸体
            this.removeMovieClip(); // 移除单位
        }
    }
};
