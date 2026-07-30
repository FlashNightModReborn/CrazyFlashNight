using System;
using System.Linq;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;
using CF7Launcher.AgentRuntime.Sessions;

namespace CF7Launcher.AgentRuntime.Gateway
{
    /// <summary>
    /// Activates a GUI lease only after binding it to the current
    /// Launcher-owned target generations and the healthy low-level guard.
    /// Domain transactions do not enter the native-input containment path.
    /// </summary>
    internal sealed class NativeInputWriteLeaseLifecycle
        : IAgentWriteLeaseLifecycle
    {
        private readonly object _sync = new object();
        private readonly SessionNativeInputAuthority _targets;
        private readonly InputSafetyStateMachine _safety;
        private readonly NativeInputGuard _guard;

        public NativeInputWriteLeaseLifecycle(
            SessionNativeInputAuthority targets,
            InputSafetyStateMachine safety,
            NativeInputGuard guard)
        {
            _targets = targets
                ?? throw new ArgumentNullException(nameof(targets));
            _safety = safety
                ?? throw new ArgumentNullException(nameof(safety));
            _guard = guard
                ?? throw new ArgumentNullException(nameof(guard));
        }

        public bool TryActivate(
            WriteLease lease,
            out string reasonCode)
        {
            if (lease == null)
                throw new ArgumentNullException(nameof(lease));
            if (lease.Kind == WriteLeaseKind.Shutdown)
            {
                return _guard.TryAuthorizeShutdownLease(
                    out reasonCode);
            }
            if (lease.Kind != WriteLeaseKind.GuiInput)
            {
                reasonCode = null;
                return true;
            }
            if (lease.TargetScope.Count != 1)
            {
                reasonCode = "target_scope_denied";
                return false;
            }

            lock (_sync)
            {
                string targetId = lease.TargetScope.Single();
                if (!_targets.TryResolve(
                        lease.SessionId,
                        targetId,
                        out NativeInputTargetSnapshot target,
                        out reasonCode))
                {
                    return false;
                }
                if (target.Epochs.LifecycleGeneration
                        != checked((long)lease.LifecycleGeneration))
                {
                    reasonCode = "stale_observation";
                    return false;
                }
                if (target.SecurityModalLatched)
                {
                    reasonCode =
                        "human_only_security_surface";
                    return false;
                }
                if (!target.Visible || target.Minimized)
                {
                    reasonCode = "target_minimized";
                    return false;
                }

                if (_guard.TryGetBoundLease(
                        out string boundSessionId,
                        out string boundLeaseId))
                {
                    if (!string.Equals(
                            boundSessionId,
                            lease.SessionId,
                            StringComparison.Ordinal))
                    {
                        reasonCode =
                            "write_lease_already_held";
                        return false;
                    }
                    if (string.Equals(
                            boundLeaseId,
                            lease.LeaseId,
                            StringComparison.Ordinal))
                    {
                        reasonCode = null;
                        return true;
                    }

                    // The broker already proved this is the only active lease
                    // for the session. A different guard binding is therefore
                    // an expired/revoked predecessor that must release only
                    // its own held controls before replacement.
                    _guard.RevokeBoundLease(
                        boundSessionId,
                        boundLeaseId,
                        "lease_expired");
                }

                InputEpochSnapshot current =
                    _safety.CurrentEpochs;
                if (current == null)
                {
                    _safety.SetInitialAuthoritativeState(
                        target.Epochs,
                        target.TargetId);
                }
                else if (!NativeInputEpochComparer.ExactEquals(
                             current,
                             target.Epochs))
                {
                    _guard.FailAndPreempt(
                        "stale_observation");
                    _safety.AdvanceAuthoritativeState(
                        target.Epochs,
                        target.TargetId,
                        "stale_observation");
                }

                try
                {
                    _guard.BindLease(
                        lease.SessionId,
                        lease.LeaseId);
                    reasonCode = null;
                    return true;
                }
                catch (InvalidOperationException exception)
                {
                    reasonCode = string.IsNullOrWhiteSpace(
                            exception.Message)
                        ? "input_guard_unhealthy"
                        : exception.Message;
                    return false;
                }
            }
        }

        public void Release(WriteLease lease)
        {
            if (lease == null
                || lease.Kind
                    != WriteLeaseKind.GuiInput)
            {
                return;
            }
            _guard.RevokeBoundLease(
                lease.SessionId,
                lease.LeaseId,
                lease.RevokeReason ?? "client_released");
        }
    }
}
