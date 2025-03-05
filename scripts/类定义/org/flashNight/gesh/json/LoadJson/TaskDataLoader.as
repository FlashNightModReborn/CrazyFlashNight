import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.gesh.object.ObjectUtil;

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
     * 解析 list.xml 文件，根据其中内容，解析并合并其中的 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadTaskData(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:TaskDataLoader = this;

        // 加载 list.xml 文件
        super.load(function(data:Object):Void {
            // trace("TaskDataLoader: list.xml 文件加载成功！");

            if (!data || !data.task || !(data.task instanceof Array)) {
                // trace("TaskDataLoader: list.xml 数据结构不正确！");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }

            var childJSONPaths:Array = data.task;
            // trace("TaskDataLoader: 需要加载的子 JSON 文件列表 = " + ObjectUtil.toString(childJSONPaths));

            self.combinedData = [];

            // 开始加载子 JSON 文件
            self.loadChildJSONFiles(childJSONPaths, 0, function():Void {
                // 将合并后的数据保存到基类的 data 属性中
                super.data = self.combinedData;

                // trace("TaskDataLoader: 所有子 JSON 文件加载并合并成功！");
                // trace("TaskDataLoader: 合并后的数据 = " + ObjectUtil.toString(self.combinedData));
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }, function():Void {
                // trace("TaskDataLoader: 加载子 JSON 文件失败！");
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            // trace("TaskDataLoader: list.xml 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 递归加载子 JSON 文件并合并数据。
     * @param paths 子 JSON 文件路径数组。
     * @param index 当前加载的文件索引。
     * @param onComplete 所有文件加载完成的回调函数。
     * @param onError 加载失败的回调函数。
     */
    private function loadChildJSONFiles(paths:Array, index:Number, onComplete:Function, onError:Function):Void {
        var self:TaskDataLoader = this;

        if (index >= paths.length) {
            // 所有文件加载完成
            onComplete();
            return;
        }

        var jsonFileName:String = paths[index];
        var jsonFilePath:String = path + jsonFileName;
        // trace("TaskDataLoader: 准备加载子 JSON 文件 = " + jsonFilePath);

        var loader:BaseJSONLoader = new BaseJSONLoader(jsonFilePath);

        loader.load(function(childData:Object):Void {
            // trace("TaskDataLoader: 子 JSON 文件加载成功 = " + jsonFilePath);
            // trace("TaskDataLoader: 子 JSON 数据 = " + ObjectUtil.toString(childData));

            // 假设 childData.tasks 中的任务数据，合并到 combinedData 中
            self.combinedData = self.combinedData.concat(childData.tasks);

            // 递归加载下一个文件
            self.loadChildJSONFiles(paths, index + 1, onComplete, onError);
        }, function():Void {
            // trace("TaskDataLoader: 子 JSON 文件加载失败 = " + jsonFilePath);
            onError();
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

