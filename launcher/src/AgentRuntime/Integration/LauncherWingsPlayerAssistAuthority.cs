using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    internal sealed class WingsPlayerAssistAuthorizationChangedEventArgs
        : EventArgs
    {
        public WingsPlayerAssistAuthorizationChangedEventArgs(
            bool authorized,
            string receiptId,
            string reasonCode)
        {
            Authorized = authorized;
            ReceiptId = receiptId;
            ReasonCode = reasonCode;
        }

        public bool Authorized { get; }
        public string ReceiptId { get; }
        public string ReasonCode { get; }
    }

    /// <summary>
    /// Launcher-owned player-assist issuer. It can issue only a short-lived,
    /// read-only grant for public lore and host-observed window metadata in the
    /// one currently selected session. Persona text never reaches this issuer.
    /// </summary>
    internal sealed class LauncherWingsPlayerAssistAuthority
        : INeutralConsentDecisionSink,
          INeutralConsentFactsAuthority,
          IDisposable
    {
        private static readonly TimeSpan PromptLifetime =
            TimeSpan.FromSeconds(60);
        private static readonly TimeSpan GrantLifetime =
            TimeSpan.FromMinutes(5);
        private static readonly string[] DataScopes =
        {
            ObservationDataScopesV1.LorePublic,
            ObservationDataScopesV1.WindowMetadata
        };

        private readonly object _sync = new object();
        private readonly Form _owner;
        private readonly IAgentRuntimeClock _clock;
        private readonly SessionSurfaceHostController _surfaces;
        private readonly LauncherHumanOnlySurfacePublisher
            _surfacePublisher;
        private readonly LauncherWingsObservationIndicator
            _indicator;
        private readonly HostPrincipalEnrollmentVerifier _verifier;
        private readonly PrincipalCredentialAuthority _credentials;
        private readonly ObservationGrantBroker _grants;
        private readonly string _targetId;
        private readonly LoreView _loreView;
        private readonly EventHandler<
            SessionSurfaceRegistryChangedEventArgs>
                _registryChanged;
        private readonly string _clientInstanceId =
            OpaqueIdGenerator.Create("wingsclient");
        private PendingConsent _pending;
        private PrincipalCredential _credential;
        private ObservationGrant _grant;
        private TrustedNeutralPermissionFacts _facts;
        private SessionMutationExpectation _activeExpectation;
        private string _activeSlot;
        private bool _disposed;

        public LauncherWingsPlayerAssistAuthority(
            Form owner,
            IAgentRuntimeClock clock,
            SessionSurfaceHostController surfaces,
            SessionRegistryHostOwner registryOwner,
            HostPrincipalEnrollmentVerifier verifier,
            PrincipalCredentialAuthority credentials,
            ObservationGrantBroker grants,
            string targetId,
            LoreView loreView)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _surfaces = surfaces
                ?? throw new ArgumentNullException(nameof(surfaces));
            _surfacePublisher =
                new LauncherHumanOnlySurfacePublisher(
                    surfaces,
                    registryOwner
                        ?? throw new ArgumentNullException(
                            nameof(registryOwner)));
            _indicator =
                new LauncherWingsObservationIndicator(owner);
            _verifier = verifier
                ?? throw new ArgumentNullException(nameof(verifier));
            _credentials = credentials
                ?? throw new ArgumentNullException(nameof(credentials));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            WingsProtocolValue.RequireOpaqueId(
                targetId,
                nameof(targetId));
            _targetId = targetId;
            _loreView = loreView
                ?? throw new ArgumentNullException(nameof(loreView));
            _registryChanged = OnRegistryChanged;
            _surfaces.Registry.Changed += _registryChanged;
        }

        public event EventHandler<
            WingsPlayerAssistAuthorizationChangedEventArgs>
                AuthorizationChanged;

        internal PrincipalCredential CredentialForTest
        {
            get
            {
                lock (_sync)
                    return _credential;
            }
        }

        internal bool TryGetActiveCredential(
            out PrincipalCredential credential,
            out string reasonCode)
        {
            lock (_sync)
            {
                credential = null;
                if (_disposed
                    || _credential == null
                    || _credential.State
                        != CredentialState.Active)
                {
                    reasonCode =
                        "wings_credential_unavailable";
                    return false;
                }
                if (!TryAuthorizeLocked(
                        ObservationDataScopesV1.LorePublic,
                        out reasonCode)
                    || !SnapshotStillMatchesLocked(
                        out reasonCode))
                {
                    return false;
                }
                credential = _credential;
                reasonCode = null;
                return true;
            }
        }

        internal Form IndicatorFormForTest =>
            _indicator.FormForTest;

        internal ObservationGrant GrantForTest
        {
            get
            {
                lock (_sync)
                    return _grant;
            }
        }

        public TrustedNeutralConsentPrompt CreatePrompt()
        {
            SessionSnapshot snapshot = _surfaces.Snapshot;
            RequireEligibleSnapshot(snapshot);
            DateTimeOffset issued = _clock.UtcNow;
            var expectation = new SessionMutationExpectation
            {
                SessionId = snapshot.SessionId,
                LifecycleGeneration =
                    snapshot.LifecycleGeneration,
                AttemptId = snapshot.AttemptId,
                AttemptGeneration =
                    snapshot.AttemptGeneration
            };
            var prompt = new TrustedNeutralConsentPrompt(
                OpaqueIdGenerator.Create("consentprompt"),
                snapshot.SessionId,
                _loreView.Progress.SaveBindingId,
                "项目内助手",
                "当前 CF7 游戏会话",
                SafeDisplay(snapshot.Slot, "当前存档"),
                new[]
                {
                    new NeutralConsentScopeDisplay(
                        "lore_public",
                        "读取当前存档可公开的同伴资料"),
                    new NeutralConsentScopeDisplay(
                        "window_metadata",
                        "读取当前 Launcher 可见界面标识")
                },
                "启用只读指导；不点击、不输入、不修改游戏。",
                issued,
                issued.Add(PromptLifetime),
                "仅在本次会话内保留授权收据；不保留或导出像素。",
                "暂停、隐藏助手、会话变化或再次授权会立即撤销。",
                "你可随时操作键鼠夺回控制；本授权不包含输入权限。");

            lock (_sync)
            {
                ThrowIfDisposed();
                if (_pending != null)
                {
                    throw new InvalidOperationException(
                        "wings_consent_already_pending");
                }
                RevokeLocked("wings_reauthorization_requested");
                _pending = new PendingConsent(
                    prompt,
                    expectation,
                    snapshot.Slot);
            }
            RaiseChanged(
                false,
                null,
                "wings_observation_consent_pending");
            return prompt;
        }

        public void SubmitHumanDecision(
            NeutralConsentDecisionIntent intent)
        {
            if (intent == null)
                throw new ArgumentNullException(nameof(intent));
            PendingConsent pending;
            lock (_sync)
            {
                pending = _pending;
                if (_disposed
                    || pending == null
                    || !string.Equals(
                        pending.Prompt.PromptId,
                        intent.PromptId,
                        StringComparison.Ordinal))
                {
                    return;
                }
            }

            // The presentation port unregisters its human-only HWND after this
            // callback returns. Reauthorization and issuance must run later.
            try
            {
                _owner.BeginInvoke(
                    new Action(
                        () => FinalizeDecision(
                            pending,
                            intent.Decision)));
            }
            catch
            {
                CompleteDenied(
                    pending,
                    "wings_consent_ui_unavailable");
            }
        }

        public bool TryResolve(
            string receiptId,
            out TrustedNeutralPermissionFacts facts,
            out string reasonCode)
        {
            lock (_sync)
            {
                facts = null;
                if (_disposed
                    || _facts == null
                    || !string.Equals(
                        _facts.ReceiptId,
                        receiptId,
                        StringComparison.Ordinal))
                {
                    reasonCode =
                        "wings_permission_facts_unavailable";
                    return false;
                }
                if (!TryAuthorizeLocked(
                        ObservationDataScopesV1.LorePublic,
                        out reasonCode)
                    || !SnapshotStillMatchesLocked(
                        out reasonCode))
                {
                    RevokeLocked(
                        reasonCode
                            ?? "wings_observation_inactive");
                    return false;
                }
                facts = _facts;
                reasonCode = null;
                return true;
            }
        }

        public WingsVisibleGuidanceContext VisibleContext(
            WingsGuidanceDomain domain)
        {
            if (domain != WingsGuidanceDomain.Ui)
                return WingsVisibleGuidanceContext.Empty(domain);
            lock (_sync)
            {
                if (!TryAuthorizeLocked(
                        ObservationDataScopesV1.WindowMetadata,
                        out _)
                    || !SnapshotStillMatchesLocked(out _))
                {
                    RevokeLocked("wings_observation_inactive");
                    return WingsVisibleGuidanceContext.Empty(
                        domain);
                }
                SessionSnapshot snapshot = _surfaces.Snapshot;
                if (string.IsNullOrWhiteSpace(
                        snapshot.ActivePanelName)
                    || !string.Equals(
                        snapshot.ActivePanelTargetId,
                        _targetId,
                        StringComparison.Ordinal))
                {
                    return WingsVisibleGuidanceContext.Empty(
                        domain);
                }
                return new WingsVisibleGuidanceContext(
                    domain,
                    "launcher-visible-panel-v1",
                    new Dictionary<string, string>(
                        StringComparer.Ordinal)
                    {
                        ["ui.visible-panel-id"] =
                            snapshot.ActivePanelName
                    });
            }
        }

        public void Suspend(string reasonCode)
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                _pending = null;
                RevokeLocked(
                    string.IsNullOrWhiteSpace(reasonCode)
                        ? "wings_observation_suspended"
                        : reasonCode);
            }
            RaiseChanged(
                false,
                null,
                reasonCode
                    ?? "wings_observation_suspended");
        }

        public void Dispose()
        {
            lock (_sync)
            {
                if (_disposed)
                    return;
                _disposed = true;
                _pending = null;
                RevokeLocked("wings_authority_disposed");
            }
            _surfaces.Registry.Changed -= _registryChanged;
            _indicator.Dispose();
        }

        private void OnRegistryChanged(
            object sender,
            SessionSurfaceRegistryChangedEventArgs args)
        {
            bool revoked = false;
            string reason = null;
            lock (_sync)
            {
                if (_disposed || _grant == null)
                    return;
                SessionSnapshot snapshot =
                    args.Snapshot.FindSession(
                        _surfaces.SessionId);
                if (snapshot == null
                    || _activeExpectation == null
                    || !SnapshotMatches(
                        snapshot,
                        _activeExpectation,
                        _activeSlot)
                    || _credential == null
                    || !_grants.TryAuthorize(
                        _grant.ObservationGrantId,
                        _credential.ClientInstanceId,
                        _credential.SecurityPrincipalId,
                        _grant.SessionId,
                        _targetId,
                        ObservationDataScopesV1
                            .LorePublic,
                        out _,
                        out reason))
                {
                    reason ??=
                        args.Invalidation?.ReasonCode
                        ?? "wings_session_binding_changed";
                    RevokeLocked(reason);
                    revoked = true;
                }
            }
            if (revoked)
                RaiseChanged(false, null, reason);
        }

        private void FinalizeDecision(
            PendingConsent pending,
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
                        pending.Expectation,
                        out string acknowledgeReason))
            {
                CompleteDenied(
                    pending,
                    acknowledgeReason
                        ?? "human_reauthorization_failed");
                return;
            }
            if (decision != NeutralConsentDecision.Allow)
            {
                CompleteDenied(
                    pending,
                    "wings_observation_consent_denied");
                return;
            }
            if (_clock.UtcNow >= pending.Prompt.ExpiresAtUtc)
            {
                CompleteDenied(
                    pending,
                    "wings_observation_consent_expired");
                return;
            }

            string receipt =
                OpaqueIdGenerator.Create("consentreceipt");
            try
            {
                lock (_sync)
                {
                    if (_disposed
                        || !ReferenceEquals(
                            _pending,
                            pending)
                        || !SnapshotMatches(
                            _surfaces.Snapshot,
                            pending.Expectation,
                            pending.Slot))
                    {
                        throw new InvalidOperationException(
                            "wings_session_binding_changed");
                    }
                    string[] capabilities = DataScopes
                        .Select(scope => "observe:" + scope)
                        .ToArray();
                    var evidence =
                        new PlayerAssistCredentialEvidence
                        {
                            ClientInstanceId =
                                _clientInstanceId,
                            ConsentReceipt = receipt,
                            SelectedSessionId =
                                pending.Expectation.SessionId,
                            AllowedCapabilities =
                                capabilities,
                            AllowedTargets =
                                new[] { _targetId },
                            RequestedLifetime =
                                GrantLifetime
                        };
                    _verifier.RegisterPlayerConsent(evidence);
                    PrincipalCredential credential =
                        _credentials.IssuePlayerAssist(
                            evidence);
                    ObservationGrant grant = null;
                    try
                    {
                        grant = _grants.Issue(
                            new ObservationGrantRequest
                            {
                                CredentialId =
                                    credential.CredentialId,
                                ClientInstanceId =
                                    credential.ClientInstanceId,
                                SessionId =
                                    pending.Expectation
                                        .SessionId,
                                Targets = new[]
                                {
                                    new ObservationTargetScope
                                    {
                                        TargetId =
                                            _targetId
                                    }
                                },
                                DataScopes = DataScopes,
                                RequestedLifetime =
                                    GrantLifetime,
                                ConsentReceipt = receipt,
                                AllowEphemeralKeyframes =
                                    false,
                                AllowPersistence = false,
                                AllowExport = false
                            });
                        if (!Authorize(
                                grant,
                                credential,
                                ObservationDataScopesV1
                                    .LorePublic)
                            || !Authorize(
                                grant,
                                credential,
                                ObservationDataScopesV1
                                    .WindowMetadata)
                            || !SnapshotMatches(
                                _surfaces.Snapshot,
                                pending.Expectation,
                                pending.Slot))
                        {
                            throw new InvalidOperationException(
                                "wings_post_issue_recheck_failed");
                        }
                        _credential = credential;
                        _grant = grant;
                        if (!_indicator.TryShow(
                                _clock.UtcNow.Add(
                                    GrantLifetime),
                                GrantLifetime,
                                () => Suspend(
                                    "wings_indicator_closed")))
                        {
                            throw new InvalidOperationException(
                                "wings_indicator_unavailable");
                        }
                        _facts =
                            new TrustedNeutralPermissionFacts(
                                receipt,
                                pending.Expectation.SessionId,
                                _loreView.Progress
                                    .SaveBindingId,
                                _loreView.LoreViewId,
                                "只读游戏界面指导",
                                DataScopes,
                                NeutralRetentionMode
                                    .SessionOnly,
                                _clock.UtcNow,
                                _clock.UtcNow.Add(
                                    GrantLifetime));
                        _activeExpectation =
                            pending.Expectation;
                        _activeSlot = pending.Slot;
                        _pending = null;
                    }
                    catch
                    {
                        if (grant != null)
                        {
                            _grants.Revoke(
                                grant.ObservationGrantId,
                                "wings_issue_rollback");
                        }
                        _credentials.Revoke(
                            credential.CredentialId,
                            "wings_issue_rollback");
                        throw;
                    }
                }
            }
            catch
            {
                CompleteDenied(
                    pending,
                    "wings_observation_issue_failed");
                return;
            }
            RaiseChanged(true, receipt, null);
        }

        private void CompleteDenied(
            PendingConsent pending,
            string reasonCode)
        {
            lock (_sync)
            {
                if (!ReferenceEquals(_pending, pending))
                    return;
                _pending = null;
                RevokeLocked(
                    reasonCode
                        ?? "wings_observation_denied");
            }
            RaiseChanged(false, null, reasonCode);
        }

        private bool TryAuthorizeLocked(
            string dataScope,
            out string reasonCode)
        {
            if (_credential == null || _grant == null)
            {
                reasonCode =
                    "wings_observation_grant_missing";
                return false;
            }
            if (!_indicator.IsAlive)
            {
                reasonCode =
                    "wings_indicator_inactive";
                return false;
            }
            return _grants.TryAuthorize(
                _grant.ObservationGrantId,
                _credential.ClientInstanceId,
                _credential.SecurityPrincipalId,
                _grant.SessionId,
                _targetId,
                dataScope,
                out _,
                out reasonCode);
        }

        private bool Authorize(
            ObservationGrant grant,
            PrincipalCredential credential,
            string dataScope)
        {
            return _grants.TryAuthorize(
                grant.ObservationGrantId,
                credential.ClientInstanceId,
                credential.SecurityPrincipalId,
                grant.SessionId,
                _targetId,
                dataScope,
                out _,
                out _);
        }

        private bool SnapshotStillMatchesLocked(
            out string reasonCode)
        {
            SessionSnapshot snapshot = _surfaces.Snapshot;
            if (_grant == null
                || _activeExpectation == null
                || !SnapshotMatches(
                    snapshot,
                    _activeExpectation,
                    _activeSlot))
            {
                reasonCode =
                    "wings_session_binding_changed";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private void RequireEligibleSnapshot(
            SessionSnapshot snapshot)
        {
            if (snapshot.SessionMode
                    == SessionMode.UnattendedTest
                || snapshot.AttemptId == null
                || !snapshot.AttemptGeneration.HasValue
                || snapshot.HumanReauthorizationRequired
                || !HasEligibleTarget(snapshot))
            {
                throw new InvalidOperationException(
                    "wings_observation_target_unavailable");
            }
        }

        private bool HasEligibleTarget(SessionSnapshot snapshot)
        {
            return snapshot.Surfaces.Any(
                surface =>
                    string.Equals(
                        surface.TargetId,
                        _targetId,
                        StringComparison.Ordinal)
                    && surface.SafetyKind
                        == AgentTargetSafetyKind.RuntimeOwned);
        }

        private bool SnapshotMatches(
            SessionSnapshot snapshot,
            SessionMutationExpectation expectation,
            string slot)
        {
            return string.Equals(
                    snapshot.SessionId,
                    expectation.SessionId,
                    StringComparison.Ordinal)
                && snapshot.LifecycleGeneration
                    == expectation.LifecycleGeneration
                && string.Equals(
                    snapshot.AttemptId,
                    expectation.AttemptId,
                    StringComparison.Ordinal)
                && snapshot.AttemptGeneration
                    == expectation.AttemptGeneration
                && string.Equals(
                    snapshot.Slot,
                    slot,
                    StringComparison.Ordinal)
                && snapshot.SessionMode
                    != SessionMode.UnattendedTest
                && !snapshot.HumanReauthorizationRequired
                && HasEligibleTarget(snapshot);
        }

        private void RevokeLocked(string reasonCode)
        {
            if (_grant != null)
            {
                _grants.Revoke(
                    _grant.ObservationGrantId,
                    reasonCode);
            }
            if (_credential != null)
            {
                _credentials.Revoke(
                    _credential.CredentialId,
                    reasonCode);
            }
            _grant = null;
            _credential = null;
            _facts = null;
            _activeExpectation = null;
            _activeSlot = null;
            _indicator.Close();
        }

        private void RaiseChanged(
            bool authorized,
            string receiptId,
            string reasonCode)
        {
            AuthorizationChanged?.Invoke(
                this,
                new WingsPlayerAssistAuthorizationChangedEventArgs(
                    authorized,
                    receiptId,
                    reasonCode));
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(
                    nameof(
                        LauncherWingsPlayerAssistAuthority));
        }

        private static string SafeDisplay(
            string value,
            string fallback)
        {
            if (string.IsNullOrWhiteSpace(value))
                return fallback;
            var builder = new StringBuilder(
                Math.Min(value.Length, 96));
            foreach (char character in value)
            {
                if (!char.IsControl(character))
                    builder.Append(character);
                if (builder.Length == 96)
                    break;
            }
            return builder.Length == 0
                ? fallback
                : builder.ToString();
        }

        private sealed class PendingConsent
        {
            public PendingConsent(
                TrustedNeutralConsentPrompt prompt,
                SessionMutationExpectation expectation,
                string slot)
            {
                Prompt = prompt;
                Expectation = expectation;
                Slot = slot;
            }

            public TrustedNeutralConsentPrompt Prompt { get; }
            public SessionMutationExpectation Expectation { get; }
            public string Slot { get; }
        }
    }
}
