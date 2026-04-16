using System;
using System.IO;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 全局日志管理器。双通道输出：
    /// 1. WinForms TextBox（运行时查看）
    /// 2. 磁盘文件（持久化，进程退出后可查）
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
        private static string _logFilePath;

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
            SetupFileLog(projectRoot);
        }

        private static void SetupFileLog(string projectRoot)
        {
            try
            {
                string logDir = Path.Combine(projectRoot, "logs");
                if (!Directory.Exists(logDir))
                    Directory.CreateDirectory(logDir);

                _logFilePath = Path.Combine(logDir, "launcher.log");

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

        public static void Log(string message)
        {
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
                if (_logBox == null || _logBox.IsDisposed) return;

                if (_logBox.TextLength > 100000)
                {
                    _logBox.Text = _logBox.Text.Substring(_logBox.TextLength - 50000);
                }

                _logBox.AppendText(line);
            }
        }

        /// <summary>关闭文件日志流。在进程退出前调用。</summary>
        public static void Shutdown()
        {
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
    }
}
