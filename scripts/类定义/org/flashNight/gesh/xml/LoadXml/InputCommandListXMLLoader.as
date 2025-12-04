import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.path.*;
import org.flashNight.gesh.xml.LoadXml.InputCommandSetXMLLoader;

/**
 * InputCommandListXMLLoader - 搓招配置列表加载器
 *
 * 加载 list.xml 并依次加载所有引用的 CommandSet XML 文件。
 * 最终返回一个以 setId 为键的配置对象字典。
 *
 * 注意：XMLLoader 返回的是经 XMLParser.parseXMLNode() 处理后的 Object，
 * 而非原始 XMLNode，因此本类直接处理 Object 结构。
 *
 * 使用方式： 
 *   var loader:InputCommandListXMLLoader = new InputCommandListXMLLoader("data/inputCommand/list.xml");
 *   loader.loadAll(function(configs:Object):Void {
 *       // configs = { barehand: {...}, lightWeapon: {...}, heavyWeapon: {...} }
 *   }, function():Void {
 *       trace("加载失败");
 *   });
 *
 * @author FlashNight
 * @version 2.0
 */
class org.flashNight.gesh.xml.LoadXml.InputCommandListXMLLoader {

    // ========== 日志方法 ==========

    private static function log(message:String, level:String):Void {
        var formattedMessage:String = "[InputCommandListXMLLoader] [" + level + "] " + message;
        if (_root["服务器"] != undefined && _root["服务器"]["发布服务器消息"] != undefined) {
            _root["服务器"]["发布服务器消息"](formattedMessage);
        }
        trace(formattedMessage);
    }

    private static function logError(message:String):Void { log(message, "ERROR"); }
    private static function logWarn(message:String):Void { log(message, "WARN"); }
    private static function logInfo(message:String):Void { log(message, "INFO"); }
    private static function logDebug(message:String):Void { log(message, "DEBUG"); }

    // ========== 实例字段 ==========

    private var _filePath:String;
    private var _isLoading:Boolean = false;
    private var _setList:Array = null;      // [{id, file, label}, ...]
    private var _configs:Object = null;     // {id: config, ...}

    // ========== 构造函数 ==========

    /**
     * 创建 InputCommandListXMLLoader 实例
     * @param relativePath 相对于资源目录的 list.xml 路径
     */
    public function InputCommandListXMLLoader(relativePath:String) {
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
     * 加载 list.xml 并解析 set 列表（不加载具体 set 文件）
     * @param onSuccess 成功回调 function(setList:Array):Void
     * @param onError 失败回调 function():Void
     */
    public function loadList(onSuccess:Function, onError:Function):Void {
        if (this._isLoading) {
            logWarn("正在加载中");
            return;
        }

        if (this._setList != null) {
            logDebug("使用缓存的 set 列表");
            if (onSuccess != null) onSuccess(this._setList);
            return;
        }

        if (this._filePath == null) {
            logError("文件路径为空");
            if (onError != null) onError();
            return;
        }

        this._isLoading = true;
        var self:InputCommandListXMLLoader = this;

        logInfo("加载 list.xml: " + this._filePath);

        new XMLLoader(this._filePath, function(parsedData:Object):Void {
            self._isLoading = false;

            // parsedData 是 XMLParser.parseXMLNode() 返回的 Object
            var setList:Array = self.parseListData(parsedData);
            if (setList != null && setList.length > 0) {
                self._setList = setList;
                logInfo("解析到 " + setList.length + " 个 CommandSet");
                if (onSuccess != null) onSuccess(setList);
            } else {
                logError("list.xml 解析失败或为空");
                if (onError != null) onError();
            }

        }, function():Void {
            self._isLoading = false;
            logError("加载失败: " + self._filePath);
            if (onError != null) onError();
        });
    }

    /**
     * 加载 list.xml 和所有引用的 CommandSet XML
     * @param onSuccess 成功回调 function(configs:Object):Void
     * @param onError 失败回调 function():Void
     */
    public function loadAll(onSuccess:Function, onError:Function):Void {
        var self:InputCommandListXMLLoader = this;

        // 先加载 list
        this.loadList(function(setList:Array):Void {
            // 然后依次加载每个 set
            self.loadSetsSequentially(setList, 0, {}, onSuccess, onError);
        }, onError);
    }

    /**
     * 顺序加载所有 set 文件
     */
    private function loadSetsSequentially(
        setList:Array,
        index:Number,
        configs:Object,
        onSuccess:Function,
        onError:Function
    ):Void {
        // 全部加载完成
        if (index >= setList.length) {
            this._configs = configs;
            logInfo("所有 CommandSet 加载完成");
            if (onSuccess != null) onSuccess(configs);
            return;
        }

        var setInfo:Object = setList[index];
        var self:InputCommandListXMLLoader = this;

        logInfo("加载 CommandSet [" + (index + 1) + "/" + setList.length + "]: " + setInfo.id);

        var loader:InputCommandSetXMLLoader = new InputCommandSetXMLLoader(setInfo.file);
        loader.load(function(config:Object):Void {
            // 成功，存入结果
            configs[setInfo.id] = config;
            // 继续加载下一个
            self.loadSetsSequentially(setList, index + 1, configs, onSuccess, onError);

        }, function():Void {
            // 单个 set 加载失败，记录警告但继续
            logWarn("CommandSet 加载失败: " + setInfo.id + "，继续加载其他 set");
            self.loadSetsSequentially(setList, index + 1, configs, onSuccess, onError);
        });
    }

    // ========== Object 结构解析 ==========

    /**
     * 解析 list.xml 的 Object 数据
     * XMLParser 返回的结构如：
     *   {
     *     Set: [
     *       { id: "barehand", file: "data/inputCommand/barehand.xml", label: "空手" },
     *       ...
     *     ]
     *   }
     * 或单个 Set 时：
     *   {
     *     Set: { id: "barehand", file: "...", label: "空手" }
     *   }
     *
     * @return [{id, file, label}, ...]
     */
    private function parseListData(data:Object):Array {
        if (data == null) {
            logError("list data 为 null");
            return null;
        }

        var setData:Object = data.Set;
        if (setData == undefined) {
            logError("list.xml 中没有找到 Set 节点");
            return null;
        }

        var setList:Array = this.ensureArray(setData);
        var result:Array = [];

        for (var i:Number = 0; i < setList.length; i++) {
            var item:Object = setList[i];
            var id:String = item.id;
            var file:String = item.file;
            var label:String = (item.label != undefined) ? item.label : id;

            if (id != undefined && file != undefined) {
                result.push({
                    id: id,
                    file: file,
                    label: label
                });
            } else {
                logWarn("Set 缺少 id 或 file 属性，跳过");
            }
        }

        return result;
    }

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

    // ========== 访问器 ==========

    /**
     * 获取 set 列表
     */
    public function getSetList():Array {
        return this._setList;
    }

    /**
     * 获取所有已加载的配置
     */
    public function getConfigs():Object {
        return this._configs;
    }

    /**
     * 获取指定 set 的配置
     */
    public function getConfig(setId:String):Object {
        if (this._configs == null) return null;
        return this._configs[setId];
    }

    /**
     * 是否已加载完成
     */
    public function isLoaded():Boolean {
        return this._configs != null;
    }

    /**
     * 是否正在加载
     */
    public function isLoading():Boolean {
        return this._isLoading;
    }
}
