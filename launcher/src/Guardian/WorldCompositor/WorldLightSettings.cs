using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text.Json;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // World, equipment and muzzle lighting share authored calibration, independently of sprite availability.
    internal sealed class WorldLightSettings
    {
        private readonly Dictionary<string, CombatFxLightProfile> _muzzles = new(StringComparer.Ordinal);
        internal float MaximumResponse { get; private set; } = .78f;
        internal string Sha256 { get; private set; } = "";
        internal float EquipmentPeak => _muzzles.TryGetValue("枪火", out var ordinary) ? ordinary.Energy : 1.5f;

        internal static WorldLightSettings Load(string projectRoot, Action<string> warn = null)
        {
            var settings = new WorldLightSettings();
            try
            {
                var bytes = File.ReadAllBytes(Path.Combine(projectRoot, CombatFxCatalog.LightsPath));
                if (bytes.Length > 32768) throw new InvalidDataException("Local lighting exceeds byte budget");
                using var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 8 });
                var root = document.RootElement;
                if (root.GetProperty("schema").GetString() != "cf7-combat-local-lights.v1")
                    throw new InvalidDataException("Unsupported local lighting schema");
                settings.MaximumResponse = Number(root, "maximumResponse", 0, .8f);
                var names = new HashSet<string>(StringComparer.Ordinal);
                foreach (var entry in root.GetProperty("muzzles").EnumerateObject())
                {
                    if (!names.Add(entry.Name))
                    {
                        settings._muzzles.Remove(entry.Name);
                        warn?.Invoke("duplicate muzzle light: " + entry.Name);
                        continue;
                    }
                    try { settings._muzzles.Add(entry.Name, ReadMuzzle(entry.Value)); }
                    catch (Exception error) when (InvalidValue(error))
                    { warn?.Invoke("invalid muzzle light " + entry.Name + ": " + error.Message); }
                }
                settings.Sha256 = Convert.ToHexString(SHA256.HashData(bytes));
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException || InvalidValue(error))
            { warn?.Invoke("local lighting configuration: " + error.Message); }
            return settings;
        }

        internal void Apply(CombatFxStyle[] styles, Action<string> warn)
        {
            var known = new HashSet<string>(StringComparer.Ordinal);
            foreach (var style in styles.Where(style => style.IsMuzzle))
            {
                known.Add(style.Linkage);
                if (_muzzles.TryGetValue(style.Linkage, out var light)) style.Light = light;
                else warn?.Invoke("missing muzzle light: " + style.Linkage);
            }
            foreach (string name in _muzzles.Keys)
                if (!known.Contains(name)) warn?.Invoke("unmapped muzzle light: " + name);
        }

        private static bool InvalidValue(Exception error) =>
            error is InvalidDataException or JsonException or KeyNotFoundException or InvalidOperationException or FormatException or OverflowException;

        private static CombatFxLightProfile ReadMuzzle(JsonElement value)
        {
            string color = value.GetProperty("color").GetString();
            if (color == null || color.Length != 7 || color[0] != '#' || !uint.TryParse(color.AsSpan(1),
                NumberStyles.HexNumber, CultureInfo.InvariantCulture, out uint rgb)) throw new InvalidDataException("invalid color");
            int ticks = value.GetProperty("ticks").GetInt32();
            if (ticks < 1 || ticks > 6) throw new InvalidDataException("invalid duration");
            return new CombatFxLightProfile(Number(value,"radius",16,256), Number(value,"energy",0,2), ticks,
                ((rgb >> 16) & 255) / 255f, ((rgb >> 8) & 255) / 255f, (rgb & 255) / 255f);
        }
        private static float Number(JsonElement owner, string field, float minimum, float maximum)
        {
            float value = owner.GetProperty(field).GetSingle();
            if (!float.IsFinite(value) || value < minimum || value > maximum) throw new InvalidDataException("invalid " + field);
            return value;
        }
    }
}
