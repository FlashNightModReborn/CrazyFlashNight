import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.MaterialDictionaryLoader extends BaseXMLLoader {
    private static var instance:MaterialDictionaryLoader = null;

    /**
     * 获取单例实例。
     * @return MaterialDictionaryLoader 实例。
     */
    public static function getInstance():MaterialDictionaryLoader {
        if (instance == null) {
            instance = new MaterialDictionaryLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 material_dictionary.xml 的相对路径。
     */
    private function MaterialDictionaryLoader() {
        super("data/dictionaries/material_dictionary.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现 material_dictionary.xml 的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadMaterialDictionary(onLoadHandler, onErrorHandler);
    }

    /**
     * 加载 material_dictionary.xml 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadMaterialDictionary(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 调用基类的 load 方法
        super.load(function(data:Object):Void {
            trace("MaterialDictionaryLoader: 文件加载成功！");

            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("MaterialDictionaryLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 材料大全 数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getMaterialDictionaryData():Object {
        return this.getData();
    }

    /**
     * 覆盖基类的 reload 方法，实现 material_dictionary.xml 的重新加载逻辑。
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
