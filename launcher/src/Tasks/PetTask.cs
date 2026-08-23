using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
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
    ///   C# → Flash {task:"cmd", action:"petSnapshot/petAdopt/petEquipWeapon/...", callId:fid, ...}
    ///   Flash → C# {task:"pet_response", callId:fid, success, ...}
    ///   C# → Web   {type:"panel_resp", panel:"pets", cmd, callId, success, ...}
    ///
    /// 注意：close 不走本桥。Team 外层只发送携 active panelInstanceId 的 exact close，
    /// 并等待 Host 确认；旧 panel:"pets" close 必须 fail-closed，不能关闭 replacement。
    /// </summary>
    public sealed class PetTask : IDisposable
    {
        private sealed class PendingRequest
        {
            public string WebCmd;
            public string PanelInstanceId;
        }

        private const int DefaultTimeoutMs = 10000;
        private static readonly Regex ValidOpaque =
            new Regex("^[A-Za-z0-9._~-]{1,160}$", RegexOptions.Compiled);

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private readonly object _lock = new object();
        private string _panelInstanceId;
        private bool _disposed;

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
                delegate(string payload)
                {
                    return socket != null && socket.TrySend(payload);
                },
                projectRoot,
                DefaultTimeoutMs)
        {
        }

        public PetTask(Func<bool> isClientReady, Action<string> send)
            : this(isClientReady, send, null)
        {
        }

        public PetTask(Func<bool> isClientReady, Action<string> send, string projectRoot)
            : this(
                isClientReady,
                AdaptSend(send),
                projectRoot,
                DefaultTimeoutMs)
        {
        }

        internal PetTask(
            Func<bool> isClientReady,
            Func<string, bool> trySend,
            string projectRoot,
            int timeoutMs)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                trySend,
                timeoutMs,
                HandlePendingEnded);
            _projectRoot = projectRoot;
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }

        public string PanelInstanceId
        {
            get { lock (_lock) return _panelInstanceId; }
        }

        public bool BindPanelInstance(string panelInstanceId)
        {
            if (!IsOpaque(panelInstanceId)) return false;
            lock (_lock)
            {
                if (_disposed) return false;
                if (string.Equals(_panelInstanceId, panelInstanceId, StringComparison.Ordinal))
                    return true;
                _pendingCalls.Clear();
                _panelInstanceId = panelInstanceId;
                return true;
            }
        }

        public void ClearPanelInstance()
        {
            lock (_lock)
            {
                _pendingCalls.Clear();
                _panelInstanceId = null;
            }
        }

        public void Dispose()
        {
            lock (_lock)
            {
                if (_disposed) return;
                _disposed = true;
                _panelInstanceId = null;
                _pendingCalls.Dispose();
            }
        }

        /// <summary>
        /// WebView 侧面板请求入口（UI 线程调用）。
        /// </summary>
        public void HandleWebRequest(string cmd, JObject parsed)
        {
            LogManager.Log("[PetTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed != null ? parsed.Value<string>("callId") : null;
            string requestedInstance = parsed != null
                ? parsed.Value<string>("panelInstanceId") : null;
            if (!IsOpaque(webCallId))
            {
                LogManager.Log("[PetTask] webCallId is empty");
                return;
            }
            string boundInstance;
            lock (_lock) boundInstance = _disposed ? null : _panelInstanceId;
            if (!IsOpaque(boundInstance)
                || !string.Equals(boundInstance, requestedInstance, StringComparison.Ordinal))
            {
                RespondError(webCallId, cmd, requestedInstance, "panel_instance_expired");
                return;
            }

            // 商城目录/宠物库是 pets.xml 的静态投影：C# 直答，不经 Flash、不需 client ready。
            // adopt_list 顺带消除"进店早于 snapshot 返回时分类页签空白"竞态。projectRoot 缺省时退回 Flash 透传。
            if (_projectRoot != null)
            {
                if (cmd == "adopt_list") { RespondAdoptList(webCallId, requestedInstance, parsed); return; }
                if (cmd == "pet_lib") { RespondPetLib(webCallId, requestedInstance); return; }
            }

            if (!_pendingCalls.IsReady())
            {
                RespondError(webCallId, cmd, requestedInstance, "disconnected");
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
                case "world_adopt":
                    // 世界内招募（NPC 处确认）：转发 petWorldAdopt；AS2 用 _pendingHireNpc 读权威。
                    // 回 hired:true（前端关面板）。见 设计 §3.3。
                    action = "petWorldAdopt";
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
                case "weapon_tooltip":
                    action = "petWeaponTooltip";
                    break;
                case "restore_stamina":
                    action = "petRestoreStamina";
                    break;
                case "equip_weapon":
                    action = "petEquipWeapon";
                    break;
                case "withdraw_weapon":
                    action = "petWithdrawWeapon";
                    break;
                case "level_up":
                    action = "petLevelUp";
                    break;
                case "delete":
                    action = "petDelete";
                    break;
                default:
                    RespondError(webCallId, cmd, requestedInstance, "unsupported_cmd");
                    return;
            }

            int fid;
            string flashJson;
            bool ownerExpired;
            lock (_lock)
            {
                ownerExpired = _disposed
                    || !string.Equals(
                        _panelInstanceId,
                        requestedInstance,
                        StringComparison.Ordinal);
                if (ownerExpired)
                {
                    fid = 0;
                    flashJson = null;
                }
                else if (!_pendingCalls.TryBegin(
                    webCallId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        PanelInstanceId = requestedInstance
                    },
                    out fid)) return;
                else
                {
                    // 信封构造 + 安全参数透传统一走 PanelBridge（含 action/task
                    // 保留键守卫，杜绝各桥漏抄）。登记和本地发送都在 owner 锁内，
                    // replacement 不能夹在二者之间把旧实例写入送往 Flash。
                    JObject flashMsg = PanelBridge.BuildFlashCommand(action, fid, parsed);
                    flashJson = flashMsg.ToString(Formatting.None);
                    LogManager.Log("[PetTask] -> Flash: " + flashJson);
                    _pendingCalls.Send(fid, flashJson + "\0");
                }
            }
            if (ownerExpired)
                RespondError(webCallId, cmd, requestedInstance, "panel_instance_expired");
        }

        /// <summary>
        /// Flash 侧回包入口（MessageRouter 在 XmlSocket 线程调用）。
        /// </summary>
        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[PetTask] <- Flash response received");
            int fid = msg.Value<int>("callId");
            PanelPendingCall<PendingRequest> pendingCall;
            if (!_pendingCalls.TryComplete(fid, out pendingCall))
            {
                if (respond != null) respond(null);
                return;
            }
            PendingRequest entry = pendingCall.Context;

            msg.Remove("task");
            msg["type"] = "panel_resp";
            msg["panel"] = "pets";
            msg["cmd"] = entry.WebCmd;
            msg["callId"] = pendingCall.WebCallId;
            msg["panelInstanceId"] = entry.PanelInstanceId;

            string json = msg.ToString(Formatting.None);
            PostToWeb(json);
            if (respond != null) respond(null);
        }

        public void ClearPending()
        {
            lock (_lock) _pendingCalls.Clear();
        }

        internal int PendingCountForTest
        {
            get { return _pendingCalls.PendingCount; }
        }

        // ── 商城目录 C# 直答（pets.xml 静态投影，等价于 AS2 handleAdoptList + snapshot.categories）──

        /// <summary>
        /// 直答可领养列表。兼容请求返回全量 categories:[{name}]；带 rosterType 时返回
        /// 非空 categories:[{index,name,count}] 与 selectedCategoryIndex。categoryIndex 使用原始索引。
        /// </summary>
        private void RespondAdoptList(
            string webCallId, string panelInstanceId, JObject parsed)
        {
            PetCatalog catalog;
            string err;
            if (!EnsureCatalogLoaded(out catalog, out err))
            {
                RespondError(webCallId, "adopt_list", panelInstanceId, err);
                return;
            }

            int categoryIndex = -1;
            string rosterType = parsed.Value<string>("rosterType");
            bool filteredByRoster = !string.IsNullOrEmpty(rosterType);
            if (filteredByRoster && !PetCatalogLoader.IsValidRosterType(rosterType))
            {
                RespondError(webCallId, "adopt_list", panelInstanceId, "invalid_roster_type");
                return;
            }
            JToken ciTok = parsed["categoryIndex"];
            if (ciTok != null)
            {
                int ci;
                if (int.TryParse(ciTok.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out ci))
                    categoryIndex = ci;
            }

            var categories = new JArray();
            var adoptable = new JArray();
            var availableCategoryIndexes = new List<int>();
            if (filteredByRoster)
            {
                for (int c = 0; c < catalog.Categories.Count; c++)
                {
                    int count = CountCategoryPets(catalog, catalog.Categories[c], rosterType);
                    if (count <= 0) continue;
                    availableCategoryIndexes.Add(c);
                    var catObj = new JObject();
                    catObj["index"] = c;
                    catObj["name"] = catalog.Categories[c].Name;
                    catObj["count"] = count;
                    categories.Add(catObj);
                }
                if (!availableCategoryIndexes.Contains(categoryIndex))
                    categoryIndex = availableCategoryIndexes.Count > 0 ? availableCategoryIndexes[0] : -1;
            }

            for (int c = 0; c < catalog.Categories.Count; c++)
            {
                PetCatalog.PetCategory cat = catalog.Categories[c];
                if (!filteredByRoster)
                {
                    var catObj = new JObject();
                    catObj["name"] = cat.Name;
                    categories.Add(catObj);
                }

                if (categoryIndex >= 0 && c != categoryIndex) continue;
                for (int r = 0; r < cat.Rows.Count; r++)
                {
                    List<int?> row = cat.Rows[r];
                    for (int m = 0; m < row.Count; m++)
                    {
                        if (!row[m].HasValue) continue;
                        PetDef def;
                        if (catalog.PetsById.TryGetValue(row[m].Value, out def)
                            && (!filteredByRoster || def.RosterType == rosterType))
                            adoptable.Add(def.ToAdoptJObject());
                    }
                }
            }

            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "pets";
            resp["cmd"] = "adopt_list";
            resp["callId"] = webCallId;
            resp["panelInstanceId"] = panelInstanceId;
            resp["success"] = true;
            resp["categories"] = categories;
            resp["adoptable"] = adoptable;
            if (filteredByRoster) resp["selectedCategoryIndex"] = categoryIndex;
            PostToWeb(resp.ToString(Formatting.None));
        }

        private static int CountCategoryPets(PetCatalog catalog, PetCatalog.PetCategory category, string rosterType)
        {
            int count = 0;
            for (int r = 0; r < category.Rows.Count; r++)
            {
                List<int?> row = category.Rows[r];
                for (int m = 0; m < row.Count; m++)
                {
                    PetDef def;
                    if (row[m].HasValue && catalog.PetsById.TryGetValue(row[m].Value, out def)
                        && def.RosterType == rosterType)
                        count++;
                }
            }
            return count;
        }

        /// <summary>
        /// 直答宠物库（替代 AS2 snapshot.petLib）。返回 { petLib:[{id,name,identifier,height,
        /// initialLevel,unlockLevel,unlockTask,unique,price,kprice,increasePrice,promotions}] }，按 id 升序。
        /// Web 用于进阶页查方案列表（getPetLibDef）。注：price 为 XML 基础价，会话内涨价以 AS2 为准（迁移方案 §9）。
        /// </summary>
        private void RespondPetLib(string webCallId, string panelInstanceId)
        {
            PetCatalog catalog;
            string err;
            if (!EnsureCatalogLoaded(out catalog, out err))
            {
                RespondError(webCallId, "pet_lib", panelInstanceId, err);
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
            resp["panelInstanceId"] = panelInstanceId;
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

        private void RespondError(
            string webCallId, string cmd, string panelInstanceId, string error)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "pets";
            resp["cmd"] = cmd;
            resp["callId"] = webCallId;
            resp["panelInstanceId"] = panelInstanceId ?? "";
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

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> pendingCall,
            PanelPendingCallEndReason reason)
        {
            if (reason == PanelPendingCallEndReason.Cleared) return;
            PendingRequest entry = pendingCall.Context;
            RespondError(
                pendingCall.WebCallId,
                entry.WebCmd,
                entry.PanelInstanceId,
                reason == PanelPendingCallEndReason.Timeout
                    ? "timeout"
                    : "delivery_unknown");
        }

        private static Func<string, bool> AdaptSend(Action<string> send)
        {
            return delegate(string payload)
            {
                if (send == null) return false;
                send(payload);
                return true;
            };
        }

        private static bool IsOpaque(string value)
        {
            return !string.IsNullOrEmpty(value) && ValidOpaque.IsMatch(value);
        }
    }
}
