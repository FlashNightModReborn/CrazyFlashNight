import org.flashNight.arki.spatial.animation.*;
_root.地图元件={};
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
