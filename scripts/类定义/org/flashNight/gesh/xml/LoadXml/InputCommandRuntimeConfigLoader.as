import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.path.*;

/**
 * InputCommandRuntimeConfigLoader - 搓招运行时参数配置加载器
 *
 * 加载 InputCommandRuntimeConfig.xml 并应用到相关类的静态配置。
 *
 * 注意：XMLLoader 返回的是经 XMLParser.parseXMLNode() 处理后的 Object，
 * 而非原始 XMLNode，因此本类直接处理 Object 结构。
 *
 * 配置结构：
 * - DFA: DefaultTimeout, DefaultFrameWindow, TimeoutBase, TimeoutFactor
 * - HistoryBuffer: EventCapacity, FrameCapacity
 * - Sampler: DoubleTapWindow
 *
 * @author FlashNight
 * @version 2.0
 */  
class org.flashNight.gesh.xml.LoadXml.InputCommandRuntimeConfigLoader {

    // ========== 日志方法 ==========

    private static function log(message:String, level:String):Void {
        var formattedMessage:String = "[InputCommandRuntimeConfigLoader] [" + level + "] " + message;
        if (_root["服务器"] != undefined && _root["服务器"]["发布服务器消息"] != undefined) {
            _root["服务器"]["发布服务器消息"](formattedMessage);
        }
        trace(formattedMessage);
    }

    private static function logError(message:String):Void { log(message, "ERROR"); }
    private static function logWarn(message:String):Void { log(message, "WARN"); }
    private static function logInfo(message:String):Void { log(message, "INFO"); }
    private static function logDebug(message:String):Void { log(message, "DEBUG"); }

    // ========== 静态配置存储 ==========

    /** DFA 配置 */
    public static var dfaDefaultTimeout:Number = 5;
    public static var dfaDefaultFrameWindow:Number = 15;
    public static var dfaTimeoutBase:Number = 3;
    public static var dfaTimeoutFactor:Number = 2;

    /** HistoryBuffer 配置 */
    public static var historyEventCapacity:Number = 64;
    public static var historyFrameCapacity:Number = 30;

    /** Sampler 配置 */
    public static var samplerDoubleTapWindow:Number = 12;

    /** Buffer 配置 */
    public static var bufferTolerance:Number = 5;

    /** 模组覆盖配置 {moduleId: {param: value, ...}, ...} */
    public static var moduleOverrides:Object = {};

    /** 是否已加载 */
    private static var _loaded:Boolean = false;

    // ========== 实例字段 ==========

    private var _filePath:String;
    private var _isLoading:Boolean = false;
    private var _rawData:Object = null;

    // ========== 构造函数 ==========

    /**
     * 创建 InputCommandRuntimeConfigLoader 实例
     * @param relativePath 相对于资源目录的配置文件路径
     */
    public function InputCommandRuntimeConfigLoader(relativePath:String) {
        PathManager.initialize();

        if (!PathManager.isEnvironmentValid()) {
            logError("未检测到有效的资源环境！");
            return;
        }

        this._filePath = PathManager.resolvePath(relativePath);
        if (this._filePath == null) {
            logError("路径解析失败: " + relativePath);
        }
    }

    // ========== 加载方法 ==========

    /**
     * 加载并应用运行时配置
     * @param onSuccess 成功回调 function(config:Object):Void
     * @param onError 失败回调 function():Void
     */
    public function load(onSuccess:Function, onError:Function):Void {
        if (this._isLoading) {
            logWarn("正在加载中");
            return;
        }

        if (InputCommandRuntimeConfigLoader._loaded) {
            logDebug("配置已加载，使用缓存");
            if (onSuccess != null) onSuccess(this.getConfigSnapshot());
            return;
        }

        if (this._filePath == null) {
            logError("文件路径为空");
            if (onError != null) onError();
            return;
        }

        this._isLoading = true;
        var self:InputCommandRuntimeConfigLoader = this;

        logInfo("加载运行时配置: " + this._filePath);

        new XMLLoader(this._filePath, function(parsedData:Object):Void {
            self._isLoading = false;

            // parsedData 是 XMLParser.parseXMLNode() 返回的 Object
            if (self.parseAndApply(parsedData)) {
                InputCommandRuntimeConfigLoader._loaded = true;
                logInfo("运行时配置加载并应用成功");
                if (onSuccess != null) onSuccess(self.getConfigSnapshot());
            } else {
                logError("配置解析失败");
                if (onError != null) onError();
            }

        }, function():Void {
            self._isLoading = false;
            logError("加载失败: " + self._filePath);
            if (onError != null) onError();
        });
    }

    // ========== Object 结构解析与应用 ==========

    /**
     * 解析 Object 数据并应用到静态配置
     *
     * XMLParser 返回的结构如：
     * {
     *   DFA: {
     *     DefaultTimeout: 5,
     *     DefaultFrameWindow: 15,
     *     TimeoutBase: 3,
     *     TimeoutFactor: 2
     *   },
     *   HistoryBuffer: {
     *     EventCapacity: 64,
     *     FrameCapacity: 30
     *   },
     *   Sampler: {
     *     DoubleTapWindow: 12
     *   },
     *   ModuleOverrides: { Module: [...] }
     * }
     */
    private function parseAndApply(data:Object):Boolean {
        if (data == null) {
            logError("data 为 null");
            return false;
        }

        this._rawData = data;

        // 解析 DFA 配置
        if (data.DFA != undefined) {
            this.parseDFAConfig(data.DFA);
        }

        // 解析 HistoryBuffer 配置
        if (data.HistoryBuffer != undefined) {
            this.parseHistoryBufferConfig(data.HistoryBuffer);
        }

        // 解析 Sampler 配置
        if (data.Sampler != undefined) {
            this.parseSamplerConfig(data.Sampler);
        }

        // 解析 Buffer 配置
        if (data.Buffer != undefined) {
            this.parseBufferConfig(data.Buffer);
        }

        // 解析 ModuleOverrides 配置
        if (data.ModuleOverrides != undefined) {
            this.parseModuleOverrides(data.ModuleOverrides);
        }

        // 应用到 CommandDFA 静态字段
        this.applyToCommandDFA();

        return true;
    }

    /**
     * 解析 DFA 配置对象
     */
    private function parseDFAConfig(dfaObj:Object):Void {
        if (dfaObj.DefaultTimeout != undefined) {
            InputCommandRuntimeConfigLoader.dfaDefaultTimeout = Number(dfaObj.DefaultTimeout);
            logDebug("DFA.DefaultTimeout = " + dfaObj.DefaultTimeout);
        }
        if (dfaObj.DefaultFrameWindow != undefined) {
            InputCommandRuntimeConfigLoader.dfaDefaultFrameWindow = Number(dfaObj.DefaultFrameWindow);
            logDebug("DFA.DefaultFrameWindow = " + dfaObj.DefaultFrameWindow);
        }
        if (dfaObj.TimeoutBase != undefined) {
            InputCommandRuntimeConfigLoader.dfaTimeoutBase = Number(dfaObj.TimeoutBase);
            logDebug("DFA.TimeoutBase = " + dfaObj.TimeoutBase);
        }
        if (dfaObj.TimeoutFactor != undefined) {
            InputCommandRuntimeConfigLoader.dfaTimeoutFactor = Number(dfaObj.TimeoutFactor);
            logDebug("DFA.TimeoutFactor = " + dfaObj.TimeoutFactor);
        }
    }

    /**
     * 解析 HistoryBuffer 配置对象
     */
    private function parseHistoryBufferConfig(bufferObj:Object):Void {
        if (bufferObj.EventCapacity != undefined) {
            InputCommandRuntimeConfigLoader.historyEventCapacity = Number(bufferObj.EventCapacity);
            logDebug("HistoryBuffer.EventCapacity = " + bufferObj.EventCapacity);
        }
        if (bufferObj.FrameCapacity != undefined) {
            InputCommandRuntimeConfigLoader.historyFrameCapacity = Number(bufferObj.FrameCapacity);
            logDebug("HistoryBuffer.FrameCapacity = " + bufferObj.FrameCapacity);
        }
    }

    /**
     * 解析 Sampler 配置对象
     */
    private function parseSamplerConfig(samplerObj:Object):Void {
        if (samplerObj.DoubleTapWindow != undefined) {
            InputCommandRuntimeConfigLoader.samplerDoubleTapWindow = Number(samplerObj.DoubleTapWindow);
            logDebug("Sampler.DoubleTapWindow = " + samplerObj.DoubleTapWindow);
        }
    }

    /**
     * 解析 Buffer 配置对象
     */
    private function parseBufferConfig(bufferObj:Object):Void {
        if (bufferObj.Tolerance != undefined) {
            InputCommandRuntimeConfigLoader.bufferTolerance = Number(bufferObj.Tolerance);
            logDebug("Buffer.Tolerance = " + bufferObj.Tolerance);
        }
    }

    /**
     * 解析模组覆盖配置
     * { Module: [...] } 或 { Module: {...} }
     */
    private function parseModuleOverrides(overridesObj:Object):Void {
        if (overridesObj.Module == undefined) return;

        var moduleList:Array = this.ensureArray(overridesObj.Module);

        for (var i:Number = 0; i < moduleList.length; i++) {
            var moduleObj:Object = moduleList[i];
            var moduleId:String = moduleObj.id;
            if (moduleId == undefined) continue;

            var overrides:Object = {};

            // 复制所有非 id 的属性作为覆盖配置
            for (var key:String in moduleObj) {
                if (key != "id") {
                    overrides[key] = moduleObj[key];
                }
            }

            InputCommandRuntimeConfigLoader.moduleOverrides[moduleId] = overrides;
            logDebug("ModuleOverride[" + moduleId + "] = " + this.objectToString(overrides));
        }
    }

    /**
     * 应用配置到 CommandDFA 静态字段
     */
    private function applyToCommandDFA():Void {
        // 尝试访问 CommandDFA 类
        var CommandDFA:Function = _global.org.flashNight.neur.InputCommand.CommandDFA;

        if (CommandDFA != undefined) {
            CommandDFA.DEFAULT_TIMEOUT = InputCommandRuntimeConfigLoader.dfaDefaultTimeout;
            CommandDFA.DEFAULT_FRAME_WINDOW = InputCommandRuntimeConfigLoader.dfaDefaultFrameWindow;
            CommandDFA.TIMEOUT_BASE = InputCommandRuntimeConfigLoader.dfaTimeoutBase;
            CommandDFA.TIMEOUT_FACTOR = InputCommandRuntimeConfigLoader.dfaTimeoutFactor;
            logInfo("已应用配置到 CommandDFA 静态字段");
        } else {
            logDebug("CommandDFA 类尚未加载，配置将在构造时生效");
        }
    }

    // ========== 工具方法 ==========

    /**
     * 确保值为数组
     * XMLParser 对于单个子节点返回对象，多个子节点返回数组
     * 注意：AS2 中 instanceof Array 可能不可靠，使用 length 属性检测
     */
    private function ensureArray(value):Array {
        if (value == undefined || value == null) {
            return [];
        }
        // AS2 中 instanceof Array 可能失败，改用 length 属性和 push 方法检测
        if (typeof(value.length) == "number" && typeof(value.push) == "function") {
            return value;
        }
        var arr:Array = [];
        arr.push(value);
        return arr;
    }

    /**
     * 对象转字符串（调试用）
     */
    private function objectToString(obj:Object):String {
        var parts:Array = [];
        for (var key:String in obj) {
            parts.push(key + ":" + obj[key]);
        }
        return "{" + parts.join(", ") + "}";
    }

    // ========== 访问器 ==========

    /**
     * 获取当前配置快照
     */
    public function getConfigSnapshot():Object {
        return {
            dfa: {
                defaultTimeout: InputCommandRuntimeConfigLoader.dfaDefaultTimeout,
                defaultFrameWindow: InputCommandRuntimeConfigLoader.dfaDefaultFrameWindow,
                timeoutBase: InputCommandRuntimeConfigLoader.dfaTimeoutBase,
                timeoutFactor: InputCommandRuntimeConfigLoader.dfaTimeoutFactor
            },
            historyBuffer: {
                eventCapacity: InputCommandRuntimeConfigLoader.historyEventCapacity,
                frameCapacity: InputCommandRuntimeConfigLoader.historyFrameCapacity
            },
            sampler: {
                doubleTapWindow: InputCommandRuntimeConfigLoader.samplerDoubleTapWindow
            },
            buffer: {
                tolerance: InputCommandRuntimeConfigLoader.bufferTolerance
            },
            moduleOverrides: InputCommandRuntimeConfigLoader.moduleOverrides
        };
    }

    /**
     * 获取指定模组的超时值（考虑覆盖配置）
     */
    public static function getTimeoutForModule(moduleId:String):Number {
        var overrides:Object = InputCommandRuntimeConfigLoader.moduleOverrides[moduleId];
        if (overrides != undefined && overrides.DefaultTimeout != undefined) {
            return Number(overrides.DefaultTimeout);
        }
        return InputCommandRuntimeConfigLoader.dfaDefaultTimeout;
    }

    /**
     * 是否已加载
     */
    public static function isConfigLoaded():Boolean {
        return InputCommandRuntimeConfigLoader._loaded;
    }
}
