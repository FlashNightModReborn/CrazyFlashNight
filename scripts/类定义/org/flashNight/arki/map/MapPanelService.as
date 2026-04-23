/**
 * 文件：org/flashNight/arki/map/MapPanelService.as
 * 说明：WebView 地图面板的主服务类。
 *
 * 职责：
 *   - install(): 注册 4 个 gameCommands 入口（snapshot/navigate/close/openWebMap）
 *   - UnlockPolicy: 根据任务进度 + 基建状态判断 8 个分组的解锁状态
 *   - SnapshotBuilder: 组装面板快照（版本、默认页、热点状态、marker、tips 等）
 *   - 4 个 handler: 对外 gameCommand 业务实现
 *
 * 所有 handler 依赖 MapPanelCatalog / MapTaskNpcRegistry / MapHotspotResolver。
 * 响应协议：{ task:"map_response", callId, success, ... }
 */

import org.flashNight.arki.map.MapPanelCatalog;
import org.flashNight.arki.map.MapTaskNpcRegistry;
import org.flashNight.arki.map.MapHotspotResolver;

class org.flashNight.arki.map.MapPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;

    /** 帧脚本唯一入口：创建 LiteJSON + 注册 4 个 gameCommands */
    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["mapPanelSnapshot"] = function(params) {
            org.flashNight.arki.map.MapPanelService.handleSnapshot(params);
        };
        _root.gameCommands["mapPanelNavigate"] = function(params) {
            org.flashNight.arki.map.MapPanelService.handleNavigate(params);
        };
        _root.gameCommands["mapPanelClose"] = function(params) {
            org.flashNight.arki.map.MapPanelService.handleClose(params);
        };
        _root.gameCommands["openWebMap"] = function(params) {
            org.flashNight.arki.map.MapPanelService.handleOpenWebMap(params);
        };

        _inited = true;
    }

    // ─────────────────────────────────────────────
    // gameCommand handlers
    // ─────────────────────────────────────────────

    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        log("mapPanelSnapshot callId=" + callId);

        sendResponse({
            task: "map_response",
            callId: callId,
            success: true,
            snapshot: buildSnapshot()
        });
    }

    public static function handleNavigate(params:Object):Void {
        var callId = params.callId;
        var targetId:String = String(params.targetId);
        var targetFrame:String = MapPanelCatalog.NAVIGATE_TARGETS[targetId];
        log("mapPanelNavigate callId=" + callId + " targetId=" + targetId + " frame=" + targetFrame);

        var resp:Object = {
            task: "map_response",
            callId: callId
        };

        if (targetFrame == undefined) {
            resp.success = false;
            resp.error = "invalid_target";
            sendResponse(resp);
            return;
        }

        MapHotspotResolver.beginPending(targetId);
        performNavigate(targetFrame);

        resp.success = true;
        resp.closePanel = true;
        sendResponse(resp);
    }

    public static function handleClose(params:Object):Void {
        log("mapPanelClose");
    }

    /**
     * 旧版 Flash 地图界面（flashswf/UI/地图界面/LIBRARY/地图界面.xml 内
     * gotoAndStop(2) 的按钮）统一走此入口，接入 WebView 新地图面板。
     * 绕过旧 frame 跳转，避免双 UI。
     */
    public static function handleOpenWebMap(params:Object):Void {
        var source:String = (params != undefined && params.source != undefined)
            ? String(params.source)
            : "as2_legacy_button";
        log("openWebMap request source=" + source);

        // 旧 Flash 地图如果已经跳到 frame 2，先收回避免双叠
        if (_root.地图界面 != undefined && _root.地图界面.gotoAndStop != undefined) {
            _root.地图界面.gotoAndStop(1);
        }

        // 交给 Launcher 打开 WebView 面板，不再隐藏 gameworld（WebView overlay 自己会盖住）
        if (_root.server != undefined && _root.server.sendSocketMessage != undefined) {
            _root.server.sendSocketMessage(
                '{"task":"panel_request","panel":"map","source":"' + source + '"}');
        } else {
            log("openWebMap failed: server/sendSocketMessage unavailable");
        }
    }

    // ─────────────────────────────────────────────
    // UnlockPolicy（Phase 1 内联为 private static，未来可抽出为独立类）
    // ─────────────────────────────────────────────

    private static function getInfrastructure():Object {
        if (_root.基建系统 == undefined) return undefined;
        return _root.基建系统.infrastructure;
    }

    private static function isUnlocked(groupName:String):Boolean {
        var progress = _root.task_chains_progress;
        var p_main = (progress != undefined) ? progress.主线 : undefined;
        var p_uni = (progress != undefined) ? progress.大学 : undefined;
        var infra = getInfrastructure();

        switch (groupName) {
            case "warlord":
                return (p_main != undefined && infra != undefined && p_main >= 75 && infra.越野车);
            case "rock":
                return (p_main != undefined && infra != undefined && p_main >= 74 && (infra.摩托车 || infra.越野车));
            case "blackiron":
                return (p_main != undefined && infra != undefined && p_main >= 72 && (infra.摩托车 || infra.越野车));
            case "fallen":
                return (infra != undefined && (infra.摩托车 || infra.越野车));
            case "defense":
                return (p_main != undefined && infra != undefined && p_main >= 14 && (infra.自行车 || infra.摩托车 || infra.越野车));
            case "restricted":
                return (p_main != undefined && infra != undefined && p_main >= 76 && infra.越野车);
            case "schoolOutside":
                if (p_uni != undefined && p_uni >= 7) return true;
                return (p_main != undefined && infra != undefined && p_main >= 28 && (infra.摩托车 || infra.越野车));
            case "schoolInside":
                return (p_uni != undefined && p_uni >= 7);
            default:
                return false;
        }
    }

    private static function buildUnlockFlags():Object {
        return {
            warlord: isUnlocked("warlord"),
            rock: isUnlocked("rock"),
            blackiron: isUnlocked("blackiron"),
            fallen: isUnlocked("fallen"),
            defense: isUnlocked("defense"),
            restricted: isUnlocked("restricted"),
            schoolOutside: isUnlocked("schoolOutside"),
            schoolInside: isUnlocked("schoolInside")
        };
    }

    private static function pushList(target:Array, source:Array):Void {
        for (var i:Number = 0; i < source.length; i++) {
            target.push(source[i]);
        }
    }

    private static function buildEnabledHotspotIds():Array {
        var unlocks:Object = buildUnlockFlags();
        var enabled:Array = [];

        pushList(enabled, MapPanelCatalog.BASE_HOTSPOT_IDS);

        if (unlocks.warlord) pushList(enabled, MapPanelCatalog.GROUPED_HOTSPOT_IDS.warlord);
        if (unlocks.rock) pushList(enabled, MapPanelCatalog.GROUPED_HOTSPOT_IDS.rock);
        if (unlocks.blackiron) pushList(enabled, MapPanelCatalog.GROUPED_HOTSPOT_IDS.blackiron);
        if (unlocks.fallen) pushList(enabled, MapPanelCatalog.GROUPED_HOTSPOT_IDS.fallen);
        if (unlocks.defense) pushList(enabled, MapPanelCatalog.GROUPED_HOTSPOT_IDS.defense);
        if (unlocks.restricted) pushList(enabled, MapPanelCatalog.GROUPED_HOTSPOT_IDS.restricted);
        if (unlocks.schoolOutside) pushList(enabled, MapPanelCatalog.GROUPED_HOTSPOT_IDS.schoolOutside);
        if (unlocks.schoolInside) pushList(enabled, MapPanelCatalog.GROUPED_HOTSPOT_IDS.schoolInside);

        return enabled;
    }

    private static function buildHotspotStates(unlocks:Object):Object {
        var states:Object = {};
        var hotspotId:String;
        var groupName:String;
        var enabled:Boolean;
        var meta:Object;

        for (var i:Number = 0; i < MapPanelCatalog.BASE_HOTSPOT_IDS.length; i++) {
            hotspotId = MapPanelCatalog.BASE_HOTSPOT_IDS[i];
            states[hotspotId] = {
                enabled: true,
                unlockGroup: "",
                lockedReason: ""
            };
        }

        for (groupName in MapPanelCatalog.GROUPED_HOTSPOT_IDS) {
            enabled = !!unlocks[groupName];
            meta = MapPanelCatalog.UNLOCK_META[groupName];
            var group:Array = MapPanelCatalog.GROUPED_HOTSPOT_IDS[groupName];
            for (var j:Number = 0; j < group.length; j++) {
                hotspotId = group[j];
                states[hotspotId] = {
                    enabled: enabled,
                    unlockGroup: groupName,
                    lockedReason: enabled ? "" : (meta != undefined ? meta.lockedReason : "区域尚未开放")
                };
            }
        }

        return states;
    }

    // ─────────────────────────────────────────────
    // SnapshotBuilder
    // ─────────────────────────────────────────────

    private static function buildMarkers(currentHotspotId:String):Array {
        var markers:Array = MapTaskNpcRegistry.buildTaskNpcMarkers();
        if (currentHotspotId == undefined || currentHotspotId == "") return markers;

        markers.push({
            id: "current_location",
            kind: "currentLocation",
            pageId: MapPanelCatalog.resolvePageId(currentHotspotId),
            hotspotId: currentHotspotId,
            label: "当前位置",
            tone: "accent"
        });

        return markers;
    }

    private static function buildTips(currentHotspotId:String):Array {
        var tips:Array = [];
        if (currentHotspotId == undefined || currentHotspotId == "") return tips;

        tips.push({
            id: "current_scene",
            pageId: MapPanelCatalog.resolvePageId(currentHotspotId),
            hotspotId: currentHotspotId,
            label: "当前位置",
            tone: "accent"
        });

        return tips;
    }

    private static function buildSnapshot():Object {
        var roommateGender:String = "";
        var currentHotspotId:String = MapHotspotResolver.resolveCurrent();
        var currentPageId:String = MapPanelCatalog.resolvePageId(currentHotspotId);
        var unlocks:Object = buildUnlockFlags();
        if (_root.性别 != undefined) {
            roommateGender = String(_root.性别);
        }

        return {
            version: 2,
            defaultPageId: currentPageId,
            regionId: currentPageId,
            currentHotspotId: currentHotspotId,
            unlocks: unlocks,
            enabledHotspotIds: buildEnabledHotspotIds(),
            hotspotStates: buildHotspotStates(unlocks),
            dynamicAvatarState: {
                roommateGender: roommateGender
            },
            markers: buildMarkers(currentHotspotId),
            tips: buildTips(currentHotspotId)
        };
    }

    // ─────────────────────────────────────────────
    // 私有工具
    // ─────────────────────────────────────────────

    private static function log(msg:String):Void {
        if (_root.server != undefined) {
            _root.server.sendServerMessage("[MapWV] " + msg);
        }
    }

    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringify(resp));
    }

    /**
     * navigate 的 4 个副作用集中在此，便于未来替换跳转实现。
     * 顺序与原帧脚本严格一致。
     */
    private static function performNavigate(targetFrame:String):Void {
        _root.关卡结束界面._visible = 0;
        _root.场景进入位置名 = "出生地";
        _root.淡出动画.淡出跳转帧(targetFrame);
        if (_root.地图界面 != undefined && _root.地图界面.gotoAndStop != undefined) {
            _root.地图界面.gotoAndStop(1);
        }
    }
}
