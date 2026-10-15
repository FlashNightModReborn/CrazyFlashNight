import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

// 经脉系统配置加载器：先读 data/meridians/list.xml，再并行加载子 JSON 并合并 meridians 数组。
// 与 AchievementDataLoader 同构；数据真源见 data/meridians/meridians_config.json。
class org.flashNight.gesh.json.LoadJson.MeridianDataLoader extends BaseXMLLoader {
    private static var instance:MeridianDataLoader = null;
    private static var path:String = "data/meridians/";
    private var combinedData:Array = null;

    /**
     * 获取单例实例。
     * @return MeridianDataLoader 实例。
     */
    public static function getInstance():MeridianDataLoader {
        if (instance == null) {
            instance = new MeridianDataLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function MeridianDataLoader() {
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现经脉数据的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败时的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadMeridianData(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 JSON 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的 meridians 数组。
     * @param onErrorHandler 加载失败时的回调函数。
     */
    public function loadMeridianData(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this.combinedData != null) {
            if (onLoadHandler != null) onLoadHandler(this.combinedData);
            return;
        }
        var self:MeridianDataLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.meridians) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.meridians);

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                childType:    "json",
                mergeFn:      ListLoader.concatField("meridians"),
                initialValue: []
            }).then(function(result:Object):Void {
                var arr = result;
                self.combinedData = arr;
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }).onCatch(function(reason:Object):Void {
                trace("[MeridianDataLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的经脉数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getMeridianData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现数据的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的经脉数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}
