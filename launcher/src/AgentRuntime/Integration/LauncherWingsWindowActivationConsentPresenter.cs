using System;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Immutable Host proposal for the only production Wings structured
    /// action currently exposed. It intentionally contains no credential,
    /// observation, lease, executable intent, or Persona-authored field.
    /// </summary>
    internal sealed class LauncherWingsWindowActivationProposal
    {
        internal LauncherWingsWindowActivationProposal(
            SessionMutationExpectation expectation,
            string slot,
            string saveBindingId,
            string loreViewId,
            string targetId,
            DateTimeOffset issuedAtUtc,
            DateTimeOffset expiresAtUtc)
        {
            Expectation = expectation
                ?? throw new ArgumentNullException(
                    nameof(expectation));
            WingsProtocolValue.RequireText(
                slot,
                160,
                nameof(slot));
            WingsProtocolValue.RequireOpaqueId(
                saveBindingId,
                nameof(saveBindingId));
            WingsProtocolValue.RequireOpaqueId(
                loreViewId,
                nameof(loreViewId));
            WingsProtocolValue.RequireOpaqueId(
                targetId,
                nameof(targetId));
            if (issuedAtUtc >= expiresAtUtc)
            {
                throw new ArgumentException(
                    "Action approval expiry must follow issuance.",
                    nameof(expiresAtUtc));
            }

            Slot = slot;
            SaveBindingId = saveBindingId;
            LoreViewId = loreViewId;
            TargetId = targetId;
            IssuedAtUtc = issuedAtUtc;
            ExpiresAtUtc = expiresAtUtc;
        }

        public SessionMutationExpectation Expectation { get; }
        public string SessionId => Expectation.SessionId;
        public string Slot { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public string TargetId { get; }
        public DateTimeOffset IssuedAtUtc { get; }
        public DateTimeOffset ExpiresAtUtc { get; }
        public string Operation =>
            AgentCapabilitiesV1.ActivateWindow;
        public string CanonicalArguments => "{}";
        public int MaximumActions => 1;
        public bool AllowsPersistence => false;
        public bool AllowsExport => false;
    }

    internal sealed class LauncherWingsWindowActivationApproval
    {
        private LauncherWingsWindowActivationApproval(
            string humanInteractionReceiptId,
            string reauthorizationReceiptId,
            string reasonCode)
        {
            HumanInteractionReceiptId =
                humanInteractionReceiptId;
            ReauthorizationReceiptId =
                reauthorizationReceiptId;
            ReasonCode = reasonCode;
        }

        public bool Approved =>
            HumanInteractionReceiptId != null
            && ReauthorizationReceiptId != null;
        public string HumanInteractionReceiptId { get; }
        public string ReauthorizationReceiptId { get; }
        public string ReasonCode { get; }

        internal static LauncherWingsWindowActivationApproval
            AllowAfterClose(
                string humanInteractionReceiptId,
                string reauthorizationReceiptId)
        {
            WingsProtocolValue.RequireOpaqueId(
                humanInteractionReceiptId,
                nameof(humanInteractionReceiptId));
            WingsProtocolValue.RequireOpaqueId(
                reauthorizationReceiptId,
                nameof(reauthorizationReceiptId));
            return new LauncherWingsWindowActivationApproval(
                humanInteractionReceiptId,
                reauthorizationReceiptId,
                null);
        }

        internal static LauncherWingsWindowActivationApproval
            Reject(string reasonCode)
        {
            return new LauncherWingsWindowActivationApproval(
                null,
                null,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "consent_required"
                    : reasonCode);
        }
    }

    /// <summary>
    /// A production implementation must publish a Launcher-owned
    /// human_only_security_surface and return Allow only after that HWND has
    /// closed, been unpublished, and the exact session has been
    /// reauthorized.
    /// </summary>
    internal interface IWingsWindowActivationConsentPresenter
    {
        Task<LauncherWingsWindowActivationApproval> PresentAsync(
            LauncherWingsWindowActivationProposal proposal,
            LauncherTrustedHumanInteractionTicket interaction,
            CancellationToken cancellationToken);
    }

    internal sealed class FailClosedWingsWindowActivationConsentPresenter
        : IWingsWindowActivationConsentPresenter
    {
        public Task<LauncherWingsWindowActivationApproval> PresentAsync(
            LauncherWingsWindowActivationProposal proposal,
            LauncherTrustedHumanInteractionTicket interaction,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                LauncherWingsWindowActivationApproval.Reject(
                    "consent_required"));
        }
    }

    /// <summary>
    /// Real neutral action card for the fixed current-game-window activation
    /// proposal. The card precedes credential and observation issuance so its
    /// security-modal epoch cannot stale an already executable intent.
    /// </summary>
    internal sealed class
        LauncherWingsWindowActivationConsentPresenter
        : IWingsWindowActivationConsentPresenter,
          INeutralConsentDecisionSink,
          IDisposable
    {
        private readonly object _sync = new object();
        private readonly Form _owner;
        private readonly IAgentRuntimeClock _clock;
        private readonly LauncherHumanOnlySurfacePublisher
            _surfacePublisher;
        private readonly WingsConsentPresentationPort _port;
        private PendingPresentation _pending;
        private bool _disposed;

        internal LauncherWingsWindowActivationConsentPresenter(
            Form owner,
            IAgentRuntimeClock clock,
            SessionSurfaceHostController surfaces,
            SessionRegistryHostOwner registryOwner)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _surfacePublisher =
                new LauncherHumanOnlySurfacePublisher(
                    surfaces
                        ?? throw new ArgumentNullException(
                            nameof(surfaces)),
                    registryOwner
                        ?? throw new ArgumentNullException(
                            nameof(registryOwner)));
            _port = new WingsConsentPresentationPort(
                owner,
                _surfacePublisher,
                this,
                () => _clock.UtcNow);
        }

        public Task<LauncherWingsWindowActivationApproval>
            PresentAsync(
                LauncherWingsWindowActivationProposal proposal,
                LauncherTrustedHumanInteractionTicket interaction,
                CancellationToken cancellationToken)
        {
            if (proposal == null)
            {
                throw new ArgumentNullException(
                    nameof(proposal));
            }
            if (interaction == null
                || interaction.Phase
                    != LauncherTrustedHumanInteractionPhase
                        .WindowActivationConsent)
            {
                return Task.FromResult(
                    LauncherWingsWindowActivationApproval.Reject(
                        "human_intervention_required"));
            }
            if (cancellationToken.IsCancellationRequested)
            {
                return Task.FromResult(
                    LauncherWingsWindowActivationApproval.Reject(
                        "consent_required"));
            }

            TrustedNeutralConsentPrompt prompt;
            try
            {
                prompt = BuildPrompt(proposal);
            }
            catch
            {
                return Task.FromResult(
                    LauncherWingsWindowActivationApproval.Reject(
                        "consent_required"));
            }

            var pending = new PendingPresentation(
                proposal,
                prompt.PromptId);
            lock (_sync)
            {
                if (_disposed)
                {
                    return Task.FromResult(
                        LauncherWingsWindowActivationApproval.Reject(
                            "consent_required"));
                }
                if (_pending != null)
                {
                    return Task.FromResult(
                        LauncherWingsWindowActivationApproval.Reject(
                            "lease_busy"));
                }
                _pending = pending;
            }

            bool presented;
            try
            {
                presented = _port.TryPresent(
                    prompt,
                    interaction,
                    out string presentationReason);
                if (!presented)
                {
                    Complete(
                        pending,
                        LauncherWingsWindowActivationApproval.Reject(
                            presentationReason
                                ?? "consent_required"));
                    return pending.Completion.Task;
                }
            }
            catch
            {
                Complete(
                    pending,
                    LauncherWingsWindowActivationApproval.Reject(
                        "consent_required"));
                return pending.Completion.Task;
            }

            CancellationTokenRegistration registration =
                cancellationToken.Register(
                    () => Cancel(pending));
            bool registrationOwned;
            lock (_sync)
            {
                registrationOwned =
                    ReferenceEquals(_pending, pending)
                    && !_disposed;
                if (registrationOwned)
                {
                    pending.CancellationRegistration =
                        registration;
                    pending.HasCancellationRegistration = true;
                }
            }
            if (!registrationOwned)
                registration.Dispose();
            return pending.Completion.Task;
        }

        internal WingsConsentForm ActiveFormForTest =>
            _port.ActiveFormForTest;

        public void SubmitHumanDecision(
            NeutralConsentDecisionIntent intent)
        {
            if (intent == null)
                throw new ArgumentNullException(nameof(intent));
            PendingPresentation pending;
            lock (_sync)
            {
                pending = _pending;
                if (pending == null
                    || !string.Equals(
                        pending.PromptId,
                        intent.PromptId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                if (intent.Decision
                    == NeutralConsentDecision.Allow)
                {
                    pending.HumanInteractionReceiptId =
                        OpaqueIdGenerator.Create(
                            "humaninteraction");
                }
            }

            // The presentation port closes and unregisters the HWND in its
            // finally block after this callback returns. Queue finalization so
            // reauthorization can run only after that cleanup.
            try
            {
                _owner.BeginInvoke(
                    new Action(
                        () => FinalizeHumanDecision(
                            pending,
                            intent.Decision)));
            }
            catch
            {
                Complete(
                    pending,
                    LauncherWingsWindowActivationApproval.Reject(
                        "consent_required"));
            }
        }

        public void Dispose()
        {
            PendingPresentation pending;
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                pending = _pending;
            }
            try
            {
                _port.Dispose();
            }
            finally
            {
                if (pending != null)
                {
                    Complete(
                        pending,
                        LauncherWingsWindowActivationApproval.Reject(
                            "consent_required"));
                }
            }
        }

        private void FinalizeHumanDecision(
            PendingPresentation pending,
            NeutralConsentDecision decision)
        {
            lock (_sync)
            {
                if (_disposed
                    || !ReferenceEquals(_pending, pending))
                {
                    return;
                }
            }

            if (!_surfacePublisher
                    .TryAcknowledgeHumanReauthorization(
                        pending.Proposal.Expectation,
                        out string reauthorizationReason))
            {
                Complete(
                    pending,
                    LauncherWingsWindowActivationApproval.Reject(
                        reauthorizationReason
                            ?? "human_intervention_required"));
                return;
            }
            if (decision != NeutralConsentDecision.Allow)
            {
                Complete(
                    pending,
                    LauncherWingsWindowActivationApproval.Reject(
                        "consent_required"));
                return;
            }
            if (_clock.UtcNow
                    >= pending.Proposal.ExpiresAtUtc
                || pending.HumanInteractionReceiptId == null)
            {
                Complete(
                    pending,
                    LauncherWingsWindowActivationApproval.Reject(
                        "consent_expired"));
                return;
            }

            Complete(
                pending,
                LauncherWingsWindowActivationApproval
                    .AllowAfterClose(
                        pending.HumanInteractionReceiptId,
                        OpaqueIdGenerator.Create(
                            "reauthorization")));
        }

        private void Cancel(PendingPresentation pending)
        {
            lock (_sync)
            {
                if (!ReferenceEquals(_pending, pending))
                    return;
            }
            try
            {
                _port.TryDismiss(
                    pending.PromptId,
                    out _);
            }
            catch
            {
            }
            Complete(
                pending,
                LauncherWingsWindowActivationApproval.Reject(
                    "consent_required"));
        }

        private void Complete(
            PendingPresentation pending,
            LauncherWingsWindowActivationApproval result)
        {
            bool owned;
            lock (_sync)
            {
                owned = ReferenceEquals(_pending, pending);
                if (owned)
                    _pending = null;
            }
            if (!owned)
                return;
            if (pending.HasCancellationRegistration)
                pending.CancellationRegistration.Unregister();
            pending.Completion.TrySetResult(result);
        }

        private static TrustedNeutralConsentPrompt BuildPrompt(
            LauncherWingsWindowActivationProposal proposal)
        {
            return new TrustedNeutralConsentPrompt(
                OpaqueIdGenerator.Create("consentprompt"),
                proposal.SessionId,
                proposal.SaveBindingId,
                "项目内助手",
                "当前 CF7 游戏会话",
                SafeDisplay(proposal.Slot, "当前存档"),
                new[]
                {
                    new NeutralConsentScopeDisplay(
                        "activate_current_game_window",
                        "仅将当前 CF7 游戏窗口切换到前台"),
                    new NeutralConsentScopeDisplay(
                        "ephemeral_pixel_snapshot",
                        "一次性读取当前游戏窗口像素以绑定本次动作")
                },
                "执行 1 次 window.activate，参数为 {}；"
                    + "不会点击、输入文字或修改存档。",
                proposal.IssuedAtUtc,
                proposal.ExpiresAtUtc,
                "像素只在本次动作连接内短暂使用；"
                    + "不持久化、不导出。",
                "暂停、隐藏助手、观察指示器消失、会话或目标变化、"
                    + "凭据失效、外部键鼠输入都会立即撤销。",
                "你可拒绝或关闭此窗口；任何外部键鼠输入都会抢占。");
        }

        private static string SafeDisplay(
            string value,
            string fallback)
        {
            if (string.IsNullOrWhiteSpace(value))
                return fallback;
            string trimmed = value.Trim();
            return trimmed.Length <= 96
                ? trimmed
                : trimmed.Substring(0, 96);
        }

        private sealed class PendingPresentation
        {
            internal PendingPresentation(
                LauncherWingsWindowActivationProposal proposal,
                string promptId)
            {
                Proposal = proposal
                    ?? throw new ArgumentNullException(
                        nameof(proposal));
                PromptId = promptId;
                Completion =
                    new TaskCompletionSource<
                        LauncherWingsWindowActivationApproval>(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
            }

            internal LauncherWingsWindowActivationProposal
                Proposal { get; }
            internal string PromptId { get; }
            internal string HumanInteractionReceiptId
            {
                get;
                set;
            }
            internal TaskCompletionSource<
                LauncherWingsWindowActivationApproval>
                    Completion { get; }
            internal CancellationTokenRegistration
                CancellationRegistration { get; set; }
            internal bool HasCancellationRegistration { get; set; }
        }
    }
}
