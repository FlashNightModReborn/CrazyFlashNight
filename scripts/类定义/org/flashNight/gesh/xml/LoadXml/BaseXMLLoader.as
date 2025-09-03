import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.path.*;
import org.flashNight.gesh.object.*;

class org.flashNight.gesh.xml.LoadXml.BaseXMLLoader {
    // 日志输出方法
    private static function log(message:String, level:String):Void {
        var formattedMessage:String = "[BaseXMLLoader] [" + level + "] " + message;
        
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
    private var _isLoading:Boolean = false; // 重命名为 _isLoading
    private var filePath:String;

    /**
     * 构造函数，初始化加载器。
     * @param relativePath String 相对于资源目录的文件路径。
     */
    public function BaseXMLLoader(relativePath:String) {
        logInfo("初始化 BaseXMLLoader，相对路径: '" + relativePath + "'");
        
        // 初始化路径管理器
        PathManager.initialize();
        logDebug("PathManager 初始化完成");
        
        if (!PathManager.isEnvironmentValid()) {
            logError("未检测到有效的资源环境！BasePath: " + PathManager.getBasePath());
            logError("当前环境: Browser=" + PathManager.isBrowserEnv() + ", Steam=" + PathManager.isSteamEnv());
            return;
        }
        
        logDebug("资源环境有效，BasePath: '" + PathManager.getBasePath() + "'");

        // 解析完整路径
        this.filePath = PathManager.resolvePath(relativePath);
        if (this.filePath == null) {
            logError("路径解析失败！相对路径: '" + relativePath + "'");
        } else {
            logInfo("路径解析成功: '" + relativePath + "' -> '" + this.filePath + "'");
        }
    }

    /**
     * 加载数据文件。
     * @param onLoadHandler 加载成功后的回调函数，接收解析后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
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
                logDebug("调用 onErrorHandler 回调");
                onErrorHandler();
            }
            return;
        }

        this._isLoading = true;
        var self:BaseXMLLoader = this;
        var startTime:Number = getTimer();

        logInfo("开始加载 XML 文件: '" + this.filePath + "'");
        logDebug("当前时间: " + new Date().toString());

        // 使用 XMLLoader 加载文件
        new XMLLoader(this.filePath, function(parsedData:Object):Void {
            var loadTime:Number = getTimer() - startTime;
            self._isLoading = false;
            self.data = parsedData;
            
            logInfo("XML 文件加载成功！文件: '" + self.filePath + "'，耗时: " + loadTime + "ms");
            
            if (parsedData != null) {
                logDebug("解析后的数据类型: " + typeof(parsedData));
                if (parsedData.firstChild) {
                    logDebug("XML 根节点: " + parsedData.firstChild.nodeName);
                }
            } else {
                logWarn("解析后的数据为 null");
            }
            
            if (onLoadHandler != null) {
                logDebug("调用 onLoadHandler 回调");
                onLoadHandler(parsedData);
            }
        }, function():Void {
            var loadTime:Number = getTimer() - startTime;
            self._isLoading = false;
            
            logError("XML 文件加载失败！文件: '" + self.filePath + "'，耗时: " + loadTime + "ms");
            logError("可能的原因: 1)文件不存在 2)路径错误 3)网络问题 4)XML格式错误");
            
            if (onErrorHandler != null) {
                logDebug("调用 onErrorHandler 回调");
                onErrorHandler();
            }
        });
    }

    /**
     * 重新加载数据文件，忽略已有缓存。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        logInfo("重新加载文件: '" + this.filePath + "'");
        this.data = null; // 清除已有数据
        this.load(onLoadHandler, onErrorHandler);
    }

    /**
     * 获取已加载的数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.data;
    }

    /**
     * 检查数据是否已加载。
     * @return Boolean 如果数据已加载，返回 true；否则返回 false。
     */
    public function isLoaded():Boolean {
        return this.data != null;
    }

    /**
     * 检查是否正在加载。
     * @return Boolean 如果正在加载，返回 true；否则返回 false。
     */
    public function isLoadingStatus():Boolean { // 重命名方法
        return this._isLoading;
    }

    public function toString():String {
        return ObjectUtil.toString(this.getData());
    }
}
