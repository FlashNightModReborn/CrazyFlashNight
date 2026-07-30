using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.RegularExpressions;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Sessions
{
    /// <summary>
    /// Host-authoritative binding between one Launcher lifecycle and its
    /// explicitly registered logical sessions/surfaces. Nothing is discovered
    /// from a title or executable name, and unknown targets fail closed.
    /// </summary>
    public sealed class SessionSurfaceRegistry
        : IAgentTargetAuthority,
          IAgentSessionModeAuthority
    {
        private static readonly Regex OpaqueIdPattern = new Regex(
            "^[A-Za-z0-9_-]{22,128}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);
        private static readonly Regex Sha256Pattern = new Regex(
            "^[A-Fa-f0-9]{64}$",
            RegexOptions.CultureInvariant | RegexOptions.Compiled);

        private const SessionInvalidationFlags LifecycleInvalidationFlags =
            SessionInvalidationFlags.ObservationGrants
            | SessionInvalidationFlags.WriteLeases
            | SessionInvalidationFlags.Observations
            | SessionInvalidationFlags.SemanticNodes
            | SessionInvalidationFlags.PendingActions
            | SessionInvalidationFlags.PendingCoordinateActions
            | SessionInvalidationFlags.PendingInput
            | SessionInvalidationFlags.PendingDomainOperations
            | SessionInvalidationFlags.ExactInstanceLeases
            | SessionInvalidationFlags.QueuedActions
            | SessionInvalidationFlags.RuntimeHeldInput
            | SessionInvalidationFlags.AttemptScopedAuthorities;

        private const SessionInvalidationFlags SecurityInvalidationFlags =
            SessionInvalidationFlags.WriteLeases
            | SessionInvalidationFlags.Observations
            | SessionInvalidationFlags.PendingActions
            | SessionInvalidationFlags.PendingInput
            | SessionInvalidationFlags.QueuedActions
            | SessionInvalidationFlags.RuntimeHeldInput;

        private readonly object _sync = new object();
        private readonly SessionRegistryHostOwner _hostOwner;
        private readonly ISessionSurfaceHostValidator _hostValidator;
        private readonly Dictionary<string, MutableSession> _sessions =
            new Dictionary<string, MutableSession>(StringComparer.Ordinal);
        private readonly Queue<SessionSurfaceRegistryChangedEventArgs>
            _pendingEvents =
                new Queue<SessionSurfaceRegistryChangedEventArgs>();

        private ulong _sequence;
        private bool _dispatchingEvents;
        private SessionSurfaceRegistrySnapshot _snapshot =
            new SessionSurfaceRegistrySnapshot(
                0,
                Array.Empty<SessionSnapshot>());

        internal SessionSurfaceRegistry(
            SessionRegistryHostOwner hostOwner,
            ISessionSurfaceHostValidator hostValidator)
        {
            _hostOwner = hostOwner
                ?? throw new ArgumentNullException(nameof(hostOwner));
            _hostValidator = hostValidator
                ?? throw new ArgumentNullException(nameof(hostValidator));
        }

        internal static SessionSurfaceRegistry CreateForCurrentLauncher(
            out SessionRegistryHostOwner hostOwner)
        {
            hostOwner = SessionRegistryHostOwner.CaptureCurrentLauncher();
            return new SessionSurfaceRegistry(
                hostOwner,
                new WindowsSessionSurfaceHostValidator());
        }

        internal event EventHandler<SessionSurfaceRegistryChangedEventArgs>
            Changed;

        internal SessionSurfaceRegistrySnapshot GetSnapshot()
        {
            lock (_sync)
            {
                return _snapshot;
            }
        }

        /// <summary>
        /// Host-private lookup used only by the Launcher mutation facade.
        /// Unlike the public/discoverable snapshot, this can return a
        /// human-only security surface so the host can refresh and remove its
        /// exact registration without ever exposing it to Agent discovery.
        /// </summary>
        internal bool TryGetRegisteredSurface(
            string sessionId,
            string targetId,
            out SessionSurfaceSnapshot surface)
        {
            lock (_sync)
            {
                surface = null;
                if (!_sessions.TryGetValue(
                        sessionId ?? string.Empty,
                        out MutableSession session)
                    || !session.Surfaces.TryGetValue(
                        targetId ?? string.Empty,
                        out MutableSurface mutable))
                {
                    return false;
                }
                surface = mutable.CreateSnapshot(
                    session.FocusEpoch,
                    session.ModalEpoch,
                    session.ActiveTargetId);
                return true;
            }
        }

        public bool TryResolve(
            string sessionId,
            string targetId,
            out AgentTargetDescriptor descriptor,
            out string reasonCode)
        {
            lock (_sync)
            {
                descriptor = null;
                if (!_sessions.TryGetValue(
                        sessionId ?? string.Empty,
                        out MutableSession session))
                {
                    reasonCode = "session_not_found";
                    return false;
                }
                if (!session.Surfaces.TryGetValue(
                        targetId ?? string.Empty,
                        out MutableSurface surface))
                {
                    reasonCode = "target_not_authoritative";
                    return false;
                }
                if (!TryValidateSurfaceWithHost(
                        session,
                        surface.ToRegistration(),
                        out reasonCode))
                {
                    return false;
                }
                if (surface.SafetyKind
                    == AgentTargetSafetyKind.HumanOnlySecuritySurface)
                {
                    descriptor = new AgentTargetDescriptor(
                        session.SessionId,
                        surface.TargetId,
                        surface.SafetyKind,
                        surface.Kind);
                    reasonCode = null;
                    return true;
                }
                if (session.HumanReauthorizationRequired)
                {
                    reasonCode = "human_intervention_required";
                    return false;
                }

                descriptor = new AgentTargetDescriptor(
                    session.SessionId,
                    surface.TargetId,
                    AgentTargetSafetyKind.RuntimeOwned,
                    surface.Kind);
                reasonCode = null;
                return true;
            }
        }

        bool IAgentSessionModeAuthority.TryResolveSessionMode(
            string sessionId,
            out SessionMode sessionMode,
            out string reasonCode)
        {
            lock (_sync)
            {
                if (!_sessions.TryGetValue(
                        sessionId ?? string.Empty,
                        out MutableSession session))
                {
                    sessionMode = default;
                    reasonCode = "session_not_found";
                    return false;
                }
                sessionMode = session.SessionMode;
                reasonCode = null;
                return true;
            }
        }

        internal bool TryValidateTargetGeneration(
            SessionTargetGenerationExpectation expectation,
            InputMode? requestedInputMode,
            out SessionSurfaceSnapshot surface,
            out string reasonCode)
        {
            return TryValidateTargetGenerationCore(
                expectation,
                requestedInputMode,
                true,
                out surface,
                out reasonCode);
        }

        /// <summary>
        /// Generation-only validation for latency-critical containment paths.
        /// The caller must already hold a live identity signal obtained by a
        /// caller-thread validation. No process module/path probe is performed.
        /// </summary>
        internal bool TryValidateTargetGenerationBounded(
            SessionTargetGenerationExpectation expectation,
            InputMode? requestedInputMode,
            out SessionSurfaceSnapshot surface,
            out string reasonCode)
        {
            return TryValidateTargetGenerationCore(
                expectation,
                requestedInputMode,
                false,
                out surface,
                out reasonCode);
        }

        private bool TryValidateTargetGenerationCore(
            SessionTargetGenerationExpectation expectation,
            InputMode? requestedInputMode,
            bool validateLiveSurfaceIdentity,
            out SessionSurfaceSnapshot surface,
            out string reasonCode)
        {
            lock (_sync)
            {
                surface = null;
                if (expectation == null)
                {
                    reasonCode = "arguments_invalid";
                    return false;
                }
                if (!_sessions.TryGetValue(
                        expectation.SessionId ?? string.Empty,
                        out MutableSession session))
                {
                    reasonCode = "session_not_found";
                    return false;
                }
                if (session.LifecycleGeneration
                    != expectation.LifecycleGeneration)
                {
                    reasonCode = "stale_lifecycle";
                    return false;
                }
                if (!AttemptMatches(
                        session,
                        expectation.AttemptId,
                        expectation.AttemptGeneration))
                {
                    reasonCode = "stale_attempt";
                    return false;
                }
                if (!session.Surfaces.TryGetValue(
                        expectation.TargetId ?? string.Empty,
                        out MutableSurface mutable))
                {
                    reasonCode = "target_not_authoritative";
                    return false;
                }
                if (validateLiveSurfaceIdentity
                    && !TryValidateSurfaceWithHost(
                        session,
                        mutable.ToRegistration(),
                        out reasonCode))
                {
                    return false;
                }
                if (mutable.SafetyKind
                    == AgentTargetSafetyKind.HumanOnlySecuritySurface)
                {
                    reasonCode = "human_only_security_surface";
                    return false;
                }
                if (session.HumanReauthorizationRequired)
                {
                    reasonCode = "human_intervention_required";
                    return false;
                }
                if (!session.DesktopAvailable)
                {
                    reasonCode = "desktop_unavailable";
                    return false;
                }
                if (mutable.Minimized)
                {
                    reasonCode = "target_minimized";
                    return false;
                }
                if (!mutable.Visible)
                {
                    reasonCode = "foreground_mismatch";
                    return false;
                }
                if (mutable.SurfaceEpoch != expectation.SurfaceEpoch)
                {
                    reasonCode = "stale_surface";
                    return false;
                }
                if (mutable.CoordinateSpaceVersion
                    != expectation.CoordinateSpaceVersion)
                {
                    reasonCode = "stale_coordinate_space";
                    return false;
                }
                if (session.FocusEpoch != expectation.FocusEpoch)
                {
                    reasonCode = "stale_focus";
                    return false;
                }
                if (session.ModalEpoch != expectation.ModalEpoch)
                {
                    reasonCode = "stale_modal";
                    return false;
                }
                if (expectation.DocumentGeneration.HasValue
                    || mutable.DocumentGeneration.HasValue)
                {
                    if (expectation.DocumentGeneration
                        != mutable.DocumentGeneration)
                    {
                        reasonCode = "stale_document";
                        return false;
                    }
                }
                if (!string.Equals(
                        expectation.PanelInstanceId,
                        session.PanelInstanceIdForTarget(
                            expectation.TargetId),
                        StringComparison.Ordinal))
                {
                    reasonCode = "stale_panel_instance";
                    return false;
                }
                if (requestedInputMode.HasValue
                    && !mutable.InputModes.Contains(
                        requestedInputMode.Value))
                {
                    reasonCode = "unsupported_for_surface";
                    return false;
                }
                if (requestedInputMode.HasValue
                    && session.RuntimeQualification.RuntimeMode
                        == RuntimeMode.UnqualifiedDev)
                {
                    if (requestedInputMode.Value
                            == InputMode.DomainTransaction
                        || !session.RuntimeQualification
                            .UnqualifiedDevVisualInputAuthorized)
                    {
                        reasonCode = "runtime_unqualified";
                        return false;
                    }
                }
                if (requestedInputMode.HasValue
                    && requestedInputMode.Value
                        != InputMode.DomainTransaction)
                {
                    if (!string.Equals(
                            session.ActiveTargetId,
                            mutable.TargetId,
                            StringComparison.Ordinal))
                    {
                        reasonCode = "foreground_mismatch";
                        return false;
                    }
                    if (session.Surfaces.Values.Any(surface =>
                            surface.SafetyKind
                                == AgentTargetSafetyKind.RuntimeOwned
                            && surface.Kind
                                == SurfaceKind.BusinessModal)
                        && mutable.Kind != SurfaceKind.BusinessModal)
                    {
                        reasonCode = "blocking_modal";
                        return false;
                    }
                }

                surface = mutable.CreateSnapshot(
                    session.FocusEpoch,
                    session.ModalEpoch,
                    session.ActiveTargetId);
                reasonCode = null;
                return true;
            }
        }

        internal bool TryValidateRegisteredSurface(
            SessionRegistryHostOwner hostOwner,
            SessionSurfaceMutationExpectation expectation,
            out string reasonCode)
        {
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session;
                MutableSurface surface = RequireSurface(
                    expectation,
                    out session);
                return TryValidateSurfaceWithHost(
                    session,
                    surface.ToRegistration(),
                    out reasonCode);
            }
        }

        internal SessionSurfaceRegistryChange RegisterSession(
            SessionRegistryHostOwner hostOwner,
            SessionHostRegistration registration)
        {
            bool shouldDispatch;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                ValidateSessionRegistration(registration);
                if (_sessions.ContainsKey(registration.SessionId))
                    throw new InvalidOperationException(
                        "session_already_registered");
                if (!_hostValidator.ValidateSession(
                        hostOwner,
                        registration,
                        out string reasonCode))
                {
                    throw new InvalidOperationException(
                        reasonCode ?? "session_owner_unverifiable");
                }

                MutableSession session = new MutableSession(registration);
                _sessions.Add(session.SessionId, session);
                change = CommitLocked(
                    new SessionScopeInvalidation(
                        SessionInvalidationLevel.Registration,
                        "session_registered",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.None,
                        Array.Empty<string>(),
                        false,
                        false),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange ReplaceLifecycle(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectedOld,
            SessionHostRegistration replacement)
        {
            bool shouldDispatch;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession old = RequireSession(expectedOld);
                ValidateSessionRegistration(replacement);
                if (string.Equals(
                        old.SessionId,
                        replacement.SessionId,
                        StringComparison.Ordinal)
                    || replacement.LifecycleGeneration
                        <= old.LifecycleGeneration)
                {
                    throw new InvalidOperationException(
                        "lifecycle_generation_not_advanced");
                }
                if (_sessions.ContainsKey(replacement.SessionId))
                    throw new InvalidOperationException(
                        "session_already_registered");
                if (!_hostValidator.ValidateSession(
                        hostOwner,
                        replacement,
                        out string reasonCode))
                {
                    throw new InvalidOperationException(
                        reasonCode ?? "session_owner_unverifiable");
                }

                string[] oldRuntimeTargets =
                    old.RuntimeTargetIds().ToArray();
                _sessions.Remove(old.SessionId);
                _sessions.Add(
                    replacement.SessionId,
                    new MutableSession(replacement));
                change = CommitLocked(
                    new SessionScopeInvalidation(
                        SessionInvalidationLevel.Lifecycle,
                        "launcher_lifecycle_replaced",
                        old.SessionId,
                        old.LifecycleGeneration,
                        LifecycleInvalidationFlags,
                        oldRuntimeTargets,
                        true,
                        true),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange RemoveSession(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectation)
        {
            bool shouldDispatch;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session = RequireSession(expectation);
                string[] targets = session.RuntimeTargetIds().ToArray();
                _sessions.Remove(session.SessionId);
                change = CommitLocked(
                    new SessionScopeInvalidation(
                        SessionInvalidationLevel.Lifecycle,
                        "session_removed",
                        session.SessionId,
                        session.LifecycleGeneration,
                        LifecycleInvalidationFlags,
                        targets,
                        true,
                        true),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange AdvanceAttempt(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectation,
            SessionAttemptRegistration nextAttempt)
        {
            bool shouldDispatch;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session = RequireSession(expectation);
                ValidateAttemptRegistration(nextAttempt);
                if (nextAttempt != null
                    && string.Equals(
                        session.AttemptId,
                        nextAttempt.AttemptId,
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "attempt_id_not_advanced");
                }
                if (!_hostValidator.ValidateAttemptProcess(
                        hostOwner,
                        nextAttempt?.FlashProcess,
                        out string reasonCode))
                {
                    throw new InvalidOperationException(
                        reasonCode ?? "flash_process_unverifiable");
                }

                string[] flashTargets = session.Surfaces.Values
                    .Where(IsFlashScoped)
                    .Where(surface => surface.SafetyKind
                        == AgentTargetSafetyKind.RuntimeOwned)
                    .Select(surface => surface.TargetId)
                    .ToArray();
                bool removedBusinessModal = session.Surfaces.Values
                    .Any(surface =>
                        IsFlashScoped(surface)
                        && surface.SafetyKind
                            == AgentTargetSafetyKind.RuntimeOwned
                        && surface.Kind == SurfaceKind.BusinessModal);
                bool removedActiveTarget = flashTargets.Contains(
                    session.ActiveTargetId,
                    StringComparer.Ordinal);
                bool removedActivePanel = flashTargets.Contains(
                    session.ActivePanelTargetId,
                    StringComparer.Ordinal);
                foreach (string targetId in session.Surfaces.Values
                    .Where(IsFlashScoped)
                    .Select(surface => surface.TargetId)
                    .ToArray())
                {
                    session.RemoveSurface(targetId);
                }
                if (removedActiveTarget)
                {
                    session.ActiveTargetId = null;
                    AdvanceFocusEpoch(session);
                }
                if (removedActivePanel)
                {
                    session.ActivePanelName = null;
                    session.ActivePanelInstanceId = null;
                    session.ActivePanelTargetId = null;
                }

                session.AttemptSequence = checked(
                    session.AttemptSequence + 1);
                session.AttemptId = nextAttempt?.AttemptId;
                session.AttemptGeneration = nextAttempt == null
                    ? null
                    : session.AttemptSequence;
                session.FlashProcess = nextAttempt?.FlashProcess;
                if (nextAttempt != null)
                {
                    session.Slot = nextAttempt.Slot;
                    session.SaveRevision = nextAttempt.SaveRevision;
                }
                if (removedBusinessModal)
                    AdvanceModalEpoch(session);

                change = CommitLocked(
                    new SessionScopeInvalidation(
                        SessionInvalidationLevel.Attempt,
                        nextAttempt == null
                            ? "attempt_ended"
                            : "attempt_advanced",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.ObservationGrants
                        | SessionInvalidationFlags.WriteLeases
                        | SessionInvalidationFlags.Observations
                        | SessionInvalidationFlags.PendingActions
                        | SessionInvalidationFlags.PendingInput
                        | SessionInvalidationFlags.PendingCoordinateActions
                        | SessionInvalidationFlags.RuntimeHeldInput
                        | SessionInvalidationFlags.AttemptScopedAuthorities,
                        flashTargets,
                        false,
                        false),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange RegisterSurface(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectation,
            SessionSurfaceHostRegistration registration)
        {
            bool shouldDispatch;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session = RequireSession(expectation);
                ValidateSurfaceRegistration(session, registration, null);
                if (session.Surfaces.ContainsKey(registration.TargetId))
                    throw new InvalidOperationException(
                        "target_already_registered");
                if (session.Surfaces.Values.Any(
                        surface => surface.WindowHandle
                            == registration.WindowHandle))
                {
                    throw new InvalidOperationException(
                        "hwnd_already_registered");
                }
                ValidateSurfaceWithHost(session, registration);

                MutableSurface surface =
                    session.AddSurface(registration);

                SessionScopeInvalidation invalidation;
                if (surface.SafetyKind
                    == AgentTargetSafetyKind.HumanOnlySecuritySurface)
                {
                    session.HumanReauthorizationRequired = true;
                    AdvanceModalEpoch(session);
                    invalidation = SecurityInvalidation(
                        session,
                        "security_surface_appeared");
                }
                else if (surface.Kind == SurfaceKind.BusinessModal)
                {
                    AdvanceModalEpoch(session);
                    invalidation = ModalInvalidation(
                        session,
                        "business_modal_appeared",
                        false);
                }
                else
                {
                    invalidation = new SessionScopeInvalidation(
                        SessionInvalidationLevel.Registration,
                        "surface_registered",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.None,
                        new[] { surface.TargetId },
                        false,
                        false);
                }

                change = CommitLocked(
                    invalidation,
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange UnregisterSurface(
            SessionRegistryHostOwner hostOwner,
            SessionSurfaceMutationExpectation expectation)
        {
            bool shouldDispatch;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session;
                MutableSurface surface = RequireSurface(
                    expectation,
                    out session);
                bool wasHumanOnly = surface.SafetyKind
                    == AgentTargetSafetyKind.HumanOnlySecuritySurface;
                bool wasBusinessModal = !wasHumanOnly
                    && surface.Kind == SurfaceKind.BusinessModal;
                session.RemoveSurface(surface.TargetId);
                if (string.Equals(
                        session.ActiveTargetId,
                        surface.TargetId,
                        StringComparison.Ordinal))
                {
                    session.ActiveTargetId = null;
                    AdvanceFocusEpoch(session);
                }
                if (string.Equals(
                        session.ActivePanelTargetId,
                        surface.TargetId,
                        StringComparison.Ordinal))
                {
                    session.ActivePanelName = null;
                    session.ActivePanelInstanceId = null;
                    session.ActivePanelTargetId = null;
                }

                SessionScopeInvalidation invalidation;
                if (wasHumanOnly)
                {
                    session.HumanReauthorizationRequired = true;
                    AdvanceModalEpoch(session);
                    invalidation = SecurityInvalidation(
                        session,
                        "security_surface_disappeared");
                }
                else if (wasBusinessModal)
                {
                    AdvanceModalEpoch(session);
                    invalidation = ModalInvalidation(
                        session,
                        "business_modal_disappeared",
                        false);
                }
                else
                {
                    invalidation = new SessionScopeInvalidation(
                        SessionInvalidationLevel.Surface,
                        "surface_unregistered",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.Observations
                        | SessionInvalidationFlags.SemanticNodes
                        | SessionInvalidationFlags.PendingActions
                        | SessionInvalidationFlags.PendingCoordinateActions
                        | SessionInvalidationFlags.PendingInput,
                        new[] { surface.TargetId },
                        false,
                        false);
                }
                change = CommitLocked(
                    invalidation,
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange RebuildSurface(
            SessionRegistryHostOwner hostOwner,
            SessionSurfaceMutationExpectation expectation,
            SessionSurfaceHostRegistration replacement)
        {
            bool shouldDispatch;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session;
                MutableSurface current = RequireSurface(
                    expectation,
                    out session);
                if (!string.Equals(
                        current.TargetId,
                        replacement?.TargetId,
                        StringComparison.Ordinal)
                    || current.Kind != replacement.Kind
                    || current.SafetyKind != replacement.SafetyKind)
                {
                    throw new InvalidOperationException(
                        "surface_identity_change_requires_reregistration");
                }
                ValidateSurfaceRegistration(
                    session,
                    replacement,
                    current.TargetId);
                if (session.Surfaces.Values.Any(
                        surface =>
                            !ReferenceEquals(surface, current)
                            && surface.WindowHandle
                                == replacement.WindowHandle))
                {
                    throw new InvalidOperationException(
                        "hwnd_already_registered");
                }
                ValidateSurfaceWithHost(session, replacement);

                current.ReplaceRegistration(replacement);
                current.SurfaceEpoch = checked(
                    current.SurfaceEpoch + 1);
                current.CoordinateSpaceVersion = checked(
                    current.CoordinateSpaceVersion + 1);
                if (current.SemanticGeneration.HasValue)
                {
                    current.SemanticGeneration = checked(
                        current.SemanticGeneration.Value + 1);
                }

                SessionScopeInvalidation invalidation;
                if (current.SafetyKind
                    == AgentTargetSafetyKind.HumanOnlySecuritySurface)
                {
                    session.HumanReauthorizationRequired = true;
                    AdvanceModalEpoch(session);
                    invalidation = SecurityInvalidation(
                        session,
                        "security_surface_rebuilt");
                }
                else
                {
                    invalidation = new SessionScopeInvalidation(
                        SessionInvalidationLevel.Surface,
                        "surface_rebuilt",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.Observations
                        | SessionInvalidationFlags.SemanticNodes
                        | SessionInvalidationFlags.PendingActions
                        | SessionInvalidationFlags.PendingCoordinateActions,
                        new[] { current.TargetId },
                        false,
                        false);
                }
                change = CommitLocked(
                    invalidation,
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange UpdateSurfaceLayout(
            SessionRegistryHostOwner hostOwner,
            SessionSurfaceMutationExpectation expectation,
            SessionSurfaceLayoutUpdate update)
        {
            bool shouldDispatch = false;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session;
                MutableSurface surface = RequireSurface(
                    expectation,
                    out session);
                ValidateLayout(update);
                if (surface.LayoutEquals(update))
                {
                    return NoChangeLocked(
                        session,
                        "surface_layout_unchanged");
                }

                bool losesFocus = string.Equals(
                        session.ActiveTargetId,
                        surface.TargetId,
                        StringComparison.Ordinal)
                    && (!update.Visible || update.Minimized);
                surface.ApplyLayout(update);
                surface.SurfaceEpoch = checked(
                    surface.SurfaceEpoch + 1);
                surface.CoordinateSpaceVersion = checked(
                    surface.CoordinateSpaceVersion + 1);
                if (losesFocus)
                {
                    session.ActiveTargetId = null;
                    AdvanceFocusEpoch(session);
                }

                SessionScopeInvalidation invalidation;
                if (surface.SafetyKind
                    == AgentTargetSafetyKind.HumanOnlySecuritySurface)
                {
                    session.HumanReauthorizationRequired = true;
                    AdvanceModalEpoch(session);
                    invalidation = SecurityInvalidation(
                        session,
                        "security_surface_layout_changed");
                }
                else
                {
                    SessionInvalidationFlags flags =
                        SessionInvalidationFlags.Observations
                        | SessionInvalidationFlags.SemanticNodes
                        | SessionInvalidationFlags.PendingActions
                        | SessionInvalidationFlags
                            .PendingCoordinateActions;
                    if (losesFocus)
                        flags |= SessionInvalidationFlags.PendingInput;
                    invalidation = new SessionScopeInvalidation(
                        SessionInvalidationLevel.Surface,
                        "surface_layout_changed",
                        session.SessionId,
                        session.LifecycleGeneration,
                        flags,
                        losesFocus
                            ? session.RuntimeTargetIds()
                            : new[] { surface.TargetId },
                        losesFocus,
                        false);
                }
                change = CommitLocked(
                    invalidation,
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange SetFocus(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectation,
            string activeTargetId)
        {
            bool shouldDispatch = false;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session = RequireSession(expectation);
                if (activeTargetId != null)
                {
                    if (!session.Surfaces.TryGetValue(
                            activeTargetId,
                            out MutableSurface target))
                    {
                        throw new InvalidOperationException(
                            "target_not_authoritative");
                    }
                    if (target.SafetyKind
                        == AgentTargetSafetyKind.HumanOnlySecuritySurface)
                    {
                        throw new InvalidOperationException(
                            "human_only_security_surface");
                    }
                    if (!target.Visible || target.Minimized)
                        throw new InvalidOperationException(
                            target.Minimized
                                ? "target_minimized"
                                : "target_not_visible");
                    if (!session.DesktopAvailable)
                        throw new InvalidOperationException(
                            "desktop_unavailable");
                }
                if (string.Equals(
                        session.ActiveTargetId,
                        activeTargetId,
                        StringComparison.Ordinal))
                {
                    return NoChangeLocked(
                        session,
                        "focus_unchanged");
                }

                session.ActiveTargetId = activeTargetId;
                AdvanceFocusEpoch(session);
                change = CommitLocked(
                    new SessionScopeInvalidation(
                        SessionInvalidationLevel.Focus,
                        activeTargetId == null
                            ? "focus_left_session"
                            : "focus_entered_session",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.Observations
                        | SessionInvalidationFlags.PendingInput,
                        session.RuntimeTargetIds(),
                        true,
                        false),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange SetDesktopAvailable(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectation,
            bool available)
        {
            bool shouldDispatch = false;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session = RequireSession(expectation);
                if (session.DesktopAvailable == available)
                {
                    return NoChangeLocked(
                        session,
                        "desktop_state_unchanged");
                }

                session.DesktopAvailable = available;
                session.ActiveTargetId = null;
                AdvanceFocusEpoch(session);
                if (!available)
                    session.HumanReauthorizationRequired = true;
                change = CommitLocked(
                    !available
                        ? SecurityInvalidation(
                            session,
                            "desktop_unavailable")
                        : new SessionScopeInvalidation(
                            SessionInvalidationLevel.Focus,
                            "desktop_available_requires_reauthorization",
                            session.SessionId,
                            session.LifecycleGeneration,
                            SessionInvalidationFlags.Observations
                            | SessionInvalidationFlags.PendingInput,
                            session.RuntimeTargetIds(),
                            true,
                            session.HumanReauthorizationRequired),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange SetExternalBlockingModal(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectation,
            BlockingModalKind blockingKind)
        {
            bool shouldDispatch = false;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session = RequireSession(expectation);
                if (blockingKind != BlockingModalKind.None
                    && blockingKind
                        != BlockingModalKind.HumanOnlySecurity
                    && blockingKind != BlockingModalKind.Foreign
                    && blockingKind != BlockingModalKind.Unknown)
                {
                    throw new InvalidOperationException(
                        "external_modal_kind_invalid");
                }
                if (session.ExternalBlockingModalKind == blockingKind)
                {
                    return NoChangeLocked(
                        session,
                        "external_modal_unchanged");
                }

                BlockingModalKind previous =
                    session.ExternalBlockingModalKind;
                session.ExternalBlockingModalKind = blockingKind;
                session.HumanReauthorizationRequired = true;
                AdvanceModalEpoch(session);
                change = CommitLocked(
                    SecurityInvalidation(
                        session,
                        blockingKind == BlockingModalKind.None
                            ? "external_modal_disappeared"
                            : previous == BlockingModalKind.None
                                ? "external_modal_appeared"
                                : "external_modal_changed"),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange AcknowledgeHumanReauthorization(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectation)
        {
            bool shouldDispatch = false;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session = RequireSession(expectation);
                if (session.ExternalBlockingModalKind
                        != BlockingModalKind.None
                    || session.Surfaces.Values.Any(surface =>
                        surface.SafetyKind
                            == AgentTargetSafetyKind
                                .HumanOnlySecuritySurface))
                {
                    throw new InvalidOperationException(
                        "security_surface_still_present");
                }
                if (!session.DesktopAvailable)
                    throw new InvalidOperationException(
                        "desktop_unavailable");
                if (!session.HumanReauthorizationRequired)
                {
                    return NoChangeLocked(
                        session,
                        "human_reauthorization_not_required");
                }

                session.HumanReauthorizationRequired = false;
                change = CommitLocked(
                    new SessionScopeInvalidation(
                        SessionInvalidationLevel.Security,
                        "human_reauthorized",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.None,
                        Array.Empty<string>(),
                        false,
                        false),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange AdvanceWebDocument(
            SessionRegistryHostOwner hostOwner,
            SessionSurfaceMutationExpectation expectation)
        {
            bool shouldDispatch;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session;
                MutableSurface surface = RequireSurface(
                    expectation,
                    out session);
                if (surface.SafetyKind
                    != AgentTargetSafetyKind.RuntimeOwned)
                {
                    throw new InvalidOperationException(
                        "human_only_security_surface");
                }
                if (surface.Kind != SurfaceKind.WebOverlay
                    || !surface.DocumentGeneration.HasValue)
                {
                    throw new InvalidOperationException(
                        "unsupported_for_surface");
                }

                surface.DocumentGeneration = checked(
                    surface.DocumentGeneration.Value + 1);
                if (surface.SemanticGeneration.HasValue)
                {
                    surface.SemanticGeneration = checked(
                        surface.SemanticGeneration.Value + 1);
                }
                change = CommitLocked(
                    new SessionScopeInvalidation(
                        SessionInvalidationLevel.Document,
                        "web_document_advanced",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.Observations
                        | SessionInvalidationFlags.SemanticNodes
                        | SessionInvalidationFlags.PendingActions,
                        new[] { surface.TargetId },
                        false,
                        false),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        internal SessionSurfaceRegistryChange ChangeActivePanel(
            SessionRegistryHostOwner hostOwner,
            SessionMutationExpectation expectation,
            string expectedCurrentPanelInstanceId,
            ActivePanelRegistration nextPanel)
        {
            bool shouldDispatch = false;
            SessionSurfaceRegistryChange change;
            lock (_sync)
            {
                RequireHostOwner(hostOwner);
                MutableSession session = RequireSession(expectation);
                if (!string.Equals(
                        session.ActivePanelInstanceId,
                        expectedCurrentPanelInstanceId,
                        StringComparison.Ordinal))
                {
                    throw new InvalidOperationException(
                        "stale_panel_instance");
                }
                ValidatePanelRegistration(session, nextPanel);
                if (PanelEquals(session, nextPanel))
                {
                    return NoChangeLocked(
                        session,
                        "panel_unchanged");
                }

                string oldTarget = session.ActivePanelTargetId;
                string newTarget = nextPanel?.TargetId;
                session.ActivePanelName = nextPanel?.Name;
                session.ActivePanelInstanceId = nextPanel?.InstanceId;
                session.ActivePanelTargetId = nextPanel?.TargetId;
                change = CommitLocked(
                    new SessionScopeInvalidation(
                        SessionInvalidationLevel.Panel,
                        nextPanel == null
                            ? "panel_closed"
                            : oldTarget == null
                                ? "panel_opened"
                                : "panel_instance_changed",
                        session.SessionId,
                        session.LifecycleGeneration,
                        SessionInvalidationFlags.Observations
                        | SessionInvalidationFlags.PendingActions
                        | SessionInvalidationFlags
                            .PendingDomainOperations
                        | SessionInvalidationFlags.ExactInstanceLeases,
                        new[] { oldTarget, newTarget },
                        false,
                        false),
                    out shouldDispatch);
            }
            if (shouldDispatch) DrainEvents();
            return change;
        }

        private SessionSurfaceRegistryChange CommitLocked(
            SessionScopeInvalidation invalidation,
            out bool shouldDispatch)
        {
            _sequence = checked(_sequence + 1);
            _snapshot = BuildSnapshotLocked();
            _pendingEvents.Enqueue(
                new SessionSurfaceRegistryChangedEventArgs(
                    _snapshot,
                    invalidation));
            shouldDispatch = !_dispatchingEvents;
            if (shouldDispatch)
                _dispatchingEvents = true;
            return new SessionSurfaceRegistryChange(
                _snapshot,
                invalidation,
                true);
        }

        private SessionSurfaceRegistryChange NoChangeLocked(
            MutableSession session,
            string reasonCode)
        {
            return new SessionSurfaceRegistryChange(
                _snapshot,
                new SessionScopeInvalidation(
                    SessionInvalidationLevel.None,
                    reasonCode,
                    session.SessionId,
                    session.LifecycleGeneration,
                    SessionInvalidationFlags.None,
                    Array.Empty<string>(),
                    false,
                    session.HumanReauthorizationRequired),
                false);
        }

        private void DrainEvents()
        {
            List<Exception> failures = null;
            while (true)
            {
                SessionSurfaceRegistryChangedEventArgs next;
                lock (_sync)
                {
                    if (_pendingEvents.Count == 0)
                    {
                        _dispatchingEvents = false;
                        break;
                    }
                    next = _pendingEvents.Dequeue();
                }

                EventHandler<SessionSurfaceRegistryChangedEventArgs> handlers =
                    Changed;
                if (handlers == null) continue;
                foreach (EventHandler<SessionSurfaceRegistryChangedEventArgs>
                    handler in handlers.GetInvocationList())
                {
                    try
                    {
                        handler(this, next);
                    }
                    catch (Exception exception)
                    {
                        failures ??= new List<Exception>();
                        failures.Add(exception);
                    }
                }
            }

            if (failures != null)
            {
                throw new AggregateException(
                    "One or more session invalidation subscribers failed.",
                    failures);
            }
        }

        private SessionSurfaceRegistrySnapshot BuildSnapshotLocked()
        {
            return new SessionSurfaceRegistrySnapshot(
                _sequence,
                _sessions.Values.Select(
                    session => session.CreateSnapshot()));
        }

        private void RequireHostOwner(SessionRegistryHostOwner hostOwner)
        {
            if (!ReferenceEquals(_hostOwner, hostOwner))
                throw new InvalidOperationException(
                    "launcher_host_owner_mismatch");
        }

        private MutableSession RequireSession(
            SessionMutationExpectation expectation)
        {
            if (expectation == null
                || !_sessions.TryGetValue(
                    expectation.SessionId ?? string.Empty,
                    out MutableSession session))
            {
                throw new InvalidOperationException(
                    "session_not_found");
            }
            if (session.LifecycleGeneration
                != expectation.LifecycleGeneration)
            {
                throw new InvalidOperationException(
                    "stale_lifecycle");
            }
            if (!AttemptMatches(
                    session,
                    expectation.AttemptId,
                    expectation.AttemptGeneration))
            {
                throw new InvalidOperationException(
                    "stale_attempt");
            }
            return session;
        }

        private MutableSurface RequireSurface(
            SessionSurfaceMutationExpectation expectation,
            out MutableSession session)
        {
            if (expectation == null)
                throw new InvalidOperationException(
                    "arguments_invalid");
            session = RequireSession(expectation.Session);
            if (!session.Surfaces.TryGetValue(
                    expectation.TargetId ?? string.Empty,
                    out MutableSurface surface))
            {
                throw new InvalidOperationException(
                    "target_not_authoritative");
            }
            if (surface.SurfaceEpoch != expectation.SurfaceEpoch)
                throw new InvalidOperationException(
                    "stale_surface");
            if (expectation.WindowHandle.HasValue
                && expectation.WindowHandle.Value
                    != surface.WindowHandle)
            {
                throw new InvalidOperationException(
                    "stale_surface");
            }
            return surface;
        }

        private static bool AttemptMatches(
            MutableSession session,
            string attemptId,
            ulong? attemptGeneration)
        {
            return string.Equals(
                    session.AttemptId,
                    attemptId,
                    StringComparison.Ordinal)
                && session.AttemptGeneration == attemptGeneration;
        }

        private void ValidateSessionRegistration(
            SessionHostRegistration registration)
        {
            if (registration == null)
                throw new ArgumentNullException(nameof(registration));
            RequireOpaqueId(registration.SessionId, "session_id_invalid");
            if (registration.LifecycleGeneration == 0)
                throw new InvalidOperationException(
                    "lifecycle_generation_invalid");
            if (!Enum.IsDefined(registration.SessionMode))
                throw new InvalidOperationException(
                    "session_mode_invalid");
            if (registration.LauncherProcess == null
                || !_hostOwner.LauncherProcess.IsExact(
                    registration.LauncherProcess))
            {
                throw new InvalidOperationException(
                    "launcher_owner_mismatch");
            }
            if (string.IsNullOrWhiteSpace(registration.Slot))
                throw new InvalidOperationException("slot_required");
            if (!Sha256Pattern.IsMatch(
                    registration.CoreSha256 ?? string.Empty))
            {
                throw new InvalidOperationException(
                    "core_hash_invalid");
            }
            if ((registration.AttemptId == null)
                != !registration.AttemptGeneration.HasValue)
            {
                throw new InvalidOperationException(
                    "attempt_binding_invalid");
            }
            if (registration.AttemptId != null)
            {
                RequireOpaqueId(
                    registration.AttemptId,
                    "attempt_id_invalid");
                if (registration.AttemptGeneration.GetValueOrDefault() == 0)
                {
                    throw new InvalidOperationException(
                        "attempt_generation_invalid");
                }
            }
            ValidateQualification(
                registration.RuntimeQualification,
                registration.LauncherProcess);
            string[] capabilities = NormalizeCapabilities(
                registration.Capabilities);
            if (registration.RuntimeQualification.RuntimeMode
                    == RuntimeMode.UnqualifiedDev
                && capabilities.Contains(
                    AgentCapabilitiesV1.AppearanceHairChange,
                    StringComparer.Ordinal))
            {
                throw new InvalidOperationException(
                    "unqualified_domain_capability_denied");
            }
        }

        private static void ValidateQualification(
            RuntimeQualificationRegistration qualification,
            SessionProcessIdentity launcherProcess)
        {
            if (qualification == null)
                throw new InvalidOperationException(
                    "runtime_qualification_required");
            if (!Enum.IsDefined(qualification.RuntimeMode)
                || string.IsNullOrWhiteSpace(
                    qualification.ActualProcessPath)
                || !System.IO.Path.IsPathFullyQualified(
                    qualification.ActualProcessPath)
                || !string.Equals(
                    System.IO.Path.GetFullPath(
                        qualification.ActualProcessPath),
                    launcherProcess.ExecutablePath,
                    StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException(
                    "runtime_qualification_invalid");
            }
            if (qualification.RuntimeMode == RuntimeMode.UnqualifiedDev)
            {
                if (string.IsNullOrWhiteSpace(
                        qualification.UnqualifiedReason)
                    || qualification.BuildIdentity != null
                    || qualification.PayloadClosure != null)
                {
                    throw new InvalidOperationException(
                        "runtime_qualification_invalid");
                }
                return;
            }

            if (!Sha256Pattern.IsMatch(
                    qualification.BuildIdentity ?? string.Empty)
                || !Sha256Pattern.IsMatch(
                    qualification.PayloadClosure ?? string.Empty)
                || qualification.UnqualifiedReason != null
                || qualification.UnqualifiedDevVisualInputAuthorized)
            {
                throw new InvalidOperationException(
                    "runtime_qualification_invalid");
            }
        }

        private static string[] NormalizeCapabilities(
            IEnumerable<string> capabilities)
        {
            string[] normalized =
                (capabilities ?? Array.Empty<string>())
                    .Where(capability =>
                        !string.IsNullOrWhiteSpace(capability))
                    .Distinct(StringComparer.Ordinal)
                    .OrderBy(
                        capability => capability,
                        StringComparer.Ordinal)
                    .ToArray();
            if (normalized.Any(capability =>
                    !AgentCapabilitiesV1.All.Contains(capability)))
            {
                throw new InvalidOperationException(
                    "capability_not_registered");
            }
            return normalized;
        }

        private static void ValidateAttemptRegistration(
            SessionAttemptRegistration registration)
        {
            if (registration == null) return;
            RequireOpaqueId(
                registration.AttemptId,
                "attempt_id_invalid");
            if (string.IsNullOrWhiteSpace(registration.Slot))
                throw new InvalidOperationException("slot_required");
            if (registration.FlashProcess == null)
                throw new InvalidOperationException(
                    "flash_process_required");
        }

        private void ValidateSurfaceRegistration(
            MutableSession session,
            SessionSurfaceHostRegistration registration,
            string replacingTargetId)
        {
            if (registration == null)
                throw new ArgumentNullException(nameof(registration));
            RequireOpaqueId(
                registration.TargetId,
                "target_id_invalid");
            if (!Enum.IsDefined(registration.Kind)
                || !Enum.IsDefined(registration.SafetyKind)
                || !Enum.IsDefined(registration.OwnerRelation))
            {
                throw new InvalidOperationException(
                    "surface_classification_invalid");
            }
            if (registration.WindowHandle <= 0
                || registration.OwnerProcess == null)
            {
                throw new InvalidOperationException(
                    "surface_owner_required");
            }
            ValidateLayout(
                new SessionSurfaceLayoutUpdate
                {
                    BoundsPhysical = registration.BoundsPhysical,
                    ClientRectPhysical = registration.ClientRectPhysical,
                    ContentRectPhysical = registration.ContentRectPhysical,
                    Dpi = registration.Dpi,
                    ZIndex = registration.ZIndex,
                    Visible = registration.Visible,
                    Minimized = registration.Minimized
                });

            ObservationMode[] observationModes =
                (registration.ObservationModes
                    ?? Array.Empty<ObservationMode>())
                    .Distinct()
                    .ToArray();
            InputMode[] inputModes =
                (registration.InputModes
                    ?? Array.Empty<InputMode>())
                    .Distinct()
                    .ToArray();
            if (observationModes.Any(mode => !Enum.IsDefined(mode))
                || inputModes.Any(mode => !Enum.IsDefined(mode)))
            {
                throw new InvalidOperationException(
                    "surface_mode_invalid");
            }
            if (registration.SafetyKind
                == AgentTargetSafetyKind.HumanOnlySecuritySurface)
            {
                if (registration.OwnerRelation
                        != SessionSurfaceOwnerRelation
                            .HumanOnlySecurityReported
                    || observationModes.Length != 0
                    || inputModes.Length != 0)
                {
                    throw new InvalidOperationException(
                        "security_surface_scope_forbidden");
                }
            }
            else
            {
                if (registration.OwnerRelation
                        == SessionSurfaceOwnerRelation
                            .HumanOnlySecurityReported
                    || observationModes.Length == 0)
                {
                    throw new InvalidOperationException(
                        "runtime_surface_registration_invalid");
                }
                if (session.RuntimeQualification.RuntimeMode
                    == RuntimeMode.UnqualifiedDev)
                {
                    if (!session.RuntimeQualification
                            .UnqualifiedDevVisualInputAuthorized
                        && inputModes.Length != 0)
                    {
                        throw new InvalidOperationException(
                            "unqualified_input_denied");
                    }
                    if (inputModes.Any(inputMode =>
                            inputMode != InputMode.SendInputGuarded))
                    {
                        throw new InvalidOperationException(
                            "unqualified_input_mode_denied");
                    }
                }
            }

            bool owned =
                registration.OwnerRelation
                    == SessionSurfaceOwnerRelation.LauncherOwned
                || registration.OwnerRelation
                    == SessionSurfaceOwnerRelation.FlashOwned;
            if (owned)
            {
                if (string.IsNullOrWhiteSpace(
                        registration.OwnerTargetId)
                    || registration.OwnerWindowHandle <= 0)
                {
                    throw new InvalidOperationException(
                        "surface_owner_target_required");
                }
                if (!session.Surfaces.TryGetValue(
                        registration.OwnerTargetId,
                        out MutableSurface ownerSurface)
                    || string.Equals(
                        ownerSurface.TargetId,
                        replacingTargetId,
                        StringComparison.Ordinal)
                    || ownerSurface.SafetyKind
                        != AgentTargetSafetyKind.RuntimeOwned
                    || ownerSurface.WindowHandle
                        != registration.OwnerWindowHandle)
                {
                    throw new InvalidOperationException(
                        "surface_owner_target_invalid");
                }
            }
            else if (registration.OwnerRelation
                == SessionSurfaceOwnerRelation
                    .HumanOnlySecurityReported)
            {
                if (registration.OwnerTargetId != null
                    || registration.OwnerWindowHandle < 0)
                {
                    throw new InvalidOperationException(
                        "surface_owner_target_unexpected");
                }
            }
            else if (registration.OwnerTargetId != null
                || registration.OwnerWindowHandle != 0)
            {
                throw new InvalidOperationException(
                    "surface_owner_target_unexpected");
            }

            if ((registration.OwnerRelation
                        == SessionSurfaceOwnerRelation.FlashTopLevel
                    || registration.OwnerRelation
                        == SessionSurfaceOwnerRelation.FlashOwned)
                && session.FlashProcess == null)
            {
                throw new InvalidOperationException(
                    "flash_process_not_registered");
            }
            if (registration.Kind == SurfaceKind.Flash
                && registration.OwnerRelation
                    != SessionSurfaceOwnerRelation.FlashTopLevel
                && registration.OwnerRelation
                    != SessionSurfaceOwnerRelation.FlashOwned)
            {
                throw new InvalidOperationException(
                    "flash_surface_owner_invalid");
            }
            if (registration.Kind == SurfaceKind.BusinessModal
                && registration.SafetyKind
                    == AgentTargetSafetyKind.RuntimeOwned
                && !owned)
            {
                throw new InvalidOperationException(
                    "business_modal_owner_required");
            }
        }

        private void ValidateSurfaceWithHost(
            MutableSession session,
            SessionSurfaceHostRegistration registration)
        {
            if (TryValidateSurfaceWithHost(
                    session,
                    registration,
                    out string reasonCode))
            {
                return;
            }
            throw new InvalidOperationException(
                reasonCode ?? "surface_owner_unverifiable");
        }

        private bool TryValidateSurfaceWithHost(
            MutableSession session,
            SessionSurfaceHostRegistration registration,
            out string reasonCode)
        {
            var context = new SessionSurfaceValidationContext(
                session.LauncherProcess,
                session.FlashProcess,
                targetId =>
                {
                    if (!session.Surfaces.TryGetValue(
                            targetId ?? string.Empty,
                            out MutableSurface surface))
                    {
                        return null;
                    }
                    return surface.CreateSnapshot(
                        session.FocusEpoch,
                        session.ModalEpoch,
                        session.ActiveTargetId);
                });
            if (!_hostValidator.ValidateSurface(
                    _hostOwner,
                    context,
                    registration,
                    out reasonCode))
            {
                reasonCode ??= "surface_owner_unverifiable";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static void ValidateLayout(
            SessionSurfaceLayoutUpdate update)
        {
            if (update == null
                || update.BoundsPhysical == null
                || update.ClientRectPhysical == null
                || update.ContentRectPhysical == null)
            {
                throw new InvalidOperationException(
                    "surface_geometry_required");
            }
            if (update.Dpi < 72 || update.Dpi > 960)
                throw new InvalidOperationException(
                    "surface_dpi_invalid");
            if (update.Minimized && update.Visible)
            {
                throw new InvalidOperationException(
                    "surface_visibility_conflict");
            }
        }

        private static void ValidatePanelRegistration(
            MutableSession session,
            ActivePanelRegistration registration)
        {
            if (registration == null) return;
            if (string.IsNullOrWhiteSpace(registration.Name)
                || registration.Name.Length > 128)
            {
                throw new InvalidOperationException(
                    "panel_name_invalid");
            }
            RequireOpaqueId(
                registration.InstanceId,
                "panel_instance_id_invalid");
            if (!session.Surfaces.TryGetValue(
                    registration.TargetId ?? string.Empty,
                    out MutableSurface target)
                || target.SafetyKind
                    != AgentTargetSafetyKind.RuntimeOwned)
            {
                throw new InvalidOperationException(
                    "panel_target_not_authoritative");
            }
        }

        private static bool PanelEquals(
            MutableSession session,
            ActivePanelRegistration panel)
        {
            return string.Equals(
                    session.ActivePanelName,
                    panel?.Name,
                    StringComparison.Ordinal)
                && string.Equals(
                    session.ActivePanelInstanceId,
                    panel?.InstanceId,
                    StringComparison.Ordinal)
                && string.Equals(
                    session.ActivePanelTargetId,
                    panel?.TargetId,
                    StringComparison.Ordinal);
        }

        private static void RequireOpaqueId(
            string value,
            string reasonCode)
        {
            if (!OpaqueIdPattern.IsMatch(value ?? string.Empty))
                throw new InvalidOperationException(reasonCode);
        }

        private static bool IsFlashScoped(MutableSurface surface)
        {
            return surface.Kind == SurfaceKind.Flash
                || surface.OwnerRelation
                    == SessionSurfaceOwnerRelation.FlashTopLevel
                || surface.OwnerRelation
                    == SessionSurfaceOwnerRelation.FlashOwned;
        }

        private static void AdvanceFocusEpoch(MutableSession session)
        {
            session.FocusEpoch = checked(session.FocusEpoch + 1);
        }

        private static void AdvanceModalEpoch(MutableSession session)
        {
            session.ModalEpoch = checked(session.ModalEpoch + 1);
        }

        private static SessionScopeInvalidation ModalInvalidation(
            MutableSession session,
            string reasonCode,
            bool security)
        {
            return new SessionScopeInvalidation(
                security
                    ? SessionInvalidationLevel.Security
                    : SessionInvalidationLevel.Modal,
                reasonCode,
                session.SessionId,
                session.LifecycleGeneration,
                security
                    ? SecurityInvalidationFlags
                    : SessionInvalidationFlags.Observations
                        | SessionInvalidationFlags.PendingInput,
                session.RuntimeTargetIds(),
                true,
                security && session.HumanReauthorizationRequired);
        }

        private static SessionScopeInvalidation SecurityInvalidation(
            MutableSession session,
            string reasonCode)
        {
            return ModalInvalidation(
                session,
                reasonCode,
                true);
        }

        private sealed class MutableSession
        {
            private readonly Dictionary<string, ulong>
                _retiredSurfaceEpochs =
                    new Dictionary<string, ulong>(
                        StringComparer.Ordinal);

            public MutableSession(SessionHostRegistration registration)
            {
                SessionId = registration.SessionId;
                LifecycleGeneration = registration.LifecycleGeneration;
                SessionMode = registration.SessionMode;
                Slot = registration.Slot;
                SaveRevision = registration.SaveRevision;
                AttemptId = registration.AttemptId;
                AttemptGeneration = registration.AttemptGeneration;
                AttemptSequence =
                    registration.AttemptGeneration.GetValueOrDefault();
                LauncherProcess = registration.LauncherProcess;
                FlashProcess = registration.FlashProcess;
                CoreSha256 = registration.CoreSha256;
                RuntimeQualification = registration.RuntimeQualification;
                Capabilities = Array.AsReadOnly(
                    NormalizeCapabilities(registration.Capabilities));
            }

            public string SessionId { get; }
            public ulong LifecycleGeneration { get; }
            public SessionMode SessionMode { get; }
            public string Slot { get; set; }
            public long? SaveRevision { get; set; }
            public string AttemptId { get; set; }
            public ulong? AttemptGeneration { get; set; }
            public ulong AttemptSequence { get; set; }
            public SessionProcessIdentity LauncherProcess { get; }
            public SessionProcessIdentity FlashProcess { get; set; }
            public string CoreSha256 { get; }
            public RuntimeQualificationRegistration RuntimeQualification
            {
                get;
            }
            public ReadOnlyCollection<string> Capabilities { get; }
            public Dictionary<string, MutableSurface> Surfaces { get; } =
                new Dictionary<string, MutableSurface>(
                    StringComparer.Ordinal);
            public ulong FocusEpoch { get; set; } = 1;
            public ulong ModalEpoch { get; set; } = 1;
            public string ActiveTargetId { get; set; }
            public string ActivePanelName { get; set; }
            public string ActivePanelInstanceId { get; set; }
            public string ActivePanelTargetId { get; set; }
            public BlockingModalKind ExternalBlockingModalKind { get; set; }
            public bool HumanReauthorizationRequired { get; set; }
            public bool DesktopAvailable { get; set; } = true;

            public string PanelInstanceIdForTarget(
                string targetId)
            {
                return targetId != null
                    && string.Equals(
                        ActivePanelTargetId,
                        targetId,
                        StringComparison.Ordinal)
                    ? ActivePanelInstanceId
                    : null;
            }

            public IEnumerable<string> RuntimeTargetIds()
            {
                return Surfaces.Values
                    .Where(surface => surface.SafetyKind
                        == AgentTargetSafetyKind.RuntimeOwned)
                    .Select(surface => surface.TargetId)
                    .OrderBy(target => target, StringComparer.Ordinal);
            }

            public MutableSurface AddSurface(
                SessionSurfaceHostRegistration registration)
            {
                ulong initialEpoch = 1;
                if (_retiredSurfaceEpochs.TryGetValue(
                        registration.TargetId,
                        out ulong retiredEpoch))
                {
                    initialEpoch = checked(retiredEpoch + 1);
                }
                var surface = new MutableSurface(
                    registration,
                    initialEpoch);
                Surfaces.Add(surface.TargetId, surface);
                return surface;
            }

            public void RemoveSurface(string targetId)
            {
                if (!Surfaces.TryGetValue(
                        targetId,
                        out MutableSurface surface))
                {
                    return;
                }
                if (!_retiredSurfaceEpochs.TryGetValue(
                        targetId,
                        out ulong retiredEpoch)
                    || surface.SurfaceEpoch > retiredEpoch)
                {
                    _retiredSurfaceEpochs[targetId] =
                        surface.SurfaceEpoch;
                }
                Surfaces.Remove(targetId);
            }

            public SessionSnapshot CreateSnapshot()
            {
                SessionHostRegistration registration =
                    new SessionHostRegistration
                    {
                        SessionId = SessionId,
                        LifecycleGeneration = LifecycleGeneration,
                        SessionMode = SessionMode,
                        Slot = Slot,
                        SaveRevision = SaveRevision,
                        AttemptId = AttemptId,
                        AttemptGeneration = AttemptGeneration,
                        LauncherProcess = LauncherProcess,
                        FlashProcess = FlashProcess,
                        CoreSha256 = CoreSha256,
                        RuntimeQualification = RuntimeQualification,
                        Capabilities = Capabilities
                    };
                return new SessionSnapshot(
                    registration,
                    Surfaces.Values
                        .Where(surface => surface.SafetyKind
                            == AgentTargetSafetyKind.RuntimeOwned)
                        .Select(surface => surface.CreateSnapshot(
                            FocusEpoch,
                            ModalEpoch,
                            ActiveTargetId)),
                    ActivePanelName,
                    ActivePanelInstanceId,
                    ActivePanelTargetId,
                    FocusEpoch,
                    ModalEpoch,
                    GetBlockingModalKind(),
                    HumanReauthorizationRequired,
                    ActiveTargetId,
                    DesktopAvailable);
            }

            private BlockingModalKind GetBlockingModalKind()
            {
                if (ExternalBlockingModalKind
                    != BlockingModalKind.None)
                {
                    return ExternalBlockingModalKind;
                }
                if (Surfaces.Values.Any(surface =>
                        surface.SafetyKind
                            == AgentTargetSafetyKind
                                .HumanOnlySecuritySurface))
                {
                    return BlockingModalKind.HumanOnlySecurity;
                }
                if (Surfaces.Values.Any(surface =>
                        surface.SafetyKind
                            == AgentTargetSafetyKind.RuntimeOwned
                        && surface.Kind
                            == SurfaceKind.BusinessModal))
                {
                    return BlockingModalKind.BusinessOwned;
                }
                return BlockingModalKind.None;
            }
        }

        private sealed class MutableSurface
        {
            public MutableSurface(
                SessionSurfaceHostRegistration registration,
                ulong initialEpoch)
            {
                TargetId = registration.TargetId;
                Kind = registration.Kind;
                SafetyKind = registration.SafetyKind;
                SurfaceEpoch = initialEpoch;
                CoordinateSpaceVersion = 1;
                bool semantic = (registration.ObservationModes
                        ?? Array.Empty<ObservationMode>())
                    .Any(mode =>
                        mode == ObservationMode.Uia
                        || mode == ObservationMode.WebSemantic);
                SemanticGeneration = semantic ? 1UL : null;
                DocumentGeneration =
                    registration.Kind == SurfaceKind.WebOverlay
                        ? 1UL
                        : null;
                ReplaceRegistration(registration);
            }

            public string TargetId { get; }
            public SurfaceKind Kind { get; }
            public AgentTargetSafetyKind SafetyKind { get; }
            public SessionSurfaceOwnerRelation OwnerRelation { get; set; }
            public SessionProcessIdentity OwnerProcess { get; set; }
            public long WindowHandle { get; set; }
            public string OwnerTargetId { get; set; }
            public long OwnerWindowHandle { get; set; }
            public SessionPhysicalRect BoundsPhysical { get; set; }
            public SessionPhysicalRect ClientRectPhysical { get; set; }
            public SessionPhysicalRect ContentRectPhysical { get; set; }
            public int Dpi { get; set; }
            public int ZIndex { get; set; }
            public bool Visible { get; set; }
            public bool Minimized { get; set; }
            public ReadOnlyCollection<ObservationMode> ObservationModes
            {
                get;
                set;
            }
            public ReadOnlyCollection<InputMode> InputModes { get; set; }
            public ulong SurfaceEpoch { get; set; }
            public ulong CoordinateSpaceVersion { get; set; }
            public ulong? SemanticGeneration { get; set; }
            public ulong? DocumentGeneration { get; set; }

            public void ReplaceRegistration(
                SessionSurfaceHostRegistration registration)
            {
                OwnerRelation = registration.OwnerRelation;
                OwnerProcess = registration.OwnerProcess;
                WindowHandle = registration.WindowHandle;
                OwnerTargetId = registration.OwnerTargetId;
                OwnerWindowHandle = registration.OwnerWindowHandle;
                BoundsPhysical = registration.BoundsPhysical;
                ClientRectPhysical = registration.ClientRectPhysical;
                ContentRectPhysical = registration.ContentRectPhysical;
                Dpi = registration.Dpi;
                ZIndex = registration.ZIndex;
                Visible = registration.Visible;
                Minimized = registration.Minimized;
                ObservationModes = Freeze(
                    registration.ObservationModes);
                InputModes = Freeze(registration.InputModes);
            }

            public bool LayoutEquals(SessionSurfaceLayoutUpdate update)
            {
                return Equals(BoundsPhysical, update.BoundsPhysical)
                    && Equals(
                        ClientRectPhysical,
                        update.ClientRectPhysical)
                    && Equals(
                        ContentRectPhysical,
                        update.ContentRectPhysical)
                    && Dpi == update.Dpi
                    && ZIndex == update.ZIndex
                    && Visible == update.Visible
                    && Minimized == update.Minimized;
            }

            public void ApplyLayout(SessionSurfaceLayoutUpdate update)
            {
                BoundsPhysical = update.BoundsPhysical;
                ClientRectPhysical = update.ClientRectPhysical;
                ContentRectPhysical = update.ContentRectPhysical;
                Dpi = update.Dpi;
                ZIndex = update.ZIndex;
                Visible = update.Visible;
                Minimized = update.Minimized;
            }

            public SessionSurfaceSnapshot CreateSnapshot(
                ulong focusEpoch,
                ulong modalEpoch,
                string activeTargetId)
            {
                return new SessionSurfaceSnapshot(
                    TargetId,
                    Kind,
                    SafetyKind,
                    OwnerRelation,
                    OwnerProcess,
                    WindowHandle,
                    OwnerTargetId,
                    OwnerWindowHandle,
                    SurfaceEpoch,
                    CoordinateSpaceVersion,
                    focusEpoch,
                    modalEpoch,
                    SemanticGeneration,
                    DocumentGeneration,
                    BoundsPhysical,
                    ClientRectPhysical,
                    ContentRectPhysical,
                    Dpi,
                    ZIndex,
                    Visible,
                    Minimized,
                    string.Equals(
                        TargetId,
                        activeTargetId,
                        StringComparison.Ordinal),
                    ObservationModes,
                    InputModes);
            }

            public SessionSurfaceHostRegistration ToRegistration()
            {
                return new SessionSurfaceHostRegistration
                {
                    TargetId = TargetId,
                    Kind = Kind,
                    SafetyKind = SafetyKind,
                    OwnerRelation = OwnerRelation,
                    OwnerProcess = OwnerProcess,
                    WindowHandle = WindowHandle,
                    OwnerTargetId = OwnerTargetId,
                    OwnerWindowHandle = OwnerWindowHandle,
                    BoundsPhysical = BoundsPhysical,
                    ClientRectPhysical = ClientRectPhysical,
                    ContentRectPhysical = ContentRectPhysical,
                    Dpi = Dpi,
                    ZIndex = ZIndex,
                    Visible = Visible,
                    Minimized = Minimized,
                    ObservationModes = ObservationModes,
                    InputModes = InputModes
                };
            }

            private static ReadOnlyCollection<T> Freeze<T>(
                IEnumerable<T> values)
            {
                return Array.AsReadOnly(
                    (values ?? Array.Empty<T>())
                        .Distinct()
                        .OrderBy(value => value)
                        .ToArray());
            }
        }
    }
}
