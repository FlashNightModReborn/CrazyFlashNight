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
            public string DisplayName;
            public string IconName;
            public int Index;
            public int MaxValue;
            public readonly List<IntelligencePage> Pages = new List<IntelligencePage>();
            public readonly Dictionary<string, string> EncryptReplace = new Dictionary<string, string>();
            public readonly Dictionary<string, string> EncryptCut = new Dictionary<string, string>();
        }

        private sealed class H5Document
        {
            public string Skin;
            public readonly Dictionary<string, JArray> Pages = new Dictionary<string, JArray>();
        }

        private struct ItemMeta
        {
            public string IconName;
            public string DisplayName;
        }

        private readonly string _dictionaryPath;
        private readonly string _itemDictionaryPath;
        private readonly string _textDir;
        private readonly string _h5Dir;
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
        private readonly Dictionary<string, H5Document> _h5Cache =
            new Dictionary<string, H5Document>();

        private static readonly HashSet<string> H5BlockTypes = new HashSet<string>(StringComparer.Ordinal)
        {
            "paragraph", "heading", "list", "table", "quote", "divider", "stamp", "note",
            "handwritten", "annotation", "terminalLog", "redaction", "decryptBlock", "blueprint", "timeline",
            "hardwareExtract", "surfaceMark"
        };

        private static readonly HashSet<string> H5InlineTypes = new HashSet<string>(StringComparer.Ordinal)
        {
            "text", "strong", "underline", "colorToken", "damageText", "redaction", "decryptText", "pcName"
        };

        private static readonly HashSet<string> H5ColorTokens = new HashSet<string>(StringComparer.Ordinal)
        {
            "danger", "warning", "info", "success", "muted", "material-basic", "material-mid",
            "material-high", "material-rare", "biohazard", "faction-army", "faction-noah",
            "faction-blackiron", "faction-university"
        };

        private static readonly HashSet<string> H5Skins = new HashSet<string>(StringComparer.Ordinal)
        {
            "paper", "report", "dossier", "terminal", "newspaper", "blueprint", "diary", "edict"
        };

        private static readonly HashSet<string> H5SurfaceVariants = new HashSet<string>(StringComparer.Ordinal)
        {
            "dirt", "water", "blood-hand", "fold", "tear"
        };

        private static readonly HashSet<string> H5DamageKinds = new HashSet<string>(StringComparer.Ordinal)
        {
            "data-loss", "smear", "deleted", "missing", "blurred", "edited"
        };

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
            _h5Dir = Path.Combine(root, "data", "intelligence_h5");
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

            string sourceError;
            if (!HasReadableContentSource(item, out sourceError))
            {
                RespondError(webCallId, "snapshot", sourceError);
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
            resp["contentMode"] = payload["contentMode"];
            if (payload["skin"] != null) resp["skin"] = payload["skin"];
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
            H5Document h5Doc;
            string h5Error;
            bool useH5 = TryLoadH5Document(item, out h5Doc, out h5Error);
            Dictionary<string, string> textMap;
            string textError;
            if (useH5)
            {
                textMap = null;
                textError = null;
            }
            else
            {
                TryLoadTextMap(item, out textMap, out textError);
            }

            JObject obj = BuildCatalogEntry(item);
            obj["value"] = value;
            obj["unlockedCount"] = CountUnlockedPages(item, value);
            obj["decryptLevel"] = decryptLevel;
            obj["pcName"] = pcName;
            obj["contentMode"] = useH5 ? "h5" : "legacy";
            if (useH5)
                obj["skin"] = h5Doc.Skin;
            if (!string.IsNullOrEmpty(h5Error) && IsH5Strict())
                obj["textError"] = h5Error;
            else if (!string.IsNullOrEmpty(textError))
                obj["textError"] = textError;

            var pages = new JArray();
            for (int i = 0; i < item.Pages.Count; i++)
            {
                IntelligencePage page = item.Pages[i];
                bool unlocked = page.Value <= value;
                string text = "";

                var pageObj = new JObject();
                pageObj["pageKey"] = page.PageKey;
                pageObj["value"] = page.Value;
                pageObj["encryptLevel"] = page.EncryptLevel;
                pageObj["unlocked"] = unlocked;
                if (useH5)
                {
                    if ((unlocked || includeLockedText) && h5Doc.Pages.ContainsKey(page.PageKey))
                    {
                        JToken cloned = h5Doc.Pages[page.PageKey].DeepClone();
                        if (!includeLockedText)
                            StripLockedDecryptText(cloned, decryptLevel);
                        pageObj["blocks"] = cloned;
                    }
                    else
                    {
                        pageObj["blocks"] = new JArray();
                    }
                }
                else
                {
                    if ((unlocked || includeLockedText) && textMap != null && textMap.ContainsKey(page.PageKey))
                        text = textMap[page.PageKey];
                    pageObj["text"] = text;
                }
                pages.Add(pageObj);
            }
            obj["pages"] = pages;

            var rules = new JObject();
            rules["replace"] = DictionaryToJObject(item.EncryptReplace);
            rules["cut"] = DictionaryToJObject(item.EncryptCut);
            obj["encryptRules"] = rules;

            return obj;
        }

        private static void StripLockedDecryptText(JToken token, int decryptLevel)
        {
            JArray arr = token as JArray;
            if (arr != null)
            {
                for (int i = 0; i < arr.Count; i++) StripLockedDecryptText(arr[i], decryptLevel);
                return;
            }
            JObject obj = token as JObject;
            if (obj == null) return;

            string type = obj.Value<string>("type");
            if (string.Equals(type, "decryptText", StringComparison.Ordinal))
            {
                int level = ParseInt(obj["level"], 0);
                if (level > decryptLevel)
                {
                    obj["content"] = new JArray();
                    obj.Remove("text");
                }
                return;
            }

            foreach (JProperty prop in obj.Properties())
                StripLockedDecryptText(prop.Value, decryptLevel);
        }

        private JObject BuildCatalogEntry(IntelligenceItem item)
        {
            var obj = new JObject();
            obj["name"] = item.Name;
            obj["displayName"] = string.IsNullOrEmpty(item.DisplayName) ? item.Name : item.DisplayName;
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
                Dictionary<string, ItemMeta> metaByName = LoadItemMetaMap();
                var items = new Dictionary<string, IntelligenceItem>();
                var catalog = new List<IntelligenceItem>();
                XmlNodeList nodes = doc.SelectNodes("/root/Item");
                if (nodes != null)
                {
                    foreach (XmlNode node in nodes)
                    {
                        IntelligenceItem item = ParseItem(node);
                        if (item == null || string.IsNullOrEmpty(item.Name)) continue;
                        ItemMeta meta;
                        if (metaByName.TryGetValue(item.Name, out meta))
                        {
                            if (!string.IsNullOrEmpty(meta.IconName)) item.IconName = meta.IconName;
                            if (!string.IsNullOrEmpty(meta.DisplayName)) item.DisplayName = meta.DisplayName;
                        }
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

        private Dictionary<string, ItemMeta> LoadItemMetaMap()
        {
            var result = new Dictionary<string, ItemMeta>();
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
                    if (string.IsNullOrEmpty(name)) continue;
                    var meta = new ItemMeta();
                    meta.IconName = ChildText(node, "icon");
                    meta.DisplayName = ChildText(node, "displayname");
                    result[name] = meta;
                }
            }
            catch (Exception ex)
            {
                LogManager.Log("[IntelligenceTask] item meta map load failed: " + ex.Message);
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

        private bool HasReadableContentSource(IntelligenceItem item, out string error)
        {
            H5Document h5Doc;
            if (TryLoadH5Document(item, out h5Doc, out error)) return true;
            if (IsH5Strict()) return false;

            Dictionary<string, string> textMap;
            return TryLoadTextMap(item, out textMap, out error);
        }

        private bool IsH5Strict()
        {
            return Directory.Exists(_h5Dir);
        }

        private bool TryLoadH5Document(IntelligenceItem item, out H5Document h5Doc, out string error)
        {
            lock (_lock)
            {
                if (_h5Cache.TryGetValue(item.Name, out h5Doc))
                {
                    error = null;
                    return true;
                }
            }

            string fullPath;
            if (!TryResolveH5Path(item.Name, out fullPath))
            {
                h5Doc = null;
                error = "h5_path_invalid";
                return false;
            }
            if (!File.Exists(fullPath))
            {
                h5Doc = null;
                error = "h5_missing";
                return false;
            }

            try
            {
                JObject root = JObject.Parse(File.ReadAllText(fullPath, Encoding.UTF8));
                string validationError;
                h5Doc = ParseH5Document(item, root, out validationError);
                if (h5Doc == null)
                {
                    error = validationError ?? "h5_invalid";
                    return false;
                }
                lock (_lock) { _h5Cache[item.Name] = h5Doc; }
                error = null;
                return true;
            }
            catch (Exception ex)
            {
                h5Doc = null;
                LogManager.Log("[IntelligenceTask] H5 parse failed for " + item.Name + ": " + ex.Message);
                error = "h5_invalid_json";
                return false;
            }
        }

        private H5Document ParseH5Document(IntelligenceItem item, JObject root, out string error)
        {
            error = null;
            if (ParseInt(root["schemaVersion"], 0) != 1)
            {
                error = "h5_schema_version";
                return null;
            }
            if (!string.Equals(root.Value<string>("itemName") ?? "", item.Name, StringComparison.Ordinal))
            {
                error = "h5_item_mismatch";
                return null;
            }

            string skin = root.Value<string>("skin") ?? "paper";
            if (!H5Skins.Contains(skin))
            {
                error = "h5_unknown_skin";
                return null;
            }

            JArray pages = root["pages"] as JArray;
            if (pages == null || pages.Count != item.Pages.Count)
            {
                error = "h5_pagekey_mismatch";
                return null;
            }

            var doc = new H5Document();
            doc.Skin = skin;
            for (int i = 0; i < pages.Count; i++)
            {
                JObject page = pages[i] as JObject;
                if (page == null)
                {
                    error = "h5_page_invalid";
                    return null;
                }
                string pageKey = page.Value<string>("pageKey") ?? "";
                if (!string.Equals(pageKey, item.Pages[i].PageKey, StringComparison.Ordinal))
                {
                    error = "h5_pagekey_mismatch";
                    return null;
                }
                JArray blocks = page["blocks"] as JArray;
                if (blocks == null)
                {
                    error = "h5_blocks_invalid";
                    return null;
                }
                string blockError;
                if (!ValidateH5Blocks(blocks, out blockError))
                {
                    error = blockError;
                    return null;
                }
                doc.Pages[pageKey] = blocks;
            }
            return doc;
        }

        private bool TryResolveH5Path(string itemName, out string fullPath)
        {
            string root = EnsureTrailingSeparator(Path.GetFullPath(_h5Dir));
            fullPath = Path.GetFullPath(Path.Combine(_h5Dir, itemName + ".json"));
            return fullPath.StartsWith(root, StringComparison.OrdinalIgnoreCase);
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

        private bool ValidateH5Blocks(JArray blocks, out string error)
        {
            for (int i = 0; i < blocks.Count; i++)
            {
                if (!ValidateH5Block(blocks[i], out error)) return false;
            }
            error = null;
            return true;
        }

        private bool ValidateH5Block(JToken token, out string error)
        {
            JObject obj = token as JObject;
            if (obj == null)
            {
                error = "h5_block_invalid";
                return false;
            }
            if (!ValidateSafeJson(obj, out error)) return false;

            string type = obj.Value<string>("type") ?? "";
            if (!H5BlockTypes.Contains(type))
            {
                error = "h5_unknown_block";
                return false;
            }
            if (type == "surfaceMark")
            {
                string variant = obj.Value<string>("variant") ?? "dirt";
                if (!H5SurfaceVariants.Contains(variant))
                {
                    error = "h5_unknown_surface_variant";
                    return false;
                }
            }

            if (!ValidateH5InlineArray(obj["content"], out error)) return false;
            if (!ValidateH5InlineOrString(obj["title"], out error)) return false;
            if (!ValidateH5InlineOrString(obj["caption"], out error)) return false;
            if (!ValidateH5InlineOrString(obj["label"], out error)) return false;
            if (!ValidateH5InlineOrString(obj["note"], out error)) return false;
            if (!ValidateH5BlockArray(obj["blocks"], out error)) return false;
            if (!ValidateH5BlockArray(obj["reveal"], out error)) return false;
            if (!ValidateH5BlockArray(obj["plain"], out error)) return false;
            if (!ValidateH5BlockArray(obj["encrypted"], out error)) return false;
            if (!ValidateH5Items(obj["items"], out error)) return false;
            if (!ValidateH5Entries(obj["entries"], out error)) return false;
            if (!ValidateH5Rows(obj["rows"], out error)) return false;
            if (!ValidateH5Steps(obj["steps"], out error)) return false;

            error = null;
            return true;
        }

        private bool ValidateH5BlockArray(JToken token, out string error)
        {
            error = null;
            if (token == null) return true;
            JArray arr = token as JArray;
            if (arr == null)
            {
                error = "h5_block_array_invalid";
                return false;
            }
            return ValidateH5Blocks(arr, out error);
        }

        private bool ValidateH5InlineArray(JToken token, out string error)
        {
            error = null;
            if (token == null) return true;
            JArray arr = token as JArray;
            if (arr == null)
            {
                error = "h5_inline_invalid";
                return false;
            }
            for (int i = 0; i < arr.Count; i++)
            {
                if (!ValidateH5Inline(arr[i], out error)) return false;
            }
            return true;
        }

        private bool ValidateH5InlineOrString(JToken token, out string error)
        {
            error = null;
            if (token == null) return true;
            if (token.Type == JTokenType.String) return ValidateSafeString(token.ToString(), out error);
            return ValidateH5InlineArray(token, out error);
        }

        private bool ValidateH5Inline(JToken token, out string error)
        {
            error = null;
            if (token == null) return true;
            if (token.Type == JTokenType.String) return ValidateSafeString(token.ToString(), out error);
            JObject obj = token as JObject;
            if (obj == null)
            {
                error = "h5_inline_invalid";
                return false;
            }
            if (!ValidateSafeJson(obj, out error)) return false;

            string type = obj.Value<string>("type") ?? "";
            if (!H5InlineTypes.Contains(type))
            {
                error = "h5_unknown_inline";
                return false;
            }
            if (type == "colorToken")
            {
                string color = obj.Value<string>("token") ?? "";
                if (!H5ColorTokens.Contains(color))
                {
                    error = "h5_unknown_color_token";
                    return false;
                }
            }
            if (type == "damageText")
            {
                string kind = obj.Value<string>("kind") ?? "data-loss";
                if (!H5DamageKinds.Contains(kind))
                {
                    error = "h5_unknown_damage_kind";
                    return false;
                }
            }
            if (!ValidateH5InlineArray(obj["content"], out error)) return false;
            if (!ValidateH5InlineArray(obj["reveal"], out error)) return false;
            return true;
        }

        private bool ValidateH5Items(JToken token, out string error)
        {
            error = null;
            if (token == null) return true;
            JArray arr = token as JArray;
            if (arr == null)
            {
                error = "h5_items_invalid";
                return false;
            }
            for (int i = 0; i < arr.Count; i++)
            {
                JToken child = arr[i];
                if (child is JArray)
                {
                    if (!ValidateH5InlineArray(child, out error)) return false;
                }
                else if (child is JObject && ((JObject)child)["type"] != null)
                {
                    if (!ValidateH5Block(child, out error)) return false;
                }
                else if (child is JObject && ((JObject)child)["content"] != null)
                {
                    if (!ValidateH5InlineArray(((JObject)child)["content"], out error)) return false;
                }
                else if (child.Type != JTokenType.String)
                {
                    error = "h5_items_invalid";
                    return false;
                }
            }
            return true;
        }

        private bool ValidateH5Entries(JToken token, out string error)
        {
            error = null;
            if (token == null) return true;
            JArray arr = token as JArray;
            if (arr == null)
            {
                error = "h5_entries_invalid";
                return false;
            }
            for (int i = 0; i < arr.Count; i++)
            {
                JObject entry = arr[i] as JObject;
                if (entry == null)
                {
                    error = "h5_entries_invalid";
                    return false;
                }
                if (!ValidateSafeJson(entry, out error)) return false;
                if (!ValidateH5InlineArray(entry["content"], out error)) return false;
                if (!ValidateH5BlockArray(entry["blocks"], out error)) return false;
            }
            return true;
        }

        private bool ValidateH5Rows(JToken token, out string error)
        {
            error = null;
            if (token == null) return true;
            JArray rows = token as JArray;
            if (rows == null)
            {
                error = "h5_rows_invalid";
                return false;
            }
            for (int i = 0; i < rows.Count; i++)
            {
                JArray row = rows[i] as JArray;
                if (row == null)
                {
                    error = "h5_rows_invalid";
                    return false;
                }
                for (int j = 0; j < row.Count; j++)
                {
                    JToken cell = row[j];
                    if (cell is JArray)
                    {
                        if (!ValidateH5InlineArray(cell, out error)) return false;
                    }
                    else if (cell.Type != JTokenType.String && cell.Type != JTokenType.Integer && cell.Type != JTokenType.Float)
                    {
                        error = "h5_rows_invalid";
                        return false;
                    }
                }
            }
            return true;
        }

        private bool ValidateH5Steps(JToken token, out string error)
        {
            error = null;
            if (token == null) return true;
            JArray steps = token as JArray;
            if (steps == null)
            {
                error = "h5_steps_invalid";
                return false;
            }
            for (int i = 0; i < steps.Count; i++)
            {
                if (steps[i].Type == JTokenType.String) continue;
                JObject obj = steps[i] as JObject;
                if (obj == null)
                {
                    error = "h5_steps_invalid";
                    return false;
                }
                if (!ValidateSafeJson(obj, out error)) return false;
                if (!ValidateH5InlineArray(obj["content"], out error)) return false;
            }
            return true;
        }

        private const int MaxValidationDepth = 50;

        private bool ValidateSafeJson(JToken token, out string error)
        {
            return ValidateSafeJson(token, 0, out error);
        }

        private bool ValidateSafeJson(JToken token, int depth, out string error)
        {
            error = null;
            if (depth > MaxValidationDepth)
            {
                error = "h5_depth_exceeded";
                return false;
            }
            JObject obj = token as JObject;
            if (obj != null)
            {
                foreach (JProperty prop in obj.Properties())
                {
                    if (prop.Name.StartsWith("on", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(prop.Name, "html", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(prop.Name, "innerHTML", StringComparison.OrdinalIgnoreCase) ||
                        string.Equals(prop.Name, "script", StringComparison.OrdinalIgnoreCase))
                    {
                        error = "h5_unsafe_key";
                        return false;
                    }
                    if (!ValidateSafeJson(prop.Value, depth + 1, out error)) return false;
                }
                return true;
            }
            JArray arr = token as JArray;
            if (arr != null)
            {
                for (int i = 0; i < arr.Count; i++)
                    if (!ValidateSafeJson(arr[i], depth + 1, out error)) return false;
                return true;
            }
            if (token != null && token.Type == JTokenType.String)
                return ValidateSafeString(token.ToString(), out error);
            return true;
        }

        private bool ValidateSafeString(string value, out string error)
        {
            error = null;
            if (value == null) return true;
            if (value.IndexOf("<script", StringComparison.OrdinalIgnoreCase) >= 0 ||
                value.IndexOf("javascript:", StringComparison.OrdinalIgnoreCase) >= 0 ||
                value.IndexOf("onerror=", StringComparison.OrdinalIgnoreCase) >= 0 ||
                value.IndexOf("onclick=", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                error = "h5_unsafe_string";
                return false;
            }
            return true;
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
            if (_disposed) return;
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_disposed) return; if (_postToWeb != null) _postToWeb(json); });
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
