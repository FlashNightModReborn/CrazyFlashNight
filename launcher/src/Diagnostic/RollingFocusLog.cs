using System;
using System.IO;
using System.Text;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Diagnostic
{
    // 只拥有固定文件名的焦点日志。重启不清空历史；旧段按容量覆盖，每段自带会话身份。
    internal sealed class RollingFocusLog : IDisposable
    {
        internal const int DefaultFileBytes = 6 * 1024 * 1024;
        internal const int FileCount = 3;
        private readonly object _gate = new object();
        private readonly string _directory;
        private readonly int _maxBytes;
        private readonly JObject _context;
        private readonly Encoding _encoding = new UTF8Encoding(false);
        private StreamWriter _writer;
        private long _bytes;
        private int _segment;
        private bool _disposed;
        private FocusIncidentRecorder _incidents;

        internal RollingFocusLog(string directory, JObject context, int maxBytes = DefaultFileBytes)
        {
            _directory = Path.GetFullPath(directory);
            _context = (JObject)context.DeepClone();
            _maxBytes = maxBytes;
            if (_maxBytes < 1024) throw new ArgumentOutOfRangeException(nameof(maxBytes));
            Directory.CreateDirectory(_directory);
            _context["retention"] = new JObject { ["files"] = FileCount, ["bytesPerFile"] = _maxBytes };
            _context["status"] = "recording";
            _context["as2ObserveReadySeen"] = false;
            WriteContext();
            OpenSegment();
            if (maxBytes == DefaultFileBytes)
            {
                // 旧 8 MiB 分段迁移：显式舍弃超出新单段预算的旧段，避免临时越过总预算。
                for (int i = 1; i < FileCount; i++)
                    if (File.Exists(SegmentPath(i)) && new FileInfo(SegmentPath(i)).Length > _maxBytes)
                    { File.Delete(SegmentPath(i)); _context["legacyOversizeSegmentDropped"] = true; }
                _context["incidentSlots"] = 4;
                _context["incidentBytesPerSlot"] = FocusIncidentRecorder.SlotBytes;
                _context["totalLogBudgetBytes"] = 22 * 1024 * 1024;
                _incidents = new FocusIncidentRecorder(_directory, (string)_context["session"]);
                WriteContext();
            }
        }

        internal static string[] Names => new[] { "focus-trace.log.2", "focus-trace.log.1", "focus-trace.log", "recording-context.json", "focus-incident.0.log", "focus-incident.1.log", "focus-incident.2.log", "focus-incident.3.log" };
        private string SegmentPath(int index) => Path.Combine(_directory, "focus-trace.log" + (index == 0 ? "" : "." + index));

        private void OpenSegment()
        {
            _writer?.Dispose();
            _writer = null;
            for (int i = FileCount - 1; i >= 1; i--)
            {
                if (File.Exists(SegmentPath(i))) File.Delete(SegmentPath(i));
                if (File.Exists(SegmentPath(i - 1))) File.Move(SegmentPath(i - 1), SegmentPath(i));
            }
            string header = "[FocusRecording] " + new JObject {
                ["event"] = "segment.start", ["segment"] = ++_segment,
                ["utc"] = DateTime.UtcNow.ToString("O"), ["context"] = _context.DeepClone()
            }.ToString(Formatting.None);
            _bytes = _encoding.GetByteCount(header) + 1;
            if (_bytes + 256 > _maxBytes) throw new InvalidOperationException("Focus recording context exceeds segment capacity.");
            _writer = new StreamWriter(new FileStream(SegmentPath(0), FileMode.Create,
                FileAccess.Write, FileShare.ReadWrite | FileShare.Delete), _encoding) { NewLine = "\n" };
            _writer.WriteLine(header);
            _writer.Flush();
        }

        internal void Append(string batch)
        {
            lock (_gate)
            {
                if (_disposed) return;
                foreach (string raw in batch.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    string line = raw;
                    int size = _encoding.GetByteCount(line) + 1;
                    if (size > _maxBytes / 2)
                    {
                        line = "[FocusRecording] " + new JObject { ["event"] = "storage.line_dropped",
                            ["session"] = _context["session"], ["bytes"] = size }.ToString(Formatting.None);
                        size = _encoding.GetByteCount(line) + 1;
                    }
                    if (_bytes + size > _maxBytes) OpenSegment();
                    _writer.WriteLine(line);
                    _bytes += size;
                    if (!(bool)_context["as2ObserveReadySeen"] && line.Contains("\"event\":\"as2.observation\"")
                        && line.Contains(" event=observe_ready ") && line.Contains("detail=rolling_host_retention"))
                    {
                        _context["as2ObserveReadySeen"] = true;
                        WriteContext();
                    }
                }
                _writer.Flush();
                try { _incidents?.Append(batch); }
                catch (Exception ex)
                {
                    _context["incidentError"] = ex.GetType().Name;
                    try { _incidents?.Dispose(); } catch { }
                    _incidents = null;
                    try { WriteContext(); } catch { }
                }
            }
        }

        private void WriteContext()
        {
            string path = Path.Combine(_directory, "recording-context.json");
            string temp = path + ".tmp";
            File.WriteAllText(temp, _context.ToString(Formatting.Indented), _encoding);
            File.Move(temp, path, true);
        }

        internal void MarkError(string error)
        {
            lock (_gate)
            {
                _context["status"] = "write_error";
                _context["error"] = error;
                try { WriteContext(); } catch { }
            }
        }

        public void Dispose()
        {
            lock (_gate)
            {
                if (_disposed) return;
                _disposed = true;
                _incidents?.Dispose();
                _incidents = null;
                _writer?.Dispose();
                _writer = null;
                if ((string)_context["status"] == "recording") _context["status"] = "stopped";
                _context["stoppedAtUtc"] = DateTime.UtcNow.ToString("O");
                WriteContext();
            }
        }
    }
}
