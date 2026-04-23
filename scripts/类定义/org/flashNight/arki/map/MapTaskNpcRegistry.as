import org.flashNight.arki.map.MapPanelCatalog;
import org.flashNight.gesh.xml.XMLParser;

/**
 * 文件：org/flashNight/arki/map/MapTaskNpcRegistry.as
 * 说明：WebView 地图面板的任务 NPC 坐标 registry。
 *
 * 职责：
 *   - 维护 NPC 原名 → marker 定义的映射（包括 alias 别名与小写 fallback 查询）
 *   - 数据由 data/map/map_panel.xml 启动时经 applyFromXml 填充（必须在 MapPanelCatalog.applyFromXml 成功之后调用）
 *   - 对外提供按 _root.tasks_to_do 筛选的 marker 投影（buildTaskNpcMarkers）
 *
 * marker 结构：{ pageId:String, hotspotId:String, point:{x:Number, y:Number} }
 */

class org.flashNight.arki.map.MapTaskNpcRegistry {
    private static var _aliases:Object;
    private static var _markers:Object;
    private static var _markersLower:Object;

    public static var isLoaded:Boolean = false;

    private static var _seeded:Boolean = seedAll();

    // Canonical whitelist：XML 必须至少包含这 54 个 canonical npc name（允许超集）
    // alias 的名字不算；新增/改名 npc 属于设计变更，需同步更新此处 + XML
    private static var REQUIRED_NPC_NAMES:Array = [
        "Pig", "Boy", "King", "冷兵器商人", "杀马特",
        "酒保", "格格巫", "丽丽丝", "舞女",
        "宝石线人", "前治安官", "黑铁会外交部长", "学生妹", "幸存老兵",
        "The Girl", "Andy Law", "Shop Girl", "Blue", "小F",
        "厨师",
        "general", "gazer", "director", "itinerant", "surveyor",
        "singer", "keyboard", "guitar",
        "火凤", "翅虎", "黑龙", "黑铁",
        "牛仔", "假肢仙人", "吸特乐",
        "artist", "soldier", "排骨", "机哥", "阿波", "PROPHET",
        "黑仔", "Bat", "Tomboy", "武器订购系统",
        "体育老师", "室友", "程铮", "剑道社长", "冯佑权",
        "理科教授", "文科老师", "Vanshuther", "教导主任"
    ];

    /**
     * 登记一个 NPC marker。小写 fallback key 遵循 "先来先占" 语义：
     * 同一小写键只在未被占用时写入。
     */
    public static function register(npcName:String, pageId:String,
                                     hotspotId:String, x:Number, y:Number):Void {
        var markerDef:Object = {
            pageId: pageId,
            hotspotId: hotspotId,
            point: { x: x, y: y }
        };
        _markers[npcName] = markerDef;

        var normalizedKey:String = String(npcName).toLowerCase();
        if (_markersLower[normalizedKey] == undefined) {
            _markersLower[normalizedKey] = markerDef;
        }
    }

    /** 查 alias 表；未命中返回原名 */
    public static function resolveAliasKey(npcName:String):String {
        if (npcName == undefined || npcName == "") return "";
        if (_aliases[npcName] != undefined) {
            return String(_aliases[npcName]);
        }
        return npcName;
    }

    /** 三级查询：原样 → alias → 小写 fallback */
    public static function findMarker(npcName:String):Object {
        if (npcName == undefined || npcName == "") return undefined;

        var resolvedName:String = resolveAliasKey(String(npcName));
        if (_markers[resolvedName] != undefined) {
            return _markers[resolvedName];
        }

        var normalizedKey:String = String(resolvedName).toLowerCase();
        if (_markersLower[normalizedKey] != undefined) {
            return _markersLower[normalizedKey];
        }

        return undefined;
    }

    /**
     * 扫描当前 _root.tasks_to_do，对每个已完成前置条件的任务，
     * 按 finish_npc 找到 marker 并去重投影为 marker 数组。
     */
    public static function buildTaskNpcMarkers():Array {
        var markers:Array = [];
        var seen:Object = {};
        var tasks:Array = _root.tasks_to_do;
        if (tasks == undefined) return markers;

        for (var i:Number = 0; i < tasks.length; i++) {
            if (!_root.taskCompleteCheck(i)) continue;

            var taskData:Object = _root.getTaskData(tasks[i].id);
            if (taskData == undefined) continue;
            if (taskData.finish_npc == undefined) continue;

            var finishNpc:String = resolveAliasKey(String(taskData.finish_npc));
            if (finishNpc == "" || seen[finishNpc]) continue;

            var markerDef:Object = findMarker(finishNpc);
            if (markerDef == undefined) continue;

            seen[finishNpc] = true;
            markers.push({
                id: "task_npc_" + finishNpc,
                kind: "taskNpc",
                pageId: markerDef.pageId,
                hotspotId: markerDef.hotspotId,
                point: {
                    x: markerDef.point.x,
                    y: markerDef.point.y
                }
            });
        }

        return markers;
    }

    /**
     * 从 XML parse 结果填表。任一校验失败 → trace + 回退空字典 + 返回 false。
     * 前置：调用者必须确保 MapPanelCatalog.applyFromXml 已先行成功（本方法读 Catalog.HOTSPOT_PAGES
     * 派生 npc.pageId）。
     *
     * @param raw  MapPanelLoader 成功回调拿到的 data 对象（即 <map_panel> 内容，非 {map_panel: ...}）
     * @return Boolean 是否成功
     */
    public static function applyFromXml(raw:Object):Boolean {
        if (raw == null) { trace("[MapTaskNpcRegistry] raw 为 null"); return false; }
        var taskNpcs:Object = raw.task_npcs;
        var npcList:Array = (taskNpcs == undefined) ? [] : XMLParser.configureDataAsArray(taskNpcs.npc);
        var aliasList:Array = (taskNpcs == undefined) ? [] : XMLParser.configureDataAsArray(taskNpcs.alias);

        // 重置（reload 场景 + 失败也回空字典）
        _aliases = {};
        _markers = {};
        _markersLower = {};

        var i:Number;

        // 1) npc 结构 + 类型 + 名字冲突（含大小写折叠）
        var npcNameSet:Object = {};
        var npcNameLowerSet:Object = {};
        for (i = 0; i < npcList.length; i++) {
            var n:Object = npcList[i];
            if (n.name == undefined || n.name == "") { trace("[MapTaskNpcRegistry] npc[" + i + "] 缺 name"); return false; }
            if (n.hotspot == undefined || n.hotspot == "") { trace("[MapTaskNpcRegistry] npc '" + n.name + "' 缺 hotspot"); return false; }
            if (n.x == undefined || n.y == undefined) { trace("[MapTaskNpcRegistry] npc '" + n.name + "' 缺 x 或 y"); return false; }
            var nx:Number = Number(n.x);
            var ny:Number = Number(n.y);
            if (isNaN(nx) || isNaN(ny)) { trace("[MapTaskNpcRegistry] npc '" + n.name + "' 坐标非数字"); return false; }
            var nameStr:String = String(n.name);
            var nameLower:String = nameStr.toLowerCase();
            if (npcNameSet[nameStr] != undefined) { trace("[MapTaskNpcRegistry] npc name 重复: " + nameStr); return false; }
            if (npcNameLowerSet[nameLower] != undefined) { trace("[MapTaskNpcRegistry] npc name 仅大小写不同冲突: " + nameStr + " vs " + npcNameLowerSet[nameLower]); return false; }
            npcNameSet[nameStr] = true;
            npcNameLowerSet[nameLower] = nameStr;
        }

        // 2) 关系校验：npc.hotspot 必须在 Catalog 里已登记
        for (i = 0; i < npcList.length; i++) {
            var n2:Object = npcList[i];
            if (MapPanelCatalog.HOTSPOT_PAGES[String(n2.hotspot)] == undefined) {
                trace("[MapTaskNpcRegistry] npc '" + n2.name + "' 指向未登记热点: " + n2.hotspot);
                return false;
            }
        }

        // 3) alias 校验：结构、名字冲突（与 npc 同名 / 两 alias 同名）、canonical 必须命中
        var aliasNameSet:Object = {};
        for (i = 0; i < aliasList.length; i++) {
            var a:Object = aliasList[i];
            if (a.name == undefined || a.name == "") { trace("[MapTaskNpcRegistry] alias[" + i + "] 缺 name"); return false; }
            if (a.canonical == undefined || a.canonical == "") { trace("[MapTaskNpcRegistry] alias '" + a.name + "' 缺 canonical"); return false; }
            var an:String = String(a.name);
            var ac:String = String(a.canonical);
            if (npcNameSet[an] != undefined) { trace("[MapTaskNpcRegistry] alias name '" + an + "' 与已有 npc 重名"); return false; }
            if (aliasNameSet[an] != undefined) { trace("[MapTaskNpcRegistry] alias name 重复: " + an); return false; }
            if (npcNameSet[ac] == undefined) { trace("[MapTaskNpcRegistry] alias '" + an + "' 的 canonical='" + ac + "' 未命中任何 npc"); return false; }
            aliasNameSet[an] = true;
        }

        // 4) Canonical 完整性（⊇ REQUIRED_NPC_NAMES，允许超集）
        var missing:Array = [];
        for (i = 0; i < REQUIRED_NPC_NAMES.length; i++) {
            if (npcNameSet[REQUIRED_NPC_NAMES[i]] == undefined) missing.push(REQUIRED_NPC_NAMES[i]);
        }
        if (missing.length > 0) {
            trace("[MapTaskNpcRegistry] REQUIRED_NPC_NAMES 缺少: " + missing.join(", "));
            return false;
        }

        // 通过校验，开始填表
        for (i = 0; i < npcList.length; i++) {
            var n3:Object = npcList[i];
            var hid:String = String(n3.hotspot);
            register(
                String(n3.name),
                String(MapPanelCatalog.HOTSPOT_PAGES[hid]),  // page 由 Catalog 派生
                hid,
                Number(n3.x),
                Number(n3.y)
            );
        }
        for (i = 0; i < aliasList.length; i++) {
            var a2:Object = aliasList[i];
            _aliases[String(a2.name)] = String(a2.canonical);
        }

        isLoaded = true;
        return true;
    }

    private static function seedAll():Boolean {
        _aliases = {};
        _markers = {};
        _markersLower = {};
        return true;
    }
}
