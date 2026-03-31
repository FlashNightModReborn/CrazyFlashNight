import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

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
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadNpcDialogues(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this.combinedData != null) {
            if (onLoadHandler != null) onLoadHandler(this.combinedData);
            return;
        }
        var self:NpcDialogueLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.items) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.items);

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                mergeFn:      NpcDialogueLoader.mergeDialogues,
                initialValue: {}
            }).then(function(result:Object):Void {
                self.combinedData = result;
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }).onCatch(function(reason:Object):Void {
                trace("[NpcDialogueLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 合并单个子 XML 的 NPC 对话数据到累加器。
     * 处理 Dialogues → Dialogue → SubDialogue 的嵌套结构，
     * 并将 PascalCase 字段名转换为 lowercase。
     */
    private static function mergeDialogues(acc:Object, childData:Object, index:Number, entry:String):Object {
        var dialoguesData:Object = childData.Dialogues;
        if (dialoguesData == null || dialoguesData == undefined) return acc;

        // Dialogues 可能是单个对象或数组
        var dialoguesArray;
        if (dialoguesData instanceof Array) {
            dialoguesArray = dialoguesData;
        } else {
            dialoguesArray = [dialoguesData];
        }

        var i:Number = 0;
        while (i < dialoguesArray.length) {
            var npcData:Object = dialoguesArray[i];
            if (npcData != null && npcData.Name != undefined) {
                var npcName:String = npcData.Name;

                if (npcData.Dialogue != null) {
                    if (acc[npcName] == undefined) {
                        acc[npcName] = [];
                    }

                    // Dialogue 可能是单个对象或数组
                    var dialogueArray;
                    if (npcData.Dialogue instanceof Array) {
                        dialogueArray = npcData.Dialogue;
                    } else {
                        dialogueArray = [npcData.Dialogue];
                    }

                    var j:Number = 0;
                    while (j < dialogueArray.length) {
                        var dialogue:Object = dialogueArray[j];
                        var dialogueObj:Object = {};

                        dialogueObj.TaskRequirement = dialogue.TaskRequirement ? Number(dialogue.TaskRequirement) : 0;

                        if (dialogue.SubDialogue != null) {
                            var subArray;
                            if (dialogue.SubDialogue instanceof Array) {
                                subArray = dialogue.SubDialogue;
                            } else {
                                subArray = [dialogue.SubDialogue];
                            }

                            var converted:Array = [];
                            var k:Number = 0;
                            while (k < subArray.length) {
                                var sub:Object = subArray[k];
                                var c:Object = {};
                                c.name = sub.Name || sub.name;
                                c.title = sub.Title || sub.title;
                                c.char = sub.Char || sub.char;
                                c.text = sub.Text || sub.text;
                                c.id = sub.id;
                                c.target = sub.Target || sub.target;
                                c.imageurl = sub.ImageUrl || sub.imageurl;
                                converted.push(c);
                                k++;
                            }
                            dialogueObj.Dialogue = converted;
                        } else {
                            dialogueObj.Dialogue = [dialogue];
                        }

                        acc[npcName].push(dialogueObj);
                        j++;
                    }
                }
            }
            i++;
        }
        return acc;
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

    /**
     * 卸载NPC对话数据，释放内存。
     * 同时清除基类缓存和合并数据。
     */
    public function unload():Void {
        this.combinedData = null;
        super.clearCache();
        trace("[NpcDialogueLoader] 对话数据已卸载");
    }

    /**
     * 检查对话数据是否已加载。
     * @return Boolean 如果数据已加载，返回 true；否则返回 false。
     */
    public function isDialogueLoaded():Boolean {
        return this.combinedData != null;
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
        trace("合并后的数据: " + ObjectUtil.stringify(combinedData));
        // 在此处处理合并后的NPC对话数据
        _root.NPC对话 = combinedData;
    },
    function():Void {
        trace("主程序：NPC对话数据加载失败！");
    }
);

*/