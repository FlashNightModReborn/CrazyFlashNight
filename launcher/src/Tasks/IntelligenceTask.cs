using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Xml;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Web 情报详情面板的数据源。
    /// Dev 路径读取本地全量 bundle；runtime 路径用 Flash 状态小包 + C# 按需正文。
    /// </summary>
    public sealed class IntelligenceTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
        }

        private sealed class RuntimeState
        {
            public readonly Dictionary<string, int> Values = new Dictionary<string, int>();
            public int DecryptLevel;
            public string PcName = "";
        }

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
        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private readonly object _lock = new object();
        private readonly Dictionary<int, PendingRequest> _pending = new Dictionary<int, PendingRequest>();
        private readonly Dictionary<int, Timer> _timers = new Dictionary<int, Timer>();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private Dictionary<string, IntelligenceItem> _items;
        private List<IntelligenceItem> _catalog;
        private RuntimeState _runtimeState;
        private int _seq;
        private volatile bool _disposed;
        private readonly Dictionary<string, Dictionary<string, string>> _textCache =
            new Dictionary<string, Dictionary<string, string>>();

        public IntelligenceTask(string projectRoot)
            : this(projectRoot, (Func<bool>)null, null)
        {
        }

        public IntelligenceTask(string projectRoot, XmlSocketServer socket)
            : this(
                projectRoot,
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); })
        {
        }

        public IntelligenceTask(string projectRoot, Func<bool> isClientReady, Action<string> send)
        {
            string root = string.IsNullOrEmpty(projectRoot)
                ? AppDomain.CurrentDomain.BaseDirectory
                : projectRoot;
            _dictionaryPath = Path.Combine(root, "data", "dictionaries", "information_dictionary.xml");
            _itemDictionaryPath = Path.Combine(root, "data", "items", "收集品_情报.xml");
            _textDir = Path.Combine(root, "data", "intelligence");
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                foreach (var t in _timers.Values) t.Dispose();
                _timers.Clear();
                _pending.Clear();
                _runtimeState = null;
            }
        }

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
                    case "state":
                        RequestFlash(webCallId, cmd, "intelligenceState", parsed);
                        break;
                    case "tooltip":
                        RequestTooltip(webCallId, parsed);
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

        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[IntelligenceTask] <- Flash response received");
            int fid = msg.Value<int>("callId");
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    if (respond != null) respond(null);
                    return;
                }
                _pending.Remove(fid);
                Timer timer;
                if (_timers.TryGetValue(fid, out timer))
                {
                    timer.Dispose();
                    _timers.Remove(fid);
                }
            }

            try
            {
                if (entry.WebCmd == "state")
                {
                    ForwardStateResponse(entry.WebCallId, msg);
                }
                else
                {
                    ForwardPassThroughResponse(entry.WebCallId, entry.WebCmd, msg);
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[IntelligenceTask] flash response failed: " + ex.Message);
                RespondError(entry.WebCallId, entry.WebCmd, "internal_error");
            }

            if (respond != null) respond(null);
        }

        private void RequestTooltip(string webCallId, JObject parsed)
        {
            EnsureCatalogLoaded();
            string itemName = parsed.Value<string>("itemName") ?? "";
            if (!_items.ContainsKey(itemName))
            {
                RespondError(webCallId, "tooltip", "unknown_item");
                return;
            }
            RequestFlash(webCallId, "tooltip", "intelligenceTooltip", parsed);
        }

        private void RequestFlash(string webCallId, string webCmd, string action, JObject parsed)
        {
            if (!_isClientReady())
            {
                RespondError(webCallId, webCmd, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                fid = ++_seq;
                _pending[fid] = new PendingRequest
                {
                    WebCallId = webCallId,
                    WebCmd = webCmd
                };
            }

            var timer = new Timer(delegate
            {
                if (_disposed) return;

                PendingRequest entry;
                lock (_lock)
                {
                    if (!_pending.TryGetValue(fid, out entry)) return;
                    _pending.Remove(fid);
                    _timers.Remove(fid);
                }

                RespondError(entry.WebCallId, entry.WebCmd, "timeout");
            }, null, 10000, Timeout.Infinite);

            lock (_lock) { _timers[fid] = timer; }

            var flashMsg = new JObject();
            flashMsg["task"] = "cmd";
            flashMsg["action"] = action;
            flashMsg["callId"] = fid;
            foreach (var prop in parsed.Properties())
            {
                if (prop.Name != "type" && prop.Name != "panel" && prop.Name != "cmd" && prop.Name != "callId")
                    flashMsg[prop.Name] = prop.Value;
            }

            string flashJson = flashMsg.ToString(Newtonsoft.Json.Formatting.None);
            LogManager.Log("[IntelligenceTask] -> Flash: " + flashJson);
            _send(flashJson + "\0");
        }

        private void ForwardStateResponse(string webCallId, JObject msg)
        {
            bool success = msg.Value<bool?>("success") ?? false;
            if (!success)
            {
                RespondError(webCallId, "state", msg.Value<string>("error") ?? "flash_error");
                return;
            }

            EnsureCatalogLoaded();

            JObject rawValues = msg["values"] as JObject;
            var state = new RuntimeState();
            state.DecryptLevel = ParseInt(msg["decryptLevel"], 0);
            state.PcName = msg.Value<string>("pcName") ?? "";

            var items = new JArray();
            var values = new JObject();
            foreach (IntelligenceItem item in _catalog)
            {
                int value = rawValues == null ? 0 : ParseInt(rawValues[item.Name], 0);
                value = ClampValue(value, item);
                state.Values[item.Name] = value;
                values[item.Name] = value;
                items.Add(BuildStateEntry(item, value));
            }

            lock (_lock) { _runtimeState = state; }

            var resp = BaseResponse("state", webCallId, true);
            resp["items"] = items;
            resp["values"] = values;
            resp["decryptLevel"] = state.DecryptLevel;
            resp["pcName"] = state.PcName;
            PostToWeb(resp.ToString(Newtonsoft.Json.Formatting.None));
        }

        private void ForwardPassThroughResponse(string webCallId, string webCmd, JObject msg)
        {
            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "intelligence";
            msg["cmd"] = webCmd;
            msg["callId"] = webCallId;
            PostToWeb(msg.ToString(Newtonsoft.Json.Formatting.None));
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

            var items = new JArray();
            foreach (IntelligenceItem item in _catalog)
                items.Add(BuildItemSnapshot(item, ClampValue(value, item), decryptLevel, pcName, true));

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

            Dictionary<string, string> probeMap;
            string textError;
            if (!TryLoadTextMap(item, out probeMap, out textError))
            {
                RespondError(webCallId, "snapshot", textError);
                return;
            }

            bool explicitState = parsed["value"] != null || parsed["decryptLevel"] != null || parsed["pcName"] != null;
            RuntimeState runtimeState = null;
            if (!explicitState)
            {
                lock (_lock) { runtimeState = _runtimeState; }
                if (runtimeState == null)
                {
                    RespondError(webCallId, "snapshot", "state_required");
                    return;
                }
            }

            int value = explicitState
                ? ParseInt(parsed["value"], item.MaxValue)
                : GetRuntimeValue(runtimeState, item.Name);
            int decryptLevel = explicitState
                ? ParseInt(parsed["decryptLevel"], 0)
                : runtimeState.DecryptLevel;
            string pcName = explicitState
                ? (parsed.Value<string>("pcName") ?? "")
                : (runtimeState.PcName ?? "");

            value = ClampValue(value, item);
            JObject payload = BuildItemSnapshot(item, value, decryptLevel, pcName, false);

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
            bool includeLockedText)
        {
            Dictionary<string, string> textMap;
            string textError;
            TryLoadTextMap(item, out textMap, out textError);

            JObject obj = BuildCatalogEntry(item);
            obj["value"] = value;
            obj["unlockedCount"] = CountUnlockedPages(item, value);
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

        private JObject BuildStateEntry(IntelligenceItem item, int value)
        {
            JObject obj = BuildCatalogEntry(item);
            obj["value"] = value;
            obj["unlockedCount"] = CountUnlockedPages(item, value);
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

        private static int GetRuntimeValue(RuntimeState state, string itemName)
        {
            int value;
            return state != null && state.Values.TryGetValue(itemName, out value) ? value : 0;
        }

        private static int ClampValue(int value, IntelligenceItem item)
        {
            if (value < 0) return 0;
            if (item != null && value > item.MaxValue) return item.MaxValue;
            return value;
        }

        private static int CountUnlockedPages(IntelligenceItem item, int value)
        {
            int count = 0;
            for (int i = 0; i < item.Pages.Count; i++)
                if (item.Pages[i].Value <= value) count++;
            return count;
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
