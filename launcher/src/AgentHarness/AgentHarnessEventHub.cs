using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.AgentHarness
{
    internal sealed class AgentHarnessEvent
    {
        internal long Seq;
        internal long UtcMs;
        internal string Kind;
        internal string Summary;
        internal JToken Data;

        internal JObject ToJson() => new JObject
        {
            ["seq"] = Seq,
            ["utcMs"] = UtcMs,
            ["kind"] = Kind ?? "",
            ["summary"] = Summary ?? "",
            ["data"] = Data != null ? Data.DeepClone() : JValue.CreateNull()
        };
    }

    internal sealed class AgentHarnessLogLine
    {
        internal long Seq;
        internal long UtcMs;
        internal string Line;

        internal JObject ToJson() => new JObject
        {
            ["seq"] = Seq,
            ["utcMs"] = UtcMs,
            ["line"] = Line ?? ""
        };
    }

    /// <summary>
    /// Monotonic watermarked event + log ring buffer with push-based async waiters
    /// and correlated AS2 response completion. Zero polling required.
    /// </summary>
    internal sealed class AgentHarnessEventHub : IDisposable
    {
        private const int MaxEvents = 2000;
        private const int MaxLogs = 4000;

        private readonly object _lock = new();
        private readonly LinkedList<AgentHarnessEvent> _events = new();
        private readonly LinkedList<AgentHarnessLogLine> _logs = new();
        private readonly List<PendingEventWaiter> _waiters = new();
        private readonly ConcurrentDictionary<string, TaskCompletionSource<JObject>> _as2Waiters =
            new(StringComparer.Ordinal);
        private long _seq;
        private long _logSeq;
        private bool _disposed;

        private sealed class PendingEventWaiter
        {
            internal long SinceSeq;
            internal Predicate<AgentHarnessEvent> Match;
            internal TaskCompletionSource<AgentHarnessEvent> Tcs;
        }

        internal long CurrentEventSeq
        {
            get { lock (_lock) { return _seq; } }
        }

        internal long CurrentLogSeq
        {
            get { lock (_lock) { return _logSeq; } }
        }

        internal void AttachLogTap()
        {
            LogManager.OnLogLine += HandleLogLine;
        }

        internal void DetachLogTap()
        {
            LogManager.OnLogLine -= HandleLogLine;
        }

        internal AgentHarnessEvent RecordEvent(string kind, string summary, JToken data = null)
        {
            if (_disposed) return null;
            AgentHarnessEvent ev;
            List<PendingEventWaiter> matched = null;
            lock (_lock)
            {
                if (_disposed) return null;
                ev = new AgentHarnessEvent
                {
                    Seq = ++_seq,
                    UtcMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                    Kind = kind ?? "",
                    Summary = summary ?? "",
                    Data = data?.DeepClone()
                };
                _events.AddLast(ev);
                while (_events.Count > MaxEvents) _events.RemoveFirst();

                for (int i = _waiters.Count - 1; i >= 0; i--)
                {
                    PendingEventWaiter w = _waiters[i];
                    if (ev.Seq > w.SinceSeq && SafeMatch(w.Match, ev))
                    {
                        matched ??= new List<PendingEventWaiter>();
                        matched.Add(w);
                        _waiters.RemoveAt(i);
                    }
                }
            }
            if (matched != null)
            {
                foreach (var w in matched) w.Tcs.TrySetResult(ev);
            }
            return ev;
        }

        internal void HandleLogLine(string message)
        {
            if (_disposed || message == null) return;
            lock (_lock)
            {
                if (_disposed) return;
                _logs.AddLast(new AgentHarnessLogLine
                {
                    Seq = ++_logSeq,
                    UtcMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                    Line = message
                });
                while (_logs.Count > MaxLogs) _logs.RemoveFirst();
            }

            const string archiveSavedMarker = "[ArchiveTask] Shadow saved: ";
            int savedIdx = message.IndexOf(archiveSavedMarker, StringComparison.Ordinal);
            if (savedIdx >= 0)
            {
                string rest = message.Substring(savedIdx + archiveSavedMarker.Length).Trim();
                int space = rest.IndexOf(' ');
                string slot = space > 0 ? rest.Substring(0, space) : rest;
                RecordEvent("archive_shadow_saved", message, new JObject { ["slot"] = slot });
            }
            else if (message.StartsWith("event=scene_transition_", StringComparison.Ordinal))
            {
                RecordEvent("scene_transition", message, new JObject { ["raw"] = message });
            }
            else if (message.StartsWith("event=harness_", StringComparison.Ordinal))
            {
                RecordEvent("harness_internal", message, new JObject { ["raw"] = message });
            }
            else
            {
                RecordEvent("log_line", message, null);
            }
        }

        internal TaskCompletionSource<JObject> RegisterAs2Waiter(string requestId)
        {
            var tcs = new TaskCompletionSource<JObject>(TaskCreationOptions.RunContinuationsAsynchronously);
            _as2Waiters[requestId] = tcs;
            return tcs;
        }

        internal void RemoveAs2Waiter(string requestId)
        {
            _as2Waiters.TryRemove(requestId, out _);
        }

        internal void CompleteAs2Response(JObject payload)
        {
            if (payload == null) return;
            string reqId = payload.Value<string>("requestId");
            if (!string.IsNullOrEmpty(reqId) && _as2Waiters.TryRemove(reqId, out var tcs))
            {
                tcs.TrySetResult((JObject)payload.DeepClone());
            }
            RecordEvent("as2_harness_response",
                "sub=" + (payload.Value<string>("sub") ?? "") + " ok=" + (payload.Value<bool?>("ok") == true),
                payload);
        }

        internal void ObserveAs2Event(JObject payload)
        {
            if (payload == null) return;
            string kind = payload.Value<string>("kind") ?? "unknown";
            RecordEvent("as2_" + kind, kind, payload);
        }

        internal async Task<(bool Matched, AgentHarnessEvent Event, long LastSeq)> WaitForAsync(
            long sinceSeq,
            Predicate<AgentHarnessEvent> match,
            int timeoutMs,
            CancellationToken ct = default)
        {
            PendingEventWaiter waiter = null;
            lock (_lock)
            {
                foreach (var ev in _events)
                {
                    if (ev.Seq > sinceSeq && SafeMatch(match, ev))
                        return (true, ev, _seq);
                }
                if (_disposed || timeoutMs <= 0)
                    return (false, null, _seq);

                waiter = new PendingEventWaiter
                {
                    SinceSeq = sinceSeq,
                    Match = match,
                    Tcs = new TaskCompletionSource<AgentHarnessEvent>(TaskCreationOptions.RunContinuationsAsynchronously)
                };
                _waiters.Add(waiter);
            }

            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            if (timeoutMs < int.MaxValue) cts.CancelAfter(timeoutMs);
            using var reg = cts.Token.Register(() => waiter.Tcs.TrySetCanceled());
            try
            {
                AgentHarnessEvent result = await waiter.Tcs.Task.ConfigureAwait(false);
                return (true, result, CurrentEventSeq);
            }
            catch (TaskCanceledException)
            {
                lock (_lock) { _waiters.Remove(waiter); }
                return (false, null, CurrentEventSeq);
            }
        }

        internal static Predicate<AgentHarnessEvent> BuildFilter(JObject filter)
        {
            if (filter == null) return _ => true;
            string kind = filter.Value<string>("kind");
            string substring = filter.Value<string>("contains");
            string regexText = filter.Value<string>("regex");
            string panel = filter.Value<string>("panel");
            string slot = filter.Value<string>("slot");
            string state = filter.Value<string>("state");
            Regex regex = !string.IsNullOrEmpty(regexText) ? new Regex(regexText, RegexOptions.CultureInvariant) : null;

            return ev =>
            {
                if (!string.IsNullOrEmpty(kind) && !string.Equals(ev.Kind, kind, StringComparison.Ordinal))
                    return false;
                if (!string.IsNullOrEmpty(panel))
                {
                    string evPanel = ev.Data?["panel"]?.Value<string>();
                    if (!string.Equals(evPanel, panel, StringComparison.Ordinal)) return false;
                }
                if (!string.IsNullOrEmpty(slot))
                {
                    string evSlot = ev.Data?["slot"]?.Value<string>();
                    if (!string.Equals(evSlot, slot, StringComparison.Ordinal)) return false;
                }
                if (!string.IsNullOrEmpty(state))
                {
                    string evState = ev.Data?["state"]?.Value<string>();
                    if (!string.Equals(evState, state, StringComparison.Ordinal)) return false;
                }
                if (!string.IsNullOrEmpty(substring) || regex != null)
                {
                    string haystack = (ev.Summary ?? "") + "\n" + (ev.Data?.ToString(Newtonsoft.Json.Formatting.None) ?? "");
                    if (!string.IsNullOrEmpty(substring) && haystack.IndexOf(substring, StringComparison.Ordinal) < 0)
                        return false;
                    if (regex != null && !regex.IsMatch(haystack))
                        return false;
                }
                return true;
            };
        }

        internal JObject QueryLogs(long sinceSeq, int limit, string contains, string regexText)
        {
            if (limit <= 0) limit = 100;
            if (limit > 1000) limit = 1000;
            Regex regex = !string.IsNullOrEmpty(regexText) ? new Regex(regexText, RegexOptions.CultureInvariant) : null;

            var matches = new JArray();
            long latestSeq;
            lock (_lock)
            {
                latestSeq = _logSeq;
                var list = new List<AgentHarnessLogLine>();
                foreach (var item in _logs)
                {
                    if (item.Seq <= sinceSeq) continue;
                    if (!string.IsNullOrEmpty(contains) && item.Line.IndexOf(contains, StringComparison.Ordinal) < 0)
                        continue;
                    if (regex != null && !regex.IsMatch(item.Line))
                        continue;
                    list.Add(item);
                }
                int start = Math.Max(0, list.Count - limit);
                for (int i = start; i < list.Count; i++) matches.Add(list[i].ToJson());
            }
            return new JObject
            {
                ["lastSeq"] = latestSeq,
                ["count"] = matches.Count,
                ["lines"] = matches
            };
        }

        private static bool SafeMatch(Predicate<AgentHarnessEvent> match, AgentHarnessEvent ev)
        {
            try { return match == null || match(ev); }
            catch { return false; }
        }

        public void Dispose()
        {
            DetachLogTap();
            lock (_lock)
            {
                if (_disposed) return;
                _disposed = true;
                foreach (var w in _waiters) w.Tcs.TrySetCanceled();
                _waiters.Clear();
            }
            foreach (var kv in _as2Waiters)
                kv.Value.TrySetCanceled();
            _as2Waiters.Clear();
        }
    }
}
