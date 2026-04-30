using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using CF7Launcher.Guardian.Hud;

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
    /// Phase 2 完整序列：
    /// - FlashSnapshot.Capture → ComposeBackdrop → backdrop 显示
    /// - WebOverlay.ResumeForPanel 完整去 LAYERED+TRANSPARENT/timer 恢复/PostToWeb
    /// - panelRect 经 PanelLayoutCatalog 决定
    /// - SetPanelEscapeEnabled 由 PanelHost 接管（_escSource）
    /// - InputShield 进 telemetry 模式（filter 为前台=Guardian + anchor 内 + panelRect 外）
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
        private readonly INativeCursor _cursor;
        private readonly IPanelEscapeSource _escSource;
        private readonly Func<IntPtr> _flashHwndProvider; // 可空：null 时降级走 placeholder backdrop
        // Phase 3: NotchOverlay/ToastOverlay 作为常驻 HUD（web 端 #notch/#toast 已被 CSS 隐藏）
        // panel 打开时 Suspend 让 backdrop 干净遮住；panel 关闭时 SetReady 恢复
        private readonly NotchOverlay _notchOverlay;
        private readonly ToastOverlay _toastOverlay;

        private readonly Queue<PanelCommand> _queue = new Queue<PanelCommand>();
        private readonly object _queueLock = new object();
        private bool _processing;
        private bool _delayedKickRegistered;

        private string _activePanel; // null = closed
        public bool IsPanelOpen { get { return _activePanel != null; } }
        public string ActivePanelName { get { return _activePanel; } }

        private int _consecutiveFailures;
        private const int FAILURE_CIRCUIT_BREAKER = 5;

        // owner 移动/大小变化时跟随：DoOpen 订阅，DoClose 与 ResetToClosedState 反订阅
        private bool _ownerLayoutSubscribed;
        // 节流：LocationChanged 拖窗时高频触发；用 BeginInvoke 合并到下一个消息泵循环
        private bool _ownerLayoutPending;

        public PanelHostController(
            Form ownerForm,
            WebOverlayForm web,
            NativeHudOverlay hud,
            NativePanelBackdrop backdrop,
            InputShieldForm shield,
            HitNumberOverlay hitNumber,
            INativeCursor cursor,
            IPanelEscapeSource escSource,
            Func<IntPtr> flashHwndProvider,
            NotchOverlay notchOverlay,
            ToastOverlay toastOverlay)
        {
            if (ownerForm == null) throw new ArgumentNullException("ownerForm");
            if (web == null) throw new ArgumentNullException("web");
            if (hud == null) throw new ArgumentNullException("hud");
            if (backdrop == null) throw new ArgumentNullException("backdrop");

            _ownerForm = ownerForm;
            _web = web;
            _hud = hud;
            _backdrop = backdrop;
            _shield = shield;     // 可空
            _hitNumber = hitNumber; // 可空
            _cursor = cursor;       // 可空（Program.cs 某些配置下不创建）
            _escSource = escSource; // 可空（fallback hotkey 模式下没有）
            _flashHwndProvider = flashHwndProvider; // 可空（snapshot 不可用时降级 placeholder）
            _notchOverlay = notchOverlay; // 可空（Phase 3 引入）
            _toastOverlay = toastOverlay; // 可空（Phase 3 引入）

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

        /// <summary>
        /// anchor 屏幕矩形 = mapper.CalcViewport 实时算的 Flash 可见区（扣除 letterbox）。
        /// **不能用 _web.Bounds**：DoFullIdleSuspend 只 SW_HIDE 不复位窗口位置/大小，
        /// 下一次 DoOpen 取到的会是上一次的 panelRect，导致新 panel 嵌在过时小矩形里。
        /// 退路：GetCurrentAnchorScreenRect 失败 → FlashHostPanel 屏幕矩形 → owner client。
        /// </summary>
        private Rectangle ComputeAnchorScreenRect()
        {
            try
            {
                Rectangle vp = _web.GetCurrentAnchorScreenRect();
                if (vp.Width > 0 && vp.Height > 0) return vp;
            }
            catch { }
            try
            {
                Control fp = GetFlashPanelOrNull();
                if (fp != null && fp.Width > 0 && fp.Height > 0)
                {
                    Point origin = fp.PointToScreen(Point.Empty);
                    return new Rectangle(origin.X, origin.Y, fp.Width, fp.Height);
                }
            }
            catch { }
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

        /// <summary>
        /// FlashSnapshot.Capture + ComposeBackdrop。失败/无 flashHwnd 时降级纯暗 dim 占位。
        /// 黑帧检测命中 → 提高 dim 强度兜底，避免玩家看到全黑无对比。
        /// </summary>
        private Bitmap CaptureBackdrop(Rectangle anchor)
        {
            IntPtr flashHwnd = (_flashHwndProvider != null) ? _flashHwndProvider() : IntPtr.Zero;
            if (flashHwnd == IntPtr.Zero)
                return ComposePlaceholderBackdrop(anchor);
            FlashSnapshot.SnapshotResult snap = null;
            try
            {
                snap = FlashSnapshot.Capture(flashHwnd);
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] FlashSnapshot.Capture failed: " + ex.Message);
                return ComposePlaceholderBackdrop(anchor);
            }
            try
            {
                bool isBlack = FlashSnapshot.IsLikelyBlackFrame(snap.FullSnapshot, snap.ContentRect);
                byte dimAlpha = isBlack ? (byte)220 : (byte)160;
                return FlashSnapshot.ComposeBackdrop(snap.FullSnapshot, snap.ContentRect, dimAlpha);
            }
            finally
            {
                if (snap.FullSnapshot != null) snap.FullSnapshot.Dispose();
            }
        }

        private Bitmap ComposePlaceholderBackdrop(Rectangle anchor)
        {
            // 兜底：无 flashHwnd / snapshot 失败时用纯暗色（不黑透至游戏世界）
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
            long perfStart = System.Diagnostics.Stopwatch.GetTimestamp();
            PerfTrace.Mark("panel.open_start", name);
            Rectangle anchor = ComputeAnchorScreenRect();
            Rectangle panelRect = PanelLayoutCatalog.GetRect(name, anchor);

            // Step 1-2: snapshot + compose（带 dim + letterbox 黑边保留 + 黑帧兜底）
            Bitmap composed = CaptureBackdrop(anchor);
            // Step 3: backdrop show + 设 panel rect（屏幕坐标，backdrop 内自转 client）
            _backdrop.SetComposedAndShow(composed, anchor);
            _backdrop.SetPanelRect(panelRect);
            // Step 4: HUD 暂停（NativeHud 容器 + Phase 3 NotchOverlay/ToastOverlay 一并隐藏，让 backdrop 干净遮住）
            _hud.Suspend();
            if (_notchOverlay != null) try { _notchOverlay.Suspend(); } catch (Exception ex) { LogManager.Log("[PanelHost] notch.Suspend failed: " + ex.Message); }
            if (_toastOverlay != null) try { _toastOverlay.Suspend(); } catch (Exception ex) { LogManager.Log("[PanelHost] toast.Suspend failed: " + ex.Message); }
            // Step 5: WebOverlay 切 panel-rect（去 LAYERED+TRANSPARENT、opaque、SetWindowPos HWND_TOP+SWP_FRAMECHANGED、PostToWeb panel_viewport_set）
            _web.ResumeForPanel(panelRect);
            // Step 6: InputShield 进 telemetry（仅记录 panelRect 外 click，不拦截）
            if (_shield != null) _shield.EnterTelemetryMode(panelRect, _ownerForm.Handle, anchor);
            EnsurePanelZOrder();
            // Step 7: 通知 web 打开 panel（panel_viewport_set 已在 ResumeForPanel 内 PostToWeb）
            string payload = "{\"type\":\"panel_cmd\",\"cmd\":\"open\",\"panel\":\"" + EscapeJson(name) + "\"";
            if (!string.IsNullOrEmpty(initDataJson))
                payload += ",\"initData\":" + initDataJson;
            payload += "}";
            try { _web.PostToWeb(payload); }
            catch (Exception ex) { LogManager.Log("[PanelHost] PostToWeb open failed: " + ex.Message); }
            // Step 8: 把 HitNumber/Cursor 重新顶置（Backdrop/WebOverlay 的 SetWindowPos HWND_TOP 把它们压下去了）
            ReTopOverlay(_hitNumber);
            // INativeCursor 抽象后 cursor 实现仍是 Form（CursorOverlayForm / DesktopCursorOverlay 都是）。
            // ReTopOverlay 需要 Handle，所以走 as Form 投影；非 Form 实现（不存在）会被静默跳过。
            ReTopOverlay(_cursor as Form);
            // Step 9: ESC 拦截启用
            if (_escSource != null) _escSource.SetPanelEscapeEnabled(true);
            // Step 10: 跟随 owner 拖窗/大小变化，重定位 backdrop+web 到新 anchor
            SubscribeOwnerLayout();

            _activePanel = name;
            LogManager.Log("[PanelHost] opened: " + name + " rect=" + panelRect.Width + "x" + panelRect.Height);
            PerfTrace.Duration("panel.open", perfStart,
                name + " rect=" + panelRect.Width + "x" + panelRect.Height);
            PerfTrace.FlushCounters("panel_open:" + name);
        }

        private Control GetFlashPanelOrNull()
        {
            // _ownerForm 在生产环境总是 GuardianForm；做防御 cast 让单测注入纯 Form 不抛
            GuardianForm gf = _ownerForm as GuardianForm;
            return (gf != null) ? (Control)gf.FlashHostPanel : null;
        }

        private void SubscribeOwnerLayout()
        {
            if (_ownerLayoutSubscribed) return;
            try
            {
                _ownerForm.LocationChanged += OnOwnerLayoutChanged;
                // FlashHostPanel.SizeChanged：viewport 变化的真实源头（全屏切换时 owner SizeChanged
                // 早于 ResizeFlashToPanel，订阅 owner.SizeChanged 会拿到旧 viewport；订阅 panel
                // 自身 SizeChanged 才能等到 layout settle 后的正确 size）
                Control fp = GetFlashPanelOrNull();
                if (fp != null) fp.SizeChanged += OnOwnerLayoutChanged;
                _ownerLayoutSubscribed = true;
            }
            catch (Exception ex) { LogManager.Log("[PanelHost] subscribe owner layout failed: " + ex.Message); }
        }

        private void UnsubscribeOwnerLayout()
        {
            if (!_ownerLayoutSubscribed) return;
            try
            {
                _ownerForm.LocationChanged -= OnOwnerLayoutChanged;
                Control fp = GetFlashPanelOrNull();
                if (fp != null) fp.SizeChanged -= OnOwnerLayoutChanged;
            }
            catch { }
            _ownerLayoutSubscribed = false;
            _ownerLayoutPending = false;
        }

        private void OnOwnerLayoutChanged(object sender, EventArgs e)
        {
            if (_activePanel == null) return;
            // 节流：拖窗 LocationChanged 高频触发；BeginInvoke 合并到下一个消息泵循环只跑一次
            if (_ownerLayoutPending) return;
            _ownerLayoutPending = true;
            try
            {
                _ownerForm.BeginInvoke(new Action(ApplyOwnerLayoutChange));
            }
            catch (Exception ex)
            {
                _ownerLayoutPending = false;
                LogManager.Log("[PanelHost] owner layout BeginInvoke failed: " + ex.Message);
            }
        }

        private void ApplyOwnerLayoutChange()
        {
            _ownerLayoutPending = false;
            if (_activePanel == null) return;
            try
            {
                Rectangle newAnchor = _web.GetCurrentAnchorScreenRect();
                if (newAnchor.Width <= 0 || newAnchor.Height <= 0) return;
                Rectangle newPanelRect = PanelLayoutCatalog.GetRect(_activePanel, newAnchor);

                _backdrop.RepositionTo(newAnchor);
                _backdrop.SetPanelRect(newPanelRect);
                _web.RepositionForPanel(newPanelRect);

                // PostToWeb 让 CSS var(--panel-w/-h) 自适应（仅在尺寸真变化时；拖窗只动位置时跳过）
                try
                {
                    _web.PostToWeb("{\"type\":\"panel_viewport_set\",\"w\":"
                        + newPanelRect.Width + ",\"h\":" + newPanelRect.Height + "}");
                }
                catch { }

                if (_shield != null)
                {
                    try { _shield.EnterTelemetryMode(newPanelRect, _ownerForm.Handle, newAnchor); }
                    catch (Exception ex) { LogManager.Log("[PanelHost] shield reposition failed: " + ex.Message); }
                }
                // ★ 拖动期间不 ReTopOverlay：backdrop/web 用 SWP_NOZORDER 不破坏 z-order，
                //   主动 ReTop 反而触发 z-order 重排导致闪烁 + 抢焦点
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] ApplyOwnerLayoutChange failed: " + ex.Message);
            }
        }

        private void DoClose()
        {
            long perfStart = System.Diagnostics.Stopwatch.GetTimestamp();
            string closingName = _activePanel;
            PerfTrace.Mark("panel.close_start", closingName ?? "<null>");
            // Step 0: 取消 owner 跟随订阅（先于 SuspendAfterPanel，防止 SW_HIDE 触发的 LocationChanged 误触发 reposition）
            UnsubscribeOwnerLayout();
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
            // Step 4: HUD 复活（NativeHud + Phase 3 NotchOverlay/ToastOverlay 一并复显）
            try { _hud.Resume(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] hud.Resume failed: " + ex.Message); }
            if (_notchOverlay != null) try { _notchOverlay.SetReady(); } catch (Exception ex) { LogManager.Log("[PanelHost] notch.SetReady failed: " + ex.Message); }
            if (_toastOverlay != null) try { _toastOverlay.SetReady(); } catch (Exception ex) { LogManager.Log("[PanelHost] toast.SetReady failed: " + ex.Message); }
            // Step 5: ESC 禁用
            if (_escSource != null) _escSource.SetPanelEscapeEnabled(false);
            // Step 6: cursor 重新顶置 + 强制刷一次位置（Notch/Toast 的 SetReady HWND_TOP 会把 cursor 压下；
            //   且 cursor 上次坐标可能在 panel 矩形内，关闭后该区域无 mouse hook 触发更新——直到玩家动鼠标
            //   才刷新 → 视觉上 cursor "消失，移动后突然出现"。这里主动 ReTop + 用当前真实鼠标位置刷一次）
            ReTopOverlay(_cursor as Form);
            try { _web.UpdateCursorFromScreenPoint(System.Windows.Forms.Cursor.Position); }
            catch (Exception ex) { LogManager.Log("[PanelHost] cursor refresh failed: " + ex.Message); }

            _activePanel = null;
            LogManager.Log("[PanelHost] closed: " + (closingName ?? "<null>"));
            PerfTrace.Duration("panel.close", perfStart, closingName ?? "<null>");
            PerfTrace.FlushCounters("panel_close:" + (closingName ?? "<null>"));
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

        private void EnsurePanelZOrder()
        {
            try
            {
                if (_backdrop == null || _web == null) return;
                if (!_backdrop.IsHandleCreated || !_web.IsHandleCreated) return;
                SetWindowPos(_backdrop.Handle, _web.Handle, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                SetWindowPos(_web.Handle, HWND_TOP, 0, 0, 0, 0,
                    SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
                LogManager.Log("[PanelHost] z-order applied: backdrop below web");
            }
            catch (Exception ex)
            {
                LogManager.Log("[PanelHost] z-order apply failed: " + ex.Message);
            }
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
            UnsubscribeOwnerLayout();
            try { _web.ForceIdleState(); }
            catch (Exception ex) { LogManager.Log("[PanelHost] Web ForceIdleState partial failure: " + ex.Message); }
            try { _backdrop.Hide(); } catch { }
            try { _hud.Resume(); } catch { }
            if (_notchOverlay != null) { try { _notchOverlay.SetReady(); } catch { } }
            if (_toastOverlay != null) { try { _toastOverlay.SetReady(); } catch { } }
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
