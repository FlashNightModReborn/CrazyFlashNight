using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;
using CF7Launcher.Guardian.Hud;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// native_interaction task：NPC 菜单 + 文档 tooltip 的共享宿主接线。
    ///
    /// 线形：AS2 ServerManager.sendTaskToNode("native_interaction", payload, null)
    ///   → {"task":"native_interaction","payload":{kind,op,version,requestId,sceneId,x,y,...}}。
    /// 回包：{"task":"cmd","action":"nativeInteractionAction"|"nativeInteractionCancel",...}\0
    ///   经 XmlSocketServer.TrySend（IsClientReady 门控，best-effort 本地写入语义）。
    ///
    /// 身份规则（COMMON.md v1 + INTEGRATION.md §2）：
    /// - requestId 精确形 ni:&lt;正整数&gt;，菜单/注释共用同一条全局递增序号；仅 show 参与
    ///   序号前沿比较——seq 小于已见最大值的 show 按迟到丢弃（不复活旧场景/旧实例）；
    ///   seq 相等 = 同请求重复 show（刷新语义放行，交给 widget 自身 revision 规则）。
    /// - hide 只按 kind+requestId(+sceneId) 精确匹配当前实例；不参与序号门控——
    ///   另一种浮层的更新 show 不得拒掉本实例的匹配 hide。
    /// - show 的 sceneId 与最近已见 sceneId 不同 = 场景滚转：旧场景 UI 全部静默清除
    ///   （AS2 已在切换时先行 hide；这里是丢失保险的兜底，不发 cancel——场景归 AS2 权威）。
    /// - 断线：HandleTransportDisconnected 全清 + 序号/场景归零；重连 ni:&lt;n&gt; 重新计数。
    ///
    /// 关闭来源：AS2 hide / 行选择（ActionChosen）/ 外部点击（NotifyPhysicalButtonDown，
    /// 由 WebOverlayForm 的 WH_MOUSE_LL 观察喂入）/ 压隐（panel_suspend、owner_hidden，
    /// 经 widget 的 INativeHudSuppressionAware）/ pinned ×（tooltip DismissRequested）。
    /// 宿主发起的关闭统一走 SessionDismissed → nativeInteractionCancel；AS2 发起的 hide 不回包。
    ///
    /// 线程：Handle 在 socket worker 线程执行，所有 widget 操作经 _uiDispatch 切到 UI 线程。
    /// </summary>
    public class NativeInteractionTask
    {
        public const string TaskKey = "native_interaction";
        private const int ProtocolVersion = 1;
        private const int MaxActions = 32;
        private const int MaxLabelLength = 80;
        private const int MaxTitleLength = 80;

        private readonly XmlSocketServer _socket;
        private readonly NpcMenuWidget _menu;
        private readonly INativeInteractionTooltipSurface _tooltip;
        private readonly Action<Action> _uiDispatch;
        private readonly TooltipInspectionController _inspection;
        private readonly object _gate = new object();

        private string _latestSceneId;
        private long _maxSeenSeq;
        private bool _maxSeenSeqValid;

        /// <summary>测试钩子：拦截 TrySend 的 payload（含 \0）。非 null 时完全接管发送。</summary>
        internal Func<string, bool> SendPayloadOverride;

        /// <summary>测试可读：本 task 驱动（或注入）的检视控制器。</summary>
        internal TooltipInspectionController Inspection { get { return _inspection; } }

        internal NativeInteractionTask(
            XmlSocketServer socket,
            NpcMenuWidget menu,
            INativeInteractionTooltipSurface tooltip,
            Action<Action> uiDispatch)
            : this(socket, menu, tooltip, uiDispatch, null)
        {
        }

        /// <summary>inspection 注入点：测试给假时钟/假指针/手动泵；生产传 null 用默认。</summary>
        internal NativeInteractionTask(
            XmlSocketServer socket,
            NpcMenuWidget menu,
            INativeInteractionTooltipSurface tooltip,
            Action<Action> uiDispatch,
            TooltipInspectionController inspection)
        {
            if (menu == null) throw new ArgumentNullException("menu");
            if (uiDispatch == null) throw new ArgumentNullException("uiDispatch");
            _socket = socket;
            _menu = menu;
            _tooltip = tooltip;
            _uiDispatch = uiDispatch;

            _menu.ActionChosen = OnMenuActionChosen;
            _menu.SessionDismissed = OnSessionDismissed;
            if (_tooltip != null)
            {
                _inspection = inspection ?? new TooltipInspectionController(_tooltip);
                NativeTooltipSurfaceAdapter adapter = _tooltip as NativeTooltipSurfaceAdapter;
                NativeInteractionWheelRoute.AttachInspection(
                    _inspection, adapter != null ? adapter.Widget : null);
                _tooltip.DismissRequested += delegate(string requestId)
                {
                    OnTooltipDismissRequested(requestId);
                };
            }
        }

        // ── 任务入口（socket worker 线程） ────────────────────────────

        public string Handle(JObject message)
        {
            JObject payload = message == null ? null : message["payload"] as JObject;
            if (payload == null)
            {
                LogManager.Log("[NativeInteraction] drop: payload missing or not object");
                return null;
            }
            JObject captured = payload;
            try
            {
                _uiDispatch(delegate { HandleOnUi(captured); });
            }
            catch (Exception ex)
            {
                LogManager.Log("[NativeInteraction] ui dispatch failed: " + ex.Message);
            }
            return null; // fire-and-forget：协议无 callId，不回包
        }

        /// <summary>socket OnClientDisconnected：全清（不发 cancel——通道已死），身份状态归零。</summary>
        public void HandleTransportDisconnected()
        {
            try { _uiDispatch(ResetAll); }
            catch { ResetAll(); }
        }

        /// <summary>
        /// WH_MOUSE_LL 物理按下转发（UI 线程，同步 O(1)）：菜单外按下 → 关闭 + cancel；
        /// pinned tooltip 外点（浮层/owner 区外）→ 终结会话 + cancel（web outsideClick 等价）。
        /// </summary>
        public void NotifyPhysicalButtonDown(int screenX, int screenY, int message)
        {
            if (IsExternalPress(_menu.Visible, _menu.ScreenBounds, screenX, screenY))
                _menu.DismissInteractive("outside_click");
            if (_inspection != null && _tooltip != null)
            {
                // dismiss 前快照 sceneId——Hide 之后 CurrentSceneId 已清空
                string sceneId = _tooltip.CurrentSceneId;
                string rid = null;
                try { rid = _inspection.TryDismissPinnedAt(screenX, screenY); }
                catch (Exception ex) { LogManager.Log("[NativeInteraction] pinned outside dismiss throw: " + ex.Message); }
                if (rid != null) SendCancel(rid, sceneId);
            }
        }

        /// <summary>外部按下判定（纯函数，测试钩子）：菜单可见 且 边界非空 且 点在界外。</summary>
        internal static bool IsExternalPress(bool menuVisible, System.Drawing.Rectangle menuBounds,
            int screenX, int screenY)
        {
            return menuVisible && menuBounds.Width > 0 && !menuBounds.Contains(screenX, screenY);
        }

        /// <summary>Web 面板打开压隐（PanelHostController interaction companion）：双 widget 终结会话。</summary>
        internal void OnPanelSuspending()
        {
            _menu.DismissInteractive("panel_suspend");
            if (_tooltip != null)
            {
                try { _tooltip.OnHostSuppressed("panel_suspend"); }
                catch (Exception ex) { LogManager.Log("[NativeInteraction] tooltip suppress throw: " + ex.Message); }
                SyncInspection();
            }
        }

        // ── ESC 关闭（KeyboardHook 探针 + GuardianForm 派发） ─────────

        /// <summary>
        /// ESC 拦截探针——在 KeyboardHook 专用钩子线程上同步调用，必须 O(1) 不抛。
        /// true = 存在可交互会话（菜单可见 / pinned tooltip 存活 / dense 处于 inspect），
        /// 该次 ESC 应被吞掉并转交 NotifyInteractionEscape。scan/pending 与 simple 不算——
        /// 瞬态注释不吃 ESC（web：只有 inspect/pinned 消费 ESC）。
        /// </summary>
        public bool IsInteractionEscapable()
        {
            if (_menu.Visible) return true;
            if (_tooltip != null && _tooltip.HasPinnedSession) return true;
            TooltipInspectionController c = _inspection;
            return c != null && c.EscConsumable;
        }

        /// <summary>
        /// 物理 ESC 到达（UI 线程）：菜单优先，其次 pinned tooltip（均回报 cancel），
        /// 再次 dense inspect → 退 scan（web resetInspectionProjection：不 hide、不发 cancel）。
        /// </summary>
        internal void NotifyInteractionEscape()
        {
            if (_menu.Visible)
            {
                _menu.DismissInteractive("escape");
                return;
            }
            if (_tooltip != null && _tooltip.HasPinnedSession)
            {
                string requestId = _tooltip.CurrentRequestId;
                string sceneId = _tooltip.CurrentSceneId;
                try { _tooltip.Reset(); }
                catch (Exception ex) { LogManager.Log("[NativeInteraction] tooltip esc reset throw: " + ex.Message); }
                SyncInspection();
                SendCancel(requestId, sceneId);
                return;
            }
            TooltipInspectionController c = _inspection;
            if (c != null)
            {
                try { c.ExitInspection(); }
                catch (Exception ex) { LogManager.Log("[NativeInteraction] esc exit-inspect throw: " + ex.Message); }
            }
        }

        /// <summary>
        /// tooltip 交互关闭（pinned × 点击 / 压隐上报）：先快照旧 requestId/sceneId，
        /// 按 requestId 精确终结本地实例（不清后来者、不触发本事件重入），
        /// 再按旧身份发一次 nativeInteractionCancel——AS2 handleCancel 不回 hide，
        /// 本地必须自己关闭浮层。与 NotifyInteractionEscape 同序。
        /// 迟到防护：requestId 不是当前实例 → 丢弃（不重复发 cancel、不动新实例）。
        /// </summary>
        private void OnTooltipDismissRequested(string requestId)
        {
            if (string.IsNullOrEmpty(requestId) || _tooltip == null) return;
            if (!string.Equals(requestId, _tooltip.CurrentRequestId, StringComparison.Ordinal))
            {
                LogManager.Log("[NativeInteraction] drop stale dismiss requestId=" + requestId);
                return;
            }
            string sceneId = _tooltip.CurrentSceneId;
            try { _tooltip.Hide(requestId); }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] tooltip dismiss hide throw: " + ex.Message); }
            SyncInspection();
            SendCancel(requestId, sceneId);
        }

        // ── UI 线程处理 ─────────────────────────────────────────────

        private void HandleOnUi(JObject payload)
        {
            // BeginInvoke 内的异常不会被外层 dispatch try 捕获——本方法是 UI 处理边界，
            // 所有字段走类型安全读取（JObject.Value<T> 遇对象/坏字符串会抛）。
            try
            {
                int? version = ReadIntField(payload, "version");
                string kind = ReadStringField(payload, "kind");
                string op = ReadStringField(payload, "op");
                string requestId = ReadStringField(payload, "requestId");
                string sceneId = ReadStringField(payload, "sceneId");
                if (version != ProtocolVersion
                    || string.IsNullOrEmpty(requestId)
                    || string.IsNullOrEmpty(sceneId)
                    || (kind != "menu" && kind != "tooltip")
                    || (op != "show" && op != "hide"))
                {
                    LogManager.Log("[NativeInteraction] drop malformed envelope kind=" + (kind ?? "?")
                        + " op=" + (op ?? "?") + " version=" + (version.HasValue ? version.Value.ToString() : "?"));
                    return;
                }

                if (op == "show") HandleShow(payload, kind, requestId, sceneId);
                else HandleHide(kind, requestId, sceneId);
            }
            catch (Exception ex)
            {
                LogManager.Log("[NativeInteraction] HandleOnUi throw: " + ex.Message);
            }
        }

        private void HandleShow(JObject payload, string kind, string requestId, string sceneId)
        {
            long seq;
            if (!TryParseRequestSeq(requestId, out seq))
            {
                // 身份契约：show 只认精确 ni:<正整数>；解析失败即拒（INTEGRATION §host-16）。
                LogManager.Log("[NativeInteraction] drop show: requestId not ni:<positive> -> "
                    + requestId);
                return;
            }

            bool sceneRolled = false;
            lock (_gate)
            {
                if (_maxSeenSeqValid)
                {
                    // 全局序号前沿：比已见最大 seq 更旧的 show 是迟到消息，丢弃防旧实例复活。
                    if (seq < _maxSeenSeq)
                    {
                        LogManager.Log("[NativeInteraction] drop stale show requestId=" + requestId
                            + " maxSeq=" + _maxSeenSeq);
                        return;
                    }
                    // ni:<n> 全局唯一：seq==max ⇒ 同一 requestId。仅当其在该 kind 下仍存活
                    // 且同场景时按刷新放行；否则是"已消费请求复活/换 kind/换 scene"，拒绝。
                    if (seq == _maxSeenSeq)
                    {
                        string activeRid;
                        string activeScene;
                        if (kind == "menu")
                        {
                            activeRid = _menu.CurrentRequestId;
                            activeScene = _menu.CurrentSceneId;
                        }
                        else
                        {
                            activeRid = _tooltip != null ? _tooltip.CurrentRequestId : null;
                            activeScene = _tooltip != null ? _tooltip.CurrentSceneId : null;
                        }
                        if (!string.Equals(activeRid, requestId, StringComparison.Ordinal)
                            || !string.Equals(activeScene, sceneId, StringComparison.Ordinal))
                        {
                            LogManager.Log("[NativeInteraction] drop consumed-request show requestId="
                                + requestId + " kind=" + kind);
                            return;
                        }
                    }
                }
                if (seq > _maxSeenSeq) _maxSeenSeq = seq;
                _maxSeenSeqValid = true;
                if (!string.Equals(sceneId, _latestSceneId, StringComparison.Ordinal))
                {
                    _latestSceneId = sceneId;
                    sceneRolled = true;
                }
            }

            if (sceneRolled)
            {
                // 新场景确立前清掉旧场景残留；AS2 已按序 hide，此处是丢失保险（静默，无 cancel）。
                // 只在确有实例且场景不同才清——空 tooltip/菜单不得吃无谓 Reset。
                string menuScene = _menu.CurrentSceneId;
                if (menuScene != null
                    && !string.Equals(menuScene, sceneId, StringComparison.Ordinal))
                    _menu.ForceClear();
                if (_tooltip != null)
                {
                    string tipScene = _tooltip.CurrentSceneId;
                    if (tipScene != null
                        && !string.Equals(tipScene, sceneId, StringComparison.Ordinal))
                    {
                        try { _tooltip.Reset(); }
                        catch (Exception ex) { LogManager.Log("[NativeInteraction] tooltip reset throw: " + ex.Message); }
                    }
                }
            }

            if (kind == "menu") ShowMenu(payload, requestId, sceneId);
            else if (_tooltip != null)
            {
                // pinned 存活期间普通（非 pinned）show 一律拒绝——web `_pinned` 守卫
                // （悬停/焦点不得顶替显式 inspector，只有新 pinned show 可替换）。
                if (_tooltip.HasPinnedSession && !TooltipShowIsPinned(payload))
                {
                    LogManager.Log("[NativeInteraction] drop non-pinned show under pinned requestId="
                        + requestId);
                    return;
                }
                try { _tooltip.Show(payload); }
                catch (Exception ex) { LogManager.Log("[NativeInteraction] tooltip show throw: " + ex.Message); }
                SyncInspection();
            }
        }

        /// <summary>payload.document.profile == "pinned"？缺省/坏值按 simple 处理（web normalizeProfile 同义）。</summary>
        private static bool TooltipShowIsPinned(JObject payload)
        {
            JObject doc = payload == null ? null : payload["document"] as JObject;
            string profile = doc == null ? null : ReadStringField(doc, "profile");
            return string.Equals(profile, "pinned", StringComparison.OrdinalIgnoreCase);
        }

        private void HandleHide(string kind, string requestId, string sceneId)
        {
            if (kind == "menu")
            {
                _menu.HideSession(requestId, sceneId);
            }
            else if (_tooltip != null)
            {
                // simple 复合悬停：owner leave 的 hide 到来时，若指针在浮层内/过桥窗内进入
                // 则保持展示（控制器接管，稍后自行 Hide）；dense/pinned/身份不符立即生效。
                bool deferred = false;
                if (_inspection != null)
                {
                    try { deferred = _inspection.TryDeferHide(requestId); }
                    catch (Exception ex) { LogManager.Log("[NativeInteraction] defer hide throw: " + ex.Message); }
                }
                if (!deferred)
                {
                    try { _tooltip.Hide(requestId); }
                    catch (Exception ex) { LogManager.Log("[NativeInteraction] tooltip hide throw: " + ex.Message); }
                }
                SyncInspection();
            }
        }

        private void SyncInspection()
        {
            TooltipInspectionController c = _inspection;
            if (c == null) return;
            try { c.Sync(); }
            catch (Exception ex) { LogManager.Log("[NativeInteraction] inspection sync throw: " + ex.Message); }
        }

        private void ShowMenu(JObject payload, string requestId, string sceneId)
        {
            NpcMenuWidget.MenuSession session = new NpcMenuWidget.MenuSession();
            session.RequestId = requestId;
            session.SceneId = sceneId;
            session.TargetName = Truncate(ReadStringField(payload, "targetName"), MaxTitleLength);
            session.Title = Truncate(ReadStringField(payload, "title"), MaxTitleLength);
            session.AnchorFx = (float)ReadNumberField(payload, "x");
            session.AnchorFy = (float)ReadNumberField(payload, "y");
            session.Entries = ParseEntries(payload["actions"] as JArray);
            _menu.ShowSession(session);
        }

        private static NpcMenuWidget.Entry[] ParseEntries(JArray actions)
        {
            if (actions == null || actions.Count == 0)
                return new NpcMenuWidget.Entry[0];
            List<NpcMenuWidget.Entry> list = new List<NpcMenuWidget.Entry>(
                Math.Min(actions.Count, MaxActions));
            for (int i = 0; i < actions.Count && list.Count < MaxActions; i++)
            {
                JObject a = actions[i] as JObject;
                if (a == null) continue;
                string id = ReadStringField(a, "id");
                if (string.IsNullOrEmpty(id)) continue;
                string label = ReadStringField(a, "label");
                if (string.IsNullOrEmpty(label)) label = id;
                NpcMenuWidget.Entry e = new NpcMenuWidget.Entry();
                e.Id = id;
                e.Label = Truncate(label, MaxLabelLength);
                e.Enabled = ReadBoolField(a, "enabled", true);
                list.Add(e);
            }
            return list.ToArray();
        }

        // 类型安全字段读取：JToken 类型不符一律回落，不抛。
        private static string ReadStringField(JObject o, string name)
        {
            JToken t = o == null ? null : o[name];
            return t != null && t.Type == JTokenType.String ? t.Value<string>() : null;
        }

        private static int? ReadIntField(JObject o, string name)
        {
            JToken t = o == null ? null : o[name];
            return t != null && t.Type == JTokenType.Integer ? (int?)t.Value<int>() : null;
        }

        private static double ReadNumberField(JObject o, string name)
        {
            JToken t = o == null ? null : o[name];
            if (t == null) return 0.0;
            if (t.Type == JTokenType.Float || t.Type == JTokenType.Integer)
                return t.Value<double>();
            return 0.0;
        }

        private static bool ReadBoolField(JObject o, string name, bool fallback)
        {
            JToken t = o == null ? null : o[name];
            return t != null && t.Type == JTokenType.Boolean ? t.Value<bool>() : fallback;
        }

        private void ResetAll()
        {
            lock (_gate)
            {
                _latestSceneId = null;
                _maxSeenSeq = 0;
                _maxSeenSeqValid = false;
            }
            _menu.ForceClear();
            if (_tooltip != null)
            {
                try { _tooltip.Reset(); }
                catch (Exception ex) { LogManager.Log("[NativeInteraction] tooltip reset throw: " + ex.Message); }
                SyncInspection();
            }
        }

        // ── 回包（C# → AS2） ─────────────────────────────────────────

        private void OnMenuActionChosen(string requestId, string sceneId, string actionId)
        {
            if (string.IsNullOrEmpty(requestId) || string.IsNullOrEmpty(actionId)) return;
            JObject cmd = new JObject();
            cmd["task"] = "cmd";
            cmd["action"] = "nativeInteractionAction";
            cmd["version"] = ProtocolVersion;
            cmd["requestId"] = requestId;
            cmd["sceneId"] = sceneId;
            cmd["actionId"] = actionId;
            TrySendPayload(cmd.ToString(Newtonsoft.Json.Formatting.None) + "\0");
        }

        private void OnSessionDismissed(string requestId, string sceneId, string reason)
        {
            SendCancel(requestId, sceneId);
        }

        private void SendCancel(string requestId, string sceneId)
        {
            if (string.IsNullOrEmpty(requestId)) return;
            JObject cmd = new JObject();
            cmd["task"] = "cmd";
            cmd["action"] = "nativeInteractionCancel";
            cmd["version"] = ProtocolVersion;
            cmd["requestId"] = requestId;
            cmd["sceneId"] = sceneId;
            TrySendPayload(cmd.ToString(Formatting.None) + "\0");
        }

        private bool TrySendPayload(string payload)
        {
            Func<string, bool> over = SendPayloadOverride;
            if (over != null)
            {
                try { return over(payload); }
                catch (Exception ex) { LogManager.Log("[NativeInteraction] send override throw: " + ex.Message); return false; }
            }
            if (_socket == null || !_socket.IsClientReady) return false;
            return _socket.TrySend(payload);
        }

        /// <summary>requestId 精确形 ni:&lt;正整数&gt; → 全局序号。无法解析返回 false（不参与序号门控）。</summary>
        internal static bool TryParseRequestSeq(string requestId, out long seq)
        {
            seq = 0;
            if (string.IsNullOrEmpty(requestId) || requestId.Length <= 3) return false;
            if (requestId[0] != 'n' || requestId[1] != 'i' || requestId[2] != ':') return false;
            long v = 0;
            for (int i = 3; i < requestId.Length; i++)
            {
                char c = requestId[i];
                if (c < '0' || c > '9') return false;
                if (v > (Int64.MaxValue - (c - '0')) / 10) return false;
                v = v * 10 + (c - '0');
            }
            if (v <= 0) return false;
            seq = v;
            return true;
        }

        private static string Truncate(string s, int max)
        {
            if (s == null) return null;
            return s.Length <= max ? s : s.Substring(0, max);
        }
    }
}
