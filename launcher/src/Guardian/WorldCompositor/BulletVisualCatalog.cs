using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;
using SkiaSharp;

namespace CF7Launcher.Guardian.WorldCompositor
{
    // The XFL-derived catalog is the single visual whitelist for the first
    // ordinary / gun-chain bullet batch. Loading it does not transfer display
    // ownership; a later paired native capability must explicitly do so.
    internal sealed class BulletVisualCatalog
    {
        internal const string RelativePath = "data/combat_visuals/bullet_styles.v1.json";
        internal const string SourceSwf = "flashswf/arts/原版素材库-子弹.swf";
        internal const string AtlasPath = "data/combat_visuals/bullets-atlas.png";
        private readonly Dictionary<string, BulletVisualStyle> _ordinary;
        private readonly Dictionary<string, BulletVisualStyle> _chainUnits;
        private readonly HashSet<string> _gunPrefixes;

        internal string Sha256 { get; }
        internal IReadOnlyList<BulletVisualStyle> Styles { get; }
        internal IReadOnlyList<string> GunChainPrefixes { get; }
        internal int AtlasWidth { get; }
        internal int AtlasHeight { get; }
        internal byte[] AtlasBgraPremultiplied { get; }

        private BulletVisualCatalog(string sha, List<BulletVisualStyle> styles, List<string> prefixes,
            int atlasWidth, int atlasHeight, byte[] atlasPixels)
        {
            Sha256 = sha;
            Styles = styles;
            GunChainPrefixes = prefixes;
            _ordinary = styles.Where(s => s.OrdinaryLinkage != null).ToDictionary(s => s.OrdinaryLinkage, StringComparer.Ordinal);
            _chainUnits = styles.Where(s => s.GunChainUnitLinkage != null).ToDictionary(s => s.GunChainUnitLinkage, StringComparer.Ordinal);
            _gunPrefixes = new HashSet<string>(prefixes, StringComparer.Ordinal);
            AtlasWidth = atlasWidth; AtlasHeight = atlasHeight; AtlasBgraPremultiplied = atlasPixels;
        }

        internal bool TryOrdinary(string linkage, out BulletVisualStyle style) =>
            _ordinary.TryGetValue(linkage, out style);

        internal bool TryGunChain(string bulletType, out BulletVisualStyle style)
        {
            style = null;
            if (bulletType == null) return false;
            int dash = bulletType.IndexOf('-');
            if (dash <= 0 || dash == bulletType.Length - 1
                || !_gunPrefixes.Contains(bulletType.Substring(0, dash))) return false;
            return _chainUnits.TryGetValue("单元体-" + bulletType.Substring(dash + 1), out style);
        }

        internal static BulletVisualCatalog Load(string projectRoot)
        {
            string path = Path.Combine(projectRoot, RelativePath.Replace('/', Path.DirectorySeparatorChar));
            byte[] bytes = File.ReadAllBytes(path);
            if (bytes.Length > 256 * 1024) throw new InvalidDataException("Bullet catalog exceeds budget");
            using JsonDocument document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 12 });
            JsonElement root = document.RootElement;
            Fields(root, "schema", "generator", "generatorSha256", "sourceSwf",
                "sourceSwfSha256", "sources", "gunChainPrefixes", "styles", "tools", "atlas");
            if (String(root.GetProperty("schema")) != "cf7-combat-bullet-styles.v1"
                || String(root.GetProperty("generator")) != "tools/combat-bullet-visuals/build.py"
                || String(root.GetProperty("sourceSwf")) != SourceSwf)
                throw new InvalidDataException("Unsupported bullet visual catalog identity");
            Hex(root.GetProperty("generatorSha256"));
            string expectedSwfHash = Hex(root.GetProperty("sourceSwfSha256"));
            string swfPath = Path.Combine(projectRoot, SourceSwf.Replace('/', Path.DirectorySeparatorChar));
            string actualSwfHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(swfPath)));
            if (!string.Equals(expectedSwfHash, actualSwfHash, StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Bullet source SWF differs from the XFL-derived catalog");

            JsonElement sources = root.GetProperty("sources");
            if (sources.ValueKind != JsonValueKind.Array || sources.GetArrayLength() < 4
                || sources.GetArrayLength() > 64)
                throw new InvalidDataException("Invalid bullet visual source list");
            var sourceNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonElement source in sources.EnumerateArray())
            {
                Fields(source, "path", "sha256");
                string name = String(source.GetProperty("path"));
                if (!name.StartsWith("flashswf/arts/原版素材库-子弹/LIBRARY/", StringComparison.Ordinal)
                    || name.Contains("..", StringComparison.Ordinal) || !sourceNames.Add(name))
                    throw new InvalidDataException("Invalid bullet visual source identity");
                Hex(source.GetProperty("sha256"));
            }

            JsonElement rawTools = root.GetProperty("tools");
            if (rawTools.ValueKind != JsonValueKind.Array || rawTools.GetArrayLength() < 5
                || rawTools.GetArrayLength() > 128)
                throw new InvalidDataException("Invalid bullet visual tool closure");
            var toolNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonElement tool in rawTools.EnumerateArray())
            {
                Fields(tool, "path", "sha256");
                string name = String(tool.GetProperty("path"));
                if (!name.StartsWith("tools/", StringComparison.Ordinal)
                    || name.Contains("..", StringComparison.Ordinal) || !toolNames.Add(name))
                    throw new InvalidDataException("Invalid bullet tool identity");
                Hex(tool.GetProperty("sha256"));
            }

            JsonElement atlas = root.GetProperty("atlas");
            Fields(atlas, "path", "sha256", "width", "height", "scale", "pillowVersion");
            if (String(atlas.GetProperty("path")) != AtlasPath)
                throw new InvalidDataException("Invalid bullet atlas path");
            int atlasWidth = atlas.GetProperty("width").GetInt32();
            int atlasHeight = atlas.GetProperty("height").GetInt32();
            float scale = Number(atlas.GetProperty("scale"), 1, 8);
            String(atlas.GetProperty("pillowVersion"));
            if (atlasWidth < 1 || atlasHeight < 1 || atlasWidth > 1024 || atlasHeight > 1024)
                throw new InvalidDataException("Bullet atlas dimensions outside budget");
            byte[] png = File.ReadAllBytes(Path.Combine(projectRoot, AtlasPath));
            if (png.Length > 1024 * 1024 || !string.Equals(Hex(atlas.GetProperty("sha256")),
                Convert.ToHexString(SHA256.HashData(png)), StringComparison.OrdinalIgnoreCase))
                throw new InvalidDataException("Bullet atlas integrity mismatch");

            JsonElement prefixItems = root.GetProperty("gunChainPrefixes");
            if (prefixItems.ValueKind != JsonValueKind.Array || prefixItems.GetArrayLength() < 1
                || prefixItems.GetArrayLength() > 16)
                throw new InvalidDataException("Invalid gun-chain prefix list");
            var prefixes = new List<string>();
            var uniquePrefixes = new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonElement item in prefixItems.EnumerateArray())
            {
                string prefix = String(item);
                if (prefix.Contains('-') || !uniquePrefixes.Add(prefix))
                    throw new InvalidDataException("Duplicate or invalid gun-chain prefix");
                prefixes.Add(prefix);
            }

            JsonElement styleItems = root.GetProperty("styles");
            if (styleItems.ValueKind != JsonValueKind.Array || styleItems.GetArrayLength() < 1
                || styleItems.GetArrayLength() > 16)
                throw new InvalidDataException("Invalid bullet visual style list");
            var styles = new List<BulletVisualStyle>();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            var ordinaryNames = new HashSet<string>(StringComparer.Ordinal);
            var unitNames = new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonElement item in styleItems.EnumerateArray())
            {
                Fields(item, "id", "ordinaryLinkage", "gunChainUnitLinkage", "visual");
                string id = String(item.GetProperty("id"));
                string ordinary = OptionalString(item.GetProperty("ordinaryLinkage"));
                string unit = OptionalString(item.GetProperty("gunChainUnitLinkage"));
                if (!ids.Add(id) || (ordinary == null && unit == null)
                    || (ordinary != null && !ordinaryNames.Add(ordinary))
                    || (unit != null && (!unitNames.Add(unit) || !unit.StartsWith("单元体-", StringComparison.Ordinal))))
                    throw new InvalidDataException("Duplicate or invalid bullet visual style");
                JsonElement visual = item.GetProperty("visual");
                string kind = String(visual.GetProperty("kind"));
                if (kind == "triangle")
                    Fields(visual, "kind", "verticesPx", "fill", "glow", "registrationPx", "frameIndex");
                else if (kind == "sprite")
                    Fields(visual, "kind", "atlasRectPx", "offsetPx", "sizePx", "registrationPx", "frameIndex");
                else throw new InvalidDataException("Unknown bullet visual kind");
                if (visual.GetProperty("frameIndex").GetInt32() != 0)
                    throw new InvalidDataException("Animated bullet visual is not in the first batch");
                float[] registration = Vector(visual.GetProperty("registrationPx"), 2, -256, 256);
                if (registration[0] != 0 || registration[1] != 0)
                    throw new InvalidDataException("Bullet visual registration must be the shared origin");
                if (kind == "sprite")
                {
                    JsonElement rect = visual.GetProperty("atlasRectPx");
                    if (rect.ValueKind != JsonValueKind.Array || rect.GetArrayLength() != 4)
                        throw new InvalidDataException("Invalid bullet atlas rectangle");
                    int x = rect[0].GetInt32(), y = rect[1].GetInt32(), w = rect[2].GetInt32(), h = rect[3].GetInt32();
                    if (x < 2 || y < 2 || w < 1 || h < 1 || w > atlasWidth - 4 || h > atlasHeight - 4
                        || x > atlasWidth - w - 2 || y > atlasHeight - h - 2)
                        throw new InvalidDataException("Bullet sprite leaves atlas padding");
                    float[] offset = Vector(visual.GetProperty("offsetPx"), 2, -256, 256);
                    float[] size = Vector(visual.GetProperty("sizePx"), 2, 0.125, 1024);
                    if (size[0] != w / scale || size[1] != h / scale)
                        throw new InvalidDataException("Bullet sprite scale mismatch");
                    styles.Add(new BulletVisualStyle(id, ordinary, unit, new CombatFxImage(
                        x / (float)atlasWidth, y / (float)atlasHeight, (x + w) / (float)atlasWidth,
                        (y + h) / (float)atlasHeight, offset[0], offset[1], size[0], size[1])));
                    continue;
                }
                JsonElement vertices = visual.GetProperty("verticesPx");
                if (vertices.ValueKind != JsonValueKind.Array || vertices.GetArrayLength() != 3)
                    throw new InvalidDataException("Bullet style must be a triangle");
                var points = new float[6];
                int index = 0;
                foreach (JsonElement point in vertices.EnumerateArray())
                {
                    float[] pair = Vector(point, 2, -256, 256);
                    points[index++] = pair[0]; points[index++] = pair[1];
                }
                if (Math.Abs((points[2] - points[0]) * (points[5] - points[1])
                    - (points[3] - points[1]) * (points[4] - points[0])) < 0.001f)
                    throw new InvalidDataException("Degenerate bullet visual triangle");
                int fill = Color(visual.GetProperty("fill"));
                JsonElement glow = visual.GetProperty("glow");
                int glowColor = 0;
                float glowX = 0, glowY = 0;
                if (glow.ValueKind != JsonValueKind.Null)
                {
                    Fields(glow, "color", "blurX", "blurY");
                    glowColor = Color(glow.GetProperty("color"));
                    glowX = Number(glow.GetProperty("blurX"), 0, 64);
                    glowY = Number(glow.GetProperty("blurY"), 0, 64);
                }
                styles.Add(new BulletVisualStyle(id, ordinary, unit, points, fill,
                    glowColor, glowX, glowY));
            }
            using var decoded = SKBitmap.Decode(png) ?? throw new InvalidDataException("Invalid bullet atlas PNG");
            if (decoded.Width != atlasWidth || decoded.Height != atlasHeight)
                throw new InvalidDataException("Bullet atlas metadata size mismatch");
            using var bitmap = new SKBitmap(new SKImageInfo(atlasWidth, atlasHeight, SKColorType.Bgra8888, SKAlphaType.Premul));
            using (var canvas = new SKCanvas(bitmap))
            {
                canvas.Clear(SKColors.Transparent); canvas.DrawBitmap(decoded, 0, 0); canvas.Flush();
            }
            var pixels = new byte[checked(atlasWidth * atlasHeight * 4)];
            Marshal.Copy(bitmap.GetPixels(), pixels, 0, pixels.Length);
            return new BulletVisualCatalog(Convert.ToHexString(SHA256.HashData(bytes)), styles, prefixes,
                atlasWidth, atlasHeight, pixels);
        }

        private static void Fields(JsonElement value, params string[] names)
        {
            if (value.ValueKind != JsonValueKind.Object)
                throw new InvalidDataException("Expected bullet visual object");
            var expected = new HashSet<string>(names, StringComparer.Ordinal);
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (JsonProperty property in value.EnumerateObject())
                if (!expected.Contains(property.Name) || !seen.Add(property.Name))
                    throw new InvalidDataException("Unknown or duplicate bullet visual field: " + property.Name);
            if (seen.Count != expected.Count)
                throw new InvalidDataException("Missing bullet visual field");
        }
        private static string String(JsonElement value)
        {
            if (value.ValueKind != JsonValueKind.String)
                throw new InvalidDataException("Bullet visual value must be a string");
            string result = value.GetString();
            if (string.IsNullOrWhiteSpace(result) || result.Length > 256 || result.Any(char.IsControl))
                throw new InvalidDataException("Invalid bullet visual string");
            return result;
        }
        private static string OptionalString(JsonElement value) =>
            value.ValueKind == JsonValueKind.Null ? null : String(value);
        private static string Hex(JsonElement value)
        {
            string result = String(value);
            if (result.Length != 64 || !result.All(Uri.IsHexDigit))
                throw new InvalidDataException("Invalid bullet visual hash");
            return result;
        }
        private static int Color(JsonElement value)
        {
            string result = String(value);
            if (result.Length != 7 || result[0] != '#' || !result.Skip(1).All(Uri.IsHexDigit))
                throw new InvalidDataException("Invalid bullet visual color");
            return int.Parse(result.Substring(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }
        private static float[] Vector(JsonElement value, int length, double minimum, double maximum)
        {
            if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() != length)
                throw new InvalidDataException("Invalid bullet visual vector");
            var result = new float[length];
            int index = 0;
            foreach (JsonElement item in value.EnumerateArray())
                result[index++] = Number(item, minimum, maximum);
            return result;
        }
        private static float Number(JsonElement value, double minimum, double maximum)
        {
            if (value.ValueKind != JsonValueKind.Number || !value.TryGetDouble(out double number)
                || !double.IsFinite(number) || number < minimum || number > maximum)
                throw new InvalidDataException("Bullet visual number outside bounds");
            return (float)number;
        }
    }

    internal sealed class BulletVisualStyle
    {
        internal string Id { get; }
        internal string OrdinaryLinkage { get; }
        internal string GunChainUnitLinkage { get; }
        internal float[] VerticesPx { get; }
        internal int FillRgb { get; }
        internal int GlowRgb { get; }
        internal float GlowX { get; }
        internal float GlowY { get; }
        internal bool IsSprite { get; }
        internal CombatFxImage Sprite { get; }
        internal BulletVisualStyle(string id, string ordinary, string unit, float[] vertices,
            int fill, int glow, float glowX, float glowY)
        {
            Id = id; OrdinaryLinkage = ordinary; GunChainUnitLinkage = unit;
            VerticesPx = vertices; FillRgb = fill; GlowRgb = glow;
            GlowX = glowX; GlowY = glowY;
        }
        internal BulletVisualStyle(string id, string ordinary, string unit, CombatFxImage sprite)
        {
            Id = id; OrdinaryLinkage = ordinary; GunChainUnitLinkage = unit;
            IsSprite = true; Sprite = sprite; VerticesPx = Array.Empty<float>(); FillRgb = 0xFFFFFF;
        }
    }
}
