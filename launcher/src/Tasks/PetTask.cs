using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Data;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 战宠面板 WebView ↔ Flash 双层 callId 桥接。
    /// 与 ArenaTask / ShopTask 同构：
    ///   Web → C#   {type:"panel", panel:"pets", cmd, callId, ...}
    ///   C# → Flash {task:"cmd", action:"petSnapshot/petAdopt/...", callId:fid, ...}
    ///   Flash → C# {task:"pet_response", callId:fid, success, ...}
    ///   C# → Web   {type:"panel_resp", panel:"pets", cmd, callId, success, ...}
    ///
    /// 注意：close 不走本桥。Web 关闭面板时 WebOverlayForm.HandlePanelMessage 直接
    /// 切 _activePanel = null + ClosePanel()。
    /// </summary>
    public sealed class PetTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCallId;
            public string WebCmd;
        }

        private readonly Func<bool> _isClientReady;
        private readonly Action<string> _send;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly Dictionary<int, PendingRequest> _pending;
        private readonly Dictionary<int, Timer> _timers;
        private int _seq;
        private readonly object _lock = new object();
        private volatile bool _disposed;

        // 商城静态目录（pets.xml）的 C# 直答缓存。projectRoot 为 null 时退化为纯 Flash 透传。
        private readonly string _projectRoot;
        private PetCatalog _catalog;
        private string _catalogError;

        public PetTask(XmlSocketServer socket)
            : this(socket, null)
        {
        }

        public PetTask(XmlSocketServer socket, string projectRoot)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); },
                projectRoot)
        {
        }

        public PetTask(Func<bool> isClientReady, Action<string> send)
            : this(isClientReady, send, null)
        {
        }

        public PetTask(Func<bool> isClientReady, Action<string> send, string projectRoot)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
            _pending = new Dictionary<int, PendingRequest>();
            _timers = new Dictionary<int, Timer>();
            _projectRoot = projectRoot;
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public void Dispose()
        {
            _disposed = true;
            ClearPending();
        }

        /// <summary>
        /// WebView 侧面板请求入口（UI 线程调用）。
        /// </summary>
        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[PetTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[PetTask] webCallId is empty");
                return;
            }

            // 商城目录/宠物库是 pets.xml 的静态投影：C# 直答，不经 Flash、不需 client ready。
            // adopt_list 顺带消除"进店早于 snapshot 返回时分类页签空白"竞态。projectRoot 缺省时退回 Flash 透传。
            if (_projectRoot != null)
            {
                if (cmd == "adopt_list") { RespondAdoptList(webCallId, parsed); return; }
                if (cmd == "pet_lib") { RespondPetLib(webCallId); return; }
            }

            if (!_isClientReady())
            {
                RespondError(webCallId, cmd, "disconnected");
                return;
            }

            string action;
            switch (cmd)
            {
                case "snapshot":
                    action = "petSnapshot";
                    break;
                case "adopt_list":
                    action = "petAdoptList";
                    break;
                case "adopt":
                    action = "petAdopt";
                    break;
                case "deploy":
                    action = "petDeploy";
                    break;
                case "advance":
                    action = "petAdvance";
                    break;
                case "preview_advance":
                    action = "petPreviewAdvance";
                    break;
                case "expand_slot":
                    action = "petExpandSlot";
                    break;
                case "rename":
                    action = "petRename";
                    break;
                case "pet_tooltip":
                    action = "petTooltip";
                    break;
                case "restore_stamina":
                    action = "petRestoreStamina";
                    break;
                case "level_up":
                    action = "petLevelUp";
                    break;
                case "delete":
                    action = "petDelete";
                    break;
                default:
                    RespondError(webCallId, cmd, "unsupported_cmd");
                    return;
            }

            int fid;
            lock (_lock)
            {
                fid = ++_seq;
                _pending[fid] = new PendingRequest
                {
                    WebCallId = webCallId,
                    WebCmd = cmd
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

            // 信封构造 + 安全参数透传统一走 PanelBridge（含 action/task 保留键守卫，杜绝各桥漏抄）。
            var flashMsg = PanelBridge.BuildFlashCommand(action, fid, parsed);

            string flashJson = flashMsg.ToString(Formatting.None);
            LogManager.Log("[PetTask] -> Flash: " + flashJson);
            _send(flashJson + "\0");
        }

        /// <summary>
        /// Flash 侧回包入口（MessageRouter 在 XmlSocket 线程调用）。
        /// </summary>
        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[PetTask] <- Flash response received");
            int fid = msg.Value<int>("callId");
            PendingRequest entry;
            lock (_lock)
            {
                if (!_pending.TryGetValue(fid, out entry))
                {
                    respond(null);
                    return;
                }
                _pending.Remove(fid);
                Timer t;
                if (_timers.TryGetValue(fid, out t))
                {
                    t.Dispose();
                    _timers.Remove(fid);
                }
            }

            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "pets";
            msg["cmd"] = entry.WebCmd;
            msg["callId"] = entry.WebCallId;

            string json = msg.ToString(Formatting.None);
            PostToWeb(json);
            respond(null);
        }

        public void ClearPending()
        {
            lock (_lock)
            {
                foreach (var t in _timers.Values) t.Dispose();
                _timers.Clear();
                _pending.Clear();
            }
        }

        // ── 商城目录 C# 直答（pets.xml 静态投影，等价于 AS2 handleAdoptList + snapshot.categories）──

        /// <summary>
        /// 直答可领养列表。返回 { categories:[{name}], adoptable:[{petId,name,identifier,height,
        /// price,kprice,unlockLevel,unlockTask,unique}] }。categories 恒为全量（供页签）；
        /// adoptable 按 categoryIndex 过滤（&lt;0 = 全部）。运行态门槛由 Web 用 snapshot 自行判定。
        /// </summary>
        private void RespondAdoptList(string webCallId, JObject parsed)
        {
            PetCatalog catalog;
            string err;
            if (!EnsureCatalogLoaded(out catalog, out err))
            {
                RespondError(webCallId, "adopt_list", err);
                return;
            }

            int categoryIndex = -1;
            JToken ciTok = parsed["categoryIndex"];
            if (ciTok != null)
            {
                int ci;
                if (int.TryParse(ciTok.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out ci))
                    categoryIndex = ci;
            }

            var categories = new JArray();
            var adoptable = new JArray();
            for (int c = 0; c < catalog.Categories.Count; c++)
            {
                PetCatalog.PetCategory cat = catalog.Categories[c];
                var catObj = new JObject();
                catObj["name"] = cat.Name;
                categories.Add(catObj);

                if (categoryIndex >= 0 && c != categoryIndex) continue;
                for (int r = 0; r < cat.Rows.Count; r++)
                {
                    List<int?> row = cat.Rows[r];
                    for (int m = 0; m < row.Count; m++)
                    {
                        if (!row[m].HasValue) continue;
                        PetDef def;
                        if (catalog.PetsById.TryGetValue(row[m].Value, out def))
                            adoptable.Add(def.ToAdoptJObject());
                    }
                }
            }

            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "pets";
            resp["cmd"] = "adopt_list";
            resp["callId"] = webCallId;
            resp["success"] = true;
            resp["categories"] = categories;
            resp["adoptable"] = adoptable;
            PostToWeb(resp.ToString(Formatting.None));
        }

        /// <summary>
        /// 直答宠物库（替代 AS2 snapshot.petLib）。返回 { petLib:[{id,name,identifier,height,
        /// initialLevel,unlockLevel,unlockTask,unique,price,kprice,increasePrice,promotions}] }，按 id 升序。
        /// Web 用于进阶页查方案列表（getPetLibDef）。注：price 为 XML 基础价，会话内涨价以 AS2 为准（迁移方案 §9）。
        /// </summary>
        private void RespondPetLib(string webCallId)
        {
            PetCatalog catalog;
            string err;
            if (!EnsureCatalogLoaded(out catalog, out err))
            {
                RespondError(webCallId, "pet_lib", err);
                return;
            }

            var petLib = new JArray();
            List<PetDef> ordered = catalog.PetsOrderedById();
            for (int i = 0; i < ordered.Count; i++)
                petLib.Add(ordered[i].ToLibJObject());

            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "pets";
            resp["cmd"] = "pet_lib";
            resp["callId"] = webCallId;
            resp["success"] = true;
            resp["petLib"] = petLib;
            PostToWeb(resp.ToString(Formatting.None));
        }

        private bool EnsureCatalogLoaded(out PetCatalog catalog, out string error)
        {
            lock (_lock)
            {
                if (_catalog != null) { catalog = _catalog; error = null; return true; }
                if (_catalogError != null) { catalog = null; error = _catalogError; return false; }
                try
                {
                    _catalog = PetCatalogLoader.Load(_projectRoot);
                    catalog = _catalog;
                    error = null;
                    return true;
                }
                catch (Exception ex)
                {
                    _catalogError = "pet_catalog_unavailable";
                    LogManager.Log("[PetTask] pet catalog load FAILED: " + ex.Message);
                    catalog = null;
                    error = _catalogError;
                    return false;
                }
            }
        }

        private void RespondError(string webCallId, string cmd, string error)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "pets";
            resp["cmd"] = cmd;
            resp["callId"] = webCallId;
            resp["success"] = false;
            resp["error"] = error;
            PostToWeb(resp.ToString(Formatting.None));
        }

        private void PostToWeb(string json)
        {
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (_postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null)
                _postToWeb(json);
        }
    }
}
