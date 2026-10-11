import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.gesh.json.LoadJson.TaskOverlayLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

// 由于需要先读取list.xml，所以继承BaseXMLLoader
class org.flashNight.gesh.json.LoadJson.TaskDataLoader extends BaseXMLLoader {
    private static var instance:TaskDataLoader = null;
    private static var path:String = "data/task/";
    private var combinedData:Array = null;
    // 增量热重载缓存：list.xml 的条目顺序与各条目已解析的子数据。
    private var entries:Array = null;
    private var sources:Object = null;
    // 基础合并结果（不含存档覆盖层）。覆盖层单独判断、不进 entries；
    // 覆盖层变化或回退时以它为底重应用，不重复解析共享文件。
    private var baseData:Array = null;

    /**
     * 获取单例实例。
     * @return TaskDataLoader 实例。
     */
    public static function getInstance():TaskDataLoader {
        if (instance == null) {
            instance = new TaskDataLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function TaskDataLoader() {
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现任务数据的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadTaskData(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 JSON 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadTaskData(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this.combinedData != null) {
            if (onLoadHandler != null) onLoadHandler(this.combinedData);
            return;
        }
        var self:TaskDataLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.task) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.task);
            var sources:Object = {};
            var merge:Function = ListLoader.concatField("tasks");

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                childType:    "json",
                mergeFn:      function(acc:Object, childData:Object, index:Number, entry:String):Object {
                    sources[entry] = childData;
                    return merge(acc, childData, index, entry);
                },
                initialValue: []
            }).then(function(result:Object):Void {
                var arr = result;
                self.entries = entries; self.sources = sources;
                self.baseData = arr;
                self.applyOverlay(function():Void {
                    if (onLoadHandler != null) onLoadHandler(self.combinedData);
                });
            }).onCatch(function(reason:Object):Void {
                trace("[TaskDataLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的任务数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getTaskDataData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现任务数据的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空现有数据
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 只重读宿主判定变化的任务源文件，其余条目沿用缓存后按 list.xml 原顺序重合并。
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
        var self:TaskDataLoader = this;
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
            mergeFn:      ListLoader.concatField("tasks"),
            initialValue: []
        }).then(function(result:Object):Void {
            // 用 untyped 中间变量绕过 Flash CS6 的 Object→Array 赋值检查（combinedData 声明为 Array）。
            var arr = result;
            self.baseData = arr;
            self.applyOverlay(function():Void {
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            });
        }).onCatch(function(reason:Object):Void {
            trace("[TaskDataLoader] " + reason);
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 在基础合并结果之上应用当前存档的覆盖层（G2-2）。文件缺失＝该存档无增量，
     * 直接用基础数据；解析失败＝TaskOverlayLoader 已报错并回 null，同样回退基础数据。
     */
    private function applyOverlay(onDone:Function):Void {
        var self:TaskDataLoader = this;
        var base:Array = this.baseData;
        var overlayPath:String = TaskOverlayLoader.resolvePath(TaskOverlayLoader.TASK_FILE);
        if (overlayPath == null) {
            this.combinedData = base;
            if (onDone != null) onDone();
            return;
        }
        TaskOverlayLoader.load(overlayPath, function(overlay:Object):Void {
            self.combinedData = (overlay == null) ? base : self.mergeOverlayTasks(base, overlay);
            if (onDone != null) onDone();
        });
    }

    /** 基础任务数组叠加覆盖层：同一 id 视为覆盖，存档条目优先生效并追加在末尾。 */
    private function mergeOverlayTasks(baseArr:Array, overlay:Object):Array {
        var overlayTasks:Array = ListLoader.normalizeToArray(overlay.tasks);
        if (overlayTasks.length == 0) return baseArr;
        var overlayIds:Object = {};
        var i:Number = 0;
        for (i = 0; i < overlayTasks.length; i++) {
            overlayIds[String(overlayTasks[i].id)] = true;
        }
        var result:Array = [];
        for (i = 0; i < baseArr.length; i++) {
            if (overlayIds[String(baseArr[i].id)] === true) {
                if (typeof _root.发布消息 == "function") {
                    _root.发布消息("任务覆盖层替代共享任务（同 id 以存档为准）：" + baseArr[i].id);
                }
                continue;
            }
            result.push(baseArr[i]);
        }
        for (i = 0; i < overlayTasks.length; i++) result.push(overlayTasks[i]);
        return result;
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的任务数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}

