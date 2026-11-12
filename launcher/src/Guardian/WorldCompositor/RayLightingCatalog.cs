using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // Small authored lighting table, independent from beam art and the global
    // compositor response ceiling. Unknown fields and duplicate keys fail closed.
    internal sealed class RayLightingCatalog
    {
        internal const string RelativePath = "data/combat_visuals/ray_lights.v1.json";
        private readonly Dictionary<string, RayLightingProfile> _profiles;
        private readonly RayLightingProfile[] _styles;
        internal string Sha256 { get; }

        private RayLightingCatalog(string sha, Dictionary<string, RayLightingProfile> profiles,
            RayLightingProfile[] styles)
        { Sha256 = sha; _profiles = profiles; _styles = styles; }

        internal static RayLightingCatalog Disabled() => new("", new(StringComparer.Ordinal),
            new RayLightingProfile[RayVisualCatalog.Styles.Length]);

        internal static RayLightingCatalog Load(string projectRoot, Action<string> warn = null) =>
            Parse(File.ReadAllBytes(Path.Combine(projectRoot, RelativePath)), warn);

        internal static RayLightingCatalog Parse(byte[] utf8, Action<string> warn = null)
        {
            if (utf8 == null || utf8.Length == 0 || utf8.Length > 32768)
                throw new InvalidDataException("Ray lighting catalog exceeds its byte budget");
            try
            {
                using var doc = JsonDocument.Parse(utf8, new JsonDocumentOptions { MaxDepth = 8 });
                JsonElement root = doc.RootElement;
                Fields(root, "schema", "ticksPerSecond", "profiles", "styles");
                if (Text(root, "schema") != "cf7-ray-lights.v1" || Integer(root, "ticksPerSecond", 30, 30) != 30)
                    throw new InvalidDataException("Unsupported ray lighting catalog");
                JsonElement profileTable = Required(root, "profiles");
                if (profileTable.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Expected ray lighting profiles");
                var profiles = new Dictionary<string, RayLightingProfile>(StringComparer.Ordinal);
                var seen = new HashSet<string>(StringComparer.Ordinal);
                foreach (JsonProperty property in profileTable.EnumerateObject())
                {
                    string name = property.Name;
                    try {
                        if (!seen.Add(name) || !RayLightOverrides.IsProfileName(name) || name is "auto" or "none")
                            throw new InvalidDataException("Invalid or duplicate ray lighting profile: " + name);
                        profiles.Add(name, ParseProfile(name, property.Value));
                    }
                    catch (InvalidDataException error) when (warn != null) {
                        profiles.Remove(name);
                        warn("event=ray_light_profile_ignored name="+name+" reason="+error.Message);
                    }
                }
                JsonElement styleTable = Required(root, "styles");
                if (styleTable.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Expected ray style mapping");
                var styles = new RayLightingProfile[RayVisualCatalog.Styles.Length];
                seen.Clear();
                foreach (var pair in styleTable.EnumerateObject()) {
                    int index = Array.IndexOf(RayVisualCatalog.Styles, pair.Name);
                    try {
                        if (index < 0 || !seen.Add(pair.Name) || pair.Value.ValueKind != JsonValueKind.String
                            || !profiles.TryGetValue(pair.Value.GetString(), out styles[index]))
                            throw new InvalidDataException("Unknown, duplicate or missing profile for ray style: " + pair.Name);
                    }
                    catch (InvalidDataException error) when (warn != null) {
                        if (index >= 0) styles[index]=null;
                        warn("event=ray_light_style_ignored style="+pair.Name+" reason="+error.Message);
                    }
                }
                for (int i=0; i<styles.Length; i++) {
                    if (seen.Contains(RayVisualCatalog.Styles[i])) continue;
                    if (warn == null) throw new InvalidDataException("Missing ray style: "+RayVisualCatalog.Styles[i]);
                    warn("event=ray_light_style_ignored style="+RayVisualCatalog.Styles[i]+" reason=missing");
                }
                return new RayLightingCatalog(Convert.ToHexString(SHA256.HashData(utf8)), profiles, styles);
            }
            catch (JsonException error)
            { throw new InvalidDataException("Malformed ray lighting catalog", error); }
        }

        private static RayLightingProfile ParseProfile(string name, JsonElement p)
        {
            Fields(p, "shape", "priority", "energy", "widthScale", "minWidth", "maxWidth", "maxLength",
                "colorSource", "color", "whiten", "holdTicks", "fadeTicks", "flicker",
                "nearWidthRatio", "maxNearRadius", "nearEnergyRatio");
            string shape = Text(p, "shape"), colorSource = Text(p, "colorSource");
            if ((shape != "cone" && shape != "beam") || (colorSource != "primary" && colorSource != "fixed"))
                throw new InvalidDataException("Unknown ray light shape or color source");
            int color = -1;
            if (colorSource == "fixed")
            {
                string hex = Text(p, "color");
                if (hex.Length != 7 || hex[0] != '#' || !int.TryParse(hex.AsSpan(1),
                    NumberStyles.HexNumber, CultureInfo.InvariantCulture, out color))
                    throw new InvalidDataException("Ray light fixed color must be #RRGGBB");
            }
            else if (p.TryGetProperty("color", out _))
                throw new InvalidDataException("A primary-color ray light cannot have an unused fixed color");
            float nearWidthRatio = 0, maxNearRadius = 0, nearEnergyRatio = 0;
            bool hasNear = p.TryGetProperty("nearWidthRatio", out _)
                || p.TryGetProperty("maxNearRadius", out _) || p.TryGetProperty("nearEnergyRatio", out _);
            if (hasNear)
            {
                if (shape != "cone") throw new InvalidDataException("Only cone profiles may have near fill");
                nearWidthRatio = Number(p, "nearWidthRatio", 0, 1);
                maxNearRadius = Number(p, "maxNearRadius", 0, 320);
                nearEnergyRatio = Number(p, "nearEnergyRatio", 0, 1);
            }
            float minWidth = Number(p, "minWidth", .5f, 512);
            float maxWidth = Number(p, "maxWidth", minWidth, 512);
            return new RayLightingProfile(name, shape == "cone" ? 1 : 2,
                Integer(p, "priority", 0, 100), Number(p, "energy", 0, 2),
                Number(p, "widthScale", .05f, 16), minWidth, maxWidth,
                Number(p, "maxLength", 1, 1024), color, Number(p, "whiten", 0, 1),
                Integer(p, "holdTicks", -1, 600), Integer(p, "fadeTicks", 0, 30),
                Number(p, "flicker", 0, .25f), nearWidthRatio, maxNearRadius, nearEnergyRatio);
        }

        internal RayLightingProfile Resolve(int style, RayLightOverrides light)
        {
            if (!light.IsValid || style < 0 || style >= _styles.Length)
                throw new ArgumentOutOfRangeException(nameof(light));
            if (light.Profile == "none") return null;
            return light.Profile == "auto" ? _styles[style] : _profiles.GetValueOrDefault(light.Profile);
        }
        internal RayLightingProfile ForStyle(int style) => _styles[style];

        private static JsonElement Required(JsonElement owner, string name)
        {
            if (!owner.TryGetProperty(name, out var value))
                throw new InvalidDataException("Missing ray lighting field: " + name);
            return value;
        }
        private static void Fields(JsonElement owner, params string[] allowed)
        {
            if (owner.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Expected a ray lighting object");
            var found = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in owner.EnumerateObject())
                if (Array.IndexOf(allowed, property.Name) < 0 || !found.Add(property.Name))
                    throw new InvalidDataException("Unknown or duplicate ray lighting field: " + property.Name);
        }
        private static string Text(JsonElement owner, string name)
        {
            var value = Required(owner, name);
            if (value.ValueKind != JsonValueKind.String) throw new InvalidDataException("Expected a ray lighting string: " + name);
            return value.GetString();
        }
        private static float Number(JsonElement owner, string name, float minimum, float maximum)
        {
            var value = Required(owner, name);
            if (value.ValueKind != JsonValueKind.Number || !value.TryGetSingle(out float number)
                || !float.IsFinite(number) || number < minimum || number > maximum)
                throw new InvalidDataException("Invalid ray lighting number: " + name);
            return number;
        }
        private static int Integer(JsonElement owner, string name, int minimum, int maximum)
        {
            var value = Required(owner, name);
            if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out int number) || number < minimum || number > maximum)
                throw new InvalidDataException("Invalid ray lighting integer: " + name);
            return number;
        }
    }

    internal sealed class RayLightingProfile
    {
        internal readonly string Name;
        internal readonly int Kind, Priority, FixedColor, HoldTicks, FadeTicks;
        // Widths describe the environment-light half width, independently of
        // the thin authored beam body or the AS2 collision width.
        internal readonly float Energy, WidthScale, MinWidth, MaxWidth, MaxLength, Whiten, Flicker;
        internal readonly float NearWidthRatio, MaxNearRadius, NearEnergyRatio;
        internal RayLightingProfile(string name, int kind, int priority, float energy, float widthScale,
            float minWidth, float maxWidth, float maxLength, int fixedColor, float whiten,
            int holdTicks, int fadeTicks, float flicker, float nearWidthRatio, float maxNearRadius, float nearEnergyRatio)
        {
            Name = name; Kind = kind; Priority = priority; Energy = energy; WidthScale = widthScale;
            MinWidth = minWidth; MaxWidth = maxWidth; MaxLength = maxLength; FixedColor = fixedColor;
            Whiten = whiten; HoldTicks = holdTicks; FadeTicks = fadeTicks; Flicker = flicker;
            NearWidthRatio = nearWidthRatio; MaxNearRadius = maxNearRadius; NearEnergyRatio = nearEnergyRatio;
        }
    }
}
