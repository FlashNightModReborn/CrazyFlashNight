using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Gateway;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Integration
{
    /// <summary>
    /// Marshals one callback to the Launcher UI thread. A false result means
    /// that host shutdown prevented the callback from running. Once callback
    /// execution starts, implementations must complete it synchronously and
    /// must not convert later cancellation into a false result.
    /// </summary>
    internal delegate Task<bool> LauncherAgentUiMarshal(
        Action callback,
        CancellationToken cancellationToken);

    /// <summary>
    /// Host-registry proof for one exact target incarnation. Activators may
    /// use only this binding; they must not rediscover a window by title,
    /// executable name, or process id alone.
    /// </summary>
    internal sealed class LauncherAgentExactTargetBinding
    {
        internal LauncherAgentExactTargetBinding(
            string sessionId,
            ulong lifecycleGeneration,
            string attemptId,
            ulong? attemptGeneration,
            string targetId,
            long windowHandle,
            SessionProcessIdentity ownerProcess,
            ulong surfaceEpoch,
            ulong coordinateSpaceVersion)
        {
            SessionId = sessionId;
            LifecycleGeneration = lifecycleGeneration;
            AttemptId = attemptId;
            AttemptGeneration = attemptGeneration;
            TargetId = targetId;
            WindowHandle = windowHandle;
            OwnerProcess = ownerProcess;
            SurfaceEpoch = surfaceEpoch;
            CoordinateSpaceVersion = coordinateSpaceVersion;
        }

        public string SessionId { get; }
        public ulong LifecycleGeneration { get; }
        public string AttemptId { get; }
        public ulong? AttemptGeneration { get; }
        public string TargetId { get; }
        public long WindowHandle { get; }
        public SessionProcessIdentity OwnerProcess { get; }
        public ulong SurfaceEpoch { get; }
        public ulong CoordinateSpaceVersion { get; }

        internal bool IsExact(
            LauncherAgentExactTargetBinding other)
        {
            return other != null
                && string.Equals(
                    SessionId,
                    other.SessionId,
                    StringComparison.Ordinal)
                && LifecycleGeneration
                    == other.LifecycleGeneration
                && string.Equals(
                    AttemptId,
                    other.AttemptId,
                    StringComparison.Ordinal)
                && AttemptGeneration
                    == other.AttemptGeneration
                && string.Equals(
                    TargetId,
                    other.TargetId,
                    StringComparison.Ordinal)
                && WindowHandle == other.WindowHandle
                && SurfaceEpoch == other.SurfaceEpoch
                && CoordinateSpaceVersion
                    == other.CoordinateSpaceVersion
                && OwnerProcess != null
                && OwnerProcess.IsExact(other.OwnerProcess);
        }
    }

    /// <summary>
    /// Narrow structured-action bridge into trusted Launcher callbacks.
    /// Target identity comes exclusively from the host registry and the
    /// constructor's exact target map; no window discovery participates.
    /// Successful results prove broker dispatch only, never target effect.
    /// </summary>
    internal sealed class LauncherAgentStructuredActionHost
        : IAgentStructuredActionHost,
          IDisposable
    {
        private readonly object _lifecycleSync = new object();
        private readonly Func<SessionSurfaceRegistrySnapshot>
            _snapshotProvider;
        private readonly LauncherAgentUiMarshal _marshalToUi;
        private readonly IReadOnlyDictionary<
            string,
            Func<LauncherAgentExactTargetBinding, bool>>
            _activateByTarget;
        private readonly Func<string, bool> _prepareSafeExit;
        private readonly Action<string> _completeSafeExit;
        private readonly Action<string> _abortSafeExit;
        private readonly Action _revealLifecycle;
        private readonly Action _cancelLifecycle;
        private readonly Func<string, bool> _tryOpenPanel;
        private bool _disposed;

        public LauncherAgentStructuredActionHost(
            Func<SessionSurfaceRegistrySnapshot> snapshotProvider,
            LauncherAgentUiMarshal marshalToUi,
            IReadOnlyDictionary<
                string,
                Func<LauncherAgentExactTargetBinding, bool>>
                    activateByTarget,
            Func<string, bool> prepareSafeExit,
            Action<string> completeSafeExit,
            Action<string> abortSafeExit,
            Action revealLifecycle,
            Action cancelLifecycle,
            Func<string, bool> tryOpenPanel)
        {
            _snapshotProvider = snapshotProvider
                ?? throw new ArgumentNullException(
                    nameof(snapshotProvider));
            _marshalToUi = marshalToUi
                ?? throw new ArgumentNullException(
                    nameof(marshalToUi));
            _activateByTarget = FreezeActivators(
                activateByTarget);
            _prepareSafeExit = prepareSafeExit
                ?? throw new ArgumentNullException(
                    nameof(prepareSafeExit));
            _completeSafeExit = completeSafeExit
                ?? throw new ArgumentNullException(
                    nameof(completeSafeExit));
            _abortSafeExit = abortSafeExit
                ?? throw new ArgumentNullException(
                    nameof(abortSafeExit));
            _revealLifecycle = revealLifecycle
                ?? throw new ArgumentNullException(
                    nameof(revealLifecycle));
            _cancelLifecycle = cancelLifecycle
                ?? throw new ArgumentNullException(
                    nameof(cancelLifecycle));
            _tryOpenPanel = tryOpenPanel
                ?? throw new ArgumentNullException(
                    nameof(tryOpenPanel));
        }

        public async Task<AgentActionPerformance> PerformAsync(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease,
            CancellationToken cancellationToken)
        {
            if (context == null)
                throw new ArgumentNullException(nameof(context));
            if (action == null)
                throw new ArgumentNullException(nameof(action));
            if (lease == null)
                throw new ArgumentNullException(nameof(lease));

            if (action.Operation
                    == AgentCapabilitiesV1.SetValue
                || action.Operation
                    == AgentCapabilitiesV1
                        .PerformSecondaryAction)
            {
                return AgentActionPerformance.Rejected(
                    "unsupported_for_surface");
            }
            if (!IsSupported(action.Operation))
            {
                return AgentActionPerformance.Rejected(
                    "operation_invalid");
            }
            if (cancellationToken.IsCancellationRequested
                || IsDisposed())
            {
                return AgentActionPerformance.Rejected(
                    "lease_revoked");
            }

            AgentActionPerformance performance = null;
            bool invoked;
            try
            {
                invoked = await _marshalToUi(
                        () => performance = PerformOnUi(
                            context,
                            action,
                            lease,
                            cancellationToken),
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
                when (cancellationToken.IsCancellationRequested)
            {
                return AgentActionPerformance.Rejected(
                    "lease_revoked");
            }
            catch (ObjectDisposedException)
            {
                return AgentActionPerformance.Rejected(
                    "lease_revoked");
            }
            catch
            {
                return AgentActionPerformance.Rejected(
                    "internal_error");
            }

            if (!invoked)
            {
                return AgentActionPerformance.Rejected(
                    "lease_revoked");
            }
            return performance
                ?? AgentActionPerformance.Rejected(
                    "internal_error");
        }

        public void Dispose()
        {
            lock (_lifecycleSync)
                _disposed = true;
        }

        private AgentActionPerformance PerformOnUi(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease,
            CancellationToken cancellationToken)
        {
            if (cancellationToken.IsCancellationRequested)
            {
                return AgentActionPerformance.Rejected(
                    "lease_revoked");
            }

            SessionSurfaceRegistrySnapshot snapshot;
            try
            {
                snapshot = _snapshotProvider();
            }
            catch
            {
                return AgentActionPerformance.Rejected(
                    "internal_error");
            }
            if (!TryValidateCurrentBinding(
                    snapshot,
                    context,
                    action,
                    lease,
                    out LauncherAgentExactTargetBinding
                        exactBinding,
                    out string reasonCode))
            {
                return AgentActionPerformance.Rejected(
                    reasonCode);
            }

            lock (_lifecycleSync)
            {
                if (_disposed
                    || cancellationToken
                        .IsCancellationRequested)
                {
                    return AgentActionPerformance.Rejected(
                        "lease_revoked");
                }
                try
                {
                    return DispatchOnUi(
                        context,
                        action,
                        lease,
                        exactBinding);
                }
                catch
                {
                    return AgentActionPerformance.Rejected(
                        "internal_error");
                }
            }
        }

        private AgentActionPerformance DispatchOnUi(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease,
            LauncherAgentExactTargetBinding exactBinding)
        {
            switch (action.Operation)
            {
                case AgentCapabilitiesV1.ActivateWindow:
                    if (!_activateByTarget.TryGetValue(
                            action.TargetId,
                            out Func<
                                LauncherAgentExactTargetBinding,
                                bool> activate))
                    {
                        return AgentActionPerformance.Rejected(
                            "unsupported_for_surface");
                    }
                    if (exactBinding == null
                        || exactBinding.WindowHandle == 0
                        || exactBinding.OwnerProcess == null
                        || !activate(exactBinding))
                    {
                        return AgentActionPerformance.Rejected(
                            "foreground_mismatch");
                    }
                    SessionSurfaceRegistrySnapshot
                        postDispatchSnapshot;
                    try
                    {
                        postDispatchSnapshot =
                            _snapshotProvider();
                    }
                    catch
                    {
                        return AgentActionPerformance.Unknown(
                            "reconcile_required",
                            ReconcileKind.VisualAmbiguous);
                    }
                    if (!TryValidateCurrentBinding(
                            postDispatchSnapshot,
                            context,
                            action,
                            lease,
                            out LauncherAgentExactTargetBinding
                                postDispatchBinding,
                            out _)
                        || !exactBinding.IsExact(
                            postDispatchBinding))
                    {
                        return AgentActionPerformance.Unknown(
                            "reconcile_required",
                            ReconcileKind.VisualAmbiguous);
                    }
                    return Completed(
                        action,
                        focusVerified: true);

                case AgentCapabilitiesV1.SessionShutdown:
                    if (!_prepareSafeExit(action.ActionId))
                    {
                        return AgentActionPerformance.Rejected(
                            "human_intervention_required");
                    }
                    return Completed(
                        action,
                        focusVerified: false,
                        reasonCode: "shutdown_requested",
                        responseCompletion:
                            new AgentRuntimeResponseCompletion(
                                delegate
                                {
                                    RunResponseCompletionOnUi(
                                        () => _completeSafeExit(
                                            action.ActionId));
                                },
                                delegate
                                {
                                    RunResponseCompletionOnUi(
                                        () => _abortSafeExit(
                                            action.ActionId));
                                }));

                case AgentCapabilitiesV1.LifecycleReveal:
                    _revealLifecycle();
                    return Completed(
                        action,
                        focusVerified: false);

                case AgentCapabilitiesV1.LifecycleCancel:
                    _cancelLifecycle();
                    return Completed(
                        action,
                        focusVerified: false);

                case AgentCapabilitiesV1.PanelOpen:
                    if (!TryReadPanel(
                            action.Arguments,
                            out string panel))
                    {
                        return AgentActionPerformance.Rejected(
                            "arguments_invalid");
                    }
                    if (!_tryOpenPanel(panel))
                    {
                        return AgentActionPerformance.Rejected(
                            "unsupported_for_surface");
                    }
                    return Completed(
                        action,
                        focusVerified: false);

                default:
                    return AgentActionPerformance.Rejected(
                        "operation_invalid");
            }
        }

        private static AgentActionPerformance Completed(
            ActionEnvelope action,
            bool focusVerified,
            string reasonCode = "none",
            AgentRuntimeResponseCompletion responseCompletion = null)
        {
            return AgentActionPerformance.Completed(
                ActionOutcome.InputDispatched,
                EvidenceKind.BrokerDispatch,
                action.TargetId,
                focusVerified,
                reasonCode: reasonCode,
                responseCompletion: responseCompletion);
        }

        private void RunResponseCompletionOnUi(Action callback)
        {
            bool invoked = _marshalToUi(
                    callback,
                    CancellationToken.None)
                .GetAwaiter()
                .GetResult();
            if (!invoked)
            {
                throw new InvalidOperationException(
                    "ui_dispatch_unavailable");
            }
        }

        private static bool TryValidateCurrentBinding(
            SessionSurfaceRegistrySnapshot snapshot,
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease,
            out LauncherAgentExactTargetBinding exactBinding,
            out string reasonCode)
        {
            exactBinding = null;
            if (context.Principal == null
                || !string.Equals(
                    action.LeaseId,
                    lease.LeaseId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    context.Principal.CredentialId,
                    lease.CredentialId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    context.Principal.ClientInstanceId,
                    lease.OwnerClientId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    context.Principal.SecurityPrincipalId,
                    lease.SecurityPrincipalId,
                    StringComparison.Ordinal))
            {
                reasonCode = "lease_owner_mismatch";
                return false;
            }
            if (lease.State == WriteLeaseState.Expired)
            {
                reasonCode = "lease_expired";
                return false;
            }
            if (lease.State == WriteLeaseState.Released
                || lease.State == WriteLeaseState.Revoked)
            {
                reasonCode = "lease_revoked";
                return false;
            }
            WriteLeaseKind requiredKind =
                action.Operation
                    == AgentCapabilitiesV1.SessionShutdown
                    ? WriteLeaseKind.Shutdown
                    : WriteLeaseKind.GuiInput;
            if (lease.Kind != requiredKind
                || !lease.Capabilities.Contains(
                    action.Operation,
                    StringComparer.Ordinal)
                || !context.Principal.AllowsCapability(
                    action.Operation))
            {
                reasonCode = "capability_denied";
                return false;
            }
            if (requiredKind == WriteLeaseKind.Shutdown
                && (lease.Capabilities.Count != 1
                    || lease.TargetScope.Count != 1
                    || lease.ActionLimit != 1))
            {
                reasonCode = "capability_denied";
                return false;
            }
            if (!string.Equals(
                    lease.SessionId,
                    action.SessionId,
                    StringComparison.Ordinal))
            {
                reasonCode = "session_mismatch";
                return false;
            }
            if (!lease.TargetScope.Contains(
                    action.TargetId,
                    StringComparer.Ordinal)
                || !context.Principal.AllowsTarget(
                    action.TargetId))
            {
                reasonCode = "observation_scope_mismatch";
                return false;
            }
            if (lease.LifecycleGeneration
                    != action.ExpectedLifecycleGeneration)
            {
                reasonCode = "stale_lifecycle";
                return false;
            }

            SessionSnapshot session = snapshot?.FindSession(
                action.SessionId);
            if (session == null)
            {
                reasonCode = "session_not_found";
                return false;
            }
            if (session.LifecycleGeneration
                    != action.ExpectedLifecycleGeneration
                || session.LifecycleGeneration
                    != lease.LifecycleGeneration)
            {
                reasonCode = "stale_lifecycle";
                return false;
            }
            if (!string.Equals(
                    session.AttemptId,
                    action.ExpectedAttemptId,
                    StringComparison.Ordinal)
                || session.AttemptGeneration
                    != action.ExpectedAttemptGeneration)
            {
                reasonCode = "stale_attempt";
                return false;
            }

            SessionSurfaceSnapshot surface = session.Surfaces
                .FirstOrDefault(candidate => string.Equals(
                    candidate.TargetId,
                    action.TargetId,
                    StringComparison.Ordinal));
            if (surface == null)
            {
                reasonCode = "target_not_found";
                return false;
            }
            if (surface.SafetyKind
                != AgentTargetSafetyKind.RuntimeOwned)
            {
                reasonCode =
                    "human_only_security_surface";
                return false;
            }
            if (requiredKind == WriteLeaseKind.Shutdown
                && surface.Kind != SurfaceKind.Launcher)
            {
                reasonCode = "unsupported_for_surface";
                return false;
            }
            if (surface.SurfaceEpoch
                != action.ExpectedSurfaceEpoch)
            {
                reasonCode = "stale_surface";
                return false;
            }
            if (surface.CoordinateSpaceVersion
                != action.ExpectedCoordinateSpaceVersion)
            {
                reasonCode =
                    "stale_coordinate_space";
                return false;
            }
            if (session.FocusEpoch
                != action.ExpectedFocusEpoch)
            {
                reasonCode = "stale_focus";
                return false;
            }
            if (session.ModalEpoch
                != action.ExpectedModalEpoch)
            {
                reasonCode = "stale_modal";
                return false;
            }
            if (!string.Equals(
                    session.PanelInstanceIdForTarget(
                        surface.TargetId),
                    action.ExpectedPanelInstanceId,
                    StringComparison.Ordinal))
            {
                reasonCode =
                    "stale_panel_instance";
                return false;
            }
            if (action.ExpectedDocumentGeneration.HasValue
                && surface.DocumentGeneration
                    != action.ExpectedDocumentGeneration)
            {
                reasonCode = "stale_document";
                return false;
            }
            if (action.ExpectedSemanticGeneration.HasValue
                && surface.SemanticGeneration
                    != action.ExpectedSemanticGeneration)
            {
                reasonCode = "stale_semantic_node";
                return false;
            }

            exactBinding =
                new LauncherAgentExactTargetBinding(
                    session.SessionId,
                    session.LifecycleGeneration,
                    session.AttemptId,
                    session.AttemptGeneration,
                    surface.TargetId,
                    surface.WindowHandle,
                    surface.OwnerProcess,
                    surface.SurfaceEpoch,
                    surface.CoordinateSpaceVersion);
            reasonCode = null;
            return true;
        }

        private static bool TryReadPanel(
            JsonElement arguments,
            out string panel)
        {
            panel = null;
            if (arguments.ValueKind != JsonValueKind.Object
                || !arguments.TryGetProperty(
                    "panel",
                    out JsonElement value)
                || value.ValueKind != JsonValueKind.String)
            {
                return false;
            }
            panel = value.GetString();
            return !string.IsNullOrWhiteSpace(panel);
        }

        private bool IsDisposed()
        {
            lock (_lifecycleSync)
                return _disposed;
        }

        private static bool IsSupported(string operation)
        {
            return operation
                    == AgentCapabilitiesV1.ActivateWindow
                || operation
                    == AgentCapabilitiesV1.SessionShutdown
                || operation
                    == AgentCapabilitiesV1.LifecycleReveal
                || operation
                    == AgentCapabilitiesV1.LifecycleCancel
                || operation
                    == AgentCapabilitiesV1.PanelOpen;
        }

        private static IReadOnlyDictionary<
            string,
            Func<LauncherAgentExactTargetBinding, bool>>
            FreezeActivators(
                IReadOnlyDictionary<
                    string,
                    Func<LauncherAgentExactTargetBinding, bool>>
                        source)
        {
            if (source == null)
                throw new ArgumentNullException(nameof(source));
            var copy = new Dictionary<
                string,
                Func<LauncherAgentExactTargetBinding, bool>>(
                    StringComparer.Ordinal);
            foreach (KeyValuePair<
                string,
                Func<LauncherAgentExactTargetBinding, bool>> pair
                in source)
            {
                if (string.IsNullOrWhiteSpace(pair.Key)
                    || pair.Value == null
                    || !copy.TryAdd(
                        pair.Key,
                        pair.Value))
                {
                    throw new ArgumentException(
                        "Exact target activators are invalid.",
                        nameof(source));
                }
            }
            return copy;
        }
    }
}
