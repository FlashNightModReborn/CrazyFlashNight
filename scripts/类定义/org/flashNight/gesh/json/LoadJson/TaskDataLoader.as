import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

// 由于需要先读取list.xml，所以继承BaseXMLLoader
class org.flashNight.gesh.json.LoadJson.TaskDataLoader extends BaseXMLLoader {
    private static var instance:TaskDataLoader = null;
    private static var path:String = "data/task/";
    private var combinedData:Array = null;

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
        var self:TaskDataLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.task) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.task);

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                childType:    "json",
                mergeFn:      ListLoader.concatField("tasks"),
                initialValue: []
            }).then(function(result:Object):Void {
                var arr = result;
                self.combinedData = arr;
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
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
     * 覆盖基类的 getData 方法，确保返回合并后的任务数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}

