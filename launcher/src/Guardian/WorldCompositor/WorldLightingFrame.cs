using System;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.WorldCompositor
{
    internal sealed class WorldLightingFrame
    {
        internal long Sequence, Scene;
        internal bool Ready, Paused, Immediate;
        internal double Light;
        internal string Mode;
        internal double[] Parameters;
        internal static bool TryParse(JObject value, out WorldLightingFrame frame)
        {
            frame = null;
            if (value == null || value.Value<int?>("version") != 1 || value["sequence"]?.Type != JTokenType.Integer
                || value["scene"]?.Type != JTokenType.Integer || value["ready"]?.Type != JTokenType.Boolean
                || value["paused"]?.Type != JTokenType.Boolean || value["immediate"]?.Type != JTokenType.Boolean
                || value["sourceNeutral"]?.Type != JTokenType.Boolean || value.Value<bool>("sourceNeutral") != true
                || value["mode"]?.Type != JTokenType.String || !(value["parameters"] is JArray values) || values.Count != 8) return false;
            long sequence = value.Value<long>("sequence"), scene = value.Value<long>("scene");
            string mode = value.Value<string>("mode");
            if (sequence < 1 || scene < 1 || string.IsNullOrEmpty(mode) || mode.Length > 48 || !Number(value["light"], 100, out double light)) return false;
            var parameters = new double[8];
            for (int i = 0; i < 8; i++) if (!Number(values[i], i < 4 ? 8 : 360, out parameters[i])) return false;
            frame = new WorldLightingFrame { Sequence=sequence, Scene=scene, Ready=value.Value<bool>("ready"),
                Paused=value.Value<bool>("paused"), Immediate=value.Value<bool>("immediate"), Mode=mode, Light=light, Parameters=parameters };
            return true;
        }
        private static bool Number(JToken token, double limit, out double number)
        {
            number = 0;
            if (token == null || (token.Type != JTokenType.Integer && token.Type != JTokenType.Float)) return false;
            number = token.Value<double>();
            return double.IsFinite(number) && Math.Abs(number) <= limit;
        }
    }
}
