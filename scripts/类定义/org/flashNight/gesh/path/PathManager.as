class org.flashNight.gesh.path.PathManager {
    private static var basePath:String = null; // 资源根路径
    private static var isValidEnvironment:Boolean = false; // 是否在 resource 环境中运行
    private static var isBrowserEnvironment:Boolean = false; // 是否在浏览器环境中运行
    private static var initialized:Boolean = false; // 标记是否已初始化

    // 可配置的基础路径列表，默认包含 resources/ 和 CrazyFlashNight/
    private static var allowedBasePaths:Array = ["resources/", "CrazyFlashNight/"];

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
            trace("测试模式：使用外部传入的 URL: " + url);
        } else {
            url = decodeURL(_url); // 使用默认逻辑获取当前文件的 URL 并解码
            trace("正常模式：当前 URL: " + url);
        }

        // 统一路径分隔符为斜杠
        url = normalizePath(url);

        // 确保 basePath 以斜杠结尾
        url = ensureTrailingSlash(url);

        // 判断是否在浏览器环境中运行
        if (isRunningInBrowser(url)) {
            isBrowserEnvironment = true;
            trace("检测到浏览器环境，设置为浏览器模式。");
        }

        // 遍历 allowedBasePaths，选择第一个匹配的基础路径
        for (var i:Number = 0; i < allowedBasePaths.length; i++) {
            var baseDir:String = allowedBasePaths[i];
            var baseDirIndex:Number = url.indexOf(baseDir);
            if (baseDirIndex != -1) {
                basePath = url.substring(0, baseDirIndex + baseDir.length);
                trace("匹配基础路径 '" + baseDir + "'，基础路径设置为: " + basePath);
                isValidEnvironment = true;
                break;
            }
        }

        // 如果没有匹配的基础路径
        if (basePath == null) {
            if (isBrowserEnvironment) {
                basePath = url; // 默认设置为当前 URL
                trace("未匹配到允许的基础路径，默认设置基础路径为: " + basePath);
                isValidEnvironment = true;
            } else {
                isValidEnvironment = false;
                trace("未检测到允许的基础目录，路径管理器未启用。");
            }
        } else {
            // 确保 basePath 以斜杠结尾
            basePath = ensureTrailingSlash(basePath);
            if (isBrowserEnvironment) {
                trace("基础路径设置为服务器路径: " + basePath);
            } else {
                trace("基础路径设置为本地路径: " + basePath);
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
     * 解析相对路径到完整路径。
     * @param relativePath String 相对路径。
     * @return String 完整路径，如果环境无效，返回 null。
     */
    public static function resolvePath(relativePath:String):String {
        if (!isEnvironmentValid()) {
            trace("当前不在有效的资源环境中，无法解析路径: " + relativePath);
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

        return basePath + relativePath;
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
            trace("当前不在有效的资源环境中，无法获取 scripts/类定义/ 路径。");
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
               "allowedBasePaths: [" + allowedBasePaths.join(", ") + "]" +
               "}";
    }
}
