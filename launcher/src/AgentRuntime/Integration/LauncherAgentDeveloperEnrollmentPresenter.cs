using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Drawing;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal sealed class LauncherAgentEnrollmentTargetOption
    {
        public LauncherAgentEnrollmentTargetOption(
            string targetId,
            SurfaceKind kind,
            string displayName)
        {
            if (string.IsNullOrWhiteSpace(targetId))
                throw new ArgumentException(
                    "A target ID is required.",
                    nameof(targetId));
            if (!Enum.IsDefined(kind))
                throw new ArgumentOutOfRangeException(nameof(kind));
            if (string.IsNullOrWhiteSpace(displayName))
                throw new ArgumentException(
                    "A display name is required.",
                    nameof(displayName));
            TargetId = targetId;
            Kind = kind;
            DisplayName = displayName;
        }

        public string TargetId { get; }
        public SurfaceKind Kind { get; }
        public string DisplayName { get; }
    }

    internal sealed class
        LauncherAgentDeveloperEnrollmentPresentationRequest
    {
        public LauncherAgentDeveloperEnrollmentPresentationRequest(
            IEnumerable<string> capabilities,
            IEnumerable<LauncherAgentEnrollmentTargetOption>
                targets)
        {
            string[] frozenCapabilities =
                (capabilities ?? Array.Empty<string>())
                    .Where(value =>
                        !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray();
            LauncherAgentEnrollmentTargetOption[] frozenTargets =
                (targets
                    ?? Array.Empty<
                        LauncherAgentEnrollmentTargetOption>())
                    .Where(value => value != null)
                    .GroupBy(
                        value => value.TargetId,
                        StringComparer.Ordinal)
                    .Select(group => group.First())
                    .OrderBy(value => value.Kind)
                    .ThenBy(
                        value => value.TargetId,
                        StringComparer.Ordinal)
                    .ToArray();
            if (frozenCapabilities.Length == 0)
                throw new ArgumentException(
                    "At least one capability is required.",
                    nameof(capabilities));
            if (frozenTargets.Length == 0
                || frozenTargets.Length
                    > AgentProtocolV1.MaximumTargetScopeItems)
            {
                throw new ArgumentException(
                    "Enrollment requires 1-32 exact targets.",
                    nameof(targets));
            }
            Capabilities =
                Array.AsReadOnly(frozenCapabilities);
            Targets = Array.AsReadOnly(frozenTargets);
        }

        public ReadOnlyCollection<string> Capabilities
        {
            get;
        }

        public ReadOnlyCollection<
            LauncherAgentEnrollmentTargetOption> Targets
        {
            get;
        }
    }

    internal sealed class
        LauncherAgentDeveloperEnrollmentSelection
    {
        private static readonly Regex OpaqueIdPattern =
            new Regex(
                "^[A-Za-z0-9_-]{22,128}$",
                RegexOptions.CultureInvariant
                | RegexOptions.Compiled);

        public LauncherAgentDeveloperEnrollmentSelection(
            string clientInstanceId,
            IEnumerable<string> allowedCapabilities,
            IEnumerable<string> allowedTargets,
            TimeSpan lifetime)
        {
            if (!OpaqueIdPattern.IsMatch(
                    clientInstanceId ?? string.Empty))
            {
                throw new ArgumentException(
                    "Client instance ID must be a 22-128 character opaque ID.",
                    nameof(clientInstanceId));
            }
            string[] capabilities = FreezeRequired(
                allowedCapabilities,
                nameof(allowedCapabilities));
            string[] targets = FreezeRequired(
                allowedTargets,
                nameof(allowedTargets));
            if (targets.Length
                > AgentProtocolV1.MaximumTargetScopeItems
                || targets.Any(target =>
                    !OpaqueIdPattern.IsMatch(target)))
            {
                throw new ArgumentException(
                    "Enrollment targets must be 1-32 opaque IDs.",
                    nameof(allowedTargets));
            }
            if (lifetime <= TimeSpan.Zero
                || lifetime > TimeSpan.FromHours(8))
            {
                throw new ArgumentOutOfRangeException(
                    nameof(lifetime));
            }
            ClientInstanceId = clientInstanceId;
            AllowedCapabilities =
                Array.AsReadOnly(capabilities);
            AllowedTargets = Array.AsReadOnly(targets);
            Lifetime = lifetime;
        }

        public string ClientInstanceId { get; }
        public ReadOnlyCollection<string> AllowedCapabilities
        {
            get;
        }
        public ReadOnlyCollection<string> AllowedTargets
        {
            get;
        }
        public TimeSpan Lifetime { get; }

        private static string[] FreezeRequired(
            IEnumerable<string> values,
            string parameter)
        {
            string[] frozen =
                (values ?? Array.Empty<string>())
                    .Where(value =>
                        !string.IsNullOrWhiteSpace(value))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(value => value, StringComparer.Ordinal)
                    .ToArray();
            if (frozen.Length == 0)
                throw new ArgumentException(
                    "At least one value is required.",
                    parameter);
            return frozen;
        }
    }

    internal interface
        ILauncherAgentDeveloperEnrollmentPresenter
    {
        LauncherAgentDeveloperEnrollmentSelection Present(
            LauncherAgentDeveloperEnrollmentPresentationRequest
                request);
    }

    /// <summary>
    /// Launcher-owned developer enrollment UI. Its HWND is registered as a
    /// human-only security surface before becoming visible, so Agent capture
    /// and input can never authorize or drive the enrollment itself.
    /// </summary>
    internal sealed class
        LauncherAgentDeveloperEnrollmentPresenter
        : ILauncherAgentDeveloperEnrollmentPresenter
    {
        private readonly Form _owner;
        private readonly SessionSurfaceHostController
            _controller;
        private readonly LauncherHumanOnlySurfacePublisher
            _surfacePublisher;
        private readonly Func<Form, Form, DialogResult>
            _showDialog;

        public LauncherAgentDeveloperEnrollmentPresenter(
            Form owner,
            SessionSurfaceHostController controller,
            SessionRegistryHostOwner hostOwner)
            : this(
                owner,
                controller,
                hostOwner,
                (dialog, dialogOwner) =>
                    dialog.ShowDialog(dialogOwner))
        {
        }

        internal LauncherAgentDeveloperEnrollmentPresenter(
            Form owner,
            SessionSurfaceHostController controller,
            SessionRegistryHostOwner hostOwner,
            Func<Form, Form, DialogResult> showDialog)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _controller = controller
                ?? throw new ArgumentNullException(
                    nameof(controller));
            _surfacePublisher =
                new LauncherHumanOnlySurfacePublisher(
                    _controller,
                    hostOwner
                        ?? throw new ArgumentNullException(
                            nameof(hostOwner)));
            _showDialog = showDialog
                ?? throw new ArgumentNullException(
                    nameof(showDialog));
        }

        public LauncherAgentDeveloperEnrollmentSelection Present(
            LauncherAgentDeveloperEnrollmentPresentationRequest
                request)
        {
            if (request == null)
                throw new ArgumentNullException(nameof(request));
            if (_owner.IsDisposed
                || !_owner.IsHandleCreated)
            {
                return null;
            }
            if (_owner.InvokeRequired)
            {
                try
                {
                    return (LauncherAgentDeveloperEnrollmentSelection)
                        _owner.Invoke(
                            new Func<
                                LauncherAgentDeveloperEnrollmentSelection>(
                                () => PresentOnUiThread(request)));
                }
                catch
                {
                    return null;
                }
            }
            return PresentOnUiThread(request);
        }

        private LauncherAgentDeveloperEnrollmentSelection
            PresentOnUiThread(
                LauncherAgentDeveloperEnrollmentPresentationRequest
                    request)
        {
            using var dialog =
                new EnrollmentDialog(request);
            SessionSnapshot session = _controller.Snapshot;
            var reauthorizationExpectation =
                new SessionMutationExpectation
                {
                    SessionId = session.SessionId,
                    LifecycleGeneration =
                        session.LifecycleGeneration,
                    AttemptId = session.AttemptId,
                    AttemptGeneration =
                        session.AttemptGeneration
                };
            Position(dialog);
            dialog.CreateControl();
            _ = dialog.Handle;
            Rectangle clientBounds =
                dialog.RectangleToScreen(
                    dialog.ClientRectangle);
            var descriptor =
                new WingsHumanOnlySurfaceDescriptor(
                    OpaqueIdGenerator.Create(
                        "developer_enrollment"),
                    dialog.Handle.ToInt64(),
                    _owner.Handle.ToInt64(),
                    dialog.Bounds,
                    clientBounds,
                    dialog.DeviceDpi);
            if (!_surfacePublisher.TryPublish(
                    descriptor,
                    out IWingsHumanOnlySurfaceLease lease,
                    out _))
            {
                return null;
            }
            DialogResult result;
            try
            {
                result = _showDialog(dialog, _owner);
            }
            finally
            {
                lease.Dispose();
            }
            // OK, Cancel, and user-close are all direct human interactions.
            // Clear the security latch only after the HWND is unpublished
            // and only if the exact session/attempt is still current.
            if (!_surfacePublisher
                    .TryAcknowledgeHumanReauthorization(
                        reauthorizationExpectation,
                        out _))
            {
                return null;
            }
            return result == DialogResult.OK
                ? dialog.Selection
                : null;
        }

        private void Position(Form dialog)
        {
            Rectangle ownerBounds = _owner.Bounds;
            int x = ownerBounds.Left
                + Math.Max(
                    0,
                    (ownerBounds.Width - dialog.Width) / 2);
            int y = ownerBounds.Top
                + Math.Max(
                    0,
                    (ownerBounds.Height - dialog.Height) / 2);
            dialog.StartPosition =
                FormStartPosition.Manual;
            dialog.Location = new Point(x, y);
        }

        private sealed class EnrollmentDialog : Form
        {
            private readonly
                LauncherAgentDeveloperEnrollmentPresentationRequest
                    _request;
            private readonly TextBox _clientId;
            private readonly CheckedListBox _capabilities;
            private readonly CheckedListBox _targets;
            private readonly ComboBox _lifetime;
            private readonly Label _error;

            public EnrollmentDialog(
                LauncherAgentDeveloperEnrollmentPresentationRequest
                    request)
            {
                _request = request;
                Text = "Agent 开发者授权";
                FormBorderStyle =
                    FormBorderStyle.FixedDialog;
                MaximizeBox = false;
                MinimizeBox = false;
                ShowInTaskbar = false;
                Width = 720;
                Height = 690;
                Font = SystemFonts.MessageBoxFont;

                var layout = new TableLayoutPanel
                {
                    Dock = DockStyle.Fill,
                    Padding = new Padding(16),
                    ColumnCount = 1,
                    RowCount = 10
                };
                layout.RowStyles.Add(
                    new RowStyle(SizeType.AutoSize));
                layout.RowStyles.Add(
                    new RowStyle(SizeType.AutoSize));
                layout.RowStyles.Add(
                    new RowStyle(SizeType.AutoSize));
                layout.RowStyles.Add(
                    new RowStyle(
                        SizeType.Absolute,
                        190));
                layout.RowStyles.Add(
                    new RowStyle(SizeType.AutoSize));
                layout.RowStyles.Add(
                    new RowStyle(
                        SizeType.Absolute,
                        150));
                layout.RowStyles.Add(
                    new RowStyle(SizeType.AutoSize));
                layout.RowStyles.Add(
                    new RowStyle(SizeType.AutoSize));
                layout.RowStyles.Add(
                    new RowStyle(
                        SizeType.Percent,
                        100));
                layout.RowStyles.Add(
                    new RowStyle(SizeType.AutoSize));
                Controls.Add(layout);

                layout.Controls.Add(
                    new Label
                    {
                        AutoSize = true,
                        MaximumSize =
                            new Size(660, 0),
                        Text =
                            "这会为同一 Windows 用户创建一个限时开发者凭据。"
                            + "授权只覆盖下方明确勾选的能力和当前窗口；"
                            + "拒绝或关闭不会影响游戏。"
                    });
                layout.Controls.Add(
                    new Label
                    {
                        AutoSize = true,
                        Margin = new Padding(0, 12, 0, 3),
                        Text =
                            "客户端实例 ID（22–128 位 base64url 字符）"
                    });
                _clientId = new TextBox
                {
                    Dock = DockStyle.Top
                };
                layout.Controls.Add(_clientId);

                _capabilities =
                    new CheckedListBox
                    {
                        Dock = DockStyle.Fill,
                        CheckOnClick = true
                    };
                foreach (string capability
                    in request.Capabilities)
                {
                    int index =
                        _capabilities.Items.Add(
                            new CapabilityItem(
                                capability));
                    if (IsDefaultReadOnlyCapability(
                            capability))
                    {
                        _capabilities.SetItemChecked(
                            index,
                            true);
                    }
                }
                layout.Controls.Add(_capabilities);

                layout.Controls.Add(
                    new Label
                    {
                        AutoSize = true,
                        Margin =
                            new Padding(0, 10, 0, 3),
                        Text = "当前精确目标"
                    });
                _targets = new CheckedListBox
                {
                    Dock = DockStyle.Fill,
                    CheckOnClick = true
                };
                foreach (
                    LauncherAgentEnrollmentTargetOption target
                    in request.Targets)
                {
                    int index = _targets.Items.Add(
                        new TargetItem(target));
                    _targets.SetItemChecked(
                        index,
                        true);
                }
                layout.Controls.Add(_targets);

                layout.Controls.Add(
                    new Label
                    {
                        AutoSize = true,
                        Margin =
                            new Padding(0, 10, 0, 3),
                        Text = "有效期"
                    });
                _lifetime = new ComboBox
                {
                    DropDownStyle =
                        ComboBoxStyle.DropDownList,
                    Width = 180
                };
                _lifetime.Items.Add(
                    new LifetimeItem(
                        "15 分钟",
                        TimeSpan.FromMinutes(15)));
                _lifetime.Items.Add(
                    new LifetimeItem(
                        "1 小时",
                        TimeSpan.FromHours(1)));
                _lifetime.Items.Add(
                    new LifetimeItem(
                        "4 小时",
                        TimeSpan.FromHours(4)));
                _lifetime.Items.Add(
                    new LifetimeItem(
                        "8 小时（上限）",
                        TimeSpan.FromHours(8)));
                _lifetime.SelectedIndex = 1;
                layout.Controls.Add(_lifetime);

                _error = new Label
                {
                    AutoSize = true,
                    ForeColor = Color.Firebrick,
                    Margin = new Padding(0, 8, 0, 0)
                };
                layout.Controls.Add(_error);

                var buttons = new FlowLayoutPanel
                {
                    AutoSize = true,
                    Dock = DockStyle.Fill,
                    FlowDirection =
                        FlowDirection.RightToLeft
                };
                var cancel = new Button
                {
                    Text = "取消",
                    DialogResult =
                        DialogResult.Cancel,
                    AutoSize = true
                };
                var allow = new Button
                {
                    Text = "创建限时凭据",
                    AutoSize = true
                };
                allow.Click += (_, _) =>
                    TryAccept();
                buttons.Controls.Add(cancel);
                buttons.Controls.Add(allow);
                layout.Controls.Add(buttons);
                AcceptButton = allow;
                CancelButton = cancel;
            }

            public LauncherAgentDeveloperEnrollmentSelection
                Selection
            {
                get;
                private set;
            }

            private void TryAccept()
            {
                try
                {
                    string[] capabilities =
                        _capabilities.CheckedItems
                            .Cast<CapabilityItem>()
                            .Select(item => item.Value)
                            .ToArray();
                    string[] targets =
                        _targets.CheckedItems
                            .Cast<TargetItem>()
                            .Select(
                                item =>
                                    item.Option.TargetId)
                            .ToArray();
                    var lifetime =
                        (LifetimeItem)
                            _lifetime.SelectedItem;
                    if (capabilities.Any(
                            capability =>
                                !_request.Capabilities
                                    .Contains(
                                        capability,
                                        StringComparer.Ordinal))
                        || targets.Any(
                            target =>
                                !_request.Targets.Any(
                                    option =>
                                        string.Equals(
                                            option.TargetId,
                                            target,
                                            StringComparison.Ordinal))))
                    {
                        throw new InvalidOperationException(
                            "选择已失效，请重新打开授权窗口。");
                    }
                    Selection =
                        new LauncherAgentDeveloperEnrollmentSelection(
                            _clientId.Text.Trim(),
                            capabilities,
                            targets,
                            lifetime.Lifetime);
                    DialogResult = DialogResult.OK;
                    Close();
                }
                catch (Exception exception)
                {
                    _error.Text = exception.Message;
                }
            }

            private static bool IsDefaultReadOnlyCapability(
                string capability)
            {
                return capability
                        == AgentCapabilitiesV1.SessionStatus
                    || capability
                        == AgentCapabilitiesV1
                            .ObservationGrantManage
                    || capability
                        == AgentCapabilitiesV1.ListWindows
                    || capability
                        == AgentCapabilitiesV1.GetWindow
                    || capability
                        == AgentCapabilitiesV1
                            .GetWindowState
                    || capability
                        == AgentCapabilitiesV1
                            .ObservationCapture
                    || capability
                        == AgentCapabilitiesV1.ContentRead
                    || capability
                        == "observe:"
                            + ObservationDataScopesV1
                                .WindowMetadata
                    || capability
                        == "observe:"
                            + ObservationDataScopesV1
                                .Pixels;
            }
        }

        private sealed class CapabilityItem
        {
            public CapabilityItem(string value)
            {
                Value = value;
            }

            public string Value { get; }

            public override string ToString()
            {
                return CapabilityDisplay(Value)
                    + "  [" + Value + "]";
            }
        }

        private sealed class TargetItem
        {
            public TargetItem(
                LauncherAgentEnrollmentTargetOption option)
            {
                Option = option;
            }

            public LauncherAgentEnrollmentTargetOption Option
            {
                get;
            }

            public override string ToString()
            {
                return Option.DisplayName
                    + "  [" + SurfaceKindDisplay(
                        Option.Kind) + "]";
            }
        }

        private sealed class LifetimeItem
        {
            public LifetimeItem(
                string display,
                TimeSpan lifetime)
            {
                Display = display;
                Lifetime = lifetime;
            }

            public string Display { get; }
            public TimeSpan Lifetime { get; }

            public override string ToString()
            {
                return Display;
            }
        }

        private static string CapabilityDisplay(string value)
        {
            if (value.StartsWith(
                    "observe:",
                    StringComparison.Ordinal))
            {
                return "读取 " + value.Substring(
                    "observe:".Length);
            }
            if (value.StartsWith(
                    "input.",
                    StringComparison.Ordinal)
                || value.StartsWith(
                    "semantic.",
                    StringComparison.Ordinal))
            {
                return "交互输入";
            }
            if (value.StartsWith(
                    "domain.",
                    StringComparison.Ordinal))
            {
                return "领域事务";
            }
            if (value.StartsWith(
                    "observation.",
                    StringComparison.Ordinal)
                || value == AgentCapabilitiesV1.ContentRead)
            {
                return "观察与内容读取";
            }
            return "运行时方法";
        }

        private static string SurfaceKindDisplay(
            SurfaceKind kind)
        {
            switch (kind)
            {
                case SurfaceKind.Launcher:
                    return "启动器";
                case SurfaceKind.Flash:
                    return "Flash 游戏";
                case SurfaceKind.WebOverlay:
                    return "Web 面板";
                case SurfaceKind.NativeHud:
                    return "原生 HUD";
                case SurfaceKind.WingsShell:
                    return "Wings";
                case SurfaceKind.BusinessModal:
                    return "业务模态窗";
                default:
                    return kind.ToString();
            }
        }
    }
}
