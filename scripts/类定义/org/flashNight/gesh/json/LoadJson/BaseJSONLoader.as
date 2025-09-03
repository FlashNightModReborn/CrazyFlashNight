import org.flashNight.gesh.json.JSONLoader;
import org.flashNight.gesh.path.PathManager;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.json.LoadJson.BaseJSONLoader {
    // 日志输出方法
    private static function log(message:String, level:String):Void {
        var formattedMessage:String = "[BaseJSONLoader] [" + level + "] " + message;
        
        // 优先使用服务器日志
        if (_root["服务器"] != undefined && _root["服务器"]["发布服务器消息"] != undefined) {
            _root["服务器"]["发布服务器消息"](formattedMessage);
        }
        // 同时使用 trace
        trace(formattedMessage);
    }
    
    private static function logError(message:String):Void {
        log(message, "ERROR");
    }
    
    private static function logWarn(message:String):Void {
        log(message, "WARN");
    }
    
    private static function logInfo(message:String):Void {
        log(message, "INFO");
    }
    
    private static function logDebug(message:String):Void {
        log(message, "DEBUG");
    }
    private var data:Object = null;
    private var _isLoading:Boolean = false; // Indicates if data is being loaded
    private var filePath:String;
    private var parseType:String = "JSON"; // JSON, LiteJSON, FastJSON

    /**
     * Constructor to initialize the JSON loader.
     * @param relativePath String The file path relative to the resource directory.
     */
    public function BaseJSONLoader(relativePath:String, _parseType:String) {
        logInfo("初始化 BaseJSONLoader，相对路径: '" + relativePath + "', 解析类型: " + (_parseType || "JSON"));
        
        // Initialize the path manager
        PathManager.initialize();
        logDebug("PathManager 初始化完成");
        
        if (!PathManager.isEnvironmentValid()) {
            logError("未检测到有效的资源环境！BasePath: " + PathManager.getBasePath());
            logError("当前环境: Browser=" + PathManager.isBrowserEnv() + ", Steam=" + PathManager.isSteamEnv());
            return;
        }
        
        logDebug("资源环境有效，BasePath: '" + PathManager.getBasePath() + "'");

        // Resolve the full file path
        this.filePath = PathManager.resolvePath(relativePath);
        if (this.filePath == null) {
            logError("路径解析失败！相对路径: '" + relativePath + "'");
        } else {
            logInfo("路径解析成功: '" + relativePath + "' -> '" + this.filePath + "'");
        }

        this.parseType = _parseType || "JSON";
        logDebug("使用解析器: " + this.parseType);
    }

    /**
     * Loads the JSON file.
     * @param onLoadHandler Function Callback function for successful load, receiving parsed data as a parameter.
     * @param onErrorHandler Function Callback function for load failure.
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this._isLoading) {
            logWarn("数据正在加载中，忽略重复加载请求！文件: '" + this.filePath + "'");
            return;
        }

        if (this.data != null) {
            logDebug("数据已存在于缓存中，直接返回。文件: '" + this.filePath + "'");
            if (onLoadHandler != null) {
                logDebug("调用 onLoadHandler 回调");
                onLoadHandler(this.data);
            }
            return;
        }

        if (this.filePath == null) {
            logError("文件路径为 null，无法加载！");
            if (onErrorHandler != null) {
                logDebug("调用 onErrorHandler 回调 (路径为 null)");
                onErrorHandler("File path is null");
            }
            return;
        }

        this._isLoading = true;
        var self:BaseJSONLoader = this;
        var startTime:Number = getTimer();

        logInfo("开始加载 JSON 文件: '" + this.filePath + "' [解析器: " + this.parseType + "]");
        logDebug("当前时间: " + new Date().toString());

        // Use JSONLoader to load the file
        new JSONLoader(this.filePath, function(parsedData:Object):Void {
            var loadTime:Number = getTimer() - startTime;
            self._isLoading = false;
            self.data = parsedData;
            
            logInfo("JSON 文件加载成功！文件: '" + self.filePath + "'，耗时: " + loadTime + "ms");
            
            if (parsedData != null) {
                logDebug("解析后的数据类型: " + typeof(parsedData));
                
                // 输出数据的基本信息
                var keyCount:Number = 0;
                for (var key:String in parsedData) {
                    keyCount++;
                    if (keyCount <= 3) {
                        logDebug("数据键: '" + key + "' (类型: " + typeof(parsedData[key]) + ")");
                    }
                }
                if (keyCount > 3) {
                    logDebug("总共 " + keyCount + " 个键");
                }
            } else {
                logWarn("解析后的数据为 null");
            }
            
            if (onLoadHandler != null) {
                logDebug("调用 onLoadHandler 回调");
                onLoadHandler(parsedData);
            }
        }, function(errorMessage:String):Void {
            var loadTime:Number = getTimer() - startTime;
            self._isLoading = false;
            
            logError("JSON 文件加载失败！文件: '" + self.filePath + "'，耗时: " + loadTime + "ms");
            logError("错误信息: " + (errorMessage || "未知错误"));
            logError("可能的原因: 1)文件不存在 2)路径错误 3)网络问题 4)JSON格式错误 5)解析器不支持");
            logDebug("使用的解析器: " + self.parseType);
            
            if (onErrorHandler != null) {
                logDebug("调用 onErrorHandler 回调");
                onErrorHandler(errorMessage);
            }
        }, null, this.parseType);
    }

    /**
     * Reloads the JSON file, ignoring cached data.
     * @param onLoadHandler Function Callback function for successful load.
     * @param onErrorHandler Function Callback function for load failure.
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        logInfo("重新加载文件: '" + this.filePath + "'");
        this.data = null; // Clear existing data
        this.load(onLoadHandler, onErrorHandler);
    }

    /**
     * Retrieves the loaded data.
     * @return Object Parsed data object, or null if not loaded.
     */
    public function getData():Object {
        return this.data;
    }

    /**
     * Checks if data has been loaded.
     * @return Boolean True if data is loaded, otherwise false.
     */
    public function isLoaded():Boolean {
        return this.data != null;
    }

    /**
     * Checks if data is currently being loaded.
     * @return Boolean True if loading is in progress, otherwise false.
     */
    public function isLoadingStatus():Boolean {
        return this._isLoading;
    }

    /**
     * Converts the loaded data to a string for debugging or logging.
     * @return String String representation of the loaded data.
     */
    public function toString():String {
        return ObjectUtil.toString(this.getData());
    }
}
