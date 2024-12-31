class org.flashNight.gesh.path.PathManager {
    private static var basePath:String = null; // 资源根路径
    private static var isValidEnvironment:Boolean = false; // 是否在 resource 环境中运行
    private static var isBrowserEnvironment:Boolean = false; // 是否在浏览器环境中运行

    /**
     * 初始化路径管理器，基于当前运行环境自动设置基础路径。
     * @param testUrl String (可选) 外部传入的 URL，用于测试模式。如果不传，则使用默认逻辑获取 URL。
     */
    public static function initialize(testUrl:String):Void {
        if (basePath != null) {
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

        // 判断是否在浏览器环境中运行
        if (isRunningInBrowser(url)) {
            isBrowserEnvironment = true;
            trace("检测到浏览器环境，设置为浏览器模式。");
            // 设置服务器基础路径，例如 "http://yourserver.com/resources/"
            basePath = "http://yourserver.com/resources/"; // 占位用路径
            // 确保 basePath 以斜杠结尾
            basePath = ensureTrailingSlash(basePath);
            isValidEnvironment = true;
            trace("基础路径设置为服务器路径: " + basePath);
        } else {
            // 检查 URL 是否包含 'resources/' 目录
            var resourceIndex:Number = url.indexOf("resources/");
            if (resourceIndex != -1) {
                basePath = url.substring(0, resourceIndex + "resources/".length); // 截断到 resources/ 为止
                basePath = ensureTrailingSlash(basePath);
                isValidEnvironment = true;
                trace("检测到资源目录，基础路径设置为: " + basePath);
            } else {
                basePath = null;
                isValidEnvironment = false;
                trace("未检测到资源目录，路径管理器未启用。");
            }
        }
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
        if (basePath == null) {
            initialize();
        }
        return basePath;
    }

    /**
     * 检查是否处于有效的资源环境中。
     * @return Boolean 如果在有效的资源环境中，返回 true；否则返回 false。
     */
    public static function isEnvironmentValid():Boolean {
        if (basePath == null) {
            initialize();
        }
        return isValidEnvironment;
    }

    /**
     * 检查当前是否在浏览器环境中运行。
     * @return Boolean 如果在浏览器环境中，返回 true；否则返回 false。
     */
    public static function isBrowserEnv():Boolean {
        if (basePath == null) {
            initialize();
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

        if (isBrowserEnvironment) {
            return basePath + relativePath;
        } else {
            if (relativePath.indexOf("resources/") == 0) {
                relativePath = relativePath.substring("resources/".length);
            }
            return basePath + relativePath;
        }
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
        return "file:///" + filePath.split("\\").join("/");
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
     * 输出 PathManager 的关键信息。
     * @return String 返回 PathManager 的关键信息，包括 basePath 和当前环境状态。
     */
    public static function toString():String {
        return "[PathManager] {" +
               "basePath: \"" + (basePath != null ? basePath : "null") + "\", " +
               "isValidEnvironment: " + isValidEnvironment + ", " +
               "isBrowserEnvironment: " + isBrowserEnvironment + "}";
    }
}