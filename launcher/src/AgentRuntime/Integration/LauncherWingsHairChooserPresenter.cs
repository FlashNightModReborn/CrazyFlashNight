using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Drawing;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal sealed class LauncherWingsHairPreparationProposal
    {
        internal LauncherWingsHairPreparationProposal(
            SessionMutationExpectation expectation,
            string slot,
            string saveBindingId,
            string loreViewId,
            string targetId,
            string panelName,
            string panelInstanceId,
            DateTimeOffset issuedAtUtc,
            DateTimeOffset expiresAtUtc)
        {
            Expectation = expectation
                ?? throw new ArgumentNullException(nameof(expectation));
            Slot = Required(slot, nameof(slot));
            SaveBindingId = Required(
                saveBindingId,
                nameof(saveBindingId));
            LoreViewId = Required(loreViewId, nameof(loreViewId));
            TargetId = Required(targetId, nameof(targetId));
            PanelName = Required(panelName, nameof(panelName));
            PanelInstanceId = Required(
                panelInstanceId,
                nameof(panelInstanceId));
            if (expiresAtUtc <= issuedAtUtc)
                throw new ArgumentOutOfRangeException(
                    nameof(expiresAtUtc));
            IssuedAtUtc = issuedAtUtc;
            ExpiresAtUtc = expiresAtUtc;
        }

        public SessionMutationExpectation Expectation { get; }
        public string SessionId => Expectation.SessionId;
        public string Slot { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public string TargetId { get; }
        public string PanelName { get; }
        public string PanelInstanceId { get; }
        public DateTimeOffset IssuedAtUtc { get; }
        public DateTimeOffset ExpiresAtUtc { get; }

        private static string Required(string value, string name)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException(
                    "A non-empty value is required.",
                    name);
            return value;
        }
    }

    internal sealed class LauncherWingsHairRestoreProposal
    {
        internal LauncherWingsHairRestoreProposal(
            SessionMutationExpectation expectation,
            string slot,
            string saveBindingId,
            string loreViewId,
            string targetId,
            string panelName,
            string panelInstanceId,
            string transactionId,
            string previewHash,
            string beforeHair,
            string afterHair,
            DateTimeOffset restoreExpiresAtUtc,
            DateTimeOffset issuedAtUtc,
            DateTimeOffset expiresAtUtc)
        {
            Expectation = expectation
                ?? throw new ArgumentNullException(nameof(expectation));
            Slot = Required(slot, nameof(slot));
            SaveBindingId = Required(
                saveBindingId,
                nameof(saveBindingId));
            LoreViewId = Required(loreViewId, nameof(loreViewId));
            TargetId = Required(targetId, nameof(targetId));
            PanelName = Required(panelName, nameof(panelName));
            PanelInstanceId = Required(
                panelInstanceId,
                nameof(panelInstanceId));
            TransactionId = Required(
                transactionId,
                nameof(transactionId));
            PreviewHash = Required(
                previewHash,
                nameof(previewHash));
            BeforeHair = Required(beforeHair, nameof(beforeHair));
            AfterHair = Required(afterHair, nameof(afterHair));
            if (restoreExpiresAtUtc <= issuedAtUtc
                || expiresAtUtc <= issuedAtUtc
                || expiresAtUtc > restoreExpiresAtUtc)
            {
                throw new ArgumentOutOfRangeException(
                    nameof(expiresAtUtc));
            }
            RestoreExpiresAtUtc = restoreExpiresAtUtc;
            IssuedAtUtc = issuedAtUtc;
            ExpiresAtUtc = expiresAtUtc;
        }

        public SessionMutationExpectation Expectation { get; }
        public string SessionId => Expectation.SessionId;
        public string Slot { get; }
        public string SaveBindingId { get; }
        public string LoreViewId { get; }
        public string TargetId { get; }
        public string PanelName { get; }
        public string PanelInstanceId { get; }
        public string TransactionId { get; }
        public string PreviewHash { get; }
        public string BeforeHair { get; }
        public string AfterHair { get; }
        public DateTimeOffset RestoreExpiresAtUtc { get; }
        public DateTimeOffset IssuedAtUtc { get; }
        public DateTimeOffset ExpiresAtUtc { get; }

        private static string Required(string value, string name)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException(
                    "A non-empty value is required.",
                    name);
            return value;
        }
    }

    internal sealed class LauncherWingsHairSecurityApproval
    {
        private LauncherWingsHairSecurityApproval(
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

        internal static LauncherWingsHairSecurityApproval Allow(
            string humanInteractionReceiptId,
            string reauthorizationReceiptId)
        {
            WingsProtocolValue.RequireOpaqueId(
                humanInteractionReceiptId,
                nameof(humanInteractionReceiptId));
            WingsProtocolValue.RequireOpaqueId(
                reauthorizationReceiptId,
                nameof(reauthorizationReceiptId));
            return new LauncherWingsHairSecurityApproval(
                humanInteractionReceiptId,
                reauthorizationReceiptId,
                null);
        }

        internal static LauncherWingsHairSecurityApproval Reject(
            string reasonCode = "consent_required")
        {
            return new LauncherWingsHairSecurityApproval(
                null,
                null,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "consent_required"
                    : reasonCode);
        }
    }

    internal sealed class LauncherWingsHairChoice
    {
        internal LauncherWingsHairChoice(
            string identifier,
            string displayName,
            bool isCurrent)
        {
            Identifier = Required(identifier, nameof(identifier));
            DisplayName = Required(displayName, nameof(displayName));
            IsCurrent = isCurrent;
        }

        public string Identifier { get; }
        public string DisplayName { get; }
        public bool IsCurrent { get; }

        public override string ToString()
        {
            return DisplayName + (IsCurrent ? "（当前）" : string.Empty);
        }

        private static string Required(string value, string name)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException(
                    "A non-empty value is required.",
                    name);
            return value;
        }
    }

    internal sealed class LauncherWingsHairChooserCard
    {
        private readonly ReadOnlyCollection<
            LauncherWingsHairChoice> _choices;

        internal LauncherWingsHairChooserCard(
            string chooserId,
            string sessionId,
            string slot,
            string targetId,
            string currentHair,
            long revision,
            long generation,
            string snapshotHash,
            IEnumerable<LauncherWingsHairChoice> choices)
        {
            WingsProtocolValue.RequireOpaqueId(
                chooserId,
                nameof(chooserId));
            WingsProtocolValue.RequireOpaqueId(
                sessionId,
                nameof(sessionId));
            WingsProtocolValue.RequireOpaqueId(
                targetId,
                nameof(targetId));
            if (string.IsNullOrWhiteSpace(slot)
                || string.IsNullOrWhiteSpace(currentHair)
                || revision < 0
                || generation < 0)
            {
                throw new ArgumentException(
                    "The Hair chooser binding is invalid.");
            }
            WingsProtocolValue.RequireSha256(
                snapshotHash,
                nameof(snapshotHash));
            LauncherWingsHairChoice[] frozen =
                (choices ?? Array.Empty<LauncherWingsHairChoice>())
                    .Where(choice => choice != null)
                    .ToArray();
            if (frozen.Length == 0
                || frozen.Length > 1024
                || frozen.Count(choice => choice.IsCurrent) != 1
                || frozen.Select(choice => choice.Identifier)
                    .Distinct(StringComparer.Ordinal)
                    .Count() != frozen.Length)
            {
                throw new ArgumentException(
                    "The trusted Hair catalog is invalid.",
                    nameof(choices));
            }
            ChooserId = chooserId;
            SessionId = sessionId;
            Slot = slot;
            TargetId = targetId;
            CurrentHair = currentHair;
            Revision = revision;
            Generation = generation;
            SnapshotHash = snapshotHash.ToLowerInvariant();
            _choices =
                new ReadOnlyCollection<LauncherWingsHairChoice>(
                    frozen);
        }

        public string ChooserId { get; }
        public string SessionId { get; }
        public string Slot { get; }
        public string TargetId { get; }
        public string CurrentHair { get; }
        public long Revision { get; }
        public long Generation { get; }
        public string SnapshotHash { get; }
        public IReadOnlyList<LauncherWingsHairChoice> Choices =>
            _choices;
    }

    internal sealed class LauncherWingsHairChooserSelection
    {
        private LauncherWingsHairChooserSelection(
            string chooserId,
            string hairIdentifier,
            string reasonCode)
        {
            ChooserId = chooserId;
            HairIdentifier = hairIdentifier;
            ReasonCode = reasonCode;
        }

        public bool Selected => HairIdentifier != null;
        public string ChooserId { get; }
        public string HairIdentifier { get; }
        public string ReasonCode { get; }

        internal static LauncherWingsHairChooserSelection Select(
            string chooserId,
            string hairIdentifier)
        {
            WingsProtocolValue.RequireOpaqueId(
                chooserId,
                nameof(chooserId));
            if (string.IsNullOrWhiteSpace(hairIdentifier))
                throw new ArgumentException(
                    "A Hair catalog identifier is required.",
                    nameof(hairIdentifier));
            return new LauncherWingsHairChooserSelection(
                chooserId,
                hairIdentifier,
                null);
        }

        internal static LauncherWingsHairChooserSelection Dismiss(
            string reasonCode = "consent_required")
        {
            return new LauncherWingsHairChooserSelection(
                null,
                null,
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "consent_required"
                    : reasonCode);
        }
    }

    internal interface ILauncherWingsHairInteractionPresenter
    {
        Task<LauncherWingsHairSecurityApproval>
            PresentPreparationAsync(
                LauncherWingsHairPreparationProposal proposal,
                LauncherTrustedHumanInteractionTicket interaction,
                CancellationToken cancellationToken);

        Task<LauncherWingsHairChooserSelection> ChooseAsync(
            LauncherWingsHairChooserCard card,
            LauncherTrustedHumanInteractionTicket interaction,
            CancellationToken cancellationToken);

        Task<LauncherWingsHairSecurityApproval>
            PresentRestoreAsync(
                LauncherWingsHairRestoreProposal proposal,
                LauncherTrustedHumanInteractionTicket interaction,
                CancellationToken cancellationToken);
    }

    internal sealed class FailClosedLauncherWingsHairInteractionPresenter
        : ILauncherWingsHairInteractionPresenter
    {
        public Task<LauncherWingsHairSecurityApproval>
            PresentPreparationAsync(
                LauncherWingsHairPreparationProposal proposal,
                LauncherTrustedHumanInteractionTicket interaction,
                CancellationToken cancellationToken)
        {
            return Task.FromResult(
                LauncherWingsHairSecurityApproval
                    .Reject("human_intervention_required"));
        }

        public Task<LauncherWingsHairChooserSelection> ChooseAsync(
            LauncherWingsHairChooserCard card,
            LauncherTrustedHumanInteractionTicket interaction,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                LauncherWingsHairChooserSelection
                    .Dismiss("human_intervention_required"));
        }

        public Task<LauncherWingsHairSecurityApproval>
            PresentRestoreAsync(
                LauncherWingsHairRestoreProposal proposal,
                LauncherTrustedHumanInteractionTicket interaction,
                CancellationToken cancellationToken)
        {
            return Task.FromResult(
                LauncherWingsHairSecurityApproval
                    .Reject("human_intervention_required"));
        }
    }

    /// <summary>
    /// Launcher-owned Hair product presenter. Preparation and restore are
    /// neutral human-only security cards. The catalog chooser is a separate
    /// structured product surface: it receives only the frozen Host catalog
    /// and cannot accept Persona/free-text identifiers.
    /// </summary>
    internal sealed class LauncherWingsHairChooserPresenter
        : ILauncherWingsHairInteractionPresenter,
          INeutralConsentDecisionSink,
          IDisposable
    {
        private static readonly TimeSpan PromptLifetime =
            TimeSpan.FromSeconds(60);

        private readonly object _sync = new object();
        private readonly Form _owner;
        private readonly IAgentRuntimeClock _clock;
        private readonly LauncherHumanOnlySurfacePublisher
            _surfacePublisher;
        private readonly WingsConsentPresentationPort _port;
        private PendingSecurity _pendingSecurity;
        private PendingChooser _pendingChooser;
        private bool _disposed;

        internal LauncherWingsHairChooserPresenter(
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
                    surfaces,
                    registryOwner);
            _port = new WingsConsentPresentationPort(
                owner,
                _surfacePublisher,
                this,
                () => _clock.UtcNow);
        }

        public Task<LauncherWingsHairSecurityApproval>
            PresentPreparationAsync(
                LauncherWingsHairPreparationProposal proposal,
                LauncherTrustedHumanInteractionTicket interaction,
                CancellationToken cancellationToken)
        {
            if (proposal == null)
                throw new ArgumentNullException(nameof(proposal));
            return PresentSecurityAsync(
                BuildPreparationPrompt(proposal),
                proposal.Expectation,
                interaction,
                cancellationToken);
        }

        public Task<LauncherWingsHairSecurityApproval>
            PresentRestoreAsync(
                LauncherWingsHairRestoreProposal proposal,
                LauncherTrustedHumanInteractionTicket interaction,
                CancellationToken cancellationToken)
        {
            if (proposal == null)
                throw new ArgumentNullException(nameof(proposal));
            return PresentSecurityAsync(
                BuildRestorePrompt(proposal),
                proposal.Expectation,
                interaction,
                cancellationToken);
        }

        public Task<LauncherWingsHairChooserSelection> ChooseAsync(
            LauncherWingsHairChooserCard card,
            LauncherTrustedHumanInteractionTicket interaction,
            CancellationToken cancellationToken)
        {
            if (card == null)
                throw new ArgumentNullException(nameof(card));
            if (interaction == null
                || interaction.Phase
                    != LauncherTrustedHumanInteractionPhase
                        .HairChooser)
            {
                return Task.FromResult(
                    LauncherWingsHairChooserSelection.Dismiss(
                        "human_intervention_required"));
            }
            if (cancellationToken.IsCancellationRequested)
            {
                return Task.FromResult(
                    LauncherWingsHairChooserSelection.Dismiss());
            }
            var pending = new PendingChooser(
                card,
                interaction);
            lock (_sync)
            {
                if (_disposed
                    || _pendingChooser != null
                    || _pendingSecurity != null)
                {
                    return Task.FromResult(
                        LauncherWingsHairChooserSelection
                            .Dismiss("human_intervention_required"));
                }
                _pendingChooser = pending;
            }
            if (!TryRunOnUi(() => ShowChooser(pending)))
            {
                CompleteChooser(
                    pending,
                    LauncherWingsHairChooserSelection
                        .Dismiss("human_intervention_required"));
                return pending.Completion.Task;
            }
            pending.CancellationRegistration =
                cancellationToken.Register(
                    () => CancelChooser(pending));
            pending.HasCancellationRegistration = true;
            return pending.Completion.Task;
        }

        internal WingsConsentForm ActiveConsentFormForTest =>
            _port.ActiveFormForTest;

        internal Form ActiveChooserFormForTest
        {
            get
            {
                lock (_sync)
                    return _pendingChooser?.Form;
            }
        }

        public void SubmitHumanDecision(
            NeutralConsentDecisionIntent intent)
        {
            if (intent == null)
                throw new ArgumentNullException(nameof(intent));
            PendingSecurity pending;
            lock (_sync)
            {
                pending = _pendingSecurity;
                if (pending == null
                    || !string.Equals(
                        pending.PromptId,
                        intent.PromptId,
                        StringComparison.Ordinal))
                {
                    return;
                }
            }
            // WingsConsentPresentationPort closes and unregisters the
            // human-only HWND only after this callback returns. Queue the
            // decision so reauthorization cannot run while that surface is
            // still registered.
            try
            {
                _owner.BeginInvoke(
                    new Action(
                        () => FinalizeSecurity(
                            pending,
                            intent.Decision)));
            }
            catch
            {
                CompleteSecurity(
                    pending,
                    LauncherWingsHairSecurityApproval
                        .Reject("human_intervention_required"));
            }
        }

        public void Dispose()
        {
            PendingSecurity security;
            PendingChooser chooser;
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                security = _pendingSecurity;
                chooser = _pendingChooser;
            }
            try
            {
                _port.Dispose();
            }
            finally
            {
                if (security != null)
                {
                    CompleteSecurity(
                        security,
                        LauncherWingsHairSecurityApproval
                            .Reject("human_intervention_required"));
                }
                if (chooser != null)
                {
                    CancelChooser(chooser);
                }
            }
        }

        private Task<LauncherWingsHairSecurityApproval>
            PresentSecurityAsync(
                TrustedNeutralConsentPrompt prompt,
                SessionMutationExpectation expectation,
                LauncherTrustedHumanInteractionTicket interaction,
                CancellationToken cancellationToken)
        {
            if (interaction == null
                || (interaction.Phase
                        != LauncherTrustedHumanInteractionPhase
                            .HairPreparationConsent
                    && interaction.Phase
                        != LauncherTrustedHumanInteractionPhase
                            .HairRestoreConsent))
            {
                return Task.FromResult(
                    LauncherWingsHairSecurityApproval.Reject(
                        "human_intervention_required"));
            }
            if (cancellationToken.IsCancellationRequested)
            {
                return Task.FromResult(
                    LauncherWingsHairSecurityApproval.Reject());
            }
            var pending = new PendingSecurity(
                prompt.PromptId,
                prompt.ExpiresAtUtc,
                expectation);
            lock (_sync)
            {
                if (_disposed
                    || _pendingSecurity != null
                    || _pendingChooser != null)
                {
                    return Task.FromResult(
                        LauncherWingsHairSecurityApproval
                            .Reject("human_intervention_required"));
                }
                _pendingSecurity = pending;
            }
            bool presented;
            try
            {
                presented = _port.TryPresent(
                    prompt,
                    interaction,
                    out _);
            }
            catch
            {
                presented = false;
            }
            if (!presented)
            {
                CompleteSecurity(
                    pending,
                    LauncherWingsHairSecurityApproval
                        .Reject("human_intervention_required"));
                return pending.Completion.Task;
            }
            pending.CancellationRegistration =
                cancellationToken.Register(
                    () => CancelSecurity(pending));
            pending.HasCancellationRegistration = true;
            return pending.Completion.Task;
        }

        private void FinalizeSecurity(
            PendingSecurity pending,
            NeutralConsentDecision decision)
        {
            lock (_sync)
            {
                if (_disposed
                    || !ReferenceEquals(
                        _pendingSecurity,
                        pending))
                {
                    return;
                }
            }
            if (!_surfacePublisher
                    .TryAcknowledgeHumanReauthorization(
                        pending.Expectation,
                        out string reasonCode))
            {
                CompleteSecurity(
                    pending,
                    LauncherWingsHairSecurityApproval
                        .Reject(reasonCode));
                return;
            }
            if (decision != NeutralConsentDecision.Allow
                || _clock.UtcNow >= pending.ExpiresAtUtc)
            {
                CompleteSecurity(
                    pending,
                    LauncherWingsHairSecurityApproval.Reject());
                return;
            }
            CompleteSecurity(
                pending,
                LauncherWingsHairSecurityApproval.Allow(
                    OpaqueIdGenerator.Create("hairhuman"),
                    OpaqueIdGenerator.Create("hairreauth")));
        }

        private void CancelSecurity(PendingSecurity pending)
        {
            try
            {
                _port.TryDismiss(pending.PromptId, out _);
            }
            catch
            {
            }
            CompleteSecurity(
                pending,
                LauncherWingsHairSecurityApproval.Reject());
        }

        private void CompleteSecurity(
            PendingSecurity pending,
            LauncherWingsHairSecurityApproval result)
        {
            bool owned;
            lock (_sync)
            {
                owned = ReferenceEquals(
                    _pendingSecurity,
                    pending);
                if (owned)
                    _pendingSecurity = null;
            }
            if (!owned)
                return;
            if (pending.HasCancellationRegistration)
                pending.CancellationRegistration.Unregister();
            pending.Completion.TrySetResult(result);
        }

        private void ShowChooser(PendingChooser pending)
        {
            lock (_sync)
            {
                if (_disposed
                    || !ReferenceEquals(
                        _pendingChooser,
                        pending))
                {
                    return;
                }
            }
            var form =
                new LauncherWingsHairChooserForm(
                    pending.Card)
                {
                    Owner = _owner
                };
            pending.Form = form;
            form.CreateControl();
            _ = form.Handle;
            if (!pending.Interaction.TryBindChooserWindow(
                    pending.Card.ChooserId,
                    form.Handle.ToInt64(),
                    _owner.Handle.ToInt64(),
                    out _))
            {
                CompleteChooser(
                    pending,
                    LauncherWingsHairChooserSelection.Dismiss(
                        "human_intervention_required"));
                form.Dispose();
                return;
            }
            form.SelectionRequested +=
                choice =>
                {
                    CompleteChooser(
                        pending,
                        LauncherWingsHairChooserSelection.Select(
                            pending.Card.ChooserId,
                            choice.Identifier));
                    form.Close();
                };
            form.FormClosed +=
                (_, _) =>
                {
                    pending.Interaction.MarkClosed(
                        form.Handle.ToInt64());
                    CompleteChooser(
                        pending,
                        LauncherWingsHairChooserSelection.Dismiss());
                    form.Dispose();
                };
            form.Show(_owner);
            form.Activate();
        }

        private void CancelChooser(PendingChooser pending)
        {
            CompleteChooser(
                pending,
                LauncherWingsHairChooserSelection.Dismiss());
            TryRunOnUi(
                () =>
                {
                    if (pending.Form != null
                        && !pending.Form.IsDisposed)
                    {
                        pending.Form.Close();
                    }
                });
        }

        private void CompleteChooser(
            PendingChooser pending,
            LauncherWingsHairChooserSelection result)
        {
            bool owned;
            lock (_sync)
            {
                owned = ReferenceEquals(_pendingChooser, pending);
                if (owned)
                    _pendingChooser = null;
            }
            if (!owned)
                return;
            if (pending.HasCancellationRegistration)
                pending.CancellationRegistration.Unregister();
            pending.Completion.TrySetResult(result);
        }

        private bool TryRunOnUi(Action action)
        {
            try
            {
                if (_owner.IsDisposed
                    || !_owner.IsHandleCreated)
                {
                    return false;
                }
                if (_owner.InvokeRequired)
                    _owner.BeginInvoke(action);
                else
                    action();
                return true;
            }
            catch
            {
                return false;
            }
        }

        private TrustedNeutralConsentPrompt
            BuildPreparationPrompt(
                LauncherWingsHairPreparationProposal proposal)
        {
            return new TrustedNeutralConsentPrompt(
                OpaqueIdGenerator.Create("consentprompt"),
                proposal.SessionId,
                proposal.SaveBindingId,
                "项目内助手",
                "当前 CF7 游戏会话",
                proposal.Slot,
                new[]
                {
                    new NeutralConsentScopeDisplay(
                        "player_state",
                        "读取当前发型、目录与版本"),
                    new NeutralConsentScopeDisplay(
                        "pixels",
                        "采集当前 Web 发型界面的短期验证帧")
                },
                "准备一次结构化发型选择；此步骤尚不修改存档。",
                proposal.IssuedAtUtc,
                proposal.ExpiresAtUtc,
                "只在本次会话内保留哈希和事务状态；不落盘或导出像素。",
                "选择发型后仍会再次显示精确 before/after 修改授权。",
                "暂停、隐藏、会话变化或外部输入会取消整个流程。");
        }

        private TrustedNeutralConsentPrompt BuildRestorePrompt(
            LauncherWingsHairRestoreProposal proposal)
        {
            return new TrustedNeutralConsentPrompt(
                OpaqueIdGenerator.Create("consentprompt"),
                proposal.SessionId,
                proposal.SaveBindingId,
                "项目内助手",
                "当前 CF7 游戏会话",
                proposal.Slot,
                new[]
                {
                    new NeutralConsentScopeDisplay(
                        "appearance_hair_restore",
                        "恢复本次事务修改前的发型")
                },
                "发型："
                    + proposal.AfterHair
                    + " → "
                    + proposal.BeforeHair,
                proposal.IssuedAtUtc,
                proposal.ExpiresAtUtc,
                "恢复令牌只保存在本次会话内；不会写入日志、对白或导出。",
                "当前发型或存档绑定已变化时，恢复会拒绝且不会覆盖人工修改。",
                "拒绝或关闭不会修改发型。");
        }

        private sealed class PendingSecurity
        {
            internal PendingSecurity(
                string promptId,
                DateTimeOffset expiresAtUtc,
                SessionMutationExpectation expectation)
            {
                PromptId = promptId;
                ExpiresAtUtc = expiresAtUtc;
                Expectation = expectation;
            }

            internal string PromptId { get; }
            internal DateTimeOffset ExpiresAtUtc { get; }
            internal SessionMutationExpectation Expectation { get; }
            internal TaskCompletionSource<
                LauncherWingsHairSecurityApproval> Completion { get; } =
                    new TaskCompletionSource<
                        LauncherWingsHairSecurityApproval>(
                            TaskCreationOptions
                                .RunContinuationsAsynchronously);
            internal CancellationTokenRegistration
                CancellationRegistration;
            internal bool HasCancellationRegistration;
        }

        private sealed class PendingChooser
        {
            internal PendingChooser(
                LauncherWingsHairChooserCard card,
                LauncherTrustedHumanInteractionTicket interaction)
            {
                Card = card;
                Interaction = interaction
                    ?? throw new ArgumentNullException(
                        nameof(interaction));
            }

            internal LauncherWingsHairChooserCard Card { get; }
            internal LauncherTrustedHumanInteractionTicket
                Interaction { get; }
            internal Form Form { get; set; }
            internal TaskCompletionSource<
                LauncherWingsHairChooserSelection> Completion { get; } =
                    new TaskCompletionSource<
                        LauncherWingsHairChooserSelection>(
                            TaskCreationOptions
                                .RunContinuationsAsynchronously);
            internal CancellationTokenRegistration
                CancellationRegistration;
            internal bool HasCancellationRegistration;
        }
    }

    internal sealed class LauncherWingsHairChooserForm : Form
    {
        private readonly ListBox _choices;

        internal LauncherWingsHairChooserForm(
            LauncherWingsHairChooserCard card)
        {
            if (card == null)
                throw new ArgumentNullException(nameof(card));
            Text = "Wings · 选择发型";
            StartPosition = FormStartPosition.CenterParent;
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            ClientSize = new Size(460, 390);
            BackColor = Color.FromArgb(245, 247, 250);

            var title = new Label
            {
                AutoSize = false,
                Text = "选择当前存档要预览的发型",
                Font = new Font(Font, FontStyle.Bold),
                Location = new Point(24, 20),
                Size = new Size(410, 28)
            };
            var detail = new Label
            {
                AutoSize = false,
                Text = "存档：" + card.Slot
                    + Environment.NewLine
                    + "选择后会显示独立的精确修改授权。",
                Location = new Point(24, 54),
                Size = new Size(410, 48)
            };
            _choices = new ListBox
            {
                Location = new Point(24, 112),
                Size = new Size(410, 205),
                IntegralHeight = false
            };
            foreach (LauncherWingsHairChoice choice
                in card.Choices)
            {
                _choices.Items.Add(choice);
            }
            _choices.SelectedItem =
                card.Choices.FirstOrDefault(
                    choice => !choice.IsCurrent);

            var choose = new Button
            {
                Text = "预览并继续",
                Location = new Point(258, 336),
                Size = new Size(96, 32)
            };
            var cancel = new Button
            {
                Text = "取消",
                DialogResult = DialogResult.Cancel,
                Location = new Point(360, 336),
                Size = new Size(74, 32)
            };
            choose.Click +=
                (_, _) =>
                {
                    if (_choices.SelectedItem
                            is LauncherWingsHairChoice choice
                        && !choice.IsCurrent)
                    {
                        SelectionRequested?.Invoke(choice);
                    }
                };
            AcceptButton = choose;
            CancelButton = cancel;
            Controls.Add(title);
            Controls.Add(detail);
            Controls.Add(_choices);
            Controls.Add(choose);
            Controls.Add(cancel);
        }

        internal event Action<LauncherWingsHairChoice>
            SelectionRequested;
    }
}
