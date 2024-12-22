import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.DOMDocumentLoader extends BaseXMLLoader {
    private static var instance:DOMDocumentLoader = null;

    /**
     * 获取单例实例。
     * @return DOMDocumentLoader 实例。
     */
    public static function getInstance():DOMDocumentLoader {
        if (instance == null) {
            instance = new DOMDocumentLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 DOMDocument 的相对路径。
     */
    private function DOMDocumentLoader() {
        super("flashswf/UI/加载背景/DOMDocument.xml"); // 替换为实际的 DOMDocument 文件路径
    }

    /**
     * 加载 DOMDocument 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadDOMDocument(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.load(function(data:Object):Void {
            trace("DOMDocumentLoader: DOMDocument 文件加载成功！");
            trace("Parsed DOMDocument Data: " + ObjectUtil.toString(data)); // 调试输出解析结果
            if (onLoadHandler != null) onLoadHandler(data);
        }, function():Void {
            trace("DOMDocumentLoader: DOMDocument 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的 DOMDocument 数据。
     * @return Object 解析后的 DOMDocument 数据对象，如果尚未加载，则返回 null。
     */
    public function getDOMDocumentData():Object {
        return this.getData();
    }

    /**
     * 获取所有文件夹项。
     * @return Array 包含所有 DOMFolderItem 的数组。
     */
    public function getFolders():Array {
        var data:Object = this.getData();
        if (data && data.folders && data.folders.DOMFolderItem) {
            // 确保返回的是数组，即使只有一个元素
            return (data.folders.DOMFolderItem instanceof Array) ? data.folders.DOMFolderItem : [data.folders.DOMFolderItem];
        }
        return [];
    }

    /**
     * 获取所有媒体项。
     * @return Array 包含所有 DOMBitmapItem 的数组。
     */
    public function getMedia():Array {
        var data:Object = this.getData();
        if (data && data.media && data.media.DOMBitmapItem) {
            return (data.media.DOMBitmapItem instanceof Array) ? data.media.DOMBitmapItem : [data.media.DOMBitmapItem];
        }
        return [];
    }

    /**
     * 获取所有符号项。
     * @return Array 包含所有 symbols 中的 Include 项的数组。
     */
    public function getSymbols():Array {
        var data:Object = this.getData();
        if (data && data.symbols && data.symbols.Include) {
            return (data.symbols.Include instanceof Array) ? data.symbols.Include : [data.symbols.Include];
        }
        return [];
    }

    /**
     * 获取所有时间轴信息。
     * @return Array 包含所有 DOMTimeline 的数组。
     */
    public function getTimelines():Array {
        var data:Object = this.getData();
        if (data && data.timelines && data.timelines.DOMTimeline) {
            return (data.timelines.DOMTimeline instanceof Array) ? data.timelines.DOMTimeline : [data.timelines.DOMTimeline];
        }
        return [];
    }

    /**
     * 获取持久化数据。
     * @return Object 包含所有 persistentData 的键值对。
     */
    public function getPersistentData():Object {
        var data:Object = this.getData();
        if (data && data.persistentData && data.persistentData.PD) {
            var pd:Object = {};
            var pds:Array = (data.persistentData.PD instanceof Array) ? data.persistentData.PD : [data.persistentData.PD];
            for (var i:Number = 0; i < pds.length; i++) {
                pd[pds[i].n] = pds[i].v;
            }
            return pd;
        }
        return {};
    }
}
