using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using CF7Launcher.Guardian;
using CF7Launcher.AgentRuntime.Input;

namespace CF7Launcher.AgentRuntime.NativeInput
{
    /// <summary>
    /// Performs the two pre-dispatch checks plus the hook-time check required
    /// around SendInput. A completed return never claims target effect; it
    /// reports only broker insertion.
    /// </summary>
    public sealed class NativeInputExecutor
    {
        private readonly InputSafetyStateMachine _safety;
        private readonly NativeInputGuard _guard;
        private readonly INativeInputWin32Facade _win32;
        private readonly IAuthoritativeNativeInputTarget _targets;

        public NativeInputExecutor(
            InputSafetyStateMachine safety,
            NativeInputGuard guard,
            INativeInputWin32Facade win32,
            IAuthoritativeNativeInputTarget targets)
        {
            _safety = safety
                ?? throw new ArgumentNullException(nameof(safety));
            _guard = guard
                ?? throw new ArgumentNullException(nameof(guard));
            _win32 = win32
                ?? throw new ArgumentNullException(nameof(win32));
            _targets = targets
                ?? throw new ArgumentNullException(nameof(targets));
        }

        public NativeInputDispatchResult Execute(
            NativeInputDispatchRequest request)
        {
            ValidateRequest(request);
            int requestedCount = request.Packets.Count;
            string sessionId = request.ExpectedEpochs.SessionId;

            if (!_guard.IsLeaseBound(
                    sessionId,
                    request.LeaseId))
            {
                return NativeInputDispatchResult.Rejected(
                    "lease_required",
                    requestedCount);
            }
            if (!_guard.TryPrepareForDispatch(
                    out string prepareReason))
            {
                return NativeInputDispatchResult.Rejected(
                    prepareReason,
                    requestedCount);
            }

            NativeInputTargetSnapshot firstTarget = null;
            NativeInputTargetSnapshot secondTarget = null;
            NativeInputTargetSnapshot hookTarget = null;
            try
            {
                string reasonCode = ValidateAuthoritativeState(
                    request,
                    null,
                    null,
                    out firstTarget,
                    out bool focusVerified);
                if (reasonCode != null)
                {
                    _guard.FailAndPreempt(reasonCode);
                    return NativeInputDispatchResult.Rejected(
                        reasonCode,
                        requestedCount,
                        focusVerified);
                }

                using NativeInputGuard.BatchHandle batch =
                    _guard.BeginBatch(
                        request.Packets,
                        hookEvent => ValidateAuthoritativeState(
                            request,
                            hookEvent,
                            Volatile.Read(ref hookTarget),
                            out _,
                            out _));

                if (!_guard.TryPrepareForDispatch(
                        out prepareReason))
                {
                    _guard.FailAndPreempt(
                        prepareReason,
                        batch.Batch);
                    return NativeInputDispatchResult.Rejected(
                        prepareReason,
                        requestedCount,
                        focusVerified);
                }

                // Capture a fresh exact-process signal after the hook batch
                // exists and immediately before SendInput's commit window.
                reasonCode = ValidateAuthoritativeState(
                    request,
                    null,
                    null,
                    out secondTarget,
                    out focusVerified);
                if (reasonCode != null)
                {
                    _guard.FailAndPreempt(
                        reasonCode,
                        batch.Batch);
                    return NativeInputDispatchResult.Rejected(
                        reasonCode,
                        requestedCount,
                        focusVerified);
                }
                Volatile.Write(ref hookTarget, secondTarget);

                int inserted;
                try
                {
                    inserted = _win32.SendInput(
                        request.Packets,
                        _guard.RuntimeInjectionTag);
                }
                catch
                {
                    inserted = 0;
                }

                if (inserted != requestedCount)
                {
                    _guard.FailAndPreempt(
                        "input_not_inserted",
                        batch.Batch);
                    LogManager.Log(
                        "[AgentRuntimeNativeInput] insertion_unknown stage=send_input"
                        + " requested=" + requestedCount
                        + " inserted=" + inserted);
                    return NativeInputDispatchResult
                        .InsertionUnknown(
                            requestedCount,
                            inserted,
                            focusVerified);
                }

                bool hookCompleted =
                    batch.WaitForHookObservation();
                if (!hookCompleted || batch.Batch.Blocked)
                {
                    string containmentReason =
                        batch.Batch.BlockReason
                        ?? "input_guard_unhealthy";
                    _guard.FailAndPreempt(
                        containmentReason,
                        batch.Batch);
                    string externalDiagnostic =
                        batch.Batch.ExternalDiagnostic;
                    LogManager.Log(
                        "[AgentRuntimeNativeInput] insertion_unknown stage=hook_observation"
                        + " requested=" + requestedCount
                        + " inserted=" + inserted
                        + " completed=" + hookCompleted
                        + " blocked=" + batch.Batch.Blocked
                        + " observed=" + batch.Batch.ObservedCount
                        + "/" + batch.Batch.PacketCount
                        + " reason=" + containmentReason
                        + externalDiagnostic);
                    return NativeInputDispatchResult
                        .InsertionUnknown(
                            requestedCount,
                            inserted,
                            focusVerified);
                }

                return NativeInputDispatchResult.Dispatched(
                    requestedCount);
            }
            finally
            {
                Volatile.Write(ref hookTarget, null);
                secondTarget?.Dispose();
                if (!ReferenceEquals(
                        firstTarget,
                        secondTarget))
                {
                    firstTarget?.Dispose();
                }
            }
        }

        private string ValidateAuthoritativeState(
            NativeInputDispatchRequest request,
            NativeLowLevelHookEvent hookEvent,
            NativeInputTargetSnapshot hookTarget,
            out NativeInputTargetSnapshot resolvedTarget,
            out bool focusVerified)
        {
            resolvedTarget = null;
            focusVerified = false;
            InputEpochSnapshot expected =
                request.ExpectedEpochs;
            NativeInputTargetSnapshot target;
            string resolveReason = null;
            if (hookEvent == null)
            {
                if (!_targets.TryResolveForDispatch(
                        expected.SessionId,
                        expected.TargetId,
                        out target,
                        out resolveReason))
                {
                    return string.IsNullOrWhiteSpace(resolveReason)
                        ? "target_not_found"
                        : resolveReason;
                }
            }
            else
            {
                target = hookTarget;
                if (target == null
                    || !_targets.TryValidateDispatchIdentity(
                        target,
                        out resolveReason))
                {
                    return string.IsNullOrWhiteSpace(resolveReason)
                        ? "surface_owner_unverifiable"
                        : resolveReason;
                }
            }
            resolvedTarget = target;
            if (!string.Equals(
                    target.SessionId,
                    expected.SessionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    target.TargetId,
                    expected.TargetId,
                    StringComparison.Ordinal))
            {
                return "session_mismatch";
            }
            if (!NativeInputEpochComparer.ExactEquals(
                    target.Epochs,
                    expected))
            {
                return "stale_observation";
            }
            if (target.SecurityModalLatched)
            {
                return "human_only_security_surface";
            }
            if (!target.Visible || target.Minimized)
            {
                return "target_minimized";
            }

            // The two caller-thread checks include exact process path/start,
            // desktop, and token probes. The low-level hook consumes only the
            // captured process handle, HWND ownership, in-memory authority,
            // foreground HWND, actual hit, and safety epochs.
            if (hookEvent == null
                && !TryValidateInteractiveDesktop())
            {
                return "desktop_unavailable";
            }
            if (hookEvent == null
                && !TryValidateIntegrity(
                    target,
                    out string integrityReason))
            {
                return integrityReason;
            }

            IntPtr foreground;
            try
            {
                foreground = _win32.GetForegroundWindow();
            }
            catch
            {
                foreground = IntPtr.Zero;
            }
            if (foreground != target.TopLevelHwnd)
            {
                return "foreground_mismatch";
            }
            focusVerified = true;
            if (hookEvent == null
                && request.RequireTargetFocus
                && !TryValidateTargetFocus(target))
            {
                focusVerified = false;
                return "stale_focus";
            }

            bool pointerAction = request.Packets.Any(
                packet => packet.Kind
                    == NativeInputPacketKind.Mouse);
            string hitTarget = null;
            if (pointerAction)
            {
                IEnumerable<NativeScreenPoint> points =
                    hookEvent?.ScreenPoint is NativeScreenPoint point
                        ? new[] { point }
                        : request.PointerHitTestPoints;
                foreach (NativeScreenPoint hitPoint in points)
                {
                    if (!TryValidateHit(
                            target,
                            hitPoint))
                    {
                        return "hit_test_mismatch";
                    }
                }
                hitTarget = target.TargetId;
            }

            InputSafetyDecision safetyDecision =
                _safety.EvaluateAtDispatch(
                    new InputDispatchCheck
                    {
                        ExpectedEpochs = expected,
                        ExpectedInputEpoch =
                            request.ExpectedInputEpoch,
                        ForegroundTargetId =
                            target.TargetId,
                        IsPointerAction = pointerAction,
                        HitTestTargetId = hitTarget
                    });
            return safetyDecision.Allowed
                ? null
                : safetyDecision.ReasonCode;
        }

        private bool TryValidateIntegrity(
            NativeInputTargetSnapshot target,
            out string reasonCode)
        {
            try
            {
                if (!_win32.TryGetProcessIntegrityLevel(
                        _win32.CurrentProcessId,
                        out int runtimeIntegrity)
                    || !_win32.TryGetProcessIntegrityLevel(
                        target.OwnerProcessId,
                        out int targetIntegrity))
                {
                    reasonCode = "input_guard_unhealthy";
                    return false;
                }
                if (targetIntegrity > runtimeIntegrity)
                {
                    reasonCode = "integrity_mismatch";
                    return false;
                }
                reasonCode = null;
                return true;
            }
            catch
            {
                reasonCode = "input_guard_unhealthy";
                return false;
            }
        }

        private bool TryValidateTargetFocus(
            NativeInputTargetSnapshot target)
        {
            try
            {
                return _win32.TryGetFocusedWindow(
                        target.TopLevelHwnd,
                        out IntPtr focused)
                    && focused != IntPtr.Zero
                    && (focused == target.TargetHwnd
                        || _win32.IsSameChildOrOwnedWindow(
                            target.TargetHwnd,
                            focused));
            }
            catch
            {
                return false;
            }
        }

        private bool TryValidateInteractiveDesktop()
        {
            try
            {
                return _win32
                    .IsInteractiveDesktopAvailable();
            }
            catch
            {
                return false;
            }
        }

        private bool TryValidateHit(
            NativeInputTargetSnapshot target,
            NativeScreenPoint point)
        {
            IntPtr hit;
            bool related;
            try
            {
                hit = _win32.WindowFromPoint(point);
                related = hit != IntPtr.Zero
                    && _win32.IsSameChildOrOwnedWindow(
                        target.TargetHwnd,
                        hit);
            }
            catch
            {
                return false;
            }
            return related
                && _targets.IsRegisteredInputWindow(
                    target,
                    hit);
        }

        private static void ValidateRequest(
            NativeInputDispatchRequest request)
        {
            if (request == null)
            {
                throw new ArgumentNullException(nameof(request));
            }
            if (string.IsNullOrWhiteSpace(request.LeaseId))
            {
                throw new ArgumentException(
                    "A lease ID is required.",
                    nameof(request));
            }
            if (request.ExpectedEpochs == null)
            {
                throw new ArgumentException(
                    "Expected epochs are required.",
                    nameof(request));
            }
            if (request.Packets == null
                || request.Packets.Count == 0
                || request.Packets.Any(
                    packet => packet == null))
            {
                throw new ArgumentException(
                    "A non-empty native input batch is required.",
                    nameof(request));
            }
            bool pointerAction = request.Packets.Any(
                packet => packet.Kind
                    == NativeInputPacketKind.Mouse);
            if (pointerAction
                && (request.PointerHitTestPoints == null
                    || request.PointerHitTestPoints.Count == 0))
            {
                throw new ArgumentException(
                    "Pointer input requires authoritative hit-test points.",
                    nameof(request));
            }
        }
    }
}
