import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.Promise;
import org.flashNight.aven.Promise.ListLoader;
import org.flashNight.aven.Promise.LoaderPromise;

class org.flashNight.gesh.xml.LoadXml.EquipModListLoader extends BaseXMLLoader {
    private static var instance:EquipModListLoader = null;
    private static var path:String = "data/items/equipment_mods/";
    private var combinedData:Array = null;
    private var presentationData:Object = null;

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
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadModData(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this.combinedData != null) {
            if (onLoadHandler != null) onLoadHandler({mod: this.combinedData, uiPresentation: this.presentationData});
            return;
        }
        var self:EquipModListLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.items) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.items);
            var presentationFile:String = String(data.uiPresentation || "ui_presentation.xml");

            var modPromise:Promise = ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                mergeFn:      EquipModListLoader.mergeModsWithSourceGrade,
                initialValue: []
            });
            var presentationPromise:Promise = LoaderPromise.loadXML(path + presentationFile);

            Promise.all([modPromise, presentationPromise]).then(function(result:Object):Void {
                var resultList = result;
                var arr = resultList[0];
                var presentation:Object = EquipModListLoader.buildPresentationIndex(resultList[1]);
                EquipModListLoader.applyPresentation(arr, presentation);
                self.combinedData = arr;
                self.presentationData = presentation;
                trace("EquipModListLoader: 合并后的配件数量 = " + self.combinedData.length);
                if (onLoadHandler != null) {
                    onLoadHandler({mod: self.combinedData, uiPresentation: self.presentationData});
                }
            }).onCatch(function(reason:Object):Void {
                trace("[EquipModListLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
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
        this.presentationData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的配件数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return {mod: this.combinedData, uiPresentation: this.presentationData};
    }

    /** 获取已解析的展示词典，供审计与测试读取。 */
    public function getPresentationData():Object {
        return this.presentationData;
    }

    /** 合并插件子文件，同时将来源文件前缀投影为稳定档级。 */
    private static function mergeModsWithSourceGrade(acc:Object, childData:Object, index:Number, entry:String):Object {
        var grade:String = resolveGradeFromEntry(entry);
        if (grade == null) throw new Error("未知插件材料档级文件: " + entry);
        var mods:Array = ListLoader.normalizeToArray(childData.mod);
        var target = acc;
        for (var i:Number = 0; i < mods.length; i++) {
            mods[i].uiGrade = grade;
            target.push(mods[i]);
        }
        return target;
    }

    private static function resolveGradeFromEntry(entry:String):String {
        if (entry.indexOf("低级材料_") == 0) return "low";
        if (entry.indexOf("中等材料_") == 0) return "medium";
        if (entry.indexOf("高等材料_") == 0) return "high";
        if (entry.indexOf("特殊材料_") == 0) return "special";
        return null;
    }

    /** 将 XMLParser 的标量/数组形状归一化为展示索引。 */
    private static function buildPresentationIndex(raw:Object):Object {
        if (raw == null) throw new Error("插件展示词典为空");
        var gradeDict:Object = {};
        var roleDict:Object = {};
        var tagRoleDict:Object = {};
        var grades:Array = ListLoader.normalizeToArray(raw.grade);
        var roles:Array = ListLoader.normalizeToArray(raw.role);
        var defaults:Array = ListLoader.normalizeToArray(raw.tagDefault);
        var i:Number;

        for (i = 0; i < grades.length; i++) {
            var gradeId:String = String(grades[i].id);
            var gradeColor:String = String(grades[i].color);
            if (!isValidGrade(gradeId) || !isValidColor(gradeColor)) {
                throw new Error("非法插件档级展示配置: " + gradeId + "/" + gradeColor);
            }
            gradeDict[gradeId] = {id: gradeId, label: String(grades[i].label), color: gradeColor};
        }
        for (i = 0; i < roles.length; i++) {
            var roleId:String = String(roles[i].id);
            var symbol:String = String(roles[i].symbol);
            if (roleId.length == 0 || !isValidSymbol(symbol)) {
                throw new Error("非法插件角色展示配置: " + roleId + "/" + symbol);
            }
            roleDict[roleId] = {id: roleId, label: String(roles[i].label), symbol: symbol};
        }
        for (i = 0; i < defaults.length; i++) {
            var tag:String = String(defaults[i].tag);
            var defaultRole:String = String(defaults[i].role);
            if (tag.length == 0 || roleDict[defaultRole] == undefined) {
                throw new Error("非法插件 tag 默认角色: " + tag + "/" + defaultRole);
            }
            tagRoleDict[tag] = defaultRole;
        }
        var fallbackRole:String = String(raw.fallbackRole || "utility");
        if (roleDict[fallbackRole] == undefined) throw new Error("插件展示兜底角色不存在: " + fallbackRole);
        return {gradeDict: gradeDict, roleDict: roleDict, tagRoleDict: tagRoleDict, fallbackRole: fallbackRole};
    }

    /** 解析优先级：插件显式 uiRole → tag 默认角色；未知声明一律阻止启动。 */
    private static function applyPresentation(mods:Array, presentation:Object):Void {
        for (var i:Number = 0; i < mods.length; i++) {
            var mod:Object = mods[i];
            var grade:Object = presentation.gradeDict[mod.uiGrade];
            if (grade == undefined) throw new Error("插件档级未注册: " + mod.name + "/" + mod.uiGrade);
            var hasExplicitRole:Boolean = mod.uiRole != undefined && String(mod.uiRole).length > 0;
            var roleId:String = hasExplicitRole ? String(mod.uiRole) : String(presentation.tagRoleDict[String(mod.tag)]);
            if (roleId.length == 0 || roleId == "undefined") {
                throw new Error("插件 tag 缺少默认展示角色: " + mod.name + "/" + mod.tag);
            }
            var role:Object = presentation.roleDict[roleId];
            if (role == undefined) throw new Error("插件声明了未知展示角色: " + mod.name + "/" + roleId);
            mod.uiGradeLabel = grade.label;
            mod.uiGradeColor = grade.color;
            mod.uiRole = role.id;
            mod.uiRoleLabel = role.label;
            mod.uiSymbol = role.symbol;
        }
    }

    private static function isValidGrade(id:String):Boolean {
        return id == "low" || id == "medium" || id == "high" || id == "special";
    }

    private static function isValidSymbol(symbol:String):Boolean {
        return symbol == "triangle-solid" || symbol == "triangle-outline"
            || symbol == "square-solid" || symbol == "square-outline"
            || symbol == "circle-solid" || symbol == "circle-outline"
            || symbol == "diamond-solid" || symbol == "diamond-outline"
            || symbol == "star-solid" || symbol == "star-outline";
    }

    private static function isValidColor(color:String):Boolean {
        return color == "#006600" || color == "#996600" || color == "#0099FF" || color == "#FFFF00";
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
