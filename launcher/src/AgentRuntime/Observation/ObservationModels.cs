using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using CF7Launcher.AgentRuntime.Contracts;

namespace CF7Launcher.AgentRuntime.Observation
{
    internal sealed class ObservationCaptureRequest
    {
        public string ObservationGrantId { get; init; }
        public string ClientInstanceId { get; init; }
        public string SecurityPrincipalId { get; init; }
        public string SessionId { get; init; }
        public string TargetId { get; init; }
        public string DataScope { get; init; } =
            ObservationDataScopesV1.Pixels;
        public bool AllowValidatedFlashKeyframeFallback { get; init; }
    }

    internal sealed class ObservationCaptureOutcome
    {
        private ObservationCaptureOutcome(
            ObservationEnvelope envelope,
            string reasonCode)
        {
            Envelope = envelope;
            ReasonCode = reasonCode;
        }

        public bool Success
        {
            get { return Envelope != null; }
        }

        public ObservationEnvelope Envelope { get; }
        public string ReasonCode { get; }

        public static ObservationCaptureOutcome Captured(
            ObservationEnvelope envelope)
        {
            return new ObservationCaptureOutcome(
                envelope
                    ?? throw new ArgumentNullException(nameof(envelope)),
                null);
        }

        public static ObservationCaptureOutcome Rejected(
            string reasonCode)
        {
            if (string.IsNullOrWhiteSpace(reasonCode))
                throw new ArgumentException(
                    "A reason code is required.",
                    nameof(reasonCode));
            return new ObservationCaptureOutcome(null, reasonCode);
        }
    }

    internal sealed class ObservationCapturePlan
    {
        public ObservationCapturePlan(
            string sessionId,
            ulong lifecycleGeneration,
            string attemptId,
            ulong? attemptGeneration,
            string panelInstanceId,
            ulong focusEpoch,
            ulong modalEpoch,
            BlockingModalKind blockingModalKind,
            ObservationSurfacePlan primarySurface,
            IEnumerable<ObservationSurfacePlan> captureSurfaces)
        {
            SessionId = RequireValue(sessionId, nameof(sessionId));
            if (lifecycleGeneration == 0)
                throw new ArgumentOutOfRangeException(
                    nameof(lifecycleGeneration));
            LifecycleGeneration = lifecycleGeneration;
            AttemptId = attemptId;
            AttemptGeneration = attemptGeneration;
            PanelInstanceId = panelInstanceId;
            FocusEpoch = focusEpoch;
            ModalEpoch = modalEpoch;
            BlockingModalKind = blockingModalKind;
            PrimarySurface = primarySurface
                ?? throw new ArgumentNullException(nameof(primarySurface));
            ObservationSurfacePlan[] surfaces =
                (captureSurfaces ?? Array.Empty<ObservationSurfacePlan>())
                    .Where(surface => surface != null)
                    .OrderBy(surface => surface.ZIndex)
                    .ThenBy(
                        surface => surface.TargetId,
                        StringComparer.Ordinal)
                    .ToArray();
            if (surfaces.Length == 0
                || !surfaces.Any(surface => string.Equals(
                    surface.TargetId,
                    primarySurface.TargetId,
                    StringComparison.Ordinal)))
            {
                throw new ArgumentException(
                    "The capture plan must include its primary surface.",
                    nameof(captureSurfaces));
            }
            if (surfaces.Select(surface => surface.TargetId)
                    .Distinct(StringComparer.Ordinal)
                    .Count()
                != surfaces.Length)
            {
                throw new ArgumentException(
                    "Capture-plan targets must be unique.",
                    nameof(captureSurfaces));
            }
            if (surfaces.Any(surface =>
                    surface.FocusEpoch != focusEpoch
                    || surface.ModalEpoch != modalEpoch))
            {
                throw new ArgumentException(
                    "Surface focus/modal generations must match the session plan.",
                    nameof(captureSurfaces));
            }
            CaptureSurfaces = Array.AsReadOnly(surfaces);
        }

        public string SessionId { get; }
        public ulong LifecycleGeneration { get; }
        public string AttemptId { get; }
        public ulong? AttemptGeneration { get; }
        public string PanelInstanceId { get; }
        public ulong FocusEpoch { get; }
        public ulong ModalEpoch { get; }
        public BlockingModalKind BlockingModalKind { get; }
        public ObservationSurfacePlan PrimarySurface { get; }
        public ReadOnlyCollection<ObservationSurfacePlan> CaptureSurfaces
        {
            get;
        }

        private static string RequireValue(string value, string parameter)
        {
            if (string.IsNullOrWhiteSpace(value))
                throw new ArgumentException(
                    "A non-empty value is required.",
                    parameter);
            return value;
        }
    }

    internal sealed class ObservationSurfacePlan
    {
        public ObservationSurfacePlan(
            string targetId,
            SurfaceKind kind,
            long windowHandle,
            int ownerProcessId,
            DateTimeOffset ownerProcessStartTimeUtc,
            string ownerExecutablePath,
            long ownerWindowHandle,
            ulong surfaceEpoch,
            ulong coordinateSpaceVersion,
            ulong focusEpoch,
            ulong modalEpoch,
            ulong? semanticGeneration,
            ulong? documentGeneration,
            PhysicalRect boundsPhysical,
            PhysicalRect clientRectPhysical,
            PhysicalRect contentRectPhysical,
            int dpi,
            int zIndex,
            bool visible,
            bool minimized,
            bool active,
            IEnumerable<ObservationMode> observationModes)
        {
            if (string.IsNullOrWhiteSpace(targetId))
                throw new ArgumentException(
                    "A target ID is required.",
                    nameof(targetId));
            if (windowHandle == 0)
                throw new ArgumentOutOfRangeException(nameof(windowHandle));
            if (ownerProcessId <= 0)
                throw new ArgumentOutOfRangeException(
                    nameof(ownerProcessId));
            if (ownerProcessStartTimeUtc == default)
                throw new ArgumentException(
                    "An owner process start time is required.",
                    nameof(ownerProcessStartTimeUtc));
            if (string.IsNullOrWhiteSpace(ownerExecutablePath)
                || !Path.IsPathFullyQualified(ownerExecutablePath))
            {
                throw new ArgumentException(
                    "An absolute owner executable path is required.",
                    nameof(ownerExecutablePath));
            }
            if (ownerWindowHandle < 0)
                throw new ArgumentOutOfRangeException(
                    nameof(ownerWindowHandle));
            if (surfaceEpoch == 0)
                throw new ArgumentOutOfRangeException(nameof(surfaceEpoch));
            if (coordinateSpaceVersion == 0)
                throw new ArgumentOutOfRangeException(
                    nameof(coordinateSpaceVersion));
            if (dpi < 72 || dpi > 960)
                throw new ArgumentOutOfRangeException(nameof(dpi));

            TargetId = targetId;
            Kind = kind;
            WindowHandle = windowHandle;
            OwnerProcessId = ownerProcessId;
            OwnerProcessStartTimeUtc =
                ownerProcessStartTimeUtc.ToUniversalTime();
            OwnerExecutablePath =
                Path.GetFullPath(ownerExecutablePath);
            OwnerWindowHandle = ownerWindowHandle;
            SurfaceEpoch = surfaceEpoch;
            CoordinateSpaceVersion = coordinateSpaceVersion;
            FocusEpoch = focusEpoch;
            ModalEpoch = modalEpoch;
            SemanticGeneration = semanticGeneration;
            DocumentGeneration = documentGeneration;
            BoundsPhysical = CloneRect(
                boundsPhysical,
                nameof(boundsPhysical));
            ClientRectPhysical = CloneRect(
                clientRectPhysical,
                nameof(clientRectPhysical));
            ContentRectPhysical = CloneRect(
                contentRectPhysical,
                nameof(contentRectPhysical));
            Dpi = dpi;
            ZIndex = zIndex;
            Visible = visible;
            Minimized = minimized;
            Active = active;
            ObservationModes = Array.AsReadOnly(
                (observationModes ?? Array.Empty<ObservationMode>())
                    .Distinct()
                    .OrderBy(mode => mode)
                    .ToArray());
        }

        public string TargetId { get; }
        public SurfaceKind Kind { get; }
        public long WindowHandle { get; }
        public int OwnerProcessId { get; }
        public DateTimeOffset OwnerProcessStartTimeUtc { get; }
        public string OwnerExecutablePath { get; }
        public long OwnerWindowHandle { get; }
        public ulong SurfaceEpoch { get; }
        public ulong CoordinateSpaceVersion { get; }
        public ulong FocusEpoch { get; }
        public ulong ModalEpoch { get; }
        public ulong? SemanticGeneration { get; }
        public ulong? DocumentGeneration { get; }
        public PhysicalRect BoundsPhysical { get; }
        public PhysicalRect ClientRectPhysical { get; }
        public PhysicalRect ContentRectPhysical { get; }
        public int Dpi { get; }
        public int ZIndex { get; }
        public bool Visible { get; }
        public bool Minimized { get; }
        public bool Active { get; }
        public ReadOnlyCollection<ObservationMode> ObservationModes { get; }

        public SourceLayer SourceLayer
        {
            get
            {
                return Kind switch
                {
                    SurfaceKind.Launcher => SourceLayer.Launcher,
                    SurfaceKind.Flash => SourceLayer.Flash,
                    SurfaceKind.WebOverlay => SourceLayer.WebOverlay,
                    SurfaceKind.NativeHud => SourceLayer.NativeHud,
                    SurfaceKind.WingsShell => SourceLayer.WingsShell,
                    SurfaceKind.BusinessModal => SourceLayer.BusinessModal,
                    _ => throw new ArgumentOutOfRangeException()
                };
            }
        }

        private static PhysicalRect CloneRect(
            PhysicalRect source,
            string parameter)
        {
            if (source == null
                || source.Width <= 0
                || source.Height <= 0)
            {
                throw new ArgumentException(
                    "A positive physical rectangle is required.",
                    parameter);
            }
            return new PhysicalRect
            {
                X = source.X,
                Y = source.Y,
                Width = source.Width,
                Height = source.Height
            };
        }
    }

    internal sealed class ObservationUseRequest
    {
        public string ObservationId { get; init; }
        public string ObservationGrantId { get; init; }
        public string ClientInstanceId { get; init; }
        public string SecurityPrincipalId { get; init; }
        public string SessionId { get; init; }
        public string TargetId { get; init; }
        public string FrameId { get; init; }
        public string DataScope { get; init; } =
            ObservationDataScopesV1.Pixels;
    }
}
