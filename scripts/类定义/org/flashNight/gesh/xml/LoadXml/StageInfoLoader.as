import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

class org.flashNight.gesh.xml.LoadXml.StageInfoLoader extends BaseXMLLoader {
    private static var instance:StageInfoLoader = null;
    private static var path:String = "data/stages/";
    private var combinedData:Object = null;

    /**
     * 获取单例实例。
     * @return StageInfoLoader 实例。
     */
    public static function getInstance():StageInfoLoader {
        if (instance == null) {
            instance = new StageInfoLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function StageInfoLoader() {
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现关卡信息的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadStageInfo(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadStageInfo(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this.combinedData != null) {
            if (onLoadHandler != null) onLoadHandler(this.combinedData);
            return;
        }
        var self:StageInfoLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.stages) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.stages);

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                pathBuilder:  StageInfoLoader.buildStagePath,
                mergeFn:      StageInfoLoader.mergeStageInfo,
                initialValue: {}
            }).then(function(result:Object):Void {
                self.combinedData = result;
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }).onCatch(function(reason:Object):Void {
                trace("[StageInfoLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /** pathBuilder: data/stages/{folderName}/__list__.xml */
    private static function buildStagePath(basePath:String, entry:String):String {
        return basePath + entry + "/__list__.xml";
    }

    /** mergeFn: 从 childData.StageInfo 提取关卡信息，注入 url 字段 */
    private static function mergeStageInfo(acc:Object, childData:Object, index:Number, entry:String):Object {
        var infoList = childData.StageInfo;
        if (infoList == null || infoList == undefined) return acc;
        // StageInfo 可能是单个对象或数组
        if (!(infoList instanceof Array)) {
            infoList = [infoList];
        }
        var i:Number = 0;
        while (i < infoList.length) {
            var info:Object = infoList[i];
            info.url = path + entry + "/" + info.Name + ".xml";
            acc[info.Name] = info;
            i++;
        }
        return acc;
    }

    /**
     * 获取已加载的关卡信息。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getStageInfoData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现关卡信息的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空现有数据
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的关卡信息。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}



/*

import org.flashNight.gesh.xml.LoadXml.StageInfoLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 获取 StageInfoLoader 实例
var StageInfoLoader:StageInfoLoader = StageInfoLoader.getInstance();

// 加载关卡信息
StageInfoLoader.loadStageInfo(
    function(combinedData:Object):Void {
        trace("主程序：关卡信息加载成功！");
        _root.StageInfoDict = combinedData;
    },
    function():Void {
        trace("主程序：关卡信息加载失败！");
    }
);

*/