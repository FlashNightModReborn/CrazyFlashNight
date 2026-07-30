using System;
using System.Collections.Generic;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Sessions
{
    /// <summary>
    /// Launcher-owner mutation facade for one logical session. It translates
    /// exact host observations into the registry's CAS mutations and never
    /// accepts wire/client claims.
    /// </summary>
    internal sealed class SessionSurfaceHostController
    {
        private readonly object _sync = new object();
        private readonly SessionSurfaceRegistry _registry;
        private readonly SessionRegistryHostOwner _owner;
        private RuntimeQualificationRegistration _qualification;
        private readonly SessionProcessIdentity _launcherProcess;
        private readonly string _coreSha256;
        private readonly string[] _capabilities;
        private SessionMode _sessionMode;
        private string _sessionId;
        private ulong _lifecycleGeneration = 1;

        public SessionSurfaceHostController(
            SessionSurfaceRegistry registry,
            SessionRegistryHostOwner owner,
            RuntimeQualificationRegistration qualification,
            string coreSha256,
            IEnumerable<string> capabilities,
            string initialSlot = "launcher_idle",
            SessionMode sessionMode =
                SessionMode.DeveloperInteractive)
        {
            _registry = registry
                ?? throw new ArgumentNullException(nameof(registry));
            _owner = owner
                ?? throw new ArgumentNullException(nameof(owner));
            _qualification = qualification
                ?? throw new ArgumentNullException(
                    nameof(qualification));
            _sessionMode = sessionMode;
            _launcherProcess = owner.LauncherProcess;
            _coreSha256 = coreSha256;
            _capabilities = (capabilities
                    ?? Array.Empty<string>())
                .Distinct(StringComparer.Ordinal)
                .OrderBy(value => value, StringComparer.Ordinal)
                .ToArray();
            _sessionId = OpaqueIdGenerator.Create("session");
            _registry.RegisterSession(
                _owner,
                BuildSession(
                    _sessionId,
                    _lifecycleGeneration,
                    initialSlot,
                    null,
                    null,
                    null,
                    null));
        }

        public string SessionId
        {
            get
            {
                lock (_sync) { return _sessionId; }
            }
        }

        public SessionSurfaceRegistry Registry
        {
            get { return _registry; }
        }

        public SessionSnapshot Snapshot
        {
            get
            {
                lock (_sync)
                {
                    return RequireSession();
                }
            }
        }

        public void SetAttempt(
            string attemptId,
            SessionProcessIdentity flashProcess,
            string slot,
            long? saveRevision)
        {
            if (flashProcess == null)
                throw new ArgumentNullException(
                    nameof(flashProcess));
            PrincipalCredentialAuthority.RequireValue(
                attemptId,
                nameof(attemptId));
            PrincipalCredentialAuthority.RequireValue(
                slot,
                nameof(slot));
            lock (_sync)
            {
                SessionSnapshot current = RequireSession();
                if (string.Equals(
                        current.AttemptId,
                        attemptId,
                        StringComparison.Ordinal)
                    && current.FlashProcess != null
                    && current.FlashProcess.IsExact(
                        flashProcess))
                {
                    return;
                }
                _registry.AdvanceAttempt(
                    _owner,
                    ExpectSession(current),
                    new SessionAttemptRegistration
                    {
                        AttemptId = attemptId,
                        FlashProcess = flashProcess,
                        Slot = slot,
                        SaveRevision = saveRevision
                    });
            }
        }

        public void ClearAttempt()
        {
            lock (_sync)
            {
                SessionSnapshot current = RequireSession();
                if (current.AttemptId == null)
                    return;
                _registry.AdvanceAttempt(
                    _owner,
                    ExpectSession(current),
                    null);
            }
        }

        public void SynchronizeSurface(
            SessionSurfaceHostRegistration observed)
        {
            if (observed == null)
                throw new ArgumentNullException(nameof(observed));
            lock (_sync)
            {
                SessionSnapshot session = RequireSession();
                if (!_registry.TryGetRegisteredSurface(
                        session.SessionId,
                        observed.TargetId,
                        out SessionSurfaceSnapshot current))
                {
                    _registry.RegisterSurface(
                        _owner,
                        ExpectSession(session),
                        observed);
                    return;
                }

                SessionSurfaceMutationExpectation currentExpectation =
                    ExpectSurface(session, current);
                if (!_registry.TryValidateRegisteredSurface(
                        _owner,
                        currentExpectation,
                        out string revalidationReason))
                {
                    // A live HWND/process identity failure poisons this exact
                    // surface generation. Remove it before reporting failure
                    // so no stale lease or hook callback can keep using it.
                    _registry.UnregisterSurface(
                        _owner,
                        currentExpectation);
                    throw new InvalidOperationException(
                        revalidationReason
                        ?? "surface_owner_unverifiable");
                }

                if (!RegistrationIdentityEquals(
                        current,
                        observed))
                {
                    if (current.Kind != observed.Kind
                        || current.SafetyKind
                            != observed.SafetyKind)
                    {
                        _registry.UnregisterSurface(
                            _owner,
                            ExpectSurface(session, current));
                        session = RequireSession();
                        _registry.RegisterSurface(
                            _owner,
                            ExpectSession(session),
                            observed);
                        return;
                    }
                    _registry.RebuildSurface(
                        _owner,
                        ExpectSurface(session, current),
                        observed);
                    return;
                }

                if (!LayoutEquals(current, observed))
                {
                    _registry.UpdateSurfaceLayout(
                        _owner,
                        ExpectSurface(session, current),
                        new SessionSurfaceLayoutUpdate
                        {
                            BoundsPhysical =
                                observed.BoundsPhysical,
                            ClientRectPhysical =
                                observed.ClientRectPhysical,
                            ContentRectPhysical =
                                observed.ContentRectPhysical,
                            Dpi = observed.Dpi,
                            ZIndex = observed.ZIndex,
                            Visible = observed.Visible,
                            Minimized = observed.Minimized
                        });
                }
            }
        }

        public void RemoveSurface(string targetId)
        {
            lock (_sync)
            {
                SessionSnapshot session = RequireSession();
                if (!_registry.TryGetRegisteredSurface(
                        session.SessionId,
                        targetId,
                        out SessionSurfaceSnapshot current))
                {
                    return;
                }
                _registry.UnregisterSurface(
                    _owner,
                    ExpectSurface(session, current));
            }
        }

        public void AdvanceWebDocument(string targetId)
        {
            PrincipalCredentialAuthority.RequireValue(
                targetId,
                nameof(targetId));
            lock (_sync)
            {
                SessionSnapshot session = RequireSession();
                if (!_registry.TryGetRegisteredSurface(
                        session.SessionId,
                        targetId,
                        out SessionSurfaceSnapshot current))
                {
                    throw new InvalidOperationException(
                        "surface_not_found");
                }
                _registry.AdvanceWebDocument(
                    _owner,
                    ExpectSurface(session, current));
            }
        }

        public void SetActivePanel(
            string name,
            string instanceId,
            string targetId)
        {
            bool clear = name == null
                && instanceId == null
                && targetId == null;
            if (!clear)
            {
                PrincipalCredentialAuthority.RequireValue(
                    name,
                    nameof(name));
                PrincipalCredentialAuthority.RequireValue(
                    instanceId,
                    nameof(instanceId));
                PrincipalCredentialAuthority.RequireValue(
                    targetId,
                    nameof(targetId));
            }

            lock (_sync)
            {
                SessionSnapshot current = RequireSession();
                if (!clear
                    && _registry.TryGetRegisteredSurface(
                        current.SessionId,
                        targetId,
                        out SessionSurfaceSnapshot target)
                    && target.Kind
                        != SurfaceKind.WebOverlay)
                {
                    throw new InvalidOperationException(
                        "unsupported_for_surface");
                }
                _registry.ChangeActivePanel(
                    _owner,
                    ExpectSession(current),
                    current.ActivePanelInstanceId,
                    clear
                        ? null
                        : new ActivePanelRegistration
                        {
                            Name = name,
                            InstanceId = instanceId,
                            TargetId = targetId
                        });
            }
        }

        public void SetFocus(string activeTargetId)
        {
            lock (_sync)
            {
                SessionSnapshot session = RequireSession();
                if (string.Equals(
                        session.ActiveTargetId,
                        activeTargetId,
                        StringComparison.Ordinal))
                {
                    return;
                }
                _registry.SetFocus(
                    _owner,
                    ExpectSession(session),
                    activeTargetId);
            }
        }

        public void SetDesktopAvailable(bool available)
        {
            lock (_sync)
            {
                SessionSnapshot session = RequireSession();
                if (session.DesktopAvailable == available)
                    return;
                _registry.SetDesktopAvailable(
                    _owner,
                    ExpectSession(session),
                    available);
            }
        }

        public void SetExternalBlockingModal(
            BlockingModalKind kind)
        {
            lock (_sync)
            {
                SessionSnapshot session = RequireSession();
                if (session.BlockingModalKind == kind)
                    return;
                _registry.SetExternalBlockingModal(
                    _owner,
                    ExpectSession(session),
                    kind);
            }
        }

        public void ReplaceLifecycle(
            RuntimeQualificationRegistration qualification,
            string slot,
            SessionMode? sessionMode = null)
        {
            if (qualification == null)
                throw new ArgumentNullException(
                    nameof(qualification));
            lock (_sync)
            {
                SessionSnapshot old = RequireSession();
                string replacementId =
                    OpaqueIdGenerator.Create("session");
                ulong replacementGeneration = checked(
                    _lifecycleGeneration + 1);
                SessionMode replacementMode =
                    sessionMode ?? _sessionMode;
                _registry.ReplaceLifecycle(
                    _owner,
                    ExpectSession(old),
                    new SessionHostRegistration
                    {
                        SessionId = replacementId,
                        LifecycleGeneration =
                            replacementGeneration,
                        SessionMode =
                            replacementMode,
                        Slot = slot,
                        LauncherProcess = _launcherProcess,
                        CoreSha256 = _coreSha256,
                        RuntimeQualification = qualification,
                        Capabilities = _capabilities
                    });
                _sessionId = replacementId;
                _lifecycleGeneration =
                    replacementGeneration;
                _qualification = qualification;
                _sessionMode = replacementMode;
            }
        }

        private SessionHostRegistration BuildSession(
            string sessionId,
            ulong lifecycleGeneration,
            string slot,
            string attemptId,
            ulong? attemptGeneration,
            SessionProcessIdentity flashProcess,
            long? saveRevision)
        {
            return new SessionHostRegistration
            {
                SessionId = sessionId,
                LifecycleGeneration = lifecycleGeneration,
                SessionMode =
                    _sessionMode,
                Slot = slot,
                SaveRevision = saveRevision,
                AttemptId = attemptId,
                AttemptGeneration = attemptGeneration,
                LauncherProcess = _launcherProcess,
                FlashProcess = flashProcess,
                CoreSha256 = _coreSha256,
                RuntimeQualification = _qualification,
                Capabilities = _capabilities
            };
        }

        private SessionSnapshot RequireSession()
        {
            return _registry.GetSnapshot()
                    .FindSession(_sessionId)
                ?? throw new InvalidOperationException(
                    "session_not_found");
        }

        private static SessionMutationExpectation ExpectSession(
            SessionSnapshot session)
        {
            return new SessionMutationExpectation
            {
                SessionId = session.SessionId,
                LifecycleGeneration =
                    session.LifecycleGeneration,
                AttemptId = session.AttemptId,
                AttemptGeneration =
                    session.AttemptGeneration
            };
        }

        private static SessionSurfaceMutationExpectation
            ExpectSurface(
                SessionSnapshot session,
                SessionSurfaceSnapshot surface)
        {
            return new SessionSurfaceMutationExpectation
            {
                Session = ExpectSession(session),
                TargetId = surface.TargetId,
                SurfaceEpoch = surface.SurfaceEpoch,
                WindowHandle = surface.WindowHandle
            };
        }

        private static bool RegistrationIdentityEquals(
            SessionSurfaceSnapshot current,
            SessionSurfaceHostRegistration observed)
        {
            return current.Kind == observed.Kind
                && current.SafetyKind
                    == observed.SafetyKind
                && current.OwnerRelation
                    == observed.OwnerRelation
                && current.OwnerProcess.IsExact(
                    observed.OwnerProcess)
                && current.WindowHandle
                    == observed.WindowHandle
                && string.Equals(
                    current.OwnerTargetId,
                    observed.OwnerTargetId,
                    StringComparison.Ordinal)
                && current.OwnerWindowHandle
                    == observed.OwnerWindowHandle
                && current.ObservationModes.SequenceEqual(
                    (observed.ObservationModes
                        ?? Array.Empty<ObservationMode>())
                        .Distinct()
                        .OrderBy(value => value))
                && current.InputModes.SequenceEqual(
                    (observed.InputModes
                        ?? Array.Empty<InputMode>())
                        .Distinct()
                        .OrderBy(value => value));
        }

        private static bool LayoutEquals(
            SessionSurfaceSnapshot current,
            SessionSurfaceHostRegistration observed)
        {
            return current.BoundsPhysical.Equals(
                    observed.BoundsPhysical)
                && current.ClientRectPhysical.Equals(
                    observed.ClientRectPhysical)
                && current.ContentRectPhysical.Equals(
                    observed.ContentRectPhysical)
                && current.Dpi == observed.Dpi
                && current.ZIndex == observed.ZIndex
                && current.Visible == observed.Visible
                && current.Minimized == observed.Minimized;
        }
    }
}
