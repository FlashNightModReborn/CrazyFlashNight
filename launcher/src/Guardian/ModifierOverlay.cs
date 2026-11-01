using System;
using System.Drawing;
using System.Windows.Forms;
using CF7Launcher.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace CF7Launcher.Guardian
{
    /// <summary>
    /// 修改器的独立 550×400 composition 浮窗。它不进入 PanelHost 的全屏面板、
    /// 不申请面板暂停，也不复用 backup/input shield；AS2 会话和写权威仍归
    /// ModifierTask / ModifierPanelService。
    /// </summary>
    internal sealed class ModifierOverlay : IDisposable
    {
        private readonly Form _owner;
        private readonly CompositionHelpSurface _surface;
        private readonly ModifierTask _task;
        private readonly Action _sendClosed;
        private readonly object _gate = new object();
        private int _sequence;
        private string _instance = "";
        private string _token = "";
        private Rectangle _lastRect = Rectangle.Empty;
        private Point _ownerLocation;
        private JObject _pendingOpen;
        private bool _preparing, _disposed;

        internal ModifierOverlay(Form owner, string webRoot, string profileRoot,
            ModifierTask task, Action sendClosed)
        {
            _owner = owner ?? throw new ArgumentNullException(nameof(owner));
            _task = task ?? throw new ArgumentNullException(nameof(task));
            _sendClosed = sendClosed;
            _surface = new CompositionHelpSurface(owner, webRoot, profileRoot,
                CompositionPanelProfile.Modifier);
            _surface.HostCloseRequested += OnHostCloseRequested;
            _surface.InboundPanelMessage += OnPanelMessage;
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
                if (_pendingOpen != null)
                {
                    _pendingOpen = null;
                    if (_sendClosed != null) { try { _sendClosed(); } catch { } }
                }
            }
            finally { _preparing = false; }
            if (pending != null && !_disposed) Open(pending);
        }

        internal bool Open(JObject data)
        {
            if (_disposed) return false;
            if (_owner.InvokeRequired)
            {
                try { _owner.BeginInvoke(new Action(delegate { Open(data); })); } catch { }
                return true;
            }
            string token = data == null ? null : data.Value<string>("token");
            if (string.IsNullOrEmpty(token)) return false;
            lock (_gate)
            {
                if (_surface.Active)
                {
                    CloseCore();
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
                try { _owner.BeginInvoke(new Action(OnCompetingPanelOpened)); } catch { }
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

        private void OnHostCloseRequested(HostCloseContext context)
        {
            if (_disposed) return;
            if (context == null || context.Endpoint == null
                || !string.Equals(context.Endpoint.Instance, _instance, StringComparison.Ordinal)) return;
            CloseCore();
        }

        private void CloseCore(bool restoreFocusAllowed = true)
        {
            if (!_surface.Active)
            {
                _instance = "";
                _token = "";
                return;
            }
            bool restoreFocus = _surface.CanRestoreGameFocus && restoreFocusAllowed;
            _pendingOpen = null;
            _instance = "";
            _token = "";
            _task.ClearPending();
            _surface.SuspendPanel();
            if (_sendClosed != null) { try { _sendClosed(); } catch { } }
            if (restoreFocus && !_disposed && _owner.Visible && _owner.WindowState != FormWindowState.Minimized)
            {
                try { _owner.Activate(); } catch { }
            }
        }

        private void OnPanelMessage(JObject message)
        {
            if (_disposed || message == null) return;
            string instance = message.Value<string>("panelInstanceId");
            string cmd = message.Value<string>("cmd");
            if (string.IsNullOrEmpty(instance) || instance != _instance || string.IsNullOrEmpty(cmd)) return;
            _task.HandleWebRequest(cmd, message);
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
            int width = Math.Max(1, (int)Math.Round(550 * scale));
            int height = Math.Max(1, (int)Math.Round(400 * scale));
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
