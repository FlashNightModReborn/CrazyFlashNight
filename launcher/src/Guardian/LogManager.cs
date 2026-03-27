using System;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 全局日志管理器。替代 Console.WriteLine，路由到 WinForms 控件。
    /// 线程安全：跨线程调用自动 Invoke 到 UI 线程。
    /// </summary>
    public static class LogManager
    {
        private static TextBox _logBox;
        private static Form _form;
        private static readonly object _lock = new object();

        public static void Init(Form form, TextBox logBox)
        {
            _form = form;
            _logBox = logBox;
        }

        public static void Log(string message)
        {
            string line = DateTime.Now.ToString("HH:mm:ss") + " " + message + Environment.NewLine;

            if (_logBox == null || _form == null)
            {
                // fallback: 调试时写 Debug output
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
            lock (_lock)
            {
                if (_logBox == null || _logBox.IsDisposed) return;

                // 限制日志长度，防止内存膨胀
                if (_logBox.TextLength > 100000)
                {
                    _logBox.Text = _logBox.Text.Substring(_logBox.TextLength - 50000);
                }

                _logBox.AppendText(line);
            }
        }
    }
}
