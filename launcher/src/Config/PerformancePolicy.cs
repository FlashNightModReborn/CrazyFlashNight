using System;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Config
{
    // Machine preference only. Runtime adoption is reported independently by the renderer.
    public sealed record PerformancePolicy(string Preset, string Mode, int MaxRenderHeight)
    {
        public static PerformancePolicy Default { get; } = new("balanced", "auto", 0);
        private static readonly int[] Heights = { 0, 360, 540, 720, 900, 1080, 1440, 2160 };
        public JObject ToJson() => new JObject {
            ["preset"] = Preset, ["mode"] = Mode, ["maxRenderHeight"] = MaxRenderHeight
        };
        public static bool TryParse(JToken value, out PerformancePolicy policy)
        {
            policy = null;
            if (value is not JObject obj || obj.Count != 3
                || obj["preset"]?.Type != JTokenType.String
                || obj["mode"]?.Type != JTokenType.String
                || obj["maxRenderHeight"]?.Type != JTokenType.Integer) return false;
            string preset = obj.Value<string>("preset"), mode = obj.Value<string>("mode");
            long height;
            try { height = obj.Value<long>("maxRenderHeight"); } catch { return false; }
            if (preset != "balanced" && preset != "performance" && preset != "quality") return false;
            if (mode != "auto" && mode != "fixed") return false;
            if (height < 0 || height > 2160 || !Heights.Contains((int)height)) return false;
            policy = new PerformancePolicy(preset, mode, (int)height);
            return true;
        }
    }
}
