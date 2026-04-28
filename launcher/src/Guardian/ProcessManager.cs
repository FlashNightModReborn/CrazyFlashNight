using System;
using System.Diagnostics;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 启动并监控 Flash Player SA 进程。
    /// Flash 退出时通知守护进程清理退出。
    /// </summary>
    public class ProcessManager : IDisposable
    {
        private Process _flashProcess;
        private readonly object _lock = new object();
        private readonly string _flashPlayerPath;
        private readonly string _swfPath;
        private readonly DateTime _startTime;

        /// <summary>
        /// Phase 1d：事件携带退出的 Process 引用（二重防御，订阅方可识别是否为当前 attempt 的进程）。
        /// </summary>
        public event Action<Process> OnFlashExited;

        public Process FlashProcess { get { lock (_lock) { return _flashProcess; } } }

        public ProcessManager(string flashPlayerPath, string swfPath)
        {
            _flashPlayerPath = flashPlayerPath;
            _swfPath = swfPath;
            _startTime = DateTime.MinValue;
        }

        public bool Start()
        {
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = _flashPlayerPath;
                psi.Arguments = "\"" + _swfPath + "\"";
                psi.UseShellExecute = false;

                lock (_lock)
                {
                    _flashProcess = Process.Start(psi);
                    if (_flashProcess == null)
                        return false;

                    _flashProcess.EnableRaisingEvents = true;
                    _flashProcess.Exited += OnProcessExited;
                }

                LogManager.Log("[Guardian] Flash Player started, PID=" + _flashProcess.Id);
                return true;
            }
            catch (Exception ex)
            {
                LogManager.Log("[Guardian] Failed to start Flash Player: " + ex.Message);
                return false;
            }
        }

        private void OnProcessExited(object sender, EventArgs e)
        {
            Process exited = sender as Process;
            int exitCode = -1;
            TimeSpan uptime = TimeSpan.Zero;

            // Phase 1d：sender 校验——仅当 sender 是当前追踪的 _flashProcess 才传播事件。
            // 防止：retry 场景下旧 Flash 的 Exited 事件晚到、串入新 attempt 的状态机。
            lock (_lock)
            {
                if (_flashProcess == null) return;
                if (!object.ReferenceEquals(exited, _flashProcess))
                {
                    LogManager.Log("[Guardian] Flash Exited from stale process, ignored (pid="
                        + (exited != null ? exited.Id.ToString() : "null") + ")");
                    return;
                }
                try { exitCode = _flashProcess.ExitCode; } catch { }
                try { uptime = DateTime.Now - _flashProcess.StartTime; } catch { }
            }

            LogManager.Log("[Guardian] Flash Player exited, code=" + exitCode
                + ", uptime=" + uptime.TotalSeconds.ToString("F1") + "s");

            if (uptime.TotalSeconds < 5)
            {
                LogManager.Log("[Guardian] WARNING: Flash exited within 5 seconds, possible crash.");
            }

            Action<Process> handler = OnFlashExited;
            if (handler != null)
                handler(exited);
        }

        /// <summary>
        /// 终结 Flash 进程。在 DoExit() 中 Application.ExitThread() 之前调用。
        /// 线程安全，可多次调用。不 Dispose Process 对象（由 Dispose() 负责）。
        /// </summary>
        public void KillFlash()
        {
            Process target;
            lock (_lock)
            {
                target = _flashProcess;
            }
            if (target == null) return;
            try
            {
                if (!target.HasExited)
                {
                    target.CloseMainWindow();
                    if (!target.WaitForExit(500))
                    {
                        target.Kill();
                        try { target.WaitForExit(1000); } catch { }
                    }
                }
            }
            catch { }
        }

        public void Dispose()
        {
            lock (_lock)
            {
                if (_flashProcess != null)
                {
                    try
                    {
                        if (!_flashProcess.HasExited)
                        {
                            _flashProcess.CloseMainWindow();
                            if (!_flashProcess.WaitForExit(3000))
                                _flashProcess.Kill();
                        }
                    }
                    catch { }
                    _flashProcess.Dispose();
                    _flashProcess = null;
                }
            }
        }
    }
}
