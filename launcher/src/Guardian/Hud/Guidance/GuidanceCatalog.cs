using System;
using System.Collections.Generic;
using System.Drawing;
using System.Globalization;
using System.Linq;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian.Hud.Guidance
{
    /// <summary>Authored content shared by native scene hints and Web help. No business state.</summary>
    public sealed class GuidanceCatalog
    {
        public sealed class VisualElement
        {
            public string Type { get; internal set; }
            public RectangleF Bounds { get; internal set; }
            public string Text { get; internal set; }
            public float FontSize { get; internal set; }
        }
        public sealed class Page
        {
            public string Title { get; internal set; }
            public string Text { get; internal set; }
            public string Image { get; internal set; }
            public IReadOnlyList<VisualElement> Visual { get; internal set; }
        }
        public sealed class Guide
        {
            public string Id { get; internal set; }
            public string Title { get; internal set; }
            public bool Tutorial { get; internal set; }
            public bool WebHelp { get; internal set; }
            public IReadOnlyList<Page> Pages { get; internal set; }
        }
        private readonly Dictionary<string, Guide> _guides = new(StringComparer.Ordinal);
        public IReadOnlyDictionary<string,string> KeyLabels { get; private set; } = new Dictionary<string,string>();
        internal static readonly string[] KeyNames = { "left", "right", "up", "down", "attack", "jump", "interact" };
        public bool TryGet(string id, out Guide guide) => _guides.TryGetValue(id ?? "", out guide);
        public static GuidanceCatalog FromJson(string json)
        {
            var root = JObject.Parse(json);
            if (root["version"]?.Type != JTokenType.Integer || root.Value<int>("version") != 1 || root["guides"] is not JArray guides || guides.Count is < 1 or > 64) throw new FormatException("Invalid guidance catalog");
            var result = new GuidanceCatalog();
            if (root["keyLabels"] != null)
            {
                if (root["keyLabels"] is not JObject labels || labels.Count > 64) throw new FormatException("Invalid key labels");
                var names = new Dictionary<string,string>(StringComparer.Ordinal);
                foreach (var label in labels.Properties())
                {
                    if (string.IsNullOrWhiteSpace(label.Name) || label.Name.Length > 24 || label.Name.Any(char.IsControl)) throw new FormatException("Invalid key name");
                    string value = Text(labels,label.Name,8);
                    if (value.Any(char.IsControl)) throw new FormatException("Invalid key label");
                    names.Add(label.Name,value);
                }
                result.KeyLabels = new System.Collections.ObjectModel.ReadOnlyDictionary<string,string>(names);
            }
            foreach (var token in guides)
            {
                if (token is not JObject obj) throw new FormatException("Invalid guide");
                string id = Text(obj, "id", 32), kind = Text(obj, "kind", 16);
                if ((kind != "scene" && kind != "tutorial") || result._guides.ContainsKey(id) || obj["pages"] is not JArray pages || pages.Count is < 1 or > 16) throw new FormatException("Invalid guide " + id);
                if (obj["surface"] != null && obj["surface"].Type != JTokenType.String) throw new FormatException("Invalid guide surface");
                string surface = obj.Value<string>("surface");
                if (surface != null && (surface != "help" || kind != "tutorial")) throw new FormatException("Invalid guide surface");
                var content = new List<Page>();
                foreach (var item in pages)
                {
                    if (item is not JObject page) throw new FormatException("Invalid page");
                    string image = page.Value<string>("image");
                    if (image != null && (!image.StartsWith("flashswf/images/", StringComparison.Ordinal) || image.Contains("..") || image.Contains('\\') || image.Contains(':'))) throw new FormatException("Invalid image reference");
                    content.Add(new Page { Title = Text(page, "title", 80), Text = Text(page, "text", 3000), Image = image, Visual = ReadVisual(page["visual"]) });
                }
                result._guides.Add(id, new Guide { Id = id, Title = Text(obj, "title", 80), Tutorial = kind == "tutorial", WebHelp = surface == "help", Pages = content.AsReadOnly() });
            }
            return result;
        }
        private static IReadOnlyList<VisualElement> ReadVisual(JToken token)
        {
            if (token == null) return Array.Empty<VisualElement>();
            if (token is not JArray elements || elements.Count is < 1 or > 48) throw new FormatException("Invalid guide visual");
            var result = new List<VisualElement>();
            foreach (JToken item in elements)
            {
                if (item is not JObject element) throw new FormatException("Invalid visual element");
                string type = Text(element, "type", 8);
                if (type is not ("key" or "text" or "mouse")) throw new FormatException("Invalid visual type");
                string[] fields = type == "mouse" ? new[] { "type", "x", "y", "width", "height" }
                    : new[] { "type", "x", "y", "width", "height", "text", "fontSize" };
                if (element.Count != fields.Length || fields.Any(f => !element.ContainsKey(f))) throw new FormatException("Invalid visual fields");
                float x = Number(element, "x", 0, 1024), y = Number(element, "y", 0, 576);
                float w = Number(element, "width", 1, 1024), h = Number(element, "height", 1, 576);
                if (x + w > 1024 || y + h > 576) throw new FormatException("Visual outside logical canvas");
                result.Add(new VisualElement { Type = type, Bounds = new RectangleF(x, y, w, h),
                    Text = type == "mouse" ? null : Text(element, "text", 80),
                    FontSize = type == "mouse" ? 0 : Number(element, "fontSize", 10, 32) });
            }
            return result.AsReadOnly();
        }
        private static float Number(JObject obj, string key, float min, float max)
        {
            if (obj[key]?.Type is not (JTokenType.Integer or JTokenType.Float)) throw new FormatException("Invalid " + key);
            if (!double.TryParse(obj[key].ToString(Newtonsoft.Json.Formatting.None), NumberStyles.Float, CultureInfo.InvariantCulture, out double value)
                || !double.IsFinite(value) || value < min || value > max) throw new FormatException("Invalid " + key);
            return (float)value;
        }
        private static string Text(JObject obj, string key, int limit)
        {
            if (obj[key]?.Type != JTokenType.String) throw new FormatException("Invalid " + key);
            string text = obj.Value<string>(key);
            if (string.IsNullOrWhiteSpace(text) || text.Length > limit) throw new FormatException("Invalid " + key);
            return text;
        }
        public static string Bind(string text, IReadOnlyDictionary<string,string> keys)
        {
            foreach (string key in KeyNames) if (keys != null && keys.TryGetValue(key, out string value)) text = text.Replace("{" + key + "}", value);
            return text;
        }
    }
}
