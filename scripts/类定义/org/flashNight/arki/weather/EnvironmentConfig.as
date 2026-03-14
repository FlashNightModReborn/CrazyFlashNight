/**
 * EnvironmentConfig.as
 * 位于：org.flashNight.arki.weather
 *
 * 环境配置数据管理器 - 负责关卡/场景环境设置的存储、访问和 XML 解析。
 * 从 WeatherSystem 中分离出的纯数据管理职责。
 *
 * @class EnvironmentConfig
 */
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.arki.weather.EnvironmentConfig {

    // ==================== 数据字典 ====================

    /** 关卡环境设置，URL 键 → envInfo */
    private var _stageEnvSettings:Object;

    /** 场景环境设置，关卡标志键 → envInfo */
    private var _sceneEnvSettings:Object;

    /** 默认环境配置模板（中文键名，与 XML 数据结构一致） */
    private var _defaultEnvConfig:Object;

    /** 当前关卡环境覆盖（由 StageManager 设置，configureEnvironment 消费后清空） */
    private var _infiniteMapEnvInfo:Object;

    // ==================== 构造函数 ====================

    public function EnvironmentConfig() {
        this._stageEnvSettings = undefined;
        this._sceneEnvSettings = undefined;
        this._infiniteMapEnvInfo = null;

        // 默认环境配置 - 中文键名与环境 XML 数据结构、_root.配置环境信息 保持一致
        this._defaultEnvConfig = {
            地址: "gk20_2_BG.swf",
            对齐原点: false,
            Xmin: 50, Xmax: 1750,
            Ymin: 330, Ymax: 600,
            背景长: 1750, 背景高: 600,
            地平线高度: 200,
            后景: null, 禁用天空: false,
            天气情况: "正常", 空间情况: "室外", 视觉情况: "光照",
            最大光照: 8, 最小光照: 4,
            背景元素: null,
            门: null, 地图碰撞箱: null,
            左侧出生线: null, 右侧出生线: null,
            佣兵刷新数据: null, BGM: null,
            允许随机天气: false,
            天气强度: 0.5
        };
    }

    // ==================== 关卡环境设置访问器 ====================

    /**
     * 获取指定 URL 的关卡环境配置（返回深拷贝，调用方可安全修改）。
     * @param url 背景 SWF 文件名
     * @return 环境配置对象的克隆，未找到返回 null
     */
    public function getStageEnv(url:String):Object {
        if (this._stageEnvSettings == undefined) return null;
        var env:Object = this._stageEnvSettings[url];
        if (env == undefined) return null;
        return ObjectUtil.clone(env);
    }

    /**
     * 获取默认关卡环境配置（返回深拷贝）。
     * 用于 StageManager 未找到指定 URL 时的回退。
     * @return 默认配置的克隆
     */
    public function getStageEnvDefault():Object {
        if (this._stageEnvSettings == undefined) return null;
        var env:Object = this._stageEnvSettings.Default;
        if (env == undefined) return null;
        return ObjectUtil.clone(env);
    }

    /**
     * 设置完整的关卡环境设置字典。
     * @param settings 以 URL 为键的环境配置字典
     */
    public function setStageEnvSettings(settings:Object):Void {
        this._stageEnvSettings = settings;
    }

    // ==================== 场景环境设置访问器 ====================

    /**
     * 获取指定标识的场景环境配置（返回引用，只读场景）。
     * @param identifier 关卡标志
     * @return 环境配置对象引用，未找到返回 null
     */
    public function getSceneEnv(identifier:String):Object {
        if (this._sceneEnvSettings == undefined) return null;
        var env:Object = this._sceneEnvSettings[identifier];
        return (env != undefined) ? env : null;
    }

    /**
     * 检查是否存在指定标识的场景环境配置。
     * @param identifier 关卡标志
     * @return Boolean
     */
    public function hasSceneEnv(identifier:String):Boolean {
        return this._sceneEnvSettings != undefined && this._sceneEnvSettings[identifier] != undefined;
    }

    /**
     * 设置完整的场景环境设置字典。
     * @param settings 以关卡标志为键的环境配置字典
     */
    public function setSceneEnvSettings(settings:Object):Void {
        this._sceneEnvSettings = settings;
    }

    // ==================== 默认配置 ====================

    /**
     * 获取默认环境配置模板（返回引用，作为解析时的 fallback 参数使用）。
     * @return 默认配置对象
     */
    public function getDefaultEnvConfig():Object {
        return this._defaultEnvConfig;
    }

    // ==================== 无限过图环境信息 ====================

    /**
     * 获取无限过图环境信息（只读引用）。
     * @return 环境信息对象，或 null
     */
    public function getInfiniteMapEnvInfo():Object {
        return this._infiniteMapEnvInfo;
    }

    /**
     * 设置无限过图环境信息（由 StageManager.initStage 写入）。
     * @param info 环境信息对象
     */
    public function setInfiniteMapEnvInfo(info:Object):Void {
        this._infiniteMapEnvInfo = info;
    }

    /**
     * 消费无限过图环境信息：读取后清空。
     * 若已有覆盖信息则返回该信息并清空，否则返回 null。
     * @return 环境信息对象，或 null
     */
    public function consumeInfiniteMapEnvInfo():Object {
        var info:Object = this._infiniteMapEnvInfo;
        if (info != null) {
            this._infiniteMapEnvInfo = null;
        }
        return info;
    }

    // ==================== 静态解析方法 ====================

    /**
     * 将 XML 原始配置解析为环境信息对象。
     * 迁移自 _root.配置环境信息()。
     *
     * @param rawConfig XML 解析后的原始配置对象
     * @param defaults  默认配置（缺失字段的回退值）
     * @return 解析后的环境信息对象，rawConfig 为空时返回 null
     */
    public static function parseEnvironmentInfo(rawConfig:Object, defaults:Object):Object {
        if (!rawConfig) return null;

        var info:Object = {};

        info.地址 = rawConfig.BackgroundURL;

        // 地图尺寸
        info.对齐原点 = rawConfig.Alignment ? true : defaults.对齐原点;
        info.Xmin = !isNaN(rawConfig.Xmin) ? Number(rawConfig.Xmin) : defaults.Xmin;
        info.Xmax = !isNaN(rawConfig.Xmax) ? Number(rawConfig.Xmax) : defaults.Xmax;
        info.Ymin = !isNaN(rawConfig.Ymin) ? Number(rawConfig.Ymin) : defaults.Ymin;
        info.Ymax = !isNaN(rawConfig.Ymax) ? Number(rawConfig.Ymax) : defaults.Ymax;
        info.背景长 = !isNaN(rawConfig.Width) ? Number(rawConfig.Width) : defaults.背景长;
        info.背景高 = !isNaN(rawConfig.Height) ? Number(rawConfig.Height) : defaults.背景高;

        // 后景信息
        info.地平线高度 = !isNaN(rawConfig.Horizon) ? rawConfig.Horizon : defaults.地平线高度;
        info.后景 = rawConfig.Skybox ? ObjectUtil.toArray(rawConfig.Skybox) : defaults.后景;
        info.禁用天空 = rawConfig.DisableSky == true ? true : defaults.禁用天空;

        // 天气信息
        info.天气情况 = rawConfig.WeatherCondition != undefined ? rawConfig.WeatherCondition : defaults.天气情况;
        info.空间情况 = rawConfig.SpaceCondition != undefined ? rawConfig.SpaceCondition : defaults.空间情况;
        info.视觉情况 = rawConfig.VisualCondition != undefined ? rawConfig.VisualCondition : defaults.视觉情况;
        info.最大光照 = rawConfig.MaxIllumination != undefined ? Number(rawConfig.MaxIllumination) : defaults.最大光照;
        info.最小光照 = rawConfig.MinIllumination != undefined ? Number(rawConfig.MinIllumination) : defaults.最小光照;

        // 天气粒子扩展字段
        info.允许随机天气 = rawConfig.AllowRandomWeather == "true" ? true : defaults.允许随机天气;
        info.天气强度 = !isNaN(rawConfig.WeatherIntensity) ? Number(rawConfig.WeatherIntensity) : defaults.天气强度;

        // 背景元素
        info.背景元素 = rawConfig.Instances ? parseBackgroundElements(ObjectUtil.toArray(rawConfig.Instances.Instance)) : defaults.背景元素;

        // 无限过图参数 - 门
        if (rawConfig.Door) {
            var doorData:Array = ObjectUtil.toArray(rawConfig.Door);
            info.门 = {};
            for (var i:Number = 0; i < doorData.length; i++) {
                var door:Object = doorData[i];
                info.门[door.Index] = door;
            }
        } else {
            info.门 = defaults.门;
        }

        info.地图碰撞箱 = rawConfig.Collision ? ObjectUtil.toArray(rawConfig.Collision) : defaults.地图碰撞箱;
        info.左侧出生线 = rawConfig.LeftSpawnLine ? rawConfig.LeftSpawnLine : defaults.左侧出生线;
        info.右侧出生线 = rawConfig.RightSpawnLine ? rawConfig.RightSpawnLine : defaults.右侧出生线;

        // 基地场景额外数据
        info.佣兵刷新数据 = rawConfig.MercenaryRefresh ? rawConfig.MercenaryRefresh : defaults.佣兵刷新数据;
        info.BGM = rawConfig.BGM ? rawConfig.BGM : defaults.BGM;

        return info;
    }

    /**
     * 解析背景元素数据：规范化名称、坐标、深度。
     * 迁移自 _root.解析背景元素()。
     *
     * @param elemData 背景元素数组
     * @return 规范化后的数组，空数组返回 null
     */
    public static function parseBackgroundElements(elemData:Array):Array {
        var len:Number = elemData.length;
        if (len <= 0) return null;
        for (var i:Number = 0; i < len; i++) {
            if (!elemData[i].name) elemData[i].name = "element" + i;
            elemData[i].x = Number(elemData[i].x);
            elemData[i].y = Number(elemData[i].y);
            if (!elemData[i].depth) elemData[i].depth = null;
        }
        return elemData;
    }
}
