using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    /// <summary>
    /// Host→AS2 物品交接命令桥（内部调用，不对 Web 开放）。
    ///
    /// 命令经既有 cmd 通道下发，AS2 以 <c>npc_item_response</c> 回包并按 requestId 关联。
    /// 超时/断线都返回 null，调用方按失败处理；本类不缓存业务结果，幂等由 AS2 的
    /// operationId 与后端 action_id 共同保证。
    /// </summary>
    public sealed class NpcItemExchangeTask
    {
        public const string ResponseTask = "npc_item_response";
        internal const int DefaultTimeoutMs = 4000;

        private sealed class Pending
        {
            internal string Op;
            internal TaskCompletionSource<JObject> Completion;
        }

        private readonly Func<string, bool> _send;
        private readonly Func<string> _newId;
        private readonly Dictionary<string, Pending> _pending = new Dictionary<string, Pending>();
        private readonly object _gate = new object();
        private int _timeoutMs = DefaultTimeoutMs;

        internal NpcItemExchangeTask(Func<string, bool> send, Func<string> newId = null)
        {
            _send = send ?? throw new ArgumentNullException(nameof(send));
            _newId = newId ?? (() => Guid.NewGuid().ToString("N"));
        }

        internal int TimeoutMs
        {
            get { return _timeoutMs; }
            set { if (value > 0) _timeoutMs = value; }
        }

        /// <summary>summary/count/grant/take；返回 AS2 回包，超时或发送失败返回 null。</summary>
        internal async Task<JObject> RequestAsync(string action, JObject args, CancellationToken token)
        {
            if (string.IsNullOrEmpty(action)) return null;
            string requestId = "npcitem:" + _newId();
            var request = new JObject
            {
                ["task"] = "cmd",
                ["action"] = action,
                ["requestId"] = requestId
            };
            if (args != null)
            {
                foreach (JProperty property in args.Properties())
                {
                    if (string.Equals(property.Name, "task", StringComparison.Ordinal)
                        || string.Equals(property.Name, "action", StringComparison.Ordinal)
                        || string.Equals(property.Name, "requestId", StringComparison.Ordinal))
                        continue;
                    request[property.Name] = property.Value;
                }
            }

            var pending = new Pending
            {
                Op = OpOf(action),
                Completion = new TaskCompletionSource<JObject>(
                    TaskCreationOptions.RunContinuationsAsynchronously)
            };
            lock (_gate) _pending[requestId] = pending;
            try
            {
                bool sent;
                try { sent = _send(request.ToString(Formatting.None) + "\0"); }
                catch (Exception ex)
                {
                    LogManager.Log("[NpcItemExchange] send failed: " + ex.Message);
                    return null;
                }
                if (!sent)
                {
                    LogManager.Log("[NpcItemExchange] command dropped (socket unavailable): " + action);
                    return null;
                }
                Task delay = Task.Delay(_timeoutMs, token);
                Task completed = await Task.WhenAny(pending.Completion.Task, delay).ConfigureAwait(false);
                if (!ReferenceEquals(completed, pending.Completion.Task))
                {
                    LogManager.Log("[NpcItemExchange] command timed out: " + action);
                    return null;
                }
                return await pending.Completion.Task.ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                return null;
            }
            finally
            {
                lock (_gate) _pending.Remove(requestId);
            }
        }

        /// <summary>MessageRouter 同步入口：按 requestId 唤醒等待者；未知/迟到回包只忽略。</summary>
        public string Handle(JObject message)
        {
            JObject payload = message != null ? message["payload"] as JObject : null;
            if (payload == null) payload = message;
            if (payload == null) return null;
            string requestId = payload.Value<string>("requestId");
            if (string.IsNullOrEmpty(requestId)) return null;

            Pending pending;
            lock (_gate)
            {
                if (!_pending.TryGetValue(requestId, out pending)) return null;
                _pending.Remove(requestId);
            }
            string op = payload.Value<string>("op") ?? "";
            if (pending.Op.Length > 0 && op.Length > 0
                && !string.Equals(pending.Op, op, StringComparison.Ordinal))
            {
                LogManager.Log("[NpcItemExchange] response op mismatch: expected="
                    + pending.Op + " actual=" + op);
            }
            pending.Completion.TrySetResult(payload);
            return null;
        }

        /// <summary>断线：所有在途命令立即失败，避免 UI 悬在扣物品/查询上。</summary>
        internal void HandleTransportDisconnected()
        {
            List<Pending> pending;
            lock (_gate)
            {
                pending = new List<Pending>(_pending.Values);
                _pending.Clear();
            }
            for (int i = 0; i < pending.Count; i++)
                pending[i].Completion.TrySetResult(null);
        }

        private static string OpOf(string action)
        {
            switch (action)
            {
                case "npcItemSummary": return "summary";
                case "npcItemCount": return "count";
                case "npcItemGrant": return "grant";
                case "npcItemTake": return "take";
                default: return "";
            }
        }
    }
}
