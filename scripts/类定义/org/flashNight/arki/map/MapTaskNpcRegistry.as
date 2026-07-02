import org.flashNight.arki.map.MapPanelCatalog;

/**
 * 文件：org/flashNight/arki/map/MapTaskNpcRegistry.as
 * 说明：WebView 地图面板的任务 NPC ↔ hotspot registry。
 *
 * 职责：
 *   - 维护 NPC 原名 → marker 定义的映射（含 alias 别名与小写 fallback 查询）
 *   - 数据由 launcher 端 DataQueryTask("task_npc_registry") 派发，经 applyFromQuery 填充
 *   - 真相源 = launcher/web/modules/map-panel-data.js 的 staticAvatars + dynamicAvatars
 *     （tools/derive-task-npc-registry.js 在 build.ps1 Step 1b 派生为 JSON，由 launcher 缓存后查询返回）
 *   - 对外提供按 _root.tasks_to_do 筛选的 marker 投影（buildTaskNpcMarkers）
 *
 * marker 结构：{ npcName:String, pageId:String, hotspotId:String, placementId:String }
 *
 * 约束：
 *   - applyFromQuery 必须在 MapPanelCatalog.applyFromCatalogJson 成功之后调用（读 Catalog.HOTSPOT_PAGES 派生 page）
 *   - 校验责任在派生脚本 tools/derive-task-npc-registry.js（label 重复/大小写折叠冲突/hotspotId 存在性
 *     均在 build 阶段拦截）；本类只做轻量结构校验
 *   - NPC 头像视觉锚点完全由 launcher 端 staticAvatars / dynamicAvatars 决定；本 registry 与视觉
 *     现已共享同一真相源，新增 NPC 只需改 launcher 端那一份
 *
 * 失败语义：
 *   - applyFromQuery 失败 → registry 留空 dict，findMarker 全 miss，buildTaskNpcMarkers 返回 []
 *     → 地图任务红点不亮（但不阻塞游戏进入）。错误信息通过 _root.服务器.发布服务器消息 留痕
 *     （trace 在 release build 被剔除）
 */

class org.flashNight.arki.map.MapTaskNpcRegistry {
    private static var _aliases:Object;
    private static var _markers:Object;
    private static var _markersLower:Object;
    private static var _markersByPlacement:Object;

    public static var isLoaded:Boolean = false;

    private static var _seeded:Boolean = seedAll();

    /**
     * 登记一个 NPC marker。小写 fallback key 遵循 "先来先占" 语义：
     * 同一小写键只在未被占用时写入。
     */
    public static function register(npcName:String, pageId:String,
                                     hotspotId:String, placementId:String):Void {
        if (placementId == undefined || placementId == "") {
            placementId = npcName + "@" + hotspotId;
        }
        var markerDef:Object = {
            npcName: npcName,
            pageId: pageId,
            hotspotId: hotspotId,
            placementId: placementId
        };

        if (_markers[npcName] == undefined) _markers[npcName] = [];
        _markers[npcName].push(markerDef);
        _markersByPlacement[getNameHotspotKey(npcName, hotspotId)] = markerDef;

        var normalizedKey:String = String(npcName).toLowerCase();
        if (_markersLower[normalizedKey] == undefined) {
            _markersLower[normalizedKey] = [];
        }
        _markersLower[normalizedKey].push(markerDef);
    }

    /** 查 alias 表；未命中返回原名 */
    public static function resolveAliasKey(npcName:String):String {
        if (npcName == undefined || npcName == "") return "";
        if (_aliases[npcName] != undefined) {
            return String(_aliases[npcName]);
        }
        return npcName;
    }

    /** 三级查询：原样 → alias → 小写 fallback；hotspotId 为空时返回首个 placement（旧协议兼容） */
    public static function findMarker(npcName:String, hotspotId:String):Object {
        if (npcName == undefined || npcName == "") return undefined;

        var resolvedName:String = resolveAliasKey(String(npcName));
        var hotspot:String = (hotspotId == undefined) ? "" : String(hotspotId);
        if (hotspot != "") {
            var exact:Object = _markersByPlacement[getNameHotspotKey(resolvedName, hotspot)];
            if (exact != undefined) return exact;
        }

        var list:Array = _markers[resolvedName];
        var hit:Object = findInMarkerList(list, hotspot);
        if (hit != undefined) return hit;

        var normalizedKey:String = String(resolvedName).toLowerCase();
        hit = findInMarkerList(_markersLower[normalizedKey], hotspot);
        if (hit != undefined) return hit;

        return undefined;
    }

    private static function findInMarkerList(list:Array, hotspotId:String):Object {
        if (list == undefined || list.length == undefined || list.length == 0) return undefined;
        if (hotspotId != undefined && hotspotId != "") {
            for (var i:Number = 0; i < list.length; i++) {
                if (String(list[i].hotspotId) == hotspotId) return list[i];
            }
            return undefined;
        }
        return list[0];
    }

    private static function getNameHotspotKey(npcName:String, hotspotId:String):String {
        return String(npcName) + "\n" + String(hotspotId);
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
            var finishHotspot:String = taskData.finish_npc_hotspot != undefined ? String(taskData.finish_npc_hotspot) : "";
            if (finishNpc == "") continue;

            var markerDef:Object = findMarker(finishNpc, finishHotspot);
            if (markerDef == undefined) continue;
            var seenKey:String = String(markerDef.placementId);
            if (seen[seenKey]) continue;

            seen[seenKey] = true;
            markers.push({
                id: "task_npc_" + seenKey,
                kind: "taskNpc",
                npcName: finishNpc,
                placementId: seenKey,
                pageId: markerDef.pageId,
                hotspotId: markerDef.hotspotId
            });
        }

        return markers;
    }

    /**
     * 扫描 _root.tasks_to_do，按任务顺序收集所有已达成任务 finish_npc 对应的 hotspotId。
     * 去重、保持任务顺序；无命中返回空数组。
     * 上层（MapPanelService.resolveDeliverableState）负责挑选首个可导航的作为直传目标。
     */
    public static function collectDeliverableHotspotIds():Array {
        var result:Array = [];
        var tasks:Array = _root.tasks_to_do;
        if (tasks == undefined) return result;

        var seen:Object = {};
        for (var i:Number = 0; i < tasks.length; i++) {
            if (!_root.taskCompleteCheck(i)) continue;

            var taskData:Object = _root.getTaskData(tasks[i].id);
            if (taskData == undefined || taskData.finish_npc == undefined) continue;

            var finishNpc:String = resolveAliasKey(String(taskData.finish_npc));
            var finishHotspot:String = taskData.finish_npc_hotspot != undefined ? String(taskData.finish_npc_hotspot) : "";
            if (finishNpc == "") continue;

            var markerDef:Object = findMarker(finishNpc, finishHotspot);
            if (markerDef == undefined) continue;

            var hid:String = String(markerDef.hotspotId);
            if (seen[hid]) continue;
            seen[hid] = true;
            result.push(hid);
        }
        return result;
    }

    /**
     * 从 DataQueryTask("task_npc_registry") 响应填表。
     *
     * 前置：MapPanelCatalog.applyFromCatalogJson 已先行成功（本方法读 Catalog.HOTSPOT_PAGES 派生 npc.pageId）。
     * 任何结构校验失败 → 服务器消息留痕 + 回退空字典 + 返回 false。
     *
     * @param result 来自 DataQueryService.query callback 的 response.result，
     *               形如 { task_npcs: [{name, hotspot}], aliases: [{name, canonical}] }
     * @return Boolean 是否成功
     */
    public static function applyFromQuery(result:Object):Boolean {
        // 无条件重置为安全零值；reload 时若后续校验失败也不会留下旧 marker 造成 stale 混合态
        _aliases = {};
        _markers = {};
        _markersLower = {};
        _markersByPlacement = {};
        isLoaded = false;

        if (result == null) {
            logFail("result 为 null");
            return false;
        }

        var npcList:Array = (result.task_npcs == undefined) ? [] : result.task_npcs;
        var aliasList:Array = (result.aliases == undefined) ? [] : result.aliases;
        var i:Number;

        // 1) npc 结构 + placement 冲突（含大小写折叠）。
        //    派生脚本已校验过；这里保留 fail-fast 防御，避免脏数据流入 _markers。
        var npcNameSet:Object = {};
        var npcNameHotspotSet:Object = {};
        var npcNameLowerSet:Object = {};
        var npcPlacementSet:Object = {};
        for (i = 0; i < npcList.length; i++) {
            var n:Object = npcList[i];
            if (n.name == undefined || n.name == "") {
                logFail("npc[" + i + "] 缺 name");
                return false;
            }
            if (n.hotspot == undefined || n.hotspot == "") {
                logFail("npc '" + n.name + "' 缺 hotspot");
                return false;
            }
            var nameStr:String = String(n.name);
            var nameLower:String = nameStr.toLowerCase();
            var hotspotStr:String = String(n.hotspot);
            var nameHotspotKey:String = getNameHotspotKey(nameStr, hotspotStr);
            if (npcNameHotspotSet[nameHotspotKey] != undefined) {
                logFail("npc placement 重复: " + nameStr + " @ " + hotspotStr);
                return false;
            }
            if (npcNameLowerSet[nameLower] != undefined && npcNameLowerSet[nameLower] != nameStr) {
                logFail("npc name 仅大小写不同冲突: " + nameStr + " vs " + npcNameLowerSet[nameLower]);
                return false;
            }
            var placementStr:String = (n.placement != undefined && n.placement != "") ? String(n.placement) : (nameStr + "@" + hotspotStr);
            if (npcPlacementSet[placementStr] != undefined) {
                logFail("npc placement id 重复: " + placementStr);
                return false;
            }
            npcNameSet[nameStr] = true;
            npcNameHotspotSet[nameHotspotKey] = true;
            npcNameLowerSet[nameLower] = nameStr;
            npcPlacementSet[placementStr] = true;
        }

        // 2) hotspot 必须在 Catalog 里已登记
        for (i = 0; i < npcList.length; i++) {
            var n2:Object = npcList[i];
            if (MapPanelCatalog.HOTSPOT_PAGES[String(n2.hotspot)] == undefined) {
                logFail("npc '" + n2.name + "' 指向未登记热点: " + n2.hotspot);
                return false;
            }
        }

        // 3) alias 校验
        var aliasNameSet:Object = {};
        for (i = 0; i < aliasList.length; i++) {
            var a:Object = aliasList[i];
            if (a.name == undefined || a.name == "") {
                logFail("alias[" + i + "] 缺 name");
                return false;
            }
            if (a.canonical == undefined || a.canonical == "") {
                logFail("alias '" + a.name + "' 缺 canonical");
                return false;
            }
            var an:String = String(a.name);
            var ac:String = String(a.canonical);
            if (npcNameSet[an] != undefined) {
                logFail("alias name '" + an + "' 与已有 npc 重名");
                return false;
            }
            if (aliasNameSet[an] != undefined) {
                logFail("alias name 重复: " + an);
                return false;
            }
            if (npcNameSet[ac] == undefined) {
                logFail("alias '" + an + "' 的 canonical='" + ac + "' 未命中任何 npc");
                return false;
            }
            aliasNameSet[an] = true;
        }

        // 通过校验，开始填表
        for (i = 0; i < npcList.length; i++) {
            var n3:Object = npcList[i];
            var hid:String = String(n3.hotspot);
            register(
                String(n3.name),
                String(MapPanelCatalog.HOTSPOT_PAGES[hid]),
                hid,
                (n3.placement != undefined && n3.placement != "") ? String(n3.placement) : (String(n3.name) + "@" + hid)
            );
        }
        for (i = 0; i < aliasList.length; i++) {
            var a2:Object = aliasList[i];
            _aliases[String(a2.name)] = String(a2.canonical);
        }

        isLoaded = true;
        return true;
    }

    /**
     * 失败信息统一走服务器消息通道（trace 在 release build 被剔除，仅服务器日志可靠留痕）。
     */
    private static function logFail(reason:String):Void {
        if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
            _root.服务器.发布服务器消息("[MapTaskNpcRegistry] " + reason);
        }
    }

    private static function seedAll():Boolean {
        _aliases = {};
        _markers = {};
        _markersLower = {};
        _markersByPlacement = {};
        return true;
    }
}
