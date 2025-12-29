import org.flashNight.gesh.path.PathManager;

/**
 * 情报文本异步加载器（V2 - 合并文件版）
 *
 * 每个Item对应一个txt文件，使用 @@@{pageKey}@@@ 分隔符切分多页内容
 * 一次加载整个Item文件，解析后缓存，翻页时直接从缓存取文本
 *
 * 使用方法:
 * IntelligenceTextLoader.loadItemText("资料", function(textMap:Object) {
 *     var page1Text:String = textMap["1"];
 *     var page1_2Text:String = textMap["1_2"];
 * });
 *
 * 或直接获取单页:
 * IntelligenceTextLoader.getPageText("资料", "1", function(text:String) {
 *     // 使用文本
 * });
 */
class org.flashNight.gesh.text.IntelligenceTextLoader {

    // 情报文本文件的固定路径前缀和后缀
    private static var PATH_PREFIX:String = "data/intelligence/";
    private static var FILE_SUFFIX:String = ".txt";

    // 分隔符正则模式 (行首 @@@key@@@)
    private static var DELIMITER_PATTERN:String = "@@@";

    // 文本缓存，使用ItemName作为key，值为 {pageKey: text} 的Object
    private static var cache:Object = {};

    // 缓存大小限制（按Item数量）
    private static var MAX_CACHE_SIZE:Number = 5;

    // 缓存访问顺序记录（用于LRU淘汰）
    private static var accessOrder:Array = [];

    /**
     * 加载整个Item的文本文件并解析
     * @param itemName Item名称（如 "资料"）
     * @param onComplete 加载完成回调，参数为 {pageKey: text} 的Object
     * @param onError 可选，加载失败回调
     */
    public static function loadItemText(itemName:String, onComplete:Function, onError:Function):Void {
        // 检查缓存
        if (cache[itemName] != undefined) {
            // 更新访问顺序
            updateAccessOrder(itemName);
            // 直接返回缓存内容
            if (onComplete != null) {
                onComplete(cache[itemName]);
            }
            return;
        }

        // 初始化路径管理器
        PathManager.initialize();

        // 拼接完整相对路径: data/intelligence/{itemName}.txt
        var relativePath:String = PATH_PREFIX + itemName + FILE_SUFFIX;

        // 解析完整路径
        var fullPath:String = PathManager.resolvePath(relativePath);
        if (fullPath == null) {
            trace("[IntelligenceTextLoader] 路径解析失败: " + relativePath);
            if (onError != null) {
                onError();
            }
            return;
        }

        // 使用LoadVars加载文本
        var loader:LoadVars = new LoadVars();

        loader.onData = function(data:String):Void {
            if (data == undefined || data == null) {
                trace("[IntelligenceTextLoader] 文件加载失败: " + fullPath);
                if (onError != null) {
                    onError();
                }
                return;
            }

            // 解析文本内容
            var textMap:Object = IntelligenceTextLoader.parseContent(data);

            // 存入缓存
            IntelligenceTextLoader.addToCache(itemName, textMap);

            // 回调
            if (onComplete != null) {
                onComplete(textMap);
            }
        };

        loader.load(fullPath);
    }

    /**
     * 获取单页文本（便捷方法）
     * @param itemName Item名称
     * @param pageKey 页键（如 "1", "1_2"）
     * @param onComplete 加载完成回调，参数为文本内容
     * @param onError 可选，加载失败回调
     */
    public static function getPageText(itemName:String, pageKey:String, onComplete:Function, onError:Function):Void {
        loadItemText(itemName, function(textMap:Object):Void {
            var text:String = textMap[pageKey];
            if (text == undefined) {
                text = "";
            }
            if (onComplete != null) {
                onComplete(text);
            }
        }, onError);
    }

    /**
     * 解析文件内容，按分隔符切分为 {pageKey: text}
     * @param content 原始文件内容
     * @return Object {pageKey: text}
     */
    private static function parseContent(content:String):Object {
        var result:Object = {};

        // 统一换行符为 \n
        content = content.split("\r\n").join("\n");
        content = content.split("\r").join("\n");

        // 按行分割
        var lines:Array = content.split("\n");

        var currentKey:String = null;
        var currentLines:Array = [];

        for (var i:Number = 0; i < lines.length; i++) {
            var line:String = lines[i];

            // 检查是否是分隔符行 @@@key@@@
            if (isDelimiterLine(line)) {
                // 保存上一个key的内容
                if (currentKey != null) {
                    result[currentKey] = trimContent(currentLines);
                }

                // 提取新key
                currentKey = extractKey(line);
                currentLines = [];
            } else {
                // 普通内容行
                if (currentKey != null) {
                    currentLines.push(line);
                }
            }
        }

        // 保存最后一个key的内容
        if (currentKey != null) {
            result[currentKey] = trimContent(currentLines);
        }

        return result;
    }

    /**
     * 检查是否是分隔符行
     */
    private static function isDelimiterLine(line:String):Boolean {
        // 去除首尾空白后检查
        var trimmed:String = trim(line);
        if (trimmed.indexOf(DELIMITER_PATTERN) == 0) {
            // 检查是否以 @@@ 结尾
            var lastIndex:Number = trimmed.lastIndexOf(DELIMITER_PATTERN);
            if (lastIndex > 3) {
                return true;
            }
        }
        return false;
    }

    /**
     * 从分隔符行提取key
     */
    private static function extractKey(line:String):String {
        var trimmed:String = trim(line);
        // 去掉首尾的 @@@
        var start:Number = DELIMITER_PATTERN.length;
        var end:Number = trimmed.lastIndexOf(DELIMITER_PATTERN);
        if (end > start) {
            return trimmed.substring(start, end);
        }
        return "";
    }

    /**
     * 将行数组合并为文本，去除首尾空行
     */
    private static function trimContent(lines:Array):String {
        // 去除首部空行
        while (lines.length > 0 && trim(lines[0]) == "") {
            lines.shift();
        }
        // 去除尾部空行
        while (lines.length > 0 && trim(lines[lines.length - 1]) == "") {
            lines.pop();
        }
        return lines.join("\n");
    }

    /**
     * 去除字符串首尾空白
     */
    private static function trim(str:String):String {
        if (str == null || str == undefined) return "";
        // 去除首部空白
        var start:Number = 0;
        while (start < str.length && isWhitespace(str.charAt(start))) {
            start++;
        }
        // 去除尾部空白
        var end:Number = str.length - 1;
        while (end >= start && isWhitespace(str.charAt(end))) {
            end--;
        }
        return str.substring(start, end + 1);
    }

    /**
     * 检查字符是否是空白字符
     */
    private static function isWhitespace(char:String):Boolean {
        return char == " " || char == "\t" || char == "\n" || char == "\r";
    }

    /**
     * 添加到缓存，并执行LRU淘汰
     */
    private static function addToCache(itemName:String, textMap:Object):Void {
        // 如果缓存已满，淘汰最久未访问的
        if (accessOrder.length >= MAX_CACHE_SIZE) {
            var oldestItem:String = String(accessOrder.shift());
            delete cache[oldestItem];
        }

        // 添加新内容
        cache[itemName] = textMap;
        accessOrder.push(itemName);
    }

    /**
     * 更新访问顺序（移到最后）
     */
    private static function updateAccessOrder(itemName:String):Void {
        // 从当前位置移除
        for (var i:Number = 0; i < accessOrder.length; i++) {
            if (accessOrder[i] == itemName) {
                accessOrder.splice(i, 1);
                break;
            }
        }
        // 添加到末尾
        accessOrder.push(itemName);
    }

    /**
     * 清空缓存
     */
    public static function clearCache():Void {
        cache = {};
        accessOrder = [];
    }

    /**
     * 获取缓存状态（调试用）
     */
    public static function getCacheInfo():String {
        return "缓存Item数: " + accessOrder.length + "/" + MAX_CACHE_SIZE;
    }

    /**
     * 检查Item是否已缓存
     * @param itemName Item名称
     */
    public static function isCached(itemName:String):Boolean {
        return cache[itemName] != undefined;
    }

    /**
     * 从缓存直接获取（如果存在）
     * @param itemName Item名称
     * @param pageKey 页键
     * @return 文本内容，未缓存则返回undefined
     */
    public static function getFromCache(itemName:String, pageKey:String):String {
        if (cache[itemName] != undefined) {
            return cache[itemName][pageKey];
        }
        return undefined;
    }
}
