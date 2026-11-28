using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Diagnostic;
using CF7Launcher.Guardian.InputOwnership;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 修改器的独立 1016×550 原生浮窗。它不进入 PanelHost 的全屏面板、
    /// 不申请面板暂停，也不复用 backup/input shield；AS2 会话和写权威仍归
    /// ModifierTask / ModifierPanelService。
    /// </summary>
    internal sealed class ModifierOverlay : IDisposable
    {
        private readonly record struct PanelIdentity(int Generation, int Connection, string Token, string Instance);
        private readonly record struct PendingOpen(JObject Data, int Connection);
        private enum FocusReturn { Returned, External, Failed, Stale }

        private readonly Form _owner;
        private readonly ModifierNativeSurface _surface;
        private readonly ModifierTask _task;
        private readonly Func<string, int, bool> _sendClosed;
        private readonly WindowManager _closeFocusManager;
        private readonly object _gate = new object();
        private int _sequence;
        private string _instance = "";
        private string _token = "";
        private Rectangle _lastRect = Rectangle.Empty;
        private Point _ownerLocation;
        private PendingOpen? _pendingOpen;
        private int _connection;
        private bool _preparing, _disposed;
        private PanelIdentity? _closing;
        internal void BindInputAuthority(ITextInputAuthority textAuthority, IUiPointerAuthority pointerAuthority)
        {
            _surface.BindInputAuthority(textAuthority, pointerAuthority);
        }

        internal ModifierOverlay(Form owner, string webRoot, string profileRoot,
            ModifierTask task, Func<string, int, bool> sendClosed, string dollPortraitsDir,
            WindowManager closeFocusManager = null)
        {
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
            _task = task ?? throw new ArgumentNullException(nameof(task));
            _sendClosed = sendClosed;
            _closeFocusManager = closeFocusManager;
            _surface = new ModifierNativeSurface(owner, webRoot, profileRoot, task, dollPortraitsDir);
            _surface.CloseRequested += OnNativeCloseRequested;
            _surface.Move += OnSurfaceMoved;
            _ownerLocation = _owner.Location;
            _owner.Move += OnOwnerMoved;
            _task.SetPostToWeb(json => _surface.TryPost(json));
            _task.SetInvoker(action =>
            {
                if (_disposed) return;
                try
                {
                    if (_owner.IsHandleCreated && _owner.InvokeRequired) _owner.BeginInvoke(action);
                    else action();
                }
                catch { }
            });
        }

        internal void Prewarm()
        {
            if (_disposed) return;
            if (_owner.InvokeRequired)
            {
                try { _owner.BeginInvoke(new Action(Prewarm)); } catch { }
                return;
            }
            if (_surface.Ready || _preparing) return;
            _preparing = true;
            PrepareAsync();
        }

        private async void PrepareAsync()
        {
            PendingOpen? pending = null;
            try
            {
                await _surface.PrepareAsync();
                pending = _pendingOpen;
                _pendingOpen = null;
            }
            catch (Exception error)
            {
                LogManager.Log("[ModifierSurface] prewarm failed: " + error.GetType().Name);
                PendingOpen? rejected = _pendingOpen;
                _pendingOpen = null;
                if (rejected is { } open) NotifyClosed(open.Data.Value<string>("token"), open.Connection, "prewarm_failed");
            }
            finally { _preparing = false; }
            if (pending is { } deferred && !_disposed && !Open(deferred.Data, deferred.Connection))
                NotifyClosed(deferred.Data.Value<string>("token"), deferred.Connection, "deferred_open_rejected");
        }

        internal bool Open(JObject data, int expectedConnection = 0)
        {
            if (_disposed) return false;
            string token = data?.Value<string>("token");
            if (string.IsNullOrEmpty(token) || !_task.TryBindPanelConnection(expectedConnection, out int connection)) return false;
            if (_owner.InvokeRequired)
            {
                try
                {
                    _owner.BeginInvoke(new Action(() =>
                    {
                        if (!Open(data, connection)) NotifyClosed(token, connection, "deferred_open_rejected");
                    }));
                    return true;
                }
                catch (InvalidOperationException) { return false; }
            }
            lock (_gate)
            {
                if (_closing.HasValue || !_task.CanRetainPanelClose) return false;
                if (_surface.Active)
                {
                    if (_connection == connection && string.Equals(_token, token, StringComparison.Ordinal)) return true;
                    CloseCore();
                    // The HUD toggle supplied a new AS2 token without opening another window.
                    NotifyClosed(token, connection, "toggle_request");
                    return true;
                }
            }
            if (!_surface.Ready)
            {
                _pendingOpen = new PendingOpen(data, connection);
                Prewarm();
                return true;
            }
            if (!_surface.Active)
            {
                Rectangle rect = TargetRect();
                if (!_surface.ResumePanel(rect)) return false;
                if (!_surface.CommitGeometry(rect, _surface.SessionGeneration))
                {
                    _surface.SuspendPanel();
                    return false;
                }
                _lastRect = rect;
            }
            string instance = "modifier.panel." + (++_sequence);
            _instance = instance;
            _token = token;
            _connection = connection;
            var initData = new JObject
            {
                ["panelInstanceId"] = instance,
                ["token"] = token,
                ["source"] = "nativehud_modifier"
            };
            var open = new JObject
            {
                ["type"] = "panel_cmd",
                ["panel"] = "modifier",
                ["cmd"] = "open",
                ["initData"] = initData
            };
            if (!_surface.TryPost(open.ToString(Formatting.None)))
            {
                _instance = "";
                _token = "";
                _connection = 0;
                _surface.SuspendPanel();
                return false;
            }
            return true;
        }

        internal void OnCompetingPanelOpened()
        {
            if (_disposed) return;
            if (_owner.InvokeRequired)
            {
                PanelIdentity panel = CurrentPanel();
                try { _owner.BeginInvoke(new Action(() => CloseCore(false, panel))); } catch { }
                return;
            }
            if (_surface.Active) CloseCore(false);
        }

        internal void OnSocketDisconnected(int connection)
        {
            if (_disposed) return;
            if (_owner.InvokeRequired)
            {
                try { _owner.BeginInvoke(new Action(() => OnSocketDisconnected(connection))); } catch { }
                return;
            }
            if (_pendingOpen is { } pending && pending.Connection == connection) _pendingOpen = null;
            if (_connection != connection || !_surface.Active) return;
            PanelIdentity? inProgress = _closing;
            _closing = CurrentPanel();
            _instance = "";
            _token = "";
            _connection = 0;
            try
            {
                _task.ClearPending();
                _surface.SuspendPanel();
            }
            finally { _closing = inProgress; }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            try { _owner.Move -= OnOwnerMoved; } catch { }
            try { _task.SetPostToWeb(null); } catch { }
            try { _surface.Dispose(); } catch { }
        }

        internal bool IsOpen => !_disposed && _surface != null && _surface.Active;
        internal bool ShouldKeepHudPresented(IntPtr deactivatingTo) => !_disposed && _surface.ShouldKeepHudPresented(deactivatingTo);

        internal void CloseFromHost()
        {
            if (_disposed) return;
            if (_owner.InvokeRequired)
            {
                PanelIdentity panel = CurrentPanel();
                _owner.BeginInvoke(new Action(() => CloseCore(false, panel)));
            }
            else CloseCore(false);
        }

        private void OnNativeCloseRequested()
        {
            if (_disposed) return;
            PanelIdentity panel = CurrentPanel();
            CloseCore(expectedPanel: panel, returnOwner: _surface.IsUserCloseRequested(panel.Generation));
        }

        private PanelIdentity CurrentPanel() => new(_surface.SessionGeneration, _connection, _token, _instance);

        private bool IsCurrentPanel(PanelIdentity panel) => !_disposed && _surface.Active && CurrentPanel() == panel
            && !string.IsNullOrEmpty(panel.Token) && !string.IsNullOrEmpty(panel.Instance);

        private IntPtr CurrentGuardianHandle => _owner.IsHandleCreated && !_owner.IsDisposed ? _owner.Handle : IntPtr.Zero;

        private void CloseCore(bool requestGameKeyboard = true, PanelIdentity? expectedPanel = null, bool returnOwner = false)
        {
            PanelIdentity panel = expectedPanel ?? CurrentPanel();
            if (_closing.HasValue || !IsCurrentPanel(panel)) return;
            _closing = panel;
            IntPtr guardian = CurrentGuardianHandle;
            try
            {
                bool requestKeyboard = requestGameKeyboard && _surface.HasSessionForeground();
                if (FocusTrace.Enabled)
                    FocusTrace.Record("modifier.close_core", new { token = panel.Token, instance = panel.Instance,
                        generation = panel.Generation, requestKeyboard });
                if (returnOwner && _closeFocusManager != null)
                {
                    FocusReturn focus = ReturnOwnerBeforeHide(panel, guardian);
                    if (focus == FocusReturn.Stale) return;
                    if (focus == FocusReturn.Failed)
                    {
                        if (IsCurrentPanel(panel)) _surface.ReportCloseFocusFailure();
                        return;
                    }
                    requestKeyboard = requestGameKeyboard && focus == FocusReturn.Returned;
                }
                if (!IsCurrentPanel(panel)) return;
                ModifierCloseScope? close = _task.RetainPanelClose(panel.Token, panel.Instance, panel.Generation, panel.Connection);
                if (_task.UsesCloseReceipts && !close.HasValue && _task.TryBindPanelConnection(panel.Connection, out _))
                {
                    _surface.ReportCloseReceiptUnavailable();
                    return;
                }
                _pendingOpen = null;
                _instance = "";
                _token = "";
                _connection = 0;
                _task.ClearPending();
                try { _surface.SuspendPanel(); }
                finally
                {
                    if (close is { } retained) _task.SubmitRetainedPanelClose(retained);
                    else if (!_task.UsesCloseReceipts) NotifyClosed(panel.Token, panel.Connection, "surface_closed");
                }
                if (!_disposed)
                {
                    if (_closeFocusManager != null)
                        requestKeyboard &= guardian != IntPtr.Zero && CurrentGuardianHandle == guardian
                            && _closeFocusManager.ReadCloseForeground() == guardian;
                    _surface.CompleteCloseInput(panel.Generation, requestKeyboard);
                }
            }
            finally { _closing = null; }
        }

        private FocusReturn ReturnOwnerBeforeHide(PanelIdentity panel, IntPtr guardian)
        {
            IntPtr before = IntPtr.Zero, after = IntPtr.Zero;
            bool attempted = false, succeeded = false;
            string error = null;
            FocusReturn outcome = FocusReturn.Failed;
            try
            {
                before = _closeFocusManager.ReadCloseForeground();
                if (!IsCurrentPanel(panel) || guardian == IntPtr.Zero || CurrentGuardianHandle != guardian)
                    return outcome = FocusReturn.Stale;
                if (before == guardian)
                {
                    after = before;
                    return outcome = FocusReturn.Returned;
                }
                if (!_surface.OwnsCurrentPanelForeground(before))
                {
                    after = before;
                    return outcome = FocusReturn.External;
                }
                attempted = true;
                succeeded = _closeFocusManager.ActivateSessionRootBeforeHide(before);
                after = _closeFocusManager.ReadCloseForeground();
                if (!IsCurrentPanel(panel) || CurrentGuardianHandle != guardian)
                    return outcome = FocusReturn.Stale;
                return outcome = after == guardian ? FocusReturn.Returned
                    : _surface.OwnsCurrentPanelForeground(after) ? FocusReturn.Failed : FocusReturn.External;
            }
            catch (Exception failure)
            {
                error = failure.GetType().Name;
                LogManager.Log("[Modifier] root handoff failed: " + error);
                return outcome;
            }
            finally
            {
                if (FocusTrace.Enabled)
                    FocusTrace.Record("modifier.close_focus", new
                    {
                        token = panel.Token, instance = panel.Instance, generation = panel.Generation,
                        before = before.ToInt64(), after = after.ToInt64(), attempted, succeeded, error, outcome = outcome.ToString()
                    });
            }
        }

        private void NotifyClosed(string token, int connection, string reason)
        {
            bool sent = false;
            try { sent = !string.IsNullOrEmpty(token) && _sendClosed?.Invoke(token, connection) == true; }
            catch (Exception error) { LogManager.Log("[Modifier] close notice failed: " + error.GetType().Name); }
            if (FocusTrace.Enabled)
                FocusTrace.Record("modifier.close_sent", new { token, connection, reason, sent });
        }

        private void OnSurfaceMoved(object sender, EventArgs e)
        {
            if (_surface.Active) _lastRect = _surface.Bounds;
        }

        private void OnOwnerMoved(object sender, EventArgs e)
        {
            if (_disposed) return;
            int dx = _owner.Left - _ownerLocation.X;
            int dy = _owner.Top - _ownerLocation.Y;
            _ownerLocation = _owner.Location;
            if (_lastRect != Rectangle.Empty) _lastRect.Offset(dx, dy);
            if (!_surface.Active || (dx == 0 && dy == 0)) return;
            _surface.RepositionPanel(_lastRect, true);
        }

        private Rectangle TargetRect()
        {
            double scale = _owner.DeviceDpi / 96.0;
            int width = Math.Max(1, (int)Math.Round(1016 * scale));
            int height = Math.Max(1, (int)Math.Round(550 * scale));
            Rectangle owner = _owner.Bounds;
            int x = owner.Left + (owner.Width - width) / 2;
            int y = owner.Top + (owner.Height - height) / 2;
            if (_lastRect != Rectangle.Empty) { x = _lastRect.X; y = _lastRect.Y; }
            Rectangle screen = Screen.FromControl(_owner).WorkingArea;
            x = Math.Max(screen.Left, Math.Min(x, screen.Right - width));
            y = Math.Max(screen.Top, Math.Min(y, screen.Bottom - height));
            return new Rectangle(x, y, width, height);
        }
    }
}
