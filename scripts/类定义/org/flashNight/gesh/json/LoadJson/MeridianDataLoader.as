import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

// 经脉系统配置加载器：先读 data/meridians/list.xml，再并行加载子 JSON 并合并。
// 合并结果是 {meridians, innerPowerCap} 对象，不是裸数组：根级 innerPowerCap 承载内力总预算，
// ListLoader.concatField 只会串接数组字段、会丢弃根级标量，故本类自带 mergeConfig。
// 数据真源见 data/meridians/meridians_config.json。
class org.flashNight.gesh.json.LoadJson.MeridianDataLoader extends BaseXMLLoader {
    private static var instance:MeridianDataLoader = null;
    private static var path:String = "data/meridians/";
    private var combinedData:Object = null;

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
     * @param onLoadHandler 加载成功后的回调函数，接收 {meridians, innerPowerCap} 合并结果。
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
                mergeFn:      org.flashNight.gesh.json.LoadJson.MeridianDataLoader.mergeConfig,
                initialValue: {meridians: [], innerPowerCap: 0}
            }).then(function(result:Object):Void {
                self.combinedData = result;
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
     * 子 JSON 合并函数：按加载顺序串接 meridians，根级 innerPowerCap 取第一个合法值。
     * 由 ListLoader 以裸函数回调调用，禁止依赖 this。
     */
    public static function mergeConfig(acc:Object, childData:Object, index:Number, entry:String):Object {
        if (childData == null) return acc;
        var list = childData.meridians;
        if (list != null) {
            if (list instanceof Array) {
                acc.meridians = acc.meridians.concat(list);
            } else {
                acc.meridians.push(list);
            }
        }
        if (acc.innerPowerCap <= 0) {
            var cap:Number = Number(childData.innerPowerCap);
            if (isFinite(cap) && cap > 0) acc.innerPowerCap = cap;
        }
        return acc;
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
