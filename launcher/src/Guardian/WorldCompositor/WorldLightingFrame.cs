using System;
using System.Linq;
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
        // Optional visual projection. Older paired AS2 sources keep their Flash particles.
        internal bool WeatherNative;
        internal int WeatherType, WeatherQuality;
        internal float WeatherIntensity;
        internal float WeatherGroundMin=360, WeatherGroundMax=520;
        internal AtmosphereFrame Atmosphere=AtmosphereFrame.None;
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
            JToken weatherNative = value["weatherNative"];
            if (weatherNative != null && weatherNative.Type != JTokenType.Boolean) return false;
            if (weatherNative?.Value<bool>() == true)
            {
                if (value["weatherType"]?.Type != JTokenType.String) return false;
                string type = value.Value<string>("weatherType");
                if (!Number(value["weatherQuality"],3,out double quality)
                    || quality < 0 || quality != Math.Floor(quality)
                    || !Number(value["weatherIntensity"], 1, out double intensity) || intensity < 0)
                    return false;
                frame.WeatherType = type switch {
                    "none" => 0, "rain" => 1, "snow" => 2,
                    "dust" => 3, "fog" => 4, "slash" => 5, _ => -1
                };
                if (frame.WeatherType < 0) return false;
                frame.WeatherNative = true;
                frame.WeatherIntensity = (float)intensity;
                frame.WeatherQuality = (int)quality;
                JToken groundMin=value["weatherGroundMin"], groundMax=value["weatherGroundMax"];
                if (groundMin!=null || groundMax!=null)
                {
                    if (!Number(groundMin,1000000,out double min)
                        || !Number(groundMax,1000000,out double max) || max<=min) return false;
                    frame.WeatherGroundMin=(float)min;
                    frame.WeatherGroundMax=(float)max;
                }
            }
            if (!AtmosphereFrame.TryParse(value["atmosphere"],out frame.Atmosphere)) return false;
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

    // The scene chooses the named look. Host owns every atmosphere pixel and
    // never asks Flash to draw a fallback overlay.
    internal sealed class AtmosphereFrame
    {
        internal static readonly AtmosphereFrame None=new AtmosphereFrame { Name="none",NativeParameters=new float[12] };
        internal string Name;
        internal float[] NativeParameters;

        internal static bool TryParse(JToken token,out AtmosphereFrame frame)
        {
            frame=None;
            if (token==null) return true; // older AS2 has no native atmosphere projection
            if (token is not JObject value || value["preset"]?.Type!=JTokenType.String
                || value["mode"]?.Type!=JTokenType.String || value["pulse"]?.Type!=JTokenType.Boolean)
                return false;
            string preset=value.Value<string>("preset");
            string mode=value.Value<string>("mode");
            if (string.IsNullOrWhiteSpace(preset) || preset.Length>48
                || preset.Any(char.IsControl) || preset is "雨" or "雪" or "沙尘"
                || (mode!="flat" && mode!="radial")
                || !Bounded(value["r"],255,out float r) || !Bounded(value["g"],255,out float g)
                || !Bounded(value["b"],255,out float b) || !Bounded(value["alpha"],100,out float alpha)
                || !Bounded(value["pulseSpeed"],1,out float speed)
                || !Bounded(value["pulseMin"],100,out float min)
                || !Bounded(value["pulseMax"],100,out float max) || max<min) return false;
            bool pulse=value.Value<bool>("pulse");
            if (preset=="none" && (alpha!=0 || pulse)) return false;
            frame=new AtmosphereFrame { Name=preset, NativeParameters=new float[] {
                r/255f,g/255f,b/255f,alpha/100f,mode=="radial" ? 1f : 0f,
                pulse ? 1f : 0f,speed*30f,min/100f,max/100f,0,0,0
            } };
            return true;
        }
        private static bool Bounded(JToken token,double limit,out float result)
        {
            result=0;
            if (token==null || (token.Type!=JTokenType.Integer && token.Type!=JTokenType.Float)) return false;
            double value=token.Value<double>();
            if (!double.IsFinite(value) || value<0 || value>limit) return false;
            result=(float)value;
            return true;
        }
    }
}
