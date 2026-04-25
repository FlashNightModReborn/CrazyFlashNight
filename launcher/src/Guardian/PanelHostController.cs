using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// Panel 状态机：把 OpenPanel / ClosePanel 序列化为命令队列，按序在 UI 线程执行。
    ///
    /// 核心不变量（Phase 2 起完全成立；Phase 1 stub 阶段尚未严格）：
    ///   IsPanelOpen ⇔ WebOverlay 在 panel-rect/opaque/non-layered 状态
    ///                ⇔ NativePanelBackdrop 显示
    ///                ⇔ NativeHudOverlay 已 Suspend
    ///                ⇔ InputShield 在 telemetry 模式
    ///
    /// 异常恢复：任何 DoOpen/DoClose 路径中途抛 → catch → ResetToClosedState 强制走 close 序列回到一致基线。
    /// 连续 N 次失败 → 熔断清空队列防级联失败。
    ///
    /// Phase 1 范围：
    /// - 队列串行化、handle-created guard、ResetToClosedState 骨架、z-order 顶置 HitNumber/Cursor
    /// - DoOpen/DoClose 调用 stub API（WebOverlay.ResumeForPanel/SuspendAfterPanel 是 Phase 1 stub）
    /// - 不做 FlashSnapshot/ComposeBackdrop（Phase 2 引入）—— Phase 1 backdrop 仅显示纯黑底
    /// - 不调用 SetPanelEscapeEnabled（Phase 1 仍走 GuardianForm.HandlePanelStateChanged 旧路径）
    /// </summary>
    public class PanelHostController
    {
        #region Win32

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter,
            int X, int Y, int cx, int cy, uint uFlags);

        private static readonly IntPtr HWND_TOP = new IntPtr(0);
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOSIZE = 0x0001;
        private const uint SWP_NOACTIVATE = 0x0010;

        #endregion

        public enum PanelCommandKind { Open, Close }

        public struct PanelCommand
        {
            public PanelCommandKind Kind;
            public string Name;
            public string InitDataJson; // 可空；OpenPanel 序列化进 panel_cmd
            public PanelCommand(PanelCommandKind kind, string name, string initDataJson)
            {
                Kind = kind;
                Name = name;
                InitDataJson = initDataJson;
            }
        }

        private readonly Form _ownerForm;
        private readonly WebOverlayForm _web;
        private readonly NativeHudOverlay _hud;
        private readonly NativePanelBackdrop _backdrop;
        private readonly InputShieldForm _shield;
        private readonly HitNumberOverlay _hitNumber;
        private readonly CursorOverlayForm _cursor;
        private readonly IPanelEscapeSource _escSource;

        private readonly Queue<PanelCommand> _queue = new Queue<PanelCommand>();
        private readonly object _queueLock = new object();
        private bool _processing;
        private bool _delayedKickRegistered;

        private string _activePanel; // null = closed
        public bool IsPanelOpen { get { return _activePanel != null; } }
        public string ActivePanelName { get { return _activePanel; } }

        private int _consecutiveFailures;
        private const int FAILURE_CIRCUIT_BREAKER = 5;

        public PanelHostController(
            Form ownerForm,
            WebOverlayForm web,
            NativeHudOverlay hud,
            NativePanelBackdrop backdrop,
            InputShieldForm shield,
            HitNumberOverlay hitNumber,
            CursorOverlayForm cursor,
            IPanelEscapeSource escSource)
        {
            if (ownerForm == null) throw new ArgumentNullException("ownerForm");
            if (web == null) throw new ArgumentNullException("web");
            if (hud == null) throw new ArgumentNullException("hud");
            if (backdrop == null) throw new ArgumentNullException("backdrop");

            _ownerForm = ownerForm;
            _web = web;
            _hud = hud;
            _backdrop = backdrop;
            _shield = shield;     // 可空（Phase 1 允许）
            _hitNumber = hitNumber; // 可空
            _cursor = cursor;       // 可空（Program.cs 某些配置下不创建）
            _escSource = escSource; // 可空（fallback hotkey 模式下没有）

            // Backdrop 点击外侧 → web panel_esc（等价 web 端 panels.js 的 backdrop click）
            _backdrop.BackdropClickedOutsidePanel += OnBackdropClickOutsidePanel;
        }

        private void OnBackdropClickOutsidePanel()
        {
            // panels.js 的 panel_esc 等价于按 ESC：触发各 panel 的 onRequestClose
            // 不发 cmd:"request_close" —— panels.js 的 panel_cmd 仅 handle open/close/force_close
            try { _web.PostToWeb("{\"type\":\"panel_esc\"}"); }
            catch (Exception ex) { LogManager.Log("[PanelHost] backdrop esc post failed: " + ex.Message); }
        }

        #region Public API

        public void OpenPanel(string name)
        {
            OpenPanel(name, null);
        }

        public void OpenPanel(string name, string initDataJson)
        {
            if (string.IsNullOrEmpty(name)) return;
            EnqueueAndPump(new PanelCommand(PanelCommandKind.Open, name, initDataJson));
        }

        public void ClosePanel()
        {
            EnqueueAndPump(new PanelCommand(PanelCommandKind.Close, null, null));
        }

        #endregion

        #region Queue

        private void EnqueueAndPump(PanelCommand cmd)
        {
            lock (_queueLock)
            {
                _queue.Enqueue(cmd);
                if (_processing) return;
                _processing = true;
            }

            // guard: handle 未创建时 BeginInvoke 抛
            if (!_ownerForm.IsHandleCreated)
            {
                if (!_delayedKickRegistered)
                {
                    _delayedKickRegistered = true;
                    _ownerForm.HandleCreated += DelayedKickOnHandleCreated;
                }
                return;
            }
            try
            {
                _ownerForm.BeginInvoke(new Action(PumpQueue));
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] BeginInvoke pump failed: " + ex.Message);
                // 释放 _processing 让下次入队能重试
                lock (_queueLock) { _processing = false; }
            }
        }

        private void DelayedKickOnHandleCreated(object sender, EventArgs e)
        {
            _ownerForm.HandleCreated -= DelayedKickOnHandleCreated;
            _delayedKickRegistered = false;
            try { _ownerForm.BeginInvoke(new Action(PumpQueue)); }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] delayed pump kick failed: " + ex.Message);
                lock (_queueLock) { _processing = false; }
            }
        }

        private void PumpQueue()
        {
            while (true)
            {
                PanelCommand cmd;
                lock (_queueLock)
                {
                    if (_queue.Count == 0) { _processing = false; return; }
                    cmd = _queue.Dequeue();
                }
                try
                {
                    ExecuteCommand(cmd);
                }
                catch (Exception ex)
                {
                    LogManager.Log("[PanelHost] command failed: " + ex);
                    try { ResetToClosedState(); }
                    catch (Exception ex2) { LogManager.Log("[PanelHost] reset failed: " + ex2); }
                }
            }
        }

        private void ExecuteCommand(PanelCommand cmd)
        {
            if (cmd.Kind == PanelCommandKind.Open)
            {
                if (_activePanel == cmd.Name) { _consecutiveFailures = 0; return; }
                if (_activePanel != null) DoClose();
                DoOpen(cmd.Name, cmd.InitDataJson);
            }
            else
            {
                if (_activePanel == null) { _consecutiveFailures = 0; return; }
                DoClose();
            }
            _consecutiveFailures = 0;
        }

        #endregion

        #region DoOpen / DoClose

        // anchorScreenRect 在 Phase 2 由 OverlayCoordinateContext 提供；Phase 1 暂用 owner 的 bounds 作占位
        private Rectangle ComputeAnchorScreenRect()
        {
            try
            {
                Point origin = _ownerForm.PointToScreen(Point.Empty);
                return new Rectangle(origin.X, origin.Y, _ownerForm.ClientSize.Width, _ownerForm.ClientSize.Height);
            }
            catch
            {
                return new Rectangle(0, 0, 1024, 576);
            }
        }

        private Rectangle ComputePanelRect(string name, Rectangle anchor)
        {
            // Phase 1 固定居中 800x600；Phase 2 起接入 PanelLayoutCatalog
            int w = Math.Min(800, anchor.Width);
            int h = Math.Min(600, anchor.Height);
            int x = anchor.X + (anchor.Width - w) / 2;
            int y = anchor.Y + (anchor.Height - h) / 2;
            return new Rectangle(x, y, w, h);
        }

        private Bitmap ComposePlaceholderBackdrop(Rectangle anchor)
        {
            // Phase 1：纯黑兜底（无 FlashSnapshot capture）
            Bitmap bmp = new Bitmap(Math.Max(1, anchor.Width), Math.Max(1, anchor.Height),
                System.Drawing.Imaging.PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            using (SolidBrush b = new SolidBrush(Color.FromArgb(255, 8, 8, 12)))
            {
                g.FillRectangle(b, 0, 0, bmp.Width, bmp.Height);
            }
            return bmp;
        }

        private void DoOpen(string name, string initDataJson)
        {
            Rectangle anchor = ComputeAnchorScreenRect();
            Rectangle panelRect = ComputePanelRect(name, anchor);

            // Step 1-2: snapshot + compose（Phase 2 真实化；Phase 1 用占位黑底）
            Bitmap composed = ComposePlaceholderBackdrop(anchor);
            // Step 3: backdrop show + 设 panel rect
            _backdrop.SetComposedAndShow(composed, anchor);
            _backdrop.SetPanelRect(panelRect);
            // Step 4: HUD 暂停
            _hud.Suspend();
            // Step 5: WebOverlay 切 panel-rect（Phase 1 stub：仅 SetWindowPos + ShowWindow）
            _web.ResumeForPanel(panelRect);
            // Step 6: InputShield 进 telemetry（Phase 1 stub）
            if (_shield != null) _shield.EnterTelemetryMode(panelRect, _ownerForm.Handle, anchor);
            // Step 7: 通知 web 打开 panel
            string payload = "{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"" + EscapeJson(name) + "\"";
            if (!string.IsNullOrEmpty(initDataJson))
                payload += ",\"initData\":" + initDataJson;
            payload += "}";
            try { _web.PostToWeb(payload); }
            catch (Exception ex) { LogManager.Log("[PanelHost] PostToWeb open failed: " + ex.Message); }
            // Step 8: 把 HitNumber/Cursor 重新顶置（Backdrop/WebOverlay 的 SetWindowPos 把它们压下去了）
            ReTopOverlay(_hitNumber);
            ReTopOverlay(_cursor);
            // Step 9: ESC 拦截启用
            if (_escSource != null) _escSource.SetPanelEscapeEnabled(true);

            _activePanel = name;
            LogManager.Log("[PanelHost] opened: " + name + " rect=" + panelRect.Width + "x" + panelRect.Height);
        }

        private void DoClose()
        {
            string closingName = _activePanel;
            // Step 1: WebOverlay 收尾（Phase 1 stub：SW_HIDE）
            try { _web.SuspendAfterPanel(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] SuspendAfterPanel failed: " + ex.Message); }
            // Step 2: Shield 退 telemetry
            if (_shield != null)
            {
                try { _shield.ExitTelemetryMode(); }
                catch (Exception ex) { LogManager.Log("[PanelHost] ExitTelemetryMode failed: " + ex.Message); }
            }
            // Step 3: backdrop 隐藏
            try { _backdrop.Hide(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] backdrop.Hide failed: " + ex.Message); }
            // Step 4: HUD 复活
            try { _hud.Resume(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] hud.Resume failed: " + ex.Message); }
            // Step 5: ESC 禁用
            if (_escSource != null) _escSource.SetPanelEscapeEnabled(false);

            _activePanel = null;
            LogManager.Log("[PanelHost] closed: " + (closingName ?? "<null>"));
        }

        private void ReTopOverlay(Form f)
        {
            if (f == null) return;
            try
            {
                if (!f.IsHandleCreated || !f.Visible) return;
                SetWindowPos(f.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
            }
            catch { }
        }

        #endregion

        #region ResetToClosedState

        /// <summary>
        /// 异常恢复 primitive：把整个系统强制拨回 idle 不变量。
        /// 必须涵盖 SuspendAfterPanel 内每一步 + backdrop/hud/shield close 序列。
        /// 关键：调用 _web.ForceIdleState()（不查 _panelMode），不是 SuspendAfterPanel。
        /// 即便部分窗口已 dispose 也尽量推进；catch 后继续。
        /// </summary>
        private void ResetToClosedState()
        {
            try { _web.ForceIdleState(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] Web ForceIdleState partial failure: " + ex.Message); }
            try { _backdrop.Hide(); } catch { }
            try { _hud.Resume(); } catch { }
            if (_shield != null) { try { _shield.ExitTelemetryMode(); } catch { } }
            if (_escSource != null) { try { _escSource.SetPanelEscapeEnabled(false); } catch { } }
            _activePanel = null;

            _consecutiveFailures++;
            if (_consecutiveFailures >= FAILURE_CIRCUIT_BREAKER)
            {
                lock (_queueLock) { _queue.Clear(); }
                LogManager.Log("[PanelHost] CIRCUIT BREAKER triggered after " + _consecutiveFailures
                    + " consecutive failures; queue cleared.");
                _consecutiveFailures = 0;
            }
        }

        #endregion

        private static string EscapeJson(string s)
        {
            if (string.IsNullOrEmpty(s)) return "";
            return s.Replace("\\", "\\\\").Replace("\"", "\\\"");
        }
    }
}
