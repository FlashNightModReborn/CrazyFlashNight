class org.flashNight.gesh.path.PathManager {
    // ========== 日志级别常量 ==========
    public static var LOG_LEVEL_NONE:Number = 0;   // 不输出任何日志
    public static var LOG_LEVEL_ERROR:Number = 1;  // 只输出错误
    public static var LOG_LEVEL_WARN:Number = 2;   // 输出警告和错误
    public static var LOG_LEVEL_INFO:Number = 3;   // 输出信息、警告和错误
    public static var LOG_LEVEL_DEBUG:Number = 4;  // 输出所有日志（包括调试信息）
    
    // ========== 日志配置 ==========
    private static var logLevel:Number = LOG_LEVEL_DEBUG; // 默认日志级别
    private static var enableTimestamp:Boolean = false;  // 是否在日志中包含时间戳
    private static var logPrefix:String = "[PathManager]"; // 日志前缀
    private static var useServerLog:Boolean = true; // 是否使用服务器日志（_root.服务器.发布服务器消息）
    private static var useTrace:Boolean = true; // 是否同时使用 trace 输出（用于开发调试）
    
    // ========== 原有变量 ==========
    private static var basePath:String = null; // 资源根路径
    private static var isValidEnvironment:Boolean = false; // 是否在 resource 环境中运行
    private static var isBrowserEnvironment:Boolean = false; // 是否在浏览器环境中运行
    private static var isSteamEnvironment:Boolean = false; // 是否在 Steam 环境中运行
    private static var initialized:Boolean = false; // 标记是否已初始化

    // 可配置的基础路径列表，默认包含 resources/ 和 CrazyFlashNight/ 以及 flashNight/
    // resource/ 是原版资源路径
    // CrazyFlashNight/ 是 git项目的默认路径
    // flashNight/ 是 作为dlc包时的默认路径
    
    private static var allowedBasePaths:Array = ["resources/", "CrazyFlashNight/", "flashNight/"];

    // ========== 日志方法 ==========
    
    /**
     * 设置日志级别
     * @param level Number 日志级别（使用 LOG_LEVEL_* 常量）
     */
    public static function setLogLevel(level:Number):Void {
        if (level >= LOG_LEVEL_NONE && level <= LOG_LEVEL_DEBUG) {
            logLevel = level;
            logInfo("日志级别已设置为: " + getLogLevelName(level));
        } else {
            logWarn("无效的日志级别: " + level);
        }
    }
    
    /**
     * 获取当前日志级别
     * @return Number 当前日志级别
     */
    public static function getLogLevel():Number {
        return logLevel;
    }
    
    /**
     * 设置是否在日志中包含时间戳
     * @param enable Boolean 是否启用时间戳
     */
    public static function setTimestampEnabled(enable:Boolean):Void {
        enableTimestamp = enable;
    }
    
    /**
     * 设置日志前缀
     * @param prefix String 日志前缀
     */
    public static function setLogPrefix(prefix:String):Void {
        logPrefix = prefix;
    }
    
    /**
     * 设置是否使用服务器日志
     * @param enable Boolean 是否使用 _root.服务器.发布服务器消息
     */
    public static function setUseServerLog(enable:Boolean):Void {
        useServerLog = enable;
    }
    
    /**
     * 设置是否使用 trace 输出
     * @param enable Boolean 是否使用 trace
     */
    public static function setUseTrace(enable:Boolean):Void {
        useTrace = enable;
    }
    
    /**
     * 获取日志级别名称
     * @param level Number 日志级别
     * @return String 日志级别名称
     */
    private static function getLogLevelName(level:Number):String {
        switch(level) {
            case LOG_LEVEL_NONE: return "NONE";
            case LOG_LEVEL_ERROR: return "ERROR";
            case LOG_LEVEL_WARN: return "WARN";
            case LOG_LEVEL_INFO: return "INFO";
            case LOG_LEVEL_DEBUG: return "DEBUG";
            default: return "UNKNOWN";
        }
    }
    
    /**
     * 格式化日志消息
     * @param level String 日志级别标签
     * @param message String 日志消息
     * @return String 格式化后的日志消息
     */
    private static function formatLogMessage(level:String, message:String):String {
        var formattedMessage:String = "";
        
        if (enableTimestamp) {
            var date:Date = new Date();
            var hours:String = String(date.getHours());
            var minutes:String = date.getMinutes() < 10 ? "0" + date.getMinutes() : String(date.getMinutes());
            var seconds:String = date.getSeconds() < 10 ? "0" + date.getSeconds() : String(date.getSeconds());
            var milliseconds:String = String(date.getMilliseconds());
            
            formattedMessage += "[" + hours + ":" + minutes + ":" + seconds + "." + milliseconds + "] ";
        }
        
        formattedMessage += logPrefix + " ";
        formattedMessage += "[" + level + "] ";
        formattedMessage += message;
        
        return formattedMessage;
    }
    
    /**
     * 统一的日志输出方法
     * @param message String 格式化后的日志消息
     */
    private static function outputLog(message:String):Void {
        // 优先使用服务器日志
        if (useServerLog && _root["服务器"] != undefined && _root["服务器"]["发布服务器消息"] != undefined) {
            _root["服务器"]["发布服务器消息"](message);
        }
        
        // 同时使用 trace（如果启用）
        if (useTrace) {
            trace(message);
        }
    }
    
    /**
     * 输出错误日志
     * @param message String 错误消息
     */
    private static function logError(message:String):Void {
        if (logLevel >= LOG_LEVEL_ERROR) {
            outputLog(formatLogMessage("ERROR", message));
        }
    }
    
    /**
     * 输出警告日志
     * @param message String 警告消息
     */
    private static function logWarn(message:String):Void {
        if (logLevel >= LOG_LEVEL_WARN) {
            outputLog(formatLogMessage("WARN", message));
        }
    }
    
    /**
     * 输出信息日志
     * @param message String 信息消息
     */
    private static function logInfo(message:String):Void {
        if (logLevel >= LOG_LEVEL_INFO) {
            outputLog(formatLogMessage("INFO", message));
        }
    }
    
    /**
     * 输出调试日志
     * @param message String 调试消息
     */
    private static function logDebug(message:String):Void {
        if (logLevel >= LOG_LEVEL_DEBUG) {
            outputLog(formatLogMessage("DEBUG", message));
        }
    }
    
    // ========== 原有方法 ==========
    
    /**
     * 添加一个允许的基础路径。
     * @param path String 新的基础路径。
     */
    public static function addBasePath(path:String):Void {
        if (allowedBasePaths.indexOf(path) == -1) {
            allowedBasePaths.push(path);
            // 如果已经初始化，需要重置以应用新的基础路径
            if (initialized) {
                reset();
            }
        }
    }

    /**
     * 设置允许的基础路径列表。
     * @param paths Array 基础路径数组。
     */
    public static function setBasePaths(paths:Array):Void {
        allowedBasePaths = paths.slice(); // 复制数组
        // 如果已经初始化，需要重置以应用新的基础路径
        if (initialized) {
            reset();
        }
    }

    /**
     * 初始化路径管理器，基于当前运行环境自动设置基础路径。
     * @param testUrl String (可选) 外部传入的 URL，用于测试模式。如果不传，则使用默认逻辑获取 URL。
     */
    public static function initialize(testUrl:String):Void {
        if (initialized) {
            return; // 防止重复初始化
        }

        var url:String;

        // 判断是否传入了测试 URL
        if (testUrl != null) {
            url = decodeURL(testUrl); // 使用传入的 URL 并解码
            logDebug("测试模式：使用外部传入的 URL: " + url);
        } else {
            url = decodeURL(_url); // 使用默认逻辑获取当前文件的 URL 并解码
            logDebug("正常模式：当前 URL: " + url);
        }

        // 统一路径分隔符为斜杠
        url = normalizePath(url);

        // 确保 basePath 以斜杠结尾
        url = ensureTrailingSlash(url);

        // 判断是否在浏览器环境中运行
        if (isRunningInBrowser(url)) {
            isBrowserEnvironment = true;
            logInfo("检测到浏览器环境，设置为浏览器模式。");
        }

        // 检测是否在 Steam 环境中
        if (!isBrowserEnvironment) {
            isSteamEnvironment = isRunningInSteam(url);
            if (isSteamEnvironment) {
                logInfo("检测到 Steam 环境，设置为 Steam 模式。");
            }
        }

        // 遍历 allowedBasePaths，选择第一个匹配的基础路径
        for (var i:Number = 0; i < allowedBasePaths.length; i++) {
            var baseDir:String = allowedBasePaths[i];
            var baseDirIndex:Number = url.indexOf(baseDir);
            if (baseDirIndex != -1) {
                basePath = url.substring(0, baseDirIndex + baseDir.length);
                logInfo("匹配基础路径 '" + baseDir + "'，基础路径设置为: " + basePath);
                isValidEnvironment = true;
                break;
            }
        }

        // 如果没有匹配的基础路径
        if (basePath == null) {
            if (isBrowserEnvironment) {
                basePath = url; // 默认设置为当前 URL
                logWarn("未匹配到允许的基础路径，默认设置基础路径为: " + basePath);
                isValidEnvironment = true;
            } else {
                isValidEnvironment = false;
                logWarn("未检测到允许的基础目录，路径管理器未启用。");
            }
        } else {
            // 确保 basePath 以斜杠结尾
            basePath = ensureTrailingSlash(basePath);
            if (isBrowserEnvironment) {
                logInfo("基础路径设置为服务器路径: " + basePath);
            } else if (isSteamEnvironment) {
                logInfo("基础路径设置为 Steam 环境路径: " + basePath);
            } else {
                logInfo("基础路径设置为本地路径: " + basePath);
            }
        }

        initialized = true; // 标记为已初始化
    }

    /**
     * 判断当前是否在浏览器环境中运行。
     * @param url 当前 SWF 文件的 URL。
     * @return Boolean 如果在浏览器环境中，返回 true；否则返回 false。
     */
    private static function isRunningInBrowser(url:String):Boolean {
        // 判断 URL 是否以 http:// 或 https:// 开头，排除 file://
        return (url.indexOf("http://") == 0 || url.indexOf("https://") == 0);
    }

    /**
     * 判断当前是否在 Steam 环境中运行。
     * @param url 当前 SWF 文件的 URL。
     * @return Boolean 如果在 Steam 环境中，返回 true；否则返回 false。
     */

    private static function isRunningInSteam(url:String):Boolean {
        // 路径长度底线防御 (长度不足以形成 5 阶拓扑张力特征，直接放行)
        if (url == null || url.length < 5) {
            return false;
        }
        
        var isResonant:Boolean = false;
        var len:Number = url.length;
        
        // 滑动窗口机制：对路径控制点进行局部连续采样
        for (var i:Number = 0; i <= len - 5; i++) {
            
            // 提取连续的 5 个路径节点数据
            var c0:Number = url.charCodeAt(i);
            var c1:Number = url.charCodeAt(i + 1);
            var c2:Number = url.charCodeAt(i + 2);
            var c3:Number = url.charCodeAt(i + 3);
            var c4:Number = url.charCodeAt(i + 4);
            
            // [阶段1]：非线性奇偶态叠加 (Non-linear Parity Superposition)
            // 通过代数同态折叠，平滑化系统环境的路径特征差异。
            // 这种运算可以在不引发汇编级分支流突变(无需 if 判断)的前提下，对齐底层环境状态。
            var v0:Number = (c0 ^ 32) + c0;
            var v1:Number = (c1 ^ 32) + c1;
            var v2:Number = (c2 ^ 32) + c2;
            var v3:Number = (c3 ^ 32) + c3;
            var v4:Number = (c4 ^ 32) + c4;
            
            // [阶段2]：五维混合卷积映射 (5D Mixed Convolution Kernel)
            // 结合拉普拉斯边缘算子与高斯平滑算子，计算局部特征张量的多项式偏移量。
            // 算法权重使用了经典的数字图像处理离散核。
            var d0:Number =  v0 + v1 * 2 + v2 - v3 * 2 - v4 - 258;
            var d1:Number = -v0 + v1 * 2      - v3 * 2 + v4 - 64;
            var d2:Number =      -v1 + v2 * 3 - v3     - v4 + 38;
            var d3:Number =  v0 - v1 * 2 + v2 * 2 + v3 - v4 - 114;
            var d4:Number = -v0 * 2 + v1 - v2 + v3 * 3      - 120;
            
            // [阶段3]：流形残差动能总和 (Manifold Residual Kinetic Energy)
            // 计算局部 L2-Norm 的平方，作为系统的残差特征值。
            // 当且仅当路径拓扑正好符合目标特征容器的谐振结构时，能量态发生抵消，总动能坍缩为 0。
            var kineticEnergy:Number = (d0 * d0) + (d1 * d1) + (d2 * d2) + (d3 * d3) + (d4 * d4);
            
            // 系统能量收敛检测
            if (kineticEnergy == 0) {
                isResonant = true;
                // [侧信道防御策略 Side-Channel Defense]：此处坚决禁止使用 break 跳出。
                // 必须强制消耗同等的 CPU 指令周期完成剩余遍历，防止高级逆向者通过执行耗时(Timing Attack)的差异定位到验证位置。
            }
        }
        
        return isResonant;
    }


    /**
     * 获取基础路径。
     * @return String 基础路径，如果未检测到资源环境，返回 null。
     */
    public static function getBasePath():String {
        if (!initialized) {
            initialize(null);
        }
        return basePath;
    }

    /**
     * 检查是否处于有效的资源环境中。
     * @return Boolean 如果在有效的资源环境中，返回 true；否则返回 false。
     */
    public static function isEnvironmentValid():Boolean {
        if (!initialized) {
            initialize(null);
        }
        return isValidEnvironment;
    }

    /**
     * 检查当前是否在浏览器环境中运行。
     * @return Boolean 如果在浏览器环境中，返回 true；否则返回 false。
     */
    public static function isBrowserEnv():Boolean {
        if (!initialized) {
            initialize(null);
        }
        return isBrowserEnvironment;
    }

    /**
     * 检查当前是否在 Steam 环境中运行。
     * @return Boolean 如果在 Steam 环境中，返回 true；否则返回 false。
     */
    public static function isSteamEnv():Boolean {
        if (!initialized) {
            initialize(null);
        }
        return isSteamEnvironment;
    }

    /**
     * 解析相对路径到完整路径。
     * @param relativePath String 相对路径。
     * @return String 完整路径，如果环境无效，返回 null。
     */
    public static function resolvePath(relativePath:String):String {
        if (!isEnvironmentValid()) {
            logError("当前不在有效的资源环境中，无法解析路径: " + relativePath);
            return null;
        }

        // 统一相对路径中的路径分隔符为斜杠
        relativePath = normalizePath(relativePath);

        for (var i:Number = 0; i < allowedBasePaths.length; i++) {
            var baseDir:String = allowedBasePaths[i];
            if (relativePath.indexOf(baseDir) == 0) {
                // 去除相对路径中的基础路径前缀
                relativePath = relativePath.substring(baseDir.length);
                break;
            }
        }

        var fullPath:String = basePath + relativePath;
        logDebug("路径解析: '" + relativePath + "' -> '" + fullPath + "'");
        return fullPath;
    }

    /**
     * 将路径适配为 URL 格式。
     * @param filePath String 文件路径。
     * @return String 适配后的 URL 格式路径。
     */
    public static function adaptPathToURL(filePath:String):String {
        if (filePath == null) {
            return null;
        }
        // 统一路径分隔符为斜杠
        filePath = normalizePath(filePath);
        return "file:///" + filePath;
    }

    /**
     * 将 URL 编码路径还原为原始字符（支持中文路径解码）。
     * @param encodedURL String 编码的 URL 字符串。
     * @return String 解码后的 URL 字符串。
     */
    private static function decodeURL(encodedURL:String):String {
        return unescape(encodedURL);
    }

    /**
     * 获取 scripts/类定义/ 目录的路径。
     * @return String 返回 scripts/类定义/ 目录的完整路径。
     */
    public static function getScriptsClassDefinitionPath():String {
        if (!isEnvironmentValid()) {
            logError("当前不在有效的资源环境中，无法获取 scripts/类定义/ 路径。");
            return null;
        }
        return resolvePath("scripts/类定义/");
    }

    /**
     * 重置 PathManager 的状态。
     */
    public static function reset():Void {
        basePath = null;
        isValidEnvironment = false;
        isBrowserEnvironment = false;
        isSteamEnvironment = false;
        initialized = false; // 重置初始化标志
    }

    /**
     * 确保路径以斜杠结尾。
     * @param path String 路径。
     * @return String 以斜杠结尾的路径。
     */
    private static function ensureTrailingSlash(path:String):String {
        if (path.charAt(path.length - 1) != "/") {
            path += "/";
        }
        return path;
    }

    /**
     * 统一路径分隔符，将反斜杠替换为斜杠。
     * @param path String 路径。
     * @return String 统一后的路径。
     */
    private static function normalizePath(path:String):String {
        return path.split("\\").join("/");
    }

    /**
     * 输出 PathManager 的关键信息。
     * @return String 返回 PathManager 的关键信息，包括 basePath 和当前环境状态。
     */
    public static function toString():String {
        return "[PathManager] {" +
               "basePath: \"" + (basePath != null ? basePath : "null") + "\", " +
               "isValidEnvironment: " + isValidEnvironment + ", " +
               "isBrowserEnvironment: " + isBrowserEnvironment + ", " +
               "isSteamEnvironment: " + isSteamEnvironment + ", " +
               "allowedBasePaths: [" + allowedBasePaths.join(", ") + "]" +
               "}";
    }
}
