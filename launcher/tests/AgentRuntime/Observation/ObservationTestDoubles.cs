using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using CF7Launcher.AgentRuntime.Contracts;
using CF7Launcher.AgentRuntime.Observation;
using CF7Launcher.AgentRuntime.Security;

namespace CF7Launcher.Tests.AgentRuntime.Observation
{
    internal sealed class ManualObservationClock : IAgentRuntimeClock
    {
        public long MonotonicMilliseconds { get; private set; } = 1000;

        public DateTimeOffset UtcNow { get; private set; } =
            new DateTimeOffset(
                2026,
                7,
                30,
                8,
                0,
                0,
                TimeSpan.Zero);

        public void Advance(TimeSpan duration)
        {
            MonotonicMilliseconds = checked(
                MonotonicMilliseconds
                + (long)duration.TotalMilliseconds);
            UtcNow = UtcNow.Add(duration);
        }
    }

    internal sealed class ObservationEnrollmentVerifier
        : IPrincipalEnrollmentVerifier
    {
        public bool TryVerifyDeveloper(
            DeveloperEnrollmentEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            authorization =
                VerifiedPrincipalAuthorization.CreateTrusted(
                    evidence.AllowedCapabilities,
                    evidence.AllowedTargets,
                    evidence.EnrollmentReceipt);
            reasonCode = null;
            return true;
        }

        public bool TryVerifyUnattended(
            UnattendedCredentialEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            authorization =
                VerifiedPrincipalAuthorization.CreateTrusted(
                    evidence.AllowedCapabilities,
                    evidence.AllowedTargets,
                    "unattended-test");
            reasonCode = null;
            return true;
        }

        public bool TryVerifyPlayerAssist(
            PlayerAssistCredentialEvidence evidence,
            out VerifiedPrincipalAuthorization authorization,
            out string reasonCode)
        {
            authorization =
                VerifiedPrincipalAuthorization.CreateTrusted(
                    evidence.AllowedCapabilities,
                    evidence.AllowedTargets,
                    evidence.ConsentReceipt);
            reasonCode = null;
            return true;
        }
    }

    internal sealed class MutableObservationAuthority
        : IObservationSessionAuthority,
          IAgentTargetAuthority,
          IAgentSessionModeAuthority
    {
        private readonly Dictionary<string, AgentTargetSafetyKind> _targets =
            new Dictionary<string, AgentTargetSafetyKind>(
                StringComparer.Ordinal);

        public ObservationCapturePlan Plan { get; set; }
        public string CreateReason { get; set; }
        public string ValidateReason { get; set; }
        public Action OnValidate { get; set; }
        public SessionMode CurrentSessionMode { get; set; } =
            SessionMode.DeveloperInteractive;
        public SurfaceKind TargetSurfaceKind { get; set; } =
            SurfaceKind.Flash;
        public int CreatePlanCalls { get; private set; }
        public int ValidatePlanCalls { get; private set; }

        public void AddTarget(
            string targetId,
            AgentTargetSafetyKind safetyKind =
                AgentTargetSafetyKind.RuntimeOwned)
        {
            _targets[targetId] = safetyKind;
        }

        public bool TryResolve(
            string sessionId,
            string targetId,
            out AgentTargetDescriptor descriptor,
            out string reasonCode)
        {
            if (!_targets.TryGetValue(
                    targetId ?? string.Empty,
                    out AgentTargetSafetyKind safety))
            {
                descriptor = null;
                reasonCode = "target_not_authoritative";
                return false;
            }
            descriptor = new AgentTargetDescriptor(
                sessionId,
                targetId,
                safety,
                TargetSurfaceKind);
            reasonCode = null;
            return true;
        }

        public bool TryResolveSessionMode(
            string sessionId,
            out SessionMode sessionMode,
            out string reasonCode)
        {
            sessionMode = CurrentSessionMode;
            reasonCode = null;
            return true;
        }

        public bool TryCreateCapturePlan(
            string sessionId,
            string targetId,
            out ObservationCapturePlan plan,
            out string reasonCode)
        {
            CreatePlanCalls++;
            if (CreateReason != null)
            {
                plan = null;
                reasonCode = CreateReason;
                return false;
            }
            plan = Plan;
            reasonCode = null;
            return true;
        }

        public bool TryValidateCapturePlan(
            ObservationCapturePlan capturedPlan,
            out string reasonCode)
        {
            ValidatePlanCalls++;
            OnValidate?.Invoke();
            reasonCode = ValidateReason;
            return reasonCode == null;
        }
    }

    internal sealed class RecordingFrameSourceFactory
        : IWindowFrameSourceFactory
    {
        private readonly Dictionary<
            string,
            Func<CancellationToken, Task<WindowFrameCaptureResult>>>
            _handlers =
                new Dictionary<
                    string,
                    Func<CancellationToken,
                        Task<WindowFrameCaptureResult>>>(
                    StringComparer.Ordinal);

        public int CreateCalls { get; private set; }
        public int CaptureCalls { get; private set; }

        public void Set(
            string targetId,
            Func<CancellationToken, Task<WindowFrameCaptureResult>>
                handler)
        {
            _handlers[targetId] = handler;
        }

        public IWindowFrameSource Create(
            ObservationSurfacePlan surface)
        {
            CreateCalls++;
            Func<CancellationToken, Task<WindowFrameCaptureResult>>
                handler = _handlers.TryGetValue(
                    surface.TargetId,
                    out var configured)
                    ? configured
                    : _ => Task.FromResult(ColorFrame());
            return new Source(
                handler,
                () => CaptureCalls++);
        }

        public static WindowFrameCaptureResult ColorFrame(
            int width = 4,
            int height = 3,
            ObservationMode mode =
                ObservationMode.WindowGraphicsCapture)
        {
            byte[] pixels = new byte[checked(width * height * 4)];
            for (int index = 0; index < pixels.Length; index += 4)
            {
                pixels[index] = 70;
                pixels[index + 1] = 110;
                pixels[index + 2] = 150;
                pixels[index + 3] = 255;
            }
            return WindowFrameCaptureResult.Captured(
                pixels,
                width,
                height,
                mode);
        }

        public static WindowFrameCaptureResult BlackFrame(
            int width = 4,
            int height = 3)
        {
            return WindowFrameCaptureResult.Captured(
                new byte[checked(width * height * 4)],
                width,
                height,
                ObservationMode.WindowGraphicsCapture);
        }

        private sealed class Source : IWindowFrameSource
        {
            private readonly Func<
                CancellationToken,
                Task<WindowFrameCaptureResult>> _handler;
            private readonly Action _onCapture;

            public Source(
                Func<CancellationToken,
                    Task<WindowFrameCaptureResult>> handler,
                Action onCapture)
            {
                _handler = handler;
                _onCapture = onCapture;
            }

            public Task<WindowFrameCaptureResult> CaptureLatestAsync(
                CancellationToken cancellationToken)
            {
                _onCapture();
                return _handler(cancellationToken);
            }

            public void Dispose()
            {
            }
        }
    }

    internal sealed class RecordingPixelAuditSink
        : IPixelContentAuditSink
    {
        public List<PixelContentAuditEvent> Events { get; } =
            new List<PixelContentAuditEvent>();
        public Action<PixelContentAuditEvent> OnRecord { get; set; }

        public void Record(PixelContentAuditEvent auditEvent)
        {
            Events.Add(auditEvent);
            OnRecord?.Invoke(auditEvent);
        }
    }

    internal sealed class RecordingFlashFallback
        : IFlashKeyframeFallback
    {
        public int Calls { get; private set; }
        public WindowFrameCaptureResult Result { get; set; }

        public Task<WindowFrameCaptureResult> CaptureAsync(
            ObservationCapturePlan plan,
            ObservationSurfacePlan surface,
            CancellationToken cancellationToken)
        {
            Calls++;
            return Task.FromResult(
                Result ?? RecordingFrameSourceFactory.ColorFrame(
                    mode: ObservationMode.FlashSnapshotKeyframe));
        }
    }
}
