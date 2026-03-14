/**
 * WeatherSystem.as
 * 位于：org.flashNight.arki.weather
 *
 * 天气系统主控制器（单例），管理昼夜周期、光照计算、夜视仪集成、
 * 经济倍率、环境配置等。
 *
 * 从帧脚本 _root.天气系统 精确复刻迁移而来。
 * 垫片中通过 _root.天气系统 = WeatherSystem.getInstance() 保持兼容。
 *
 * @class WeatherSystem
 */
import org.flashNight.arki.weather.NightVisionManager;
import org.flashNight.arki.component.Effect.LightingEngine;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.xml.LoadXml.WeatherSystemConfigLoader;
import org.flashNight.naki.Interpolation.Interpolatior;
import org.flashNight.gesh.number.NumberUtil;

dynamic class org.flashNight.arki.weather.WeatherSystem {

    // ==================== 单例 ====================

    private static var _instance:WeatherSystem;

    /**
     * 获取单例实例。
     * 首次调用后用函数替换优化（同 HorizontalScroller 模式）。
     */
    public static function getInstance():WeatherSystem {
        if (!_instance) {
            _instance = new WeatherSystem();
        }
        // 函数替换：后续调用直接返回缓存实例
        WeatherSystem.getInstance = function():WeatherSystem {
            return _instance;
        };
        return _instance;
    }

    // ==================== 内部管理器 ====================

    private var _nightVisionMgr:NightVisionManager;
    private var _initialized:Boolean;

    // ==================== 构造函数 ====================

    /**
     * 构造函数：初始化全部属性为默认值。
     * 属性名保持中文，与旧 _root.天气系统.xxx 外部访问完全一致。
     */
    private function WeatherSystem() {
        this._nightVisionMgr = new NightVisionManager();
        this._initialized = false;

        // ---- 昼夜周期 ----
        this.昼夜长度 = 15 * 60 * 30;  // 一天15分钟
        this.小时帧数 = this.昼夜长度 / 24;
        this.光照等级更新阈值 = 0.1;
        this.使用滤镜渲染 = false;
        this.开启昼夜系统 = true;
        this.暂停昼夜系统 = false;
        this.时间倍率启动等级 = 2.5;
        this.当前时间 = 6;
        this.当前帧数 = 0;
        this.昼夜光照 = [0, 0, 1, 4, 7, 7, 7, 7, 7, 7, 7, 7, 9, 7, 7, 7, 7, 7, 7, 4, 1, 0, 0, 0];
        this.当前光照等级 = this.昼夜光照[this.当前时间];
        this.光照等级最大值 = 9;
        this.光照等级最小值 = 0;
        this.最大光照 = this.光照等级最大值;
        this.最小光照 = this.光照等级最小值;

        // ---- 经济倍率 ----
        this.金币时间倍率 = 1;
        this.金币时间最大倍率 = 2;
        this.经验时间倍率 = 1;
        this.经验时间最大倍率 = 2;
        this.人物信息透明度 = 100;

        // ---- 天气/环境 ----
        this.天气情况 = "正常";
        this.空间情况 = "室外";
        this.视觉情况 = "光照";

        // ---- 环境配置数据（直接存为实例属性，保持引用语义） ----
        this.关卡环境设置 = undefined;
        this.场景环境设置 = undefined;
        this.无限过图环境信息 = null;

        // ---- 默认环境配置 ----
        this.默认环境配置 = {
            地址: "gk20_2_BG.swf",
            对齐原点: false,
            Xmin: 50,
            Xmax: 1750,
            Ymin: 330,
            Ymax: 600,
            背景长: 1750,
            背景高: 600,
            地平线高度: 200,
            后景: null,
            禁用天空: false,
            天气情况: "正常",
            空间情况: "室外",
            视觉情况: "光照",
            最大光照: 8,
            最小光照: 4,
            背景元素: null,
            门: null,
            地图碰撞箱: null,
            左侧出生线: null,
            右侧出生线: null,
            佣兵刷新数据: null,
            BGM: null
        };

        // ---- 夜视仪兼容属性 ----
        // 外部代码可能直接读 _root.天气系统.夜视仪
        // 保持为空对象以兼容旧代码的 if(夜视仪.视觉情况) 判断
        this.夜视仪 = {};
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
        // 注册 EventBus 订阅（仅首次）
        if (!this._initialized) {
            this._initialized = true;
            var bus:EventBus = EventBus.getInstance();
            bus.subscribe("WeatherUpdated", this.updateWeather, this);
            bus.subscribe("WeatherTimeRateUpdated", this._onTimeRateUpdated, this);
            bus.subscribe("SceneChanged", this._onSceneChanged, this);
        }

        // 异步加载 XML 配置
        var configLoader:WeatherSystemConfigLoader = WeatherSystemConfigLoader.getInstance();
        var self:WeatherSystem = this;

        configLoader.load(
            function(data:Object):Void {
                var params:Object = data.GeneralParameters;

                self.昼夜长度 = params.DayLength;
                self.小时帧数 = params.HourFrames;
                self.光照等级更新阈值 = params.LightUpdateThreshold;
                self.使用滤镜渲染 = params.UseFilterRendering;
                self.开启昼夜系统 = params.EnableDayNightCycle;
                self.暂停昼夜系统 = params.PauseDayNightCycle;
                self.时间倍率启动等级 = params.TimeMultiplierStartLevel;
                self.金币时间倍率 = params.CoinTimeMultiplier;
                self.金币时间最大倍率 = params.CoinTimeMaxMultiplier;
                self.经验时间倍率 = params.ExpTimeMultiplier;
                self.经验时间最大倍率 = params.ExpTimeMaxMultiplier;
                self.人物信息透明度 = params.CharacterInfoOpacity;
                self.天气情况 = params.WeatherCondition;
                self.空间情况 = params.SpaceCondition;
                self.视觉情况 = params.VisualCondition;
                self.当前时间 = params.CurrentTime;
                self.当前帧数 = params.CurrentFrame;
                self.光照等级最大值 = params.MaxLight;
                self.光照等级最小值 = params.MinLight;
                self.最大光照 = self.光照等级最大值;
                self.最小光照 = self.光照等级最小值;
                self.无限过图环境信息 = params.InfiniteMapEnvironmentInfo == "null" ? null : params.InfiniteMapEnvironmentInfo;

                var lightLevels:Array = data.LightLevels.Hour;
                self.昼夜光照 = [];
                for (var i:Number = 0; i < 24; i++) {
                    self.昼夜光照[i] = lightLevels[i];
                }
                self.当前光照等级 = self.昼夜光照[self.当前时间];

                trace("天气系统配置已加载成功！");
                if (onComplete != undefined) {
                    onComplete();
                }
            },
            function():Void {
                trace("天气系统配置加载失败，使用默认配置！");
                // 默认值已在构造函数中设置，无需重复
                trace("默认配置已应用！");
                if (onError != undefined) {
                    onError();
                }
            }
        );
    }

    // ==================== 核心方法 ====================

    /**
     * 获取当前游戏内时间（0-24 小时制）。
     * @return 当前时间（浮点数）
     */
    public function getCurrentTime():Number {
        if (!this.开启昼夜系统) return 7;
        if (this.暂停昼夜系统) return this.当前时间;
        var frameCount:Number = _root.帧计时器.当前帧数;
        this.当前时间 = (this.当前时间 + (frameCount - this.当前帧数) / this.小时帧数) % 24;
        this.当前帧数 = frameCount;
        return this.当前时间;
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
            level = Interpolatior.linear(time, baseIdx, nextIdx, this.昼夜光照[baseIdx], this.昼夜光照[nextIdx]);
        } else if ((time <= 11 && time >= 4) || (time <= 18 && time >= 13)) {
            level = 7;
        }

        if (level > this.最大光照) {
            level = this.最大光照;
        } else if (level < this.最小光照) {
            level = this.最小光照;
        }

        if (Math.abs(level - this.当前光照等级) > this.光照等级更新阈值 || !this.当前光照等级) {
            this.当前光照等级 = level;
        }
        return this.当前光照等级;
    }

    /**
     * 更新天气状态（WeatherUpdated 事件 handler）。
     * 计算光照、校验夜视仪、应用光照渲染、发布经济倍率事件。
     */
    public function updateWeather():Void {
        var lightLevel:Number = this.getCurrentLightLevel();
        var visualCondition:String = this.视觉情况;
        var bus:EventBus = EventBus.getInstance();

        // 夜视仪校验（委托给 NightVisionManager）
        var controlTarget:MovieClip = _root.gameworld[_root.控制目标];
        var nvVisual:String = this._nightVisionMgr.validate(lightLevel, controlTarget);
        var nvRegistered:Object = this._nightVisionMgr.getRegistered();

        // 同步兼容属性 _root.天气系统.夜视仪
        if (nvRegistered != null) {
            this.夜视仪 = nvRegistered;
        } else {
            this.夜视仪 = {};
        }

        if (nvVisual != null) {
            visualCondition = nvVisual;
            bus.publish("夜视仪启动", lightLevel);
        }

        // 经济倍率逻辑
        if (lightLevel <= this.时间倍率启动等级 && nvVisual == null) {
            bus.publish("WeatherTimeRateUpdated", lightLevel);
        } else {
            if (this.金币时间倍率 !== 1) {
                this.金币时间倍率 = 1;
                this.经验时间倍率 = 1;
                this.人物信息透明度 = 100;

                if (!_root.gameworld.__updatedWeatherTimeRate) {
                    bus.publish("WeatherTimeRateUpdated", lightLevel);
                    _root.gameworld.__updatedWeatherTimeRate = true;
                    _global.ASSetPropFlags(_root.gameworld, ["__updatedWeatherTimeRate"], 1, false);
                }
            }
        }

        // 应用光照渲染
        LightingEngine.applyLighting(_root.gameworld, lightLevel, visualCondition, this.使用滤镜渲染);
        LightingEngine.applyLighting(_root.天空盒, lightLevel, visualCondition, false);
    }

    /**
     * 配置当前环境（场景加载时调用）。
     * @param envInfo 环境信息对象
     */
    public function configureEnvironment(envInfo:Object):Void {
        if (this.无限过图环境信息) {
            envInfo = this.无限过图环境信息;
            this.无限过图环境信息 = null;
        }
        if (envInfo.天气情况) this.天气情况 = envInfo.天气情况;
        if (envInfo.空间情况) this.空间情况 = envInfo.空间情况;
        if (envInfo.视觉情况) this.视觉情况 = envInfo.视觉情况;
        if (envInfo.最大光照 != undefined) this.最大光照 = envInfo.最大光照;
        if (envInfo.最小光照 != undefined) this.最小光照 = envInfo.最小光照;
    }

    /**
     * 请求刷新天气（合帧）。
     * 同一帧内多次请求合并为下一帧执行一次 WeatherUpdated。
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
        var opacity:Number = this.人物信息透明度;

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

    /**
     * 注册夜视仪（委托给 NightVisionManager）。
     * @param owner 夜视仪配置对象
     */
    public function registerNightVision(owner:Object):Void {
        this._nightVisionMgr.register(owner);
        this.requestRefresh();
    }

    /**
     * 注销夜视仪（委托给 NightVisionManager）。
     * @param owner 夜视仪配置对象
     * @return Boolean 是否成功注销
     */
    public function unregisterNightVision(owner:Object):Boolean {
        var result:Boolean = this._nightVisionMgr.unregister(owner);
        if (result) {
            this.requestRefresh();
        }
        return result;
    }

    // ==================== EventBus 命名回调 ====================

    /**
     * WeatherTimeRateUpdated 事件回调。
     * 计算金币/经验倍率和信息透明度。
     */
    public function _onTimeRateUpdated(lightLevel:Number):Void {
        this.金币时间倍率 = NumberUtil.clamp(
            Interpolatior.linear(lightLevel, 0, this.时间倍率启动等级, this.金币时间最大倍率, 1),
            1,
            this.金币时间最大倍率
        );
        this.经验时间倍率 = NumberUtil.clamp(
            Interpolatior.linear(lightLevel, 0, this.时间倍率启动等级, this.经验时间最大倍率, 1),
            1,
            this.经验时间最大倍率
        );
        this.人物信息透明度 = Interpolatior.linear(lightLevel, 0, this.时间倍率启动等级, 0, 100);
    }

    /**
     * SceneChanged 事件回调。
     * 场景切换时重新计算光照和同步单位状态。
     */
    public function _onSceneChanged():Void {
        var bus:EventBus = EventBus.getInstance();
        var lightLevel:Number = this.getCurrentLightLevel();
        bus.publish("WeatherTimeRateUpdated", lightLevel);
        this.defensiveRefreshUnits();
    }
}
