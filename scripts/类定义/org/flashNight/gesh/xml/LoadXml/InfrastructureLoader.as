import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.InfrastructureLoader extends BaseXMLLoader {
    private static var instance:InfrastructureLoader = null;

    /**
     * 获取单例实例。
     * @return InfrastructureLoader 实例。
     */
    public static function getInstance():InfrastructureLoader {
        if (instance == null) {
            instance = new InfrastructureLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 infrastructure.xml 的相对路径。
     */
    private function InfrastructureLoader() {
        super("data/infrastructure/infrastructure.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现 infrastructure.xml 的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadInfrastructure(onLoadHandler, onErrorHandler);
    }

    /**
     * 加载 infrastructure.xml 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadInfrastructure(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 调用基类的 load 方法
        super.load(function(data:Object):Void {
            trace("InfrastructureLoader: 文件加载成功！");

            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("InfrastructureLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 基建项目 数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getInfrastructureData():Object {
        return this.getData();
    }

    /**
     * 覆盖基类的 reload 方法，实现 infrastructure.xml 的重新加载逻辑。
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
