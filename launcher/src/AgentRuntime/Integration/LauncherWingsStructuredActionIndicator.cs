using System;
using System.Drawing;
using System.Windows.Forms;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal enum WingsStructuredActionIndicatorKind
    {
        WindowActivation,
        HairChange
    }

    internal interface IWingsStructuredActionIndicator
        : IDisposable
    {
        bool IsAlive { get; }

        bool TryShow(
            DateTimeOffset expiresAtUtc,
            TimeSpan lifetime,
            Action revoked);

        void Close();
    }

    /// <summary>
    /// Launcher-owned, non-observable indicator for one short structured
    /// action connection. It is not a registry target. Closing, hiding or
    /// expiry invokes the coordinator's whole-connection revocation callback.
    /// </summary>
    internal sealed class LauncherWingsStructuredActionIndicator
        : IWingsStructuredActionIndicator
    {
        private readonly Form _owner;
        private readonly WingsStructuredActionIndicatorKind _kind;
        private Form _form;
        private Timer _expiryTimer;
        private Action _revoked;
        private bool _suppressRevocation;
        private volatile bool _disposed;

        internal LauncherWingsStructuredActionIndicator(
            Form owner)
            : this(
                owner,
                WingsStructuredActionIndicatorKind
                    .WindowActivation)
        {
        }

        internal LauncherWingsStructuredActionIndicator(
            Form owner,
            WingsStructuredActionIndicatorKind kind)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            if (!Enum.IsDefined(kind))
                throw new ArgumentOutOfRangeException(nameof(kind));
            _kind = kind;
            _owner.VisibleChanged += OnOwnerVisibleChanged;
            _owner.FormClosed += OnOwnerFormClosed;
        }

        internal Form FormForTest => InvokeOnOwner(
            () => _form,
            null);

        public bool IsAlive => InvokeOnOwner(
            () => !_disposed
                && _form != null
                && !_form.IsDisposed
                && _form.IsHandleCreated
                && _form.Visible
                && !_owner.IsDisposed
                && _owner.Visible,
            false);

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
            return InvokeOnOwner(
                () => TryShowOnUi(
                    expiresAtUtc,
                    lifetime,
                    revoked),
                false);
        }

        public void Close()
        {
            InvokeOnOwner(
                () =>
                {
                    CloseOnUi(suppressRevocation: true);
                    return true;
                },
                false);
        }

        public void Dispose()
        {
            if (_disposed)
                return;
            InvokeOnOwner(
                () =>
                {
                    if (_disposed)
                        return true;
                    _disposed = true;
                    _owner.VisibleChanged -=
                        OnOwnerVisibleChanged;
                    _owner.FormClosed -=
                        OnOwnerFormClosed;
                    CloseOnUi(suppressRevocation: true);
                    return true;
                },
                false);
            _disposed = true;
        }

        private bool TryShowOnUi(
            DateTimeOffset expiresAtUtc,
            TimeSpan lifetime,
            Action revoked)
        {
            if (_disposed
                || _owner.IsDisposed
                || !_owner.IsHandleCreated
                || !_owner.Visible)
            {
                return false;
            }
            try
            {
                CloseOnUi(suppressRevocation: true);
                _revoked = revoked;
                var form = new Form
                {
                    Text = "CF7 临时动作授权",
                    ShowInTaskbar = false,
                    StartPosition = FormStartPosition.Manual,
                    FormBorderStyle =
                        FormBorderStyle.FixedToolWindow,
                    MaximizeBox = false,
                    MinimizeBox = false,
                    ClientSize = new Size(330, 102),
                    Owner = _owner,
                    TopMost = _owner.TopMost
                };
                var label = new Label
                {
                    AutoSize = false,
                    Location = new Point(12, 9),
                    Size = new Size(306, 58),
                    Text = _kind
                        == WingsStructuredActionIndicatorKind
                            .HairChange
                        ? "已授权一次结构化发型事务。\r\n"
                            + "同一连接、一次性写入；像素不落盘。到期 "
                            + expiresAtUtc.ToLocalTime()
                                .ToString("HH:mm:ss")
                        : "已授权 1 次“激活游戏窗口”。\r\n"
                            + "一次性像素绑定；不点击、不输入、"
                            + "不持久化。到期 "
                        + expiresAtUtc.ToLocalTime()
                            .ToString("HH:mm:ss")
                };
                var stop = new Button
                {
                    Text = "立即撤销",
                    Location = new Point(231, 70),
                    Size = new Size(87, 24)
                };
                stop.Click += (_, _) => form.Close();
                form.Controls.Add(label);
                form.Controls.Add(stop);
                form.FormClosed += OnIndicatorFormClosed;
                form.VisibleChanged +=
                    OnIndicatorVisibleChanged;
                form.Location = new Point(
                    Math.Max(0, _owner.Right - form.Width),
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
                return IsAliveOnUi();
            }
            catch
            {
                CloseOnUi(suppressRevocation: true);
                return false;
            }
        }

        private void OnIndicatorFormClosed(
            object sender,
            FormClosedEventArgs args)
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

        private void OnIndicatorVisibleChanged(
            object sender,
            EventArgs args)
        {
            if (sender is Form form
                && !form.Visible
                && !_suppressRevocation)
            {
                NotifyRevocation();
            }
        }

        private void OnExpiryTimerTick(
            object sender,
            EventArgs args)
        {
            CloseOnUi(suppressRevocation: false);
        }

        private void OnOwnerVisibleChanged(
            object sender,
            EventArgs args)
        {
            if (!_owner.Visible)
                CloseOnUi(suppressRevocation: false);
        }

        private void OnOwnerFormClosed(
            object sender,
            FormClosedEventArgs args)
        {
            CloseOnUi(suppressRevocation: false);
        }

        private bool IsAliveOnUi()
        {
            return !_disposed
                && _form != null
                && !_form.IsDisposed
                && _form.IsHandleCreated
                && _form.Visible
                && !_owner.IsDisposed
                && _owner.Visible;
        }

        private void NotifyRevocation()
        {
            if (_suppressRevocation)
                return;
            Action revoked = _revoked;
            _revoked = null;
            revoked?.Invoke();
        }

        private void CloseOnUi(bool suppressRevocation)
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

        private T InvokeOnOwner<T>(
            Func<T> action,
            T fallback)
        {
            try
            {
                if (_owner.IsDisposed
                    || !_owner.IsHandleCreated)
                {
                    return fallback;
                }
                if (_owner.InvokeRequired)
                {
                    return (T)_owner.Invoke(action);
                }
                return action();
            }
            catch
            {
                return fallback;
            }
        }
    }
}
