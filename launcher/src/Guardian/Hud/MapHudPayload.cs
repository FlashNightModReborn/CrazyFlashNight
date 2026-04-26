using System.Collections.Generic;
using Newtonsoft.Json;

namespace CF7Launcher.Guardian.Hud
{
    /// <summary>
    /// 顶层文档：tools/export-maphud-data.js 输出的 launcher/data/map_hud_data.json schema。
    /// MapHudDataCatalog 反序列化此结构，供 MapHudWidget 按 hotspotId 查询。
    ///
    /// missing-field policy（与计划硬约束 #6 / Phase 4.7.2 对齐）：
    /// - 所有 list 字段保持 null 而非默认 new List，区分"JSON 空数组 []"vs"字段缺失"
    /// - 反序列化用 MissingMemberHandling.Ignore；缺失字段在 catalog/widget 层 log + fallback，不抛
    /// </summary>
    public class MapHudPayload
    {
        [JsonProperty("protocolVersion")]
        public int? ProtocolVersion { get; set; }

        [JsonProperty("generatedAt")]
        public string GeneratedAt { get; set; }

        [JsonProperty("sourceFile")]
        public string SourceFile { get; set; }

        [JsonProperty("hotspots")]
        public Dictionary<string, MapHudHotspotEntry> Hotspots { get; set; }
    }

    public class MapHudHotspotEntry
    {
        [JsonProperty("meta")]
        public MapHudMeta Meta { get; set; }

        [JsonProperty("outline")]
        public MapHudOutline Outline { get; set; }
    }

    public class MapHudMeta
    {
        [JsonProperty("pageId")]
        public string PageId { get; set; }

        [JsonProperty("pageLabel")]
        public string PageLabel { get; set; }

        [JsonProperty("hotspotId")]
        public string HotspotId { get; set; }

        [JsonProperty("label")]
        public string Label { get; set; }

        [JsonProperty("sceneName")]
        public string SceneName { get; set; }

        /// <summary>unlock group id（如 "warlord"/"defense"），用于 widget 主题染色；空串 = 无 group</summary>
        [JsonProperty("group")]
        public string Group { get; set; }
    }

    public class MapHudOutline
    {
        [JsonProperty("focusFilterId")]
        public string FocusFilterId { get; set; }

        [JsonProperty("focusFilterLabel")]
        public string FocusFilterLabel { get; set; }

        [JsonProperty("viewportRect")]
        public RectF? ViewportRect { get; set; }

        [JsonProperty("currentRect")]
        public RectF? CurrentRect { get; set; }

        /// <summary>null = 字段缺失；非 null + 空 list = 显式空</summary>
        [JsonProperty("blocks")]
        public List<MapHudBlock> Blocks { get; set; }

        [JsonProperty("visuals")]
        public List<MapHudVisual> Visuals { get; set; }
    }

    public class MapHudBlock
    {
        [JsonProperty("hotspotId")]
        public string HotspotId { get; set; }

        [JsonProperty("label")]
        public string Label { get; set; }

        [JsonProperty("sourceRect")]
        public RectF? SourceRect { get; set; }
    }

    public class MapHudVisual
    {
        [JsonProperty("id")]
        public string Id { get; set; }

        [JsonProperty("label")]
        public string Label { get; set; }

        /// <summary>相对 launcher/web/ 的资源路径；MapHudWidget 必须做 path safety 校验后才加载</summary>
        [JsonProperty("assetUrl")]
        public string AssetUrl { get; set; }

        [JsonProperty("hotspotIds")]
        public List<string> HotspotIds { get; set; }

        [JsonProperty("sourceRect")]
        public RectF? SourceRect { get; set; }

        [JsonProperty("isCurrent")]
        public bool IsCurrent { get; set; }
    }

    /// <summary>
    /// AS2/JS 端 JSON rect 形态 {x,y,w,h}。不用 System.Drawing.RectangleF 是因为
    /// 它的 Location/Size 是 set-only 派生属性，Newtonsoft 反序列化会报 missing setter。
    /// </summary>
    public struct RectF
    {
        [JsonProperty("x")]
        public float X { get; set; }

        [JsonProperty("y")]
        public float Y { get; set; }

        [JsonProperty("w")]
        public float W { get; set; }

        [JsonProperty("h")]
        public float H { get; set; }
    }
}
