using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;
using CF7Launcher.AgentRuntime.Transport;

namespace CF7Launcher.AgentRuntime.Gateway
{
    /// <summary>
    /// Single cleanup authority for transport disconnect, registry
    /// invalidation and low-level input preemption. All resources are tracked
    /// by opaque server IDs; cleanup never trusts a client-provided principal
    /// or session claim.
    /// </summary>
    internal sealed class AgentRuntimeRevocationCoordinator
        : IAgentConnectionRevocationSink,
          INativeInputPreemptionSink,
          IDisposable
    {
        private readonly object _sync = new object();
        private readonly PrincipalCredentialAuthority _credentials;
        private readonly ObservationGrantBroker _grants;
        private readonly WriteLeaseBroker _leases;
        private readonly Dictionary<string, ConnectionResources>
            _connections =
                new Dictionary<string, ConnectionResources>(
                    StringComparer.Ordinal);
        private readonly Dictionary<string, string>
            _currentDeveloperEnrollmentReceipts =
                new Dictionary<string, string>(
                    StringComparer.Ordinal);
        private readonly HashSet<string>
            _revokedDeveloperClients =
                new HashSet<string>(StringComparer.Ordinal);
        private NativeInputGuard _nativeGuard;
        private bool _disposed;

        public AgentRuntimeRevocationCoordinator(
            PrincipalCredentialAuthority credentials,
            ObservationGrantBroker grants,
            WriteLeaseBroker leases)
        {
            _credentials = credentials
                ?? throw new ArgumentNullException(
                    nameof(credentials));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            _leases = leases
                ?? throw new ArgumentNullException(nameof(leases));
        }

        public void BindNativeGuard(NativeInputGuard guard)
        {
            if (guard == null)
            {
                throw new ArgumentNullException(
                    nameof(guard));
            }
            lock (_sync)
            {
                ThrowIfDisposed();
                if (_nativeGuard != null
                    && !ReferenceEquals(_nativeGuard, guard))
                {
                    throw new InvalidOperationException(
                        "native_input_guard_already_bound");
                }
                if (_nativeGuard == null)
                {
                    _nativeGuard = guard;
                    guard.ExternalInputObserved +=
                        HandleExternalInputObserved;
                }
            }
        }

        internal bool TryClaimShutdownDeliveryWrite(
            string leaseId)
        {
            NativeInputGuard guard;
            long expectedExternalInputSequence;
            LeaseResource trackedLease;
            lock (_sync)
            {
                if (_disposed)
                    return false;
                guard = _nativeGuard;
                trackedLease = _connections.Values
                    .SelectMany(resources =>
                        resources.Leases.Values)
                    .FirstOrDefault(resource =>
                        string.Equals(
                            resource.LeaseId,
                            leaseId,
                            StringComparison.Ordinal));
                if (trackedLease == null)
                    return false;
                expectedExternalInputSequence =
                    trackedLease.HumanOverrideFence;
            }
            if (guard == null)
            {
                return false;
            }
            if (!guard.PollHookHealth(false))
            {
                RevokeLeaseAndCancelQueuedActions(
                    trackedLease.SessionId,
                    trackedLease.LeaseId,
                    "input_guard_unhealthy");
                return false;
            }
            bool claimed =
                _leases.TryClaimShutdownDeliveryWrite(
                leaseId,
                () => guard.TryClaimExternalInputSequence(
                    expectedExternalInputSequence));
            guard.PreemptClaimHealthFailureIfAny();
            return claimed;
        }

        internal bool TryClaimStructuredActionDispatch(
            string leaseId)
        {
            NativeInputGuard guard;
            long expectedExternalInputSequence;
            LeaseResource trackedLease;
            lock (_sync)
            {
                if (_disposed)
                    return false;
                guard = _nativeGuard;
                trackedLease = _connections.Values
                    .SelectMany(resources =>
                        resources.Leases.Values)
                    .FirstOrDefault(resource =>
                        resource.Kind
                            == WriteLeaseKind.StructuredAction
                        && string.Equals(
                            resource.LeaseId,
                            leaseId,
                            StringComparison.Ordinal));
                if (trackedLease == null)
                    return false;
                expectedExternalInputSequence =
                    trackedLease.HumanOverrideFence;
            }
            if (guard == null)
            {
                return false;
            }
            if (!guard.PollHookHealth(false))
            {
                RevokeLeaseAndCancelQueuedActions(
                    trackedLease.SessionId,
                    trackedLease.LeaseId,
                    "input_guard_unhealthy");
                return false;
            }
            string claimReason = null;
            bool claimed =
                _leases.TryClaimStructuredActionDispatch(
                    leaseId,
                    () => guard.TryClaimExternalInputSequence(
                        expectedExternalInputSequence,
                        out claimReason));
            guard.PreemptClaimHealthFailureIfAny();
            if (!claimed)
            {
                RevokeLeaseAndCancelQueuedActions(
                    trackedLease.SessionId,
                    trackedLease.LeaseId,
                    claimReason ?? "lease_revoked");
            }
            return claimed;
        }

        public void RegisterConnection(
            string connectionId,
            PrincipalCredential credential)
        {
            RegisterConnection(
                connectionId,
                credential,
                null);
        }

        public void RegisterConnection(
            string connectionId,
            PrincipalCredential credential,
            Action<string> terminateConnection)
        {
            RequireValue(connectionId, nameof(connectionId));
            if (credential == null)
                throw new ArgumentNullException(nameof(credential));
            string rejectionReason = null;
            lock (_sync)
            {
                ThrowIfDisposed();
                if (_connections.ContainsKey(connectionId))
                {
                    throw new InvalidOperationException(
                        "connection_already_registered");
                }
                if (credential.PrincipalKind
                    == AgentPrincipalKind.DeveloperAgent)
                {
                    if (_revokedDeveloperClients.Contains(
                            credential.ClientInstanceId))
                    {
                        rejectionReason =
                            "developer_enrollment_revoked";
                    }
                    else if (_currentDeveloperEnrollmentReceipts
                        .TryGetValue(
                            credential.ClientInstanceId,
                            out string currentReceipt)
                        && !string.Equals(
                            currentReceipt,
                            credential.IssuerReceipt,
                            StringComparison.Ordinal))
                    {
                        rejectionReason =
                            "developer_enrollment_rotated";
                    }
                    else
                    {
                        _currentDeveloperEnrollmentReceipts[
                            credential.ClientInstanceId] =
                                credential.IssuerReceipt;
                    }
                }
                if (rejectionReason == null)
                {
                    _connections.Add(
                        connectionId,
                        new ConnectionResources(
                            credential,
                            terminateConnection));
                }
            }
            if (rejectionReason != null)
            {
                _credentials.Revoke(
                    credential.CredentialId,
                    rejectionReason);
                TryTerminate(
                    terminateConnection,
                    rejectionReason);
                throw new InvalidOperationException(
                    rejectionReason);
            }
        }

        public int ActivateDeveloperEnrollment(
            string clientInstanceId,
            string enrollmentReceipt,
            string reasonCode)
        {
            RequireValue(
                clientInstanceId,
                nameof(clientInstanceId));
            RequireValue(
                enrollmentReceipt,
                nameof(enrollmentReceipt));
            RequireValue(reasonCode, nameof(reasonCode));
            List<ConnectionResources> revoked;
            lock (_sync)
            {
                ThrowIfDisposed();
                _currentDeveloperEnrollmentReceipts[
                    clientInstanceId] =
                        enrollmentReceipt;
                _revokedDeveloperClients.Remove(
                    clientInstanceId);
                revoked = DetachDeveloperConnectionsLocked(
                    clientInstanceId,
                    enrollmentReceipt);
            }
            foreach (ConnectionResources resources in revoked)
                RevokeDetached(resources, reasonCode);
            return revoked.Count;
        }

        public int RevokeDeveloperEnrollment(
            string clientInstanceId,
            string reasonCode)
        {
            RequireValue(
                clientInstanceId,
                nameof(clientInstanceId));
            RequireValue(reasonCode, nameof(reasonCode));
            List<ConnectionResources> revoked;
            lock (_sync)
            {
                ThrowIfDisposed();
                _currentDeveloperEnrollmentReceipts.Remove(
                    clientInstanceId);
                _revokedDeveloperClients.Add(
                    clientInstanceId);
                revoked = DetachDeveloperConnectionsLocked(
                    clientInstanceId,
                    null);
            }
            foreach (ConnectionResources resources in revoked)
                RevokeDetached(resources, reasonCode);
            return revoked.Count;
        }

        public bool IsDispatchAuthorized(
            string connectionId,
            PrincipalCredential credential)
        {
            if (credential == null)
                return false;
            if (!_credentials.TryResolveActive(
                    credential.CredentialId,
                    credential.ClientInstanceId,
                    out PrincipalCredential active,
                    out _)
                || !ReferenceEquals(active, credential))
            {
                return false;
            }
            lock (_sync)
            {
                if (_disposed
                    || !_connections.TryGetValue(
                        connectionId ?? string.Empty,
                        out ConnectionResources resources)
                    || !ReferenceEquals(
                        resources.Credential,
                        credential)
                    || credential.State
                        != CredentialState.Active)
                {
                    return false;
                }
                if (credential.PrincipalKind
                    != AgentPrincipalKind.DeveloperAgent)
                {
                    return true;
                }
                return !_revokedDeveloperClients.Contains(
                        credential.ClientInstanceId)
                    && _currentDeveloperEnrollmentReceipts
                        .TryGetValue(
                            credential.ClientInstanceId,
                            out string currentReceipt)
                    && string.Equals(
                        currentReceipt,
                        credential.IssuerReceipt,
                        StringComparison.Ordinal);
            }
        }

        public bool TryCaptureSessionFence(
            string connectionId,
            PrincipalCredential credential,
            string sessionId,
            ulong lifecycleGeneration,
            out SessionFenceTicket ticket,
            out string reasonCode)
        {
            RequireValue(sessionId, nameof(sessionId));
            ticket = null;
            if (lifecycleGeneration == 0)
            {
                reasonCode = "stale_lifecycle";
                return false;
            }
            if (!IsExactActiveCredential(credential))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            lock (_sync)
            {
                if (!TryResolveConnectionLocked(
                        connectionId,
                        credential,
                        out ConnectionResources resources,
                        out reasonCode)
                    || !TryValidateSessionBindingLocked(
                        resources,
                        sessionId,
                        lifecycleGeneration,
                        out reasonCode))
                {
                    return false;
                }
                NativeInputGuard guard = _nativeGuard;
                ticket = new SessionFenceTicket(
                    connectionId,
                    credential,
                    sessionId,
                    lifecycleGeneration,
                    resources.SessionFenceEpoch,
                    guard?.CaptureExternalInputSequence()
                        ?? -1);
                reasonCode = null;
                return true;
            }
        }

        public bool TryTrackGrant(
            SessionFenceTicket ticket,
            ObservationGrant grant,
            out string reasonCode)
        {
            if (ticket == null)
                throw new ArgumentNullException(nameof(ticket));
            if (grant == null)
                throw new ArgumentNullException(nameof(grant));
            if (!IsExactActiveCredential(ticket.Credential))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            lock (_sync)
            {
                if (!TryResolveFenceTicketLocked(
                        ticket,
                        out ConnectionResources resources,
                        out reasonCode))
                {
                    return false;
                }
                if (!string.Equals(
                        grant.SecurityPrincipalId,
                        ticket.Credential.SecurityPrincipalId,
                        StringComparison.Ordinal))
                {
                    reasonCode = "principal_mismatch";
                    return false;
                }
                if (!string.Equals(
                        grant.SessionId,
                        ticket.SessionId,
                        StringComparison.Ordinal))
                {
                    reasonCode = "session_mismatch";
                    return false;
                }
                resources.Grants.Add(
                    grant.ObservationGrantId,
                    new GrantResource(
                        grant.SessionId,
                        ticket.LifecycleGeneration,
                        grant.ObservationGrantId));
                reasonCode = null;
                return true;
            }
        }

        public bool TryTrackLease(
            SessionFenceTicket ticket,
            WriteLease lease,
            out string reasonCode)
        {
            if (ticket == null)
                throw new ArgumentNullException(nameof(ticket));
            if (lease == null)
                throw new ArgumentNullException(nameof(lease));
            if (!IsExactActiveCredential(ticket.Credential))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            lock (_sync)
            {
                if (!TryResolveFenceTicketLocked(
                        ticket,
                        out ConnectionResources resources,
                        out reasonCode))
                {
                    return false;
                }
                if (!string.Equals(
                        lease.SecurityPrincipalId,
                        ticket.Credential.SecurityPrincipalId,
                        StringComparison.Ordinal))
                {
                    reasonCode = "principal_mismatch";
                    return false;
                }
                if (!string.Equals(
                        lease.SessionId,
                        ticket.SessionId,
                        StringComparison.Ordinal)
                    || lease.LifecycleGeneration
                        != ticket.LifecycleGeneration)
                {
                    reasonCode = "session_mismatch";
                    return false;
                }
                if (lease.State != WriteLeaseState.Active)
                {
                    reasonCode =
                        lease.RevokeReason ?? "lease_revoked";
                    return false;
                }
                if ((lease.Kind == WriteLeaseKind.Shutdown
                        || lease.Kind
                            == WriteLeaseKind.StructuredAction)
                    && (ticket.HumanOverrideFence < 0
                        || _nativeGuard == null
                        || !_nativeGuard
                            .TryAuthorizeShutdownLease(
                                out reasonCode)))
                {
                    reasonCode ??= "input_guard_unhealthy";
                    return false;
                }
                resources.Leases.Add(
                    lease.LeaseId,
                    new LeaseResource(
                        lease.SessionId,
                        lease.LifecycleGeneration,
                        lease.LeaseId,
                        lease.Kind,
                        ticket.HumanOverrideFence));
                reasonCode = null;
                return true;
            }
        }

        public bool IsSessionFenceCurrent(
            SessionFenceTicket ticket,
            out string reasonCode)
        {
            if (ticket == null)
                throw new ArgumentNullException(nameof(ticket));
            if (!IsExactActiveCredential(ticket.Credential))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            lock (_sync)
            {
                return TryResolveFenceTicketLocked(
                    ticket,
                    out _,
                    out reasonCode);
            }
        }

        public void RevokeGrantAndForget(
            string connectionId,
            string grantId,
            string reasonCode)
        {
            RequireValue(grantId, nameof(grantId));
            RequireValue(reasonCode, nameof(reasonCode));
            lock (_sync)
            {
                if (_connections.TryGetValue(
                        connectionId ?? string.Empty,
                        out ConnectionResources resources))
                {
                    resources.Grants.Remove(grantId);
                }
            }
            _grants.Revoke(grantId, reasonCode);
        }

        public bool TryAttachSession(
            string connectionId,
            PrincipalCredential credential,
            string sessionId,
            ulong lifecycleGeneration,
            out string reasonCode)
        {
            RequireValue(sessionId, nameof(sessionId));
            if (!IsExactActiveCredential(credential))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            lock (_sync)
            {
                if (!TryResolveConnectionLocked(
                        connectionId,
                        credential,
                        out ConnectionResources resources,
                        out reasonCode))
                {
                    return false;
                }
                SessionAttachment attachment =
                    resources.Attachment;
                if (resources.SessionFenceMode
                        == SessionFenceMode.Attached)
                {
                    if (attachment != null
                        && string.Equals(
                            attachment.SessionId,
                            sessionId,
                            StringComparison.Ordinal)
                        && attachment.LifecycleGeneration
                            == lifecycleGeneration)
                    {
                        reasonCode = null;
                        return true;
                    }
                    reasonCode = "session_mismatch";
                    return false;
                }
                if (resources.SessionFenceMode
                        == SessionFenceMode.ExplicitlyDetached)
                {
                    SessionAttachment detached =
                        resources.DetachedAttachment;
                    if (detached == null
                        || !string.Equals(
                            detached.SessionId,
                            sessionId,
                            StringComparison.Ordinal)
                        || detached.LifecycleGeneration
                            != lifecycleGeneration)
                    {
                        reasonCode = "session_mismatch";
                        return false;
                    }
                }
                AdvanceSessionFenceLocked(
                    resources,
                    "session_mismatch");
                resources.Attachment =
                    new SessionAttachment(
                        sessionId,
                        lifecycleGeneration);
                resources.DetachedAttachment = null;
                resources.SessionFenceMode =
                    SessionFenceMode.Attached;
                reasonCode = null;
                return true;
            }
        }

        public bool TryDetachSession(
            string connectionId,
            PrincipalCredential credential,
            string sessionId,
            ulong lifecycleGeneration,
            out string reasonCode)
        {
            RequireValue(sessionId, nameof(sessionId));
            if (!IsExactActiveCredential(credential))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            GrantResource[] grants;
            LeaseResource[] leases;
            PendingActionResource[] actions;
            NativeInputGuard guard;
            lock (_sync)
            {
                if (!TryResolveConnectionLocked(
                        connectionId,
                        credential,
                        out ConnectionResources resources,
                        out reasonCode))
                {
                    return false;
                }
                SessionAttachment attachment =
                    resources.Attachment;
                if (resources.SessionFenceMode
                        != SessionFenceMode.Attached
                    || attachment == null
                    || !string.Equals(
                        attachment.SessionId,
                        sessionId,
                        StringComparison.Ordinal)
                    || attachment.LifecycleGeneration
                        != lifecycleGeneration)
                {
                    reasonCode = "session_mismatch";
                    return false;
                }
                AdvanceSessionFenceLocked(
                    resources,
                    "session_mismatch");
                resources.Attachment = null;
                resources.DetachedAttachment = attachment;
                resources.SessionFenceMode =
                    SessionFenceMode.ExplicitlyDetached;
                grants = resources.Grants.Values
                    .Where(resource => string.Equals(
                        resource.SessionId,
                        sessionId,
                        StringComparison.Ordinal))
                    .ToArray();
                leases = resources.Leases.Values
                    .Where(resource => string.Equals(
                        resource.SessionId,
                        sessionId,
                        StringComparison.Ordinal))
                    .ToArray();
                actions = resources.Actions.Values
                    .Where(resource => string.Equals(
                        resource.SessionId,
                        sessionId,
                        StringComparison.Ordinal))
                    .ToArray();
                foreach (GrantResource grant in grants)
                    resources.Grants.Remove(grant.GrantId);
                foreach (LeaseResource lease in leases)
                    resources.Leases.Remove(lease.LeaseId);
                foreach (PendingActionResource action in actions)
                {
                    string registrationId = resources.Actions
                        .Single(pair =>
                            ReferenceEquals(
                                pair.Value,
                                action))
                        .Key;
                    resources.Actions.Remove(registrationId);
                }
                guard = _nativeGuard;
            }
            foreach (GrantResource grant in grants)
            {
                _grants.Revoke(
                    grant.GrantId,
                    "session_detached");
            }
            foreach (LeaseResource lease in leases)
            {
                _leases.Revoke(
                    lease.LeaseId,
                    "session_detached");
                TryRevokeGuardLease(
                    guard,
                    lease,
                    "session_detached");
            }
            CancelAndDispose(
                actions.Select(action => action.Source));
            reasonCode = null;
            return true;
        }

        public ActionCancellationRegistration RegisterAction(
            string connectionId,
            string leaseId,
            CancellationToken callerCancellation)
        {
            RequireValue(connectionId, nameof(connectionId));
            lock (_sync)
            {
                ConnectionResources resources =
                    RequireConnectionLocked(connectionId);
                string sessionId = null;
                LeaseResource lease = null;
                if (leaseId != null
                    && !resources.Leases.TryGetValue(
                        leaseId,
                        out lease))
                {
                    throw new InvalidOperationException(
                        "lease_owner_mismatch");
                }
                if (lease != null)
                {
                    sessionId = lease.SessionId;
                    if (!_leases
                            .IsActionRegistrationAllowed(
                                leaseId))
                    {
                        throw new InvalidOperationException(
                            "lease_revoked");
                    }
                }
                var source =
                    CancellationTokenSource.CreateLinkedTokenSource(
                        callerCancellation);
                string registrationId =
                    OpaqueIdGenerator.Create("pending");
                resources.Actions.Add(
                    registrationId,
                    new PendingActionResource(
                        sessionId,
                        leaseId,
                        source));
                return new ActionCancellationRegistration(
                    this,
                    connectionId,
                    registrationId,
                    source.Token);
            }
        }

        public Task RevokeAsync(
            string connectionId,
            AgentConnectionTermination termination)
        {
            string reason = termination?.ReasonCode
                ?? "connection_closed";
            RevokeConnection(connectionId, reason);
            return Task.CompletedTask;
        }

        public void RevokeLeaseAndCancelQueuedActions(
            string sessionId,
            string leaseId,
            string reasonCode)
        {
            RequireValue(reasonCode, nameof(reasonCode));
            NativeInputGuard guard;
            LeaseResource trackedLease = null;
            List<CancellationTokenSource> actions;
            lock (_sync)
            {
                actions = new List<CancellationTokenSource>();
                foreach (ConnectionResources resources
                    in _connections.Values)
                {
                    foreach (PendingActionResource action
                        in resources.Actions.Values)
                    {
                        if (string.Equals(
                                action.LeaseId,
                                leaseId,
                                StringComparison.Ordinal))
                        {
                            actions.Add(action.Source);
                        }
                    }
                    if (resources.Leases.TryGetValue(
                            leaseId,
                            out LeaseResource candidate))
                    {
                        trackedLease ??= candidate;
                    }
                    resources.Leases.Remove(leaseId);
                }
                guard = _nativeGuard;
            }

            _leases.Revoke(leaseId, reasonCode);
            Cancel(actions);
            TryRevokeGuardLease(
                guard,
                trackedLease,
                reasonCode);
        }

        public void UntrackLeaseAndCancelQueuedActions(
            string sessionId,
            string leaseId,
            string reasonCode)
        {
            RequireValue(reasonCode, nameof(reasonCode));
            NativeInputGuard guard;
            LeaseResource trackedLease = null;
            List<CancellationTokenSource> actions;
            lock (_sync)
            {
                actions = new List<CancellationTokenSource>();
                foreach (ConnectionResources resources
                    in _connections.Values)
                {
                    foreach (PendingActionResource action
                        in resources.Actions.Values)
                    {
                        if (string.Equals(
                                action.LeaseId,
                                leaseId,
                                StringComparison.Ordinal))
                        {
                            actions.Add(action.Source);
                        }
                    }
                    if (resources.Leases.TryGetValue(
                            leaseId,
                            out LeaseResource candidate))
                    {
                        trackedLease ??= candidate;
                    }
                    resources.Leases.Remove(leaseId);
                }
                guard = _nativeGuard;
            }

            Cancel(actions);
            TryRevokeGuardLease(
                guard,
                trackedLease,
                reasonCode);
        }

        public void HandleSessionInvalidation(
            SessionScopeInvalidation invalidation)
        {
            if (invalidation == null)
                throw new ArgumentNullException(
                    nameof(invalidation));
            string reason = string.IsNullOrWhiteSpace(
                    invalidation.ReasonCode)
                ? "stale_observation"
                : invalidation.ReasonCode;

            if (invalidation.Has(
                    SessionInvalidationFlags.ObservationGrants))
            {
                _grants.RevokeSession(
                    invalidation.SessionId,
                    reason);
            }

            List<LeaseResource> leases = new List<LeaseResource>();
            List<CancellationTokenSource> actions =
                new List<CancellationTokenSource>();
            NativeInputGuard guard;
            lock (_sync)
            {
                foreach (ConnectionResources resources
                    in _connections.Values)
                {
                    bool attachedSessionInvalidated =
                        string.Equals(
                            resources.Attachment?.SessionId,
                            invalidation.SessionId,
                            StringComparison.Ordinal);
                    bool detachedSessionInvalidated =
                        string.Equals(
                            resources.DetachedAttachment
                                ?.SessionId,
                            invalidation.SessionId,
                            StringComparison.Ordinal);
                    bool trackedSessionInvalidated =
                        resources.Grants.Values.Any(
                            value => string.Equals(
                                value.SessionId,
                                invalidation.SessionId,
                                StringComparison.Ordinal))
                        || resources.Leases.Values.Any(
                            value => string.Equals(
                                value.SessionId,
                                invalidation.SessionId,
                                StringComparison.Ordinal));
                    if (invalidation.Level
                            == SessionInvalidationLevel.Lifecycle
                        && (resources.SessionFenceMode
                                == SessionFenceMode
                                    .InitialBootstrap
                            || attachedSessionInvalidated
                            || detachedSessionInvalidated
                            || trackedSessionInvalidated))
                    {
                        AdvanceSessionFenceLocked(
                            resources,
                            "stale_lifecycle");
                        if (attachedSessionInvalidated)
                        {
                            resources.Attachment = null;
                            resources.SessionFenceMode =
                                SessionFenceMode
                                    .InitialBootstrap;
                        }
                    }
                    if (invalidation.Has(
                            SessionInvalidationFlags
                                .ObservationGrants))
                    {
                        GrantResource[] scopedGrants =
                            resources.Grants.Values
                                .Where(value =>
                                    string.Equals(
                                        value.SessionId,
                                        invalidation.SessionId,
                                        StringComparison.Ordinal))
                                .ToArray();
                        foreach (GrantResource grant
                            in scopedGrants)
                        {
                            resources.Grants.Remove(
                                grant.GrantId);
                        }
                    }
                    if (invalidation.Has(
                            SessionInvalidationFlags.WriteLeases))
                    {
                        LeaseResource[] scopedLeases =
                            resources.Leases.Values.Where(
                                value =>
                                    invalidation
                                        .RequiresHumanReauthorization
                                    || string.Equals(
                                        value.SessionId,
                                        invalidation.SessionId,
                                        StringComparison.Ordinal))
                            .ToArray();
                        foreach (LeaseResource lease
                            in scopedLeases)
                        {
                            leases.Add(lease);
                        }
                        foreach (LeaseResource lease
                            in scopedLeases)
                        {
                            resources.Leases.Remove(lease.LeaseId);
                        }
                    }

                    if (invalidation.Has(
                            SessionInvalidationFlags.QueuedActions)
                        || invalidation.Has(
                            SessionInvalidationFlags.PendingActions)
                        || invalidation.Has(
                            SessionInvalidationFlags
                                .PendingCoordinateActions)
                        || invalidation.Has(
                            SessionInvalidationFlags.PendingInput))
                    {
                        actions.AddRange(
                            resources.Actions.Values
                                .Where(action =>
                                    (invalidation
                                            .RequiresHumanReauthorization
                                        || string.Equals(
                                            action.SessionId,
                                            invalidation.SessionId,
                                            StringComparison.Ordinal))
                                    && !PreserveClaimedStructuredAction(
                                        resources,
                                        action,
                                        invalidation))
                                .Select(action => action.Source));
                    }
                }
                guard = _nativeGuard;
            }

            foreach (LeaseResource lease in leases
                .DistinctBy(value => value.LeaseId))
            {
                _leases.Revoke(lease.LeaseId, reason);
                TryRevokeGuardLease(
                    guard,
                    lease,
                    reason);
            }
            if (invalidation.RequiresHumanReauthorization)
                _leases.RevokeAllForHumanOverride(reason);
            Cancel(actions);
            if (invalidation.Has(
                    SessionInvalidationFlags.RuntimeHeldInput)
                || invalidation.Has(
                    SessionInvalidationFlags.PendingInput)
                || invalidation.RequiresHumanReauthorization)
            {
                guard?.FailAndPreempt(reason);
            }
        }

        private bool PreserveClaimedStructuredAction(
            ConnectionResources resources,
            PendingActionResource action,
            SessionScopeInvalidation invalidation)
        {
            const SessionInvalidationFlags
                SelfPanelMutationFlags =
                    SessionInvalidationFlags.Observations
                    | SessionInvalidationFlags.PendingActions
                    | SessionInvalidationFlags
                        .PendingDomainOperations
                    | SessionInvalidationFlags
                        .ExactInstanceLeases;
            if (invalidation.Level
                    != SessionInvalidationLevel.Panel
                || (!string.Equals(
                        invalidation.ReasonCode,
                        "panel_opened",
                        StringComparison.Ordinal)
                    && !string.Equals(
                        invalidation.ReasonCode,
                        "panel_instance_changed",
                        StringComparison.Ordinal))
                || invalidation.Flags != SelfPanelMutationFlags
                || invalidation.RequiresHumanReauthorization
                || action.LeaseId == null
                || !resources.Leases.TryGetValue(
                    action.LeaseId,
                    out LeaseResource lease)
                || lease.Kind
                    != WriteLeaseKind.StructuredAction
                || !string.Equals(
                    lease.SessionId,
                    invalidation.SessionId,
                    StringComparison.Ordinal)
                || lease.LifecycleGeneration
                    != invalidation.LifecycleGeneration)
            {
                return false;
            }
            return _leases.IsStructuredActionDispatchClaimed(
                lease.LeaseId);
        }

        public void RevokeConnection(
            string connectionId,
            string reasonCode)
        {
            RequireValue(reasonCode, nameof(reasonCode));
            ConnectionResources resources;
            NativeInputGuard guard;
            lock (_sync)
            {
                if (!_connections.Remove(
                        connectionId ?? string.Empty,
                        out resources))
                {
                    return;
                }
                guard = _nativeGuard;
            }

            RevokeDetached(
                resources,
                reasonCode,
                guard);
        }

        public void RevokeCredential(
            string credentialId,
            string reasonCode)
        {
            RequireValue(
                credentialId,
                nameof(credentialId));
            RequireValue(
                reasonCode,
                nameof(reasonCode));
            List<ConnectionResources> revoked;
            NativeInputGuard guard;
            lock (_sync)
            {
                ThrowIfDisposed();
                string[] connectionIds = _connections
                    .Where(pair =>
                        string.Equals(
                            pair.Value.Credential
                                .CredentialId,
                            credentialId,
                            StringComparison.Ordinal))
                    .Select(pair => pair.Key)
                    .ToArray();
                revoked =
                    new List<ConnectionResources>(
                        connectionIds.Length);
                foreach (string connectionId
                    in connectionIds)
                {
                    if (_connections.Remove(
                            connectionId,
                            out ConnectionResources resources))
                    {
                        revoked.Add(resources);
                    }
                }
                guard = _nativeGuard;
            }

            if (revoked.Count == 0)
            {
                _credentials.Revoke(
                    credentialId,
                    reasonCode);
                return;
            }
            foreach (ConnectionResources resources
                in revoked)
            {
                RevokeDetached(
                    resources,
                    reasonCode,
                    guard);
            }
        }

        public void Dispose()
        {
            string[] connectionIds;
            NativeInputGuard guard;
            lock (_sync)
            {
                if (_disposed) return;
                _disposed = true;
                connectionIds = _connections.Keys.ToArray();
                guard = _nativeGuard;
            }
            if (guard != null)
            {
                guard.ExternalInputObserved -=
                    HandleExternalInputObserved;
            }
            foreach (string connectionId in connectionIds)
            {
                RevokeConnection(
                    connectionId,
                    "runtime_shutdown");
            }
            lock (_sync)
            {
                if (ReferenceEquals(_nativeGuard, guard))
                    _nativeGuard = null;
            }
        }

        private void HandleExternalInputObserved(
            ExternalInputObservation observation)
        {
            if (observation == null)
                return;
            HandleHumanOverride(
                observation.ReasonCode);
        }

        internal void HandleHumanOverride(string reasonCode)
        {
            string reason = string.IsNullOrWhiteSpace(
                    reasonCode)
                ? "human_input"
                : reasonCode;
            List<CancellationTokenSource> actions;
            lock (_sync)
            {
                if (_disposed)
                    return;
                _leases.RevokeAllForHumanOverride(
                    reason,
                    out IReadOnlyCollection<string>
                        claimedStructuredLeaseIds);
                var claimedStructured =
                    new HashSet<string>(
                        claimedStructuredLeaseIds,
                        StringComparer.Ordinal);
                actions = _connections.Values
                    .SelectMany(resources =>
                        resources.Actions.Values)
                    .Where(action =>
                        action.LeaseId == null
                        || !claimedStructured.Contains(
                            action.LeaseId))
                    .Select(action => action.Source)
                    .Distinct()
                    .ToList();
            }
            Cancel(actions);
        }

        private void CompleteAction(
            string connectionId,
            string registrationId)
        {
            PendingActionResource action = null;
            lock (_sync)
            {
                if (_connections.TryGetValue(
                        connectionId,
                        out ConnectionResources resources))
                {
                    resources.Actions.Remove(
                        registrationId,
                        out action);
                }
            }
            action?.Source.Dispose();
        }

        private ConnectionResources RequireConnectionLocked(
            string connectionId)
        {
            ThrowIfDisposed();
            if (!_connections.TryGetValue(
                    connectionId ?? string.Empty,
                    out ConnectionResources resources))
            {
                throw new InvalidOperationException(
                    "connection_not_registered");
            }
            return resources;
        }

        private bool IsExactActiveCredential(
            PrincipalCredential credential)
        {
            return credential != null
                && _credentials.TryResolveActive(
                    credential.CredentialId,
                    credential.ClientInstanceId,
                    out PrincipalCredential active,
                    out _)
                && ReferenceEquals(active, credential);
        }

        private bool TryResolveConnectionLocked(
            string connectionId,
            PrincipalCredential credential,
            out ConnectionResources resources,
            out string reasonCode)
        {
            resources = null;
            if (_disposed
                || !_connections.TryGetValue(
                    connectionId ?? string.Empty,
                    out resources))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            if (credential == null
                || !ReferenceEquals(
                    resources.Credential,
                    credential))
            {
                reasonCode = "principal_mismatch";
                return false;
            }
            if (credential.State != CredentialState.Active)
            {
                reasonCode = "credential_revoked";
                return false;
            }
            if (credential.PrincipalKind
                    == AgentPrincipalKind.DeveloperAgent
                && (_revokedDeveloperClients.Contains(
                        credential.ClientInstanceId)
                    || !_currentDeveloperEnrollmentReceipts
                        .TryGetValue(
                            credential.ClientInstanceId,
                            out string currentReceipt)
                    || !string.Equals(
                        currentReceipt,
                        credential.IssuerReceipt,
                        StringComparison.Ordinal)))
            {
                reasonCode = "credential_revoked";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private bool TryResolveFenceTicketLocked(
            SessionFenceTicket ticket,
            out ConnectionResources resources,
            out string reasonCode)
        {
            if (!TryResolveConnectionLocked(
                    ticket.ConnectionId,
                    ticket.Credential,
                    out resources,
                    out reasonCode))
            {
                return false;
            }
            if (resources.SessionFenceEpoch
                != ticket.SessionFenceEpoch)
            {
                reasonCode =
                    resources.SessionFenceRejectionReason
                    ?? "stale_lifecycle";
                return false;
            }
            return TryValidateSessionBindingLocked(
                resources,
                ticket.SessionId,
                ticket.LifecycleGeneration,
                out reasonCode);
        }

        private static bool TryValidateSessionBindingLocked(
            ConnectionResources resources,
            string sessionId,
            ulong lifecycleGeneration,
            out string reasonCode)
        {
            if (resources.SessionFenceMode
                    == SessionFenceMode.ExplicitlyDetached)
            {
                reasonCode = "session_mismatch";
                return false;
            }
            if (resources.SessionFenceMode
                    == SessionFenceMode.Attached)
            {
                SessionAttachment attachment =
                    resources.Attachment;
                if (attachment == null
                    || !string.Equals(
                        attachment.SessionId,
                        sessionId,
                        StringComparison.Ordinal)
                    || attachment.LifecycleGeneration
                        != lifecycleGeneration)
                {
                    reasonCode = "session_mismatch";
                    return false;
                }
            }
            reasonCode = null;
            return true;
        }

        private static void AdvanceSessionFenceLocked(
            ConnectionResources resources,
            string rejectionReason)
        {
            resources.SessionFenceEpoch =
                checked(resources.SessionFenceEpoch + 1);
            resources.SessionFenceRejectionReason =
                rejectionReason;
        }

        private List<ConnectionResources>
            DetachDeveloperConnectionsLocked(
                string clientInstanceId,
                string retainedEnrollmentReceipt)
        {
            string[] connectionIds = _connections
                .Where(pair =>
                    pair.Value.Credential.PrincipalKind
                        == AgentPrincipalKind.DeveloperAgent
                    && string.Equals(
                        pair.Value.Credential.ClientInstanceId,
                        clientInstanceId,
                        StringComparison.Ordinal)
                    && (retainedEnrollmentReceipt == null
                        || !string.Equals(
                            pair.Value.Credential.IssuerReceipt,
                            retainedEnrollmentReceipt,
                            StringComparison.Ordinal)))
                .Select(pair => pair.Key)
                .ToArray();
            var revoked = new List<ConnectionResources>(
                connectionIds.Length);
            foreach (string connectionId in connectionIds)
            {
                if (_connections.Remove(
                        connectionId,
                        out ConnectionResources resources))
                {
                    revoked.Add(resources);
                }
            }
            return revoked;
        }

        private void RevokeDetached(
            ConnectionResources resources,
            string reasonCode,
            NativeInputGuard guard = null)
        {
            if (resources == null)
                return;
            if (guard == null)
            {
                lock (_sync)
                {
                    guard = _nativeGuard;
                }
            }
            foreach (GrantResource grant
                in resources.Grants.Values)
            {
                _grants.Revoke(
                    grant.GrantId,
                    reasonCode);
            }
            foreach (LeaseResource lease
                in resources.Leases.Values)
            {
                _leases.Revoke(lease.LeaseId, reasonCode);
                TryRevokeGuardLease(
                    guard,
                    lease,
                    reasonCode);
            }
            // Publish revoked authority before cancellation can wake an
            // action owner. That owner must never observe its one-shot
            // action_limit_consumed marker as the revocation cause.
            Cancel(
                resources.Actions.Values.Select(
                    action => action.Source));
            _credentials.Revoke(
                resources.Credential.CredentialId,
                reasonCode);
            resources.Terminate(reasonCode);
            resources.Dispose();
        }

        private static void Cancel(
            IEnumerable<CancellationTokenSource> sources)
        {
            foreach (CancellationTokenSource source
                in (sources
                    ?? Array.Empty<CancellationTokenSource>())
                    .Distinct())
            {
                try { source.Cancel(); }
                catch (ObjectDisposedException) { }
            }
        }

        private static void CancelAndDispose(
            IEnumerable<CancellationTokenSource> sources)
        {
            CancellationTokenSource[] copy =
                (sources
                    ?? Array.Empty<CancellationTokenSource>())
                    .Distinct()
                    .ToArray();
            Cancel(copy);
            foreach (CancellationTokenSource source in copy)
                source.Dispose();
        }

        private static void TryTerminate(
            Action<string> terminateConnection,
            string reasonCode)
        {
            try
            {
                terminateConnection?.Invoke(reasonCode);
            }
            catch
            {
            }
        }

        private static void TryRevokeGuardLease(
            NativeInputGuard guard,
            LeaseResource lease,
            string reasonCode)
        {
            if (lease?.Kind != WriteLeaseKind.GuiInput)
                return;
            try
            {
                guard?.RevokeBoundLease(
                    lease.SessionId,
                    lease.LeaseId,
                    reasonCode);
            }
            catch (ObjectDisposedException)
            {
            }
        }

        private static void RequireValue(
            string value,
            string parameter)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException(
                    "A non-empty value is required.",
                    parameter);
        }

        private void ThrowIfDisposed()
        {
            if (_disposed)
                throw new ObjectDisposedException(
                    nameof(
                        AgentRuntimeRevocationCoordinator));
        }

        internal sealed class ActionCancellationRegistration
            : IDisposable
        {
            private AgentRuntimeRevocationCoordinator _owner;
            private readonly string _connectionId;
            private readonly string _registrationId;

            internal ActionCancellationRegistration(
                AgentRuntimeRevocationCoordinator owner,
                string connectionId,
                string registrationId,
                CancellationToken token)
            {
                _owner = owner;
                _connectionId = connectionId;
                _registrationId = registrationId;
                Token = token;
            }

            public CancellationToken Token { get; }

            public void Dispose()
            {
                AgentRuntimeRevocationCoordinator owner =
                    Interlocked.Exchange(ref _owner, null);
                owner?.CompleteAction(
                    _connectionId,
                    _registrationId);
            }
        }

        internal sealed class SessionFenceTicket
        {
            internal SessionFenceTicket(
                string connectionId,
                PrincipalCredential credential,
                string sessionId,
                ulong lifecycleGeneration,
                ulong sessionFenceEpoch,
                long humanOverrideFence)
            {
                ConnectionId = connectionId;
                Credential = credential;
                SessionId = sessionId;
                LifecycleGeneration = lifecycleGeneration;
                SessionFenceEpoch = sessionFenceEpoch;
                HumanOverrideFence = humanOverrideFence;
            }

            internal string ConnectionId { get; }
            internal PrincipalCredential Credential { get; }
            internal string SessionId { get; }
            internal ulong LifecycleGeneration { get; }
            internal ulong SessionFenceEpoch { get; }
            internal long HumanOverrideFence { get; }
        }

        private sealed class ConnectionResources : IDisposable
        {
            private Action<string> _terminateConnection;

            public ConnectionResources(
                PrincipalCredential credential,
                Action<string> terminateConnection)
            {
                Credential = credential;
                _terminateConnection = terminateConnection;
            }

            public PrincipalCredential Credential { get; }
            public SessionAttachment Attachment { get; set; }
            public SessionAttachment DetachedAttachment
            {
                get;
                set;
            }
            public SessionFenceMode SessionFenceMode
            {
                get;
                set;
            } = SessionFenceMode.InitialBootstrap;
            public ulong SessionFenceEpoch { get; set; } = 1;
            public string SessionFenceRejectionReason
            {
                get;
                set;
            }
            public Dictionary<string, GrantResource> Grants
            {
                get;
            } = new Dictionary<string, GrantResource>(
                StringComparer.Ordinal);
            public Dictionary<string, LeaseResource> Leases
            {
                get;
            } = new Dictionary<string, LeaseResource>(
                StringComparer.Ordinal);
            public Dictionary<string, PendingActionResource> Actions
            {
                get;
            } = new Dictionary<string, PendingActionResource>(
                StringComparer.Ordinal);

            public void Terminate(string reasonCode)
            {
                Action<string> terminate =
                    Interlocked.Exchange(
                        ref _terminateConnection,
                        null);
                TryTerminate(terminate, reasonCode);
            }

            public void Dispose()
            {
                Interlocked.Exchange(
                    ref _terminateConnection,
                    null);
                foreach (PendingActionResource action
                    in Actions.Values)
                {
                    action.Source.Dispose();
                }
                Actions.Clear();
            }
        }

        private sealed record LeaseResource(
            string SessionId,
            ulong LifecycleGeneration,
            string LeaseId,
            WriteLeaseKind Kind,
            long HumanOverrideFence);

        private sealed record GrantResource(
            string SessionId,
            ulong LifecycleGeneration,
            string GrantId);

        private sealed record SessionAttachment(
            string SessionId,
            ulong LifecycleGeneration);

        private sealed record PendingActionResource(
            string SessionId,
            string LeaseId,
            CancellationTokenSource Source);

        private enum SessionFenceMode
        {
            InitialBootstrap,
            Attached,
            ExplicitlyDetached
        }
    }
}
