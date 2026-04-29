using System;
using System.Collections.Generic;
using System.IO;
using Newtonsoft.Json;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 启动期加载 launcher/data/map_hud_data.json，按 hotspotId 提供 outline + meta 查询。
    ///
    /// 数据通路：
    ///   build-time: tools/export-maphud-data.js 调 MapPanelData.resolveHotspotMeta + getHudOutline
    ///               遍历所有 hotspotId → 写入 launcher/data/map_hud_data.json
    ///   runtime:    MapHudDataCatalog.LoadFromDataDir 反序列化进 dict
    ///   widget:     MapHudWidget 收到 mh UiData → catalog.GetEntry(hotspotId) → render
    ///
    /// missing-field policy：JSON 缺失或文件读不到 → IsAvailable=false，widget 静默退化为不渲染。
    /// 不抛异常，启动期失败只 log + 关 HUD。
    /// </summary>
    public class MapHudDataCatalog
    {
        public const int SUPPORTED_PROTOCOL_VERSION = 1;

        // P2-2 perf：catalog 支持"后台异步填充"模式。LoadAsync 立即返回空 catalog，
        // 后台线程读 JSON 完成后原子替换 _byId / metadata。GetEntry 在加载前返回 null
        // —— widget 已能处理 null（`if (_mapEntry == null) return`），不渲染地图直到加载完成。
        // 主线程不再被 162 KB JSON 反序列化阻塞。
        private volatile Dictionary<string, MapHudHotspotEntry> _byId;
        private volatile bool _available;
        private int? _protocolVersion;
        private string _generatedAt;

        public bool IsAvailable { get { return _available; } }
        public int? ProtocolVersion { get { return _protocolVersion; } }
        public string GeneratedAt { get { return _generatedAt; } }
        public int HotspotCount { get { Dictionary<string, MapHudHotspotEntry> snap = _byId; return snap == null ? 0 : snap.Count; } }

        private MapHudDataCatalog(MapHudPayload payload, bool available)
        {
            _available = available;
            _byId = BuildIndex(payload, out _protocolVersion, out _generatedAt);
        }

        private static Dictionary<string, MapHudHotspotEntry> BuildIndex(MapHudPayload payload, out int? protocolVersion, out string generatedAt)
        {
            Dictionary<string, MapHudHotspotEntry> byId = new Dictionary<string, MapHudHotspotEntry>(StringComparer.Ordinal);
            protocolVersion = null;
            generatedAt = null;
            if (payload != null)
            {
                protocolVersion = payload.ProtocolVersion;
                generatedAt = payload.GeneratedAt;
                if (payload.Hotspots != null)
                {
                    foreach (KeyValuePair<string, MapHudHotspotEntry> kv in payload.Hotspots)
                    {
                        if (string.IsNullOrEmpty(kv.Key) || kv.Value == null) continue;
                        byId[kv.Key] = kv.Value;
                    }
                }
            }
            return byId;
        }

        /// <summary>
        /// 按 hotspotId 查 outline + meta；找不到 / 后台加载未完成时返回 null（widget 会清屏）。
        /// </summary>
        public MapHudHotspotEntry GetEntry(string hotspotId)
        {
            if (string.IsNullOrEmpty(hotspotId)) return null;
            Dictionary<string, MapHudHotspotEntry> snap = _byId;
            if (snap == null) return null;
            MapHudHotspotEntry entry;
            if (snap.TryGetValue(hotspotId, out entry)) return entry;
            return null;
        }

        /// <summary>所有 asset URL 集合（去重）；用于 P2-1 prewarm 预加载 silhouette PNG。</summary>
        public IEnumerable<string> EnumerateAssetUrls()
        {
            Dictionary<string, MapHudHotspotEntry> snap = _byId;
            if (snap == null) yield break;
            HashSet<string> seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (KeyValuePair<string, MapHudHotspotEntry> kv in snap)
            {
                MapHudHotspotEntry entry = kv.Value;
                if (entry == null || entry.Outline == null || entry.Outline.Visuals == null) continue;
                foreach (MapHudVisual v in entry.Outline.Visuals)
                {
                    if (v == null || string.IsNullOrEmpty(v.AssetUrl)) continue;
                    if (seen.Add(v.AssetUrl)) yield return v.AssetUrl;
                }
            }
        }

        /// <summary>
        /// 加载入口。失败时返回不可用 catalog（IsAvailable=false），不抛。
        /// </summary>
        public static MapHudDataCatalog LoadFromFile(string jsonPath)
        {
            try
            {
                if (string.IsNullOrEmpty(jsonPath) || !File.Exists(jsonPath))
                {
                    LogManager.Log("[MapHudCatalog] data file not found: " + (jsonPath ?? "<null>") + " — HUD disabled");
                    return new MapHudDataCatalog(null, false);
                }
                string raw = File.ReadAllText(jsonPath);
                JsonSerializerSettings settings = new JsonSerializerSettings();
                settings.MissingMemberHandling = MissingMemberHandling.Ignore;
                MapHudPayload payload = JsonConvert.DeserializeObject<MapHudPayload>(raw, settings);
                if (payload == null)
                {
                    LogManager.Log("[MapHudCatalog] payload parsed null from " + jsonPath + " — HUD disabled");
                    return new MapHudDataCatalog(null, false);
                }
                if (payload.ProtocolVersion == null)
                {
                    LogManager.Log("[MapHudCatalog] WARN: protocolVersion missing; assuming v" + SUPPORTED_PROTOCOL_VERSION);
                }
                else if (payload.ProtocolVersion.Value != SUPPORTED_PROTOCOL_VERSION)
                {
                    LogManager.Log("[MapHudCatalog] WARN: unsupported protocolVersion=" + payload.ProtocolVersion.Value
                                   + " (expected " + SUPPORTED_PROTOCOL_VERSION + "); attempting parse anyway");
                }
                int count = payload.Hotspots != null ? payload.Hotspots.Count : 0;
                LogManager.Log("[MapHudCatalog] loaded " + count + " hotspots from " + jsonPath
                               + " (generated " + (payload.GeneratedAt ?? "?") + ")");
                return new MapHudDataCatalog(payload, count > 0);
            }
            catch (Exception ex)
            {
                LogManager.Log("[MapHudCatalog] load failed: " + ex.Message + " — HUD disabled");
                return new MapHudDataCatalog(null, false);
            }
        }

        /// <summary>
        /// 测试用：直接从内存 payload 构建。
        /// </summary>
        public static MapHudDataCatalog FromPayload(MapHudPayload payload)
        {
            int count = (payload != null && payload.Hotspots != null) ? payload.Hotspots.Count : 0;
            return new MapHudDataCatalog(payload, count > 0);
        }

        /// <summary>
        /// P2-2 perf：异步加载入口。立即返回空 catalog；后台 ThreadPool 读完 JSON 后原子替换索引。
        /// 加载完成前 GetEntry 返回 null，widget 不渲染地图——视觉等价于"hotspot 未知"，无错位。
        /// 期望耗时（162 KB JSON）：~30-80 ms 全藏在 Flash 启动等待窗口。
        /// </summary>
        public static MapHudDataCatalog LoadFromFileAsync(string jsonPath)
        {
            MapHudDataCatalog catalog = new MapHudDataCatalog(null, false);
            System.Threading.ThreadPool.QueueUserWorkItem(delegate(object state)
            {
                try
                {
                    string path = (string)state;
                    if (string.IsNullOrEmpty(path) || !File.Exists(path))
                    {
                        LogManager.Log("[MapHudCatalog] async data file not found: " + (path ?? "<null>") + " — HUD disabled");
                        return;
                    }
                    string raw = File.ReadAllText(path);
                    JsonSerializerSettings settings = new JsonSerializerSettings();
                    settings.MissingMemberHandling = MissingMemberHandling.Ignore;
                    MapHudPayload payload = JsonConvert.DeserializeObject<MapHudPayload>(raw, settings);
                    if (payload == null)
                    {
                        LogManager.Log("[MapHudCatalog] async payload parsed null from " + path + " — HUD disabled");
                        return;
                    }
                    int? proto;
                    string generated;
                    Dictionary<string, MapHudHotspotEntry> idx = BuildIndex(payload, out proto, out generated);
                    catalog._protocolVersion = proto;
                    catalog._generatedAt = generated;
                    catalog._byId = idx; // volatile 写：后续 reader 能读到完整 dict
                    catalog._available = idx.Count > 0;
                    LogManager.Log("[MapHudCatalog] async loaded " + idx.Count + " hotspots from " + path
                                   + " (generated " + (generated ?? "?") + ")");
                    PerfTrace.Mark("mapHud.catalog_async_done", "count=" + idx.Count);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[MapHudCatalog] async load failed: " + ex.Message + " — HUD disabled");
                    PerfTrace.Mark("mapHud.catalog_async_failed", ex.Message);
                }
            }, jsonPath);
            return catalog;
        }
    }
}
