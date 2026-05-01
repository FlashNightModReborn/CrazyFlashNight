using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Xml;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Web 情报详情面板的数据源。只读取固定情报字典和 data/intelligence 文本目录。
    /// </summary>
    public sealed class IntelligenceTask
    {
        private sealed class IntelligencePage
        {
            public int Value;
            public string PageKey;
            public int EncryptLevel;
        }

        private sealed class IntelligenceItem
        {
            public string Name;
            public string IconName;
            public int Index;
            public int MaxValue;
            public readonly List<IntelligencePage> Pages = new List<IntelligencePage>();
            public readonly Dictionary<string, string> EncryptReplace = new Dictionary<string, string>();
            public readonly Dictionary<string, string> EncryptCut = new Dictionary<string, string>();
        }

        private readonly string _dictionaryPath;
        private readonly string _itemDictionaryPath;
        private readonly string _textDir;
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private Dictionary<string, IntelligenceItem> _items;
        private List<IntelligenceItem> _catalog;
        private readonly Dictionary<string, Dictionary<string, string>> _textCache =
            new Dictionary<string, Dictionary<string, string>>();

        public IntelligenceTask(string projectRoot)
        {
            string root = string.IsNullOrEmpty(projectRoot)
                ? AppDomain.CurrentDomain.BaseDirectory
                : projectRoot;
            _dictionaryPath = Path.Combine(root, "data", "dictionaries", "information_dictionary.xml");
            _itemDictionaryPath = Path.Combine(root, "data", "items", "收集品_情报.xml");
            _textDir = Path.Combine(root, "data", "intelligence");
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[IntelligenceTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[IntelligenceTask] webCallId is empty");
                return;
            }

            try
            {
                switch (cmd)
                {
                    case "bundle":
                        RespondBundle(webCallId, parsed);
                        break;
                    case "catalog":
                        RespondCatalog(webCallId);
                        break;
                    case "snapshot":
                        RespondSnapshot(webCallId, parsed);
                        break;
                    default:
                        RespondError(webCallId, cmd, "unsupported_cmd");
                        break;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[IntelligenceTask] failed: " + ex.Message);
                RespondError(webCallId, cmd, "internal_error");
            }
        }

        private void RespondCatalog(string webCallId)
        {
            EnsureCatalogLoaded();
            var items = new JArray();
            foreach (IntelligenceItem item in _catalog)
                items.Add(BuildCatalogEntry(item));

            var resp = BaseResponse("catalog", webCallId, true);
            resp["items"] = items;
            PostToWeb(resp.ToString(Newtonsoft.Json.Formatting.None));
        }

        private void RespondBundle(string webCallId, JObject parsed)
        {
            EnsureCatalogLoaded();

            int value = ParseInt(parsed["value"], 0);
            int decryptLevel = ParseInt(parsed["decryptLevel"], 0);
            string pcName = parsed.Value<string>("pcName") ?? "";
            JObject valuesByName = parsed["values"] as JObject;

            var items = new JArray();
            foreach (IntelligenceItem item in _catalog)
            {
                int itemValue = valuesByName != null && valuesByName[item.Name] != null
                    ? ParseInt(valuesByName[item.Name], value)
                    : value;
                items.Add(BuildItemSnapshot(item, itemValue, decryptLevel, pcName, true, true));
            }

            var resp = BaseResponse("bundle", webCallId, true);
            resp["value"] = value;
            resp["decryptLevel"] = decryptLevel;
            resp["pcName"] = pcName;
            resp["items"] = items;
            PostToWeb(resp.ToString(Newtonsoft.Json.Formatting.None));
        }

        private void RespondSnapshot(string webCallId, JObject parsed)
        {
            EnsureCatalogLoaded();

            string itemName = parsed.Value<string>("itemName") ?? "";
            IntelligenceItem item;
            if (!_items.TryGetValue(itemName, out item))
            {
                RespondError(webCallId, "snapshot", "unknown_item");
                return;
            }

            Dictionary<string, string> textMap;
            string textError;
            if (!TryLoadTextMap(item, out textMap, out textError))
            {
                RespondError(webCallId, "snapshot", textError);
                return;
            }

            int value = ParseInt(parsed["value"], item.MaxValue);
            int decryptLevel = ParseInt(parsed["decryptLevel"], 0);
            string pcName = parsed.Value<string>("pcName") ?? "";

            JObject payload = BuildItemSnapshot(item, value, decryptLevel, pcName, false, false);

            var resp = BaseResponse("snapshot", webCallId, true);
            resp["item"] = BuildCatalogEntry(item);
            resp["name"] = payload["name"];
            resp["maxValue"] = payload["maxValue"];
            resp["value"] = payload["value"];
            resp["decryptLevel"] = payload["decryptLevel"];
            resp["pcName"] = payload["pcName"];
            resp["pages"] = payload["pages"];
            resp["encryptRules"] = payload["encryptRules"];

            PostToWeb(resp.ToString(Newtonsoft.Json.Formatting.None));
        }

        private JObject BuildItemSnapshot(
            IntelligenceItem item,
            int value,
            int decryptLevel,
            string pcName,
            bool includeLockedText,
            bool tolerateMissingText)
        {
            Dictionary<string, string> textMap;
            string textError;
            if (!TryLoadTextMap(item, out textMap, out textError))
            {
                if (!tolerateMissingText)
                    throw new InvalidOperationException(textError);
                textMap = null;
            }

            JObject obj = BuildCatalogEntry(item);
            obj["value"] = value;
            obj["decryptLevel"] = decryptLevel;
            obj["pcName"] = pcName;
            if (!string.IsNullOrEmpty(textError))
                obj["textError"] = textError;

            var pages = new JArray();
            for (int i = 0; i < item.Pages.Count; i++)
            {
                IntelligencePage page = item.Pages[i];
                bool unlocked = page.Value <= value;
                string text = "";
                if ((unlocked || includeLockedText) && textMap != null && textMap.ContainsKey(page.PageKey))
                    text = textMap[page.PageKey];

                var pageObj = new JObject();
                pageObj["pageKey"] = page.PageKey;
                pageObj["value"] = page.Value;
                pageObj["encryptLevel"] = page.EncryptLevel;
                pageObj["unlocked"] = unlocked;
                pageObj["text"] = text;
                pages.Add(pageObj);
            }
            obj["pages"] = pages;

            var rules = new JObject();
            rules["replace"] = DictionaryToJObject(item.EncryptReplace);
            rules["cut"] = DictionaryToJObject(item.EncryptCut);
            obj["encryptRules"] = rules;

            return obj;
        }

        private JObject BuildCatalogEntry(IntelligenceItem item)
        {
            var obj = new JObject();
            obj["name"] = item.Name;
            obj["iconName"] = string.IsNullOrEmpty(item.IconName) ? item.Name : item.IconName;
            obj["index"] = item.Index;
            obj["maxValue"] = item.MaxValue;
            obj["pageCount"] = item.Pages.Count;
            return obj;
        }

        private void EnsureCatalogLoaded()
        {
            lock (_lock)
            {
                if (_items != null) return;

                var doc = new XmlDocument();
                doc.Load(_dictionaryPath);
                Dictionary<string, string> iconByName = LoadItemIconMap();
                var items = new Dictionary<string, IntelligenceItem>();
                var catalog = new List<IntelligenceItem>();
                XmlNodeList nodes = doc.SelectNodes("/root/Item");
                if (nodes != null)
                {
                    foreach (XmlNode node in nodes)
                    {
                        IntelligenceItem item = ParseItem(node);
                        if (item == null || string.IsNullOrEmpty(item.Name)) continue;
                        string iconName;
                        if (iconByName.TryGetValue(item.Name, out iconName) && !string.IsNullOrEmpty(iconName))
                            item.IconName = iconName;
                        items[item.Name] = item;
                        catalog.Add(item);
                    }
                }
                catalog.Sort(delegate(IntelligenceItem a, IntelligenceItem b)
                {
                    int cmp = a.Index.CompareTo(b.Index);
                    return cmp != 0 ? cmp : string.Compare(a.Name, b.Name, StringComparison.Ordinal);
                });
                _items = items;
                _catalog = catalog;
            }
        }

        private IntelligenceItem ParseItem(XmlNode node)
        {
            var item = new IntelligenceItem();
            item.Name = ChildText(node, "Name");
            item.Index = ParseInt(ChildText(node, "Index"), 0);

            XmlNode replace = SelectChild(node, "EncryptReplace");
            if (replace != null) FillRuleMap(replace, item.EncryptReplace);
            XmlNode cut = SelectChild(node, "EncryptCut");
            if (cut != null) FillRuleMap(cut, item.EncryptCut);

            foreach (XmlNode child in node.ChildNodes)
            {
                if (child.NodeType != XmlNodeType.Element || child.Name != "Information") continue;
                var page = new IntelligencePage();
                page.Value = ParseInt(AttributeText(child, "Value"), 0);
                page.PageKey = AttributeText(child, "PageKey");
                page.EncryptLevel = ParseInt(AttributeText(child, "EncryptLevel"), 0);
                if (string.IsNullOrEmpty(page.PageKey)) continue;
                item.Pages.Add(page);
                if (page.Value > item.MaxValue) item.MaxValue = page.Value;
            }

            return item;
        }

        private Dictionary<string, string> LoadItemIconMap()
        {
            var result = new Dictionary<string, string>();
            if (!File.Exists(_itemDictionaryPath)) return result;

            try
            {
                var doc = new XmlDocument();
                doc.Load(_itemDictionaryPath);
                XmlNodeList nodes = doc.SelectNodes("//item");
                if (nodes == null) return result;
                foreach (XmlNode node in nodes)
                {
                    string name = ChildText(node, "name");
                    string icon = ChildText(node, "icon");
                    if (!string.IsNullOrEmpty(name) && !string.IsNullOrEmpty(icon))
                        result[name] = icon;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[IntelligenceTask] item icon map load failed: " + ex.Message);
            }
            return result;
        }

        private void FillRuleMap(XmlNode parent, Dictionary<string, string> target)
        {
            foreach (XmlNode child in parent.ChildNodes)
            {
                if (child.NodeType != XmlNodeType.Element) continue;
                target[child.Name] = child.InnerText ?? "";
            }
        }

        private bool TryLoadTextMap(IntelligenceItem item, out Dictionary<string, string> textMap, out string error)
        {
            lock (_lock)
            {
                if (_textCache.TryGetValue(item.Name, out textMap))
                {
                    error = null;
                    return true;
                }
            }

            string fullPath;
            if (!TryResolveTextPath(item.Name, out fullPath))
            {
                textMap = null;
                error = "text_path_invalid";
                return false;
            }
            if (!File.Exists(fullPath))
            {
                textMap = null;
                error = "text_missing";
                return false;
            }

            string content = File.ReadAllText(fullPath, Encoding.UTF8);
            textMap = ParseTextContent(content);
            lock (_lock) { _textCache[item.Name] = textMap; }
            error = null;
            return true;
        }

        private bool TryResolveTextPath(string itemName, out string fullPath)
        {
            string root = EnsureTrailingSeparator(Path.GetFullPath(_textDir));
            fullPath = Path.GetFullPath(Path.Combine(_textDir, itemName + ".txt"));
            return fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase);
        }

        internal static Dictionary<string, string> ParseTextContent(string content)
        {
            var result = new Dictionary<string, string>();
            if (content == null) return result;

            content = content.Replace("\r\n", "\n").Replace("\r", "\n");
            string[] lines = content.Split('\n');
            string currentKey = null;
            var currentLines = new List<string>();

            for (int i = 0; i < lines.Length; i++)
            {
                string line = lines[i];
                string delimiterKey;
                if (TryExtractDelimiter(line, out delimiterKey))
                {
                    if (currentKey != null)
                        result[currentKey] = TrimContent(currentLines);
                    currentKey = delimiterKey;
                    currentLines.Clear();
                }
                else if (currentKey != null)
                {
                    currentLines.Add(line);
                }
            }

            if (currentKey != null)
                result[currentKey] = TrimContent(currentLines);

            return result;
        }

        private static bool TryExtractDelimiter(string line, out string key)
        {
            key = null;
            if (line == null) return false;
            string trimmed = line.Trim();
            if (!trimmed.StartsWith("@@@", StringComparison.Ordinal)) return false;
            int last = trimmed.LastIndexOf("@@@", StringComparison.Ordinal);
            if (last <= 3) return false;
            key = trimmed.Substring(3, last - 3);
            return key.Length > 0;
        }

        private static string TrimContent(List<string> lines)
        {
            int start = 0;
            int end = lines.Count - 1;
            while (start <= end && string.IsNullOrWhiteSpace(lines[start])) start++;
            while (end >= start && string.IsNullOrWhiteSpace(lines[end])) end--;
            if (end < start) return "";

            var sb = new StringBuilder();
            for (int i = start; i <= end; i++)
            {
                if (i > start) sb.Append('\n');
                sb.Append(lines[i]);
            }
            return sb.ToString();
        }

        private JObject BaseResponse(string cmd, string callId, bool success)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "intelligence";
            resp["cmd"] = cmd;
            resp["callId"] = callId;
            resp["success"] = success;
            return resp;
        }

        private void RespondError(string webCallId, string cmd, string error)
        {
            var resp = BaseResponse(cmd, webCallId, false);
            resp["error"] = error;
            PostToWeb(resp.ToString(Newtonsoft.Json.Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null)
                _postToWeb(json);
        }

        private static JObject DictionaryToJObject(Dictionary<string, string> dict)
        {
            var obj = new JObject();
            foreach (KeyValuePair<string, string> pair in dict)
                obj[pair.Key] = pair.Value;
            return obj;
        }

        private static XmlNode SelectChild(XmlNode node, string name)
        {
            foreach (XmlNode child in node.ChildNodes)
                if (child.NodeType == XmlNodeType.Element && child.Name == name) return child;
            return null;
        }

        private static string ChildText(XmlNode node, string name)
        {
            XmlNode child = SelectChild(node, name);
            return child == null ? "" : (child.InnerText ?? "");
        }

        private static string AttributeText(XmlNode node, string name)
        {
            XmlAttribute attr = node.Attributes == null ? null : node.Attributes[name];
            return attr == null ? "" : (attr.Value ?? "");
        }

        private static int ParseInt(JToken token, int fallback)
        {
            if (token == null) return fallback;
            int value;
            if (int.TryParse(token.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out value))
                return value;
            return fallback;
        }

        private static int ParseInt(string raw, int fallback)
        {
            int value;
            if (int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out value))
                return value;
            return fallback;
        }

        private static string EnsureTrailingSeparator(string path)
        {
            if (path.EndsWith(Path.DirectorySeparatorChar.ToString(), StringComparison.Ordinal) ||
                path.EndsWith(Path.AltDirectorySeparatorChar.ToString(), StringComparison.Ordinal))
                return path;
            return path + Path.DirectorySeparatorChar;
        }
    }
}
