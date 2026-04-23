import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.MapPanelLoader extends BaseXMLLoader {
    private static var instance:MapPanelLoader = null;

    /**
     * 获取单例实例。
     * @return MapPanelLoader 实例。
     */
    public static function getInstance():MapPanelLoader {
        if (instance == null) {
            instance = new MapPanelLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 map_panel.xml 的相对路径。
     */
    private function MapPanelLoader() {
        super("data/map/map_panel.xml");
    }

    /**
     * 覆盖基类的 load 方法。相比模板多一层守卫：
     *   - XMLLoader 在根节点不存在时 parsedData == null，基类仍走 success；这里兜底转 error
     *   - 正常根节点下必须至少含 groups/hotspots/task_npcs 中的一个，否则也视为失败
     *   （parser 行为：返回的 data 是根节点内容，不是 {rootName: content}；见 XMLLoader.as L43-51）
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        super.load(function(data:Object):Void {
            if (data == null) {
                trace("MapPanelLoader: 加载成功但数据为 null（XML 空根节点），视为失败");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            if (data.groups == undefined && data.hotspots == undefined && data.task_npcs == undefined) {
                trace("MapPanelLoader: 根节点下无 groups/hotspots/task_npcs，视为失败");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            trace("MapPanelLoader: 文件加载成功！");
            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("MapPanelLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 地图面板 数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getMapPanelData():Object {
        return this.getData();
    }

    /**
     * 覆盖基类的 reload 方法，实现 map_panel.xml 的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空缓存并重新加载
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回正确的数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return super.getData();
    }
}
