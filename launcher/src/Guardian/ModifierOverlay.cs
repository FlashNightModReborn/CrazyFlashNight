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
        private readonly Form _owner;
        private readonly ModifierNativeSurface _surface;
        private readonly ModifierTask _task;
        private readonly Func<string, bool> _sendClosed;
        private readonly WindowManager _closeFocusManager;
        private readonly object _gate = new object();
        private int _sequence;
        private string _instance = "";
        private string _token = "";
        private Rectangle _lastRect = Rectangle.Empty;
        private Point _ownerLocation;
        private JObject _pendingOpen;
        private bool _preparing, _disposed;
        internal void BindInputAuthority(ITextInputAuthority textAuthority, IUiPointerAuthority pointerAuthority)
        {
            _surface.BindInputAuthority(textAuthority, pointerAuthority);
        }

        internal ModifierOverlay(Form owner, string webRoot, string profileRoot,
            ModifierTask task, Func<string, bool> sendClosed, string dollPortraitsDir,
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
            JObject pending = null;
            try
            {
                await _surface.PrepareAsync();
                pending = _pendingOpen;
                _pendingOpen = null;
            }
            catch (Exception error)
            {
                LogManager.Log("[ModifierSurface] prewarm failed: " + error.GetType().Name);
                JObject rejected = _pendingOpen;
                _pendingOpen = null;
                if (rejected != null) NotifyClosed(rejected.Value<string>("token"), "prewarm_failed");
            }
            finally { _preparing = false; }
            if (pending != null && !_disposed && !Open(pending))
                NotifyClosed(pending.Value<string>("token"), "deferred_open_rejected");
        }

        internal bool Open(JObject data)
        {
            if (_disposed) return false;
            string token = data?.Value<string>("token");
            if (string.IsNullOrEmpty(token)) return false;
            if (_owner.InvokeRequired)
            {
                try
                {
                    _owner.BeginInvoke(new Action(() =>
                    {
                        if (!Open(data)) NotifyClosed(token, "deferred_open_rejected");
                    }));
                    return true;
                }
                catch (InvalidOperationException) { return false; }
            }
            lock (_gate)
            {
                if (_surface.Active)
                {
                    if (string.Equals(_token, token, StringComparison.Ordinal)) return true;
                    CloseCore();
                    // The HUD toggle supplied a new AS2 token without opening another window.
                    NotifyClosed(token, "toggle_request");
                    return true;
                }
            }
            if (!_surface.Ready)
            {
                _pendingOpen = data;
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
                int generation = _surface.SessionGeneration;
                try { _owner.BeginInvoke(new Action(() => CloseCore(false, generation))); } catch { }
                return;
            }
            if (_surface.Active) CloseCore(false);
        }

        internal void OnSocketDisconnected()
        {
            if (_disposed) return;
            if (_owner.InvokeRequired)
            {
                try { _owner.BeginInvoke(new Action(OnSocketDisconnected)); } catch { }
                return;
            }
            _task.ClearPending();
            _surface.SuspendPanel();
            _pendingOpen = null;
            _instance = "";
            _token = "";
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
                int generation = _surface.SessionGeneration;
                _owner.BeginInvoke(new Action(() => CloseCore(false, generation)));
            }
            else CloseCore(false);
        }

        private void OnNativeCloseRequested()
        {
            if (_disposed) return;
            int generation = _surface.SessionGeneration;
            CloseCore(expectedGeneration: generation, returnOwner: _surface.IsUserCloseRequested(generation));
        }

        private void CloseCore(bool requestGameKeyboard = true, int? expectedGeneration = null,
            bool returnOwner = false)
        {
            if (_disposed || (expectedGeneration.HasValue && expectedGeneration != _surface.SessionGeneration)) return;
            if (!_surface.Active)
            {
                _instance = "";
                _token = "";
                return;
            }
            bool requestKeyboard = requestGameKeyboard && _surface.HasSessionForeground();
            int generation = _surface.SessionGeneration;
            string token = _token;
            if (FocusTrace.Enabled)
                FocusTrace.Record("modifier.close_core", new { token, instance = _instance, generation, requestKeyboard });
            if (returnOwner && _closeFocusManager != null)
            {
                ReturnOwnerBeforeHide(generation, token, _instance);
                if (_disposed || !_surface.Active || generation != _surface.SessionGeneration) return;
            }
            _pendingOpen = null;
            _instance = "";
            _token = "";
            _task.ClearPending();
            _surface.SuspendPanel();
            NotifyClosed(token, "surface_closed");
            if (!_disposed) _surface.CompleteCloseInput(generation, requestKeyboard);
        }

        private void ReturnOwnerBeforeHide(int generation, string token, string instance)
        {
            IntPtr before = IntPtr.Zero, after = IntPtr.Zero;
            bool attempted = false, succeeded = false;
            string error = null;
            try
            {
                before = _closeFocusManager.ReadCloseForeground();
                attempted = _surface.OwnsCurrentPanelForeground(before);
                if (attempted) succeeded = _closeFocusManager.ActivateSessionRootBeforeHide(before);
                after = _closeFocusManager.ReadCloseForeground();
            }
            catch (Exception failure)
            {
                error = failure.GetType().Name;
                LogManager.Log("[Modifier] root handoff failed: " + error);
            }
            if (FocusTrace.Enabled)
                FocusTrace.Record("modifier.close_focus", new
                {
                    token, instance, generation, before = before.ToInt64(), after = after.ToInt64(), attempted, succeeded, error
                });
        }

        private void NotifyClosed(string token, string reason)
        {
            bool sent = false;
            try { sent = !string.IsNullOrEmpty(token) && _sendClosed?.Invoke(token) == true; }
            catch (Exception error) { LogManager.Log("[Modifier] close notice failed: " + error.GetType().Name); }
            if (FocusTrace.Enabled)
                FocusTrace.Record("modifier.close_sent", new { token, reason, sent });
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
