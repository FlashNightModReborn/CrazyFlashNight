import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;

/**
 * A2 材料档案 authored catalog loader。
 *
 * material_catalog.xml 的 Material 物理顺序就是 archiveOrder；本类只负责
 * 保留 XMLParser 的数组顺序，不在运行时重排、补项或从 legacy dictionary 反推。
 */
class org.flashNight.gesh.xml.LoadXml.MaterialCatalogLoader extends BaseXMLLoader {
    private static var instance:MaterialCatalogLoader = null;

    /**
     * 获取单例实例。
     * @return MaterialCatalogLoader 实例。
     */
    public static function getInstance():MaterialCatalogLoader {
        if (instance == null) {
            instance = new MaterialCatalogLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 authored material_catalog.xml 的相对路径。
     */
    private function MaterialCatalogLoader() {
        super("data/dictionaries/material_catalog.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现 material_catalog.xml 的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadMaterialCatalog(onLoadHandler, onErrorHandler);
    }

    /**
     * 加载 material_catalog.xml 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadMaterialCatalog(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 调用基类的 load 方法
        super.load(function(data:Object):Void {
            if (data == null || typeof data != "object"
                    || Number(data.schemaVersion) != 1
                    || !(data.Material instanceof Array)
                    || data.DirectPurpose == undefined) {
                trace("MaterialCatalogLoader: 文件结构非法！");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            trace("MaterialCatalogLoader: 文件加载成功！");

            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("MaterialCatalogLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 authored 材料档案数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getMaterialCatalogData():Object {
        return this.getData();
    }

    /**
     * 覆盖基类的 reload 方法，实现 material_catalog.xml 的重新加载逻辑。
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
