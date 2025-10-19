import org.flashNight.gesh.json.LoadJson.BaseJSONLoader;
 
/**
 * ProgressGuideLoader 类
 * 用于加载任务进度引导数据
 * 当玩家没有可进行的任务时，根据主线进度显示对应的引导提示
 */
class org.flashNight.gesh.json.LoadJson.ProgressGuideLoader extends BaseJSONLoader {
    private static var instance:ProgressGuideLoader = null;
    private static var path:String = "data/task/progress_guide.json";

    /**
     * 获取单例实例
     * @return ProgressGuideLoader 实例
     */
    public static function getInstance():ProgressGuideLoader {
        if (instance == null) {
            instance = new ProgressGuideLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 progress_guide.json 的相对路径
     */
    private function ProgressGuideLoader() {
        super(path);
    }

    /**
     * 加载引导数据
     * @param onLoadHandler 加载成功后的回调函数，接收引导数据作为参数
     * @param onErrorHandler 加载失败后的回调函数
     */
    public function loadGuideData(onLoadHandler:Function, onErrorHandler:Function):Void {
        super.load(onLoadHandler, onErrorHandler);
    }

    /**
     * 获取已加载的引导数据
     * @return Object 引导数据对象，如果尚未加载，则返回 null
     */
    public function getGuideData():Object {
        return this.getData();
    }

    /**
     * 重新加载引导数据
     * @param onLoadHandler 加载成功后的回调函数
     * @param onErrorHandler 加载失败后的回调函数
     */
    public function reloadGuideData(onLoadHandler:Function, onErrorHandler:Function):Void {
        super.reload(onLoadHandler, onErrorHandler);
    }
}
