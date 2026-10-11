import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.gesh.json.LoadJson.TaskOverlayLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

// 由于需要先读取list.xml，所以继承BaseXMLLoader
class org.flashNight.gesh.json.LoadJson.TaskTextLoader extends BaseXMLLoader {
    private static var instance:TaskTextLoader = null;
    private static var path:String = "data/task/text/";
    private var combinedData:Object = null;
    // 增量热重载缓存：list.xml 的条目顺序与各条目已解析的子数据。
    private var entries:Array = null;
    private var sources:Object = null;
    // 基础合并结果（不含存档覆盖层）。覆盖层单独判断、不进 entries；
    // 覆盖层变化或回退时以它为底重应用，不重复解析共享文件。
    private var baseData:Object = null;

    /**
     * 获取单例实例。
     * @return TaskTextLoader 实例。
     */
    public static function getInstance():TaskTextLoader {
        if (instance == null) {
            instance = new TaskTextLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function TaskTextLoader() {
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现任务文本的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadTaskText(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 JSON 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadTaskText(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this.combinedData != null) {
            if (onLoadHandler != null) onLoadHandler(this.combinedData);
            return;
        }
        var self:TaskTextLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.text) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.text);
            var sources:Object = {};
            var merge:Function = ListLoader.dictMerge();

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                childType:    "json",
                mergeFn:      function(acc:Object, childData:Object, index:Number, entry:String):Object {
                    sources[entry] = childData;
                    return merge(acc, childData, index, entry);
                },
                initialValue: {}
            }).then(function(result:Object):Void {
                self.entries = entries; self.sources = sources;
                self.baseData = result;
                self.applyOverlay(function():Void {
                    if (onLoadHandler != null) onLoadHandler(self.combinedData);
                });
            }).onCatch(function(reason:Object):Void {
                trace("[TaskTextLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的任务文本。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getTaskTextData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现任务文本的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空现有数据
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 只重读宿主判定变化的任务文本文件，其余条目沿用缓存后按 list.xml 原顺序重合并。
     * 缓存不全时退回整目录 reload，不猜半份数据。
     * 覆盖层（data/rag/agent_saves/...）单独判断、不走 ownedEntries：
     * 仅覆盖层变化时基础合并结果原样保留，只重新应用一次覆盖层。
     * @param names 宿主给出的变化文件相对路径清单；null/undefined 表示整目录重载。
     */
    public function reloadFiles(names:Array, onLoadHandler:Function, onErrorHandler:Function):Void {
        if (!(names instanceof Array) || this.combinedData == null || this.entries == null || this.sources == null) {
            this.reload(onLoadHandler, onErrorHandler);
            return;
        }
        var self:TaskTextLoader = this;
        var owned:Array = ListLoader.ownedEntries(names, path, this.entries);
        var overlayTouched:Boolean = false;
        var i:Number = 0;
        while (i < names.length) {
            if (TaskOverlayLoader.isOverlayPath(String(names[i]))) { overlayTouched = true; break; }
            i++;
        }
        if (owned.length == 0) {
            if (!overlayTouched) {
                if (onLoadHandler != null) onLoadHandler(this.combinedData);
                return;
            }
            this.applyOverlay(function():Void {
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            });
            return;
        }
        ListLoader.reloadChanged({
            entries:      this.entries,
            sources:      this.sources,
            changed:      owned,
            basePath:     path,
            childType:    "json",
            mergeFn:      ListLoader.dictMerge(),
            initialValue: {}
        }).then(function(result:Object):Void {
            self.baseData = result;
            self.applyOverlay(function():Void {
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            });
        }).onCatch(function(reason:Object):Void {
            trace("[TaskTextLoader] " + reason);
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 在基础合并结果之上应用当前存档的覆盖层（G2-2）。文件缺失＝该存档无增量，
     * 直接用基础数据；解析失败＝TaskOverlayLoader 已报错并回 null，同样回退基础数据。
     */
    private function applyOverlay(onDone:Function):Void {
        var self:TaskTextLoader = this;
        var base:Object = this.baseData;
        var overlayPath:String = TaskOverlayLoader.resolvePath(TaskOverlayLoader.TEXT_FILE);
        if (overlayPath == null) {
            this.combinedData = base;
            if (onDone != null) onDone();
            return;
        }
        TaskOverlayLoader.load(overlayPath, function(overlay:Object):Void {
            self.combinedData = (overlay == null) ? base : self.mergeOverlayText(base, overlay);
            if (onDone != null) onDone();
        });
    }

    /** 文本覆盖层按 key 覆盖基础 dict；覆盖层键总是赢。 */
    private function mergeOverlayText(baseObj:Object, overlay:Object):Object {
        var result:Object = {};
        var key:String;
        for (key in baseObj) result[key] = baseObj[key];
        for (key in overlay) result[key] = overlay[key];
        return result;
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的任务文本。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}

