/**
 * WeatherSystem.as
 * 位于：org.flashNight.arki.weather
 *
 * 天气系统主控制器（单例），管理昼夜周期、光照计算、夜视仪集成、
 * 经济倍率、环境配置等。
 *
 * 从帧脚本 _root.天气系统 迁移而来，所有属性和方法均使用英文命名。
 * 垫片中通过 _root.天气系统 = WeatherSystem.getInstance() 保持最低兼容。
 *
 * @class WeatherSystem
 */
import org.flashNight.arki.weather.NightVisionManager;
import org.flashNight.arki.weather.EnvironmentConfig;
import org.flashNight.arki.component.Effect.LightingEngine;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.xml.LoadXml.WeatherSystemConfigLoader;
import org.flashNight.naki.Interpolation.Interpolatior;
import org.flashNight.gesh.number.NumberUtil;
import org.flashNight.arki.render.WeatherParticleRenderer;
import org.flashNight.arki.render.SkyboxRenderer;
import org.flashNight.arki.render.GameWorldOverlayRenderer;

class org.flashNight.arki.weather.WeatherSystem {

    // ==================== 单例 ====================

    private static var _instance:WeatherSystem;

    public static function getInstance():WeatherSystem {
        if (!_instance) {
            _instance = new WeatherSystem();
        }
        WeatherSystem.getInstance = function():WeatherSystem {
            return _instance;
        };
        return _instance;
    }

    // ==================== 内部管理器 ====================

    private var _nightVisionMgr:NightVisionManager;
    private var _envConfig:EnvironmentConfig;
    private var _initialized:Boolean;

    // ==================== 公共属性（带类型声明，编译期可检查） ====================

    // ---- 昼夜周期 ----
    public var dayLength:Number;
    public var hourFrames:Number;
    public var lightUpdateThreshold:Number;
    public var useFilterRendering:Boolean;
    public var enableDayNightCycle:Boolean;
    public var pauseDayNightCycle:Boolean;
    public var timeMultiplierStartLevel:Number;
    public var currentTime:Number;
    public var currentFrame:Number;
    public var dayNightLightLevels:Array;
    public var currentLightLevel:Number;
    public var maxLightLevel:Number;
    public var minLightLevel:Number;
    public var maxLight:Number;
    public var minLight:Number;

    // ---- 经济倍率 ----
    public var coinTimeMultiplier:Number;
    public var coinTimeMaxMultiplier:Number;
    public var expTimeMultiplier:Number;
    public var expTimeMaxMultiplier:Number;
    public var characterInfoOpacity:Number;

    // ---- 天气/环境 ----
    public var weatherCondition:String;
    public var spaceCondition:String;
    public var visualCondition:String;

    // ---- 环境配置数据（委托给 EnvironmentConfig） ----
    // 已迁移至 _envConfig，通过 getEnvConfig() 访问

    // ==================== SWF 资产兼容桥接 ====================

    /**
     * 为不可修改的 SWF 资产建立中文属性名→英文属性名的 addProperty 桥接。
     * 必须在 class 方法内执行（而非帧脚本），因为 AS2 帧脚本的 activation object
     * 在帧结束后被回收，闭包捕获的局部变量会变成 undefined。
     * class 方法中的 this 由 EventBus/调用方绑定，始终有效。
     */
    public function setupLegacyBridge():Void {
        var self:WeatherSystem = this;
        // 睡觉界面.swf: 读写 当前时间
        this.addProperty("当前时间",
            function():Number { return self.currentTime; },
            function(v:Number):Void { self.currentTime = v; });
        // 新版人物文字信息.swf / things0: 只读 人物信息透明度
        this.addProperty("人物信息透明度",
            function():Number { return self.characterInfoOpacity; },
            null);
        // 柜员女僵尸.swf: 只读 金币/经验时间倍率
        this.addProperty("金币时间倍率",
            function():Number { return self.coinTimeMultiplier; },
            null);
        this.addProperty("经验时间倍率",
            function():Number { return self.expTimeMultiplier; },
            null);
        // FPSVisualization (addProperty 方式兼容旧 mock)
        this.addProperty("昼夜光照",
            function():Array { return self.dayNightLightLevels; },
            null);
        // 系统设置UI.swf: 读写 开启/暂停/滤镜
        this.addProperty("开启昼夜系统",
            function():Boolean { return self.enableDayNightCycle; },
            function(v:Boolean):Void { self.enableDayNightCycle = v; });
        this.addProperty("暂停昼夜系统",
            function():Boolean { return self.pauseDayNightCycle; },
            function(v:Boolean):Void { self.pauseDayNightCycle = v; });
        this.addProperty("使用滤镜渲染",
            function():Boolean { return self.useFilterRendering; },
            function(v:Boolean):Void { self.useFilterRendering = v; });
    }

    // ==================== 构造函数 ====================

    private function WeatherSystem() {
        this._nightVisionMgr = new NightVisionManager();
        this._envConfig = new EnvironmentConfig();
        this._initialized = false;

        // ---- 昼夜周期默认值 ----
        this.dayLength = 15 * 60 * 30;
        this.hourFrames = this.dayLength / 24;
        this.lightUpdateThreshold = 0.1;
        this.useFilterRendering = false;
        this.enableDayNightCycle = true;
        this.pauseDayNightCycle = false;
        this.timeMultiplierStartLevel = 2.5;
        this.currentTime = 6;
        this.currentFrame = 0;
        this.dayNightLightLevels = [0, 0, 1, 4, 7, 7, 7, 7, 7, 7, 7, 7, 9, 7, 7, 7, 7, 7, 7, 4, 1, 0, 0, 0];
        this.currentLightLevel = this.dayNightLightLevels[this.currentTime];
        this.maxLightLevel = 9;
        this.minLightLevel = 0;
        this.maxLight = this.maxLightLevel;
        this.minLight = this.minLightLevel;

        // ---- 经济倍率默认值 ----
        this.coinTimeMultiplier = 1;
        this.coinTimeMaxMultiplier = 2;
        this.expTimeMultiplier = 1;
        this.expTimeMaxMultiplier = 2;
        this.characterInfoOpacity = 100;

        // ---- 天气/环境默认值 ----
        this.weatherCondition = "正常";
        this.spaceCondition = "室外";
        this.visualCondition = "光照";

    }

    // ==================== 初始化 ====================

    /**
     * 异步初始化：加载 XML 配置 + 注册 EventBus 订阅。
     * 内置 _initialized guard 防止重复订阅。
     *
     * @param onComplete 加载成功回调
     * @param onError    加载失败回调
     */
    public function initialize(onComplete:Function, onError:Function):Void {
        if (!this._initialized) {
            this._initialized = true;
            var bus:EventBus = EventBus.getInstance();
            bus.subscribe("WeatherUpdated", this.updateWeather, this);
            bus.subscribe("WeatherTimeRateUpdated", this._onTimeRateUpdated, this);
            bus.subscribe("SceneChanged", this._onSceneChanged, this);
            bus.subscribe("SceneReady", this._onSceneReady, this);

            // 初始化天气渲染器（订阅 frameEnd 实现逐帧更新）
            WeatherParticleRenderer.initialize();
            SkyboxRenderer.initialize();
            GameWorldOverlayRenderer.initialize();
        }

        var configLoader:WeatherSystemConfigLoader = WeatherSystemConfigLoader.getInstance();
        var self:WeatherSystem = this;

        configLoader.load(
            function(data:Object):Void {
                var params:Object = data.GeneralParameters;

                self.dayLength = params.DayLength;
                self.hourFrames = params.HourFrames;
                self.lightUpdateThreshold = params.LightUpdateThreshold;
                // XML 解析可能返回字符串 "true"/"false"，必须强转 boolean
                // 否则 "false"（非空字符串）在 if() 中为 truthy，会冻结时间
                // 且系统设置 UI 复选框用 == true/false 严格比较，字符串不匹配会导致按钮失效
                self.useFilterRendering = (params.UseFilterRendering === true || params.UseFilterRendering === "true");
                self.enableDayNightCycle = (params.EnableDayNightCycle === true || params.EnableDayNightCycle === "true");
                self.pauseDayNightCycle = (params.PauseDayNightCycle === true || params.PauseDayNightCycle === "true");
                self.timeMultiplierStartLevel = params.TimeMultiplierStartLevel;
                self.coinTimeMultiplier = params.CoinTimeMultiplier;
                self.coinTimeMaxMultiplier = params.CoinTimeMaxMultiplier;
                self.expTimeMultiplier = params.ExpTimeMultiplier;
                self.expTimeMaxMultiplier = params.ExpTimeMaxMultiplier;
                self.characterInfoOpacity = params.CharacterInfoOpacity;
                self.weatherCondition = params.WeatherCondition;
                self.spaceCondition = params.SpaceCondition;
                self.visualCondition = params.VisualCondition;
                self.currentTime = params.CurrentTime;
                self.currentFrame = params.CurrentFrame;
                self.maxLightLevel = params.MaxLight;
                self.minLightLevel = params.MinLight;
                self.maxLight = self.maxLightLevel;
                self.minLight = self.minLightLevel;
                var infMapEnv:Object = params.InfiniteMapEnvironmentInfo == "null" ? null : params.InfiniteMapEnvironmentInfo;
                self._envConfig.setInfiniteMapEnvInfo(infMapEnv);

                var lightLevels:Array = data.LightLevels.Hour;
                self.dayNightLightLevels = [];
                for (var i:Number = 0; i < 24; i++) {
                    self.dayNightLightLevels[i] = lightLevels[i];
                }
                self.currentLightLevel = self.dayNightLightLevels[self.currentTime];

                trace("天气系统配置已加载成功！");
                if (onComplete != undefined) {
                    onComplete();
                }
            },
            function():Void {
                trace("天气系统配置加载失败，使用默认配置！");
                trace("默认配置已应用！");
                if (onError != undefined) {
                    onError();
                }
            }
        );
    }

    // ==================== 环境配置访问 ====================

    /**
     * 获取环境配置管理器。
     * @return EnvironmentConfig
     */
    public function getEnvConfig():EnvironmentConfig {
        return this._envConfig;
    }

    // ==================== 核心方法 ====================

    /**
     * 获取当前游戏内时间（0-24 小时制）。
     * @return 当前时间（浮点数）
     */
    public function getCurrentTime():Number {
        if (!this.enableDayNightCycle) return 7;
        if (this.pauseDayNightCycle) return this.currentTime;
        var frameCount:Number = _root.帧计时器.当前帧数;
        this.currentTime = (this.currentTime + (frameCount - this.currentFrame) / this.hourFrames) % 24;
        this.currentFrame = frameCount;
        return this.currentTime;
    }

    /**
     * 获取当前光照等级（含插值和范围钳制）。
     * @return 当前光照等级
     */
    public function getCurrentLightLevel():Number {
        var time:Number = this.getCurrentTime();
        var level:Number = 0;

        if ((time < 4 && time > 1) || (time < 13 && time > 11) || (time < 21 && time > 18)) {
            var baseIdx:Number = Math.floor(time);
            var nextIdx:Number = Math.ceil(time);
            level = Interpolatior.linear(time, baseIdx, nextIdx, this.dayNightLightLevels[baseIdx], this.dayNightLightLevels[nextIdx]);
        } else if ((time <= 11 && time >= 4) || (time <= 18 && time >= 13)) {
            level = 7;
        }

        level = NumberUtil.clamp(level, this.minLight, this.maxLight);

        if (Math.abs(level - this.currentLightLevel) > this.lightUpdateThreshold || !this.currentLightLevel) {
            this.currentLightLevel = level;
        }
        return this.currentLightLevel;
    }

    /**
     * 更新天气状态（WeatherUpdated 事件 handler）。
     */
    public function updateWeather():Void {
        var lightLevel:Number = this.getCurrentLightLevel();
        var vc:String = this.visualCondition;
        var bus:EventBus = EventBus.getInstance();
        // 夜视仪校验
        var controlTarget:MovieClip = _root.gameworld[_root.控制目标];
        var nvVisual:String = this._nightVisionMgr.validate(lightLevel, controlTarget);

        if (nvVisual != null) {
            vc = nvVisual;
            bus.publish("夜视仪启动", lightLevel);
        }

        // 经济倍率逻辑
        if (lightLevel <= this.timeMultiplierStartLevel && nvVisual == null) {
            bus.publish("WeatherTimeRateUpdated", lightLevel);
        } else {
            if (this.coinTimeMultiplier !== 1) {
                this.coinTimeMultiplier = 1;
                this.expTimeMultiplier = 1;
                this.characterInfoOpacity = 100;

                if (!_root.gameworld.__updatedWeatherTimeRate) {
                    bus.publish("WeatherTimeRateUpdated", lightLevel);
                    _root.gameworld.__updatedWeatherTimeRate = true;
                    _global.ASSetPropFlags(_root.gameworld, ["__updatedWeatherTimeRate"], 1, false);
                }
            }
        }

        // 应用光照渲染
        LightingEngine.applyLighting(_root.gameworld, lightLevel, vc, this.useFilterRendering);
        LightingEngine.applyLighting(_root.天空盒, lightLevel, vc, false);

        // 更新天空盒目标色（低频驱动，逐帧 lerp 由渲染器自行完成）
        SkyboxRenderer.setTimeAndWeather(this.currentTime, this.weatherCondition);
    }

    /**
     * 配置当前环境（场景加载时调用）。
     * @param envInfo 环境信息对象
     */
    public function configureEnvironment(envInfo:Object):Void {
        var override:Object = this._envConfig.consumeInfiniteMapEnvInfo();
        if (override != null) {
            envInfo = override;
        }
        if (envInfo.天气情况) this.weatherCondition = envInfo.天气情况;
        if (envInfo.空间情况) this.spaceCondition = envInfo.空间情况;
        if (envInfo.视觉情况) this.visualCondition = envInfo.视觉情况;
        if (envInfo.最大光照 != undefined) this.maxLight = envInfo.最大光照;
        if (envInfo.最小光照 != undefined) this.minLight = envInfo.最小光照;

        // ---- 天空盒渲染器：室内/禁用天空判定 ----
        var skyDisabled:Boolean = (this.spaceCondition == "室内") || (envInfo.禁用天空 == true);
        SkyboxRenderer.setSkyEnabled(!skyDisabled);

        // ---- 天气粒子渲染器（室内外均可用） ----
        // 优先使用 envInfo.粒子类型（显式指定，室内外通用）
        // 未指定时，室外从 天气情况 推导，室内默认关闭
        var particleType:String = envInfo.粒子类型;
        var particleIntensity:Number = envInfo.粒子强度;
        if (particleType == undefined) {
            if (!skyDisabled) {
                // 室外：从天气情况推导粒子类型
                var wc:String = this.weatherCondition;
                var defaultIntensity:Number = envInfo.天气强度 != undefined ? envInfo.天气强度 : 0.5;
                if (wc == "雨") {
                    particleType = "rain"; particleIntensity = defaultIntensity;
                } else if (wc == "雪") {
                    particleType = "snow"; particleIntensity = defaultIntensity;
                } else if (wc == "沙尘") {
                    particleType = "dust"; particleIntensity = defaultIntensity;
                } else if (envInfo.允许随机天气 == true) {
                    _randomizeWeather(defaultIntensity);
                    particleType = null; // _randomizeWeather 已内部调用 setWeather
                }
            }
        }
        // 分发到粒子渲染器（_randomizeWeather 路径已自行处理，跳过）
        if (particleType != undefined) {
            WeatherParticleRenderer.setWeather(particleType, particleIntensity);
        } else if (particleType == undefined && envInfo.允许随机天气 != true) {
            WeatherParticleRenderer.setWeather("none", 0);
        }

        // ---- gameworld 色调叠加（室内外均可用） ----
        var overlay:Object = envInfo.色调叠加;
        if (overlay != undefined && overlay != null) {
            GameWorldOverlayRenderer.setOverlay(overlay.r, overlay.g, overlay.b, overlay.alpha);
            if (overlay.mode != undefined) {
                GameWorldOverlayRenderer.setMode(overlay.mode);
            }
            if (overlay.pulse) {
                GameWorldOverlayRenderer.setPulse(true, overlay.pulseSpeed, overlay.pulseMin, overlay.pulseMax);
            }
        } else {
            GameWorldOverlayRenderer.clearOverlay();
        }

        // ---- 天空盒色调：设置目标值，逐帧 lerp 平滑过渡 ----
        if (!skyDisabled) {
            SkyboxRenderer.setTimeAndWeather(this.currentTime, this.weatherCondition);
            var groundY:Number = _root.Ymax;
            if (!isNaN(groundY) && groundY > 0) {
                SkyboxRenderer.setGroundY(groundY);
            }
        }
    }

    /**
     * 随机掷骰决定天气（室外 + 允许随机天气 场景）。
     */
    private function _randomizeWeather(intensity:Number):Void {
        var roll:Number = Math.random() * 100;
        if (roll < 20) {
            WeatherParticleRenderer.setWeather("rain", intensity);
            this.weatherCondition = "雨";
        } else if (roll < 25) {
            WeatherParticleRenderer.setWeather("snow", intensity);
            this.weatherCondition = "雪";
        } else if (roll < 30) {
            WeatherParticleRenderer.setWeather("dust", intensity);
            this.weatherCondition = "沙尘";
        } else {
            WeatherParticleRenderer.setWeather("none", 0);
        }
    }

    /**
     * 请求刷新天气（合帧）。
     */
    public function requestRefresh():Void {
        var bus:EventBus = EventBus.getInstance();

        if (!_root.帧计时器.添加或更新任务) {
            bus.publish("WeatherUpdated");
            return;
        }

        _root.帧计时器.添加或更新任务(this, "__WeatherSystem_RequestRefresh", function() {
            EventBus.getInstance().publish("WeatherUpdated");
        }, 1);
    }

    /**
     * 防御性刷新：同步场景中所有单位的天气相关状态。
     * @return 刷新的单位数量
     */
    public function defensiveRefreshUnits():Number {
        var gameworld:MovieClip = _root.gameworld;
        if (!gameworld) {
            return 0;
        }

        var count:Number = 0;
        var opacity:Number = this.characterInfoOpacity;

        for (var each:String in gameworld) {
            var unit:MovieClip = gameworld[each];
            if (unit && unit.hp > 0) {
                var ic:MovieClip = unit.新版人物文字信息 || unit.人物文字信息;
                if (ic) {
                    ic._alpha = opacity;
                    count++;
                }
            }
        }

        return count;
    }

    // ==================== 夜视仪接口 ====================

    public function registerNightVision(owner:Object):Void {
        this._nightVisionMgr.register(owner);
        this.requestRefresh();
    }

    public function unregisterNightVision(owner:Object):Boolean {
        var result:Boolean = this._nightVisionMgr.unregister(owner);
        if (result) {
            this.requestRefresh();
        }
        return result;
    }

    /**
     * 获取夜视仪管理器实例（供高级用途）。
     * @return NightVisionManager
     */
    public function getNightVisionManager():NightVisionManager {
        return this._nightVisionMgr;
    }

    // ==================== EventBus 命名回调 ====================

    public function _onTimeRateUpdated(lightLevel:Number):Void {
        this.coinTimeMultiplier = NumberUtil.clamp(
            Interpolatior.linear(lightLevel, 0, this.timeMultiplierStartLevel, this.coinTimeMaxMultiplier, 1),
            1,
            this.coinTimeMaxMultiplier
        );
        this.expTimeMultiplier = NumberUtil.clamp(
            Interpolatior.linear(lightLevel, 0, this.timeMultiplierStartLevel, this.expTimeMaxMultiplier, 1),
            1,
            this.expTimeMaxMultiplier
        );
        this.characterInfoOpacity = Interpolatior.linear(lightLevel, 0, this.timeMultiplierStartLevel, 0, 100);
    }

    /**
     * SceneReady 事件回调。
     * 碰撞箱和场景元素就绪后，将地图边界传入粒子渲染器并激活。
     */
    public function _onSceneReady():Void {
        var xmin:Number = _root.Xmin;
        var xmax:Number = _root.Xmax;
        var ymin:Number = _root.Ymin;
        var ymax:Number = _root.Ymax;
        if (!isNaN(xmin) && !isNaN(xmax) && !isNaN(ymin) && !isNaN(ymax)) {
            WeatherParticleRenderer.activateWithBounds(xmin, xmax, ymin, ymax);
        }
    }

    /**
     * SceneChanged 事件回调。
     * 场景切换时清理夜视仪注册、重新计算光照、同步单位状态。
     */
    public function _onSceneChanged():Void {
        // 场景切换时清除夜视仪注册，防止跨场景残留
        this._nightVisionMgr.clear();

        // 清理天气渲染器状态
        WeatherParticleRenderer.dispose();
        SkyboxRenderer.dispose();
        GameWorldOverlayRenderer.dispose();

        var bus:EventBus = EventBus.getInstance();
        var lightLevel:Number = this.getCurrentLightLevel();
        bus.publish("WeatherTimeRateUpdated", lightLevel);
        this.defensiveRefreshUnits();
    }
}
