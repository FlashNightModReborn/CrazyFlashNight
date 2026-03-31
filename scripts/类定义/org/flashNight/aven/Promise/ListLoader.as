/**
 * org.flashNight.aven.Promise.ListLoader
 *
 * 通用子文件并行加载编排器。
 *
 * 设计原则：
 *   - ListLoader 只管"子文件加载 + 合并"，不碰 list.xml 的读取和缓存
 *   - list.xml 由领域 loader 的 super.load() 负责（保留 BaseXMLLoader 实例缓存）
 *   - 领域 loader 提取 entries 后调用 ListLoader.loadChildren(config)
 *
 * 并发控制：
 *   config.concurrency 控制每批并行请求数，默认 4。
 *   Flash Player 8 约 8 条并发连接，保守默认避免打满。
 *   _chainBatches 按批链式 Promise.all，每批完成后启动下一批。
 *
 * 合并策略：
 *   mergeFn(accumulator, childData, index, entry) → accumulator
 *   提供 3 个工厂方法覆盖常见模式：concatField / dictMerge / keyedMerge。
 *   复杂场景（NpcDialogueLoader、StageInfoLoader）传自定义函数。
 */
import org.flashNight.aven.Promise.Promise;
import org.flashNight.aven.Promise.LoaderPromise;

class org.flashNight.aven.Promise.ListLoader {

    /** 默认并发窗口大小 */
    private static var DEFAULT_CONCURRENCY:Number = 4;

    /**
     * 并行加载子文件并合并结果。
     *
     * @param config 配置对象：
     *   entries:Array         — 子文件条目列表（已归一化为 Array）
     *   basePath:String       — 子文件基础路径（如 "data/items/"）
     *   childType:String      — "xml"（默认）或 "json"
     *   parseType:String      — JSON 解析器类型（仅 childType=="json" 时生效）
     *   concurrency:Number    — 并发窗口大小（默认 4）
     *   pathBuilder:Function  — 可选，function(basePath:String, entry:String):String
     *                           默认：basePath + entry
     *   mergeFn:Function      — function(accumulator, childData, index, entry):Object
     *   initialValue:Object   — 累加器初始值（[] 或 {}）
     * @return Promise 合并后的结果
     */
    public static function loadChildren(config:Object):Promise {
        var entries:Array = config.entries;
        if (entries == null || entries.length == 0) {
            return Promise.resolve(config.initialValue);
        }

        var basePath:String = config.basePath;
        var childType:String = config.childType || "xml";
        var parseType:String = config.parseType;
        var concurrency:Number = config.concurrency;
        if (concurrency == undefined || concurrency == null || concurrency < 1) {
            concurrency = DEFAULT_CONCURRENCY;
        }
        var pathBuilder:Function = config.pathBuilder;
        var mergeFn:Function = config.mergeFn;
        var acc:Object = config.initialValue;

        // 选择加载函数
        var loaderFn:Function;
        if (childType == "json") {
            loaderFn = ListLoader._makeJSONLoader(parseType);
        } else {
            loaderFn = LoaderPromise.loadXML;
        }

        return ListLoader._chainBatches(
            entries, basePath, concurrency,
            loaderFn, mergeFn, acc,
            pathBuilder, 0
        );
    }

    /**
     * 标量→数组归一化。XMLParser 对单元素返回标量，多元素返回 Array。
     * 领域 loader 提取 data[tagName] 后调用此方法归一化。
     *
     * @param value XMLParser 返回的值（可能是 String/Object 或 Array）
     * @return Array 始终返回数组
     */
    public static function normalizeToArray(value:Object):Array {
        if (value == null || value == undefined) {
            return [];
        }
        if (value instanceof Array) {
            // 用 untyped 中间变量绕过 Flash CS6 的 Object→Array 类型检查。
            // AS2 的 Array(x) 是构造函数调用会包装，不能用于类型转换。
            var asArr = value;
            return asArr;
        }
        return [value];
    }

    // ================================================================
    // 预定义合并策略工厂
    // ================================================================

    /**
     * 提取子数据的指定字段并 concat 到数组。
     * 处理字段值为单个 Object 或 Array 两种情况（EquipModListLoader 边界）。
     *
     * @param fieldName 子数据中的字段名（如 "item"、"mod"、"tasks"）
     * @return Function mergeFn(acc, childData, index, entry):Array
     */
    public static function concatField(fieldName:String):Function {
        return function(acc:Object, childData:Object, index:Number, entry:String):Object {
            var field:Object = childData[fieldName];
            if (field == null || field == undefined) {
                return acc;
            }
            var arr = acc;
            if (field instanceof Array) {
                return arr.concat(field);
            }
            // 单值：push 到数组
            arr.push(field);
            return acc;
        };
    }

    /**
     * 将子数据的所有 key 合并到累加器对象（浅合并）。
     *
     * @return Function mergeFn(acc, childData, index, entry):Object
     */
    public static function dictMerge():Function {
        return function(acc:Object, childData:Object, index:Number, entry:String):Object {
            for (var key:String in childData) {
                acc[key] = childData[key];
            }
            return acc;
        };
    }

    /**
     * 以条目名（去扩展名）为 key 存储子数据。
     *
     * @return Function mergeFn(acc, childData, index, entry):Object
     */
    public static function keyedMerge():Function {
        return function(acc:Object, childData:Object, index:Number, entry:String):Object {
            var key:String = entry;
            var dotIdx:Number = entry.lastIndexOf(".");
            if (dotIdx > 0) {
                key = entry.substring(0, dotIdx);
            }
            acc[key] = childData;
            return acc;
        };
    }

    // ================================================================
    // 内部实现
    // ================================================================

    /**
     * 创建 JSON 加载函数（绑定 parseType）。
     * 分离为静态方法以避免 IIFE（AS2 约束）。
     */
    private static function _makeJSONLoader(parseType:String):Function {
        return function(relativePath:String):Promise {
            return LoaderPromise.loadJSON(relativePath, parseType);
        };
    }

    /**
     * 按批链式加载。每批 batchSize 个文件并行，全部完成后合并结果并启动下一批。
     *
     * @param entries     子文件条目数组
     * @param basePath    基础路径
     * @param batchSize   每批大小
     * @param loaderFn    加载函数 function(path:String):Promise
     * @param mergeFn     合并函数
     * @param acc         当前累加器
     * @param pathBuilder 路径构建函数（可为 null）
     * @param offset      当前批起始索引
     * @return Promise 最终累加器
     */
    private static function _chainBatches(
        entries:Array, basePath:String, batchSize:Number,
        loaderFn:Function, mergeFn:Function, acc:Object,
        pathBuilder:Function, offset:Number
    ):Promise {
        if (offset >= entries.length) {
            return Promise.resolve(acc);
        }

        var end:Number = offset + batchSize;
        if (end > entries.length) {
            end = entries.length;
        }

        var batch:Array = [];
        var i:Number = offset;
        while (i < end) {
            var childPath:String;
            if (pathBuilder != null) {
                childPath = pathBuilder(basePath, entries[i]);
            } else {
                childPath = basePath + entries[i];
            }
            batch.push(loaderFn(childPath));
            i++;
        }

        // 捕获当前批的 offset 和 end 供合并回调使用
        return Promise.all(batch).then(
            ListLoader._makeBatchMerger(entries, basePath, batchSize,
                loaderFn, mergeFn, acc, pathBuilder, offset, end)
        );
    }

    /**
     * 创建单批合并+继续链式的回调函数。
     * 分离为静态方法以避免 IIFE。
     */
    private static function _makeBatchMerger(
        entries:Array, basePath:String, batchSize:Number,
        loaderFn:Function, mergeFn:Function, acc:Object,
        pathBuilder:Function, offset:Number, end:Number
    ):Function {
        return function(results:Object):Object {
            var arr = results;
            var j:Number = 0;
            while (j < arr.length) {
                acc = mergeFn(acc, arr[j], offset + j, entries[offset + j]);
                j++;
            }
            return ListLoader._chainBatches(
                entries, basePath, batchSize,
                loaderFn, mergeFn, acc,
                pathBuilder, end
            );
        };
    }
}
