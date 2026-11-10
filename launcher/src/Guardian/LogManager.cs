using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 全局日志管理器：WinForms TextBox、launcher.log 与独立低频 perf session JSONL。
    /// 会话文件随 InitFileLog/Shutdown 创建和关闭，帧线程只排队调度事件。
    ///
    /// 线程安全：跨线程调用自动 Invoke 到 UI 线程（TextBox 部分）。
    /// 文件写入使用独立锁，不阻塞 UI。
    /// </summary>
    public static class LogManager
    {
        private static TextBox _logBox;
        private static Form _form;
        private static readonly object _uiLock = new object();

        // 文件日志
        private static StreamWriter _fileWriter;
        private static readonly object _fileLock = new object();
        private static readonly object _perfFileLock = new object();
        private static readonly object _sessionQueueLock = new object();
        private static string _logFilePath;
        private static StreamWriter _perfSessionWriter;
        private static string _perfSessionLogPath;
        private static readonly Queue<QueuedPerfSessionEvent> _perfSessionEvents =
            new Queue<QueuedPerfSessionEvent>();
        private static Func<DateTime> _perfUtcNow = () => DateTime.UtcNow;
        private static Func<double> _perfNowMs =
            () => Stopwatch.GetTimestamp() * 1000.0 / Stopwatch.Frequency;
        private static double _perfSessionStartedMs;
        private static long _perfSampleSequence;
        private static volatile bool _perfSessionActive;
        private static bool _perfSessionFailureReported;
        private static bool _perfSessionLifecycleActive;
        internal static Action PerfSessionWriteFailureForTests;

        private readonly record struct QueuedPerfSessionEvent(
            bool IsPresented,
            DateTime Utc,
            double ElapsedMs,
            long Command,
            int Scene,
            RenderSelection Selection,
            int SourceWidth,
            int SourceHeight,
            string Reason)
        {
            internal static QueuedPerfSessionEvent ForRequest(DateTime utc,double elapsedMs,
                long command,int scene,RenderSelection target,string reason)
            {
                return new QueuedPerfSessionEvent(false,utc,elapsedMs,command,scene,
                    target,0,0,reason);
            }

            internal static QueuedPerfSessionEvent ForPresented(DateTime utc,double elapsedMs,
                long command,RenderSelection actual,System.Drawing.Size source,string reason)
            {
                return new QueuedPerfSessionEvent(true,utc,elapsedMs,command,0,
                    actual,source.Width,source.Height,reason);
            }

            internal string ToJsonLine()
            {
                var item=new JObject
                {
                    ["event"]=IsPresented ? "render_schedule_presented" : "render_schedule_request",
                    ["utc"]=Utc.ToString("O",CultureInfo.InvariantCulture),
                    ["elapsedMs"]=ElapsedMs,
                    ["command"]=Command
                };
                if(IsPresented)
                {
                    item["actualStage"]=Selection.Stage;
                    item["actualHeight"]=Selection.Height;
                    item["actualQuality"]=Selection.Quality;
                    item["actualEffectLevel"]=Selection.EffectLevel;
                    item["sourceWidth"]=SourceWidth;
                    item["sourceHeight"]=SourceHeight;
                }
                else
                {
                    item["scene"]=Scene;
                    item["targetStage"]=Selection.Stage;
                    item["targetHeight"]=Selection.Height;
                    item["targetQuality"]=Selection.Quality;
                    item["targetEffectLevel"]=Selection.EffectLevel;
                }
                item["reason"]=Reason;
                return item.ToString(Formatting.None);
            }
        }

        // 测试 sink：非 null 时 Log() 短路，不写文件不写 UI。
        // volatile 保证多线程 set / 读取的可见性；teardown 时与 in-flight Log() 的 race
        // 可接受（测试环境 sink 通常是 noop 或 list 收集器，race 不影响语义）。
        private static volatile Action<string> _sink;

        public static void SetSink(Action<string> sink) { _sink = sink; }
        public static void ResetSink() { _sink = null; }

        /// <summary>launcher.log 文件路径（供 /logs endpoint 读取）。</summary>
        public static string LogFilePath { get { return _logFilePath; } }

        /// <summary>
        /// 初始化 UI 日志通道。由 GuardianForm 构造函数调用。
        /// </summary>
        public static void Init(Form form, TextBox logBox)
        {
            _form = form;
            _logBox = logBox;
        }

        /// <summary>
        /// 启用文件日志通道。在 projectRoot 确定后调用，不影响已初始化的 UI 通道。
        /// </summary>
        public static void InitFileLog(string projectRoot)
        {
            InitFileLog(projectRoot,null,null);
        }

        internal static void InitFileLog(string projectRoot,Func<DateTime> utcNow,
            Func<double> monotonicNowMs)
        {
            _perfUtcNow=utcNow ?? (() => DateTime.UtcNow);
            _perfNowMs=monotonicNowMs ??
                (() => Stopwatch.GetTimestamp()*1000.0/Stopwatch.Frequency);
            PerfSessionWriteFailureForTests=null;
            SetupFileLog(projectRoot);
            SetupPerfSession(projectRoot);
        }

        internal static string PerfSessionLogPath { get { return _perfSessionLogPath; } }

        private static void SetupFileLog(string projectRoot)
        {
            try
            {
                string logDir = Path.Combine(projectRoot, "logs");
                if (!Directory.Exists(logDir))
                    Directory.CreateDirectory(logDir);

                string logFilePath = Path.Combine(logDir, "launcher.log");
                if (_fileWriter != null)
                {
                    if (_logFilePath == null)
                        _logFilePath = logFilePath;
                    return;
                }
                _logFilePath = logFilePath;

                // 启动时轮转：旧日志 → .1（保留 1 份备份）
                if (File.Exists(_logFilePath))
                {
                    FileInfo fi = new FileInfo(_logFilePath);
                    // 超过 2MB 或上次写入超过 1 天则轮转
                    if (fi.Length > 2 * 1024 * 1024
                        || fi.LastWriteTime.Date < DateTime.Now.Date)
                    {
                        string backup = _logFilePath + ".1";
                        try { File.Delete(backup); } catch { }
                        try { File.Move(_logFilePath, backup); } catch { }
                    }
                }

                _fileWriter = new StreamWriter(_logFilePath, true, System.Text.Encoding.UTF8);
                _fileWriter.AutoFlush = true;

                // 会话分隔符
                _fileWriter.WriteLine();
                _fileWriter.WriteLine("════════ " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " ════════");
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.Write("[LogManager] File log init failed: " + ex.Message);
            }
        }

        private static void SetupPerfSession(string projectRoot)
        {
            lock (_perfFileLock)
            {
                if (_perfSessionLifecycleActive) return;
                _perfSessionLifecycleActive=true;
                _perfSessionFailureReported=false;
                _perfSessionFailureReason=null;
                FileStream stream=null;
                try
                {
                    string directory=Path.Combine(projectRoot,"logs","perf-sessions");
                    Directory.CreateDirectory(directory);
                    string stamp=_perfUtcNow().ToUniversalTime().ToString("yyyyMMdd'T'HHmmss.fffffff'Z'",CultureInfo.InvariantCulture);
                    string fileName=stamp+"-"+Process.GetCurrentProcess().Id.ToString(CultureInfo.InvariantCulture)
                        +"-"+Guid.NewGuid().ToString("N")+".jsonl";
                    _perfSessionLogPath=Path.Combine(directory,fileName);
                    stream=new FileStream(_perfSessionLogPath,FileMode.CreateNew,FileAccess.Write,FileShare.Read);
                    _perfSessionWriter=new StreamWriter(stream,new UTF8Encoding(false));
                    _perfSessionWriter.AutoFlush=true;
                    lock (_sessionQueueLock)
                    {
                        _perfSessionEvents.Clear();
                        _perfSessionStartedMs=_perfNowMs();
                        _perfSessionActive=true;
                    }
                    _perfSampleSequence=0;
                    Assembly core=typeof(LogManager).Assembly;
                    string mvid=core.ManifestModule.ModuleVersionId.ToString("D");
                    string fileVersion=string.IsNullOrEmpty(core.Location) ? null
                        : FileVersionInfo.GetVersionInfo(core.Location).FileVersion;
                    string identity=ReadRuntimeBuildIdentity(core.Location,out string identityReason);
                    var start=NewPerfEvent("session_start");
                    start["pid"]=Process.GetCurrentProcess().Id;
                    start["coreMvid"]=mvid;
                    start["coreFileVersion"]=fileVersion;
                    start["buildIdentity"]=identity;
                    start["buildIdentityReason"]=identity==null ? identityReason : null;
                    start["taskProgress"]=JValue.CreateNull();
                    start["taskProgressReason"]="not_exported";
                    WritePerfEventLocked(start);
                }
                catch (Exception ex)
                {
                    try { stream?.Close(); } catch { }
                    HandlePerfSessionWriteFailure(ex.GetType().Name);
                }
            }
        }

        private static string _perfSessionFailureReason;

        private static string ReadRuntimeBuildIdentity(string assemblyLocation,out string reason)
        {
            reason=null;
            try
            {
                if(string.IsNullOrEmpty(assemblyLocation)) {
                    reason="core_location_unavailable"; return null;
                }
                string directory=Path.GetDirectoryName(assemblyLocation);
                string path=Path.Combine(directory,"cf7-runtime-manifest.tsv");
                if(!File.Exists(path)) { reason="runtime_manifest_unavailable"; return null; }
                string identity=null;
                foreach(string line in File.ReadLines(path)) {
                    string[] fields=line.Split('\t');
                    if(fields.Length!=2 || fields[0]!="buildIdentityHash") continue;
                    if(identity!=null || !IsSha256(fields[1])) {
                        reason="runtime_manifest_identity_invalid"; return null;
                    }
                    identity=fields[1];
                }
                if(identity==null) reason="runtime_manifest_identity_unavailable";
                return identity;
            }
            catch (Exception ex)
            {
                reason="runtime_manifest_"+ex.GetType().Name;
                return null;
            }
        }

        private static bool IsSha256(string value)
        {
            if(value==null || value.Length!=64) return false;
            foreach(char c in value)
                if(!((c>='0' && c<='9') || (c>='a' && c<='f') || (c>='A' && c<='F'))) return false;
            return true;
        }

        private static JObject NewPerfEvent(string name)
        {
            double elapsed=Math.Max(0,_perfNowMs()-_perfSessionStartedMs);
            return new JObject
            {
                ["event"]=name,
                ["utc"]=_perfUtcNow().ToUniversalTime().ToString("O",CultureInfo.InvariantCulture),
                ["elapsedMs"]=Math.Round(elapsed,3)
            };
        }

        private static JToken NullableValue<T>(T? value) where T : struct
        {
            return value.HasValue ? new JValue(value.Value) : JValue.CreateNull();
        }

        internal static void EnqueueRenderScheduleRequest(long command,int scene,
            RenderSelection target,string reason)
        {
            if(!_perfSessionActive) return;
            try
            {
                lock (_sessionQueueLock)
                {
                    if(!_perfSessionActive) return;
                    DateTime utc=_perfUtcNow().ToUniversalTime();
                    double elapsedMs=Math.Round(Math.Max(0,_perfNowMs()-_perfSessionStartedMs),3);
                    _perfSessionEvents.Enqueue(QueuedPerfSessionEvent.ForRequest(
                        utc,elapsedMs,command,scene,target,reason));
                }
            }
            catch (Exception ex)
            {
                HandlePerfSessionWriteFailure(ex.GetType().Name);
            }
        }

        internal static void EnqueueRenderSchedulePresented(long command,
            RenderSelection actual,System.Drawing.Size source,string reason)
        {
            if(!_perfSessionActive) return;
            try
            {
                lock (_sessionQueueLock)
                {
                    if(!_perfSessionActive) return;
                    DateTime utc=_perfUtcNow().ToUniversalTime();
                    double elapsedMs=Math.Round(Math.Max(0,_perfNowMs()-_perfSessionStartedMs),3);
                    _perfSessionEvents.Enqueue(QueuedPerfSessionEvent.ForPresented(
                        utc,elapsedMs,command,actual,source,reason));
                }
            }
            catch (Exception ex)
            {
                HandlePerfSessionWriteFailure(ex.GetType().Name);
            }
        }

        private static string[] DrainPerfSessionEventLines()
        {
            QueuedPerfSessionEvent[] drained;
            lock (_sessionQueueLock)
            {
                if(_perfSessionEvents.Count==0) return Array.Empty<string>();
                drained=_perfSessionEvents.ToArray();
                _perfSessionEvents.Clear();
            }
            string[] lines=new string[drained.Length];
            for(int i=0;i<drained.Length;i++)
                lines[i]=drained[i].ToJsonLine();
            return lines;
        }

        internal static void WritePerfSessionSample(PerfTelemetrySnapshot snapshot)
        {
            if(snapshot==null || !_perfSessionActive) return;
            try
            {
                string[] queuedLines=DrainPerfSessionEventLines();
                var item=NewPerfEvent("perf_sample");
                item["frameDomain"]="host_f_ingress";
                item["sourceFrameAvailable"]=false;
                item["as2SampleFrame"]=JValue.CreateNull();
                item["connectionGeneration"]=NullableValue(snapshot.ConnectionGeneration);
                item["hostFrameOrdinal"]=NullableValue(snapshot.HostFrameOrdinal);
                item["sourceScene"]=NullableValue(snapshot.SourceScene);
                item["sourceSampleSequence"]=NullableValue(snapshot.SourceSampleSequence);
                item["sampleFrame"]=NullableValue(snapshot.SampleFrame);
                item["stalenessFrames"]=NullableValue(snapshot.StalenessFrames);
                item["sampleAgeMs"]=NullableValue(snapshot.SampleAgeMs);
                item["acceptedSampleFrame"]=NullableValue(snapshot.AcceptedSampleFrame);
                item["acceptedStalenessFrames"]=NullableValue(snapshot.AcceptedStalenessFrames);
                item["acceptedSampleAgeMs"]=NullableValue(snapshot.AcceptedSampleAgeMs);
                item["frameIngressAgeMs"]=NullableValue(snapshot.FrameIngressAgeMs);
                item["transportAgeMs"]=NullableValue(snapshot.TransportAgeMs);
                item["inboundCount"]=NullableValue(snapshot.InboundCount);
                item["sourceFps"]=NullableValue(snapshot.SourceFps);
                item["acceptedFps"]=NullableValue(snapshot.AcceptedFps);
                item["sampleRejectReason"]=snapshot.SampleRejectReason;
                item["paused"]=NullableValue(snapshot.Paused);
                item["foreground"]=NullableValue(snapshot.Foreground);
                item["surfaceGate"]=NullableValue(snapshot.SurfaceGate);
                item["connected"]=NullableValue(snapshot.Connected);
                lock (_perfFileLock)
                {
                    if(_perfSessionWriter==null) return;
                    for(int i=0;i<queuedLines.Length;i++)
                    {
                        if(!WritePerfLineLocked(queuedLines[i])) return;
                    }
                    item["sessionSampleSequence"]=++_perfSampleSequence;
                    WritePerfEventLocked(item);
                }
            }
            catch (Exception ex)
            {
                HandlePerfSessionWriteFailure(ex.GetType().Name);
            }
        }

        private static bool WritePerfEventLocked(JObject item)
        {
            return item!=null && WritePerfLineLocked(item.ToString(Formatting.None));
        }

        private static bool WritePerfLineLocked(string jsonLine)
        {
            if(_perfSessionWriter==null) return false;
            try
            {
                PerfSessionWriteFailureForTests?.Invoke();
                _perfSessionWriter.WriteLine(jsonLine);
                return true;
            }
            catch (Exception ex)
            {
                HandlePerfSessionWriteFailure(ex.GetType().Name);
                return false;
            }
        }

        private static void HandlePerfSessionWriteFailure(string reason)
        {
            string reportReason=null;
            lock (_perfFileLock)
            {
                _perfSessionActive=false;
                _perfSessionFailureReason=reason ?? "unknown";
                try { _perfSessionWriter?.Close(); } catch { }
                _perfSessionWriter=null;
                lock (_sessionQueueLock)
                {
                    _perfSessionEvents.Clear();
                }
                if(!_perfSessionFailureReported && _perfSessionFailureReason!=null)
                {
                    _perfSessionFailureReported=true;
                    reportReason=_perfSessionFailureReason;
                }
            }
            if(reportReason!=null)
            {
                try { Log("event=perf_session_disabled reason="+reportReason); }
                catch { }
            }
        }

        public static void Log(string message)
        {
            var s = _sink;
            if (s != null) { s(message); return; }

            string ts = DateTime.Now.ToString("HH:mm:ss.fff");
            string line = ts + " " + message;

            // 通道 1：文件（同步写入，AutoFlush）
            WriteToFile(line);

            // 通道 2：UI TextBox
            WriteToUi(line + Environment.NewLine);
        }

        private static void WriteToFile(string line)
        {
            if (_fileWriter == null) return;
            lock (_fileLock)
            {
                try
                {
                    _fileWriter.WriteLine(line);
                }
                catch { }
            }
        }

        private static void WriteToUi(string line)
        {
            if (_logBox == null || _form == null)
            {
                System.Diagnostics.Debug.Write(line);
                return;
            }

            if (_form.IsDisposed || _form.Disposing || _logBox.IsDisposed || _logBox.Disposing)
            {
                System.Diagnostics.Debug.Write(line);
                return;
            }

            if (!_form.IsHandleCreated || !_logBox.IsHandleCreated)
            {
                System.Diagnostics.Debug.Write(line);
                return;
            }

            if (_logBox.InvokeRequired)
            {
                try
                {
                    _logBox.BeginInvoke(new Action<string>(AppendText), line);
                }
                catch { }
            }
            else
            {
                AppendText(line);
            }
        }

        private static void AppendText(string line)
        {
            lock (_uiLock)
            {
                if (_logBox == null || _form == null) return;
                if (_form.IsDisposed || _form.Disposing || _logBox.IsDisposed || _logBox.Disposing) return;
                if (!_form.IsHandleCreated || !_logBox.IsHandleCreated) return;

                try
                {
                    if (_logBox.TextLength > 100000)
                    {
                        _logBox.Text = _logBox.Text.Substring(_logBox.TextLength - 50000);
                    }

                    _logBox.AppendText(line);
                }
                catch
                {
                    System.Diagnostics.Debug.Write(line);
                }
            }
        }

        /// <summary>关闭文件日志流。在进程退出前调用。</summary>
        public static void Shutdown()
        {
            ShutdownPerfSession();
            lock (_fileLock)
            {
                if (_fileWriter != null)
                {
                    try
                    {
                        _fileWriter.Flush();
                        _fileWriter.Close();
                    }
                    catch { }
                    _fileWriter = null;
                }
            }
        }

        private static void ShutdownPerfSession()
        {
            lock (_perfFileLock)
            {
                try {
                    if(_perfSessionWriter!=null) {
                        string[] queuedLines=DrainPerfSessionEventLines();
                        for(int i=0;i<queuedLines.Length && _perfSessionWriter!=null;i++)
                            WritePerfLineLocked(queuedLines[i]);
                        if(_perfSessionWriter!=null) {
                            var end=NewPerfEvent("session_end");
                            end["reason"]="shutdown";
                            WritePerfEventLocked(end);
                        }
                    }
                }
                catch (Exception ex) { HandlePerfSessionWriteFailure(ex.GetType().Name); }
                finally {
                    _perfSessionActive=false;
                    try { _perfSessionWriter?.Close(); } catch { }
                    _perfSessionWriter=null;
                    lock (_sessionQueueLock)
                    {
                        _perfSessionEvents.Clear();
                    }
                    _perfSessionLifecycleActive=false;
                }
                PerfSessionWriteFailureForTests=null;
            }
        }
    }
}
