using System;
using System.Drawing;
using System.Windows.Forms;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Neutral, Launcher-owned observation indicator. It is deliberately not
    /// published into the Agent surface registry and therefore can never be an
    /// observation target. Closing or hiding it revokes the bound read grant.
    /// </summary>
    internal sealed class LauncherWingsObservationIndicator
        : IDisposable
    {
        private readonly Form _owner;
        private Form _form;
        private Timer _expiryTimer;
        private Action _revoked;
        private bool _suppressRevocation;
        private bool _disposed;

        public LauncherWingsObservationIndicator(Form owner)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _owner.VisibleChanged += OnOwnerVisibleChanged;
            _owner.FormClosed += OnOwnerFormClosed;
        }

        internal Form FormForTest => _form;

        public bool IsAlive =>
            !_disposed
            && _form != null
            && !_form.IsDisposed
            && _form.IsHandleCreated
            && _form.Visible
            && !_owner.IsDisposed
            && _owner.Visible;

        public bool TryShow(
            DateTimeOffset expiresAtUtc,
            TimeSpan lifetime,
            Action revoked)
        {
            if (revoked == null)
                throw new ArgumentNullException(nameof(revoked));
            if (lifetime <= TimeSpan.Zero
                || lifetime.TotalMilliseconds > int.MaxValue)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(lifetime));
            }
            if (_disposed
                || _owner.IsDisposed
                || !_owner.IsHandleCreated
                || !_owner.Visible)
            {
                return false;
            }
            try
            {
                CloseForm(suppressRevocation: true);
                _revoked = revoked;
                var form = new Form
                {
                    Text = "CF7 只读观察",
                    ShowInTaskbar = false,
                    StartPosition = FormStartPosition.Manual,
                    FormBorderStyle = FormBorderStyle.FixedToolWindow,
                    MaximizeBox = false,
                    MinimizeBox = false,
                    ClientSize = new Size(286, 76),
                    Owner = _owner,
                    TopMost = _owner.TopMost
                };
                var label = new Label
                {
                    AutoSize = false,
                    Location = new Point(12, 10),
                    Size = new Size(262, 34),
                    Text = "项目内助手正在只读观察当前界面。\r\n"
                        + "无输入、无像素保留；到期 "
                        + expiresAtUtc.ToLocalTime()
                            .ToString("HH:mm:ss")
                };
                var stop = new Button
                {
                    Text = "停止观察",
                    Location = new Point(187, 46),
                    Size = new Size(87, 24)
                };
                stop.Click += (_, _) => form.Close();
                form.Controls.Add(label);
                form.Controls.Add(stop);
                form.FormClosed += OnIndicatorFormClosed;
                form.VisibleChanged +=
                    OnIndicatorVisibleChanged;
                form.Location = new Point(
                    Math.Max(
                        0,
                        _owner.Right - form.Width),
                    Math.Max(0, _owner.Top));
                _form = form;
                _expiryTimer = new Timer
                {
                    Interval = Math.Max(
                        1,
                        checked((int)
                            lifetime.TotalMilliseconds))
                };
                _expiryTimer.Tick += OnExpiryTimerTick;
                _expiryTimer.Start();
                form.Show(_owner);
                _ = form.Handle;
                return IsAlive;
            }
            catch
            {
                CloseForm(suppressRevocation: true);
                return false;
            }
        }

        public void Close()
        {
            CloseForm(suppressRevocation: true);
        }

        public void Dispose()
        {
            if (_disposed)
                return;
            _disposed = true;
            _owner.VisibleChanged -= OnOwnerVisibleChanged;
            _owner.FormClosed -= OnOwnerFormClosed;
            CloseForm(suppressRevocation: true);
        }

        private void OnIndicatorFormClosed(
            object sender,
            FormClosedEventArgs e)
        {
            if (sender is Form form)
            {
                form.FormClosed -= OnIndicatorFormClosed;
                form.VisibleChanged -=
                    OnIndicatorVisibleChanged;
            }
            if (ReferenceEquals(_form, sender))
                _form = null;
            StopExpiryTimer();
            NotifyRevocation();
        }

        private void OnExpiryTimerTick(
            object sender,
            EventArgs e)
        {
            CloseForm(suppressRevocation: false);
        }

        private void OnIndicatorVisibleChanged(
            object sender,
            EventArgs e)
        {
            if (sender is Form form
                && !form.Visible
                && !_suppressRevocation)
            {
                NotifyRevocation();
            }
        }

        private void OnOwnerVisibleChanged(
            object sender,
            EventArgs e)
        {
            if (!_owner.Visible)
            {
                CloseForm(suppressRevocation: false);
            }
        }

        private void OnOwnerFormClosed(
            object sender,
            FormClosedEventArgs e)
        {
            CloseForm(suppressRevocation: false);
        }

        private void NotifyRevocation()
        {
            if (_suppressRevocation)
                return;
            Action revoked = _revoked;
            _revoked = null;
            revoked?.Invoke();
        }

        private void CloseForm(bool suppressRevocation)
        {
            StopExpiryTimer();
            Form form = _form;
            _form = null;
            Action revoked = _revoked;
            _revoked = null;
            if (form == null)
            {
                if (!suppressRevocation)
                    revoked?.Invoke();
                return;
            }
            bool previous = _suppressRevocation;
            _suppressRevocation =
                previous || suppressRevocation;
            try
            {
                form.FormClosed -= OnIndicatorFormClosed;
                form.VisibleChanged -=
                    OnIndicatorVisibleChanged;
                if (!form.IsDisposed)
                {
                    form.Close();
                    form.Dispose();
                }
            }
            finally
            {
                _suppressRevocation = previous;
            }
            if (!suppressRevocation)
                revoked?.Invoke();
        }

        private void StopExpiryTimer()
        {
            Timer timer = _expiryTimer;
            _expiryTimer = null;
            if (timer == null)
                return;
            timer.Stop();
            timer.Tick -= OnExpiryTimerTick;
            timer.Dispose();
        }
    }
}
