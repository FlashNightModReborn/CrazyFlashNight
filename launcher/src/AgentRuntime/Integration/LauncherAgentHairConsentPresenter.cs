using System;
using System.Collections.Generic;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Wings;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Publishes a Launcher-owned consent HWND into the session registry as a
    /// human-only security surface before it is made visible. Removing the
    /// lease never acknowledges reauthorization by itself.
    /// </summary>
    internal sealed class LauncherHumanOnlySurfacePublisher
        : IWingsHumanOnlySurfacePublisher
    {
        private readonly SessionSurfaceHostController _controller;
        private readonly SessionSurfaceRegistry _registry;
        private readonly SessionRegistryHostOwner _owner;

        public LauncherHumanOnlySurfacePublisher(
            SessionSurfaceHostController controller,
            SessionRegistryHostOwner owner)
        {
            _controller = controller
                ?? throw new ArgumentNullException(nameof(controller));
            _registry = controller.Registry;
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
        }

        public bool TryPublish(
            WingsHumanOnlySurfaceDescriptor descriptor,
            out IWingsHumanOnlySurfaceLease lease,
            out string reasonCode)
        {
            lease = null;
            if (descriptor == null)
            {
                reasonCode =
                    "human_only_surface_descriptor_missing";
                return false;
            }
            try
            {
                _controller.SynchronizeSurface(
                    descriptor.ToSessionRegistration(
                        _owner.LauncherProcess));
                if (!_registry.TryGetRegisteredSurface(
                        _controller.SessionId,
                        descriptor.TargetId,
                        out SessionSurfaceSnapshot published)
                    || published.WindowHandle
                        != descriptor.WindowHandle
                    || published.OwnerWindowHandle
                        != descriptor.OwnerWindowHandle
                    || published.SurfaceEpoch == 0)
                {
                    _controller.RemoveSurface(
                        descriptor.TargetId);
                    reasonCode =
                        "human_only_surface_publish_failed";
                    return false;
                }
                lease = new SurfaceLease(
                    _controller,
                    published);
                reasonCode = null;
                return true;
            }
            catch
            {
                reasonCode =
                    "human_only_surface_publish_failed";
                return false;
            }
        }

        public bool TryAcknowledgeHumanReauthorization(
            SessionMutationExpectation expectation,
            out string reasonCode)
        {
            if (expectation == null)
            {
                reasonCode =
                    "human_reauthorization_expectation_missing";
                return false;
            }
            try
            {
                _registry.AcknowledgeHumanReauthorization(
                    _owner,
                    expectation);
                reasonCode = null;
                return true;
            }
            catch (InvalidOperationException exception)
            {
                reasonCode = exception.Message switch
                {
                    "security_surface_still_present" =>
                        "security_modal_active",
                    "desktop_unavailable" =>
                        "desktop_unavailable",
                    _ => "human_reauthorization_failed"
                };
                return false;
            }
            catch
            {
                reasonCode = "human_reauthorization_failed";
                return false;
            }
        }

        private sealed class SurfaceLease
            : IWingsHumanOnlySurfaceLease
        {
            private SessionSurfaceHostController _controller;
            private readonly string _targetId;

            public SurfaceLease(
                SessionSurfaceHostController controller,
                SessionSurfaceSnapshot surface)
            {
                _controller = controller;
                _targetId = surface.TargetId;
                TargetId = surface.TargetId;
                WindowHandle = surface.WindowHandle;
                OwnerWindowHandle =
                    surface.OwnerWindowHandle;
                SurfaceEpoch = surface.SurfaceEpoch;
            }

            public string TargetId { get; }
            public long WindowHandle { get; }
            public long OwnerWindowHandle { get; }
            public ulong SurfaceEpoch { get; }

            public void Dispose()
            {
                SessionSurfaceHostController controller =
                    Interlocked.Exchange(
                        ref _controller,
                        null);
                if (controller == null)
                    return;
                try
                {
                    controller.RemoveSurface(_targetId);
                }
                catch
                {
                    // A failed unregister remains visible to the registry.
                    // The later reauthorization acknowledgement will then
                    // fail closed with security_surface_still_present.
                }
            }
        }
    }

    /// <summary>
    /// The production bridge from a real human decision on a neutral
    /// Launcher-owned window to the Hair consent issuer. It never mints the
    /// domain token itself.
    /// </summary>
    internal sealed class LauncherAgentHairConsentPresenter
        : IAgentHairConsentPresenter,
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
        private PendingPresentation _pending;
        private bool _disposed;

        public LauncherAgentHairConsentPresenter(
            Form owner,
            IAgentRuntimeClock clock,
            SessionSurfaceHostController controller,
            SessionRegistryHostOwner registryOwner)
        {
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _clock = clock
                ?? throw new ArgumentNullException(nameof(clock));
            _surfacePublisher =
                new LauncherHumanOnlySurfacePublisher(
                    controller,
                    registryOwner);
            _port = new WingsConsentPresentationPort(
                owner,
                _surfacePublisher,
                this,
                () => _clock.UtcNow);
        }

        public Task<AgentHairConsentPresentationResult> PresentAsync(
            AgentHairConsentPresentationRequest request,
            CancellationToken cancellationToken)
        {
            if (request == null)
                throw new ArgumentNullException(nameof(request));
            if (cancellationToken.IsCancellationRequested)
            {
                return Task.FromResult(
                    AgentHairConsentPresentationResult
                        .Unavailable());
            }
            if (request.Interaction == null
                || request.Interaction.Phase
                    != LauncherTrustedHumanInteractionPhase
                        .HairCommitConsent)
            {
                return Task.FromResult(
                    AgentHairConsentPresentationResult
                        .Unavailable());
            }

            TrustedNeutralConsentPrompt prompt;
            SessionMutationExpectation expectation;
            try
            {
                prompt = BuildPrompt(request);
                expectation = BuildExpectation(request);
            }
            catch
            {
                return Task.FromResult(
                    AgentHairConsentPresentationResult
                        .Unavailable());
            }
            var pending = new PendingPresentation(
                prompt.PromptId,
                prompt.ExpiresAtUtc,
                expectation);
            lock (_sync)
            {
                if (_disposed)
                {
                    return Task.FromResult(
                        AgentHairConsentPresentationResult
                            .Unavailable());
                }
                if (_pending != null)
                {
                    return Task.FromResult(
                        AgentHairConsentPresentationResult
                            .Unavailable());
                }
                _pending = pending;
            }

            bool presented;
            try
            {
                presented = _port.TryPresent(
                    prompt,
                    request.Interaction,
                    out _);
            }
            catch
            {
                presented = false;
            }
            if (!presented)
            {
                Complete(
                    pending,
                    AgentHairConsentPresentationResult
                        .Unavailable());
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
                    pending.HasCancellationRegistration =
                        true;
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
            }

            // WingsConsentPresentationPort closes and unregisters the HWND in
            // its finally block after this callback returns. Queue the trusted
            // decision so reauthorization can only run after that cleanup.
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
                    AgentHairConsentPresentationResult
                        .Unavailable());
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
                        AgentHairConsentPresentationResult
                            .Unavailable());
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

            // An explicit Allow, Reject, or user-close Dismiss is a trusted
            // human interaction.
            // Clear the security-modal latch only after the consent HWND has
            // been removed. Allow additionally depends on this acknowledgement
            // succeeding; no token can be issued otherwise.
            if (!_surfacePublisher
                    .TryAcknowledgeHumanReauthorization(
                        pending.Expectation,
                        out _))
            {
                Complete(
                    pending,
                    AgentHairConsentPresentationResult
                        .Unavailable());
                return;
            }

            if (decision == NeutralConsentDecision.Allow
                && _clock.UtcNow >= pending.ExpiresAtUtc)
            {
                Complete(
                    pending,
                    AgentHairConsentPresentationResult
                        .Unavailable());
                return;
            }

            Complete(
                pending,
                decision == NeutralConsentDecision.Allow
                    ? AgentHairConsentPresentationResult.Allow(
                        OpaqueIdGenerator.Create(
                            "consentreceipt"))
                    : AgentHairConsentPresentationResult
                        .Reject());
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
                AgentHairConsentPresentationResult
                    .Unavailable());
        }

        private void Complete(
            PendingPresentation pending,
            AgentHairConsentPresentationResult result)
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

        private TrustedNeutralConsentPrompt BuildPrompt(
            AgentHairConsentPresentationRequest request)
        {
            DateTimeOffset issued = _clock.UtcNow;
            return new TrustedNeutralConsentPrompt(
                OpaqueIdGenerator.Create("consentprompt"),
                request.SessionId,
                SaveBindingId(request),
                RequesterDisplayName(request.PrincipalKind),
                "当前 CF7 游戏会话",
                SafeDisplay(
                    request.Preview.Binding.SlotId,
                    96,
                    "当前存档"),
                new[]
                {
                    new NeutralConsentScopeDisplay(
                        "appearance_hair_change",
                        "仅修改当前角色发型")
                },
                "发型："
                    + SafeDisplay(
                        request.Preview.BeforeHair,
                        160,
                        "未知")
                    + " → "
                    + SafeDisplay(
                        request.Preview.AfterHair,
                        160,
                        "未知"),
                issued,
                issued.Add(PromptLifetime),
                "仅在本次会话内保留事务收据；不导出像素或存档。",
                "拒绝或关闭不会修改发型；授权令牌仅可使用一次。",
                "你可随时操作键鼠夺回控制，或关闭助手暂停。");
        }

        private static string SaveBindingId(
            AgentHairConsentPresentationRequest request)
        {
            string canonical = request.SessionId
                + "\n"
                + request.LifecycleGeneration
                + "\n"
                + request.Preview.Binding.AttemptId
                + "\n"
                + request.Preview.Binding.SlotId
                + "\n"
                + request.Preview.Binding.SaveSignature;
            byte[] digest = SHA256.HashData(
                Encoding.UTF8.GetBytes(canonical));
            return "save_"
                + Convert.ToBase64String(
                        digest,
                        0,
                        16)
                    .TrimEnd('=')
                    .Replace('+', '-')
                    .Replace('/', '_');
        }

        private static string RequesterDisplayName(
            AgentPrincipalKind kind)
        {
            return kind switch
            {
                AgentPrincipalKind.DeveloperAgent =>
                    "本机开发 Agent",
                AgentPrincipalKind.UnattendedTestRunner =>
                    "本机测试 Agent",
                AgentPrincipalKind.WingsPersona =>
                    "项目内助手",
                _ => "本机 Agent"
            };
        }

        private static SessionMutationExpectation BuildExpectation(
            AgentHairConsentPresentationRequest request)
        {
            if (!string.Equals(
                    request.SessionId,
                    request.Preview.Binding.SessionId,
                    StringComparison.Ordinal)
                || request.Preview.Binding
                        .LifecycleGeneration <= 0
                || request.LifecycleGeneration
                    != checked((ulong)request.Preview.Binding
                        .LifecycleGeneration)
                || request.Preview.Binding
                        .AttemptGeneration <= 0)
            {
                throw new InvalidOperationException(
                    "consent_session_binding_invalid");
            }
            return new SessionMutationExpectation
            {
                SessionId = request.SessionId,
                LifecycleGeneration =
                    request.LifecycleGeneration,
                AttemptId =
                    request.Preview.Binding.AttemptId,
                AttemptGeneration = checked(
                    (ulong)request.Preview.Binding
                        .AttemptGeneration)
            };
        }

        private static string SafeDisplay(
            string value,
            int maximumLength,
            string fallback)
        {
            if (string.IsNullOrWhiteSpace(value))
                return fallback;
            var builder = new StringBuilder(
                Math.Min(value.Length, maximumLength));
            foreach (char character in value)
            {
                if (!char.IsControl(character))
                    builder.Append(character);
                if (builder.Length >= maximumLength)
                    break;
            }
            return builder.Length == 0
                ? fallback
                : builder.ToString();
        }

        private sealed class PendingPresentation
        {
            public PendingPresentation(
                string promptId,
                DateTimeOffset expiresAtUtc,
                SessionMutationExpectation expectation)
            {
                PromptId = promptId;
                ExpiresAtUtc = expiresAtUtc;
                Expectation = expectation
                    ?? throw new ArgumentNullException(
                        nameof(expectation));
                Completion =
                    new TaskCompletionSource<
                        AgentHairConsentPresentationResult>(
                        TaskCreationOptions
                            .RunContinuationsAsynchronously);
            }

            public string PromptId { get; }
            public DateTimeOffset ExpiresAtUtc { get; }
            public SessionMutationExpectation Expectation { get; }
            public TaskCompletionSource<
                AgentHairConsentPresentationResult>
                    Completion { get; }
            public CancellationTokenRegistration
                CancellationRegistration { get; set; }
            public bool HasCancellationRegistration { get; set; }
        }
    }
}
