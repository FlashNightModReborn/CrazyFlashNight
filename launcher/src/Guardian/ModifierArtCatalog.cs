using System;
using System.Drawing;
using System.IO;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    internal sealed class ModifierArtCatalog
    {
        private readonly string _root;
        private readonly JObject _layout;

        internal ModifierArtCatalog(string webRoot)
        {
            _root = Path.GetFullPath(Path.Combine(webRoot, "assets", "modifier", "native"));
            try
            {
                string path = Path.Combine(_root, "layout.json");
                if (File.Exists(path)) _layout = JObject.Parse(File.ReadAllText(path));
            }
            catch { _layout = null; }
        }

        internal string Background(string page)
        {
            return SafePath(Text((_layout?["pages"] as JObject)?[page]?["background"]));
        }

        internal string ButtonImage(string page, string action, bool hover, bool pressed)
        {
            JObject states = Button(page, action)?["states"] as JObject;
            if (states == null) return null;
            string state = action.StartsWith("tab:", StringComparison.Ordinal) ? "over"
                : pressed && states["down"] != null ? "down"
                : hover && states["over"] != null ? "over" : "up";
            return SafePath(Text(states[state]));
        }

        internal bool ButtonFlipX(string page, string action)
        {
            JToken value = Button(page, action)?["flipX"];
            return value != null && value.Type == JTokenType.Boolean && value.Value<bool>();
        }

        internal RectangleF AssetRect(string page, string action)
        {
            return Rect(Button(page, action)?["assetRect"]);
        }

        internal RectangleF HitRect(string page, string action)
        {
            return Rect(Button(page, action)?["hitRect"]);
        }

        internal RectangleF UnitFrameMask
        {
            get { return Rect(_layout?["unitFrameMask"]); }
        }

        internal RectangleF UnitRow(int index)
        {
            JArray rows = _layout?["unitRows"] as JArray;
            return rows != null && index >= 0 && index < rows.Count ? Rect(rows[index]) : RectangleF.Empty;
        }

        private JObject Button(string page, string action)
        {
            return ((_layout?["pages"] as JObject)?[page]?["buttons"] as JObject)?[action] as JObject;
        }

        private string SafePath(string relative)
        {
            if (string.IsNullOrEmpty(relative)) return null;
            string path = Path.GetFullPath(Path.Combine(_root, relative.Replace('/', Path.DirectorySeparatorChar)));
            return path.StartsWith(_root + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)
                && File.Exists(path) ? path : null;
        }

        private static string Text(JToken token)
        {
            return token != null && token.Type == JTokenType.String ? token.Value<string>() : null;
        }

        private static RectangleF Rect(JToken token)
        {
            JArray value = token as JArray;
            if (value == null || value.Count != 4) return RectangleF.Empty;
            try
            {
                float left = value[0].Value<float>();
                float top = value[1].Value<float>();
                float right = value[2].Value<float>();
                float bottom = value[3].Value<float>();
                return right > left && bottom > top
                    ? RectangleF.FromLTRB(left, top, right, bottom) : RectangleF.Empty;
            }
            catch { return RectangleF.Empty; }
        }
    }
}
