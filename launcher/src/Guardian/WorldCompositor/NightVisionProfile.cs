using System;
using System.Collections.Generic;
using System.Globalization;
using System.Xml.Linq;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Same XML node is consumed by Flash's unit tint and the native camera.
    // Mode activation remains exclusively owned by WeatherSystem/NightVisionManager.
    internal sealed class NightVisionProfile
    {
        internal static readonly NightVisionProfile None = new NightVisionProfile { Native = new float[16] };
        internal string Name, Title;
        internal float[] Native;
        internal float UnitStrength;
        internal float ShadowLift;
        internal bool Enabled => Native[0] == 1;

        // Shadow lift is baked into the LUT; optional scan strength occupies the
        // previously zero native slot 15. Old XML profiles still submit zero.
        internal static float ReadShadowLift(XElement effects)
            => ReadOptional(effects, "ShadowLift", 2);
        internal static float ReadScanStrength(XElement effects)
            => ReadOptional(effects, "ScanStrength", .08f);
        private static float ReadOptional(XElement effects, string key, float maximum)
        {
            var node = effects?.Element(key);
            if (node == null) return 0;
            if (!float.TryParse(node.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out float value)
                || !float.IsFinite(value) || value < 0 || value > maximum)
                throw new FormatException("Invalid night vision parameter: " + key);
            return value;
        }

        internal static Dictionary<string, NightVisionProfile> Load(string path)
        {
            var profiles = new Dictionary<string, NightVisionProfile>(StringComparer.Ordinal);
            var document = XDocument.Load(path);
            foreach (var set in document.Root.Elements("PresetSet"))
            {
                var node = set.Element("VisionEffects");
                if (node == null) continue;
                string name = (string)set.Element("name"), title = (string)node.Element("Title");
                if (string.IsNullOrWhiteSpace(name) || profiles.ContainsKey(name)
                    || (string)node.Element("Version") != "1" || string.IsNullOrWhiteSpace(title))
                    throw new FormatException("Invalid night vision profile identity");
                float Number(string key, float low, float high)
                {
                    if (!float.TryParse((string)node.Element(key), NumberStyles.Float, CultureInfo.InvariantCulture, out float value)
                        || !float.IsFinite(value) || value < low || value > high)
                        throw new FormatException("Invalid night vision parameter: " + name + "/" + key);
                    return value;
                }
                float unit = Number("UnitStrength", 0, 1);
                Number("UnitRed", 0, 1); Number("UnitGreen", 0, 1); Number("UnitBlue", 0, 1);
                profiles.Add(name, new NightVisionProfile { Name = name, Title = title, UnitStrength = unit, ShadowLift = ReadShadowLift(node), Native = new[] {
                    1f, Number("EdgeStrength",0,2), Number("EdgeWidth",.5f,3), Number("EdgeSuppression",0,1),
                    Number("EdgeHalo",0,1), Number("EdgeRadius",1,6), Number("Retention",.15f,1), Number("GlareStrength",0,2),
                    Number("EdgeRed",0,1), Number("EdgeGreen",0,1), Number("EdgeBlue",0,1), Number("GlareThreshold",.25f,8),
                    Number("GainFloor",.15f,1), Number("RecoverySeconds",.05f,2), Number("AttackSeconds",.01f,.5f), ReadScanStrength(node)
                }});
            }
            return profiles;
        }
    }
}
