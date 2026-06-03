import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 加载 data/map/map_panel.xml（瘦身后仅含 <avatar_visibility> 段；groups/hotspots 已迁出至
// map_catalog.json 走 DataQueryService("map_catalog")，task_npcs/aliases 走 task_npc_registry.json）。
// 与原 MapPanelLoader 的差别：不再要求根节点含 groups/hotspots——本 loader 只为 avatar_visibility
// 服务，而 <avatar_visibility> 段允许整段缺失（MapPanelCatalog.applyAvatarVisibilityFromXml 把
// 缺失视为"空表 = 默认全可见"），故只在根节点 null 时判失败。
class org.flashNight.gesh.xml.LoadXml.MapAvatarVisibilityLoader extends BaseXMLLoader {
    private static var instance:MapAvatarVisibilityLoader = null;

    /**
     * 获取单例实例。
     * @return MapAvatarVisibilityLoader 实例。
     */
    public static function getInstance():MapAvatarVisibilityLoader {
        if (instance == null) {
            instance = new MapAvatarVisibilityLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 map_panel.xml 的相对路径。
     */
    private function MapAvatarVisibilityLoader() {
        super("data/map/map_panel.xml");
    }

    /**
     * 覆盖基类的 load 方法。相比模板多一层守卫：
     *   - XMLLoader 在根节点不存在时 parsedData == null，基类仍走 success；这里兜底转 error
     *   - 不再要求 groups/hotspots（已迁出）；<avatar_visibility> 段缺失是合法的（默认全可见）
     *   （parser 行为：返回的 data 是根节点内容，不是 {rootName: content}；见 XMLLoader.as L43-51）
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:MapAvatarVisibilityLoader = this;
        super.load(function(data:Object):Void {
            // BaseXMLLoader.load 在回调前已把 parsedData 写入缓存。若此处判坏，需主动 clearCache，
            // 否则后续 load() 会反复吐出同一份坏 data 且 isLoaded() 误报为 true。
            if (data == null) {
                trace("MapAvatarVisibilityLoader: 加载成功但数据为 null（XML 空根节点），视为失败");
                self.clearCache();
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            trace("MapAvatarVisibilityLoader: 文件加载成功！");
            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("MapAvatarVisibilityLoader: 文件加载失败！");
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
