import org.flashNight.gesh.xml.*;
import org.flashNight.gesh.path.*;
import org.flashNight.gesh.object.*;

class org.flashNight.gesh.xml.LoadXml.BaseXMLLoader {
    private var data:Object = null;
    private var _isLoading:Boolean = false; // 重命名为 _isLoading
    private var filePath:String;

    /**
     * 构造函数，初始化加载器。
     * @param relativePath String 相对于资源目录的文件路径。
     */
    public function BaseXMLLoader(relativePath:String) {
        // 初始化路径管理器
        PathManager.initialize();
        if (!PathManager.isEnvironmentValid()) {
            trace("BaseXMLLoader: 未检测到资源目录，无法加载文件！");
            return;
        }

        // 解析完整路径
        this.filePath = PathManager.resolvePath(relativePath);
        if (this.filePath == null) {
            trace("BaseXMLLoader: 路径解析失败，无法加载文件！");
        }
    }

    /**
     * 加载数据文件。
     * @param onLoadHandler 加载成功后的回调函数，接收解析后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this._isLoading) { // 使用重命名后的变量
            trace("BaseXMLLoader: 数据正在加载中，请勿重复加载！");
            return;
        }

        if (this.data != null) {
            trace("BaseXMLLoader: 数据已加载，直接回调。");
            if (onLoadHandler != null) onLoadHandler(this.data);
            return;
        }

        if (this.filePath == null) {
            trace("BaseXMLLoader: 文件路径无效，无法加载！");
            if (onErrorHandler != null) onErrorHandler();
            return;
        }

        this._isLoading = true;
        var self:BaseXMLLoader = this;

        trace("BaseXMLLoader: 开始加载文件：" + this.filePath);

        // 使用 XMLLoader 加载文件
        new XMLLoader(this.filePath, function(parsedData:Object):Void {
            self._isLoading = false;
            self.data = parsedData; // 保存数据到实例变量
            trace("BaseXMLLoader: 文件加载成功！");
            if (onLoadHandler != null) onLoadHandler(parsedData);
        }, function():Void {
            self._isLoading = false;
            trace("BaseXMLLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 重新加载数据文件，忽略已有缓存。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.data = null; // 清除已有数据
        this.load(onLoadHandler, onErrorHandler);
    }

    /**
     * 获取已加载的数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.data;
    }

    /**
     * 检查数据是否已加载。
     * @return Boolean 如果数据已加载，返回 true；否则返回 false。
     */
    public function isLoaded():Boolean {
        return this.data != null;
    }

    /**
     * 检查是否正在加载。
     * @return Boolean 如果正在加载，返回 true；否则返回 false。
     */
    public function isLoadingStatus():Boolean { // 重命名方法
        return this._isLoading;
    }

    public function toString():String {
        return ObjectUtil.toString(this.getData());
    }
}
