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

        public event Action OnFlashExited;

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
            int exitCode = -1;
            TimeSpan uptime = TimeSpan.Zero;
            lock (_lock)
            {
                if (_flashProcess == null) return;
                try { exitCode = _flashProcess.ExitCode; } catch { }
                try { uptime = DateTime.Now - _flashProcess.StartTime; } catch { }
            }

            LogManager.Log("[Guardian] Flash Player exited, code=" + exitCode
                + ", uptime=" + uptime.TotalSeconds.ToString("F1") + "s");

            if (uptime.TotalSeconds < 5)
            {
                LogManager.Log("[Guardian] WARNING: Flash exited within 5 seconds, possible crash.");
            }

            Action handler = OnFlashExited;
            if (handler != null)
                handler();
        }

        /// <summary>
        /// 终结 Flash 进程。在 DoExit() 中 Application.ExitThread() 之前调用。
        /// 线程安全，可多次调用。不 Dispose Process 对象（由 Dispose() 负责）。
        /// </summary>
        public void KillFlash()
        {
            lock (_lock)
            {
                if (_flashProcess == null) return;
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
            }
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
