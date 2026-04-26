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

        private readonly Dictionary<string, MapHudHotspotEntry> _byId;
        private readonly int? _protocolVersion;
        private readonly string _generatedAt;
        private readonly bool _available;

        public bool IsAvailable { get { return _available; } }
        public int? ProtocolVersion { get { return _protocolVersion; } }
        public string GeneratedAt { get { return _generatedAt; } }
        public int HotspotCount { get { return _byId.Count; } }

        private MapHudDataCatalog(MapHudPayload payload, bool available)
        {
            _available = available;
            _byId = new Dictionary<string, MapHudHotspotEntry>(StringComparer.Ordinal);
            if (payload != null)
            {
                _protocolVersion = payload.ProtocolVersion;
                _generatedAt = payload.GeneratedAt;
                if (payload.Hotspots != null)
                {
                    foreach (KeyValuePair<string, MapHudHotspotEntry> kv in payload.Hotspots)
                    {
                        if (string.IsNullOrEmpty(kv.Key) || kv.Value == null) continue;
                        _byId[kv.Key] = kv.Value;
                    }
                }
            }
        }

        /// <summary>
        /// 按 hotspotId 查 outline + meta；找不到返回 null（widget 会清屏）。
        /// </summary>
        public MapHudHotspotEntry GetEntry(string hotspotId)
        {
            if (string.IsNullOrEmpty(hotspotId)) return null;
            MapHudHotspotEntry entry;
            if (_byId.TryGetValue(hotspotId, out entry)) return entry;
            return null;
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
    }
}
