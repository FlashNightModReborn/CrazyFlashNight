using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Drawing;
using System.Linq;
using System.Security.Cryptography;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Integration;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Wings
{
    internal sealed class NeutralConsentScopeDisplay
    {
        public NeutralConsentScopeDisplay(
            string scopeKey,
            string displayText)
        {
            WingsProtocolValue.RequireStableKey(
                scopeKey,
                nameof(scopeKey));
            WingsProtocolValue.RequireText(
                displayText,
                160,
                nameof(displayText));
            ScopeKey = scopeKey;
            DisplayText = displayText;
        }

        public string ScopeKey { get; }
        public string DisplayText { get; }
    }

    /// <summary>
    /// Host-owned neutral presentation facts. This model carries no grant,
    /// lease, token, or signer.
    /// </summary>
    internal sealed class TrustedNeutralConsentPrompt
    {
        internal TrustedNeutralConsentPrompt(
            string promptId,
            string sessionId,
            string saveBindingId,
            string requesterDisplayName,
            string sessionDisplayName,
            string saveDisplayName,
            IEnumerable<NeutralConsentScopeDisplay> scopes,
            string actionPreview,
            DateTimeOffset issuedAtUtc,
            DateTimeOffset expiresAtUtc,
            string retentionAndExportText,
            string revocationText,
            string killSwitchText)
        {
            WingsProtocolValue.RequireOpaqueId(
                promptId,
                nameof(promptId));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            WingsProtocolValue.RequireOpaqueId(
                saveBindingId,
                nameof(saveBindingId));
            WingsProtocolValue.RequireText(
                requesterDisplayName,
                128,
                nameof(requesterDisplayName));
            WingsProtocolValue.RequireText(
                sessionDisplayName,
                128,
                nameof(sessionDisplayName));
            WingsProtocolValue.RequireText(
                saveDisplayName,
                128,
                nameof(saveDisplayName));
            WingsProtocolValue.RequireText(
                actionPreview,
                512,
                nameof(actionPreview));
            WingsProtocolValue.RequireText(
                retentionAndExportText,
                256,
                nameof(retentionAndExportText));
            WingsProtocolValue.RequireText(
                revocationText,
                256,
                nameof(revocationText));
            WingsProtocolValue.RequireText(
                killSwitchText,
                256,
                nameof(killSwitchText));
            if (issuedAtUtc >= expiresAtUtc)
                throw new ArgumentException(
                    "Consent prompt expiry must be after issuance.",
                    nameof(expiresAtUtc));
            NeutralConsentScopeDisplay[] frozenScopes =
                (scopes ?? Array.Empty<NeutralConsentScopeDisplay>())
                    .ToArray();
            if (frozenScopes.Length == 0
                || frozenScopes.Length > 32
                || frozenScopes.Any(scope => scope == null)
                || frozenScopes
                    .Select(scope => scope.ScopeKey)
                    .Distinct(StringComparer.Ordinal)
                    .Count() != frozenScopes.Length)
            {
                throw new ArgumentException(
                    "Consent prompt needs 1-32 unique neutral scopes.",
                    nameof(scopes));
            }

            PromptId = promptId;
            SessionId = sessionId;
            SaveBindingId = saveBindingId;
            RequesterDisplayName = requesterDisplayName;
            SessionDisplayName = sessionDisplayName;
            SaveDisplayName = saveDisplayName;
            Scopes = Array.AsReadOnly(
                frozenScopes
                    .OrderBy(
                        scope => scope.ScopeKey,
                        StringComparer.Ordinal)
                    .ToArray());
            ActionPreview = actionPreview;
            IssuedAtUtc = issuedAtUtc;
            ExpiresAtUtc = expiresAtUtc;
            RetentionAndExportText = retentionAndExportText;
            RevocationText = revocationText;
            KillSwitchText = killSwitchText;
        }

        public string PromptId { get; }
        public string SessionId { get; }
        public string SaveBindingId { get; }
        public string RequesterDisplayName { get; }
        public string SessionDisplayName { get; }
        public string SaveDisplayName { get; }
        public ReadOnlyCollection<NeutralConsentScopeDisplay> Scopes
        {
            get;
        }
        public string ActionPreview { get; }
        public DateTimeOffset IssuedAtUtc { get; }
        public DateTimeOffset ExpiresAtUtc { get; }
        public string RetentionAndExportText { get; }
        public string RevocationText { get; }
        public string KillSwitchText { get; }

        public string SafeRequesterCategory => "项目内助手";
    }

    internal enum NeutralConsentDecision
    {
        Allow,
        Reject,
        Dismiss
    }

    internal sealed class NeutralConsentDecisionIntent
    {
        internal NeutralConsentDecisionIntent(
            string promptId,
            NeutralConsentDecision decision)
        {
            WingsProtocolValue.RequireOpaqueId(
                promptId,
                nameof(promptId));
            if (!Enum.IsDefined(decision))
                throw new ArgumentOutOfRangeException(
                    nameof(decision));
            PromptId = promptId;
            Decision = decision;
        }

        public string PromptId { get; }
        public NeutralConsentDecision Decision { get; }

        /// <summary>
        /// Technical refusal never changes affinity, route, rewards, or
        /// access to core content.
        /// </summary>
        public int PenaltyDelta => 0;
    }

    /// <summary>
    /// Implemented by the host-owned consent broker. The presentation layer
    /// submits intent only; the broker may reject it and is solely
    /// responsible for any signed receipt.
    /// </summary>
    internal interface INeutralConsentDecisionSink
    {
        void SubmitHumanDecision(
            NeutralConsentDecisionIntent intent);
    }

    internal interface IWingsHumanOnlySurfaceLease : IDisposable
    {
        string TargetId { get; }
        long WindowHandle { get; }
        long OwnerWindowHandle { get; }
        ulong SurfaceEpoch { get; }
    }

    /// <summary>
    /// The host must publish the hidden HWND as human-only before it becomes
    /// visible. Returning false prevents presentation.
    /// </summary>
    internal interface IWingsHumanOnlySurfacePublisher
    {
        bool TryPublish(
            WingsHumanOnlySurfaceDescriptor descriptor,
            out IWingsHumanOnlySurfaceLease lease,
            out string reasonCode);
    }

    internal sealed class WingsHumanOnlySurfaceDescriptor
    {
        internal WingsHumanOnlySurfaceDescriptor(
            string targetId,
            long windowHandle,
            long ownerWindowHandle,
            Rectangle boundsPhysical,
            Rectangle clientRectPhysical,
            int dpi)
        {
            WingsProtocolValue.RequireOpaqueId(
                targetId,
                nameof(targetId));
            if (windowHandle == 0)
                throw new ArgumentOutOfRangeException(
                    nameof(windowHandle));
            if (boundsPhysical.Width <= 0
                || boundsPhysical.Height <= 0
                || clientRectPhysical.Width <= 0
                || clientRectPhysical.Height <= 0)
            {
                throw new ArgumentException(
                    "Human-only surface bounds must be positive.");
            }
            if (dpi < 48 || dpi > 960)
                throw new ArgumentOutOfRangeException(nameof(dpi));

            TargetId = targetId;
            WindowHandle = windowHandle;
            OwnerWindowHandle = ownerWindowHandle;
            BoundsPhysical = boundsPhysical;
            ClientRectPhysical = clientRectPhysical;
            Dpi = dpi;
        }

        public string TargetId { get; }
        public long WindowHandle { get; }
        public long OwnerWindowHandle { get; }
        public Rectangle BoundsPhysical { get; }
        public Rectangle ClientRectPhysical { get; }
        public int Dpi { get; }
        public AgentTargetSafetyKind SafetyKind =>
            AgentTargetSafetyKind.HumanOnlySecuritySurface;
        public bool IsObservationTarget => false;
        public ReadOnlyCollection<ObservationMode> ObservationModes =>
            Array.AsReadOnly(Array.Empty<ObservationMode>());
        public ReadOnlyCollection<InputMode> InputModes =>
            Array.AsReadOnly(Array.Empty<InputMode>());

        public SessionSurfaceHostRegistration ToSessionRegistration(
            SessionProcessIdentity ownerProcess)
        {
            if (ownerProcess == null)
                throw new ArgumentNullException(nameof(ownerProcess));
            return new SessionSurfaceHostRegistration
            {
                TargetId = TargetId,
                Kind = SurfaceKind.BusinessModal,
                SafetyKind =
                    AgentTargetSafetyKind.HumanOnlySecuritySurface,
                OwnerRelation =
                    SessionSurfaceOwnerRelation
                        .HumanOnlySecurityReported,
                OwnerProcess = ownerProcess,
                WindowHandle = WindowHandle,
                OwnerWindowHandle = OwnerWindowHandle,
                BoundsPhysical = Rect(BoundsPhysical),
                ClientRectPhysical = Rect(ClientRectPhysical),
                ContentRectPhysical = Rect(ClientRectPhysical),
                Dpi = Dpi,
                ZIndex = int.MaxValue,
                Visible = true,
                Minimized = false,
                ObservationModes = Array.Empty<ObservationMode>(),
                InputModes = Array.Empty<InputMode>()
            };
        }

        internal static WingsHumanOnlySurfaceDescriptor FromForm(
            Form form,
            string targetId)
        {
            if (form == null)
                throw new ArgumentNullException(nameof(form));
            if (!form.IsHandleCreated)
                throw new InvalidOperationException(
                    "consent_surface_handle_missing");
            Rectangle client = form.RectangleToScreen(
                form.ClientRectangle);
            return new WingsHumanOnlySurfaceDescriptor(
                targetId,
                form.Handle.ToInt64(),
                form.Owner?.IsHandleCreated == true
                    ? form.Owner.Handle.ToInt64()
                    : 0,
                form.Bounds,
                client,
                form.DeviceDpi);
        }

        private static SessionPhysicalRect Rect(Rectangle value)
        {
            return new SessionPhysicalRect(
                value.X,
                value.Y,
                value.Width,
                value.Height);
        }
    }

    internal sealed class WingsConsentPresentationPort : IDisposable
    {
        private readonly Form _owner;
        private readonly IWingsHumanOnlySurfacePublisher _publisher;
        private readonly INeutralConsentDecisionSink _decisionSink;
        private readonly Func<DateTimeOffset> _utcNow;
        private WingsConsentForm _activeForm;
        private IWingsHumanOnlySurfaceLease _activeLease;
        private LauncherTrustedHumanInteractionTicket
            _activeInteraction;
        private bool _disposed;

        public WingsConsentPresentationPort(
            Form owner,
            IWingsHumanOnlySurfacePublisher publisher,
            INeutralConsentDecisionSink decisionSink,
            Func<DateTimeOffset> utcNow = null)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _publisher = publisher
                ?? throw new ArgumentNullException(nameof(publisher));
            _decisionSink = decisionSink
                ?? throw new ArgumentNullException(
                    nameof(decisionSink));
            _utcNow = utcNow ?? (() => DateTimeOffset.UtcNow);
        }

        public bool TryPresent(
            TrustedNeutralConsentPrompt prompt,
            out string reasonCode)
        {
            if (prompt == null)
                throw new ArgumentNullException(nameof(prompt));
            return InvokeOnOwner(
                (out string reason) =>
                    TryPresentOnUi(
                        prompt,
                        null,
                        out reason),
                out reasonCode);
        }

        public bool TryPresent(
            TrustedNeutralConsentPrompt prompt,
            LauncherTrustedHumanInteractionTicket interaction,
            out string reasonCode)
        {
            if (prompt == null)
                throw new ArgumentNullException(nameof(prompt));
            if (interaction == null)
                throw new ArgumentNullException(nameof(interaction));
            return InvokeOnOwner(
                (out string reason) =>
                    TryPresentOnUi(
                        prompt,
                        interaction,
                        out reason),
                out reasonCode);
        }

        internal WingsConsentForm ActiveFormForTest =>
            _activeForm;
        internal Form Owner => _owner;

        internal bool TryDismiss(
            string promptId,
            out string reasonCode)
        {
            WingsProtocolValue.RequireOpaqueId(
                promptId,
                nameof(promptId));
            return InvokeOnOwner(
                (out string reason) =>
                {
                    if (_disposed)
                    {
                        reason =
                            "consent_port_disposed";
                        return false;
                    }
                    if (_activeForm == null
                        || !string.Equals(
                            _activeForm.PromptId,
                            promptId,
                            StringComparison.Ordinal))
                    {
                        reason =
                            "consent_prompt_not_active";
                        return false;
                    }
                    CloseActiveForm();
                    reason = null;
                    return true;
                },
                out reasonCode);
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

        private bool TryPresentOnUi(
            TrustedNeutralConsentPrompt prompt,
            LauncherTrustedHumanInteractionTicket interaction,
            out string reasonCode)
        {
            if (_disposed)
            {
                reasonCode = "consent_port_disposed";
                return false;
            }
            if (_owner.IsDisposed
                || !_owner.IsHandleCreated
                || !_owner.Visible)
            {
                reasonCode = "consent_owner_not_available";
                return false;
            }
            if (_activeForm != null)
            {
                reasonCode = "consent_prompt_already_visible";
                return false;
            }
            DateTimeOffset now = _utcNow();
            if (now < prompt.IssuedAtUtc
                || now >= prompt.ExpiresAtUtc)
            {
                reasonCode = "consent_prompt_not_current";
                return false;
            }
            LastSubmissionFailureReason = null;

            var form = new WingsConsentForm(prompt)
            {
                Owner = _owner
            };
            form.CreateControl();
            _ = form.Handle;
            string targetId = CreateOpaqueTargetId();
            WingsHumanOnlySurfaceDescriptor descriptor =
                WingsHumanOnlySurfaceDescriptor.FromForm(
                    form,
                    targetId);
            if (interaction != null
                && !interaction.TryBindSecuritySurface(
                    descriptor,
                    out reasonCode))
            {
                form.Dispose();
                return false;
            }
            IWingsHumanOnlySurfaceLease lease = null;
            bool published;
            try
            {
                published = _publisher.TryPublish(
                    descriptor,
                    out lease,
                    out reasonCode);
            }
            catch
            {
                form.Dispose();
                reasonCode =
                    "human_only_surface_publish_failed";
                return false;
            }
            if (!published || lease == null)
            {
                lease?.Dispose();
                form.Dispose();
                reasonCode ??=
                    "human_only_surface_publish_rejected";
                return false;
            }
            if (interaction != null
                && !interaction.TryConfirmPublishedSurface(
                    lease.TargetId,
                    lease.WindowHandle,
                    lease.OwnerWindowHandle,
                    lease.SurfaceEpoch,
                    out reasonCode))
            {
                lease.Dispose();
                form.Dispose();
                return false;
            }

            _activeForm = form;
            _activeLease = lease;
            _activeInteraction = interaction;
            form.DecisionRequested += OnDecisionRequested;
            form.FormClosed += OnFormClosed;
            if (interaction != null
                && !interaction.TryRegisterRevocation(
                    () =>
                    {
                        try
                        {
                            TryDismiss(
                                prompt.PromptId,
                                out _);
                        }
                        catch
                        {
                        }
                    }))
            {
                CloseActiveForm();
                reasonCode =
                    "human_intervention_required";
                return false;
            }
            try
            {
                form.Show(_owner);
                form.Activate();
                reasonCode = null;
                return true;
            }
            catch
            {
                CloseActiveForm();
                reasonCode = "consent_surface_show_failed";
                return false;
            }
        }

        private void OnDecisionRequested(
            object sender,
            NeutralConsentDecision decision)
        {
            WingsConsentForm form = sender as WingsConsentForm;
            if (form == null || !ReferenceEquals(form, _activeForm))
                return;
            var intent = new NeutralConsentDecisionIntent(
                form.PromptId,
                decision);
            try
            {
                _decisionSink.SubmitHumanDecision(intent);
            }
            catch
            {
                LastSubmissionFailureReason =
                    "consent_broker_submission_failed";
            }
            finally
            {
                CloseActiveForm();
            }
        }

        private void OnFormClosed(object sender, FormClosedEventArgs e)
        {
            if (sender is WingsConsentForm form)
            {
                form.DecisionRequested -= OnDecisionRequested;
                form.FormClosed -= OnFormClosed;
                _activeInteraction?.MarkClosed(
                    form.Handle.ToInt64());
            }
            _activeForm = null;
            _activeLease?.Dispose();
            _activeLease = null;
            _activeInteraction = null;
        }

        private void CloseActiveForm()
        {
            WingsConsentForm form = _activeForm;
            if (form == null)
                return;
            form.CloseForHost();
            if (!form.IsDisposed)
                form.Dispose();
            if (ReferenceEquals(_activeForm, form))
            {
                _activeInteraction?.MarkClosed(
                    form.Handle.ToInt64());
                _activeForm = null;
                _activeLease?.Dispose();
                _activeLease = null;
                _activeInteraction = null;
            }
        }

        private void DisposeOnUi()
        {
            if (_disposed)
                return;
            _disposed = true;
            CloseActiveForm();
        }

        internal string LastSubmissionFailureReason { get; private set; }

        private bool InvokeOnOwner(
            TryPresentDelegate action,
            out string reasonCode)
        {
            if (_owner.IsDisposed)
            {
                reasonCode = "consent_owner_not_available";
                return false;
            }
            if (_owner.InvokeRequired)
            {
                PresentResult result =
                    (PresentResult)_owner.Invoke(
                        new Func<PresentResult>(() =>
                        {
                            bool accepted = action(out string reason);
                            return new PresentResult(
                                accepted,
                                reason);
                        }));
                reasonCode = result.ReasonCode;
                return result.Accepted;
            }
            return action(out reasonCode);
        }

        private static string CreateOpaqueTargetId()
        {
            byte[] bytes = RandomNumberGenerator.GetBytes(16);
            return "hc_"
                + Convert.ToBase64String(bytes)
                    .TrimEnd('=')
                    .Replace('+', '-')
                    .Replace('/', '_');
        }

        private delegate bool TryPresentDelegate(
            out string reasonCode);

        private sealed class PresentResult
        {
            public PresentResult(
                bool accepted,
                string reasonCode)
            {
                Accepted = accepted;
                ReasonCode = reasonCode;
            }

            public bool Accepted { get; }
            public string ReasonCode { get; }
        }
    }

    internal sealed class WingsConsentForm : Form
    {
        private bool _decisionRaised;
        private bool _allowClose;

        public WingsConsentForm(
            TrustedNeutralConsentPrompt prompt)
        {
            PromptId = prompt.PromptId;
            Text = "Launcher 权限确认";
            Name = "WingsNeutralConsent";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            ShowInTaskbar = false;
            MinimizeBox = false;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(560, 510);
            AutoScaleMode = AutoScaleMode.Dpi;

            var content = new TableLayoutPanel
            {
                Dock = DockStyle.Fill,
                Padding = new Padding(16),
                ColumnCount = 1,
                RowCount = 10,
                AutoScroll = true
            };
            content.ColumnStyles.Add(
                new ColumnStyle(SizeType.Percent, 100));
            Controls.Add(content);

            content.Controls.Add(Heading(
                prompt.RequesterDisplayName
                + "（"
                + prompt.SafeRequesterCategory
                + "）正在请求权限"));
            content.Controls.Add(Line(
                "目标会话："
                + prompt.SessionDisplayName));
            content.Controls.Add(Line(
                "目标存档："
                + prompt.SaveDisplayName));
            content.Controls.Add(Line(
                "请求范围：\r\n"
                + string.Join(
                    "\r\n",
                    prompt.Scopes.Select(
                        scope => "• " + scope.DisplayText))));
            content.Controls.Add(Line(
                "动作预览："
                + prompt.ActionPreview));
            content.Controls.Add(Line(
                "有效期至："
                + prompt.ExpiresAtUtc
                    .ToLocalTime()
                    .ToString("yyyy-MM-dd HH:mm:ss")));
            content.Controls.Add(Line(
                "留存 / 导出："
                + prompt.RetentionAndExportText));
            content.Controls.Add(Line(
                "撤销方式："
                + prompt.RevocationText));
            content.Controls.Add(Line(
                "Kill Switch："
                + prompt.KillSwitchText));

            var buttons = new FlowLayoutPanel
            {
                Dock = DockStyle.Fill,
                FlowDirection = FlowDirection.RightToLeft,
                AutoSize = true
            };
            AllowButton = new Button
            {
                Text = "允许",
                AutoSize = true
            };
            RejectButton = new Button
            {
                Text = "拒绝",
                AutoSize = true
            };
            AllowButton.Click += (_, __) =>
                RaiseDecision(NeutralConsentDecision.Allow);
            RejectButton.Click += (_, __) =>
                RaiseDecision(NeutralConsentDecision.Reject);
            buttons.Controls.Add(AllowButton);
            buttons.Controls.Add(RejectButton);
            content.Controls.Add(buttons);
            AcceptButton = AllowButton;
            CancelButton = RejectButton;
        }

        public string PromptId { get; }
        internal Button AllowButton { get; }
        internal Button RejectButton { get; }

        public event EventHandler<NeutralConsentDecision>
            DecisionRequested;

        internal void CloseForHost()
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
                RaiseDecision(NeutralConsentDecision.Dismiss);
                return;
            }
            base.OnFormClosing(e);
        }

        private void RaiseDecision(NeutralConsentDecision decision)
        {
            if (_decisionRaised)
                return;
            _decisionRaised = true;
            AllowButton.Enabled = false;
            RejectButton.Enabled = false;
            DecisionRequested?.Invoke(this, decision);
        }

        private static Control Heading(string text)
        {
            return new Label
            {
                Text = text,
                AutoSize = true,
                Font = new Font(
                    SystemFonts.MessageBoxFont,
                    FontStyle.Bold),
                Margin = new Padding(0, 0, 0, 12)
            };
        }

        private static Control Line(string text)
        {
            return new Label
            {
                Text = text,
                AutoSize = true,
                MaximumSize = new Size(510, 0),
                Margin = new Padding(0, 0, 0, 10)
            };
        }
    }
}
