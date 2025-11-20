import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.EquipModListLoader extends BaseXMLLoader {
    private static var instance:EquipModListLoader = null;
    private static var path:String = "data/items/equipment_mods/";
    private var combinedData:Array = null;

    /**
     * 获取单例实例。
     * @return EquipModListLoader 实例。
     */
    public static function getInstance():EquipModListLoader {
        if (instance == null) {
            instance = new EquipModListLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function EquipModListLoader() { 
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现配件数据的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadModData(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，解析并合并其中的 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadModData(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:EquipModListLoader = this;

        // 加载 list.xml 文件
        super.load(function(data:Object):Void {
            trace("EquipModListLoader: list.xml 文件加载成功！");
            // trace("EquipModListLoader: list.xml 数据 = " + ObjectUtil.toString(data));

            if (!data || !data.items) {
                trace("EquipModListLoader: list.xml 数据结构不正确！");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }

            // 处理 data.items 可能是字符串或数组的情况
            var childXmlPaths:Array;
            if (data.items instanceof Array) {
                childXmlPaths = data.items;
            } else {
                // 如果是单个字符串，包装为数组
                childXmlPaths = [data.items];
            }
            trace("EquipModListLoader: 需要加载的子 XML 文件列表 = " + ObjectUtil.toString(childXmlPaths));

            self.combinedData = [];

            // 开始加载子 XML 文件
            self.loadChildXmlFiles(childXmlPaths, 0, function():Void {
                // 将合并后的数据保存到基类的 data 属性中
                super.data = {mod: self.combinedData};

                trace("EquipModListLoader: 所有子 XML 文件加载并合并成功！");
                trace("EquipModListLoader: 合并后的配件数量 = " + self.combinedData.length);
                if (onLoadHandler != null) {
                    onLoadHandler({mod: self.combinedData});
                }
            }, function():Void {
                trace("EquipModListLoader: 加载子 XML 文件失败！");
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            trace("EquipModListLoader: list.xml 文件加载失败！");
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
        var self:EquipModListLoader = this;

        if (index >= paths.length) {
            // 所有文件加载完成
            onComplete();
            return;
        }

        var xmlFileName:String = paths[index];
        var xmlFilePath:String = path + xmlFileName;
        trace("EquipModListLoader: 准备加载子 XML 文件 = " + xmlFilePath);

        var loader:BaseXMLLoader = new BaseXMLLoader(xmlFilePath);

        loader.load(function(childData:Object):Void {
            trace("EquipModListLoader: 子 XML 文件加载成功 = " + xmlFilePath);
            // trace("EquipModListLoader: 子 XML 数据 = " + ObjectUtil.toString(childData));

            // 处理 childData.mod，可能是单个对象或数组
            if (childData.mod) {
                if (childData.mod instanceof Array) {
                    // 如果是数组，直接合并
                    self.combinedData = self.combinedData.concat(childData.mod);
                    trace("EquipModListLoader: 从 " + xmlFileName + " 加载了 " + childData.mod.length + " 个配件");
                } else {
                    // 如果是单个对象，包装为数组
                    self.combinedData.push(childData.mod);
                    trace("EquipModListLoader: 从 " + xmlFileName + " 加载了 1 个配件");
                }
            }

            // 递归加载下一个文件
            self.loadChildXmlFiles(paths, index + 1, onComplete, onError);
        }, function():Void {
            trace("EquipModListLoader: 子 XML 文件加载失败 = " + xmlFilePath);
            onError();
        });
    }

    /**
     * 获取已加载的配件数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getModData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现配件数据的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空现有数据
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的配件数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return {mod: this.combinedData};
    }
}



/*

import org.flashNight.gesh.xml.LoadXml.EquipModListLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 获取 EquipModListLoader 实例
var modListLoader:EquipModListLoader = EquipModListLoader.getInstance();

// 加载配件数据
modListLoader.loadModData(
    function(data:Object):Void {
        trace("主程序：装备配件数据加载成功！");
        trace("主程序：配件总数 = " + data.mod.length);

        // 传递给 EquipmentUtil 进行初始化
        org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
    },
    function():Void {
        trace("主程序：装备配件数据加载失败！");
    }
);

*/
