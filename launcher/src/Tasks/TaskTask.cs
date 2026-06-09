using System;
using System.Collections.Generic;
using System.Threading;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// 任务面板 WebView ↔ Flash 双层 callId 桥接。
    /// 与 PetTask / MercTask 同构：
    ///   Web → C#   {type:"panel", panel:"tasks", cmd, callId, ...}
    ///   C# → Flash {task:"cmd", action:"taskSnapshot/taskDetail/...", callId:fid, ...}
    ///   Flash → C# {task:"task_response", callId:fid, success, ...}
    ///   C# → Web   {type:"panel_resp", panel:"tasks", cmd, callId, success, ...}
    ///
    /// 注意：close 不走本桥。Web 关闭面板时 WebOverlayForm.HandlePanelMessage 直接
    /// 切 _activePanel = null + ClosePanel()。
    /// </summary>
    public sealed class TaskTask : IDisposable
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

        public TaskTask(XmlSocketServer socket)
            : this(
                delegate { return socket != null && socket.IsClientReady; },
                delegate(string payload) { if (socket != null) socket.Send(payload); })
        {
        }

        public TaskTask(Func<bool> isClientReady, Action<string> send)
        {
            _isClientReady = isClientReady ?? delegate { return false; };
            _send = send ?? delegate { };
            _pending = new Dictionary<int, PendingRequest>();
            _timers = new Dictionary<int, Timer>();
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
            LogManager.Log("[TaskTask] HandleWebRequest: cmd=" + cmd);
            string webCallId = parsed.Value<string>("callId");
            if (string.IsNullOrEmpty(webCallId))
            {
                LogManager.Log("[TaskTask] webCallId is empty");
                return;
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
                    action = "taskSnapshot";
                    break;
                case "detail":
                    action = "taskDetail";
                    break;
                case "tooltip":
                    // 物品注释（name-keyed）：转发 itemName 给 AS2 tasksTooltip，回包含 introHTML/descHTML/itemType
                    action = "tasksTooltip";
                    break;
                case "finishTask":
                    // 交付任务（写操作）：转发 taskId 给 AS2 taskFinish；AS2 端按 taskId 解析当前
                    // index 并以 taskCompleteCheck 二次门控，回包含刷新后的 tasks 概要（splice 后 index 已偏移）
                    action = "taskFinish";
                    break;
                case "deleteTask":
                    // 放弃任务（写操作）：转发 taskId 给 AS2 taskDelete；主线任务由 AS2 拒绝，
                    // 回包含刷新后的 tasks 概要
                    action = "taskDelete";
                    break;
                case "navigateFinish":
                    // 前往交付（便利增强）：转发 taskId 给 AS2 taskNavigateFinish；AS2 复用地图
                    // NPC→hotspot 跳转，成功回 closePanel:true（前端关面板让场景淡出跳转）
                    action = "taskNavigateFinish";
                    break;
                case "treeState":
                    // 事件日志/任务树 动态进度小叠加（WS6，只读）：AS2 回链进度+已完成 id 集+进行中 id；
                    // 静态任务目录由 build 派生 task-catalog.json 供 web 直读，不经此桥
                    action = "taskTreeState";
                    break;
                case "replayDialogue":
                    // 剧情对话回放（WS6，命令回传）：转发 taskId/which 给 AS2 taskReplayDialogue；
                    // AS2 按防剧透门控（仅已接取/已完成才回，否则 locked）回传单任务对话文本行
                    // lines:[{speaker,sub,text}]，web 内联渲染、不关面板（轻量文本态）
                    action = "taskReplayDialogue";
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
            LogManager.Log("[TaskTask] -> Flash: " + flashJson);
            _send(flashJson + "\0");
        }

        /// <summary>
        /// Flash 侧回包入口（MessageRouter 在 XmlSocket 线程调用）。
        /// </summary>
        public void HandleFlashResponse(JObject msg, Action<string> respond)
        {
            LogManager.Log("[TaskTask] <- Flash response received");
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
            msg["panel"] = "tasks";
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

        private void RespondError(string webCallId, string cmd, string error)
        {
            var resp = new JObject();
            resp["type"] = "panel_resp";
            resp["panel"] = "tasks";
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
