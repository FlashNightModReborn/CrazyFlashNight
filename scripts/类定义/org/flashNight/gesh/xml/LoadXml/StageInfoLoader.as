import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

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
     * 解析 list.xml 文件，根据其中内容，解析并合并其中的 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadStageInfo(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:StageInfoLoader = this;

        // 加载 list.xml 文件
        super.load(function(data:Object):Void {
            // trace("StageInfoLoader: list.xml 文件加载成功！");
            // trace("StageInfoLoader: list.xml 数据 = " + ObjectUtil.toString(data));

            if (!data || !data.stages || !(data.stages instanceof Array)) {
                // trace("StageInfoLoader: list.xml 数据结构不正确！");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }

            var childXmlFolderPaths:Array = data.stages;
            // trace("StageInfoLoader: 需要加载的子 XML 文件夹列表 = " + ObjectUtil.toString(childXmlFolderPaths));

            self.combinedData = {};

            // 开始加载子 XML 文件
            self.loadChildXmlFiles(childXmlFolderPaths, 0, function():Void {
                // 将合并后的数据保存到基类的 data 属性中
                super.data = self.combinedData;

                // trace("StageInfoLoader: 所有子 XML 文件加载并合并成功！");
                // trace("StageInfoLoader: 合并后的数据 = " + ObjectUtil.toString(self.combinedData));
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }, function():Void {
                // trace("StageInfoLoader: 加载子 XML 文件失败！");
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            // trace("StageInfoLoader: list.xml 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 递归加载子 XML 文件并合并数据。
     * @param paths 子 XML 文件路径数组。
     * @param index 当前加载的文件索引。
     * @param onComplete 所有文件加载完成的回调函数。
     * @param onError 加载失败的回调函数。
     */
    private function loadChildXmlFiles(paths:Array, index:Number, onComplete:Function, onError:Function):Void {
        var self:StageInfoLoader = this;

        if (index >= paths.length) {
            // 所有文件加载完成
            onComplete();
            return;
        }

        var xmlFolderName:String = paths[index];
        var xmlFilePath:String = path + xmlFolderName + "/__list__.xml";
        // trace("StageInfoLoader: 准备加载子 XML 文件 = " + xmlFilePath);

        var loader:BaseXMLLoader = new BaseXMLLoader(xmlFilePath);

        loader.load(function(childData:Object):Void {
            // trace("StageInfoLoader: 子 XML 文件加载成功 = " + xmlFilePath);
            // trace("StageInfoLoader: 子 XML 数据 = " + ObjectUtil.toString(childData));

            // 假设 childData.StageInfo 中的关卡信息，合并到 combinedData 中
            var infoList = childData.StageInfo;
            //填写每个关卡对应的url
            for(var i=0; i<infoList.length; i++){
                var info = infoList[i];
                info.url = path + xmlFolderName + "/" + info.Name + ".xml";
                self.combinedData[info.Name] = info;
            }

            // 递归加载下一个文件
            self.loadChildXmlFiles(paths, index + 1, onComplete, onError);
        }, function():Void {
            // trace("StageInfoLoader: 子 XML 文件加载失败 = " + xmlFilePath);
            onError();
        });
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