// DwmEtwMonitor — raw P/Invoke ETW 实时 consumer, 订阅 DWM 相关 provider 并按秒计数事件。
//
// 用途: 在高配开发机上仍能看见 MPO churn / DWM 重配置事件频次。
// 平均帧时间在高配机上被压平, 但 churn 事件计数对硬件强弱不敏感 (它是事件驱动的), 因此
// 在你这台机器上 B0 前后对比也能看出"事件频次降了"的信号。
//
// 权限: ETW 实时会话需要 admin 或 Performance Log Users 成员。非 admin 启动直接 log warn + skip。
// 不影响 launcher 主流程; 失败安全降级。
//
// 注意: 这是一个"事件计数器"。不解析 EVENT_RECORD payload, 只 ++counter, 因此 callback 极轻量。
//       若以后要细分 plane state change vs present completed, 在 OnEventRecord 里加 payload 解析即可。
//
// C# 5 / net462.

using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Threading;
using CF7Launcher.Guardian;

namespace CF7Launcher.Diagnostic
{
    public static class DwmEtwMonitor
    {
        // ====== Provider GUIDs ======
        // Microsoft-Windows-Dwm-Core — DWM 合成器核心活动 (DwmPresentSurface / DwmFlipChain / DwmFrameEvent ...)
        public static readonly Guid DwmCoreProvider = new Guid("9E9BBA3C-2E38-40CB-99F4-9E8281425164");
        // Microsoft-Windows-DxgKrnl — DXGI/DXGK kernel 事件, 含 MPO plane state. 需 admin。
        public static readonly Guid DxgKrnlProvider = new Guid("802ec45a-1e99-4b83-9920-87c98277ba9d");

        // ====== ETW 常量 ======
        private const uint EVENT_TRACE_REAL_TIME_MODE       = 0x00000100;
        private const uint PROCESS_TRACE_MODE_REAL_TIME     = 0x00000100;
        private const uint PROCESS_TRACE_MODE_EVENT_RECORD  = 0x10000000;
        private const uint EVENT_TRACE_CONTROL_STOP         = 1;
        private const uint EVENT_CONTROL_CODE_ENABLE_PROVIDER  = 1;
        private const uint EVENT_CONTROL_CODE_DISABLE_PROVIDER = 0;
        private const int  WNODE_FLAG_TRACED_GUID            = 0x00020000;
        private const byte TRACE_LEVEL_INFORMATION           = 4;
        private const ulong MATCH_ANY_KEYWORD                = 0xFFFFFFFFFFFFFFFFul;

        private const int ERROR_SUCCESS         = 0;
        private const int ERROR_ALREADY_EXISTS  = 183;
        private const int ERROR_ACCESS_DENIED   = 5;
        private const int ERROR_INVALID_HANDLE  = 6;
        private const int ERROR_CANCELLED       = 1223;

        // INVALID_PROCESSTRACE_HANDLE: 32-bit = 0x00000000FFFFFFFF, 64-bit = 0xFFFFFFFFFFFFFFFF
        private static readonly ulong INVALID_TRACE_HANDLE =
            IntPtr.Size == 8 ? 0xFFFFFFFFFFFFFFFFul : 0x00000000FFFFFFFFul;

        private const int LoggerNameMaxBytes = 1024;
        private const int LogFileNameMaxBytes = 1024;

        private const string SessionName = "CF7ME-Diag-DWM";

        // ====== P/Invoke ======
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
        private static extern uint StartTraceW(out ulong TraceHandle, string InstanceName, IntPtr Properties);

        [DllImport("advapi32.dll", SetLastError = false)]
        private static extern uint EnableTraceEx2(
            ulong TraceHandle, ref Guid ProviderId, uint ControlCode,
            byte Level, ulong MatchAnyKeyword, ulong MatchAllKeyword,
            uint Timeout, IntPtr EnableParameters);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
        private static extern ulong OpenTraceW(ref EVENT_TRACE_LOGFILEW Logfile);

        [DllImport("advapi32.dll", SetLastError = false)]
        private static extern uint ProcessTrace(ulong[] HandleArray, uint HandleCount, IntPtr StartTime, IntPtr EndTime);

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
        private static extern uint ControlTraceW(ulong TraceHandle, string InstanceName, IntPtr Properties, uint ControlCode);

        [DllImport("advapi32.dll", SetLastError = false)]
        private static extern uint CloseTrace(ulong TraceHandle);

        [DllImport("kernel32.dll")]
        private static extern bool QueryPerformanceCounter(out long lpPerformanceCount);

        [DllImport("kernel32.dll")]
        private static extern bool QueryPerformanceFrequency(out long lpFrequency);

        // ====== Native structs (按 evntrace.h 布局) ======

        [StructLayout(LayoutKind.Sequential)]
        private struct WNODE_HEADER
        {
            public uint BufferSize;
            public uint ProviderId;
            public ulong HistoricalContext;
            public long TimeStamp;
            public Guid Guid;
            public uint ClientContext;
            public uint Flags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct EVENT_TRACE_PROPERTIES
        {
            public WNODE_HEADER Wnode;
            public uint BufferSize;          // KB per buffer
            public uint MinimumBuffers;
            public uint MaximumBuffers;
            public uint MaximumFileSize;
            public uint LogFileMode;
            public uint FlushTimer;
            public uint EnableFlags;
            public int AgeLimit;
            public uint NumberOfBuffers;
            public uint FreeBuffers;
            public uint EventsLost;
            public uint BuffersWritten;
            public uint LogBuffersLost;
            public uint RealTimeBuffersLost;
            public IntPtr LoggerThreadId;
            public uint LogFileNameOffset;
            public uint LoggerNameOffset;
        }

        // !!! CRITICAL LAYOUT CONSTRAINT !!!
        // 之前的实现按字段拼凑只算出 248 字节, 而 Windows TRACE_LOGFILE_HEADER 在 x64 是 280 字节,
        // 32 字节差让后面的 BufferCallback / EventRecordCallback 在 EVENT_TRACE_LOGFILEW 里全部错位 →
        // kernel 读到的 callback 是垃圾函数指针 → 进程在 first DWM event 时 access violation 直接死。
        // 体现: admin session 启用 ETW 后 1-4s 内必死, 无 .NET 异常, 无 shutdown 日志。
        //
        // 修复方式: 用 Size 属性强制 marshalled 大小为 Windows 真值, 内部字段只留一个供文档,
        // 这块 OpenTrace 会 in/out 填, 我们从不读取, 所以字段对不对齐不重要; 总大小对得上就够。
        // 280 是 x64 的真值, x86 是 268; 用 280 在两个平台上都至少 = 真值, 不会让后续字段提前。
        [StructLayout(LayoutKind.Sequential, Size = 280)]
        private struct TRACE_LOGFILE_HEADER
        {
            public uint BufferSize;  // 仅留一个字段做文档锚; 其余 OpenTrace 写入, 我们不读
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct EVENT_TRACE_HEADER_PLACEHOLDER
        {
            public ushort Size; public ushort FieldTypeFlags;
            public uint Version;
            public uint ThreadId; public uint ProcessId;
            public long TimeStamp;
            public Guid Guid;
            public uint KernelTime; public uint UserTime;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct EVENT_TRACE_PLACEHOLDER
        {
            public EVENT_TRACE_HEADER_PLACEHOLDER Header;
            public uint InstanceId;
            public uint ParentInstanceId;
            public Guid ParentGuid;
            public IntPtr MofData;
            public uint MofLength;
            public uint ClientContext;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct EVENT_TRACE_LOGFILEW
        {
            [MarshalAs(UnmanagedType.LPWStr)] public string LogFileName;
            [MarshalAs(UnmanagedType.LPWStr)] public string LoggerName;
            public long CurrentTime;
            public uint BuffersRead;
            public uint LogFileMode;   // union with ProcessTraceMode
            public EVENT_TRACE_PLACEHOLDER CurrentEvent;
            public TRACE_LOGFILE_HEADER LogfileHeader;
            public IntPtr BufferCallback;
            public uint BufferSize;
            public uint Filled;
            public uint EventsLost;
            public IntPtr EventRecordCallback;  // union with EventCallback
            public uint IsKernelTrace;
            public IntPtr Context;
        }

        // EVENT_RECORD callback signature
        private delegate void EventRecordCallback(IntPtr eventRecord);

        // ====== 状态 ======
        private static int _started;                       // 0 / 1
        private static long _eventCount;                   // 跨线程累加 (callback 写 / timer 读)
        private static long _lastReportedCount;
        private static ulong _sessionHandle;
        private static ulong _consumerHandle = INVALID_TRACE_HANDLE_STATIC();
        private static IntPtr _propertiesBuffer = IntPtr.Zero;
        private static int _propertiesBufferSize;
        private static Thread _consumerThread;
        private static EventRecordCallback _callback;      // 保持引用防 GC
        private static GCHandle _callbackPin;
        private static System.Threading.Timer _reportTimer;
        private static int _reportIntervalSec = 5;
        private static long _qpcFreq = 10000000;
        private static long _lastReportQpc;
        private static Guid _enabledProvider;
        private static string _enabledProviderName;

        private static ulong INVALID_TRACE_HANDLE_STATIC()
        {
            return IntPtr.Size == 8 ? 0xFFFFFFFFFFFFFFFFul : 0x00000000FFFFFFFFul;
        }

        public static bool IsRunning { get { return _started != 0; } }
        public static long EventCount { get { return Interlocked.Read(ref _eventCount); } }

        /// <summary>检查当前进程是否以 Administrator 角色运行。</summary>
        public static bool IsElevated()
        {
            try
            {
                using (WindowsIdentity id = WindowsIdentity.GetCurrent())
                {
                    WindowsPrincipal principal = new WindowsPrincipal(id);
                    return principal.IsInRole(WindowsBuiltInRole.Administrator);
                }
            }
            catch { return false; }
        }

        /// <summary>
        /// 启动 ETW 实时会话, 订阅指定 provider (默认 Microsoft-Windows-Dwm-Core).
        /// 返回 true = 启动成功; false = 无权限 / 启动失败 (日志已写)。
        /// </summary>
        public static bool Start(Guid provider, string providerNameForLog, int reportIntervalSec)
        {
            if (Interlocked.CompareExchange(ref _started, 1, 0) != 0)
            {
                LogManager.Log("[EtwMpo] already started, skipping");
                return false;
            }

            if (!IsElevated())
            {
                LogManager.Log("[EtwMpo] requires Administrator (process not elevated) — ETW listener skipped");
                Interlocked.Exchange(ref _started, 0);
                return false;
            }

            _reportIntervalSec = Math.Max(1, reportIntervalSec);
            _enabledProvider = provider;
            _enabledProviderName = providerNameForLog ?? provider.ToString();
            QueryPerformanceFrequency(out _qpcFreq);
            if (_qpcFreq <= 0) _qpcFreq = 10000000;
            QueryPerformanceCounter(out _lastReportQpc);

            // 结构体大小 sanity check — 上一轮 bug 因 TRACE_LOGFILE_HEADER 短了 32 字节, EventRecordCallback
            // 错位导致 kernel 调垃圾指针. 现在 sized fix 后, 这条日志能让任何后续布局漂移立即被发现。
            int sLogfile = Marshal.SizeOf(typeof(EVENT_TRACE_LOGFILEW));
            int sHeader  = Marshal.SizeOf(typeof(TRACE_LOGFILE_HEADER));
            int sEvent   = Marshal.SizeOf(typeof(EVENT_TRACE_PLACEHOLDER));
            LogManager.Log("[EtwMpo] struct sizes: EVENT_TRACE_LOGFILEW=" + sLogfile
                + " TRACE_LOGFILE_HEADER=" + sHeader
                + " EVENT_TRACE=" + sEvent
                + " (expected x64: 448 / 280 / 88)");

            try
            {
                if (!StartSession()) { Cleanup(); Interlocked.Exchange(ref _started, 0); return false; }
                if (!EnableProvider()) { Cleanup(); Interlocked.Exchange(ref _started, 0); return false; }
                if (!OpenConsumer()) { Cleanup(); Interlocked.Exchange(ref _started, 0); return false; }
            }
            catch (Exception ex)
            {
                LogManager.Log("[EtwMpo] start exception: " + ex.GetType().Name + " " + ex.Message);
                Cleanup();
                Interlocked.Exchange(ref _started, 0);
                return false;
            }

            // 消费线程: ProcessTrace 阻塞直到 CloseTrace 触发其退出
            _consumerThread = new Thread(ConsumerThreadProc);
            _consumerThread.IsBackground = true;
            _consumerThread.Name = "CF7ME-EtwConsumer";
            _consumerThread.Start();

            _reportTimer = new System.Threading.Timer(
                OnReportTick, null,
                _reportIntervalSec * 1000,
                _reportIntervalSec * 1000);

            LogManager.Log("[EtwMpo] started provider=" + _enabledProviderName
                + " interval=" + _reportIntervalSec + "s session=" + SessionName);
            return true;
        }

        /// <summary>关闭 ETW 会话, 等待消费线程退出。安全可重入。</summary>
        public static void Stop()
        {
            if (Interlocked.CompareExchange(ref _started, 0, 1) != 1) return;

            System.Threading.Timer rt = _reportTimer;
            _reportTimer = null;
            if (rt != null) { try { rt.Dispose(); } catch { } }

            // 1) DisableProvider (best-effort) — 不强制成功
            try
            {
                Guid p = _enabledProvider;
                EnableTraceEx2(_sessionHandle, ref p, EVENT_CONTROL_CODE_DISABLE_PROVIDER,
                    TRACE_LEVEL_INFORMATION, MATCH_ANY_KEYWORD, 0, 0, IntPtr.Zero);
            }
            catch { }

            // 2) CloseTrace consumer handle → 让 ProcessTrace 返回
            ulong consumer = _consumerHandle;
            if (consumer != INVALID_TRACE_HANDLE)
            {
                try { CloseTrace(consumer); } catch { }
                _consumerHandle = INVALID_TRACE_HANDLE;
            }

            // 3) ControlTrace STOP — 真正停掉 session
            if (_sessionHandle != 0 && _propertiesBuffer != IntPtr.Zero)
            {
                try
                {
                    ControlTraceW(_sessionHandle, SessionName, _propertiesBuffer, EVENT_TRACE_CONTROL_STOP);
                }
                catch { }
            }

            // 4) Join consumer 线程 (有 timeout 兜底)
            Thread ct = _consumerThread;
            _consumerThread = null;
            if (ct != null)
            {
                try { ct.Join(2000); } catch { }
            }

            Cleanup();
            LogManager.Log("[EtwMpo] stopped totalEvents=" + Interlocked.Read(ref _eventCount));
        }

        private static void Cleanup()
        {
            if (_propertiesBuffer != IntPtr.Zero)
            {
                try { Marshal.FreeHGlobal(_propertiesBuffer); } catch { }
                _propertiesBuffer = IntPtr.Zero;
            }
            if (_callbackPin.IsAllocated)
            {
                try { _callbackPin.Free(); } catch { }
            }
            _callback = null;
            _sessionHandle = 0;
            _consumerHandle = INVALID_TRACE_HANDLE;
        }

        private static bool StartSession()
        {
            int propsSize = Marshal.SizeOf(typeof(EVENT_TRACE_PROPERTIES));
            int totalSize = propsSize + LoggerNameMaxBytes + LogFileNameMaxBytes;
            _propertiesBuffer = Marshal.AllocHGlobal(totalSize);
            _propertiesBufferSize = totalSize;
            // zero-fill
            for (int i = 0; i < totalSize; i += 8) Marshal.WriteInt64(_propertiesBuffer, i, 0);

            EVENT_TRACE_PROPERTIES props = new EVENT_TRACE_PROPERTIES();
            props.Wnode.BufferSize = (uint)totalSize;
            props.Wnode.Guid = Guid.NewGuid();
            props.Wnode.ClientContext = 1;  // QueryPerformanceCounter clock
            props.Wnode.Flags = WNODE_FLAG_TRACED_GUID;
            props.BufferSize = 64;          // 64 KB per buffer (默认值, 高频 provider 防丢)
            props.MinimumBuffers = 4;
            props.MaximumBuffers = 64;
            props.LogFileMode = EVENT_TRACE_REAL_TIME_MODE;
            props.FlushTimer = 1;           // 1s flush, 减少 callback 延迟
            props.LoggerNameOffset = (uint)propsSize;
            props.LogFileNameOffset = (uint)(propsSize + LoggerNameMaxBytes);

            Marshal.StructureToPtr(props, _propertiesBuffer, false);

            ulong handle;
            uint err = StartTraceW(out handle, SessionName, _propertiesBuffer);
            if (err == ERROR_ALREADY_EXISTS)
            {
                // 上次进程崩溃残留 — stop 再 start
                ControlTraceW(0, SessionName, _propertiesBuffer, EVENT_TRACE_CONTROL_STOP);
                // 重新填一遍 properties (ControlTrace 会改写)
                for (int i = 0; i < totalSize; i += 8) Marshal.WriteInt64(_propertiesBuffer, i, 0);
                Marshal.StructureToPtr(props, _propertiesBuffer, false);
                err = StartTraceW(out handle, SessionName, _propertiesBuffer);
            }
            if (err != ERROR_SUCCESS)
            {
                LogManager.Log("[EtwMpo] StartTraceW failed err=" + err
                    + (err == ERROR_ACCESS_DENIED ? " (ACCESS_DENIED — non-admin?)" : ""));
                return false;
            }
            _sessionHandle = handle;
            return true;
        }

        private static bool EnableProvider()
        {
            Guid p = _enabledProvider;
            uint err = EnableTraceEx2(_sessionHandle, ref p,
                EVENT_CONTROL_CODE_ENABLE_PROVIDER,
                TRACE_LEVEL_INFORMATION,
                MATCH_ANY_KEYWORD, 0, 0, IntPtr.Zero);
            if (err != ERROR_SUCCESS)
            {
                LogManager.Log("[EtwMpo] EnableTraceEx2 failed err=" + err);
                return false;
            }
            return true;
        }

        private static bool OpenConsumer()
        {
            _callback = new EventRecordCallback(OnEventRecord);
            _callbackPin = GCHandle.Alloc(_callback);

            EVENT_TRACE_LOGFILEW lf = new EVENT_TRACE_LOGFILEW();
            lf.LoggerName = SessionName;
            lf.LogFileName = null;
            lf.LogFileMode = PROCESS_TRACE_MODE_REAL_TIME | PROCESS_TRACE_MODE_EVENT_RECORD;
            lf.EventRecordCallback = Marshal.GetFunctionPointerForDelegate(_callback);

            ulong h = OpenTraceW(ref lf);
            if (h == INVALID_TRACE_HANDLE)
            {
                LogManager.Log("[EtwMpo] OpenTraceW returned INVALID_HANDLE");
                return false;
            }
            _consumerHandle = h;
            return true;
        }

        private static void ConsumerThreadProc()
        {
            ulong[] handles = new ulong[] { _consumerHandle };
            try
            {
                uint rc = ProcessTrace(handles, 1, IntPtr.Zero, IntPtr.Zero);
                // CANCELLED / INVALID_HANDLE = 正常退出 (Stop 调 CloseTrace)
                if (rc != ERROR_SUCCESS && rc != ERROR_CANCELLED && rc != ERROR_INVALID_HANDLE)
                    LogManager.Log("[EtwMpo] ProcessTrace returned " + rc);
            }
            catch (Exception ex)
            {
                LogManager.Log("[EtwMpo] ProcessTrace threw: " + ex.GetType().Name + " " + ex.Message);
            }
        }

        // ETW 回调 — hot path, 必须极轻量. 不解析 payload, 只 ++counter.
        private static void OnEventRecord(IntPtr eventRecord)
        {
            Interlocked.Increment(ref _eventCount);
        }

        private static void OnReportTick(object _)
        {
            if (_started == 0) return;
            long now = Interlocked.Read(ref _eventCount);
            long delta = now - _lastReportedCount;
            _lastReportedCount = now;

            long nowQpc;
            QueryPerformanceCounter(out nowQpc);
            double elapsedSec = (double)(nowQpc - _lastReportQpc) / _qpcFreq;
            _lastReportQpc = nowQpc;
            if (elapsedSec <= 0) elapsedSec = _reportIntervalSec;

            double ratePerSec = delta / elapsedSec;
            LogManager.Log("[EtwMpo] " + elapsedSec.ToString("F1") + "s"
                + " provider=" + _enabledProviderName
                + " events=" + delta
                + " (" + ratePerSec.ToString("F1") + "/s)"
                + " total=" + now);
        }
    }
}
