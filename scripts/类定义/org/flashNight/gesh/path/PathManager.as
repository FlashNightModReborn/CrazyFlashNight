class org.flashNight.gesh.path.PathManager {
    private static var basePath:String = null; // 资源根路径
    private static var isValidEnvironment:Boolean = false; // 是否在 resource 环境中运行

    /**
     * 初始化路径管理器，基于当前运行环境自动设置基础路径。
     */
    public static function initialize():Void {
        var url:String = decodeURL(_url); // 获取当前文件的 URL 并解码中文路径
        trace("当前 URL: " + url);

        // 检查 URL 是否包含 'resources/' 目录
        var resourceIndex:Number = url.indexOf("resources/");
        if (resourceIndex != -1) {
            basePath = url.substring(0, resourceIndex + "resources/".length); // 截断到 resources/ 为止
            isValidEnvironment = true;
            trace("检测到资源目录，基础路径设置为: " + basePath);
        } else {
            basePath = null;
            isValidEnvironment = false;
            trace("未检测到资源目录，路径管理器未启用。");
        }
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
     * 解析相对路径到完整路径。
     * @param relativePath String 相对路径。
     * @return String 完整路径，如果环境无效，返回 null。
     */
    public static function resolvePath(relativePath:String):String {
        if (!isEnvironmentValid()) {
            trace("当前不在资源环境中，无法解析路径: " + relativePath);
            return null;
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
            trace("当前不在资源环境中，无法获取 scripts/类定义/ 路径。");
            return null;
        }
        // 假设 scripts/类定义/ 在 resources/ 下
        return basePath + "scripts/类定义/";
    }
}
