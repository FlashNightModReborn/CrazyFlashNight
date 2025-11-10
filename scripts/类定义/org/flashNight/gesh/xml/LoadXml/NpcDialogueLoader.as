import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.NpcDialogueLoader extends BaseXMLLoader {
    private static var instance:NpcDialogueLoader = null;
    private static var path:String = "data/dialogues/";
    private var combinedData:Object = null;

    /**
     * 获取单例实例。
     * @return NpcDialogueLoader 实例。
     */
    public static function getInstance():NpcDialogueLoader {
        if (instance == null) {
            instance = new NpcDialogueLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function NpcDialogueLoader() {
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现NPC对话的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadNpcDialogues(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，解析并合并其中的 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadNpcDialogues(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:NpcDialogueLoader = this;

        // 加载 list.xml 文件
        super.load(function(data:Object):Void {
            // trace("NpcDialogueLoader: list.xml 文件加载成功！");
            // trace("NpcDialogueLoader: list.xml 数据 = " + ObjectUtil.toString(data));

            if (!data || !data.items || !(data.items instanceof Array)) {
                // trace("NpcDialogueLoader: list.xml 数据结构不正确！");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }

            var childXmlPaths:Array = data.items;
            // trace("NpcDialogueLoader: 需要加载的子 XML 文件列表 = " + ObjectUtil.toString(childXmlPaths));

            self.combinedData = {};

            // 开始加载子 XML 文件
            self.loadChildXmlFiles(childXmlPaths, 0, function():Void {
                // 将合并后的数据保存到基类的 data 属性中
                super.data = self.combinedData;

                // trace("NpcDialogueLoader: 所有子 XML 文件加载并合并成功！");
                // trace("NpcDialogueLoader: 合并后的数据 = " + ObjectUtil.toString(self.combinedData));
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }, function():Void {
                // trace("NpcDialogueLoader: 加载子 XML 文件失败！");
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            // trace("NpcDialogueLoader: list.xml 文件加载失败！");
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
        var self:NpcDialogueLoader = this;

        if (index >= paths.length) {
            // 所有文件加载完成
            onComplete();
            return;
        }

        var xmlFileName:String = paths[index];
        var xmlFilePath:String = path + xmlFileName;
        // trace("NpcDialogueLoader: 准备加载子 XML 文件 = " + xmlFilePath);

        var loader:BaseXMLLoader = new BaseXMLLoader(xmlFilePath);

        loader.load(function(childData:Object):Void {
            // trace("NpcDialogueLoader: 子 XML 文件加载成功 = " + xmlFilePath);
            // trace("NpcDialogueLoader: 子 XML 数据 = " + ObjectUtil.toString(childData));

            // NPC对话数据结构: childData.Dialogues 是一个数组，每个元素包含 Name 和 Dialogue
            if (childData.Dialogues) {
                var dialoguesArray:Array = (childData.Dialogues instanceof Array) ? childData.Dialogues : [childData.Dialogues];

                for (var i:Number = 0; i < dialoguesArray.length; i++) {
                    var npcData:Object = dialoguesArray[i];
                    if (npcData && npcData.Name) {
                        var npcName:String = npcData.Name;
                        // trace("NpcDialogueLoader: 合并NPC对话，NPC名称 = " + npcName);

                        // 将整个Dialogue数组存储，保持原有数据结构
                        if (npcData.Dialogue) {
                            self.combinedData[npcName] = (npcData.Dialogue instanceof Array) ? npcData.Dialogue : [npcData.Dialogue];
                        }
                    }
                }
            }

            // 递归加载下一个文件
            self.loadChildXmlFiles(paths, index + 1, onComplete, onError);
        }, function():Void {
            // trace("NpcDialogueLoader: 子 XML 文件加载失败 = " + xmlFilePath);
            onError();
        });
    }

    /**
     * 获取已加载的NPC对话数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getNpcDialogueData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现NPC对话数据的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空现有数据
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的NPC对话数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}



/*

import org.flashNight.gesh.xml.LoadXml.NpcDialogueLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 获取 NpcDialogueLoader 实例
var npcDialogueLoader:NpcDialogueLoader = NpcDialogueLoader.getInstance();

// 加载NPC对话数据
npcDialogueLoader.loadNpcDialogues(
    function(combinedData:Object):Void {
        trace("主程序：NPC对话数据加载成功！");
        trace("合并后的数据: " + ObjectUtil.toString(combinedData));
        // 在此处处理合并后的NPC对话数据
        _root.NPC对话 = combinedData;
    },
    function():Void {
        trace("主程序：NPC对话数据加载失败！");
    }
);

*/