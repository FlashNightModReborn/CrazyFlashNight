// UlwCommitMonitor — 计量 OverlayBase.CommitBitmap 调用频率与每次 UpdateLayeredWindow 耗时。
//
// 高配开发机上 MPO churn 不会显现为"平均帧时间高"，但会显现为我们自己 ULW 调用的 p99 尖刺：
// DWM 重配置 plane 时, 我们后续的 UpdateLayeredWindow 会被合成器内部锁/排队阻塞。
// 因此 p99(ULW commit) 是"DWM 在让我们等多久"的进程内代理指标, 不需 admin、不需 ETW。
//
// 启用时几乎零分配, 禁用时只有两次静态读 + 一次条件分支。
//
// C# 5 / net462.

using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;
using CF7Launcher.Guardian;

namespace CF7Launcher.Diagnostic
{
    public static class UlwCommitMonitor
    {
        [DllImport("kernel32.dll")]
        private static extern bool QueryPerformanceCounter(out long lpPerformanceCount);

        [DllImport("kernel32.dll")]
        private static extern bool QueryPerformanceFrequency(out long lpFrequency);

        private static long _qpcFreq = 10000000;        // fallback 100ns ticks
        private static int _enabled;                    // 0 / 1
        private static readonly object _lock = new object();
        private static List<long> _samples = new List<long>(512);
        private static System.Threading.Timer _reportTimer;
        private static int _reportIntervalSec = 5;
        private static long _totalCommits;
        private static long _lastReportedTotalCommits;
        private static long _lastReportTickQpc;
        private static int _droppedSamples;             // 锁竞争时溢出丢弃计数 (永远 < total)

        // commit hot path 上限: 单次 5s 窗口预期 < 1500 样本 (300fps * 5 * ~多 overlay), 上限 4096 防失控.
        private const int SampleHardCap = 4096;

        public static bool IsEnabled { get { return _enabled != 0; } }

        public static void Start(int reportIntervalSec)
        {
            QueryPerformanceFrequency(out _qpcFreq);
            if (_qpcFreq <= 0) _qpcFreq = 10000000;
            _reportIntervalSec = Math.Max(1, reportIntervalSec);

            long now;
            QueryPerformanceCounter(out now);
            _lastReportTickQpc = now;

            Interlocked.Exchange(ref _enabled, 1);

            // Timer 在 ThreadPool 线程触发, 不抢 UI 线程 / commit 线程
            _reportTimer = new System.Threading.Timer(
                OnTick, null,
                _reportIntervalSec * 1000,
                _reportIntervalSec * 1000);

            LogManager.Log("[UlwMonitor] started interval=" + _reportIntervalSec + "s qpcFreq=" + _qpcFreq);
        }

        public static void Stop()
        {
            Interlocked.Exchange(ref _enabled, 0);
            System.Threading.Timer t = _reportTimer;
            _reportTimer = null;
            if (t != null) { try { t.Dispose(); } catch { } }
        }

        /// <summary>commit hot path 起始时间戳; 禁用时返回 0 (RecordCommit 会跳过).</summary>
        public static long StartTick()
        {
            if (_enabled == 0) return 0;
            long t;
            QueryPerformanceCounter(out t);
            return t;
        }

        /// <summary>commit hot path 结束: 记录耗时 (QPC tick). startTick==0 时短路.</summary>
        public static void RecordCommit(long startTick)
        {
            if (_enabled == 0 || startTick == 0) return;
            long endTick;
            QueryPerformanceCounter(out endTick);
            long elapsed = endTick - startTick;
            if (elapsed < 0) elapsed = 0;  // 罕见: 跨核 QPC 漂移

            lock (_lock)
            {
                _totalCommits++;
                if (_samples.Count < SampleHardCap)
                    _samples.Add(elapsed);
                else
                    _droppedSamples++;
            }
        }

        private static void OnTick(object _)
        {
            List<long> snapshot;
            long totalDelta;
            int dropped;
            long nowQpc;
            QueryPerformanceCounter(out nowQpc);
            long elapsedTicks;

            lock (_lock)
            {
                snapshot = _samples;
                _samples = new List<long>(snapshot.Count > 0 ? snapshot.Count : 64);
                totalDelta = _totalCommits - _lastReportedTotalCommits;
                _lastReportedTotalCommits = _totalCommits;
                dropped = _droppedSamples;
                _droppedSamples = 0;
                elapsedTicks = nowQpc - _lastReportTickQpc;
                _lastReportTickQpc = nowQpc;
            }

            double elapsedSec = elapsedTicks > 0 ? (double)elapsedTicks / _qpcFreq : _reportIntervalSec;
            if (elapsedSec <= 0) elapsedSec = _reportIntervalSec;

            if (snapshot.Count == 0)
            {
                LogManager.Log("[UlwMonitor] " + elapsedSec.ToString("F1") + "s no commits");
                return;
            }

            snapshot.Sort();
            double tickToMs = 1000.0 / _qpcFreq;
            double p50 = snapshot[snapshot.Count / 2] * tickToMs;
            double p95 = snapshot[Math.Min(snapshot.Count - 1, (snapshot.Count * 95) / 100)] * tickToMs;
            double p99 = snapshot[Math.Min(snapshot.Count - 1, (snapshot.Count * 99) / 100)] * tickToMs;
            double max = snapshot[snapshot.Count - 1] * tickToMs;
            double commitsPerSec = totalDelta / elapsedSec;

            string line = "[UlwMonitor] " + elapsedSec.ToString("F1") + "s"
                + " commits=" + totalDelta
                + " (" + commitsPerSec.ToString("F1") + "/s)"
                + " p50=" + p50.ToString("F2") + "ms"
                + " p95=" + p95.ToString("F2") + "ms"
                + " p99=" + p99.ToString("F2") + "ms"
                + " max=" + max.ToString("F2") + "ms";
            if (dropped > 0) line += " dropped=" + dropped;
            LogManager.Log(line);
        }
    }
}
