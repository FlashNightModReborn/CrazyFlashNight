// LayerAuditDump — 当前进程所有顶级 HWND 的结构性快照。
// 目的：给"我们到底拥有几个顶级 layered 窗口"这个数字一个 deterministic、PR 前后可对比的来源。
// 不依赖 admin / ETW / 性能采样；高配开发机上看不出性能差，也能看出 5→2 的结构差。
// C# 5 / net462。

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Forms;
using CF7Launcher.Guardian;

namespace CF7Launcher.Diagnostic
{
    public static class LayerAuditDump
    {
        #region Win32
        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetClassNameW(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern int GetWindowTextW(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern int GetWindowTextLengthW(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true, EntryPoint = "GetWindowLongW")]
        private static extern int GetWindowLong32(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true, EntryPoint = "GetWindowLongPtrW")]
        private static extern IntPtr GetWindowLongPtr64(IntPtr hWnd, int nIndex);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern IntPtr GetParent(IntPtr hWnd);

        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        private const int GWL_STYLE = -16;
        private const int GWL_EXSTYLE = -20;

        [StructLayout(LayoutKind.Sequential)]
        private struct RECT { public int Left, Top, Right, Bottom; }
        #endregion

        // 关心的 ex-style 位
        private const int WS_EX_LAYERED             = 0x00080000;
        private const int WS_EX_TRANSPARENT         = 0x00000020;
        private const int WS_EX_TOOLWINDOW          = 0x00000080;
        private const int WS_EX_NOACTIVATE          = 0x08000000;
        private const int WS_EX_TOPMOST             = 0x00000008;
        private const int WS_EX_NOREDIRECTIONBITMAP = 0x00200000;

        // style 位（参考用）
        private const int WS_CHILD   = 0x40000000;

        private struct WindowInfo
        {
            public IntPtr Handle;
            public string ClassName;
            public string Title;
            public int Style;
            public int ExStyle;
            public bool Visible;
            public IntPtr Parent;
            public RECT Bounds;
        }

        private static int GetExStyle(IntPtr hWnd)
        {
            if (IntPtr.Size == 8)
                return (int)GetWindowLongPtr64(hWnd, GWL_EXSTYLE).ToInt64();
            return GetWindowLong32(hWnd, GWL_EXSTYLE);
        }

        private static int GetStyle(IntPtr hWnd)
        {
            if (IntPtr.Size == 8)
                return (int)GetWindowLongPtr64(hWnd, GWL_STYLE).ToInt64();
            return GetWindowLong32(hWnd, GWL_STYLE);
        }

        /// <summary>
        /// 枚举当前进程所有顶级窗口并写入 LogManager。
        /// reason: 标识本次 dump 的触发点 ("startup" / "post-ready" / "on-demand" 等)。
        /// 返回 layered 顶级窗口数量（方便调用方直接对比）。
        /// </summary>
        public static int DumpToLog(string reason)
        {
            List<WindowInfo> list;
            try { list = Collect(); }
            catch (Exception ex)
            {
                LogManager.Log("[LayerAudit] collect failed: " + ex.Message);
                return -1;
            }

            int layered = 0;
            int visibleLayered = 0;
            for (int i = 0; i < list.Count; i++)
            {
                if ((list[i].ExStyle & WS_EX_LAYERED) != 0)
                {
                    layered++;
                    if (list[i].Visible) visibleLayered++;
                }
            }

            LogManager.Log(
                "[LayerAudit] reason=" + (reason ?? "?")
                + " pid=" + Process.GetCurrentProcess().Id
                + " toplevel=" + list.Count
                + " layered=" + layered
                + " layered_visible=" + visibleLayered);

            for (int i = 0; i < list.Count; i++)
            {
                WindowInfo w = list[i];
                string flags = DecodeExStyle(w.ExStyle);
                int width = w.Bounds.Right - w.Bounds.Left;
                int height = w.Bounds.Bottom - w.Bounds.Top;
                string managed = TryGetManagedFormName(w.Handle);
                LogManager.Log(
                    "[LayerAudit]   #" + (i + 1).ToString("D2")
                    + " hwnd=0x" + w.Handle.ToInt64().ToString("X")
                    + " cls=" + (w.ClassName ?? "")
                    + " title=" + Quote(w.Title)
                    + " vis=" + (w.Visible ? "Y" : "N")
                    + " ex=" + flags
                    + " pos=" + w.Bounds.Left + "," + w.Bounds.Top
                    + " size=" + width + "x" + height
                    + " mfn=" + (managed ?? "-"));
            }

            return layered;
        }

        /// <summary>
        /// 仅返回 layered 顶级窗口数量（不写日志，供监控/对比代码静默查询）。
        /// </summary>
        public static int CountLayeredToplevel()
        {
            try
            {
                List<WindowInfo> list = Collect();
                int n = 0;
                for (int i = 0; i < list.Count; i++)
                    if ((list[i].ExStyle & WS_EX_LAYERED) != 0) n++;
                return n;
            }
            catch { return -1; }
        }

        private static List<WindowInfo> Collect()
        {
            uint myPid = (uint)Process.GetCurrentProcess().Id;
            List<WindowInfo> result = new List<WindowInfo>(32);

            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam)
            {
                uint pid;
                GetWindowThreadProcessId(hWnd, out pid);
                if (pid != myPid) return true;

                WindowInfo info = new WindowInfo();
                info.Handle = hWnd;
                info.ClassName = ReadClassName(hWnd);
                info.Title = ReadTitle(hWnd);
                info.Style = GetStyle(hWnd);
                info.ExStyle = GetExStyle(hWnd);
                info.Visible = IsWindowVisible(hWnd);
                info.Parent = GetParent(hWnd);
                GetWindowRect(hWnd, out info.Bounds);
                result.Add(info);
                return true;
            }, IntPtr.Zero);

            return result;
        }

        private static string ReadClassName(IntPtr hWnd)
        {
            StringBuilder sb = new StringBuilder(256);
            int n = GetClassNameW(hWnd, sb, sb.Capacity);
            return n > 0 ? sb.ToString(0, n) : "";
        }

        private static string ReadTitle(IntPtr hWnd)
        {
            int len = GetWindowTextLengthW(hWnd);
            if (len <= 0) return "";
            StringBuilder sb = new StringBuilder(len + 1);
            int n = GetWindowTextW(hWnd, sb, sb.Capacity);
            return n > 0 ? sb.ToString(0, n) : "";
        }

        private static string Quote(string s)
        {
            if (s == null) return "\"\"";
            if (s.Length > 60) s = s.Substring(0, 60) + "...";
            return "\"" + s.Replace("\"", "\\\"") + "\"";
        }

        /// <summary>
        /// hwnd → managed Form 类名（短名, 不含 namespace）。
        /// 通过 Form.FromHandle 反查 WinForms 注册表; 非 WinForms hwnd (IME / BroadcastEvent) 返回 null。
        /// 因为 Control.FromHandle 必须在 UI 线程调用, 这里走 Application.OpenForms 兜底遍历, 找到 Handle 相等的 Form。
        /// </summary>
        private static string TryGetManagedFormName(IntPtr hWnd)
        {
            try
            {
                // 1. Form.FromHandle 直接反查 (要求在 UI 线程, 但 LayerAudit 通常在 UI 线程触发)
                Control c = Control.FromHandle(hWnd);
                if (c != null)
                {
                    Type t = c.GetType();
                    string n = t.Name;
                    // 区分宿主 vs 内嵌 panel: 若是 Form 直接返回, 否则附加父 Form 信息
                    if (c is Form) return n;
                    Form pf = c.FindForm();
                    if (pf != null && pf != c) return n + "@" + pf.GetType().Name;
                    return n;
                }
                // 2. 兜底: 遍历 OpenForms (跨线程时 FromHandle 返回 null 但 OpenForms 有时仍可用)
                foreach (Form f in Application.OpenForms)
                {
                    if (f.IsHandleCreated && f.Handle == hWnd)
                        return f.GetType().Name;
                }
            }
            catch { }
            return null;
        }

        private static string DecodeExStyle(int ex)
        {
            List<string> parts = new List<string>(6);
            if ((ex & WS_EX_LAYERED) != 0) parts.Add("LAYERED");
            if ((ex & WS_EX_TRANSPARENT) != 0) parts.Add("TRANSPARENT");
            if ((ex & WS_EX_TOOLWINDOW) != 0) parts.Add("TOOLWINDOW");
            if ((ex & WS_EX_NOACTIVATE) != 0) parts.Add("NOACTIVATE");
            if ((ex & WS_EX_TOPMOST) != 0) parts.Add("TOPMOST");
            if ((ex & WS_EX_NOREDIRECTIONBITMAP) != 0) parts.Add("NOREDIRBMP");
            if (parts.Count == 0) return "(none)";
            return string.Join("|", parts.ToArray());
        }
    }
}
