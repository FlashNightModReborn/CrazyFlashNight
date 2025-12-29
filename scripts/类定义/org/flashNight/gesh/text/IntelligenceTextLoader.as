import org.flashNight.gesh.path.PathManager;

/**
 * 情报文本异步加载器
 * 用于按需加载情报信息的文本内容，实现内存优化
 *
 * 使用方法:
 * IntelligenceTextLoader.loadText("资料_1.txt", function(text:String) {
 *     // 使用加载的文本
 * });
 */
class org.flashNight.gesh.text.IntelligenceTextLoader {

    // 情报文本文件的固定路径前缀和后缀
    private static var PATH_PREFIX:String = "data/intelligence/";
    private static var FILE_SUFFIX:String = ".txt";

    // 文本缓存，使用文件名作为key
    private static var cache:Object = {};

    // 缓存大小限制
    private static var MAX_CACHE_SIZE:Number = 20;

    // 缓存访问顺序记录（用于LRU淘汰）
    private static var accessOrder:Array = [];

    /**
     * 加载文本文件
     * @param textId 文本ID，如 "资料_1"（不含路径和后缀）
     * @param onComplete 加载完成回调，参数为文本内容
     * @param onError 可选，加载失败回调
     */
    public static function loadText(textId:String, onComplete:Function, onError:Function):Void {
        // 检查缓存（使用textId作为key）
        if (cache[textId] != undefined) {
            // 更新访问顺序
            updateAccessOrder(textId);
            // 直接返回缓存内容
            if (onComplete != null) {
                onComplete(cache[textId]);
            }
            return;
        }

        // 初始化路径管理器
        PathManager.initialize();

        // 拼接完整相对路径: data/intelligence/{textId}.txt
        var relativePath:String = PATH_PREFIX + textId + FILE_SUFFIX;

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
            // 兜底处理：空文件或加载失败时返回空字符串
            if (data == undefined || data == null) {
                data = "";
                trace("[IntelligenceTextLoader] 文件为空或加载失败，使用空字符串: " + fullPath);
            }
            // 存入缓存（使用textId作为key）
            IntelligenceTextLoader.addToCache(textId, data);
            // 回调
            if (onComplete != null) {
                onComplete(data);
            }
        };

        loader.load(fullPath);
    }

    /**
     * 添加到缓存，并执行LRU淘汰
     */
    private static function addToCache(path:String, text:String):Void {
        // 如果缓存已满，淘汰最久未访问的
        if (accessOrder.length >= MAX_CACHE_SIZE) {
            var oldestPath:String = String(accessOrder.shift());
            delete cache[oldestPath];
        }

        // 添加新内容
        cache[path] = text;
        accessOrder.push(path);
    }

    /**
     * 更新访问顺序（移到最后）
     */
    private static function updateAccessOrder(path:String):Void {
        // 从当前位置移除
        for (var i:Number = 0; i < accessOrder.length; i++) {
            if (accessOrder[i] == path) {
                accessOrder.splice(i, 1);
                break;
            }
        }
        // 添加到末尾
        accessOrder.push(path);
    }

    /**
     * 预加载多个文本（可选优化）
     * @param textIds 文本ID数组
     * @param onComplete 全部加载完成回调
     */
    public static function preloadTexts(textIds:Array, onComplete:Function):Void {
        var loaded:Number = 0;
        var total:Number = textIds.length;

        if (total == 0) {
            if (onComplete != null) onComplete();
            return;
        }

        for (var i:Number = 0; i < textIds.length; i++) {
            loadText(textIds[i], function(text:String):Void {
                loaded++;
                if (loaded >= total && onComplete != null) {
                    onComplete();
                }
            }, function():Void {
                loaded++;
                if (loaded >= total && onComplete != null) {
                    onComplete();
                }
            });
        }
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
        return "缓存条目: " + accessOrder.length + "/" + MAX_CACHE_SIZE;
    }

    /**
     * 从缓存获取（如果存在）
     * @param textId 文本ID
     */
    public static function getFromCache(textId:String):String {
        return cache[textId];
    }

    /**
     * 检查是否已缓存
     * @param textId 文本ID
     */
    public static function isCached(textId:String):Boolean {
        return cache[textId] != undefined;
    }
}
