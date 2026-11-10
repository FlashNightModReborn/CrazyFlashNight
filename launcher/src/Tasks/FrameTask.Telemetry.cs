using System;
using System.Threading;
using CF7Launcher.Bus;
using CF7Launcher.Guardian;

namespace CF7Launcher.Tasks
{
    public partial class FrameTask
    {
        private readonly object _perfTelemetryWriteLock = new object();
        private Timer _perfTelemetryTimer;
        private int _perfTelemetryCallbackActive;
        private int _perfTelemetryStopped;
        private int _perfTelemetryFaultReported;

        private void StartPerfTelemetry()
        {
            if (Volatile.Read(ref _perfTelemetryStopped) != 0) return;
            var timer = new Timer(_ => SamplePerfTelemetry(), null, 1000, 1000);
            if (Interlocked.CompareExchange(ref _perfTelemetryTimer, timer, null) != null)
                timer.Dispose();
        }

        private void StopPerfTelemetry()
        {
            if (Interlocked.Exchange(ref _perfTelemetryStopped, 1) != 0) return;
            Timer timer = Interlocked.Exchange(ref _perfTelemetryTimer, null);
            timer?.Dispose();
            lock (_perfTelemetryWriteLock) { }
        }

        private void SamplePerfTelemetry()
        {
            if (Volatile.Read(ref _perfTelemetryStopped) != 0) return;
            if (Interlocked.Exchange(ref _perfTelemetryCallbackActive, 1) != 0) return;
            try
            {
                if (Volatile.Read(ref _perfTelemetryStopped) != 0) return;
                XmlSocketServer socket = _socket;
                PerfTransportSnapshot transport = socket == null
                    ? default : socket.CapturePerfTransportSnapshot();
                PerfTelemetrySnapshot snapshot = _fpsBuffer.CapturePerfTelemetry(transport);
                // Activation is a Host fact even when no new F/source sample arrives.
                snapshot.Foreground = _decisionEngine?.CurrentPerfForeground;
                lock (_perfTelemetryWriteLock)
                {
                    if (Volatile.Read(ref _perfTelemetryStopped) != 0) return;
                    LogManager.WritePerfSessionSample(snapshot);
                }
            }
            catch (Exception ex)
            {
                if (Interlocked.Exchange(ref _perfTelemetryFaultReported, 1) == 0)
                {
                    try { LogManager.Log("event=perf_telemetry_disabled type=" + ex.GetType().Name); }
                    catch { }
                }
            }
            finally
            {
                Volatile.Write(ref _perfTelemetryCallbackActive, 0);
            }
        }

        internal Newtonsoft.Json.Linq.JObject CaptureIssue205State()
        {
            var transport = _socket == null ? default : _socket.CapturePerfTransportSnapshot();
            var s = _fpsBuffer.CapturePerfTelemetry(transport);
            return new Newtonsoft.Json.Linq.JObject {
                ["connectionGeneration"] = s.ConnectionGeneration, ["hostFrameOrdinal"] = s.HostFrameOrdinal,
                ["sourceScene"] = s.SourceScene, ["sourceSampleSequence"] = s.SourceSampleSequence,
                ["sourceSampleHostFrame"] = s.SampleFrame, ["sourceStalenessFrames"] = s.StalenessFrames,
                ["sourceSampleAgeMs"] = s.SampleAgeMs, ["acceptedHostFrame"] = s.AcceptedSampleFrame,
                ["acceptedStalenessFrames"] = s.AcceptedStalenessFrames, ["acceptedAgeMs"] = s.AcceptedSampleAgeMs,
                ["frameIngressAgeMs"] = s.FrameIngressAgeMs, ["transportAgeMs"] = s.TransportAgeMs,
                ["inboundMessages"] = s.InboundCount, ["sourceFps"] = s.SourceFps, ["acceptedFps"] = s.AcceptedFps,
                ["sampleRejectReason"] = s.SampleRejectReason, ["paused"] = s.Paused,
                ["foreground"] = _decisionEngine?.CurrentPerfForeground, ["surfaceGate"] = s.SurfaceGate,
                ["connected"] = s.Connected
            };
        }
        internal void SamplePerfTelemetryForTests() => SamplePerfTelemetry();
    }
}
