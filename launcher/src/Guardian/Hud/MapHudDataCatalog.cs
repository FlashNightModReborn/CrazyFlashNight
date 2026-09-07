using System;
using System.Collections.Generic;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>由同一 C# 地图域投影替换的内存 HUD 索引；没有 JSON sidecar 或独立磁盘加载入口。</summary>
    public class MapHudDataCatalog
    {
        public const int SUPPORTED_PROTOCOL_VERSION = 1;
        private sealed class Snapshot
        {
            public readonly Dictionary<string, MapHudHotspotEntry> Entries = new(StringComparer.Ordinal);
            public readonly int? ProtocolVersion;
            public readonly string GeneratedAt;
            public Snapshot(MapHudPayload payload)
            {
                ProtocolVersion = payload?.ProtocolVersion; GeneratedAt = payload?.GeneratedAt;
                if (payload?.Hotspots != null)
                    foreach (var pair in payload.Hotspots)
                        if (!string.IsNullOrEmpty(pair.Key) && pair.Value != null) Entries[pair.Key] = pair.Value;
            }
        }
        private volatile Snapshot _snapshot;
        private MapHudDataCatalog(MapHudPayload payload) { _snapshot = new Snapshot(payload); }
        public bool IsAvailable => _snapshot.Entries.Count > 0;
        public int? ProtocolVersion => _snapshot.ProtocolVersion;
        public string GeneratedAt => _snapshot.GeneratedAt;
        public int HotspotCount => _snapshot.Entries.Count;
        public void ReplacePayload(MapHudPayload payload) { _snapshot = new Snapshot(payload); }
        public MapHudHotspotEntry GetEntry(string hotspotId)
        {
            if (string.IsNullOrEmpty(hotspotId)) return null;
            return _snapshot.Entries.TryGetValue(hotspotId, out var entry) ? entry : null;
        }
        public static MapHudDataCatalog FromPayload(MapHudPayload payload) => new(payload);
    }
}
