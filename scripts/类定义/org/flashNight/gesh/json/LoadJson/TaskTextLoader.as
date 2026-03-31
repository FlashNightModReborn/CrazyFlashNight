import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

// 由于需要先读取list.xml，所以继承BaseXMLLoader
class org.flashNight.gesh.json.LoadJson.TaskTextLoader extends BaseXMLLoader {
    private static var instance:TaskTextLoader = null;
    private static var path:String = "data/task/text/";
    private var combinedData:Object = null;

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
        var self:TaskTextLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.text) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.text);

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                childType:    "json",
                mergeFn:      ListLoader.dictMerge(),
                initialValue: {}
            }).then(function(result:Object):Void {
                self.combinedData = result;
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
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
     * 覆盖基类的 getData 方法，确保返回合并后的任务文本。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}

