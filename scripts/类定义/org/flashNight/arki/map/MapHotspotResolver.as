/**
 * 文件：org/flashNight/arki/map/MapHotspotResolver.as
 * 说明：WebView 地图面板的当前热点解析器（含 pending/TTL 状态机）。
 *
 * 背景：
 *   跨一级菜单跳转时，_root._currentlabel 可能继续停在旧房间；
 *   因此解析时先读真实场景源，再在"底层仍停留旧房间/空值"时使用 pending target 兜底。
 *
 * 状态：
 *   _pendingHotspotId        — navigate 预期进入的目标 hotspot
 *   _pendingSourceHotspotId  — navigate 触发时记录的源 hotspot
 *   _lastResolvedHotspotId   — 上一次成功解析的 hotspot（空状态时的 fallback）
 *   _pendingStaleTicks       — pending 连续多少次解析仍未被 source 追上
 *   _pendingMaxStaleTicks    — 超过这个阈值强制清空 pending, fallback 到 source
 *
 * 四源定义（按权威度排列）：
 *   _root.关卡标志        — 当前场景标识（外部地图/基地部分地图的权威源，场景切换前即更新）
 *   _root._currentlabel   — Flash 内置当前帧标签（时间轴异步，跨一级菜单跳转时会滞后）
 *   _root.场景进入位置名  — 场景进入位置名
 *   _root.关卡地图帧值    — 关卡地图帧值
 *
 * 排序原因：跳转地图 → gotoAndPlay("基地地图"|"外部地图") 前，关卡标志已写入新值，
 * 但 _currentlabel 要等时间轴跑到目标帧才更新；先取 _currentlabel 会在 gap 窗口
 * 内解析出旧 hotspot 造成 HUD 高亮错误房间。
 */

import org.flashNight.arki.map.MapPanelCatalog;

class org.flashNight.arki.map.MapHotspotResolver {
    private static var _pendingHotspotId:String = "";
    private static var _pendingSourceHotspotId:String = "";
    private static var _lastResolvedHotspotId:String = "";
    private static var _pendingStaleTicks:Number = 0;
    private static var _pendingMaxStaleTicks:Number = 6;

    /**
     * 从四源解析当前 hotspotId（不考虑 pending）。
     * 命中顺序：关卡标志 → _currentlabel → 场景进入位置名 → 关卡地图帧值。
     * 对 _currentlabel 命中的结果额外用 isHotspotCompatibleWithRuntime 过滤，
     * 避免跳图中 label 残留旧值时返回上一 scene kind 的 hotspot。
     */
    public static function resolveCurrentFromSources():String {
        var hotspotId:String = MapPanelCatalog.resolveHotspotIdByFrameName(
            String(_root.关卡标志 || ""));
        if (hotspotId != "") return hotspotId;

        hotspotId = MapPanelCatalog.resolveHotspotIdByFrameName(
            String(_root._currentlabel || ""));
        if (hotspotId != "" && isHotspotCompatibleWithRuntime(hotspotId)) return hotspotId;

        hotspotId = MapPanelCatalog.resolveHotspotIdByFrameName(
            String(_root.场景进入位置名 || ""));
        if (hotspotId != "" && isHotspotCompatibleWithRuntime(hotspotId)) return hotspotId;

        hotspotId = MapPanelCatalog.resolveHotspotIdByFrameName(
            String(_root.关卡地图帧值 || ""));
        if (hotspotId != "" && isHotspotCompatibleWithRuntime(hotspotId)) return hotspotId;
        return "";
    }

    /**
     * 判断当前真实场景源是否已经位于指定地图帧。
     * 只读 source，不读 pending，避免刚发起跳转时把乐观目标误判为已到达。
     */
    public static function isCurrentFrameName(frameName:String):Boolean {
        if (frameName == undefined || frameName == "") return false;
        if (_root.当前为战斗地图 == true) return false;

        var targetHotspotId:String = MapPanelCatalog.resolveHotspotIdByFrameName(String(frameName));
        if (targetHotspotId == "") return false;
        return resolveCurrentFromSources() == targetHotspotId;
    }

    private static function resolveRuntimeSceneKind():String {
        if (_root.当前为战斗地图 == true) return "combat";

        var stageFlagHotspotId:String = MapPanelCatalog.resolveHotspotIdByFrameName(
            String(_root.关卡标志 || ""));
        if (stageFlagHotspotId != "") {
            var pageId:String = String(MapPanelCatalog.resolvePageId(stageFlagHotspotId) || "base");
            return pageId == "base" ? "base" : "outdoor";
        }

        var currentLabel:String = String(_root._currentlabel || "");
        if (currentLabel == "基地地图") return "base";
        if (currentLabel == "外部地图") return "outdoor";
        return "";
    }

    private static function isHotspotCompatibleWithRuntime(hotspotId:String):Boolean {
        var sceneKind:String = resolveRuntimeSceneKind();
        var pageId:String;
        if (hotspotId == undefined || hotspotId == "") return false;
        if (sceneKind == "") return true;
        if (sceneKind == "combat") return false;

        pageId = String(MapPanelCatalog.resolvePageId(hotspotId) || "base");
        if (sceneKind == "base") return pageId == "base";
        if (sceneKind == "outdoor") return pageId != "base";
        return true;
    }

    /**
     * 考虑 pending/TTL 的当前 hotspotId 解析。
     *
     * 三种场景：
     *   1) pending == source：跳转已生效，清空 pending，返回 source
     *   2) source 为空 或 source == oldSource：还在追齐，增加 stale 计数；
     *      超阈值时强制清空 pending，fallback 到 source/last
     *   3) source 到达"第三个位置"（既非 pending 也非 oldSource）：清空 pending，直接用 source
     *   无 pending 时直接返回 source 或 last。
     */
    public static function resolveCurrent():String {
        var sourceHotspotId:String = resolveCurrentFromSources();
        var pendingHotspotId:String = String(_pendingHotspotId || "");
        var pendingSourceHotspotId:String = String(_pendingSourceHotspotId || "");

        if (pendingHotspotId != "") {
            if (sourceHotspotId == pendingHotspotId) {
                _pendingHotspotId = "";
                _pendingSourceHotspotId = "";
                _pendingStaleTicks = 0;
                _lastResolvedHotspotId = sourceHotspotId;
                return sourceHotspotId;
            }

            if (sourceHotspotId == "" || sourceHotspotId == pendingSourceHotspotId) {
                // source 滞后或回到起始态，继续用 pending，累加 stale 计数
                _pendingStaleTicks = Number(_pendingStaleTicks || 0) + 1;
                if (_pendingStaleTicks >= Number(_pendingMaxStaleTicks || 6)) {
                    // TTL 到期：跳转可能失败，强制清空 pending，fallback 回 source
                    _pendingHotspotId = "";
                    _pendingSourceHotspotId = "";
                    _pendingStaleTicks = 0;
                    if (sourceHotspotId != "") {
                        _lastResolvedHotspotId = sourceHotspotId;
                        return sourceHotspotId;
                    }
                    if (isHotspotCompatibleWithRuntime(String(_lastResolvedHotspotId || ""))) {
                        return String(_lastResolvedHotspotId || "");
                    }
                    return "";
                }
                _lastResolvedHotspotId = pendingHotspotId;
                return pendingHotspotId;
            }

            // source 到达第三个位置（既不是 pending 也不是 old source），清空 pending
            _pendingHotspotId = "";
            _pendingSourceHotspotId = "";
            _pendingStaleTicks = 0;
        }

        if (sourceHotspotId != "") {
            _lastResolvedHotspotId = sourceHotspotId;
            return sourceHotspotId;
        }

        if (isHotspotCompatibleWithRuntime(String(_lastResolvedHotspotId || ""))) {
            return String(_lastResolvedHotspotId || "");
        }
        return "";
    }

    /**
     * navigate 触发时调用：
     * 记录 pending 目标 + 当前 source snapshot + 重置 stale 计数，
     * 并把 lastResolved 乐观设置为 target（让后续 snapshot 立即反映预期）。
     */
    public static function beginPending(targetHotspotId:String):Void {
        _pendingSourceHotspotId = resolveCurrentFromSources();
        _pendingHotspotId = String(targetHotspotId || "");
        _pendingStaleTicks = 0;
        _lastResolvedHotspotId = String(targetHotspotId || "");
    }

    /** 测试 / 切场景时重置所有状态 */
    public static function reset():Void {
        _pendingHotspotId = "";
        _pendingSourceHotspotId = "";
        _lastResolvedHotspotId = "";
        _pendingStaleTicks = 0;
    }
}
