import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.BulletsCasesLoader extends BaseXMLLoader {
    private static var instance:BulletsCasesLoader = null;

    /**
     * 获取单例实例。
     * @return BulletsCasesLoader 实例。
     */
    public static function getInstance():BulletsCasesLoader {
        if (instance == null) {
            instance = new BulletsCasesLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 bullets_cases.xml 的相对路径。
     */
    private function BulletsCasesLoader() {
        super("data/items/bullets_cases.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现 bullets_cases.xml 的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadBulletsCases(onLoadHandler, onErrorHandler);
    }

    /**
     * 加载 bullets_cases.xml 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadBulletsCases(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 调用基类的 load 方法
        super.load(function(data:Object):Void {
            trace("BulletsCasesLoader: 文件加载成功！");

            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("BulletsCasesLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 bullets_cases 数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getBulletsCasesData():Object {
        return this.getData();
    }

    /**
     * 覆盖基类的 reload 方法，实现 bullets_cases.xml 的重新加载逻辑。
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
