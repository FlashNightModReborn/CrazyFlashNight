using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Text.RegularExpressions;
using CF7Launcher.Guardian;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Diagnostic
{
    // Observation only: no timers, retries, business acknowledgements or write-state changes.
    internal sealed class SkillResponseDiagnostics
    {
        internal sealed class Entry
        {
            internal string CallId, Instance, Command;
            internal int Epoch, FlashCallId;
            internal double Started;
            internal readonly HashSet<string> Stages = new(StringComparer.Ordinal);
        }

        private static readonly Regex CallId = new("^[A-Za-z0-9._-]{1,96}$");
        private static readonly Regex InstanceId = new("^[A-Za-z0-9._~-]{1,160}$");
        private static readonly HashSet<string> Commands = new(StringComparer.Ordinal)
            { "snapshot", "learnPreview", "learnCommit", "equip", "unequip", "moveSlot", "setPassive", "reorder" };
        private static readonly HashSet<string> WebStages = new(StringComparer.Ordinal)
            { "web_received", "dom_refresh_begin", "dom_refresh_end", "dom_refresh_failed", "frame_callback" };
        private static readonly HashSet<string> HostStages = new(StringComparer.Ordinal)
            { "ui_dispatch_requested", "ui_dispatch_enter", "web_post_begin", "web_post_returned",
                "web_post_returned_unobserved", "web_post_rejected", "web_post_failed" };
        private static readonly HashSet<string> Keys = new(StringComparer.Ordinal)
            { "type", "panel", "panelInstanceId", "callId", "cmd", "writeEpoch", "stage", "durationMs" };
        private readonly object sync = new();
        private readonly Queue<Entry> order = new();
        private readonly Dictionary<string, Entry> entries = new(StringComparer.Ordinal);
        private readonly Action<string> log;
        private readonly Func<double> clock;

        internal SkillResponseDiagnostics(Action<string> log, Func<double> clock = null)
        {
            this.log = log;
            this.clock = clock ?? (() => Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency);
        }

        internal int RetainedCount { get { lock (sync) return entries.Count; } }

        internal Entry Begin(string callId, string instance, string command, int epoch, int flashCallId = 0)
        {
            if (!CallId.IsMatch(callId ?? "") || !InstanceId.IsMatch(instance ?? "")
                || !Commands.Contains(command ?? "") || epoch < 0) return null;
            var entry = new Entry { CallId = callId, Instance = instance, Command = command, Epoch = epoch,
                FlashCallId = flashCallId, Started = clock() };
            lock (sync)
            {
                while (order.Count >= 64)
                {
                    var expired = order.Dequeue();
                    if (entries.TryGetValue(expired.CallId, out var current) && ReferenceEquals(expired, current))
                        entries.Remove(expired.CallId);
                }
                entries[callId] = entry; order.Enqueue(entry);
            }
            Record(entry, "ui_dispatch_requested");
            return entry;
        }

        internal void Record(Entry entry, string stage, double? webDuration = null)
        {
            if (entry == null || (!HostStages.Contains(stage) && !WebStages.Contains(stage))) return;
            string line;
            lock (sync)
            {
                if (!entries.TryGetValue(entry.CallId, out var current) || !ReferenceEquals(entry, current)
                    || !entry.Stages.Add(stage)) return;
                line = "event=skill_response_stage callIdRef=" + AuthorityLogFormatter.CreateReference(entry.CallId)
                    + " panelInstanceIdRef=" + AuthorityLogFormatter.CreateReference(entry.Instance)
                    + " cmd=" + entry.Command + " epoch=" + entry.Epoch.ToString(CultureInfo.InvariantCulture)
                    + " flashCallId=" + entry.FlashCallId.ToString(CultureInfo.InvariantCulture)
                    + " stage=" + stage + " hostElapsedMs=" + Math.Max(0, clock() - entry.Started).ToString("F3", CultureInfo.InvariantCulture);
                if (webDuration.HasValue) line += " webDurationMs=" + webDuration.Value.ToString("F3", CultureInfo.InvariantCulture);
            }
            try { log?.Invoke(line); } catch { }
        }

        internal bool TryRecordWeb(JObject message, string activeInstance)
        {
            if (message == null || message.Count != Keys.Count || message.Properties().Any(p => !Keys.Contains(p.Name))) return false;
            foreach (string key in new[] { "type", "panel", "panelInstanceId", "callId", "cmd", "stage" })
                if (message[key]?.Type != JTokenType.String) return false;
            if (message.Value<string>("type") != "skill_response_diag" || message.Value<string>("panel") != "skills") return false;
            if (message["writeEpoch"]?.Type != JTokenType.Integer
                || (message["durationMs"]?.Type != JTokenType.Integer && message["durationMs"]?.Type != JTokenType.Float)) return false;
            double duration = message.Value<double>("durationMs");
            if (!double.IsFinite(duration) || duration < 0 || duration > 600000) return false;
            string stage = message.Value<string>("stage");
            if (!WebStages.Contains(stage) || message.Value<string>("panelInstanceId") != activeInstance) return false;
            Entry entry;
            lock (sync)
            {
                if (!entries.TryGetValue(message.Value<string>("callId"), out entry)
                    || entry.Instance != activeInstance || entry.Command != message.Value<string>("cmd")
                    || !JToken.DeepEquals(message["writeEpoch"], new JValue(entry.Epoch))) return false;
            }
            Record(entry, stage, duration);
            return true;
        }
    }
}
