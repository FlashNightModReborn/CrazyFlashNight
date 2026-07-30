using System;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal enum WingsNotificationKind
    {
        Information,
        Permission,
        Warning,
        Error
    }

    internal sealed class WingsShellNotification
    {
        public WingsShellNotification(
            WingsNotificationKind kind,
            string text)
        {
            if (!Enum.IsDefined(kind))
                throw new ArgumentOutOfRangeException(nameof(kind));
            WingsProtocolValue.RequireText(
                text,
                512,
                nameof(text));
            Kind = kind;
            Text = text;
        }

        public WingsNotificationKind Kind { get; }
        public string Text { get; }
    }

    /// <summary>
    /// Host callbacks contain lifecycle intent only. There is deliberately no
    /// method that signs consent, grants observation, grants a write lease, or
    /// exits the game.
    /// </summary>
    internal interface IWingsShellHostActions
    {
        bool StructuredWindowActivationAvailable { get; }
        bool StructuredHairChangeAvailable { get; }
        void SubmitDialogue(string text);
        void ApplyPauseEffects(WingsShellEffect requiredEffects);
        void RequestFreshActivation();
        void RequestNeutralConsentPresentation();
        void RequestActivateCurrentGameWindow();
        void RequestChangeHair();
    }

    /// <summary>
    /// Composable production host for the owned WinForms shell. Program may
    /// instantiate it later without making the shell an authority.
    /// </summary>
    internal sealed class WingsShellHost : IDisposable
    {
        private readonly Form _owner;
        private readonly WingsPersonaStateMachine _personaState;
        private readonly WingsShellStateMachine _shellState;
        private readonly IWingsShellHostActions _hostActions;
        private readonly WingsConsentPresentationPort _consentPort;
        private WingsShellForm _form;
        private bool _disposed;

        public WingsShellHost(
            Form owner,
            WingsPersonaStateMachine personaState,
            WingsShellStateMachine shellState,
            IWingsShellHostActions hostActions,
            WingsConsentPresentationPort consentPort)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _personaState = personaState
                ?? throw new ArgumentNullException(
                    nameof(personaState));
            _shellState = shellState
                ?? throw new ArgumentNullException(
                    nameof(shellState));
            _hostActions = hostActions
                ?? throw new ArgumentNullException(
                    nameof(hostActions));
            _consentPort = consentPort
                ?? throw new ArgumentNullException(
                    nameof(consentPort));
            if (!ReferenceEquals(_consentPort.Owner, _owner))
                throw new ArgumentException(
                    "Consent port must share the shell owner.",
                    nameof(consentPort));
            _owner.FormClosed += OnOwnerFormClosed;
        }

        public WingsShellSnapshot ShellSnapshot =>
            _shellState.Snapshot;

        public WingsPersonaStateSnapshot PersonaSnapshot =>
            _personaState.Snapshot;

        internal WingsShellForm FormForTest => _form;

        public bool TryShowShell(out string reasonCode)
        {
            return InvokeOnOwner(
                () =>
                {
                    if (!OwnerAvailable(out string reason))
                        return OperationResult.Fail(reason);
                    WingsShellForm form = EnsureForm();
                    _shellState.ShowPersona();
                    ProjectState(form);
                    if (!form.Visible)
                        form.Show(_owner);
                    form.BringToFront();
                    return OperationResult.Success();
                },
                out reasonCode);
        }

        public bool TryHidePersona(out string reasonCode)
        {
            return InvokeOnOwner(
                () =>
                {
                    if (_disposed)
                    {
                        return OperationResult.Fail(
                            "wings_shell_disposed");
                    }
                    _shellState.HidePersona();
                    if (_form != null && !_form.IsDisposed)
                        _form.HideForHost();
                    return OperationResult.Success();
                },
                out reasonCode);
        }

        public bool TryPause(
            out string reasonCode,
            string neutralPausePolicyReceiptId = null,
            INeutralPausePolicyAuthority pausePolicyAuthority = null)
        {
            return InvokeOnOwner(
                () =>
                {
                    if (!OwnerAvailable(out string reason))
                        return OperationResult.Fail(reason);
                    WingsShellTransition transition =
                        _shellState.Pause(
                            neutralPausePolicyReceiptId,
                            pausePolicyAuthority);
                    ProjectState(EnsureForm());
                    try
                    {
                        _hostActions.ApplyPauseEffects(
                            transition.RequiredEffects);
                    }
                    catch
                    {
                        SetNotificationOnUi(
                            new WingsShellNotification(
                                WingsNotificationKind.Error,
                                "暂停请求未被 Host 完整确认；"
                                + "权限状态按安全方向保持暂停。"));
                        return OperationResult.Fail(
                            "pause_effect_sink_failed");
                    }
                    return OperationResult.Success();
                },
                out reasonCode);
        }

        public bool TryResume(out string reasonCode)
        {
            return InvokeOnOwner(
                () =>
                {
                    if (!OwnerAvailable(out string reason))
                        return OperationResult.Fail(reason);
                    WingsShellTransition transition =
                        _shellState.ResumeShell();
                    ProjectState(EnsureForm());
                    if (transition.RequiredEffects.HasFlag(
                            WingsShellEffect
                                .RequiresFreshActivation))
                    {
                        try
                        {
                            _hostActions.RequestFreshActivation();
                        }
                        catch
                        {
                            SetNotificationOnUi(
                                new WingsShellNotification(
                                    WingsNotificationKind.Error,
                                    "恢复需要在 Launcher "
                                    + "中重新确认观察状态。"));
                            return OperationResult.Fail(
                                "fresh_activation_sink_failed");
                        }
                    }
                    return OperationResult.Success();
                },
                out reasonCode);
        }

        public bool TryAppendCheckedDialogue(
            WingsCheckedOutput output,
            out string reasonCode)
        {
            if (output == null)
                throw new ArgumentNullException(nameof(output));
            if (!output.Accepted)
            {
                reasonCode = "unchecked_dialogue_rejected";
                return false;
            }
            return InvokeOnOwner(
                () =>
                {
                    if (!OwnerAvailable(out string reason))
                        return OperationResult.Fail(reason);
                    EnsureForm().AppendAssistantText(output.Text);
                    return OperationResult.Success();
                },
                out reasonCode);
        }

        public bool TryNotify(
            WingsShellNotification notification,
            out string reasonCode)
        {
            if (notification == null)
                throw new ArgumentNullException(nameof(notification));
            return InvokeOnOwner(
                () =>
                {
                    if (!OwnerAvailable(out string reason))
                        return OperationResult.Fail(reason);
                    SetNotificationOnUi(notification);
                    return OperationResult.Success();
                },
                out reasonCode);
        }

        internal void RefreshProjectedState()
        {
            if (_disposed
                || _form == null
                || _form.IsDisposed)
            {
                return;
            }
            if (_owner.InvokeRequired)
            {
                _owner.Invoke(
                    new Action(
                        () => ProjectState(_form)));
            }
            else
            {
                ProjectState(_form);
            }
        }

        public bool TryPresentConsent(
            TrustedNeutralConsentPrompt prompt,
            out string reasonCode)
        {
            if (_disposed)
            {
                reasonCode = "wings_shell_disposed";
                return false;
            }
            return _consentPort.TryPresent(prompt, out reasonCode);
        }

        public void Dispose()
        {
            if (_disposed)
                return;
            if (_owner.IsDisposed || !_owner.IsHandleCreated)
            {
                DisposeOnUi();
                return;
            }
            if (_owner.InvokeRequired)
                _owner.Invoke(new Action(DisposeOnUi));
            else
                DisposeOnUi();
        }

        private WingsShellForm EnsureForm()
        {
            if (_form != null && !_form.IsDisposed)
                return _form;
            _form = new WingsShellForm
            {
                Owner = _owner
            };
            _form.HideRequested += OnHideRequested;
            _form.PauseToggleRequested += OnPauseToggleRequested;
            _form.DialogueSubmitted += OnDialogueSubmitted;
            _form.ConsentPresentationRequested +=
                OnConsentPresentationRequested;
            _form.ActivateCurrentGameWindowRequested +=
                OnActivateCurrentGameWindowRequested;
            _form.ChangeHairRequested +=
                OnChangeHairRequested;
            _form.FormClosed += OnShellFormClosed;
            ProjectState(_form);
            return _form;
        }

        private void OnHideRequested(object sender, EventArgs e)
        {
            TryHidePersona(out _);
        }

        private void OnPauseToggleRequested(object sender, EventArgs e)
        {
            if (_shellState.Snapshot.Paused)
                TryResume(out _);
            else
                TryPause(out _);
        }

        private void OnDialogueSubmitted(
            object sender,
            string text)
        {
            try
            {
                _hostActions.SubmitDialogue(text);
                _form?.AppendUserText(text);
            }
            catch
            {
                SetNotificationOnUi(
                    new WingsShellNotification(
                        WingsNotificationKind.Error,
                        "消息未被 Host 接收。"));
            }
        }

        private void OnConsentPresentationRequested(
            object sender,
            EventArgs e)
        {
            try
            {
                _hostActions.RequestNeutralConsentPresentation();
            }
            catch
            {
                SetNotificationOnUi(
                    new WingsShellNotification(
                        WingsNotificationKind.Error,
                        "Launcher 暂时无法展示中性授权界面。"));
            }
        }

        private void OnActivateCurrentGameWindowRequested(
            object sender,
            EventArgs e)
        {
            try
            {
                _hostActions.RequestActivateCurrentGameWindow();
            }
            catch
            {
                SetNotificationOnUi(
                    new WingsShellNotification(
                        WingsNotificationKind.Error,
                        "Launcher 暂时无法提交激活窗口请求。"));
            }
        }

        private void OnChangeHairRequested(
            object sender,
            EventArgs e)
        {
            try
            {
                _hostActions.RequestChangeHair();
            }
            catch
            {
                SetNotificationOnUi(
                    new WingsShellNotification(
                        WingsNotificationKind.Error,
                        "Launcher 暂时无法提交发型切换请求。"));
            }
        }

        private void OnShellFormClosed(
            object sender,
            FormClosedEventArgs e)
        {
            if (sender is WingsShellForm form)
            {
                form.HideRequested -= OnHideRequested;
                form.PauseToggleRequested -=
                    OnPauseToggleRequested;
                form.DialogueSubmitted -= OnDialogueSubmitted;
                form.ConsentPresentationRequested -=
                    OnConsentPresentationRequested;
                form.ActivateCurrentGameWindowRequested -=
                    OnActivateCurrentGameWindowRequested;
                form.ChangeHairRequested -=
                    OnChangeHairRequested;
                form.FormClosed -= OnShellFormClosed;
            }
            _form = null;
        }

        private void OnOwnerFormClosed(
            object sender,
            FormClosedEventArgs e)
        {
            DisposeOnUi();
        }

        private void SetNotificationOnUi(
            WingsShellNotification notification)
        {
            EnsureForm().SetNotification(notification);
        }

        private void ProjectState(WingsShellForm form)
        {
            form.ProjectState(
                _shellState.Snapshot,
                _personaState.Snapshot,
                _hostActions
                    .StructuredWindowActivationAvailable,
                _hostActions
                    .StructuredHairChangeAvailable);
        }

        private bool OwnerAvailable(out string reasonCode)
        {
            if (_disposed)
            {
                reasonCode = "wings_shell_disposed";
                return false;
            }
            if (_owner.IsDisposed || !_owner.IsHandleCreated)
            {
                reasonCode = "wings_shell_owner_unavailable";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool InvokeOnOwner(
            Func<OperationResult> action,
            out string reasonCode)
        {
            if (_owner.IsDisposed)
            {
                reasonCode = "wings_shell_owner_unavailable";
                return false;
            }
            OperationResult result;
            if (_owner.InvokeRequired)
            {
                result = (OperationResult)_owner.Invoke(action);
            }
            else
            {
                result = action();
            }
            reasonCode = result.ReasonCode;
            return result.Accepted;
        }

        private void DisposeOnUi()
        {
            if (_disposed)
                return;
            _disposed = true;
            _owner.FormClosed -= OnOwnerFormClosed;
            _consentPort.Dispose();
            WingsShellForm form = _form;
            if (form != null)
            {
                form.CloseForOwnerShutdown();
                form.Dispose();
                _form = null;
            }
        }

        private sealed class OperationResult
        {
            private OperationResult(
                bool accepted,
                string reasonCode)
            {
                Accepted = accepted;
                ReasonCode = reasonCode;
            }

            public bool Accepted { get; }
            public string ReasonCode { get; }

            public static OperationResult Success()
            {
                return new OperationResult(true, null);
            }

            public static OperationResult Fail(string reasonCode)
            {
                return new OperationResult(false, reasonCode);
            }
        }
    }

    internal sealed class WingsShellForm : Form
    {
        private readonly RichTextBox _transcript;
        private readonly Label _notification;
        private readonly Label _state;
        private readonly TextBox _input;
        private bool _allowClose;

        public WingsShellForm()
        {
            Text = "项目内助手";
            Name = "WingsShell";
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            ShowInTaskbar = false;
            MinimizeBox = false;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(430, 430);
            AutoScaleMode = AutoScaleMode.Dpi;

            var layout = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                Padding = new Padding(12),
                ColumnCount = 1,
                RowCount = 6
            };
            layout.ColumnStyles.Add(
                new ColumnStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(
                new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            Controls.Add(layout);

            _state = new Label
            {
                AutoSize = true,
                Font = new Font(
                    SystemFonts.MessageBoxFont,
                    FontStyle.Bold)
            };
            _notification = new Label
            {
                AutoSize = true,
                MaximumSize = new Size(390, 0),
                ForeColor = Color.DimGray,
                Text = "仅使用当前存档已公开信息。"
            };
            _transcript = new RichTextBox
            {
                Dock = DockStyle.Fill,
                ReadOnly = true,
                DetectUrls = false,
                BorderStyle = BorderStyle.FixedSingle,
                BackColor = SystemColors.Window
            };
            _input = new TextBox
            {
                Dock = DockStyle.Fill,
                MaxLength = 512
            };
            var sendRow = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                ColumnCount = 2,
                AutoSize = true
            };
            sendRow.ColumnStyles.Add(
                new ColumnStyle(SizeType.Percent, 100));
            sendRow.ColumnStyles.Add(
                new ColumnStyle(SizeType.AutoSize));
            SendButton = new Button
            {
                Text = "发送",
                AutoSize = true
            };
            sendRow.Controls.Add(_input, 0, 0);
            sendRow.Controls.Add(SendButton, 1, 0);

            var actions = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                AutoSize = true,
                FlowDirection = FlowDirection.LeftToRight
            };
            PauseButton = new Button
            {
                Text = "暂停",
                AutoSize = true
            };
            ConsentButton = new Button
            {
                Text = "查看权限",
                AutoSize = true
            };
            HideButton = new Button
            {
                Text = "隐藏助手",
                AutoSize = true
            };
            ActivateGameButton = new Button
            {
                Text = "激活游戏窗口",
                AutoSize = true,
                Visible = false,
                Enabled = false
            };
            ChangeHairButton = new Button
            {
                Text = "更换发型",
                AutoSize = true,
                Visible = false,
                Enabled = false
            };
            actions.Controls.Add(PauseButton);
            actions.Controls.Add(ConsentButton);
            actions.Controls.Add(ActivateGameButton);
            actions.Controls.Add(ChangeHairButton);
            actions.Controls.Add(HideButton);

            layout.Controls.Add(_state);
            layout.Controls.Add(_notification);
            layout.Controls.Add(_transcript);
            layout.Controls.Add(sendRow);
            layout.Controls.Add(actions);
            layout.Controls.Add(new Label
            {
                AutoSize = true,
                ForeColor = Color.DimGray,
                Text = "真实权限由 Launcher 中性界面确认；"
                    + "关闭本窗口不会退出游戏。"
            });

            SendButton.Click += (_, __) => SubmitDialogue();
            _input.KeyDown += (_, e) =>
            {
                if (e.KeyCode == Keys.Enter
                    && !e.Shift)
                {
                    e.SuppressKeyPress = true;
                    SubmitDialogue();
                }
            };
            PauseButton.Click += (_, __) =>
                PauseToggleRequested?.Invoke(
                    this,
                    EventArgs.Empty);
            ConsentButton.Click += (_, __) =>
                ConsentPresentationRequested?.Invoke(
                    this,
                    EventArgs.Empty);
            ActivateGameButton.Click += (_, __) =>
                ActivateCurrentGameWindowRequested?.Invoke(
                    this,
                    EventArgs.Empty);
            ChangeHairButton.Click += (_, __) =>
                ChangeHairRequested?.Invoke(
                    this,
                    EventArgs.Empty);
            HideButton.Click += (_, __) =>
                HideRequested?.Invoke(this, EventArgs.Empty);
        }

        internal Button SendButton { get; }
        internal Button PauseButton { get; }
        internal Button ConsentButton { get; }
        internal Button ActivateGameButton { get; }
        internal Button ChangeHairButton { get; }
        internal Button HideButton { get; }
        internal string TranscriptText => _transcript.Text;
        internal string NotificationText => _notification.Text;
        internal string StateText => _state.Text;
        internal TextBox InputForTest => _input;

        public event EventHandler HideRequested;
        public event EventHandler PauseToggleRequested;
        public event EventHandler ConsentPresentationRequested;
        public event EventHandler
            ActivateCurrentGameWindowRequested;
        public event EventHandler ChangeHairRequested;
        public event EventHandler<string> DialogueSubmitted;

        internal void ProjectState(
            WingsShellSnapshot shell,
            WingsPersonaStateSnapshot persona,
            bool structuredWindowActivationAvailable,
            bool structuredHairChangeAvailable)
        {
            _state.Text =
                "状态："
                + OperationText(persona.OperationState)
                + (shell.Paused ? "（已暂停）" : string.Empty);
            PauseButton.Text = shell.Paused ? "恢复" : "暂停";
            ActivateGameButton.Visible =
                structuredWindowActivationAvailable;
            ActivateGameButton.Enabled =
                structuredWindowActivationAvailable
                && !shell.Paused
                && shell.Presentation
                    == WingsPersonaPresentation.Visible
                && shell.ReadGrantActive
                && persona.OperationState
                    == WingsOperationState.Idle;
            ChangeHairButton.Visible =
                structuredHairChangeAvailable;
            ChangeHairButton.Enabled =
                structuredHairChangeAvailable
                && !shell.Paused
                && shell.Presentation
                    == WingsPersonaPresentation.Visible
                && shell.ReadGrantActive
                && persona.OperationState
                    == WingsOperationState.Idle;
        }

        internal void AppendAssistantText(string text)
        {
            AppendTranscript("助手", text);
        }

        internal void AppendUserText(string text)
        {
            AppendTranscript("你", text);
        }

        internal void SetNotification(
            WingsShellNotification notification)
        {
            _notification.Text = notification.Text;
            _notification.ForeColor = notification.Kind switch
            {
                WingsNotificationKind.Error => Color.Firebrick,
                WingsNotificationKind.Warning => Color.DarkOrange,
                WingsNotificationKind.Permission => Color.DarkBlue,
                _ => Color.DimGray
            };
        }

        internal void HideForHost()
        {
            Hide();
        }

        internal void CloseForOwnerShutdown()
        {
            _allowClose = true;
            Close();
        }

        protected override void OnFormClosing(
            FormClosingEventArgs e)
        {
            if (!_allowClose
                && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                HideRequested?.Invoke(this, EventArgs.Empty);
                return;
            }
            base.OnFormClosing(e);
        }

        private void SubmitDialogue()
        {
            string text = (_input.Text ?? string.Empty).Trim();
            if (text.Length == 0
                || text.Any(character =>
                    char.IsControl(character)
                    && character != '\t'))
            {
                return;
            }
            _input.Clear();
            DialogueSubmitted?.Invoke(this, text);
        }

        private void AppendTranscript(string speaker, string text)
        {
            if (_transcript.TextLength != 0)
                _transcript.AppendText(Environment.NewLine);
            _transcript.AppendText(speaker + "：" + text);
            _transcript.SelectionStart =
                _transcript.TextLength;
            _transcript.ScrollToCaret();
        }

        private static string OperationText(
            WingsOperationState state)
        {
            return state switch
            {
                WingsOperationState.Offline => "离线",
                WingsOperationState.Idle => "空闲",
                WingsOperationState.Observing => "观察中",
                WingsOperationState.Advising => "建议中",
                WingsOperationState.AwaitingGrant => "等待授权",
                WingsOperationState.Executing => "执行中",
                WingsOperationState.Reporting => "报告中",
                WingsOperationState.SafeError => "安全错误",
                _ => "未知"
            };
        }
    }
}
