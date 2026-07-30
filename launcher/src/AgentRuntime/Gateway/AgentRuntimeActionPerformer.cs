using System;
using System.Collections.Generic;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Domain;
using CF7Launcher.AgentRuntime.Input;
using CF7Launcher.AgentRuntime.NativeInput;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Gateway
{
    internal interface IAgentStructuredActionHost
    {
        Task<AgentActionPerformance> PerformAsync(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease,
            CancellationToken cancellationToken);
    }

    internal sealed class FailClosedAgentStructuredActionHost
        : IAgentStructuredActionHost
    {
        public Task<AgentActionPerformance> PerformAsync(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease,
            CancellationToken cancellationToken)
        {
            return Task.FromResult(
                AgentActionPerformance.Rejected(
                    "unsupported_for_surface"));
        }
    }

    internal interface INativeScreenCoordinateNormalizer
    {
        bool TryNormalize(
            NativeScreenPoint point,
            out int absoluteX,
            out int absoluteY);
    }

    internal sealed class WindowsNativeScreenCoordinateNormalizer
        : INativeScreenCoordinateNormalizer
    {
        private const int SmXVirtualScreen = 76;
        private const int SmYVirtualScreen = 77;
        private const int SmCxVirtualScreen = 78;
        private const int SmCyVirtualScreen = 79;

        public bool TryNormalize(
            NativeScreenPoint point,
            out int absoluteX,
            out int absoluteY)
        {
            int left = GetSystemMetrics(SmXVirtualScreen);
            int top = GetSystemMetrics(SmYVirtualScreen);
            int width = GetSystemMetrics(SmCxVirtualScreen);
            int height = GetSystemMetrics(SmCyVirtualScreen);
            absoluteX = 0;
            absoluteY = 0;
            if (width <= 1
                || height <= 1
                || point.X < left
                || point.Y < top
                || (long)point.X >= (long)left + width
                || (long)point.Y >= (long)top + height)
            {
                return false;
            }
            absoluteX = checked((int)Math.Round(
                (point.X - (double)left)
                * 65535d
                / (width - 1),
                MidpointRounding.AwayFromZero));
            absoluteY = checked((int)Math.Round(
                (point.Y - (double)top)
                * 65535d
                / (height - 1),
                MidpointRounding.AwayFromZero));
            return absoluteX is >= 0 and <= 65535
                && absoluteY is >= 0 and <= 65535;
        }

        [DllImport("user32.dll")]
        private static extern int GetSystemMetrics(int index);
    }

    /// <summary>
    /// Routes the frozen action methods into native containment, structured
    /// Launcher adapters or the Hairdresser domain transaction. A successful
    /// native result proves broker dispatch only; it never fabricates target
    /// effect evidence.
    /// </summary>
    internal sealed class CompositeAgentRuntimeActionPerformer
        : IAgentRuntimeActionPerformer
    {
        private const uint MouseMove = 0x0001;
        private const uint MouseLeftDown = 0x0002;
        private const uint MouseLeftUp = 0x0004;
        private const uint MouseRightDown = 0x0008;
        private const uint MouseRightUp = 0x0010;
        private const uint MouseMiddleDown = 0x0020;
        private const uint MouseMiddleUp = 0x0040;
        private const uint MouseWheel = 0x0800;
        private const uint MouseHWheel = 0x1000;
        private const uint MouseVirtualDesk = 0x4000;
        private const uint MouseAbsolute = 0x8000;
        private const uint KeyExtended = 0x0001;
        private const int MaximumTextCodeUnitsPerBatch = 64;

        private readonly NativeInputExecutor _nativeInput;
        private readonly NativeInputGuard _guard;
        private readonly InputSafetyStateMachine _safety;
        private readonly AgentObservationEnvelopeStore _observations;
        private readonly INativeScreenCoordinateNormalizer
            _coordinates;
        private readonly IAgentStructuredActionHost
            _structuredHost;
        private readonly HairAppearanceModifierTransaction _hair;
        private readonly IAgentHairPreviewStore _hairPreviews;
        private readonly IAgentHairDomainTargetAuthority
            _hairTargets;

        public CompositeAgentRuntimeActionPerformer(
            NativeInputExecutor nativeInput,
            NativeInputGuard guard,
            InputSafetyStateMachine safety,
            AgentObservationEnvelopeStore observations,
            IAgentStructuredActionHost structuredHost,
            HairAppearanceModifierTransaction hair,
            IAgentHairPreviewStore hairPreviews,
            IAgentHairDomainTargetAuthority hairTargets,
            INativeScreenCoordinateNormalizer coordinates = null)
        {
            _nativeInput = nativeInput
                ?? throw new ArgumentNullException(
                    nameof(nativeInput));
            _guard = guard
                ?? throw new ArgumentNullException(nameof(guard));
            _safety = safety
                ?? throw new ArgumentNullException(nameof(safety));
            _observations = observations
                ?? throw new ArgumentNullException(
                    nameof(observations));
            _structuredHost = structuredHost
                ?? throw new ArgumentNullException(
                    nameof(structuredHost));
            _hair = hair
                ?? throw new ArgumentNullException(nameof(hair));
            _hairPreviews = hairPreviews
                ?? throw new ArgumentNullException(
                    nameof(hairPreviews));
            _hairTargets = hairTargets
                ?? throw new ArgumentNullException(
                    nameof(hairTargets));
            _coordinates = coordinates
                ?? new WindowsNativeScreenCoordinateNormalizer();
        }

        public Task<AgentActionPerformance> PerformAsync(
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

            return action.Operation switch
            {
                AgentCapabilitiesV1.Click
                    when action.NodeId != null =>
                    _structuredHost.PerformAsync(
                        context,
                        action,
                        lease,
                        cancellationToken),
                AgentCapabilitiesV1.Click =>
                    Task.FromResult(
                        PerformClick(context, action, lease)),
                AgentCapabilitiesV1.PressKey =>
                    Task.FromResult(
                        PerformPressKey(action, lease)),
                AgentCapabilitiesV1.TypeText =>
                    PerformTypeTextAsync(
                        action,
                        lease,
                        cancellationToken),
                AgentCapabilitiesV1.Scroll =>
                    Task.FromResult(
                        PerformScroll(context, action, lease)),
                AgentCapabilitiesV1.Drag =>
                    PerformDragAsync(
                        context,
                        action,
                        lease,
                        cancellationToken),
                AgentCapabilitiesV1.SetValue or
                AgentCapabilitiesV1.PerformSecondaryAction or
                AgentCapabilitiesV1.ActivateWindow or
                AgentCapabilitiesV1.SessionShutdown or
                AgentCapabilitiesV1.LifecycleReveal or
                AgentCapabilitiesV1.LifecycleCancel or
                AgentCapabilitiesV1.PanelOpen =>
                    _structuredHost.PerformAsync(
                        context,
                        action,
                        lease,
                        cancellationToken),
                AgentMethodsV1.HairCommit or
                AgentMethodsV1.HairRestore =>
                    PerformHairAsync(
                        context,
                        action,
                        lease,
                        cancellationToken),
                _ => Task.FromResult(
                    AgentActionPerformance.Rejected(
                        "operation_invalid"))
            };
        }

        private AgentActionPerformance PerformClick(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease)
        {
            if (!TryResolvePoint(
                    context,
                    action,
                    "x",
                    "y",
                    out NativeScreenPoint point,
                    out int normalizedX,
                    out int normalizedY,
                    out string reasonCode))
            {
                return AgentActionPerformance.Rejected(
                    reasonCode);
            }
            string button =
                action.Arguments.GetProperty("button")
                    .GetString();
            int count =
                action.Arguments.GetProperty("clickCount")
                    .GetInt32();
            if (!TryGetButton(
                    button,
                    out uint downFlag,
                    out uint upFlag,
                    out string controlId))
            {
                return AgentActionPerformance.Rejected(
                    "arguments_invalid");
            }
            var packets = new List<NativeInputPacket>
            {
                AbsoluteMove(normalizedX, normalizedY)
            };
            for (int i = 0; i < count; i++)
            {
                packets.Add(
                    NativeInputPacket.Mouse(
                        normalizedX,
                        normalizedY,
                        0,
                        downFlag,
                        controlId,
                        NativeControlTransition.Down));
                packets.Add(
                    NativeInputPacket.Mouse(
                        normalizedX,
                        normalizedY,
                        0,
                        upFlag,
                        controlId,
                        NativeControlTransition.Up));
            }
            return DispatchNative(
                action,
                lease,
                packets,
                new[] { point });
        }

        private AgentActionPerformance PerformPressKey(
            ActionEnvelope action,
            WriteLease lease)
        {
            string key =
                action.Arguments.GetProperty("key").GetString();
            string[] modifiers = JsonSerializer
                .Deserialize<string[]>(
                    action.Arguments.GetProperty("modifiers")
                        .GetRawText(),
                    AgentProtocolV1.JsonOptions)
                ?? Array.Empty<string>();
            int repeat =
                action.Arguments.GetProperty("repeat")
                    .GetInt32();
            if (!TryResolveKey(
                    key,
                    out ushort virtualKey,
                    out bool extended)
                || IsSystemShortcut(
                    key,
                    modifiers))
            {
                return AgentActionPerformance.Rejected(
                    "arguments_invalid");
            }

            var packets = new List<NativeInputPacket>();
            foreach (string modifier
                in OrderedModifiers(modifiers))
            {
                ushort modifierKey =
                    ModifierVirtualKey(modifier);
                packets.Add(
                    NativeInputPacket.Key(
                        modifierKey,
                        0,
                        0,
                        false));
            }
            for (int i = 0; i < repeat; i++)
            {
                packets.Add(
                    NativeInputPacket.Key(
                        virtualKey,
                        0,
                        extended ? KeyExtended : 0,
                        false));
                packets.Add(
                    NativeInputPacket.Key(
                        virtualKey,
                        0,
                        extended ? KeyExtended : 0,
                        true));
            }
            string[] ordered = OrderedModifiers(
                modifiers);
            for (int i = ordered.Length - 1;
                i >= 0;
                i--)
            {
                packets.Add(
                    NativeInputPacket.Key(
                        ModifierVirtualKey(ordered[i]),
                        0,
                        0,
                        true));
            }
            return DispatchNative(
                action,
                lease,
                packets,
                Array.Empty<NativeScreenPoint>());
        }

        private async Task<AgentActionPerformance>
            PerformTypeTextAsync(
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
        {
            string text;
            try
            {
                text = action.Arguments
                    .GetProperty("text")
                    .GetString();
            }
            catch (InvalidOperationException)
            {
                return AgentActionPerformance.Rejected(
                    "arguments_invalid");
            }
            if (!TryPlanTypeTextCodeUnitBatches(
                    text,
                    out int[] batchCodeUnitCounts))
            {
                return AgentActionPerformance.Rejected(
                    "arguments_invalid");
            }
            bool anyDispatched = false;
            int offset = 0;
            foreach (int count in batchCodeUnitCounts)
            {
                cancellationToken.ThrowIfCancellationRequested();
                var packets = new List<NativeInputPacket>(
                    count * 2);
                for (int i = 0; i < count; i++)
                {
                    char value = text[offset + i];
                    packets.Add(
                        NativeInputPacket.Unicode(
                            value,
                            false));
                    packets.Add(
                        NativeInputPacket.Unicode(
                            value,
                            true));
                }
                AgentActionPerformance result = DispatchNative(
                    action,
                    lease,
                    packets,
                    Array.Empty<NativeScreenPoint>(),
                    requireTargetFocus: true);
                if (result.Outcome
                    != ActionOutcome.InputDispatched)
                {
                    if (anyDispatched
                        && result.Outcome
                            == ActionOutcome.Rejected)
                    {
                        _guard.FailAndPreempt(
                            result.ReasonCode);
                        return AgentActionPerformance.Unknown(
                            "reconcile_required",
                            ReconcileKind.VisualAmbiguous);
                    }
                    return result;
                }
                anyDispatched = true;
                offset += count;
                await Task.Yield();
            }
            return AgentActionPerformance.Completed(
                ActionOutcome.InputDispatched,
                EvidenceKind.BrokerDispatch,
                action.TargetId,
                true);
        }

        internal static bool TryPlanTypeTextCodeUnitBatches(
            string text,
            out int[] batchCodeUnitCounts)
        {
            batchCodeUnitCounts = Array.Empty<int>();
            if (string.IsNullOrEmpty(text))
                return false;

            for (int i = 0; i < text.Length; i++)
            {
                char value = text[i];
                if (char.IsHighSurrogate(value))
                {
                    if (i + 1 >= text.Length
                        || !char.IsLowSurrogate(text[i + 1]))
                    {
                        return false;
                    }
                    i++;
                }
                else if (char.IsLowSurrogate(value))
                {
                    return false;
                }
            }

            var batches = new List<int>();
            for (int offset = 0;
                offset < text.Length;)
            {
                int count = Math.Min(
                    MaximumTextCodeUnitsPerBatch,
                    text.Length - offset);
                if (offset + count < text.Length
                    && char.IsHighSurrogate(
                        text[offset + count - 1]))
                {
                    count--;
                }
                batches.Add(count);
                offset += count;
            }
            batchCodeUnitCounts = batches.ToArray();
            return true;
        }

        private AgentActionPerformance PerformScroll(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            WriteLease lease)
        {
            if (!TryResolvePoint(
                    context,
                    action,
                    "x",
                    "y",
                    out NativeScreenPoint point,
                    out int normalizedX,
                    out int normalizedY,
                    out string reasonCode))
            {
                return AgentActionPerformance.Rejected(
                    reasonCode);
            }
            int deltaX = action.Arguments
                .GetProperty("deltaX").GetInt32();
            int deltaY = action.Arguments
                .GetProperty("deltaY").GetInt32();
            var packets = new List<NativeInputPacket>
            {
                AbsoluteMove(normalizedX, normalizedY)
            };
            if (deltaY != 0)
            {
                packets.Add(
                    NativeInputPacket.Mouse(
                        normalizedX,
                        normalizedY,
                        unchecked((uint)deltaY),
                        MouseWheel));
            }
            if (deltaX != 0)
            {
                packets.Add(
                    NativeInputPacket.Mouse(
                        normalizedX,
                        normalizedY,
                        unchecked((uint)deltaX),
                        MouseHWheel));
            }
            return DispatchNative(
                action,
                lease,
                packets,
                new[] { point });
        }

        private async Task<AgentActionPerformance>
            PerformDragAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
        {
            if (!TryResolvePoint(
                    context,
                    action,
                    "startX",
                    "startY",
                    out NativeScreenPoint start,
                    out int normalizedStartX,
                    out int normalizedStartY,
                    out string reasonCode)
                || !TryResolvePoint(
                    context,
                    action,
                    "endX",
                    "endY",
                    out NativeScreenPoint end,
                    out int normalizedEndX,
                    out int normalizedEndY,
                    out reasonCode))
            {
                return AgentActionPerformance.Rejected(
                    reasonCode);
            }
            int durationMs = action.Arguments
                .GetProperty("durationMs").GetInt32();
            bool pointerDown = false;
            try
            {
                AgentActionPerformance initial =
                    DispatchNative(
                        action,
                        lease,
                        new[]
                        {
                            AbsoluteMove(
                                normalizedStartX,
                                normalizedStartY),
                            NativeInputPacket.Mouse(
                                normalizedStartX,
                                normalizedStartY,
                                0,
                                MouseLeftDown,
                                "MouseLeft",
                                NativeControlTransition.Down)
                        },
                        new[] { start });
                if (initial.Outcome
                    != ActionOutcome.InputDispatched)
                {
                    return initial;
                }
                pointerDown = true;

                int steps = Math.Clamp(
                    (int)Math.Ceiling(
                        durationMs / 16d),
                    1,
                    625);
                int delayMs = Math.Max(
                    1,
                    durationMs / steps);
                for (int step = 1;
                    step < steps;
                    step++)
                {
                    await Task.Delay(
                            delayMs,
                            cancellationToken)
                        .ConfigureAwait(false);
                    double progress =
                        step / (double)steps;
                    NativeScreenPoint point = Lerp(
                        start,
                        end,
                        progress);
                    if (!_coordinates.TryNormalize(
                            point,
                            out int x,
                            out int y))
                    {
                        return UnknownAfterPointerDown(
                            "stale_coordinate_space");
                    }
                    AgentActionPerformance movement =
                        DispatchNative(
                            action,
                            lease,
                            new[] { AbsoluteMove(x, y) },
                            new[] { point });
                    if (movement.Outcome
                        != ActionOutcome.InputDispatched)
                    {
                        return UnknownAfterPointerDown(
                            movement.ReasonCode);
                    }
                }
                await Task.Delay(
                        Math.Max(
                            0,
                            durationMs
                            - delayMs * (steps - 1)),
                        cancellationToken)
                    .ConfigureAwait(false);
                AgentActionPerformance final =
                    DispatchNative(
                        action,
                        lease,
                        new[]
                        {
                            AbsoluteMove(
                                normalizedEndX,
                                normalizedEndY),
                            NativeInputPacket.Mouse(
                                normalizedEndX,
                                normalizedEndY,
                                0,
                                MouseLeftUp,
                                "MouseLeft",
                                NativeControlTransition.Up)
                        },
                        new[] { end });
                if (final.Outcome
                    != ActionOutcome.InputDispatched)
                {
                    return UnknownAfterPointerDown(
                        final.ReasonCode);
                }
                pointerDown = false;
                return final;
            }
            finally
            {
                if (pointerDown)
                {
                    _guard.FailAndPreempt(
                        cancellationToken.IsCancellationRequested
                            ? "deadline_exceeded"
                            : "reconcile_required");
                }
            }
        }

        private async Task<AgentActionPerformance>
            PerformHairAsync(
                AgentRuntimeDispatchContext context,
                ActionEnvelope action,
                WriteLease lease,
                CancellationToken cancellationToken)
        {
            if (lease.Kind
                    != WriteLeaseKind.DomainTransaction
                || !string.Equals(
                    lease.Operation,
                    action.Operation,
                    StringComparison.Ordinal))
            {
                return AgentActionPerformance.Rejected(
                    "operation_invalid");
            }
            string transactionId = action.Arguments
                .GetProperty("transactionId").GetString();
            string previewHash =
                action.Operation
                    == AgentMethodsV1.HairCommit
                    ? action.Arguments
                        .GetProperty("previewHash")
                        .GetString()
                    : lease.PreviewHash;
            string reasonCode = null;
            if (!string.Equals(
                    lease.PreviewHash,
                    previewHash,
                    StringComparison.OrdinalIgnoreCase)
                || !_hairPreviews.TryResolve(
                    context,
                    transactionId,
                    previewHash,
                    out string previewTargetId,
                    out HairAppearancePreview preview,
                    out reasonCode)
                || !string.Equals(
                    action.TargetId,
                    previewTargetId,
                    StringComparison.Ordinal)
                || !_hairTargets.TryAuthorize(
                    action.SessionId,
                    action.TargetId,
                    out reasonCode)
                || !string.Equals(
                    preview.Binding.SessionId,
                    action.SessionId,
                    StringComparison.Ordinal)
                || preview.Binding.LifecycleGeneration
                    != checked((long)
                        action.ExpectedLifecycleGeneration)
                || !string.Equals(
                    lease.ExpectedRevision,
                    preview.ExpectedRevision.ToString(
                        CultureInfo.InvariantCulture),
                    StringComparison.Ordinal))
            {
                return AgentActionPerformance.Rejected(
                    AgentRuntimeGateway.NormalizeReason(
                        reasonCode
                            ?? "domain_revision_conflict"));
            }

            HairTransactionResult result;
            if (action.Operation
                == AgentMethodsV1.HairCommit)
            {
                result = await _hair.CommitAsync(
                        preview,
                        action.Arguments
                            .GetProperty("consentToken")
                            .GetString(),
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            else
            {
                result = await _hair.RestoreAsync(
                        transactionId,
                        action.Arguments
                            .GetProperty("restoreToken")
                            .GetString(),
                        cancellationToken)
                    .ConfigureAwait(false);
            }
            return MapHairResult(action, result);
        }

        private static AgentActionPerformance MapHairResult(
            ActionEnvelope action,
            HairTransactionResult result)
        {
            if (result == null)
            {
                return AgentActionPerformance.Unknown(
                    "domain_commit_unknown",
                    ReconcileKind.DomainAuthoritative);
            }
            if (result.Outcome
                    == HairTransactionOutcome.DomainCommitted
                || result.Outcome
                    == HairTransactionOutcome.Restored)
            {
                return AgentActionPerformance.Completed(
                    ActionOutcome.DomainCommitted,
                    EvidenceKind.DomainAck,
                    action.TargetId,
                    false,
                    domainResult:
                        new HairDomainActionResult
                        {
                            TransactionId =
                                result.TransactionId,
                            PreviewHash =
                                result.PreviewHash,
                            RestoreToken =
                                result.RestoreToken,
                            RestoreExpiresAtUtc =
                                result
                                    .RestoreExpiresAtUtc
                        });
            }
            string reason =
                AgentRuntimeMethodDispatcher
                    .NormalizeHairReason(
                        result.ReasonCode);
            if (result.Outcome
                == HairTransactionOutcome.Unknown)
            {
                return AgentActionPerformance.Unknown(
                    reason,
                    result.ReconcileKind
                        == "manual_required"
                        ? ReconcileKind.ManualRequired
                        : ReconcileKind
                            .DomainAuthoritative);
            }
            return AgentActionPerformance.Rejected(reason);
        }

        private AgentActionPerformance UnknownAfterPointerDown(
            string reasonCode)
        {
            _guard.FailAndPreempt(
                string.IsNullOrWhiteSpace(reasonCode)
                    ? "reconcile_required"
                    : reasonCode);
            return AgentActionPerformance.Unknown(
                "reconcile_required",
                ReconcileKind.VisualAmbiguous);
        }

        private AgentActionPerformance DispatchNative(
            ActionEnvelope action,
            WriteLease lease,
            IReadOnlyList<NativeInputPacket> packets,
            IReadOnlyList<NativeScreenPoint> hitPoints,
            bool requireTargetFocus = false)
        {
            InputEpochSnapshot epochs;
            try
            {
                epochs = new InputEpochSnapshot(
                    action.SessionId,
                    checked((long)
                        action.ExpectedLifecycleGeneration),
                    action.ExpectedAttemptId,
                    checked((long)action
                        .ExpectedAttemptGeneration
                        .GetValueOrDefault()),
                    action.TargetId,
                    checked((long)
                        action.ExpectedSurfaceEpoch),
                    checked((long)action
                        .ExpectedCoordinateSpaceVersion),
                    action.ExpectedPanelInstanceId,
                    checked((long)action
                        .ExpectedDocumentGeneration
                        .GetValueOrDefault()),
                    checked((long)
                        action.ExpectedFocusEpoch),
                    checked((long)
                        action.ExpectedModalEpoch));
            }
            catch (OverflowException)
            {
                return AgentActionPerformance.Rejected(
                    "stale_observation");
            }
            NativeInputDispatchResult result =
                _nativeInput.Execute(
                    new NativeInputDispatchRequest
                    {
                        LeaseId = lease.LeaseId,
                        ExpectedEpochs = epochs,
                        ExpectedInputEpoch =
                            _safety.InputEpoch,
                        RequireTargetFocus =
                            requireTargetFocus,
                        Packets = packets,
                        PointerHitTestPoints = hitPoints
                    });
            if (result.Outcome
                == ActionOutcome.InputDispatched)
            {
                return AgentActionPerformance.Completed(
                    ActionOutcome.InputDispatched,
                    EvidenceKind.BrokerDispatch,
                    action.TargetId,
                    result.FocusVerified);
            }
            if (result.Outcome == ActionOutcome.Unknown)
            {
                return AgentActionPerformance.Unknown(
                    result.ReasonCode,
                    result.ReconcileKind);
            }
            return AgentActionPerformance.Rejected(
                result.ReasonCode);
        }

        private bool TryResolvePoint(
            AgentRuntimeDispatchContext context,
            ActionEnvelope action,
            string xName,
            string yName,
            out NativeScreenPoint point,
            out int normalizedX,
            out int normalizedY,
            out string reasonCode)
        {
            point = default;
            normalizedX = 0;
            normalizedY = 0;
            if (!_observations.TryGetFrame(
                    context,
                    action,
                    out FrameEnvelope frame,
                    out reasonCode))
            {
                return false;
            }
            int x = action.Arguments
                .GetProperty(xName).GetInt32();
            int y = action.Arguments
                .GetProperty(yName).GetInt32();
            if (x < 0
                || y < 0
                || x >= frame.Width
                || y >= frame.Height
                || frame.FrameToTargetContentTransform == null
                || frame.ContentRectPhysical == null)
            {
                reasonCode =
                    "stale_coordinate_space";
                return false;
            }
            AffineTransform transform =
                frame.FrameToTargetContentTransform;
            double frameX = x + 0.5d;
            double frameY = y + 0.5d;
            double contentX =
                transform.M11 * frameX
                + transform.M21 * frameY
                + transform.Dx;
            double contentY =
                transform.M12 * frameX
                + transform.M22 * frameY
                + transform.Dy;
            if (!double.IsFinite(contentX)
                || !double.IsFinite(contentY)
                || contentX < 0
                || contentY < 0
                || contentX
                    >= frame.ContentRectPhysical.Width
                || contentY
                    >= frame.ContentRectPhysical.Height)
            {
                reasonCode =
                    "stale_coordinate_space";
                return false;
            }
            long screenX = checked(
                (long)frame.ContentRectPhysical.X
                + (long)Math.Floor(contentX));
            long screenY = checked(
                (long)frame.ContentRectPhysical.Y
                + (long)Math.Floor(contentY));
            if (screenX < int.MinValue
                || screenX > int.MaxValue
                || screenY < int.MinValue
                || screenY > int.MaxValue)
            {
                reasonCode =
                    "stale_coordinate_space";
                return false;
            }
            point = new NativeScreenPoint(
                (int)screenX,
                (int)screenY);
            if (!_coordinates.TryNormalize(
                    point,
                    out normalizedX,
                    out normalizedY))
            {
                reasonCode =
                    "stale_coordinate_space";
                return false;
            }
            reasonCode = null;
            return true;
        }

        private static NativeInputPacket AbsoluteMove(
            int normalizedX,
            int normalizedY)
        {
            return NativeInputPacket.Mouse(
                normalizedX,
                normalizedY,
                0,
                MouseMove
                | MouseAbsolute
                | MouseVirtualDesk);
        }

        private static bool TryGetButton(
            string button,
            out uint down,
            out uint up,
            out string controlId)
        {
            switch (button)
            {
                case "primary":
                    down = MouseLeftDown;
                    up = MouseLeftUp;
                    controlId = "MouseLeft";
                    return true;
                case "secondary":
                    down = MouseRightDown;
                    up = MouseRightUp;
                    controlId = "MouseRight";
                    return true;
                case "middle":
                    down = MouseMiddleDown;
                    up = MouseMiddleUp;
                    controlId = "MouseMiddle";
                    return true;
                default:
                    down = 0;
                    up = 0;
                    controlId = null;
                    return false;
            }
        }

        private static string[] OrderedModifiers(
            IEnumerable<string> modifiers)
        {
            var requested = new HashSet<string>(
                modifiers ?? Array.Empty<string>(),
                StringComparer.Ordinal);
            var ordered = new List<string>(3);
            foreach (string candidate
                in new[] { "ctrl", "alt", "shift" })
            {
                if (requested.Contains(candidate))
                    ordered.Add(candidate);
            }
            return ordered.ToArray();
        }

        private static ushort ModifierVirtualKey(
            string modifier)
        {
            return modifier switch
            {
                "ctrl" => 0x11,
                "alt" => 0x12,
                "shift" => 0x10,
                _ => throw new InvalidOperationException(
                    "arguments_invalid")
            };
        }

        private static bool TryResolveKey(
            string key,
            out ushort virtualKey,
            out bool extended)
        {
            virtualKey = 0;
            extended = false;
            if (string.IsNullOrWhiteSpace(key))
                return false;
            string normalized = key.Trim().ToLowerInvariant();
            if (normalized.Length == 1)
            {
                char value = normalized[0];
                if (value is >= 'a' and <= 'z')
                {
                    virtualKey = (ushort)char.ToUpperInvariant(
                        value);
                    return true;
                }
                if (value is >= '0' and <= '9')
                {
                    virtualKey = value;
                    return true;
                }
            }
            if (normalized.Length is 2 or 3
                && normalized[0] == 'f'
                && int.TryParse(
                    normalized.Substring(1),
                    NumberStyles.None,
                    CultureInfo.InvariantCulture,
                    out int function)
                && function is >= 1 and <= 12)
            {
                virtualKey = checked(
                    (ushort)(0x70 + function - 1));
                return true;
            }
            (virtualKey, extended) = normalized switch
            {
                "backspace" => ((ushort)0x08, false),
                "tab" => ((ushort)0x09, false),
                "enter" => ((ushort)0x0D, false),
                "escape" => ((ushort)0x1B, false),
                "space" => ((ushort)0x20, false),
                "page_up" => ((ushort)0x21, true),
                "page_down" => ((ushort)0x22, true),
                "end" => ((ushort)0x23, true),
                "home" => ((ushort)0x24, true),
                "arrow_left" => ((ushort)0x25, true),
                "arrow_up" => ((ushort)0x26, true),
                "arrow_right" => ((ushort)0x27, true),
                "arrow_down" => ((ushort)0x28, true),
                "insert" => ((ushort)0x2D, true),
                "delete" => ((ushort)0x2E, true),
                _ => ((ushort)0, false)
            };
            return virtualKey != 0;
        }

        private static bool IsSystemShortcut(
            string key,
            IEnumerable<string> modifiers)
        {
            string normalized =
                key?.Trim().ToLowerInvariant();
            var set = new HashSet<string>(
                modifiers ?? Array.Empty<string>(),
                StringComparer.Ordinal);
            bool alt = set.Contains("alt");
            bool ctrl = set.Contains("ctrl");
            bool shift = set.Contains("shift");
            return (alt
                    && (normalized == "tab"
                        || normalized == "escape"
                        || normalized == "f4"
                        || normalized == "space"))
                || (ctrl && normalized == "escape")
                || (ctrl
                    && shift
                    && normalized == "escape")
                || (ctrl
                    && alt
                    && (normalized == "delete"
                        || normalized == "end"));
        }

        private static NativeScreenPoint Lerp(
            NativeScreenPoint start,
            NativeScreenPoint end,
            double progress)
        {
            return new NativeScreenPoint(
                checked((int)Math.Round(
                    start.X
                    + (end.X - (double)start.X)
                    * progress,
                    MidpointRounding.AwayFromZero)),
                checked((int)Math.Round(
                    start.Y
                    + (end.Y - (double)start.Y)
                    * progress,
                    MidpointRounding.AwayFromZero)));
        }
    }
}
