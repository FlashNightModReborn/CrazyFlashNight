using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Lightweight JSONL performance trace. High-frequency paths should use Counter()
    /// and flush snapshots at lifecycle boundaries instead of writing every event.
    /// </summary>
    public static class PerfTrace
    {
        private static readonly object _lock = new object();
        private static readonly Dictionary<string, long> _counters = new Dictionary<string, long>();
        private static long _startTimestamp = Stopwatch.GetTimestamp();
        private static StreamWriter _writer;
        private static string _tracePath;
        private static bool _enabled;

        public static string TracePath { get { return _tracePath; } }

        public static void SetProcessStart(long timestamp)
        {
            if (timestamp > 0)
                _startTimestamp = timestamp;
        }

        public static void Init(string projectRoot)
        {
            if (string.IsNullOrEmpty(projectRoot))
                return;
            lock (_lock)
            {
                if (_writer != null)
                    return;
                try
                {
                    string logDir = Path.Combine(projectRoot, "logs");
                    if (!Directory.Exists(logDir))
                        Directory.CreateDirectory(logDir);

                    _tracePath = Path.Combine(logDir, "perf-latest.jsonl");
                    FileStream fs = new FileStream(_tracePath, FileMode.Create, FileAccess.Write, FileShare.Read);
                    _writer = new StreamWriter(fs, new UTF8Encoding(false));
                    _writer.AutoFlush = true;
                    _enabled = true;
                    WriteEventLocked("session", "start", null, 0);
                    LogManager.Log("[PerfTrace] writing " + _tracePath);
                }
                catch (Exception ex)
                {
                    _enabled = false;
                    _writer = null;
                    LogManager.Log("[PerfTrace] init failed: " + ex.Message);
                }
            }
        }

        public static IDisposable Scope(string name)
        {
            return new PerfScope(name);
        }

        public static void Mark(string name)
        {
            Mark(name, null);
        }

        public static void Mark(string name, string detail)
        {
            if (!_enabled) return;
            lock (_lock)
            {
                WriteEventLocked("mark", name, detail, 0);
            }
        }

        public static void Duration(string name, long startTimestamp)
        {
            Duration(name, startTimestamp, null);
        }

        public static void Duration(string name, long startTimestamp, string detail)
        {
            if (!_enabled) return;
            double durationMs = ElapsedMs(startTimestamp);
            lock (_lock)
            {
                WriteEventLocked("duration", name, detail, durationMs);
            }
        }

        public static void Counter(string name)
        {
            Counter(name, 1);
        }

        public static void Counter(string name, long delta)
        {
            if (string.IsNullOrEmpty(name)) return;
            lock (_lock)
            {
                long current;
                _counters.TryGetValue(name, out current);
                _counters[name] = current + delta;
            }
        }

        public static void FlushCounters(string reason)
        {
            if (!_enabled) return;
            lock (_lock)
            {
                if (_counters.Count == 0)
                    return;
                StringBuilder detail = new StringBuilder();
                detail.Append("{\"reason\":\"");
                detail.Append(JsonEscape(reason ?? "unspecified"));
                detail.Append("\",\"counters\":{");
                bool first = true;
                foreach (KeyValuePair<string, long> kv in _counters)
                {
                    if (!first) detail.Append(',');
                    first = false;
                    detail.Append('"');
                    detail.Append(JsonEscape(kv.Key));
                    detail.Append("\":");
                    detail.Append(kv.Value.ToString(CultureInfo.InvariantCulture));
                }
                detail.Append("}}");
                WriteEventLocked("counters", "snapshot", detail.ToString(), 0, true);
            }
        }

        public static void Shutdown()
        {
            lock (_lock)
            {
                try
                {
                    if (_writer != null)
                    {
                        if (_counters.Count > 0)
                            FlushCounters("shutdown");
                        WriteEventLocked("session", "end", null, 0);
                        _writer.Flush();
                        _writer.Close();
                    }
                }
                catch { }
                finally
                {
                    _writer = null;
                    _enabled = false;
                }
            }
        }

        private static double ElapsedMs(long timestamp)
        {
            return (Stopwatch.GetTimestamp() - timestamp) * 1000.0 / Stopwatch.Frequency;
        }

        private static double SinceStartMs()
        {
            return ElapsedMs(_startTimestamp);
        }

        private static void WriteEventLocked(string kind, string name, string detail, double durationMs)
        {
            WriteEventLocked(kind, name, detail, durationMs, false);
        }

        private static void WriteEventLocked(string kind, string name, string detail, double durationMs, bool detailIsJson)
        {
            if (_writer == null) return;

            StringBuilder sb = new StringBuilder(256);
            sb.Append("{\"ts\":\"");
            sb.Append(DateTime.Now.ToString("O", CultureInfo.InvariantCulture));
            sb.Append("\",\"t_ms\":");
            sb.Append(SinceStartMs().ToString("0.###", CultureInfo.InvariantCulture));
            sb.Append(",\"thread\":");
            sb.Append(Thread.CurrentThread.ManagedThreadId);
            sb.Append(",\"kind\":\"");
            sb.Append(JsonEscape(kind ?? ""));
            sb.Append("\",\"name\":\"");
            sb.Append(JsonEscape(name ?? ""));
            sb.Append('"');
            if (durationMs > 0)
            {
                sb.Append(",\"duration_ms\":");
                sb.Append(durationMs.ToString("0.###", CultureInfo.InvariantCulture));
            }
            if (!string.IsNullOrEmpty(detail))
            {
                sb.Append(",\"detail\":");
                if (detailIsJson)
                    sb.Append(detail);
                else
                {
                    sb.Append('"');
                    sb.Append(JsonEscape(detail));
                    sb.Append('"');
                }
            }
            sb.Append('}');
            try { _writer.WriteLine(sb.ToString()); } catch { }
        }

        private static string JsonEscape(string value)
        {
            if (string.IsNullOrEmpty(value))
                return "";
            StringBuilder sb = new StringBuilder(value.Length + 8);
            for (int i = 0; i < value.Length; i++)
            {
                char c = value[i];
                switch (c)
                {
                    case '\\': sb.Append("\\\\"); break;
                    case '"': sb.Append("\\\""); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 32)
                            sb.Append("\\u" + ((int)c).ToString("x4", CultureInfo.InvariantCulture));
                        else
                            sb.Append(c);
                        break;
                }
            }
            return sb.ToString();
        }

        private sealed class PerfScope : IDisposable
        {
            private readonly string _name;
            private readonly long _start;
            private bool _disposed;

            public PerfScope(string name)
            {
                _name = name ?? "scope";
                _start = Stopwatch.GetTimestamp();
            }

            public void Dispose()
            {
                if (_disposed) return;
                _disposed = true;
                Duration(_name, _start);
            }
        }
    }
}
