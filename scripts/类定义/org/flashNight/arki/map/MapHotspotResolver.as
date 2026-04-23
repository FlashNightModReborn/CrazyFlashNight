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
 * 三源定义：
 *   _root._currentlabel   — Flash 内置当前帧标签
 *   _root.场景进入位置名  — 场景进入位置名
 *   _root.关卡地图帧值    — 关卡地图帧值
 */

import org.flashNight.arki.map.MapPanelCatalog;

class org.flashNight.arki.map.MapHotspotResolver {
    private static var _pendingHotspotId:String = "";
    private static var _pendingSourceHotspotId:String = "";
    private static var _lastResolvedHotspotId:String = "";
    private static var _pendingStaleTicks:Number = 0;
    private static var _pendingMaxStaleTicks:Number = 6;

    /**
     * 从三源解析当前 hotspotId（不考虑 pending）。
     * 命中顺序：_currentlabel → 场景进入位置名 → 关卡地图帧值。
     */
    public static function resolveCurrentFromSources():String {
        var hotspotId:String = MapPanelCatalog.resolveHotspotIdByFrameName(
            String(_root._currentlabel || ""));
        if (hotspotId != "") return hotspotId;

        hotspotId = MapPanelCatalog.resolveHotspotIdByFrameName(
            String(_root.场景进入位置名 || ""));
        if (hotspotId != "") return hotspotId;

        hotspotId = MapPanelCatalog.resolveHotspotIdByFrameName(
            String(_root.关卡地图帧值 || ""));
        return hotspotId;
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
                    return String(_lastResolvedHotspotId || "");
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

        return String(_lastResolvedHotspotId || "");
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
