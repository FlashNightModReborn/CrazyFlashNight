using System;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 平板 Web 面板 domain 的 WebView↔Flash callId 桥。
    ///
    /// Web 信封 {type:'panel', panel:'tablet', domain:'tablet', cmd, callId, panelInstanceId,
    /// payload:{v:1,...}} 经 WebOverlayForm 域路由进入 HandleWebRequest；命令映射后经
    /// PanelBridge.BuildFlashCommand 下发 AS2 gameCommands（tabletInfraSync /
    /// tabletInfraUpgrade / tabletOpenNpcShop / openRagTerminal），AS2 以 socket task
    /// "tablet_response" + callId 回执，HandleFlashResponse 完成 pending 并按
    /// panel_resp 回包 Web。
    ///
    /// 写权威：等级/材料/金币的裁决与回滚全部在 AS2 侧（引擎_lsy_基建系统.as，
    /// 与 基建内容整体.xml 同一事务原语）；本任务只做信封校验与在途超时。
    /// 升级属于真写：超时/DeliveryUnknown 按 unknown 处理，前端不得重放。
    /// </summary>
    public sealed class TabletTask
    {
        private const int DefaultTimeoutMs = 5000;
        private const int MaxInfraEntries = 128;
        private const int MaxInfraName = 80;
        private static readonly Regex ValidCallId =
            new Regex("^[A-Za-z0-9._-]{1,96}$", RegexOptions.Compiled);
        private static readonly Regex ValidPanelInstanceId = new Regex(
            "^[A-Za-z0-9._~-]{1,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private sealed class PendingRequest
        {
            public string WebCmd;
            public string OwnerPanel;
            public string OwnerPanelInstanceId;
            public bool IsWrite;
            public JObject NormalizedPayload;
        }

        private readonly PanelPendingCallTracker<PendingRequest> _pendingCalls;
        private readonly object _lock = new object();
        private Action<string> _postToWeb;
        private Action<Action> _invokeOnUI;
        private Func<string> _activePanelName;
        private bool _disposed;

        public TabletTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { return socket != null && socket.TrySend(payload); },
                DefaultTimeoutMs) { }

        public TabletTask(Func<bool> isClientReady, Func<string, bool> trySend, int timeoutMs)
        {
            _pendingCalls = new PanelPendingCallTracker<PendingRequest>(
                isClientReady,
                trySend,
                Math.Max(1, timeoutMs),
                HandlePendingEnded);
        }

        public void SetPostToWeb(Action<string> post) { _postToWeb = post; }
        public void SetInvoker(Action<Action> invoker) { _invokeOnUI = invoker; }
        public void SetActivePanelProvider(Func<string> provider) { _activePanelName = provider; }

        internal int PendingCount { get { return _pendingCalls.PendingCount; } }

        private static bool TryResolveCommand(string cmd, out string action, out bool isWrite)
        {
            isWrite = false;
            switch (cmd)
            {
                case "snapshot": action = "tabletInfraSync"; return true;
                case "upgrade": action = "tabletInfraUpgrade"; isWrite = true; return true;
                case "open_npc_shop": action = "tabletOpenNpcShop"; return true;
                case "open_ragchat": action = "openRagTerminal"; return true;
                default: action = null; return false;
            }
        }

        private static bool IsSafeName(string value)
        {
            if (string.IsNullOrEmpty(value) || value.Length > MaxInfraName
                || value != value.Trim()
                || string.Equals(value, "undefined", StringComparison.OrdinalIgnoreCase))
                return false;
            for (int i = 0; i < value.Length; i++)
                if (char.IsControl(value[i])) return false;
            return true;
        }

        private static bool TryNormalizePayload(string cmd, JObject payload, out JObject normalized)
        {
            normalized = new JObject { ["v"] = 1 };
            if (cmd == "snapshot" || cmd == "open_ragchat") return true;
            if (cmd == "open_npc_shop")
            {
                string shopId = payload.Value<string>("shopId");
                if (!IsSafeName(shopId)) return false;
                normalized["shopId"] = shopId;
                return true;
            }
            if (cmd == "upgrade")
            {
                string name = payload.Value<string>("name");
                if (!IsSafeName(name)) return false;
                normalized["name"] = name;
                return true;
            }
            return false;
        }

        /// <summary>Web→C# 面板域入口（domain='tablet'）。</summary>
        public void HandleWebRequest(JObject parsed)
        {
            string callId = parsed != null ? parsed.Value<string>("callId") : null;
            string cmd = parsed != null ? parsed.Value<string>("cmd") : null;
            string ownerPanel = parsed != null ? parsed.Value<string>("panel") : null;
            string ownerPanelInstanceId = parsed != null
                ? parsed.Value<string>("panelInstanceId") : null;
            if (!string.Equals(ownerPanel, "tablet", StringComparison.Ordinal)
                || string.IsNullOrEmpty(ownerPanelInstanceId)
                || !ValidPanelInstanceId.IsMatch(ownerPanelInstanceId)) return;
            if (string.IsNullOrEmpty(callId)) return;
            if (!ValidCallId.IsMatch(callId))
            {
                RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_call_id");
                return;
            }
            if (!string.Equals(parsed.Value<string>("domain"), "tablet", StringComparison.Ordinal))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_domain");
                return;
            }

            string action;
            bool isWrite;
            if (!TryResolveCommand(cmd, out action, out isWrite))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_cmd");
                return;
            }

            JObject payload = parsed["payload"] as JObject;
            if (payload == null || payload["v"] == null || payload["v"].Type != JTokenType.Integer)
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_payload");
                return;
            }
            if (payload.Value<int>("v") != 1)
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "unsupported_version");
                return;
            }
            JObject normalized;
            if (!TryNormalizePayload(cmd, payload, out normalized))
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "invalid_payload");
                return;
            }
            if (!_pendingCalls.IsReady())
            {
                RejectAndRemember(callId, cmd, ownerPanel, ownerPanelInstanceId, "disconnected");
                return;
            }

            int fid;
            lock (_lock)
            {
                if (_disposed) return;
                if (_pendingCalls.IsKnownWebCallId(callId)) return;
                // 写命令串行化：一次只允许一个在途升级；读命令不挡。
                if (isWrite && _pendingCalls.PendingCount != 0)
                {
                    if (!_pendingCalls.TryRememberRejected(callId)) return;
                    RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, "busy");
                    return;
                }
                if (!_pendingCalls.TryBegin(
                    callId,
                    new PendingRequest
                    {
                        WebCmd = cmd,
                        OwnerPanel = ownerPanel,
                        OwnerPanelInstanceId = ownerPanelInstanceId,
                        IsWrite = isWrite,
                        NormalizedPayload = (JObject)normalized.DeepClone()
                    },
                    out fid)) return;
            }

            JObject flash = PanelBridge.BuildFlashCommand(action, fid, normalized);
            string json = flash.ToString(Formatting.None);
            LogManager.Log(AuthorityLogFormatter.FormatFlashCommand("TabletTask", flash));
            _pendingCalls.Send(fid, json + "\0");
        }

        /// <summary>AS2→C# socket task "tablet_response"（callId 相关）。</summary>
        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            if (respond != null) respond(null);
            int fid = msg != null && msg["callId"] != null && msg["callId"].Type == JTokenType.Integer
                ? msg["callId"].Value<int>() : 0;
            if (fid <= 0) return;
            PanelPendingCall<PendingRequest> call;
            lock (_lock)
            {
                if (!_pendingCalls.TryComplete(fid, out call)) return;
            }
            PendingRequest entry = call.Context;
            JObject web = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "tablet",
                ["domain"] = "tablet",
                ["cmd"] = entry.WebCmd ?? "",
                ["callId"] = call.WebCallId,
                ["success"] = msg["success"] != null && msg["success"].Type == JTokenType.Boolean
                    ? msg["success"].Value<bool>()
                    : msg["ok"] != null && msg["ok"].Type == JTokenType.Boolean
                        && msg["ok"].Value<bool>()
            };
            if (msg["error"] != null && msg["error"].Type == JTokenType.String)
                web["error"] = msg["error"];
            if (msg["name"] != null && msg["name"].Type == JTokenType.String)
                web["name"] = msg["name"];
            if (msg["level"] != null && msg["level"].Type == JTokenType.Integer)
                web["level"] = msg["level"];
            JObject infra = ParseInfrastructure(msg["infrastructure"]);
            if (infra != null) web["infrastructure"] = infra;
            JObject assets = ParseAssets(msg["assets"]);
            if (assets != null) web["assets"] = assets;
            if (msg["ragAvailable"] != null && msg["ragAvailable"].Type == JTokenType.Boolean)
                web["ragAvailable"] = msg["ragAvailable"].Value<bool>();
            Post(web.ToString(Formatting.None));
        }

        /// <summary>assets 透传：money + materials/skills 名称→整数映射，供"所需/拥有"展示。</summary>
        private static JObject ParseAssets(JToken token)
        {
            JObject src = token as JObject;
            if (src == null) return null;
            JObject map = new JObject();
            if (src["money"] != null)
            {
                if (src["money"].Type != JTokenType.Integer) return null;
                long money = src["money"].Value<long>();
                if (money < 0 || money > 9007199254740991L) return null;
                map["money"] = money;
            }
            foreach (string key in new[] { "materials", "skills" })
            {
                JObject dict = src[key] as JObject;
                if (dict == null) continue;
                if (dict.Count > MaxInfraEntries) return null;
                JObject clean = new JObject();
                foreach (var p in dict.Properties())
                {
                    if (string.IsNullOrEmpty(p.Name) || p.Name.Length > MaxInfraName
                        || p.Name != p.Name.Trim()) return null;
                    if (p.Value.Type != JTokenType.Integer) return null;
                    long v = p.Value.Value<long>();
                    if (v < 0 || v > 9007199254740991L) return null;
                    clean[p.Name] = v;
                }
                map[key] = clean;
            }
            return map;
        }

        private static JObject ParseInfrastructure(JToken token)
        {
            JObject src = token as JObject;
            if (src == null) return null;
            if (src.Count > MaxInfraEntries) return null;
            JObject map = new JObject();
            foreach (var p in src.Properties())
            {
                if (string.IsNullOrEmpty(p.Name) || p.Name.Length > MaxInfraName
                    || p.Name != p.Name.Trim()) return null;
                if (p.Value.Type != JTokenType.Integer) return null;
                int level = p.Value.Value<int>();
                if (level < 0 || level > 99) return null;
                map[p.Name] = level;
            }
            return map;
        }

        private void HandlePendingEnded(
            PanelPendingCall<PendingRequest> call,
            PanelPendingCallEndReason reason)
        {
            PendingRequest entry = call.Context;
            // 写命令超时/DeliveryUnknown 不代表未执行：AS2 侧可能已提交。
            // 前端收到 unknown 后禁止重放，只能重新 snapshot 读真值。
            string error = reason == PanelPendingCallEndReason.Timeout ? "timeout"
                : reason == PanelPendingCallEndReason.DeliveryUnknown ? "delivery_unknown"
                : "cleared";
            JObject web = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "tablet",
                ["domain"] = "tablet",
                ["cmd"] = entry.WebCmd ?? "",
                ["callId"] = call.WebCallId,
                ["success"] = false,
                ["error"] = error,
                ["unknown"] = reason != PanelPendingCallEndReason.Cleared
            };
            Post(web.ToString(Formatting.None));
        }

        private void RejectAndRemember(string callId, string cmd,
            string ownerPanel, string ownerPanelInstanceId, string error)
        {
            if (callId != null && _pendingCalls.IsReady() && !_pendingCalls.TryRememberRejected(callId))
                return;
            RespondError(callId, cmd, ownerPanel, ownerPanelInstanceId, error);
        }

        private void RespondError(string callId, string cmd,
            string ownerPanel, string ownerPanelInstanceId, string error)
        {
            JObject web = new JObject
            {
                ["type"] = "panel_resp",
                ["panel"] = "tablet",
                ["domain"] = "tablet",
                ["cmd"] = cmd ?? "",
                ["callId"] = callId ?? "",
                ["success"] = false,
                ["error"] = error
            };
            Post(web.ToString(Formatting.None));
        }

        private void Post(string json)
        {
            // 陈旧响应不回灌已换主的 web 文档：只在 tablet 仍为活动面板时投递。
            string active = _activePanelName != null ? _activePanelName() : null;
            if (active != "tablet") return;
            if (_invokeOnUI != null)
                _invokeOnUI(delegate { if (!_disposed && _postToWeb != null) _postToWeb(json); });
            else if (_postToWeb != null) _postToWeb(json);
        }

        public void Dispose()
        {
            lock (_lock)
            {
                if (_disposed) return;
                _disposed = true;
                _pendingCalls.Dispose();
            }
        }
    }
}
