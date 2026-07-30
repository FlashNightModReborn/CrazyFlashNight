using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.AgentRuntime.Observation
{
    /// <summary>
    /// Grant-gated, host-authoritative observation coordinator. Authorization
    /// and all target-scope checks finish before a frame source can be created
    /// or invoked.
    /// </summary>
    internal sealed class ObservationCaptureBroker : IDisposable
    {
        private readonly object _observationSync = new object();
        private readonly IAgentRuntimeClock _clock;
        private readonly ObservationGrantBroker _grants;
        private readonly IObservationSessionAuthority _sessions;
        private readonly IWindowFrameSourceFactory _frameSources;
        private readonly IFlashKeyframeFallback _flashFallback;
        private readonly PixelContentHandleStore _content;
        private readonly ConcurrentDictionary<string, CaptureSlot> _slots =
            new ConcurrentDictionary<string, CaptureSlot>(
                StringComparer.Ordinal);
        private readonly Dictionary<string, ObservationRecord> _observations =
            new Dictionary<string, ObservationRecord>(
                StringComparer.Ordinal);
        private int _disposed;

        public ObservationCaptureBroker(
            IAgentRuntimeClock clock,
            ObservationGrantBroker grants,
            IObservationSessionAuthority sessions,
            IWindowFrameSourceFactory frameSources,
            IFlashKeyframeFallback flashFallback,
            PixelContentHandleStore content)
        {
            _clock = clock ?? throw new ArgumentNullException(nameof(clock));
            _grants = grants
                ?? throw new ArgumentNullException(nameof(grants));
            _sessions = sessions
                ?? throw new ArgumentNullException(nameof(sessions));
            _frameSources = frameSources
                ?? throw new ArgumentNullException(nameof(frameSources));
            _flashFallback = flashFallback;
            _content = content
                ?? throw new ArgumentNullException(nameof(content));
        }

        public async Task<ObservationCaptureOutcome> CaptureAsync(
            ObservationCaptureRequest request,
            CancellationToken cancellationToken = default)
        {
            ThrowIfDisposed();
            string invalidReason = ValidateRequest(request);
            if (invalidReason != null)
                return ObservationCaptureOutcome.Rejected(invalidReason);

            // This is intentionally the first stateful operation. No session
            // metadata is resolved and no capture source is touched first.
            if (!_grants.TryAuthorize(
                    request.ObservationGrantId,
                    request.ClientInstanceId,
                    request.SecurityPrincipalId,
                    request.SessionId,
                    request.TargetId,
                    request.DataScope,
                    out ObservationGrant grant,
                    out string reasonCode))
            {
                return ObservationCaptureOutcome.Rejected(
                    reasonCode ?? "observation_grant_inactive");
            }

            if (!_sessions.TryCreateCapturePlan(
                    request.SessionId,
                    request.TargetId,
                    out ObservationCapturePlan plan,
                    out reasonCode))
            {
                return ObservationCaptureOutcome.Rejected(
                    reasonCode ?? "capture_unavailable");
            }
            if (plan == null
                || !string.Equals(
                    plan.SessionId,
                    request.SessionId,
                    StringComparison.Ordinal)
                || !string.Equals(
                    plan.PrimarySurface.TargetId,
                    request.TargetId,
                    StringComparison.Ordinal))
            {
                return ObservationCaptureOutcome.Rejected(
                    "target_not_authoritative");
            }

            // A business modal is its own frame/target. Every frame therefore
            // needs an explicit target scope under the same grant.
            foreach (ObservationSurfacePlan surface
                in plan.CaptureSurfaces)
            {
                if (!_grants.TryAuthorize(
                        request.ObservationGrantId,
                        request.ClientInstanceId,
                        request.SecurityPrincipalId,
                        request.SessionId,
                        surface.TargetId,
                        request.DataScope,
                        out _,
                        out reasonCode))
                {
                    return ObservationCaptureOutcome.Rejected(
                        reasonCode ?? "target_scope_denied");
                }
            }

            bool allowFallback =
                request.AllowValidatedFlashKeyframeFallback
                && grant.AllowEphemeralKeyframes
                && _flashFallback != null;
            Task<CapturedSurface>[] captureTasks =
                plan.CaptureSurfaces.Select(surface =>
                    CaptureSurfaceAsync(
                        plan,
                        surface,
                        allowFallback,
                        cancellationToken))
                    .ToArray();
            CapturedSurface[] captures;
            try
            {
                captures = await Task.WhenAll(captureTasks)
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                DisposeCompletedCaptures(captureTasks);
                return ObservationCaptureOutcome.Rejected(
                    "capture_cancelled");
            }
            catch
            {
                DisposeCompletedCaptures(captureTasks);
                return ObservationCaptureOutcome.Rejected(
                    "capture_unavailable");
            }

            try
            {
                CapturedSurface failed = captures.FirstOrDefault(
                    capture => !capture.Success);
                if (failed != null)
                {
                    return ObservationCaptureOutcome.Rejected(
                        failed.ReasonCode ?? "capture_unavailable");
                }

                if (!_sessions.TryValidateCapturePlan(
                        plan,
                        out reasonCode))
                {
                    return ObservationCaptureOutcome.Rejected(
                        reasonCode ?? "stale_surface");
                }

                string observationId =
                    OpaqueIdGenerator.Create("observation");
                var frames = new List<FrameEnvelope>(captures.Length);
                foreach (CapturedSurface capture in captures
                    .OrderBy(item => item.Surface.ZIndex)
                    .ThenBy(
                        item => item.Surface.TargetId,
                        StringComparer.Ordinal))
                {
                    string frameId = OpaqueIdGenerator.Create("frame");
                    var binding = new PixelContentBinding
                    {
                        ClientInstanceId = request.ClientInstanceId,
                        SecurityPrincipalId =
                            request.SecurityPrincipalId,
                        SessionId = request.SessionId,
                        ObservationGrantId =
                            request.ObservationGrantId,
                        ObservationId = observationId,
                        TargetId = capture.Surface.TargetId,
                        DataScope = request.DataScope
                    };
                    if (!_content.TryCreate(
                            binding,
                            capture.Result.Pixels,
                            out PixelContentHandleDescriptor handle,
                            out reasonCode))
                    {
                        _content.RevokeObservation(
                            observationId,
                            reasonCode ?? "capture_unavailable");
                        return ObservationCaptureOutcome.Rejected(
                            reasonCode ?? "capture_unavailable");
                    }
                    frames.Add(
                        CreateFrame(
                            frameId,
                            observationId,
                            capture,
                            handle));
                }

                foreach (ObservationSurfacePlan surface
                    in plan.CaptureSurfaces)
                {
                    if (!_grants.TryAuthorize(
                            request.ObservationGrantId,
                            request.ClientInstanceId,
                            request.SecurityPrincipalId,
                            request.SessionId,
                            surface.TargetId,
                            request.DataScope,
                            out _,
                            out reasonCode))
                    {
                        _content.RevokeObservation(
                            observationId,
                            reasonCode
                                ?? "observation_grant_inactive");
                        return ObservationCaptureOutcome.Rejected(
                            reasonCode
                                ?? "observation_grant_inactive");
                    }
                }
                if (!_sessions.TryValidateCapturePlan(
                        plan,
                        out reasonCode))
                {
                    _content.RevokeObservation(
                        observationId,
                        reasonCode ?? "stale_surface");
                    return ObservationCaptureOutcome.Rejected(
                        reasonCode ?? "stale_surface");
                }

                ObservationEnvelope envelope = CreateEnvelope(
                    request,
                    plan,
                    observationId,
                    frames);
                long expires = Math.Min(
                    checked(
                        _clock.MonotonicMilliseconds
                        + AgentProtocolV1.MaximumObservationTtlMs),
                    grant.ExpiresMonotonic);
                lock (_observationSync)
                {
                    PurgeExpiredObservationsLocked();
                    _observations.Add(
                        observationId,
                        new ObservationRecord(
                            request,
                            plan,
                            envelope,
                            expires));
                }
                return ObservationCaptureOutcome.Captured(envelope);
            }
            finally
            {
                foreach (CapturedSurface capture in captures)
                    capture?.Dispose();
            }
        }

        /// <summary>
        /// Validates an observation for a later read or write. A write attempt
        /// consumes the observation exactly once; read-only inspection and
        /// observations made by other readers do not consume it.
        /// </summary>
        public bool TryUseObservation(
            ObservationUseRequest request,
            bool consumeForWrite,
            out string reasonCode)
        {
            ThrowIfDisposed();
            if (request == null
                || string.IsNullOrWhiteSpace(request.ObservationId))
            {
                reasonCode = "arguments_invalid";
                return false;
            }

            ObservationRecord record;
            bool expired = false;
            lock (_observationSync)
            {
                if (!_observations.TryGetValue(
                        request.ObservationId,
                        out record))
                {
                    reasonCode = "observation_not_found";
                    return false;
                }
                if (record.ExpiresMonotonic
                    <= _clock.MonotonicMilliseconds)
                {
                    record.TerminalReason = "stale_observation_ttl";
                    reasonCode = record.TerminalReason;
                    _observations.Remove(request.ObservationId);
                    expired = true;
                }
                else if (record.Consumed)
                {
                    reasonCode = "observation_consumed";
                    return false;
                }
                else if (!record.MatchesOwner(request))
                {
                    reasonCode = "observation_owner_mismatch";
                    return false;
                }
                else if (!record.ContainsTargetAndFrame(
                        request.TargetId,
                        request.FrameId))
                {
                    reasonCode = request.FrameId == null
                        ? "target_scope_denied"
                        : "stale_frame";
                    return false;
                }
            }
            if (expired)
            {
                _content.RevokeObservation(
                    request.ObservationId,
                    "stale_observation_ttl");
                reasonCode = "stale_observation_ttl";
                return false;
            }

            if (!_grants.TryAuthorize(
                    request.ObservationGrantId,
                    request.ClientInstanceId,
                    request.SecurityPrincipalId,
                    request.SessionId,
                    request.TargetId,
                    request.DataScope,
                    out _,
                    out reasonCode))
            {
                reasonCode ??= "observation_grant_inactive";
                return false;
            }
            if (!_sessions.TryValidateCapturePlan(
                    record.Plan,
                    out reasonCode))
            {
                reasonCode ??= "stale_surface";
                return false;
            }

            bool revokeObservation = false;
            bool observationAccepted = false;
            lock (_observationSync)
            {
                if (!_observations.TryGetValue(
                        request.ObservationId,
                        out ObservationRecord current)
                    || !ReferenceEquals(current, record))
                {
                    reasonCode = record.TerminalReason
                        ?? "observation_not_found";
                    return false;
                }
                if (record.ExpiresMonotonic
                    <= _clock.MonotonicMilliseconds)
                {
                    record.TerminalReason =
                        "stale_observation_ttl";
                    _observations.Remove(
                        request.ObservationId);
                    revokeObservation = true;
                    reasonCode = record.TerminalReason;
                }
                else if (record.Consumed)
                {
                    reasonCode = "observation_consumed";
                    return false;
                }
                else if (!record.MatchesOwner(request))
                {
                    reasonCode =
                        "observation_owner_mismatch";
                    return false;
                }
                else if (!record.ContainsTargetAndFrame(
                        request.TargetId,
                        request.FrameId))
                {
                    reasonCode = request.FrameId == null
                        ? "target_scope_denied"
                        : "stale_frame";
                    return false;
                }
                else if (consumeForWrite)
                {
                    record.Consumed = true;
                    record.TerminalReason =
                        "observation_consumed";
                    revokeObservation = true;
                    observationAccepted = true;
                }
                else
                {
                    reasonCode = null;
                    return true;
                }
            }
            if (revokeObservation)
            {
                _content.RevokeObservation(
                    record.ObservationId,
                    record.TerminalReason);
            }
            if (!observationAccepted)
                return false;
            reasonCode = null;
            return true;
        }

        /// <summary>
        /// Terminally releases an observation acknowledged by its exact
        /// owner. Acknowledgement is cleanup, not a new observation and not
        /// evidence of an action effect.
        /// </summary>
        public bool TryAcknowledgeObservation(
            ObservationUseRequest request,
            out string reasonCode)
        {
            ThrowIfDisposed();
            if (request == null
                || string.IsNullOrWhiteSpace(
                    request.ObservationId))
            {
                reasonCode = "arguments_invalid";
                return false;
            }

            ObservationRecord record;
            bool acknowledged = false;
            lock (_observationSync)
            {
                if (!_observations.TryGetValue(
                        request.ObservationId,
                        out record))
                {
                    reasonCode =
                        "observation_not_found";
                    return false;
                }
                if (!record.MatchesOwner(request))
                {
                    reasonCode =
                        "observation_owner_mismatch";
                    return false;
                }
                if (!record.ContainsTargetAndFrame(
                        request.TargetId,
                        request.FrameId))
                {
                    reasonCode = request.FrameId == null
                        ? "target_scope_denied"
                        : "stale_frame";
                    return false;
                }
                if (record.ExpiresMonotonic
                    <= _clock.MonotonicMilliseconds)
                {
                    record.TerminalReason =
                        "stale_observation_ttl";
                    reasonCode = record.TerminalReason;
                }
                else
                {
                    record.TerminalReason =
                        "observation_acknowledged";
                    reasonCode = null;
                    acknowledged = true;
                }
                _observations.Remove(
                    request.ObservationId);
            }
            _content.RevokeObservation(
                record.ObservationId,
                record.TerminalReason);
            return acknowledged;
        }

        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0)
                return;
            foreach (CaptureSlot slot in _slots.Values)
                slot.Dispose();
            _slots.Clear();
            lock (_observationSync)
            {
                foreach (ObservationRecord record
                    in _observations.Values)
                {
                    _content.RevokeObservation(
                        record.ObservationId,
                        "observation_broker_disposed");
                }
                _observations.Clear();
            }
        }

        private async Task<CapturedSurface> CaptureSurfaceAsync(
            ObservationCapturePlan plan,
            ObservationSurfacePlan surface,
            bool allowFallback,
            CancellationToken cancellationToken)
        {
            string slotKey = string.Join(
                "|",
                plan.SessionId,
                surface.TargetId,
                surface.WindowHandle,
                surface.SurfaceEpoch);
            CaptureSlot slot = _slots.GetOrAdd(
                slotKey,
                _ =>
                {
                    try
                    {
                        return new CaptureSlot(
                            _frameSources.Create(surface));
                    }
                    catch
                    {
                        return new CaptureSlot(
                            new UnavailableFrameSource());
                    }
                });
            WindowFrameCaptureResult result =
                await slot.CaptureLatestAsync(cancellationToken)
                    .ConfigureAwait(false);
            if (CapturedFrameSafety.IsAcceptableBgra(
                    result,
                    out string reasonCode))
            {
                return CapturedSurface.Captured(
                    surface,
                    result,
                    _clock.MonotonicMilliseconds);
            }

            bool backpressure = string.Equals(
                result?.ReasonCode,
                "capture_backpressure",
                StringComparison.Ordinal);
            result?.Dispose();
            if (backpressure)
            {
                return CapturedSurface.Rejected(
                    surface,
                    "capture_backpressure");
            }

            bool eligibleFallback =
                allowFallback
                && surface.Kind == SurfaceKind.Flash
                && surface.ObservationModes.Contains(
                    ObservationMode.FlashSnapshotKeyframe);
            if (!eligibleFallback)
            {
                return CapturedSurface.Rejected(
                    surface,
                    reasonCode ?? "capture_unavailable");
            }

            WindowFrameCaptureResult fallback;
            try
            {
                fallback = await _flashFallback.CaptureAsync(
                            plan,
                            surface,
                            cancellationToken)
                        .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch
            {
                return CapturedSurface.Rejected(
                    surface,
                    "capture_unavailable");
            }
            if (!CapturedFrameSafety.IsAcceptableBgra(
                    fallback,
                    out reasonCode))
            {
                fallback?.Dispose();
                return CapturedSurface.Rejected(
                    surface,
                    reasonCode ?? "capture_unavailable");
            }
            return CapturedSurface.Captured(
                surface,
                fallback,
                _clock.MonotonicMilliseconds);
        }

        private ObservationEnvelope CreateEnvelope(
            ObservationCaptureRequest request,
            ObservationCapturePlan plan,
            string observationId,
            List<FrameEnvelope> frames)
        {
            ObservationSurfacePlan primary = plan.PrimarySurface;
            return new ObservationEnvelope
            {
                ObservationId = observationId,
                ObservationGrantId = request.ObservationGrantId,
                SessionId = plan.SessionId,
                LifecycleGeneration = plan.LifecycleGeneration,
                CapturedUtc = _clock.UtcNow,
                CapturedAtMonotonic = ToProtocolMonotonic(
                    _clock.MonotonicMilliseconds),
                AttemptId = plan.AttemptId,
                AttemptGeneration = plan.AttemptGeneration,
                PanelInstanceId = plan.PanelInstanceId,
                DocumentGeneration = primary.DocumentGeneration,
                TargetId = primary.TargetId,
                SurfaceEpoch = primary.SurfaceEpoch,
                CoordinateSpaceVersion =
                    primary.CoordinateSpaceVersion,
                FocusEpoch = plan.FocusEpoch,
                ModalEpoch = plan.ModalEpoch,
                SemanticSnapshotId =
                    primary.SemanticGeneration.HasValue
                        ? OpaqueIdGenerator.Create("semantic")
                        : null,
                SemanticGeneration = primary.SemanticGeneration,
                Visible = primary.Visible,
                Minimized = primary.Minimized,
                Active = primary.Active,
                BlockingModalKind = plan.BlockingModalKind,
                Frames = frames
            };
        }

        private static FrameEnvelope CreateFrame(
            string frameId,
            string observationId,
            CapturedSurface capture,
            PixelContentHandleDescriptor handle)
        {
            ObservationSurfacePlan surface = capture.Surface;
            PhysicalRect captureRect = CloneRect(
                surface.BoundsPhysical);
            double scaleX =
                (double)captureRect.Width / capture.Result.Width;
            double scaleY =
                (double)captureRect.Height / capture.Result.Height;
            return new FrameEnvelope
            {
                FrameId = frameId,
                ObservationId = observationId,
                TargetId = surface.TargetId,
                SurfaceEpoch = surface.SurfaceEpoch,
                SourceLayer = surface.SourceLayer,
                ZIndex = surface.ZIndex,
                CapturedAtMonotonic = ToProtocolMonotonic(
                    capture.CapturedAtMonotonic),
                CoordinateSpaceId =
                    OpaqueIdGenerator.Create("coord"),
                CoordinateSpaceVersion =
                    surface.CoordinateSpaceVersion,
                CaptureRectPhysical = captureRect,
                ClientRectPhysical = CloneRect(
                    surface.ClientRectPhysical),
                ContentRectPhysical = CloneRect(
                    surface.ContentRectPhysical),
                FrameToTargetContentTransform =
                    new AffineTransform
                    {
                        M11 = scaleX,
                        M12 = 0,
                        M21 = 0,
                        M22 = scaleY,
                        Dx = captureRect.X
                            - surface.ContentRectPhysical.X,
                        Dy = captureRect.Y
                            - surface.ContentRectPhysical.Y
                    },
                Width = capture.Result.Width,
                Height = capture.Result.Height,
                Dpi = surface.Dpi,
                PixelFormat = capture.Result.PixelFormat,
                ContentHash = handle.ContentHash,
                OpaqueContentHandle = handle.Handle
            };
        }

        private void PurgeExpiredObservationsLocked()
        {
            string[] expired = _observations
                .Where(pair =>
                    pair.Value.ExpiresMonotonic
                        <= _clock.MonotonicMilliseconds)
                .Select(pair => pair.Key)
                .ToArray();
            foreach (string observationId in expired)
            {
                ObservationRecord record =
                    _observations[observationId];
                record.TerminalReason = "stale_observation_ttl";
                _content.RevokeObservation(
                    observationId,
                    record.TerminalReason);
                _observations.Remove(observationId);
            }
        }

        private static PhysicalRect CloneRect(PhysicalRect source)
        {
            return new PhysicalRect
            {
                X = source.X,
                Y = source.Y,
                Width = source.Width,
                Height = source.Height
            };
        }

        private static ulong ToProtocolMonotonic(long value)
        {
            return checked((ulong)Math.Max(1, value));
        }

        private static void DisposeCompletedCaptures(
            IEnumerable<Task<CapturedSurface>> tasks)
        {
            foreach (Task<CapturedSurface> task in tasks)
            {
                if (task.Status == TaskStatus.RanToCompletion)
                    task.GetAwaiter().GetResult()?.Dispose();
            }
        }

        private static string ValidateRequest(
            ObservationCaptureRequest request)
        {
            if (request == null
                || string.IsNullOrWhiteSpace(
                    request.ObservationGrantId)
                || string.IsNullOrWhiteSpace(
                    request.ClientInstanceId)
                || string.IsNullOrWhiteSpace(
                    request.SecurityPrincipalId)
                || string.IsNullOrWhiteSpace(request.SessionId)
                || string.IsNullOrWhiteSpace(request.TargetId)
                || string.IsNullOrWhiteSpace(request.DataScope))
            {
                return "arguments_invalid";
            }
            if (!string.Equals(
                    request.DataScope,
                    ObservationDataScopesV1.Pixels,
                    StringComparison.Ordinal))
            {
                return "observation_scope_mismatch";
            }
            return null;
        }

        private void ThrowIfDisposed()
        {
            if (Volatile.Read(ref _disposed) != 0)
                throw new ObjectDisposedException(GetType().Name);
        }

        private sealed class CaptureSlot : IDisposable
        {
            private readonly IWindowFrameSource _source;
            private int _busy;
            private int _disposed;

            public CaptureSlot(IWindowFrameSource source)
            {
                _source = source
                    ?? throw new ArgumentNullException(nameof(source));
            }

            public async Task<WindowFrameCaptureResult>
                CaptureLatestAsync(CancellationToken cancellationToken)
            {
                if (Volatile.Read(ref _disposed) != 0)
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                if (Interlocked.CompareExchange(
                        ref _busy,
                        1,
                        0) != 0)
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_backpressure");
                }
                try
                {
                    // IWindowFrameSource's contract is latest-only. The slot
                    // adds a one-in-flight bound and no pending queue.
                    return await _source.CaptureLatestAsync(
                            cancellationToken)
                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException)
                {
                    throw;
                }
                catch
                {
                    return WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable");
                }
                finally
                {
                    Volatile.Write(ref _busy, 0);
                }
            }

            public void Dispose()
            {
                if (Interlocked.Exchange(ref _disposed, 1) == 0)
                    _source.Dispose();
            }
        }

        private sealed class UnavailableFrameSource
            : IWindowFrameSource
        {
            public Task<WindowFrameCaptureResult> CaptureLatestAsync(
                CancellationToken cancellationToken)
            {
                return Task.FromResult(
                    WindowFrameCaptureResult.Unavailable(
                        "capture_unavailable"));
            }

            public void Dispose()
            {
            }
        }

        private sealed class CapturedSurface : IDisposable
        {
            private CapturedSurface(
                ObservationSurfacePlan surface,
                WindowFrameCaptureResult result,
                long capturedAtMonotonic,
                string reasonCode)
            {
                Surface = surface;
                Result = result;
                CapturedAtMonotonic = capturedAtMonotonic;
                ReasonCode = reasonCode;
            }

            public bool Success
            {
                get { return Result?.Success == true; }
            }

            public ObservationSurfacePlan Surface { get; }
            public WindowFrameCaptureResult Result { get; }
            public long CapturedAtMonotonic { get; }
            public string ReasonCode { get; }

            public static CapturedSurface Captured(
                ObservationSurfacePlan surface,
                WindowFrameCaptureResult result,
                long capturedAtMonotonic)
            {
                return new CapturedSurface(
                    surface,
                    result,
                    capturedAtMonotonic,
                    null);
            }

            public static CapturedSurface Rejected(
                ObservationSurfacePlan surface,
                string reasonCode)
            {
                return new CapturedSurface(
                    surface,
                    null,
                    0,
                    reasonCode);
            }

            public void Dispose()
            {
                Result?.Dispose();
            }
        }

        private sealed class ObservationRecord
        {
            private readonly HashSet<string> _targets;
            private readonly Dictionary<string, string> _frameTargets;

            public ObservationRecord(
                ObservationCaptureRequest request,
                ObservationCapturePlan plan,
                ObservationEnvelope envelope,
                long expiresMonotonic)
            {
                ClientInstanceId = request.ClientInstanceId;
                SecurityPrincipalId = request.SecurityPrincipalId;
                ObservationGrantId = request.ObservationGrantId;
                SessionId = request.SessionId;
                DataScope = request.DataScope;
                Plan = plan;
                ObservationId = envelope.ObservationId;
                ExpiresMonotonic = expiresMonotonic;
                _targets = plan.CaptureSurfaces
                    .Select(surface => surface.TargetId)
                    .ToHashSet(StringComparer.Ordinal);
                _frameTargets = envelope.Frames.ToDictionary(
                    frame => frame.FrameId,
                    frame => frame.TargetId,
                    StringComparer.Ordinal);
            }

            public string ClientInstanceId { get; }
            public string SecurityPrincipalId { get; }
            public string ObservationGrantId { get; }
            public string SessionId { get; }
            public string DataScope { get; }
            public ObservationCapturePlan Plan { get; }
            public string ObservationId { get; }
            public long ExpiresMonotonic { get; }
            public bool Consumed { get; set; }
            public string TerminalReason { get; set; }

            public bool MatchesOwner(ObservationUseRequest request)
            {
                return string.Equals(
                        ClientInstanceId,
                        request.ClientInstanceId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        SecurityPrincipalId,
                        request.SecurityPrincipalId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        ObservationGrantId,
                        request.ObservationGrantId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        SessionId,
                        request.SessionId,
                        StringComparison.Ordinal)
                    && string.Equals(
                        DataScope,
                        request.DataScope,
                        StringComparison.Ordinal);
            }

            public bool ContainsTargetAndFrame(
                string targetId,
                string frameId)
            {
                if (!_targets.Contains(targetId ?? string.Empty))
                    return false;
                if (frameId == null) return true;
                return _frameTargets.TryGetValue(
                        frameId,
                        out string frameTarget)
                    && string.Equals(
                        frameTarget,
                        targetId,
                        StringComparison.Ordinal);
            }
        }
    }
}
